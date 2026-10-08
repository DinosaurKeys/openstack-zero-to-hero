# OpenStack Dual-NIC Networking

This document describes the final dual-NIC network architecture used by the three-node Kolla-Ansible OpenStack homelab.

The original deployment used a temporary single-NIC design with a Linux bridge and veth pair.

The lab has now been migrated to a dedicated physical interface for Neutron external/provider traffic.

## Final design

```text
Management / Control / VXLAN

enp0s31f6
     |
     v
  br-mgmt
     |
     +-- node1 192.168.0.200/24
     +-- node2 192.168.0.201/24
     +-- node3 192.168.0.202/24


Neutron External / Provider Traffic

ext0
  |
  v
br-ex
  |
Neutron external network

```

The two physical interfaces have separate jobs:

```text
enp0s31f6 = management, OpenStack control/API, VXLAN
ext0      = Neutron external/provider network
```

`ext0` is a TP-Link UE306 USB 3.0 Gigabit Ethernet adapter using the Linux `r8152` driver.

The external NIC does not have an IP address. It operates as a Layer-2 uplink for Open vSwitch `br-ex`.

---

# 1. Why We Migrated to Two NICs

The original lab had only one physical Ethernet interface:

```text
enp0s31f6
```

That single interface had to carry both:

```text
Management / OpenStack control traffic
Neutron external/provider traffic
```

To make that work, the original design used a veth pair:

```text
veth-host <====> veth-ovs
```

The old external path was:

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

This worked, but it mixed management and Neutron external traffic through the same physical NIC.

After installing the second USB Ethernet adapter, the external network could be separated.

The new design is:

```text
Management path:

br-mgmt
   |
enp0s31f6
   |
Home LAN


Neutron external path:

br-ex
   |
 ext0
   |
Home LAN
```

The old veth pair is no longer required.

---

# 2. VMware Mental Model

A useful VMware comparison is:

```text
Linux / OpenStack              VMware concept

enp0s31f6                      physical vmnic
br-mgmt                        vSwitch / management port group
192.168.0.20x on br-mgmt       VMkernel-style management IP

ext0                           second physical vmnic
br-ex                          external/provider vSwitch
Neutron external network       VM/public network port group
```

The key principle is:

```text
Management traffic has its own physical uplink.

Neutron external/provider traffic has its own physical uplink.
```
# 3. Physical NIC Inventory

Each OpenStack node now has two physical Ethernet interfaces.

| Node | Management NIC | Management IP | External NIC | USB NIC MAC | Driver |
|---|---|---|---|---|---|
| node1 | `enp0s31f6` | `192.168.0.200/24` | `ext0` | `00:e0:4c:2c:16:78` | `r8152` |
| node2 | `enp0s31f6` | `192.168.0.201/24` | `ext0` | `00:e0:4c:30:46:88` | `r8152` |
| node3 | `enp0s31f6` | `192.168.0.202/24` | `ext0` | `00:e0:4c:55:7e:58` | `r8152` |

The onboard Intel NIC uses:

```text
driver: e1000e
```

The TP-Link UE306 USB Ethernet adapter uses:

```text
driver: r8152
```

The USB adapter is renamed consistently to:

```text
ext0
```

on all three nodes.

---

# 4. Netplan Layout

Each node uses two Netplan files:

```text
/etc/netplan/50-cloud-init.yaml
/etc/netplan/60-neutron-external.yaml
```

Their responsibilities are separated:

```text
50-cloud-init.yaml
    |
    +-- enp0s31f6
    +-- br-mgmt
    +-- management IP
    +-- default gateway
    +-- DNS

60-neutron-external.yaml
    |
    +-- USB Ethernet adapter
    +-- rename to ext0
    +-- no IP address
```

Netplan reads and merges the YAML files.

The fact that there are two files does not mean there are two separate
network configuration systems.

---

# 5. Management Netplan

Example for node1:

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s31f6:
      dhcp4: false
      dhcp6: false

  bridges:
    br-mgmt:
      interfaces:
        - enp0s31f6
      addresses:
        - 192.168.0.200/24
      routes:
        - to: default
          via: 192.168.0.1
      nameservers:
        addresses:
          - 192.168.0.1
          - 1.1.1.1
```

Node2 uses:

```text
192.168.0.201/24
```

Node3 uses:

```text
192.168.0.202/24
```

The physical interface itself has no IP address:

```text
enp0s31f6   UP
```

The IP belongs to the Linux bridge:

```text
br-mgmt     UP     192.168.0.20x/24
```

---

# 6. External NIC Netplan

Node1:

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    neutron-external:
      match:
        macaddress: "00:e0:4c:2c:16:78"
        driver: r8152
      set-name: ext0
      dhcp4: false
      dhcp6: false
      accept-ra: false
      link-local: []
      optional: true
```

Node2 uses:

```text
00:e0:4c:30:46:88
```

Node3 uses:

```text
00:e0:4c:55:7e:58
```

The important properties are:

```text
set-name: ext0
dhcp4: false
dhcp6: false
link-local: []
```

Therefore `ext0` does not receive an IP address.

It is reserved for Open vSwitch and Neutron external traffic.

---

# 7. Important Netplan Matching Lesson

Originally the USB NIC was matched only by MAC address:

```yaml
match:
  macaddress: "00:e0:4c:2c:16:78"
```

After `ext0` was connected to Open vSwitch `br-ex`, Netplan reported:

```text
Cannot find unique matching interface for neutron-external
```

Inspection showed that `ext0` and `br-ex` could present the same MAC
address to Netplan.

The reliable configuration therefore also matches the USB NIC driver:

```yaml
match:
  macaddress: "00:e0:4c:2c:16:78"
  driver: r8152
```

This identifies the physical USB Ethernet device rather than the OVS
bridge.

After adding:

```text
driver: r8152
```

both commands succeeded:

```bash
sudo netplan generate
sudo netplan try --timeout 30
```

This configuration was tested successfully on all three nodes.
# 8. Kolla-Ansible Network Configuration

The final Kolla-Ansible configuration uses:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "ext0"
```

This means:

```text
network_interface
    |
    +-- OpenStack management/control traffic
    +-- API traffic
    +-- VXLAN/tunnel traffic in this lab
    |
    +-- br-mgmt


neutron_external_interface
    |
    +-- Neutron external/provider traffic
    |
    +-- ext0
```

The external USB NIC must not have an IP address assigned to it.

Open vSwitch uses it as a Layer-2 physical uplink.

---

# 9. Old Open vSwitch External Path

Before the dual-NIC migration, `br-ex` used:

```text
veth-ovs
```

The complete path was:

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

This was the temporary single-NIC workaround.

The management NIC therefore indirectly carried both:

```text
management/control traffic
Neutron external traffic
```

---

# 10. New Open vSwitch External Path

After the second NIC was installed, `br-ex` was connected directly to:

```text
ext0
```

The external path became:

```text
br-ex
  |
ext0
  |
physical LAN
```

Management remained completely separate:

```text
br-mgmt
   |
enp0s31f6
   |
physical LAN
```

The final architecture is therefore:

```text
                 OpenStack Node

          MANAGEMENT / CONTROL
                  |
              br-mgmt
                  |
             enp0s31f6
                  |
                  +-------------------- LAN


          NEUTRON EXTERNAL
                  |
                br-ex
                  |
                ext0
                  |
                  +-------------------- LAN
```

---

# 11. Migrating br-ex from veth-ovs to ext0

The migration was performed one node at a time.

This reduced the blast radius and allowed each node to be tested before
changing the next one.

The Open vSwitch commands must be executed inside the Kolla
`openvswitch_vswitchd` container.

General command:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl \
  --if-exists del-port br-ex veth-ovs \
  -- \
  --may-exist add-port br-ex ext0
```

From Hermes, node1 was changed with:

```bash
ssh openstack@192.168.0.200 '
  sudo docker exec openvswitch_vswitchd \
    ovs-vsctl \
    --if-exists del-port br-ex veth-ovs \
    -- \
    --may-exist add-port br-ex ext0
'
```

The same operation was then performed on node2 and node3.

---

# 12. Verify br-ex

After migration, verify the external bridge:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

Expected result:

```text
ext0
phy-br-ex
```

The old port:

```text
veth-ovs
```

must no longer be connected to `br-ex`.

From Hermes:

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="

  ssh openstack@192.168.0.$ip '
    sudo docker exec openvswitch_vswitchd \
      ovs-vsctl list-ports br-ex
  '
done
```

Expected on every node:

```text
ext0
phy-br-ex
```

---

# 13. Rollback

If a node loses Neutron external connectivity during the migration,
the OVS change can be reversed.

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl \
  --if-exists del-port br-ex ext0 \
  -- \
  --may-exist add-port br-ex veth-ovs
```

From Hermes, for example on node1:

```bash
ssh openstack@192.168.0.200 '
  sudo docker exec openvswitch_vswitchd \
    ovs-vsctl \
    --if-exists del-port br-ex ext0 \
    -- \
    --may-exist add-port br-ex veth-ovs
'
```

This rollback was kept available until the new external NIC path had
been validated.

# 14. Remove the Old veth Pair from Netplan

After `br-ex` had been migrated successfully to `ext0`, the old veth pair was no longer needed.

The old management Netplan contained:

```yaml
virtual-ethernets:
  veth-host:
    peer: veth-ovs
  veth-ovs:
    peer: veth-host
```

and `br-mgmt` included:

```yaml
interfaces:
  - enp0s31f6
  - veth-host
```

The final management configuration removes both veth interfaces.

Example for node1:

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s31f6:
      dhcp4: false
      dhcp6: false

  bridges:
    br-mgmt:
      interfaces:
        - enp0s31f6
      addresses:
        - 192.168.0.200/24
      routes:
        - to: default
          via: 192.168.0.1
      nameservers:
        addresses:
          - 192.168.0.1
          - 1.1.1.1
```

Node2 uses:

```text
192.168.0.201/24
```

Node3 uses:

```text
192.168.0.202/24
```

---

# 15. Safe Netplan Validation

Before applying changes:

```bash
sudo netplan generate
```

If there are no errors, test safely:

```bash
sudo netplan try --timeout 30
```

A normal result is:

```text
Do you want to keep these settings?

Press ENTER before the timeout to accept the new configuration
```

Press Enter only after confirming SSH connectivity remains intact.

The successful test was performed independently on all three nodes.

---

# 16. Final Interface State

The final physical interface layout is:

```text
enp0s31f6   UP
ext0        UP
br-mgmt     UP
```

Neither physical NIC directly owns an IPv4 address.

Example node1:

```text
enp0s31f6   UP
ext0        UP
br-mgmt     UP   192.168.0.200/24
```

Example driver verification:

```bash
ethtool -i enp0s31f6 | grep driver
ethtool -i ext0 | grep driver
```

Expected:

```text
driver: e1000e
driver: r8152
```

---

# 17. Verify the Old veth Interfaces Are Gone

Check:

```bash
ip -br link show veth-host
ip -br link show veth-ovs
```

After cleanup, both should be absent.

A convenient check is:

```bash
ip -br link show veth-host 2>/dev/null || echo "veth-host removed"
ip -br link show veth-ovs 2>/dev/null || echo "veth-ovs removed"
```

Expected:

```text
veth-host removed
veth-ovs removed
```

---

# 18. Verify Open vSwitch

Check `br-ex`:

```bash
sudo docker exec openvswitch_vswitchd \
  ovs-vsctl list-ports br-ex
```

Expected:

```text
ext0
phy-br-ex
```

This confirms the old `veth-ovs` uplink is no longer being used.

---

# 19. Floating IP Validation

The migration was validated using running VMs on different compute nodes.

## node1

VM:

```text
cirros-01
```

Floating IP:

```text
192.168.0.164
```

## node2

VM:

```text
ai-cirros-01
```

Floating IP:

```text
192.168.0.153
```

Successful ping:

```text
0% packet loss
```

## node3

VM:

```text
tf-cirros-01
```

Floating IP:

```text
192.168.0.150
```

Successful ping:

```text
0% packet loss
```

This proves that Neutron external traffic is passing through:

```text
br-ex
  |
ext0
  |
physical LAN
```

rather than through the old veth path.

---

# 20. Reboot Persistence

After all three nodes were migrated to the dedicated external NIC,
the cluster was fully shut down and restarted.

After reboot, each node still showed:

```text
ext0 UP
```

and:

```text
br-ex ports:
ext0
phy-br-ex
```

This proved that the external NIC configuration survived reboot.

The management bridge also returned with the correct node address:

```text
node1 br-mgmt = 192.168.0.200/24
node2 br-mgmt = 192.168.0.201/24
node3 br-mgmt = 192.168.0.202/24
```

The Kolla VIP was also observed on `br-mgmt` when owned by the active HA node:

```text
192.168.0.100/32
```

---

# 21. Final Health Validation

After the dual-NIC migration and veth cleanup:

```bash
./scripts/lab-status.sh
```

returned:

```text
RESULT: HEALTHY
PASS checks: 14
```

The validated state was:

```text
Node reachability:        3/3
MariaDB:                  3/3 healthy
ProxySQL:                 3/3 healthy
Placement API:            3/3 healthy
Nova control:             12/12 healthy
Neutron control:          9/9 healthy
Nova control services:    6/6 enabled and up
Nova compute services:    3/3 enabled and up
Hypervisors:              3/3 up
Neutron agents:           12/12 alive and UP
```

---

# 22. Final Architecture Summary

The final network architecture is:

```text
                     OpenStack Node
                           |
          +----------------+----------------+
          |                                 |
          |                                 |
      enp0s31f6                           ext0
       e1000e                              r8152
          |                                 |
          v                                 v
      br-mgmt                             br-ex
          |                                 |
          |                                 |
Management / API / VXLAN          Neutron external/provider
          |
   192.168.0.20x/24
```

The key design rule is:

```text
Management/control traffic stays on enp0s31f6.

Neutron external/provider traffic stays on ext0.
```

The temporary single-NIC veth workaround is no longer required.
