# Hermes OpenStack Operator v1

## Goal

Use Hermes as an AI Infrastructure-as-Code assistant.

Hermes writes Terraform and Ansible code only.

Joe reviews and executes infrastructure commands.

## Architecture

```text
Joe
 |
 v
Hermes + OpenRouter
 |
 | File Operations only
 v
Terraform / Ansible
 |
 v
STOP
 |
 v
Joe reviews
 |
 +-- terraform validate
 +-- terraform plan
 +-- terraform apply
 |
 v
OpenStack
```

## Security Model

Hermes is configured with:

- File Operations
- Skills
- Clarifying Questions

Terminal access is disabled.

Hermes writes IaC files only. Joe executes Terraform and Ansible commands.

Hermes must never choose or embed OpenStack administrator credentials.

## OpenStack Authentication

The Terraform provider does not specify a cloud:

```hcl
provider "openstack" {
}
```

Joe selects the OpenStack identity before execution.

For the AI lab:

    export OS_CLIENT_CONFIG_FILE="$HOME/.config/openstack/hermes-clouds.yaml"
    export OS_CLOUD=hermes-operator

Restricted identity:

- Project: ai-lab
- User: hermes-operator
- Role: member

During the first test Hermes copied kolla-admin from the reference workload.

This was corrected.

Lesson learned:

    AI writes IaC.
    Human selects credentials.
    Human executes IaC.

## First AI-Generated Workload

Hermes created terraform/02-ai-lab with:

- ai-private network
- ai-private-subnet
- 10.20.0.0/24
- ai-router
- ai-sg
- ICMP ingress
- SSH TCP/22 ingress
- ai-key
- ai-cirros-01
- floating IP

Joe then ran:

    terraform init
    terraform validate
    terraform plan

Plan result:

    11 to add
    0 to change
    0 to destroy

Joe reviewed the plan and manually ran terraform apply.

Result:

    Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

VM validation:

- Name: ai-cirros-01
- Status: ACTIVE
- Fixed IP: 10.20.0.188
- Floating IP: 192.168.0.153
- SSH: PASS
- Gateway connectivity: PASS
- Internet connectivity: PASS

## Final Workflow

Hermes writes IaC.

Hermes stops.

Joe reviews, validates, plans, and applies.

This is the preferred Hermes OpenStack Operator v1 workflow.
