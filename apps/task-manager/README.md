# Flask Task Manager — Beginner Guide

## What is this?
A **Flask** web application that stores tasks in **PostgreSQL**, running on your OpenStack VM.

Flask is a lightweight Python web framework. Think of it as a tool that lets you write Python functions that respond to web requests (like visiting a URL in your browser).

## Project Structure
```
apps/task-manager/
├── app.py                    # The Flask application
├── requirements.txt          # Python dependencies (Flask + psycopg)
├── README.md                 # This file
└── templates/
    └── index.html            # HTML template with Jinja2 syntax
```

## The Code Explained (`app.py`)

### 1. Import and Setup
```python
import os
import logging
from flask import Flask, jsonify, render_template, request, redirect, url_for
import psycopg

# Configure logging: generic messages only, no sensitive data
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
```
- `Flask(__name__)` creates the application object.
- `psycopg` is the PostgreSQL driver (modern, fast, supports prepared statements).
- `render_template` renders HTML templates with Jinja2 (auto-escapes variables).
- `request` gives access to form data, `redirect`/`url_for` handle navigation.
- **Logging** configured to output generic messages only — no sensitive data in logs.

### 2. Database Connection
```python
def get_db_connection():
    """Create a database connection from environment variables."""
    return psycopg.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "appdb"),
        user=os.environ.get("PGUSER", "appuser"),
        password=os.environ.get("PGPASSWORD", ""),
        autocommit=True,
    )
```
- Reads **all credentials from environment variables** — no hardcoded secrets.
- `autocommit=True` means each statement commits immediately (fine for simple CRUD).
- Connection is opened per-request using a context manager (`with`), ensuring it closes.

### 3. Routes — Health Check
```python
@app.route("/health")
def health():
    return jsonify({"status": "ok"})
```
- Unchanged: returns JSON for monitoring/load balancers.

### 4. Routes — List Tasks (GET /)
```python
@app.route("/")
def index():
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id, title, completed FROM tasks ORDER BY id")
                tasks = cur.fetchall()
    except psycopg.Error:
        logger.error("Database query failed: list tasks")
        return "Database unavailable", 503
    return render_template("index.html", tasks=tasks)
```
- Fetches all tasks from the `tasks` table.
- **Parameterized query**: `cur.execute("SELECT ...")` — no string interpolation, prevents SQL injection.
- On DB error (`psycopg.Error`), logs generic message and returns **HTTP 503** — never exposes internals.
- Passes `tasks` (list of tuples) to the template.

### 5. Routes — Add Task (POST /add)
```python
@app.route("/add", methods=["POST"])
def add_task():
    title = request.form.get("title", "").strip()
    if not title:
        return redirect(url_for("index"))
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO tasks (title, completed) VALUES (%s, FALSE)",
                    (title,),
                )
    except psycopg.Error:
        logger.error("Database query failed: add task")
        return "Database unavailable", 503
    return redirect(url_for("index"))
```
- Gets `title` from form data, strips whitespace.
- **Parameterized INSERT** with `%s` placeholder — safe from SQL injection.
- On DB error, logs and returns **HTTP 503**.
- Redirects back to `/` after insert (Post/Redirect/Get pattern).

### 6. Routes — Toggle Complete (POST /toggle/<id>)
```python
@app.route("/toggle/<int:task_id>", methods=["POST"])
def toggle_task(task_id):
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE tasks SET completed = NOT completed WHERE id = %s",
                    (task_id,),
                )
    except psycopg.Error:
        logger.error("Database query failed: toggle task")
        return "Database unavailable", 503
    return redirect(url_for("index"))
```
- `<int:task_id>` converts URL parameter to integer (Flask validates).
- Parameterized UPDATE with `%s`.
- On DB error, logs and returns **HTTP 503**.

### 7. Routes — Delete Task (POST /delete/<id>)
```python
@app.route("/delete/<int:task_id>", methods=["POST"])
def delete_task(task_id):
    try:
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
    except psycopg.Error:
        logger.error("Database query failed: delete task")
        return "Database unavailable", 503
    return redirect(url_for("index"))
```
- Parameterized DELETE.
- On DB error, logs and returns **HTTP 503**.

### 8. Running the App
```python
if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)
```
- `host="127.0.0.1"` — Flask listens only on localhost inside the VM.
- NGINX (port 80) proxies to `127.0.0.1:5000`.

## Template (`templates/index.html`)

Uses **Jinja2** templating (built into Flask):

```html
{% for task in tasks %}
<li class="task {% if task[2] %}completed{% endif %}">
    <span class="task-title">{{ task[1] }}</span>
    ...
{% endfor %}
```

- `{{ task[1] }}` — **auto-escaped** output (prevents XSS).
- `{% if task[2] %}` — conditional CSS class for completed tasks.
- Forms use `action="{{ url_for('add_task') }}"` — generates correct URLs.

## Dependencies (`requirements.txt`)
```
Flask==3.0.3
psycopg[binary]==3.1.18
```
- `psycopg[binary]` includes pre-compiled C extensions (no build tools needed).
- Install with: `pip install -r requirements.txt`

## Environment Variables (Required at Runtime)
| Variable | Description | Default |
|----------|-------------|---------|
| `PGHOST` | PostgreSQL host | `localhost` |
| `PGPORT` | PostgreSQL port | `5432` |
| `PGDATABASE` | Database name | `appdb` |
| `PGUSER` | Database user | `appuser` |
| `PGPASSWORD` | Database password | *(required)* |

**Never hardcode these.** The Ansible deployment injects them via systemd `EnvironmentFile` at `/etc/task-manager/task-manager.env` (root:root, 0600).

## How to Run Locally (for testing)
```bash
cd apps/task-manager
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Set env vars (replace with your local DB)
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=appdb
export PGUSER=appuser
export PGPASSWORD=yourpassword

python app.py
```
Then open `http://localhost:5000/` and `http://localhost:5000/health`.

## Deployment Status (OpenStack Lab)
✅ **Completed** — The application is deployed to `web-01` via Ansible:
- PostgreSQL on `db-01` (10.20.0.197) with `appdb`/`appuser` and scram-sha-256 auth
- Flask app runs under Gunicorn as systemd service `task-manager`
- NGINX on `web-01` proxies port 80 → `http://127.0.0.1:5000/`
- DB credentials delivered via protected `EnvironmentFile` (not in service unit)
- Health checks pass at `http://<web-01-floating-ip>/health`

## Production Notes
- Flask's **development server** (`app.run()`) is used **only when running `app.py` directly** (e.g., local testing). Do not use in production.
- Our **OpenStack deployment uses Gunicorn + NGINX** — the `app.run()` block is never executed in production.
- Gunicorn bound to `127.0.0.1:5000` + **NGINX reverse proxy** (NGINX already installed on web-01).
- NGINX listens on port 80 and proxies to `http://127.0.0.1:5000/`.
- The `tasks` table must exist in PostgreSQL (created separately by Ansible `create-tasks-table.yml`).
- No database tables are created automatically on startup.
- No credentials in code or logs.

## Security

### Implemented Protections
- **Parameterized queries** (`%s` placeholders) prevent SQL injection.
- **Jinja2 auto-escaping** prevents XSS in templates.
- **Environment variables** for all secrets — nothing in code.
- **Logging** outputs generic messages only — no sensitive data.
- **HTTP 503 on DB errors** — no stack traces leaked to users.
- **POST for mutations** — add/toggle/delete use POST, not GET.
- **Protected credentials file** — `/etc/task-manager/task-manager.env` (root:root, 0600).

### Current Limitations (Not Yet Addressed)
- ❌ **HTTP only** — no TLS/HTTPS termination (NGINX on port 80 only).
- ❌ **No login/authentication** — any network caller can access the app.
- ❌ **No CSRF protection** — forms vulnerable to cross-site request forgery.
- ❌ **No rate limiting** — no protection against abuse/DoS.
- ⚠️ **Partial security headers** — NGINX sets basic headers (e.g., `X-Content-Type-Options: nosniff`), but **CSP and HSTS are not configured**.

These are acceptable for a learning lab but would need remediation before any real deployment.

## Next Steps (For Learning)
1. Add HTTPS with self-signed or real certificates (NGINX + certbot)
2. Implement user authentication (Flask-Login or similar)
3. Add CSRF protection (Flask-WTF)
4. Add security headers via NGINX or Flask-Talisman
5. Deploy behind a load balancer with health checks