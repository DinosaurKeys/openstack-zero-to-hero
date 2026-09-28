# Neutron Routers, Agents, Namespaces, and High Availability

This document explains how Neutron routing works across multiple OpenStack nodes.

The main questions are:

```text
Where does a Neutron router actually run?

Does every node have the router?

Who creates and manages it?

How does a VM on node2 reach a router on node1?

What happens if the router node dies?

What is DVR?
```

This guide assumes the conventional:

```text
Neutron
+
ML2
+
Open vSwitch
+
Neutron L3 Agent
```

architecture used for this learning lab.

In the current Kolla-Ansible configuration, the default Neutron plugin agent is:

```text
openvswitch
```

and both:

```text
Neutron DVR
Neutron Agent HA
```

are disabled by default unless explicitly enabled.

---

# 1. The Most Important Correction

A Neutron router does NOT automatically run independently on every OpenStack node.

Instead, the nodes can run:

```text
neutron-l3-agent
```

The L3 agent is capable of hosting Neutron routers.

For example:

```text
node1
├── neutron-l3-agent
└── can host routers

node2
├── neutron-l3-agent
└── can host routers

node3
├── neutron-l3-agent
└── can host routers
```

But a particular router might actually be hosted on:

```text
node1
```

only.

---

# 2. Small Memory Model

Remember:

```text
neutron-server
    = controller / brain

neutron-l3-agent
    = router worker

qrouter namespace
    = actual Linux routing environment
```

Or even shorter:

```text
Neutron Server
    says WHAT

L3 Agent
    BUILDS it

Linux namespace
    ROUTES packets
```

---

# 3. Control Plane vs Data Plane

This distinction is extremely important.

## Control Plane

The control plane decides:

```text
What should the network look like?
```

Examples:

```text
create network

create subnet

create router

attach subnet to router

associate Floating IP

create security rule
```

Components include:

```text
neutron-server
database
RabbitMQ
Neutron agents
```

---

## Data Plane

The data plane moves actual packets.

Examples:

```text
TAP interfaces

br-int

VXLAN tunnels

router namespaces

br-ex

physical NICs
```

Important:

```text
VM packets do NOT pass through RabbitMQ.
```

RabbitMQ carries control/service messages.

Actual network traffic travels through Linux and OVS networking.

---

# 4. Simple Diagram

```text
CONTROL PLANE

User / OpenStack CLI
        |
        v
  Neutron API
        |
        v
 neutron-server
        |
        | instructions
        v
 Neutron Agents


DATA PLANE

VM
 |
TAP
 |
br-int
 |
VXLAN
 |
qrouter namespace
 |
br-ex
 |
physical network
```

---

# 5. What Does neutron-server Do?

The Neutron server provides the Networking API.

For example, the user requests:

```bash
openstack router create router01
```

Neutron records the desired state.

Conceptually:

```text
User:
"I want router01."

        |
        v

neutron-server:
"Router router01 should exist."
```

The server does not itself need to forward every packet.

Instead it coordinates agents which implement the desired networking state.

---

# 6. What Does the L3 Agent Do?

The:

```text
neutron-l3-agent
```

implements Layer 3 networking functions.

Think:

```text
routing
NAT
external gateway connectivity
Floating IP processing
```

Simplified:

```text
neutron-server
      |
      | instructions
      v
neutron-l3-agent
      |
      | creates/configures
      v
Linux router namespace
```

---

# 7. What Is a Linux Network Namespace?

A Linux network namespace is an isolated networking environment.

Each namespace can have its own:

```text
interfaces

IP addresses

routing table

ARP table

firewall rules

NAT rules
```

Think of it as:

```text
a small isolated networking world inside Linux
```

---

# 8. Why Does Neutron Use Namespaces?

Imagine two different OpenStack tenants.

Tenant A:

```text
10.10.10.0/24
```

Tenant B:

```text
10.10.10.0/24
```

They use the exact same IP range.

Normally that would conflict.

But separate namespaces allow:

```text
qrouter-A
    10.10.10.1

qrouter-B
    10.10.10.1
```

to coexist on the same physical host.

Conceptually:

```text
Linux Host

+-----------------------+
| qrouter-A             |
|                       |
| 10.10.10.1            |
+-----------------------+

+-----------------------+
| qrouter-B             |
|                       |
| 10.10.10.1            |
+-----------------------+
```

They are isolated from each other.

---

# 9. Neutron Router Namespace

After OpenStack is deployed, running:

```bash
ip netns
```

may show something similar to:

```text
qrouter-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

That is a router namespace.

The UUID corresponds to the OpenStack router.

---

# 10. The Router Is Not a VM

This is important.

A Neutron router does not have to be a separate virtual machine.

Instead:

```text
Linux Host
    |
    +-- network namespace
           |
           +-- interfaces
           +-- routes
           +-- NAT
           +-- firewall
```

This makes Neutron routers lightweight.

A single host can host many logical routers.

---

# 11. Router Internal Interface

A conventional Neutron router may have an interface resembling:

```text
qr-xxxxxxxx
```

Think:

```text
qr = router internal side
```

Example:

```text
private-net
10.10.10.0/24
      |
      |
qr-xxxx
10.10.10.1
      |
+----------------+
| qrouter        |
+----------------+
```

The VM sees:

```text
10.10.10.1
```

as its default gateway.

---

# 12. Router External Interface

The router may also have an interface resembling:

```text
qg-xxxxxxxx
```

Think:

```text
qg = gateway/external side
```

Conceptually:

```text
+----------------+
| qrouter        |
+----------------+
      |
    qg-xxxx
      |
 external-net
      |
    br-ex
```

---

# 13. Complete Router Picture

```text
private-net
10.10.10.0/24
      |
      |
   qr-xxxx
      |
      v
+----------------------+
| qrouter namespace    |
|                      |
| routing table        |
| NAT                  |
| firewall rules       |
+----------------------+
      |
   qg-xxxx
      |
      v
external-net
      |
    br-ex
      |
physical network
```

---

# 14. Inside the Router

Eventually we can inspect a router directly.

First:

```bash
ip netns
```

Then:

```bash
ip netns exec qrouter-<UUID> ip addr
```

This shows the router interfaces.

---

Its routes:

```bash
ip netns exec qrouter-<UUID> ip route
```

might conceptually look like:

```text
10.10.10.0/24 dev qr-xxxx

default via 192.168.0.1 dev qg-xxxx
```

This is normal Linux routing.

---

# 15. OpenStack Routing Is Still Linux Routing

This is one of the most useful lessons.

Neutron sounds complicated because it contains many services.

But underneath, much of the networking is built from familiar Linux concepts:

```text
network namespaces

interfaces

bridges

routes

iptables/nftables

NAT

VXLAN

Open vSwitch
```

Neutron automates and coordinates those pieces.

---

# 16. Where Does a Router Run?

Imagine we create:

```text
router01
```

and all three nodes have an L3 agent:

```text
node1
node2
node3
```

Neutron can schedule the router to one of those agents.

For example:

```text
router01
    |
    v
node1
```

So:

```text
node1
└── qrouter-router01

node2
└── no active router01

node3
└── no active router01
```

in a simple non-HA centralized architecture.

---

# 17. But the VM Could Be on Another Node

Imagine:

```text
router01
    runs on node1

ubuntu01
    runs on node2
```

The VM still needs to use:

```text
router01
```

as its gateway.

How?

Overlay networking.

---

# 18. Node-to-Node Overlay

Simplified:

```text
NODE2

ubuntu01
   |
  TAP
   |
 br-int
   |
   |
   | VXLAN
   |
========================
   |
   |
 br-int
   |
qrouter
   |
NODE1
```

The logical network spans the two physical servers.

---

# 19. Why VXLAN Exists

Without an overlay, the VM network would have to exist physically everywhere.

VXLAN allows OpenStack to create logical Layer 2 networks on top of an existing IP network.

Conceptually:

```text
VM Ethernet frame
       |
       v
VXLAN encapsulation
       |
       v
normal IP network
       |
       v
other OpenStack host
```

---

# 20. Underlay vs Overlay

These two terms are useful.

## Underlay

The real physical network.

In our lab:

```text
192.168.0.0/24
```

with physical Ethernet interfaces and switches.

---

## Overlay

The logical network created on top of it.

Example:

```text
private-net
10.10.10.0/24
```

carried between nodes using something such as:

```text
VXLAN
```

---

# 21. Diagram

```text
OVERLAY

ubuntu01
10.10.10.25
      |
      +======================+
              VXLAN
      +======================+
                            |
                      Neutron Router
                      10.10.10.1


UNDERLAY

node2
192.168.0.201
      |
physical network
      |
node1
192.168.0.200
```

The overlay uses the underlay to transport packets.

---

# 22. VMware / NSX Mental Model

A rough comparison:

```text
OpenStack VXLAN
      ~
logical overlay networking
```

Similar conceptually to overlay networking used by NSX.

You have:

```text
logical network
      |
encapsulation
      |
physical transport network
```

The technologies and implementations differ, but the mental model is useful.

---

# 23. Packet Example

Suppose:

```text
ubuntu01
10.10.10.25
node2
```

runs:

```bash
ping 8.8.8.8
```

But:

```text
router01
```

is on:

```text
node1
```

The packet could conceptually travel:

```text
ubuntu01
   |
   v
TAP
   |
   v
br-int
node2
   |
   | VXLAN
   v
physical network
   |
   v
node1
   |
   v
br-int
   |
   v
qrouter-router01
   |
   v
br-ex
   |
   v
external network
```

---

# 24. Our Three-Node Architecture

Our Kolla inventory currently uses:

```text
node1 = control + network + compute

node2 = control + network + compute

node3 = control + network + compute
```

So conceptually:

```text
        OPENSTACK THREE-NODE LAB

NODE1             NODE2             NODE3

control           control           control
network           network           network
compute           compute           compute
```

Each node can participate in multiple roles.

---

# 25. Network Services on All Three Nodes

Because all three nodes are in the:

```ini
[network]
```

group, Kolla may deploy relevant Neutron network agents across those nodes.

Conceptually:

```text
NODE1
├── OVS
├── br-int
├── br-ex
└── Neutron agents

NODE2
├── OVS
├── br-int
├── br-ex
└── Neutron agents

NODE3
├── OVS
├── br-int
├── br-ex
└── Neutron agents
```

Exactly which agents run depends on the final Neutron configuration.

---

# 26. Important: Agent Exists vs Router Exists

Do not confuse:

```text
neutron-l3-agent exists on node2
```

with:

```text
router01 is actively hosted on node2
```

They are different statements.

The L3 agent is:

```text
capability
```

The router namespace is:

```text
specific router instance
```

---

# 27. Easy Analogy

Think:

```text
L3 Agent = ESXi host capable of running workload

Router Namespace = actual workload assigned there
```

Not technically equivalent, but useful as a placement analogy.

---

# 28. How Does Neutron Know Which Node Hosts the Router?

Neutron keeps track of router-to-agent scheduling.

Conceptually:

```text
router01
      |
      v
L3 Agent on node1
```

The control plane knows:

```text
router01 should be implemented on node1
```

The L3 agent on node1 builds and maintains the required Linux networking objects.

---

# 29. What Happens When the Router Configuration Changes?

Suppose we add an external gateway.

User:

```text
Set router01 gateway to external-net.
```

Conceptually:

```text
OpenStack CLI
      |
      v
Neutron API
      |
      v
neutron-server
      |
      v
L3 agent
      |
      v
modify qrouter namespace
```

The agent updates the Linux configuration.

---

# 30. What Happens When a Floating IP Is Added?

User associates:

```text
192.168.0.160
```

with:

```text
10.10.10.25
```

Conceptually:

```text
Neutron API
     |
     v
neutron-server
     |
     v
L3 agent
     |
     v
NAT/networking rules
```

The control plane describes the desired relationship.

The data plane implements it.

---

# 31. What Happens If node1 Dies?

Now we reach High Availability.

Suppose:

```text
router01
```

is only active on:

```text
node1
```

and node1 fails.

Without router HA, traffic using that router may be interrupted.

Conceptually:

```text
VM
 |
 v
router01 on node1
 |
 X   node1 died
 |
Internet
```

The router needs to be restored/rescheduled before connectivity returns.

---

# 32. Neutron Agent HA

Kolla has an option:

```yaml
enable_neutron_agent_ha: true
```

In the current Kolla-Ansible defaults, this is:

```yaml
false
```

unless explicitly enabled.

For our learning lab we will decide deliberately whether to enable it rather than changing it blindly.

---

# 33. Router HA Concept

With L3 HA, the logical router can have router instances on multiple nodes.

Conceptually:

```text
             router01

NODE1           NODE2           NODE3

qrouter         qrouter         qrouter
ACTIVE          BACKUP          BACKUP
```

Only the active instance handles the main routing role at that moment.

---

# 34. VRRP

The router instances coordinate using:

```text
VRRP
```

Very simplified:

```text
NODE1
router01
ACTIVE

       VRRP

NODE2
router01
BACKUP

       VRRP

NODE3
router01
BACKUP
```

If the active router disappears, another can take over.

---

# 35. Keepalived

Neutron can use:

```text
Keepalived
```

to implement VRRP-based router HA.

You have already seen Keepalived concepts before with an API VIP.

Same broad principle:

```text
multiple systems
       |
shared logical address/state
       |
one active
others standby
```

---

# 36. Router Failover

Before failure:

```text
node1
router01
ACTIVE

node2
router01
BACKUP
```

Then:

```text
node1 dies
```

Conceptually:

```text
node1                  node2

ACTIVE
  X
                       BACKUP
                          |
                          v
                       ACTIVE
```

Traffic can resume through node2.

---

# 37. API VIP HA vs Neutron Router HA

Do not confuse these.

Our OpenStack API VIP:

```text
192.168.0.100
```

is for OpenStack service APIs.

Conceptually:

```text
OpenStack client
      |
192.168.0.100
      |
HAProxy / Keepalived
      |
OpenStack APIs
```

---

Neutron Router HA is different.

It protects:

```text
VM network routing
```

Conceptually:

```text
VM
 |
Neutron router
 |
external network
```

So:

```text
API HA
!=
VM router HA
```

---

# 38. Two Different Keepalived Uses

Conceptually:

```text
Keepalived use #1

OpenStack API VIP
192.168.0.100
```

and:

```text
Keepalived use #2

Neutron L3 HA
router redundancy
```

Same underlying HA technology concept, different purpose.

---

# 39. What Is DVR?

DVR means:

```text
Distributed Virtual Routing
```

This changes how routing is distributed across the OpenStack environment.

---

# 40. Traditional Centralized Routing

Without DVR:

```text
VM on node2
      |
      v
br-int
      |
      | VXLAN
      v
node1
      |
Neutron Router
      |
br-ex
      |
Internet
```

Traffic may need to travel to the node hosting the centralized router.

---

# 41. Why Could That Be Inefficient?

Imagine:

```text
VM-A on node2

VM-B on node3
```

If routing is centralized, some traffic may need to travel through a network node.

Conceptually:

```text
node2
VM-A
 |
 |
 v
node1
router
 |
 |
 v
node3
VM-B
```

That can create:

```text
extra hops
central bottlenecks
larger failure domains
```

---

# 42. DVR Idea

DVR distributes routing functions closer to compute nodes.

Conceptually:

```text
NODE1
router components

NODE2
router components
    |
   VM

NODE3
router components
    |
   VM
```

This reduces dependence on one centralized router location for certain traffic flows.

---

# 43. Simplified DVR Traffic

Instead of:

```text
VM node2
   |
   v
router node1
   |
   v
VM node3
```

some routing can happen locally/distributed:

```text
VM node2
   |
distributed router functionality
   |
overlay
   |
VM node3
```

This can improve scalability.

---

# 44. But DVR Adds Complexity

DVR introduces additional concepts and components.

Examples include:

```text
distributed router namespaces

SNAT namespaces

router components on compute hosts

different L3 agent modes
```

So we are NOT starting with DVR.

---

# 45. Current Kolla Default

In the current Kolla configuration sample:

```yaml
enable_neutron_dvr: false
```

That is helpful for our learning lab.

We can first understand conventional centralized routing.

Later, DVR can become an advanced exercise.

---

# 46. Why Start Simple?

Our goal is:

```text
Understand first.

Optimize second.
```

Starting with:

```text
centralized router
+
OVS
+
VXLAN
```

makes it easier to observe:

```text
where router lives
where packet goes
where NAT happens
where br-ex connects
```

Then DVR will make much more sense later.

---

# 47. Centralized vs DVR

Simple comparison:

| Feature | Centralized L3 | DVR |
|---|---|---|
| Easy to understand | Better | More complex |
| Router concentrated on network nodes | Yes | Less |
| Distributed routing on computes | No | Yes |
| Good for learning | Excellent | Later |
| More components | Fewer | More |

For this homelab:

```text
Start centralized.
```

---

# 48. What About East-West Traffic?

Two common traffic directions:

```text
north-south
```

means:

```text
VM ↔ outside OpenStack
```

For example:

```text
VM → Internet
```

---

```text
east-west
```

means:

```text
VM ↔ VM
```

For example:

```text
VM-A → VM-B
```

inside the OpenStack cloud.

---

# 49. Same Network, Same Host

Imagine:

```text
VM-A
10.10.10.25

VM-B
10.10.10.26
```

both on node2 and both on:

```text
private-net
```

Conceptually:

```text
VM-A
 |
TAP
 |
br-int
 |
TAP
 |
VM-B
```

No router is required because they are on the same Layer 2 subnet.

---

# 50. Same Network, Different Hosts

Now:

```text
VM-A on node2

VM-B on node3
```

Same private network.

Conceptually:

```text
NODE2

VM-A
 |
br-int
 |
VXLAN
====================
 |
br-int
 |
VM-B

NODE3
```

Still no L3 router needed if they are in the same subnet.

The overlay extends the Layer 2 network between hosts.

---

# 51. Different Networks

Suppose:

```text
VM-A
10.10.10.25

VM-B
10.20.20.25
```

Now routing is required.

Conceptually:

```text
10.10.10.0/24
      |
      v
Neutron Router
      |
      v
10.20.20.0/24
```

This is Layer 3 traffic.

---

# 52. Router Namespace Routing Table

Inside the router:

```text
10.10.10.0/24
```

might connect through:

```text
qr-interface-A
```

and:

```text
10.20.20.0/24
```

through:

```text
qr-interface-B
```

Conceptually:

```text
        qrouter

10.10.10.1
    |
qr-A
    |
+----------------+
| routing table  |
+----------------+
    |
qr-B
    |
10.20.20.1
```

Again: normal routing concepts.

---

# 53. Where Is DHCP?

Neutron can also provide DHCP for tenant networks.

The DHCP agent may use another namespace.

You may see names similar to:

```text
qdhcp-<network-UUID>
```

This is separate from:

```text
qrouter-<router-UUID>
```

---

# 54. qrouter vs qdhcp

Memory:

```text
qrouter
    routing / NAT

qdhcp
    DHCP services
```

These are different network namespaces with different jobs.

---

# 55. Example

```text
private-net
10.10.10.0/24
```

Could have:

```text
qdhcp namespace
      |
      | gives VM:
      |
      +-- IP 10.10.10.25
      +-- gateway 10.10.10.1
      +-- DNS
```

while:

```text
qrouter namespace
      |
      | provides:
      |
      +-- gateway 10.10.10.1
      +-- routing
      +-- NAT
```

---

# 56. DHCP vs Router

Another memory shortcut:

```text
DHCP:
"What IP should I use?"

Router:
"Where should this packet go?"
```

Very different responsibilities.

---

# 57. Where Does br-ex Fit?

The router's external side needs access to the provider/external network.

That eventually reaches:

```text
br-ex
```

In our lab:

```text
qrouter
   |
 qg-xxxx
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

---

# 58. Why Every Network Node Has veth-ovs

Because all three nodes are currently:

```text
network nodes
```

we prepared:

```text
veth-ovs
```

on all three.

That gives each node a potential path between:

```text
Neutron external networking
```

and:

```text
physical home LAN
```

---

# 59. Future Two-NIC Design

Later our USB Ethernet adapters will simplify this.

Instead of:

```text
br-ex
 |
veth-ovs
 ||
veth-host
 |
br-mgmt
 |
enp0s31f6
```

we can eventually have:

```text
Management NIC
enp0s31f6
    |
192.168.0.20x
```

and separately:

```text
USB NIC
   |
 br-ex
   |
Neutron external network
```

That is cleaner.

---

# 60. One-NIC Design vs Two-NIC Design

Current learning design:

```text
ONE PHYSICAL NIC

management
+
external Neutron traffic

share physical interface through bridge/veth
```

Future:

```text
TWO PHYSICAL NICs

NIC1
management/control

NIC2
Neutron external traffic
```

The two-NIC design is easier to reason about operationally.

---

# 61. But the Single-NIC Design Is Valuable

The single-NIC design forced us to understand:

```text
Linux bridges

veth pairs

interface ownership

OVS external interface

Neutron external connectivity
```

That is useful learning.

---

# 62. Three-Node Packet Example

Suppose:

```text
ubuntu01
node2
10.10.10.25

router01
node1

Internet
outside OpenStack
```

Full conceptual path:

```text
NODE2

ubuntu01
   |
 TAP
   |
br-int
   |
VXLAN
   |
===========================
   |
NODE1
   |
br-int
   |
qrouter-router01
   |
NAT
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
   |
Internet
```

That diagram is worth remembering.

---

# 63. What Does the Neutron Server Manage?

The Neutron server keeps track of logical objects such as:

```text
networks

subnets

ports

routers

Floating IPs

security groups
```

It represents:

```text
desired networking state
```

---

# 64. What Do Agents Do?

Agents translate desired state into actual host configuration.

Conceptually:

```text
Neutron database:

"router01 exists"
       |
       v
Neutron agent:

"build Linux networking needed for router01"
```

This is an important infrastructure automation concept.

---

# 65. Desired State vs Actual State

This idea will appear everywhere in modern infrastructure.

```text
Desired state:
router01 should exist.

Actual state:
qrouter namespace and interfaces exist on node1.
```

Neutron tries to keep them aligned.

---

# 66. Similar Idea in Kubernetes

There is a loose conceptual similarity:

```text
Kubernetes:

API desired state
      |
controllers
      |
actual resources
```

Neutron:

```text
Neutron API desired state
      |
agents
      |
actual networking
```

Not the same architecture, but the desired-state concept is useful.

---

# 67. Why Agents Matter for Troubleshooting

Suppose Horizon shows:

```text
router01
ACTIVE
```

but packets do not flow.

We may investigate the actual node:

```text
Which L3 agent owns router01?

Does qrouter exist?

Does its route table look correct?

Does qg interface exist?

Can the namespace reach the gateway?

Is br-ex correct?
```

That moves troubleshooting from:

```text
"OpenStack networking is broken."
```

to:

```text
"Which layer is broken?"
```

Much better.

---

# 68. Troubleshooting Layers

A useful order:

```text
1. OpenStack object

2. Neutron agent

3. namespace

4. interfaces

5. routes

6. NAT

7. OVS bridges

8. overlay

9. physical network
```

Work from logical to physical.

---

# 69. Example Troubleshooting

VM cannot reach Internet.

First:

```text
Does VM have an IP?
```

Then:

```text
Does VM have correct gateway?
```

Then:

```text
Does router exist?
```

Then:

```text
Which node hosts router?
```

Then:

```text
Does qrouter namespace exist?
```

Then:

```text
Does router have correct route?
```

Then:

```text
Does external gateway work?
```

Then:

```text
Does br-ex reach the LAN?
```

This is much better than randomly restarting containers.

---

# 70. Commands We Will Use Later

Once OpenStack is deployed:

```bash
openstack router list
```

shows logical routers.

---

```bash
openstack network agent list
```

shows networking agents.

---

```bash
ip netns
```

shows Linux network namespaces.

---

```bash
ovs-vsctl show
```

shows OVS topology.

---

```bash
ip -br addr
```

shows Linux interfaces.

---

# 71. Inspect Router Namespace

Example:

```bash
ip netns exec qrouter-<UUID> ip addr
```

Then:

```bash
ip netns exec qrouter-<UUID> ip route
```

This is where the architecture becomes real.

---

# 72. Test Connectivity From Inside Router

We may later do something such as:

```bash
ip netns exec qrouter-<UUID> ping -c 3 192.168.0.1
```

This answers:

```text
Can the Neutron router itself reach the physical gateway?
```

Extremely useful troubleshooting test.

---

# 73. Why This Is Powerful

If:

```text
router namespace → gateway
```

works,

but:

```text
VM → Internet
```

doesn't,

we have narrowed the problem.

The issue is probably somewhere between:

```text
VM
and
router namespace
```

rather than external connectivity.

---

# 74. Networking Troubleshooting Is Path Troubleshooting

The packet has a path.

Our job is to find where it stops.

Example:

```text
VM
 ✅
 |
TAP
 ✅
 |
br-int
 ✅
 |
VXLAN
 ✅
 |
router
 ✅
 |
br-ex
 ❌
 |
LAN
```

Now we know where to investigate.

---

# 75. VMware Troubleshooting Mental Model

This is similar to checking:

```text
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
```

OpenStack has more visible layers, but the troubleshooting philosophy is the same:

```text
follow the packet
```

---

# 76. What I Want to Remember

The most important architecture:

```text
neutron-server
      |
      | CONTROL
      v
Neutron agents
      |
      | BUILD
      v
Linux / OVS networking
      |
      | FORWARDS
      v
actual VM packets
```

---

# 77. Router Memory Model

```text
qrouter
    = virtual router implemented in Linux namespace

qr-*
    = router internal interface

qg-*
    = router external gateway interface

qdhcp
    = DHCP namespace
```

---

# 78. Multi-Node Memory Model

```text
VM on node2
      |
    br-int
      |
    VXLAN
      |
    br-int
      |
router on node1
      |
    br-ex
      |
     LAN
```

---

# 79. HA Memory Model

Without HA:

```text
router01
   |
node1
   |
node1 dies
   |
routing interruption
```

With HA:

```text
router01

node1
ACTIVE

node2
BACKUP

node3
BACKUP
```

If node1 dies:

```text
node2
becomes ACTIVE
```

---

# 80. DVR Memory Model

Traditional:

```text
VM
 |
remote centralized router
 |
outside
```

DVR:

```text
routing functionality distributed closer to compute nodes
```

For this lab:

```text
Learn centralized first.

Study DVR later.
```

---

# 81. Final Cheat Sheet

```text
neutron-server
    = NETWORK CONTROL PLANE

neutron-l3-agent
    = L3 WORKER

qrouter
    = ACTUAL LINUX ROUTER ENVIRONMENT

qr-*
    = INTERNAL ROUTER SIDE

qg-*
    = EXTERNAL ROUTER SIDE

qdhcp
    = DHCP NAMESPACE

br-int
    = INTERNAL OVS SWITCHING

br-ex
    = EXTERNAL OVS BRIDGE

VXLAN
    = HOST-TO-HOST OVERLAY

VRRP
    = ROUTER HA ELECTION/FAILOVER

Keepalived
    = IMPLEMENTS HA/VRRP FUNCTIONS

DVR
    = DISTRIBUTED VIRTUAL ROUTING
```

---

# 82. One-Sentence Explanation

If someone asks:

> How does a Neutron router work?

A good answer is:

```text
Neutron's control plane tells L3 agents what logical routers should exist,
and the agents implement those routers using Linux networking constructs,
while OVS and overlay networking connect VMs and routers across physical hosts.
```

---

# 83. The Big Picture

```text
                         NEUTRON CONTROL PLANE

                         neutron-server
                               |
                               |
                +--------------+--------------+
                |              |              |
                v              v              v
            L3 Agent       OVS Agent      DHCP Agent


                         NETWORK DATA PLANE

 NODE1                     NODE2                     NODE3

+---------+               +---------+               +---------+
| br-int  |===============| br-int  |===============| br-int  |
|    |    |    VXLAN      |    |    |    VXLAN      |    |    |
| qrouter |               |   VMs   |               |   VMs   |
|    |    |               |         |               |         |
| br-ex   |               | br-ex   |               | br-ex   |
+----+----+               +----+----+               +----+----+
     |                         |                         |
     +-------------------------+-------------------------+
                               |
                            HOME LAN
```

That is the picture to carry into the Kolla deployment.

---

# 84. What Comes Next

After deployment we will stop talking hypothetically.

We will inspect the real environment:

```bash
openstack network agent list
```

then:

```bash
ip netns
```

then:

```bash
ovs-vsctl show
```

then enter the router itself:

```bash
ip netns exec qrouter-<UUID> ip addr
```

and:

```bash
ip netns exec qrouter-<UUID> ip route
```

At that point:

```text
diagram
```

becomes:

```text
actual Linux networking
```

and the concepts should become much easier to remember.
