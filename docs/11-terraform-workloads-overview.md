# Terraform Workloads Overview

This repository currently contains two OpenStack Terraform workloads.

---

## 01-first-workload

Path:

```text
terraform/01-first-workload/
```

### Purpose

This was the first Terraform learning workload.

It was created manually while learning how Terraform maps to the OpenStack
resources previously created with the OpenStack CLI.

### Architecture

```text
public network
     |
 tf-router
     |
10.10.20.0/24
     |
 tf-private
     |
tf-cirros-01
     |
floating IP
```

### Terraform manages

- private network `tf-private`
- subnet `10.10.20.0/24`
- router `tf-router`
- security group `tf-sg`
- ICMP ingress
- SSH TCP/22 ingress
- keypair `tf-key`
- VM `tf-cirros-01`
- floating IP and association

### Existing resources reused as data sources

- public network
- `cirros-0.6.3` image
- `m1.cirros` flavor

### Purpose of this workload

```text
Learn Terraform
Understand state
Learn plan/apply/destroy
Prove infrastructure can be rebuilt
```

This workload was written and operated manually by Joe.

---

## 02-ai-lab

Path:

```text
terraform/02-ai-lab/
```

### Purpose

This workload demonstrates AI-assisted Infrastructure as Code.

Hermes generates or modifies Terraform files.

Hermes does not execute Terraform.

Joe reviews and executes all Terraform commands.

### Architecture

```text
public network
     |
 ai-router
     |
10.20.0.0/24
     |
 ai-private
     |
     +-- ai-cirros-01
     |      fixed:    10.20.0.188
     |      floating: 192.168.0.153
     |
     +-- ai-cirros-02
            fixed:    10.20.0.166
            floating: 192.168.0.157
```

### Terraform manages

- private network `ai-private`
- subnet `ai-private-subnet`
- CIDR `10.20.0.0/24`
- router `ai-router`
- security group `ai-sg`
- ICMP ingress
- SSH TCP/22 ingress
- keypair `ai-key`
- VM `ai-cirros-01`
- VM `ai-cirros-02`
- one floating IP per VM
- floating-IP associations

### Existing resources reused as data sources

- public network
- `cirros-0.6.3` image
- `m1.cirros` flavor

### Authentication

Terraform does not hard-code an OpenStack cloud:

```hcl
provider "openstack" {
}
```

Joe selects the OpenStack identity before execution.

For this workload:

```bash
export OS_CLIENT_CONFIG_FILE="$HOME/.config/openstack/hermes-clouds.yaml"
export OS_CLOUD=hermes-operator
```

OpenStack identity:

```text
Project: ai-lab
User:    hermes-operator
Role:    member
```

### AI workflow

```text
Joe asks Hermes
      |
      v
Hermes writes Terraform
      |
      v
Hermes stops
      |
      v
Joe reviews git diff
      |
      v
terraform validate
      |
      v
terraform plan
      |
      v
Joe approves
      |
      v
terraform apply
```

Hermes Terminal access is disabled.

Hermes can edit files but cannot directly run Terraform, OpenStack CLI,
Ansible, SSH, sudo, or Git commands.

---

## Main Difference

```text
01-first-workload
-----------------
Human writes Terraform
Human runs Terraform
Purpose: learn Terraform


02-ai-lab
---------
Hermes writes Terraform
Human reviews Terraform
Human runs Terraform
Purpose: learn AI-assisted IaC
```

The important principle for `02-ai-lab` is:

```text
AI writes IaC.
Human selects credentials.
Human reviews the plan.
Human executes the change.
```

