# Hermes Test 3 - Modify Existing Infrastructure

## Goal

Test whether Hermes can modify an existing OpenStack resource without recreating or destroying infrastructure.

## Request

Hermes was asked to modify only `ai-cirros-02` and add:

```hcl
metadata = {
  environment = "ai-lab"
  managed_by  = "hermes-iac"
  purpose     = "terraform-learning"
}
```

Hermes modified only:

```text
terraform/02-ai-lab/compute.tf
```

Hermes did not run Terraform or OpenStack commands.

## Terraform Plan

Terraform reported:

```text
Plan: 0 to add, 2 to change, 0 to destroy.
```

The primary change was:

```text
openstack_compute_instance_v2.vm2
```

Terraform planned to update `ai-cirros-02` in place.

Terraform also temporarily showed the floating-IP association as an in-place change because its port ID is obtained through a data source that depends on the VM.

No resource replacement or destruction was proposed.

## Terraform Apply

Actual result:

```text
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

Only the VM required an actual change.

The existing floating IP remained:

```text
192.168.0.157
```

The existing fixed IP remained:

```text
10.20.0.166
```

## OpenStack Verification

The metadata was verified with:

```bash
openstack server show ai-cirros-02 -f yaml -c properties
```

Result:

```yaml
properties:
  environment: ai-lab
  managed_by: hermes-iac
  purpose: terraform-learning
```

## Final Terraform Verification

A final:

```bash
terraform plan
```

returned:

```text
No changes. Your infrastructure matches the configuration.
```

## Result

Test 3: PASS

```text
Hermes writes Terraform change
        |
        v
Hermes stops
        |
        v
Joe reviews the change
        |
        v
terraform validate
        |
        v
terraform plan
        |
        v
Human approval
        |
        v
terraform apply
        |
        v
Existing VM updated in place
```

This test proves that Hermes can modify an existing Terraform-managed OpenStack resource while the human remains responsible for reviewing and executing the change.

## AI Operator Tests So Far

```text
Test 1
Hermes creates infrastructure
PASS

Test 2
Hermes adds infrastructure to an existing deployment
PASS

Test 3
Hermes modifies an existing resource in place
PASS
```

Security model remains:

```text
AI writes IaC.
Human selects credentials.
Human reviews the plan.
Human executes the change.
```
