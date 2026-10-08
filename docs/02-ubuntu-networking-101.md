# Ubuntu Networking 101

This document is a reusable reference for safely inspecting and changing networking on Ubuntu Server.

It is intentionally separate from the OpenStack-specific networking configuration.

Sections 13-15 preserve the original single-NIC OpenStack networking stage as a learning exercise.

The current dual-NIC OpenStack architecture is summarized at the end of this chapter and documented in detail in:

```text
docs/17-openstack-dual-nic-networking.md
```

---

# 1. Safety First - Confirm the Server

Before modifying networking, always verify which server you are connected to.

```bash
hostname
hostnamectl
```

Example:

```text
openstack@node1:~$ hostname
node1
```

## Important rule

Never assume you are in the correct SSH window.

A correct networking command executed on the wrong server can cause an outage.

Before commands such as:

```bash
sudo netplan try
sudo netplan apply
```

run:

```bash
hostname
```

first.

---

# 2. Inspect the Current Network

Show network interfaces and IP addresses:

```bash
ip -br addr
```

Example of a normal Ubuntu server:

```text
lo           UNKNOWN  127.0.0.1/8
enp0s31f6    UP       192.168.0.200/24
```

Show the routing table:

```bash
ip route
```

Example:

```text
default via 192.168.0.1 dev enp0s31f6
192.168.0.0/24 dev enp0s31f6 scope link src 192.168.0.200
```

The important information is:

```text
Interface: enp0s31f6
IP:        192.168.0.200/24
Gateway:   192.168.0.1
```

---

# 3. Find the Netplan Configuration

List Netplan files:

```bash
ls -l /etc/netplan/
```

Example:

```text
50-cloud-init.yaml
```

Read the configuration:

```bash
sudo cat /etc/netplan/*.yaml
```

A normal static-IP configuration might look like:

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s31f6:
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

---

# 4. Understand Cloud-Init

A file named:

```text
/etc/netplan/50-cloud-init.yaml
```

usually means cloud-init originally generated the networking configuration.

This does NOT mean cloud-init must always be disabled.

For a normal cloud VM, cloud-init may intentionally manage networking.

For a manually managed homelab server, we may decide to take control of networking ourselves.

To disable future cloud-init network generation:

```bash
echo 'network: {config: disabled}' | \
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

Verify:

```bash
cat /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

Expected:

```text
network: {config: disabled}
```

## Important

Do not blindly disable cloud-init on every Ubuntu machine.

First determine how that machine is supposed to be managed.

---

# 5. Back Up Netplan Before Changing Anything

Always make a backup.

Example:

```bash
sudo cp -a \
  /etc/netplan/50-cloud-init.yaml \
  /etc/netplan/50-cloud-init.yaml.backup
```

Verify:

```bash
ls -l /etc/netplan/
```

You should see both:

```text
50-cloud-init.yaml
50-cloud-init.yaml.backup
```

The backup file does not end with `.yaml`, so this command:

```bash
sudo cat /etc/netplan/*.yaml
```

will only display the active YAML file.

To view the backup:

```bash
sudo cat /etc/netplan/50-cloud-init.yaml.backup
```

---

# 6. Simple Static IP Change

For an ordinary Ubuntu VM or server, you normally do NOT need a Linux bridge or veth pair.

A normal design is simply:

```text
Physical/Virtual NIC
        |
        |
   192.168.0.200
```

Example Netplan:

```yaml
network:
  version: 2
  renderer: networkd

  ethernets:
    enp0s31f6:
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

To change the IP, for example from:

```text
192.168.0.200
```

to:

```text
192.168.0.210
```

change:

```yaml
addresses:
  - 192.168.0.200/24
```

to:

```yaml
addresses:
  - 192.168.0.210/24
```

---

# 7. DNS Configuration

DNS servers belong under:

```yaml
nameservers:
  addresses:
```

Example:

```yaml
nameservers:
  addresses:
    - 192.168.0.1
    - 1.1.1.1
```

The `search:` option is different.

It is for DNS suffixes such as:

```yaml
search:
  - lab.local
```

Do NOT put a DNS server IP such as `1.1.1.1` under `search:`.

---

# 8. Validate the Configuration Before Applying It

After editing Netplan, first run:

```bash
sudo netplan generate
```

This validates the configuration and generates the backend network configuration.

If the command returns silently:

```text
openstack@node1:~$
```

that normally means validation succeeded.

It does NOT apply the new network yet.

Then inspect what Netplan understands:

```bash
sudo netplan get
```

Check carefully:

```text
IP address
interface
gateway
DNS
```

---

# 9. Test the Network Change Safely

When possible, use:

```bash
sudo netplan try
```

You will see something similar to:

```text
Do you want to keep these settings?

Press ENTER before the timeout to accept the new configuration

Changes will revert in 120 seconds
```

Do NOT immediately press Enter.

From another machine, test the server first.

For example:

```bash
ping 192.168.0.200
```

Then:

```bash
ssh openstack@192.168.0.200
```

If networking works correctly, return to the server console and press:

```text
ENTER
```

to accept the configuration.

If networking breaks and you cannot confirm the configuration, Netplan attempts to roll back after the timeout.

---

# 10. netplan try vs netplan apply

Safer method:

```bash
sudo netplan try
```

This provides a rollback timer.

Direct method:

```bash
sudo netplan apply
```

This immediately applies the configuration.

For remote servers, prefer:

```bash
sudo netplan try
```

when supported.

Be especially careful with:

```bash
sudo netplan apply
```

because a bad configuration can immediately kill your SSH connection.

---

# 11. Verify After Changing Networking

Check interfaces:

```bash
ip -br addr
```

Check routing:

```bash
ip route
```

Test the gateway:

```bash
ping -c 3 192.168.0.1
```

Test Internet connectivity without DNS:

```bash
ping -c 3 1.1.1.1
```

Test DNS:

```bash
ping -c 3 google.com
```

Check DNS configuration:

```bash
resolvectl status
```

Finally, test SSH from another machine.

---

# 12. Useful Troubleshooting Commands

Show interfaces:

```bash
ip -br addr
```

Detailed interface information:

```bash
ip addr
```

Routing:

```bash
ip route
```

Systemd network status:

```bash
networkctl
```

Specific interface:

```bash
networkctl status enp0s31f6
```

DNS:

```bash
resolvectl status
```

Network service logs:

```bash
journalctl -u systemd-networkd
```

Netplan configuration:

```bash
sudo netplan get
```

Validate Netplan:

```bash
sudo netplan generate
```

---

# 13. Historical OpenStack Single-NIC Stage

Changing the IP of a normal Ubuntu VM is simpler than the networking used during the original single-NIC stage of this OpenStack lab.

## Normal Ubuntu VM

```text
enp0s31f6
     |
     |
192.168.0.200
```

The NIC owns the IP address directly.

## Original Single-NIC OpenStack Node

During the original build, the OpenStack node looked like:

```text
                192.168.0.200
                      |
                  br-mgmt
                 /       \
                /         \
        enp0s31f6       veth-host
                           ||
                           ||
                        veth-ovs
```

Here:

```text
enp0s31f6
```

did NOT own the management IP directly.

Instead:

```text
br-mgmt
```

owned:

```text
192.168.0.200/24
```

The physical NIC was a Layer-2 member of the Linux bridge.

This design is preserved because it is useful for understanding Linux bridges, veth pairs, and how a single physical interface can be shared between different networking roles.

---

# 14. Why the Original Lab Used the Bridge and veth Pair

At this stage of the original build, each node had only one physical Ethernet interface available for OpenStack networking.

That physical NIC had to carry both:

```text
OpenStack management traffic
+
Neutron external-network traffic
```

The Linux bridge allowed Ubuntu to retain management connectivity.

The veth pair:

```text
veth-host <========> veth-ovs
```

acted like a virtual Ethernet cable.

Historical design:

```text
Home LAN
   |
enp0s31f6
   |
br-mgmt -------- 192.168.0.200
   |
veth-host
   ||
   ||
veth-ovs
```

When OpenStack was deployed, Open vSwitch used:

```text
veth-ovs
   |
 br-ex
   |
Neutron
```

The resulting historical external path was:

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
physical LAN
```

This was an OpenStack-specific workaround for the single-NIC stage.

You do NOT need this architecture simply to change the IP of a normal Ubuntu VM.

---

# 15. Historical Bridge Verification Commands

During the single-NIC stage, useful commands included the following.

Show Linux bridge ports:

```bash
bridge link
```

Historical example:

```text
enp0s31f6 ... master br-mgmt
veth-host ... master br-mgmt
```

Show only members of `br-mgmt`:

```bash
ip link show master br-mgmt
```

Inspect the veth pair:

```bash
ip -d link show veth-host
```

```bash
ip -d link show veth-ovs
```

The output:

```text
veth-host@veth-ovs
```

and:

```text
veth-ovs@veth-host
```

shows that the interfaces are paired.

These commands remain useful for understanding the historical design documented in:

```text
docs/03-openstack-single-nic-networking.md
```

---

# 16. Quick Ubuntu IP Change Checklist

Before changing networking:

```bash
hostname
ip -br addr
ip route
ls -l /etc/netplan/
sudo cat /etc/netplan/*.yaml
```

Backup:

```bash
sudo cp -a /etc/netplan/50-cloud-init.yaml \
  /etc/netplan/50-cloud-init.yaml.backup
```

Edit the configuration.

Validate:

```bash
sudo netplan generate
```

Inspect:

```bash
sudo netplan get
```

Test safely:

```bash
sudo netplan try
```

From another machine test:

```bash
ping <server-ip>
ssh <user>@<server-ip>
```

After accepting the configuration:

```bash
ip -br addr
ip route
ping -c 3 <gateway>
ping -c 3 1.1.1.1
ping -c 3 google.com
```

---

# 17. The Most Important Lessons

1. Confirm the hostname before modifying networking.
2. Back up Netplan before changing it.
3. Understand whether cloud-init manages networking.
4. `netplan generate` validates; it does not activate the network.
5. `netplan get` shows Netplan's interpreted configuration.
6. `netplan try` is safer than blindly using `netplan apply`.
7. Verify gateway, Internet routing, DNS, and SSH separately.
8. A normal Ubuntu static IP does not require a bridge.
9. The historical bridge and `veth-host` / `veth-ovs` pair existed because the original OpenStack design had only one physical NIC available for both management and Neutron external traffic.
10. Never assume that because a YAML file looks valid, remote connectivity will survive the change.

---

# 18. Current OpenStack Dual-NIC Design

The lab later moved away from the single-NIC workaround.

The current management path is:

```text
enp0s31f6
     |
  br-mgmt
     |
node management IP
OpenStack API/control traffic
VXLAN underlay traffic
```

The current Neutron external/provider path is separate:

```text
Neutron
   |
 br-ex
   |
 ext0
   |
physical LAN
```

Kolla-Ansible currently uses:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "ext0"
```

The important distinction is:

```text
enp0s31f6 / br-mgmt
    management + API + VXLAN underlay

ext0 / br-ex
    Neutron external/provider traffic
```

The full migration and current implementation are documented in:

```text
docs/17-openstack-dual-nic-networking.md
```

The original single-NIC implementation remains documented in:

```text
docs/03-openstack-single-nic-networking.md
```

Both are useful:

```text
Chapter 03
    explains how the single-NIC workaround worked

Chapter 17
    documents the current dual-NIC production state of the homelab
```
