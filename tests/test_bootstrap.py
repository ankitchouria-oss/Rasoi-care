from conftest import register_and_login, auth_headers, mock_firebase_claims


def test_customer_bootstrap_unverified_email_cannot_take_over_existing_account(client, monkeypatch):
    victim = register_and_login(client, email="victim@example.com")

    # A brand-new Firebase account claiming the victim's email, but not
    # verified by Firebase — must never attach to the victim's real row.
    mock_firebase_claims(monkeypatch, uid="attacker-uid", email="victim@example.com", email_verified=False)
    resp = client.post("/api/me/bootstrap", json={"name": "Attacker"}, headers=auth_headers("x"))
    assert resp.status_code == 200
    attacker = resp.get_json()
    assert attacker["id"] != victim["user"]["id"]


def test_customer_bootstrap_verified_email_merges_into_existing_account(client, monkeypatch):
    victim = register_and_login(client, email="victim2@example.com")

    # A verified email match is the legitimate "old password account"
    # migration path and should still work.
    mock_firebase_claims(monkeypatch, uid="real-uid", email="victim2@example.com", email_verified=True)
    resp = client.post("/api/me/bootstrap", json={"name": "Victim"}, headers=auth_headers("x"))
    assert resp.status_code == 200
    assert resp.get_json()["id"] == victim["user"]["id"]


def test_staff_bootstrap_second_signup_cannot_become_owner(client, monkeypatch):
    mock_firebase_claims(monkeypatch, uid="owner-uid", email="owner@example.com", email_verified=True)
    first = client.post("/api/staff/bootstrap", json={"role": "owner"}, headers=auth_headers("x"))
    # The seeded demo staff (see database.py's seed_staff) means this
    # deployment already has staff before this call — so even the "first"
    # real signup here is not the true first-ever bootstrap.
    assert first.get_json()["role"] == "staff"

    mock_firebase_claims(monkeypatch, uid="attacker-uid", email="attacker@example.com", email_verified=True)
    second = client.post("/api/staff/bootstrap", json={"role": "owner"}, headers=auth_headers("x"))
    assert second.status_code == 200
    assert second.get_json()["role"] == "staff"


def test_staff_bootstrap_unverified_email_cannot_take_over_existing_staff(client, monkeypatch):
    mock_firebase_claims(monkeypatch, uid="staffer-uid", email="staffer@example.com", email_verified=True)
    original = client.post("/api/staff/bootstrap", json={}, headers=auth_headers("x")).get_json()

    mock_firebase_claims(monkeypatch, uid="attacker-uid", email="staffer@example.com", email_verified=False)
    resp = client.post("/api/staff/bootstrap", json={}, headers=auth_headers("x"))
    assert resp.get_json()["id"] != original["id"]
