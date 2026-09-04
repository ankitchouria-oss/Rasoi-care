from conftest import register_and_login, auth_headers


def test_health_check(client):
    resp = client.get("/api/health")
    assert resp.status_code == 200


def test_register_creates_account_and_returns_token(client):
    body = register_and_login(client)
    assert body["token"]
    assert body["user"]["email"] == "alice@example.com"
    assert body["user"]["name"] == "Alice"
    assert body["user"]["phone"] == "9876543210"


def test_register_duplicate_email_rejected(client):
    register_and_login(client)
    resp = client.post(
        "/api/auth/register",
        json={"email": "alice@example.com", "password": "hunter22", "name": "Alice 2"},
    )
    assert resp.status_code >= 400


def test_register_rejects_short_password(client):
    resp = client.post(
        "/api/auth/register",
        json={"email": "bob@example.com", "password": "abc", "name": "Bob"},
    )
    assert resp.status_code == 400


def test_login_with_correct_credentials_succeeds(client):
    register_and_login(client)
    resp = client.post("/api/auth/login", json={"email": "alice@example.com", "password": "hunter22"})
    assert resp.status_code == 200
    assert resp.get_json()["token"]


def test_login_with_wrong_password_fails(client):
    register_and_login(client)
    resp = client.post("/api/auth/login", json={"email": "alice@example.com", "password": "wrong-pass"})
    assert resp.status_code == 401


def test_login_unknown_email_fails(client):
    resp = client.post("/api/auth/login", json={"email": "nobody@example.com", "password": "whatever1"})
    assert resp.status_code == 401


def test_me_requires_auth(client):
    resp = client.get("/api/auth/me")
    assert resp.status_code == 401


def test_me_returns_current_user(client):
    body = register_and_login(client)
    resp = client.get("/api/auth/me", headers=auth_headers(body["token"]))
    assert resp.status_code == 200
    assert resp.get_json()["email"] == "alice@example.com"


def test_me_rejects_garbage_token(client):
    resp = client.get("/api/auth/me", headers={"Authorization": "Bearer not-a-real-token"})
    assert resp.status_code == 401
