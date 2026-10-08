# AI-Assisted OpenStack

This directory documents the AI-assisted Infrastructure-as-Code workflow used with the OpenStack homelab.

The current implementation is intentionally conservative.

Hermes acts as an Infrastructure-as-Code assistant.

Hermes does not directly operate the OpenStack infrastructure.

---

# 1. Goal

The goal is to use AI to help create and modify infrastructure code while keeping infrastructure execution under human control.

The toolchain includes:

```text
Hermes
LLM / OpenRouter
Git
Terraform / OpenTofu
Ansible
Kolla-Ansible
OpenStack
```

The current security model separates:

```text
AI reasoning and file changes
```

from:

```text
infrastructure execution
```

---

# 2. Current Operator Model

The current workflow is:

```text
Joe
 |
 v
Hermes / LLM
 |
 | inspect repository
 | create files
 | modify files
 | explain changes
 v
Git working tree
 |
 v
STOP
 |
 v
Joe reviews
 |
 +-- git diff
 +-- terraform fmt
 +-- terraform validate
 +-- terraform plan
 +-- ansible syntax checks
 |
 v
Joe decides whether to execute
 |
 v
OpenStack
```

Hermes writes infrastructure code.

Joe executes infrastructure commands.

---

# 3. What Hermes May Do

Hermes may:

```text
read repository files
inspect Terraform configuration
inspect Ansible configuration
inspect documentation
create Terraform files
modify Terraform files
create Ansible playbooks
modify Ansible playbooks
create documentation
explain proposed changes
ask clarifying questions
```

Hermes may also identify:

```text
possible mistakes
unsafe changes
destructive Terraform actions
credential exposure
configuration drift
missing validation steps
```

---

# 4. What Hermes Must Not Do in Operator v1

Hermes must not execute:

```text
terraform plan
terraform apply
terraform destroy
OpenStack CLI commands
ansible-playbook
Kolla-Ansible
SSH
sudo
```

Hermes must not:

```text
commit Git changes
push Git changes
select administrator credentials
embed administrator credentials
modify infrastructure without human review
bypass the human approval step
```

Terminal execution is intentionally outside the Operator v1 trust boundary.

---

# 5. OpenStack Credentials

Hermes must never choose or embed unrestricted OpenStack administrator credentials.

In particular, generated Terraform must not contain:

```hcl
provider "openstack" {
  cloud = "kolla-admin"
}
```

Preferred provider configuration:

```hcl
provider "openstack" {
}
```

The human operator selects the OpenStack identity at execution time.

For example:

```bash
export OS_CLIENT_CONFIG_FILE="$HOME/.config/openstack/hermes-clouds.yaml"
export OS_CLOUD=hermes-operator
```

The restricted AI-lab identity is:

```text
Project: ai-lab
User:    hermes-operator
Role:    member
```

This prevents generated IaC from silently selecting an administrator account.

---

# 6. Required Workflow

The required Operator v1 workflow is:

```text
User request
      |
      v
Hermes inspects the repository
      |
      v
Hermes writes or modifies IaC
      |
      v
Hermes explains what changed
      |
      v
STOP
      |
      v
Joe reviews Git diff
      |
      v
Joe validates
      |
      v
Joe runs terraform plan
      |
      v
Joe reviews the plan
      |
      v
Joe decides whether to apply
```

The same principle applies to Ansible.

```text
Hermes writes playbook
      |
      v
STOP
      |
      v
Joe reviews
      |
      v
syntax check
      |
      v
Joe decides whether to run it
```

---

# 7. Why terraform plan Is Human-Executed in v1

`terraform plan` is usually read-only with respect to infrastructure.

However, it still requires:

```text
Terraform execution
provider initialization
OpenStack authentication
access to infrastructure state
```

Operator v1 therefore keeps even `terraform plan` outside Hermes.

This produces a simple security boundary:

```text
Hermes
    FILE OPERATIONS

Joe
    EXECUTION
```

There is no ambiguity about who is allowed to contact OpenStack.

---

# 8. Git Is the Review Boundary

Changes created by Hermes should be reviewed through Git.

Useful commands include:

```bash
git status
git diff
git diff --check
```

The intended process is:

```text
Hermes change
      |
      v
Git diff
      |
      v
Human review
      |
      v
validation
      |
      v
execution
```

Git provides a visible record of what the AI changed before infrastructure is affected.

---

# 9. Terraform Safety Boundary

Hermes may create or modify Terraform.

Hermes must not automatically run:

```bash
terraform apply
```

or:

```bash
terraform destroy
```

Joe reviews:

```bash
terraform fmt
terraform validate
terraform plan
```

before deciding whether the proposed change is acceptable.

A plan containing unexpected:

```text
destroy
replace
recreate
```

actions must be investigated before execution.

---

# 10. Ansible Safety Boundary

Hermes may create or modify Ansible playbooks.

Hermes must not automatically execute:

```bash
ansible-playbook
```

Infrastructure-changing playbooks should first be reviewed.

Useful human-operated checks include:

```bash
ansible-playbook \
  -i ansible/inventory.ini \
  <PLAYBOOK> \
  --syntax-check
```

For networking changes, additional caution is required because an incorrect configuration can break SSH connectivity.

---

# 11. Kolla-Ansible Safety Boundary

Kolla-Ansible manages the OpenStack control plane itself.

Commands such as:

```text
deploy
reconfigure
stop
destroy
rabbitmq-reset-state
mariadb-recovery
```

can have much larger consequences than normal workload changes.

Operator v1 does not allow Hermes to execute Kolla-Ansible.

Hermes may:

```text
inspect configuration
write proposed configuration
explain a command
prepare a runbook
review expected effects
```

Joe remains responsible for execution.

---

# 12. Current AI Lab

The repository contains:

```text
terraform/02-ai-lab
```

This workload was created through the controlled Hermes workflow.

Hermes generated Terraform resources including:

```text
private network
private subnet
router
security group
ICMP rule
SSH rule
SSH keypair
CirrOS VM
Floating IP
```

The human operator then performed:

```text
terraform init
terraform validate
terraform plan
terraform apply
```

The resulting workload was successfully validated.

---

# 13. Security Guardrail Test

The repository includes:

```text
docs/14-hermes-security-guardrail-test.md
```

Hermes was deliberately asked to violate the security rules by:

```text
embedding kolla-admin
running Terraform
running OpenStack CLI
bypassing human approval
```

Hermes refused those actions.

This is the expected Operator v1 behavior.

---

# 14. What We Are Avoiding

The goal is not:

```text
AI
 |
 v
unrestricted shell
 |
 v
root
 |
 v
OpenStack administrator
```

That model creates unnecessary risk.

The current model is:

```text
AI
 |
 v
Infrastructure-as-Code changes
 |
 v
Git review
 |
 v
human validation
 |
 v
human approval
 |
 v
infrastructure
```

---

# 15. Future Operator Versions

Operator v1 is intentionally restrictive.

Future experiments may introduce additional controlled capabilities.

For example:

```text
Operator v2
    possibly allow safe validation commands

Operator v3
    possibly allow restricted execution

Operator v4
    possibly orchestrate controlled rebuild workflows
```

Those capabilities must be designed and tested deliberately.

They should not be enabled simply because the AI can technically execute commands.

Each additional permission must have:

```text
clear scope
restricted credentials
logging
validation
approval boundaries
recovery procedures
```

---

# 16. Long-Term Direction

The long-term goal is for the Git repository to become the source of truth for the homelab.

Conceptually:

```text
GitHub repository
       |
       v
desired infrastructure state
       |
       v
Hermes
       |
       | inspect
       | reason
       | prepare changes
       v
execution plan
       |
       v
HUMAN APPROVAL
       |
       v
Ansible / Kolla-Ansible / Terraform
       |
       v
OpenStack
       |
       v
health validation
```

Eventually this could support a controlled request such as:

```text
Rebuild the OpenStack homelab from the Git repository.
```

But that capability belongs to a later operator version.

It is not part of Operator v1.

---

# 17. Core Security Principle

The current rule is simple:

```text
AI WRITES.

HUMAN REVIEWS.

HUMAN EXECUTES.
```

Or, more specifically:

```text
Hermes
    changes files

Git
    shows the changes

Joe
    validates and executes

OpenStack
    receives only approved changes
```

This is the preferred Hermes OpenStack Operator v1 model.
