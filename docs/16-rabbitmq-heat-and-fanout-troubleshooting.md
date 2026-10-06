# RabbitMQ, Heat, and Stream Fanout Troubleshooting

This chapter documents a real RabbitMQ memory incident in the three-node
Kolla-Ansible OpenStack homelab.

It is intentionally separate from Chapter 04 because this was an operational
troubleshooting incident involving RabbitMQ queue growth, Heat, quorum queues,
stream fanout, and memory pressure.

---

# 1. Lab Context

The OpenStack cluster consists of three converged nodes:

```text
node1  192.168.0.200
node2  192.168.0.201
node3  192.168.0.202
```

Each node has approximately 15 GiB of usable RAM.

RabbitMQ provides the oslo.messaging backend used by OpenStack services and
runs as a three-node RabbitMQ cluster.

---

# 2. Initial Symptom

The first symptom was unusually high memory consumption.

RabbitMQ was using much more RAM than expected for a small homelab.

The useful diagnostic command was:

```bash
sudo docker exec rabbitmq rabbitmq-diagnostics memory_breakdown
```

During the incident, node1 showed approximately:

```text
quorum_queue_procs: 1.8992 GB
allocated_unused:   0.6433 GB
quorum_ets:         0.4389 GB
```

The important value was:

```text
quorum_queue_procs ~= 1.9 GB
```

This suggested that RabbitMQ quorum queues needed investigation.

---

# 3. Queue Explosion

RabbitMQ contained roughly 40,000 queues.

Approximately 37,000 were Heat-related queues with names similar to:

```text
engine_worker.<UUID>
heat-engine-listener.<UUID>
```

Most were empty and had no active consumers.

Therefore the problem was not thousands of queued OpenStack messages.

The problem was the number of RabbitMQ queue objects.

```text
Many Heat-related queues
        |
        v
Quorum queue state
        |
        v
RabbitMQ process and metadata overhead
        |
        v
High memory consumption
```

Quorum queues maintain additional replicated state for high availability.

Tens of thousands of unnecessary quorum queues therefore consume substantial
resources even when they contain no messages.

---

# 4. Heat Was Involved, but Heat Was Not Proven Broken

The stale queues were clearly Heat-related.

However, this does not mean:

```text
Heat = broken
```

After RabbitMQ cleanup, Heat was enabled again and tested.

The healthy state was approximately:

```text
Total RabbitMQ queues: ~300
Heat-related queues:   ~50-60
```

A Heat stack was created and deleted.

The queue count remained stable instead of increasing into the thousands.

Therefore the correct conclusion is:

> Heat owned the historical stale queues, but enabling Heat did not reproduce
> the queue explosion.

The exact historical lifecycle that produced tens of thousands of abandoned
queues was not conclusively identified.

---

# 5. What Fanout Means

OpenStack services communicate through RabbitMQ using oslo.messaging.

Some messages are sent to one specific worker.

Other messages use fanout, meaning that a message is delivered to multiple
interested consumers.

Conceptually:

```text
                 +--> worker A
                 |
publisher --> RabbitMQ --> worker B
                 |
                 +--> worker C
```

Fanout itself is normal OpenStack behavior.

The setting investigated in this incident does not disable fanout messaging.

It changes the RabbitMQ mechanism used to implement it.

---

# 6. RabbitMQ Stream Fanout

Modern Kolla-Ansible supports RabbitMQ streams for fanout.

The setting is:

```yaml
om_enable_rabbitmq_stream_fanout: true
```

Streams are normally the preferred modern implementation.

During troubleshooting in this lab, stream fanout caused RabbitMQ coordination
errors including:

```text
coordinator_unavailable
```

Nova and Neutron messaging became unstable.

To stabilize the lab, stream fanout was disabled:

```yaml
om_enable_rabbitmq_stream_fanout: false
```

Important:

```text
stream fanout disabled != OpenStack fanout disabled
```

OpenStack continues using normal RPC and fanout messaging through the
alternative queue implementation.

This is therefore a lab-specific workaround and not a general production
recommendation.

---

# 7. Production Best Practice

For a modern production Kolla deployment, RabbitMQ streams are normally the
preferred implementation for fanout.

A typical modern oslo.messaging configuration uses:

```text
rabbit_quorum_queue = True
rabbit_transient_quorum_queue = True
use_queue_manager = True
rabbit_stream_fanout = True
```

Therefore a production environment should not blindly copy:

```yaml
om_enable_rabbitmq_stream_fanout: false
```

If stream fanout fails in production, the preferred approach is to investigate
the RabbitMQ stream cluster and coordinator problem.

Official references:

- Kolla-Ansible RabbitMQ:
  https://docs.openstack.org/kolla-ansible/latest/reference/message-queues/rabbitmq.html
- oslo.messaging RabbitMQ driver:
  https://docs.openstack.org/oslo.messaging/latest/admin/rabbit.html
- oslo.messaging RabbitMQ options:
  https://docs.openstack.org/oslo.messaging/latest/configuration/opts.html

---

# 8. RabbitMQ Cleanup Result

After the old RabbitMQ queue state was cleaned, quorum queue process memory
dropped dramatically.

A later healthy measurement showed:

```text
node1 quorum_queue_procs: 0.0187 GB
node2 quorum_queue_procs: 0.0205 GB
node3 quorum_queue_procs: 0.0176 GB
```

Compare node1:

```text
During incident: ~1.8992 GB
After cleanup:   ~0.0187 GB
```

This is roughly a 100x reduction in the queue-process memory component.

This strongly suggests that the original RabbitMQ memory problem was caused by
the abnormal queue population rather than normal Heat operation.

---

# 9. Healthy Heat-On Baseline

Before disabling Heat, the lab was measured while Heat was still running.

Kolla configuration:

```yaml
enable_heat: "yes"
om_enable_rabbitmq_stream_fanout: false
```

Heat containers were running on all three nodes:

```text
heat_engine
heat_api_cfn
heat_api
```

RabbitMQ showed:

```text
Total queues:        298
Heat-related queues: 63
```

The OpenStack health check showed:

```text
MariaDB:              3/3 healthy
ProxySQL:             3/3 healthy
Placement API:        3/3 healthy
Nova control:         12/12 healthy
Neutron control:      9/9 healthy
Nova services:        6/6 enabled and up
Nova compute:         3/3 enabled and up
Hypervisors:          3/3 up
Neutron agents:       12/12 alive and UP

RESULT: HEALTHY
```

Memory with Heat enabled:

| Node | Used | Available | Swap used |
|---|---:|---:|---:|
| node1 | 9.7 GiB | 5.9 GiB | 542 MiB |
| node2 | 9.4 GiB | 6.1 GiB | 205 MiB |
| node3 | 8.5 GiB | 7.0 GiB | 116 MiB |

This proves that Heat can operate normally without immediately recreating the
old queue explosion.

---

# 10. Why Heat Was Disabled

Heat is optional for the current lab learning path.

Terraform communicates directly with the OpenStack APIs and does not require
Heat.

The current focus is:

```text
Terraform
   |
   +--> Keystone
   +--> Nova
   +--> Neutron
   +--> Glance
   +--> Cinder / Ceph
```

Because each node only has approximately 15 GiB RAM, unused optional services
consume valuable resources.

Heat was therefore disabled:

```yaml
enable_heat: "no"
```

This was a resource optimization.

It was not because Heat was proven defective.

---

# 11. Heat-Off Validation

After stopping Heat:

```text
node1: No Heat containers running
node2: No Heat containers running
node3: No Heat containers running
```

The lab remained healthy:

```text
RESULT: HEALTHY
PASS checks: 14
```

Nova, Neutron, Keystone, Placement, MariaDB, ProxySQL, and all three
hypervisors remained operational.

---

# 12. Memory Before and After Heat

Before stopping Heat:

| Node | Available |
|---|---:|
| node1 | 5.9 GiB |
| node2 | 6.1 GiB |
| node3 | 7.0 GiB |

After stopping Heat:

| Node | Available |
|---|---:|
| node1 | 6.7 GiB |
| node2 | 6.9 GiB |
| node3 | 7.9 GiB |

Approximate RAM recovered:

| Node | Improvement |
|---|---:|
| node1 | +0.8 GiB |
| node2 | +0.8 GiB |
| node3 | +0.9 GiB |

Approximately:

```text
2.5 GiB
```

was recovered across the cluster.

For three machines with approximately 15 GiB RAM each, this is significant.

Swap remained:

```text
node1: 542 MiB
node2: 205 MiB
node3: 116 MiB
```

This is normal.

Linux does not automatically move all previously swapped pages back into RAM
when memory becomes available.

When reading `free -h`, the most useful number is normally:

```text
available
```

rather than only:

```text
free
```

---

# 13. Heat Queues Remained After Heat Was Stopped

Immediately after stopping Heat, RabbitMQ was checked again.

Result:

```text
Total queues:        298
Heat-related queues: 63
```

The queue count did not immediately decrease.

This is an important observation.

```text
Heat stopped
     !=
Heat queues immediately deleted
```

Some RabbitMQ queues are durable and can remain after their consumer stops.

The critical difference is scale:

```text
Historical problem: ~37,000 Heat queues
Current state:           63 Heat queues
```

The current 63 queues do not by themselves indicate that the previous problem
has returned.

Their count should remain stable while Heat is disabled.

---

# 14. Useful Validation Commands

## Check Kolla settings

```bash
grep -E '^(enable_heat|om_enable_rabbitmq_stream_fanout):' \
  /etc/kolla/globals.yml
```

Current result:

```yaml
enable_heat: "no"
om_enable_rabbitmq_stream_fanout: false
```

## Check Heat containers

```bash
for ip in 200 201 202; do
    echo
    echo "===== NODE $ip ====="

    ssh openstack@192.168.0.$ip \
      'sudo docker ps --format "{{.Names}}" |
       grep -E "^heat_" ||
       echo "No Heat containers running"'
done
```

## Count RabbitMQ queues

```bash
ssh openstack@192.168.0.200 '
echo -n "Total queues: "
sudo docker exec rabbitmq rabbitmqctl -q list_queues name | wc -l

echo -n "Heat-related queues: "
sudo docker exec rabbitmq rabbitmqctl -q list_queues name |
grep -Ei "heat|engine_worker" |
wc -l
'
```

## RabbitMQ memory breakdown

```bash
for ip in 200 201 202; do
    echo
    echo "========== NODE $ip =========="
    ssh openstack@192.168.0.$ip \
      'sudo docker exec rabbitmq rabbitmq-diagnostics memory_breakdown | head -20'
done
```

## Host memory

```bash
for ip in 200 201 202; do
    echo
    echo "========== NODE $ip =========="
    ssh openstack@192.168.0.$ip 'free -h'
done
```

## Overall OpenStack health

```bash
./scripts/lab-status.sh
```

Expected:

```text
RESULT: HEALTHY
```

---

# 15. Current State

The current intentional Kolla configuration is:

```yaml
enable_heat: "no"
om_enable_rabbitmq_stream_fanout: false
```

Current architecture:

```text
Heat                         OFF
RabbitMQ stream fanout       OFF
OpenStack normal fanout/RPC  ON
RabbitMQ                     ON
Quorum queues                ON
Nova                         HEALTHY
Neutron                      HEALTHY
Terraform -> OpenStack       WORKING
```

---

# 16. Remaining Investigation

Two questions are intentionally still open.

## Why did the historical Heat queues accumulate?

Possible areas to investigate later:

- queue TTL / expiration
- durable queue lifecycle
- oslo.messaging queue manager
- repeated Heat engine recreation
- RabbitMQ state surviving service restarts
- version-specific behavior

We should not claim a root cause until it is proven.

## Why did RabbitMQ stream fanout fail?

The long-term production-style target remains:

```yaml
om_enable_rabbitmq_stream_fanout: true
```

Before attempting that again, investigate:

- RabbitMQ cluster membership
- stream coordinator health
- stream replicas
- RabbitMQ logs
- Kolla/RabbitMQ versions
- previous stream state

---

# 17. Lessons Learned

1. High RabbitMQ RAM does not necessarily mean many queued messages.
2. Check queue count and queue ownership early.
3. Empty quorum queues still consume resources.
4. Heat created the historical queue objects, but Heat was not proven broken.
5. Stream fanout and fanout itself are not the same thing.
6. Lab workarounds should not automatically become production standards.
7. Always measure before and after changes.
8. Optional OpenStack services matter on small-memory nodes.
9. Durable queues may survive after their service stops.
10. A healthy measured baseline is more valuable than guessing.

