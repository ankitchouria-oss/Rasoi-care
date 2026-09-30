"""Kitchen Passport API: full technician workflow, role-based access,
configuration, and a consistency check that every displayed indicator
matches a fresh engine calculation over the stored raw data."""
import base64
import re
from datetime import date

import pytest

import database
from conftest import add_technician, auth_headers, register_and_login
from kitchen_passport import engine, routes, seed, store
from kitchen_passport.seed import CHIMNEY_BASE, HOB_GOOD

TODAY = date(2026, 9, 30)
OWNER = {"phone": "9822000001", "pin": "1234"}
STAFF = {"phone": "9822000002", "pin": "1234"}
JPEG = base64.b64encode(b"\xff\xd8\xff\xe0" + b"0" * 64).decode()


@pytest.fixture(autouse=True)
def fixed_today(monkeypatch):
    monkeypatch.setattr(routes, "_today", lambda: TODAY)


def staff_token(client, who=OWNER):
    return client.post("/api/staff/login", json=who).get_json()["token"]


def setup_customer_and_tech(client, email="ankit@example.com", phone="9876543210", tech_id="tech1",
                            tech_phone="9811100001"):
    user = register_and_login(client, email=email, name="Ankit", phone=phone)
    h = auth_headers(user["token"])
    passport = client.get("/api/kp/me/passport", headers=h).get_json()
    kitchen_id = passport["kitchens"][0]["kitchen"]["kitchen_id"]
    client.patch(f"/api/kp/me/kitchens/{kitchen_id}", json={"cooking_intensity": "MODERATE"}, headers=h)
    r = client.post(f"/api/kp/me/kitchens/{kitchen_id}/appliances",
                    json={"category": "CHIMNEY", "brand": "Elica", "last_service_date": "2026-07-01"}, headers=h)
    assert r.status_code == 201, r.get_json()
    appliance_id = r.get_json()["appliance_id"]
    conn = database.get_db()
    add_technician(conn, tid=tech_id)
    conn.close()
    sh = auth_headers(staff_token(client))
    assert client.post(f"/api/kp/admin/technicians/{tech_id}/pin", json={"phone": tech_phone, "pin": "4321"},
                       headers=sh).status_code == 200
    job = client.post("/api/kp/admin/jobs", json={"kitchen_id": kitchen_id, "technician_id": tech_id,
                                                  "scheduled_date": TODAY.isoformat()}, headers=sh)
    assert job.status_code == 201, job.get_json()
    th = auth_headers(client.post("/api/kp/tech/login", json={"phone": tech_phone, "pin": "4321"}).get_json()["token"])
    return {"h": h, "sh": sh, "th": th, "passport": passport, "kitchen_id": kitchen_id,
            "appliance_id": appliance_id, "job_id": job.get_json()["job_id"]}


SPEC_BEFORE = dict(CHIMNEY_BASE, measured_suction=936, filter_condition="HEAVY_GREASE", grease_accumulation="LIGHT",
                   blockage_level="MODERATE", airflow_condition="REDUCED")
SPEC_AFTER = dict(CHIMNEY_BASE, measured_suction=1150)


def run_service(client, s, before=SPEC_BEFORE, after=SPEC_AFTER, findings=None):
    r = client.post(f"/api/kp/tech/jobs/{s['job_id']}/services", json={"appliance_id": s["appliance_id"]},
                    headers=s["th"])
    assert r.status_code == 201, r.get_json()
    sid = r.get_json()["service_id"]
    b = client.post(f"/api/kp/tech/services/{sid}/inspections", json={"phase": "BEFORE", "values": before},
                    headers=s["th"])
    assert b.status_code == 201, b.get_json()
    assert client.post(f"/api/kp/tech/services/{sid}/photos", json={"kind": "BEFORE", "mime_type": "image/jpeg",
                                                                      "dataBase64": JPEG}, headers=s["th"]).status_code == 201
    a = client.post(f"/api/kp/tech/services/{sid}/inspections",
                    json={"phase": "AFTER", "values": after, "technician_findings": findings or []}, headers=s["th"])
    assert a.status_code == 201, a.get_json()
    client.post(f"/api/kp/tech/services/{sid}/photos", json={"kind": "AFTER", "mime_type": "image/jpeg",
                                                               "dataBase64": JPEG}, headers=s["th"])
    done = client.post(f"/api/kp/tech/services/{sid}/complete", json={
        "work_performed": "Deep cleaning", "parts": [{"part_name": "Baffle filter", "quantity": 2, "unit_price": 450,
                                                      "warranty_days": 90}], "labour_amount": 599}, headers=s["th"])
    assert done.status_code == 200, done.get_json()
    return sid, b.get_json(), a.get_json(), done.get_json()


def test_passport_ids_and_qr_payload(client):
    s = setup_customer_and_tech(client)
    assert re.match(r"^RC-KP-\d{8}$", s["passport"]["passport_id"])
    assert s["passport"]["qr_payload"].startswith("RCKP:" + s["passport"]["passport_id"] + ":")
    assert re.match(r"^RC-CH-\d{6}$", s["appliance_id"])
    # QR payload contains no personal data
    assert "Ankit" not in s["passport"]["qr_payload"] and "9876" not in s["passport"]["qr_payload"]


def test_full_technician_workflow(client):
    s = setup_customer_and_tech(client)
    jobs = client.get("/api/kp/tech/jobs", headers=s["th"]).get_json()
    assert jobs[0]["customer"]["full_name"] == "Ankit" and jobs[0]["appliances"][0]["appliance_id"] == s["appliance_id"]
    scan = client.post("/api/kp/tech/scan", json={"code": s["passport"]["qr_payload"]}, headers=s["th"])
    assert scan.status_code == 200 and scan.get_json()["customer"]["full_name"] == "Ankit"
    assert "latitude" not in scan.get_json()["customer"]

    preview = client.post("/api/kp/tech/evaluate", json={"appliance_id": s["appliance_id"], "values": SPEC_BEFORE},
                          headers=s["th"]).get_json()
    sid, before, after, done = run_service(client, s)
    assert before["evaluation"]["health"]["score"] == preview["health"]["score"] == 78
    assert before["evaluation"]["priority"]["priority"] == "MEDIUM"
    assert done["comparison"]["before"] == 78
    assert done["comparison"]["improvement"] == after["evaluation"]["health"]["score"] - 78
    assert done["comparison"]["message"].startswith("Your Kitchen Chimney Health improved by")
    assert done["status"] == "AWAITING_APPROVAL"
    assert done["invoice"]["total_amount"] == 599 + 900
    assert len(done["photos"]) == 2
    assert done["parts_replaced"][0]["warranty_until"] == "2026-12-29"

    # Customer sees the same numbers
    dash = client.get(f"/api/kp/kitchens/{s['kitchen_id']}/dashboard", headers=s["h"]).get_json()
    card = dash["appliances"][0]
    ev = after["evaluation"]
    assert card["indicators"]["health"]["score"] == ev["health"]["score"]
    assert card["indicators"]["safety"]["status"] == ev["safety"]["status"]
    assert card["indicators"]["action"]["priority"] == ev["priority"]["priority"]
    assert card["indicators"]["service"]["recommended_service_date"] == ev["schedule"]["recommended_service_date"]
    assert card["indicators"]["service"]["days_remaining"] == ev["schedule"]["days_remaining"]
    assert dash["overall"]["overall_score"] == ev["health"]["score"]  # single appliance

    # Approve, report, timeline, photo access
    assert client.post(f"/api/kp/me/services/{sid}/approve", headers=s["h"]).get_json()["status"] == "COMPLETED"
    assert client.post(f"/api/kp/me/services/{sid}/approve", headers=s["h"]).status_code == 409
    report = client.get(f"/api/kp/kitchens/{s['kitchen_id']}/report?service_id={sid}", headers=s["h"]).get_json()
    assert report["passport_id"] == s["passport"]["passport_id"]
    assert report["service"]["comparison"]["before"] == 78
    tl = client.get(f"/api/kp/kitchens/{s['kitchen_id']}/timeline", headers=s["h"]).get_json()
    assert tl[0]["score"] == ev["health"]["score"] and tl[0]["date"] == TODAY.isoformat()
    pid = done["photos"][0]["photo_id"]
    img = client.get(f"/api/kp/photos/{pid}", headers=s["h"])
    assert img.status_code == 200 and img.data.startswith(b"\xff\xd8\xff")
    assert "no-store" in img.headers["Cache-Control"]

    # Full inspection view keeps raw values + derived measurement
    detail = client.get(f"/api/kp/appliances/{s['appliance_id']}", headers=s["h"]).get_json()
    ins = client.get(f"/api/kp/inspections/{before['inspection_id']}", headers=s["h"]).get_json()
    meas = {m["param_key"]: m for m in ins["measurements"]}
    assert meas["measured_suction"]["value"] == 936 and not meas["measured_suction"]["derived"]
    assert meas["suction_percentage"]["value"] == 78.0 and meas["suction_percentage"]["derived"]
    assert [x["score"] for x in detail["score_history"]] == [78, ev["health"]["score"]]

    # Job completes; technician loses access once the job is done
    assert client.post("/api/kp/tech/scan", json={"code": s["passport"]["passport_id"]}, headers=s["th"]).status_code == 404
    assert client.get(f"/api/kp/appliances/{s['appliance_id']}", headers=s["th"]).status_code == 404


def test_critical_safety_flows_to_dashboard_and_notification(client):
    s = setup_customer_and_tech(client)
    after = dict(SPEC_AFTER, wiring_condition="EXPOSED")
    sid, before, a, done = run_service(client, s, after=after)
    ev = a["evaluation"]
    assert ev["health"]["score"] >= 85 and ev["safety"]["status"] == "CRITICAL"
    card = client.get(f"/api/kp/kitchens/{s['kitchen_id']}/dashboard", headers=s["h"]).get_json()["appliances"][0]
    assert card["indicators"]["safety"]["status"] == "CRITICAL"
    assert card["indicators"]["action"]["priority"] == "EMERGENCY"
    assert card["safety_findings"][0]["level"] == "CRITICAL"
    notes = client.get("/api/kp/me/notifications", headers=s["h"]).get_json()
    assert any(n["kind"] == "on_safety_critical" for n in notes)
    conn = database.get_db()
    queued = conn.execute("SELECT channel FROM kp_notifications WHERE kind = 'on_safety_critical'").fetchall()
    conn.close()
    assert {r["channel"] for r in queued} == {"app", "sms", "whatsapp"}


def test_technician_defined_critical_finding(client):
    s = setup_customer_and_tech(client)
    _, _, a, _ = run_service(client, s, findings=[{"level": "CRITICAL", "description": "Socket melting behind unit"}])
    assert a["evaluation"]["safety"]["status"] == "CRITICAL"
    assert a["evaluation"]["safety"]["findings"][0]["source"] == "TECHNICIAN"


def test_invalid_inspection_rejected_with_fields(client):
    s = setup_customer_and_tech(client)
    sid = client.post(f"/api/kp/tech/jobs/{s['job_id']}/services", json={"appliance_id": s["appliance_id"]},
                      headers=s["th"]).get_json()["service_id"]
    r = client.post(f"/api/kp/tech/services/{sid}/inspections",
                    json={"phase": "BEFORE", "values": {"measured_suction": "abc", "score": 100}}, headers=s["th"])
    assert r.status_code == 400
    assert "measured_suction" in r.get_json()["fields"] and "filter_condition" in r.get_json()["fields"]
    # AFTER before BEFORE / complete before AFTER are refused
    assert client.post(f"/api/kp/tech/services/{sid}/inspections", json={"phase": "AFTER", "values": SPEC_AFTER},
                       headers=s["th"]).status_code == 409
    assert client.post(f"/api/kp/tech/services/{sid}/complete", json={}, headers=s["th"]).status_code == 409
    bad = client.post(f"/api/kp/tech/services/{sid}/photos",
                      json={"kind": "BEFORE", "mime_type": "image/png", "dataBase64": JPEG}, headers=s["th"])
    assert bad.status_code == 400


def test_customers_cannot_see_each_other(client):
    s = setup_customer_and_tech(client)
    sid, before, _, done = run_service(client, s)
    bob = register_and_login(client, email="bob@example.com", name="Bob", phone="9876543299")
    bh = auth_headers(bob["token"])
    for url in (f"/api/kp/kitchens/{s['kitchen_id']}/dashboard", f"/api/kp/appliances/{s['appliance_id']}",
                f"/api/kp/inspections/{before['inspection_id']}", f"/api/kp/services/{sid}",
                f"/api/kp/kitchens/{s['kitchen_id']}/timeline", f"/api/kp/kitchens/{s['kitchen_id']}/report",
                f"/api/kp/photos/{done['photos'][0]['photo_id']}"):
        assert client.get(url, headers=bh).status_code == 404, url
    assert client.post(f"/api/kp/me/kitchens/{s['kitchen_id']}/appliances", json={"category": "HOB"},
                       headers=bh).status_code == 404
    assert client.post(f"/api/kp/me/services/{sid}/approve", headers=bh).status_code == 404
    assert client.get(f"/api/kp/kitchens/{s['kitchen_id']}/dashboard").status_code == 401


def test_role_boundaries(client):
    s = setup_customer_and_tech(client)
    # customer can't use technician/admin routes
    assert client.get("/api/kp/tech/jobs", headers=s["h"]).status_code == 403
    assert client.get("/api/kp/admin/config", headers=s["h"]).status_code == 403
    assert client.post("/api/kp/tech/evaluate", json={"appliance_id": s["appliance_id"], "values": SPEC_BEFORE},
                       headers=s["h"]).status_code == 403
    # technician can't reach admin or another technician's job
    assert client.get("/api/kp/admin/passports", headers=s["th"]).status_code == 403
    conn = database.get_db()
    add_technician(conn, tid="tech2")
    conn.close()
    client.post("/api/kp/admin/technicians/tech2/pin", json={"phone": "9811100002", "pin": "5555"}, headers=s["sh"])
    t2 = auth_headers(client.post("/api/kp/tech/login", json={"phone": "9811100002", "pin": "5555"}).get_json()["token"])
    assert client.post("/api/kp/tech/scan", json={"code": s["passport"]["qr_payload"]}, headers=t2).status_code == 404
    assert client.post(f"/api/kp/tech/jobs/{s['job_id']}/services", json={"appliance_id": s["appliance_id"]},
                       headers=t2).status_code == 404
    # tampered QR token rejected
    pid = s["passport"]["passport_id"]
    assert client.post("/api/kp/tech/scan", json={"code": f"RCKP:{pid}:forged"}, headers=s["th"]).status_code == 404
    # non-owner staff can read but not change config / PINs
    st = auth_headers(staff_token(client, STAFF))
    assert client.get("/api/kp/admin/config", headers=st).status_code == 200
    assert client.put("/api/kp/admin/config/kitchen_weights", json={"value": {"CHIMNEY": 1}}, headers=st).status_code == 403
    assert client.post("/api/kp/admin/technicians/tech2/pin", json={"phone": "9811100003", "pin": "1111"},
                       headers=st).status_code == 403
    # wrong PIN
    assert client.post("/api/kp/tech/login", json={"phone": "9811100001", "pin": "0000"}).status_code == 401


def test_admin_config_changes_version_and_rescore_keeps_raw_data(client):
    s = setup_customer_and_tech(client)
    sid, before, after, _ = run_service(client, s)
    r = client.put("/api/kp/admin/config/category:CHIMNEY",
                   json={"value": {"weights": {"filter": 100, "suction": 0, "motor": 0, "noise": 0, "duct": 0,
                                               "electrical": 0, "physical": 0, "service_history": 0, "grease": 0,
                                               "technician": 0}}}, headers=s["sh"])
    assert r.status_code == 200 and r.get_json()["algorithm_version"] == 2
    ev = client.post(f"/api/kp/admin/inspections/{before['inspection_id']}/rescore", headers=s["sh"]).get_json()
    assert ev["health"]["score"] == 30          # HEAVY_GREASE = 0.3 of 100
    assert ev["algorithm_version"] == 2
    ins = client.get(f"/api/kp/inspections/{before['inspection_id']}", headers=s["h"]).get_json()
    assert {m["param_key"]: m["value"] for m in ins["measurements"]}["filter_condition"] == "HEAVY_GREASE"
    # Rescoring a historical inspection doesn't change the appliance's current score
    card = client.get(f"/api/kp/appliances/{s['appliance_id']}", headers=s["h"]).get_json()
    assert card["indicators"]["health"]["score"] == after["evaluation"]["health"]["score"]
    # Bad config rejected; reset works
    assert client.put("/api/kp/admin/config/score_thresholds", json={"value": [{"min": 10, "status": "A"},
                                                                              {"min": 50, "status": "B"}]},
                      headers=s["sh"]).status_code == 400
    assert client.put("/api/kp/admin/config/category:CHIMNEY", json={"value": {"weights": {"nope": 5}}},
                      headers=s["sh"]).status_code == 400
    assert client.delete("/api/kp/admin/config/category:CHIMNEY", headers=s["sh"]).status_code == 200
    cfg = client.get("/api/kp/config/public").get_json()
    assert sum(c["weight"] for c in cfg["categories"]["CHIMNEY"]["components"]) == 100


def test_countdown_updates_with_date(client, monkeypatch):
    s = setup_customer_and_tech(client)
    _, _, a, _ = run_service(client, s)
    rec = date.fromisoformat(a["evaluation"]["schedule"]["recommended_service_date"])
    monkeypatch.setattr(routes, "_today", lambda: date.fromordinal(rec.toordinal() + 12))
    card = client.get(f"/api/kp/appliances/{s['appliance_id']}", headers=s["h"]).get_json()["indicators"]["service"]
    assert card["days_remaining"] == -12 and card["overdue_days"] == 12
    assert card["status"] == "OVERDUE" and card["text"] == "Overdue by 12 days"


def test_seeded_demo_indicators_match_engine_recalculation(client):
    """Before finishing: for every seeded sample customer and appliance,
    recompute from the stored raw inspection values and check that the
    displayed health, safety, priority, next service date and days
    remaining are all consistent."""
    conn = database.get_db()
    assert seed.seed_demo(conn, TODAY)
    cfg = store.load_config(conn)
    checked = 0
    for k in conn.execute("SELECT * FROM kp_kitchens").fetchall():
        dash = store.kitchen_dashboard(conn, cfg, dict(k), TODAY)
        for card in dash["appliances"]:
            sc = store.current_score(conn, card["appliance_id"])
            ins = conn.execute("SELECT * FROM kp_appliance_inspections WHERE inspection_id = ?",
                               (sc["inspection_id"],)).fetchone()
            raw = store.load_measurements(conn, sc["inspection_id"])
            h = engine.calculate_appliance_health_score(cfg, card["category"], raw, today=date.fromisoformat(ins["inspected_at"]),
                                                        history=None)
            ind = card["indicators"]
            # health score: engine over stored raw data (service-history component aside)
            sh = [c for c in sc["components"] if c["key"] == "service_history"]
            if not sh:
                assert ind["health"]["score"] == h["score"]
            assert ind["health"]["status"] == engine.score_status(cfg, ind["health"]["score"])
            safety = engine.calculate_safety_status(cfg, card["category"], h["values"])
            assert ind["safety"]["status"] == safety["status"]
            prio = engine.calculate_repair_priority(cfg, card["category"],
                                                    dict(h, score=sc["score"], components=sc["components"]), safety)
            assert ind["action"]["priority"] == prio["priority"]
            sched = store.schedule_for(conn, card["appliance_id"])
            assert ind["service"]["recommended_service_date"] == sched["recommended_service_date"]
            rec = date.fromisoformat(sched["recommended_service_date"])
            assert rec == date.fromisoformat(sched["last_service_date"]).fromordinal(
                date.fromisoformat(sched["last_service_date"]).toordinal() + sched["adjusted_service_interval_days"])
            assert ind["service"]["days_remaining"] == (rec - TODAY).days
            assert ind["service"]["status"] == engine.service_status(cfg, (rec - TODAY).days)["status"]
            checked += 1
        scores = [{"appliance_id": c["appliance_id"], "category": c["category"],
                   "score": c["indicators"]["health"]["score"], "priority": c["indicators"]["action"]["priority"]}
                  for c in dash["appliances"]]
        assert dash["overall"]["overall_score"] == engine.calculate_kitchen_health_score(cfg, scores)["overall_score"]
    assert checked == 7
    # Meera: good hob score yet CRITICAL safety
    meera = conn.execute("SELECT k.* FROM kp_kitchens k JOIN kp_kitchen_passports p ON p.passport_id = k.passport_id "
                         "JOIN kp_customers c ON c.customer_id = p.customer_id WHERE c.full_name = 'Meera'").fetchone()
    d = store.kitchen_dashboard(conn, cfg, dict(meera), TODAY)
    hob = [a for a in d["appliances"] if a["category"] == "HOB"][0]["indicators"]
    assert hob["health"]["score"] >= 90 and hob["safety"]["status"] == "CRITICAL" and hob["action"]["priority"] == "EMERGENCY"
    assert d["overall"]["worst_safety_status"] == "CRITICAL"
    # Ankit's chimney AI trend is declining
    ch = conn.execute("SELECT appliance_id FROM kp_appliances WHERE appliance_id = 'RC-CH-000001'").fetchone()
    assert store.ai_appliance_summary(conn, cfg, ch["appliance_id"], store=False)["trend"] == "declining"
    assert not seed.seed_demo(conn, TODAY)  # idempotent
    conn.close()


def test_demo_logins_work(client):
    conn = database.get_db()
    seed.seed_demo(conn, TODAY)
    conn.close()
    login = client.post("/api/auth/login", json={"email": "ankit@rasoicare.demo", "password": "demo1234"}).get_json()
    p = client.get("/api/kp/me/passport", headers=auth_headers(login["token"])).get_json()
    assert p["passport_id"] == "RC-KP-00000001" and len(p["kitchens"][0]["appliances"]) == 5
    t = client.post("/api/kp/tech/login", json={"phone": seed.DEMO_TECH_PHONE, "pin": seed.DEMO_TECH_PIN}).get_json()
    jobs = client.get("/api/kp/tech/jobs", headers=auth_headers(t["token"])).get_json()
    assert {j["customer"]["full_name"] for j in jobs} == {"Ankit", "Meera"}


def test_frontend_page_served(client):
    r = client.get("/kitchen-passport")
    assert r.status_code == 200 and b"Kitchen Passport" in r.data
