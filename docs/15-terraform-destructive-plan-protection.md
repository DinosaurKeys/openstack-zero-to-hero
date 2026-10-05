# Terraform Test 6 - Destructive Plan Protection

## Goal

Verify that Terraform can show a destructive operation without changing OpenStack until a human explicitly approves execution.

## Test

The following command was used:

```bash
terraform plan -destroy
```

Terraform reported:

```text
Plan: 0 to add, 0 to change, 14 to destroy.
```

The plan included both AI lab VMs and the Terraform-managed network resources.

No terraform apply or terraform destroy command was executed.

## Verification

After reviewing the destructive plan:

```bash
openstack server list
```

confirmed:

```text
ai-cirros-01  ACTIVE
ai-cirros-02  ACTIVE
```

## Result

Test 6: PASS

```text
Destructive plan generated
        |
        v
Human reviews destruction
        |
        v
Human does not approve
        |
        v
No infrastructure is destroyed
```

This proves the human approval boundary protects the OpenStack environment from destructive Terraform execution.
