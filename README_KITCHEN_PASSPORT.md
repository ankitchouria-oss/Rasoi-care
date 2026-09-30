# Kitchen Passport & Kitchen Health Score (Rasoi Care)

Every customer gets a permanent digital **Kitchen Passport** (`RC-KP-00000128`). It holds their kitchen, appliance registry
(`RC-CH-000128`, `RC-HB-…`, `RC-DW-…`, `RC-OV-…`, `RC-MW-…`, `RC-RF-…`), inspections, measurements, before/after photos,
service, repair and parts history, warranties, and a health timeline.

Technicians never type a health score. They enter inspection values, and the engines calculate **four separate
indicators** for every appliance:

| Indicator | Example | Engine |
|---|---|---|
| **HEALTH** | 88/100 — Healthy | weighted inspection parameters → `calculate_appliance_health_score` |
| **SAFETY** | Normal / ATTENTION REQUIRED / CRITICAL | rules on raw values + technician findings → `calculate_safety_status` |
| **SERVICE** | 42 days remaining / Overdue by 12 days | personalised interval → `calculate_next_service_date`, `calculate_days_remaining` |
| **ACTION** | Preventive maintenance recommended | `calculate_repair_priority` + `generate_recommendations` |

Safety is calculated separately from health, so a high score never hides a critical problem. For example, a hob with a
suspected gas leak shows `Health 90/100 · Safety CRITICAL · Priority EMERGENCY`.

## Run it

```bash
pip install -r requirements-dev.txt
python -m kitchen_passport.seed      # optional demo data (idempotent)
python app.py                        # http://127.0.0.1:8420/kitchen-passport
pytest                               # full suite (engine + API + existing app tests)
```

`KP_TODAY=2026-09-30 python app.py` pins "today" for demos. Postgres works the same way as the rest of the app
(set `DATABASE_URL`).

Demo logins (after seeding):

| Role | Login |
|---|---|
| Customer (5 appliances, 4-visit history) | `ankit@rasoicare.demo` / `demo1234` |
| Customer (hob gas leak: CRITICAL) | `meera@rasoicare.demo` / `demo1234` |
| Technician | phone `9822000099` / PIN `4321` |
| Admin owner | phone `9822000001` / PIN `1234` (the existing staff seed, `STAFF_SEED_OWNER_PIN`) |

## Layout

```
kitchen_passport/
  config.py   DEFAULT_CONFIG: categories, parameters, weights, thresholds, intervals,
              safety rules, recommendation rules, priority rules, notification rules
  engine.py   pure scoring/safety/priority/service/recommendation/timeline/AI functions
  schema.py   relational schema (kp_* tables, SQLite + Postgres)
  store.py    persistence + orchestration (record inspection, complete service, dashboard,
              passport, report, timeline, rescore, notifications)
  routes.py   Flask blueprint /api/kp/* with role-based access
  seed.py     demo customers, technician and history
  sql/supabase_rls.sql   Row Level Security policies for a Supabase deployment
kitchen_passport.html    customer / technician / admin UI (served at /kitchen-passport)
tests/test_kitchen_passport_engine.py, tests/test_kitchen_passport_api.py
```

All scoring logic lives in `engine.py`. Screens and API routes only display what it returns, so no scoring logic is
duplicated. The specification's function names are exported as aliases (`calculateApplianceHealthScore`, …).
`generateHealthReport` and `generateKitchenPassport` are `store.generate_health_report` and
`store.generate_kitchen_passport`.

## Scoring

Each category is a list of **parameters** (typed: enum with per-option fractions, number, bool, text) and weighted
**components**:

```
component fraction ∈ [0,1]  →  score = round( Σ weight·fraction / Σ weight · 100 )
```

Components without applicable data (for example, the electrical connection on a gas hob) are dropped and the remaining
weights are renormalised to 100. This is also how Microwave and Refrigerator are normalised.

| Category | Components (weights) |
|---|---|
| Chimney | Suction 25 · Filter 15 · Motor 10 · Noise 10 · Duct 10 · Electrical 10 · Physical 5 · Service history 5 · Grease 5 · Technician 5 |
| Hob | Burner perf 20 · Flame 15 · Ignition 10 · Gas/Electrical 15 · Burner cond 10 · Knobs 5 · Pan supports 5 · Glass 5 · Safety 10 · Cleaning 5 |
| Dishwasher | Washing 15 · Drainage 15 · Spray arms 10 · Filter 10 · Inlet 10 · Leakage 10 · Drying 10 · Door seal 5 · Odour 5 · Noise 5 · Service history 5 |
| Oven | Heating 20 · Temp consistency 15 · Element 10 · Fan 10 · Door seal 10 · Electrical 10 · Interior 5 · Control 5 · Door 5 · Cleaning 5 · Service history 5 |
| Microwave / Refrigerator | see `config.py` (phase 2, totals 100) |

The engine calculates derived measurements itself. The technician does not enter them:

- `suction_percentage = measured / rated × 100`
- oven `temperature_difference = |measured − set|` and `temperature_overshoot = measured − set`
- fridge `temperature_deviation = |measured − 4 °C|`

The **service-history** component is derived from the appliance's own history: time since the last service relative to
the interval, and repairs in the last 12 months.

Worked example from the specification: heavy grease, suction 78%, and moderate duct restriction score **78/100**, with
priority **MEDIUM**, action within **30 days**, and the recommendations *Chimney deep cleaning · Filter maintenance ·
Airflow inspection*. This case is asserted in the tests.

### Status thresholds

- Score: 90+ EXCELLENT, 80+ HEALTHY, 70+ MONITOR, 50+ ATTENTION_REQUIRED, otherwise CRITICAL.
- Service countdown: more than 30 days NOT_DUE, 15–30 APPROACHING, 1–14 DUE_SOON, 0 DUE, negative OVERDUE.

Both threshold sets are configurable.

### Repair priority (first match wins)

1. **EMERGENCY**: critical safety.
2. **HIGH**: a malfunction value (for example `MOTOR_REPLACEMENT_REQUIRED`, drain `BLOCKED`), a score below 50, or a
   key-performance component at 0.2 or below.
3. **MEDIUM**: safety attention required, a score below 70, or a key-performance component below 0.75.
4. **LOW**: a score below 80 or any component below 0.5.
5. **PREVENTIVE**: a score below 90 or safety MONITOR.
6. **MONITOR**: none of the above.

### Service due engine

Starting interval: the category base, or the manufacturer interval when one is recorded. It is then adjusted:

- × cooking intensity (LIGHT 1.25, MODERATE 1.0, HEAVY 0.75), for chimney, hob and oven only
- × high daily cooking hours
- × current health status factor
- × score drop since the previous inspection
- × repairs in the last 12 months
- × appliance age
- blended with the customer's previous interval

The result is clamped to 7–365 days, then capped by repair priority (EMERGENCY 1, HIGH 7, MEDIUM 30, LOW 60 days).
Every adjustment is stored in `kp_service_schedules.factors_json` and shown under *View Full Inspection*.

`days_remaining` is recalculated from the stored `recommended_service_date` on every read, so the countdown is always
current. When the date has passed, the appliance shows `overdue_days`.

## Technician workflow (UI → API)

| Step | Action | API |
|---|---|---|
| 1 | Scan passport QR (camera via `BarcodeDetector`, or type the ID) | `POST /api/kp/tech/scan` |
| 2 | Select appliance | `POST /api/kp/tech/jobs/<job>/services` |
| 3–5 | Checklist and measurements, with a live calculation preview | `POST /api/kp/tech/evaluate` (nothing is saved) |
| 3–5 | Save the before-service inspection | `POST /api/kp/tech/services/<sid>/inspections {phase: BEFORE}` |
| 6 / 8 | Before and after photos | `POST /api/kp/tech/services/<sid>/photos` (JPEG/PNG/WebP, magic bytes checked) |
| 7 | Perform the service, then record the after inspection (`phase: AFTER`) | `POST /api/kp/tech/services/<sid>/inspections` |
| 9–10 | Parts, observations and labour | — |
| 11–14 | Health, safety, priority and next service date are calculated server-side for each inspection | — |
| 15 | Customer approves the service | `POST /api/kp/me/services/<sid>/approve` |
| 16–17 | Service is completed: before/after comparison, invoice, kitchen score, timeline point and notifications | `POST /api/kp/tech/services/<sid>/complete` |

A CRITICAL finding immediately queues notifications through the channels in `notifications.on_safety_critical`
(app, SMS, WhatsApp). The in-app message is delivered straight away. SMS and WhatsApp stay `QUEUED` until a provider is
integrated in phase 3.

## Other endpoints

| Area | Endpoints |
|---|---|
| Customer | `GET /api/kp/me/passport` (created on first open), `PATCH /api/kp/me/profile`, `POST/PATCH /api/kp/me/kitchens[/<id>]`, `POST /api/kp/me/kitchens/<id>/appliances`, `GET /api/kp/me/notifications` |
| Shared (role-checked) | `GET /api/kp/kitchens/<id>/dashboard`, `…/timeline`, `…/report[?service_id=]`, `GET /api/kp/appliances/<id>`, `POST /api/kp/appliances/<id>/ai-summary`, `GET /api/kp/inspections/<id>`, `GET /api/kp/services/<id>`, `GET /api/kp/photos/<id>` |
| Technician | `POST /api/kp/tech/login`, `GET /api/kp/tech/jobs?date=` |
| Staff | `GET /api/kp/admin/passports[/<id>]`, `GET/POST /api/kp/admin/jobs`, `GET /api/kp/admin/technicians`, `GET /api/kp/admin/config` |
| Owner only | `PUT/DELETE /api/kp/admin/config/<section>`, `POST /api/kp/admin/technicians/<id>/pin`, `POST /api/kp/admin/inspections/<id>/rescore` |
| Public (no customer data) | `GET /api/kp/config/public`: the parameter schema for the forms |

## Configuration

`GET /api/kp/admin/config` returns the merged config, and the admin UI's *Configuration* tab edits it. The editable
sections are:

- `score_thresholds`
- `countdown_thresholds`
- `kitchen_weights`
- `service_intervals`
- `repair_priority`
- `safety` (global rules)
- `notifications`
- `category:<CODE>` (weights, base interval, safety rules, recommendations, parameters, and new categories)

Every save is validated, stored in `kp_config`, and logged in `kp_config_history`. Each save also bumps
`algorithm_version`, which is stored with every calculated score.

Raw inspection values are stored one row per parameter in `kp_inspection_measurements`, with typed columns and the
parameter schema version. This means any inspection can be re-scored under a new algorithm
(`/admin/inspections/<id>/rescore`) without losing the original data. New categories are added by config alone:
`kp_appliance_categories` and `kp_inspection_parameters` are kept in sync automatically.

## Security

- Identity always comes from a verified token signature plus a database row:
  - customers: backend JWT
  - technicians: Firebase ID token, or a Kitchen Passport PIN JWT with `typ=kp_tech`
  - staff: staff JWT

  Editable user metadata is never used for authorisation.
- Customers reach only their own passport. Technicians reach only kitchens where they hold an `ASSIGNED` or
  `IN_PROGRESS` job, and lose access when the job completes. Staff have read access. Config and PIN changes need the
  owner role.
- "Not yours" returns 404, so IDs can't be probed.
- The QR code encodes only `RCKP:<passport_id>:<random token>`. Scanning reveals nothing without an authenticated,
  job-holding technician, and a forged token is rejected (constant-time compare). Latitude and longitude are never
  returned by the API.
- Photos are stored privately and served only through the authorised `/api/kp/photos/<id>` route, with
  `Cache-Control: private, no-store`. There is no public URL.
- Technician PIN login is behind the app's existing brute-force backoff (`_auth_gate`). Every authenticated route is
  rate-limited.
- For a Supabase deployment, `kitchen_passport/sql/supabase_rls.sql` enables RLS on every `kp_*` table with equivalent
  policies. Roles come from a server-managed `kp_app_roles` table, not user metadata, and the service-role key must stay
  server-side.

## AI-ready data (phase 5)

`generate_ai_health_summary` is deterministic and grounded in the data. It reads only the stored inspections (one per
visit, using the arrival condition), detects trends (for example chimney 98 → 97 → 88 → 78 is reported as "declined
over the last 3 inspections"), names the components that got worse, and returns **OBSERVED DATA / POSSIBLE CAUSES /
RECOMMENDED ACTION**. When there is no inspection it says safety cannot be assessed.

Outputs are stored in `kp_ai_assessments` with a model tag (`rules-v1`). An LLM can later rephrase these facts, but it
must only be given this structured data so that it cannot invent measurements. Photo AI (preliminary visual
assessment) will attach to `kp_photos` and `kp_ai_assessments` in phase 5.

## Phases

| Phase | Scope | Status |
|---|---|---|
| MVP | Items 1–18 of the specification | Done |
| 2 | Microwave and Refrigerator models | Already included in the engine |
| 3 | WhatsApp/SMS | Notifications are queued with channel rules; needs a provider integration |
| 4 | Membership/AMC | `membership_status` and `amc_status` fields exist |
| 5–6 | AI and predictive maintenance | Data model is ready; rule-based summary shipped |
