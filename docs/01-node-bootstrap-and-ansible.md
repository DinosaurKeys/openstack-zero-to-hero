# Node Bootstrap and Ansible

This document describes how the three Ubuntu OpenStack nodes were prepared for automated management with Ansible.

The goal was to first understand the manual process and then automate it.

---

# 1. Lab Nodes

The OpenStack lab consists of three Lenovo ThinkCentre M910q systems.

| Node | Management IP | OS |
|---|---|---|
| node1 | 192.168.0.200 | Ubuntu 24.04 LTS |
| node2 | 192.168.0.201 | Ubuntu 24.04 LTS |
| node3 | 192.168.0.202 | Ubuntu 24.04 LTS |

The management workstation is the Hermes VM.

```text
Hermes VM
   |
   | SSH / Ansible
   |
   +---- node1 192.168.0.200
   +---- node2 192.168.0.201
   +---- node3 192.168.0.202
```

---

# 2. Verify Each Node

Before configuring automation, verify the hostname and operating system locally.

```bash
hostname
hostnamectl
```

Example:

```text
Static hostname: node1
Operating System: Ubuntu 24.04.5 LTS
Architecture: x86-64
Hardware Vendor: Lenovo
Hardware Model: ThinkCentre M910q
```

Verify the current IP address:

```bash
ip -br addr
```

Verify routing:

```bash
ip route
```

Expected management addresses:

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

# 3. Human User vs Automation User

The normal human administration account is:

```text
joe
```

A separate account was created for automation:

```text
openstack
```

The purpose is separation of responsibility.

```text
joe
 |
 +-- human administration

openstack
 |
 +-- Ansible
 +-- Kolla-Ansible
 +-- automation
```

This is cleaner than using the normal personal account for every automated action.

---

# 4. Create the Automation User

On each node:

```bash
sudo adduser openstack
```

Add the user to the sudo group:

```bash
sudo usermod -aG sudo openstack
```

Verify:

```bash
id openstack
```

The output should show membership in the `sudo` group.

---

# 5. Configure Passwordless Sudo

Create a dedicated sudoers file:

```bash
echo 'openstack ALL=(ALL) NOPASSWD:ALL' | \
sudo tee /etc/sudoers.d/90-openstack
```

Protect it:

```bash
sudo chmod 440 /etc/sudoers.d/90-openstack
```

Validate its syntax:

```bash
sudo visudo -cf /etc/sudoers.d/90-openstack
```

Expected:

```text
/etc/sudoers.d/90-openstack: parsed OK
```

---

# 6. Important: SSH Password vs sudo Password

These are different authentication mechanisms.

Passwordless sudo:

```text
openstack
   |
 sudo
   |
 root
```

is controlled by:

```text
/etc/sudoers.d/90-openstack
```

Passwordless SSH:

```text
Hermes
   |
 SSH key
   |
 openstack@node
```

is controlled by SSH public-key authentication.

`NOPASSWD` in sudoers does NOT automatically make SSH passwordless.

---

# 7. Create an SSH Key on Hermes

On Hermes, check whether an SSH key already exists:

```bash
ls -l ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

If it does not exist:

```bash
ssh-keygen -t ed25519 -C "hermes-openstack-lab"
```

The private key is:

```text
~/.ssh/id_ed25519
```

The public key is:

```text
~/.ssh/id_ed25519.pub
```

Never commit the private key to Git.

---

# 8. Copy the SSH Key to the Nodes

From Hermes:

```bash
ssh-copy-id openstack@192.168.0.200
```

```bash
ssh-copy-id openstack@192.168.0.201
```

```bash
ssh-copy-id openstack@192.168.0.202
```

The password for the `openstack` account is needed the first time.

After the key is installed, test:

```bash
ssh openstack@192.168.0.200
```

```bash
ssh openstack@192.168.0.201
```

```bash
ssh openstack@192.168.0.202
```

No remote account password should be requested.

---

# 9. Verify the Automation User

After connecting to a node:

```bash
hostname
whoami
sudo whoami
```

Example on node1:

```text
node1
openstack
root
```

This proves:

```text
SSH login user = openstack
sudo privilege = root
```

---

# 10. Create the Ansible Inventory

On Hermes, inside the repository:

```text
ansible/inventory.ini
```

The inventory is:

```ini
[openstack]
node1 ansible_host=192.168.0.200
node2 ansible_host=192.168.0.201
node3 ansible_host=192.168.0.202

[openstack:vars]
ansible_user=openstack
ansible_become=true
ansible_become_method=sudo
ansible_python_interpreter=/usr/bin/python3
```

The variable:

```ini
ansible_user=openstack
```

tells Ansible which remote user to use.

The variable:

```ini
ansible_become=true
```

allows privilege escalation with sudo.

The variable:

```ini
ansible_python_interpreter=/usr/bin/python3
```

avoids Python interpreter discovery warnings.

---

# 11. Test Ansible Connectivity

From Hermes:

```bash
ansible all \
  -i ansible/inventory.ini \
  -m ping
```

Expected:

```text
node1 | SUCCESS
node2 | SUCCESS
node3 | SUCCESS
```

Ansible's `ping` module is not the same as ICMP ping.

It verifies:

```text
Hermes
   |
 SSH
   |
 remote Python
   |
 Ansible module execution
```

A successful Ansible ping therefore confirms several things at once:

```text
SSH connectivity
SSH authentication
Python availability
Ansible execution
```

---

# 12. Verify Hostnames with Ansible

Run:

```bash
ansible all \
  -i ansible/inventory.ini \
  -m command \
  -a "hostname"
```

Expected:

```text
node1 -> node1
node2 -> node2
node3 -> node3
```

---

# 13. Verify Passwordless sudo with Ansible

Run:

```bash
ansible all \
  -i ansible/inventory.ini \
  -b \
  -m command \
  -a "whoami"
```

Expected on every node:

```text
root
```

This proves:

```text
Hermes
  |
Ansible
  |
SSH as openstack
  |
sudo
  |
root
```

---

# 14. First Ansible Playbook

The first real playbook is:

```text
ansible/playbooks/01-base-preparation.yml
```

Its purpose is to create a common baseline on all three nodes.

It performs tasks such as:

```text
update APT cache
install administration tools
populate /etc/hosts
verify hostnames
```

Run it with:

```bash
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/01-base-preparation.yml
```

---

# 15. Understanding Idempotency

Ansible playbooks should normally be idempotent.

That means:

```text
first run
 |
 | system does not match desired state
 |
 changes are made
```

Then:

```text
second run
 |
 | system already matches desired state
 |
 little or nothing changes
```

Our second run showed:

```text
node1 changed=0
node2 changed=0
node3 changed=0
```

That demonstrated idempotency.

---

# 16. OpenStack Preflight Playbook

The second playbook is:

```text
ansible/playbooks/02-preflight.yml
```

Its purpose is to inspect the nodes before deploying OpenStack.

It checks:

```text
hostname
network interfaces
routes
RAM
disks
CPU virtualization
/dev/kvm
NTP
swap
```

Run:

```bash
ansible-playbook \
  -i ansible/inventory.ini \
  ansible/playbooks/02-preflight.yml
```

---

# 17. Preflight Results

All three nodes successfully showed approximately:

```text
RAM: 15 GiB
CPU virtualization flags: 8
/dev/kvm: present
NTP synchronized: yes
Swap: 4 GiB
```

Management network:

```text
node1 = 192.168.0.200/24
node2 = 192.168.0.201/24
node3 = 192.168.0.202/24
```

At this stage the management NIC was:

```text
enp0s31f6
```

---

# 18. KVM Verification

KVM support was already available from the Linux kernel.

Check:

```bash
ls -l /dev/kvm
```

Example:

```text
crw-rw---- 1 root kvm ... /dev/kvm
```

Check loaded modules:

```bash
lsmod | grep kvm
```

Example:

```text
kvm_intel
kvm
irqbypass
```

Check whether QEMU/libvirt was manually installed:

```bash
dpkg -l | grep -E 'qemu-kvm|libvirt'
```

No output was expected at this stage.

We did not manually install the complete QEMU/libvirt stack because Kolla-Ansible will later manage the OpenStack compute components.

---

# 19. Useful Ansible Ad-Hoc Commands

Ping every node:

```bash
ansible all -i ansible/inventory.ini -m ping
```

Run `hostname` everywhere:

```bash
ansible all \
  -i ansible/inventory.ini \
  -m command \
  -a "hostname"
```

Run a privileged command:

```bash
ansible all \
  -i ansible/inventory.ini \
  -b \
  -m command \
  -a "whoami"
```

Show addresses:

```bash
ansible all \
  -i ansible/inventory.ini \
  -m command \
  -a "ip -br addr"
```

Show routes:

```bash
ansible all \
  -i ansible/inventory.ini \
  -m command \
  -a "ip route"
```

---

# 20. Important Ansible Output Detail

Commands such as:

```bash
ansible all -m command -a "hostname"
```

may display:

```text
CHANGED
```

even though the command only read information.

For ad-hoc `command` and `shell` tasks, Ansible may report `changed` by default.

For playbook checks where no configuration is being modified, use:

```yaml
changed_when: false
```

Example:

```yaml
- name: Verify hostname
  ansible.builtin.command: hostname
  register: hostname_result
  changed_when: false
```

---

# 21. Current Repository Structure

At this phase:

```text
openstack-zero-to-hero/
|
├── ansible/
│   ├── inventory.ini
│   └── playbooks/
│       ├── 01-base-preparation.yml
│       ├── 02-preflight.yml
│       └── 03-single-nic-network.yml
|
└── docs/
    ├── 00-hermes-client-zero-to-hero.md
    ├── 01-node-bootstrap-and-ansible.md
    ├── 02-ubuntu-networking-101.md
    └── 03-openstack-single-nic-networking.md
```

---

# 22. Main Lessons

1. Create a dedicated automation account instead of using a personal login.
2. SSH keys and passwordless sudo solve different problems.
3. Validate sudoers files with `visudo`.
4. Test one node manually before automating all nodes.
5. Ansible inventory defines which machines are managed.
6. `ansible -m ping` verifies more than network ICMP connectivity.
7. Use `ansible_become` when root privileges are required.
8. Idempotency means repeat runs should converge toward zero changes.
9. Hardware and networking should be inspected before deploying OpenStack.
10. Automation should replace a process only after the manual process is understood.

---

# 23. Next Phase

The next phase is OpenStack networking.

Because the nodes currently have only one physical Ethernet interface, the lab uses:

```text
enp0s31f6
     |
  br-mgmt
     |
 management IP
```

plus:

```text
veth-host <========> veth-ovs
```

This is documented separately in:

```text
docs/03-openstack-single-nic-networking.md
```
