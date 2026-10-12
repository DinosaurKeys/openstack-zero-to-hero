# Ansible Ubuntu App Lab

## Overview
This playbook configures the `web-01` VM (created by Terraform in `terraform/03-ubuntu-app-lab/`) with NGINX and a simple welcome page.

## Prerequisites
- Terraform has created the VM and outputs show `vm_floating_ip = 192.168.0.169`
- SSH key `~/.ssh/openstack-lab-vm` exists and matches the `ai-key` keypair
- VM is reachable via SSH as `ubuntu` user
- Python 3.12 available at `/usr/bin/python3.12` (verified with `ansible -m ping`)

## Files
- `inventory.yml` — Static inventory for web-01
- `playbook.yml` — Installs NGINX, enables service, deploys welcome page

## Run the playbook
```bash
cd ansible/03-ubuntu-app-lab
ansible-playbook -i inventory.yml playbook.yml
```

## Verify
```bash
# Check NGINX is running
curl http://192.168.0.169

# Expected output: HTML page with "OpenStack + Terraform + Ansible + Hermes"
```

## Idempotency
Re-running the playbook produces no changes (all tasks use state-based modules: `apt`, `systemd`, `copy`).