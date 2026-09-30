"""
Kitchen Passport engines — pure functions, no database or Flask access.

Every screen, API route, report and test goes through these functions,
so scoring logic exists in exactly one place. All functions take the
active `config` (see config.DEFAULT_CONFIG) and, where time matters, an
explicit `today` so results are deterministic and testable.

Spec name → function:
  calculateApplianceHealthScore  calculate_appliance_health_score
  calculateKitchenHealthScore    calculate_kitchen_health_score
  calculateSafetyStatus          calculate_safety_status
  calculateRepairPriority        calculate_repair_priority
  calculateNextServiceDate       calculate_next_service_date
  calculateDaysRemaining         calculate_days_remaining
  generateRecommendations        generate_recommendations
  generateBeforeAfterComparison  generate_before_after_comparison
  generateHealthTimeline         generate_health_timeline
  generateAIHealthSummary        generate_ai_health_summary
  evaluateInspection             evaluate_inspection (runs all of the above
                                 for one appliance inspection)
generateHealthReport and generateKitchenPassport assemble stored data and
live in store.py.
"""

from datetime import date, timedelta

SAFETY_ORDER = ["NORMAL", "MONITOR", "ATTENTION_REQUIRED", "CRITICAL"]
PRIORITY_ORDER = ["MONITOR", "PREVENTIVE", "LOW", "MEDIUM", "HIGH", "EMERGENCY"]


class InspectionError(ValueError):
    """Raised when inspection data is missing or invalid. `fields` maps
    param key → problem so the technician UI can highlight them."""

    def __init__(self, fields):
        super().__init__("Invalid inspection data: " + ", ".join(f"{k} {v}" for k, v in fields.items()))
        self.fields = fields


def _to_date(value):
    if value is None or value == "":
        return None
    if isinstance(value, date):
        return value
    return date.fromisoformat(str(value)[:10])


def get_category(config, category):
    cat = config["categories"].get(category)
    if not cat:
        raise InspectionError({"category": f"unknown category {category!r}"})
    return cat


# ================================================================ validation
def validate_inspection(config, category, values):
    """Coerces raw technician input to typed values, checks required
    params and enum options. Returns a clean dict (unknown keys dropped)."""
    cat = get_category(config, category)
    clean, errors = {}, {}
    for p in cat["params"]:
        key = p["key"]
        raw = values.get(key)
        if raw is None or (isinstance(raw, str) and raw.strip() == ""):
            if p["required"]:
                errors[key] = "is required"
            continue
        if p["type"] == "enum":
            v = str(raw).strip().upper()
            if v not in p["options"]:
                errors[key] = f"must be one of {', '.join(p['options'])}"
                continue
            clean[key] = v
        elif p["type"] == "number":
            try:
                v = float(raw)
            except (TypeError, ValueError):
                errors[key] = "must be a number"
                continue
            if v < 0 or v != v:
                errors[key] = "must be zero or positive"
                continue
            clean[key] = v
        elif p["type"] == "bool":
            if isinstance(raw, bool):
                clean[key] = raw
            elif str(raw).strip().lower() in ("true", "yes", "1"):
                clean[key] = True
            elif str(raw).strip().lower() in ("false", "no", "0"):
                clean[key] = False
            else:
                errors[key] = "must be true or false"
        else:
            clean[key] = str(raw).strip()[:500]
    if category == "CHIMNEY" and clean.get("rated_suction") == 0:
        errors["rated_suction"] = "must be greater than zero"
    if errors:
        raise InspectionError(errors)
    return clean


def derive_values(category, values):
    """Adds calculated measurements (never technician-entered)."""
    out = dict(values)
    if category == "CHIMNEY" and out.get("rated_suction"):
        out["suction_percentage"] = round(out["measured_suction"] / out["rated_suction"] * 100, 1)
    if category == "OVEN" and "set_temperature" in out and "measured_temperature" in out:
        out["temperature_difference"] = round(abs(out["measured_temperature"] - out["set_temperature"]), 1)
        out["temperature_overshoot"] = round(out["measured_temperature"] - out["set_temperature"], 1)
    if category == "REFRIGERATOR" and "measured_fridge_temperature" in out:
        out["temperature_deviation"] = round(abs(out["measured_fridge_temperature"] - 4.0), 1)
    return out


# ================================================================ scoring
def service_history_fraction(history, base_interval_days, today):
    """Score component derived from the appliance's own history.
    history: {"last_service_date", "repairs_12m"}."""
    history = history or {}
    last = _to_date(history.get("last_service_date"))
    if last is None:
        fraction = 0.5
    else:
        ratio = (today - last).days / max(1, base_interval_days)
        if ratio <= 1.0:
            fraction = 1.0
        elif ratio <= 1.25:
            fraction = 0.8
        elif ratio <= 1.5:
            fraction = 0.6
        elif ratio <= 2.0:
            fraction = 0.4
        else:
            fraction = 0.2
    extra_repairs = max(0, int(history.get("repairs_12m") or 0) - 1)
    return max(0.0, round(fraction - 0.1 * extra_repairs, 3))


def _band(value, bands, direction):
    for threshold, fraction in bands:
        if direction == "lower_better":
            if value <= threshold:
                return fraction
        elif value >= threshold:
            return fraction
    return bands[-1][1]


def _score_scorer(scorer, cat, values, ctx):
    """Returns a fraction 0..1, or None when nothing applicable was
    measured (e.g. optional param absent / NOT_APPLICABLE)."""
    t = scorer["type"]
    params = {p["key"]: p for p in cat["params"]}
    if t == "enum":
        fr = []
        for key in scorer["params"]:
            if key in values:
                f = params[key]["options"].get(values[key])
                if f is not None:
                    fr.append(f)
        if not fr:
            return None
        return min(fr) if scorer.get("combine") == "min" else sum(fr) / len(fr)
    if t == "bool_bad":
        fr = [0.0 if values[k] else 1.0 for k in scorer["params"] if k in values]
        return sum(fr) / len(fr) if fr else None
    if t == "band":
        if scorer["param"] not in values:
            return None
        return _band(values[scorer["param"]], scorer["bands"], scorer.get("direction", "higher_better"))
    if t == "mixed":
        fr = [f for f in (_score_scorer(s, cat, values, ctx) for s in scorer["scorers"]) if f is not None]
        return sum(fr) / len(fr) if fr else None
    if t == "service_history":
        return service_history_fraction(ctx.get("history"), cat["base_service_interval_days"], ctx["today"])
    raise ValueError(f"unknown scorer type {t}")


def score_status(config, score):
    for band in config["score_thresholds"]:
        if score >= band["min"]:
            return band["status"]
    return config["score_thresholds"][-1]["status"]


def status_label(config, status):
    for band in config["score_thresholds"]:
        if band["status"] == status:
            return band["label"]
    return status.replace("_", " ").title()


def calculate_appliance_health_score(config, category, raw_values, history=None, today=None):
    """0-100 score from weighted inspection parameters. Returns
    {score, status, components:[...], values (validated + derived)}.
    Components with no applicable data are dropped and the remaining
    weights renormalised to 100."""
    today = today or date.today()
    cat = get_category(config, category)
    values = derive_values(category, validate_inspection(config, category, raw_values))
    ctx = {"history": history, "today": today}
    components, total_w, earned = [], 0.0, 0.0
    for c in cat["components"]:
        f = _score_scorer(c["scorer"], cat, values, ctx)
        if f is None:
            continue
        f = max(0.0, min(1.0, f))
        total_w += c["weight"]
        earned += c["weight"] * f
        components.append({
            "key": c["key"], "label": c["label"], "weight": c["weight"], "fraction": round(f, 3),
            "points": round(c["weight"] * f, 2), "key_performance": c.get("key_performance", False),
        })
    if total_w == 0:
        raise InspectionError({"inspection": "no scorable parameters"})
    score = int(round(earned / total_w * 100))
    for comp in components:
        comp["normalized_max"] = round(comp["weight"] / total_w * 100, 2)
    return {"score": score, "status": score_status(config, score), "components": components, "values": values}


# ================================================================ safety
def _rule_matches(rule, values):
    v = values.get(rule["param"])
    op = rule["op"]
    if op == "true":
        return v is True
    if v is None:
        return False
    if op == "eq":
        return v == rule["value"]
    if op == "in":
        return v in rule["value"]
    if op == "gt":
        return isinstance(v, (int, float)) and v > rule["value"]
    if op == "lt":
        return isinstance(v, (int, float)) and v < rule["value"]
    if op == "nonempty":
        return bool(str(v).strip())
    return False


def calculate_safety_status(config, category, values, technician_findings=None):
    """Independent of the health score. Returns {status, findings}.
    technician_findings: [{"level", "description"}] — technician-defined
    safety-critical conditions are always honoured."""
    cat = get_category(config, category)
    findings = []
    for r in list(cat.get("safety_rules", [])) + list(config["safety"].get("global_rules", [])):
        if _rule_matches(r, values):
            findings.append({"level": r["level"], "finding": r["finding"],
                             "customer_message": r["customer_message"], "param": r["param"],
                             "value": values.get(r["param"]), "source": "RULE"})
    for tf in technician_findings or []:
        level = str(tf.get("level", "")).upper()
        if level not in SAFETY_ORDER or level == "NORMAL":
            continue
        desc = str(tf.get("description", "")).strip()[:300] or "Technician-reported safety concern"
        findings.append({"level": level, "finding": desc, "customer_message": desc, "param": None,
                         "value": None, "source": "TECHNICIAN"})
    # A parameter matching both a CRITICAL and a lesser rule keeps only
    # the most severe entry, so the customer isn't shown both.
    best = {}
    for f in findings:
        k = (f["param"], f["source"], f["finding"] if f["param"] is None else None)
        if k not in best or SAFETY_ORDER.index(f["level"]) > SAFETY_ORDER.index(best[k]["level"]):
            best[k] = f
    findings = sorted(best.values(), key=lambda f: -SAFETY_ORDER.index(f["level"]))
    status = findings[0]["level"] if findings else "NORMAL"
    return {"status": status, "findings": findings}


# ================================================================ priority
def calculate_repair_priority(config, category, health, safety):
    """health = calculate_appliance_health_score result. Returns
    {priority, reason, recommended_within_days}."""
    rp = config["repair_priority"]
    cat = get_category(config, category)
    score = health["score"]
    comps = health["components"]
    malfunctions = [
        p["label"] for p in cat["params"]
        if p["type"] == "enum" and health["values"].get(p["key"]) in p.get("malfunction", [])
    ]
    keyp = [c for c in comps if c["key_performance"]]

    if safety["status"] == "CRITICAL":
        prio, reason = "EMERGENCY", "Critical safety issue"
    elif malfunctions:
        prio, reason = "HIGH", "Malfunction: " + ", ".join(malfunctions)
    elif score < rp["high_below_score"]:
        prio, reason = "HIGH", f"Health score {score} below {rp['high_below_score']}"
    elif any(c["fraction"] <= rp["high_component_fraction"] for c in keyp):
        c = min(keyp, key=lambda c: c["fraction"])
        prio, reason = "HIGH", f"Major performance failure: {c['label']}"
    elif safety["status"] == "ATTENTION_REQUIRED":
        prio, reason = "MEDIUM", "Safety attention required"
    elif score < rp["medium_below_score"]:
        prio, reason = "MEDIUM", f"Health score {score} below {rp['medium_below_score']}"
    elif any(c["fraction"] < rp["medium_component_fraction"] for c in keyp):
        c = min(keyp, key=lambda c: c["fraction"])
        prio, reason = "MEDIUM", f"Performance significantly reduced: {c['label']}"
    elif score < rp["low_below_score"] or any(c["fraction"] < rp["low_component_fraction"] for c in comps):
        prio, reason = "LOW", "Minor repair recommended"
    elif score < rp["preventive_below_score"] or safety["status"] == "MONITOR":
        prio, reason = "PREVENTIVE", "Routine maintenance"
    else:
        prio, reason = "MONITOR", "No immediate action required"
    return {"priority": prio, "reason": reason, "recommended_within_days": rp["recommended_within_days"].get(prio)}


# ================================================================ service due
def calculate_days_remaining(recommended_service_date, today=None):
    """Reusable countdown. Returns {days_remaining, overdue_days}."""
    today = today or date.today()
    d = _to_date(recommended_service_date)
    if d is None:
        return {"days_remaining": None, "overdue_days": 0}
    diff = (d - today).days
    return {"days_remaining": diff, "overdue_days": -diff if diff < 0 else 0}


def service_status(config, days_remaining):
    if days_remaining is None:
        return {"status": "NOT_SCHEDULED", "label": "Not scheduled", "color": "grey"}
    for band in config["countdown_thresholds"]:
        if days_remaining >= band["min"]:
            return {"status": band["status"], "label": band["label"], "color": band["color"]}
    last = config["countdown_thresholds"][-1]
    return {"status": last["status"], "label": last["label"], "color": last["color"]}


def calculate_next_service_date(config, category, *, last_service_date, health_score, health_status_,
                                repair_priority, kitchen=None, appliance=None, history=None, today=None):
    """Personalised interval from category base (or manufacturer
    recommendation), cooking intensity, usage, health, score trend,
    repair history, age and the customer's previous interval.
    Returns the stored service-schedule fields plus `factors` explaining
    every adjustment."""
    today = today or date.today()
    si = config["service_intervals"]
    cat = get_category(config, category)
    kitchen = kitchen or {}
    appliance = appliance or {}
    history = history or {}
    factors = []

    base = cat["base_service_interval_days"]
    if appliance.get("manufacturer_interval_days"):
        base = int(appliance["manufacturer_interval_days"])
        factors.append({"factor": "Manufacturer recommendation", "value": base})
    interval = float(base)

    if cat.get("intensity_sensitive"):
        f = si["cooking_intensity_factor"].get((kitchen.get("cooking_intensity") or "MODERATE").upper(), 1.0)
        if f != 1.0:
            interval *= f
            factors.append({"factor": f"Cooking intensity {kitchen.get('cooking_intensity')}", "multiplier": f})
        hours = kitchen.get("approximate_daily_cooking_hours")
        if hours is not None and float(hours) > si["daily_hours_threshold"]:
            interval *= si["daily_hours_factor"]
            factors.append({"factor": f"High usage ({hours} h/day)", "multiplier": si["daily_hours_factor"]})

    f = si["health_status_factor"].get(health_status_, 1.0)
    if f != 1.0:
        interval *= f
        factors.append({"factor": f"Current health {health_status_}", "multiplier": f})

    prev = history.get("previous_score")
    if prev is not None and prev - health_score >= si["score_drop_threshold"]:
        interval *= si["score_drop_factor"]
        factors.append({"factor": f"Score dropped {prev - health_score} pts since last inspection",
                        "multiplier": si["score_drop_factor"]})

    if int(history.get("repairs_12m") or 0) >= si["repairs_12m_threshold"]:
        interval *= si["repairs_factor"]
        factors.append({"factor": f"{history['repairs_12m']} repairs in 12 months", "multiplier": si["repairs_factor"]})

    age = appliance.get("appliance_age_years")
    if age is not None and age >= si["age_years_threshold"]:
        interval *= si["age_factor"]
        factors.append({"factor": f"Appliance age {age} years", "multiplier": si["age_factor"]})

    prev_interval = history.get("previous_interval_days")
    blend = si["previous_interval_blend"]
    if prev_interval and blend:
        interval = interval * (1 - blend) + float(prev_interval) * blend
        factors.append({"factor": f"Customer history (previous interval {prev_interval} d)", "blend": blend})

    interval = max(si["min_days"], min(si["max_days"], int(round(interval))))
    cap = si["priority_cap_days"].get(repair_priority)
    if cap is not None and interval > cap:
        interval = cap
        factors.append({"factor": f"Repair priority {repair_priority} caps interval", "cap_days": cap})

    last = _to_date(last_service_date) or today
    rec_date = last + timedelta(days=interval)
    cd = calculate_days_remaining(rec_date, today)
    st = service_status(config, cd["days_remaining"])
    return {
        "base_service_interval_days": base,
        "adjusted_service_interval_days": interval,
        "last_service_date": last.isoformat(),
        "recommended_service_date": rec_date.isoformat(),
        "days_remaining": cd["days_remaining"],
        "overdue_days": cd["overdue_days"],
        "service_status": st["status"],
        "service_status_label": st["label"],
        "service_color": st["color"],
        "factors": factors,
    }


# ================================================================ recommendations
def generate_recommendations(config, category, health, safety, priority):
    """Customer-friendly recommendations (plus the technical reason for
    the full-inspection view). Returns {items, action, priority,
    recommended_within_days}."""
    cat = get_category(config, category)
    comp_map = {c["key"]: c for c in health["components"]}
    items, seen = [], set()

    for f in safety["findings"]:
        if f["level"] == "CRITICAL":
            text_ = "Urgent safety repair" if f["source"] == "RULE" else "Urgent safety inspection"
            if text_ not in seen:
                seen.add(text_)
                items.append({"text": text_, "technical": f["finding"], "urgent": True})

    for r in cat.get("recommendations", []):
        w = r["when"]
        if "component" in w:
            c = comp_map.get(w["component"])
            hit = c is not None and c["fraction"] < w["below"]
        else:
            hit = _rule_matches(w, health["values"])
        if hit and r["text"] not in seen:
            seen.add(r["text"])
            items.append({"text": r["text"], "technical": r["technical"], "urgent": False})

    if any(f["level"] == "ATTENTION_REQUIRED" for f in safety["findings"]) and "Electrical inspection" not in seen \
            and any("lectric" in f["finding"] for f in safety["findings"]):
        items.append({"text": "Electrical inspection", "technical": "Safety attention: electrical", "urgent": False})
        seen.add("Electrical inspection")

    if not items:
        label = "Routine preventive maintenance" if priority["priority"] != "MONITOR" else "No action needed — keep up regular use and cleaning"
        items.append({"text": label, "technical": priority["reason"], "urgent": False})

    rp = config["repair_priority"]
    action = rp["action_text"][priority["priority"]]
    if priority["priority"] == "EMERGENCY":
        action = safety["findings"][0]["customer_message"] if safety["findings"] else action
    elif priority["priority"] in ("HIGH", "MEDIUM", "LOW") and items:
        action = items[0]["text"] + (" recommended" if priority["priority"] != "HIGH" else " required")
    return {"items": items, "action": action, "priority": priority["priority"],
            "recommended_within_days": priority["recommended_within_days"]}


# ================================================================ one-shot
def evaluate_inspection(config, category, raw_values, *, history=None, kitchen=None, appliance=None,
                        technician_findings=None, last_service_date=None, today=None):
    """Steps 11–14 of the technician workflow in one call: health →
    safety → priority → next service date → recommendations. Every
    number shown anywhere in the app comes from this function."""
    today = today or date.today()
    health = calculate_appliance_health_score(config, category, raw_values, history=history, today=today)
    safety = calculate_safety_status(config, category, health["values"], technician_findings)
    priority = calculate_repair_priority(config, category, health, safety)
    schedule = calculate_next_service_date(
        config, category, last_service_date=last_service_date or today, health_score=health["score"],
        health_status_=health["status"], repair_priority=priority["priority"], kitchen=kitchen,
        appliance=appliance, history=history, today=today)
    recs = generate_recommendations(config, category, health, safety, priority)
    return {
        "algorithm_version": config["algorithm_version"],
        "category": category,
        "health": health,
        "safety": safety,
        "priority": priority,
        "schedule": schedule,
        "recommendations": recs,
    }


def four_indicators(config, *, score, status, safety_status, days_remaining, overdue_days, service_state, action,
                    priority):
    """The four independent indicators every appliance card shows."""
    if days_remaining is None:
        service_text = "Not scheduled"
    elif days_remaining < 0:
        service_text = f"Overdue by {overdue_days} day{'s' if overdue_days != 1 else ''}"
    elif days_remaining == 0:
        service_text = "Due today"
    else:
        service_text = f"{days_remaining} day{'s' if days_remaining != 1 else ''} remaining"
    return {
        "health": {"score": score, "status": status, "label": status_label(config, status) if status else None,
                   "text": f"{score}/100 — {status_label(config, status)}" if score is not None else "Not inspected"},
        "safety": {"status": safety_status, "label": (safety_status or "UNKNOWN").replace("_", " ").title(),
                   "text": "ATTENTION REQUIRED" if safety_status == "ATTENTION_REQUIRED" else (safety_status or "Not inspected").title()},
        "service": {"days_remaining": days_remaining, "overdue_days": overdue_days, "status": service_state,
                    "text": service_text},
        "action": {"text": action, "priority": priority},
    }


# ================================================================ kitchen
def calculate_kitchen_health_score(config, appliance_scores, previous_score=None):
    """appliance_scores: [{appliance_id, category, score, priority, action,
    label}] (latest score per appliance). Weighted by
    config.kitchen_weights, renormalised over categories present;
    several appliances in one category share that category's weight."""
    scored = [a for a in appliance_scores if a.get("score") is not None]
    if not scored:
        return {"overall_score": None, "score_status": None, "score_change_from_previous": None,
                "lowest_scoring_appliance": None, "highest_priority_action": None, "weights_used": {}}
    weights = config["kitchen_weights"]
    by_cat = {}
    for a in scored:
        by_cat.setdefault(a["category"], []).append(a["score"])
    total_w = sum(weights.get(c, 10) for c in by_cat)
    overall = sum(weights.get(c, 10) * (sum(s) / len(s)) for c, s in by_cat.items()) / total_w
    overall = int(round(overall))
    lowest = min(scored, key=lambda a: a["score"])
    top = max(scored, key=lambda a: (PRIORITY_ORDER.index(a.get("priority") or "MONITOR"), -a["score"]))
    return {
        "overall_score": overall,
        "score_status": score_status(config, overall),
        "score_change_from_previous": (overall - previous_score) if previous_score is not None else None,
        "lowest_scoring_appliance": {"appliance_id": lowest["appliance_id"], "label": lowest.get("label"),
                                     "score": lowest["score"]},
        "highest_priority_action": {"appliance_id": top["appliance_id"], "label": top.get("label"),
                                    "priority": top.get("priority"), "action": top.get("action")},
        "weights_used": {c: round(weights.get(c, 10) / total_w * 100, 1) for c in by_cat},
    }


# ================================================================ before / after
def generate_before_after_comparison(label, before_score, after_score):
    if before_score is None or after_score is None:
        return None
    diff = after_score - before_score
    if diff > 0:
        msg = f"Your {label} Health improved by {diff} point{'s' if diff != 1 else ''}."
    elif diff < 0:
        msg = f"Your {label} Health changed by {diff} points."
    else:
        msg = f"Your {label} Health is unchanged."
    return {"before": before_score, "after": after_score, "improvement": diff, "message": msg}


# ================================================================ timeline
def generate_health_timeline(snapshots):
    """snapshots: [{date, score, ...}] any order → newest first with
    change from the previous (older) entry."""
    ordered = sorted(snapshots, key=lambda s: s["date"])
    out, prev = [], None
    for s in ordered:
        item = dict(s)
        item["change"] = (s["score"] - prev) if (prev is not None and s["score"] is not None) else None
        if s["score"] is not None:
            prev = s["score"]
        out.append(item)
    return list(reversed(out))


# ================================================================ AI summary (rule-based, data-grounded)
def detect_trend(scores, min_points=3):
    """scores oldest → newest. 'declining' when each of the last
    `min_points` inspections is lower than the one before."""
    if len(scores) < min_points:
        return "insufficient_data"
    tail = scores[-min_points:]
    if all(b < a for a, b in zip(tail, tail[1:])):
        return "declining"
    if all(b > a for a, b in zip(tail, tail[1:])):
        return "improving"
    return "stable"


def generate_ai_health_summary(config, label, category, inspections):
    """Grounded summary for one appliance from its stored inspections
    (oldest → newest: [{date, score, components:[{key,label,fraction}],
    safety_status}]). Only states what the data shows — it never invents
    a measurement and never calls an appliance safe without a recorded
    inspection. Output sections: observed_data, possible_causes,
    recommended_action. An LLM can later rephrase this, but must be
    given only these facts."""
    if not inspections:
        return {
            "observed_data": [f"No inspection has been recorded for this {label.lower()} yet."],
            "possible_causes": [],
            "recommended_action": [f"Book a {label.lower()} inspection to establish a baseline."],
            "trend": "insufficient_data",
            "disclaimer": "No inspection data — safety cannot be assessed.",
        }
    scores = [i["score"] for i in inspections]
    trend = detect_trend(scores)
    observed = [f"Health score history: {' → '.join(str(s) for s in scores)}."]
    causes, actions = [], []
    if trend == "declining":
        n = 0
        while n < len(scores) - 1 and scores[-1 - n] < scores[-2 - n]:
            n += 1
        observed.append(f"Health score has declined over the last {n} inspections.")
    elif trend == "improving":
        observed.append("Health score has improved over recent inspections.")
    first, last = inspections[0], inspections[-1]
    if len(inspections) >= 2:
        f0 = {c["key"]: c for c in first.get("components", [])}
        worsened = []
        for c in last.get("components", []):
            if c["key"] in f0 and c["key"] != "service_history" and c["fraction"] < f0[c["key"]]["fraction"] - 0.1:
                worsened.append(c["label"])
        if worsened:
            observed.append("Recorded inspection data indicates declining " + ", ".join(w.lower() for w in worsened) + ".")
            causes.extend(f"Wear or build-up affecting {w.lower()}" for w in worsened)
    weak = [c["label"] for c in last.get("components", []) if c["fraction"] < 0.6 and c["key"] != "service_history"]
    if weak:
        observed.append("Latest inspection shows weak areas: " + ", ".join(weak) + ".")
    if last.get("safety_status") and last["safety_status"] != "NORMAL":
        observed.append(f"Latest recorded safety status: {last['safety_status'].replace('_', ' ')}.")
        actions.append("Follow the safety recommendation from your last inspection before continued use.")
    if trend == "declining" or weak:
        actions.append(f"Book {label.lower()} inspection")
    if not actions:
        actions.append("Continue routine maintenance at the recommended service date.")
    return {
        "observed_data": observed,
        "possible_causes": causes or ["No specific cause can be inferred from recorded data."],
        "recommended_action": actions,
        "trend": trend,
        "disclaimer": f"Based only on recorded inspections (latest {last['date']}). "
                      "This is not a substitute for a physical inspection.",
    }


# camelCase aliases matching the specification's function names
calculateApplianceHealthScore = calculate_appliance_health_score
calculateKitchenHealthScore = calculate_kitchen_health_score
calculateSafetyStatus = calculate_safety_status
calculateRepairPriority = calculate_repair_priority
calculateNextServiceDate = calculate_next_service_date
calculateDaysRemaining = calculate_days_remaining
generateRecommendations = generate_recommendations
generateBeforeAfterComparison = generate_before_after_comparison
generateHealthTimeline = generate_health_timeline
generateAIHealthSummary = generate_ai_health_summary
