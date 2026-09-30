"""
Kitchen Passport persistence + orchestration. All scoring is delegated
to engine.py; this module only loads inputs from the database, calls the
engines, and stores both the raw inspection data and the results.
"""

import copy
import json
import secrets
import uuid
from datetime import date, datetime, timedelta

from . import engine
from .config import DEFAULT_CONFIG
from .schema import SCHEMA

CONFIG_SECTIONS = ("score_thresholds", "countdown_thresholds", "kitchen_weights", "service_intervals",
                   "repair_priority", "safety", "notifications")


def _now():
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"


def _uid(prefix):
    return f"{prefix}-{uuid.uuid4().hex[:12]}"


def _j(v):
    return json.dumps(v, separators=(",", ":"))


def _row(r):
    return dict(r) if r is not None else None


# ================================================================ init / config
def init_kp(conn):
    conn.executescript(SCHEMA)
    conn.commit()
    cfg = load_config(conn)
    sync_categories(conn, cfg)


def sync_categories(conn, cfg):
    """Mirrors the category + parameter schema from config into
    kp_appliance_categories / kp_inspection_parameters so the data model
    documents exactly which parameters each schema version captured."""
    version = cfg["algorithm_version"]
    for code, cat in cfg["categories"].items():
        if conn.execute("SELECT code FROM kp_appliance_categories WHERE code = ?", (code,)).fetchone():
            conn.execute("UPDATE kp_appliance_categories SET label = ?, id_prefix = ?, phase = ? WHERE code = ?",
                         (cat["label"], cat["id_prefix"], cat.get("phase", 1), code))
        else:
            conn.execute("INSERT INTO kp_appliance_categories (code, label, id_prefix, phase, active) VALUES (?,?,?,?,1)",
                         (code, cat["label"], cat["id_prefix"], cat.get("phase", 1)))
        for p in cat["params"]:
            exists = conn.execute(
                "SELECT 1 AS x FROM kp_inspection_parameters WHERE category = ? AND param_key = ? AND schema_version = ?",
                (code, p["key"], version)).fetchone()
            if not exists:
                conn.execute(
                    "INSERT INTO kp_inspection_parameters (category, param_key, schema_version, label, value_type, unit, "
                    "options_json, required) VALUES (?,?,?,?,?,?,?,?)",
                    (code, p["key"], version, p["label"], p["type"], p.get("unit"),
                     _j(p.get("options")) if p.get("options") else None, 1 if p["required"] else 0))
    conn.commit()


def _deep_merge(base, over):
    if isinstance(base, dict) and isinstance(over, dict):
        out = dict(base)
        for k, v in over.items():
            out[k] = _deep_merge(base.get(k), v) if k in base else v
        return out
    return copy.deepcopy(over)


def load_config(conn):
    cfg = copy.deepcopy(DEFAULT_CONFIG)
    for r in conn.execute("SELECT section, value_json FROM kp_config").fetchall():
        section, value = r["section"], json.loads(r["value_json"])
        if section == "algorithm_version":
            cfg["algorithm_version"] = int(value)
        elif section.startswith("category:"):
            code = section.split(":", 1)[1]
            if code in cfg["categories"]:
                cfg["categories"][code] = _deep_merge(cfg["categories"][code], value)
            else:
                cfg["categories"][code] = value
        elif section in cfg:
            cfg[section] = _deep_merge(cfg[section], value) if isinstance(cfg[section], dict) else value
    return cfg


class ConfigError(ValueError):
    pass


def _validate_section(section, value, cfg):
    """Rejects configs that would make the engines misbehave."""
    if section in ("score_thresholds", "countdown_thresholds"):
        if not isinstance(value, list) or not value:
            raise ConfigError(f"{section} must be a non-empty list")
        mins = [b.get("min") for b in value]
        if any(not isinstance(m, (int, float)) for m in mins) or mins != sorted(mins, reverse=True):
            raise ConfigError(f"{section} 'min' values must be numbers in descending order")
        if any(not b.get("status") for b in value):
            raise ConfigError(f"{section} entries need a status")
    elif section == "kitchen_weights":
        if not isinstance(value, dict) or any(not isinstance(v, (int, float)) or v < 0 for v in value.values()):
            raise ConfigError("kitchen_weights must map category → non-negative number")
    elif section.startswith("category:"):
        if not isinstance(value, dict):
            raise ConfigError("category override must be an object")
        comps = value.get("components")
        if comps is not None:
            if not isinstance(comps, list) or any(not isinstance(c.get("weight"), (int, float)) or c["weight"] < 0 for c in comps):
                raise ConfigError("components need non-negative numeric weights")
        if "base_service_interval_days" in value and (not isinstance(value["base_service_interval_days"], int)
                                                      or value["base_service_interval_days"] < 1):
            raise ConfigError("base_service_interval_days must be a positive integer")
        if "weights" in value:
            if not isinstance(value["weights"], dict):
                raise ConfigError("weights must map component → number")
    elif section not in CONFIG_SECTIONS:
        raise ConfigError(f"unknown config section {section}")
    elif not isinstance(value, type(cfg[section])):
        raise ConfigError(f"{section} must be a {type(cfg[section]).__name__}")


def save_config_section(conn, section, value, updated_by):
    cfg = load_config(conn)
    # Friendly shape for weight editing: {"weights": {component_key: w}}
    if section.startswith("category:") and isinstance(value, dict) and "weights" in value:
        code = section.split(":", 1)[1]
        if code not in cfg["categories"]:
            raise ConfigError("unknown category")
        _validate_section(section, value, cfg)
        comps = copy.deepcopy(cfg["categories"][code]["components"])
        known = {c["key"] for c in comps}
        for k, w in value["weights"].items():
            if k not in known or not isinstance(w, (int, float)) or w < 0:
                raise ConfigError(f"invalid weight for {k}")
        for c in comps:
            if c["key"] in value["weights"]:
                c["weight"] = value["weights"][c["key"]]
        if sum(c["weight"] for c in comps) <= 0:
            raise ConfigError("weights must not all be zero")
        rest = {k: v for k, v in value.items() if k != "weights"}
        value = dict(rest, components=comps)
    _validate_section(section, value, cfg)
    new_version = cfg["algorithm_version"] + 1
    ts = _now()
    for sec, val in ((section, value), ("algorithm_version", new_version)):
        if conn.execute("SELECT section FROM kp_config WHERE section = ?", (sec,)).fetchone():
            conn.execute("UPDATE kp_config SET value_json = ?, updated_by = ?, updated_at = ? WHERE section = ?",
                         (_j(val), updated_by, ts, sec))
        else:
            conn.execute("INSERT INTO kp_config (section, value_json, updated_by, updated_at) VALUES (?,?,?,?)",
                         (sec, _j(val), updated_by, ts))
    conn.execute("INSERT INTO kp_config_history (id, algorithm_version, section, value_json, updated_by, created_at) "
                 "VALUES (?,?,?,?,?,?)", (_uid("CFG"), new_version, section, _j(value), updated_by, ts))
    conn.commit()
    cfg = load_config(conn)
    sync_categories(conn, cfg)
    return cfg


def reset_config_section(conn, section, updated_by):
    conn.execute("DELETE FROM kp_config WHERE section = ?", (section,))
    cfg = load_config(conn)
    new_version = cfg["algorithm_version"] + 1
    conn.execute("DELETE FROM kp_config WHERE section = 'algorithm_version'")
    conn.execute("INSERT INTO kp_config (section, value_json, updated_by, updated_at) VALUES (?,?,?,?)",
                 ("algorithm_version", _j(new_version), updated_by, _now()))
    conn.commit()
    return load_config(conn)


# ================================================================ ids
def next_seq(conn, name):
    row = conn.execute("SELECT value FROM kp_counters WHERE name = ?", (name,)).fetchone()
    if row is None:
        value = 1
        conn.execute("INSERT INTO kp_counters (name, value) VALUES (?, 2)", (name,))
    else:
        value = row["value"]
        conn.execute("UPDATE kp_counters SET value = ? WHERE name = ?", (value + 1, name))
    return value


def new_passport_id(conn):
    return f"RC-KP-{next_seq(conn, 'passport'):08d}"


def new_appliance_id(conn, cfg, category):
    prefix = cfg["categories"][category]["id_prefix"]
    return f"RC-{prefix}-{next_seq(conn, 'appliance:' + prefix):06d}"


# ================================================================ customers / passports
def get_customer_by_user(conn, user_id):
    return _row(conn.execute("SELECT * FROM kp_customers WHERE user_id = ?", (user_id,)).fetchone())


def ensure_customer_passport(conn, user, today=None):
    """Creates the customer profile, permanent Kitchen Passport and a
    first kitchen the first time a customer opens the module."""
    today = today or date.today()
    cust = get_customer_by_user(conn, user["id"])
    if not cust:
        cid = _uid("CUS")
        conn.execute(
            "INSERT INTO kp_customers (customer_id, user_id, full_name, mobile_number, whatsapp_number, email, "
            "customer_since, created_at) VALUES (?,?,?,?,?,?,?,?)",
            (cid, user["id"], user["name"], user["phone"] if "phone" in user.keys() else None,
             user["phone"] if "phone" in user.keys() else None, user["email"], today.isoformat(), _now()))
        cust = get_customer_by_user(conn, user["id"])
    passport = _row(conn.execute("SELECT * FROM kp_kitchen_passports WHERE customer_id = ?",
                                 (cust["customer_id"],)).fetchone())
    if not passport:
        pid = new_passport_id(conn)
        conn.execute("INSERT INTO kp_kitchen_passports (passport_id, customer_id, qr_token, created_at) VALUES (?,?,?,?)",
                     (pid, cust["customer_id"], secrets.token_urlsafe(16), _now()))
        conn.execute("INSERT INTO kp_kitchens (kitchen_id, passport_id, name, cooking_intensity, created_at) "
                     "VALUES (?,?,?,?,?)", (_uid("KIT"), pid, "My Kitchen", "MODERATE", _now()))
        passport = _row(conn.execute("SELECT * FROM kp_kitchen_passports WHERE passport_id = ?", (pid,)).fetchone())
    conn.commit()
    return cust, passport


def kitchens_for_passport(conn, passport_id):
    return [_row(r) for r in conn.execute("SELECT * FROM kp_kitchens WHERE passport_id = ? ORDER BY created_at",
                                          (passport_id,)).fetchall()]


def kitchen_owner(conn, kitchen_id):
    """(kitchen, passport, customer) for a kitchen id, or (None, None, None)."""
    k = _row(conn.execute("SELECT * FROM kp_kitchens WHERE kitchen_id = ?", (kitchen_id,)).fetchone())
    if not k:
        return None, None, None
    p = _row(conn.execute("SELECT * FROM kp_kitchen_passports WHERE passport_id = ?", (k["passport_id"],)).fetchone())
    c = _row(conn.execute("SELECT * FROM kp_customers WHERE customer_id = ?", (p["customer_id"],)).fetchone())
    return k, p, c


def appliance_owner(conn, appliance_id):
    a = _row(conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (appliance_id,)).fetchone())
    if not a:
        return None, None, None, None
    k, p, c = kitchen_owner(conn, a["kitchen_id"])
    return a, k, p, c


# ================================================================ appliances
APPLIANCE_FIELDS = ("brand", "model", "serial_number", "purchase_date", "installation_date", "warranty_start",
                    "warranty_end", "extended_warranty", "installation_company", "manufacturer_interval_days",
                    "last_service_date")


def create_appliance(conn, cfg, kitchen_id, category, fields):
    aid = new_appliance_id(conn, cfg, category)
    vals = {k: fields.get(k) for k in APPLIANCE_FIELDS}
    vals["extended_warranty"] = 1 if vals.get("extended_warranty") else 0
    conn.execute(
        "INSERT INTO kp_appliances (appliance_id, kitchen_id, category, brand, model, serial_number, purchase_date, "
        "installation_date, warranty_start, warranty_end, extended_warranty, installation_company, "
        "manufacturer_interval_days, last_service_date, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (aid, kitchen_id, category, vals["brand"], vals["model"], vals["serial_number"], vals["purchase_date"],
         vals["installation_date"], vals["warranty_start"], vals["warranty_end"], vals["extended_warranty"],
         vals["installation_company"], vals["manufacturer_interval_days"], vals["last_service_date"], _now()))
    if vals["warranty_end"]:
        conn.execute("INSERT INTO kp_warranties (id, appliance_id, kind, provider, start_date, end_date, created_at) "
                     "VALUES (?,?,?,?,?,?,?)", (_uid("WAR"), aid, "EXTENDED" if vals["extended_warranty"] else "MANUFACTURER",
                                                 vals["brand"], vals["warranty_start"], vals["warranty_end"], _now()))
    _refresh_kitchen_counts(conn, kitchen_id)
    conn.commit()
    return aid


def _refresh_kitchen_counts(conn, kitchen_id):
    pass  # number_of_appliances is computed on read (see kitchen_dict) so it can never drift


def appliance_age_years(a, today):
    d = engine._to_date(a.get("installation_date") or a.get("purchase_date"))
    return round((today - d).days / 365.25, 1) if d else None


def appliance_history(conn, appliance, today):
    """Inputs the engines need from the appliance's own past."""
    since = (today - timedelta(days=365)).isoformat()
    repairs = conn.execute(
        "SELECT COUNT(*) AS n FROM kp_service_records WHERE appliance_id = ? AND service_type = 'REPAIR' "
        "AND status IN ('COMPLETED','AWAITING_APPROVAL') AND service_date >= ?",
        (appliance["appliance_id"], since)).fetchone()["n"]
    prev = conn.execute("SELECT score FROM kp_health_scores WHERE appliance_id = ? AND is_current = 1",
                        (appliance["appliance_id"],)).fetchone()
    sched = conn.execute("SELECT adjusted_service_interval_days FROM kp_service_schedules WHERE appliance_id = ?",
                         (appliance["appliance_id"],)).fetchone()
    return {
        "last_service_date": appliance.get("last_service_date"),
        "repairs_12m": repairs,
        "previous_score": prev["score"] if prev else None,
        "previous_interval_days": sched["adjusted_service_interval_days"] if sched else None,
    }


def current_score(conn, appliance_id):
    r = _row(conn.execute("SELECT * FROM kp_health_scores WHERE appliance_id = ? AND is_current = 1",
                          (appliance_id,)).fetchone())
    if r:
        r["components"] = json.loads(r.pop("components_json"))
    return r


def schedule_for(conn, appliance_id):
    return _row(conn.execute("SELECT * FROM kp_service_schedules WHERE appliance_id = ?", (appliance_id,)).fetchone())


def appliance_card(conn, cfg, a, today):
    """The appliance with its four live indicators. Days remaining is
    recomputed from the stored recommended date on every read so the
    countdown is always current."""
    cat = cfg["categories"].get(a["category"], {"label": a["category"]})
    sc = current_score(conn, a["appliance_id"])
    sched = schedule_for(conn, a["appliance_id"])
    rec_date = sched["recommended_service_date"] if sched else a.get("next_service_date")
    cd = engine.calculate_days_remaining(rec_date, today)
    st = engine.service_status(cfg, cd["days_remaining"])
    safety = sc["safety_status"] if sc else None
    open_findings = [_row(f) for f in conn.execute(
        "SELECT level, finding, customer_message FROM kp_safety_findings WHERE appliance_id = ? AND resolved_at IS NULL "
        "AND inspection_id = ?", (a["appliance_id"], sc["inspection_id"] if sc else "")).fetchall()]
    recs = [_row(r) for r in conn.execute(
        "SELECT text, priority, urgent, recommended_within_days FROM kp_repair_recommendations "
        "WHERE appliance_id = ? AND inspection_id = ? AND status = 'OPEN'",
        (a["appliance_id"], sc["inspection_id"] if sc else "")).fetchall()]
    action = sc["action_text"] if sc else "Book first inspection"
    indicators = engine.four_indicators(
        cfg, score=sc["score"] if sc else None, status=sc["score_status"] if sc else None, safety_status=safety,
        days_remaining=cd["days_remaining"], overdue_days=cd["overdue_days"], service_state=st["status"],
        action=action, priority=sc["repair_priority"] if sc else None)
    indicators["service"].update({"label": st["label"], "color": st["color"], "recommended_service_date": rec_date,
                                  "last_service_date": a.get("last_service_date")})
    out = dict(a)
    out.update({
        "label": cat["label"],
        "appliance_age": appliance_age_years(a, today),
        "indicators": indicators,
        "safety_findings": open_findings,
        "recommendations": recs,
        "score_calculated_at": sc["calculated_at"] if sc else None,
        "algorithm_version": sc["algorithm_version"] if sc else None,
        "warranty_active": bool(a.get("warranty_end") and engine._to_date(a["warranty_end"]) >= today),
    })
    return out


def kitchen_dict(conn, k):
    k = dict(k)
    k["number_of_appliances"] = conn.execute(
        "SELECT COUNT(*) AS n FROM kp_appliances WHERE kitchen_id = ? AND current_status != 'REMOVED'",
        (k["kitchen_id"],)).fetchone()["n"]
    return k


def list_appliance_cards(conn, cfg, kitchen_id, today):
    rows = conn.execute("SELECT * FROM kp_appliances WHERE kitchen_id = ? AND current_status != 'REMOVED' "
                        "ORDER BY created_at", (kitchen_id,)).fetchall()
    return [appliance_card(conn, cfg, _row(r), today) for r in rows]


# ================================================================ inspections
def _store_measurements(conn, cfg, category, inspection_id, raw_values, derived_values):
    params = {p["key"]: p for p in cfg["categories"][category]["params"]}
    for key, v in derived_values.items():
        p = params.get(key)
        is_derived = 0 if key in raw_values and p is not None else 1
        num_v = v if isinstance(v, (int, float)) and not isinstance(v, bool) else None
        bool_v = (1 if v else 0) if isinstance(v, bool) else None
        text_v = v if isinstance(v, str) else None
        unit = p.get("unit") if p else ("%" if key == "suction_percentage" else "°C")
        conn.execute("INSERT INTO kp_inspection_measurements (id, inspection_id, param_key, value_num, value_text, "
                     "value_bool, unit, derived) VALUES (?,?,?,?,?,?,?,?)",
                     (_uid("MEA"), inspection_id, key, num_v, text_v, bool_v, unit, is_derived))


def load_measurements(conn, inspection_id, include_derived=False):
    rows = conn.execute("SELECT * FROM kp_inspection_measurements WHERE inspection_id = ?", (inspection_id,)).fetchall()
    out = {}
    for r in rows:
        if r["derived"] and not include_derived:
            continue
        if r["value_bool"] is not None:
            out[r["param_key"]] = bool(r["value_bool"])
        elif r["value_num"] is not None:
            out[r["param_key"]] = r["value_num"]
        else:
            out[r["param_key"]] = r["value_text"]
    return out


def record_inspection(conn, cfg, appliance, raw_values, *, phase="INSPECTION", service_id=None, technician_id=None,
                      technician_findings=None, observations=None, today=None, update_schedule=None):
    """Validate → evaluate with the engines → persist raw values and all
    calculated results. Returns (inspection_id, evaluation)."""
    today = today or date.today()
    _, kitchen, _, _ = appliance_owner(conn, appliance["appliance_id"])
    history = appliance_history(conn, appliance, today)
    app_ctx = dict(appliance, appliance_age_years=appliance_age_years(appliance, today))
    is_service_done = phase in ("AFTER", "INSPECTION")
    last_service = today if is_service_done else (appliance.get("last_service_date") or today)
    ev = engine.evaluate_inspection(cfg, appliance["category"], raw_values, history=history, kitchen=kitchen,
                                    appliance=app_ctx, technician_findings=technician_findings,
                                    last_service_date=last_service, today=today)
    iid = _uid("INS")
    ts = _now()
    conn.execute("INSERT INTO kp_appliance_inspections (inspection_id, appliance_id, service_id, technician_id, phase, "
                 "param_schema_version, inspected_at, observations, technician_findings_json, created_at) "
                 "VALUES (?,?,?,?,?,?,?,?,?,?)",
                 (iid, appliance["appliance_id"], service_id, technician_id, phase, cfg["algorithm_version"],
                  today.isoformat(), (observations or "")[:2000] or None, _j(technician_findings or []), ts))
    _store_measurements(conn, cfg, appliance["category"], iid, raw_values, ev["health"]["values"])
    _store_results(conn, appliance["appliance_id"], iid, ev, ts)
    if update_schedule if update_schedule is not None else is_service_done:
        _store_schedule(conn, appliance["appliance_id"], iid, ev["schedule"], ts)
    conn.commit()
    return iid, ev


def _store_results(conn, appliance_id, iid, ev, ts):
    conn.execute("UPDATE kp_health_scores SET is_current = 0 WHERE appliance_id = ?", (appliance_id,))
    conn.execute("INSERT INTO kp_health_scores (id, inspection_id, appliance_id, algorithm_version, score, score_status, "
                 "safety_status, repair_priority, priority_reason, action_text, components_json, is_current, calculated_at) "
                 "VALUES (?,?,?,?,?,?,?,?,?,?,?,1,?)",
                 (_uid("HSC"), iid, appliance_id, ev["algorithm_version"], ev["health"]["score"], ev["health"]["status"],
                  ev["safety"]["status"], ev["priority"]["priority"], ev["priority"]["reason"],
                  ev["recommendations"]["action"], _j(ev["health"]["components"]), ts))
    for f in ev["safety"]["findings"]:
        conn.execute("INSERT INTO kp_safety_findings (id, inspection_id, appliance_id, level, finding, customer_message, "
                     "param_key, source, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                     (_uid("SAF"), iid, appliance_id, f["level"], f["finding"], f["customer_message"], f["param"],
                      f["source"], ts))
    # Older open recommendations are superseded by the newest inspection.
    conn.execute("UPDATE kp_repair_recommendations SET status = 'SUPERSEDED' WHERE appliance_id = ? AND status = 'OPEN'",
                 (appliance_id,))
    for r in ev["recommendations"]["items"]:
        conn.execute("INSERT INTO kp_repair_recommendations (id, inspection_id, appliance_id, text, technical_detail, "
                     "priority, urgent, recommended_within_days, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                     (_uid("REC"), iid, appliance_id, r["text"], r["technical"], ev["priority"]["priority"],
                      1 if r["urgent"] else 0, ev["priority"]["recommended_within_days"], ts))


def _store_schedule(conn, appliance_id, iid, s, ts):
    params = (s["base_service_interval_days"], s["adjusted_service_interval_days"], s["last_service_date"],
              s["recommended_service_date"], _j(s["factors"]), iid, ts)
    if schedule_for(conn, appliance_id):
        conn.execute("UPDATE kp_service_schedules SET base_service_interval_days = ?, adjusted_service_interval_days = ?, "
                     "last_service_date = ?, recommended_service_date = ?, factors_json = ?, source_inspection_id = ?, "
                     "updated_at = ? WHERE appliance_id = ?", params + (appliance_id,))
    else:
        conn.execute("INSERT INTO kp_service_schedules (base_service_interval_days, adjusted_service_interval_days, "
                     "last_service_date, recommended_service_date, factors_json, source_inspection_id, updated_at, "
                     "appliance_id) VALUES (?,?,?,?,?,?,?,?)", params + (appliance_id,))
    conn.execute("UPDATE kp_appliances SET last_service_date = ?, next_service_date = ? WHERE appliance_id = ?",
                 (s["last_service_date"], s["recommended_service_date"], appliance_id))


def inspection_detail(conn, cfg, inspection_id):
    ins = _row(conn.execute("SELECT * FROM kp_appliance_inspections WHERE inspection_id = ?", (inspection_id,)).fetchone())
    if not ins:
        return None
    a = _row(conn.execute("SELECT category FROM kp_appliances WHERE appliance_id = ?", (ins["appliance_id"],)).fetchone())
    cat = cfg["categories"].get(a["category"], {"params": []})
    labels = {p["key"]: (p["label"], p.get("unit")) for p in cat["params"]}
    labels.update({"suction_percentage": ("Suction percentage", "%"),
                   "temperature_difference": ("Temperature difference", "°C"),
                   "temperature_overshoot": ("Temperature above set point", "°C"),
                   "temperature_deviation": ("Deviation from 4 °C", "°C")})
    meas = conn.execute("SELECT * FROM kp_inspection_measurements WHERE inspection_id = ?", (inspection_id,)).fetchall()
    ins["measurements"] = [{
        "param_key": m["param_key"], "label": labels.get(m["param_key"], (m["param_key"], None))[0],
        "value": bool(m["value_bool"]) if m["value_bool"] is not None else (m["value_num"] if m["value_num"] is not None else m["value_text"]),
        "unit": m["unit"], "derived": bool(m["derived"])} for m in meas]
    sc = _row(conn.execute("SELECT * FROM kp_health_scores WHERE inspection_id = ? ORDER BY calculated_at DESC",
                           (inspection_id,)).fetchone())
    if sc:
        sc["components"] = json.loads(sc.pop("components_json"))
    ins["health_score"] = sc
    ins["safety_findings"] = [_row(r) for r in conn.execute(
        "SELECT level, finding, customer_message, param_key, source FROM kp_safety_findings WHERE inspection_id = ?",
        (inspection_id,)).fetchall()]
    ins["recommendations"] = [_row(r) for r in conn.execute(
        "SELECT text, technical_detail, priority, urgent, recommended_within_days, status FROM kp_repair_recommendations "
        "WHERE inspection_id = ?", (inspection_id,)).fetchall()]
    ins["technician_findings"] = json.loads(ins.pop("technician_findings_json") or "[]")
    ins["photos"] = photo_meta(conn, inspection_id=inspection_id)
    return ins


def rescore_inspection(conn, cfg, inspection_id, today=None):
    """Re-runs the current algorithm over stored raw values (raw data is
    never modified). Stores a new health-score row for that inspection
    and makes it current if it was the appliance's latest."""
    ins = _row(conn.execute("SELECT * FROM kp_appliance_inspections WHERE inspection_id = ?", (inspection_id,)).fetchone())
    if not ins:
        return None
    a, kitchen, _, _ = appliance_owner(conn, ins["appliance_id"])
    today = today or engine._to_date(ins["inspected_at"])
    raw = load_measurements(conn, inspection_id)
    history = appliance_history(conn, a, today)
    ev = engine.evaluate_inspection(cfg, a["category"], raw, history=history, kitchen=kitchen,
                                    appliance=dict(a, appliance_age_years=appliance_age_years(a, today)),
                                    technician_findings=json.loads(ins["technician_findings_json"] or "[]"),
                                    last_service_date=a.get("last_service_date") or today, today=today)
    latest = conn.execute("SELECT inspection_id FROM kp_health_scores WHERE appliance_id = ? AND is_current = 1",
                          (a["appliance_id"],)).fetchone()
    ts = _now()
    if latest and latest["inspection_id"] == inspection_id:
        conn.execute("DELETE FROM kp_safety_findings WHERE inspection_id = ?", (inspection_id,))
        _store_results(conn, a["appliance_id"], inspection_id, ev, ts)
    else:
        conn.execute("INSERT INTO kp_health_scores (id, inspection_id, appliance_id, algorithm_version, score, score_status, "
                     "safety_status, repair_priority, priority_reason, action_text, components_json, is_current, "
                     "calculated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,0,?)",
                     (_uid("HSC"), inspection_id, a["appliance_id"], ev["algorithm_version"], ev["health"]["score"],
                      ev["health"]["status"], ev["safety"]["status"], ev["priority"]["priority"], ev["priority"]["reason"],
                      ev["recommendations"]["action"], _j(ev["health"]["components"]), ts))
    conn.commit()
    return ev


# ================================================================ photos
def photo_meta(conn, *, appliance_id=None, service_id=None, inspection_id=None):
    where, args = [], []
    for col, v in (("appliance_id", appliance_id), ("service_id", service_id), ("inspection_id", inspection_id)):
        if v:
            where.append(f"{col} = ?")
            args.append(v)
    if not where:
        return []
    rows = conn.execute("SELECT photo_id, appliance_id, service_id, inspection_id, kind, mime_type, caption, created_at "
                        "FROM kp_photos WHERE " + " AND ".join(where) + " ORDER BY created_at", tuple(args)).fetchall()
    return [_row(r) for r in rows]


def add_photo(conn, appliance_id, service_id, kind, mime_type, data_b64, caption, uploaded_by, inspection_id=None):
    pid = _uid("PHO")
    conn.execute("INSERT INTO kp_photos (photo_id, appliance_id, service_id, inspection_id, kind, mime_type, data_b64, "
                 "caption, uploaded_by, created_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                 (pid, appliance_id, service_id, inspection_id, kind, mime_type, data_b64, caption, uploaded_by, _now()))
    conn.commit()
    return pid


# ================================================================ services
def start_service(conn, appliance, job_id, technician_id, service_type, today):
    sid = _uid("SVC")
    conn.execute("INSERT INTO kp_service_records (service_id, appliance_id, job_id, technician_id, service_type, status, "
                 "service_date, created_at) VALUES (?,?,?,?,?,'IN_PROGRESS',?,?)",
                 (sid, appliance["appliance_id"], job_id, technician_id, service_type, today.isoformat(), _now()))
    if job_id:
        conn.execute("UPDATE kp_technician_jobs SET status = 'IN_PROGRESS' WHERE job_id = ? AND status = 'ASSIGNED'",
                     (job_id,))
    conn.commit()
    return sid


def get_service(conn, service_id):
    return _row(conn.execute("SELECT * FROM kp_service_records WHERE service_id = ?", (service_id,)).fetchone())


def complete_service(conn, cfg, service, *, work_performed, observations, parts, labour_amount, today):
    """Marks the service done (awaiting customer approval), stores parts
    + invoice, refreshes the kitchen score/timeline and queues
    notifications. The after-inspection must already be recorded."""
    a, kitchen, passport, cust = appliance_owner(conn, service["appliance_id"])
    parts_total = 0
    for p in parts or []:
        qty = int(p.get("quantity") or 1)
        price = int(p.get("unit_price") or 0)
        parts_total += qty * price
        wdays = int(p.get("warranty_days") or 0)
        conn.execute("INSERT INTO kp_part_replacements (id, service_id, appliance_id, part_id, part_name, quantity, "
                     "unit_price, warranty_until, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                     (_uid("PRT"), service["service_id"], a["appliance_id"], p.get("part_id"), str(p["part_name"])[:120],
                      qty, price, (today + timedelta(days=wdays)).isoformat() if wdays else None, _now()))
    conn.execute("UPDATE kp_service_records SET status = 'AWAITING_APPROVAL', work_performed = ?, "
                 "technician_observations = ?, completed_at = ? WHERE service_id = ?",
                 ((work_performed or "")[:2000], (observations or "")[:2000], _now(), service["service_id"]))
    conn.execute("INSERT INTO kp_invoices (invoice_id, service_id, labour_amount, parts_amount, total_amount, created_at) "
                 "VALUES (?,?,?,?,?,?)", (_uid("INV"), service["service_id"], int(labour_amount or 0), parts_total,
                                         int(labour_amount or 0) + parts_total, _now()))
    if service.get("job_id"):
        remaining = conn.execute("SELECT COUNT(*) AS n FROM kp_service_records WHERE job_id = ? AND status = 'IN_PROGRESS'",
                                 (service["job_id"],)).fetchone()["n"]
        if remaining == 0:
            conn.execute("UPDATE kp_technician_jobs SET status = 'COMPLETED', completed_at = ? WHERE job_id = ?",
                         (_now(), service["job_id"]))
    conn.commit()
    snap = recalc_kitchen(conn, cfg, kitchen["kitchen_id"], today, service_id=service["service_id"])
    notify(conn, cfg, cust["customer_id"], "on_report_ready", "Kitchen Health Report ready",
           f"Your {cfg['categories'][a['category']]['label']} service is complete. "
           f"Kitchen Health is now {snap['overall_score']}/100.", a["appliance_id"])
    return snap


def attach_inspection_to_service(conn, service_id, phase, inspection_id, score):
    if phase == "BEFORE":
        conn.execute("UPDATE kp_service_records SET before_inspection_id = ?, before_score = ? WHERE service_id = ?",
                     (inspection_id, score, service_id))
    else:
        conn.execute("UPDATE kp_service_records SET after_inspection_id = ?, after_score = ? WHERE service_id = ?",
                     (inspection_id, score, service_id))
    conn.commit()


def service_detail(conn, cfg, service_id):
    s = get_service(conn, service_id)
    if not s:
        return None
    a = _row(conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (s["appliance_id"],)).fetchone())
    label = cfg["categories"].get(a["category"], {}).get("label", a["category"])
    tech = conn.execute("SELECT id, name FROM technicians WHERE id = ?", (s["technician_id"],)).fetchone() \
        if s["technician_id"] else None
    s["appliance_label"] = label
    s["technician"] = {"id": tech["id"], "name": tech["name"]} if tech else None
    s["comparison"] = engine.generate_before_after_comparison(label, s["before_score"], s["after_score"])
    s["before_inspection"] = inspection_detail(conn, cfg, s["before_inspection_id"]) if s["before_inspection_id"] else None
    s["after_inspection"] = inspection_detail(conn, cfg, s["after_inspection_id"]) if s["after_inspection_id"] else None
    s["parts_replaced"] = [_row(r) for r in conn.execute(
        "SELECT part_name, quantity, unit_price, warranty_until FROM kp_part_replacements WHERE service_id = ?",
        (service_id,)).fetchall()]
    s["invoice"] = _row(conn.execute("SELECT * FROM kp_invoices WHERE service_id = ?", (service_id,)).fetchone())
    s["photos"] = photo_meta(conn, service_id=service_id)
    s["warranty"] = {"warranty_end": a.get("warranty_end"), "extended_warranty": bool(a.get("extended_warranty"))}
    return s


def list_services(conn, appliance_id):
    return [_row(r) for r in conn.execute(
        "SELECT service_id, service_type, status, service_date, before_score, after_score, work_performed "
        "FROM kp_service_records WHERE appliance_id = ? ORDER BY service_date DESC, created_at DESC",
        (appliance_id,)).fetchall()]


# ================================================================ kitchen score / timeline
def recalc_kitchen(conn, cfg, kitchen_id, today, service_id=None):
    rows = conn.execute("SELECT * FROM kp_appliances WHERE kitchen_id = ? AND current_status != 'REMOVED'",
                        (kitchen_id,)).fetchall()
    scores = []
    for a in rows:
        sc = current_score(conn, a["appliance_id"])
        if sc:
            scores.append({"appliance_id": a["appliance_id"], "category": a["category"], "score": sc["score"],
                           "priority": sc["repair_priority"], "action": sc["action_text"],
                           "label": cfg["categories"].get(a["category"], {}).get("label", a["category"])})
    # One timeline point per kitchen per day: a visit that services
    # several appliances updates that day's point instead of stacking.
    prev = conn.execute("SELECT overall_score FROM kp_health_timeline WHERE kitchen_id = ? AND score_date < ? "
                        "ORDER BY score_date DESC, created_at DESC LIMIT 1", (kitchen_id, today.isoformat())).fetchone()
    k = engine.calculate_kitchen_health_score(cfg, scores, prev["overall_score"] if prev else None)
    if k["overall_score"] is None:
        return k
    conn.execute("UPDATE kp_kitchens SET overall_health_score = ?, overall_score_status = ?, last_overall_inspection = ? "
                 "WHERE kitchen_id = ?", (k["overall_score"], k["score_status"], today.isoformat(), kitchen_id))
    same_day = conn.execute("SELECT id FROM kp_health_timeline WHERE kitchen_id = ? AND score_date = ?",
                            (kitchen_id, today.isoformat())).fetchone()
    vals = (k["overall_score"], k["score_status"], k["score_change_from_previous"], _j(k["lowest_scoring_appliance"]),
            _j(k["highest_priority_action"]), service_id, _j(scores))
    if same_day:
        conn.execute("UPDATE kp_health_timeline SET overall_score = ?, score_status = ?, score_change_from_previous = ?, "
                     "lowest_scoring_appliance = ?, highest_priority_action = ?, service_id = ?, "
                     "appliance_scores_json = ? WHERE id = ?", vals + (same_day["id"],))
    else:
        conn.execute("INSERT INTO kp_health_timeline (overall_score, score_status, score_change_from_previous, "
                     "lowest_scoring_appliance, highest_priority_action, service_id, appliance_scores_json, id, "
                     "kitchen_id, score_date, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                     vals + (_uid("TML"), kitchen_id, today.isoformat(), _now()))
    conn.commit()
    k["score_date"] = today.isoformat()
    return k


def timeline(conn, kitchen_id):
    rows = conn.execute("SELECT * FROM kp_health_timeline WHERE kitchen_id = ? ORDER BY score_date, created_at",
                        (kitchen_id,)).fetchall()
    snaps = [{"id": r["id"], "date": r["score_date"], "score": r["overall_score"], "status": r["score_status"],
              "service_id": r["service_id"], "appliance_scores": json.loads(r["appliance_scores_json"]),
              "lowest_scoring_appliance": json.loads(r["lowest_scoring_appliance"] or "null"),
              "highest_priority_action": json.loads(r["highest_priority_action"] or "null")} for r in rows]
    return engine.generate_health_timeline(snaps)


# ================================================================ dashboard / reports
def kitchen_dashboard(conn, cfg, kitchen, today):
    cards = list_appliance_cards(conn, cfg, kitchen["kitchen_id"], today)
    scores = [{"appliance_id": c["appliance_id"], "category": c["category"], "score": c["indicators"]["health"]["score"],
               "priority": c["indicators"]["action"]["priority"], "action": c["indicators"]["action"]["text"],
               "label": c["label"]} for c in cards]
    tl = timeline(conn, kitchen["kitchen_id"])
    prev = tl[1]["score"] if len(tl) > 1 else None
    k = engine.calculate_kitchen_health_score(cfg, scores, prev)
    worst_safety = max((c["indicators"]["safety"]["status"] or "NORMAL" for c in cards),
                       key=engine.SAFETY_ORDER.index, default="NORMAL")
    actions = []
    for c in cards:
        for r in c["recommendations"]:
            actions.append({"appliance_id": c["appliance_id"], "appliance": c["label"], "text": r["text"],
                            "priority": r["priority"], "urgent": bool(r["urgent"]),
                            "days_remaining": c["indicators"]["service"]["days_remaining"]})
    order = engine.PRIORITY_ORDER
    actions = [a for a in actions if a["priority"] != "MONITOR"]
    actions.sort(key=lambda a: (-order.index(a["priority"]), a["days_remaining"] if a["days_remaining"] is not None else 9999))
    return {
        "kitchen": kitchen_dict(conn, kitchen),
        "overall": dict(k, status_label=engine.status_label(cfg, k["score_status"]) if k["score_status"] else None,
                        worst_safety_status=worst_safety),
        "appliances": cards,
        "recommended_actions": actions,
    }


def generate_kitchen_passport(conn, cfg, passport_id, today, *, include_contact=True):
    """Full passport document: customer → kitchens → appliances →
    health → service history → warranty → previous problems."""
    p = _row(conn.execute("SELECT * FROM kp_kitchen_passports WHERE passport_id = ?", (passport_id,)).fetchone())
    if not p:
        return None
    c = _row(conn.execute("SELECT * FROM kp_customers WHERE customer_id = ?", (p["customer_id"],)).fetchone())
    customer = {"customer_id": c["customer_id"], "full_name": c["full_name"], "customer_since": c["customer_since"],
                "membership_status": c["membership_status"], "amc_status": c["amc_status"],
                "service_location": c["service_location"], "preferred_service_time": c["preferred_service_time"],
                "preferred_contact_method": c["preferred_contact_method"]}
    if include_contact:
        customer.update({"mobile_number": c["mobile_number"], "whatsapp_number": c["whatsapp_number"],
                         "email": c["email"], "address": c["address"]})
    kitchens = []
    for k in kitchens_for_passport(conn, passport_id):
        dash = kitchen_dashboard(conn, cfg, k, today)
        for a in dash["appliances"]:
            a["service_history"] = list_services(conn, a["appliance_id"])
            a["warranties"] = [_row(r) for r in conn.execute(
                "SELECT kind, provider, start_date, end_date FROM kp_warranties WHERE appliance_id = ?",
                (a["appliance_id"],)).fetchall()]
            a["previous_problems"] = [_row(r) for r in conn.execute(
                "SELECT f.level, f.finding, i.inspected_at FROM kp_safety_findings f JOIN kp_appliance_inspections i "
                "ON i.inspection_id = f.inspection_id WHERE f.appliance_id = ? ORDER BY i.inspected_at DESC LIMIT 10",
                (a["appliance_id"],)).fetchall()]
        kitchens.append(dash)
    return {"passport_id": p["passport_id"], "status": p["status"], "created_at": p["created_at"],
            "customer": customer, "kitchens": kitchens,
            "overall_kitchen_health": kitchens[0]["overall"] if kitchens else None}


def generate_health_report(conn, cfg, kitchen_id, today, service_id=None):
    """Kitchen Health Report (customer-friendly; technical detail kept in
    `technical` for the "View Full Inspection" section)."""
    k, p, c = kitchen_owner(conn, kitchen_id)
    dash = kitchen_dashboard(conn, cfg, k, today)
    report = {
        "title": "Kitchen Health Report",
        "generated_on": today.isoformat(),
        "passport_id": p["passport_id"],
        "customer_name": c["full_name"],
        "kitchen": {"name": k["name"], "cooking_intensity": k["cooking_intensity"]},
        "overall": dash["overall"],
        "appliances": [{
            "appliance_id": a["appliance_id"], "label": a["label"], "brand": a["brand"], "model": a["model"],
            "health": a["indicators"]["health"], "safety": a["indicators"]["safety"],
            "service": a["indicators"]["service"], "action": a["indicators"]["action"],
            "safety_findings": a["safety_findings"], "recommendations": a["recommendations"],
        } for a in dash["appliances"]],
        "recommended_actions": dash["recommended_actions"],
        "service": service_detail(conn, cfg, service_id) if service_id else None,
        "disclaimer": "Scores are calculated automatically from recorded inspection measurements. "
                      "Safety status is assessed separately from the health score.",
    }
    return report


# ================================================================ AI (data-grounded, rule-based)
def ai_appliance_summary(conn, cfg, appliance_id, store=True):
    a = _row(conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (appliance_id,)).fetchone())
    rows = conn.execute(
        "SELECT i.inspected_at, h.score, h.components_json, h.safety_status FROM kp_appliance_inspections i "
        "JOIN kp_health_scores h ON h.inspection_id = i.inspection_id "
        "WHERE i.appliance_id = ? AND h.id = (SELECT h2.id FROM kp_health_scores h2 WHERE h2.inspection_id = i.inspection_id "
        "ORDER BY h2.calculated_at DESC LIMIT 1) "
        # One reading per visit: the arrival (BEFORE) condition shows wear
        # between services; an AFTER reading is used only when the visit
        # had no BEFORE inspection.
        "AND NOT (i.phase = 'AFTER' AND EXISTS (SELECT 1 FROM kp_appliance_inspections b WHERE "
        "b.service_id = i.service_id AND b.phase = 'BEFORE')) "
        "ORDER BY i.inspected_at, i.created_at", (appliance_id,)).fetchall()
    ins = [{"date": r["inspected_at"], "score": r["score"], "components": json.loads(r["components_json"]),
            "safety_status": r["safety_status"]} for r in rows]
    label = cfg["categories"].get(a["category"], {}).get("label", a["category"])
    out = engine.generate_ai_health_summary(cfg, label, a["category"], ins)
    if store:
        conn.execute("INSERT INTO kp_ai_assessments (id, appliance_id, kind, input_summary_json, output_json, model, "
                     "created_at) VALUES (?,?,?,?,?,?,?)",
                     (_uid("AIA"), appliance_id, "TREND_SUMMARY", _j({"scores": [i["score"] for i in ins]}), _j(out),
                      "rules-v1", _now()))
        conn.commit()
    return out


# ================================================================ notifications
def notify(conn, cfg, customer_id, rule_key, title, body, appliance_id=None):
    channels = cfg["notifications"].get(rule_key, ["app"])
    for ch in channels:
        # In-app notifications are delivered by being stored; external
        # channels are queued for a provider integration (phase 3).
        conn.execute("INSERT INTO kp_notifications (id, customer_id, kind, channel, title, body, appliance_id, status, "
                     "created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                     (_uid("NTF"), customer_id, rule_key, ch, title[:200], body[:1000], appliance_id,
                      "DELIVERED" if ch == "app" else "QUEUED", _now()))
    conn.commit()


def notify_safety(conn, cfg, appliance_id, ev):
    a, k, p, c = appliance_owner(conn, appliance_id)
    level = ev["safety"]["status"]
    label = cfg["categories"][a["category"]]["label"]
    if level == "CRITICAL":
        notify(conn, cfg, c["customer_id"], "on_safety_critical", f"SAFETY WARNING — {label}",
               ev["safety"]["findings"][0]["customer_message"], appliance_id)
    elif level == "ATTENTION_REQUIRED":
        notify(conn, cfg, c["customer_id"], "on_safety_attention", f"Safety attention — {label}",
               ev["safety"]["findings"][0]["customer_message"], appliance_id)
