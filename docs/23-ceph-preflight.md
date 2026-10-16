# Ceph Preflight Diagnostics

## Purpose

Record the completed automated preflight baseline for the three
OpenStack nodes. Manual readiness review is still required before
Ceph deployment.

## Execution Order

Run from the repository root using `ansible/inventory.ini`.

First, install diagnostic tools:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/06-ceph-diagnostic-tools.yml
```

Then run the diagnostics:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/05-ceph-preflight.yml
```

Playbook 06 installs `smartmontools`. Its initial execution succeeded
on all three nodes, with `changed=1` and `failed=0` per node.

Playbook 05 performs read-only diagnostics and asserts selected
conditions. Memory, swap, and firewall results require human review.

## Validated Preflight Results

| Node | ok | changed | unreachable | failed | skipped |
|---|---:|---:|---:|---:|---:|
| node1 | 93 | 0 | 0 | 0 | 4 |
| node2 | 93 | 0 | 0 | 0 | 4 |
| node3 | 93 | 0 | 0 | 0 | 4 |

These results record a completed automated baseline.

## SMART Findings

- **node1 — 192.168.0.200:** SMART passed overall.
  `Runtime_Bad_Block=11` remains a finding for review.
- **node2 — 192.168.0.201:** Automated SMART assertions passed;
  detailed attributes have not been reviewed here.
- **node3 — 192.168.0.202:** Automated SMART assertions passed;
  detailed attributes have not been reviewed here.

## Remaining Review

The [deployment design](22-ceph-deployment-design.md) remains applicable.

- Revalidate device paths, serials, mounts, consumers, and permission
  to discard old data before any disk cleanup.
- Confirm host dependencies, time synchronization, management
  interfaces, firewall reachability, and Ceph port availability.
- Review current RAM headroom and OpenStack health before deployment.
  Monitor both during staged deployment, workloads, and recovery.
- Review exact installation and cleanup commands before approval.
- Resolve Cinder, Glance, Nova, and libvirt Ceph client compatibility
  before their respective OpenStack storage integrations.
- Pause staged deployment on OOM events, sustained swapping,
  or OpenStack health regression.

## Execution Boundaries

These results do not authorize Ceph installation or disk cleanup.
Preserve existing SATA LVM/BlueStore metadata until cleanup is approved.
Exclude the entire OS NVMe device from Ceph provisioning.

Keep `ext0` dedicated to Neutron external networking.
Network changes and OpenStack service restarts require separate approval.
