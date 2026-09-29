#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
STATUS_SCRIPT="${SCRIPT_DIR}/lab-status.sh"

NODES=(node1 node2 node3)

declare -A IP_BY_NODE=(
  [node1]="192.168.0.200"
  [node2]="192.168.0.201"
  [node3]="192.168.0.202"
)

declare -A REACHABLE

MODE="${1:---check}"

usage() {
  cat <<USAGE
Usage:

  ./scripts/lab-recover.sh --check
  ./scripts/lab-recover.sh --plan
  ./scripts/lab-recover.sh --apply

Modes:

  --check   Run the read-only lab status checker.
  --plan    Diagnose the lab and print proposed recovery actions.
  --apply   Diagnose, ask for approval, apply supported repairs,
            then rerun the status checker.

No repair is performed by --check or --plan.
USAGE
}

case "$MODE" in
  --check|--plan|--apply)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown option: $MODE"
    usage
    exit 2
    ;;
esac


# ------------------------------------------------------------
# Environment
# ------------------------------------------------------------

if ! command -v openstack >/dev/null 2>&1; then

  if [[ -f "$HOME/venvs/kolla/bin/activate" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/venvs/kolla/bin/activate"
  fi

fi

export OS_CLIENT_CONFIG_FILE="${OS_CLIENT_CONFIG_FILE:-/etc/kolla/clouds.yaml}"
export OS_CLOUD="${OS_CLOUD:-kolla-admin}"


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

ssh_node() {
  local node="$1"
  shift

  local ip="${IP_BY_NODE[$node]}"

  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o LogLevel=ERROR \
    "openstack@${ip}" "$@"
}


refresh_reachability() {
  local node

  for node in "${NODES[@]}"; do

    if ssh_node "$node" 'true' >/dev/null 2>&1; then
      REACHABLE[$node]="yes"
    else
      REACHABLE[$node]="no"
    fi

  done
}


reachable_count() {
  local node
  local count=0

  for node in "${NODES[@]}"; do
    if [[ "${REACHABLE[$node]:-no}" == "yes" ]]; then
      count=$((count + 1))
    fi
  done

  echo "$count"
}


container_state() {
  local node="$1"
  local container="$2"

  ssh_node "$node" \
    "sudo docker inspect \
      --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
      '${container}' 2>/dev/null"
}


container_runtime_state() {
  local node="$1"
  local container="$2"

  ssh_node "$node" \
    "sudo docker inspect \
      --format '{{.State.Status}}' \
      '${container}' 2>/dev/null"
}


container_is_healthy() {
  local node="$1"
  local container="$2"
  local state

  state="$(container_state "$node" "$container" 2>/dev/null || true)"

  [[ "$state" == "running healthy" ]]
}


healthy_count() {
  local container="$1"
  local node
  local count=0

  for node in "${NODES[@]}"; do

    if [[ "${REACHABLE[$node]:-no}" != "yes" ]]; then
      continue
    fi

    if container_is_healthy "$node" "$container"; then
      count=$((count + 1))
    fi

  done

  echo "$count"
}


running_count() {
  local container="$1"
  local node
  local state
  local count=0

  for node in "${NODES[@]}"; do

    if [[ "${REACHABLE[$node]:-no}" != "yes" ]]; then
      continue
    fi

    state="$(container_runtime_state "$node" "$container" 2>/dev/null || true)"

    if [[ "$state" == "running" ]]; then
      count=$((count + 1))
    fi

  done

  echo "$count"
}


show_container_states() {
  local container="$1"
  local node
  local state

  for node in "${NODES[@]}"; do

    if [[ "${REACHABLE[$node]:-no}" != "yes" ]]; then
      printf '      %-5s %s\n' "$node" "unreachable"
      continue
    fi

    state="$(container_state "$node" "$container" 2>/dev/null || true)"

    [[ -n "$state" ]] || state="not-found-or-no-response"

    printf '      %-5s %s\n' "$node" "$state"

  done
}


openstack_auth_ok() {
  command -v openstack >/dev/null 2>&1 &&
  openstack token issue \
    -f value \
    -c expires >/dev/null 2>&1
}


wait_for_container_cluster() {
  local container="$1"
  local expected="$2"
  local timeout="$3"

  local elapsed=0
  local count

  while (( elapsed < timeout )); do

    refresh_reachability

    count="$(healthy_count "$container")"

    if [[ "$count" -eq "$expected" ]]; then
      return 0
    fi

    printf 'Waiting for %s: %s/%s healthy...\n' \
      "$container" "$count" "$expected"

    sleep 5
    elapsed=$((elapsed + 5))

  done

  return 1
}


wait_for_openstack_api() {
  local timeout="$1"
  local elapsed=0

  while (( elapsed < timeout )); do

    if openstack_auth_ok; then
      return 0
    fi

    echo "Waiting for OpenStack authentication..."
    sleep 5
    elapsed=$((elapsed + 5))

  done

  return 1
}


restart_container_service() {
  local node="$1"
  local container="$2"

  local unit="kolla-${container}-container.service"

  echo "Restarting ${container} on ${node}"

  ssh_node "$node" \
    "sudo systemctl reset-failed '${unit}' >/dev/null 2>&1 || true
     sudo systemctl restart '${unit}'"
}


# ------------------------------------------------------------
# Read-only diagnosis / plan
# ------------------------------------------------------------

print_plan() {

  local node
  local nodes_up
  local db_healthy
  local db_running
  local count
  local state

  echo
  echo "OPENSTACK RECOVERY PLAN"
  echo "======================="
  echo

  refresh_reachability

  nodes_up="$(reachable_count)"

  echo "Node reachability: ${nodes_up}/3"

  for node in "${NODES[@]}"; do
    echo "  ${node}: ${REACHABLE[$node]}"
  done

  echo

  if [[ "$nodes_up" -ne 3 ]]; then
    echo "BLOCKED:"
    echo "  Not all OpenStack nodes are reachable."
    echo "  No automatic OpenStack recovery should be attempted."
    echo
    echo "Recommended action:"
    echo "  Fix power/network/SSH reachability first."
    return 1
  fi


  # ----------------------------------------------------------
  # MariaDB / Galera
  # ----------------------------------------------------------

  db_healthy="$(healthy_count mariadb)"
  db_running="$(running_count mariadb)"

  echo "MariaDB:"
  show_container_states mariadb
  echo

  if [[ "$db_healthy" -eq 3 ]]; then

    echo "MariaDB decision:"
    echo "  PASS - 3/3 healthy."
    echo "  No mariadb-recovery required."

  elif [[ "$db_running" -eq 0 ]]; then

    echo "MariaDB decision:"
    echo "  RECOVERY CANDIDATE - no MariaDB container is running."
    echo
    echo "Proposed action:"
    echo "  kolla-ansible mariadb-recovery \\"
    echo "    -i kolla/inventory/multinode"

  else

    echo "MariaDB decision:"
    echo "  MANUAL REVIEW REQUIRED."
    echo
    echo "Reason:"
    echo "  The cluster is neither 3/3 healthy nor completely stopped."
    echo "  This script will NOT run mariadb-recovery for a partial/"
    echo "  ambiguous MariaDB state."

    return 1

  fi

  echo


  # If MariaDB is not yet healthy, dependent service decisions
  # should be made only after database recovery.

  if [[ "$db_healthy" -ne 3 ]]; then

    echo "Dependent services:"
    echo "  Will be re-evaluated after MariaDB recovery."
    echo
    echo "NO CHANGES HAVE BEEN MADE."

    return 0

  fi


  # ----------------------------------------------------------
  # ProxySQL
  # ----------------------------------------------------------

  count="$(healthy_count proxysql)"

  echo "ProxySQL: ${count}/3 healthy"

  if [[ "$count" -ne 3 ]]; then

    for node in "${NODES[@]}"; do

      if ! container_is_healthy "$node" proxysql; then
        state="$(container_state "$node" proxysql 2>/dev/null || true)"
        echo "  Proposed: restart proxysql on ${node} (${state})"
      fi

    done

  fi

  echo


  # ----------------------------------------------------------
  # Control services
  # ----------------------------------------------------------

  local services=(
    placement_api
    nova_conductor
    nova_scheduler
    nova_api
    nova_metadata
    neutron_server
    neutron_rpc_server
    neutron_periodic_worker
  )

  echo "Control services:"

  local service

  for service in "${services[@]}"; do

    count="$(healthy_count "$service")"

    if [[ "$count" -eq 3 ]]; then

      printf '  %-28s 3/3 healthy - no action\n' "$service"

    else

      printf '  %-28s %s/3 healthy\n' "$service" "$count"

      for node in "${NODES[@]}"; do

        if ! container_is_healthy "$node" "$service"; then

          state="$(container_state "$node" "$service" 2>/dev/null || true)"

          echo "      Proposed: restart ${service} on ${node} (${state})"

        fi

      done

    fi

  done

  echo


  # ----------------------------------------------------------
  # Nova computes
  # ----------------------------------------------------------

  if openstack_auth_ok; then

    echo "Nova compute services:"

    while read -r host status service_state; do

      [[ -n "${host:-}" ]] || continue

      if [[ "$service_state" == "up" ]]; then

        echo "  ${host}: status=${status} state=${service_state} - no action"
        continue

      fi

      echo "  ${host}: status=${status} state=${service_state}"

      if [[ "$status" == "disabled" ]]; then

        local reason

        reason="$(
          openstack compute service list \
            --host "$host" \
            --service nova-compute \
            --long \
            -f value \
            -c 'Disabled Reason' 2>/dev/null |
          head -n 1
        )"

        echo "      Disabled Reason: ${reason:-unknown}"

        if [[ "$reason" == AUTO:* ]]; then

          echo "      Proposed:"
          echo "        enable ${host} nova-compute"
          echo "        restart nova_compute on ${host}"

        else

          echo "      MANUAL REVIEW:"
          echo "        compute is disabled but not AUTO-disabled"
          echo "        script will not enable it"

        fi

      else

        echo "      Proposed:"
        echo "        restart nova_compute on ${host}"

      fi

    done < <(
      openstack compute service list \
        --service nova-compute \
        -f value \
        -c Host \
        -c Status \
        -c State 2>/dev/null
    )

  else

    echo "Nova compute services:"
    echo "  OpenStack API authentication unavailable."
    echo "  Compute recovery will be re-evaluated after control-plane repair."

  fi

  echo
  echo "Neutron agents:"
  echo "  Checked by lab-status.sh."
  echo "  Version 1 does NOT automatically restart individual"
  echo "  Neutron agent containers."
  echo
  echo "NO CHANGES HAVE BEEN MADE."

}


# ------------------------------------------------------------
# Apply recovery
# ------------------------------------------------------------

apply_recovery() {

  local answer
  local node
  local nodes_up
  local db_healthy
  local db_running
  local count

  echo
  echo "============================================================"
  echo "RECOVERY APPLY MODE"
  echo "============================================================"
  echo
  echo "This mode may restart OpenStack services."
  echo
  echo "Type APPLY to continue."
  echo "Anything else cancels."
  echo

  read -r -p "> " answer

  if [[ "$answer" != "APPLY" ]]; then
    echo "Cancelled. No changes made."
    exit 0
  fi


  # ----------------------------------------------------------
  # Reachability gate
  # ----------------------------------------------------------

  refresh_reachability
  nodes_up="$(reachable_count)"

  if [[ "$nodes_up" -ne 3 ]]; then

    echo "ERROR:"
    echo "Only ${nodes_up}/3 nodes are reachable."
    echo "Recovery aborted."

    return 1
  fi


  # ----------------------------------------------------------
  # MariaDB safety gate
  # ----------------------------------------------------------

  db_healthy="$(healthy_count mariadb)"
  db_running="$(running_count mariadb)"

  if [[ "$db_healthy" -eq 3 ]]; then

    echo
    echo "MariaDB 3/3 healthy - no database recovery needed."

  elif [[ "$db_running" -eq 0 ]]; then

    echo
    echo "============================================================"
    echo "MARIADB / GALERA RECOVERY APPROVAL"
    echo "============================================================"
    echo
    echo "All nodes are reachable."
    echo "No MariaDB container is currently running."
    echo
    echo "Proposed command:"
    echo
    echo "kolla-ansible mariadb-recovery \\"
    echo "  -i kolla/inventory/multinode"
    echo
    echo "Type MARIADB-RECOVERY to approve this database recovery."
    echo "Anything else cancels."
    echo

    read -r -p "> " answer

    if [[ "$answer" != "MARIADB-RECOVERY" ]]; then
      echo "MariaDB recovery not approved. Stopping."
      return 1
    fi

    if ! command -v kolla-ansible >/dev/null 2>&1; then
      echo "ERROR: kolla-ansible is not available."
      return 1
    fi

    echo
    echo "Running Kolla-Ansible MariaDB recovery..."

    (
      cd "$REPO_ROOT" || exit 1

      kolla-ansible mariadb-recovery \
        -i kolla/inventory/multinode
    )

    if [[ "$?" -ne 0 ]]; then
      echo "ERROR: mariadb-recovery failed."
      return 1
    fi

    echo
    echo "Waiting for MariaDB 3/3 healthy..."

    if ! wait_for_container_cluster mariadb 3 180; then

      echo "ERROR:"
      echo "MariaDB did not become 3/3 healthy within 180 seconds."
      return 1

    fi

    echo "MariaDB recovered: 3/3 healthy."

  else

    echo
    echo "ERROR:"
    echo "MariaDB is in a partial or ambiguous state."
    echo
    echo "Healthy: ${db_healthy}/3"
    echo "Running: ${db_running}/3"
    echo
    echo "Automatic mariadb-recovery is intentionally blocked."
    echo "Use the recovery runbook for manual diagnosis."

    return 1

  fi


  # ----------------------------------------------------------
  # ProxySQL
  # ----------------------------------------------------------

  echo
  echo "Checking ProxySQL..."

  for node in "${NODES[@]}"; do

    if ! container_is_healthy "$node" proxysql; then
      restart_container_service "$node" proxysql
    fi

  done

  sleep 5


  # ----------------------------------------------------------
  # Control plane
  # ----------------------------------------------------------

  local services=(
    placement_api
    nova_conductor
    nova_scheduler
    nova_api
    nova_metadata
    neutron_server
    neutron_rpc_server
    neutron_periodic_worker
  )

  local service

  echo
  echo "Checking control-plane containers..."

  for service in "${services[@]}"; do

    for node in "${NODES[@]}"; do

      if ! container_is_healthy "$node" "$service"; then

        restart_container_service "$node" "$service"

      fi

    done

    sleep 3

  done


  # ----------------------------------------------------------
  # Wait for OpenStack API
  # ----------------------------------------------------------

  echo
  echo "Waiting for OpenStack authentication..."

  if ! wait_for_openstack_api 120; then

    echo "ERROR:"
    echo "OpenStack authentication did not recover within 120 seconds."
    echo
    echo "Stopping before compute recovery."

    return 1
  fi

  echo "OpenStack authentication works."


  # ----------------------------------------------------------
  # Nova compute recovery
  # ----------------------------------------------------------

  echo
  echo "Checking Nova compute services..."

  while read -r host status service_state; do

    [[ -n "${host:-}" ]] || continue

    if [[ "$service_state" == "up" ]]; then
      echo "${host}: nova-compute already up"
      continue
    fi

    echo
    echo "${host}: nova-compute status=${status} state=${service_state}"

    if [[ "$status" == "disabled" ]]; then

      reason="$(
        openstack compute service list \
          --host "$host" \
          --service nova-compute \
          --long \
          -f value \
          -c 'Disabled Reason' 2>/dev/null |
        head -n 1
      )"

      echo "Disabled Reason: ${reason:-unknown}"

      if [[ "$reason" == AUTO:* ]]; then

        echo "AUTO-disabled compute detected."

        echo "Enabling ${host} nova-compute..."

        openstack compute service set \
          --enable "$host" nova-compute

      else

        echo "SKIP:"
        echo "${host} is disabled but not AUTO-disabled."
        echo "It will not be enabled automatically."

        continue

      fi

    fi

    if [[ -z "${IP_BY_NODE[$host]+x}" ]]; then
      echo "ERROR: no IP mapping for compute host ${host}"
      continue
    fi

    restart_container_service "$host" nova_compute

  done < <(
    openstack compute service list \
      --service nova-compute \
      -f value \
      -c Host \
      -c Status \
      -c State 2>/dev/null
  )

  echo
  echo "Waiting 20 seconds for Nova heartbeats..."
  sleep 20


  # ----------------------------------------------------------
  # Final verification
  # ----------------------------------------------------------

  echo
  echo "============================================================"
  echo "FINAL HEALTH CHECK"
  echo "============================================================"
  echo

  "$STATUS_SCRIPT"
}


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

case "$MODE" in

  --check)

    exec "$STATUS_SCRIPT"
    ;;


  --plan)

    "$STATUS_SCRIPT" || true

    print_plan
    ;;


  --apply)

    "$STATUS_SCRIPT" || true

    print_plan || true

    apply_recovery
    ;;

esac
