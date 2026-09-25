# OpenStack Single-NIC Networking

This document explains the temporary single-NIC network architecture used by the OpenStack homelab.

The three OpenStack nodes currently have only one physical Ethernet interface each.

The goal is to allow the same physical NIC to carry:

- Ubuntu management traffic
- OpenStack API/control traffic
- Neutron external/provider traffic

without giving the physical management NIC directly to Open vSwitch.

---

# 1. Nodes

Current management addresses:

| Node | Management IP |
|---|---|
| node1 | 192.168.0.200/24 |
| node2 | 192.168.0.201/24 |
| node3 | 192.168.0.202/24 |

Gateway:

```text
192.168.0.1
```

Physical Ethernet interface:

```text
enp0s31f6
```

---

# 2. Original Network Design

Immediately after Ubuntu installation, each node looked like:

```text
Home LAN
   |
enp0s31f6
   |
192.168.0.200
```

For node1:

```text
enp0s31f6 = 192.168.0.200/24
```

For node2:

```text
enp0s31f6 = 192.168.0.201/24
```

For node3:

```text
enp0s31f6 = 192.168.0.202/24
```

The physical NIC directly owned the management IP.

---

# 3. Why This Is a Problem for OpenStack

OpenStack Neutron needs an external interface that can eventually connect to the Open vSwitch external bridge:

```text
br-ex
```

The external path will eventually look approximately like:

```text
OpenStack VM
     |
Neutron router
     |
Floating IP
     |
   br-ex
     |
External network
```

With a dedicated second physical NIC, this is simple.

Example:

```text
NIC 1
 |
Management

NIC 2
 |
br-ex
 |
Neutron
```

But initially our nodes only have one wired NIC:

```text
enp0s31f6
```

That NIC is already required for:

```text
SSH
Ansible
Kolla-Ansible
OpenStack APIs
cluster communication
```

We therefore do not want to hand that physical interface directly to Open vSwitch.

---

# 4. Temporary Single-NIC Solution

The temporary design is:

```text
                    Home LAN
                       |
                  enp0s31f6
                       |
                    br-mgmt
                  /         \
                 /           \
        Management IP      veth-host
                              ||
                              ||
                           veth-ovs
```

The management IP moves from:

```text
enp0s31f6
```

to:

```text
br-mgmt
```

The physical NIC becomes a Layer-2 bridge port.

---

# 5. Linux Bridge

`br-mgmt` is a Linux software bridge.

A useful VMware mental model is:

```text
Linux                    VMware concept

enp0s31f6       ~        physical vmnic
br-mgmt         ~        vSwitch
host IP         ~        host/VMkernel-style L3 interface
```

This is only an analogy, but it helps explain the design.

---

# 6. Moving the Management IP

Before:

```text
enp0s31f6
     |
192.168.0.200
```

After:

```text
enp0s31f6
     |
  br-mgmt
     |
192.168.0.200
```

The important idea is:

```text
The IP address did not change.

The interface that owns the IP changed.
```

For node1:

```text
192.168.0.200
```

still exists, but it belongs to:

```text
br-mgmt
```

instead of:

```text
enp0s31f6
```

---

# 7. What Is a veth Pair?

Linux can create a pair of virtual Ethernet interfaces.

Our pair is:

```text
veth-host <========> veth-ovs
```

A useful mental model is:

```text
virtual Ethernet cable
```

Traffic entering one end exits the other end.

`veth-host` is connected to:

```text
br-mgmt
```

The other side:

```text
veth-ovs
```

is intentionally left free for Open vSwitch.

---

# 8. Current Architecture

The complete current design is:

```text
                     HOME LAN
                        |
                        |
                   enp0s31f6
                        |
                        |
                    +---------+
                    | br-mgmt |
                    +---------+
                     /       \
                    /         \
        Management IP       veth-host
                               ||
                               ||
                            veth-ovs
```

Node addresses:

```text
node1 br-mgmt = 192.168.0.200/24
node2 br-mgmt = 192.168.0.201/24
node3 br-mgmt = 192.168.0.202/24
```

---

# 9. Future OpenStack Architecture

After Open vSwitch and Neutron are deployed, the intended path is:

```text
                     HOME LAN
                        |
                   enp0s31f6
                        |
                     br-mgmt
                    /       \
management IP              veth-host
                              ||
                              ||
                           veth-ovs
                              |
                            br-ex
                              |
                           Neutron
                              |
                        Floating IP
                              |
                         OpenStack VM
```

The important interface for Neutron will be:

```text
veth-ovs
```

It provides access to the physical LAN without giving Open vSwitch direct control of the physical management NIC.

---

# 10. Netplan Configuration

The node1 configuration is:

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s31f6:
      dhcp4: false
      dhcp6: false

  virtual-ethernets:
    veth-host:
      peer: veth-ovs
    veth-ovs:
      peer: veth-host

  bridges:
    br-mgmt:
      interfaces:
        - enp0s31f6
        - veth-host
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

# 11. What Each Netplan Section Does

The physical interface:

```yaml
ethernets:
  enp0s31f6:
    dhcp4: false
    dhcp6: false
```

means the physical interface exists but does not receive an IP address directly.

The veth pair:

```yaml
virtual-ethernets:
  veth-host:
    peer: veth-ovs
  veth-ovs:
    peer: veth-host
```

creates:

```text
veth-host <========> veth-ovs
```

The bridge:

```yaml
bridges:
  br-mgmt:
```

creates the Linux bridge.

The bridge ports:

```yaml
interfaces:
  - enp0s31f6
  - veth-host
```

produce:

```text
             br-mgmt
             /     \
            /       \
   enp0s31f6       veth-host
```

The management address:

```yaml
addresses:
  - 192.168.0.200/24
```

belongs to the bridge.

---

# 12. Cloud-Init

The original Ubuntu installation generated:

```text
/etc/netplan/50-cloud-init.yaml
```

Because this is a manually managed homelab, cloud-init network generation was disabled:

```bash
echo 'network: {config: disabled}' | \
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

This prevents future cloud-init activity from regenerating the network configuration unexpectedly.

This is a decision specific to how this lab is managed.

It should not be blindly applied to every Ubuntu system.

---

# 13. Backup Before Network Changes

The original Netplan configuration was backed up:

```bash
sudo cp -a \
  /etc/netplan/50-cloud-init.yaml \
  /etc/netplan/50-cloud-init.yaml.backup
```

This allowed the original configuration to be inspected or restored if necessary.

---

# 14. Safe Manual Deployment on node1

The architecture was first tested manually on:

```text
node1
```

This was intentional.

The process was:

```text
understand
   |
configure one node
   |
validate
   |
test
   |
understand the result
   |
automate
```

We did not immediately push a network configuration to all three machines.

---

# 15. Netplan Validation

Before activating the configuration:

```bash
sudo netplan generate
```

Then:

```bash
sudo netplan get
```

`netplan generate` validates and generates backend configuration.

It does not normally activate the new live networking.

---

# 16. netplan try

The configuration was activated safely using:

```bash
sudo netplan try
```

Netplan temporarily applies the configuration and presents a rollback timer.

Example:

```text
Do you want to keep these settings?

Press ENTER before the timeout to accept the new configuration

Changes will revert in 120 seconds
```

Before accepting a remote network change, connectivity should be tested from another machine.

---

# 17. Bridge Parameter Lesson

Initially the bridge configuration included:

```yaml
parameters:
  stp: false
  forward-delay: 0
```

The configuration itself was valid and:

```bash
sudo netplan generate
```

succeeded.

However:

```bash
sudo netplan try
```

refused with a message similar to:

```text
reverting custom parameters for bridges and bonds is not supported
```

The problem was not invalid YAML.

The problem was that `netplan try` could not guarantee rollback of those bridge parameters.

They were not required for this lab, so they were removed.

This allowed:

```bash
sudo netplan try
```

to provide its normal rollback protection.

---

# 18. Validate the Live Network

After applying the change:

```bash
ip -br addr
```

Node1 showed:

```text
enp0s31f6        UP
br-mgmt          UP   192.168.0.200/24
veth-ovs         UP
veth-host        UP
```

The important result is:

```text
enp0s31f6 = no IPv4 address
br-mgmt   = management IPv4 address
```

---

# 19. Verify Routing

Run:

```bash
ip route
```

Expected on node1:

```text
default via 192.168.0.1 dev br-mgmt
192.168.0.0/24 dev br-mgmt scope link src 192.168.0.200
```

The default route must now use:

```text
br-mgmt
```

instead of:

```text
enp0s31f6
```

---

# 20. Verify Bridge Membership

Run:

```bash
bridge link
```

Expected conceptually:

```text
enp0s31f6 ... master br-mgmt
veth-host ... master br-mgmt
```

This proves both interfaces are Layer-2 ports of the Linux bridge.

Another useful command is:

```bash
ip link show master br-mgmt
```

---

# 21. Inspect the veth Pair

Run:

```bash
ip -d link show veth-host
```

and:

```bash
ip -d link show veth-ovs
```

The names appear as:

```text
veth-host@veth-ovs
```

and:

```text
veth-ovs@veth-host
```

This shows that they are peers.

`veth-host` is attached to:

```text
br-mgmt
```

while `veth-ovs` remains free.

---

# 22. Connectivity Tests

Test the default gateway:

```bash
ping -c 3 192.168.0.1
```

Test Internet routing:

```bash
ping -c 3 1.1.1.1
```

Test DNS:

```bash
ping -c 3 google.com
```

Test SSH from Hermes:

```bash
ssh openstack@192.168.0.200
```

Test Ansible:

```bash
ansible node1 \
  -i ansible/inventory.ini \
  -m ping
```

Expected:

```text
node1 | SUCCESS
```

---

# 23. Automation with Ansible

After node1 was proven manually, the network configuration was converted into:

```text
ansible/playbooks/03-single-nic-network.yml
```

This follows an important rule:

```text
Understand manually first.
Automate second.
```

The playbook:

- backs up Netplan
- disables cloud-init network generation
- writes the single-NIC configuration
- runs `netplan generate`

It intentionally does not automatically run:

```bash
netplan apply
```

This keeps activation of management-network changes under manual control.

---

# 24. Dynamic Node Addresses

The Ansible playbook uses:

```yaml
addresses:
  - {{ ansible_host }}/24
```

The inventory already contains:

```ini
node1 ansible_host=192.168.0.200
node2 ansible_host=192.168.0.201
node3 ansible_host=192.168.0.202
```

Therefore one playbook can generate the correct address for each node.

---

# 25. Serial Execution

The playbook contains:

```yaml
serial: 1
```

This tells Ansible to process one host at a time.

Network changes are high risk.

Processing one host at a time prevents a bad configuration from being prepared on the entire cluster simultaneously.

---

# 26. node2 and node3

After node1 was proven manually, the Ansible playbook prepared node2.

The generated file was inspected before activation.

The same process was then used for node3.

Final addresses:

```text
node1 br-mgmt = 192.168.0.200/24
node2 br-mgmt = 192.168.0.201/24
node3 br-mgmt = 192.168.0.202/24
```

---

# 27. Final Cluster Validation

Ansible connectivity:

```bash
ansible all \
  -i ansible/inventory.ini \
  -m ping
```

All three nodes returned:

```text
SUCCESS
```

Network state:

```bash
ansible all \
  -i ansible/inventory.ini \
  -m shell \
  -a 'echo "=== $(hostname) ==="; ip -br addr; ip route'
```

Bridge state:

```bash
ansible all \
  -i ansible/inventory.ini \
  -b \
  -m command \
  -a "bridge link"
```

All nodes showed:

```text
enp0s31f6 -> member of br-mgmt
veth-host -> member of br-mgmt
br-mgmt   -> owns management IP
veth-ovs  -> free peer
```

---

# 28. Important Safety Lesson

Before changing networking:

```bash
hostname
```

Always verify which system the terminal belongs to.

During this lab, commands were almost run against Hermes while intending to modify an OpenStack node.

The prompt clearly distinguishes systems:

```text
joe@hermes
```

versus:

```text
openstack@node1
openstack@node2
openstack@node3
```

A correct command on the wrong server can still cause an outage.

---

# 29. Hermes Networking Is Different

Hermes runs inside VMware Workstation using VMware NAT.

Its interface looks different:

```text
ens33
```

with an address on the VMware NAT network.

Example:

```text
192.168.162.x
```

Do not confuse Hermes networking with the OpenStack physical-node network:

```text
192.168.0.0/24
```

---

# 30. Future Two-NIC Design

USB Ethernet adapters have been ordered for the OpenStack nodes.

Once installed, the architecture can be simplified.

Current temporary design:

```text
               enp0s31f6
                   |
                br-mgmt
               /       \
management IP          veth pair
                          |
                        br-ex
```

Future design:

```text
enp0s31f6                      USB Ethernet
    |                               |
Management                        br-ex
    |                               |
192.168.0.x                      Neutron
```

Conceptually:

```text
NIC 1 = management/control traffic
NIC 2 = external/provider traffic
```

The single-NIC work is still valuable because it demonstrates how Linux bridges, veth pairs, routes, and OpenStack external networking fit together.

---

# 31. Planned Kolla-Ansible Mapping

For the current single-NIC architecture, the intended Kolla concepts are:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "veth-ovs"
```

This means:

```text
br-mgmt
```

carries OpenStack management/control communication.

And:

```text
veth-ovs
```

will be used as the external Neutron-facing interface.

We will validate the final Kolla configuration again before deployment rather than blindly copying historical configuration.

---

# 32. Current Network Summary

Each node now has:

```text
Home LAN
   |
enp0s31f6
   |
br-mgmt -------- management IP
   |
veth-host
   ||
   ||
veth-ovs
   |
future br-ex
   |
Neutron
```

Addresses:

```text
node1 = 192.168.0.200
node2 = 192.168.0.201
node3 = 192.168.0.202
```

Gateway:

```text
192.168.0.1
```

---

# 33. Main Lessons

1. A physical NIC does not need to own the host IP directly.
2. A Linux bridge can become the host Layer-3 interface.
3. Physical NICs can operate as Layer-2 bridge ports.
4. A veth pair behaves like a virtual Ethernet cable.
5. `veth-host` connects the physical LAN side to the bridge.
6. `veth-ovs` provides a future attachment point for Open vSwitch.
7. Test management networking on one server before automating the cluster.
8. `netplan generate` and `netplan try` serve different purposes.
9. Always test SSH before accepting a remote networking change.
10. Always verify `hostname` before modifying network configuration.
11. The single-NIC design is temporary but provides valuable Linux networking experience.
12. A dedicated second NIC will simplify the eventual Neutron architecture.
