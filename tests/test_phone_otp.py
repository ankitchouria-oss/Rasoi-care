import app as app_module
from conftest import auth_headers, register_and_login


def _capture_sms(monkeypatch):
    captured = {}

    def fake_send_sms(to_number, content, *, request_id=None):
        captured["to"] = to_number
        captured["content"] = content
        return True

    monkeypatch.setattr(app_module, "send_sms", fake_send_sms)
    return captured


def _code_from(captured):
    # "your sign-in code is 1234." — pull the 4 digits back out.
    import re
    return re.search(r"code is (\d{4})", captured["content"]).group(1)


def test_send_otp_requires_valid_phone(client):
    resp = client.post("/api/auth/phone/send-otp", json={"phone": "123"})
    assert resp.status_code == 400


def test_full_signup_flow_creates_account_with_unguessable_password(client, monkeypatch):
    captured = _capture_sms(monkeypatch)
    phone = "9812345670"

    sent = client.post("/api/auth/phone/send-otp", json={"phone": phone})
    assert sent.status_code == 200
    assert sent.get_json()["sent"] is True
    code = _code_from(captured)

    verified = client.post("/api/auth/phone/verify-otp", json={"phone": phone, "otp": code})
    assert verified.status_code == 200
    assert verified.get_json() == {"needsRegistration": True}

    registered = client.post(
        "/api/auth/phone/register", json={"phone": phone, "name": "New Customer"}
    )
    assert registered.status_code == 201, registered.get_json()
    body = registered.get_json()
    assert body["token"]
    assert body["user"]["phone"] == phone

    # The old predictable scheme ('rc-' + phone) must not work anymore.
    old_scheme_login = client.post(
        "/api/auth/login",
        json={"email": f"{phone}@rasoicare.demo", "password": f"rc-{phone}"},
    )
    assert old_scheme_login.status_code == 401


def test_verify_otp_logs_in_existing_account_by_phone(client, monkeypatch):
    phone = "9812345671"
    register_and_login(client, email="existing@example.com", phone=phone)

    captured = _capture_sms(monkeypatch)
    client.post("/api/auth/phone/send-otp", json={"phone": phone})
    code = _code_from(captured)

    resp = client.post("/api/auth/phone/verify-otp", json={"phone": phone, "otp": code})
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["token"]
    assert body["user"]["phone"] == phone


def test_verify_otp_rejects_wrong_code(client, monkeypatch):
    phone = "9812345672"
    _capture_sms(monkeypatch)
    client.post("/api/auth/phone/send-otp", json={"phone": phone})

    resp = client.post("/api/auth/phone/verify-otp", json={"phone": phone, "otp": "0000"})
    assert resp.status_code == 400


def test_register_requires_verified_phone_first(client):
    resp = client.post(
        "/api/auth/phone/register", json={"phone": "9812345673", "name": "Nobody"}
    )
    assert resp.status_code == 400


def test_register_is_one_time_use_of_the_verified_flag(client, monkeypatch):
    phone = "9812345674"
    captured = _capture_sms(monkeypatch)
    client.post("/api/auth/phone/send-otp", json={"phone": phone})
    code = _code_from(captured)
    client.post("/api/auth/phone/verify-otp", json={"phone": phone, "otp": code})

    first = client.post("/api/auth/phone/register", json={"phone": phone, "name": "Alice"})
    assert first.status_code == 201

    # The verified flag is one-time — a second register call without
    # re-verifying must not be able to piggyback on the first's proof of
    # phone ownership.
    second = client.post("/api/auth/phone/register", json={"phone": phone, "name": "Alice"})
    assert second.status_code == 400
