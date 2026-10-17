# Ceph Deployment Plan

Status: DRAFT — bootstrap (08), host enrollment (09), and memory-policy (10) complete.
Cluster disk cleanup, OSD creation, and OpenStack storage integration
remain unapproved.

## Purpose and Scope

Plan an independently managed Ceph cluster on the three existing OpenStack
nodes, following the [deployment design](22-ceph-deployment-design.md) and
[preflight report](23-ceph-preflight.md).

This chapter defines the proposed stages and checks. Prepare and review the
Ansible automation before requesting execution approval. Hermes AI prepares
files; the human operator reviews and runs approved infrastructure commands.

Do not change the existing inventory, preflight playbook, or diagnostic-tools
playbook while preparing this plan. Use a dedicated feature branch for subsequent changes.

## Recorded Baseline

These are observations from 2026-10-16, not permanent readiness guarantees.

- `./scripts/lab-status.sh` reported HEALTHY with 14 passed checks.
- The subsequent RAM sample reported the following values.

| Node | Management IP | Available RAM (MiB) | Swap used (MiB) |
|---|---|---:|---:|
| node1 | 192.168.0.200 | 6785 | 0 |
| node2 | 192.168.0.201 | 7775 | 0 |
| node3 | 192.168.0.202 | 7540 | 0 |

The automated preflight passed on all three nodes. Manual readiness review
remains open. Node1's `Runtime_Bad_Block=11` requires review; an overall SMART
pass does not resolve that finding. Review the detailed SMART attributes on
node2 and node3 as well, including vendor-specific counters.

## Inventory and Version Selection

Use the existing `ansible/inventory.ini`, group `openstack`, and SSH account
`openstack` with passwordless sudo. Do not create a second inventory.

| Component | Proposed value |
|---|---|
| Ceph release | Tentacle 20.2.4 |
| Bootstrap and administrative host | node2 |
| Standalone executable | `/usr/local/sbin/cephadm-20.2.4` on node2 |
| Executable source | `https://download.ceph.com/rpm-20.2.4/el9/noarch/cephadm` |
| Ceph container image | `quay.io/ceph/ceph:v20.2.4` |
| Container engine | Existing Docker installation |

The download is the standalone executable, despite the `rpm-20.2.4` directory
name. Do not extract it with RPM tools. No Ceph APT repository or host-installed
`ceph-common` is needed for this approach.

No verified executable checksum or image digest is recorded here. Do not invent
one. Record the actual artifact hash and resolved image digest during approved
installation; a locally calculated hash is an inventory record, not independent
proof of authenticity. Any version change requires review.

## cephadm vs MGR

The standalone cephadm executable is our deployment and administration tool,
initially installed on node2. MGR is a continuously running Ceph management
service; our design places MGR containers on node2 and node3: one active, one
standby. The active MGR runs the cephadm orchestration module, coordinating
daemon deployment across hosts through SSH. Node3 can run MGR without a
separately installed host cephadm executable. Playbook 07 installs the
executable only; bootstrap later creates the first MON and MGR.

## Stage 0 — Readiness and Approval Before Installation

Before requesting approval to run the installation/bootstrap automation:

- Confirm Python 3, systemd, existing Docker, LVM2, time synchronization, SSH,
  and passwordless sudo on the hosts. Review any missing dependency separately;
  do not silently install packages or restart Docker/OpenStack services.
- Check for host-installed Ceph packages, existing Ceph configuration, keys,
  daemon state, or services. Review remnants before proceeding. Do not overwrite
  `/etc/ceph` or adopt/remove old cluster state automatically.
- Review current OpenStack health, RAM headroom, swap activity, and disk health.
- Confirm management addresses and the `192.168.0.0/24` subnet. Review firewall
  reachability and required Ceph ports between the hosts and intended clients.
  MONs use TCP 3300/6789; daemon traffic can use TCP 6800–7568.
- Keep Ceph client, replication, and recovery traffic on the shared 1 Gbps
  management network. Preserve `ext0` for Neutron external networking.
- Revalidate the SATA device identities, mounts, descendants, and consumers.
  Existing LVM/BlueStore metadata remains untouched at this stage.
- Review the exact proposed automation, its host scope, and its package,
  firewall, filesystem, SSH, and service effects before execution approval.

Playbook 05 is a pre-bootstrap check: its assertions deliberately reject an
existing Ceph deployment or occupied Ceph ports. Do not use it unchanged as a
post-deployment health check.

## Stage 1 — Install Only the Standalone Executable on node2

Proposed implementation: an Ansible task targeting node2 downloads the exact
URL above over HTTPS with certificate validation, using `ansible.builtin.get_url`.
Set the destination to `/usr/local/sbin/cephadm-20.2.4`, owner/group `root:root`,
and mode `0755`. Review an unexpected pre-existing destination before replacing
it. Do not install RPM extraction tools or change APT repositories.

After approved installation, verify on node2:

```bash
/usr/local/sbin/cephadm-20.2.4 version
```

Status: node2 executable installed; bootstrap and host enrollment are complete (see [chapter 26](26-ceph-bootstrap-and-host-enrollment.md) and [chapter 27](27-ceph-osd-preparation.md)). Disk cleanup and OSD creation remain unapproved.
Require release **20.2.4**, not “20.2.4 or later”. Stop on a download error,
unexpected existing file, execution error, or version mismatch.

## Command Convention for Stages 2–8

All Ceph administrative commands below run on **node2** through the pinned
container image. The following temporary Bash function is shorthand for that
complete command; defining it does not install a wrapper script:

```bash
ceph_lab() {
  sudo /usr/local/sbin/cephadm-20.2.4 \
    --docker --image quay.io/ceph/ceph:v20.2.4 \
    shell -- ceph "$@"
}
```

Define it in each new node2 shell before using the examples. Future Ansible
tasks must use the full executable/argument list and must not depend on an
interactive shell function. Ceph commands are not available as direct
`cephadm ceph ...` or `cephadm orch ...` subcommands.

Run proposed commands individually after approval; inspect their results
before continuing. Commands that change configuration or placement are changes
to the infrastructure, even when the surrounding stage also includes checks.

## Stage 2 — Bootstrap on node2 and Constrain Initial Placement

Proposed bootstrap command, run on node2 only after approval:

```bash
sudo /usr/local/sbin/cephadm-20.2.4 \
  --docker --image quay.io/ceph/ceph:v20.2.4 \
  bootstrap \
  --mon-ip 192.168.0.201 \
  --ssh-user openstack \
  --skip-dashboard \
  --skip-monitoring-stack \
  --skip-prepare-host \
  --skip-firewalld
```

The skip flags do not replace dependency or network validation. Bootstrap
creates Ceph state, containers, systemd units, administrative credentials,
and a Ceph SSH key. Do not blindly rerun it after a partial failure or add
`--allow-overwrite` to bypass existing files.

Before enrolling another host, constrain the initial services to node2:

```bash
ceph_lab orch apply mon --placement="1 node2"
ceph_lab orch apply mgr --placement="1 node2"
```

Verify the resulting specifications and running daemons before proceeding:

```bash
ceph_lab orch ls --export
ceph_lab orch ps --refresh
ceph_lab -s
ceph_lab health detail
ceph_lab versions
```

Expected: one MON and one active MGR on node2, release 20.2.4, no OSDs, and no
dashboard or monitoring stack. Ceph may also deploy its normal crash-reporting
daemon. Keep the `_admin` label on node2 initially.

`TOO_FEW_OSDS` is expected while fewer than three OSDs exist. Other warnings
must be explained against the actual deployment stage; do not treat every
HEALTH_WARN as acceptable or suppress warnings to obtain HEALTH_OK.

## Stage 3 — Authorize Ceph's Public SSH Key and Enroll Hosts

The Ceph cluster's SSH key differs from the key Hermes already uses.

Using Hermes's existing access, the proposed Ansible automation reads only
node2's `/etc/ceph/ceph.pub` and adds that public key idempotently to the
`openstack` account's `authorized_keys` on node1 and node3. Preserve existing
keys, ownership, and appropriate SSH file permissions. Review these account
authorization changes before execution. Never export Ceph's private SSH key
or commit private keys/admin keyrings to Git.

After public-key authorization, enroll the hosts from node2:

```bash
ceph_lab orch host add node1 192.168.0.200
ceph_lab orch host add node3 192.168.0.202
ceph_lab orch host ls
```

Expected: all three correctly named hosts are online and Ceph can connect as
`openstack` with passwordless sudo. Initial MON/MGR placement remains restricted
to node2 until Stage 4. No `mon` or `mgr` labels are required because placement
uses explicit host lists.

## Stage 4 — Apply the Final MON and MGR Placement

Proposed commands on node2:

```bash
ceph_lab orch apply mon --placement="3 node1 node2 node3"
ceph_lab orch apply mgr --placement="2 node2 node3"
```

Check convergence before continuing:

```bash
ceph_lab quorum_status --format json-pretty
ceph_lab mgr dump --format json-pretty
ceph_lab orch ls --export
ceph_lab orch ps --refresh
ceph_lab config get mon public_network
```

Expected: all three MONs in quorum, one active MGR and one standby across
node2/node3, and no MGR on node1. Two MONs are enough to retain quorum during
a single failure; the healthy baseline is all three, not two.

Verify the MON public network is the confirmed management subnet
`192.168.0.0/24`. Resolve any mismatch before proceeding. Do not add a separate
Ceph network or repurpose `ext0` in this deployment.

## Stage 5 — Set OSD Memory Policy Before Creating Any OSD

Proposed configuration changes on node2:

```bash
ceph_lab config set osd osd_memory_target_autotune false
ceph_lab config set osd osd_memory_target 2147483648
```

Verify the stored configuration before OSDs exist:

```bash
ceph_lab config get osd osd_memory_target_autotune
ceph_lab config get osd osd_memory_target
ceph_lab config dump
```

Require `false` and `2147483648`, respectively, with no conflicting overrides.
After OSD creation, verify the running daemons as described in Stage 7.

The 2 GiB value is a soft target. Budget at least 2.4 GiB per OSD as the
provisional allowance, plus separate headroom for MON/MGR, the OS, OpenStack,
workload growth, and recovery. This does not enforce a 2 GiB or 2.4 GiB ceiling.
Status: Applied and repeat-run validated; see [chapter 27](27-ceph-osd-preparation.md).

---
2026-10-17 update (disk validation stage): SMART long self-test completed on all three SATA devices; see [chapter 28](28-ceph-disk-validation.md). The memory-policy stage and bootstrap/enrollment results above are preserved as historical records.

## Stage 6 — Separate Cleanup Approval, Then One OSD at a Time

**Stop before this stage until the exact cleanup procedure has been written,
reviewed, and explicitly approved for each identified disk.** This chapter
contains no approved disk-erasure procedure. Approval for installation or
bootstrap does not authorize cleanup or OSD creation.

Before cleanup, reconfirm identity, serial, mounts, descendants, holders,
consumers, SMART findings, and permission to discard all old data. Preserve
existing metadata until approval. After approved cleanup, verify device
availability and absence of the old signatures before authorizing provisioning.

| Node | Required serial | Proposed OSD device |
|---|---|---|
| node1 | 50026B7766070422 | `/dev/disk/by-id/ata-KINGSTON_SUV400S37240G_50026B7766070422` |
| node2 | 4P3521354988 | `/dev/disk/by-id/ata-ADATA_SU630_4P3521354988` |
| node3 | 50026B768317883A | `/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B768317883A` |

Never select all available disks. Exclude `/dev/nvme0n1`, all its partitions,
and `ubuntu-vg` from OSD/WAL/DB provisioning. Ceph's normal software and MON/MGR
state will occupy space in the existing OS filesystem; this does not authorize
repartitioning or allocating the OS device to an OSD.

Proposed OSD creation commands on node2, each requiring the preceding cleanup
and provisioning approvals:

```bash
ceph_lab orch daemon add osd node1:/dev/disk/by-id/ata-KINGSTON_SUV400S37240G_50026B7766070422
```

Run the Stage 7 checks and the Stage 8 health/resource checks before proceeding
to the next host.

```bash
ceph_lab orch daemon add osd node2:/dev/disk/by-id/ata-ADATA_SU630_4P3521354988
```

Repeat the checks before the final host:

```bash
ceph_lab orch daemon add osd node3:/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B768317883A
```

Expected final state: one OSD per host, all three up and in, using only the
approved SATA devices. Do not assume the assigned OSD IDs.

## Stage 7 — Verify OSD Placement, Runtime Configuration, and Memory

Checks on node2 after each OSD is added:

```bash
ceph_lab osd ls
ceph_lab osd tree
ceph_lab osd stat
ceph_lab orch ps --refresh
```

For each actual running OSD ID reported above, inspect both options with
`ceph config show osd.<actual-id> <option>` through `ceph_lab`. The options are
`osd_memory_target` and `osd_memory_target_autotune`; require `2147483648` and
`false`. Here `<actual-id>` is a template to replace, not literal command text.

Use `config show` for running settings; `config get` alone does not establish
what a running daemon is using. Review unexpected configuration sources or
overrides. Record actual daemon memory from `orch ps` and host memory samples;
do not infer consumption from the configured target or require usage below it.

## Stage 8 — Health and Resource Checks After Every Stage

On node2, after bootstrap:

```bash
ceph_lab -s
ceph_lab health detail
ceph_lab orch ps --refresh
ceph_lab versions
```

On **Hermes**, from the repository root:

```bash
./scripts/lab-status.sh
```

Collect host memory and swap activity from Hermes:

```bash
ansible -i ansible/inventory.ini openstack -m ansible.builtin.command -a 'free -m'
ansible -i ansible/inventory.ini openstack -m ansible.builtin.command -a 'vmstat 1 5'
```

These two ad-hoc commands inspect host state. Ansible's command module can
display CHANGED by default even for such diagnostic commands. Inspect the
interval samples in `vmstat`, rather than relying on its first summary row.
A short sample is a baseline, not proof of sufficient headroom under recovery.

- Require the existing OpenStack status script to pass all 14 checks.
- Before three OSDs exist, review stage-related warnings including
  `TOO_FEW_OSDS`. Investigate every unexpected warning before continuing.
- After all three OSDs are up/in and deployment has settled, require HEALTH_OK
  before calling the core deployment complete. Investigate lingering warnings;
  do not assume low PG counts automatically justify HEALTH_WARN.
- Pause on a failed command, unexpected daemon placement/version, loss of MON
  quorum, daemon crashes/flapping, unresolved health warnings, OOM events,
  sustained swap I/O, inadequate RAM headroom, or OpenStack health regression.
- Static nonzero swap allocation alone is not a stop condition. Review active
  swap I/O and memory pressure. The recorded baseline had zero swap used.
- If a stage fails, stop before the next stage. Review logs and the actual
  partial state; do not run automatic cleanup or bootstrap again blindly.

## Completion and Later Learning Stages

Record actual versions, resolved image identity, daemon placement, OSD IDs and
device serials, memory observations, health output, and approved changes in the
deployment record. Keep credentials and private key material out of Git.

A healthy core cluster does not demonstrate RBD read/write behavior or
OpenStack integration. Separately plan an RBD smoke test and subsequent pool
creation. Preserve the chapter 22 policy: replication size 3, min_size 2, with
replicas on separate hosts. Review pool/PG choices before creating pools.

Before Cinder, Glance, Nova RBD, or libvirt integration, resolve client/server
compatibility and the Ceph authentication advisory. Check actual Ubuntu
security backports; the observed Glance client version
`20.2.0-0ubuntu2~cloud0` alone does not settle compatibility. Do not weaken Ceph
authentication to bypass this review.

Defer dashboard, Prometheus/Grafana, CephFS, RGW, and OpenStack storage
integration. Workload and recovery validation require their own reviewed
steps. Return later to the web-01/db-01 lessons in chapter 20.

## References

- [Ceph releases](https://docs.ceph.com/en/latest/releases/)
- [cephadm installation](https://docs.ceph.com/en/tentacle/cephadm/install/)
- [cephadm command reference](https://docs.ceph.com/en/tentacle/man/8/cephadm/)
- [Host enrollment and SSH](https://docs.ceph.com/en/tentacle/cephadm/host-management/)
- [Service placement](https://docs.ceph.com/en/tentacle/cephadm/services/)
- [MON service](https://docs.ceph.com/en/tentacle/cephadm/services/mon/)
- [MGR service](https://docs.ceph.com/en/tentacle/cephadm/services/mgr/)
- [OSD service and memory tuning](https://docs.ceph.com/en/tentacle/cephadm/services/osd/)
- [Configuration and runtime settings](https://docs.ceph.com/en/tentacle/rados/configuration/ceph-conf/)
- [Memory guidance](https://docs.ceph.com/en/tentacle/start/hardware-recommendations/)
- [Health checks](https://docs.ceph.com/en/tentacle/rados/operations/health-checks/)
- [Ceph networking](https://docs.ceph.com/en/tentacle/rados/configuration/network-config-ref/)
- [Ceph pools](https://docs.ceph.com/en/tentacle/rados/operations/pools/)
- [Kolla external Ceph](https://docs.openstack.org/kolla-ansible/2026.1/reference/storage/external-ceph-guide.html)
- [OpenStack Ceph authentication advisory](https://docs.openstack.org/security-notes/OSSN-0108.html)
