# OpenStack Reboot and Cold-Boot Recovery Runbook

This runbook documents how to check and recover the current three-node Kolla-Ansible OpenStack homelab after a reboot or complete shutdown.

## Lab

```text
Hermes
  |
  +-- node1  192.168.0.200
  +-- node2  192.168.0.201
  +-- node3  192.168.0.202

Kolla internal VIP: 192.168.0.100
```

All three nodes currently run:

- OpenStack control services
- OpenStack network services
- Nova compute services
- MariaDB/Galera

The purpose of this document is to make reboot recovery predictable instead of troubleshooting from zero every time.

---

# 1. Why this runbook exists

There are two very different reboot situations.

## Rolling reboot

Only one OpenStack node is rebooted while the other two remain running.

This is the preferred maintenance method.

```text
node1 reboot
      ↓
wait until healthy
      ↓
node2 reboot
      ↓
wait until healthy
      ↓
node3 reboot
```

Because two Galera members remain online while one node is rebooted, the database cluster should retain quorum.

## Full cold boot

All three OpenStack nodes are powered off.

Example:

```text
node1 OFF
node2 OFF
node3 OFF
```

When all Galera members disappear, there may be no surviving Primary Component.

After the nodes boot again, MariaDB may therefore require explicit recovery.

The important lesson from this lab is:

```text
Full cluster shutdown
        ↓
Galera recovery problem
        ↓
OpenStack service dependency failures
```

This is not primarily an Ubuntu 24.04 problem.

The same architectural issue can occur regardless of the Ubuntu version because the database cluster itself was completely stopped.

---

# 2. Prepare Hermes

Start from Hermes.

```bash
cd ~/git/openstack-zero-to-hero
```

Activate the Kolla-Ansible virtual environment:

```bash
source ~/venvs/kolla/bin/activate
```

Configure the OpenStack CLI:

```bash
export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin
```

Optional checks:

```bash
kolla-ansible --version
openstack --version
```

---

# 3. First check: are all nodes reachable?

Always begin with the physical/operating-system layer.

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="
  ssh openstack@192.168.0.$ip \
    'hostname; uptime'
done
```

Expected result:

```text
node1 reachable
node2 reachable
node3 reachable
```

If SSH does not work to a node:

```text
STOP
```

Do not troubleshoot OpenStack services yet.

First investigate:

```text
power
network
bridge configuration
IP address
SSH
```

---

# 4. Check MariaDB FIRST

MariaDB is one of the most important dependencies in the OpenStack control plane.

Check it before restarting Nova, Neutron, Placement, or other database-dependent services.

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="
  ssh openstack@192.168.0.$ip \
    'sudo docker ps -a --filter name=mariadb \
      --format "table {{.Names}}\t{{.Status}}"'
done
```

Healthy target:

```text
===== NODE 200 =====
mariadb   Up ... (healthy)

===== NODE 201 =====
mariadb   Up ... (healthy)

===== NODE 202 =====
mariadb   Up ... (healthy)
```

If all three MariaDB containers are healthy:

```text
DO NOT RUN mariadb-recovery
```

Continue to the next checks.

---

# 5. Full cold boot: MariaDB/Galera recovery

If all three nodes were powered off and MariaDB cannot form a healthy cluster again, use Kolla-Ansible's recovery procedure.

From Hermes:

```bash
kolla-ansible mariadb-recovery \
  -i kolla/inventory/multinode
```

Kolla-Ansible performs the Galera recovery procedure and determines which member should be used for recovery.

Normal recovery should NOT involve manually editing:

```text
grastate.dat
```

Do not manually run:

```text
galera_new_cluster
```

for the normal homelab recovery workflow.

After Kolla recovery completes, verify MariaDB again:

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="
  ssh openstack@192.168.0.$ip \
    'sudo docker ps --filter name=mariadb \
      --format "table {{.Names}}\t{{.Status}}"'
done
```

Do not continue until all three MariaDB containers are healthy.

---

# 6. Check ProxySQL

Once MariaDB is healthy, check ProxySQL.

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="
  ssh openstack@192.168.0.$ip \
    'sudo docker ps --filter name=proxysql \
      --format "table {{.Names}}\t{{.Status}}"'
done
```

Expected:

```text
node1  proxysql  healthy
node2  proxysql  healthy
node3  proxysql  healthy
```

The important dependency chain is:

```text
MariaDB
   ↓
ProxySQL
   ↓
OpenStack database clients
```

---

# 7. Check the OpenStack control-plane containers

After MariaDB and ProxySQL are healthy, inspect Placement, Nova, and Neutron.

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="

  ssh openstack@192.168.0.$ip \
    'sudo docker ps -a --format "table {{.Names}}\t{{.Status}}" |
     grep -E "placement_api|nova_api|nova_metadata|nova_scheduler|nova_conductor|neutron_server|neutron_rpc_server|neutron_periodic_worker"'
done
```

Healthy services should normally show:

```text
Up ... (healthy)
```

A useful recovery dependency order is:

```text
MariaDB
   ↓
ProxySQL
   ↓
Placement
   ↓
Nova conductor
   ↓
Nova scheduler
   ↓
Nova API / metadata
   ↓
Neutron server
```

Do not mass-restart these services before confirming that MariaDB is healthy.

---

# 8. How Kolla containers are restarted

One important lesson from this lab was that Docker itself is not the only supervisor.

Docker inspection showed:

```text
RestartPolicy=no
```

but Kolla created systemd units with:

```text
Restart=always
```

The actual model is:

```text
systemd
   ↓
kolla-<container>-container.service
   ↓
Docker container
```

Therefore prefer the Kolla-created systemd service when restarting a container.

Example:

```bash
ssh openstack@192.168.0.200 \
  'sudo systemctl restart kolla-nova_conductor-container.service'
```

General pattern:

```text
kolla-<container-name>-container.service
```

Examples:

```text
kolla-placement_api-container.service

kolla-nova_api-container.service
kolla-nova_metadata-container.service
kolla-nova_scheduler-container.service
kolla-nova_conductor-container.service
kolla-nova_compute-container.service
kolla-nova_libvirt-container.service

kolla-neutron_server-container.service
```

Inspect systemd supervision:

```bash
sudo systemctl show kolla-nova_compute-container.service \
  -p Restart \
  -p NRestarts \
  -p ActiveState \
  -p SubState
```

Example healthy systemd state:

```text
Restart=always
ActiveState=active
SubState=running
```

---

# 9. Docker health is not OpenStack health

Another important lesson:

```text
Docker healthy
```

does not necessarily mean:

```text
OpenStack service healthy
```

A container can be running and passing its Docker healthcheck while the application inside is unable to participate correctly in OpenStack.

We observed exactly this with:

```text
nova_compute
```

The container reported:

```text
healthy
```

while Nova reported the compute service:

```text
down
```

Therefore always perform OpenStack-level validation after checking containers.

---

# 10. Validate OpenStack authentication

Test Keystone authentication:

```bash
openstack token issue
```

Successful output confirms the OpenStack CLI can authenticate.

Do not copy authentication tokens into:

```text
GitHub
documentation
chat logs
scripts
```

---

# 11. Check Nova services

Run:

```bash
openstack compute service list
```

Healthy target:

```text
nova-scheduler  node1  enabled  up
nova-scheduler  node2  enabled  up
nova-scheduler  node3  enabled  up

nova-conductor  node1  enabled  up
nova-conductor  node2  enabled  up
nova-conductor  node3  enabled  up

nova-compute    node1  enabled  up
nova-compute    node2  enabled  up
nova-compute    node3  enabled  up
```

Remember the difference:

```text
Status
```

means administrative scheduling state:

```text
enabled / disabled
```

while:

```text
State
```

represents whether Nova considers the service alive:

```text
up / down
```

Example:

```text
Status = enabled
State  = down
```

means the service is allowed to participate, but Nova is not receiving the expected heartbeat.

---

# 12. Check hypervisors

Run:

```bash
openstack hypervisor list
```

Healthy target:

```text
node1   up
node2   up
node3   up
```

Example:

```text
+---------------------+-------+
| Hypervisor Hostname | State |
+---------------------+-------+
| node1               | up    |
| node2               | up    |
| node3               | up    |
+---------------------+-------+
```

---

# 13. Check Neutron agents

Run:

```bash
openstack network agent list
```

The current deployment contains agents such as:

```text
DHCP agent
Open vSwitch agent
L3 agent
Metadata agent
```

on all three nodes.

Healthy agents should show:

```text
Alive = :-)
State = UP
```

---

# 14. If one nova-compute is DOWN

Example:

```text
Host   Binary         Status    State
node1  nova-compute   disabled  down
```

First get more information.

```bash
openstack compute service list \
  --host node1 \
  --service nova-compute \
  --long
```

Check the local container:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker ps -a --filter name=nova_compute \
    --format "table {{.Names}}\t{{.Status}}"'
```

Check libvirt:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker ps -a --filter name=nova_libvirt \
    --format "table {{.Names}}\t{{.Status}}"'
```

Inspect nova-compute logs:

```bash
ssh openstack@192.168.0.200 \
  'sudo tail -n 200 \
    /var/lib/docker/volumes/kolla_logs/_data/nova/nova-compute.log |
    grep -Ei "libvirt|ERROR|CRITICAL|Traceback|connection|heartbeat|conductor" |
    tail -n 100'
```

Diagnose before restarting anything.

---

# 15. AUTO-disabled nova-compute

During the first cold-boot recovery, node1 showed:

```text
Disabled Reason:
AUTO: Connection to libvirt lost
```

The container itself was:

```text
Up ... (healthy)
```

but OpenStack reported:

```text
nova-compute
State = down
```

Later, the nova-compute logs repeatedly showed:

```text
Timed out waiting for nova-conductor.
Is it running?
Or did this service start before nova-conductor?
```

This occurred after the control plane had been unavailable because of the database failure.

After confirming:

```text
MariaDB healthy
ProxySQL healthy
nova-conductor healthy
nova-libvirt healthy
```

node1 compute was re-enabled:

```bash
openstack compute service set \
  --enable node1 nova-compute
```

Then only node1 nova-compute was restarted:

```bash
ssh openstack@192.168.0.200 \
  'sudo systemctl restart kolla-nova_compute-container.service'
```

After waiting for a fresh Nova heartbeat:

```bash
openstack compute service list \
  --host node1 \
  --service nova-compute \
  --long
```

returned:

```text
Status = enabled
State  = up
```

and:

```bash
openstack hypervisor list
```

returned:

```text
node1 up
node2 up
node3 up
```

Do not automatically enable a compute service that was intentionally disabled by an administrator.

Check the `Disabled Reason` first.

---

# 16. Observed full cold-boot failure

The first full shutdown/restart of this deployment produced this sequence:

```text
All three OpenStack nodes powered off
        ↓
All Galera members stopped
        ↓
No surviving Galera Primary Component
        ↓
MariaDB could not form a healthy cluster normally
        ↓
Nova / Placement / Neutron lost database access
        ↓
some services exited
others remained running but unhealthy
        ↓
kolla-ansible mariadb-recovery
        ↓
MariaDB recovered 3/3
        ↓
ProxySQL healthy 3/3
        ↓
database-dependent control services recovered/restarted
        ↓
Placement healthy
        ↓
Nova control plane healthy
        ↓
Neutron control plane healthy
        ↓
node1 nova-compute still reported DOWN
        ↓
nova-compute logs showed conductor RPC timeouts
        ↓
node1 nova-compute restarted
        ↓
heartbeat returned
        ↓
all three hypervisors UP
```

This is the known recovery pattern for the lab.

---

# 17. Preferred rolling reboot procedure

Whenever possible, reboot one node at a time rather than shutting down all three simultaneously.

Before starting:

```bash
openstack compute service list
openstack hypervisor list
openstack network agent list
```

Make sure the cloud is healthy first.

## Reboot node1

Always verify the machine identity before a reboot.

```bash
ssh openstack@192.168.0.200 'hostname'
```

Expected:

```text
node1
```

Then:

```bash
ssh openstack@192.168.0.200 \
  'hostname; sudo reboot'
```

Wait until it comes back:

```bash
until ssh -o ConnectTimeout=3 \
  openstack@192.168.0.200 'hostname'; do
  echo "Waiting for node1..."
  sleep 5
done
```

Check MariaDB:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker ps --filter name=mariadb \
    --format "table {{.Names}}\t{{.Status}}"'
```

Check compute:

```bash
openstack compute service list \
  --host node1 \
  --service nova-compute \
  --long
```

Check Neutron:

```bash
openstack network agent list \
  --host node1
```

Check hypervisors:

```bash
openstack hypervisor list
```

Only proceed when node1 is healthy again.

Then repeat the same process for:

```text
node2
```

and later:

```text
node3
```

Do not reboot node2 while node1 is still unhealthy.

---

# 18. Full cold-boot quick checklist

Use this checklist after all three SFF machines have been powered on.

```text
PHYSICAL / OS

[ ] node1 reachable
[ ] node2 reachable
[ ] node3 reachable


DATABASE

[ ] MariaDB node1 healthy
[ ] MariaDB node2 healthy
[ ] MariaDB node3 healthy

If the complete Galera cluster failed:

[ ] kolla-ansible mariadb-recovery completed


DATABASE PROXY

[ ] ProxySQL node1 healthy
[ ] ProxySQL node2 healthy
[ ] ProxySQL node3 healthy


CONTROL PLANE

[ ] Placement healthy

[ ] Nova conductor healthy
[ ] Nova scheduler healthy
[ ] Nova API healthy
[ ] Nova metadata healthy

[ ] Neutron server healthy
[ ] Neutron RPC server healthy
[ ] Neutron periodic worker healthy


OPENSTACK API

[ ] openstack token issue works


COMPUTE

[ ] node1 nova-compute State=up
[ ] node2 nova-compute State=up
[ ] node3 nova-compute State=up

[ ] node1 hypervisor up
[ ] node2 hypervisor up
[ ] node3 hypervisor up


NETWORKING

[ ] Neutron agents all Alive
[ ] Neutron agents all UP
```

If every check passes:

```text
OPENSTACK LAB RECOVERED
```

---

# 19. Useful log locations

Nova:

```text
/var/lib/docker/volumes/kolla_logs/_data/nova/
```

Placement:

```text
/var/lib/docker/volumes/kolla_logs/_data/placement/
```

Neutron:

```text
/var/lib/docker/volumes/kolla_logs/_data/neutron/
```

MariaDB:

```text
/var/lib/docker/volumes/kolla_logs/_data/mariadb/
```

---

# 20. Troubleshooting philosophy

Do not immediately restart the entire cloud.

Use this order:

```text
1. Reachability
      ↓
2. MariaDB
      ↓
3. ProxySQL
      ↓
4. Placement
      ↓
5. Nova control plane
      ↓
6. Neutron control plane
      ↓
7. Nova compute
      ↓
8. OpenStack API verification
```

The rule is:

```text
diagnose
   ↓
understand dependency
   ↓
repair only broken component
   ↓
validate
```

not:

```text
restart everything
and hope
```

---

# 21. Rules for future Hermes-assisted recovery

When Hermes is later asked something such as:

```text
Check my OpenStack lab after reboot.
```

or:

```text
Recover my OpenStack lab.
```

Hermes should use this runbook as the recovery procedure.

Rules:

1. Diagnose before changing anything.
2. Check node reachability first.
3. Check MariaDB before OpenStack application services.
4. Never run `mariadb-recovery` if Galera is already healthy.
5. Use Kolla-Ansible `mariadb-recovery` for a complete Galera outage.
6. Do not manually edit `grastate.dat` during normal recovery.
7. Do not manually use `galera_new_cluster` during normal recovery.
8. Wait for MariaDB to become healthy before repairing database-dependent services.
9. Check ProxySQL after MariaDB.
10. Restart only unhealthy or stale services.
11. Prefer the Kolla-created systemd service for container restarts.
12. Never automatically enable a manually disabled Nova compute service.
13. Check `Disabled Reason` before enabling a compute service.
14. Validate container health and OpenStack application health separately.
15. Validate with the OpenStack CLI after repairs.
16. Never expose `/etc/kolla/passwords.yml`.
17. Never expose passwords from `/etc/kolla/clouds.yaml`.
18. Never copy OpenStack authentication tokens into logs or GitHub.
19. Explain what appears broken before repairing it.
20. After repair, rerun health checks and report PASS or FAIL.

---

# 22. Current recovery helper scripts

The helper scripts are now implemented:

```text
scripts/lab-status.sh
scripts/lab-recover.sh
```

## lab-status.sh

This script is read-only.

Run:

```bash
cd ~/git/openstack-zero-to-hero
./scripts/lab-status.sh
```

Healthy result:

```text
RESULT: HEALTHY
PASS checks: 14
```

A non-zero exit status means attention is required.

Example:

```bash
./scripts/lab-status.sh
echo $?
```

```text
0 = healthy
1 = attention required
```

---

## lab-recover.sh

The recovery helper supports:

```bash
./scripts/lab-recover.sh --check
./scripts/lab-recover.sh --plan
./scripts/lab-recover.sh --apply
```

Meaning:

```text
--check
    read-only health check

--plan
    diagnose and describe proposed repairs

--apply
    request approval and repair supported failures
```

Important:

```bash
./scripts/lab-recover.sh
```

without an argument defaults to:

```text
--check
```

It does NOT perform recovery.

The tested safety model is:

```text
diagnose
   ↓
plan
   ↓
human approval
   ↓
repair only broken services
   ↓
final health check
```

The script has been tested with a deliberately stopped
`placement_api` on node1.

It correctly detected:

```text
placement_api 2/3 healthy
```

proposed:

```text
restart placement_api on node1
```

and, after approval, restarted only that service.

Final result:

```text
RESULT: HEALTHY
```

---

# 23. Proven full cold-boot recovery procedure

A complete shutdown of all three OpenStack nodes has now produced the
same Galera failure more than once.

The important pattern is:

```text
all three nodes powered off
        ↓
all Galera members disappear
        ↓
no surviving PRIMARY component
        ↓
MariaDB containers may show:

running starting

or:

exited unhealthy

        ↓
MariaDB remains 0/3 healthy
        ↓
Keystone / Placement / Nova / Neutron fail
```

Important lesson:

```text
running != healthy
```

A MariaDB container being in:

```text
running starting
```

does NOT prove that the Galera cluster has recovered.

---

## Cold-boot Step 1: check the lab

After powering on all nodes:

```bash
cd ~/git/openstack-zero-to-hero
source ~/venvs/kolla/bin/activate

export OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
export OS_CLOUD=kolla-admin

./scripts/lab-status.sh
```

If MariaDB reports:

```text
MariaDB: 3/3 healthy
```

do NOT run `mariadb-recovery`.

Continue with normal service validation.

---

## Cold-boot Step 2: recognize the known Galera failure

Known failure example:

```text
MariaDB: 0/3 healthy

node1/mariadb=running starting
node2/mariadb=running starting
node3/mariadb=running starting
```

At the same time, dependent services may report:

```text
Placement unhealthy
Nova unhealthy
Neutron unhealthy
Keystone authentication failed
```

Do NOT begin by restarting those services.

The database is the first dependency to repair.

---

## Cold-boot Step 3: recover Galera

Run:

```bash
kolla-ansible mariadb-recovery \
  -i kolla/inventory/multinode
```

Do not manually:

```text
edit grastate.dat
change safe_to_bootstrap
run galera_new_cluster
```

during the normal Kolla recovery workflow.

After recovery:

```bash
./scripts/lab-status.sh
```

The first required milestone is:

```text
MariaDB: 3/3 healthy
ProxySQL: 3/3 healthy
```

---

## Cold-boot Step 4: repair stale OpenStack services

After MariaDB has recovered, some OpenStack processes may remain
unhealthy because they started while the database was unavailable.

First inspect the proposed actions:

```bash
./scripts/lab-recover.sh --plan
```

Confirm that MariaDB shows:

```text
3/3 healthy
No mariadb-recovery required
```

Then inspect which Placement, Nova, or Neutron services are proposed
for restart.

If the plan is correct:

```bash
./scripts/lab-recover.sh --apply
```

At the prompt:

```text
Type APPLY to continue.
```

enter:

```text
APPLY
```

The script restarts supported unhealthy/stale services and performs a
final health check.

Target:

```text
RESULT: HEALTHY
PASS checks: 14
```

---

# 24. Preferred operating rule

For normal maintenance:

```text
DO NOT reboot all three control nodes together.
```

Use:

```text
node1 reboot
     ↓
wait for HEALTHY
     ↓
node2 reboot
     ↓
wait for HEALTHY
     ↓
node3 reboot
     ↓
wait for HEALTHY
```

This allows the remaining Galera members to retain quorum.

For an intentional full shutdown:

```text
expect possible Galera recovery
```

and use the procedure in Section 23.

The practical cold-boot recovery sequence is:

```text
./scripts/lab-status.sh
        ↓
MariaDB 0/3?
        ↓
kolla-ansible mariadb-recovery
        ↓
./scripts/lab-status.sh
        ↓
MariaDB 3/3
        ↓
./scripts/lab-recover.sh --plan
        ↓
./scripts/lab-recover.sh --apply
        ↓
./scripts/lab-status.sh
        ↓
RESULT: HEALTHY
```
