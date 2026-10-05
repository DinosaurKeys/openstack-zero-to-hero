# AI-Assisted OpenStack

This directory documents the AI-assisted OpenStack automation project.

## Goal

Build a controlled AI operator using:

- Hermes
- Claude or OpenRouter
- Terraform / OpenTofu
- Ansible
- Git
- OpenStack APIs

## Target Workflow

```text
User
 |
 v
Hermes / LLM
 |
 v
Git Repository
 |
 v
Terraform / OpenTofu
 |
 | fmt
 | validate
 | plan
 v
Human Approval
 |
 v
terraform apply
 |
 v
Restricted OpenStack Credential
 |
 v
OpenStack APIs
```

## Initial Security Rules

Hermes may:

- read the repository
- inspect Terraform configuration
- generate Terraform code
- run `terraform fmt`
- run `terraform validate`
- run `terraform plan`
- explain proposed changes

Hermes must not initially:

- automatically run `terraform apply`
- automatically run `terraform destroy`
- use unrestricted OpenStack administrator credentials
- SSH to node1, node2, or node3 as root
- modify Kolla configuration without approval
- perform unrestricted Keystone administration

## Project Direction

The goal is not:

```text
AI -> unrestricted shell -> OpenStack admin
```

The goal is:

```text
Natural-language request
        |
        v
Hermes / LLM
        |
        v
Terraform change
        |
        v
Git diff
        |
        v
terraform plan
        |
        v
Human review / approval
        |
        v
OpenStack
```

