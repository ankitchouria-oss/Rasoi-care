"""
Kitchen Passport REST API (Flask blueprint, mounted at /api/kp).

Roles and what they can reach
-----------------------------
customer    backend JWT from /api/auth/login — only their own passport,
            kitchens, appliances, inspections, services, photos.
technician  Firebase ID token (Partner app) or a Kitchen Passport PIN
            token from /api/kp/tech/login — only kitchens where they have
            an ASSIGNED / IN_PROGRESS job, and only services they perform.
staff       Admin-app staff JWT — read access to all passports, job
            assignment. Config changes and technician PINs need the
            owner role.

Identity always comes from a verified token signature + a database
lookup — never from any client-editable metadata. Every "not yours"
answer is a 404 so ids can't be probed for existence.
"""

import base64
import binascii
import json
import os
import re
from datetime import date, datetime, timedelta, timezone
from functools import wraps

import jwt
from flask import Blueprint, Response, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

from . import engine, store

PHONE_RE = re.compile(r"^\+?[0-9]{10,15}$")
PIN_RE = re.compile(r"^[0-9]{4,8}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
MAX_PHOTO_B64 = 4_000_000
IMAGE_MAGIC = {"image/jpeg": (b"\xff\xd8\xff",), "image/png": (b"\x89PNG",), "image/webp": (b"RIFF",)}


def _today():
    """Single source of 'today' for the API (overridable in tests and via
    KP_TODAY for demos)."""
    forced = os.environ.get("KP_TODAY")
    return date.fromisoformat(forced) if forced else date.today()


def _err(status, message, **extra):
    body = {"error": message}
    body.update(extra)
    return jsonify(body), status


def _body():
    data = request.get_json(force=True, silent=True)
    return data if isinstance(data, dict) else None


def _clean_date(v):
    if v in (None, ""):
        return None
    if not isinstance(v, str) or not DATE_RE.match(v):
        raise ValueError("dates must be YYYY-MM-DD")
    date.fromisoformat(v)
    return v


def create_blueprint(hooks):
    """hooks: get_db, get_bearer_token, decode_token, decode_staff_token,
    verify_firebase_token, jwt_secret, jwt_algorithm, rate_limit_authenticated,
    auth_gate, auth_gate_record — supplied by app.py so this module shares
    the host app's auth, database and rate limiting."""
    bp = Blueprint("kitchen_passport", __name__, url_prefix="/api/kp")
    get_db = hooks["get_db"]

    # ------------------------------------------------------------ auth
    def tech_token(technician_id):
        now = datetime.now(timezone.utc)
        return jwt.encode({"sub": technician_id, "typ": "kp_tech", "iat": now, "exp": now + timedelta(days=7)},
                          hooks["jwt_secret"], algorithm=hooks["jwt_algorithm"])

    def _decode_tech(token):
        try:
            p = jwt.decode(token, hooks["jwt_secret"], algorithms=[hooks["jwt_algorithm"]])
            return p.get("sub") if p.get("typ") == "kp_tech" else None
        except jwt.PyJWTError:
            return None

    def _resolve_principal():
        token = hooks["get_bearer_token"]()
        if not token:
            return None
        conn = get_db()
        try:
            tid = _decode_tech(token)
            if tid:
                row = conn.execute("SELECT * FROM technicians WHERE id = ?", (tid,)).fetchone()
                return {"role": "technician", "id": row["id"], "row": dict(row)} if row else None
            sid = hooks["decode_staff_token"](token)
            if sid:
                row = conn.execute("SELECT * FROM staff WHERE id = ?", (sid,)).fetchone()
                if row and row["active"]:
                    return {"role": "staff", "id": row["id"], "row": dict(row), "owner": row["role"] == "owner"}
                return None
            uid = hooks["decode_token"](token)
            if uid:
                row = conn.execute("SELECT * FROM users WHERE id = ?", (uid,)).fetchone()
                return {"role": "customer", "id": row["id"], "row": row} if row else None
            claims = hooks["verify_firebase_token"](token)
            if claims:
                row = conn.execute("SELECT * FROM technicians WHERE firebase_uid = ?", (claims["uid"],)).fetchone()
                if row:
                    return {"role": "technician", "id": row["id"], "row": dict(row)}
                row = conn.execute("SELECT * FROM users WHERE firebase_uid = ?", (claims["uid"],)).fetchone()
                if row:
                    return {"role": "customer", "id": row["id"], "row": row}
                row = conn.execute("SELECT * FROM staff WHERE firebase_uid = ?", (claims["uid"],)).fetchone()
                if row and row["active"]:
                    return {"role": "staff", "id": row["id"], "row": dict(row), "owner": row["role"] == "owner"}
            return None
        finally:
            conn.close()

    def kp_auth(*roles, owner=False):
        def deco(fn):
            @wraps(fn)
            def wrapper(*a, **kw):
                p = _resolve_principal()
                if not p:
                    return _err(401, "Unauthorized")
                if p["role"] not in roles:
                    return _err(403, "Forbidden")
                if owner and not p.get("owner"):
                    return _err(403, "Owner role required")
                if hooks["rate_limit_authenticated"](f"kp:{p['role']}:{p['id']}"):
                    return _err(429, "Too Many Requests")
                g.kp = p
                return fn(*a, **kw)
            return wrapper
        return deco

    def _tech_kitchens(conn, tech_id):
        rows = conn.execute("SELECT DISTINCT kitchen_id FROM kp_technician_jobs WHERE technician_id = ? "
                            "AND status IN ('ASSIGNED','IN_PROGRESS')", (tech_id,)).fetchall()
        return {r["kitchen_id"] for r in rows}

    def can_access_kitchen(conn, kitchen_id):
        """Central authorisation check — every kitchen/appliance/
        inspection/service/photo route funnels through here."""
        p = g.kp
        if p["role"] == "staff":
            return True
        if p["role"] == "technician":
            return kitchen_id in _tech_kitchens(conn, p["id"])
        k, passport, cust = store.kitchen_owner(conn, kitchen_id)
        return bool(cust and cust["user_id"] == p["id"])

    def can_access_appliance(conn, appliance_id):
        a = conn.execute("SELECT kitchen_id FROM kp_appliances WHERE appliance_id = ?", (appliance_id,)).fetchone()
        return bool(a and can_access_kitchen(conn, a["kitchen_id"]))

    def cfg(conn):
        return store.load_config(conn)

    # ------------------------------------------------------------ public schema
    @bp.route("/config/public", methods=["GET"])
    def public_config():
        """Parameter schema for the inspection forms + thresholds for
        colouring. Contains no customer data."""
        conn = get_db()
        c = cfg(conn)
        conn.close()
        cats = {code: {"label": cat["label"], "phase": cat.get("phase", 1), "params": cat["params"],
                       "components": [{"key": x["key"], "label": x["label"], "weight": x["weight"]} for x in cat["components"]],
                       "base_service_interval_days": cat["base_service_interval_days"]}
                for code, cat in c["categories"].items()}
        return jsonify({"algorithm_version": c["algorithm_version"], "categories": cats,
                        "score_thresholds": c["score_thresholds"], "countdown_thresholds": c["countdown_thresholds"],
                        "safety_levels": c["safety"]["levels"], "priorities": engine.PRIORITY_ORDER})

    # ------------------------------------------------------------ customer
    @bp.route("/me/passport", methods=["GET"])
    @kp_auth("customer")
    def my_passport():
        conn = get_db()
        c = cfg(conn)
        cust, passport = store.ensure_customer_passport(conn, g.kp["row"], _today())
        doc = store.generate_kitchen_passport(conn, c, passport["passport_id"], _today())
        # The QR carries only an opaque reference; scanning it reveals
        # nothing without an authenticated technician session + job.
        doc["qr_payload"] = f"RCKP:{passport['passport_id']}:{passport['qr_token']}"
        doc["customer"].update({k: cust[k] for k in ("mobile_number", "whatsapp_number", "email", "address")})
        conn.close()
        return jsonify(doc)

    PROFILE_FIELDS = {"full_name": 100, "mobile_number": 15, "whatsapp_number": 15, "email": 254, "address": 500,
                      "service_location": 200, "preferred_service_time": 50, "preferred_contact_method": 20}

    @bp.route("/me/profile", methods=["PATCH"])
    @kp_auth("customer")
    def update_profile():
        data = _body()
        if data is None:
            return _err(400, "JSON object required")
        conn = get_db()
        cust, _ = store.ensure_customer_passport(conn, g.kp["row"], _today())
        sets, args, errors = [], [], {}
        for k, maxlen in PROFILE_FIELDS.items():
            if k in data:
                v = data[k]
                if v is not None and (not isinstance(v, str) or len(v) > maxlen):
                    errors[k] = f"must be text up to {maxlen} chars"
                    continue
                if k in ("mobile_number", "whatsapp_number") and v and not PHONE_RE.match(v):
                    errors[k] = "invalid phone"
                    continue
                if k == "preferred_contact_method" and v and v.upper() not in ("CALL", "SMS", "WHATSAPP", "EMAIL", "APP"):
                    errors[k] = "must be CALL/SMS/WHATSAPP/EMAIL/APP"
                    continue
                sets.append(f"{k} = ?")
                args.append(v.upper() if k == "preferred_contact_method" and v else v)
        for k in ("latitude", "longitude"):
            if k in data:
                v = data[k]
                lim = 90 if k == "latitude" else 180
                if v is not None and (not isinstance(v, (int, float)) or abs(v) > lim):
                    errors[k] = "invalid coordinate"
                    continue
                sets.append(f"{k} = ?")
                args.append(v)
        if errors:
            conn.close()
            return _err(400, "Invalid request", fields=errors)
        if sets:
            conn.execute(f"UPDATE kp_customers SET {', '.join(sets)} WHERE customer_id = ?", tuple(args) + (cust["customer_id"],))
            conn.commit()
        conn.close()
        return jsonify({"ok": True})

    KITCHEN_ENUMS = {"cooking_intensity": ("LIGHT", "MODERATE", "HEAVY"),
                     "cooking_frequency": ("RARELY", "DAILY_ONCE", "DAILY_TWICE", "DAILY_THRICE_PLUS"),
                     "kitchen_type": ("MODULAR", "SEMI_MODULAR", "TRADITIONAL", "OPEN", "COMMERCIAL")}

    def _kitchen_fields(data):
        vals, errors = {}, {}
        for k, allowed in KITCHEN_ENUMS.items():
            if k in data and data[k] is not None:
                v = str(data[k]).upper()
                if v not in allowed:
                    errors[k] = f"must be one of {', '.join(allowed)}"
                else:
                    vals[k] = v
        if "name" in data:
            if not isinstance(data["name"], str) or not 1 <= len(data["name"].strip()) <= 60:
                errors["name"] = "1-60 chars"
            else:
                vals["name"] = data["name"].strip()
        if "kitchen_age" in data and data["kitchen_age"] is not None:
            if not isinstance(data["kitchen_age"], int) or not 0 <= data["kitchen_age"] <= 100:
                errors["kitchen_age"] = "0-100"
            else:
                vals["kitchen_age"] = data["kitchen_age"]
        if "approximate_daily_cooking_hours" in data and data["approximate_daily_cooking_hours"] is not None:
            v = data["approximate_daily_cooking_hours"]
            if not isinstance(v, (int, float)) or not 0 <= v <= 24:
                errors["approximate_daily_cooking_hours"] = "0-24"
            else:
                vals["approximate_daily_cooking_hours"] = v
        if "installation_information" in data:
            vals["installation_information"] = str(data["installation_information"] or "")[:500]
        return vals, errors

    @bp.route("/me/kitchens", methods=["POST"])
    @kp_auth("customer")
    def add_kitchen():
        data = _body() or {}
        vals, errors = _kitchen_fields(data)
        if errors:
            return _err(400, "Invalid request", fields=errors)
        conn = get_db()
        _, passport = store.ensure_customer_passport(conn, g.kp["row"], _today())
        kid = store._uid("KIT")
        conn.execute("INSERT INTO kp_kitchens (kitchen_id, passport_id, name, cooking_intensity, created_at) VALUES (?,?,?,?,?)",
                     (kid, passport["passport_id"], vals.pop("name", "Kitchen"), vals.pop("cooking_intensity", "MODERATE"),
                      store._now()))
        for k, v in vals.items():
            conn.execute(f"UPDATE kp_kitchens SET {k} = ? WHERE kitchen_id = ?", (v, kid))
        conn.commit()
        conn.close()
        return jsonify({"kitchen_id": kid}), 201

    @bp.route("/me/kitchens/<kitchen_id>", methods=["PATCH"])
    @kp_auth("customer")
    def update_kitchen(kitchen_id):
        data = _body() or {}
        vals, errors = _kitchen_fields(data)
        if errors:
            return _err(400, "Invalid request", fields=errors)
        conn = get_db()
        if not can_access_kitchen(conn, kitchen_id):
            conn.close()
            return _err(404, "not found")
        for k, v in vals.items():  # k is from a fixed allow-list above
            conn.execute(f"UPDATE kp_kitchens SET {k} = ? WHERE kitchen_id = ?", (v, kitchen_id))
        conn.commit()
        conn.close()
        return jsonify({"ok": True})

    @bp.route("/kitchens/<kitchen_id>/dashboard", methods=["GET"])
    @kp_auth("customer", "technician", "staff")
    def dashboard(kitchen_id):
        conn = get_db()
        if not can_access_kitchen(conn, kitchen_id):
            conn.close()
            return _err(404, "not found")
        k = store.kitchen_owner(conn, kitchen_id)[0]
        out = store.kitchen_dashboard(conn, cfg(conn), k, _today())
        conn.close()
        return jsonify(out)

    @bp.route("/me/kitchens/<kitchen_id>/appliances", methods=["POST"])
    @kp_auth("customer", "staff")
    def register_appliance(kitchen_id):
        data = _body()
        if data is None:
            return _err(400, "JSON object required")
        conn = get_db()
        if not can_access_kitchen(conn, kitchen_id):
            conn.close()
            return _err(404, "not found")
        c = cfg(conn)
        category = str(data.get("category", "")).upper()
        errors = {}
        if category not in c["categories"]:
            errors["category"] = f"must be one of {', '.join(c['categories'])}"
        fields = {}
        for k in ("brand", "model", "serial_number", "installation_company"):
            v = data.get(k)
            if v is not None and (not isinstance(v, str) or len(v) > 100):
                errors[k] = "text up to 100 chars"
            fields[k] = v.strip() if isinstance(v, str) else None
        for k in ("purchase_date", "installation_date", "warranty_start", "warranty_end", "last_service_date"):
            try:
                fields[k] = _clean_date(data.get(k))
            except ValueError as e:
                errors[k] = str(e)
        if fields.get("last_service_date") and fields["last_service_date"] > _today().isoformat():
            errors["last_service_date"] = "cannot be in the future"
        fields["extended_warranty"] = bool(data.get("extended_warranty"))
        mi = data.get("manufacturer_interval_days")
        if mi is not None and (not isinstance(mi, int) or not 7 <= mi <= 730):
            errors["manufacturer_interval_days"] = "7-730"
        fields["manufacturer_interval_days"] = mi
        if errors:
            conn.close()
            return _err(400, "Invalid request", fields=errors)
        aid = store.create_appliance(conn, c, kitchen_id, category, fields)
        a = conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (aid,)).fetchone()
        card = store.appliance_card(conn, c, dict(a), _today())
        conn.close()
        return jsonify(card), 201

    @bp.route("/appliances/<appliance_id>", methods=["GET"])
    @kp_auth("customer", "technician", "staff")
    def appliance_detail(appliance_id):
        conn = get_db()
        if not can_access_appliance(conn, appliance_id):
            conn.close()
            return _err(404, "not found")
        c = cfg(conn)
        a = dict(conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (appliance_id,)).fetchone())
        out = store.appliance_card(conn, c, a, _today())
        out["services"] = store.list_services(conn, appliance_id)
        sc = store.current_score(conn, appliance_id)
        out["current_inspection_id"] = sc["inspection_id"] if sc else None
        out["score_components"] = sc["components"] if sc else []
        sched = store.schedule_for(conn, appliance_id)
        if sched:
            sched["factors"] = json.loads(sched.pop("factors_json") or "[]")
        out["schedule"] = sched
        out["score_history"] = [dict(r) for r in conn.execute(
            "SELECT i.inspected_at, i.phase, h.score, h.safety_status, h.repair_priority, i.inspection_id "
            "FROM kp_health_scores h JOIN kp_appliance_inspections i ON i.inspection_id = h.inspection_id "
            "WHERE h.appliance_id = ? AND h.id = (SELECT h2.id FROM kp_health_scores h2 WHERE h2.inspection_id = "
            "i.inspection_id ORDER BY h2.calculated_at DESC LIMIT 1) ORDER BY i.inspected_at, i.created_at",
            (appliance_id,)).fetchall()]
        out["ai_summary"] = store.ai_appliance_summary(conn, c, appliance_id, store=False)
        conn.close()
        return jsonify(out)

    @bp.route("/appliances/<appliance_id>/ai-summary", methods=["POST"])
    @kp_auth("customer", "technician", "staff")
    def appliance_ai(appliance_id):
        conn = get_db()
        if not can_access_appliance(conn, appliance_id):
            conn.close()
            return _err(404, "not found")
        out = store.ai_appliance_summary(conn, cfg(conn), appliance_id, store=True)
        conn.close()
        return jsonify(out)

    @bp.route("/inspections/<inspection_id>", methods=["GET"])
    @kp_auth("customer", "technician", "staff")
    def get_inspection(inspection_id):
        conn = get_db()
        ins = conn.execute("SELECT appliance_id FROM kp_appliance_inspections WHERE inspection_id = ?",
                           (inspection_id,)).fetchone()
        if not ins or not can_access_appliance(conn, ins["appliance_id"]):
            conn.close()
            return _err(404, "not found")
        out = store.inspection_detail(conn, cfg(conn), inspection_id)
        conn.close()
        return jsonify(out)

    def _service_access(conn, service_id):
        s = store.get_service(conn, service_id)
        if not s or not can_access_appliance(conn, s["appliance_id"]):
            return None
        return s

    @bp.route("/services/<service_id>", methods=["GET"])
    @kp_auth("customer", "technician", "staff")
    def get_service(service_id):
        conn = get_db()
        if not _service_access(conn, service_id):
            conn.close()
            return _err(404, "not found")
        out = store.service_detail(conn, cfg(conn), service_id)
        conn.close()
        return jsonify(out)

    @bp.route("/me/services/<service_id>/approve", methods=["POST"])
    @kp_auth("customer")
    def approve_service(service_id):
        conn = get_db()
        s = _service_access(conn, service_id)
        if not s:
            conn.close()
            return _err(404, "not found")
        if s["status"] != "AWAITING_APPROVAL":
            conn.close()
            return _err(409, f"Service is {s['status']}, not awaiting approval")
        conn.execute("UPDATE kp_service_records SET status = 'COMPLETED', customer_approved_at = ? WHERE service_id = ?",
                     (store._now(), service_id))
        conn.commit()
        conn.close()
        return jsonify({"ok": True, "status": "COMPLETED"})

    @bp.route("/kitchens/<kitchen_id>/timeline", methods=["GET"])
    @kp_auth("customer", "technician", "staff")
    def get_timeline(kitchen_id):
        conn = get_db()
        if not can_access_kitchen(conn, kitchen_id):
            conn.close()
            return _err(404, "not found")
        out = store.timeline(conn, kitchen_id)
        conn.close()
        return jsonify(out)

    @bp.route("/kitchens/<kitchen_id>/report", methods=["GET"])
    @kp_auth("customer", "technician", "staff")
    def get_report(kitchen_id):
        conn = get_db()
        if not can_access_kitchen(conn, kitchen_id):
            conn.close()
            return _err(404, "not found")
        sid = request.args.get("service_id")
        if sid:
            s = store.get_service(conn, sid)
            if not s or store.appliance_owner(conn, s["appliance_id"])[1]["kitchen_id"] != kitchen_id:
                conn.close()
                return _err(404, "not found")
        out = store.generate_health_report(conn, cfg(conn), kitchen_id, _today(), service_id=sid)
        conn.close()
        return jsonify(out)

    @bp.route("/photos/<photo_id>", methods=["GET"])
    @kp_auth("customer", "technician", "staff")
    def get_photo(photo_id):
        """Private photos are only ever served through this authorised
        route (bearer token required) — there is no public URL."""
        conn = get_db()
        ph = conn.execute("SELECT * FROM kp_photos WHERE photo_id = ?", (photo_id,)).fetchone()
        if not ph or not can_access_appliance(conn, ph["appliance_id"]):
            conn.close()
            return _err(404, "not found")
        conn.close()
        resp = Response(base64.b64decode(ph["data_b64"]), mimetype=ph["mime_type"])
        resp.headers["Cache-Control"] = "private, no-store"
        return resp

    @bp.route("/me/notifications", methods=["GET"])
    @kp_auth("customer")
    def my_notifications():
        conn = get_db()
        cust = store.get_customer_by_user(conn, g.kp["id"])
        rows = [] if not cust else conn.execute(
            "SELECT id, kind, channel, title, body, appliance_id, status, created_at FROM kp_notifications "
            "WHERE customer_id = ? AND channel = 'app' ORDER BY created_at DESC LIMIT 50", (cust["customer_id"],)).fetchall()
        conn.close()
        return jsonify([dict(r) for r in rows])

    # ------------------------------------------------------------ technician
    @bp.route("/tech/login", methods=["POST"])
    def tech_login():
        data = _body() or {}
        phone, pin = str(data.get("phone", "")), str(data.get("pin", ""))
        if not PHONE_RE.match(phone) or not PIN_RE.match(pin):
            return _err(400, "phone and 4-8 digit pin required")
        gated = hooks["auth_gate"]("kp_tech:" + phone)
        if gated:
            return gated
        conn = get_db()
        cred = conn.execute("SELECT * FROM kp_technician_credentials WHERE phone = ?", (phone,)).fetchone()
        tech = conn.execute("SELECT id, name FROM technicians WHERE id = ?", (cred["technician_id"],)).fetchone() if cred else None
        conn.close()
        if not cred or not tech or not check_password_hash(cred["pin_hash"], pin):
            hooks["auth_gate_record"]("kp_tech:" + phone, False)
            return _err(401, "Invalid phone or PIN")
        hooks["auth_gate_record"]("kp_tech:" + phone, True)
        return jsonify({"token": tech_token(tech["id"]), "technician": {"id": tech["id"], "name": tech["name"]}})

    @bp.route("/tech/jobs", methods=["GET"])
    @kp_auth("technician")
    def tech_jobs():
        day = request.args.get("date") or _today().isoformat()
        if not DATE_RE.match(day):
            return _err(400, "date must be YYYY-MM-DD")
        conn = get_db()
        c = cfg(conn)
        rows = conn.execute(
            "SELECT * FROM kp_technician_jobs WHERE technician_id = ? AND (scheduled_date = ? OR "
            "(status IN ('ASSIGNED','IN_PROGRESS') AND scheduled_date <= ?)) ORDER BY scheduled_date, created_at",
            (g.kp["id"], day, day)).fetchall()
        jobs = []
        for j in rows:
            k, p, cust = store.kitchen_owner(conn, j["kitchen_id"])
            active = j["status"] in ("ASSIGNED", "IN_PROGRESS")
            cards = store.list_appliance_cards(conn, c, j["kitchen_id"], _today()) if active else []
            if j["appliance_id"]:
                cards = [x for x in cards if x["appliance_id"] == j["appliance_id"]]
            jobs.append({
                "job_id": j["job_id"], "status": j["status"], "scheduled_date": j["scheduled_date"],
                "job_type": j["job_type"], "notes": j["notes"], "kitchen_id": j["kitchen_id"],
                "passport_id": p["passport_id"],
                "customer": {"full_name": cust["full_name"],
                             "address": cust["address"] if active else None,
                             "service_location": cust["service_location"],
                             "mobile_number": cust["mobile_number"] if active else None},
                "appliances": [{"appliance_id": x["appliance_id"], "label": x["label"], "brand": x["brand"],
                                "indicators": x["indicators"]} for x in cards],
            })
        conn.close()
        return jsonify(jobs)

    @bp.route("/tech/scan", methods=["POST"])
    @kp_auth("technician", "staff")
    def tech_scan():
        """QR payload is RCKP:<passport_id>:<qr_token> (or a typed
        passport id). A technician only gets the passport if they have an
        active job at one of its kitchens."""
        data = _body() or {}
        code = str(data.get("code", "")).strip()
        m = re.match(r"^RCKP:(RC-KP-\d{8}):([A-Za-z0-9_-]+)$", code)
        pid = m.group(1) if m else code.upper()
        if not re.match(r"^RC-KP-\d{8}$", pid):
            return _err(400, "Not a Kitchen Passport code")
        conn = get_db()
        p = conn.execute("SELECT * FROM kp_kitchen_passports WHERE passport_id = ?", (pid,)).fetchone()
        if not p or (m and not _consteq(p["qr_token"], m.group(2))):
            conn.close()
            return _err(404, "not found")
        kitchens = store.kitchens_for_passport(conn, pid)
        if g.kp["role"] == "technician":
            allowed = _tech_kitchens(conn, g.kp["id"])
            if not any(k["kitchen_id"] in allowed for k in kitchens):
                conn.close()
                return _err(404, "not found")
        doc = store.generate_kitchen_passport(conn, cfg(conn), pid, _today(), include_contact=True)
        if g.kp["role"] == "technician":
            allowed = _tech_kitchens(conn, g.kp["id"])
            doc["kitchens"] = [k for k in doc["kitchens"] if k["kitchen"]["kitchen_id"] in allowed]
            doc["customer"].pop("email", None)
        conn.close()
        return jsonify(doc)

    def _consteq(a, b):
        import hmac
        return hmac.compare_digest(str(a), str(b))

    def _tech_job(conn, job_id):
        j = conn.execute("SELECT * FROM kp_technician_jobs WHERE job_id = ?", (job_id,)).fetchone()
        if not j or j["technician_id"] != g.kp["id"] or j["status"] not in ("ASSIGNED", "IN_PROGRESS"):
            return None
        return dict(j)

    @bp.route("/tech/jobs/<job_id>/services", methods=["POST"])
    @kp_auth("technician")
    def tech_start_service(job_id):
        data = _body() or {}
        conn = get_db()
        j = _tech_job(conn, job_id)
        if not j:
            conn.close()
            return _err(404, "not found")
        aid = data.get("appliance_id")
        a = conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (aid,)).fetchone()
        if not a or a["kitchen_id"] != j["kitchen_id"] or (j["appliance_id"] and j["appliance_id"] != aid):
            conn.close()
            return _err(404, "appliance not found for this job")
        stype = str(data.get("service_type", "SERVICE")).upper()
        if stype not in ("SERVICE", "REPAIR", "INSPECTION", "INSTALLATION"):
            conn.close()
            return _err(400, "service_type must be SERVICE/REPAIR/INSPECTION/INSTALLATION")
        existing = conn.execute("SELECT service_id FROM kp_service_records WHERE job_id = ? AND appliance_id = ? "
                                "AND status = 'IN_PROGRESS'", (job_id, aid)).fetchone()
        sid = existing["service_id"] if existing else store.start_service(conn, dict(a), job_id, g.kp["id"], stype, _today())
        conn.close()
        return jsonify({"service_id": sid}), 201

    def _tech_service(conn, service_id):
        s = store.get_service(conn, service_id)
        if not s or s["technician_id"] != g.kp["id"] or s["status"] != "IN_PROGRESS":
            return None
        if s["job_id"] and not _tech_job(conn, s["job_id"]):
            return None
        return s

    def _findings(data):
        tf = data.get("technician_findings") or []
        if not isinstance(tf, list) or len(tf) > 20:
            raise engine.InspectionError({"technician_findings": "must be a list (max 20)"})
        out = []
        for f in tf:
            if not isinstance(f, dict) or str(f.get("level", "")).upper() not in engine.SAFETY_ORDER:
                raise engine.InspectionError({"technician_findings": "each needs level + description"})
            out.append({"level": str(f["level"]).upper(), "description": str(f.get("description", ""))[:300]})
        return out

    @bp.route("/tech/evaluate", methods=["POST"])
    @kp_auth("technician", "staff")
    def tech_evaluate():
        """Live preview of what the engines will calculate — nothing is
        saved. The UI uses it so the technician sees the result before
        submitting; the saved result is recomputed server-side."""
        data = _body() or {}
        conn = get_db()
        c = cfg(conn)
        a = conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (data.get("appliance_id"),)).fetchone()
        if not a or not can_access_appliance(conn, a["appliance_id"]):
            conn.close()
            return _err(404, "not found")
        a = dict(a)
        kitchen = store.kitchen_owner(conn, a["kitchen_id"])[0]
        today = _today()
        try:
            ev = engine.evaluate_inspection(
                c, a["category"], data.get("values") or {}, history=store.appliance_history(conn, a, today),
                kitchen=kitchen, appliance=dict(a, appliance_age_years=store.appliance_age_years(a, today)),
                technician_findings=_findings(data), last_service_date=today, today=today)
        except engine.InspectionError as e:
            conn.close()
            return _err(400, "Invalid inspection data", fields=e.fields)
        conn.close()
        return jsonify(ev)

    @bp.route("/tech/services/<service_id>/inspections", methods=["POST"])
    @kp_auth("technician")
    def tech_inspection(service_id):
        data = _body()
        if data is None:
            return _err(400, "JSON object required")
        phase = str(data.get("phase", "")).upper()
        if phase not in ("BEFORE", "AFTER"):
            return _err(400, "phase must be BEFORE or AFTER")
        conn = get_db()
        s = _tech_service(conn, service_id)
        if not s:
            conn.close()
            return _err(404, "not found")
        if phase == "AFTER" and not s["before_inspection_id"]:
            conn.close()
            return _err(409, "Record the BEFORE inspection first")
        c = cfg(conn)
        a = dict(conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (s["appliance_id"],)).fetchone())
        try:
            iid, ev = store.record_inspection(
                conn, c, a, data.get("values") or {}, phase=phase, service_id=service_id, technician_id=g.kp["id"],
                technician_findings=_findings(data), observations=str(data.get("observations") or ""), today=_today())
        except engine.InspectionError as e:
            conn.close()
            return _err(400, "Invalid inspection data", fields=e.fields)
        store.attach_inspection_to_service(conn, service_id, phase, iid, ev["health"]["score"])
        if ev["safety"]["status"] in ("CRITICAL", "ATTENTION_REQUIRED"):
            store.notify_safety(conn, c, a["appliance_id"], ev)
        conn.close()
        return jsonify({"inspection_id": iid, "evaluation": ev}), 201

    @bp.route("/tech/services/<service_id>/photos", methods=["POST"])
    @kp_auth("technician")
    def tech_photo(service_id):
        data = _body() or {}
        kind = str(data.get("kind", "")).upper()
        mime = str(data.get("mime_type", "image/jpeg")).lower()
        b64 = data.get("dataBase64")
        if kind not in ("BEFORE", "AFTER", "ERROR_DISPLAY", "PART", "OTHER"):
            return _err(400, "kind must be BEFORE/AFTER/ERROR_DISPLAY/PART/OTHER")
        if mime not in IMAGE_MAGIC:
            return _err(400, "mime_type must be image/jpeg, image/png or image/webp")
        if not isinstance(b64, str) or not 0 < len(b64) <= MAX_PHOTO_B64:
            return _err(400, f"dataBase64 required (max {MAX_PHOTO_B64} chars)")
        try:
            raw = base64.b64decode(b64, validate=True)
        except (binascii.Error, ValueError):
            return _err(400, "dataBase64 is not valid base64")
        if not raw.startswith(IMAGE_MAGIC[mime]):
            return _err(400, "file content does not match mime_type")
        conn = get_db()
        s = _tech_service(conn, service_id)
        if not s:
            conn.close()
            return _err(404, "not found")
        insp = s["before_inspection_id"] if kind == "BEFORE" else (s["after_inspection_id"] if kind == "AFTER" else None)
        pid = store.add_photo(conn, s["appliance_id"], service_id, kind, mime, b64,
                              str(data.get("caption") or "")[:200] or None, g.kp["id"], inspection_id=insp)
        conn.close()
        return jsonify({"photo_id": pid}), 201

    @bp.route("/tech/services/<service_id>/complete", methods=["POST"])
    @kp_auth("technician")
    def tech_complete(service_id):
        data = _body() or {}
        conn = get_db()
        s = _tech_service(conn, service_id)
        if not s:
            conn.close()
            return _err(404, "not found")
        if not s["after_inspection_id"]:
            conn.close()
            return _err(409, "Record the AFTER inspection before completing")
        parts = data.get("parts") or []
        if not isinstance(parts, list) or len(parts) > 30:
            conn.close()
            return _err(400, "parts must be a list (max 30)")
        for p in parts:
            if not isinstance(p, dict) or not str(p.get("part_name", "")).strip():
                conn.close()
                return _err(400, "each part needs part_name")
            for k in ("quantity", "unit_price", "warranty_days"):
                if p.get(k) is not None and (not isinstance(p[k], int) or p[k] < 0 or p[k] > 10_000_000):
                    conn.close()
                    return _err(400, f"part {k} must be a non-negative integer")
        labour = data.get("labour_amount") or 0
        if not isinstance(labour, int) or labour < 0:
            conn.close()
            return _err(400, "labour_amount must be a non-negative integer")
        snap = store.complete_service(conn, cfg(conn), s, work_performed=str(data.get("work_performed") or ""),
                                      observations=str(data.get("observations") or ""), parts=parts,
                                      labour_amount=labour, today=_today())
        out = store.service_detail(conn, cfg(conn), service_id)
        out["kitchen_health"] = snap
        conn.close()
        return jsonify(out)

    # ------------------------------------------------------------ admin / staff
    @bp.route("/admin/config", methods=["GET"])
    @kp_auth("staff")
    def admin_config():
        conn = get_db()
        c = cfg(conn)
        hist = [dict(r) for r in conn.execute(
            "SELECT algorithm_version, section, updated_by, created_at FROM kp_config_history "
            "ORDER BY created_at DESC LIMIT 30").fetchall()]
        conn.close()
        return jsonify({"config": c, "history": hist})

    @bp.route("/admin/config/<section>", methods=["PUT", "DELETE"])
    @kp_auth("staff", owner=True)
    def admin_config_save(section):
        conn = get_db()
        try:
            if request.method == "DELETE":
                c = store.reset_config_section(conn, section, g.kp["id"])
            else:
                data = _body()
                if data is None or "value" not in data:
                    conn.close()
                    return _err(400, "body must be {\"value\": ...}")
                c = store.save_config_section(conn, section, data["value"], g.kp["id"])
        except store.ConfigError as e:
            conn.close()
            return _err(400, str(e))
        conn.close()
        return jsonify({"algorithm_version": c["algorithm_version"]})

    @bp.route("/admin/passports", methods=["GET"])
    @kp_auth("staff")
    def admin_passports():
        q = (request.args.get("q") or "").strip()[:60]
        conn = get_db()
        rows = conn.execute(
            "SELECT p.passport_id, c.full_name, c.mobile_number, k.kitchen_id, k.name AS kitchen_name, "
            "k.overall_health_score, k.overall_score_status FROM kp_kitchen_passports p "
            "JOIN kp_customers c ON c.customer_id = p.customer_id JOIN kp_kitchens k ON k.passport_id = p.passport_id "
            "WHERE (? = '' OR p.passport_id LIKE ? OR LOWER(c.full_name) LIKE ?) ORDER BY p.passport_id LIMIT 100",
            (q, f"%{q.upper()}%", f"%{q.lower()}%")).fetchall()
        conn.close()
        return jsonify([dict(r) for r in rows])

    @bp.route("/admin/passports/<passport_id>", methods=["GET"])
    @kp_auth("staff")
    def admin_passport(passport_id):
        conn = get_db()
        doc = store.generate_kitchen_passport(conn, cfg(conn), passport_id, _today())
        conn.close()
        return jsonify(doc) if doc else _err(404, "not found")

    @bp.route("/admin/technicians", methods=["GET"])
    @kp_auth("staff")
    def admin_technicians():
        conn = get_db()
        rows = conn.execute("SELECT t.id, t.name, t.category, t.area, c.phone AS kp_login_phone FROM technicians t "
                            "LEFT JOIN kp_technician_credentials c ON c.technician_id = t.id ORDER BY t.name").fetchall()
        conn.close()
        return jsonify([dict(r) for r in rows])

    @bp.route("/admin/technicians/<tech_id>/pin", methods=["POST"])
    @kp_auth("staff", owner=True)
    def admin_set_pin(tech_id):
        data = _body() or {}
        phone, pin = str(data.get("phone", "")), str(data.get("pin", ""))
        if not PHONE_RE.match(phone) or not PIN_RE.match(pin):
            return _err(400, "phone and 4-8 digit pin required")
        conn = get_db()
        if not conn.execute("SELECT id FROM technicians WHERE id = ?", (tech_id,)).fetchone():
            conn.close()
            return _err(404, "not found")
        clash = conn.execute("SELECT technician_id FROM kp_technician_credentials WHERE phone = ?", (phone,)).fetchone()
        if clash and clash["technician_id"] != tech_id:
            conn.close()
            return _err(409, "phone already used by another technician")
        conn.execute("DELETE FROM kp_technician_credentials WHERE technician_id = ?", (tech_id,))
        conn.execute("INSERT INTO kp_technician_credentials (technician_id, phone, pin_hash, created_at) VALUES (?,?,?,?)",
                     (tech_id, phone, generate_password_hash(pin), store._now()))
        conn.commit()
        conn.close()
        return jsonify({"ok": True})

    @bp.route("/admin/jobs", methods=["GET", "POST"])
    @kp_auth("staff")
    def admin_jobs():
        conn = get_db()
        if request.method == "GET":
            rows = conn.execute(
                "SELECT j.*, t.name AS technician_name, c.full_name AS customer_name FROM kp_technician_jobs j "
                "JOIN technicians t ON t.id = j.technician_id JOIN kp_kitchens k ON k.kitchen_id = j.kitchen_id "
                "JOIN kp_kitchen_passports p ON p.passport_id = k.passport_id "
                "JOIN kp_customers c ON c.customer_id = p.customer_id ORDER BY j.scheduled_date DESC LIMIT 100").fetchall()
            conn.close()
            return jsonify([dict(r) for r in rows])
        data = _body() or {}
        errors = {}
        k = conn.execute("SELECT kitchen_id FROM kp_kitchens WHERE kitchen_id = ?", (data.get("kitchen_id"),)).fetchone()
        if not k:
            errors["kitchen_id"] = "unknown kitchen"
        if not conn.execute("SELECT id FROM technicians WHERE id = ?", (data.get("technician_id"),)).fetchone():
            errors["technician_id"] = "unknown technician"
        aid = data.get("appliance_id")
        if aid:
            a = conn.execute("SELECT kitchen_id FROM kp_appliances WHERE appliance_id = ?", (aid,)).fetchone()
            if not a or (k and a["kitchen_id"] != k["kitchen_id"]):
                errors["appliance_id"] = "not in this kitchen"
        try:
            day = _clean_date(data.get("scheduled_date")) or _today().isoformat()
        except ValueError as e:
            errors["scheduled_date"] = str(e)
            day = None
        jtype = str(data.get("job_type", "SERVICE")).upper()
        if jtype not in ("SERVICE", "REPAIR", "INSPECTION", "INSTALLATION"):
            errors["job_type"] = "SERVICE/REPAIR/INSPECTION/INSTALLATION"
        if errors:
            conn.close()
            return _err(400, "Invalid request", fields=errors)
        jid = f"KPJ-{store.next_seq(conn, 'job'):06d}"
        conn.execute("INSERT INTO kp_technician_jobs (job_id, kitchen_id, technician_id, appliance_id, scheduled_date, "
                     "job_type, notes, created_by, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
                     (jid, data["kitchen_id"], data["technician_id"], aid, day, jtype,
                      str(data.get("notes") or "")[:500] or None, g.kp["id"], store._now()))
        conn.commit()
        conn.close()
        return jsonify({"job_id": jid}), 201

    @bp.route("/admin/inspections/<inspection_id>/rescore", methods=["POST"])
    @kp_auth("staff", owner=True)
    def admin_rescore(inspection_id):
        conn = get_db()
        ev = store.rescore_inspection(conn, cfg(conn), inspection_id)
        conn.close()
        return jsonify(ev) if ev else _err(404, "not found")

    return bp
