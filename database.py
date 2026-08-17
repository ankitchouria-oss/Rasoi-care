"""
RasoiCare backend — database layer.

Two modes, chosen by whether DATABASE_URL is set:

- Unset (default): SQLite, a single file on disk (rasoicare.db). Zero
  setup, which makes it the right choice for local development — but
  Render's free web services have ephemeral disk, so anything written
  here is wiped on every redeploy.
- Set to a Postgres connection string (e.g. a free Neon/Render/Railway/
  Supabase database): every real booking, account, and stock change
  survives redeploys.

app.py's routes never touch this distinction — they all call
conn.execute(...)/.fetchone()/.fetchall() with `?` placeholders and
dict-style row access (row["col"]) exactly as sqlite3.Row provides.
When DATABASE_URL is set, get_db() returns a thin wrapper around a real
psycopg2/Postgres connection that accepts the same calling convention,
so nothing outside this file needs to change.
"""

import sqlite3
import os
import re
import json
import uuid
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rasoicare.db")
DATABASE_URL = os.environ.get("DATABASE_URL")

SCHEMA = """
CREATE TABLE IF NOT EXISTS technicians (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    category        TEXT NOT NULL,
    area            TEXT NOT NULL DEFAULT '',
    verified        INTEGER NOT NULL DEFAULT 0,
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
    area            TEXT,
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

CREATE TABLE IF NOT EXISTS staff (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    phone           TEXT UNIQUE NOT NULL,
    pin_hash        TEXT NOT NULL,
    role            TEXT NOT NULL DEFAULT 'staff',
    active          INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS inventory (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    sku             TEXT NOT NULL,
    category        TEXT NOT NULL,
    quantity        INTEGER NOT NULL DEFAULT 0,
    reorder_level   INTEGER NOT NULL DEFAULT 10,
    updated_at      TEXT NOT NULL
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

-- Standalone Home Services app (separate from the RasoiCare tables
-- above). Single-user prototype for now, so wallet/profile are one
-- fixed row (id=1) rather than keyed by an authenticated user.
CREATE TABLE IF NOT EXISTS hs_bookings (
    id              TEXT PRIMARY KEY,
    service_id      TEXT NOT NULL,
    service_name    TEXT NOT NULL,
    price           INTEGER NOT NULL,
    date            TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'Requested',
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hs_wallet (
    id      INTEGER PRIMARY KEY CHECK (id = 1),
    points  INTEGER NOT NULL DEFAULT 100
);

CREATE TABLE IF NOT EXISTS hs_wallet_tx (
    id          TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    amount      INTEGER NOT NULL,
    created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hs_profile (
    id      INTEGER PRIMARY KEY CHECK (id = 1),
    name    TEXT NOT NULL DEFAULT 'Ankit',
    plan    TEXT
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


from werkzeug.security import generate_password_hash

STAFF_SEED = [
    # (id, name, phone, pin, role)
    ("staff_owner", "Priya Deshmukh", "9822000001", "1234", "owner"),
    ("staff_ops", "Rahul Jadhav", "9822000002", "1234", "staff"),
]

INVENTORY_SEED = [
    # (id, name, sku, category, quantity, reorder_level)
    ("inv_baffle_filter", "Elica baffle filter 90cm", "ELF-90B", "RasoiAir", 8, 40),
    ("inv_ro_membrane", "RO membrane 80 GPD", "ROM-80", "RasoiPure", 14, 40),
    ("inv_hob_igniter", "Hob igniter — universal", "HBI-U", "RasoiSpark", 9, 30),
    ("inv_dw_pump", "Dishwasher drain pump", "DWP-BSH", "RasoiWash", 26, 30),
    ("inv_fridge_gas", "Fridge gas R600a (can)", "GAS-600", "RasoiChill", 48, 30),
]


class _PgRow(dict):
    """Postgres rows come back as plain dicts (via RealDictCursor) — this
    just adds sqlite3.Row's attribute-style access isn't needed, but
    dict already supports row["col"] and "col" in row.keys(), which is
    every access pattern app.py actually uses."""


class _PgCursor:
    """Wraps a psycopg2 cursor so callers written for sqlite3 don't need
    to change: fetchone()/fetchall() return dict-like rows."""

    def __init__(self, cur):
        self._cur = cur

    def fetchone(self):
        row = self._cur.fetchone()
        return _PgRow(row) if row is not None else None

    def fetchall(self):
        return [_PgRow(r) for r in self._cur.fetchall()]

    def close(self):
        self._cur.close()


_QMARK_RE = re.compile(r"\?")


class _PgConnection:
    """Wraps a psycopg2 connection so app.py's sqlite3-style calls
    (`?` placeholders, conn.execute(...).fetchone()/.fetchall(),
    conn.executescript(...)) work unchanged against Postgres."""

    def __init__(self, pg_conn):
        self._conn = pg_conn

    def execute(self, sql, params=()):
        import psycopg2.extras

        cur = self._conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(_QMARK_RE.sub("%s", sql), params)
        return _PgCursor(cur)

    def executescript(self, sql):
        cur = self._conn.cursor()
        cur.execute(sql)
        cur.close()

    def commit(self):
        self._conn.commit()

    def close(self):
        self._conn.close()


def get_db():
    if DATABASE_URL:
        import psycopg2

        pg_conn = psycopg2.connect(DATABASE_URL)
        return _PgConnection(pg_conn)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def _table_columns(conn, table_name):
    """Column names for `table_name` — works against either backend, so
    the three migrate_* functions below don't need to know which one
    they're running against."""
    if DATABASE_URL:
        rows = conn.execute(
            "SELECT column_name AS name FROM information_schema.columns "
            "WHERE table_name = ?",
            (table_name,),
        ).fetchall()
    else:
        rows = conn.execute(f"PRAGMA table_info({table_name})").fetchall()
    return {row["name"] for row in rows}


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
        "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
        "VALUES (?,?,?,?,?,?,?,?,?)",
        ("ramesh", "Ramesh Kumar", "RasoiSpark", "College Road", 1, 1, 4.8, 312, 312),
    )
    for tid, name, category, area, online, rating, jobs in [
        ("suresh", "Suresh Patil", "RasoiAir", "Gangapur Road", 0, 4.6, 240),
        ("deepak", "Deepak Verma", "RasoiBuilt", "Indira Nagar", 1, 4.9, 150),
        ("anjali", "Anjali Kulkarni", "RasoiSpark", "Panchavati", 1, 4.7, 190),
    ]:
        conn.execute(
            "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            (tid, name, category, area, 1, online, rating, jobs, jobs),
        )

    ts = now()
    conn.execute(
        "INSERT INTO bookings (id, category, service, price, technician_id, customer_name, status, "
        "bachat_slot, service_rating, tech_rating, area, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        ("RC-2291", "RasoiSpark", "Ignition Fix", 399, "ramesh", "Amit Sharma", "Completed",
         None, 2, 2, "College Road", ts, ts),
    )
    conn.execute(
        "INSERT INTO bookings (id, category, service, price, technician_id, customer_name, status, "
        "bachat_slot, service_rating, tech_rating, area, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        ("RC-1987", "RasoiAir", "Deep Cleaning", 1600, "ramesh", "Amit Sharma", "Completed",
         1, 5, 5, "Gangapur Road", ts, ts),
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
    cols = _table_columns(conn, "bookings")
    if "user_id" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN user_id TEXT")
    if "service_id" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN service_id TEXT")
    if "total_amount" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN total_amount INTEGER")
        conn.execute("UPDATE bookings SET total_amount = price WHERE total_amount IS NULL")
    if "area" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN area TEXT")
    if "lat" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN lat REAL")
    if "lng" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN lng REAL")
    if "in_progress_at" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN in_progress_at TEXT")
    if "suction_before" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN suction_before INTEGER")
    if "suction_after" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN suction_after INTEGER")
    if "time_on_site_min" not in cols:
        conn.execute("ALTER TABLE bookings ADD COLUMN time_on_site_min INTEGER")
    conn.commit()


def migrate_technicians_columns(conn):
    """Older rasoicare.db files predate the area/verification work."""
    cols = _table_columns(conn, "technicians")
    if "area" not in cols:
        conn.execute("ALTER TABLE technicians ADD COLUMN area TEXT NOT NULL DEFAULT ''")
    if "verified" not in cols:
        conn.execute("ALTER TABLE technicians ADD COLUMN verified INTEGER NOT NULL DEFAULT 0")
        # Technicians that already existed before this column shipped were
        # already live and taking real jobs — treat them as verified rather
        # than silently pulling them out of rotation.
        conn.execute("UPDATE technicians SET verified = 1")
    if "email" not in cols:
        conn.execute("ALTER TABLE technicians ADD COLUMN email TEXT")
    if "firebase_uid" not in cols:
        conn.execute("ALTER TABLE technicians ADD COLUMN firebase_uid TEXT")
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_technicians_firebase_uid "
            "ON technicians(firebase_uid) WHERE firebase_uid IS NOT NULL"
        )
    conn.commit()


def migrate_firebase_columns(conn):
    """Bridges Firebase-authenticated native apps (Customer/Partner/Admin)
    onto this backend without disturbing the existing password/PIN auth
    the web apps use — each table just gains an optional firebase_uid to
    key off once a native app calls its bootstrap endpoint."""
    user_cols = _table_columns(conn, "users")
    if "firebase_uid" not in user_cols:
        conn.execute("ALTER TABLE users ADD COLUMN firebase_uid TEXT")
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_firebase_uid "
            "ON users(firebase_uid) WHERE firebase_uid IS NOT NULL"
        )

    staff_cols = _table_columns(conn, "staff")
    if "email" not in staff_cols:
        conn.execute("ALTER TABLE staff ADD COLUMN email TEXT")
    if "firebase_uid" not in staff_cols:
        conn.execute("ALTER TABLE staff ADD COLUMN firebase_uid TEXT")
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_firebase_uid "
            "ON staff(firebase_uid) WHERE firebase_uid IS NOT NULL"
        )
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


def seed_staff(conn):
    """Owner/staff demo logins for the admin web app, seeded once and left
    alone afterwards (real invites shouldn't be wiped by a demo reset)."""
    row = conn.execute("SELECT COUNT(*) AS n FROM staff").fetchone()
    if row["n"] > 0:
        return
    ts = now()
    for sid, name, phone, pin, role in STAFF_SEED:
        conn.execute(
            "INSERT INTO staff (id, name, phone, pin_hash, role, active, created_at) VALUES (?,?,?,?,?,1,?)",
            (sid, name, phone, generate_password_hash(pin), role, ts),
        )
    conn.commit()


def seed_inventory(conn):
    """Spare-parts stock, seeded once. Left alone by /api/reset (which
    only resets bookings/technicians/complaints) since real stock counts
    shouldn't reset with the demo data."""
    row = conn.execute("SELECT COUNT(*) AS n FROM inventory").fetchone()
    if row["n"] > 0:
        return
    ts = now()
    for iid, name, sku, category, quantity, reorder_level in INVENTORY_SEED:
        conn.execute(
            "INSERT INTO inventory (id, name, sku, category, quantity, reorder_level, updated_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (iid, name, sku, category, quantity, reorder_level, ts),
        )
    conn.commit()


def seed_home_services(conn):
    """One-time defaults for the Home Services wallet/profile row. Left
    alone on subsequent boots (and by the RasoiCare /api/reset, which
    only touches the RasoiCare tables) so real usage isn't wiped."""
    if conn.execute("SELECT 1 FROM hs_wallet WHERE id = 1").fetchone() is None:
        conn.execute("INSERT INTO hs_wallet (id, points) VALUES (1, 100)")
    if conn.execute("SELECT 1 FROM hs_profile WHERE id = 1").fetchone() is None:
        conn.execute("INSERT INTO hs_profile (id, name, plan) VALUES (1, 'Ankit', NULL)")
    conn.commit()


def init_db(reset=False):
    conn = get_db()
    conn.executescript(SCHEMA)
    conn.commit()
    migrate_bookings_columns(conn)
    migrate_technicians_columns(conn)
    migrate_firebase_columns(conn)
    seed_catalog(conn)
    seed_staff(conn)
    seed_inventory(conn)
    seed_home_services(conn)
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
