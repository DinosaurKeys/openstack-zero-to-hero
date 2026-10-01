# Inside an OpenStack VM

This chapter follows one real OpenStack instance from the Nova API down to
libvirt, Neutron, Open vSwitch, the Neutron router, and finally the physical
network.

The goal is not to memorize every Linux interface name.

The goal is to understand where to look when a VM or its networking fails.

---

# 1. Lab Instance Used in This Chapter

The instance used during this walkthrough:

```text
OpenStack name:     cirros-01
OpenStack UUID:     42e55ee6-8ed1-4e16-aaa0-3e5a1bf47800
Compute host:       node1
Nova instance name: instance-00000002

Fixed IP:           10.10.10.205
Floating IP:        192.168.0.164

Neutron port UUID:  0e07d42f-01d2-4ebf-9761-35fbd868cf90
MAC address:        fa:16:3e:65:33:f4
```

These values are specific to this deployment.

UUIDs, interface names, fixed IPs, floating IPs, and compute placement can
change after a rebuild.

---

# 2. OpenStack Server vs Nova Internal Instance

From Hermes:

```bash
openstack server show cirros-01 \
  -c id \
  -c name \
  -c OS-EXT-SRV-ATTR:host \
  -c OS-EXT-SRV-ATTR:instance_name \
  -c addresses
```

Observed:

```text
OS-EXT-SRV-ATTR:host          node1
OS-EXT-SRV-ATTR:instance_name instance-00000002
addresses                     private=10.10.10.205, 192.168.0.164
id                            42e55ee6-8ed1-4e16-aaa0-3e5a1bf47800
name                          cirros-01
```

The relationship is:

```text
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
```

`instance-00000002` is not another VM.

It is Nova's internal name for the same VM on the compute host.

---

# 3. Prove the VM Exists in libvirt

On node1, Kolla runs libvirt inside the `nova_libvirt` container.

From Hermes:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt virsh list --all'
```

Observed:

```text
Id   Name                State
-----------------------------------
1    instance-00000002   running
```

This proves:

```text
OpenStack cirros-01
        |
Nova instance-00000002
        |
libvirt domain on node1
```

A useful high-level relationship is:

```text
Nova
 ↓
libvirt
 ↓
QEMU
 ↓
KVM
```

Nova owns the VM lifecycle.

Use OpenStack commands for normal lifecycle operations:

```bash
openstack server stop cirros-01
openstack server start cirros-01
openstack server reboot cirros-01
openstack server delete cirros-01
```

Do not normally modify OpenStack-managed VMs directly with destructive
`virsh` commands.

---

# 4. Match the VM NIC to the Neutron Port

Inspect the libvirt NIC:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt virsh domiflist instance-00000002'
```

Observed:

```text
Interface        Type     Source           Model    MAC
----------------------------------------------------------------
tap0e07d42f-01   bridge   qbr0e07d42f-01   virtio   fa:16:3e:65:33:f4
```

Inspect the XML:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt virsh dumpxml instance-00000002 | grep -A12 "<interface"'
```

Observed:

```text
<interface type='bridge'>
  <mac address='fa:16:3e:65:33:f4'/>
  <source bridge='qbr0e07d42f-01'/>
```

The MAC address matches the Neutron port:

```text
fa:16:3e:65:33:f4
```

Therefore:

```text
Neutron port
      =
libvirt VM NIC
```

viewed from two different layers.

---

# 5. VM NIC to Linux Bridge

Inspect the Linux bridge:

```bash
ssh openstack@192.168.0.200 \
  'ip link show master qbr0e07d42f-01'
```

Observed:

```text
qvb0e07d42f-01@qvo0e07d42f-01
tap0e07d42f-01
```

The path is:

```text
cirros-01
   |
eth0
   |
tap0e07d42f-01
   |
qbr0e07d42f-01
   |
qvb0e07d42f-01
```

`qbr` is a Linux bridge used in the Neutron port plumbing.

---

# 6. qvb and qvo Form a veth Pair

Observed:

```text
qvb0e07d42f-01@qvo0e07d42f-01
```

Conceptually:

```text
Linux bridge side               OVS side

qbr
 |
qvb ===== virtual cable ===== qvo
```

So the path becomes:

```text
cirros-01
   ↓
tap0e07d42f-01
   ↓
qbr0e07d42f-01
   ↓
qvb0e07d42f-01
   ║
qvo0e07d42f-01
```

---

# 7. qvo Connects to br-int

Check which OVS bridge owns the `qvo` interface:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl port-to-br qvo0e07d42f-01'
```

Observed:

```text
br-int
```

The path is now:

```text
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
```

`br-int` is Neutron's Open vSwitch integration bridge.

---

# 8. Inspect br-int

List its ports:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-int'
```

Observed:

```text
int-br-ex
patch-tun
qg-461876dd-d5
qr-69ed44e1-3f
qvo0e07d42f-01
tap93e3269a-dc
```

Important ports:

```text
qvo0e07d42f-01
    VM connection

qr-69ed44e1-3f
    Neutron router private-side interface

qg-461876dd-d5
    Neutron router external-side interface

tap93e3269a-dc
    DHCP-related interface

patch-tun
    connection toward br-tun

int-br-ex
    connection toward br-ex
```

---

# 9. Inspect the Neutron Router Namespace

The router namespace is:

```text
qrouter-fdeeaf9a-cbb7-4986-87ed-3bc4ad9283c8
```

Entering a Linux network namespace requires root privileges.

Correct command:

```bash
ssh openstack@192.168.0.200 \
  'sudo ip netns exec qrouter-fdeeaf9a-cbb7-4986-87ed-3bc4ad9283c8 ip addr'
```

Observed private-side interface:

```text
qr-69ed44e1-3f
10.10.10.1/24
MTU 1450
```

Observed external-side interface:

```text
qg-461876dd-d5
192.168.0.152/24
192.168.0.164/32
MTU 1500
```

The meanings are:

```text
10.10.10.1
    tenant/private router gateway

192.168.0.152
    Neutron router external/SNAT address

192.168.0.164
    floating IP associated with cirros-01
```

This is important:

```text
192.168.0.164
```

exists on the Neutron router side.

It is not configured inside CirrOS.

Inside CirrOS, the VM only sees:

```text
10.10.10.205
```

Neutron performs the floating-IP translation.

---

# 10. Router Traffic Toward br-ex

The external router interface returns traffic to `br-int`.

The `br-int` bridge connects toward the external bridge using an OVS patch
pair.

Check the first side:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl port-to-br int-br-ex'
```

Observed:

```text
br-int
```

Inspect `br-ex`:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-ex'
```

Observed:

```text
phy-br-ex
veth-ovs
```

Verify the patch pair:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl get Interface int-br-ex options'
```

Observed:

```text
{peer=phy-br-ex}
```

Then:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl get Interface phy-br-ex options'
```

Observed:

```text
{peer=int-br-ex}
```

Therefore:

```text
br-int
   ↓
int-br-ex
   ║
   ║ OVS patch pair
   ║
phy-br-ex
   ↓
br-ex
```

---

# 11. Single-NIC External Network Workaround

This lab currently has one physical Ethernet NIC per node.

The external OpenStack bridge therefore uses a veth pair to reach the same
Linux bridge used by the physical NIC.

Inspect the veth pair:

```bash
ssh openstack@192.168.0.200 \
  'ip link show veth-ovs; echo; ip link show veth-host'
```

Observed:

```text
veth-ovs@veth-host
veth-host@veth-ovs
```

The bridge memberships are:

```text
veth-ovs  → Open vSwitch / br-ex side
veth-host → Linux br-mgmt side
```

Inspect `br-mgmt`:

```bash
ssh openstack@192.168.0.200 \
  'ip link show master br-mgmt'
```

Observed:

```text
enp0s31f6
veth-host
```

Therefore the external path is:

```text
br-ex
  ↓
veth-ovs
  ║
  ║ Linux veth pair
  ║
veth-host
  ↓
br-mgmt
  ↓
enp0s31f6
  ↓
physical LAN
```

---

# 12. Full Verified External Packet Path

The complete path verified in this lab is:

```text
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
veth-ovs
    ║
veth-host
    ↓
br-mgmt
    ↓
enp0s31f6
    ↓
physical LAN
    ↓
192.168.0.1
    ↓
Internet
```

---

# 13. br-tun and VXLAN

The tenant network `private` was previously observed as:

```text
Network type: VXLAN
VNI:          137
MTU:          1450
```

Inspect `br-tun`:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-tun'
```

Observed:

```text
patch-int
```

No explicit cross-node VXLAN tunnel port was observed on node1 at this time.

The `br-int` side contains:

```text
patch-tun
```

Verify the patch pair:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl get Interface patch-tun options'
```

Observed:

```text
{peer=patch-int}
```

And:

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl get Interface patch-int options'
```

Observed:

```text
{peer=patch-tun}
```

Therefore:

```text
br-int
   ↓
patch-tun
   ║
   ║ OVS patch pair
   ║
patch-int
   ↓
br-tun
```

Important distinction:

```text
tenant network uses VXLAN
        does not mean
every packet crosses a VXLAN tunnel
```

In the currently observed workload:

```text
cirros-01        node1
Neutron router   node1
DHCP namespace   node1
```

The VM's tested Internet path can remain local to node1 until reaching the
external network.

If tenant endpoints later exist on different physical nodes, VXLAN becomes
the mechanism used to carry that tenant Layer-2 network between those hosts.

Conceptually:

```text
VM on node1
   ↓
br-int
   ↓
br-tun
   ↓
VXLAN VNI 137
========================
physical underlay
========================
   ↓
br-tun
   ↓
br-int
   ↓
VM on another node
```

This cross-node path was not directly observed in this chapter.

---

# 14. MTU Observation

The tenant-side interfaces were observed using:

```text
MTU 1450
```

The external-side interfaces were observed using:

```text
MTU 1500
```

VXLAN encapsulation adds overhead.

Using a smaller tenant MTU leaves room for the encapsulation before the
packet travels across a 1500-byte physical network.

---

# 15. How This Changes With a Second Physical NIC

Most of the OpenStack VM path does not change.

This remains:

```text
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
```

The current single-NIC external path is:

```text
br-ex
 ↓
veth-ovs
 ║
veth-host
 ↓
br-mgmt
 ↓
enp0s31f6
```

With a dedicated second Ethernet adapter for the Neutron external network,
the design can become:

```text
Management NIC
enp0s31f6
   ↓
br-mgmt
   ↓
node management IP
```

and separately:

```text
br-ex
   ↓
second physical NIC
   ↓
physical switch
```

The single-NIC veth workaround would no longer be required.

Conceptually, Kolla would change from:

```yaml
network_interface: br-mgmt
neutron_external_interface: veth-ovs
```

to something similar to:

```yaml
network_interface: br-mgmt
neutron_external_interface: <SECOND-NIC>
```

The exact second-NIC interface name must be verified on the host before
making this change.

A second external NIC does not automatically mean VXLAN traffic also moves
to that NIC.

A common two-NIC design is:

```text
NIC 1
    management/API + tunnel traffic

NIC 2
    Neutron external/provider traffic
```

---

# 16. Troubleshooting Mental Model

When a VM has a networking problem, work from the VM outward.

## Check the OpenStack object

```bash
openstack server show cirros-01
```

## Check the Neutron port

```bash
openstack port list --server cirros-01
```

Verify:

```text
status
fixed IP
MAC address
```

## Check compute placement

```bash
openstack server show cirros-01 \
  -c OS-EXT-SRV-ATTR:host \
  -c OS-EXT-SRV-ATTR:instance_name
```

## Check libvirt

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt virsh list --all'
```

## Check the VM interface

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec nova_libvirt virsh domiflist instance-00000002'
```

## Check the Linux bridge

```bash
ssh openstack@192.168.0.200 \
  'ip link show master qbr0e07d42f-01'
```

## Check br-int

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-int'
```

## Check the Neutron router

```bash
ssh openstack@192.168.0.200 \
  'sudo ip netns exec qrouter-fdeeaf9a-cbb7-4986-87ed-3bc4ad9283c8 ip addr'
```

## Check br-ex

```bash
ssh openstack@192.168.0.200 \
  'sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-ex'
```

## Check the physical uplink

```bash
ssh openstack@192.168.0.200 \
  'ip link show master br-mgmt'
```

The troubleshooting path is therefore:

```text
OpenStack server
      ↓
Nova placement
      ↓
libvirt
      ↓
Neutron port
      ↓
tap/qbr/qvb/qvo
      ↓
br-int
      ↓
router namespace
      ↓
br-ex
      ↓
physical network
```

---

# 17. Chapter Summary

The important lesson is not the exact interface names.

The important relationship is:

```text
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
external bridge
      ↓
physical network
```

For this lab, that relationship was verified using real commands rather than
only architecture diagrams.

