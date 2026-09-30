"""
Demo data for the Kitchen Passport module.

    python -m kitchen_passport.seed            # seeds rasoicare.db (or DATABASE_URL)

Creates (idempotently — skipped if the demo customer already exists):
  * Customer "Ankit"  — ankit@rasoicare.demo / demo1234 — 5 appliances with
    four quarterly inspections (Dec 2025 → Sep 2026) so the timeline,
    before/after comparison and AI trend (chimney 95 → 91 → 86 → 78) work.
  * Customer "Meera"  — meera@rasoicare.demo / demo1234 — a hob that scores
    well but has a suspected gas leak (health high, safety CRITICAL).
  * Technician "Ramesh Kumar" — Kitchen Passport login 9822000099 / PIN 4321,
    with jobs assigned for today at both kitchens.
  * Staff owner login is the existing Admin seed (9822000001 / PIN from
    STAFF_SEED_OWNER_PIN, default 1234).
All inspection results are produced by the real engines from raw
measurements — no score is typed in.
"""

from datetime import date, timedelta

from werkzeug.security import generate_password_hash

from . import store

DEMO_TECH_ID = "kp_demo_tech"
DEMO_TECH_PHONE = "9822000099"
DEMO_TECH_PIN = "4321"
DEMO_PASSWORD = "demo1234"

CHIMNEY_BASE = dict(
    rated_suction=1200, measured_suction=1150, filter_condition="CLEAN", suction_unit="m3/h", test_condition="Max speed, filters fitted", motor_condition="NORMAL",
    noise_vibration="NORMAL", duct_diameter=150, duct_length=3, bend_count=2, outlet_condition="GOOD",
    blockage_level="NONE", airflow_condition="GOOD", wiring_condition="GOOD", plug_condition="GOOD",
    switch_condition="GOOD", earthing_condition="PROPER", visible_damage=False, overheating=False,
    physical_condition="GOOD", grease_accumulation="NONE", technician_assessment="GOOD")
HOB_GOOD = dict(
    burner_performance="GOOD", flame_quality="BLUE_STEADY", ignition_condition="WORKING",
    gas_connection_condition="GOOD", electrical_connection_condition="NOT_APPLICABLE", burner_condition="GOOD",
    knob_condition="GOOD", pan_support_condition="GOOD", glass_condition="GOOD", leakage_check="NO_LEAK",
    cleaning_condition="CLEAN")
DW_GOOD = dict(
    washing_performance="GOOD", drainage_condition="GOOD", drainage_time=2, spray_arm_condition="GOOD",
    filter_condition="CLEAN", inlet_condition="GOOD", outlet_condition="GOOD", leakage_condition="NONE",
    drying_condition="GOOD", door_seal="GOOD", odour="NONE", noise="NORMAL")
OVEN_GOOD = dict(
    set_temperature=180, measured_temperature=183, heating_time=9, element_condition="GOOD", fan_condition="GOOD",
    door_seal="GOOD", electrical_condition="GOOD", control_panel="GOOD", door_mechanism="GOOD",
    interior_condition="GOOD", cleaning_condition="CLEAN")
FRIDGE_GOOD = dict(
    cooling_performance="GOOD", measured_fridge_temperature=4.5, compressor_condition="NORMAL", fan_condition="GOOD",
    door_gasket="GOOD", frost_condition="NORMAL", drainage_condition="GOOD", interior_condition="GOOD",
    noise="NORMAL", electrical_condition="GOOD")

# Quarterly history for Ankit: (date, {category: overrides})
ANKIT_HISTORY = [
    ("2025-12-15", {
        "CHIMNEY": dict(measured_suction=1150),
        "HOB": {}, "DISHWASHER": {}, "OVEN": {}, "REFRIGERATOR": {}}),
    ("2026-03-15", {
        "CHIMNEY": dict(measured_suction=1080, filter_condition="LIGHT_GREASE", grease_accumulation="LIGHT"),
        "HOB": dict(cleaning_condition="MODERATE"),
        "DISHWASHER": dict(filter_condition="DIRTY"),
        "OVEN": dict(measured_temperature=188), "REFRIGERATOR": {}}),
    ("2026-06-15", {
        "CHIMNEY": dict(measured_suction=1000, filter_condition="MODERATE_GREASE", grease_accumulation="LIGHT",
                        airflow_condition="REDUCED"),
        "HOB": dict(cleaning_condition="MODERATE", flame_quality="MOSTLY_BLUE"),
        "DISHWASHER": dict(filter_condition="DIRTY", drainage_condition="SLOW", drainage_time=4, odour="MILD"),
        "OVEN": dict(measured_temperature=190, heating_time=12, cleaning_condition="MODERATE"),
        "REFRIGERATOR": dict(measured_fridge_temperature=5.5)}),
]
# Sep 2026 is a real service visit with a before + after inspection each.
ANKIT_SEPT_BEFORE = {
    "CHIMNEY": dict(measured_suction=936, filter_condition="HEAVY_GREASE", grease_accumulation="LIGHT",
                    blockage_level="MODERATE", airflow_condition="REDUCED"),
    "HOB": dict(cleaning_condition="DIRTY", burner_condition="CLOGGED", flame_quality="YELLOW_TIPS"),
    "DISHWASHER": dict(filter_condition="CLOGGED", drainage_condition="SLOW", drainage_time=5, odour="MILD",
                       spray_arm_condition="PARTIALLY_BLOCKED"),
    "OVEN": dict(measured_temperature=196, heating_time=14, cleaning_condition="DIRTY"),
    "REFRIGERATOR": dict(measured_fridge_temperature=6, door_gasket="WORN"),
}
ANKIT_SEPT_AFTER = {
    "CHIMNEY": dict(measured_suction=1010, filter_condition="LIGHT_GREASE", blockage_level="MODERATE",
                    airflow_condition="REDUCED"),
    "HOB": dict(flame_quality="MOSTLY_BLUE"),
    "DISHWASHER": dict(filter_condition="DIRTY", drainage_condition="SLOW", drainage_time=4, odour="MILD",
                       spray_arm_condition="PARTIALLY_BLOCKED", washing_performance="AVERAGE"),
    "OVEN": dict(measured_temperature=192, heating_time=12, element_condition="WEAK"),
    "REFRIGERATOR": dict(door_gasket="WORN", measured_fridge_temperature=5),
}
BASE = {"CHIMNEY": CHIMNEY_BASE, "HOB": HOB_GOOD, "DISHWASHER": DW_GOOD, "OVEN": OVEN_GOOD,
        "REFRIGERATOR": FRIDGE_GOOD}


def _user(conn, uid, email, name, phone):
    if not conn.execute("SELECT id FROM users WHERE id = ?", (uid,)).fetchone():
        conn.execute("INSERT INTO users (id, email, password_hash, name, phone, created_at) VALUES (?,?,?,?,?,?)",
                     (uid, email, generate_password_hash(DEMO_PASSWORD), name, phone, store._now()))
        conn.commit()
    return conn.execute("SELECT * FROM users WHERE id = ?", (uid,)).fetchone()


def _technician(conn):
    if not conn.execute("SELECT id FROM technicians WHERE id = ?", (DEMO_TECH_ID,)).fetchone():
        conn.execute("INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, "
                     "jobs_completed) VALUES (?,?,?,?,1,1,4.8,120,120)",
                     (DEMO_TECH_ID, "Ramesh Kumar", "RasoiSpark", "College Road"))
    if not conn.execute("SELECT technician_id FROM kp_technician_credentials WHERE technician_id = ?",
                        (DEMO_TECH_ID,)).fetchone():
        conn.execute("INSERT INTO kp_technician_credentials (technician_id, phone, pin_hash, created_at) VALUES (?,?,?,?)",
                     (DEMO_TECH_ID, DEMO_TECH_PHONE, generate_password_hash(DEMO_TECH_PIN), store._now()))
    conn.commit()


def _values(cat, overrides):
    return dict(BASE[cat], **overrides)


def _job(conn, kitchen_id, day, appliance_id=None, job_type="SERVICE", notes=None, status="ASSIGNED"):
    jid = f"KPJ-{store.next_seq(conn, 'job'):06d}"
    conn.execute("INSERT INTO kp_technician_jobs (job_id, kitchen_id, technician_id, appliance_id, scheduled_date, "
                 "job_type, status, notes, created_by, created_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
                 (jid, kitchen_id, DEMO_TECH_ID, appliance_id, day.isoformat(), job_type, status, notes, "seed",
                  store._now()))
    conn.commit()
    return jid


def seed_demo(conn, today=None):
    today = today or date.today()
    store.init_kp(conn)
    if conn.execute("SELECT customer_id FROM kp_customers WHERE user_id = 'USR-kpdemo-ankit'").fetchone():
        return False
    cfg = store.load_config(conn)
    _technician(conn)

    # ---------------------------------------------------------- Ankit
    user = _user(conn, "USR-kpdemo-ankit", "ankit@rasoicare.demo", "Ankit", "9876500001")
    cust, passport = store.ensure_customer_passport(conn, user, date(2025, 12, 1))
    conn.execute("UPDATE kp_customers SET address = ?, service_location = ?, preferred_service_time = ?, "
                 "preferred_contact_method = 'WHATSAPP', membership_status = 'MEMBER', amc_status = 'NONE' "
                 "WHERE customer_id = ?", ("Flat 12, Shanti Heights, College Road, Nashik 422005", "College Road, Nashik",
                                           "Weekends 10am-1pm", cust["customer_id"]))
    kitchen = store.kitchens_for_passport(conn, passport["passport_id"])[0]
    conn.execute("UPDATE kp_kitchens SET kitchen_type = 'MODULAR', kitchen_age = 6, cooking_frequency = 'DAILY_TWICE', "
                 "cooking_intensity = 'HEAVY', approximate_daily_cooking_hours = 3.5 WHERE kitchen_id = ?",
                 (kitchen["kitchen_id"],))
    conn.commit()
    kitchen = store.kitchen_owner(conn, kitchen["kitchen_id"])[0]
    specs = [
        ("CHIMNEY", dict(brand="Elica", model="WD HAC 90", serial_number="EL90-22871", purchase_date="2022-02-10",
                         installation_date="2022-02-15", warranty_start="2022-02-15", warranty_end="2027-02-14",
                         extended_warranty=True, installation_company="Elica Service")),
        ("HOB", dict(brand="Faber", model="Jumbo 4B", serial_number="FB4-1182", purchase_date="2022-02-10",
                     installation_date="2022-02-15", warranty_start="2022-02-15", warranty_end="2024-02-14")),
        ("DISHWASHER", dict(brand="Bosch", model="SMS66GI01I", serial_number="BSH-99812", purchase_date="2023-05-01",
                            installation_date="2023-05-04", warranty_start="2023-05-04", warranty_end="2026-05-03")),
        ("OVEN", dict(brand="Siemens", model="HB578", serial_number="SI-5780", purchase_date="2022-03-01",
                      installation_date="2022-03-05", warranty_start="2022-03-05", warranty_end="2025-03-04")),
        ("REFRIGERATOR", dict(brand="LG", model="GL-T322", serial_number="LG-3220", purchase_date="2021-11-11",
                              installation_date="2021-11-11", warranty_start="2021-11-11", warranty_end="2031-11-10",
                              extended_warranty=True)),
    ]
    appl = {}
    for cat, f in specs:
        aid = store.create_appliance(conn, cfg, kitchen["kitchen_id"], cat, f)
        appl[cat] = aid

    def _a(aid):
        return dict(conn.execute("SELECT * FROM kp_appliances WHERE appliance_id = ?", (aid,)).fetchone())

    for day_s, overrides in ANKIT_HISTORY:
        day = date.fromisoformat(day_s)
        jid = _job(conn, kitchen["kitchen_id"], day, job_type="SERVICE", status="ASSIGNED")
        for cat, ov in overrides.items():
            a = _a(appl[cat])
            sid = store.start_service(conn, a, jid, DEMO_TECH_ID, "SERVICE", day)
            iid, ev = store.record_inspection(conn, cfg, a, _values(cat, ov), phase="AFTER", service_id=sid,
                                              technician_id=DEMO_TECH_ID, observations="Routine service", today=day)
            store.attach_inspection_to_service(conn, sid, "AFTER", iid, ev["health"]["score"])
            conn.execute("UPDATE kp_service_records SET status = 'COMPLETED', work_performed = ?, completed_at = ?, "
                         "customer_approved_at = ? WHERE service_id = ?",
                         ("Routine preventive service", store._now(), store._now(), sid))
        conn.execute("UPDATE kp_technician_jobs SET status = 'COMPLETED' WHERE job_id = ?", (jid,))
        conn.commit()
        store.recalc_kitchen(conn, cfg, kitchen["kitchen_id"], day)

    sept = date(2026, 9, 15)
    jid = _job(conn, kitchen["kitchen_id"], sept, job_type="SERVICE")
    for cat in BASE:
        a = _a(appl[cat])
        sid = store.start_service(conn, a, jid, DEMO_TECH_ID, "REPAIR" if cat == "OVEN" else "SERVICE", sept)
        iid, ev = store.record_inspection(conn, cfg, a, _values(cat, ANKIT_SEPT_BEFORE[cat]), phase="BEFORE",
                                          service_id=sid, technician_id=DEMO_TECH_ID, today=sept)
        store.attach_inspection_to_service(conn, sid, "BEFORE", iid, ev["health"]["score"])
        a = _a(appl[cat])
        iid, ev = store.record_inspection(conn, cfg, a, _values(cat, ANKIT_SEPT_AFTER[cat]), phase="AFTER",
                                          service_id=sid, technician_id=DEMO_TECH_ID,
                                          observations="Serviced; see recommendations", today=sept)
        store.attach_inspection_to_service(conn, sid, "AFTER", iid, ev["health"]["score"])
        parts = [{"part_name": "Baffle filter gasket", "quantity": 1, "unit_price": 350, "warranty_days": 90}] \
            if cat == "CHIMNEY" else []
        store.complete_service(conn, cfg, store.get_service(conn, sid),
                               work_performed=f"{cfg['categories'][cat]['label']} service", observations="",
                               parts=parts, labour_amount=499, today=sept)
        conn.execute("UPDATE kp_service_records SET status = 'COMPLETED', customer_approved_at = ? WHERE service_id = ?",
                     (store._now(), sid))
    conn.commit()
    _job(conn, kitchen["kitchen_id"], today, appliance_id=appl["DISHWASHER"], job_type="SERVICE",
         notes="Dishwasher filter + drain service")

    # ---------------------------------------------------------- Meera (critical safety)
    user = _user(conn, "USR-kpdemo-meera", "meera@rasoicare.demo", "Meera", "9876500002")
    cust, passport = store.ensure_customer_passport(conn, user, date(2026, 1, 5))
    conn.execute("UPDATE kp_customers SET address = ?, service_location = ? WHERE customer_id = ?",
                 ("22 Gangapur Road, Nashik", "Gangapur Road, Nashik", cust["customer_id"]))
    kitchen2 = store.kitchens_for_passport(conn, passport["passport_id"])[0]
    conn.commit()
    hob = store.create_appliance(conn, cfg, kitchen2["kitchen_id"], "HOB",
                                 dict(brand="Prestige", model="Royale 3B", purchase_date="2024-01-10",
                                      installation_date="2024-01-12"))
    ch = store.create_appliance(conn, cfg, kitchen2["kitchen_id"], "CHIMNEY",
                                dict(brand="Faber", model="Hood Primus", purchase_date="2024-01-10",
                                     installation_date="2024-01-12"))
    day = today - timedelta(days=2)
    jid = _job(conn, kitchen2["kitchen_id"], day)
    for aid, values in ((ch, _values("CHIMNEY", dict(measured_suction=1130))),
                        (hob, _values("HOB", dict(leakage_check="SUSPECTED")))):
        a = _a(aid)
        sid = store.start_service(conn, a, jid, DEMO_TECH_ID, "INSPECTION", day)
        iid, ev = store.record_inspection(conn, cfg, a, values, phase="BEFORE", service_id=sid,
                                          technician_id=DEMO_TECH_ID, today=day)
        store.attach_inspection_to_service(conn, sid, "BEFORE", iid, ev["health"]["score"])
        iid, ev = store.record_inspection(conn, cfg, _a(aid), values, phase="AFTER", service_id=sid,
                                          technician_id=DEMO_TECH_ID, observations="Gas smell near hob inlet"
                                          if aid == hob else "", today=day)
        store.attach_inspection_to_service(conn, sid, "AFTER", iid, ev["health"]["score"])
        store.complete_service(conn, cfg, store.get_service(conn, sid), work_performed="Inspection",
                               observations="", parts=[], labour_amount=0, today=day)
        if ev["safety"]["status"] in ("CRITICAL", "ATTENTION_REQUIRED"):
            store.notify_safety(conn, cfg, aid, ev)
    _job(conn, kitchen2["kitchen_id"], today, appliance_id=hob, job_type="REPAIR", notes="URGENT: gas leak repair")
    return True


if __name__ == "__main__":
    import sys, os
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import database
    database.init_db()
    c = database.get_db()
    print("Seeded demo data" if seed_demo(c) else "Demo data already present")
    c.close()
