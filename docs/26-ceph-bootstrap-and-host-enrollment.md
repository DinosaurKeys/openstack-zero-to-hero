# Ceph Bootstrap and Host Enrollment

Status: Bootstrap (08) and enrollment (09) completed 2026-10-16. See [Chapter 27](27-ceph-osd-preparation.md) for OSD preparation.
The OSD memory policy was subsequently applied; see [chapter 27](27-ceph-osd-preparation.md).
Disk cleanup, OSD creation, and OpenStack integration review remain unapproved.

## Version and Identity

- Release: 20.2.4 (tentacle)
- FSID: c692f389-c98e-11f1-97b4-002324ebf501
- Executable: /usr/local/sbin/cephadm-20.2.4 (node2)

## Execution Commands and Variables

Bootstrap (08):

```bash
ansible-playbook -i ansible/inventory.ini \
  ansible/playbooks/08-ceph-bootstrap.yml \
  -e ceph_bootstrap_approved=true
```

Enrollment (09):

```bash
ansible-playbook -i ansible/inventory.ini \
  ansible/playbooks/09-ceph-host-enrollment.yml \
  --extra-vars '{"ceph_host_enrollment_approved": true, "ceph_expected_fsid": "c692f389-c98e-11f1-97b4-002324ebf501"}'
```

Both playbooks target node2 for administration; 09 acts on node1/node3
through delegation and builtin modules.

## Observed Results

| Playbook | ok | changed | unreachable | failed | skipped |
|---|---:|---:|---:|---:|---:|
| 08 bootstrap | 43 | 3 | 0 | 0 | 1 |
| 09 enrollment | 35 | 4 | 0 | 0 | 0 |

- MON placement: 3 hosts (node1, node2, node3) — all in quorum.
- MGR placement: 2 hosts — node2 active, node3 standby; none on node1.
- Hosts enrolled: 3. `_admin` label only on node2.
- Zero OSDs, zero pools.
- Health: HEALTH_WARN with the expected TOO_FEW_OSDS warning before any OSD creation.
- OpenStack (`scripts/lab-status.sh`): HEALTHY, 14 checks passed before and
  after enrollment.
- Post-enrollment available RAM (MiB): node1=6275, node2=7190, node3=6573.
- Swap usage and sampled swap I/O: zero on all nodes.

## Fresh-Deployment Note

These are fresh-deployment stages. Before any rerun, inspect actual Ceph
state (directories, containers, systemd units, ports, FSID, keys). A future
rebuild will generate a different FSID and must be treated as a new cluster,
not an in-place restart of this one.

## Unapproved Gates Preserved

- Disk cleanup (Stage 6) and per-host SATA identity verification.
- Verify the applied memory policy and actual resource use in running OSDs after OSD creation.
- Actual OSD creation, replication validation, and recovery headroom review.
- Cinder/Glance/Nova RBD integration and the Ceph authentication advisory.
- Defer dashboard, Prometheus/Grafana, CephFS, RGW.
- Node1 `Runtime_Bad_Block=11` remains open; an overall SMART pass does not resolve it.
- Glance client version `20.2.0-0ubuntu2~cloud0` requires compatibility review before integration.
