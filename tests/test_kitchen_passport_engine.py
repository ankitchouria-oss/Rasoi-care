"""Kitchen Passport engines — sample customers checked against hand
calculations from the specification."""
import copy
from datetime import date

import pytest

from kitchen_passport import engine
from kitchen_passport.config import DEFAULT_CONFIG
from kitchen_passport.seed import CHIMNEY_BASE, DW_GOOD, FRIDGE_GOOD, HOB_GOOD, OVEN_GOOD

C = DEFAULT_CONFIG
TODAY = date(2026, 9, 30)


def cfg():
    return copy.deepcopy(DEFAULT_CONFIG)


def test_category_weights_total_100():
    for code, cat in C["categories"].items():
        assert sum(c["weight"] for c in cat["components"]) == 100, code


def test_perfect_chimney_scores_100_excellent():
    h = engine.calculate_appliance_health_score(C, "CHIMNEY", dict(CHIMNEY_BASE, measured_suction=1200),
                                                history={"last_service_date": "2026-08-01"}, today=TODAY)
    assert h["score"] == 100
    assert h["status"] == "EXCELLENT"
    assert h["values"]["suction_percentage"] == 100.0


def test_spec_example_chimney_78_medium_30_days():
    """Section 20: heavy grease, suction 22% below, moderate duct
    restriction → 78/100, MEDIUM, within 30 days, the three actions."""
    v = dict(CHIMNEY_BASE, measured_suction=936, filter_condition="HEAVY_GREASE", grease_accumulation="LIGHT",
             blockage_level="MODERATE", airflow_condition="REDUCED")
    ev = engine.evaluate_inspection(C, "CHIMNEY", v, history={"last_service_date": "2026-07-01"}, today=TODAY)
    assert ev["health"]["values"]["suction_percentage"] == 78.0
    # suction band 70-79 → 0.7*25 = 17.5; filter 0.3*15 = 4.5; duct avg(1,.5,.6)=.7 & bends 1 → .85*10 = 8.5;
    # grease .8*5 = 4; others full: 10+10+10+5+5+5 = 45 → 17.5+4.5+8.5+4+45 = 79.5 - service ok → round(79.5)...
    comps = {c["key"]: c["points"] for c in ev["health"]["components"]}
    assert comps["suction"] == 17.5 and comps["filter"] == 4.5 and comps["grease"] == 4.0
    assert ev["health"]["score"] == round(sum(comps.values()))
    assert ev["health"]["score"] == 78
    assert ev["health"]["status"] == "MONITOR"
    assert ev["safety"]["status"] == "NORMAL"
    assert ev["priority"]["priority"] == "MEDIUM"
    assert ev["priority"]["recommended_within_days"] == 30
    texts = [i["text"] for i in ev["recommendations"]["items"]]
    assert texts[:3] == ["Chimney deep cleaning", "Filter maintenance", "Airflow inspection"]
    s = ev["schedule"]
    assert s["adjusted_service_interval_days"] == 30
    assert s["recommended_service_date"] == "2026-10-30"
    assert s["days_remaining"] == 30


def test_high_score_does_not_hide_critical_safety():
    v = dict(CHIMNEY_BASE, measured_suction=1180, wiring_condition="EXPOSED")
    ev = engine.evaluate_inspection(C, "CHIMNEY", v, history={"last_service_date": "2026-08-01"}, today=TODAY)
    assert ev["health"]["score"] >= 85
    assert ev["safety"]["status"] == "CRITICAL"
    assert ev["priority"]["priority"] == "EMERGENCY"
    assert ev["recommendations"]["items"][0]["urgent"] is True
    assert "wiring" in ev["recommendations"]["action"].lower()
    assert ev["schedule"]["adjusted_service_interval_days"] == 1


def test_hob_gas_leak_is_critical_even_with_high_score():
    ev = engine.evaluate_inspection(C, "HOB", dict(HOB_GOOD, leakage_check="SUSPECTED"), today=TODAY)
    assert ev["health"]["score"] == 90
    assert ev["safety"]["status"] == "CRITICAL"
    assert ev["priority"]["priority"] == "EMERGENCY"
    assert ev["recommendations"]["items"][0]["text"] == "Urgent safety repair"


def test_hob_not_applicable_connection_is_excluded_not_penalised():
    h = engine.calculate_appliance_health_score(C, "HOB", HOB_GOOD, today=TODAY)
    conn = [c for c in h["components"] if c["key"] == "connection"][0]
    assert conn["fraction"] == 1.0
    assert h["score"] == 100


def test_dishwasher_leak_near_electrical_critical_and_minor_monitor():
    ev = engine.evaluate_inspection(C, "DISHWASHER", dict(DW_GOOD, leakage_condition="NEAR_ELECTRICAL"),
                                    history={"last_service_date": "2026-08-01"}, today=TODAY)
    assert ev["safety"]["status"] == "CRITICAL"
    ev2 = engine.evaluate_inspection(C, "DISHWASHER", dict(DW_GOOD, leakage_condition="MINOR"),
                                     history={"last_service_date": "2026-08-01"}, today=TODAY)
    assert ev2["safety"]["status"] == "MONITOR"
    assert [f["level"] for f in ev2["safety"]["findings"]] == ["MONITOR"]


def test_dishwasher_blocked_drain_is_high_priority():
    ev = engine.evaluate_inspection(C, "DISHWASHER", dict(DW_GOOD, drainage_condition="BLOCKED", drainage_time=12),
                                    history={"last_service_date": "2026-08-01"}, today=TODAY)
    assert ev["priority"]["priority"] == "HIGH"
    assert ev["schedule"]["adjusted_service_interval_days"] == 7


def test_oven_temperature_derivation_and_overheat_rule():
    ev = engine.evaluate_inspection(C, "OVEN", dict(OVEN_GOOD, measured_temperature=225), today=TODAY)
    assert ev["health"]["values"]["temperature_difference"] == 45
    assert ev["safety"]["status"] == "CRITICAL"
    # Only the most severe rule for the same parameter is reported.
    assert len([f for f in ev["safety"]["findings"] if f["param"] == "temperature_overshoot"]) == 1
    ev2 = engine.evaluate_inspection(C, "OVEN", dict(OVEN_GOOD, measured_temperature=150), today=TODAY)
    assert ev2["safety"]["status"] == "NORMAL"          # under-heating is not a safety issue
    assert ev2["health"]["values"]["temperature_difference"] == 30


def test_microwave_and_refrigerator_normalised_to_100():
    mw = dict(heating_performance="GOOD", heating_consistency="EVEN", turntable_condition="GOOD", door_latch="GOOD",
              door_seal="GOOD", fan_condition="GOOD", interior_condition="GOOD", control_panel="GOOD", noise="NORMAL",
              electrical_condition="GOOD")
    assert engine.calculate_appliance_health_score(C, "MICROWAVE", mw, history={"last_service_date": "2026-09-01"},
                                                   today=TODAY)["score"] == 100
    assert engine.calculate_appliance_health_score(C, "REFRIGERATOR", dict(FRIDGE_GOOD, measured_fridge_temperature=4),
                                                   history={"last_service_date": "2026-09-01"}, today=TODAY)["score"] == 100
    ev = engine.evaluate_inspection(C, "MICROWAVE", dict(mw, door_latch="FAULTY"), today=TODAY)
    assert ev["safety"]["status"] == "CRITICAL"


def test_missing_and_invalid_values_rejected():
    with pytest.raises(engine.InspectionError) as e:
        engine.calculate_appliance_health_score(C, "CHIMNEY", {"rated_suction": 1000}, today=TODAY)
    assert "measured_suction" in e.value.fields and "filter_condition" in e.value.fields
    with pytest.raises(engine.InspectionError) as e:
        engine.calculate_appliance_health_score(C, "CHIMNEY", dict(CHIMNEY_BASE, filter_condition="SPARKLY"), today=TODAY)
    assert "filter_condition" in e.value.fields
    with pytest.raises(engine.InspectionError):
        engine.calculate_appliance_health_score(C, "CHIMNEY", dict(CHIMNEY_BASE, rated_suction=0), today=TODAY)


def test_health_score_cannot_be_injected():
    v = dict(CHIMNEY_BASE, measured_suction=600, filter_condition="BLOCKED", score=100, health_score=100)
    h = engine.calculate_appliance_health_score(C, "CHIMNEY", v, today=TODAY)
    assert h["score"] < 80
    assert "score" not in h["values"] and "health_score" not in h["values"]


@pytest.mark.parametrize("score,status", [(100, "EXCELLENT"), (90, "EXCELLENT"), (89, "HEALTHY"), (80, "HEALTHY"),
                                          (79, "MONITOR"), (70, "MONITOR"), (69, "ATTENTION_REQUIRED"),
                                          (50, "ATTENTION_REQUIRED"), (49, "CRITICAL"), (0, "CRITICAL")])
def test_score_status_thresholds(score, status):
    assert engine.score_status(C, score) == status


@pytest.mark.parametrize("days,status", [(76, "NOT_DUE"), (31, "NOT_DUE"), (30, "APPROACHING"), (15, "APPROACHING"),
                                         (14, "DUE_SOON"), (1, "DUE_SOON"), (0, "DUE"), (-12, "OVERDUE")])
def test_service_status_thresholds(days, status):
    assert engine.service_status(C, days)["status"] == status


def test_countdown_spec_examples():
    assert engine.calculate_days_remaining("2026-12-15", date(2026, 9, 30)) == {"days_remaining": 76, "overdue_days": 0}
    assert engine.calculate_days_remaining("2026-09-18", date(2026, 9, 30)) == {"days_remaining": -12, "overdue_days": 12}


def test_thresholds_are_configurable():
    c = cfg()
    c["score_thresholds"][0]["min"] = 95
    assert engine.score_status(c, 92) == "HEALTHY"
    c["countdown_thresholds"][0]["min"] = 60
    assert engine.service_status(c, 45)["status"] == "APPROACHING"


def test_weights_are_configurable():
    c = cfg()
    for comp in c["categories"]["CHIMNEY"]["components"]:
        comp["weight"] = 100 if comp["key"] == "filter" else 0
    h = engine.calculate_appliance_health_score(c, "CHIMNEY", dict(CHIMNEY_BASE, filter_condition="MODERATE_GREASE"),
                                                today=TODAY)
    assert h["score"] == 60


def test_service_interval_uses_intensity_health_and_history():
    base_args = dict(last_service_date="2026-09-30", health_score=95, health_status_="EXCELLENT",
                     repair_priority="MONITOR", today=TODAY)
    moderate = engine.calculate_next_service_date(C, "CHIMNEY", kitchen={"cooking_intensity": "MODERATE"}, **base_args)
    heavy = engine.calculate_next_service_date(C, "CHIMNEY", kitchen={"cooking_intensity": "HEAVY"}, **base_args)
    light = engine.calculate_next_service_date(C, "CHIMNEY", kitchen={"cooking_intensity": "LIGHT"}, **base_args)
    assert moderate["adjusted_service_interval_days"] == round(90 * 1.15)
    assert heavy["adjusted_service_interval_days"] == round(90 * 0.75 * 1.15)
    assert light["adjusted_service_interval_days"] == round(90 * 1.25 * 1.15)
    # Dishwasher is not intensity-sensitive
    dw = engine.calculate_next_service_date(C, "DISHWASHER", kitchen={"cooking_intensity": "HEAVY"}, **base_args)
    assert dw["adjusted_service_interval_days"] == round(120 * 1.15)
    # Score drop + repairs + previous interval all shorten
    hist = engine.calculate_next_service_date(C, "CHIMNEY", kitchen={"cooking_intensity": "MODERATE"},
                                              history={"previous_score": 110, "repairs_12m": 2,
                                                       "previous_interval_days": 60}, **base_args)
    expected = round((90 * 1.15 * 0.85 * 0.85) * 0.75 + 60 * 0.25)
    assert hist["adjusted_service_interval_days"] == expected
    assert len(hist["factors"]) == 4
    manu = engine.calculate_next_service_date(C, "OVEN", appliance={"manufacturer_interval_days": 120}, **base_args)
    assert manu["base_service_interval_days"] == 120


def test_service_history_component():
    assert engine.service_history_fraction({}, 90, TODAY) == 0.5
    assert engine.service_history_fraction({"last_service_date": "2026-08-01"}, 90, TODAY) == 1.0
    assert engine.service_history_fraction({"last_service_date": "2026-04-15"}, 90, TODAY) == 0.4
    assert engine.service_history_fraction({"last_service_date": "2026-03-01"}, 90, TODAY) == 0.2
    assert engine.service_history_fraction({"last_service_date": "2026-08-01", "repairs_12m": 3}, 90, TODAY) == 0.8


def test_kitchen_score_weighted_spec_example():
    apps = [("CHIMNEY", 88), ("HOB", 94), ("DISHWASHER", 76), ("OVEN", 82), ("REFRIGERATOR", 85)]
    k = engine.calculate_kitchen_health_score(C, [
        {"appliance_id": c, "category": c, "score": s, "priority": "MONITOR", "action": "x", "label": c} for c, s in apps],
        previous_score=78)
    # 88*.30 + 94*.20 + 76*.20 + 82*.15 + 85*.15 = 85.45
    assert k["overall_score"] == 85
    assert k["score_status"] == "HEALTHY"
    assert k["score_change_from_previous"] == 7
    assert k["lowest_scoring_appliance"]["appliance_id"] == "DISHWASHER"


def test_kitchen_score_renormalises_missing_categories_and_picks_priority():
    k = engine.calculate_kitchen_health_score(C, [
        {"appliance_id": "a", "category": "CHIMNEY", "score": 90, "priority": "MONITOR", "action": "none"},
        {"appliance_id": "b", "category": "HOB", "score": 60, "priority": "EMERGENCY", "action": "gas leak"}])
    assert k["overall_score"] == round((90 * 30 + 60 * 20) / 50)
    assert k["highest_priority_action"]["action"] == "gas leak"


def test_before_after_and_timeline():
    c = engine.generate_before_after_comparison("Chimney", 64, 89)
    assert c["improvement"] == 25
    assert c["message"] == "Your Chimney Health improved by 25 points."
    tl = engine.generate_health_timeline([{"date": "2026-09-01", "score": 86}, {"date": "2025-12-01", "score": 91},
                                          {"date": "2026-06-01", "score": 78}, {"date": "2026-03-01", "score": 83}])
    assert [(t["score"], t["change"]) for t in tl] == [(86, 8), (78, -5), (83, -8), (91, None)]


def test_ai_summary_trend_grounded_in_data():
    comps = lambda f: [{"key": "filter", "label": "Filter / Grease", "fraction": f},
                       {"key": "suction", "label": "Suction / Performance", "fraction": f}]
    ins = [{"date": d, "score": s, "components": comps(f), "safety_status": "NORMAL"}
           for d, s, f in [("2025-12-01", 95, 1.0), ("2026-03-01", 91, .9), ("2026-06-01", 86, .7), ("2026-09-01", 78, .5)]]
    out = engine.generate_ai_health_summary(C, "Kitchen Chimney", "CHIMNEY", ins)
    assert out["trend"] == "declining"
    assert "declined over the last 3 inspections" in " ".join(out["observed_data"])
    assert "filter / grease" in " ".join(out["observed_data"])
    assert "Book kitchen chimney inspection" in out["recommended_action"]
    empty = engine.generate_ai_health_summary(C, "Oven", "OVEN", [])
    assert "safety cannot be assessed" in empty["disclaimer"]
