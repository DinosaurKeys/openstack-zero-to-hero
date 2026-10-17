# Ceph OSD Preparation

Status: Memory policy applied 2026-10-16. Disk cleanup and OSD provisioning remain unapproved.

## Observed Results (2026-10-16)

- Ceph version: 20.2.4 (tentacle)
- Cluster FSID: c692f389-c98e-11f1-97b4-002324ebf501
- Playbook executed: ansible/playbooks/10-ceph-osd-memory-policy.yml
- Administered from: node2 (central policy for future OSDs)
- Configuration changes:
  - osd_memory_target_autotune: true → false
  - osd_memory_target: 4294967296 → 2147483648 bytes (2 GiB)
- Initial run results: ok=19, changed=1, unreachable=0, failed=0, skipped=0
- Repeat run results: ok=18, changed=0, unreachable=0, failed=0, skipped=1
- OpenStack health: HEALTHY, 14 checks passed before and after application
- OSD status: Zero OSDs; no disks cleaned or provisioned

## Key Explanations

- The 2 GiB value for `osd_memory_target` is a **soft target**, not a reservation or hard limit.
- Budget at least **2.4 GiB per OSD** plus additional headroom for MON/MGR, host OS, OpenStack services, workload growth, and recovery scenarios.
- After OSD creation, verify actual runtime settings and memory consumption using the ceph_lab function (defined in chapter 24) on node2:
  ```
  ceph_lab config show osd.<actual-id> osd_memory_target
  ceph_lab config show osd.<actual-id> osd_memory_target_autotune
  ceph_lab orch ps --refresh
  ```
  Replace `<actual-id>` with the actual OSD ID after creation.
- The execution command used:
  ```bash
  ansible-playbook -i ansible/inventory.ini ansible/playbooks/10-ceph-osd-memory-policy.yml --extra-vars '{"ceph_osd_memory_policy_approved": true, "ceph_expected_fsid": "c692f389-c98e-11f1-97b4-002324ebf501"}'
  ```

- A future rebuild must use the FSID generated during that rebuild.
  The FSID recorded above identifies only the current cluster.

## Preserved SMART Findings

- All three disks reported overall PASSED in SMART evaluations.
- Node1's `Runtime_Bad_Block=11` remains unresolved and requires review.
- Node2's extended self-test log is readable but empty (no completed self-tests logged).
- Node2 lacks the extended comprehensive error log; its unusual vendor counters remain unverified.
- No completed self-tests are logged on any disk.
- Disk cleanup and OSD provisioning remain unapproved and require separate explicit approval.

## Next Steps

This stage prepares the memory policy for OSDs but does not authorize disk cleanup, OSD creation, or any storage integration. Subsequent stages require:
1. Explicit approval for disk cleanup procedures per host.
2. Explicit approval for OSD creation (one at a time, with validation).
3. Verify runtime settings and monitor actual OSD memory usage and host RAM headroom.
4. Review of OpenStack integration prerequisites (Cinder, Glance, Nova, and libvirt Ceph client compatibility and authentication advisory).

---
2026-10-17 update: SMART long self-test completed; see [chapter 28](28-ceph-disk-validation.md). The memory-policy results, observed FSID, and preserved SMART findings above remain historical records.
