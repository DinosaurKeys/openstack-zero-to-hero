# Hermes Client: Zero to Hero for the OpenStack Homelab

This guide documents the management workstation used for the OpenStack Kolla-Ansible homelab.

The goal is simple:

- keep Hermes isolated from the personal Windows profile
- use Hermes as an AI-assisted Linux/IaC workstation
- keep browser, personal files, and unnecessary integrations out of scope
- install the tools needed for OpenStack automation
- understand every layer instead of blindly running commands

> **Lab principle:** Hermes is useful because it can run terminal commands and work with files. Treat it like a privileged automation tool, not like a normal chat application.

---

## 1. Architecture

```text
Personal Windows laptop
|
+-- Personal Windows environment
|   +-- Browser
|   +-- Password manager
|   +-- Documents
|   +-- OneDrive / personal files
|
+-- VMware Workstation
    |
    +-- hermes-mgmt
        Ubuntu Server 24.04 LTS
        VMware NAT
        |
        +-- Hermes Agent
        +-- Git
        +-- SSH
        +-- Python virtual environment
        +-- Ansible
        +-- Kolla-Ansible
        +-- Terraform
        |
        +-- SSH --> node1 192.168.0.200
        +-- SSH --> node2 192.168.0.201
        +-- SSH --> node3 192.168.0.202
```

Hermes runs inside a dedicated Ubuntu VM instead of directly on the personal Windows installation.

### Why use a dedicated VM?

Hermes can use terminal and file tools. Those tools run with the permissions of the Linux user running Hermes.

The VM is therefore the real security boundary:

```text
Hermes
  |
  +-- can work inside the Ubuntu VM
  |
  X  no Windows shared folders
  X  no personal browser profile
  X  no personal Windows SSH keys
```

Do not treat application-level tool switches as a replacement for OS isolation.

---

## 2. VMware VM configuration

Recommended VM:

| Setting | Value |
|---|---|
| Name | `hermes-mgmt` |
| OS | Ubuntu Server 24.04 LTS |
| CPU | 4 vCPU |
| RAM | 8 GB |
| Disk | 40-60 GB |
| Network | VMware NAT |
| Firmware | UEFI |
| Linux user | `joe` |
| Hostname | `hermes` or `hermes-mgmt` |

### VMware isolation settings

Disable:

- Shared Folders
- Drag and Drop
- Copy and Paste

Do not map Windows locations such as:

- `C:\`
- Documents
- Downloads
- OneDrive
- browser profile folders

### Why NAT?

The Hermes VM does not need to be directly exposed on the home LAN.

Typical traffic flow:

```text
hermes-mgmt
   |
   | VMware NAT
   v
Windows host
   |
   +--> 192.168.0.200
   +--> 192.168.0.201
   +--> 192.168.0.202
```

The VM can normally initiate connections to the physical OpenStack nodes while remaining behind VMware NAT.

---

## 3. Install Ubuntu Server 24.04

During installation:

```text
OS:       Ubuntu Server 24.04 LTS
Hostname: hermes
User:     joe
SSH:      Install OpenSSH Server
```

Do not install Docker, Kubernetes, OpenStack, or other unnecessary software during the OS installation.

---

## 4. First boot checks

Check the host:

```bash
hostnamectl
```

Check interfaces:

```bash
ip -br addr
```

Check routing:

```bash
ip route
```

Check Internet connectivity:

```bash
ping -c 3 1.1.1.1
ping -c 3 github.com
```

### Check disk space before installing Hermes

```bash
df -h
lsblk
```

Do not continue with a nearly-full root filesystem.

A 40-60 GB virtual disk is recommended for this management VM because the machine will eventually contain Python environments, Ansible collections, Terraform plugins, Git repositories, logs, and OpenStack tooling.

---

## 5. Update Ubuntu

```bash
sudo apt update
sudo apt full-upgrade -y
```

Install basic packages:

```bash
sudo apt install -y \
  git \
  curl \
  wget \
  vim \
  jq \
  unzip \
  tree \
  htop \
  tmux \
  openssh-client \
  ca-certificates \
  gnupg \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  libffi-dev \
  gcc \
  libssl-dev \
  libdbus-glib-1-dev
```

Reboot:

```bash
sudo reboot
```

---

## 6. Take a VMware snapshot

Before installing Hermes, create a snapshot such as:

```text
Ubuntu-clean-before-Hermes
```

This gives a simple rollback point if an experiment damages the VM.

---

## 7. Install Hermes

For a cautious installation, download the official installer first instead of immediately piping it into Bash.

```bash
cd ~
curl -fsSL \
  https://hermes-agent.nousresearch.com/install.sh \
  -o hermes-install.sh
```

Inspect it:

```bash
less hermes-install.sh
```

Then install:

```bash
bash hermes-install.sh
```

Do **not** run the Hermes installer with `sudo`.

Reload the shell:

```bash
source ~/.bashrc
```

Verify:

```bash
hermes --help
hermes doctor
```

Official project:

- https://github.com/NousResearch/hermes-agent
- https://hermes-agent.nousresearch.com/docs/getting-started/installation

---

## 8. Initial Hermes setup

When Hermes asks which setup path to use, select:

```text
Blank Slate
```

The purpose is to start with the smallest capability set and enable only what is needed.

### Model provider

Choose:

```text
OpenRouter
```

Use a **dedicated OpenRouter API key** for this VM.

Do not reuse a high-value API key shared by unrelated projects.

### Free model during learning

For initial testing use:

```text
openrouter/free
```

This avoids consuming paid model credits while learning the workflow.

Free-model availability and limits can change, so verify the current OpenRouter model list when needed.

---

## 9. Configure Hermes tools

After setup:

```bash
hermes tools
```

For this OpenStack management VM, keep the initial tool surface deliberately small.

### Enable

```text
Terminal & Processes
File Operations
Skills
Clarifying Questions
```

Optional:

```text
Vision / Image Analysis
```

### Disable initially

```text
Web Search & Scraping
Browser Automation
Code Execution
Memory
Session Search
Connections
Delegation
Cron Jobs
Computer Use
Discord
Discord Admin
Spotify
Home Assistant
Image Generation
Video Generation
Text-to-Speech
X Search
```

The exact menu can change between Hermes versions. The principle matters more than the count:

> Enable only capabilities required for the current job.

### Why Terminal is allowed

Terminal access is required for the lab because Hermes will eventually help run:

```text
ssh
git
ansible
ansible-playbook
kolla-ansible
terraform
```

Terminal access is powerful. This is exactly why Hermes lives in an isolated VM.

---

## 10. Verify Hermes configuration

Useful checks:

```bash
hermes doctor
hermes tools
hermes config show
```

Do not assume a setup mode selected exactly the options expected. Verify the effective configuration after installation.

### Start the Hermes chat correctly

Run:

```bash
hermes chat
```

Then type natural-language prompts inside the Hermes interface.

Example:

```text
Explain what ip -br addr does. Do not execute any commands.
```

Do not type that directly at the normal Linux prompt:

```text
joe@hermes:~$
```

The Linux shell will interpret the first word as a command.

---

## 11. Install the OpenStack/IaC toolchain

Hermes itself does not contain Ansible or Terraform.

The relationship is:

```text
Hermes
   |
   +-- Terminal & Processes
          |
          +-- ssh
          +-- git
          +-- ansible
          +-- kolla-ansible
          +-- terraform
```

---

## 12. Install Kolla-Ansible in a Python virtual environment

Do not install the lab's Kolla-Ansible stack globally with `apt`.

Create a Python virtual environment:

```bash
mkdir -p ~/venvs
python3 -m venv ~/venvs/kolla
source ~/venvs/kolla/bin/activate
```

The shell should now look similar to:

```text
(kolla) joe@hermes:~$
```

Upgrade pip:

```bash
pip install -U pip
```

Install the Kolla-Ansible 2026.1 branch:

```bash
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2026.1
```

Install Kolla's Ansible dependencies:

```bash
kolla-ansible install-deps
```

Verify:

```bash
ansible --version
kolla-ansible --version
```

Lab versions observed during this build:

```text
Ansible Core:   2.20.9
Kolla-Ansible:  22.2.1.dev10
Python:         3.12.3
```

Official Kolla-Ansible documentation:

- https://docs.openstack.org/kolla-ansible/2026.1/user/quickstart.html

---

## 13. Install Terraform

Add HashiCorp's signing key:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
```

Add the repository:

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list
```

Install Terraform:

```bash
sudo apt update
sudo apt install -y terraform
```

Verify:

```bash
terraform version
```

Lab version observed:

```text
Terraform v1.16.4
```

Official Terraform installation documentation:

- https://developer.hashicorp.com/terraform/install

---

## 14. Verify the complete toolchain

```bash
ssh -V
git --version
terraform version

source ~/venvs/kolla/bin/activate

ansible --version
kolla-ansible --version
```

Expected components:

```text
OpenSSH
Git
Terraform
Python 3
Ansible Core
Kolla-Ansible
```

---

## 15. Create a dedicated SSH key

Create a key specifically for this homelab:

```bash
ssh-keygen -t ed25519 -C "hermes-openstack-lab"
```

Default location:

```text
/home/joe/.ssh/id_ed25519
/home/joe/.ssh/id_ed25519.pub
```

Important:

```text
id_ed25519       PRIVATE KEY - never commit or share
id_ed25519.pub   PUBLIC KEY  - copy to managed nodes
```

Do not copy a personal Windows SSH private key into this VM.

After the OpenStack nodes are rebuilt, the public key can be installed with:

```bash
ssh-copy-id joe@192.168.0.200
ssh-copy-id joe@192.168.0.201
ssh-copy-id joe@192.168.0.202
```

---

## 16. Clone the homelab repository

```bash
mkdir -p ~/git
cd ~/git

git clone https://github.com/DinosaurKeys/openstack-kolla-homelab.git
cd openstack-kolla-homelab
```

Verify:

```bash
git status
tree -L 2
```

The management VM now becomes the deployment workstation for the entire lab.

---

## 17. Final design

```text
hermes-mgmt
Ubuntu Server 24.04
|
+-- Hermes Agent
|   +-- minimal tool access
|   +-- OpenRouter
|   +-- openrouter/free while learning
|
+-- Git
|
+-- SSH
|   +-- dedicated homelab key
|
+-- ~/venvs/kolla
|   +-- Ansible
|   +-- Kolla-Ansible
|
+-- Terraform
|
+-- ~/git/openstack-kolla-homelab
|
+-- SSH --> node1
+-- SSH --> node2
+-- SSH --> node3
```

---

## 18. Security checklist

Before giving Hermes access to the OpenStack nodes:

- [ ] Hermes runs inside a dedicated VM
- [ ] VMware Shared Folders are disabled
- [ ] Drag and Drop is disabled
- [ ] Copy and Paste is disabled
- [ ] No personal browser profile is present
- [ ] No personal Windows SSH private keys are present
- [ ] OpenRouter uses a dedicated API key
- [ ] Browser Automation is disabled
- [ ] Computer Use is disabled
- [ ] Connections are disabled
- [ ] Cron Jobs are disabled
- [ ] Memory is disabled unless deliberately required
- [ ] Terminal access is intentionally enabled
- [ ] File access is intentionally enabled
- [ ] A dedicated homelab SSH key is used
- [ ] Secrets are excluded from Git

Never commit:

```text
/etc/kolla/passwords.yml
admin-openrc.sh
clouds.yaml with credentials
*.tfstate
*.tfstate.*
terraform.tfvars containing secrets
.env
SSH private keys
OpenRouter API keys
```

---

## 19. Troubleshooting

### Error: No space left on device

Observed during this build:

```text
OSError: [Errno 28] No space left on device
```

Check:

```bash
df -h
df -i
lsblk
sudo pvs
sudo vgs
sudo lvs
```

In this lab, the LVM volume group had free space while the root logical volume was only 10 GB.

The recovery command was:

```bash
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
```

Then verify:

```bash
df -h /
```

Do not blindly run this command on another system. First verify the LVM layout and that the volume group actually contains free extents.

### VMware virtual disk was expanded but Ubuntu did not grow

Increasing a VMDK only enlarges the virtual block device.

Depending on the partitioning layout, there may still be additional layers to expand:

```text
VMDK
  |
partition
  |
LVM Physical Volume
  |
Volume Group
  |
Logical Volume
  |
filesystem
```

Always inspect `lsblk`, `pvs`, `vgs`, and `lvs` before changing partitions.

### Natural-language prompt produces "Command not found"

Wrong:

```text
joe@hermes:~$ Explain what ip -br addr does
```

That is the Linux shell.

Correct:

```bash
hermes chat
```

Then enter the question inside Hermes.

### NAT VM cannot reach the OpenStack nodes

Check:

```bash
ip -br addr
ip route
ping -c 3 192.168.0.200
```

If VMware NAT does not route correctly to the physical LAN on the host, switch the management VM to Bridged networking and retest. NAT is preferred initially because it reduces unnecessary inbound exposure.

---

## 20. Screenshots

Recommended repository layout:

```text
docs/
├── 00-hermes-client-zero-to-hero.md
└── images/
    └── hermes/
        ├── image0.jpeg
        ├── image1.jpeg
        └── image2.jpeg
```

Example Markdown references:

```markdown
![Hermes provider selection](images/hermes/image0.jpeg)

![Hermes setup](images/hermes/image1.jpeg)

![Hermes tool configuration](images/hermes/image2.jpeg)
```

Add screenshots only after checking that they do **not** show API keys, passwords, tokens, private SSH keys, or other secrets.

---

## 21. Next phase

The Hermes management client is now ready.

Next:

```text
Reinstall node1/node2/node3 with Ubuntu Server 24.04
        |
        v
configure static networking
        |
        v
copy dedicated SSH public key
        |
        v
manual Linux preparation
        |
        v
Ansible automation
        |
        v
Kolla-Ansible deployment
        |
        v
manual OpenStack resources
        |
        v
Terraform
        |
        v
Hermes-assisted IaC review
```

The purpose of Hermes in this project is not to replace understanding. It is to become a controlled assistant around a workflow that remains reproducible with Git, Ansible, Kolla-Ansible, and Terraform.
