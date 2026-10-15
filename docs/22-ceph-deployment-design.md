# Ceph Deployment Design

Assessment date: 2026-10-15.
Status: Proposed lab design; deployment is not yet approved.

## Scope

Deploy an independently managed Ceph cluster using cephadm on the
three existing OpenStack nodes. Both platforms share host resources.

Start with RBD block storage. Add OpenStack integration and Grafana later.

## Versions

- Kolla-Ansible tooling: 22.2.1.dev10.
- Observed Glance image: quay.io/openstack.kolla/glance-api:2026.1-ubuntu-noble.
- Observed Glance librados2/librbd1: 20.2.0-0ubuntu2~cloud0.
- Proposed Ceph server release: Tentacle 20.2.4.

Client compatibility remains unresolved. Upstream 20.2.4 introduced
aes256k authentication support requiring updated clients.
Verify Ubuntu backports or plan updated Kolla images before integration.
Check Cinder, Nova, and libvirt clients as well as Glance.

## Proposed Daemon Placement

| Node | Management IP | Ceph daemons |
|---|---|---|
| node1 | 192.168.0.200 | MON + OSD |
| node2 | 192.168.0.201 | MON + OSD + MGR |
| node3 | 192.168.0.202 | MON + OSD + MGR |

- Three MONs maintain quorum with one MON unavailable.
- Two MGRs provide one active manager and one standby.
- MGRs do not require quorum.
- Node1 has the least available RAM, so MGRs are placed elsewhere.
- Proposed bootstrap host: node2, which had the most available RAM.
- Use explicit daemon placement.
- Defer CephFS, RGW, and the Grafana/Prometheus monitoring stack.

## Provisional Memory Budget

Each host has approximately 15.5 GiB total RAM.

| Node | Observed available MiB | Available GiB | After 2.4 GiB OSD allowance |
|---|---:|---:|---:|
| node1 | 5645 | 5.51 | 3.11 GiB |
| node2 | 7881 | 7.70 | 5.30 GiB |
| node3 | 6721 | 6.56 | 4.16 GiB |

- Proposed initial osd_memory_target: 2 GiB per OSD.
- Proposed osd_memory_target_autotune: false, set before adding OSDs.
- Allow at least 20% extra for OSD memory: 2.4 GiB per host.
- These are planning allowances, not hard memory limits.
- Remaining RAM must cover MON/MGR daemons and OpenStack growth.
- Recovery may need additional headroom.
- No swap I/O occurred during the short sample.
- Node1 had 256 KiB allocated in swap.

This is a constrained lab proposal. Validate actual memory use during
normal workload and recovery before approving OpenStack integration.

## Proposed OSD Devices

One SATA device per host, approximately 223.6 GiB each.
The lsblk display of 223.6G represents binary units, approximately 240 GB.

| Node | Observed serial | Persistent device path |
|---|---|---|
| node1 | 50026B7766070422 | /dev/disk/by-id/ata-KINGSTON_SUV400S37240G_50026B7766070422 |
| node2 | 4P3521354988 | /dev/disk/by-id/ata-ADATA_SU630_4P3521354988 |
| node3 | 50026B768317883A | /dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B768317883A |

Each listed path resolved to /dev/sda during inspection.

All three disks contain old Ceph LVM/BlueStore metadata.
Their contents have not been approved for deletion.
Node2 reports an all-zero WWN; use its serial-based ATA path.

Ubuntu uses /dev/nvme0n1, including the ubuntu-vg volume group.
Exclude the entire NVMe device from Ceph provisioning.
Unused space in ubuntu-vg is outside this design.

Revalidate device paths, serials, mounts, and consumers before cleanup.
Use explicit device selection rather than automatic disk discovery.

## Networking

Use the existing 1 Gbps management network for Ceph client,
replication, and recovery traffic.

Confirm the current subnet, interfaces, firewall rules, and port
availability before bootstrap.

Keep ext0 dedicated to Neutron external networking.
Do not change OpenStack networking.

Shared bandwidth is a lab limitation, especially during recovery.

## Proposed RBD Pool Policy

- Replicated pools with size 3 and min_size 2.
- Place replicas on separate hosts.
- Nominal replicated capacity: approximately 223.6 GiB before overhead.
- Operating capacity will be lower after metadata and free-space reserves.
- With one host unavailable, full three-copy redundancy cannot be
  restored until that host returns or replacement capacity is added.

Choose pool and placement-group settings before creating pools.
Create only the pools required for each learning stage.

## Remaining Checks and Execution Boundaries

1. Validate disk health, mounts, consumers, and old-data disposal.
2. Check host dependencies, time synchronization, and network ports.
3. Review exact installation and cleanup commands before approval.
4. Obtain approval before installing Ceph or removing disk metadata.
5. During deployment, validate memory and OpenStack health after each stage.
6. Pause on OOM events, sustained swapping, or OpenStack health regression.
7. Resolve client compatibility before Cinder/Glance/Nova integration.

This branch changes documentation only.
Do not wipe disks, install Ceph, or restart OpenStack services.

## Learning Sequence

1. Review and commit this design.
2. Prepare and review deployment automation.
3. Deploy Ceph after approval and validate its health and resource use.
4. Integrate Cinder and test volume attachment and boot from volume.
5. Integrate Glance; evaluate Nova instance disks on RBD separately.
6. Provision Ceph-backed workloads with Terraform.
7. Add Grafana and study performance and recovery.

Return later to the web-01/db-01 application deployment lessons.

## References

- [Ceph releases](https://docs.ceph.com/en/latest/releases/)
- [Ceph memory guidance](https://docs.ceph.com/en/tentacle/start/hardware-recommendations/)
- [cephadm deployment](https://docs.ceph.com/en/tentacle/cephadm/install/)
- [MON quorum](https://docs.ceph.com/en/tentacle/rados/operations/add-or-rm-mons/)
- [MGR availability](https://docs.ceph.com/en/tentacle/mgr/administrator/)
- [Ceph networking](https://docs.ceph.com/en/tentacle/rados/configuration/network-config-ref/)
- [Ceph pools](https://docs.ceph.com/en/tentacle/rados/operations/pools/)
- [Kolla external Ceph](https://docs.openstack.org/kolla-ansible/2026.1/reference/storage/external-ceph-guide.html)
- [OpenStack Ceph authentication advisory](https://docs.openstack.org/security-notes/OSSN-0108.html)
