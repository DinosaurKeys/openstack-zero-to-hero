# 19 — OpenStack Live Migration vs VMware vMotion

## Objective

Demonstrate planned VM migration between OpenStack compute
nodes without shutting down the guest.

## Environment

- Three-node Kolla-Ansible OpenStack homelab
- Ubuntu 24.04
- KVM / libvirt
- Local Nova instance storage
- No shared Ceph storage
- Management networking over br-mgmt

## Storage architecture

Each node stores Nova instance disks under:

/var/lib/docker/volumes/nova_compute/_data

The directory is mounted inside nova_compute at /var/lib/nova.

Backing filesystem:

/dev/mapper/ubuntu--vg-ubuntu--lv

Filesystem: ext4
Capacity: approximately 98 GiB per node

This is local storage, not shared storage.

## Live migration test

VM: ai-cirros-01
Instance UUID: d0ba0068-b502-42e2-b9eb-40ef4f08458d

Source: node2
Destination: node1
Method: Block live migration
Floating IP: 192.168.0.153

The VM was started and its floating IP was reachable
before the test.

Migration command:

```bash
OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml \
OS_CLOUD=kolla-admin \
openstack --os-compute-api-version 2.87 \
  server migrate \
  --live-migration \
  --block-migration \
  --host node1 \
  --wait \
  d0ba0068-b502-42e2-b9eb-40ef4f08458d
```

## Verification

Check the VM's compute host:

```bash
OS_CLIENT_CONFIG_FILE=/etc/kolla/clouds.yaml \
OS_CLOUD=kolla-admin \
openstack server show d0ba0068-b502-42e2-b9eb-40ef4f08458d \
  -c name -c status -c OS-EXT-SRV-ATTR:host -f yaml
```

Confirmed results:

- VM status: ACTIVE
- Original host: node2
- Destination host: node1
- Migration type: live-migration
- Nova migration status: completed
- Start: 2026-10-11 18:14:06 UTC
- Completion: 2026-10-11 18:14:43 UTC
- Total migration duration: 37 seconds
- No ping timeouts observed during the test

The migration duration is not equivalent to guest downtime.

## Important limitations

- Block live migration can work without shared Ceph storage.
- The source and destination compute hosts must remain available during migration.
- Live migration supports planned maintenance, not automatic recovery after host failure.
- Local Nova instance disks are not a substitute for persistent, backed-up database storage.

## Conclusion

Successfully migrated ai-cirros-01 from node2 to node1
while the instance remained ACTIVE.

This validates our first OpenStack block live migration test.
