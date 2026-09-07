from conftest import register_and_login, auth_headers


def test_hs_state_requires_auth(client):
    resp = client.get("/api/hs/state")
    assert resp.status_code == 401


def test_hs_state_lazily_creates_wallet_and_profile(client):
    user = register_and_login(client)
    resp = client.get("/api/hs/state", headers=auth_headers(user["token"]))
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["bookings"] == []
    assert body["wallet"] == {"points": 100, "tx": []}
    assert body["profile"]["name"] == "Alice"


def test_hs_booking_lifecycle_and_cashback(client):
    user = register_and_login(client)
    headers = auth_headers(user["token"])

    created = client.post(
        "/api/hs/bookings",
        json={"serviceId": "otg", "date": "2026-09-05"},
        headers=headers,
    )
    assert created.status_code == 201
    booking_id = created.get_json()["id"]

    # Requested -> Accepted -> On the way -> In Progress -> Completed
    result = None
    for _ in range(4):
        result = client.patch(f"/api/hs/bookings/{booking_id}/advance", headers=headers).get_json()

    assert result["booking"]["status"] == "Completed"
    assert result["wallet"]["points"] == 122  # 100 starter + 5% of 449 (server-priced from the catalog)
    assert result["wallet"]["tx"][0]["label"] == "Cashback: OTG"


def test_hs_redeem_requires_enough_points(client):
    user = register_and_login(client)
    headers = auth_headers(user["token"])
    resp = client.post("/api/hs/wallet/redeem", headers=headers)
    assert resp.status_code == 200  # 100 starter points covers the 50-point redemption
    assert resp.get_json()["points"] == 50

    resp2 = client.post("/api/hs/wallet/redeem", headers=headers)
    assert resp2.status_code == 200
    assert resp2.get_json()["points"] == 0

    resp3 = client.post("/api/hs/wallet/redeem", headers=headers)
    assert resp3.status_code == 400


def test_hs_profile_update(client):
    user = register_and_login(client)
    headers = auth_headers(user["token"])
    resp = client.patch("/api/hs/profile", json={"name": "Renamed"}, headers=headers)
    assert resp.status_code == 200
    assert resp.get_json()["name"] == "Renamed"


def test_hs_data_isolated_between_users(client):
    alice = register_and_login(client, email="hs-alice@example.com", phone="9111111111")
    bob = register_and_login(client, email="hs-bob@example.com", name="Bob", phone="9222222222")

    client.post(
        "/api/hs/bookings",
        json={"serviceId": "otg", "date": "2026-09-05"},
        headers=auth_headers(alice["token"]),
    )

    bob_state = client.get("/api/hs/state", headers=auth_headers(bob["token"])).get_json()
    assert bob_state["bookings"] == []
    assert bob_state["wallet"]["points"] == 100


def test_hs_booking_rejects_unknown_service_and_client_price(client):
    user = register_and_login(client)
    headers = auth_headers(user["token"])
    resp = client.post(
        "/api/hs/bookings",
        json={"serviceId": "svc1", "price": 9_999_999, "date": "2026-09-05"},
        headers=headers,
    )
    assert resp.status_code == 400


def test_hs_advance_on_unknown_booking_404s(client):
    user = register_and_login(client)
    resp = client.patch("/api/hs/bookings/does-not-exist/advance", headers=auth_headers(user["token"]))
    assert resp.status_code == 404


def test_hs_reset(client):
    user = register_and_login(client)
    headers = auth_headers(user["token"])
    client.post(
        "/api/hs/bookings",
        json={"serviceId": "otg", "date": "2026-09-05"},
        headers=headers,
    )
    resp = client.post("/api/hs/reset", headers=headers)
    assert resp.status_code == 200

    state = client.get("/api/hs/state", headers=headers).get_json()
    assert state["bookings"] == []
    assert state["wallet"]["points"] == 100
