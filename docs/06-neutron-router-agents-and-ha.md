Neutron Routers, Agents, Namespaces, and High Availability
This chapter explains how Neutron routing works across the three-node OpenStack homelab.
The goal is to answer practical questions:
Where does a Neutron router actually run?

Does every node have the same router?

What does neutron-l3-agent do?

What is a qrouter namespace?

How does a VM on node2 reach a router hosted on another node?

How does external traffic reach the physical LAN?

What is router HA?

What is DVR?

How do I prove which layer is broken?
This chapter focuses on the conventional learning model used by this lab:
Neutron
+
ML2
+
Open vSwitch
+
Neutron agents
+
Linux network namespaces
+
VXLAN
The detailed packet-by-packet view is in:
docs/05-neutron-packet-walk.md
The current physical dual-NIC design is documented in:
docs/17-openstack-dual-nic-networking.md
1. The Most Important Idea
A Neutron router is not automatically a virtual machine.
In the conventional L3-agent model, it is implemented using Linux networking constructs.
A simplified picture is:
Neutron API
    |
    v
neutron-server
    |
    v
neutron-l3-agent
    |
    v
qrouter namespace
    |
    +-- interfaces
    +-- routes
    +-- NAT
    +-- neighbour state
Memory:
neutron-server
    says WHAT should exist

neutron-l3-agent
    implements the routing state

qrouter namespace
    actually routes packets
2. Control Plane vs Data Plane
This distinction is essential.
Control plane
The control plane describes and coordinates desired networking state.
Examples:
create network
create subnet
create router
attach subnet
set external gateway
associate Floating IP
create security rule
Components include:
Neutron API
neutron-server
database
RabbitMQ
Neutron agents
Data plane
The data plane actually moves packets.
Examples:
VM virtual NIC
TAP-style interfaces
br-int
VXLAN
router namespaces
br-ex
ext0
physical LAN
Important:
VM packets do NOT pass through RabbitMQ.
RabbitMQ carries control/service messages.
The real packet moves through Linux networking and Open vSwitch.
3. Simple Architecture
                    CONTROL PLANE

OpenStack CLI / Horizon / Terraform
              |
              v
         Neutron API
              |
              v
        neutron-server
              |
              v
        Neutron agents


                     DATA PLANE

VM
 |
TAP / Neutron port
 |
br-int
 |
VXLAN if required
 |
qrouter namespace
 |
br-ex
 |
ext0
 |
physical LAN
This distinction becomes extremely useful during troubleshooting.
4. What neutron-server Does
neutron-server provides the Networking API and coordinates desired network state.
For example:
openstack router create router01
means conceptually:
User:
"I want router01 to exist."

        |
        v

Neutron:
"Record router01 as desired state."

        |
        v

Agents:
"Implement the required Linux/OVS state."
neutron-server does not need to forward every VM packet itself.
5. What neutron-l3-agent Does
The L3 agent implements Layer-3 networking functions.
Think:
routing
external gateway connectivity
NAT
Floating IP processing
router namespaces
Simplified:
neutron-server
      |
      v
neutron-l3-agent
      |
      v
qrouter namespace
The agent is the worker.
The namespace is the networking environment it builds and maintains.
6. What Is a Linux Network Namespace?
A Linux network namespace is an isolated networking environment.
It can have its own:
interfaces
IP addresses
routing table
neighbour table
firewall/NAT state
Think:
a small isolated networking world inside Linux
This allows many logical routers to coexist on one physical node.
7. Why Namespaces Are Useful
Imagine two tenants both use:
10.10.10.0/24
They can still have separate routers:
qrouter-A
    gateway 10.10.10.1

qrouter-B
    gateway 10.10.10.1
because they live in isolated network namespaces.
Conceptually:
Linux Host

+-----------------------+
| qrouter-A             |
| 10.10.10.1            |
+-----------------------+

+-----------------------+
| qrouter-B             |
| 10.10.10.1            |
+-----------------------+
The address overlap is possible because the networking environments are isolated.
8. qrouter Namespace
A router namespace commonly looks like:
qrouter-<router-UUID>
On a physical OpenStack node:
sudo ip netns
may show:
qrouter-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
The UUID corresponds to the OpenStack router.
9. qr and qg Interfaces
Inside a router namespace, interfaces commonly resemble:
qr-xxxxxxxx
qg-xxxxxxxx
Memory:
qr
    router internal side

qg
    router gateway/external side
Conceptually:
private network
      |
   qr-xxxx
      |
+----------------+
| qrouter        |
| routing + NAT  |
+----------------+
      |
   qg-xxxx
      |
external network
10. Router Internal Side
Suppose the private subnet is:
10.20.0.0/24
and the VM gateway is:
10.20.0.1
The router internal side represents that gateway relationship.
Conceptually:
VM
10.20.0.188
    |
    v
10.20.0.1
    |
 qr-xxxx
    |
 qrouter
To the VM, this still looks like normal IP routing.
11. Router External Side
The router also needs a path toward the external/provider network.
Conceptually:
qrouter
   |
qg-xxxx
   |
external network
   |
br-ex
   |
ext0
   |
physical LAN
In the current lab:
ext0
is the physical Layer-2 uplink used by br-ex.
12. Current Physical External Path
The current dual-NIC architecture is:
MANAGEMENT / CONTROL / VXLAN

br-mgmt
   |
enp0s31f6
   |
physical LAN
and separately:
NEUTRON EXTERNAL

br-ex
  |
ext0
  |
physical LAN
Kolla-Ansible uses:
network_interface: "br-mgmt"
neutron_external_interface: "ext0"
This is the current design.
13. Historical Single-NIC Path
The original learning stage used:
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
physical LAN
That design was intentionally kept in:
docs/03-openstack-single-nic-networking.md
It remains useful for learning Linux bridges and veth pairs.
It is not the current physical path of this homelab.
14. Where Does a Router Run?
A Neutron router is scheduled to one or more L3 agents depending on the configured routing model.
In a simple centralized non-HA example:
node1
    qrouter-router01

node2
    no router01 namespace

node3
    no router01 namespace
The fact that a node runs an L3 agent does not automatically mean every router is active there.
15. Agent Exists vs Router Exists
Do not confuse:
neutron-l3-agent exists on node2
with:
router01 is hosted on node2
They describe different things.
Memory:
L3 agent
    capability / worker

qrouter namespace
    specific logical router implementation
A rough VMware-style placement analogy is:
L3 agent
    host capable of running a workload

qrouter
    actual workload assigned there
The analogy is not exact, but it helps.
16. Find the Router From Hermes
Start from the OpenStack control plane.
Run on Hermes:
openstack router list
Inspect one router:
openstack router show <router-name-or-UUID>
Show its ports:
openstack port list --router <router-name-or-UUID>
This maps the logical router to its internal/external Neutron attachments.
17. Find Which L3 Agent Hosts the Router
From Hermes:
openstack network agent list --agent-type l3
For a particular router:
openstack network agent list \
  --router <router-name-or-UUID>
This is much better than SSHing to every node and guessing.
Once you know the host, inspect that node directly.
18. Inspect the Router Namespace
On the node hosting the router:
sudo ip netns
Then:
sudo ip netns exec qrouter-<UUID> \
  ip -br addr
Inspect routing:
sudo ip netns exec qrouter-<UUID> \
  ip route
Inspect neighbour state:
sudo ip netns exec qrouter-<UUID> \
  ip neigh
At this point:
OpenStack object
has become:
real Linux state
19. OpenStack Routing Is Still Linux Routing
This is one of the best lessons from Neutron.
Underneath the OpenStack terminology are familiar Linux concepts:
network namespaces
interfaces
routes
ARP/neighbour discovery
NAT
firewall rules
VXLAN
Open vSwitch
Neutron automates and coordinates these pieces.
The more Linux networking you understand, the less mysterious Neutron becomes.
20. VM and Router on Different Nodes
Suppose:
VM:
node2

router:
node1
The VM can still use that router because its Neutron network spans the physical hosts.
Simplified:
NODE2

VM
 |
TAP
 |
br-int
 |
VXLAN
 |
============================
 |
VXLAN
 |
br-int
 |
qrouter

NODE1
The logical network is carried over the physical underlay.
21. Underlay vs Overlay
Underlay
The actual physical IP network.
In this lab:
192.168.0.0/24
The management/tunnel side uses:
br-mgmt
   |
enp0s31f6
Overlay
The logical Neutron network carried across that physical network.
Example:
10.20.0.0/24
using VXLAN.
Memory:
UNDERLAY
    physical transport

OVERLAY
    logical tenant network
22. VXLAN
VXLAN allows Layer-2 tenant networks to span physical hosts.
Very simplified:
original VM Ethernet frame
        |
        v
VXLAN encapsulation
        |
        v
physical IP network
        |
        v
remote OpenStack node
VMware / NSX mental model:
logical network
      |
encapsulation
      |
physical transport
The implementation differs, but the overlay concept is familiar.
23. Example — VM to Internet
Suppose:
VM:
node2

Fixed IP:
10.20.0.188

router:
hosted on another node
The simplified path is:
VM
 |
TAP / Neutron port
 |
br-int
 |
VXLAN if router is remote
 |
qrouter
 |
NAT
 |
br-ex
 |
ext0
 |
physical LAN
 |
Internet
The physical dual-NIC change affects the bottom of the path.
The Neutron routing concepts remain the same.
24. North-South vs East-West
Two useful traffic directions:
north-south
    VM ↔ outside OpenStack
Example:
VM → Internet
and:
east-west
    VM ↔ VM
Example:
VM-A → VM-B
inside the cloud.
25. Same Network, Same Host
Suppose:
VM-A
10.20.0.25

VM-B
10.20.0.26
and both are on the same Neutron subnet and same compute host.
Conceptually:
VM-A
 |
TAP
 |
br-int
 |
TAP
 |
VM-B
A Layer-3 router is not required for two addresses on the same Layer-2 subnet.
26. Same Network, Different Hosts
Now place them on different nodes:
VM-A on node2
VM-B on node3
Same Neutron network:
NODE2

VM-A
 |
br-int
 |
VXLAN
 |
====================
 |
VXLAN
 |
br-int
 |
VM-B

NODE3
The overlay extends the tenant network between hosts.
27. Different Networks
Suppose:
VM-A
10.10.10.25/24

VM-B
10.20.0.25/24
Now Layer-3 routing is required.
Conceptually:
10.10.10.0/24
       |
       v
 Neutron Router
       |
       v
10.20.0.0/24
This is normal routing expressed through Neutron.
28. qdhcp Namespace
Neutron can provide DHCP services using another namespace.
You may see:
qdhcp-<network-UUID>
Do not confuse this with:
qrouter-<router-UUID>
Memory:
qdhcp
    provides DHCP

qrouter
    provides routing/NAT
29. DHCP vs Router
A simple memory hook:
DHCP asks:
"What network settings should the VM use?"

Router asks:
"Where should this packet go?"
Different responsibilities.
30. Floating IPs
A Floating IP creates an externally reachable relationship to a VM fixed IP.
Conceptually:
192.168.0.153
      |
      | NAT
      v
10.20.0.188
The current lab has validated this path using:
ai-cirros-01
with:
Fixed IP:
10.20.0.188

Floating IP:
192.168.0.153
A post-cold-boot ping produced:
4 transmitted
4 received
0% packet loss
That proves the Neutron data plane remained functional after reboot.
31. Inspect Floating IP State
From Hermes:
openstack floating ip list
Inspect one:
openstack floating ip show 192.168.0.153
Then inspect the attached port:
openstack port show <port-UUID>
This connects:
Floating IP
    ↓
Neutron port
    ↓
Fixed IP
    ↓
VM
32. Router HA Concept
High availability changes how router state is placed.
A simplified HA model can look like:
router01

node1
ACTIVE

node2
BACKUP

node3
BACKUP
If the active router instance becomes unavailable, another instance can take over.
This is conceptually different from a simple centralized non-HA router that exists on only one node.
33. VRRP and Keepalived
Neutron L3 HA can use:
VRRP
implemented with:
Keepalived
Simplified:
router instance A
ACTIVE

      VRRP

router instance B
BACKUP
If the active instance fails:
BACKUP
   ↓
ACTIVE
The exact behavior depends on the Neutron configuration.
34. API VIP HA Is Not Router HA
Do not mix these concepts.
The OpenStack API VIP:
192.168.0.100
uses Keepalived to protect API access.
Conceptually:
OpenStack client
      |
192.168.0.100
      |
Keepalived / HAProxy
      |
OpenStack APIs
Neutron router HA protects:
VM routing
So:
API HA
    !=
Neutron router HA
Same broad HA technology family.
Different purpose.
35. Current VIP Observation
After the latest cold boot, the API VIP was observed on node2:
node2 br-mgmt
    192.168.0.201/24
    192.168.0.100/32
This proves the API VIP returned correctly after reboot.
It does not by itself prove that Neutron router HA is enabled.
That distinction is important.
36. Do Not Assume HA Settings
Do not infer Neutron router HA or DVR only because:
all three nodes run network agents
or because:
all three nodes have br-ex
Those observations prove that network functionality is deployed across the cluster.
They do not automatically prove:
every router is HA
or:
DVR is enabled
Always confirm with actual Kolla configuration and OpenStack state.
37. What Is DVR?
DVR means:
Distributed Virtual Routing
Traditional centralized routing may require traffic to travel to the node hosting the router.
DVR distributes routing functions closer to compute nodes for some traffic flows.
38. Centralized Routing
Simplified:
VM on node2
      |
      v
br-int
      |
      | VXLAN
      v
node1
      |
qrouter
      |
br-ex
      |
external network
This is relatively easy to understand and observe.
That makes it a strong learning model.
39. DVR Idea
With DVR, routing functions can be distributed closer to the compute nodes.
Conceptually:
node1
router components

node2
router components
   |
  VM

node3
router components
   |
  VM
This can reduce some centralized traffic paths.
40. DVR Adds Complexity
DVR introduces additional concepts.
Examples can include:
distributed router namespaces
SNAT namespaces
router components on compute hosts
different L3-agent modes
For a learning lab, understanding conventional routing first is a good strategy.
Memory:
Understand first.
Optimize later.
41. Centralized vs DVR
Concept	Centralized routing	DVR
Easier to visualize	Yes	More complex
Router functions concentrated	More	Less
Distributed routing on computes	No	Yes
Good first learning model	Excellent	Advanced
Operational complexity	Lower	Higher


The purpose of this comparison is conceptual.
Always inspect the actual deployment before assuming which mode is active.
42. Neutron Agents
Neutron agents turn desired configuration into host-level networking.
Examples may include:
L3 agent
DHCP agent
OVS agent
metadata agent
From Hermes:
openstack network agent list
The current lab health check reports:
12/12 Neutron agents alive and UP
This is a useful control-plane health indicator.
43. Agent Health Is Not the Whole Story
This:
12/12 Neutron agents UP
is excellent.
But it does not automatically prove:
a Floating IP works
or:
a VM can reach the Internet
That is why the lab also performs real data-plane tests.
Think in layers:
agent health
    control-plane evidence

Floating-IP ping
    data-plane evidence
Both matter.
44. Current br-ex State
On each OpenStack node:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
currently shows:
ext0
phy-br-ex
The important physical uplink is:
ext0
phy-br-ex is part of the OVS bridge-to-bridge connectivity.
It is not another physical NIC.
45. Inspect OVS Correctly in This Kolla Lab
Open vSwitch runs inside Kolla containers.
Use:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
Inspect br-int:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-int
Inspect br-ex:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
Do not assume that running ovs-vsctl directly on the host is the correct method in this deployment.
46. Inspect All Nodes From Hermes
From Hermes:
for ip in 200 201 202; do
  echo
  echo "===== NODE $ip ====="

  ssh openstack@192.168.0.$ip '
    echo "--- Interfaces ---"
    ip -br addr show br-mgmt
    ip -br link show ext0

    echo
    echo "--- br-ex ---"
    sudo docker exec openvswitch_vswitchd \
      ovs-vsctl list-ports br-ex
  '
done
The latest cold-boot validation confirmed:
node1
br-mgmt 192.168.0.200/24
ext0 UP

node2
br-mgmt 192.168.0.201/24
VIP 192.168.0.100/32
ext0 UP

node3
br-mgmt 192.168.0.202/24
ext0 UP
and all three returned:
ext0
phy-br-ex
for br-ex.
47. Router Troubleshooting Workflow
If a VM cannot reach the Internet, do not immediately restart Neutron.
Follow the path.
Step 1 — VM
Inside the VM:
ip addr
ip route
Ask:
Does it have the correct fixed IP?

Does it have the correct gateway?
Step 2 — OpenStack objects
From Hermes:
openstack server show <server>
openstack port list --server <server>
openstack router list
openstack router show <router>
Ask:
Does the VM port exist?

Is the subnet attached to the router?

Does the router have an external gateway?
48. Find the Router Host
From Hermes:
openstack network agent list \
  --router <router-name-or-UUID>
Then SSH to the relevant host.
Ask:
Does the expected L3 agent exist?

Does the qrouter namespace exist?
49. Test Inside the Router
On the router host:
sudo ip netns exec qrouter-<UUID> \
  ip -br addr
sudo ip netns exec qrouter-<UUID> \
  ip route
Then test the physical gateway:
sudo ip netns exec qrouter-<UUID> \
  ping -c 3 192.168.0.1
This test is powerful.
If:
router namespace → physical gateway
works but:
VM → Internet
fails, then the external uplink is probably not the first place to investigate.
50. Inspect NAT Carefully
For investigation only, NAT state may be visible through an iptables-compatible view depending on the deployed Neutron implementation.
Example:
sudo ip netns exec qrouter-<UUID> \
  iptables -t nat -S
Do not manually edit Neutron-managed rules.
The goal is:
observe
not:
repair OpenStack by hand
Manual changes can conflict with Neutron's desired state.
51. Packet Capture
When deeper troubleshooting is required:
sudo tcpdump -ni ext0
Watch ICMP:
sudo tcpdump -ni ext0 icmp
Watch a specific Floating IP:
sudo tcpdump -ni ext0 host 192.168.0.153
Packet capture answers:
Did the packet reach this point?
It does not automatically prove that the next hop works.
52. Troubleshooting Is Path Troubleshooting
A packet has a path.
Your job is to find the first point where reality differs from the expected path.
Example:
VM
 ✅
 |
br-int
 ✅
 |
VXLAN
 ✅
 |
qrouter
 ✅
 |
br-ex
 ✅
 |
ext0
 ❌
 |
LAN
Now the failure domain is small.
This is much better than saying:
"Neutron is broken."
53. VMware Troubleshooting Mental Model
This is very similar to checking:
VM NIC
   |
Port Group
   |
vSwitch
   |
uplink
   |
physical switch
   |
router
In this OpenStack lab:
VM vNIC
   |
Neutron port / TAP
   |
br-int
   |
VXLAN / router
   |
br-ex
   |
ext0
   |
physical LAN
Different products.
Same troubleshooting philosophy:
follow the packet
54. Desired State vs Actual State
This is one of the most valuable concepts in the whole project.
Desired state:
router01 should exist
Actual state:
Neutron database entry
+
scheduled L3 agent
+
qrouter namespace
+
interfaces
+
routes
+
NAT state
Neutron agents try to keep actual state aligned with desired state.
55. Why This Matters for Terraform
Terraform also works with desired infrastructure state.
For example:
resource "openstack_networking_router_v2" "router" {
  name = "router01"
}
Terraform says:
I want this OpenStack router to exist.
Terraform calls the OpenStack APIs.
Neutron then implements the networking state.
Conceptually:
Terraform
    |
    v
OpenStack API
    |
    v
Neutron desired state
    |
    v
Neutron agents
    |
    v
Linux / OVS actual state
This is an excellent bridge between OpenStack and Infrastructure as Code.
56. Why This Matters for Ansible
Ansible usually works at a different layer.
For example:
Terraform
    creates VM

Ansible
    configures VM
Or for the OpenStack hosts:
Ansible
    configures Linux prerequisites
    networking
    packages
    files
Kolla-Ansible itself demonstrates this model:
desired configuration
      |
      v
Ansible tasks
      |
      v
actual Linux/container state
Learning Neutron desired state helps reinforce why Ansible idempotency matters.
57. Why This Matters for Hermes
Hermes should not become an all-powerful root operator.
A safer learning model is:
Hermes
    helps write/review IaC
        |
        v
Terraform / Ansible
        |
        v
human review
        |
        v
controlled apply
For OpenStack networking, Hermes can help:
explain a Terraform plan
generate Ansible tasks
review configuration
compare desired vs actual state
suggest troubleshooting commands
But high-impact operations should remain deliberate.
This matches the security guardrails documented in:
AI/HERMES-IAC-RULES.md
58. Three Automation Layers
A useful mental model for the next learning phase is:
Terraform
    creates cloud resources

Ansible
    configures operating systems / applications

Hermes
    assists with authoring, review, explanation, and troubleshooting
Example:
Terraform
    create network
    create subnet
    create router
    create VM
        |
        v
Ansible
    install NGINX
    configure web page
        |
        v
Hermes
    review the code
    explain the plan
    help troubleshoot safely
This is where the homelab becomes a practical IaC platform.
59. Current Healthy Baseline
The current lab baseline is:
Node reachability:
3/3

MariaDB:
3/3 healthy

ProxySQL:
3/3 healthy

Placement:
3/3 healthy

Nova control:
12/12 healthy

Nova compute:
3/3 enabled/up

Hypervisors:
3/3 up

Neutron control:
9/9 healthy

Neutron agents:
12/12 alive and UP

Keystone:
authentication works

br-ex:
ext0 + phy-br-ex on all nodes

Floating IP:
validated after cold boot

Overall:
HEALTHY
This is the state to preserve before intentional networking experiments.
60. Router Memory Model
neutron-server
    = NETWORK CONTROL PLANE

neutron-l3-agent
    = ROUTER WORKER

qrouter
    = LINUX ROUTER ENVIRONMENT

qr-*
    = ROUTER INTERNAL SIDE

qg-*
    = ROUTER EXTERNAL SIDE

qdhcp
    = DHCP NAMESPACE

br-int
    = INTERNAL OVS SWITCHING

br-ex
    = EXTERNAL OVS BRIDGE

ext0
    = CURRENT EXTERNAL PHYSICAL UPLINK

VXLAN
    = HOST-TO-HOST OVERLAY
61. HA Memory Model
API VIP HA
    protects OpenStack API access

Neutron router HA
    protects VM routing

VRRP
    election/failover mechanism

Keepalived
    can implement VRRP-based HA

DVR
    distributes routing functionality
Do not assume a feature is enabled merely because you understand the concept.
Always verify the actual configuration.
62. Multi-Node Memory Model
VM on node2
      |
    br-int
      |
    VXLAN
      |
    br-int
      |
qrouter on another node
      |
    br-ex
      |
     ext0
      |
     LAN
This is the picture to carry into troubleshooting.
63. Useful Commands — Hermes
Logical OpenStack state:
openstack router list
openstack router show <router>
openstack port list --router <router>
openstack network agent list
openstack network agent list --agent-type l3
openstack network agent list --router <router>
openstack floating ip list
These commands answer:
What does OpenStack think should exist?
64. Useful Commands — OpenStack Node
Actual Linux state:
sudo ip netns
sudo ip netns exec qrouter-<UUID> \
  ip -br addr
sudo ip netns exec qrouter-<UUID> \
  ip route
sudo ip netns exec qrouter-<UUID> \
  ip neigh
Actual OVS state:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
These commands answer:
What actually exists on Linux right now?
65. The Big Troubleshooting Question
When OpenStack networking fails, compare:
DESIRED STATE
with:
ACTUAL STATE
Example:
OpenStack says:
router01 exists

but Linux says:
qrouter namespace missing
Now you have a meaningful failure.
That is far more useful than:
"Networking doesn't work."
66. Final One-Sentence Explanation
If someone asks:
How does a Neutron router work?

A strong answer is:
Neutron's control plane records the desired logical router,
Neutron agents implement that router using Linux networking
and Open vSwitch, and the resulting namespaces, routes,
NAT state, overlays, and external bridge move the actual packets.
67. Final Lesson
Neutron looks complicated because it exposes many layers.
But those layers become manageable when you separate them:
OpenStack object
      |
      v
Neutron control plane
      |
      v
Neutron agent
      |
      v
Linux namespace / OVS
      |
      v
physical network
For troubleshooting:
follow the packet
For automation:
understand desired state
For the next phase of this homelab:
Terraform
    creates infrastructure

Ansible
    configures systems

Hermes
    helps you understand and safely automate both
That is where OpenStack becomes the platform for learning IaC rather than the final destination.
