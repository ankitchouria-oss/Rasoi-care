"""
RasoiCare backend — database layer.

Real SQLite database (a single file on disk: rasoicare.db). SQLite is a
genuine SQL database — not a mock — it just happens to need zero setup,
which makes it the right choice for a first real backend. For a
production deployment serving real traffic at scale, swap this for
Postgres (e.g. via Render/Railway/Supabase's managed Postgres) by
changing only this file — the Flask routes in app.py don't need to
change, since they all go through the helper functions defined here.
"""

import sqlite3
import os
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rasoicare.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS technicians (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    category        TEXT NOT NULL,
    online          INTEGER NOT NULL DEFAULT 1,
    rating          REAL NOT NULL DEFAULT 5.0,
    rating_count    INTEGER NOT NULL DEFAULT 0,
    jobs_completed  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS bookings (
    id              TEXT PRIMARY KEY,
    category        TEXT NOT NULL,
    service         TEXT NOT NULL,
    price           INTEGER NOT NULL,
    technician_id   TEXT NOT NULL REFERENCES technicians(id),
    customer_name   TEXT NOT NULL DEFAULT 'Amit Sharma',
    status          TEXT NOT NULL DEFAULT 'Requested',
    bachat_slot     INTEGER,
    service_rating  INTEGER,
    tech_rating     INTEGER,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS complaints (
    id              TEXT PRIMARY KEY,
    booking_id      TEXT NOT NULL REFERENCES bookings(id),
    text            TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'New',
    response        TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS counters (
    name    TEXT PRIMARY KEY,
    value   INTEGER NOT NULL
);
"""


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def now():
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def seed(conn):
    """Populate fresh tables with the same starting story used across
    the RasoiCare prototypes, so this backend slots in as a drop-in
    replacement for the in-memory demo."""
    conn.executescript(
        "DELETE FROM complaints; DELETE FROM bookings; "
        "DELETE FROM technicians; DELETE FROM counters;"
    )
    conn.execute(
        "INSERT INTO technicians (id, name, category, online, rating, rating_count, jobs_completed) "
        "VALUES (?,?,?,?,?,?,?)",
        ("ramesh", "Ramesh Kumar", "RasoiSpark", 1, 4.8, 312, 312),
    )
    for tid, name, category, online, rating, jobs in [
        ("suresh", "Suresh Patil", "RasoiAir", 0, 4.6, 240),
        ("deepak", "Deepak Verma", "RasoiBuilt", 1, 4.9, 150),
        ("anjali", "Anjali Kulkarni", "RasoiSpark", 1, 4.7, 190),
    ]:
        conn.execute(
            "INSERT INTO technicians (id, name, category, online, rating, rating_count, jobs_completed) "
            "VALUES (?,?,?,?,?,?,?)",
            (tid, name, category, online, rating, jobs, jobs),
        )

    ts = now()
    conn.execute(
        "INSERT INTO bookings (id, category, service, price, technician_id, customer_name, status, "
        "bachat_slot, service_rating, tech_rating, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        ("RC-2291", "RasoiSpark", "Ignition Fix", 399, "ramesh", "Amit Sharma", "Completed",
         None, 2, 2, ts, ts),
    )
    conn.execute(
        "INSERT INTO bookings (id, category, service, price, technician_id, customer_name, status, "
        "bachat_slot, service_rating, tech_rating, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        ("RC-1987", "RasoiAir", "Deep Cleaning", 1600, "ramesh", "Amit Sharma", "Completed",
         1, 5, 5, ts, ts),
    )
    conn.execute(
        "INSERT INTO complaints (id, booking_id, text, status, response, created_at) VALUES (?,?,?,?,?,?)",
        ("CMP-1", "RC-2291",
         "Technician arrived 40 minutes late and the ignition issue came back within 2 days "
         "of the visit. Would like a free re-visit.",
         "New", None, ts),
    )
    conn.execute("INSERT INTO counters (name, value) VALUES ('order', 2292)")
    conn.execute("INSERT INTO counters (name, value) VALUES ('complaint', 2)")
    conn.commit()


def init_db(reset=False):
    conn = get_db()
    conn.executescript(SCHEMA)
    conn.commit()
    row = conn.execute("SELECT COUNT(*) AS n FROM technicians").fetchone()
    if reset or row["n"] == 0:
        seed(conn)
    conn.close()


def next_id(conn, counter_name, prefix):
    row = conn.execute("SELECT value FROM counters WHERE name = ?", (counter_name,)).fetchone()
    value = row["value"]
    conn.execute("UPDATE counters SET value = ? WHERE name = ?", (value + 1, counter_name))
    return f"{prefix}-{value}"
