import database
from conftest import register_and_login, auth_headers, add_technician


def _first_service_id(client):
    services = client.get("/api/services").get_json()
    return services[0]["id"]


def test_create_booking_requires_auth(client):
    resp = client.post("/api/bookings", json={"service_id": "x"})
    assert resp.status_code == 401


def test_create_booking_fails_with_no_technicians(client):
    user = register_and_login(client)
    service_id = _first_service_id(client)
    resp = client.post(
        "/api/bookings",
        json={"service_id": service_id},
        headers=auth_headers(user["token"]),
    )
    assert resp.status_code == 503


def test_create_booking_happy_path(client):
    conn = database.get_db()
    add_technician(conn)
    conn.close()

    user = register_and_login(client)
    service_id = _first_service_id(client)
    resp = client.post(
        "/api/bookings",
        json={"service_id": service_id},
        headers=auth_headers(user["token"]),
    )
    assert resp.status_code == 201, resp.get_json()
    body = resp.get_json()
    assert body["id"].startswith("RC-")
    assert body["status"] == "Requested"
    assert body["technicianId"] is None

    listing = client.get("/api/bookings", headers=auth_headers(user["token"])).get_json()
    assert len(listing) == 1
    assert listing[0]["id"] == body["id"]


def test_create_booking_rejects_unknown_service_id(client):
    conn = database.get_db()
    add_technician(conn)
    conn.close()

    user = register_and_login(client)
    resp = client.post(
        "/api/bookings",
        json={"service_id": "does-not-exist"},
        headers=auth_headers(user["token"]),
    )
    assert resp.status_code == 400


def test_bookings_isolated_between_customers(client):
    conn = database.get_db()
    add_technician(conn)
    conn.close()

    alice = register_and_login(client, email="alice2@example.com", phone="9876543211")
    bob = register_and_login(client, email="bob2@example.com", name="Bob", phone="9876543212")
    service_id = _first_service_id(client)

    client.post("/api/bookings", json={"service_id": service_id}, headers=auth_headers(alice["token"]))

    bob_bookings = client.get("/api/bookings", headers=auth_headers(bob["token"])).get_json()
    assert bob_bookings == []
