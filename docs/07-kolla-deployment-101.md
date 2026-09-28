# Kolla-Ansible Deployment 101

This document explains what happens when we move from prepared Linux hosts to an actual running OpenStack cloud.

The important workflow is:

```text
bootstrap-servers
        ↓
prechecks
        ↓
deploy
        ↓
post-deploy
```

These commands are not interchangeable.

Each stage has a different purpose.

---

# 1. Where We Are Before Deploy

At this point the three physical OpenStack nodes are prepared.

```text
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
```

All three have:

```text
Ubuntu
Docker
SSH
passwordless sudo
KVM
/dev/kvm
OpenStack networking preparation
```

The Kolla deployment machine is:

```text
hermes
```

Hermes is not an OpenStack compute/controller node.

It is the machine running:

```text
Ansible
Kolla-Ansible
Terraform later
OpenStack CLI later
```

---

# 2. Current Kolla Configuration

Important `/etc/kolla/globals.yml` settings:

```yaml
kolla_base_distro: "ubuntu"

kolla_container_engine: "docker"

kolla_internal_vip_address: "192.168.0.100"

network_interface: "br-mgmt"

neutron_external_interface: "veth-ovs"

nova_compute_virt_type: "kvm"
```

Meaning:

```text
Ubuntu
    Kolla container image base

Docker
    container runtime

192.168.0.100
    OpenStack internal API VIP

br-mgmt
    management/API interface

veth-ovs
    Neutron external interface

KVM
    VM hypervisor
```

---

# 3. Deployment Workflow

Our deployment flow is:

```text
Linux installation
      ↓
SSH setup
      ↓
Ansible connectivity
      ↓
network preparation
      ↓
Kolla inventory
      ↓
globals.yml
      ↓
passwords.yml
      ↓
install-deps
      ↓
bootstrap-servers
      ↓
prechecks
      ↓
DEPLOY
```

The first stages prepare the environment.

`deploy` creates the cloud.

---

# 4. What bootstrap-servers Did

We ran:

```bash
kolla-ansible bootstrap-servers \
  -i kolla/inventory/multinode
```

This prepared the Linux hosts for Kolla.

Among other host-level preparation, Docker was installed and started.

We verified:

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

Important:

```text
bootstrap-servers
```

did NOT deploy OpenStack services.

Think:

```text
bootstrap
    =
prepare operating system
```

---

# 5. What prechecks Did

We then ran:

```bash
kolla-ansible prechecks \
  -i kolla/inventory/multinode \
  --use-test-images
```

The final result was:

```text
localhost  failed=0
node1      failed=0
node2      failed=0
node3      failed=0
```

So Kolla believes the infrastructure is ready for deployment.

Think:

```text
prechecks
    =
"Are the hosts ready?"
```

---

# 6. Why --use-test-images Was Needed

The current image configuration uses:

```text
quay.io/openstack.kolla
```

Kolla treats these as test/evaluation images and requires an explicit acknowledgement during prechecks.

Therefore we used:

```bash
--use-test-images
```

This does NOT mean:

```text
ignore all validation
```

It means:

```text
I acknowledge that I am using the test-image namespace.
```

The rest of the prechecks still run normally.

For this homelab and learning environment this is acceptable.

A production environment would normally use controlled, validated images and often its own registry.

---

# 7. What Deploy Means

Now we reach:

```bash
kolla-ansible deploy \
  -i kolla/inventory/multinode
```

This is fundamentally different from bootstrap.

Before:

```text
Linux hosts
+
Docker
+
networking
```

After a successful deployment:

```text
OpenStack cloud
```

---

# 8. Simple Mental Model

```text
bootstrap-servers
        =
prepare Linux

prechecks
        =
validate Linux

deploy
        =
build OpenStack
```

---

# 9. What Kolla-Ansible Does

Remember the distinction:

```text
Kolla
    =
container images

Kolla-Ansible
    =
Ansible automation that deploys/configures
those containers
```

Kolla-Ansible runs from:

```text
Hermes
```

and connects using SSH/Ansible to:

```text
node1
node2
node3
```

---

# 10. Deployment Architecture

Conceptually:

```text
                 HERMES

            Kolla-Ansible
                  |
                  |
               Ansible
                  |
          +-------+-------+
          |       |       |
          v       v       v

       node1    node2    node3
          |       |       |
        Docker  Docker  Docker
          |       |       |
          +-------+-------+
                  |
                  v

             OpenStack
```

---

# 11. Core Services That Will Appear

A normal core OpenStack deployment includes services such as:

```text
Keystone
Glance
Nova
Placement
Neutron
Heat
Horizon
```

along with infrastructure supporting them.

---

# 12. OpenStack Memory Model

```text
Keystone
    WHO?

Nova
    VM?

Placement
    WHERE?

Glance
    IMAGE?

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

During deploy these names stop being diagrams and become real running services.

---

# 13. Supporting Infrastructure

Before most OpenStack APIs can function, Kolla must build supporting infrastructure.

Examples include:

```text
MariaDB
RabbitMQ
Memcached
HAProxy
Keepalived
```

These are not optional background trivia.

The OpenStack services depend heavily on them.

---

# 14. MariaDB

OpenStack services need persistent state.

For example:

```text
Nova
Neutron
Keystone
Glance
```

need databases.

Conceptually:

```text
OpenStack service
       |
       v
   MariaDB
```

Memory:

```text
MariaDB = REMEMBER
```

---

# 15. RabbitMQ

OpenStack is made of distributed services.

They need to communicate.

RabbitMQ provides messaging between many of those components.

Conceptually:

```text
Nova API
   |
RabbitMQ
   |
Nova Compute
```

Important:

```text
VM network packets do NOT go through RabbitMQ.
```

RabbitMQ carries control-plane messaging.

---

# 16. HAProxy

OpenStack APIs run across multiple controller nodes.

Instead of users connecting individually to:

```text
node1
node2
node3
```

we use:

```text
192.168.0.100
```

HAProxy distributes API connections to backend services.

Conceptually:

```text
Client
   |
192.168.0.100
   |
HAProxy
   |
+-- node1
+-- node2
+-- node3
```

---

# 17. Keepalived

Keepalived provides the Virtual IP:

```text
192.168.0.100
```

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

One node owns the VIP at a time.

If that node fails, another can take ownership.

---

# 18. Keystone

Keystone handles Identity.

Memory:

```text
Keystone = WHO
```

It manages concepts such as:

```text
users
projects
roles
authentication
tokens
service catalog
```

Most OpenStack requests eventually involve Keystone authentication.

---

# 19. Glance

Glance is the OpenStack Image service.

Memory:

```text
Glance = IMAGE
```

Example:

```text
Ubuntu cloud image
        |
      Glance
        |
      Nova
        |
        VM
```

Glance is roughly comparable to a VM template/image repository concept.

---

# 20. Placement

Placement tracks compute resource inventory and allocations.

Examples:

```text
CPU
RAM
resource providers
allocations
```

Memory:

```text
Placement = WHERE resources exist
```

Placement supplies resource information.

Nova Scheduler uses that information when choosing a compute host.

---

# 21. Nova

Nova is the Compute service.

Memory:

```text
Nova = VM
```

It manages VM lifecycle operations such as:

```text
create
start
stop
delete
resize
migrate
```

The VM execution chain is roughly:

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

---

# 22. Neutron

Neutron provides networking.

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

---

# 23. Open vSwitch

With the current lab architecture, Open vSwitch provides software switching.

Important bridges include:

```text
br-int
br-ex
```

Memory:

```text
br-int
    internal OpenStack switching

br-ex
    external/provider network
```

---

# 24. Heat

Heat provides orchestration.

It can create multiple OpenStack resources from templates.

Conceptually:

```text
template
   |
 Heat
   |
+-- networks
+-- routers
+-- VMs
+-- volumes
```

It is OpenStack-native infrastructure orchestration.

Later we will also use Terraform.

---

# 25. Horizon

Horizon is the OpenStack web dashboard.

It gives us a GUI for things such as:

```text
instances
images
networks
routers
volumes
projects
users
```

But the GUI is not the architecture.

Horizon calls OpenStack APIs.

---

# 26. Approximate Deployment Sequence

Do not treat this as a strict task-by-task guarantee.

Conceptually the deployment progresses like:

```text
1. gather host information

2. generate configuration

3. prepare container configuration directories

4. pull required container images

5. configure infrastructure services

6. initialize databases

7. start messaging services

8. start HA/load-balancing services

9. deploy Keystone

10. deploy image services

11. deploy compute services

12. deploy networking services

13. deploy Horizon

14. perform service registration/configuration
```

Ansible handles dependencies between these stages.

---

# 27. Service Registration

OpenStack services need to know about each other.

Keystone maintains a Service Catalog.

Conceptually:

```text
Keystone Service Catalog

Nova
    compute API URL

Neutron
    networking API URL

Glance
    image API URL

Heat
    orchestration API URL
```

Clients can authenticate and discover service endpoints.

---

# 28. Databases

Each major service generally has its own logical database.

Conceptually:

```text
MariaDB

├── keystone database
├── nova database
├── neutron database
├── glance database
└── placement database
```

They share the database infrastructure but keep application data logically separated.

---

# 29. Docker Containers

OpenStack processes will run inside Docker containers.

Examples may include containers resembling:

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

Exact container names depend on the Kolla release and configuration.

---

# 30. Before and After Docker Check

Before deploy:

```bash
docker ps
```

may show few or no Kolla containers.

After deploy:

```bash
docker ps
```

should show many OpenStack-related containers.

This gives a simple visual demonstration of what `deploy` changed.

---

# 31. Checking All Nodes

From Hermes:

```bash
ansible baremetal \
  -i kolla/inventory/multinode \
  -b \
  -m shell \
  -a 'echo "===== $(hostname) ====="; docker ps'
```

This displays running Docker containers on all OpenStack nodes.

---

# 32. Important Ansible / Docker Template Lesson

Docker supports Go-template formatting such as:

```text
{{.Names}}
```

Ansible also uses:

```text
{{ ... }}
```

for Jinja templates.

Therefore a command such as:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

inside an Ansible ad-hoc shell command can fail because Ansible tries to interpret:

```text
{{.Names}}
```

as Jinja.

The error may look like:

```text
Syntax error in template: unexpected '.'
```

This happens before the remote shell command executes.

For simple inspection, use:

```bash
docker ps
```

instead.

---

# 33. Deploy Command

The actual deployment command is:

```bash
kolla-ansible deploy \
  -i kolla/inventory/multinode
```

Run this from:

```text
Hermes
```

inside the Kolla Python virtual environment.

---

# 34. What Ansible Output Means

During deployment you will see:

```text
ok
changed
skipping
FAILED
```

Meaning:

```text
ok
    state already correct

changed
    Ansible changed something

skipping
    task does not apply

FAILED
    task could not complete
```

---

# 35. Many Skipped Tasks Are Normal

Kolla supports many OpenStack services.

Our lab does not enable everything.

Therefore output containing:

```text
skipping
skipping
skipping
```

is completely normal.

It does not mean the deployment is broken.

---

# 36. Image Pulling

Container images have to be downloaded.

This may take time because there are multiple images and three hosts.

Conceptually:

```text
quay.io
   |
   +--> node1
   |
   +--> node2
   |
   +--> node3
```

Each host needs images for the containers it will run.

---

# 37. What to Do If Deployment Fails

Do not randomly restart containers.

Do not immediately change several settings.

Find the FIRST meaningful failure.

Look for:

```text
TASK [...]
```

followed by:

```text
fatal: [...]
```

and then inspect:

```text
PLAY RECAP
```

The first failure often explains later failures.

---

# 38. Good Troubleshooting Process

Use:

```text
1. identify failed task

2. identify failed host

3. read exact error

4. identify which component is involved

5. inspect that component

6. correct one thing

7. rerun idempotent automation
```

Avoid:

```text
random package installation

random config changes

random container restarts
```

---

# 39. Desired State

Kolla-Ansible is declarative/idempotent in spirit.

We describe the desired configuration.

Ansible compares:

```text
desired state
```

against:

```text
actual state
```

and makes required changes.

This is an important Infrastructure-as-Code principle.

---

# 40. Why Rerunning Can Be Safe

Most Ansible tasks are designed to be idempotent.

Example:

First run:

```text
Docker package missing
    ↓
install Docker
    ↓
changed
```

Second run:

```text
Docker already installed
    ↓
nothing required
    ↓
ok
```

That is one of the main benefits of configuration automation.

---

# 41. But Rerunning Is Not Troubleshooting

Even though rerunning is often safe:

```text
rerun
```

should not replace:

```text
understand error
```

For this project we intentionally inspect failures before retrying them.

The goal is learning, not simply reaching a green screen.

---

# 42. VMware Mental Model

Very approximately:

```text
bootstrap
    prepare hosts

prechecks
    validate host readiness

deploy
    build the cloud control plane and compute/network services
```

This is not exactly equivalent to a VMware installer.

But the useful mental sequence is:

```text
prepare infrastructure
        ↓
validate infrastructure
        ↓
deploy management/control plane
        ↓
start workloads
```

---

# 43. After Successful Deployment

Do not immediately create VMs.

First inspect the cloud.

We want to see:

```text
containers
services
VIP
databases
RabbitMQ
OpenStack APIs
OVS
Neutron namespaces
```

---

# 44. First Post-Deploy Investigation

We will inspect:

```bash
docker ps
```

on all three nodes.

Then:

```text
Which container belongs to which service?
```

For example:

```text
MariaDB
RabbitMQ
HAProxy
Keepalived
Keystone
Glance
Nova
Neutron
Horizon
```

---

# 45. Inspect the VIP

Our internal API VIP is:

```text
192.168.0.100
```

After deployment we should investigate:

```text
Which node currently owns it?

Which interface is it attached to?

What happens if that node fails?
```

Useful commands later include:

```bash
ip addr
```

and inspecting Keepalived containers/configuration.

---

# 46. Inspect Neutron

After deployment, networking theory becomes real.

We will inspect:

```bash
ovs-vsctl show
```

and eventually:

```bash
ip netns
```

Then compare the output against our Neutron architecture notes.

---

# 47. Inspect Compute

We will inspect:

```text
nova-compute
libvirt
KVM
```

and map:

```text
Nova
  ↓
nova-compute
  ↓
libvirt
  ↓
QEMU/KVM
```

to actual running containers/processes.

---

# 48. Inspect MariaDB

We will verify that the database cluster is healthy.

This makes:

```text
MariaDB = REMEMBER
```

a real operational concept rather than just a mnemonic.

---

# 49. Inspect RabbitMQ

We will verify that RabbitMQ is running across the control nodes.

This will make:

```text
RabbitMQ = TALK
```

visible in the real environment.

---

# 50. Inspect HAProxy

We will inspect how requests arriving at:

```text
192.168.0.100
```

are forwarded to OpenStack API services.

This turns:

```text
HAProxy = LOAD BALANCE
```

into something observable.

---

# 51. Our Learning Philosophy

The objective is NOT:

```text
copy command
wait
OpenStack works
```

The objective is:

```text
command
   ↓
understand what changed
   ↓
inspect the result
   ↓
connect it to architecture
```

That is how the lab becomes transferable professional knowledge.

---

# 52. Final Deployment Mental Model

```text
                    HERMES
                      |
                 Kolla-Ansible
                      |
                    Ansible
                      |
        +-------------+-------------+
        |             |             |
        v             v             v
      NODE1         NODE2         NODE3
        |             |             |
      Docker        Docker        Docker
        |             |             |
        +-------------+-------------+
                      |
            OPENSTACK SERVICES
                      |
        +-------------+-------------+
        |             |             |
     Keystone       Nova         Neutron
        |             |             |
      Glance       KVM/VMs      OVS/VXLAN
        |
      Images

Infrastructure underneath:

MariaDB
RabbitMQ
HAProxy
Keepalived
```

---

# 53. The Main Memory Hook

```text
BOOTSTRAP
    prepare hosts

PRECHECKS
    validate hosts

DEPLOY
    build OpenStack

POST-DEPLOY
    prepare client/admin access
```

That is the Kolla-Ansible lifecycle to remember.

---

# 54. Actual Post-Deployment Observations

After `kolla-ansible deploy` completed successfully, the lab was inspected rather than immediately creating workloads.

This allowed the theoretical architecture to be compared with the actual deployed environment.

## Container Counts

Before deployment:

```text
node1 = 0 containers
node2 = 0 containers
node3 = 0 containers
