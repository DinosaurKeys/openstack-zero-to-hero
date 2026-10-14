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


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


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


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000)