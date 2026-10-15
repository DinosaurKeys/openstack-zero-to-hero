# Ceph Readiness Assessment

## Cluster Inventory

Three Ubuntu 24.04 OpenStack nodes:
- node1: 192.168.0.200
- node2: 192.168.0.201
- node3: 192.168.0.202

## Memory Profile

Each node has approximately 15 GiB total RAM.

Available RAM at time of assessment:
- node1: 5.6 GiB
- node2: 7.8 GiB
- node3: 6.9 GiB

## Storage Profile

Each node has a 223.6 GB SATA disk at `/dev/sda` containing old Ceph BlueStore/LVM metadata from a previous deployment.

## Network Profile

All management NICs operate at 1 Gbps full duplex.

All nine node-to-node ping tests passed with 0% packet loss.

The `ext0` interface is dedicated to Neutron external networking and must not be repurposed.

## Ceph Status

No Ceph systemd services or Docker containers were found in our checks.

## Open Risks

1. **Ceph and OpenStack memory contention** — Available RAM (5.6–7.8 GiB) may be insufficient for both Ceph OSDs and existing OpenStack workloads.
2. **Existing disk metadata requires controlled cleanup** — `/dev/sda` contains BlueStore/LVM remnants that must be removed safely before Ceph adoption.
3. **Shared 1 Gbps management network may become a performance bottleneck** — Ceph replication and recovery traffic will compete with OpenStack management traffic.
4. **Disk availability and Ceph resource sizing require further validation** — Single 223 GB disk per node limits Ceph layout options (no dedicated WAL/DB devices, limited capacity for PGs).

## Safety Rules

- Do not wipe disks
- Do not install Ceph yet
- Do not modify OpenStack networking
- Do not restart OpenStack services
- Do not run infrastructure commands without human approval

## Proposed Learning Sequence

1. **Independent Ceph cluster using Cephadm** — Deploy Ceph on the same three OpenStack nodes. Ceph remains independently managed but shares host RAM and the management network. Validate cluster health, daemon placement, and resource usage.
2. **Cinder integration** — Configure Cinder to use Ceph RBD, then validate volume creation, attachment, and boot from volume.
3. **Glance/Nova integration** — Store Glance images in Ceph RBD. Separately evaluate using RBD for Nova instance disks.
4. **Infrastructure as Code** — Use Ansible and Cephadm to automate Ceph deployment, Kolla-Ansible to configure OpenStack integration, and Terraform to provision OpenStack VMs and Ceph-backed Cinder volumes.
5. **Grafana** — Deploy Ceph dashboards (Ceph exporter + Grafana) for observability of cluster health, PG states, OSD performance, and capacity.
