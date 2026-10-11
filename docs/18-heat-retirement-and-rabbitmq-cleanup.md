# 18 — Heat Retirement and RabbitMQ Queue Cleanup

## Purpose

This chapter records a real maintenance operation performed on
9–10 October 2026 against the three-node Kolla-Ansible OpenStack lab.

The objective was to remove unused Heat services and stale RabbitMQ
queues without disrupting the remaining OpenStack control plane.

This is an EXISTING-DEPLOYMENT recovery procedure.

Do not automatically delete RabbitMQ queues during a fresh installation.

## Lab environment

| Component | Configuration |
|---|---|
| Operating system | Ubuntu 24.04.5 LTS |
| Nodes | node1 .200, node2 .201, node3 .202 |
| RabbitMQ | 4.2.9, three-node cluster |
| Container runtime | Docker |
| Service manager | Kolla-generated systemd units |
| OpenStack automation | Kolla-Ansible |
| Validation | scripts/lab-status.sh |

Full node addresses are in the repository README.

## 1. What went wrong?

The Kolla configuration contained:

```yaml
enable_heat: "no"
```

However, Heat containers remained running on all three nodes.

Investigation confirmed that the following systemd units were
still active and enabled:

```text
kolla-heat_engine-container.service
kolla-heat_api-container.service
kolla-heat_api_cfn-container.service
```

The units were capable of restarting Heat even though the desired
Kolla configuration had Heat disabled.

RabbitMQ also retained thousands of Heat-related quorum queues.

Their names matched two families:

```text
heat-engine-listener.<UUID>
engine_worker.<UUID>
```

The investigated queues had zero messages and zero consumers.

The exact historical mechanism that caused the accumulation
was not conclusively established.

## 2. Retire unused Heat services

IMPORTANT: Before retiring Heat in another deployment, identify
all projects and stacks that depend on it.

For this incident, admin and ai-lab stack checks returned no stacks.
The service project was not independently verified, and a global
stack listing was denied by Heat policy. This limitation is preserved
here rather than claiming all projects were conclusively empty.

On this lab, Heat was stopped with:

```bash
for ip in 200 201 202; do
  ssh openstack@192.168.0.$ip \
    'sudo systemctl stop \
      kolla-heat_engine-container.service \
      kolla-heat_api-container.service \
      kolla-heat_api_cfn-container.service'
done
```

Automatic startup was then disabled:

```bash
for ip in 200 201 202; do
  ssh openstack@192.168.0.$ip \
    'sudo systemctl disable \
      kolla-heat_engine-container.service \
      kolla-heat_api-container.service \
      kolla-heat_api_cfn-container.service'
done
```

All nine units were independently verified as:

```text
active=inactive
enabled=disabled
```

The Docker containers and their data were not removed.

Disabling these units prevents their normal systemd boot startup,
but future Kolla-Ansible operations may reconfigure them.

## 3. RabbitMQ investigation

The RabbitMQ cluster was verified as:

```text
Running nodes:
rabbit@node1
rabbit@node2
rabbit@node3

Alarms: none
Network partitions: none
```

The queue inventory identified 10,522 Heat-named quorum queues
with zero messages and zero consumers.

The inventory was saved outside Git:

```text
~/heat-queues-before.tsv
```

This file was an inventory, NOT a recoverable RabbitMQ backup.

Deleting quorum queues removes replicated queue state and is
not reversible merely by restoring that inventory.

## 4. Controlled cleanup performed

The cleanup progressed through these verified stages:

| Stage | Result |
|---|---|
| Initial CLI test | 1 queue deleted |
| Remaining pilot | 9 queues deleted |
| CLI batch | 100 queues deleted |
| HTTP API batch | 100 queues deleted |
| Automated cleanup | 42 batches, maximum 250 per batch |
| Final batch | 61 queues deleted |
| Final eligible queue count | 0 |

One queue had also disappeared between inventory checks,
so the exact number deleted by our commands should not be
inferred solely from subtracting the initial and final counts.

The automated cleanup used RabbitMQ's authenticated management API
through an SSH tunnel.

The operator ran:

```text
~/heat-queue-cleanup.py
```

This utility was kept outside the repository during the incident.
It must be separately reviewed before being committed as a
reusable maintenance tool.

Safety controls included:

- Strict Heat queue names with UUIDs
- Quorum queue type checks
- Zero-message and zero-consumer checks
- A fresh API inspection before deletion
- Explicit operator authorization
- Individual queue deletions
- Periodic RabbitMQ health checks
- OpenStack health validation after each batch
- Per-deletion audit logs

The checks reduce risk but do not make deletion atomic.
There remains a possible state change between inspection
and deletion.

No broad queue TTL policy, RabbitMQ reset, or HA reduction
was used.

## 5. Final recorded results

The automated job reported:

```text
===== BATCH 42 =====
Remaining eligible: 61
Deleting: 61
SUCCESS: 61 deleted
OpenStack: HEALTHY (14/14)
COMPLETE: No eligible Heat queues remain.
```

The final cleanup audit log was:

```text
/home/joe/heat-api-delete-20261009-220900.jsonl
```

The overall health history was saved at:

```text
/home/joe/heat-bulk-health-20261009-203653.log
```

The final result demonstrates successful removal of eligible
Heat queues while the core OpenStack health checks remained green.

This validation does not constitute a complete functional test
of every application or tenant.

## Post-cleanup memory measurements

Measurements collected after the successful 42-batch cleanup:

| Node | RAM available before | RAM available after | Gain |
|---|---:|---:|---:|
| node1 | 5.4 GiB | 6.2 GiB | +0.8 GiB |
| node2 | 6.0 GiB | 6.8 GiB | +0.8 GiB |
| node3 | 6.1 GiB | 6.8 GiB | +0.7 GiB |

Approximately 2.3 GiB more host RAM was available across
the cluster compared with the post-Heat-stop baseline.

RabbitMQ container memory:

| Node | Before | After |
|---|---:|---:|
| node1 | 2.132 GiB | 1.271 GiB |
| node2 | 2.091 GiB | 1.225 GiB |
| node3 | 1.803 GiB | 969.5 MiB |

Combined RabbitMQ container memory fell by approximately 2.6 GiB.

RabbitMQ quorum queue-process memory:

| Node | Before | After |
|---|---:|---:|
| node1 | 0.6475 gb | 0.0198 gb |
| node2 | 0.6347 gb | 0.0179 gb |
| node3 | 0.6283 gb | 0.0170 gb |

This represents approximately a 97% reduction in the
quorum queue-process memory component on each node.

These are observed snapshots, not a controlled benchmark.
Normal workload fluctuations and Linux memory management
can also affect host available-memory measurements.

Conclusion: retiring unused Heat services and removing
the abandoned-looking queues substantially reduced measured
RabbitMQ memory consumption while core OpenStack health
remained at 14/14 checks passed.

## 6. Future fresh-build configuration

For this resource-constrained homelab, the intended configuration
in /etc/kolla/globals.yml is:

```yaml
enable_heat: "no"
om_enable_rabbitmq_stream_fanout: false
```

The second setting is a LAB-SPECIFIC workaround documented in
Chapter 16. It should not be assumed to be a production default.

On a clean installation:

1. Decide which optional services are actually required.
2. Set enable_heat before the initial Kolla deployment.
3. Validate the deployed service inventory.
4. Verify RabbitMQ cluster health and queue counts.
5. Record a memory and health baseline.

Do not run the destructive queue cleanup on a normal fresh build.

For an existing deployment, changing globals.yml alone
must not be assumed to retire already-deployed services.

## 7. Verification commands

Check Heat service state on all nodes:

```bash
for ip in 200 201 202; do
  echo "===== NODE $ip ====="
  ssh openstack@192.168.0.$ip '
    for svc in heat_engine heat_api heat_api_cfn; do
      unit="kolla-${svc}-container.service"
      printf "%-15s active=%-10s enabled=%s\n" \
        "$svc" \
        "$(systemctl is-active "$unit")" \
        "$(systemctl is-enabled "$unit")"
    done
  '
done
```

Check the remaining Heat queues:

```bash
ssh -n openstack@192.168.0.200 \
  'sudo docker exec rabbitmq rabbitmqctl -p / list_queues name type messages consumers' |
awk '
  $1 ~ /^(heat-engine-listener|engine_worker)\.[0-9a-f-]+$/ {
    count++
  }
  END {
    printf "Remaining Heat-named queues: %d\n", count+0
  }
'
```

Validate OpenStack:

```bash
./scripts/lab-status.sh
```

The normal core health target is:

```text
RESULT: HEALTHY
PASS checks: 14
```

## 8. Lessons for disaster recovery

- Desired Kolla configuration and actual runtime state can differ.
- A running container may be controlled by a systemd unit.
- Stopping a container and disabling automatic startup are different.
- Durable RabbitMQ queues may outlive their original consumers.
- Thousands of empty quorum queues can consume meaningful resources.
- Queue deletion must be restricted, auditable and validated.
- A queue inventory is not a RabbitMQ data backup.
- Destructive maintenance is not a prerequisite for fresh deployment.
- Historical fixes should be documented without automatically
  becoming permanent installation steps.

The next learning milestone is repeatability: deploy the cloud
from documented Ubuntu, Ansible and Kolla configuration, then
provision application VMs through Terraform and Ansible.
