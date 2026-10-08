OpenStack Architecture 101
This chapter is a review guide for the core OpenStack services used in this homelab.
The goal is not to memorize every daemon or container.
The goal is to understand the main responsibilities well enough that:
Kolla-Ansible container names
OpenStack CLI output
Terraform resources
Neutron networking
troubleshooting logs
stop looking like unrelated pieces.
This chapter describes the current deployed lab.
Historical single-NIC networking is preserved separately in:
docs/03-openstack-single-nic-networking.md
The current dual-NIC implementation is documented in:
docs/17-openstack-dual-nic-networking.md
1. The Small Mental Model
Start with this:
Keystone   = WHO
Nova       = VM
Placement  = WHERE
Glance     = IMAGE
Neutron    = NETWORK

MariaDB    = REMEMBER
RabbitMQ   = TALK

HAProxy    = LOAD BALANCE
Keepalived = VIP
ProxySQL   = DATABASE PROXY

libvirt + QEMU + KVM = RUN
If this picture is clear, the rest of OpenStack becomes much easier to reason about.
2. OpenStack Is a Collection of Services
OpenStack is not one monolithic application.
It is a collection of cooperating services:
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
           v
           VM
Coming from VMware, this is one of the biggest mental shifts.
A VMware environment often feels unified through vCenter.
OpenStack exposes more of the individual infrastructure services.
3. Current Homelab Layout
The current lab contains:
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
All three nodes are converged:
control
network
compute
Hermes is the administration and automation machine.
Hermes
  |
  +-- Ansible
  +-- Kolla-Ansible
  +-- OpenStack CLI
  +-- Terraform
  +-- Git
The OpenStack internal API VIP is:
192.168.0.100
4. Current Network Architecture
Each node uses two physical networking roles.
Management / control / VXLAN side
br-mgmt
   |
enp0s31f6
   |
physical LAN
Management addresses:
node1 = 192.168.0.200/24
node2 = 192.168.0.201/24
node3 = 192.168.0.202/24
The API VIP:
192.168.0.100/32
is hosted on br-mgmt by the active Keepalived owner.
Neutron external/provider side
br-ex
  |
ext0
  |
physical LAN
ext0 is the dedicated USB Ethernet adapter used by Neutron as the external/provider uplink.
Kolla uses:
network_interface: "br-mgmt"
neutron_external_interface: "ext0"
The old single-NIC veth design is no longer the current packet path.
5. Why the Dual-NIC Split Matters
The two network roles are easier to understand when separated.
NIC 1
enp0s31f6
    |
br-mgmt
    |
management
OpenStack APIs
control traffic
VXLAN underlay
and:
NIC 2
ext0
   |
br-ex
   |
Neutron external/provider traffic
Floating IP traffic
This avoids forcing management and external-provider connectivity through the same physical NIC.
6. Keystone — WHO Are You?
Keystone is the OpenStack Identity service.
It deals with:
users
projects
roles
authentication
tokens
service catalog
Conceptually:
User
 |
 | credentials
 v
Keystone
 |
 | token
 v
OpenStack APIs
Keystone authenticates users and services.
It does not create virtual machines.
VMware mental model
A rough analogy is:
Keystone
    ~
vCenter SSO / identity / RBAC concepts
The analogy is useful but not exact.
7. Projects, Users, and Roles
OpenStack separates identity from ownership.
A useful model is:
User
  |
  | gets a role
  v
Project
  |
  v
OpenStack resources
Examples of project-owned resources:
VMs
networks
routers
security groups
Floating IPs
volumes
This matters when learning Terraform because the same API may create resources in different projects depending on the selected OpenStack identity.
8. Nova — VM Compute Management
Nova is the OpenStack Compute service.
Nova manages instance lifecycle operations such as:
create
start
stop
reboot
delete
resize
migrate
Important Nova components include:
nova-api
nova-scheduler
nova-conductor
nova-compute
Nova is not itself the hypervisor.
9. Nova API — The Front Door
When a user, Horizon, Terraform, or the OpenStack CLI requests a VM, the request reaches the Nova API.
Example:
Create VM

Name: ubuntu01
vCPU: 2
RAM: 4 GB
Image: Ubuntu
Network: private-net
Conceptually:
Terraform / CLI / Horizon
          |
          v
       Nova API
Terraform is not bypassing OpenStack.
Terraform automates OpenStack by calling its APIs.
10. Placement — WHERE Are Resources Available?
Placement tracks resource inventories and allocations.
For example:
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
Important distinction:
Placement
    provides resource inventory and allocation information

Nova Scheduler
    chooses the compute host
Placement does not simply say:
Run the VM on node2.
It helps Nova understand where resources are available.
11. Nova Scheduler — Choose the Compute Host
Nova Scheduler decides where a new instance should run.
Conceptually:
Nova API
   |
   v
Placement
   |
   | candidate hosts
   v
Nova Scheduler
   |
   | choose node2
   v
node2
A rough VMware analogy is placement logic associated with scheduling or DRS.
It is not a direct 1:1 equivalent.
12. nova-compute — Host-Side Compute Service
Each compute host runs a nova-compute service.
In this lab:
node1
└── nova-compute

node2
└── nova-compute

node3
└── nova-compute
If Nova Scheduler selects node2, the work eventually reaches:
nova-compute on node2
That service manages the instance lifecycle on the selected host.
13. libvirt, QEMU, and KVM
The virtualization stack is approximately:
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
KVM
KVM provides hardware-assisted virtualization through the Linux kernel.
The lab verified:
/dev/kvm
on all three physical nodes.
QEMU
QEMU provides the VM process and virtual hardware/device model.
libvirt
libvirt provides a management API used by Nova to control QEMU/KVM.
Memory:
Nova asks libvirt

libvirt manages QEMU/KVM

QEMU/KVM runs the VM
14. VMware-Oriented Compute View
OpenStack/Linux	VMware-ish Mental Model
Nova	VM lifecycle/orchestration
Nova Scheduler	Placement logic
nova-compute	Host-side compute service
libvirt	Virtualization management API
QEMU/KVM	Hypervisor/runtime layer
Instance	Virtual Machine


These are learning analogies rather than exact equivalents.
15. Glance — IMAGE
Glance is the OpenStack Image service.
Typical images may include:
CirrOS
Ubuntu cloud image
Rocky Linux cloud image
Conceptually:
Nova
 |
 | needs image
 v
Glance
 |
 v
Compute host
 |
 v
VM
A VMware-style mental model is:
Glance image
    ~
template / image repository concept
Glance is not the running VM itself.
Memory:
Glance = IMAGE
16. Neutron — NETWORK
Neutron is the OpenStack Networking service.
It manages logical objects such as:
networks
subnets
ports
routers
DHCP
security groups
Floating IPs
external networks
A VMware-oriented mapping:
OpenStack	VMware-ish Mental Model
Neutron Network	Port Group / logical network
Neutron Port	VM vNIC connection
Subnet	IP subnet configuration
Neutron Router	Virtual L3 router
Security Group	Distributed firewall-like rules
Floating IP	External NAT address
Open vSwitch	Software switching layer


Again, these are learning aids, not exact product mappings.
17. Private Network Example
Imagine:
Network:
private-net

Subnet:
10.10.10.0/24
Two VMs might receive:
VM1 = 10.10.10.25
VM2 = 10.10.10.26
Conceptually:
VM1                  VM2
10.10.10.25          10.10.10.26
 |                      |
 +------ private-net ----+
           |
      10.10.10.0/24
This gives tenant/internal connectivity.
External access requires routing.
18. Neutron Router
A Neutron router connects Layer-3 networks.
For example:
               Neutron Router
                 /                         /                  private-net        external-net
       10.10.10.0/24      192.168.0.0/24
A simplified north-south path is:
VM
 |
private-net
 |
Neutron Router
 |
external-net
 |
br-ex
 |
ext0
 |
physical LAN
The deeper implementation is covered in Chapters 05 and 06.
19. Floating IP
A VM may have an internal address:
10.20.0.188
That address is not directly exposed to the home LAN.
A Floating IP can provide an externally reachable NAT address.
The current lab has validated:
VM:
ai-cirros-01

Fixed IP:
10.20.0.188

Floating IP:
192.168.0.153
Conceptually:
Hermes / LAN
     |
     | ping / SSH
     v
192.168.0.153
     |
     | Neutron NAT
     v
10.20.0.188
     |
     v
VM
The latest cold-boot validation produced:
4 transmitted
4 received
0% packet loss
20. Open vSwitch
Open vSwitch is usually abbreviated:
OVS
It provides software switching used by Neutron.
Important bridges include:
br-int
br-ex
Memory:
br-int
    OpenStack internal integration switching

br-ex
    external/provider bridge
The current external path is:
Neutron
   |
br-ex
   |
ext0
   |
physical LAN
21. OVS in This Kolla Deployment
In this lab, OVS is managed inside Kolla containers.
Inspect it with:
sudo docker exec openvswitch_vswitchd   ovs-vsctl show
Inspect br-ex:
sudo docker exec openvswitch_vswitchd   ovs-vsctl list-ports br-ex
The current validated br-ex ports are:
ext0
phy-br-ex
on all three nodes.
22. Historical Single-NIC Architecture
The lab originally used:
br-ex
  |
veth-ovs
  ||
veth-host
  |
br-mgmt
  |
enp0s31f6
This design was useful because it allowed one physical NIC to carry both:
management traffic
+
Neutron external traffic
It is preserved as a learning stage in:
docs/03-openstack-single-nic-networking.md
It should not be confused with the current dual-NIC architecture.
23. Common Neutron Services
The deployed environment contains Neutron components with roles such as:
neutron-server
neutron-openvswitch-agent
neutron-l3-agent
neutron-dhcp-agent
neutron-metadata-agent
Human translation:
neutron-server
    Neutron API / control service

neutron-openvswitch-agent
    manages OVS networking

neutron-l3-agent
    routing and NAT

neutron-dhcp-agent
    DHCP for tenant networks

neutron-metadata-agent
    metadata access support
The exact implementation details are explored in Chapters 05 and 06.
24. MariaDB — REMEMBER
OpenStack services require persistent databases.
Conceptually:
Nova      ─┐
Neutron   ─┼──> service databases
Keystone  ─┤
Glance    ─┤
Placement ─┘
             |
             v
          MariaDB
Memory:
MariaDB = REMEMBER
A healthy database layer is critical because API containers can still be running while database-backed operations fail.
25. ProxySQL — Database Proxy Layer
The current Kolla deployment also uses ProxySQL.
A simplified model is:
OpenStack service
       |
       v
    ProxySQL
       |
       v
    MariaDB
ProxySQL provides a database proxy layer in front of the MariaDB cluster.
The health script checks:
MariaDB
ProxySQL
separately.
26. RabbitMQ — TALK
OpenStack services communicate internally using messaging.
RabbitMQ provides messaging used for RPC and asynchronous service communication.
A simplified example:
Nova control service
       |
       v
    RabbitMQ
       |
       v
nova-compute
Memory:
RabbitMQ = TALK
Important:
VM packets do not pass through RabbitMQ.
RabbitMQ belongs to the service/control communication plane.
27. HAProxy — LOAD BALANCE
The OpenStack APIs run across multiple control nodes.
Clients use:
192.168.0.100
rather than targeting an individual controller.
Conceptually:
OpenStack CLI / Terraform
          |
          v
   192.168.0.100
          |
          v
       HAProxy
      /   |        /    |     node1  node2  node3
Memory:
HAProxy = LOAD BALANCE
28. Keepalived — VIP
Keepalived provides high availability for:
192.168.0.100/32
One eligible node owns the VIP at a time.
After the latest cold boot, the VIP was observed on:
node2
Conceptually:
node1
node2
node3
   |
Keepalived election/failover
   |
192.168.0.100
Memory:
Keepalived = VIP
29. API VIP HA Is Not Neutron Router HA
These are separate concepts.
API VIP HA
Protects OpenStack API access.
client
  |
192.168.0.100
  |
Keepalived
  |
HAProxy
  |
OpenStack APIs
Neutron router HA
Protects VM routing.
VM
 |
Neutron router
 |
external network
Do not assume router HA merely because the API VIP is highly available.
30. End-to-End: Create One VM
Imagine:
openstack server create   --image cirros-0.6.3   --flavor m1.cirros   --network private-net   test-vm
What happens?
31. Step 1 — Authentication
Keystone answers:
Who are you?

What project are you using?

Are you allowed to perform this action?
The client receives authenticated API access.
32. Step 2 — Nova API
Nova receives:
Create a VM called test-vm
with information such as:
image
flavor
network
project
security groups
33. Step 3 — Placement
Nova needs to know:
Which compute resource providers can satisfy the request?
Placement exposes the resource information and allocations required by Nova.
34. Step 4 — Nova Scheduler
Nova Scheduler chooses a compute host.
For example:
node2
35. Step 5 — Glance
Nova needs the selected image.
Glance provides the image metadata/data required to boot the instance.
36. Step 6 — Neutron
Neutron creates or uses the networking objects required by the VM.
Examples:
Neutron port
MAC address
fixed IP
network binding
security group association
37. Step 7 — Internal Messaging
Nova services coordinate the work.
RabbitMQ participates in this service-to-service communication.
Conceptually:
Nova control services
       |
       v
    RabbitMQ
       |
       v
nova-compute
38. Step 8 — nova-compute
The selected compute node receives the work through nova-compute.
It prepares the instance on that physical host.
39. Step 9 — libvirt / QEMU / KVM
The actual VM execution chain becomes:
nova-compute
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
VM
40. Step 10 — VM Networking
Neutron attaches the VM to the requested network.
The packet path begins with the VM virtual NIC and reaches:
br-int
through Neutron/OVS plumbing.
If the packet must leave the tenant network, it may then reach a Neutron router.
41. Step 11 — External Connectivity
For north-south traffic:
VM
 |
Neutron internal network
 |
Neutron Router
 |
br-ex
 |
ext0
 |
physical LAN
If a Floating IP is associated, Neutron also provides the NAT relationship.
42. The Full VM-Creation Mental Picture
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
                 choose a host
                        |
                        v
                 nova-compute
                        |
                        v
                    libvirt
                        |
                        v
                   QEMU + KVM
                        |
                        v
                      VM
                        |
                   virtual NIC
                        |
                     Neutron
                        |
                     br-int
                        |
                 Neutron Router
                        |
                     br-ex
                        |
                      ext0
                        |
                  physical LAN
This is the current architecture to remember.
43. Where Kolla Fits
Kolla does not replace OpenStack services.
Think:
Kolla
    provides container images
Kolla-Ansible then deploys and configures those images.
Conceptually:
OpenStack services
       |
       v
Kolla container images
       |
       v
Kolla-Ansible
       |
       v
Docker containers on node1/node2/node3
44. Kolla vs Kolla-Ansible
Kolla
Kolla
    = container images
Examples:
Nova image
Neutron image
Keystone image
Glance image
Kolla-Ansible
Kolla-Ansible
    = Ansible deployment automation
It determines and configures things such as:
which nodes run which services
service configuration
container startup
network mappings
HA configuration
database initialization
service registration
45. Why One Node Can Be Control AND Compute
This lab uses a converged three-node design.
Conceptually:
node1
├── control
├── network
└── compute

node2
├── control
├── network
└── compute

node3
├── control
├── network
└── compute
This is intentional.
A small homelab gets more usable compute capacity when all three nodes participate in multiple roles.
46. Control Plane vs Compute Plane
A useful distinction:
CONTROL PLANE
-------------
Keystone
Nova API
Nova Scheduler
Placement
Glance
Neutron API
MariaDB
ProxySQL
RabbitMQ
HAProxy
Keepalived

        |
        | controls
        v

COMPUTE / DATA EXECUTION
------------------------
nova-compute
libvirt
QEMU/KVM
VMs
The physical nodes host both planes in this converged design.
47. Control Plane vs Network Data Plane
Another important distinction:
NETWORK CONTROL PLANE
---------------------
Neutron API
neutron-server
Neutron agents
database
RabbitMQ

        |
        | desired state
        v

NETWORK DATA PLANE
------------------
VM interfaces
br-int
VXLAN
router namespaces
br-ex
ext0
physical LAN
This explains why:
Neutron API healthy
does not automatically mean:
VM network traffic works.
Both layers must be validated.
48. What the Health Script Proves
The repository contains:
scripts/lab-status.sh
The current healthy baseline includes:
3/3 nodes reachable
3/3 MariaDB healthy
3/3 ProxySQL healthy
3/3 Placement API healthy
12/12 Nova control healthy
9/9 Neutron control healthy
Keystone authentication works
6/6 Nova control services enabled/up
3/3 nova-compute enabled/up
3/3 hypervisors up
12/12 Neutron agents alive/up
Result:
RESULT: HEALTHY
PASS checks: 14
This validates multiple control-plane layers.
49. What the Floating-IP Test Proves
The lab also validates a real workload path.
ai-cirros-01
Fixed IP:    10.20.0.188
Floating IP: 192.168.0.153
A successful ping after cold boot proves more than API health.
It validates:
physical external NIC
br-ex
Neutron routing/NAT
Floating IP
VM network path
running workload
This is data-plane evidence.
50. Why Container Health Alone Is Not Enough
A container can be:
running
while the OpenStack service is:
unusable
Examples:
nova-compute container running
but
Nova service DOWN
or:
Keystone container running
but
authentication fails
Therefore troubleshoot at several layers:
container
service
API
data plane
51. Cinder — BLOCK STORAGE
Cinder is the OpenStack Block Storage service.
Think:
Cinder = attachable VM volumes
Conceptually:
VM
 |
 +-- root disk
 |
 +-- Cinder volume
A VMware-oriented mental model is:
Cinder volume
    ~
virtual disk / block-storage service
Cinder is useful to understand even if it is not the main focus of the current learning stage.
52. Ceph — DISTRIBUTED STORAGE
Ceph is not OpenStack itself.
It is a distributed storage platform that OpenStack can use as a backend.
Conceptually:
             OpenStack
                 |
       +---------+---------+
       |         |         |
       v         v         v
     Glance    Cinder     Nova
       \         |         /
        \        |        /
         +-------+-------+
                 |
                 v
               Ceph
Possible uses include:
Glance image data
Cinder volumes
Nova instance disks
The current homelab disks still contain historical Ceph BlueStore metadata, but Ceph is not required to understand the core control-plane architecture documented here.
53. Why Ceph Is a Separate Learning Layer
OpenStack already includes many moving parts:
Keystone
Nova
Placement
Glance
Neutron
RabbitMQ
MariaDB
ProxySQL
HAProxy
Keepalived
KVM
OVS
Ceph introduces another distributed system:
MON
MGR
OSD
CRUSH
RBD
pools
replication
It is easier to learn after the OpenStack control/network/compute architecture is already familiar.
54. VMware-Oriented Review Table
OpenStack / Component	Purpose	VMware-ish Mental Model
Keystone	Identity/authentication	vCenter SSO / RBAC concepts
Nova	Compute lifecycle	VM management/orchestration
Placement	Resource inventory/allocation	Resource availability
Nova Scheduler	Select compute host	Placement/scheduling logic
nova-compute	Host-side compute service	Host-side VM management
Glance	Image service	Template/image repository
Neutron	Networking	Virtual networking platform
Cinder	Block storage	VM disk/block storage service
Horizon	Web UI	Management UI
MariaDB	Persistent service state	Backend database
ProxySQL	DB proxy layer	Database proxy/load-balancing concept
RabbitMQ	Internal messaging	Message bus
HAProxy	API load balancing	Load balancer
Keepalived	VIP failover	Virtual IP HA
libvirt	Virtualization API	Hypervisor management layer
QEMU/KVM	VM runtime	Hypervisor/runtime layer


These comparisons are learning aids rather than exact equivalents.
55. Terraform Fits Above the OpenStack APIs
Terraform does not replace Nova, Neutron, or Keystone.
Terraform describes desired cloud resources and calls the OpenStack APIs.
Conceptually:
Terraform
    |
    v
OpenStack API
    |
    +-- Nova
    +-- Neutron
    +-- Glance data lookups
    +-- Keystone authentication
Example:
Terraform resource:
openstack_compute_instance_v2

        |
        v

Nova API

        |
        v

OpenStack VM
This is why learning the OpenStack architecture first makes Terraform much easier to understand.
56. Ansible Fits at a Different Layer
Ansible is mainly used here for:
host preparation
Linux configuration
preflight checks
network configuration
application configuration
Kolla-Ansible then uses Ansible to deploy OpenStack itself.
A useful distinction:
Terraform
    creates cloud infrastructure

Ansible
    configures systems

Kolla-Ansible
    configures/deploys OpenStack services
They overlap in automation philosophy but operate at different layers.
57. Hermes Fits Above the Automation
Hermes should be treated as an assistant around the IaC workflow.
Conceptually:
User request
    |
    v
Hermes
    |
    v
Terraform / Ansible change
    |
    v
Git diff / validation
    |
    v
Human approval
    |
    v
execution
Hermes should understand the architecture so that a request such as:
Create a new private network and VM.
can be translated into the correct IaC resources rather than random shell commands.
58. Desired State Appears Everywhere
The same idea appears repeatedly:
Terraform:
resource should exist

Ansible:
host should have this configuration

Neutron:
router/network/port should exist

Kolla-Ansible:
OpenStack service configuration should match globals/inventory
This is one of the most transferable infrastructure concepts in the entire lab.
59. The OpenStack Service Dependency Story
A simplified dependency picture:
User / Terraform
       |
       v
   Keystone
       |
       v
 OpenStack APIs
       |
       +--> Nova
       +--> Neutron
       +--> Glance
       +--> Placement
       |
       +--> MariaDB / ProxySQL
       |
       +--> RabbitMQ
Then compute execution continues:
Nova
 |
 v
nova-compute
 |
 v
libvirt
 |
 v
QEMU/KVM
 |
 v
VM
And network execution continues:
Neutron
 |
 v
OVS / namespaces / VXLAN
 |
 v
br-ex
 |
 v
ext0
 |
 v
physical LAN
60. The 30-Second OpenStack Explanation
If someone asks:
What happens when OpenStack creates a VM?

A strong short answer is:
Keystone authenticates the request.

Nova receives the VM request.

Placement reports available compute resources.

Nova Scheduler chooses a compute node.

Glance provides the image.

Neutron provides the VM network connectivity.

RabbitMQ helps OpenStack services communicate.

nova-compute asks libvirt/QEMU/KVM to run the VM.

MariaDB stores persistent service state.

If external connectivity is required, Neutron routes through br-ex and ext0.
If that explanation makes sense, the architecture is starting to stick.
61. Review Cheat Sheet
Keystone
    WHO

Nova
    VM

Placement
    WHERE

Glance
    IMAGE

Neutron
    NETWORK

MariaDB
    REMEMBER

ProxySQL
    DB PROXY

RabbitMQ
    TALK

HAProxy
    LOAD BALANCE

Keepalived
    VIP

KVM
    RUN

Cinder
    BLOCK STORAGE

Ceph
    DISTRIBUTED STORAGE
62. Current End-to-End Network Memory Hook
For a VM reaching the home LAN or Internet:
VM
 |
 v
Neutron port
 |
 v
br-int
 |
 v
Neutron router
 |
 v
br-ex
 |
 v
ext0
 |
 v
physical LAN
 |
 v
home router / Internet
For incoming Floating-IP traffic:
LAN client
 |
 v
Floating IP
 |
 v
ext0
 |
 v
br-ex
 |
 v
Neutron router / NAT
 |
 v
VM fixed IP
The detailed packet walk is in:
docs/05-neutron-packet-walk.md
63. Current Control-Plane Memory Hook
Hermes
  |
  v
192.168.0.100
OpenStack API VIP
  |
  v
HAProxy
  |
  +--> API services on node1
  +--> API services on node2
  +--> API services on node3
Keepalived controls which node currently owns:
192.168.0.100/32
64. Current Three-Node Mental Picture
                         HERMES
                           |
         Ansible / Kolla / Terraform / CLI
                           |
                           v
                    192.168.0.100
                     API VIP
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
               OpenStack services
                           |
          +----------------+----------------+
          |                                 |
       br-mgmt                            br-ex
          |                                 |
     enp0s31f6                            ext0
          |                                 |
 management/API/VXLAN              Neutron external
That is the architecture to carry forward.
65. What Comes Next
After understanding the high-level architecture, the next chapter follows a real packet through Neutron:
docs/05-neutron-packet-walk.md
That chapter turns:
Neutron
OVS
br-int
br-ex
router
NAT
Floating IP
VXLAN
ext0
into an actual packet path.
Then:
docs/06-neutron-router-agents-and-ha.md
explains router placement, namespaces, agents, HA, and DVR concepts.
66. Final Memory Hook
WHO      = Keystone
VM       = Nova
WHERE    = Placement
IMAGE    = Glance
NETWORK  = Neutron
REMEMBER = MariaDB
TALK     = RabbitMQ
RUN      = KVM
VIP      = Keepalived
BALANCE  = HAProxy
DB PROXY = ProxySQL
Do not memorize every daemon.
Understand which layer owns which responsibility.
That is enough to make the rest of OpenStack much easier to learn.
