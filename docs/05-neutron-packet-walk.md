# Neutron Packet Walk

This chapter follows actual network traffic through the OpenStack homelab.

The goal is not to memorize every Neutron component.

The goal is to answer one question:

```text
Where does the packet actually go?
```

We will follow several important traffic flows:

```text
1. VM → Internet
2. Laptop → Floating IP → VM
3. VM → VM on the same Neutron network
4. VM → VM across different OpenStack hosts
```

This chapter ties together:

```text
Neutron
Open vSwitch
br-int
br-ex
br-tun
TAP interfaces
Neutron routers
Linux network namespaces
Fixed IPs
Floating IPs
Security Groups
SNAT
DNAT
VXLAN
ext0
br-mgmt
```

---

# 1. Important Lab Evolution

This lab has used two different physical external-network designs.

The Neutron concepts remained mostly the same.

What changed was how:

```text
br-ex
```

reached the physical LAN.

## Original single-NIC design

The original lab used:

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
  |
physical LAN
```

Kolla-Ansible used:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "veth-ovs"
```

This architecture is intentionally preserved as a learning exercise in:

```text
docs/03-openstack-single-nic-networking.md
```

## Current dual-NIC design

The lab was later upgraded with a dedicated external NIC.

The current external path is:

```text
br-ex
  |
ext0
  |
physical LAN
```

Kolla-Ansible now uses:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "ext0"
```

Management and OpenStack control traffic remain on:

```text
br-mgmt
   |
enp0s31f6
```

The physical migration is documented in:

```text
docs/17-openstack-dual-nic-networking.md
```

The important lesson is:

```text
The logical Neutron packet flow did not fundamentally change.

Only the physical uplink behind br-ex changed.
```

---

# 2. Current Host Network Model

Each OpenStack node currently looks approximately like:

```text
                         OpenStack Node

          MANAGEMENT / CONTROL / VXLAN

                     br-mgmt
                        |
                   enp0s31f6
                        |
                        |
                    HOME LAN


                    NEUTRON EXTERNAL

                       br-ex
                        |
                       ext0
                        |
                        |
                    HOME LAN
```

Management addresses:

```text
node1 br-mgmt = 192.168.0.200/24
node2 br-mgmt = 192.168.0.201/24
node3 br-mgmt = 192.168.0.202/24
```

OpenStack API VIP:

```text
192.168.0.100
```

The dedicated Neutron external interface:

```text
ext0
```

does not need its own host IP address.

It operates as a Layer-2 uplink for Open vSwitch.

---

# 3. Small Neutron Memory Model

Start with this:

```text
br-int
    = inside OpenStack

br-ex
    = toward external/provider network

br-tun
    = tunnel/overlay switching

Fixed IP
    = VM private IP

Floating IP
    = external NAT address

Neutron Port
    = logical network attachment

Security Group
    = VM network firewall policy

SNAT
    = rewrite source address

DNAT
    = rewrite destination address

VXLAN
    = overlay between OpenStack hosts
```

That is enough to understand most packet paths.

---

# 4. Control Plane vs Data Plane

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
attach subnet
create port
associate Floating IP
create Security Group rule
```

Components include:

```text
Neutron API
neutron-server
RabbitMQ
Neutron agents
database
```

## Data Plane

The data plane moves the actual packets.

Examples:

```text
VM vNIC
TAP interface
Open vSwitch
br-int
br-tun
VXLAN
router namespace
br-ex
ext0
physical LAN
```

Very important:

```text
VM packets do NOT travel through RabbitMQ.
```

RabbitMQ carries control-plane messages between OpenStack services.

The actual VM packet travels through Linux and Open vSwitch networking.

---

# 5. Example VM

For learning, imagine a VM with:

```text
Name:
demo-vm

Private network:
10.20.0.0/24

Fixed IP:
10.20.0.25

Default gateway:
10.20.0.1

Floating IP:
192.168.0.160
```

The exact addresses are examples.

The concepts are the important part.

---

# 6. What Is a Neutron Port?

A Neutron port represents a network attachment.

A VM port can contain information such as:

```text
MAC address
fixed IP
network
security groups
device ID
binding host
```

Conceptually:

```text
demo-vm
   |
   |
Neutron Port
   |
   +-- MAC
   +-- Fixed IP
   +-- Security Groups
   +-- Network
```

From Hermes, inspect a VM's ports with:

```bash
openstack port list --server <server-name-or-UUID>
```

Example:

```bash
openstack port list --server demo-vm
```

Then inspect a specific port:

```bash
openstack port show <port-UUID>
```

---

# 7. VM Virtual NIC and TAP Interface

Inside the VM we normally see an interface such as:

```text
eth0
```

or another Linux predictable interface name.

Conceptually:

```text
VM
 |
eth0
 |
virtual NIC
 |
TAP
```

The TAP-style interface connects the virtual machine into the host networking stack.

VMware mental model:

```text
VM vNIC
   |
virtual switch port
```

The technologies are different, but the mental model is useful.

---

# 8. br-int — Integration Bridge

The VM-side networking connects into:

```text
br-int
```

`br-int` means:

```text
integration bridge
```

A useful memory hook:

```text
br-int = inside OpenStack
```

Simplified:

```text
VM
 |
TAP
 |
br-int
```

Many OpenStack logical networks meet at `br-int`.

Neutron and the OVS agent install the switching state needed to keep those logical networks isolated.

---

# 9. Open vSwitch

Open vSwitch is usually abbreviated:

```text
OVS
```

Think of OVS as programmable virtual switching infrastructure.

It connects things such as:

```text
VM ports
tenant networks
router interfaces
overlay tunnels
provider networks
external networks
```

A rough VMware comparison is:

```text
vSwitch / Distributed Switch concepts
```

but OVS is not VMware vSphere networking.

---

# 10. br-tun and VXLAN

When a Neutron tenant network spans multiple physical OpenStack nodes, traffic must cross the physical network.

In the ML2/OVS model this commonly involves:

```text
br-int
   |
patch port
   |
br-tun
   |
VXLAN tunnel
   |
physical underlay
```

Conceptually:

```text
NODE2

VM
 |
TAP
 |
br-int
 |
br-tun
 |
VXLAN
 |
================ PHYSICAL NETWORK ================
 |
VXLAN
 |
br-tun
 |
br-int

NODE1
```

Do not worry about memorizing every OVS patch-port name.

Remember:

```text
br-int = logical VM switching

br-tun = overlay/tunnel switching
```

---

# 11. Underlay vs Overlay

These terms are worth learning.

## Underlay

The real physical network.

In this lab:

```text
192.168.0.0/24
```

The physical underlay connects:

```text
node1
node2
node3
Hermes
home router
```

## Overlay

The logical tenant network built on top of the underlay.

Example:

```text
10.20.0.0/24
```

VXLAN allows this logical Layer-2 network to span multiple OpenStack hosts.

Memory:

```text
UNDERLAY = physical transport

OVERLAY = virtual tenant network
```

---

# 12. Neutron Router

Suppose our VM has:

```text
10.20.0.25
```

and its gateway is:

```text
10.20.0.1
```

That gateway belongs to a Neutron router.

Conceptually:

```text
private network
10.20.0.0/24
      |
      |
   10.20.0.1
      |
+----------------+
| Neutron Router |
+----------------+
      |
      |
external network
```

In the conventional Neutron L3-agent architecture used for this learning lab, routers are implemented using Linux networking constructs.

---

# 13. Router Namespace

A Neutron router commonly appears as a Linux network namespace:

```text
qrouter-<UUID>
```

Think:

```text
qrouter
    =
small isolated Linux networking environment
```

It can have its own:

```text
interfaces
IP addresses
routing table
ARP/neighbour table
NAT rules
firewall state
```

The router is not another full virtual machine.

---

# 14. qr and qg Interfaces

Inside a router namespace you may see interfaces resembling:

```text
qr-xxxxxxxx
qg-xxxxxxxx
```

Memory:

```text
qr
    = router internal side

qg
    = router gateway/external side
```

Conceptually:

```text
private-net
     |
 qr-xxxx
     |
+----------------+
| qrouter        |
|                |
| routing + NAT  |
+----------------+
     |
 qg-xxxx
     |
external-net
```

---

# 15. Find the Router From Hermes

Run on **Hermes**, with OpenStack credentials loaded:

```bash
openstack router list
```

Inspect one:

```bash
openstack router show <router-name-or-UUID>
```

Show its Neutron ports:

```bash
openstack port list --router <router-name-or-UUID>
```

These ports help reveal the router's internal and external attachments.

---

# 16. Find Which Node Hosts the Router

From Hermes:

```bash
openstack network agent list --agent-type l3
```

To find the L3 agent hosting a specific router:

```bash
openstack network agent list \
  --router <router-name-or-UUID>
```

This is extremely useful.

Instead of guessing:

```text
Which node owns the qrouter namespace?
```

we ask Neutron.

Example conceptual result:

```text
Router:
router01

Hosted by:
L3 agent on node2
```

Then inspect networking on:

```text
node2
```

---

# 17. Inspect Network Namespaces

Run this on the physical OpenStack node hosting the router:

```bash
sudo ip netns
```

You may see entries such as:

```text
qrouter-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

qdhcp-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Memory:

```text
qrouter
    = routing / NAT

qdhcp
    = DHCP service
```

---

# 18. Inspect the Router Directly

Once you know the router UUID:

```bash
sudo ip netns exec qrouter-<UUID> ip -br addr
```

Inspect routes:

```bash
sudo ip netns exec qrouter-<UUID> ip route
```

Inspect neighbours:

```bash
sudo ip netns exec qrouter-<UUID> ip neigh
```

This is where Neutron stops being abstract.

You are looking at:

```text
a real Linux networking environment
```

created and maintained by OpenStack.

---

# 19. Packet Walk 1 — VM to Internet

Now follow an outbound packet.

Inside the VM:

```bash
ping 8.8.8.8
```

The VM sees:

```text
My address:
10.20.0.25

My subnet:
10.20.0.0/24

Destination:
8.8.8.8
```

Because:

```text
8.8.8.8
```

is outside the local subnet, the VM sends the packet to its default gateway:

```text
10.20.0.1
```

So the first part is ordinary IP routing:

```text
VM
10.20.0.25
     |
     v
10.20.0.1
Neutron Router
```

---

# 20. VM to Router — Same Host

If the VM networking endpoint and router are on the same physical host, the simplified path is:

```text
VM
 |
TAP
 |
br-int
 |
router internal interface
 |
qrouter
```

---

# 21. VM to Router — Different Hosts

Suppose:

```text
VM:
node2

Router:
node1
```

The logical network must cross the physical hosts.

Simplified:

```text
NODE2

VM
 |
TAP
 |
br-int
 |
br-tun
 |
VXLAN
 |
===============================
 |
VXLAN
 |
br-tun
 |
br-int
 |
qrouter

NODE1
```

The physical network carries the encapsulated VXLAN packet.

The VM still believes it is connected to its normal private Ethernet network.

---

# 22. SNAT

The packet begins as:

```text
SOURCE:
10.20.0.25

DESTINATION:
8.8.8.8
```

The home network does not have a route back to:

```text
10.20.0.25
```

Neutron therefore uses Source NAT for ordinary outbound traffic.

Simplified:

```text
10.20.0.25
     |
     | SNAT
     v
router external address
```

Memory:

```text
SNAT

S = SOURCE
```

SNAT changes the source address.

---

# 23. br-ex — External Bridge

After routing/NAT, the packet needs to reach the external/provider network.

This involves:

```text
br-ex
```

Memory:

```text
br-int = INSIDE

br-ex = EXTERNAL
```

Simplified:

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

---

# 24. OVS Patch Ports Between Bridges

The real OVS topology may contain patch ports connecting internal and external switching.

On this lab, `br-ex` has been observed with ports such as:

```text
ext0
phy-br-ex
```

Important:

```text
phy-br-ex
```

is not another physical Ethernet adapter.

It is part of the OVS bridge-to-bridge connectivity.

Conceptually:

```text
br-int
   |
OVS patch connection
   |
br-ex
   |
ext0
```

This is why:

```text
ovs-vsctl list-ports br-ex
```

may show more than just the physical uplink.

---

# 25. Current External Uplink

The current physical external path is:

```text
br-ex
  |
ext0
  |
Home LAN
```

`ext0` is dedicated to Neutron external/provider traffic.

It does not carry the node management IP.

Management remains:

```text
br-mgmt
   |
enp0s31f6
```

---

# 26. Complete Outbound Path

The simplified current path is:

```text
VM
10.20.0.25
     |
     v
VM vNIC
     |
    TAP
     |
   br-int
     |
     | VXLAN if router is remote
     |
Neutron Router
10.20.0.1
     |
     | SNAT
     v
   br-ex
     |
    ext0
     |
Home LAN
     |
Home Router
192.168.0.1
     |
Internet
     |
8.8.8.8
```

This is:

```text
north-south traffic
```

because it travels between:

```text
OpenStack
    ↕
outside network
```

---

# 27. Original Outbound Path

Before the dual-NIC upgrade, only the bottom of the path was different:

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
  |
Home LAN
```

Compare that with today:

```text
br-ex
  |
ext0
  |
Home LAN
```

The logical Neutron concepts above `br-ex` remain the same.

This is why Chapter 03 and Chapter 17 can both be useful learning material without conflicting.

---

# 28. Floating IP Is Not Required for Normal Outbound Traffic

A VM does not normally require a Floating IP simply to initiate connections such as:

```bash
ping 8.8.8.8
```

or:

```bash
apt update
```

The Neutron router can provide outbound SNAT.

Simplified:

```text
VM fixed IP
    |
   SNAT
    |
external network
    |
Internet
```

A Floating IP is especially important when an external system must initiate traffic toward a specific VM.

---

# 29. What Is a Floating IP?

Suppose:

```text
VM Fixed IP:
10.20.0.25

Floating IP:
192.168.0.160
```

Neutron creates a relationship between them:

```text
192.168.0.160
      |
      | NAT
      v
10.20.0.25
```

The Floating IP belongs to the Neutron networking layer.

It is not normally configured as another IP inside the guest operating system.

---

# 30. Inspect Floating IPs From Hermes

List Floating IPs:

```bash
openstack floating ip list
```

Inspect one:

```bash
openstack floating ip show 192.168.0.160
```

This can reveal information such as:

```text
Floating IP
Fixed IP
Port
Router
Status
```

Then inspect the associated port:

```bash
openstack port show <port-UUID>
```

This is one of the fastest ways to map:

```text
Floating IP
    ↓
Neutron port
    ↓
Fixed IP
    ↓
VM
```

---

# 31. Packet Walk 2 — Laptop to Floating IP

Suppose the laptop sends:

```bash
ssh user@192.168.0.160
```

The packet begins as:

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

With the current dual-NIC architecture, the physical entry path is:

```text
Laptop
   |
Home LAN
   |
ext0
   |
br-ex
```

Neutron can then process the Floating IP mapping.

---

# 32. DNAT

Neutron knows:

```text
192.168.0.160
      |
      v
10.20.0.25
```

Conceptually the destination is rewritten:

```text
Before:

DESTINATION = 192.168.0.160


After:

DESTINATION = 10.20.0.25
```

This is:

```text
DNAT
```

Memory:

```text
D = DESTINATION
```

---

# 33. Security Groups

Correct routing does not automatically mean traffic is allowed.

Security Groups provide network policy around VM ports.

For SSH we might allow:

```text
Direction:
Ingress

Protocol:
TCP

Port:
22
```

If the rule does not allow the traffic, you can have:

```text
Floating IP        correct
Router             correct
DNAT               correct
VM                 ACTIVE
Network path       correct

SSH                BLOCKED
```

Therefore:

```text
Do not immediately blame routing.
```

Inspect Security Groups too.

From Hermes:

```bash
openstack security group list
```

Show one:

```bash
openstack security group show <security-group>
```

List its rules:

```bash
openstack security group rule list <security-group>
```

---

# 34. Complete Inbound Path

Simplified current path:

```text
Laptop
192.168.0.59
     |
     | SSH to 192.168.0.160
     v
Home LAN
     |
    ext0
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
10.20.0.25
     |
   br-int
     |
     | VXLAN if VM is remote
     |
   br-int
     |
    TAP
     |
VM
10.20.0.25
```

Security Group policy is also enforced on the VM network path.

The exact low-level implementation can depend on Neutron/OVS firewall configuration, so the important learning point is:

```text
routing can be correct while security policy still blocks traffic
```

---

# 35. Return Traffic

The VM replies:

```text
SOURCE:
10.20.0.25

DESTINATION:
192.168.0.59
```

Neutron maintains the NAT relationship.

Conceptually:

```text
10.20.0.25
      |
      v
Neutron NAT
      |
      v
192.168.0.160
      |
      v
Laptop
```

From the laptop's perspective it is communicating with:

```text
192.168.0.160
```

The laptop does not need a route to:

```text
10.20.0.25
```

---

# 36. SNAT vs DNAT

Simple memory model:

```text
SNAT
    changes SOURCE

DNAT
    changes DESTINATION
```

Typical examples:

```text
VM → Internet
    SNAT

Laptop → Floating IP → VM
    DNAT
```

This is simplified but extremely useful.

---

# 37. Three Important IP Types

Do not mix these up.

## Host management IP

Examples:

```text
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
```

Purpose:

```text
SSH
Ansible
Kolla-Ansible
OpenStack management/control traffic
VXLAN underlay in this lab
```

## VM Fixed IP

Example:

```text
10.20.0.25
```

Purpose:

```text
VM address inside a Neutron tenant/private network
```

## Floating IP

Example:

```text
192.168.0.160
```

Purpose:

```text
externally reachable NAT address associated with a VM port
```

Memory:

```text
Host:
192.168.0.200

VM inside OpenStack:
10.20.0.25

VM reachable from LAN:
192.168.0.160
```

---

# 38. Packet Walk 3 — VM to VM on Same Network

Imagine:

```text
VM-A
10.20.0.25

VM-B
10.20.0.26
```

Both belong to:

```text
10.20.0.0/24
```

No Layer-3 router is required simply because they are in the same IP subnet.

## Same physical host

Simplified:

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

This is east-west traffic.

---

# 39. Same Network Across Different Hosts

Suppose:

```text
VM-A:
node2

VM-B:
node3
```

but both belong to the same Neutron network.

Conceptually:

```text
NODE2

VM-A
 |
TAP
 |
br-int
 |
br-tun
 |
VXLAN
 |
===============================
 |
VXLAN
 |
br-tun
 |
br-int
 |
TAP
 |
VM-B

NODE3
```

The overlay extends the logical Layer-2 network across the physical hosts.

---

# 40. Different Tenant Networks

Suppose:

```text
VM-A:
10.10.10.25/24

VM-B:
10.20.0.25/24
```

Now Layer-3 routing is required.

Conceptually:

```text
10.10.10.0/24
      |
      v
Neutron Router
      |
      v
10.20.0.0/24
```

This is ordinary routing implemented by Neutron.

---

# 41. DHCP Namespace

Neutron can also provide DHCP for tenant networks.

You may see:

```text
qdhcp-<network-UUID>
```

Memory:

```text
qdhcp
    = DHCP namespace

qrouter
    = routing/NAT namespace
```

DHCP answers:

```text
What IP configuration should this VM use?
```

The router answers:

```text
Where should this packet go?
```

Different jobs.

---

# 42. Inspect Open vSwitch in This Kolla Lab

This lab runs Open vSwitch inside Kolla containers.

Therefore do **not** assume this host command will work:

```text
ovs-vsctl show
```

Instead run on the OpenStack node:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
```

Inspect `br-ex`:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

Current expected `br-ex` ports include:

```text
ext0
phy-br-ex
```

Inspect `br-int`:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-int
```

The exact list varies according to active VMs, routers, networks, and Neutron state.

---

# 43. Inspect All Three Nodes From Hermes

From Hermes:

```bash
for ip in 200 201 202; do
  echo
  echo "===== NODE $ip ====="

  ssh openstack@192.168.0.$ip '
    sudo docker exec openvswitch_vswitchd \
      ovs-vsctl list-ports br-ex
  '
done
```

Expected external uplink on every node:

```text
ext0
```

You should also see the OVS patch-side port associated with the bridge.

---

# 44. Verify the Physical Interfaces

On an OpenStack node:

```bash
ip -br addr
```

Current design should show approximately:

```text
enp0s31f6    UP
ext0         UP
br-mgmt      UP    192.168.0.20x/24
```

The dedicated external interface should not have a normal host IPv4 address:

```text
ext0
```

Check the USB NIC driver:

```bash
ethtool -i ext0
```

Expected driver:

```text
r8152
```

---

# 45. Verify Linux Routing

On an OpenStack node:

```bash
ip route
```

The node's normal management default route belongs to the management side:

```text
br-mgmt
```

not:

```text
ext0
```

This reinforces the separation:

```text
br-mgmt
    = host management/control

ext0
    = Neutron external Layer-2 uplink
```

---

# 46. Inspect a VM From Hermes

Start with:

```bash
openstack server list --all-projects
```

Inspect a VM:

```bash
openstack server show <server-name-or-UUID>
```

Then map the VM to Neutron:

```bash
openstack port list \
  --server <server-name-or-UUID>
```

Inspect the port:

```bash
openstack port show <port-UUID>
```

Now you can connect:

```text
Nova VM
   |
Neutron port
   |
Fixed IP
   |
Network
   |
Security Groups
```

---

# 47. Practical Floating-IP Investigation

From Hermes:

```bash
openstack floating ip list
```

Suppose you are troubleshooting:

```text
192.168.0.160
```

Run:

```bash
openstack floating ip show 192.168.0.160
```

Identify:

```text
fixed IP
port ID
router ID
status
```

Then:

```bash
openstack port show <port-ID>
```

and:

```bash
openstack router show <router-ID>
```

This gives you a chain from:

```text
Floating IP
    ↓
VM port
    ↓
Fixed IP
    ↓
Router
```

---

# 48. Find the Router Host

Once you have the router:

```bash
openstack network agent list \
  --router <router-name-or-UUID>
```

Note the host running the L3 agent.

Then SSH to that node.

Example:

```bash
ssh openstack@192.168.0.201
```

Now find:

```bash
sudo ip netns
```

Locate:

```text
qrouter-<router-UUID>
```

---

# 49. Test From Inside the Router

Inside the router namespace, inspect addresses:

```bash
sudo ip netns exec qrouter-<UUID> \
  ip -br addr
```

Inspect routes:

```bash
sudo ip netns exec qrouter-<UUID> \
  ip route
```

Test the home gateway:

```bash
sudo ip netns exec qrouter-<UUID> \
  ping -c 3 192.168.0.1
```

This is a powerful test.

If:

```text
qrouter → physical gateway
```

works but:

```text
VM → Internet
```

fails, then the external side is probably not the first place to investigate.

The failure is more likely somewhere between:

```text
VM
and
router
```

---

# 50. Inspect NAT Carefully

Depending on the Neutron firewall/NAT implementation, NAT state may be visible through iptables-compatible rules.

For investigation only, one useful command can be:

```bash
sudo ip netns exec qrouter-<UUID> \
  iptables -t nat -S
```

Do not modify these rules manually.

They are managed by Neutron.

The purpose here is:

```text
observe
```

not:

```text
manually repair Neutron-generated firewall rules
```

---

# 51. Troubleshooting — VM Cannot Reach Internet

Follow the packet instead of randomly restarting containers.

## Step 1 — VM

Inside the VM:

```bash
ip addr
ip route
```

Verify:

```text
correct fixed IP
correct subnet
correct default gateway
```

Test the gateway:

```bash
ping -c 3 <private-gateway-IP>
```

## Step 2 — OpenStack objects

From Hermes:

```bash
openstack server show <server>
openstack port list --server <server>
openstack router list
openstack router show <router>
```

Verify that:

```text
VM port exists
router exists
private subnet is connected
router has external gateway
```

## Step 3 — L3 agent

```bash
openstack network agent list \
  --router <router>
```

Identify the router host.

## Step 4 — Router namespace

On that node:

```bash
sudo ip netns
```

Then:

```bash
sudo ip netns exec qrouter-<UUID> ip route
```

Test external gateway:

```bash
sudo ip netns exec qrouter-<UUID> \
  ping -c 3 192.168.0.1
```

## Step 5 — OVS external bridge

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

Current design should include:

```text
ext0
```

## Step 6 — Physical NIC

```bash
ip -br link show ext0
```

and:

```bash
ethtool ext0
```

Now you have checked the path instead of guessing.

---

# 52. Troubleshooting — Floating IP Does Not Respond

From Hermes:

```bash
openstack floating ip show <floating-IP>
```

Check:

```text
Is it associated with a port?

Does it point to the expected fixed IP?

Which router owns it?
```

Then:

```bash
openstack port show <port-ID>
```

Check Security Groups:

```bash
openstack security group list
```

and:

```bash
openstack security group rule list <security-group>
```

For ping, ICMP must be permitted by policy.

For SSH, TCP/22 must be permitted by policy and the VM must actually be running an SSH server.

Then check the router and external path:

```bash
openstack network agent list --router <router>
```

followed on the router host by:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

The troubleshooting question is always:

```text
At which layer does the packet stop?
```

---

# 53. Useful Packet Capture

When deeper troubleshooting is required, packet capture can help prove whether traffic reaches a particular interface.

For example, on an OpenStack node:

```bash
sudo tcpdump -ni ext0
```

To watch ICMP:

```bash
sudo tcpdump -ni ext0 icmp
```

To watch a particular Floating IP:

```bash
sudo tcpdump -ni ext0 host 192.168.0.160
```

Use packet capture for observation.

Do not assume that seeing a packet on one interface proves the entire path works.

The next hop still needs to be checked.

---

# 54. Troubleshooting Philosophy

Do not begin with:

```text
restart Neutron
restart OVS
restart Docker
redeploy OpenStack
```

Begin with:

```text
follow the packet
```

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
```

Now the failure domain is much smaller.

This is exactly the same troubleshooting mindset used with physical networking or VMware networking.

---

# 55. VMware Troubleshooting Mental Model

VMware-style thought process:

```text
VM vNIC
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

OpenStack equivalent:

```text
VM vNIC
   |
TAP / Neutron Port
   |
br-int
   |
overlay / router
   |
br-ex
   |
ext0
   |
physical network
```

Different technologies.

Same principle:

```text
follow the packet one hop at a time
```

---

# 56. Useful Command Cheat Sheet

## Run on Hermes

OpenStack objects:

```bash
openstack server list --all-projects
openstack server show <server>

openstack network list
openstack subnet list

openstack port list --server <server>
openstack port show <port>

openstack router list
openstack router show <router>
openstack port list --router <router>

openstack floating ip list
openstack floating ip show <floating-IP>

openstack security group list
openstack security group rule list <security-group>

openstack network agent list
openstack network agent list --agent-type l3
openstack network agent list --router <router>
```

## Run on an OpenStack node

Linux networking:

```bash
hostname
ip -br addr
ip route
ip neigh
sudo ip netns
```

OVS:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
```

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-int
```

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

Router namespace:

```bash
sudo ip netns exec qrouter-<UUID> \
  ip -br addr
```

```bash
sudo ip netns exec qrouter-<UUID> \
  ip route
```

```bash
sudo ip netns exec qrouter-<UUID> \
  ip neigh
```

Connectivity:

```bash
sudo ip netns exec qrouter-<UUID> \
  ping -c 3 192.168.0.1
```

Packet capture:

```bash
sudo tcpdump -ni ext0
```

---

# 57. Current Outbound Memory Path

Remember this:

```text
VM
 ↓
TAP / Neutron Port
 ↓
br-int
 ↓
VXLAN if needed
 ↓
Neutron Router
 ↓
SNAT
 ↓
br-ex
 ↓
ext0
 ↓
LAN
 ↓
Internet
```

---

# 58. Current Inbound Memory Path

Remember this:

```text
Laptop
 ↓
Floating IP
 ↓
ext0
 ↓
br-ex
 ↓
DNAT / Neutron Router
 ↓
br-int
 ↓
VXLAN if needed
 ↓
TAP / Neutron Port
 ↓
VM Fixed IP
```

Security Group policy must also allow the traffic.

---

# 59. Original Single-NIC Memory Path

For comparison, the original external side was:

```text
br-ex
 ↓
veth-ovs
 ↓
veth-host
 ↓
br-mgmt
 ↓
enp0s31f6
 ↓
LAN
```

Today it is:

```text
br-ex
 ↓
ext0
 ↓
LAN
```

That is the main physical-network difference between Chapter 03 and Chapter 17.

---

# 60. Final Memory Hooks

```text
Neutron
    = OpenStack networking service

Neutron Port
    = logical network attachment

br-int
    = inside OpenStack

br-tun
    = overlay/tunnel switching

br-ex
    = outside/provider side

qrouter
    = Linux router namespace

qr-*
    = router internal side

qg-*
    = router external side

qdhcp
    = DHCP namespace

Fixed IP
    = private VM address

Floating IP
    = external NAT address

SNAT
    = rewrite source

DNAT
    = rewrite destination

Security Group
    = VM network policy

VXLAN
    = overlay between hosts

ext0
    = current physical Neutron external uplink

br-mgmt
    = management/control and tunnel underlay in this lab
```

---

# 61. The Most Important Lesson

Do not try to memorize every generated interface name or UUID.

Understand the responsibilities:

```text
VM creates packet
       |
       v
Neutron Port
       |
       v
OVS switches it
       |
       v
VXLAN carries it between hosts when necessary
       |
       v
Neutron Router routes/NATs it
       |
       v
br-ex sends it toward the external network
       |
       v
ext0 carries it onto the physical LAN
```

When networking fails:

```text
follow the packet
```

and find the first point where reality stops matching the expected path.

That is much more useful than randomly restarting OpenStack services.
