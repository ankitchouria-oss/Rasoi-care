"""
RasoiCare backend — real Flask REST API.

This is the server all three apps (Customer, Technician, Admin) call
over HTTP. Run it locally with `python3 app.py`, or deploy it (see
README.md) to get a public URL so it can be reached from real,
separate devices.
"""

import os
import json
import re
from datetime import datetime, timedelta, timezone
from functools import wraps

import jwt
from flask import Flask, request, jsonify, send_from_directory
from werkzeug.security import generate_password_hash, check_password_hash
from database import get_db, init_db, next_id, now, new_uuid_id

app = Flask(__name__)
FRONTEND_DIR = os.path.dirname(os.path.abspath(__file__))

JWT_SECRET = os.environ.get("JWT_SECRET", "rasoicare-dev-secret-change-in-prod")
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_DAYS = 7
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


@app.route("/")
def index():
    return send_from_directory(FRONTEND_DIR, "index.html")


@app.route("/customer")
def customer_app():
    return send_from_directory(FRONTEND_DIR, "customer.html")


@app.route("/technician")
def technician_app():
    return send_from_directory(FRONTEND_DIR, "technician.html")


@app.route("/admin")
def admin_app():
    return send_from_directory(FRONTEND_DIR, "admin.html")


@app.route("/smiler")
def smiler_app():
    return send_from_directory(FRONTEND_DIR, "smiler.html")


@app.route("/homeservices")
def homeservices_app():
    return send_from_directory(FRONTEND_DIR, "homeservices.html")

STATUS_ORDER = ["Requested", "Accepted", "On the way", "In Progress", "Completed"]


# ---------------------------------------------------------------- CORS
# Hand-rolled instead of pulling in flask-cors, so this has zero extra
# dependencies to install at deploy time. Lets any frontend origin
# (the customer app, technician app, admin dashboard — each opened as
# its own file/origin) call this API from the browser.
@app.after_request
def add_cors_headers(resp):
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return resp


@app.route("/api/<path:_any>", methods=["OPTIONS"])
def cors_preflight(_any):
    return "", 204


# ---------------------------------------------------------------- helpers
def booking_row_to_dict(row):
    keys = row.keys()
    return {
        "id": row["id"],
        "category": row["category"],
        "service": row["service"],
        "price": row["price"],
        "technicianId": row["technician_id"],
        "customerName": row["customer_name"],
        "status": row["status"],
        "bachatSlot": row["bachat_slot"],
        "ratings": (
            {"service": row["service_rating"], "tech": row["tech_rating"]}
            if row["service_rating"] is not None
            else None
        ),
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
        "user_id": row["user_id"] if "user_id" in keys else None,
        "service_id": row["service_id"] if "service_id" in keys else None,
        "total_amount": row["total_amount"] if "total_amount" in keys else row["price"],
        "area": row["area"] if "area" in keys else None,
    }


def complaint_row_to_dict(row):
    return {
        "id": row["id"],
        "bookingId": row["booking_id"],
        "text": row["text"],
        "status": row["status"],
        "response": row["response"],
        "createdAt": row["created_at"],
    }


def technician_row_to_dict(row):
    keys = row.keys()
    return {
        "id": row["id"],
        "name": row["name"],
        "category": row["category"],
        "area": row["area"] if "area" in keys else "",
        "verified": bool(row["verified"]) if "verified" in keys else True,
        "online": bool(row["online"]),
        "rating": round(row["rating"], 1),
        "ratingCount": row["rating_count"],
        "jobsCompleted": row["jobs_completed"],
    }


def user_row_to_dict(row):
    return {
        "id": row["id"],
        "email": row["email"],
        "name": row["name"],
        "phone": row["phone"],
        "created_at": row["created_at"],
    }


def appliance_row_to_dict(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "category": row["category"],
        "mono": row["mono"],
    }


def service_row_to_dict(row):
    return {
        "id": row["id"],
        "appliance_id": row["appliance_id"],
        "appliance_name": row["appliance_name"],
        "category": row["category"],
        "name": row["name"],
        "price": row["price"],
        "quick_fix": bool(row["quick_fix"]),
    }


def staff_row_to_dict(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "phone": row["phone"],
        "role": row["role"],
        "active": bool(row["active"]),
        "createdAt": row["created_at"],
    }


def inventory_row_to_dict(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "sku": row["sku"],
        "category": row["category"],
        "quantity": row["quantity"],
        "reorderLevel": row["reorder_level"],
        "lowStock": row["quantity"] < row["reorder_level"],
        "updatedAt": row["updated_at"],
    }


def amc_plan_row_to_dict(row):
    return {
        "id": row["id"],
        "name": row["name"],
        "price": row["price"],
        "duration_months": row["duration_months"],
        "benefits": json.loads(row["benefits"]),
    }


# ---------------------------------------------------------------- auth
def generate_token(user_id):
    payload = {
        "sub": user_id,
        "exp": datetime.now(timezone.utc) + timedelta(days=JWT_EXPIRY_DAYS),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token):
    """Returns the user id from a valid token, or None if missing/expired/invalid."""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload.get("sub")
    except jwt.PyJWTError:
        return None


def get_bearer_token():
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return header[len("Bearer "):].strip()


def get_current_user_optional():
    """Returns the user row for a valid Bearer token, or None (does not
    reject the request) — used by endpoints that behave differently for
    authenticated vs anonymous callers without requiring auth."""
    token = get_bearer_token()
    if not token:
        return None
    user_id = decode_token(token)
    if not user_id:
        return None
    conn = get_db()
    row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    conn.close()
    return row


def require_auth(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = get_bearer_token()
        if not token:
            return jsonify({"error": "Unauthorized", "message": "Missing bearer token"}), 401
        user_id = decode_token(token)
        if not user_id:
            return jsonify({"error": "Unauthorized", "message": "Invalid or expired token"}), 401
        conn = get_db()
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        conn.close()
        if not row:
            return jsonify({"error": "Unauthorized", "message": "User no longer exists"}), 401
        request.user = row
        return fn(*args, **kwargs)
    return wrapper


def generate_staff_token(staff_id):
    payload = {
        "sub": staff_id,
        "typ": "staff",
        "exp": datetime.now(timezone.utc) + timedelta(days=JWT_EXPIRY_DAYS),
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_staff_token(token):
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        if payload.get("typ") != "staff":
            return None
        return payload.get("sub")
    except jwt.PyJWTError:
        return None


def require_staff_auth(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        token = get_bearer_token()
        if not token:
            return jsonify({"error": "Unauthorized", "message": "Missing bearer token"}), 401
        staff_id = decode_staff_token(token)
        if not staff_id:
            return jsonify({"error": "Unauthorized", "message": "Invalid or expired token"}), 401
        conn = get_db()
        row = conn.execute("SELECT * FROM staff WHERE id = ?", (staff_id,)).fetchone()
        conn.close()
        if not row or not row["active"]:
            return jsonify({"error": "Unauthorized", "message": "Staff account not found or inactive"}), 401
        request.staff = row
        return fn(*args, **kwargs)
    return wrapper


def require_owner(fn):
    @wraps(fn)
    @require_staff_auth
    def wrapper(*args, **kwargs):
        if request.staff["role"] != "owner":
            return jsonify({"error": "Forbidden", "message": "Owner role required"}), 403
        return fn(*args, **kwargs)
    return wrapper


@app.route("/api/staff/login", methods=["POST"])
def staff_login():
    data = request.get_json(force=True, silent=True) or {}
    phone = (data.get("phone") or "").strip()
    pin = data.get("pin") or ""
    conn = get_db()
    row = conn.execute("SELECT * FROM staff WHERE phone = ?", (phone,)).fetchone()
    conn.close()
    if not row or not row["active"] or not check_password_hash(row["pin_hash"], pin):
        return jsonify({"error": "Invalid phone or PIN"}), 401
    return jsonify({"token": generate_staff_token(row["id"]), "staff": staff_row_to_dict(row)})


@app.route("/api/staff/me", methods=["GET"])
@require_staff_auth
def staff_me():
    return jsonify(staff_row_to_dict(request.staff))


@app.route("/api/staff", methods=["GET"])
@require_staff_auth
def list_staff():
    conn = get_db()
    rows = conn.execute("SELECT * FROM staff ORDER BY name").fetchall()
    conn.close()
    return jsonify([staff_row_to_dict(r) for r in rows])


@app.route("/api/staff", methods=["POST"])
@require_owner
def invite_staff():
    data = request.get_json(force=True, silent=True) or {}
    name = (data.get("name") or "").strip()
    phone = (data.get("phone") or "").strip()
    pin = data.get("pin") or ""
    role = data.get("role") or "staff"
    if not name or not phone or len(pin) < 4:
        return jsonify({"error": "name, phone, and a pin of at least 4 digits are required"}), 400
    if role not in ("owner", "staff"):
        return jsonify({"error": "role must be 'owner' or 'staff'"}), 400

    conn = get_db()
    existing = conn.execute("SELECT id FROM staff WHERE phone = ?", (phone,)).fetchone()
    if existing:
        conn.close()
        return jsonify({"error": "A staff account with this phone already exists"}), 409
    staff_id = new_uuid_id("STF")
    conn.execute(
        "INSERT INTO staff (id, name, phone, pin_hash, role, active, created_at) VALUES (?,?,?,?,?,1,?)",
        (staff_id, name, phone, generate_password_hash(pin), role, now()),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM staff WHERE id = ?", (staff_id,)).fetchone()
    conn.close()
    return jsonify(staff_row_to_dict(row)), 201


@app.route("/api/staff/<staff_id>", methods=["PATCH"])
@require_owner
def update_staff(staff_id):
    data = request.get_json(force=True, silent=True) or {}
    conn = get_db()
    row = conn.execute("SELECT * FROM staff WHERE id = ?", (staff_id,)).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "not found"}), 404
    role = data.get("role", row["role"])
    active = int(data["active"]) if "active" in data else row["active"]
    if role not in ("owner", "staff"):
        conn.close()
        return jsonify({"error": "role must be 'owner' or 'staff'"}), 400
    conn.execute("UPDATE staff SET role = ?, active = ? WHERE id = ?", (role, active, staff_id))
    conn.commit()
    row = conn.execute("SELECT * FROM staff WHERE id = ?", (staff_id,)).fetchone()
    conn.close()
    return jsonify(staff_row_to_dict(row))


@app.route("/api/auth/register", methods=["POST"])
def auth_register():
    data = request.get_json(force=True, silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    name = (data.get("name") or "").strip()
    phone = data.get("phone")

    if not email or not EMAIL_RE.match(email):
        return jsonify({"error": "A valid email is required"}), 400
    if len(password) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400
    if not name:
        return jsonify({"error": "Name is required"}), 400

    conn = get_db()
    existing = conn.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
    if existing:
        conn.close()
        return jsonify({"error": "Email already registered"}), 409

    user_id = new_uuid_id("USR")
    conn.execute(
        "INSERT INTO users (id, email, password_hash, name, phone, created_at) VALUES (?,?,?,?,?,?)",
        (user_id, email, generate_password_hash(password), name, phone, now()),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    conn.close()
    return jsonify({"token": generate_token(user_id), "user": user_row_to_dict(row)}), 201


@app.route("/api/auth/login", methods=["POST"])
def auth_login():
    data = request.get_json(force=True, silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""

    conn = get_db()
    row = conn.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    conn.close()
    if not row or not check_password_hash(row["password_hash"], password):
        return jsonify({"error": "Invalid email or password"}), 401

    return jsonify({"token": generate_token(row["id"]), "user": user_row_to_dict(row)})


@app.route("/api/auth/me", methods=["GET"])
@require_auth
def auth_me():
    return jsonify(user_row_to_dict(request.user))


# ---------------------------------------------------------------- health
@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"ok": True, "service": "rasoicare-backend"})


# ---------------------------------------------------------------- appliances
@app.route("/api/appliances", methods=["GET"])
def list_appliances():
    category = request.args.get("category")
    conn = get_db()
    if category:
        rows = conn.execute(
            "SELECT * FROM appliances WHERE category = ? ORDER BY name", (category,)
        ).fetchall()
    else:
        rows = conn.execute("SELECT * FROM appliances ORDER BY name").fetchall()
    conn.close()
    return jsonify([appliance_row_to_dict(r) for r in rows])


@app.route("/api/appliances/<appliance_id>", methods=["GET"])
def get_appliance(appliance_id):
    conn = get_db()
    row = conn.execute("SELECT * FROM appliances WHERE id = ?", (appliance_id,)).fetchone()
    conn.close()
    if not row:
        return jsonify({"error": "Appliance not found"}), 404
    return jsonify(appliance_row_to_dict(row))


# ---------------------------------------------------------------- services
SERVICE_SELECT = (
    "SELECT services.*, appliances.name AS appliance_name FROM services "
    "JOIN appliances ON appliances.id = services.appliance_id"
)


@app.route("/api/services", methods=["GET"])
def list_services():
    category = request.args.get("category")
    quick_fix_param = request.args.get("quick_fix")

    clauses, params = [], []
    if category:
        clauses.append("services.category = ?")
        params.append(category)
    if quick_fix_param is not None:
        clauses.append("services.quick_fix = ?")
        params.append(1 if quick_fix_param.lower() in ("true", "1", "yes") else 0)

    sql = SERVICE_SELECT
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY services.name"

    conn = get_db()
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    return jsonify([service_row_to_dict(r) for r in rows])


@app.route("/api/services/<service_id>", methods=["GET"])
def get_service(service_id):
    conn = get_db()
    row = conn.execute(SERVICE_SELECT + " WHERE services.id = ?", (service_id,)).fetchone()
    conn.close()
    if not row:
        return jsonify({"error": "Service not found"}), 404
    return jsonify(service_row_to_dict(row))


# ---------------------------------------------------------------- amc
@app.route("/api/amc/plans", methods=["GET"])
def list_amc_plans():
    conn = get_db()
    rows = conn.execute("SELECT * FROM amc_plans ORDER BY price").fetchall()
    conn.close()
    return jsonify([amc_plan_row_to_dict(r) for r in rows])


@app.route("/api/amc/my-subscription", methods=["GET"])
@require_auth
def my_amc_subscription():
    conn = get_db()
    row = conn.execute(
        "SELECT * FROM amc_subscriptions WHERE user_id = ? ORDER BY created_at DESC LIMIT 1",
        (request.user["id"],),
    ).fetchone()
    conn.close()
    if not row:
        return jsonify({"subscribed": False, "subscription": None})
    conn = get_db()
    plan_row = conn.execute("SELECT * FROM amc_plans WHERE id = ?", (row["plan_id"],)).fetchone()
    conn.close()
    return jsonify({
        "subscribed": True,
        "subscription": {
            "id": row["id"],
            "plan": amc_plan_row_to_dict(plan_row) if plan_row else None,
            "status": row["status"],
            "start_date": row["start_date"],
            "end_date": row["end_date"],
        },
    })


@app.route("/api/amc/subscribe", methods=["POST"])
@require_auth
def subscribe_amc():
    data = request.get_json(force=True, silent=True) or {}
    plan_id = data.get("plan_id")
    conn = get_db()
    plan_row = conn.execute("SELECT * FROM amc_plans WHERE id = ?", (plan_id,)).fetchone()
    if not plan_row:
        conn.close()
        return jsonify({"error": "Unknown plan_id"}), 400

    sub_id = new_uuid_id("AMCSUB")
    start = datetime.now(timezone.utc).date()
    end = start + timedelta(days=30 * plan_row["duration_months"])
    conn.execute(
        "INSERT INTO amc_subscriptions (id, user_id, plan_id, status, start_date, end_date, created_at) "
        "VALUES (?,?,?,?,?,?,?)",
        (sub_id, request.user["id"], plan_id, "Active", start.isoformat(), end.isoformat(), now()),
    )
    conn.commit()
    conn.close()
    return jsonify({"id": sub_id, "plan": amc_plan_row_to_dict(plan_row), "status": "Active",
                     "start_date": start.isoformat(), "end_date": end.isoformat()}), 201


# ---------------------------------------------------------------- kitchen health score
def appliance_health_row_to_dict(row):
    return {
        "id": row["id"],
        "appliance_id": row["appliance_id"],
        "appliance_name": row["appliance_name"],
        "metric_name": row["metric_name"],
        "value_pct": row["value_pct"],
        "status_label": row["status_label"],
        "updated_at": row["updated_at"],
    }


HEALTH_SELECT = (
    "SELECT appliance_health.*, appliances.name AS appliance_name FROM appliance_health "
    "JOIN appliances ON appliances.id = appliance_health.appliance_id"
)


@app.route("/api/health-score", methods=["GET"])
@require_auth
def get_health_score():
    conn = get_db()
    rows = conn.execute(
        HEALTH_SELECT + " WHERE appliance_health.user_id = ? ORDER BY appliance_health.updated_at DESC",
        (request.user["id"],),
    ).fetchall()
    conn.close()
    return jsonify([appliance_health_row_to_dict(r) for r in rows])


@app.route("/api/bookings/<booking_id>/health-update", methods=["POST"])
def update_booking_health(booking_id):
    """Called by the Technician app after completing a job — not auth-
    required (the technician app has no login system; the booking's own
    user_id tells us whose Kitchen Health Score to update, same pattern
    as /advance and the rating endpoint)."""
    data = request.get_json(force=True, silent=True) or {}
    metric_name = (data.get("metric_name") or "").strip()
    status_label = (data.get("status_label") or "").strip()
    try:
        value_pct = int(data.get("value_pct"))
    except (TypeError, ValueError):
        return jsonify({"error": "value_pct must be a number"}), 400
    if not metric_name or not status_label:
        return jsonify({"error": "metric_name and status_label are required"}), 400
    value_pct = max(0, min(100, value_pct))

    conn = get_db()
    booking = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    if not booking:
        conn.close()
        return jsonify({"error": "not found"}), 404
    if not booking["user_id"]:
        conn.close()
        return jsonify({"error": "This booking has no associated user account"}), 400

    appliance_id = None
    if booking["service_id"]:
        service_row = conn.execute(
            "SELECT appliance_id FROM services WHERE id = ?", (booking["service_id"],)
        ).fetchone()
        if service_row:
            appliance_id = service_row["appliance_id"]
    if not appliance_id:
        # Legacy bookings (Bachat Package etc.) have no service_id — fall
        # back to the first appliance in the booking's category family.
        fallback = conn.execute(
            "SELECT id FROM appliances WHERE category = ? LIMIT 1", (booking["category"],)
        ).fetchone()
        appliance_id = fallback["id"] if fallback else None
    if not appliance_id:
        conn.close()
        return jsonify({"error": "Could not resolve an appliance for this booking"}), 400

    health_id = new_uuid_id("HEALTH")
    conn.execute(
        "INSERT INTO appliance_health (id, user_id, appliance_id, metric_name, value_pct, status_label, updated_at) "
        "VALUES (?,?,?,?,?,?,?) "
        "ON CONFLICT(user_id, appliance_id) DO UPDATE SET "
        "metric_name=excluded.metric_name, value_pct=excluded.value_pct, "
        "status_label=excluded.status_label, updated_at=excluded.updated_at",
        (health_id, booking["user_id"], appliance_id, metric_name, value_pct, status_label, now()),
    )
    conn.commit()
    row = conn.execute(
        HEALTH_SELECT + " WHERE appliance_health.user_id = ? AND appliance_health.appliance_id = ?",
        (booking["user_id"], appliance_id),
    ).fetchone()
    conn.close()
    return jsonify(appliance_health_row_to_dict(row)), 201


# ---------------------------------------------------------------- bookings
@app.route("/api/bookings", methods=["GET"])
def list_bookings():
    """Auth-optional: with a Bearer token, returns only that user's
    bookings (the authenticated "my bookings" view). Without one, returns
    every booking — this is what technician.html/admin.html rely on for
    their unauthenticated ops views, so it must keep working unchanged."""
    user = get_current_user_optional()
    conn = get_db()
    if user:
        rows = conn.execute(
            "SELECT * FROM bookings WHERE user_id = ? ORDER BY created_at DESC", (user["id"],)
        ).fetchall()
    else:
        rows = conn.execute("SELECT * FROM bookings ORDER BY created_at DESC").fetchall()
    conn.close()
    return jsonify([booking_row_to_dict(r) for r in rows])


@app.route("/api/bookings/<booking_id>", methods=["GET"])
def get_booking(booking_id):
    """Auth-optional, same reasoning as list_bookings: with a token the
    caller can only fetch their own booking (404s otherwise, not 403, to
    avoid confirming other ids exist); without one, unrestricted."""
    user = get_current_user_optional()
    conn = get_db()
    row = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    conn.close()
    if not row:
        return jsonify({"error": "not found"}), 404
    if user and row["user_id"] and row["user_id"] != user["id"]:
        return jsonify({"error": "not found"}), 404
    return jsonify(booking_row_to_dict(row))


@app.route("/api/bookings", methods=["POST"])
@require_auth
def create_booking():
    """Called by the Customer app when someone books a service. Accepts
    either a catalog `service_id` (price/category looked up server-side,
    so the client can't tamper with total_amount) or the legacy
    category/service/price shape used by the Bachat Package promo
    booking, which isn't a purchasable catalog item."""
    data = request.get_json(force=True, silent=True) or {}
    service_id = data.get("service_id")
    bachat_slot = data.get("bachatSlot")
    area = (data.get("area") or "").strip() or None
    technician_id = data.get("technicianId")

    if service_id:
        conn = get_db()
        service_row = conn.execute(SERVICE_SELECT + " WHERE services.id = ?", (service_id,)).fetchone()
        conn.close()
        if not service_row:
            return jsonify({"error": "Unknown service_id"}), 400
        category = service_row["category"]
        service = service_row["appliance_name"] + " · " + service_row["name"]
        price = service_row["price"]
    else:
        category = data.get("category")
        service = data.get("service")
        price = data.get("price", 0)
        service_id = None
        if not category or not service:
            return jsonify({"error": "service_id, or category and service, are required"}), 400

    total_amount = price

    conn = get_db()
    if not technician_id:
        # Auto-route to a verified, on-duty technician in the customer's own
        # area first (fastest to reach them), falling back to any verified
        # on-duty technician for the category, then to anyone at all so the
        # NOT NULL technician_id column is always satisfiable.
        match = None
        if area:
            match = conn.execute(
                "SELECT id FROM technicians WHERE category = ? AND area = ? AND verified = 1 AND online = 1 LIMIT 1",
                (category, area),
            ).fetchone()
        if not match:
            match = conn.execute(
                "SELECT id FROM technicians WHERE category = ? AND verified = 1 AND online = 1 LIMIT 1",
                (category,),
            ).fetchone()
        if not match:
            # No one for this category is online right now — still prefer a
            # same-specialty technician (even offline/unverified) over an
            # unrelated one; a mismatched specialty is worse than a wait.
            match = conn.execute(
                "SELECT id FROM technicians WHERE category = ? LIMIT 1", (category,)
            ).fetchone()
        if not match:
            match = conn.execute("SELECT id FROM technicians LIMIT 1").fetchone()
        technician_id = match["id"] if match else "ramesh"

    booking_id = next_id(conn, "order", "RC")
    ts = now()
    conn.execute(
        "INSERT INTO bookings (id, category, service, price, technician_id, customer_name, "
        "status, bachat_slot, service_rating, tech_rating, area, created_at, updated_at, "
        "user_id, service_id, total_amount) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (booking_id, category, service, price, technician_id, request.user["name"],
         "Requested", bachat_slot, None, None, area, ts, ts,
         request.user["id"], service_id, total_amount),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    conn.close()
    return jsonify(booking_row_to_dict(row)), 201


@app.route("/api/bookings/<booking_id>/advance", methods=["PATCH"])
def advance_booking(booking_id):
    """Called by the Technician app to move a job to its next status."""
    conn = get_db()
    row = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "not found"}), 404

    idx = STATUS_ORDER.index(row["status"]) if row["status"] in STATUS_ORDER else 0
    if idx >= len(STATUS_ORDER) - 1:
        conn.close()
        return jsonify(booking_row_to_dict(row))

    new_status = STATUS_ORDER[idx + 1]
    conn.execute(
        "UPDATE bookings SET status = ?, updated_at = ? WHERE id = ?",
        (new_status, now(), booking_id),
    )
    if new_status == "Completed":
        conn.execute(
            "UPDATE technicians SET jobs_completed = jobs_completed + 1 WHERE id = ?",
            (row["technician_id"],),
        )
    conn.commit()
    row = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    conn.close()
    return jsonify(booking_row_to_dict(row))


@app.route("/api/bookings/<booking_id>/assign", methods=["PATCH"])
def assign_technician(booking_id):
    """Called by the Admin app to assign or reassign which technician is on
    a booking — e.g. routing a freshly requested job, or swapping in a
    replacement if the original technician can't make it."""
    data = request.get_json(force=True, silent=True) or {}
    technician_id = data.get("technician_id")
    if not technician_id:
        return jsonify({"error": "technician_id is required"}), 400

    conn = get_db()
    booking = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    if not booking:
        conn.close()
        return jsonify({"error": "not found"}), 404
    tech = conn.execute("SELECT * FROM technicians WHERE id = ?", (technician_id,)).fetchone()
    if not tech:
        conn.close()
        return jsonify({"error": "Unknown technician_id"}), 400

    new_status = "Accepted" if booking["status"] == "Requested" else booking["status"]
    conn.execute(
        "UPDATE bookings SET technician_id = ?, status = ?, updated_at = ? WHERE id = ?",
        (technician_id, new_status, now(), booking_id),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    conn.close()
    return jsonify(booking_row_to_dict(row))


@app.route("/api/bookings/<booking_id>/rating", methods=["POST"])
def rate_booking(booking_id):
    """Called by the Customer app after a job completes. Updates the
    booking's ratings, rolls the technician's aggregate rating, and
    optionally opens a complaint — all in one transaction."""
    data = request.get_json(force=True)
    service_rating = int(data.get("serviceRating", 0))
    tech_rating = int(data.get("techRating", 0))
    raise_complaint = bool(data.get("raiseComplaint"))
    complaint_text = data.get("complaintText") or "Customer flagged this service as unsatisfactory."

    conn = get_db()
    booking = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    if not booking:
        conn.close()
        return jsonify({"error": "not found"}), 404

    conn.execute(
        "UPDATE bookings SET service_rating = ?, tech_rating = ?, updated_at = ? WHERE id = ?",
        (service_rating, tech_rating, now(), booking_id),
    )

    tech = conn.execute(
        "SELECT * FROM technicians WHERE id = ?", (booking["technician_id"],)
    ).fetchone()
    new_count = tech["rating_count"] + 1
    new_rating = round(((tech["rating"] * tech["rating_count"]) + tech_rating) / new_count, 2)
    conn.execute(
        "UPDATE technicians SET rating = ?, rating_count = ? WHERE id = ?",
        (new_rating, new_count, tech["id"]),
    )

    complaint = None
    if raise_complaint:
        complaint_id = next_id(conn, "complaint", "CMP")
        ts = now()
        conn.execute(
            "INSERT INTO complaints (id, booking_id, text, status, response, created_at) "
            "VALUES (?,?,?,?,?,?)",
            (complaint_id, booking_id, complaint_text, "New", None, ts),
        )
        complaint = {"id": complaint_id, "bookingId": booking_id, "text": complaint_text,
                     "status": "New", "response": None, "createdAt": ts}

    conn.commit()
    row = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    conn.close()
    return jsonify({"booking": booking_row_to_dict(row), "complaint": complaint})


# ---------------------------------------------------------------- complaints
@app.route("/api/complaints", methods=["GET"])
def list_complaints():
    conn = get_db()
    rows = conn.execute("SELECT * FROM complaints ORDER BY created_at DESC").fetchall()
    conn.close()
    return jsonify([complaint_row_to_dict(r) for r in rows])


@app.route("/api/complaints/<complaint_id>", methods=["PATCH"])
def update_complaint(complaint_id):
    """Called by the Technician app (respond + resolve) or the Admin
    dashboard (force resolve / reopen)."""
    data = request.get_json(force=True)
    conn = get_db()
    row = conn.execute("SELECT * FROM complaints WHERE id = ?", (complaint_id,)).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "not found"}), 404

    response = data.get("response", row["response"])
    status = data.get("status", row["status"])
    conn.execute(
        "UPDATE complaints SET response = ?, status = ? WHERE id = ?",
        (response, status, complaint_id),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM complaints WHERE id = ?", (complaint_id,)).fetchone()
    conn.close()
    return jsonify(complaint_row_to_dict(row))


# ---------------------------------------------------------------- technicians
@app.route("/api/technicians", methods=["GET"])
def list_technicians():
    conn = get_db()
    rows = conn.execute("SELECT * FROM technicians ORDER BY name").fetchall()
    conn.close()
    return jsonify([technician_row_to_dict(r) for r in rows])


@app.route("/api/technicians", methods=["POST"])
def create_technician():
    """Called by the Admin app to add a new technician. New hires start
    unverified and offline — they're excluded from auto-routing and from
    the technician app's job feed until an admin verifies them."""
    data = request.get_json(force=True, silent=True) or {}
    name = (data.get("name") or "").strip()
    category = (data.get("category") or "").strip()
    area = (data.get("area") or "").strip()
    if not name or not category or not area:
        return jsonify({"error": "name, category and area are required"}), 400

    conn = get_db()
    tech_id = new_uuid_id("TECH")
    conn.execute(
        "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
        "VALUES (?,?,?,?,0,0,5.0,0,0)",
        (tech_id, name, category, area),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM technicians WHERE id = ?", (tech_id,)).fetchone()
    conn.close()
    return jsonify(technician_row_to_dict(row)), 201


@app.route("/api/technicians/<technician_id>/verify", methods=["PATCH"])
def verify_technician(technician_id):
    """Called by the Admin app once it has checked a new technician's
    documents/background — flips them verified and brings them online so
    they start appearing in auto-routing and the job feed."""
    conn = get_db()
    row = conn.execute("SELECT * FROM technicians WHERE id = ?", (technician_id,)).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "not found"}), 404
    conn.execute("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", (technician_id,))
    conn.commit()
    row = conn.execute("SELECT * FROM technicians WHERE id = ?", (technician_id,)).fetchone()
    conn.close()
    return jsonify(technician_row_to_dict(row))


# ---------------------------------------------------------------- inventory
@app.route("/api/inventory", methods=["GET"])
def list_inventory():
    conn = get_db()
    rows = conn.execute("SELECT * FROM inventory ORDER BY name").fetchall()
    conn.close()
    return jsonify([inventory_row_to_dict(r) for r in rows])


@app.route("/api/inventory", methods=["POST"])
@require_staff_auth
def create_inventory_item():
    data = request.get_json(force=True, silent=True) or {}
    name = (data.get("name") or "").strip()
    sku = (data.get("sku") or "").strip()
    category = (data.get("category") or "").strip()
    try:
        quantity = int(data.get("quantity", 0))
        reorder_level = int(data.get("reorderLevel", 10))
    except (TypeError, ValueError):
        return jsonify({"error": "quantity and reorderLevel must be numbers"}), 400
    if not name or not sku or not category:
        return jsonify({"error": "name, sku and category are required"}), 400

    conn = get_db()
    item_id = new_uuid_id("INV")
    conn.execute(
        "INSERT INTO inventory (id, name, sku, category, quantity, reorder_level, updated_at) "
        "VALUES (?,?,?,?,?,?,?)",
        (item_id, name, sku, category, quantity, reorder_level, now()),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM inventory WHERE id = ?", (item_id,)).fetchone()
    conn.close()
    return jsonify(inventory_row_to_dict(row)), 201


@app.route("/api/inventory/<item_id>", methods=["PATCH"])
@require_staff_auth
def update_inventory_item(item_id):
    data = request.get_json(force=True, silent=True) or {}
    conn = get_db()
    row = conn.execute("SELECT * FROM inventory WHERE id = ?", (item_id,)).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "not found"}), 404
    try:
        quantity = int(data["quantity"]) if "quantity" in data else row["quantity"]
        reorder_level = int(data["reorderLevel"]) if "reorderLevel" in data else row["reorder_level"]
    except (TypeError, ValueError):
        conn.close()
        return jsonify({"error": "quantity and reorderLevel must be numbers"}), 400
    conn.execute(
        "UPDATE inventory SET quantity = ?, reorder_level = ?, updated_at = ? WHERE id = ?",
        (quantity, reorder_level, now(), item_id),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM inventory WHERE id = ?", (item_id,)).fetchone()
    conn.close()
    return jsonify(inventory_row_to_dict(row))


# ---------------------------------------------------------------- stats
@app.route("/api/stats/overview", methods=["GET"])
def stats_overview():
    conn = get_db()
    total_bookings = conn.execute("SELECT COUNT(*) AS n FROM bookings").fetchone()["n"]
    revenue = conn.execute(
        "SELECT COALESCE(SUM(price),0) AS s FROM bookings WHERE status = 'Completed'"
    ).fetchone()["s"]
    open_complaints = conn.execute(
        "SELECT COUNT(*) AS n FROM complaints WHERE status != 'Resolved'"
    ).fetchone()["n"]
    online_techs = conn.execute(
        "SELECT COUNT(*) AS n FROM technicians WHERE online = 1"
    ).fetchone()["n"]
    total_techs = conn.execute("SELECT COUNT(*) AS n FROM technicians").fetchone()["n"]
    conn.close()
    return jsonify({
        "totalBookings": total_bookings,
        "revenue": revenue,
        "openComplaints": open_complaints,
        "onlineTechnicians": online_techs,
        "totalTechnicians": total_techs,
    })


# ---------------------------------------------------------------- reports
PERIOD_DAYS = {"week": 7, "month": 30, "quarter": 90}
TECH_PAYOUT_RATE = 0.65  # assumed share of revenue paid out to technicians — not a real ledger figure


@app.route("/api/stats/reports", methods=["GET"])
@require_staff_auth
def stats_reports():
    period = request.args.get("period", "week")
    days = PERIOD_DAYS.get(period, 7)
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(timespec="seconds") + "Z"

    conn = get_db()
    bookings = conn.execute(
        "SELECT * FROM bookings WHERE created_at >= ? ORDER BY created_at", (cutoff,)
    ).fetchall()
    complaints = conn.execute(
        "SELECT * FROM complaints WHERE created_at >= ?", (cutoff,)
    ).fetchall()
    technicians = conn.execute("SELECT * FROM technicians").fetchall()
    conn.close()

    completed = [b for b in bookings if b["status"] == "Completed"]

    revenue_by_day = {}
    rating_sum_by_day = {}
    rating_count_by_day = {}
    for b in completed:
        day = b["updated_at"][:10]
        amount = b["total_amount"] if "total_amount" in b.keys() and b["total_amount"] is not None else b["price"]
        revenue_by_day[day] = revenue_by_day.get(day, 0) + amount
        if b["service_rating"] is not None:
            rating_sum_by_day[day] = rating_sum_by_day.get(day, 0) + b["service_rating"]
            rating_count_by_day[day] = rating_count_by_day.get(day, 0) + 1
    revenue_trend = [{"date": d, "revenue": v} for d, v in sorted(revenue_by_day.items())]
    rating_trend = [
        {"date": d, "avgRating": round(rating_sum_by_day[d] / rating_count_by_day[d], 2)}
        for d in sorted(rating_count_by_day)
    ]

    revenue_by_category = {}
    for b in completed:
        amount = b["total_amount"] if "total_amount" in b.keys() and b["total_amount"] is not None else b["price"]
        revenue_by_category[b["category"]] = revenue_by_category.get(b["category"], 0) + amount
    revenue_by_category = [
        {"category": c, "revenue": v} for c, v in sorted(revenue_by_category.items(), key=lambda kv: -kv[1])
    ]

    jobs_by_tech = {}
    revenue_by_tech = {}
    for b in completed:
        amount = b["total_amount"] if "total_amount" in b.keys() and b["total_amount"] is not None else b["price"]
        jobs_by_tech[b["technician_id"]] = jobs_by_tech.get(b["technician_id"], 0) + 1
        revenue_by_tech[b["technician_id"]] = revenue_by_tech.get(b["technician_id"], 0) + amount
    leaderboard = sorted(
        [
            {
                "id": t["id"],
                "name": t["name"],
                "jobsInPeriod": jobs_by_tech.get(t["id"], 0),
                "revenueInPeriod": revenue_by_tech.get(t["id"], 0),
                "rating": round(t["rating"], 1),
            }
            for t in technicians
        ],
        key=lambda x: -x["revenueInPeriod"],
    )

    complaint_status_breakdown = {}
    for c in complaints:
        complaint_status_breakdown[c["status"]] = complaint_status_breakdown.get(c["status"], 0) + 1

    gross_revenue = sum(revenue_by_day.values())
    result = {
        "period": period,
        "revenueTrend": revenue_trend,
        "ratingTrend": rating_trend,
        "revenueByCategory": revenue_by_category,
        "technicianLeaderboard": leaderboard,
        "complaintStatusBreakdown": [
            {"status": s, "count": n} for s, n in complaint_status_breakdown.items()
        ],
        "grossRevenue": gross_revenue,
        "completedJobs": len(completed),
        "isOwner": request.staff["role"] == "owner",
        "pnl": None,
    }
    if request.staff["role"] == "owner":
        payout = round(gross_revenue * TECH_PAYOUT_RATE)
        result["pnl"] = {
            "grossRevenue": gross_revenue,
            "technicianPayout": payout,
            "netMargin": gross_revenue - payout,
            "payoutRateAssumed": TECH_PAYOUT_RATE,
        }
    return jsonify(result)


# ---------------------------------------------------------------- reset (demo convenience)
@app.route("/api/reset", methods=["POST"])
def reset():
    init_db(reset=True)
    return jsonify({"ok": True})


# ==================================================================
# Home Services API — backs homeservices.html. A separate, single-user
# prototype (no auth yet), so wallet/profile are the one fixed row
# seeded by seed_home_services(); untouched by /api/reset above, which
# only resets the RasoiCare tables.
# ==================================================================
def hs_booking_row_to_dict(row):
    return {
        "id": row["id"],
        "serviceId": row["service_id"],
        "serviceName": row["service_name"],
        "price": row["price"],
        "date": row["date"],
        "status": row["status"],
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def hs_wallet_state(conn):
    wallet_row = conn.execute("SELECT * FROM hs_wallet WHERE id = 1").fetchone()
    tx_rows = conn.execute("SELECT * FROM hs_wallet_tx ORDER BY created_at DESC").fetchall()
    return {
        "points": wallet_row["points"],
        "tx": [{"label": t["label"], "amount": t["amount"], "ts": t["created_at"]} for t in tx_rows],
    }


def hs_profile_dict(row):
    return {"name": row["name"], "plan": row["plan"]}


@app.route("/api/hs/state", methods=["GET"])
def hs_state():
    conn = get_db()
    bookings = conn.execute("SELECT * FROM hs_bookings ORDER BY created_at DESC").fetchall()
    profile_row = conn.execute("SELECT * FROM hs_profile WHERE id = 1").fetchone()
    wallet = hs_wallet_state(conn)
    conn.close()
    return jsonify({
        "bookings": [hs_booking_row_to_dict(b) for b in bookings],
        "wallet": wallet,
        "profile": hs_profile_dict(profile_row),
    })


@app.route("/api/hs/bookings", methods=["POST"])
def hs_create_booking():
    data = request.get_json(force=True, silent=True) or {}
    service_id = data.get("serviceId")
    service_name = data.get("serviceName")
    price = data.get("price")
    date = data.get("date")
    if not service_id or not service_name or not isinstance(price, (int, float)) or not date:
        return jsonify({"error": "serviceId, serviceName, price and date are required"}), 400

    conn = get_db()
    booking_id = new_uuid_id("HS")
    ts = now()
    conn.execute(
        "INSERT INTO hs_bookings (id, service_id, service_name, price, date, status, created_at, updated_at) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (booking_id, service_id, service_name, price, date, STATUS_ORDER[0], ts, ts),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM hs_bookings WHERE id = ?", (booking_id,)).fetchone()
    conn.close()
    return jsonify(hs_booking_row_to_dict(row)), 201


@app.route("/api/hs/bookings/<booking_id>/advance", methods=["PATCH"])
def hs_advance_booking(booking_id):
    """Called by the client's auto-progress timers to move a booking to
    its next status; awards wallet cashback the moment it reaches
    Completed. Same STATUS_ORDER stages as RasoiCare's bookings."""
    conn = get_db()
    row = conn.execute("SELECT * FROM hs_bookings WHERE id = ?", (booking_id,)).fetchone()
    if not row:
        conn.close()
        return jsonify({"error": "not found"}), 404

    idx = STATUS_ORDER.index(row["status"]) if row["status"] in STATUS_ORDER else 0
    if idx < len(STATUS_ORDER) - 1:
        new_status = STATUS_ORDER[idx + 1]
        conn.execute(
            "UPDATE hs_bookings SET status = ?, updated_at = ? WHERE id = ?",
            (new_status, now(), booking_id),
        )
        if new_status == "Completed":
            earned = round(row["price"] * 0.05)
            conn.execute("UPDATE hs_wallet SET points = points + ? WHERE id = 1", (earned,))
            conn.execute(
                "INSERT INTO hs_wallet_tx (id, label, amount, created_at) VALUES (?,?,?,?)",
                (new_uuid_id("TX"), "Cashback: " + row["service_name"], earned, now()),
            )
        conn.commit()
        row = conn.execute("SELECT * FROM hs_bookings WHERE id = ?", (booking_id,)).fetchone()

    wallet = hs_wallet_state(conn)
    conn.close()
    return jsonify({"booking": hs_booking_row_to_dict(row), "wallet": wallet})


@app.route("/api/hs/wallet/redeem", methods=["POST"])
def hs_redeem():
    conn = get_db()
    wallet_row = conn.execute("SELECT * FROM hs_wallet WHERE id = 1").fetchone()
    if wallet_row["points"] < 50:
        conn.close()
        return jsonify({"error": "Not enough points"}), 400
    conn.execute("UPDATE hs_wallet SET points = points - 50 WHERE id = 1")
    conn.execute(
        "INSERT INTO hs_wallet_tx (id, label, amount, created_at) VALUES (?,?,?,?)",
        (new_uuid_id("TX"), "Redeemed for ₹5 off", -50, now()),
    )
    conn.commit()
    wallet = hs_wallet_state(conn)
    conn.close()
    return jsonify(wallet)


@app.route("/api/hs/profile", methods=["PATCH"])
def hs_update_profile():
    data = request.get_json(force=True, silent=True) or {}
    conn = get_db()
    if data.get("name"):
        conn.execute("UPDATE hs_profile SET name = ? WHERE id = 1", (data["name"].strip(),))
    if "plan" in data:
        conn.execute("UPDATE hs_profile SET plan = ? WHERE id = 1", (data["plan"],))
    conn.commit()
    row = conn.execute("SELECT * FROM hs_profile WHERE id = 1").fetchone()
    conn.close()
    return jsonify(hs_profile_dict(row))


@app.route("/api/hs/reset", methods=["POST"])
def hs_reset():
    conn = get_db()
    conn.execute("DELETE FROM hs_bookings")
    conn.execute("DELETE FROM hs_wallet_tx")
    conn.execute("UPDATE hs_wallet SET points = 100 WHERE id = 1")
    conn.execute("UPDATE hs_profile SET name = 'Ankit', plan = NULL WHERE id = 1")
    conn.commit()
    conn.close()
    return jsonify({"ok": True})


if __name__ == "__main__":
    init_db()
    port = int(os.environ.get("PORT", 8420))
    print(f"RasoiCare backend running on http://127.0.0.1:{port}")
    app.run(host="0.0.0.0", port=port, debug=False)
else:
    init_db()
