# Cephadm Installation and Validation

Status: node2 executable installed (2026-10-16). Bootstrap, host enrollment,
disk cleanup, and OSD creation remain unapproved.

## Observed Results

Target: node2 (192.168.0.201) only. Playbook: `ansible/playbooks/07-cephadm-install.yml`.
Installed path: `/usr/local/sbin/cephadm-20.2.4`.

Version output:

```
cephadm version 20.2.4 (7f793731f1b39eb4f465e960113d2363c311b964) tentacle (stable)
```

Observed file SHA256 (observed identity, not an independently verified upstream checksum):

```
5b78c8d5772ef7c5c8619dac6ee0b36716b829338ea7a11c9f2b896626ab354f
```

Results:

| Run | ok | changed | unreachable | failed | skipped |
|---|---:|---:|---:|---:|---:|
| Initial | 8 | 1 | 0 | 0 | 1 |
| Repeat | 7 | 0 | 0 | 0 | 2 |

OpenStack health (`scripts/lab-status.sh`): HEALTHY, 14 checks passed, before and after.

## Idempotence

The repeat run produced `changed=0`; the executable was preserved unchanged when already correct. `force: false` and `stat` inspection prevent unwanted replacements.

## Repository Commands

Commands below assume the working directory `/home/joe/git/openstack-zero-to-hero` with the kolla venv active.

Syntax check playbook:

```bash
ansible-playbook --syntax-check -i ansible/inventory.ini ansible/playbooks/07-cephadm-install.yml
```

List hosts:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/07-cephadm-install.yml --list-hosts
```

Install with approval:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/07-cephadm-install.yml --extra-vars '{"cephadm_install_approved": true}'
```

Health check:

```bash
./scripts/lab-status.sh
```

Only the standalone tool was installed. Later stages are unapproved.

See chapter 24 (deployment plan) and chapter 22 (design) for placement context.
