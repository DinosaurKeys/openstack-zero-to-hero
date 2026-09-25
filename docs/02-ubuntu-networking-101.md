# Ubuntu Networking 101

This document is a reusable reference for safely inspecting and changing networking on Ubuntu Server.

It is intentionally separate from the OpenStack-specific networking configuration.

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

# 13. Our OpenStack Lab Is Different

Changing the IP of a normal Ubuntu VM is simpler than the networking used in our OpenStack lab.

## Normal Ubuntu VM

```text
enp0s31f6
     |
     |
192.168.0.200
```

The NIC owns the IP address directly.

## Our Single-NIC OpenStack Node

Our OpenStack node currently looks like:

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

does NOT own the management IP.

Instead:

```text
br-mgmt
```

owns:

```text
192.168.0.200/24
```

The physical NIC is a Layer-2 member of the Linux bridge.

---

# 14. Why OpenStack Uses the Bridge and veth Pair

We currently have only one physical Ethernet interface.

That physical NIC must temporarily carry both:

```text
OpenStack management traffic
+
Neutron external-network traffic
```

The Linux bridge allows Ubuntu to retain management connectivity.

The veth pair:

```text
veth-host <========> veth-ovs
```

acts like a virtual Ethernet cable.

Current design:

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

Later OpenStack/Open vSwitch will use:

```text
veth-ovs
   |
 br-ex
   |
Neutron
```

This is OpenStack-specific.

You do NOT need this architecture simply to change the IP of a normal Ubuntu VM.

---

# 15. Bridge Verification Commands

Show Linux bridge ports:

```bash
bridge link
```

Example:

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
9. Our bridge and veth pair exist because of the single-NIC OpenStack design.
10. Never assume that because a YAML file looks valid, remote connectivity will survive the change.
