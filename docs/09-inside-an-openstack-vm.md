Inside an OpenStack VM
This chapter follows one real OpenStack instance from the OpenStack API down through Nova, libvirt, Linux networking, Neutron, Open vSwitch, the Neutron router, and finally the physical network.
The goal is not to memorize every generated interface name.
The goal is to understand:
which layer owns what
how the layers connect
where to look when a VM fails
where to look when VM networking fails
This walkthrough preserves observations from the original manually created VM:
cirros-01
Those UUIDs, interface names, IP addresses, and compute placement are historical observations from that workload.
The current physical external-network design is:
br-ex
  |
ext0
  |
physical LAN
The original single-NIC veth design is preserved separately in:
docs/03-openstack-single-nic-networking.md
1. Historical Instance Used in This Walkthrough
The VM observed during the original exercise was:
OpenStack name:     cirros-01
OpenStack UUID:     42e55ee6-8ed1-4e16-aaa0-3e5a1bf47800
Compute host:       node1
Nova instance name: instance-00000002

Fixed IP:           10.10.10.205
Floating IP:        192.168.0.164

Neutron port UUID:  0e07d42f-01d2-4ebf-9761-35fbd868cf90
MAC address:        fa:16:3e:65:33:f4
These values are not rebuild requirements.
After recreation, OpenStack may choose different:
UUIDs
fixed IPs
Floating IPs
compute hosts
tap names
qbr names
qvb/qvo names
router namespace UUIDs
The relationships are what matter.
2. Start From the OpenStack Object
From Hermes:
openstack server show cirros-01 \
  -c id \
  -c name \
  -c OS-EXT-SRV-ATTR:host \
  -c OS-EXT-SRV-ATTR:instance_name \
  -c addresses
Historical observation:
OS-EXT-SRV-ATTR:host          node1
OS-EXT-SRV-ATTR:instance_name instance-00000002
addresses                     private=10.10.10.205, 192.168.0.164
id                            42e55ee6-8ed1-4e16-aaa0-3e5a1bf47800
name                          cirros-01
The relationship was:
cirros-01
    |
OpenStack UUID
42e55ee6-8ed1-4e16-aaa0-3e5a1bf47800
    |
Nova internal instance name
instance-00000002
    |
compute host
node1
instance-00000002 is not another VM.
It is Nova's internal libvirt-domain name for the same OpenStack instance.
3. Always Find the Current Compute Host First
Do not assume a VM is on node1 because this historical example was.
Run:
openstack server show <SERVER> \
  -c OS-EXT-SRV-ATTR:host \
  -c OS-EXT-SRV-ATTR:instance_name
Example:
host          node2
instance_name instance-0000000a
Only then SSH to the correct physical node.
Memory:
OpenStack tells you WHERE the VM is.

Then inspect Linux/libvirt on that host.
This prevents troubleshooting the wrong server.
4. Prove the VM Exists in libvirt
In this Kolla deployment, libvirt runs inside:
nova_libvirt
For the historical VM on node1:
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt virsh list --all'
Observed:
Id   Name                State
-----------------------------------
1    instance-00000002   running
This proves:
OpenStack cirros-01
        |
Nova instance-00000002
        |
libvirt domain on node1
Useful mental model:
Nova
  |
  v
libvirt
  |
  v
QEMU
  |
  v
KVM
Use OpenStack commands for normal lifecycle operations:
openstack server stop cirros-01
openstack server start cirros-01
openstack server reboot cirros-01
openstack server delete cirros-01
Do not normally use destructive virsh commands against an OpenStack-managed VM.
OpenStack must remain the control plane for VM lifecycle.
5. Match the VM NIC to the Neutron Port
Inspect the VM NIC through libvirt:
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt \
  virsh domiflist instance-00000002'
Historical observation:
Interface        Type     Source           Model    MAC
----------------------------------------------------------------
tap0e07d42f-01   bridge   qbr0e07d42f-01   virtio   fa:16:3e:65:33:f4
Inspect the libvirt XML:
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt \
  virsh dumpxml instance-00000002 | grep -A12 "<interface"'
Observed:
<interface type='bridge'>
  <mac address='fa:16:3e:65:33:f4'/>
  <source bridge='qbr0e07d42f-01'/>
Now inspect the Neutron port from Hermes:
openstack port list --server cirros-01
The MAC matched:
fa:16:3e:65:33:f4
Therefore:
Neutron port
      =
libvirt VM NIC
seen from two different infrastructure layers.
6. VM NIC to Linux Bridge
Inspect the Linux bridge on the compute host:
ssh openstack@192.168.0.200 \
  'ip link show master qbr0e07d42f-01'
Historical observation:
qvb0e07d42f-01@qvo0e07d42f-01
tap0e07d42f-01
The path becomes:
cirros-01
   |
eth0
   |
tap0e07d42f-01
   |
qbr0e07d42f-01
   |
qvb0e07d42f-01
qbr is a Linux bridge used in this Neutron port-plumbing model.
7. qvb and qvo Form a veth Pair
Historical observation:
qvb0e07d42f-01@qvo0e07d42f-01
Conceptually:
Linux bridge side               OVS side

qbr
 |
qvb ===== virtual cable ===== qvo
So:
cirros-01
   ↓
tap0e07d42f-01
   ↓
qbr0e07d42f-01
   ↓
qvb0e07d42f-01
   ║
qvo0e07d42f-01
This veth pair is part of the VM's Neutron port plumbing.
Do not confuse it with the old host-level:
veth-host / veth-ovs
single-NIC workaround.
They are different veth pairs serving different purposes.
8. qvo Connects to br-int
Check which OVS bridge owns the qvo interface:
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd \
  ovs-vsctl port-to-br qvo0e07d42f-01'
Historical result:
br-int
The path is now:
cirros-01
   ↓
tap
   ↓
qbr
   ↓
qvb
   ║
qvo
   ↓
br-int
br-int is the Neutron/Open vSwitch integration bridge.
9. Inspect br-int
List its ports:
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-int'
Historical output included:
int-br-ex
patch-tun
qg-461876dd-d5
qr-69ed44e1-3f
qvo0e07d42f-01
tap93e3269a-dc
Important meanings:
qvo0e07d42f-01
    VM-side OVS connection

qr-69ed44e1-3f
    router private-side interface

qg-461876dd-d5
    router external-side interface

tap93e3269a-dc
    DHCP-related interface

patch-tun
    path toward br-tun

int-br-ex
    path toward br-ex
The exact generated suffixes will change.
The prefixes and roles are the useful learning points.
10. Inspect the Neutron Router Namespace
Historical router namespace:
qrouter-fdeeaf9a-cbb7-4986-87ed-3bc4ad9283c8
A better rebuild workflow is:
openstack network agent list \
  --router lab-router
Then inspect the correct L3-agent host:
sudo ip netns
Once the namespace is known:
sudo ip netns exec qrouter-<ROUTER-UUID> \
  ip -br addr
Historical private-side interface:
qr-69ed44e1-3f
10.10.10.1/24
MTU 1450
Historical external-side interface:
qg-461876dd-d5
192.168.0.152/24
192.168.0.164/32
MTU 1500
Meanings:
10.10.10.1
    tenant router gateway

192.168.0.152
    router external/SNAT address

192.168.0.164
    Floating IP associated with cirros-01
The Floating IP exists on the Neutron routing side.
It is not configured on eth0 inside CirrOS.
Inside the guest, the VM sees only:
10.10.10.205
Neutron performs the translation outside the VM.
11. Router Traffic Toward br-ex
br-int connects toward the external bridge using an OVS patch pair.
Check the br-int side:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl port-to-br int-br-ex
Expected:
br-int
Inspect br-ex:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
The current validated ports are:
ext0
phy-br-ex
Verify the OVS patch pair:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl get Interface int-br-ex options
Expected conceptually:
{peer=phy-br-ex}
Then:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl get Interface phy-br-ex options
Expected conceptually:
{peer=int-br-ex}
Therefore:
br-int
   ↓
int-br-ex
   ║
   ║ OVS patch pair
   ║
phy-br-ex
   ↓
br-ex
phy-br-ex is not a physical NIC.
It is the OVS patch-port side connected to br-ex.
12. Current External Physical Uplink
The current external uplink is:
ext0
Check it:
ip -br link show ext0
The lab uses TP-Link UE306 USB Gigabit Ethernet adapters with the:
r8152
driver.
Current MAC identities are:
node1  00:e0:4c:2c:16:78
node2  00:e0:4c:30:46:88
node3  00:e0:4c:55:7e:58
Current architecture:
br-ex
  |
ext0
  |
physical switch / LAN
ext0 has no normal host IP address.
It is used as a Layer-2 external/provider uplink for Neutron.
13. Current Full External Packet Path
Using the historical cirros-01 identifiers, but today's physical uplink, the conceptual path is:
cirros-01
10.10.10.205
    ↓
tap0e07d42f-01
    ↓
qbr0e07d42f-01
    ↓
qvb0e07d42f-01
    ║
qvo0e07d42f-01
    ↓
br-int
    ↓
qr-69ed44e1-3f
10.10.10.1
    ↓
qrouter namespace
    ↓
routing / NAT
    ↓
qg-461876dd-d5
192.168.0.152
192.168.0.164/32
    ↓
br-int
    ↓
int-br-ex
    ║
phy-br-ex
    ↓
br-ex
    ↓
ext0
    ↓
physical LAN
    ↓
192.168.0.1
    ↓
Internet
The exact generated interface names can change.
The architecture does not.
14. Historical Single-NIC External Path
Before the dual-NIC migration, the last physical leg was:
br-ex
  ↓
veth-ovs
  ║
veth-host
  ↓
br-mgmt
  ↓
enp0s31f6
  ↓
physical LAN
That design allowed one physical NIC to carry both management and Neutron external traffic.
It is intentionally preserved in:
docs/03-openstack-single-nic-networking.md
It is not the current external path.
Current:
br-ex
  ↓
ext0
  ↓
physical LAN
15. br-tun and VXLAN
The tenant network private was historically observed as:
Network type: VXLAN
VNI:          137
MTU:          1450
Inspect br-tun:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-tun
The br-int side commonly includes:
patch-tun
and br-tun includes its peer:
patch-int
Conceptually:
br-int
   ↓
patch-tun
   ║
   ║ OVS patch pair
   ║
patch-int
   ↓
br-tun
Important:
tenant network type = VXLAN
does not mean every packet must cross a physical VXLAN tunnel.
If the VM and the required network endpoint are local to the same node, the packet may stay local through much of the path.
When tenant endpoints are on different physical nodes, VXLAN carries that logical Layer-2 network across the physical underlay.
Conceptually:
VM on node1
   ↓
br-int
   ↓
br-tun
   ↓
VXLAN
========================
management/tunnel underlay
========================
   ↓
br-tun
   ↓
br-int
   ↓
endpoint on another node
In the current lab, tunnel/control traffic uses the management side:
br-mgmt
   |
enp0s31f6
The dedicated ext0 interface is for external/provider traffic.
16. Underlay and External Uplink Are Different Roles
This is an important dual-NIC distinction.
Management / API / tunnel underlay
br-mgmt
   |
enp0s31f6
Carries things such as:
node management
OpenStack control/API communication
VXLAN underlay traffic
Neutron external/provider
br-ex
   |
ext0
Carries:
provider-network traffic
Floating IP traffic
north-south external traffic
Adding a second NIC did not automatically move VXLAN to ext0.
The two interfaces have different roles.
17. MTU Observation
Tenant-side interfaces were observed using:
MTU 1450
External-side interfaces were observed using:
MTU 1500
VXLAN encapsulation adds overhead.
Reducing the tenant MTU gives the encapsulated frame room to travel over a normal 1500-byte physical underlay without fragmentation problems.
Memory:
tenant packet
    1450

+ VXLAN overhead

physical underlay
    1500
18. Floating IP Inbound Path
For incoming traffic from Hermes to the historical VM:
Hermes
  |
  | ping / SSH
  v
192.168.0.164
Floating IP
  |
  v
ext0
  |
  v
br-ex
  |
  v
Neutron router namespace
  |
  | DNAT
  v
10.10.10.205
  |
  v
br-int
  |
  v
qvo/qvb/qbr/tap
  |
  v
cirros-01
Inside the VM:
ip addr
does not show:
192.168.0.164
because the Floating IP is implemented by Neutron outside the guest.
19. VM Outbound Path
For a VM reaching the Internet:
cirros-01
10.10.10.205
  |
  v
10.10.10.1
tenant gateway
  |
  v
Neutron router
  |
  | SNAT
  v
external network
  |
  v
br-ex
  |
  v
ext0
  |
  v
192.168.0.1
home router
  |
  v
Internet
This is normal routing/NAT implemented through OpenStack networking.
20. Security Groups Fit Before the Packet Reaches the VM
A reachable Floating IP does not bypass Neutron security policy.
For example:
Floating IP exists
        +
VM is running
does not guarantee:
SSH works
if TCP/22 is not allowed by the VM security group.
Troubleshooting therefore includes:
openstack security group list
openstack security group rule list <SECURITY-GROUP>
and:
openstack port show <PORT-UUID>
Security policy is another layer in the packet path.
21. DHCP and Metadata
Tenant VMs typically receive their network configuration from Neutron DHCP.
A namespace may look like:
qdhcp-<NETWORK-UUID>
Inside the guest, the metadata service is commonly reachable through:
169.254.169.254
The historical CirrOS route included:
169.254.169.254 via 10.10.10.2
Memory:
qdhcp
    gives network configuration

metadata
    gives instance metadata
These are different from the L3 router function.
22. Troubleshooting Workflow — Start Logical
When a VM has a problem, begin from OpenStack before diving into Linux interfaces.
Server state
openstack server show <SERVER>
Ask:
ACTIVE?

correct image?

correct flavor?

correct network?
Compute placement
openstack server show <SERVER> \
  -c OS-EXT-SRV-ATTR:host \
  -c OS-EXT-SRV-ATTR:instance_name
Now you know which physical host to inspect.
23. Troubleshooting Workflow — Check the Neutron Port
openstack port list --server <SERVER>
Then:
openstack port show <PORT-UUID>
Check:
port status
fixed IP
MAC address
network ID
security groups
binding host
This connects the OpenStack logical object to the compute-host networking.
24. Troubleshooting Workflow — Check libvirt
On the VM's actual compute host:
sudo docker exec nova_libvirt \
  virsh list --all
Then:
sudo docker exec nova_libvirt \
  virsh domiflist <INSTANCE-NAME>
Ask:
Does the libvirt domain exist?

Is it running?

Does the VM NIC MAC match the Neutron port?
If not, the problem is already narrowed.
25. Troubleshooting Workflow — Check Linux/OVS Plumbing
Inspect the generated Linux bridge and interfaces if present:
ip link
Inspect OVS:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
Find a qvo port's OVS bridge:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl port-to-br <QVO-INTERFACE>
Expected for the VM port:
br-int
26. Troubleshooting Workflow — Check the Router
From Hermes:
openstack router list
Find the L3 agent host:
openstack network agent list \
  --router <ROUTER>
On that host:
sudo ip netns
Inspect:
sudo ip netns exec qrouter-<UUID> \
  ip -br addr
sudo ip netns exec qrouter-<UUID> \
  ip route
Test the external gateway:
sudo ip netns exec qrouter-<UUID> \
  ping -c 3 192.168.0.1
This tells you whether the router namespace itself can reach the physical gateway.
27. Troubleshooting Workflow — Check br-ex and ext0
On the relevant node:
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
Current expected physical uplink:
ext0
Check interface state:
ip -br link show ext0
Check its MAC:
cat /sys/class/net/ext0/address
Check its driver:
ethtool -i ext0
Expected driver:
r8152
The physical uplink should be:
UP
LOWER_UP
when the cable/switch path is healthy.
28. Troubleshooting Workflow — Packet Capture
If you still do not know where the packet stops, capture it.
Watch external traffic:
sudo tcpdump -ni ext0
Watch ICMP:
sudo tcpdump -ni ext0 icmp
Watch one Floating IP:
sudo tcpdump -ni ext0 host <FLOATING-IP>
Packet capture answers:
Did the packet reach this layer?
Then move inward or outward depending on the answer.
29. The Troubleshooting Ladder
A useful order is:
1. OpenStack server
2. Nova compute placement
3. Neutron port
4. security group
5. libvirt domain
6. VM virtual NIC
7. qbr/qvb/qvo or equivalent port plumbing
8. br-int
9. router namespace
10. br-ex
11. ext0
12. physical LAN
Do not begin with random container restarts.
Find the broken layer first.
30. Desired State vs Actual State
This chapter demonstrates a useful infrastructure pattern.
OpenStack desired state might say:
cirros-01 should be ACTIVE

port X should be attached

fixed IP should be 10.10.10.205

Floating IP should be associated
Actual host state includes:
libvirt domain
tap device
Linux bridge
veth pair
OVS port
router namespace
routes
NAT state
physical uplink
Troubleshooting compares:
what OpenStack thinks should exist
against:
what Linux/OVS actually built
This same mental model will later appear in:
Terraform
Ansible
Hermes-assisted IaC
31. VMware Mental Model
Coming from VMware, a rough troubleshooting analogy is:
OpenStack instance
    ~
VM object

Neutron port
    ~
vNIC / logical switch connection

qbr/qvb/qvo + br-int
    ~
virtual switching path

Neutron router
    ~
virtual/distributed routing function

br-ex
    ~
external virtual switch/bridge

ext0
    ~
physical uplink
The technologies differ.
The operational habit is the same:
follow the packet
32. Current Cold-Boot Validation
After the latest full servers-off / cold-boot test, the lab validated:
3/3 nodes reachable
MariaDB healthy
ProxySQL healthy
Placement healthy
Nova control healthy
3/3 nova-compute up
3/3 hypervisors up
12/12 Neutron agents alive
dual-NIC persistence working
API VIP working
Floating IP data plane working
The active test VM:
ai-cirros-01
had:
Fixed IP:
10.20.0.188

Floating IP:
192.168.0.153
and the Floating IP responded successfully after cold boot.
That proves the current:
ext0
  |
br-ex
  |
Neutron
  |
VM
data path survives reboot.
33. Historical vs Current Values
This chapter intentionally contains two types of information.
Historical observation
Examples:
cirros-01
instance-00000002
10.10.10.205
192.168.0.164
tap0e07d42f-01
qbr0e07d42f-01
qrouter-fdee...
These make the architecture concrete.
Current architecture
Examples:
network_interface: br-mgmt
neutron_external_interface: ext0

br-ex
  |
ext0
  |
physical LAN
Do not copy historical UUIDs or dynamically generated interface names into automation.
Use OpenStack discovery commands to obtain current values.
34. Useful Discovery Commands
From Hermes:
openstack server list --all-projects
openstack server show <SERVER>
openstack port list --server <SERVER>
openstack router list
openstack network agent list
openstack floating ip list
On the relevant OpenStack node:
sudo ip netns
sudo docker exec nova_libvirt \
  virsh list --all
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl show
ip -br addr
These let you rediscover the actual runtime state instead of relying on old IDs.
35. Final Packet Path Memory Hook
Inside the compute/network stack:
VM
 ↓
tap
 ↓
qbr
 ↓
qvb/qvo
 ↓
br-int
 ↓
Neutron router
 ↓
br-ex
 ↓
ext0
 ↓
physical LAN
Across nodes when the overlay is needed:
br-int
 ↓
br-tun
 ↓
VXLAN
 ↓
physical underlay on br-mgmt/enp0s31f6
 ↓
br-tun
 ↓
br-int
Two roles:
enp0s31f6 / br-mgmt
    management + API + VXLAN underlay

ext0 / br-ex
    Neutron external/provider traffic
36. Chapter Summary
The most important relationship is:
OpenStack server
      ↓
Nova
      ↓
libvirt / QEMU / KVM
      ↓
virtual NIC
      ↓
Neutron port
      ↓
Linux + OVS network plumbing
      ↓
Neutron router
      ↓
br-ex
      ↓
ext0
      ↓
physical network
The exact generated names are temporary.
The architecture is the durable knowledge.
When troubleshooting:
start with the OpenStack object

discover the actual host and port

follow the packet one layer at a time
That turns:
"OpenStack networking is broken"
into a much more useful question:
"At which layer does the expected state stop matching reality?"
