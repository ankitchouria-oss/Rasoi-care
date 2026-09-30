"""
Kitchen Passport relational schema (SQLite + Postgres compatible — the
same `?`-placeholder wrapper in database.py serves both).

Tables are prefixed `kp_` so they never collide with the existing
booking app's `appliances`/`appliance_health` tables. Raw inspection
values live one-row-per-parameter in kp_inspection_measurements (typed
value_num / value_text columns + the param schema version), never in a
single free-text blob, so they can be re-scored or analysed later.
"""

SCHEMA = """
CREATE TABLE IF NOT EXISTS kp_config (
    section         TEXT PRIMARY KEY,
    value_json      TEXT NOT NULL,
    updated_by      TEXT,
    updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_config_history (
    id              TEXT PRIMARY KEY,
    algorithm_version INTEGER NOT NULL,
    section         TEXT NOT NULL,
    value_json      TEXT NOT NULL,
    updated_by      TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_counters (
    name            TEXT PRIMARY KEY,
    value           INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_customers (
    customer_id     TEXT PRIMARY KEY,
    user_id         TEXT UNIQUE NOT NULL REFERENCES users(id),
    full_name       TEXT NOT NULL,
    mobile_number   TEXT,
    whatsapp_number TEXT,
    email           TEXT,
    address         TEXT,
    service_location TEXT,
    latitude        REAL,
    longitude       REAL,
    preferred_service_time TEXT,
    preferred_contact_method TEXT,
    customer_since  TEXT NOT NULL,
    membership_status TEXT NOT NULL DEFAULT 'NONE',
    amc_status      TEXT NOT NULL DEFAULT 'NONE',
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_kitchen_passports (
    passport_id     TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES kp_customers(customer_id),
    qr_token        TEXT UNIQUE NOT NULL,
    status          TEXT NOT NULL DEFAULT 'ACTIVE',
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_kitchens (
    kitchen_id      TEXT PRIMARY KEY,
    passport_id     TEXT NOT NULL REFERENCES kp_kitchen_passports(passport_id),
    name            TEXT NOT NULL DEFAULT 'My Kitchen',
    kitchen_type    TEXT,
    kitchen_age     INTEGER,
    cooking_frequency TEXT,
    cooking_intensity TEXT NOT NULL DEFAULT 'MODERATE',
    approximate_daily_cooking_hours REAL,
    installation_information TEXT,
    last_overall_inspection TEXT,
    overall_health_score INTEGER,
    overall_score_status TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_appliance_categories (
    code            TEXT PRIMARY KEY,
    label           TEXT NOT NULL,
    id_prefix       TEXT NOT NULL,
    phase           INTEGER NOT NULL DEFAULT 1,
    active          INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS kp_inspection_parameters (
    category        TEXT NOT NULL REFERENCES kp_appliance_categories(code),
    param_key       TEXT NOT NULL,
    schema_version  INTEGER NOT NULL,
    label           TEXT NOT NULL,
    value_type      TEXT NOT NULL,
    unit            TEXT,
    options_json    TEXT,
    required        INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (category, param_key, schema_version)
);

CREATE TABLE IF NOT EXISTS kp_appliances (
    appliance_id    TEXT PRIMARY KEY,
    kitchen_id      TEXT NOT NULL REFERENCES kp_kitchens(kitchen_id),
    category        TEXT NOT NULL REFERENCES kp_appliance_categories(code),
    brand           TEXT,
    model           TEXT,
    serial_number   TEXT,
    purchase_date   TEXT,
    installation_date TEXT,
    warranty_start  TEXT,
    warranty_end    TEXT,
    extended_warranty INTEGER NOT NULL DEFAULT 0,
    installation_company TEXT,
    manufacturer_interval_days INTEGER,
    current_status  TEXT NOT NULL DEFAULT 'ACTIVE',
    last_service_date TEXT,
    next_service_date TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_technician_credentials (
    technician_id   TEXT PRIMARY KEY REFERENCES technicians(id),
    phone           TEXT UNIQUE NOT NULL,
    pin_hash        TEXT NOT NULL,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_technician_jobs (
    job_id          TEXT PRIMARY KEY,
    kitchen_id      TEXT NOT NULL REFERENCES kp_kitchens(kitchen_id),
    technician_id   TEXT NOT NULL REFERENCES technicians(id),
    appliance_id    TEXT REFERENCES kp_appliances(appliance_id),
    scheduled_date  TEXT NOT NULL,
    job_type        TEXT NOT NULL DEFAULT 'SERVICE',
    status          TEXT NOT NULL DEFAULT 'ASSIGNED',
    notes           TEXT,
    created_by      TEXT,
    created_at      TEXT NOT NULL,
    completed_at    TEXT
);

CREATE TABLE IF NOT EXISTS kp_service_records (
    service_id      TEXT PRIMARY KEY,
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    job_id          TEXT REFERENCES kp_technician_jobs(job_id),
    technician_id   TEXT REFERENCES technicians(id),
    service_type    TEXT NOT NULL DEFAULT 'SERVICE',
    status          TEXT NOT NULL DEFAULT 'IN_PROGRESS',
    service_date    TEXT NOT NULL,
    before_inspection_id TEXT,
    after_inspection_id TEXT,
    before_score    INTEGER,
    after_score     INTEGER,
    work_performed  TEXT,
    technician_observations TEXT,
    customer_approved_at TEXT,
    created_at      TEXT NOT NULL,
    completed_at    TEXT
);

CREATE TABLE IF NOT EXISTS kp_appliance_inspections (
    inspection_id   TEXT PRIMARY KEY,
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    service_id      TEXT REFERENCES kp_service_records(service_id),
    technician_id   TEXT REFERENCES technicians(id),
    phase           TEXT NOT NULL DEFAULT 'BEFORE',
    param_schema_version INTEGER NOT NULL,
    inspected_at    TEXT NOT NULL,
    observations    TEXT,
    technician_findings_json TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_inspection_measurements (
    id              TEXT PRIMARY KEY,
    inspection_id   TEXT NOT NULL REFERENCES kp_appliance_inspections(inspection_id),
    param_key       TEXT NOT NULL,
    value_num       REAL,
    value_text      TEXT,
    value_bool      INTEGER,
    unit            TEXT,
    derived         INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS kp_health_scores (
    id              TEXT PRIMARY KEY,
    inspection_id   TEXT NOT NULL REFERENCES kp_appliance_inspections(inspection_id),
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    algorithm_version INTEGER NOT NULL,
    score           INTEGER NOT NULL,
    score_status    TEXT NOT NULL,
    safety_status   TEXT NOT NULL,
    repair_priority TEXT NOT NULL,
    priority_reason TEXT,
    action_text     TEXT,
    components_json TEXT NOT NULL,
    is_current      INTEGER NOT NULL DEFAULT 1,
    calculated_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_safety_findings (
    id              TEXT PRIMARY KEY,
    inspection_id   TEXT NOT NULL REFERENCES kp_appliance_inspections(inspection_id),
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    level           TEXT NOT NULL,
    finding         TEXT NOT NULL,
    customer_message TEXT,
    param_key       TEXT,
    source          TEXT NOT NULL,
    resolved_at     TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_repair_recommendations (
    id              TEXT PRIMARY KEY,
    inspection_id   TEXT NOT NULL REFERENCES kp_appliance_inspections(inspection_id),
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    text            TEXT NOT NULL,
    technical_detail TEXT,
    priority        TEXT NOT NULL,
    urgent          INTEGER NOT NULL DEFAULT 0,
    recommended_within_days INTEGER,
    status          TEXT NOT NULL DEFAULT 'OPEN',
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_service_schedules (
    appliance_id    TEXT PRIMARY KEY REFERENCES kp_appliances(appliance_id),
    base_service_interval_days INTEGER NOT NULL,
    adjusted_service_interval_days INTEGER NOT NULL,
    last_service_date TEXT NOT NULL,
    recommended_service_date TEXT NOT NULL,
    factors_json    TEXT,
    source_inspection_id TEXT,
    updated_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_parts (
    part_id         TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    category        TEXT,
    part_number     TEXT,
    price           INTEGER NOT NULL DEFAULT 0,
    warranty_days   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS kp_part_replacements (
    id              TEXT PRIMARY KEY,
    service_id      TEXT NOT NULL REFERENCES kp_service_records(service_id),
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    part_id         TEXT REFERENCES kp_parts(part_id),
    part_name       TEXT NOT NULL,
    quantity        INTEGER NOT NULL DEFAULT 1,
    unit_price      INTEGER NOT NULL DEFAULT 0,
    warranty_until  TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_warranties (
    id              TEXT PRIMARY KEY,
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    kind            TEXT NOT NULL,
    provider        TEXT,
    start_date      TEXT,
    end_date        TEXT,
    reference       TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_photos (
    photo_id        TEXT PRIMARY KEY,
    appliance_id    TEXT NOT NULL REFERENCES kp_appliances(appliance_id),
    service_id      TEXT REFERENCES kp_service_records(service_id),
    inspection_id   TEXT,
    kind            TEXT NOT NULL,
    mime_type       TEXT NOT NULL,
    data_b64        TEXT NOT NULL,
    caption         TEXT,
    uploaded_by     TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_invoices (
    invoice_id      TEXT PRIMARY KEY,
    service_id      TEXT NOT NULL REFERENCES kp_service_records(service_id),
    labour_amount   INTEGER NOT NULL DEFAULT 0,
    parts_amount    INTEGER NOT NULL DEFAULT 0,
    total_amount    INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'ISSUED',
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_notifications (
    id              TEXT PRIMARY KEY,
    customer_id     TEXT NOT NULL REFERENCES kp_customers(customer_id),
    kind            TEXT NOT NULL,
    channel         TEXT NOT NULL,
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    appliance_id    TEXT,
    status          TEXT NOT NULL DEFAULT 'QUEUED',
    created_at      TEXT NOT NULL,
    read_at         TEXT
);

CREATE TABLE IF NOT EXISTS kp_health_timeline (
    id              TEXT PRIMARY KEY,
    kitchen_id      TEXT NOT NULL REFERENCES kp_kitchens(kitchen_id),
    score_date      TEXT NOT NULL,
    overall_score   INTEGER NOT NULL,
    score_status    TEXT NOT NULL,
    score_change_from_previous INTEGER,
    lowest_scoring_appliance TEXT,
    highest_priority_action TEXT,
    service_id      TEXT,
    appliance_scores_json TEXT NOT NULL,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kp_ai_assessments (
    id              TEXT PRIMARY KEY,
    appliance_id    TEXT REFERENCES kp_appliances(appliance_id),
    kitchen_id      TEXT REFERENCES kp_kitchens(kitchen_id),
    kind            TEXT NOT NULL,
    input_summary_json TEXT NOT NULL,
    output_json     TEXT NOT NULL,
    model           TEXT NOT NULL,
    created_at      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS kp_idx_appl_kitchen ON kp_appliances(kitchen_id);
CREATE INDEX IF NOT EXISTS kp_idx_insp_appl ON kp_appliance_inspections(appliance_id);
CREATE INDEX IF NOT EXISTS kp_idx_meas_insp ON kp_inspection_measurements(inspection_id);
CREATE INDEX IF NOT EXISTS kp_idx_scores_appl ON kp_health_scores(appliance_id);
CREATE INDEX IF NOT EXISTS kp_idx_jobs_tech ON kp_technician_jobs(technician_id, scheduled_date);
CREATE INDEX IF NOT EXISTS kp_idx_svc_appl ON kp_service_records(appliance_id);
CREATE INDEX IF NOT EXISTS kp_idx_timeline_kitchen ON kp_health_timeline(kitchen_id, score_date);
"""
