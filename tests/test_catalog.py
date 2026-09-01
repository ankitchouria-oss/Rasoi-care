def test_appliances_listed(client):
    resp = client.get("/api/appliances")
    assert resp.status_code == 200
    body = resp.get_json()
    assert isinstance(body, list) and len(body) > 0


def test_services_listed(client):
    resp = client.get("/api/services")
    assert resp.status_code == 200
    body = resp.get_json()
    assert isinstance(body, list) and len(body) > 0
    assert "price" in body[0]
