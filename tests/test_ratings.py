import database
from conftest import register_and_login, auth_headers, add_technician


def _completed_booking(client, user, tid="tech1"):
    conn = database.get_db()
    add_technician(conn, tid=tid)
    conn.close()
    services = client.get("/api/services").get_json()
    resp = client.post(
        "/api/bookings",
        json={"service_id": services[0]["id"]},
        headers=auth_headers(user["token"]),
    )
    booking_id = resp.get_json()["id"]
    conn = database.get_db()
    conn.execute(
        "UPDATE bookings SET technician_id = ?, status = 'Completed' WHERE id = ?",
        (tid, booking_id),
    )
    conn.commit()
    conn.close()
    return booking_id


def test_rating_cannot_be_submitted_twice(client):
    user = register_and_login(client)
    booking_id = _completed_booking(client, user)

    first = client.post(
        f"/api/bookings/{booking_id}/rating",
        json={"serviceRating": 5, "techRating": 5},
        headers=auth_headers(user["token"]),
    )
    assert first.status_code == 200

    conn = database.get_db()
    tech_after_first = conn.execute("SELECT rating, rating_count FROM technicians WHERE id = 'tech1'").fetchone()
    conn.close()
    assert tech_after_first["rating_count"] == 11  # seeded at 10 + this one

    # Replaying the same rating (or a spammed 1-star) must not roll the
    # technician's average a second time.
    second = client.post(
        f"/api/bookings/{booking_id}/rating",
        json={"serviceRating": 1, "techRating": 1},
        headers=auth_headers(user["token"]),
    )
    assert second.status_code == 400

    conn = database.get_db()
    tech_after_second = conn.execute("SELECT rating, rating_count FROM technicians WHERE id = 'tech1'").fetchone()
    conn.close()
    assert tech_after_second["rating_count"] == 11
    assert tech_after_second["rating"] == tech_after_first["rating"]


def test_rating_rejects_other_customers_booking(client):
    alice = register_and_login(client, email="alice3@example.com", phone="9876543213")
    bob = register_and_login(client, email="bob3@example.com", name="Bob", phone="9876543214")
    booking_id = _completed_booking(client, alice)

    resp = client.post(
        f"/api/bookings/{booking_id}/rating",
        json={"serviceRating": 1, "techRating": 1},
        headers=auth_headers(bob["token"]),
    )
    # 404, not 403 — booking ids are sequential, so a 403 here would
    # confirm the id exists and belongs to someone else.
    assert resp.status_code == 404
