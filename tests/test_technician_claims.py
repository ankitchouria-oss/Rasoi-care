import database
from conftest import register_and_login, auth_headers, mock_firebase_claims


def _bootstrap_technician(client, monkeypatch, uid, category="RasoiSpark", area="Test Area"):
    mock_firebase_claims(monkeypatch, uid=uid, email=f"{uid}@example.com", email_verified=True)
    resp = client.post(
        "/api/technician/bootstrap",
        json={"name": "Test Tech", "category": category, "area": area},
        headers=auth_headers("x"),
    )
    assert resp.status_code == 200, resp.get_json()
    return resp.get_json()


def _create_booking(client, category="RasoiSpark", area=None, lat=None, lng=None, address_line=None):
    conn = database.get_db()
    conn.execute(
        "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
        "VALUES ('seed-tech', 'Seed Tech', ?, 'Test Area', 1, 1, 4.5, 10, 10)",
        (category,),
    )
    conn.commit()
    conn.close()
    user = register_and_login(client, email="customer-claims@example.com", phone="9876500001")
    services = client.get("/api/services").get_json()
    service_id = next(s["id"] for s in services if s["category"] == category)
    payload = {"service_id": service_id}
    if lat is not None:
        payload["lat"] = lat
    if lng is not None:
        payload["lng"] = lng
    if address_line is not None:
        payload["addressLine"] = address_line
    booking = client.post(
        "/api/bookings", json=payload, headers=auth_headers(user["token"])
    ).get_json()
    return booking


def test_available_bookings_hides_address_and_phone_before_claim(client, monkeypatch):
    booking = _create_booking(client)
    tech = _bootstrap_technician(client, monkeypatch, uid="tech-see")
    conn = database.get_db()
    conn.execute("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", (tech["id"],))
    conn.commit()
    conn.close()

    resp = client.get("/api/technician/bookings/available", headers=auth_headers("x"))
    assert resp.status_code == 200
    listed = next(b for b in resp.get_json() if b["id"] == booking["id"])
    assert listed["addressLine"] is None
    assert listed["customerPhone"] is None
    assert listed["lat"] is None
    assert listed["lng"] is None


def test_unverified_technician_cannot_claim_a_booking(client, monkeypatch):
    booking = _create_booking(client)
    # bootstrap_technician always leaves a new technician unverified.
    _bootstrap_technician(client, monkeypatch, uid="tech-unverified")

    resp = client.patch(f"/api/bookings/{booking['id']}/claim", headers=auth_headers("x"))
    assert resp.status_code == 403

    conn = database.get_db()
    row = conn.execute("SELECT technician_id FROM bookings WHERE id = ?", (booking["id"],)).fetchone()
    conn.close()
    assert row["technician_id"] is None


def test_verified_technician_can_claim_a_booking(client, monkeypatch):
    booking = _create_booking(client)
    tech = _bootstrap_technician(client, monkeypatch, uid="tech-verified")
    conn = database.get_db()
    conn.execute("UPDATE technicians SET verified = 1 WHERE id = ?", (tech["id"],))
    conn.commit()
    conn.close()

    resp = client.patch(f"/api/bookings/{booking['id']}/claim", headers=auth_headers("x"))
    assert resp.status_code == 200
    assert resp.get_json()["technicianId"] == tech["id"]


def test_booking_city_inferred_from_coordinates(client):
    booking = _create_booking(client, lat=19.9975, lng=73.7898)  # Nashik
    assert booking["city"] == "Nashik"


def test_booking_city_inferred_from_address_text_without_coordinates(client):
    booking = _create_booking(client, address_line="12 FC Road, Pune, Maharashtra")
    assert booking["city"] == "Pune"


def test_booking_with_no_address_has_no_city(client):
    booking = _create_booking(client)
    assert booking["city"] is None


def test_available_bookings_only_reaches_technicians_in_the_same_city(client, monkeypatch):
    # A Nashik-area booking (real coordinates) must not show up for a
    # technician who registered in a different city — this is exactly the
    # bug fixed here: the old code compared the booking's address *label*
    # ("Home"/"Office") against the technician's city, which never matched
    # a real booking, so this dispatch filter was effectively dead.
    booking = _create_booking(client, lat=19.9975, lng=73.7898)  # Nashik
    assert booking["city"] == "Nashik"

    nashik_tech = _bootstrap_technician(client, monkeypatch, uid="tech-nashik", area="Nashik")
    conn = database.get_db()
    conn.execute("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", (nashik_tech["id"],))
    conn.commit()
    conn.close()
    listing = client.get("/api/technician/bookings/available", headers=auth_headers("x")).get_json()
    assert any(b["id"] == booking["id"] for b in listing)

    pune_tech = _bootstrap_technician(client, monkeypatch, uid="tech-pune", area="Pune")
    conn = database.get_db()
    conn.execute("UPDATE technicians SET verified = 1, online = 1 WHERE id = ?", (pune_tech["id"],))
    conn.commit()
    conn.close()
    listing2 = client.get("/api/technician/bookings/available", headers=auth_headers("x")).get_json()
    assert not any(b["id"] == booking["id"] for b in listing2)
