# OpenStack Architecture 101

This page is a review guide for the core OpenStack services used in this homelab.

The goal is **not** to memorize every daemon.

The goal is to understand the few core responsibilities well enough that Kolla-Ansible container names and deployment logs stop looking random.

---

# 1. The Small Mental Model

Start with this:

```text
Keystone  = WHO
Nova      = VM
Placement = WHERE
Glance    = IMAGE
Neutron   = NETWORK

MariaDB   = REMEMBER
RabbitMQ  = TALK

libvirt + QEMU + KVM = RUN
```

If this picture is clear, the rest of OpenStack becomes much easier to learn.

---

# 2. OpenStack Is a Collection of Services

OpenStack is not one monolithic application.

It is a collection of cooperating services:

```text
                 User / Terraform / Horizon
                          |
                          v
                     Keystone
                  Authentication
                          |
            +-------------+-------------+
            |             |             |
            v             v             v
          Nova          Glance        Neutron
         Compute        Images        Network
            |
       Placement
            |
      nova-compute
            |
     libvirt/QEMU/KVM
            |
            VM
```

This is one of the biggest mental shifts coming from VMware.

A VMware environment often feels unified through vCenter.

OpenStack exposes more of the individual infrastructure services.

---

# 3. Keystone — WHO Are You?

Keystone is the OpenStack Identity service.

It deals with:

```text
users
projects
roles
authentication
tokens
service catalog
```

Conceptually:

```text
User
 |
 | credentials
 v
Keystone
 |
 | token
 v
OpenStack APIs
```

Keystone authenticates users and services.

It does **not** create virtual machines.

## VMware Mental Model

A rough analogy is:

```text
Keystone ~ vCenter SSO / identity and RBAC concepts
```

The analogy is useful, but not exact.

---

# 4. Nova — VM Compute Management

Nova is the OpenStack Compute service.

Nova manages the lifecycle of instances:

```text
create
start
stop
reboot
delete
resize
migrate
```

Nova itself is split into several components.

Important ones for this lab include:

```text
nova-api
nova-scheduler
nova-conductor
nova-compute
```

---

# 5. Nova API — The Front Door

When a user, Horizon, Terraform, or the OpenStack CLI requests a VM, the request reaches the Nova API.

Example request:

```text
Create VM:

Name: ubuntu01
vCPU: 2
RAM: 4 GB
Image: Ubuntu 24.04
Network: private-net
```

Conceptually:

```text
Terraform / CLI / Horizon
          |
          v
       Nova API
```

`nova-api` is the front door to the Nova compute service.

Terraform is not bypassing OpenStack.

Terraform is automating OpenStack through its APIs.

---

# 6. Placement — WHERE Are Resources Available?

Placement tracks resource inventories and allocations.

For example:

```text
node1
├── CPU
├── RAM
└── resource inventory

node2
├── CPU
├── RAM
└── resource inventory

node3
├── CPU
├── RAM
└── resource inventory
```

When Nova needs a host for a new VM, Placement helps identify which resource providers can satisfy the requested resources.

Important distinction:

```text
Placement = resource information / candidates

Scheduler = makes the placement decision
```

Placement does not simply say:

```text
Run the VM on node2.
```

Instead, it helps Nova understand what capacity is available.

---

# 7. Nova Scheduler — Choose the Compute Host

Nova Scheduler decides which compute host should run the instance.

Conceptually:

```text
Nova API
   |
   v
Placement
   |
   | possible hosts
   v
Nova Scheduler
   |
   | choose node2
   v
node2
```

A rough VMware analogy is placement logic associated with scheduling or DRS.

But Nova Scheduler should not be treated as a direct 1:1 equivalent of VMware DRS.

The important question Nova Scheduler answers is:

```text
Where should this new VM run?
```

---

# 8. Nova Compute — Host-Side Compute Service

Each compute host normally runs a `nova-compute` service.

In this lab:

```text
node1
└── nova-compute

node2
└── nova-compute

node3
└── nova-compute
```

If the scheduler selects node2, the work eventually reaches:

```text
nova-compute on node2
```

Nova Compute manages the instance on that host.

But:

> `nova-compute` is not itself the hypervisor.

---

# 9. libvirt, QEMU, and KVM

The virtualization stack is approximately:

```text
Nova Compute
     |
     v
  libvirt
     |
     v
   QEMU
     |
     v
    KVM
     |
     v
Linux kernel / CPU virtualization
```

## KVM

KVM is Linux kernel virtualization support.

In this lab it was verified with:

```bash
ls -l /dev/kvm
```

and:

```bash
lsmod | grep kvm
```

The nodes showed components such as:

```text
/dev/kvm
kvm_intel
kvm
```

That tells us the physical hosts already support hardware-assisted virtualization.

## QEMU

QEMU provides the VM process and device emulation.

## libvirt

libvirt provides a management API used by software such as Nova to control the virtualization layer.

The useful mental model is:

```text
Nova asks libvirt

libvirt manages QEMU/KVM

QEMU/KVM runs the VM
```

---

# 10. VMware-Oriented Compute View

A simplified comparison:

| OpenStack/Linux | VMware-ish Mental Model |
|---|---|
| Nova | VM lifecycle/orchestration |
| Nova Scheduler | VM placement logic |
| nova-compute | Host-side compute service |
| libvirt | Virtualization management API |
| QEMU/KVM | Hypervisor/runtime layer |
| Instance | Virtual Machine |

These are learning analogies.

They are not exact product equivalents.

---

# 11. Glance — IMAGE

Glance is the OpenStack Image service.

A typical image might be:

```text
ubuntu-24.04.qcow2
```

Glance stores image metadata and provides images used when launching instances.

A useful VMware mental model is:

```text
Glance image
    ~
VM template / image repository concept
```

Conceptually:

```text
Nova
 |
 | need Ubuntu image
 v
Glance
 |
 v
Compute host
 |
 v
VM
```

Glance is **not** the running VM disk service itself.

Later, Ceph can be used as a backend for Glance image data.

For now remember:

```text
Glance = IMAGE
```

---

# 12. Neutron — NETWORK

Neutron is the OpenStack Networking service.

It manages concepts such as:

```text
networks
subnets
ports
routers
DHCP
security groups
floating IPs
external networks
```

A useful VMware-oriented mapping is:

| OpenStack | VMware-ish Mental Model |
|---|---|
| Neutron Network | Port Group / logical network |
| Neutron Port | VM vNIC connection |
| Subnet | IP subnet configuration |
| Neutron Router | Virtual L3 router |
| Security Group | Distributed firewall-like rule set |
| Floating IP | External NAT address |
| Open vSwitch | Software switching layer |

Again, these are learning analogies rather than exact 1:1 mappings.

---

# 13. Private Network Example

Imagine we create:

```text
Network: private-net

Subnet:
10.10.10.0/24
```

Two VMs might receive:

```text
VM1 = 10.10.10.25
VM2 = 10.10.10.26
```

Conceptually:

```text
VM1                  VM2
10.10.10.25          10.10.10.26
 |                      |
 +------ private-net ----+
           |
      10.10.10.0/24
```

This gives internal connectivity.

But external access requires routing.

---

# 14. Neutron Router

A Neutron router connects private and external networks.

```text
               Neutron Router
                 /         \
                /           \
       private-net        external-net
       10.10.10.0/24      192.168.0.0/24
```

Traffic can then follow a path such as:

```text
VM
 |
private-net
 |
Neutron Router
 |
external-net
 |
Home LAN / router
 |
Internet
```

This router is virtual.

It is part of the OpenStack networking environment.

---

# 15. Floating IP

A VM may have an internal address:

```text
10.10.10.25
```

That address is not necessarily directly reachable from the home LAN.

A Floating IP can provide an external NAT address.

For example:

```text
Floating IP:
192.168.0.160

Internal VM IP:
10.10.10.25
```

Conceptually:

```text
Laptop
 |
 | ssh 192.168.0.160
 v
Neutron
 |
 | NAT
 v
10.10.10.25
 |
VM
```

So the VM can keep its private address while still being reachable through an external address.

---

# 16. Why We Built veth-ovs

Our current single-NIC lab networking looks like this:

```text
                     HOME LAN
                        |
                   enp0s31f6
                        |
                     br-mgmt
                    /       \
             management     veth-host
                               ||
                               ||
                            veth-ovs
```

The management IPs live on:

```text
br-mgmt
```

For example:

```text
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
```

The free side:

```text
veth-ovs
```

is intended to become the external-facing Neutron interface.

Later:

```text
veth-ovs
   |
   v
 br-ex
   |
   v
Neutron
```

So the Linux bridge and veth work was preparing a path between:

```text
OpenStack virtual networking
        |
        v
physical home LAN
```

It was not random Linux configuration.

---

# 17. Open vSwitch

Open vSwitch is usually abbreviated:

```text
OVS
```

It is a software switching platform.

Later we will see bridge names such as:

```text
br-int
br-ex
```

For now, use this simplified mental model:

```text
br-int = OpenStack internal integration switching

br-ex = bridge toward the external physical network
```

A simplified traffic path:

```text
VM
 |
virtual interface
 |
br-int
 |
Neutron
 |
br-ex
 |
veth-ovs
 |
physical network
```

The real networking path contains more detail.

We will inspect the actual bridges after Kolla creates them.

---

# 18. Common Neutron Containers

Kolla-Ansible may later deploy containers with names such as:

```text
neutron_server
neutron_openvswitch_agent
neutron_l3_agent
neutron_dhcp_agent
neutron_metadata_agent
```

Human translation:

```text
neutron-server
    Neutron API / central service

neutron-openvswitch-agent
    Manages OVS networking on hosts

neutron-l3-agent
    Routing and NAT

neutron-dhcp-agent
    Provides IP configuration to instances

neutron-metadata-agent
    Helps instances access cloud metadata
```

Do not memorize every container name yet.

The purpose of this section is simply to make the names recognizable during deployment.

---

# 19. MariaDB — REMEMBER

OpenStack services need persistent databases.

MariaDB stores service state such as configuration and resource records.

Conceptually:

```text
Nova     ─┐
Neutron  ─┼──> Service Databases
Keystone ─┤          |
Glance   ─┘       MariaDB
```

The memory hook is:

```text
MariaDB = REMEMBER
```

It stores information that OpenStack services need to persist.

---

# 20. RabbitMQ — TALK

OpenStack services also need to communicate internally.

RabbitMQ provides a messaging system used by services for asynchronous communication and RPC.

A simplified example:

```text
Nova Scheduler
      |
      v
   RabbitMQ
      |
      v
nova-compute
```

The memory hook is:

```text
RabbitMQ = TALK
```

It helps OpenStack services communicate with each other.

---

# 21. End-to-End: Create One VM

Imagine we eventually run:

```bash
openstack server create \
  --image ubuntu-24.04 \
  --flavor m1.small \
  --network private-net \
  ubuntu01
```

What happens?

## Step 1 — Authentication

Keystone checks:

```text
Who are you?
Are you allowed to do this?
```

Authentication succeeds and the OpenStack APIs can trust the request.

---

## Step 2 — Nova API

Nova receives:

```text
Create a new VM called ubuntu01
```

with information such as:

```text
image
flavor
network
project
```

---

## Step 3 — Placement

Nova needs to know:

```text
Which compute hosts have enough resources?
```

Placement provides resource information.

For example:

```text
node1 → possible
node2 → possible
node3 → insufficient resources
```

---

## Step 4 — Nova Scheduler

Nova Scheduler chooses a host.

For example:

```text
node2
```

---

## Step 5 — Glance

Nova needs the selected operating system image:

```text
Ubuntu 24.04
```

Glance provides the image information/data needed to boot the instance.

---

## Step 6 — Neutron

The VM also needs networking.

Neutron creates things such as:

```text
virtual network port
MAC address
private IP
network connection
security group association
```

---

## Step 7 — Internal Messaging

Nova services coordinate the work.

RabbitMQ is used as part of the internal messaging infrastructure.

Conceptually:

```text
Nova control services
       |
       v
    RabbitMQ
       |
       v
nova-compute node2
```

---

## Step 8 — nova-compute

The `nova-compute` service on node2 receives the work.

It prepares the VM on that compute host.

---

## Step 9 — libvirt / QEMU / KVM

Nova Compute communicates with libvirt.

Then:

```text
libvirt
   |
   v
QEMU
   |
   v
KVM
```

actually runs the virtual machine.

---

## Step 10 — Network Attachment

Neutron connects the VM's virtual interface to the OpenStack virtual network.

The VM might receive:

```text
10.10.10.25
```

---

## Step 11 — Floating IP

If we assign:

```text
192.168.0.160
```

as a Floating IP, Neutron can provide a NAT path:

```text
192.168.0.160
      |
      v
10.10.10.25
```

Now the VM can be reachable from the home LAN.

---

# 22. The Full Mental Picture

This is the main diagram to review:

```text
                       USER
                        |
            CLI / Horizon / Terraform
                        |
                        v
                   Keystone
                  WHO ARE YOU?
                        |
                        v
                    Nova API
                  I WANT A VM
                        |
            +-----------+-----------+
            |           |           |
            v           v           v
       Placement     Glance      Neutron
       WHERE?        IMAGE?      NETWORK?
            \           |           /
             \          |          /
              +---------+---------+
                        |
                 Nova Scheduler
                        |
                  choose node2
                        |
                        v
                 nova-compute
                    node2
                        |
                        v
                    libvirt
                        |
                        v
                   QEMU + KVM
                        |
                        v
                   +---------+
                   | ubuntu01|
                   +---------+
                        |
                   virtual NIC
                        |
                     Neutron
                        |
                  private-net
                   10.10.10.x
                        |
                 Neutron Router
                        |
                     br-ex
                        |
                    veth-ovs
                        ||
                    veth-host
                        |
                     br-mgmt
                        |
                   enp0s31f6
                        |
                    HOME LAN
```

That is the basic OpenStack cloud we are building.

---

# 23. Where Kolla Fits

Kolla does not replace these services.

Kolla provides container images containing OpenStack services.

Conceptually:

```text
OpenStack Services
        |
        v
Kolla Container Images
        |
        v
Kolla-Ansible
        |
        v
Deploy and configure containers
```

Examples of containers we may eventually see:

```text
keystone
nova_api
nova_scheduler
nova_compute
placement_api
glance_api
neutron_server
rabbitmq
mariadb
haproxy
keepalived
```

Before this architecture lesson, those names looked like random containers.

Now we can begin mapping them back to their purpose.

---

# 24. Kolla vs Kolla-Ansible

These names are related but different.

## Kolla

Think:

```text
Kolla = container images
```

Examples:

```text
Nova container image
Neutron container image
Keystone container image
Glance container image
```

## Kolla-Ansible

Think:

```text
Kolla-Ansible = deployment automation
```

It uses Ansible to determine:

```text
which nodes run which services
how services are configured
how containers are started
how networking is configured
how HA is configured
```

A useful comparison:

```text
Kubespray
   |
   +--> Ansible deploys Kubernetes

Kolla-Ansible
   |
   +--> Ansible deploys OpenStack
```

They are not the same project.

They simply have a similar automation role.

---

# 25. Why One Node Can Be Control AND Compute

Our lab is using a converged three-node architecture.

Our Kolla inventory contains nodes in multiple groups.

For example:

```ini
[control]
node1
node2
node3

[network]
node1
node2
node3

[compute]
node1
node2
node3
```

That is intentional.

It means:

```text
node1
├── control services
├── network services
└── compute workloads

node2
├── control services
├── network services
└── compute workloads

node3
├── control services
├── network services
└── compute workloads
```

A server can therefore run both:

```text
OpenStack control-plane containers
```

and:

```text
virtual machines
```

This is useful for a small homelab because we only have three physical nodes.

---

# 26. Control Plane vs Compute Plane

Another useful mental picture:

```text
CONTROL PLANE
-------------
Keystone
Nova API
Nova Scheduler
Placement
Glance
Neutron API
MariaDB
RabbitMQ
HAProxy
Keepalived

        |
        | controls
        v

COMPUTE PLANE
-------------
nova-compute
libvirt
QEMU
KVM
VMs
```

Our three-node lab mixes both planes onto the same physical servers.

In a larger environment, they may be separated.

---

# 27. HAProxy and Keepalived

These two components become important because we have three control nodes.

Our OpenStack API VIP is planned as:

```text
192.168.0.100
```

Instead of users connecting directly to:

```text
node1
node2
node3
```

they can use:

```text
192.168.0.100
```

Conceptually:

```text
             192.168.0.100
                   |
                   v
              Keepalived
                   |
                   v
                HAProxy
              /    |    \
             /     |     \
          node1  node2  node3
```

## Keepalived

Memory hook:

```text
Keepalived = VIP
```

It provides high availability for the virtual IP.

## HAProxy

Memory hook:

```text
HAProxy = LOAD BALANCE
```

It sends API traffic toward available OpenStack services.

So eventually:

```text
OpenStack CLI
      |
      v
192.168.0.100
      |
      v
HAProxy
      |
      +--> node1 API
      +--> node2 API
      +--> node3 API
```

---

# 28. Where Cinder Fits

We have not deployed Cinder yet.

Cinder is the OpenStack Block Storage service.

Think:

```text
Cinder = attachable VM disks
```

For example:

```text
VM
 |
 +-- root disk
 |
 +-- Cinder volume: 100 GB
```

A VMware-oriented mental model might be:

```text
Cinder volume
    ~
virtual disk backed by shared/block storage
```

Again, not an exact 1:1 comparison.

---

# 29. Where Ceph Fits

Ceph is not OpenStack itself.

Ceph is a distributed storage platform.

It can provide storage backends for OpenStack.

Eventually our design may look like:

```text
                 OpenStack
                     |
          +----------+----------+
          |          |          |
          v          v          v
        Glance     Cinder      Nova
          \          |          /
           \         |         /
            +--------+--------+
                     |
                     v
                   Ceph
```

Possible uses:

```text
Glance
  → image storage

Cinder
  → block volumes

Nova
  → VM disk storage
```

Our three nodes each have an additional disk:

```text
node1 /dev/sda
node2 /dev/sda
node3 /dev/sda
```

Those disks still contain old Ceph BlueStore metadata.

We are intentionally **not wiping them yet**.

Ceph comes later after the basic OpenStack architecture is understood.

---

# 30. Why We Are Delaying Ceph

There are already many moving parts:

```text
Keystone
Nova
Placement
Glance
Neutron
RabbitMQ
MariaDB
HAProxy
Keepalived
KVM
OVS
```

Adding Ceph immediately would introduce even more concepts:

```text
MON
MGR
OSD
CRUSH
RBD
pools
PGs
replication
```

So our learning order is:

```text
OpenStack architecture
        |
        v
Deploy basic OpenStack
        |
        v
Create first VM
        |
        v
Understand Neutron
        |
        v
Understand Cinder
        |
        v
Ceph
```

That keeps each layer understandable.

---

# 31. VMware-Oriented Review Table

| OpenStack | Purpose | VMware-ish Mental Model |
|---|---|---|
| Keystone | Identity/authentication | vCenter SSO / RBAC concepts |
| Nova | Compute lifecycle | VM management/orchestration |
| Placement | Resource inventory/allocation | Resource availability information |
| Nova Scheduler | Select compute host | Placement/scheduling logic |
| nova-compute | Host-side compute service | Host-side VM management |
| Glance | Image service | Template/image repository |
| Neutron | Networking | Virtual networking platform |
| Cinder | Block storage | VM disk/block storage service |
| Horizon | Web UI | Management UI |
| MariaDB | Persistent service state | Backend database |
| RabbitMQ | Internal messaging | Message bus |
| HAProxy | API load balancing | Load balancer |
| Keepalived | Virtual IP HA | VIP failover |
| libvirt | Virtualization API | Hypervisor management layer |
| QEMU/KVM | VM runtime | Hypervisor/runtime layer |

These comparisons are learning aids rather than exact equivalents.

---

# 32. Review Cheat Sheet

If everything else disappears from memory, remember this:

```text
Keystone  = WHO
Nova      = VM
Placement = WHERE
Glance    = IMAGE
Neutron   = NETWORK

MariaDB   = REMEMBER
RabbitMQ  = TALK

HAProxy   = LOAD BALANCE
Keepalived = VIP

KVM       = RUN
Cinder    = BLOCK STORAGE
Ceph      = DISTRIBUTED STORAGE
```

And the short VM creation story:

```text
WHO?
 |
 v
Keystone

I WANT A VM
 |
 v
Nova

WHERE CAN IT RUN?
 |
 v
Placement

CHOOSE A HOST
 |
 v
Nova Scheduler

WHICH IMAGE?
 |
 v
Glance

WHICH NETWORK?
 |
 v
Neutron

RUN IT
 |
 v
nova-compute
 |
libvirt
 |
QEMU/KVM
 |
VM
```

---

# 33. The 30-Second OpenStack Explanation

If someone asks:

> What happens when OpenStack creates a VM?

A good short answer is:

```text
Keystone authenticates the user.

Nova receives the VM request.

Placement reports available compute resources.

Nova Scheduler chooses a compute node.

Glance provides the VM image.

Neutron provides networking.

RabbitMQ helps the services communicate.

nova-compute asks libvirt/QEMU/KVM to run the VM.

MariaDB stores persistent OpenStack state.
```

If that explanation makes sense, the architecture is already starting to stick.

---

# 34. What Comes Next

The next architecture lesson is:

# Neutron Packet Walk

Instead of learning more service names, we will follow an actual packet.

Example:

```text
ubuntu01
   |
   | ping 8.8.8.8
   v
VM NIC
   |
   v
OpenStack internal network
   |
   v
Neutron Router
   |
   v
br-ex
   |
   v
veth-ovs
   |
   v
veth-host
   |
   v
br-mgmt
   |
   v
enp0s31f6
   |
   v
Home Router
   |
   v
Internet
```

Then we will reverse the direction:

```text
Laptop
   |
   | ssh 192.168.0.160
   v
Floating IP
   |
   v
Neutron
   |
   v
NAT
   |
   v
10.10.10.25
   |
   v
ubuntu01
```

That lesson will connect:

```text
Neutron
OVS
br-int
br-ex
veth pairs
routers
NAT
Floating IPs
```

to the Linux networking work already completed in this lab.

---

# Final Memory Hook

```text
WHO      = Keystone
VM       = Nova
WHERE    = Placement
IMAGE    = Glance
NETWORK  = Neutron
REMEMBER = MariaDB
TALK     = RabbitMQ
RUN      = KVM
```

Do not try to memorize everything at once.

The important goal is to recognize each service when we see it during the real Kolla-Ansible deployment.
