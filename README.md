# OpenStack Zero to Hero

A practical three-node OpenStack homelab built from zero using Ubuntu, Ansible, Kolla-Ansible, Terraform, and AI-assisted Infrastructure as Code.

This repository documents the actual evolution of the lab — including working configurations, mistakes, migrations, troubleshooting, recovery procedures, and lessons learned.

The goal is not only to build OpenStack.

The goal is to understand how the infrastructure works and use it as a platform for learning:

```text
Linux
  ↓
Networking
  ↓
Ansible
  ↓
OpenStack
  ↓
Terraform
  ↓
AI-assisted IaC
  ↓
Operations / Monitoring
```

---

# Lab Architecture

The lab currently consists of three Lenovo ThinkCentre M910q systems.

```text
node1    192.168.0.200
node2    192.168.0.201
node3    192.168.0.202
```

OpenStack internal API VIP:

```text
192.168.0.100
```

Deployment/control machine:

```text
Hermes
```

Hermes runs tools such as:

```text
Ansible
Kolla-Ansible
Terraform
OpenStack CLI
AI-assisted IaC tooling
```

---

# Current Network Architecture

Each OpenStack node uses two physical network interfaces.

```text
                     OpenStack Node
                           |
          +----------------+----------------+
          |                                 |
          |                                 |
      enp0s31f6                           ext0
          |                                 |
          v                                 v
      br-mgmt                             br-ex
          |                                 |
          |                                 |
Management / API / VXLAN          Neutron External Network
```

Management addresses:

```text
node1 br-mgmt = 192.168.0.200/24
node2 br-mgmt = 192.168.0.201/24
node3 br-mgmt = 192.168.0.202/24
```

Kolla-Ansible uses:

```yaml
network_interface: "br-mgmt"
neutron_external_interface: "ext0"
```

The original lab used a single physical NIC with a Linux bridge and veth pair.

That configuration is intentionally preserved in this repository because it is useful for learning Linux networking and for people building OpenStack systems with only one physical NIC.

The lab was later upgraded to a dedicated second NIC for Neutron external traffic.

---

# Learning Path

The documentation is designed to be read approximately in order.

## Part 1 — Build the Foundation

### 00 — Hermes Client Zero to Hero

```text
docs/00-hermes-client-zero-to-hero.md
```

Build the Linux control machine used to manage the lab.

Topics include:

```text
Linux
Git
Ansible
Terraform
Hermes
SSH
```

### 01 — Node Bootstrap and Ansible

```text
docs/01-node-bootstrap-and-ansible.md
```

Prepare the three OpenStack nodes and establish Ansible connectivity.

### 02 — Ubuntu Networking 101

```text
docs/02-ubuntu-networking-101.md
```

Learn the Ubuntu and Netplan networking concepts required before modifying OpenStack networking.

### 03 — OpenStack Single-NIC Networking

```text
docs/03-openstack-single-nic-networking.md
```

The original OpenStack network design.

This chapter is intentionally preserved as a learning exercise.

It demonstrates:

```text
Linux bridges
veth pairs
Netplan
Layer-2 connectivity
OpenStack external networking
```

---

# Part 2 — Understand OpenStack

### 04 — OpenStack Architecture 101

```text
docs/04-openstack-architecture-101.md
```

Understand the major OpenStack services and how they communicate.

### 05 — Neutron Packet Walk

```text
docs/05-neutron-packet-walk.md
```

Follow VM traffic through Neutron, Open vSwitch, routers, NAT, and external networking.

### 06 — Neutron Router Agents and HA

```text
docs/06-neutron-router-agents-and-ha.md
```

Understand Neutron routing and high availability.

### 07 — Kolla-Ansible Deployment

```text
docs/07-kolla-deployment-101.md
```

Understand what Kolla-Ansible does during:

```text
bootstrap-servers
prechecks
deploy
post-deploy
```

### 08 — First Tenant and VM

```text
docs/08-openstack-first-tenant-and-vm.md
```

Create the first OpenStack project, networks, router, security groups, floating IP, and VM.

### 09 — Inside an OpenStack VM

```text
docs/09-inside-an-openstack-vm.md
```

Understand what happens inside an OpenStack instance.

---

# Part 3 — Infrastructure as Code

### 10 — Terraform OpenStack 101

```text
docs/10-terraform-openstack-101.md
```

Start managing OpenStack infrastructure using Terraform.

### 11 — Terraform Workloads

```text
docs/11-terraform-workloads-overview.md
```

Review the Terraform workloads stored under:

```text
terraform/
```

### 12 — Hermes Modifying Infrastructure

```text
docs/12-hermes-modify-existing-infrastructure.md
```

Introduce AI-assisted Infrastructure as Code.

### 13 — Terraform Drift Detection

```text
docs/13-terraform-drift-detection.md
```

Learn what happens when real infrastructure no longer matches Terraform state.

### 14 — Hermes Security Guardrails

```text
docs/14-hermes-security-guardrail-test.md
```

Test the security boundaries around the AI assistant.

### 15 — Terraform Destructive Plan Protection

```text
docs/15-terraform-destructive-plan-protection.md
```

Detect dangerous Terraform changes before applying them.

---

# Part 4 — Troubleshooting and Operations

### 16 — RabbitMQ, Heat and Fanout Troubleshooting

```text
docs/16-rabbitmq-heat-and-fanout-troubleshooting.md
```

Document real troubleshooting performed against the running cluster.

### 17 — OpenStack Dual-NIC Networking

```text
docs/17-openstack-dual-nic-networking.md
```

Documents the upgrade from:

```text
single physical NIC
+
veth workaround
```

to:

```text
management NIC
+
dedicated Neutron external NIC
```

This is the current network architecture.

### OpenStack Reboot and Recovery Runbook

```text
docs/openstack-reboot-and-recovery-runbook.md
```

Documents controlled startup, shutdown, health verification, MariaDB recovery, Nova/Neutron recovery, and RabbitMQ last-resort recovery procedures.

---

# Automation

## Ansible

```text
ansible/
```

Contains inventory and host-preparation playbooks.

The Ansible examples are intentionally readable so the repository can also be used as a learning resource.

## Kolla-Ansible

```text
kolla/
```

Contains the multinode inventory used to deploy the OpenStack cluster.

Sensitive Kolla credentials are not stored in Git.

## Terraform

```text
terraform/
```

Contains real OpenStack workloads managed with Terraform.

Current examples include:

```text
01-first-workload
02-ai-lab
```

## AI-Assisted IaC

```text
AI/
```

Documents the security model used for Hermes-assisted infrastructure work.

The preferred model is:

```text
Human request
      |
      v
Hermes / AI
      |
      v
Write or modify IaC
      |
      v
Git diff
      |
      v
Human review
      |
      v
terraform validate / plan
      |
      v
Human approval
      |
      v
terraform apply
```

The goal is not:

```text
AI
 |
 v
unrestricted root shell
 |
 v
OpenStack administrator
```

Human approval remains part of the infrastructure workflow.

---

# Operations Scripts

The repository includes helper scripts under:

```text
scripts/
```

Current tools include:

```text
lab-status.sh
lab-recover.sh
```

`lab-status.sh` provides a health summary of the OpenStack cluster.

`lab-recover.sh` assists with known recovery procedures while intentionally avoiding destructive last-resort operations such as automatically resetting RabbitMQ state.

---

# Current Lab Status

The three-node cluster has been validated with:

```text
3/3 nodes reachable
3/3 MariaDB containers healthy
3/3 ProxySQL healthy
Placement healthy
Nova control services healthy
3/3 nova-compute services up
3/3 hypervisors up
12/12 Neutron agents alive
Floating IP connectivity working
Dual-NIC networking working
```

The normal health-check target is:

```text
RESULT: HEALTHY
PASS checks: 14
```

---

# Planned Learning Labs

Once the OpenStack foundation is stable, the lab will be used for practical infrastructure exercises.

Planned examples include:

```text
NGINX web server
Grafana monitoring
Ansible configuration management
Terraform provisioning
AI-assisted IaC workflows
```

These workloads will be used to practice automation rather than continually redesigning the OpenStack foundation.

---

# Project Philosophy

This repository is not intended to show a perfect environment that appeared fully formed.

It documents the journey.

Some earlier configurations are intentionally kept because understanding why they worked — and why they were later changed — is valuable.

The objective is:

```text
Build it
Understand it
Break it safely
Recover it
Automate it
Document it
Learn from it
```

The final goal is to develop practical skills in:

```text
Linux
Networking
OpenStack
Ansible
Terraform
Infrastructure as Code
AI-assisted operations
Troubleshooting
Monitoring
```
