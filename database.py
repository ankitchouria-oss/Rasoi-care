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
import json
import uuid
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

CREATE TABLE IF NOT EXISTS users (
    id              TEXT PRIMARY KEY,
    email           TEXT UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    name            TEXT NOT NULL,
    phone           TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS appliances (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    category        TEXT NOT NULL,
    mono            TEXT NOT NULL,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS services (
    id              TEXT PRIMARY KEY,
    appliance_id    TEXT NOT NULL REFERENCES appliances(id),
    category        TEXT NOT NULL,
    name            TEXT NOT NULL,
    price           INTEGER NOT NULL,
    quick_fix       INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS amc_plans (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    price               INTEGER NOT NULL,
    duration_months     INTEGER NOT NULL,
    benefits            TEXT NOT NULL,
    created_at          TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS amc_subscriptions (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL REFERENCES users(id),
    plan_id         TEXT NOT NULL REFERENCES amc_plans(id),
    status          TEXT NOT NULL DEFAULT 'Active',
    start_date      TEXT NOT NULL,
    end_date        TEXT NOT NULL,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS appliance_health (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL REFERENCES users(id),
    appliance_id    TEXT NOT NULL REFERENCES appliances(id),
    metric_name     TEXT NOT NULL,
    value_pct       INTEGER NOT NULL,
    status_label    TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    UNIQUE(user_id, appliance_id)
);
"""

APPLIANCES_SEED = [
    ("app_chimney", "Chimney", "RasoiAir", "CH"),
    ("app_hob", "Hob", "RasoiSpark", "HB"),
    ("app_cooktop", "Cooktop", "RasoiSpark", "CT"),
    ("app_microwave", "Built-in Microwave", "RasoiBuilt", "MW"),
    ("app_dishwasher", "Dishwasher", "RasoiWash", "DW"),
    ("app_fridge", "Refrigerator", "RasoiChill", "RF"),
    ("app_otg", "OTG", "RasoiBuilt", "OT"),
    ("app_purifier", "Water Purifier", "RasoiPure", "WP"),
]

# (id, appliance_id, category, name, price, quick_fix)
SERVICES_SEED = [
    ("svc_chimney_deep_cleaning", "app_chimney", "RasoiAir", "Deep Cleaning", 1600, 0),
    ("svc_chimney_low_suction", "app_chimney", "RasoiAir", "Low Suction", 399, 1),
    ("svc_chimney_noisy_motor", "app_chimney", "RasoiAir", "Noisy Motor", 499, 1),
    ("svc_hob_ignition_fix", "app_hob", "RasoiSpark", "Ignition Fix", 399, 1),
    ("svc_hob_burner_cleaning", "app_hob", "RasoiSpark", "Burner Cleaning", 299, 1),
    ("svc_cooktop_ignition_fix", "app_cooktop", "RasoiSpark", "Ignition Fix", 399, 1),
    ("svc_cooktop_autoshutoff", "app_cooktop", "RasoiSpark", "Auto-shutoff Issue", 449, 1),
    ("svc_microwave_not_heating", "app_microwave", "RasoiBuilt", "Not Heating", 599, 0),
    ("svc_microwave_door_repair", "app_microwave", "RasoiBuilt", "Door / Hinge Repair", 399, 1),
    ("svc_microwave_general", "app_microwave", "RasoiBuilt", "General Service", 349, 1),
    ("svc_dishwasher_not_draining", "app_dishwasher", "RasoiWash", "Not Draining", 549, 0),
    ("svc_dishwasher_general", "app_dishwasher", "RasoiWash", "General Service", 399, 1),
    ("svc_fridge_not_cooling", "app_fridge", "RasoiChill", "Not Cooling", 699, 0),
    ("svc_fridge_gas_refill", "app_fridge", "RasoiChill", "Gas Refill", 1200, 0),
    ("svc_fridge_general", "app_fridge", "RasoiChill", "General Service", 399, 1),
    ("svc_otg_not_heating", "app_otg", "RasoiBuilt", "Not Heating", 399, 1),
    ("svc_otg_general", "app_otg", "RasoiBuilt", "General Service", 299, 1),
    ("svc_purifier_filter_change", "app_purifier", "RasoiPure", "Filter Change", 499, 1),
    ("svc_purifier_not_purifying", "app_purifier", "RasoiPure", "Not Purifying", 399, 1),
    ("svc_purifier_annual_service", "app_purifier", "RasoiPure", "Annual Service", 349, 1),
]

# (id, name, price, duration_months, benefits list)
AMC_PLANS_SEED = [
    ("amc_basic", "Basic Care", 999, 12,
     ["1 free check-up per year", "10% off repairs", "Standard response time"]),
    ("amc_premium", "Premium Care", 1999, 12,
     ["2 free check-ups per year", "10% off every repair", "Priority scheduling"]),
    ("amc_elite", "Elite Care", 3499, 12,
     ["4 free check-ups per year", "20% off every repair", "Priority scheduling", "24/7 dedicated support"]),
]


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


def migrate_bookings_columns(conn):
    """Older rasoicare.db files predate the auth/catalog work and lack
    these columns. SQLite's ALTER TABLE ADD COLUMN is safe to run on an
    existing table with data, so this upgrades in place instead of
    requiring a manual db reset."""
    cols = {row["name"] for row in conn.execute("PRAGMA table_info(bookings)").fetchall()}
    if "user_id" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN user_id TEXT")
    if "service_id" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN service_id TEXT")
    if "total_amount" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN total_amount INTEGER")
        conn.execute("UPDATE bookings SET total_amount = price WHERE total_amount IS NULL")
    conn.commit()


def seed_catalog(conn):
    """Appliances/services/AMC plans are static reference data, seeded
    once and left alone by demo resets (unlike bookings/complaints)."""
    row = conn.execute("SELECT COUNT(*) AS n FROM appliances").fetchone()
    if row["n"] > 0:
        return
    ts = now()
    for aid, name, category, mono in APPLIANCES_SEED:
        conn.execute(
            "INSERT INTO appliances (id, name, category, mono, created_at) VALUES (?,?,?,?,?)",
            (aid, name, category, mono, ts),
        )
    for sid, appliance_id, category, name, price, quick_fix in SERVICES_SEED:
        conn.execute(
            "INSERT INTO services (id, appliance_id, category, name, price, quick_fix, created_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (sid, appliance_id, category, name, price, quick_fix, ts),
        )
    for pid, name, price, duration_months, benefits in AMC_PLANS_SEED:
        conn.execute(
            "INSERT INTO amc_plans (id, name, price, duration_months, benefits, created_at) "
            "VALUES (?,?,?,?,?,?)",
            (pid, name, price, duration_months, json.dumps(benefits), ts),
        )
    conn.commit()


def init_db(reset=False):
    conn = get_db()
    conn.executescript(SCHEMA)
    conn.commit()
    migrate_bookings_columns(conn)
    seed_catalog(conn)
    row = conn.execute("SELECT COUNT(*) AS n FROM technicians").fetchone()
    if reset or row["n"] == 0:
        seed(conn)
    conn.close()


def next_id(conn, counter_name, prefix):
    row = conn.execute("SELECT value FROM counters WHERE name = ?", (counter_name,)).fetchone()
    value = row["value"]
    conn.execute("UPDATE counters SET value = ? WHERE name = ?", (value + 1, counter_name))
    return f"{prefix}-{value}"


def new_uuid_id(prefix):
    """IDs for entities outside the demo-reset lifecycle (users, AMC
    subscriptions) — not counter-based, so a demo /api/reset can't
    collide them with previously-issued ids."""
    return f"{prefix}-{uuid.uuid4().hex[:10]}"
