# Neutron Packet Walk

This document follows actual network traffic through OpenStack.

Instead of memorizing Neutron component names, the goal is to understand:

```text
Where does the packet actually go?
```

We will follow two flows:

```text
1. VM → Internet
2. Laptop → Floating IP → VM
```

This ties together:

```text
Neutron
Open vSwitch
br-int
br-ex
Neutron Router
Floating IP
Fixed IP
SNAT
DNAT
Security Groups
TAP interfaces
VXLAN
veth-ovs
veth-host
br-mgmt
```

---

# 1. Lab Example

We will use this example throughout the document.

```text
OpenStack VM:
ubuntu01

VM Fixed IP:
10.10.10.25

VM Default Gateway:
10.10.10.1

Floating IP:
192.168.0.160

Laptop:
192.168.0.59

Home LAN:
192.168.0.0/24

Home Router:
192.168.0.1
```

Our physical OpenStack nodes use:

```text
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
```

---

# 2. Small Neutron Memory Model

Start with this:

```text
br-int = INSIDE OpenStack

br-ex = OUTSIDE OpenStack

Fixed IP = VM private IP

Floating IP = external NAT IP

Neutron Port = VM network attachment

Security Group = virtual firewall

SNAT = rewrite SOURCE

DNAT = rewrite DESTINATION
```

This is enough to understand most of the packet flow.

---

# 3. Current Single-NIC Host Design

Before OpenStack deployment, our physical network looks like this:

```text
                      HOME LAN
                         |
                    enp0s31f6
                         |
                      br-mgmt
                     /       \
              host IP        veth-host
                                ||
                                ||
                             veth-ovs
```

The management IP lives on:

```text
br-mgmt
```

not directly on:

```text
enp0s31f6
```

For example:

```text
node1
br-mgmt = 192.168.0.200
```

Kolla will later use:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "veth-ovs"
```

Conceptually:

```text
Neutron
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

This is why we created the veth pair.

---

# 4. Packet Walk 1 — VM to Internet

Imagine:

```text
ubuntu01
10.10.10.25/24
```

Inside the VM we run:

```bash
ping 8.8.8.8
```

The question is:

> How does the packet reach the Internet?

---

# 5. Step 1 — VM Checks Its Routing Table

The VM knows:

```text
My subnet:
10.10.10.0/24

My IP:
10.10.10.25

Destination:
8.8.8.8
```

Because:

```text
8.8.8.8
```

is not inside:

```text
10.10.10.0/24
```

the VM sends the traffic toward its default gateway:

```text
10.10.10.1
```

So:

```text
ubuntu01
10.10.10.25
     |
     v
10.10.10.1
```

This is normal IP routing.

OpenStack has not changed basic networking concepts.

---

# 6. Step 2 — VM Virtual NIC

Inside the VM, we might see:

```text
eth0
```

or another predictable Linux interface name.

Conceptually:

```text
ubuntu01
   |
 eth0
   |
virtual NIC
```

QEMU/libvirt connects this virtual NIC into the host networking stack.

---

# 7. TAP Interface

Outside the VM, Linux commonly uses a TAP-style interface to connect the VM to virtual networking.

Conceptually:

```text
ubuntu01
   |
 eth0
   |
virtual NIC
   |
 TAP
```

A TAP interface can be thought of as:

```text
virtual Ethernet cable from the VM into the host
```

VMware mental model:

```text
VM vNIC
   |
virtual switch port
```

---

# 8. Step 3 — br-int

The VM-side interface connects into:

```text
br-int
```

`br-int` means:

```text
integration bridge
```

A useful learning shortcut:

```text
br-int = OpenStack internal switching
```

So the path becomes:

```text
ubuntu01
   |
virtual NIC
   |
 TAP
   |
br-int
```

---

# 9. What Is Open vSwitch?

Open vSwitch is usually abbreviated:

```text
OVS
```

It is a programmable software switch.

Neutron can tell OVS how traffic should flow between:

```text
VM ports
logical networks
routers
tunnels
external networks
```

Think:

```text
OVS = virtual switching infrastructure
```

A rough VMware analogy is:

```text
vSwitch / Distributed Switch concepts
```

although OVS and VMware switching are not identical products.

---

# 10. Step 4 — Neutron Router

Our VM wants to reach its gateway:

```text
10.10.10.1
```

That gateway belongs to a Neutron Router.

Conceptually:

```text
              Neutron Router
          +--------------------+
          |                    |
private   |                    | external
10.10.10.1                    |
          +--------------------+
```

In the conventional Neutron L3 architecture, the router is often implemented using a Linux network namespace.

Later we may see:

```bash
ip netns
```

with entries similar to:

```text
qrouter-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

# 11. A Neutron Router Is Not a VM

This distinction is important.

The router is not necessarily:

```text
another virtual machine
```

It can be a Linux network namespace containing:

```text
interfaces
IP addresses
routing table
NAT rules
firewall rules
```

Conceptually:

```text
Physical Linux host
 |
 +-- qrouter-A
 |
 +-- qrouter-B
 |
 +-- qrouter-C
```

Each namespace can behave like an independent router.

---

# 12. Router Interfaces

You may later see interfaces with names resembling:

```text
qr-xxxxxxxx
qg-xxxxxxxx
```

A useful memory trick:

```text
qr = router internal side

qg = gateway/external side
```

Conceptually:

```text
private-net
10.10.10.0/24
     |
     |
 qr-xxxx
     |
+----------------+
| Neutron Router |
+----------------+
     |
 qg-xxxx
     |
external-net
192.168.0.0/24
```

Do not memorize the UUIDs.

Understand what the interfaces represent.

---

# 13. Linux Routing Still Applies

Inside the router namespace there is a normal Linux routing table.

Conceptually it might contain:

```text
10.10.10.0/24 → internal interface

default → external gateway
```

So when the router receives:

```text
destination = 8.8.8.8
```

it knows:

```text
This is not on my private network.

Use the external route.
```

Very similar to a physical router.

---

# 14. Step 5 — SNAT

The packet originally contains:

```text
SOURCE:
10.10.10.25

DESTINATION:
8.8.8.8
```

But the home LAN does not know how to route directly back to:

```text
10.10.10.25
```

because that is an OpenStack private address.

Neutron therefore performs Source NAT for ordinary outbound traffic.

Simplified:

```text
10.10.10.25
     |
     | SNAT
     v
external router address
```

Memory trick:

```text
SNAT

S = SOURCE
```

SNAT changes the source address.

---

# 15. Step 6 — br-ex

After routing and NAT, traffic enters:

```text
br-ex
```

A useful shortcut:

```text
br-int = internal

br-ex = external
```

So:

```text
VM
 |
br-int
 |
Neutron Router
 |
SNAT
 |
br-ex
```

Now we are approaching the physical network.

---

# 16. Step 7 — veth-ovs

Our Kolla configuration says:

```yaml
neutron_external_interface: "veth-ovs"
```

So conceptually:

```text
br-ex
  |
veth-ovs
```

The other end is:

```text
veth-host
```

Together:

```text
veth-ovs
   ||
veth-host
```

A veth pair behaves roughly like a virtual Ethernet cable.

Whatever enters one side can exit the other.

---

# 17. Step 8 — br-mgmt

`veth-host` belongs to:

```text
br-mgmt
```

So:

```text
br-ex
  |
veth-ovs
  ||
veth-host
  |
br-mgmt
```

The physical interface:

```text
enp0s31f6
```

is also connected to:

```text
br-mgmt
```

Therefore traffic can reach the physical LAN.

---

# 18. Full Outbound Path

The complete simplified path is:

```text
ubuntu01
10.10.10.25
     |
     | ping 8.8.8.8
     v
   eth0
     |
virtual NIC
     |
    TAP
     |
   br-int
     |
     v
Neutron Router
10.10.10.1
     |
     | SNAT
     v
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
Home Router
192.168.0.1
     |
 Internet
     |
 8.8.8.8
```

This is called:

```text
north-south traffic
```

because traffic is moving between:

```text
OpenStack cloud
     ↕
external world
```

---

# 19. Floating IP Is Not Required for Normal Outbound Traffic

This is important.

The VM does not necessarily need a Floating IP just to do:

```bash
ping 8.8.8.8
```

or:

```bash
apt update
```

The Neutron Router can provide outbound SNAT.

Simplified:

```text
VM private IP
     |
    SNAT
     |
external network
     |
Internet
```

Floating IPs become especially important when an external machine must initiate traffic toward a specific VM.

---

# 20. Packet Walk 2 — Laptop to VM

Now reverse the direction.

Our laptop is:

```text
192.168.0.59
```

Our VM has:

```text
Fixed IP:
10.10.10.25
```

And OpenStack assigns it:

```text
Floating IP:
192.168.0.160
```

From the laptop:

```bash
ssh ubuntu@192.168.0.160
```

How does OpenStack deliver that connection to:

```text
10.10.10.25
```

?

---

# 21. What Is a Floating IP?

The VM still has its private address:

```text
10.10.10.25
```

OpenStack creates a mapping:

```text
192.168.0.160
      |
      v
10.10.10.25
```

A Floating IP therefore acts as an externally reachable address associated with a VM's Neutron port/fixed IP.

---

# 22. Floating IP Is Not Normally Configured Inside the VM

Inside:

```text
ubuntu01
```

running:

```bash
ip addr
```

will normally show:

```text
10.10.10.25
```

It will not normally show:

```text
192.168.0.160
```

as another interface address.

Why?

Because the Floating IP mapping exists in the Neutron networking layer.

Conceptually:

```text
192.168.0.160
      |
     NAT
      |
10.10.10.25
```

The guest VM does not need to know the Floating IP exists.

---

# 23. Incoming Packet

Laptop sends:

```text
SOURCE:
192.168.0.59

DESTINATION:
192.168.0.160

PROTOCOL:
TCP

DESTINATION PORT:
22
```

The packet enters the home LAN.

---

# 24. Incoming Physical Path

The packet reaches the OpenStack external networking path:

```text
Home LAN
   |
enp0s31f6
   |
br-mgmt
   |
veth-host
   ||
veth-ovs
   |
br-ex
```

Now Neutron can process the packet.

---

# 25. DNAT

Neutron knows the mapping:

```text
192.168.0.160
      |
      v
10.10.10.25
```

It rewrites the destination.

Before:

```text
DESTINATION:
192.168.0.160
```

After:

```text
DESTINATION:
10.10.10.25
```

This is:

```text
DNAT
```

Memory trick:

```text
D = DESTINATION
```

---

# 26. SNAT vs DNAT

Useful first mental model:

```text
SNAT
    changes SOURCE

DNAT
    changes DESTINATION
```

Typical lab use:

```text
VM → Internet
    SNAT

Laptop → Floating IP → VM
    DNAT
```

This is simplified but very useful for understanding the architecture.

---

# 27. What Is a Neutron Port?

A Neutron Port represents a network attachment.

For a VM, it can contain information such as:

```text
MAC address
fixed IP address
logical network
security groups
device owner
VM association
```

Example:

```text
Neutron Port
├── Network: private-net
├── Fixed IP: 10.10.10.25
├── MAC: fa:16:3e:xx:xx:xx
├── Security Group: default
└── Device: ubuntu01
```

A Floating IP is associated with a specific fixed IP / Neutron port.

---

# 28. Security Groups

Correct routing does not automatically mean traffic is allowed.

OpenStack Security Groups apply firewall policy to VM networking.

For SSH, we might allow:

```text
Direction:
Ingress

Protocol:
TCP

Port:
22

Source:
192.168.0.0/24
```

If the rule does not exist:

```text
Floating IP      OK
DNAT             OK
Routing          OK
VM               Running
SSH              BLOCKED
```

So when troubleshooting OpenStack networking:

```text
Do not immediately blame routing.
```

Always check Security Groups too.

---

# 29. Incoming Packet Reaches the VM Network

After DNAT:

```text
destination = 10.10.10.25
```

The router knows:

```text
10.10.10.0/24
```

belongs to the private network.

So traffic proceeds toward:

```text
br-int
```

Conceptually:

```text
br-ex
  |
Neutron Router
  |
DNAT
  |
br-int
```

---

# 30. Same-Host VM

If the router and VM networking endpoint are on the same physical host, the simplified path is:

```text
Neutron Router
      |
    br-int
      |
     TAP
      |
 ubuntu01
```

---

# 31. VM on Another OpenStack Node

Now suppose:

```text
Router:
node1

VM:
node2
```

The private logical network must span both machines.

Simplified:

```text
NODE1

Neutron Router
      |
    br-int
      |
      | VXLAN / overlay
      |
============================

NODE2
      |
    br-int
      |
     TAP
      |
 ubuntu01
```

The packet travels across the physical network while remaining part of the same logical Neutron network.

---

# 32. What Is VXLAN?

VXLAN is an overlay networking technology.

Very simplified:

```text
original VM Ethernet frame

        ↓

wrapped inside another packet

        ↓

sent between physical hosts
```

Conceptually:

```text
+---------------------------------------+
| Physical network packet               |
|                                       |
| node2 -----------------------> node1  |
|                                       |
|   +-------------------------------+   |
|   | VXLAN                         |   |
|   |                               |   |
|   | original VM network packet    |   |
|   +-------------------------------+   |
+---------------------------------------+
```

The physical LAN transports the outer packet.

The VM only sees its logical OpenStack network.

---

# 33. VMware / NSX Mental Model

If you have seen NSX overlays, this idea should feel somewhat familiar:

```text
logical tenant network
       |
encapsulation
       |
physical underlay network
```

The implementation is different, but the concept of overlay networking is similar.

---

# 34. Full Inbound Path

The complete simplified path:

```text
Laptop
192.168.0.59
     |
     | SSH 192.168.0.160
     v
Home LAN
     |
enp0s31f6
     |
 br-mgmt
     |
 veth-host
     ||
 veth-ovs
     |
   br-ex
     |
Floating IP
192.168.0.160
     |
     | DNAT
     v
Neutron Router
     |
10.10.10.25
     |
Security Group
     |
   br-int
     |
 VXLAN
(if VM is remote)
     |
   br-int
     |
    TAP
     |
 ubuntu01
10.10.10.25
```

---

# 35. Return Traffic

The VM replies:

```text
SOURCE:
10.10.10.25

DESTINATION:
192.168.0.59
```

Neutron maintains the NAT relationship.

Conceptually:

```text
10.10.10.25
      |
      v
Neutron
      |
      v
192.168.0.160
      |
      v
Laptop
```

From the laptop's perspective, it is communicating with:

```text
192.168.0.160
```

The laptop does not need to know that:

```text
10.10.10.25
```

exists.

---

# 36. Three Different IP Types

This distinction is extremely important.

## Host Management IP

Examples:

```text
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
```

Purpose:

```text
manage OpenStack physical nodes
SSH
Ansible
OpenStack control traffic
```

---

## VM Fixed IP

Example:

```text
ubuntu01 = 10.10.10.25
```

Purpose:

```text
VM address inside Neutron private network
```

---

## Floating IP

Example:

```text
192.168.0.160
```

Purpose:

```text
external NAT address used to reach a VM
```

So:

```text
Host management:
192.168.0.200

VM internal:
10.10.10.25

VM external:
192.168.0.160
```

Different jobs.

---

# 37. Control Plane vs Data Plane

This distinction becomes very useful later.

## Control Plane

The control plane decides:

```text
What should the network look like?
```

Examples:

```text
Neutron Server
RabbitMQ
Neutron Agents
```

Commands might represent:

```text
create network

create router

create port

associate Floating IP

configure security rule
```

---

## Data Plane

The data plane actually moves packets.

Examples:

```text
TAP
OVS
br-int
VXLAN
Neutron Router
br-ex
physical NIC
```

Very important:

```text
VM packets do NOT travel through RabbitMQ.
```

RabbitMQ helps coordinate services.

The actual packet flows through networking interfaces and switches.

---

# 38. Quick Diagram

```text
CONTROL PLANE

Neutron Server
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
Router
 |
br-ex
 |
NIC
 |
LAN
```

---

# 39. br-int vs br-ex

If you remember only two OVS bridge names:

```text
br-int
```

means:

```text
inside OpenStack
```

and:

```text
br-ex
```

means:

```text
toward external/provider network
```

Memory:

```text
INT = internal

EX = external
```

---

# 40. VMware-Oriented Mental Model

A simplified comparison:

```text
OpenStack

VM
 |
TAP
 |
br-int
 |
virtual router
 |
br-ex
 |
physical uplink
```

Rough VMware mental picture:

```text
VM
 |
vNIC
 |
virtual switch
 |
virtual router / edge
 |
uplink
 |
physical network
```

Not exact, but useful.

---

# 41. Common Troubleshooting Questions

If:

```text
VM cannot reach Internet
```

check:

```text
Does VM have correct fixed IP?

Does VM have correct default gateway?

Does Neutron router exist?

Is router external gateway configured?

Is external network correct?

Is br-ex connected correctly?

Is veth-ovs UP?

Does the host reach the physical LAN?

Are NAT rules present?
```

---

If:

```text
Laptop cannot SSH to Floating IP
```

check:

```text
Does Floating IP exist?

Is it associated with correct Neutron port?

Does Security Group allow TCP/22?

Is SSH running inside VM?

Does VM have correct default route?

Does Neutron router have external connectivity?

Is br-ex connected to the external interface?
```

---

# 42. Commands We Will Use After Deployment

Once OpenStack is actually running, useful commands include:

```bash
ip netns
```

to see network namespaces.

---

```bash
ovs-vsctl show
```

to inspect Open vSwitch.

---

```bash
ip -br addr
```

to inspect interfaces.

---

```bash
ip route
```

to inspect Linux routing.

---

Inside a router namespace:

```bash
ip netns exec qrouter-<UUID> ip addr
```

and:

```bash
ip netns exec qrouter-<UUID> ip route
```

Later we can inspect NAT/firewall rules too.

---

# 43. The Goal After Deployment

After Kolla deploys Neutron, we should compare:

```text
THEORY
```

from this document against:

```text
REAL LINUX NETWORK STATE
```

For example:

```text
Does br-int really exist?

Does br-ex really exist?

Where is veth-ovs attached?

Which qrouter namespace exists?

What IP does the router have?

Which node hosts the router?

What VXLAN interfaces exist?
```

That is where the theory becomes permanent knowledge.

---

# 44. Review Cheat Sheet

```text
Neutron
    networking service

OVS
    software switch

br-int
    internal OpenStack switching

br-ex
    external network bridge

TAP
    VM-to-host virtual cable

Neutron Port
    network attachment

Fixed IP
    VM private IP

Floating IP
    external NAT IP

Security Group
    VM firewall policy

SNAT
    rewrite source

DNAT
    rewrite destination

VXLAN
    overlay between OpenStack hosts
```

---

# 45. Outbound Memory Path

```text
VM
 ↓
TAP
 ↓
br-int
 ↓
Neutron Router
 ↓
SNAT
 ↓
br-ex
 ↓
veth-ovs
 ↓
veth-host
 ↓
br-mgmt
 ↓
physical NIC
 ↓
LAN
 ↓
Internet
```

---

# 46. Inbound Memory Path

```text
Laptop
 ↓
Floating IP
 ↓
br-ex
 ↓
DNAT
 ↓
Neutron Router
 ↓
Security Group
 ↓
br-int
 ↓
TAP
 ↓
VM Fixed IP
```

---

# 47. Final Memory Hook

```text
br-int = INSIDE

br-ex = OUTSIDE

Fixed IP = PRIVATE VM ADDRESS

Floating IP = EXTERNAL NAT ADDRESS

SNAT = SOURCE

DNAT = DESTINATION

Security Group = FIREWALL

VXLAN = TUNNEL BETWEEN HOSTS
```

Do not try to memorize every interface name.

The important part is understanding the direction of the packet and which component is responsible for each step.
