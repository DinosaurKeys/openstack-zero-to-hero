# Terraform Test 4 - Drift Detection and Reconciliation

## Goal

Test whether Terraform detects infrastructure that was manually changed outside Terraform and restores the declared configuration.

## Test Environment

Workload:

```text
terraform/02-ai-lab
```

VM:

```text
ai-cirros-02
```

OpenStack identity:

```text
hermes-operator
```

## Test 1 - Metadata Drift

The VM metadata was manually changed outside Terraform:

```bash
openstack server set \
  --property environment=manual-drift \
  ai-cirros-02
```

OpenStack confirmed:

```text
environment: manual-drift
managed_by: hermes-iac
purpose: terraform-learning
```

However:

```bash
terraform plan
```

returned:

```text
No changes. Your infrastructure matches the configuration.
```

Result:

```text
Metadata drift was not detected by Terraform in this lab.
```

The metadata was manually restored to:

```text
environment: ai-lab
```

## Test 2 - VM Name Drift

The VM was manually renamed outside Terraform:

```bash
openstack server set \
  --name ai-cirros-02-manual \
  ai-cirros-02
```

Terraform detected the drift:

```text
name = "ai-cirros-02-manual" -> "ai-cirros-02"
```

Terraform plan:

```text
Plan: 0 to add, 2 to change, 0 to destroy.
```

The main change was the VM name.

Terraform also planned an in-place reevaluation of the floating-IP association because its port depends on the VM.

No resource replacement or destruction was proposed.

## Reconciliation

Terraform was applied manually by Joe.

Actual result:

```text
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

OpenStack confirmed the VM name was restored:

```text
ai-cirros-02
```

The VM remained ACTIVE.

Its addresses remained:

```text
Fixed IP:    10.20.0.166
Floating IP: 192.168.0.157
```

## Final Verification

A final:

```bash
terraform plan
```

returned:

```text
No changes. Your infrastructure matches the configuration.
```

## Result

Test 4: PASS

```text
Manual OpenStack change
        |
        v
Terraform detects drift
        |
        v
Human reviews plan
        |
        v
0 add / 0 destroy
        |
        v
Human approves
        |
        v
Terraform restores desired state
        |
        v
Final plan: No changes
```

## Important Lesson

Terraform drift detection depends on what the provider refreshes and compares.

Observed in this lab:

```text
VM name drift      -> detected
VM metadata drift  -> not detected
```

Do not assume every OpenStack property will automatically produce a Terraform drift plan.

The final authority remains:

```text
Terraform configuration = desired state
Terraform plan          = review point
Human                    = approval point
```
