"""
RasoiCare backend — real Flask REST API.

This is the server all three apps (Customer, Technician, Admin) call
over HTTP. Run it locally with `python3 app.py`, or deploy it (see
README.md) to get a public URL so it can be reached from real,
separate devices.
"""

import os

from flask import Flask, request, jsonify, send_from_directory
from database import get_db, init_db, next_id, now

app = Flask(__name__)
FRONTEND_DIR = os.path.dirname(os.path.abspath(__file__))


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
    return {
        "id": row["id"],
        "name": row["name"],
        "category": row["category"],
        "online": bool(row["online"]),
        "rating": round(row["rating"], 1),
        "ratingCount": row["rating_count"],
        "jobsCompleted": row["jobs_completed"],
    }


# ---------------------------------------------------------------- health
@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"ok": True, "service": "rasoicare-backend"})


# ---------------------------------------------------------------- bookings
@app.route("/api/bookings", methods=["GET"])
def list_bookings():
    conn = get_db()
    rows = conn.execute("SELECT * FROM bookings ORDER BY created_at DESC").fetchall()
    conn.close()
    return jsonify([booking_row_to_dict(r) for r in rows])


@app.route("/api/bookings/<booking_id>", methods=["GET"])
def get_booking(booking_id):
    conn = get_db()
    row = conn.execute("SELECT * FROM bookings WHERE id = ?", (booking_id,)).fetchone()
    conn.close()
    if not row:
        return jsonify({"error": "not found"}), 404
    return jsonify(booking_row_to_dict(row))


@app.route("/api/bookings", methods=["POST"])
def create_booking():
    """Called by the Customer app when someone books a service."""
    data = request.get_json(force=True)
    category = data.get("category")
    service = data.get("service")
    price = data.get("price", 0)
    bachat_slot = data.get("bachatSlot")
    technician_id = data.get("technicianId", "ramesh")

    if not category or not service:
        return jsonify({"error": "category and service are required"}), 400

    conn = get_db()
    booking_id = next_id(conn, "order", "RC")
    ts = now()
    conn.execute(
        "INSERT INTO bookings (id, category, service, price, technician_id, customer_name, "
        "status, bachat_slot, service_rating, tech_rating, created_at, updated_at) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        (booking_id, category, service, price, technician_id, "Amit Sharma",
         "Requested", bachat_slot, None, None, ts, ts),
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


# ---------------------------------------------------------------- reset (demo convenience)
@app.route("/api/reset", methods=["POST"])
def reset():
    init_db(reset=True)
    return jsonify({"ok": True})


if __name__ == "__main__":
    init_db()
    port = int(os.environ.get("PORT", 8420))
    print(f"RasoiCare backend running on http://127.0.0.1:{port}")
    app.run(host="0.0.0.0", port=port, debug=False)
else:
    init_db()
