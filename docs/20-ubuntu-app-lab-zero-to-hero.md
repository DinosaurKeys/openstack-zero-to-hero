# Ubuntu Application Lab — Zero to Hero

This guide walks through building a complete two-tier web application on OpenStack using Terraform, Ansible, PostgreSQL, Flask, Gunicorn, and NGINX.

It assumes you've completed the Terraform 01/02 and AI Lab (02) foundations. This is the next step: a real application with a database backend.

---

## 1. What We're Building

A **two-tier application**:

```
┌─────────────────────────────────────────────────────────────┐
│                        HOME LAN                             │
│                     192.168.0.0/24                          │
└─────────────────────────────┬───────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Floating IP      │
                    │  192.168.0.x      │
                    └─────────┬─────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      web-01 (VM)                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │   NGINX     │───▶│  Gunicorn   │───▶│   Flask App     │  │
│  │  (port 80)  │    │ (127.0.0.1:  │    │  (task-manager) │  │
│  │             │    │   5000)     │    │                 │  │
│  └─────────────┘    └─────────────┘    └────────┬────────┘  │
└─────────────────────────────────────────────────│───────────┘
                                                  │
                          ┌───────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      db-01 (VM)                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           PostgreSQL 16                             │   │
│  │  listen: localhost, 10.20.0.197                     │   │
│  │  auth: scram-sha-256                                │   │
│  │  db: appdb, user: appuser                           │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**VMware comparison:**
| OpenStack | VMware Concept |
|-----------|----------------|
| web-01 VM | Application server VM |
| db-01 VM | Database server VM |
| Floating IP | NAT/External IP on edge gateway |
| Security groups | Distributed firewall rules |
| Neutron router | Tier-0/Tier-1 gateway |

---

## 2. Why Each Component?

| Component | Purpose | Why Here? |
|-----------|---------|-----------|
| **Terraform** | Creates cloud infrastructure (VMs, networks, security groups) | Declarative, reproducible, version-controlled |
| **Ansible** | Configures OS, installs packages, deploys application | Imperative configuration, idempotent, runs on VMs |
| **PostgreSQL** | Relational database for task data | Production-grade, ACID, OpenStack-native |
| **Flask** | Python web framework for the application | Lightweight, beginner-friendly, runs on Gunicorn |
| **Gunicorn** | WSGI HTTP server for Flask | Production WSGI server, multi-worker |
| **NGINX** | Reverse proxy, static files, security headers | Terminates HTTP, proxies to Gunicorn, adds headers |

---

## 3. Prerequisites

- OpenStack lab running (3 nodes, healthy per `lab-status.sh`)
- Terraform installed on Hermes (`terraform version` → 1.16.x)
- Ansible installed on Hermes (`ansible --version`)
- SSH key at `~/.ssh/openstack-lab-vm` (registered as `ai-key` in OpenStack)
- `clouds.yaml` with a restricted cloud profile (e.g., `hermes-operator`)
- Ansible Vault password for `db-secrets.yml` (see note below)

> **Note:** `db-secrets.yml` is **excluded from Git** (in `.gitignore`). For a fresh deployment, you must create it separately with `ansible-vault create db-secrets.yml` and add the `vault_app_db_password` variable. The file contains the PostgreSQL password for `appuser` encrypted with your Ansible Vault password.

---

## 4. Deployment Order (Chronological)

```
Step 1: Terraform → Create infrastructure
Step 2: Ansible   → Configure PostgreSQL
Step 3: Ansible   → Create database & user
Step 4: Ansible   → Create tasks table
Step 5: Ansible   → Configure PostgreSQL network access
Step 6: Ansible   → Deploy Flask app (Gunicorn + NGINX)
Step 7: Verify    → Health checks, end-to-end test
```

Each step builds on the previous. Run in order.

---

## 5. Step 1 — Terraform: Create Infrastructure

**Directory:** `terraform/03-ubuntu-app-lab/`

### Files

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform 1.16, OpenStack provider 3.4.0 |
| `providers.tf` | OpenStack provider (no hardcoded cloud) |
| `data.tf` | Look up existing: Ubuntu image, flavor, network, subnet, SSH keypair |
| `network.tf` | Two security groups: `web-sg` (SSH+HTTP from 192.168.0.0/24 LAN **to web-01**), `db-sg` (SSH from web-sg, PostgreSQL **TCP 5432 from any VM with web-sg**) |
| `compute.tf` | Two VMs: `web-01` (web-sg), `db-01` (db-sg) on `ai-private` network |
| `floating-ip.tf` | Floating IP for `web-01` only (db-01 stays private) |
| `outputs.tf` | Useful IPs and names for Ansible inventory |

### Key Design Decisions

- **No router created here** — uses existing `ai-private` network/subnet from AI Lab (02)
- **Security groups reference each other** — `db-sg` allows PostgreSQL (5432) only from `web-sg` (not CIDR)
- **db-01 has no floating IP** — only reachable via `web-01` (bastion/jump)
- **Ansible inventory uses ProxyJump** — `db-01` accessed through `web-01`

### Commands

```bash
# On Hermes, select restricted cloud
export OS_CLIENT_CONFIG_FILE="$HOME/.config/openstack/hermes-clouds.yaml"
export OS_CLOUD=hermes-operator

cd ~/git/openstack-zero-to-hero/terraform/03-ubuntu-app-lab
terraform fmt
terraform validate
terraform plan
terraform apply
```

**What to verify:**
- `terraform apply` completes with 2 VMs, 2 security groups, 1 floating IP
- Outputs show `web-01` floating IP, `db-01` fixed IP (10.20.0.197)
- `openstack server list` shows both VMs ACTIVE

---

## 6. Step 2 — Ansible: Configure PostgreSQL Base

**Playbook:** `ansible/03-ubuntu-app-lab/db-playbook.yml`

### What It Does

```yaml
- Update APT cache
- Install postgresql + postgresql-client
- Enable/start postgresql service
- Verify with pg_isready
```

### Commands

```bash
cd ~/git/openstack-zero-to-hero/ansible/03-ubuntu-app-lab
ansible-playbook -i inventory.yml db-playbook.yml
```

**Verify:** `PostgreSQL ready: true` in output.

---

## 7. Step 3 — Ansible: Create Database & User

**Playbook:** `ansible/03-ubuntu-app-lab/create-appdb.yml`

### What It Does

- Loads `db-secrets.yml` (Ansible Vault, contains `vault_app_db_password`)
- Creates role `appuser` with `LOGIN,NOSUPERUSER,NOCREATEDB,NOCREATEROLE`
- Creates database `appdb` owned by `appuser`
- Verifies both exist via `postgresql_info`

### Commands

```bash
cd ~/git/openstack-zero-to-hero/ansible/03-ubuntu-app-lab
ansible-playbook -i inventory.yml create-appdb.yml --ask-vault-pass
```

**Verify:** Both assertions pass: `Database appdb verified`, `Role appuser verified`.

---

## 8. Step 4 — Ansible: Create Tasks Table

**Playbook:** `ansible/03-ubuntu-app-lab/create-tasks-table.yml`

### What It Does

- Creates `public.tasks` table in `appdb` with columns:
  - `id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY`
  - `title TEXT NOT NULL`
  - `completed BOOLEAN NOT NULL DEFAULT FALSE`
- Owner: `appuser`
- Verifies structure, identity column, primary key, ownership, permissions

### Commands

```bash
cd ~/git/openstack-zero-to-hero/ansible/03-ubuntu-app-lab
ansible-playbook -i inventory.yml create-tasks-table.yml
```

**Verify:** All assertions pass, summary shows correct columns and permissions.

---

## 9. Step 5 — Ansible: Configure PostgreSQL Network Access

**Playbook:** `ansible/03-ubuntu-app-lab/configure-postgresql.yml`

### What It Does

| Task | File Modified | Value |
|------|---------------|-------|
| Set `listen_addresses` | `/etc/postgresql/16/main/postgresql.conf` | `localhost,10.20.0.197` |
| Add pg_hba rule | `/etc/postgresql/16/main/pg_hba.conf` | `host appdb appuser 10.20.0.15/32 scram-sha-256` |
| Flush handlers | — | Restarts PostgreSQL if config changed |
| Verify `listen_addresses` | `SHOW listen_addresses;` | Must equal `localhost,10.20.0.197` |
| Verify `pg_hba_file_rules` | `SELECT rule_number, database, user_name, address, auth_method, error FROM pg_hba_file_rules WHERE 'appdb' = ANY(database) AND error IS NOT NULL;` | Must return 0 rows |

**Security notes:**
- **OpenStack firewall (db-sg):** Allows PostgreSQL TCP 5432 from any VM assigned `web-sg` (not a fixed CIDR)
- **PostgreSQL pg_hba:** Further restricts `appuser` access to `appdb` only from `10.20.0.15/32` (web-01 fixed IP) using `scram-sha-256`
- Authentication: `scram-sha-256` (modern, salted)
- Existing local/loopback rules preserved unchanged
- No `db-secrets.yml` loaded — this playbook doesn't need passwords

### Commands

```bash
cd ~/git/openstack-zero-to-hero/ansible/03-ubuntu-app-lab
ansible-playbook -i inventory.yml configure-postgresql.yml
```

**Verify:** Output shows `listen_addresses verified: localhost,10.20.0.197` and `pg_hba_file_rules verified: no errors`.

---

## 10. Step 6 — Ansible: Deploy Flask Application

**Playbook:** `ansible/03-ubuntu-app-lab/deploy-task-manager.yml`

### What It Does (in order)

1. **Prerequisites** — `python3-venv`, `python3-pip`
2. **App user** — `taskmgr` system user, home `/opt/task-manager`
3. **App directory** — `/opt/task-manager` (0750, taskmgr:taskmgr)
4. **Copy code** — `app.py`, `requirements.txt`, `templates/index.html`
5. **Virtual environment** — `/opt/task-manager/venv`
6. **Install deps** — Flask, psycopg, Gunicorn in venv
7. **EnvironmentFile** — `/etc/task-manager/task-manager.env` (root:root, 0600)
   ```
   PGHOST=10.20.0.197
   PGPORT=5432
   PGDATABASE=appdb
   PGUSER=appuser
   PGPASSWORD={{ vault_app_db_password | to_json }}
   ```
   - Template: `templates/task-manager.env.j2`
   - `no_log: true` — password never in Ansible output
8. **Systemd service** — `/etc/systemd/system/task-manager.service`
   - Uses `EnvironmentFile=/etc/task-manager/task-manager.env`
   - Gunicorn: 3 workers, bind 127.0.0.1:5000
9. **NGINX config** — `/etc/nginx/sites-available/task-manager`
   - Proxies `/` and `/health` to `http://127.0.0.1:5000`
   - Security headers: `X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`
   - Denies hidden files
10. **Validate & health check** — `nginx -t`, then polls `/health` on Gunicorn and NGINX

### Commands

```bash
cd ~/git/openstack-zero-to-hero/ansible/03-ubuntu-app-lab
ansible-playbook -i inventory.yml deploy-task-manager.yml --ask-vault-pass
```

**Verify:** Final output shows:
```
Gunicorn /health: {"status": "ok"}
NGINX  /health: {"status": "ok"}
```

---

## 11. Step 7 — Verification & Testing

### From Hermes (or any LAN host)

```bash
# Get floating IP from Terraform output
cd ~/git/openstack-zero-to-hero/terraform/03-ubuntu-app-lab
WEB_IP=$(terraform output -raw vm_floating_ip)

# Test health endpoint via NGINX
curl -s http://$WEB_IP/health | jq .

# Test full application
curl -s http://$WEB_IP/
```

**Expected health response:**
```json
{"status": "ok"}
```

**Expected app response:** HTML page with task list (empty initially), add/toggle/delete forms.

### From web-01 (inside VM)

```bash
ssh -i ~/.ssh/openstack-lab-vm ubuntu@$WEB_IP

# Direct Gunicorn health
curl -s http://127.0.0.1:5000/health

# Check service status
sudo systemctl status task-manager
sudo systemctl status nginx

# Check EnvironmentFile permissions
ls -la /etc/task-manager/task-manager.env
# Should show: -rw------- root root
```

### From db-01 (via jump)

```bash
# SSH through web-01 (ProxyJump in inventory)
ssh -i ~/.ssh/openstack-lab-vm -J ubuntu@$WEB_IP ubuntu@10.20.0.197

# Check PostgreSQL config
sudo -u postgres psql -c "SHOW listen_addresses;"
# Should show: localhost,10.20.0.197

# Check pg_hba rules
sudo -u postgres psql -c "SELECT * FROM pg_hba_file_rules WHERE 'appdb' = ANY(database);"

# Verify appdb and tasks table
sudo -u postgres psql -d appdb -c "\dt"
sudo -u postgres psql -d appdb -c "SELECT * FROM tasks;"
```

---

## 12. Security Precautions Implemented

| Layer | Protection |
|-------|------------|
| **Network** | db-01 no floating IP; OpenStack firewall (db-sg) allows TCP 5432 from any VM with web-sg; PostgreSQL pg_hba further restricts appuser to 10.20.0.15/32 |
| **PostgreSQL** | `listen_addresses` restricted; `scram-sha-256` auth; pg_hba allows only web-01 IP |
| **Credentials** | Vault-encrypted password; deployed via root-only 0600 EnvironmentFile; `no_log: true` |
| **Application** | Parameterized queries (SQL injection prevention); Jinja2 auto-escape (XSS prevention); HTTP 503 on DB errors (no stack traces) |
| **NGINX** | Security headers (`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `X-XSS-Protection`); hidden file blocking |
| **Systemd** | Dedicated `taskmgr` user (no shell, no home); service runs in venv isolation |

### Current Limitations (Not Yet Addressed)

- ❌ **HTTP only** — no TLS/HTTPS (port 80 only)
- ❌ **No authentication** — any LAN host can access the app
- ❌ **No CSRF protection** — forms vulnerable to cross-site request forgery
- ❌ **No rate limiting** — no abuse/DoS protection
- ⚠️ **Partial security headers** — CSP and HSTS not configured

---

## 13. Lessons Learned

### Terraform
- **Data sources vs resources** — Use `data` for existing infra (networks, images, flavors), `resource` for things Terraform should own
- **Security group references** — `remote_group_id` is cleaner than CIDR for tier-to-tier access
- **No floating IP for DB** — Keeps attack surface minimal; Ansible uses ProxyJump

### Ansible
- **Handlers + flush_handlers** — Restart PostgreSQL only once after all config changes
- **Verification after handlers** — Query live PostgreSQL (`SHOW listen_addresses`, `pg_hba_file_rules`) rather than checking files
- **EnvironmentFile pattern** — Keeps secrets out of systemd unit (world-readable); 0600 root-only file
- **Vault + to_json** — Escapes special chars in password for EnvironmentFile format
- **Idempotent lineinfile** — Precise regexps prevent duplicate rules on re-run

### Application
- **Per-request connections** — `with get_db_connection()` context manager ensures cleanup
- **Specific exception handling** — `except psycopg.Error:` not bare `except:`
- **Health endpoint** — Critical for Ansible verification and future load balancers
- **Gunicorn workers** — 3 workers handles concurrent requests; adjust for CPU cores

---

## 14. Relationship to AI Lab & Hermes Workflow

### This Lab Extends the AI Lab (02)

| AI Lab (02) | This Lab (03) |
|-------------|---------------|
| CirrOS test VM | Ubuntu application VMs |
| Basic network/security | Two-tier security groups |
| Proves OpenStack works | Deploys real workload |
| Manual verification | Automated health checks |

### Hermes-Assisted IaC Workflow

```
User Request
    │
    ▼
Hermes reads repo (Terraform, Ansible, app code)
    │
    ▼
Hermes proposes changes (git diff)
    │
    ▼
Human reviews & approves
    │
    ▼
Human runs: terraform apply / ansible-playbook
    │
    ▼
Hermes analyzes real output
    │
    ▼
Iterate or document
```

**Key principle from `AI/HERMES-LEARNING-GUIDE.md`:**
> UNDERSTAND before AUTOMATE
> MEASURE before CHANGE

Hermes helps translate intent into correct IaC resources — but the human executes and verifies.

---

## 15. Repository Files Reference

### Terraform (`terraform/03-ubuntu-app-lab/`)
```
versions.tf           # Provider versions
providers.tf          # OpenStack provider (no cloud)
data.tf               # Lookups: image, flavor, network, subnet, keypair
network.tf            # Security groups (web-sg, db-sg) + rules
compute.tf            # VMs: web-01, db-01
floating-ip.tf        # Floating IP for web-01 only
outputs.tf            # IPs, names for Ansible
```

### Ansible (`ansible/03-ubuntu-app-lab/`)
```
inventory.yml              # web-01 (direct), db-01 (ProxyJump)
playbook.yml               # Base NGINX welcome page
db-playbook.yml            # Install/start PostgreSQL
create-appdb.yml           # Create appdb, appuser (uses vault)
create-tasks-table.yml     # Create tasks table + verify
configure-postgresql.yml   # listen_addresses + pg_hba + verify
deploy-task-manager.yml    # Full Flask deployment
templates/
  task-manager.env.j2      # EnvironmentFile template (vault password)
  task-manager.service.j2  # Systemd unit (uses EnvironmentFile)
  task-manager.nginx.j2    # NGINX reverse proxy config
db-secrets.yml             # Ansible Vault: vault_app_db_password **(not in Git — create with `ansible-vault create`)**
```

### Application (`apps/task-manager/`)
```
app.py                  # Flask app (health, CRUD, parameterized queries)
requirements.txt        # Flask==3.0.3, psycopg[binary]==3.1.18
templates/index.html    # Jinja2 template (auto-escaped)
README.md               # Beginner guide (this lab's app documentation)
```

---

## 16. Troubleshooting Quick Reference

| Symptom | Check |
|---------|-------|
| Health check fails | `sudo systemctl status task-manager`; `sudo journalctl -u task-manager -f` |
| NGINX 502 | `curl http://127.0.0.1:5000/health` (Gunicorn); check Gunicorn logs |
| DB connection error | Verify `pg_hba.conf` rule; `sudo -u postgres psql -c "SELECT * FROM pg_hba_file_rules WHERE 'appdb' = ANY(database);"` |
| Floating IP unreachable | `openstack floating ip list`; security group `web-sg` allows HTTP from your CIDR |
| Ansible ProxyJump fails | `ssh -i ~/.ssh/openstack-lab-vm -J ubuntu@<web-floating> ubuntu@10.20.0.197` manually |
| Vault decrypt fails | `ansible-playbook ... --ask-vault-pass` (correct password) |

---

## 17. What's Next (Learning Path)

1. **Add HTTPS** — certbot + NGINX TLS termination
2. **Add authentication** — Flask-Login, user sessions
3. **Add CSRF protection** — Flask-WTF
4. **Add security headers** — CSP, HSTS via NGINX or Flask-Talisman
5. **Add rate limiting** — NGINX `limit_req_zone`
6. **Load balancer** — Terraform Octavia LB + multiple web VMs
7. **Monitoring** — Prometheus + Grafana on separate VM
8. **CI/CD** — GitHub Actions → Terraform plan → Ansible deploy

---

## 18. Summary

This lab demonstrated the complete **Infrastructure as Code → Configuration Management → Application Deployment** pipeline:

```
Terraform (cloud infra)
    │
    ▼
Ansible (OS + middleware + app)
    │
    ▼
Working two-tier app on OpenStack
```

Each layer is version-controlled, reproducible, and verifiable. The security model follows defense-in-depth: network isolation, least-privilege database access, encrypted secrets, and application-level protections.

**Files created/modified in this lab:**
- `terraform/03-ubuntu-app-lab/*.tf` (6 files)
- `ansible/03-ubuntu-app-lab/*.yml` (6 playbooks)
- `ansible/03-ubuntu-app-lab/templates/*.j2` (3 templates)
- `apps/task-manager/*` (4 app files)

> **⚠️ WARNING:** `terraform destroy` will permanently delete the working lab VMs (web-01, db-01), security groups, and floating IP. Only run this if you intend to tear down the entire lab environment. The Terraform configuration files remain for rebuild.