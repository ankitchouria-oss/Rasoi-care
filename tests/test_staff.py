from conftest import auth_headers

OWNER_PHONE = "9822000001"
OWNER_PIN = "1234"


def test_staff_login_succeeds_with_seeded_owner(client):
    resp = client.post("/api/staff/login", json={"phone": OWNER_PHONE, "pin": OWNER_PIN})
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["token"]
    assert body["staff"]["role"] == "owner"


def test_staff_login_wrong_pin_rejected(client):
    resp = client.post("/api/staff/login", json={"phone": OWNER_PHONE, "pin": "0000"})
    assert resp.status_code == 401


def test_staff_me_requires_auth(client):
    resp = client.get("/api/staff/me")
    assert resp.status_code == 401


def test_staff_me_returns_current_staff(client):
    login = client.post("/api/staff/login", json={"phone": OWNER_PHONE, "pin": OWNER_PIN}).get_json()
    resp = client.get("/api/staff/me", headers=auth_headers(login["token"]))
    assert resp.status_code == 200
    assert resp.get_json()["phone"] == OWNER_PHONE


def test_customer_token_rejected_on_staff_route(client):
    from conftest import register_and_login
    user = register_and_login(client)
    resp = client.get("/api/staff/me", headers=auth_headers(user["token"]))
    assert resp.status_code == 401
