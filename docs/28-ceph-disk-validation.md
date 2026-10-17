# Ceph Disk Validation

Assessment date: 2026-10-17.
Status: SMART long self-test completed on all three disks; disk cleanup
and OSD creation remain unapproved.

## Cluster Context

- Cluster FSID: c692f389-c98e-11f1-97b4-002324ebf501
- Playbook for start: `ansible/playbooks/11-ceph-smart-selftest-start.yml`
- Playbook for report: `ansible/playbooks/12-ceph-smart-selftest-report.yml`
- Playbook 11 starts approved background SSD long tests.
- Playbook 12 reads results; it does not start tests.

These are SSD (SATA) disk tests, not Ceph daemon health checks or OpenStack
service checks. A passing SMART result is separate from `HEALTH_OK` in Ceph
and from the 14-check OpenStack `lab-status.sh` result.

## Confirmed Results

All three disks reported their long self-test completed without error.

## Node1 Report Exception (2026-10-17)

Node1 initially failed report validation because its extended self-test log
revision was 0. Both the standard and extended log formats for that exact
disk were manually compared and agreed: the same completed long test entry
was present in both formats.

The corrected report in playbook 12 accepts only the exact node1 combination:

- Model: `KINGSTON SUV400S37240G`
- Serial: `50026B7766070422`
- Firmware: `0C3FD6SD`
- Extended log format (`smart_log_format == 'extended'`)
- Log revision: `0`
- A completed long-test entry (`smart_latest.type.value == 2`); the value 2 identifies a long self-test, while the execution/log status and exit flags determine whether that test completed without error.

The revision-0 header warning remains visible in the output. It is preserved
as a documented exception, not hidden, and does not change any disk-use
approval. Other disks must still meet the normal expected log format and
revision rules.

## Observed Playbook Execution Results

Playbook 11 (start — approved background long test):

| Node | ok | changed | unreachable | failed | skipped |
|---|---:|---:|---:|---:|---:|
| node1 | 22 | 1 | 0 | 0 | 0 |
| node2 | 18 | 1 | 0 | 0 | 0 |
| node3 | 18 | 1 | 0 | 0 | 0 |

Playbook 12 (report before correction):

| Node | ok | changed | unreachable | failed | skipped |
|---|---:|---:|---:|---:|---:|
| node1 | 14 | 0 | 0 | 1 | 0 |
| node2 | 15 | 0 | 0 | 0 | 0 |
| node3 | 15 | 0 | 0 | 0 | 0 |

Playbook 12 (after correction, run with `--limit node1`):

| Node | ok | changed | unreachable | failed | skipped |
|---|---:|---:|---:|---:|---:|
| node1 | 16 | 0 | 0 | 0 | 0 |

No corrected three-node run was performed; only the single-host
`--limit node1` verification is recorded above.

## Copyable Commands

Start the approved background SMART long self-test:

```bash
ansible-playbook -i ansible/inventory.ini \
  ansible/playbooks/11-ceph-smart-selftest-start.yml \
  -e ceph_smart_selftest_approved=true \
  -e ceph_expected_fsid="c692f389-c98e-11f1-97b4-002324ebf501"
```

Read the read-only SMART report:

```bash
ansible-playbook -i ansible/inventory.ini \
  ansible/playbooks/12-ceph-smart-selftest-report.yml
```

Review only node1 after the correction:

```bash
ansible-playbook -i ansible/inventory.ini \
  ansible/playbooks/12-ceph-smart-selftest-report.yml \
  --limit node1
```

These commands inspect the SATA devices (`/dev/disk/by-id/ata-...`) mapped
in playbooks 11 and 12 and exclude `/dev/nvme0n1` and any other NVMe
reference. They do not clean disks, start services, or modify OpenStack.

Playbook 11 starts approved background SMART long self-tests and preserves any test already running; after a completed test, another approved run can start a new test. Playbook 12 performs only read-only SMART reporting and does not start tests.

## SSD Tests vs Cluster and OpenStack Health

- SMART self-test results describe the physical disk. A completed long
  self-test does not mean the disk is approved for cleanup or provisioning.
- The Ceph `HEALTH_OK` / `HEALTH_WARN` status and the 14-check OpenStack
  `HEALTHY` result describe cluster services and host connectivity, not
  disk-level readiness.
- Disk cleanup and OSD creation remain separate approval stages.

## Unresolved Findings

- Node1 `Runtime_Bad_Block=11` remains unresolved.
- Node2's comprehensive error log is reported as unsupported by the device; that feature limitation is confirmed. Its unusual vendor-counter values remain unverified, and their interpretation remains open.
- No completed self-tests were previously logged on any disk before this
  stage; the long-test results in this chapter are the first completed
  records.

## Rebuild Note

A future rebuild must use the FSID generated during that rebuild. The FSID
recorded above (`c692f389-c98e-11f1-97b4-002324ebf501`) identifies only the
current cluster. Only playbook 11 requires `ceph_expected_fsid`; it verifies the intended cluster through node2 before starting tests. Playbook 12 reads SMART data and does not contact Ceph or require an FSID. The SATA device mappings must be revalidated after a rebuild.

## Preserved Boundaries

- This documentation update changed README.md and chapters 24, 27 and 28. It did not modify playbooks or inventory.
- Earlier in this stage, playbook 11 started the approved background SMART long self-tests, and playbook 12 received the reviewed reporting correction (node1 revision-zero exception). Existing SATA LVM/BlueStore data was preserved.
- Disk contents, LVM metadata, Ceph container state, OpenStack services,
  networking, and host configurations were preserved.
- No commands were executed, committed, or pushed as part of this
  documentation update.
