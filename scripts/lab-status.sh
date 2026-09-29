#!/usr/bin/env bash

set -u
set -o pipefail

NODES=(node1 node2 node3)
IPS=(192.168.0.200 192.168.0.201 192.168.0.202)

PASS_COUNT=0
FAIL_COUNT=0
OVERALL_FAIL=0

declare -A REACHABLE

pass() {
  printf 'PASS  %s\n' "$1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  OVERALL_FAIL=1
}

section() {
  printf '\n== %s ==\n' "$1"
}

ssh_node() {
  local ip="$1"
  shift

  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=4 \
    -o LogLevel=ERROR \
    "openstack@${ip}" "$@"
}

container_state() {
  local ip="$1"
  local container="$2"

  ssh_node "$ip" \
    "sudo docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' '${container}' 2>/dev/null"
}

check_container_group() {
  local label="$1"
  shift

  local containers=("$@")
  local expected=$(( ${#NODES[@]} * ${#containers[@]} ))
  local healthy=0
  local node ip container state
  local details=()

  for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    ip="${IPS[$i]}"

    for container in "${containers[@]}"; do

      if [[ "${REACHABLE[$node]:-no}" != "yes" ]]; then
        details+=("${node}/${container}=node-unreachable")
        continue
      fi

      state="$(container_state "$ip" "$container" 2>/dev/null || true)"

      if [[ "$state" == "running healthy" ]]; then
        healthy=$((healthy + 1))
      else
        [[ -n "$state" ]] || state="not-found-or-no-response"
        details+=("${node}/${container}=${state}")
      fi

    done
  done

  if (( healthy == expected )); then
    pass "${label}: ${healthy}/${expected} healthy"
  else
    fail "${label}: ${healthy}/${expected} healthy"

    for state in "${details[@]}"; do
      printf '      %s\n' "$state"
    done
  fi
}

printf 'OPENSTACK LAB STATUS\n'
printf '====================\n'
printf 'Run time: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

section "Hermes environment"

if ! command -v openstack >/dev/null 2>&1; then

  if [[ -f "$HOME/venvs/kolla/bin/activate" ]]; then
    source "$HOME/venvs/kolla/bin/activate"
  fi

fi

if command -v openstack >/dev/null 2>&1; then
  pass "OpenStack CLI found: $(command -v openstack)"
else
  fail "OpenStack CLI not found"
fi

export OS_CLIENT_CONFIG_FILE="${OS_CLIENT_CONFIG_FILE:-/etc/kolla/clouds.yaml}"
export OS_CLOUD="${OS_CLOUD:-kolla-admin}"

printf '      OS_CLOUD=%s\n' "$OS_CLOUD"
printf '      OS_CLIENT_CONFIG_FILE=%s\n' "$OS_CLIENT_CONFIG_FILE"

section "Node reachability"

reachable_count=0

for i in "${!NODES[@]}"; do

  node="${NODES[$i]}"
  ip="${IPS[$i]}"

  if remote_name="$(ssh_node "$ip" 'hostname' 2>/dev/null)"; then

    REACHABLE[$node]="yes"
    reachable_count=$((reachable_count + 1))

    pass "${node} (${ip}) reachable as ${remote_name}"

  else

    REACHABLE[$node]="no"
    fail "${node} (${ip}) unreachable"

  fi

done

section "Core containers"

check_container_group "MariaDB" mariadb

check_container_group "ProxySQL" proxysql

check_container_group "Placement API" placement_api

check_container_group "Nova control" \
  nova_api \
  nova_metadata \
  nova_scheduler \
  nova_conductor

check_container_group "Neutron control" \
  neutron_server \
  neutron_rpc_server \
  neutron_periodic_worker

section "OpenStack API"

OPENSTACK_AUTH_OK=0

if command -v openstack >/dev/null 2>&1 && \
   openstack token issue -f value -c expires >/dev/null 2>&1; then

  OPENSTACK_AUTH_OK=1
  pass "Keystone authentication works"

else

  fail "Keystone authentication failed"

fi

if (( OPENSTACK_AUTH_OK == 1 )); then

  section "Nova services"

  compute_output="$(openstack compute service list \
    -f value \
    -c Binary \
    -c Host \
    -c Status \
    -c State 2>/dev/null || true)"

  nova_control_total="$(awk '
    $1=="nova-scheduler" || $1=="nova-conductor" {
      c++
    }
    END {
      print c+0
    }
  ' <<<"$compute_output")"

  nova_control_ok="$(awk '
    ($1=="nova-scheduler" || $1=="nova-conductor") &&
    $3=="enabled" &&
    $4=="up" {
      c++
    }
    END {
      print c+0
    }
  ' <<<"$compute_output")"

  if [[ "$nova_control_total" -eq 6 &&
        "$nova_control_ok" -eq 6 ]]; then

    pass "Nova control services: 6/6 enabled and up"

  else

    fail "Nova control services: ${nova_control_ok}/${nova_control_total} enabled and up (expected 6/6)"

    awk '
      ($1=="nova-scheduler" || $1=="nova-conductor") &&
      !($3=="enabled" && $4=="up") {
        printf "      %s %s status=%s state=%s\n",
        $1,$2,$3,$4
      }
    ' <<<"$compute_output"

  fi

  nova_compute_total="$(awk '
    $1=="nova-compute" {
      c++
    }
    END {
      print c+0
    }
  ' <<<"$compute_output")"

  nova_compute_ok="$(awk '
    $1=="nova-compute" &&
    $3=="enabled" &&
    $4=="up" {
      c++
    }
    END {
      print c+0
    }
  ' <<<"$compute_output")"

  if [[ "$nova_compute_total" -eq 3 &&
        "$nova_compute_ok" -eq 3 ]]; then

    pass "Nova compute services: 3/3 enabled and up"

  else

    fail "Nova compute services: ${nova_compute_ok}/${nova_compute_total} enabled and up (expected 3/3)"

    awk '
      $1=="nova-compute" &&
      !($3=="enabled" && $4=="up") {
        printf "      %s status=%s state=%s\n",
        $2,$3,$4
      }
    ' <<<"$compute_output"

  fi

  section "Hypervisors"

  hypervisor_output="$(openstack hypervisor list \
    -f value \
    -c 'Hypervisor Hostname' \
    -c State 2>/dev/null || true)"

  hypervisor_total="$(awk '
    NF {
      c++
    }
    END {
      print c+0
    }
  ' <<<"$hypervisor_output")"

  hypervisor_ok="$(awk '
    $2=="up" {
      c++
    }
    END {
      print c+0
    }
  ' <<<"$hypervisor_output")"

  if [[ "$hypervisor_total" -eq 3 &&
        "$hypervisor_ok" -eq 3 ]]; then

    pass "Hypervisors: 3/3 up"

  else

    fail "Hypervisors: ${hypervisor_ok}/${hypervisor_total} up (expected 3/3)"

    awk '
      $2!="up" {
        printf "      %s state=%s\n",
        $1,$2
      }
    ' <<<"$hypervisor_output"

  fi

  section "Neutron agents"

  neutron_output="$(openstack network agent list \
    -f value \
    -c Alive \
    -c State 2>/dev/null || true)"

  neutron_total="$(awk '
    NF {
      c++
    }
    END {
      print c+0
    }
  ' <<<"$neutron_output")"

  neutron_ok="$(awk '
    {
      alive=0
      state=0

      for (i=1; i<=NF; i++) {
        value=tolower($i)

        if (value=="true" || $i==":-)") {
          if (!alive) {
            alive=1
          } else {
            state=1
          }
        }

        if ($i=="UP") {
          state=1
        }
      }

      if (alive && state) {
        c++
      }
    }

    END {
      print c+0
    }
  ' <<<"$neutron_output")"

  if [[ "$neutron_total" -ge 12 &&
        "$neutron_ok" -eq "$neutron_total" ]]; then

    pass "Neutron agents: ${neutron_ok}/${neutron_total} alive and UP"

  else

    fail "Neutron agents: ${neutron_ok}/${neutron_total} alive and UP (expected at least 12, all healthy)"

  fi

else

  printf '\nSkipping OpenStack service checks because authentication failed.\n'

fi

section "Result"

if (( OVERALL_FAIL == 0 )); then

  printf 'RESULT: HEALTHY\n'
  printf 'PASS checks: %d\n' "$PASS_COUNT"

  exit 0

else

  printf 'RESULT: ATTENTION REQUIRED\n'
  printf 'PASS checks: %d\n' "$PASS_COUNT"
  printf 'FAIL checks: %d\n' "$FAIL_COUNT"

  printf '\nNext: follow docs/openstack-reboot-and-recovery-runbook.md\n'

  exit 1

fi
