# Kolla-Ansible Deployment 101

This chapter explains how the three-node homelab moved from prepared Ubuntu hosts to a working OpenStack cloud using Kolla-Ansible.

The purpose is not only to record commands.

The goal is to understand what each Kolla-Ansible stage does, what services appear, how the deployed cloud maps to Linux and Docker, and how to verify that the cloud is actually healthy.

The core workflow is:

```text
prepare hosts
     ↓
bootstrap-servers
     ↓
prechecks
     ↓
deploy
     ↓
post-deploy
     ↓
validate
     ↓
operate
```

These stages are related, but they are not interchangeable.

---

# 1. Lab Architecture

The OpenStack cluster contains three physical nodes:

```text
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
```

All three nodes run:

```text
Ubuntu 24.04 LTS
Docker
KVM
OpenStack control services
OpenStack network services
OpenStack compute services
```

The control machine is:

```text
Hermes
```

Hermes is not an OpenStack compute node.

It is the administration and automation machine.

Hermes runs tools such as:

```text
Ansible
Kolla-Ansible
OpenStack CLI
Terraform
Git
```

Conceptually:

```text
                         HERMES
                           |
                 Ansible / Kolla-Ansible
                           |
             +-------------+-------------+
             |             |             |
             v             v             v
           node1         node2         node3
             |             |             |
           Docker        Docker        Docker
             |             |             |
             +-------------+-------------+
                           |
                       OpenStack
```

---

# 2. Current Network Architecture

The lab originally used a single-NIC workaround.

That learning stage is documented in:

```text
docs/03-openstack-single-nic-networking.md
```

The current lab uses two physical NIC roles.

## Management / control / VXLAN

```text
br-mgmt
   |
enp0s31f6
   |
physical LAN
```

Management addresses:

```text
node1 = 192.168.0.200/24
node2 = 192.168.0.201/24
node3 = 192.168.0.202/24
```

The OpenStack internal API VIP is:

```text
192.168.0.100/32
```

## Neutron external/provider traffic

```text
br-ex
  |
ext0
  |
physical LAN
```

`ext0` is the dedicated USB Ethernet interface used as the Neutron external uplink.

It does not need a normal host IPv4 address.

The full migration and Netplan configuration are documented in:

```text
docs/17-openstack-dual-nic-networking.md
```

---

# 3. Current Kolla Network Mapping

The important Kolla networking settings are:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "ext0"
```

Meaning:

```text
br-mgmt
    management traffic
    OpenStack API/control traffic
    VXLAN/tunnel underlay in this lab

ext0
    Neutron external/provider Layer-2 uplink
```

The original single-NIC deployment used:

```yaml
neutron_external_interface: "veth-ovs"
```

That value belongs to the historical single-NIC stage.

The current cluster uses:

```yaml
neutron_external_interface: "ext0"
```

Do not copy the old value into the current dual-NIC deployment.

---

# 4. Important globals.yml Concepts

A simplified representation of the important settings is:

```yaml
kolla_base_distro: "ubuntu"

kolla_container_engine: "docker"

kolla_internal_vip_address: "192.168.0.100"

network_interface: "br-mgmt"

neutron_external_interface: "ext0"

nova_compute_virt_type: "kvm"
```

Meaning:

```text
ubuntu
    base distribution used by Kolla images

docker
    container engine

192.168.0.100
    highly available OpenStack API VIP

br-mgmt
    host management/control interface

ext0
    Neutron external/provider uplink

kvm
    hardware-assisted virtualization
```

The real `/etc/kolla/globals.yml` may contain additional settings.

Passwords and secrets must not be committed to GitHub.

Later in the repository we keep a sanitized example rather than publishing the live secrets file.

---

# 5. Deployment Workflow

The complete learning path was:

```text
Ubuntu installation
       ↓
openstack user
       ↓
passwordless SSH
       ↓
Ansible connectivity
       ↓
base preparation
       ↓
preflight validation
       ↓
network preparation
       ↓
Kolla inventory
       ↓
globals.yml
       ↓
passwords.yml
       ↓
Kolla dependencies
       ↓
bootstrap-servers
       ↓
prechecks
       ↓
deploy
       ↓
post-deploy
       ↓
OpenStack validation
```

The first stages prepare Linux.

Kolla-Ansible then turns those Linux hosts into an OpenStack cloud.

---

# 6. Kolla vs Kolla-Ansible

These names are related but different.

```text
Kolla
    provides container images

Kolla-Ansible
    uses Ansible to configure and deploy
    those containerized OpenStack services
```

A useful mental model is:

```text
Kolla
    = WHAT is packaged

Kolla-Ansible
    = HOW it is deployed
```

Kolla-Ansible runs from Hermes and connects to the nodes using SSH and Ansible.

---

# 7. Inventory

Kolla-Ansible needs an inventory describing which hosts perform which roles.

This lab uses:

```text
kolla/inventory/multinode
```

The three nodes participate in multiple roles.

Conceptually:

```text
NODE1             NODE2             NODE3

control           control           control
network           network           network
compute           compute           compute
```

This is a compact converged homelab design.

It is useful for learning because all three machines participate in the cloud rather than dedicating one machine exclusively to a single role.

---

# 8. bootstrap-servers

The bootstrap stage was run from Hermes:

```bash
kolla-ansible bootstrap-servers \
  -i kolla/inventory/multinode
```

Its job is to prepare the operating systems for Kolla.

Think:

```text
bootstrap-servers
    =
prepare Linux hosts
```

It performs host-level preparation required by Kolla-Ansible.

The important distinction is:

```text
bootstrap-servers
    does NOT mean
OpenStack is already deployed
```

After bootstrap, the hosts are prepared for the deployment.

---

# 9. Docker After Bootstrap

Docker was installed and running on all three nodes.

The lab observed:

```text
node1
Docker 29.8.1
active

node2
Docker 29.8.1
active

node3
Docker 29.8.1
active
```

Docker is the runtime used by this Kolla deployment.

Later, OpenStack services appear as Docker containers.

---

# 10. prechecks

Before deployment we ran:

```bash
kolla-ansible prechecks \
  -i kolla/inventory/multinode \
  --use-test-images
```

The final precheck result was:

```text
localhost  failed=0
node1      failed=0
node2      failed=0
node3      failed=0
```

Think:

```text
prechecks
    =
"Does the environment look ready for deployment?"
```

Prechecks are not the deployment itself.

They validate prerequisites and configuration assumptions.

---

# 11. Why --use-test-images Was Used

The lab image configuration used:

```text
quay.io/openstack.kolla
```

Kolla-Ansible required explicit acknowledgement of the test/evaluation image namespace during prechecks.

Therefore:

```bash
--use-test-images
```

was supplied.

This does not mean:

```text
skip validation
```

It means that the operator explicitly acknowledges the image source being used.

For a learning homelab this was acceptable.

A production environment should use a deliberate image-management and registry strategy.

---

# 12. deploy

The main deployment command was:

```bash
kolla-ansible deploy \
  -i kolla/inventory/multinode
```

This command was run from:

```text
Hermes
```

inside the Kolla Python virtual environment.

This is the stage that turns:

```text
prepared Linux hosts
+
Docker
+
networking
```

into:

```text
a running OpenStack cloud
```

Memory:

```text
BOOTSTRAP
    prepare hosts

PRECHECKS
    validate hosts

DEPLOY
    build OpenStack
```

---

# 13. What Deployment Creates

Kolla-Ansible deploys containerized OpenStack services and supporting infrastructure.

Core services in this lab include concepts such as:

```text
Keystone
Glance
Nova
Placement
Neutron
Heat
Horizon
```

Supporting infrastructure includes:

```text
MariaDB
RabbitMQ
Memcached
HAProxy
Keepalived
ProxySQL
Open vSwitch
```

OpenStack is not one daemon.

It is a collection of cooperating services.

---

# 14. OpenStack Memory Model

A compact memory model:

```text
Keystone
    WHO?

Glance
    IMAGE?

Nova
    VM?

Placement
    WHERE?

Neutron
    NETWORK?

MariaDB
    REMEMBER

RabbitMQ
    TALK

HAProxy
    LOAD BALANCE

Keepalived
    VIP

KVM
    RUN
```

These are shortcuts, not full definitions.

They are useful when first learning the architecture.

---

# 15. MariaDB

OpenStack services require persistent state.

Examples include:

```text
Keystone
Nova
Neutron
Glance
Placement
```

They store information in databases.

Conceptually:

```text
OpenStack services
       |
       v
    MariaDB
```

Memory:

```text
MariaDB = REMEMBER
```

This lab runs MariaDB as a clustered control-plane service.

---

# 16. ProxySQL

ProxySQL sits in front of the database layer and provides database proxying/load-balancing functionality for the deployed architecture.

A useful simplified picture is:

```text
OpenStack service
       |
       v
    ProxySQL
       |
       v
    MariaDB
```

The health script therefore checks both:

```text
MariaDB
ProxySQL
```

---

# 17. RabbitMQ

RabbitMQ provides messaging between distributed OpenStack services.

For example:

```text
Nova API
   |
RabbitMQ
   |
Nova services
```

Memory:

```text
RabbitMQ = TALK
```

Important:

```text
VM network packets do NOT pass through RabbitMQ.
```

RabbitMQ is part of the control/service communication plane.

Neutron data-plane packets travel through Linux networking and Open vSwitch.

---

# 18. HAProxy

OpenStack APIs run across multiple control nodes.

Clients do not need to target individual nodes.

Instead they use the API VIP:

```text
192.168.0.100
```

Conceptually:

```text
OpenStack client
      |
      v
192.168.0.100
      |
      v
   HAProxy
      |
 +----+----+
 |    |    |
 v    v    v
node1 node2 node3
```

Memory:

```text
HAProxy = LOAD BALANCE
```

---

# 19. Keepalived

Keepalived provides high availability for the VIP:

```text
192.168.0.100/32
```

Only one node owns that VIP at a particular moment.

Conceptually:

```text
node1
node2
node3
   |
Keepalived
   |
192.168.0.100
```

If the active owner disappears, another eligible node can take over.

During the validated cold boot documented later in this chapter, the VIP was observed on:

```text
node2
```

attached to:

```text
br-mgmt
```

---

# 20. Keystone

Keystone provides identity and authentication.

Memory:

```text
Keystone = WHO
```

It manages concepts such as:

```text
users
projects
roles
tokens
authentication
service catalog
```

A useful health check is therefore not merely:

```text
Is the Keystone container running?
```

but:

```text
Can the OpenStack CLI authenticate successfully?
```

---

# 21. Glance

Glance provides the Image service.

Memory:

```text
Glance = IMAGE
```

Conceptually:

```text
cloud image
    |
    v
  Glance
    |
    v
   Nova
    |
    v
    VM
```

The CirrOS image used by test VMs is stored and served through the OpenStack image workflow.

---

# 22. Placement

Placement tracks compute resource inventories and allocations.

Examples:

```text
CPU
RAM
resource providers
allocations
```

Memory:

```text
Placement = WHERE resources are available
```

Nova Scheduler uses resource information when deciding where an instance can run.

---

# 23. Nova

Nova provides Compute.

Memory:

```text
Nova = VM
```

Nova manages lifecycle operations such as:

```text
create
start
stop
delete
resize
migrate
```

The execution chain is approximately:

```text
Nova
  |
nova-compute
  |
libvirt
  |
QEMU
  |
KVM
  |
hardware
```

All three homelab nodes currently participate as compute hosts.

---

# 24. Neutron

Neutron provides OpenStack networking.

Memory:

```text
Neutron = NETWORK
```

It manages logical objects such as:

```text
networks
subnets
ports
routers
Floating IPs
security groups
```

The detailed packet path is documented in:

```text
docs/05-neutron-packet-walk.md
```

---

# 25. Open vSwitch

The lab uses Open vSwitch for software switching.

Important bridges include:

```text
br-int
br-ex
```

Conceptually:

```text
br-int
    OpenStack internal integration switching

br-ex
    external/provider network bridge
```

The current external path is:

```text
br-ex
  |
ext0
  |
physical LAN
```

---

# 26. OVS Commands in This Kolla Lab

An important operational lesson is that OVS commands are executed through the Kolla Open vSwitch container.

Do not assume that this host command is the correct inspection method:

```text
ovs-vsctl show
```

Use:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
```

Inspect the external bridge:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

Current expected ports include:

```text
ext0
phy-br-ex
```

This was validated on all three nodes.

---

# 27. Heat

Heat provides OpenStack-native orchestration.

It can create groups of OpenStack resources from templates.

Conceptually:

```text
template
   |
   v
 Heat
   |
   +-- networks
   +-- routers
   +-- instances
   +-- other resources
```

Terraform is also used in this repository.

The two tools solve related automation problems from different ecosystems.

---

# 28. Horizon

Horizon is the OpenStack web dashboard.

It gives a graphical view of resources such as:

```text
instances
images
networks
routers
projects
users
```

Horizon is a client of the OpenStack APIs.

It is not the control plane by itself.

---

# 29. Approximate Deployment Sequence

Do not treat this as an exact internal task order for every Kolla release.

Conceptually deployment includes work such as:

```text
gather host information
       ↓
generate configuration
       ↓
prepare container configuration
       ↓
pull container images
       ↓
deploy infrastructure services
       ↓
initialize databases
       ↓
start messaging
       ↓
configure HA/load balancing
       ↓
deploy OpenStack APIs
       ↓
deploy compute/network agents
       ↓
register services/endpoints
       ↓
validate service state
```

Ansible handles dependencies between the many individual tasks.

---

# 30. Service Registration

OpenStack services need to discover and trust one another.

Keystone maintains the Service Catalog.

Conceptually:

```text
Keystone Service Catalog

Nova
    compute API endpoint

Neutron
    networking API endpoint

Glance
    image API endpoint

Heat
    orchestration API endpoint
```

After authentication, clients can discover the appropriate service endpoints.

---

# 31. Databases

Major OpenStack services generally maintain separate logical databases.

Conceptually:

```text
MariaDB

├── keystone
├── nova
├── neutron
├── glance
└── placement
```

They use shared database infrastructure while keeping application data logically separated.

---

# 32. Docker Containers

After deployment, OpenStack processes run inside Docker containers.

Typical names may resemble:

```text
keystone
glance_api
nova_api
nova_compute
neutron_server
neutron_l3_agent
neutron_openvswitch_agent
rabbitmq
mariadb
haproxy
keepalived
```

Exact names depend on the deployed Kolla release and enabled services.

On a node:

```bash
sudo docker ps
```

shows the running containers.

---

# 33. Checking Containers on All Nodes

From Hermes:

```bash
ansible baremetal \
  -i kolla/inventory/multinode \
  -b \
  -m shell \
  -a 'echo "===== $(hostname) ====="; docker ps'
```

This is useful for learning which services run on which node.

For targeted troubleshooting, SSH directly to the relevant node and inspect only the required container.

---

# 34. Ansible vs Docker Template Syntax

Docker supports Go-template formatting such as:

```text
{{.Names}}
```

Ansible uses Jinja syntax:

```text
{{ ... }}
```

Therefore embedding this directly inside some Ansible shell commands can cause Ansible to interpret Docker's formatting expression as Jinja.

For example:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

may fail before the remote shell executes.

For simple ad-hoc inspection, use:

```bash
docker ps
```

or carefully escape/template the command.

This is a useful example of two automation tools using similar syntax for different purposes.

---

# 35. Reading Ansible Output

During Kolla-Ansible operations you see results such as:

```text
ok
changed
skipping
FAILED
```

Meaning:

```text
ok
    desired state already satisfied

changed
    Ansible changed the target

skipping
    task does not apply to this host/configuration

FAILED
    task could not complete
```

Many skipped tasks are normal because Kolla-Ansible supports many services and configurations that this lab does not enable.

---

# 36. Image Pulling

Deployment requires container images on the nodes that run each service.

Conceptually:

```text
image registry
     |
     +--> node1
     |
     +--> node2
     |
     +--> node3
```

The first deployment therefore performs significantly more image download and initialization work than an already-running cluster.

---

# 37. What to Do When Deploy Fails

Do not start with random changes.

Do not restart every container.

Do not reinstall packages without understanding the error.

Use:

```text
1. identify the first meaningful failed task
2. identify the failed host
3. read the exact error
4. identify the affected service
5. inspect that service
6. change one thing
7. rerun the appropriate automation
```

Look for:

```text
TASK [...]
fatal: [...]
PLAY RECAP
```

The first meaningful failure often explains the errors that follow.

---

# 38. Idempotency

Ansible automation is designed around desired state.

Conceptually:

```text
desired state
      |
      v
   Ansible
      |
      v
actual state
```

Example:

First run:

```text
package missing
     ↓
install package
     ↓
changed
```

Second run:

```text
package already present
     ↓
nothing required
     ↓
ok
```

That is idempotency.

Kolla-Ansible benefits from the same automation model.

---

# 39. Rerunning Is Not the Same as Troubleshooting

Idempotent automation means reruns are often useful.

But:

```text
rerun command
```

should not replace:

```text
understand failure
```

This project intentionally records failure modes and recovery paths because understanding them is part of the learning goal.

---

# 40. Post-Deployment Client Access

After deployment, Hermes became the OpenStack administration client.

The environment currently uses:

```text
OpenStack CLI
OS_CLOUD=kolla-admin
OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml
```

A simple API validation is:

```bash
openstack token issue
```

or another read-only OpenStack CLI query.

The lab health script performs a Keystone authentication check automatically.

---

# 41. OpenStack CLI Examples

From Hermes:

```bash
openstack service list
```

```bash
openstack compute service list
```

```bash
openstack hypervisor list
```

```bash
openstack network agent list
```

```bash
openstack server list --all-projects
```

These commands inspect the logical OpenStack control-plane state.

They complement container-level inspection on the physical nodes.

---

# 42. Inspecting the VIP

The OpenStack API VIP is:

```text
192.168.0.100/32
```

To find the current owner from Hermes:

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="
  ssh openstack@192.168.0.$ip \
    'ip -br addr show br-mgmt'
done
```

Only the active Keepalived owner should show the VIP in addition to its normal node management address.

During the validated cold boot, node2 showed:

```text
192.168.0.201/24
192.168.0.100/32
```

---

# 43. Inspecting Neutron

On a node:

```bash
sudo ip netns
```

shows Neutron network namespaces where applicable.

Open vSwitch is inspected through the container:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
```

External bridge ports:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

Expected current uplink:

```text
ext0
```

For the deeper packet walk, see:

```text
docs/05-neutron-packet-walk.md
```

---

# 44. Inspecting Compute

The logical control-plane view:

```bash
openstack compute service list
```

and:

```bash
openstack hypervisor list
```

should agree with the physical expectation:

```text
node1
node2
node3
```

All three nodes currently run compute services and appear as healthy hypervisors.

This connects:

```text
Nova
  ↓
nova-compute
  ↓
libvirt
  ↓
QEMU/KVM
```

to the actual cluster.

---

# 45. Health Script

The repository includes:

```text
scripts/lab-status.sh
```

Run from Hermes:

```bash
./scripts/lab-status.sh
```

It performs a compact health check across several layers:

```text
Hermes client environment
node reachability
core containers
Keystone authentication
Nova services
hypervisors
Neutron agents
```

This is more useful than checking only whether containers are running.

---

# 46. Validated Healthy State

A fully healthy run produced:

```text
OPENSTACK LAB STATUS
====================

Node reachability:
3/3

MariaDB:
3/3 healthy

ProxySQL:
3/3 healthy

Placement API:
3/3 healthy

Nova control:
12/12 healthy

Neutron control:
9/9 healthy

Keystone:
authentication works

Nova control services:
6/6 enabled and up

Nova compute services:
3/3 enabled and up

Hypervisors:
3/3 up

Neutron agents:
12/12 alive and UP

RESULT:
HEALTHY

PASS checks:
14
```

This is the baseline state we want before starting new experiments.

---

# 47. Cold-Boot Validation

The cluster was later powered on from a full shutdown and validated again.

No manual recovery was required before the health test.

The result remained:

```text
RESULT: HEALTHY
PASS checks: 14
```

That validated:

```text
node reachability
database services
OpenStack APIs
Nova control plane
Nova compute services
hypervisors
Neutron agents
```

This is important because a deployment is not truly useful if it works only immediately after installation.

It must also return to a healthy state after normal reboot/power-cycle operations.

---

# 48. Dual-NIC Persistence After Cold Boot

After the cold boot, all three nodes still had the expected management interfaces.

```text
node1
br-mgmt = 192.168.0.200/24

node2
br-mgmt = 192.168.0.201/24

node3
br-mgmt = 192.168.0.202/24
```

All three dedicated Neutron external interfaces were:

```text
ext0
UP
LOWER_UP
```

The USB adapter MAC addresses remained:

```text
node1 = 00:e0:4c:2c:16:78
node2 = 00:e0:4c:30:46:88
node3 = 00:e0:4c:55:7e:58
```

---

# 49. br-ex Persistence

After the same cold boot:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

returned on every node:

```text
ext0
phy-br-ex
```

This confirms:

```text
br-ex
  |
ext0
  |
physical LAN
```

survived the reboot.

The old single-NIC:

```text
veth-ovs
```

path was not restored.

---

# 50. Floating-IP Validation

A running test VM was used to validate the Neutron data plane.

The VM:

```text
ai-cirros-01
```

was:

```text
ACTIVE
```

with:

```text
Fixed IP:
10.20.0.188

Floating IP:
192.168.0.153
```

From Hermes:

```bash
ping -c 4 192.168.0.153
```

returned:

```text
4 packets transmitted
4 received
0% packet loss
```

This proves more than API health.

It proves that a real packet can traverse the deployed Neutron data plane to a workload after cold boot.

---

# 51. What the Floating-IP Test Proves

The successful ping validates a chain resembling:

```text
Hermes / LAN
     |
     v
192.168.0.153
Floating IP
     |
     v
ext0
     |
     v
br-ex
     |
     v
Neutron routing/NAT
     |
     v
VM fixed IP
10.20.0.188
```

Therefore the test validates several layers together:

```text
physical external NIC
OVS br-ex
Neutron external network
Floating IP
router/NAT path
VM networking
running workload
```

---

# 52. Deployment vs Recovery

A healthy deployed cloud still needs an operational recovery strategy.

Do not confuse:

```text
kolla-ansible deploy
```

with:

```text
routine recovery
```

A deployment command should not be the first reaction to every runtime problem.

The repository contains a dedicated runbook:

```text
docs/openstack-reboot-and-recovery-runbook.md
```

Use that document for:

```text
cold-boot recovery
MariaDB recovery
service recovery
RabbitMQ/Nova RPC last-resort recovery
```

---

# 53. Important RabbitMQ Lesson

The lab previously encountered a condition where Nova compute services remained down even though containers were running.

The investigation showed stale/broken RabbitMQ RPC state.

Normal restarts were not enough.

A last-resort recovery used:

```bash
kolla-ansible stop \
  -i kolla/inventory/multinode \
  --tags nova,neutron \
  --yes-i-really-really-mean-it
```

then:

```bash
kolla-ansible rabbitmq-reset-state \
  -i kolla/inventory/multinode
```

then:

```bash
kolla-ansible deploy \
  -i kolla/inventory/multinode \
  --tags nova,neutron
```

This procedure is documented in the recovery runbook.

Important rule:

```text
rabbitmq-reset-state
    =
LAST RESORT
```

It must not become an automatic startup action.

---

# 54. Important MariaDB Lesson

A previous cold boot also demonstrated that clustered database services may require deliberate recovery if the Galera/MariaDB cluster cannot safely select a primary state automatically.

The recovery command is:

```bash
kolla-ansible mariadb-recovery \
  -i kolla/inventory/multinode
```

This is a recovery tool.

It is not part of every normal boot.

The latest validated cold boot did not require it.

That distinction matters:

```text
normal boot
    should recover normally

recovery command
    is used when health checks prove recovery is needed
```

---

# 55. Do Not Diagnose by Container State Alone

A container can be:

```text
running
```

while the OpenStack service represented by that container is still unusable.

Examples:

```text
nova-compute container running
but
Nova reports compute service DOWN
```

or:

```text
Keystone container running
but
authentication fails
```

Therefore health must be checked at several layers:

```text
container layer
service layer
API layer
data plane
```

That is why:

```text
./scripts/lab-status.sh
```

and an actual Floating-IP test are both valuable.

---

# 56. Troubleshooting Hierarchy

A useful order is:

```text
1. Can Hermes reach the nodes?

2. Are the required containers healthy?

3. Can Keystone authenticate?

4. Are Nova services enabled/up?

5. Are hypervisors up?

6. Are Neutron agents alive?

7. Is br-ex connected to ext0?

8. Does a Floating IP actually pass traffic?
```

This moves from:

```text
basic infrastructure
```

toward:

```text
actual workload functionality
```

---

# 57. Do Not Randomly Restart the Cloud

When something fails, avoid:

```text
restart everything
redeploy everything
reset RabbitMQ immediately
run database recovery automatically
change several configurations at once
```

Instead:

```text
observe
   ↓
narrow the failure
   ↓
understand the affected layer
   ↓
apply the smallest justified recovery
   ↓
validate again
```

This is a better operational habit and a better learning habit.

---

# 58. VMware Mental Model

A rough VMware-oriented comparison can help:

```text
Kolla bootstrap
    prepare physical hosts

Kolla prechecks
    validate readiness

Kolla deploy
    deploy the cloud control/services layer

Nova compute
    workload execution service

Neutron / OVS
    virtual networking layer

Glance
    image/template repository concept

Placement
    resource inventory/allocation concept
```

This is not a one-to-one product mapping.

It is only a mental bridge from familiar VMware infrastructure concepts.

---

# 59. Control Plane vs Data Plane

Deployment creates both control-plane and data-plane components.

## Control plane

Examples:

```text
Keystone
Nova API
Neutron API
Placement
RabbitMQ
MariaDB
HAProxy
Keepalived
```

These decide and coordinate what should happen.

## Data plane

Examples:

```text
KVM/QEMU
VM interfaces
Open vSwitch
VXLAN
Neutron router namespaces
br-ex
ext0
```

These execute workloads and move packets.

Memory:

```text
control plane
    decides

data plane
    carries out
```

---

# 60. Current Validated Architecture

The deployed lab can be summarized as:

```text
                            HERMES
                              |
          +-------------------+-------------------+
          |                   |                   |
       Ansible           Kolla-Ansible        Terraform
          |                   |                   |
          +-------------------+-------------------+
                              |
                              v
                    OpenStack API VIP
                      192.168.0.100
                              |
                           HAProxy
                              |
             +----------------+----------------+
             |                |                |
             v                v                v
           node1            node2            node3
          .200              .201              .202
             |                |                |
       control/network  control/network  control/network
          compute           compute           compute
             |                |                |
             +----------------+----------------+
                              |
              +---------------+---------------+
              |                               |
          br-mgmt                           br-ex
              |                               |
         enp0s31f6                           ext0
              |                               |
       management/API/                Neutron external/
       VXLAN underlay                  provider traffic
```

---

# 61. Current Healthy Baseline

The baseline before beginning new learning experiments is:

```text
Nodes:
3/3 reachable

MariaDB:
3/3 healthy

ProxySQL:
3/3 healthy

Placement API:
3/3 healthy

Nova control:
12/12 healthy

Nova compute:
3/3 enabled and up

Hypervisors:
3/3 up

Neutron control:
9/9 healthy

Neutron agents:
12/12 alive and UP

Keystone:
authentication works

Dual-NIC networking:
persistent after cold boot

Floating IP:
validated with 0% packet loss

Overall:
HEALTHY
```

This is the state we want to preserve before intentionally changing the lab.

---

# 62. When to Freeze the Foundation

Once the foundation is healthy, do not keep redesigning it without a learning objective.

The OpenStack cluster now becomes the platform on which other skills can be practiced.

Examples:

```text
Terraform
    create OpenStack infrastructure

Ansible
    configure workloads

NGINX
    provide a simple application

Grafana / Prometheus
    provide monitoring

Hermes
    assist with IaC and operations under security guardrails
```

The goal changes from:

```text
keep rebuilding OpenStack
```

to:

```text
use OpenStack to learn infrastructure engineering
```

---

# 63. Main Kolla-Ansible Memory Hook

Remember:

```text
BOOTSTRAP
    prepare the Linux hosts

PRECHECKS
    validate readiness

DEPLOY
    build/configure OpenStack

POST-DEPLOY
    configure client access

VALIDATE
    prove APIs and services are healthy

OPERATE
    monitor, troubleshoot, recover carefully
```

That is the lifecycle to carry forward.

---

# 64. Final Lesson

The most important lesson from this deployment is not the syntax of one Kolla-Ansible command.

It is the relationship between the layers:

```text
Linux hosts
    ↓
Ansible
    ↓
Kolla-Ansible
    ↓
Docker containers
    ↓
OpenStack services
    ↓
Open vSwitch / KVM / Linux networking
    ↓
VM workloads
```

When the cloud is healthy, these layers work together.

When something fails, troubleshoot the specific layer instead of treating OpenStack as one giant black box.

That is the point of this homelab.

