# Rasoi Care — Project Audit

_Date: 2026-10-11 · Branch audited: `claude/quirky-faraday-xb3o7f`_

## 1. Test results

| Check | Result |
|---|---|
| `pytest` (backend, 11 test files) | **59 passed, 0 failed** (22.9 s) |
| Line coverage | `app.py` **54%** (980/2123 lines missed), `database.py` **77%**, total **57%** |
| Warnings | 243 × `DeprecationWarning: datetime.utcnow()` (`database.py:407`) |
| `pip-audit` | **pyjwt 2.13.0 — 8 advisories** (PYSEC-2026-4140/4141/4142/4147/4148/4150/4151/4183); fixed in 2.14.0 / **2.15.0** |
| `bandit -ll` | 12 Medium hits — all reviewed, none exploitable (see §3.4) |
| Flutter (`flutter analyze` / `flutter test`) | **Not run** — no Flutter SDK in the audit container. Only `careplus_flutter` has tests (1 screenshot test); the other 5 apps have none. |

Reproduce:
```bash
python -m venv .venv && .venv/bin/pip install -r requirements-dev.txt pytest-cov pip-audit bandit
.venv/bin/pytest -q --cov=app --cov=database
.venv/bin/pip-audit -r requirements.txt
.venv/bin/bandit -q -ll app.py database.py
```

## 2. Project inventory

| Component | Tech | Size |
|---|---|---|
| Backend API | Flask + gunicorn, SQLite or Postgres (`DATABASE_URL`) | `app.py` 4,640 lines, `database.py` 918 lines, ~90 routes |
| Web front-ends | Single-file HTML/JS (`admin`, `customer`, `technician`, `homeservices`, `smiler`, `index`) | ~4,800 lines |
| Mobile apps | Flutter + Riverpod + Firebase: `careplus_flutter` (customer), `careplus_partner` (technician), `careplus_admin` | |
| WebView wrappers | `rasoi_web_customer/partner/admin` (Flutter) | |
| CI | `build-apks.yml` (release APKs on push to `main`), `codeql.yml` | |
| Deploy | Render (`render.yaml`, free plan), `Procfile` | |

## 3. Findings

Severity: 🔴 High · 🟠 Medium · 🟡 Low · ✅ Good practice observed

### 3.1 Secrets & supply chain

- 🔴 **Release keystores committed to git** — `careplus_{flutter,partner,admin}/android/app/rasoi-care-upload.jks`. Passwords are correctly kept in `local.properties`, but the keystore itself is now in history permanently; it is only protected by password strength. Recommend: rotate the upload key via Play Console (if Play App Signing is enabled), remove the `.jks` from the repo, add `*.jks` to `.gitignore`, and supply it to CI from an encrypted secret.
- 🟠 **Vulnerable dependency: `PyJWT==2.13.0`** (8 advisories). Bump to `PyJWT==2.15.0`.
- 🟠 **Release APKs fall back to debug signing** when the keystore password is absent (`build.gradle.kts:96`). CI (`build-apks.yml`) never supplies a keystore, so every published GitHub-release APK is **debug-signed** and can't be upgraded in place by a properly signed build. Fail the release build instead, or wire signing secrets into CI.
- 🟡 Firebase API key in `google-services.json` / `firebase_options.dart` — normal for Firebase clients, but ensure the key is restricted (Android package + SHA-1) in Google Cloud Console and Firestore/Storage security rules are locked down (rules are not in this repo, so could not be audited).
- 🟡 Unpinned deps: `gunicorn>=`, `cryptography>=`, `psycopg2-binary>=`, `pytest>=`. Pin or add a lockfile for reproducible deploys.

### 3.2 Backend security

- 🟠 **Rate limiting trusts `X-Forwarded-For` blindly** (`app.py:355` `_client_ip`). Any client can set the header and get a fresh IP bucket per request, defeating the per-IP auth/OTP backoff (`_auth_gate`) and global/public limits. Use `werkzeug.middleware.proxy_fix.ProxyFix(x_for=1)` with the known proxy-hop count and read `request.remote_addr`.
- 🟠 **All rate-limit / OTP state is in process memory** (`_backoff_state`, `_web_phone_otp_state`, `_cancel_otp_state`). It resets on every restart (frequent on Render free plan) and is not shared if gunicorn is run with >1 worker — limits multiply by worker count and an OTP issued in one worker can't be verified in another. Move to Redis/DB, or document and enforce `--workers 1`.
- 🟠 **4-digit OTP** (`app.py:310`, 10,000 combinations). Acceptable only because of per-OTP attempt counters + backoff; combined with the XFF bypass above, risk increases. Consider 6 digits.
- 🟠 **`POST /api/reset` is guarded by `require_staff_auth`, not `require_owner`** (`app.py:4412`). It currently only re-runs `init_db()` (idempotent migrations + seed), so impact is low today, but the name invites a future destructive change. Restrict to owner or remove from production.
- 🟡 **`JWT_SECRET` falls back to a random value** with only a warning (`app.py:467`). Sessions silently die on every restart if misconfigured, and with multiple workers each worker gets a *different* secret (tokens randomly rejected). Fail fast in production instead. (`render.yaml` does set `generateValue: true` ✅.)
- 🟡 No `Content-Security-Policy` header; the HTML pages use `innerHTML` heavily. HSTS, `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy` are present ✅.
- 🟡 CORS `Access-Control-Allow-Origin: *` on `/api/*`. Safe with bearer tokens (no cookies), but tighten to known origins.
- 🟡 `homeservices.html` has no HTML-escape helper; it interpolates `b.service`, `b.date` into `innerHTML`. Service name is server-priced from `HS_SERVICES` ✅, but `date` is client-supplied — self-XSS at minimum. Add the same `esc()` used in the other pages.
- ✅ Passwords/PINs hashed with Werkzeug (`generate_password_hash`); OTPs via `secrets`; Firebase ID tokens verified RS256 against Google certs; JWT `algorithms=[...]` pinned; KYC documents proxied with host allow-list (prevents SSRF and raw URL leakage); booking list/photo endpoints now require ownership checks; server-side pricing for Home Services; `MAX_CONTENT_LENGTH` 16 MB; first-staff-becomes-owner bootstrap with later roles forced to `staff`.

### 3.3 Reliability & data

- 🟠 **SQLite on Render free plan is ephemeral** — if `DATABASE_URL` is unset, all data is lost on every deploy/restart. Make `DATABASE_URL` mandatory in production.
- 🟡 Migrations are hand-rolled and run on every boot (`init_db`); no versioning table. Consider Alembic or a `schema_version` row.
- 🟡 `datetime.utcnow()` deprecated (`database.py:407`) — replace with `datetime.now(timezone.utc)`.
- 🟡 Monolithic `app.py` (4.6k lines) — split into Flask blueprints (auth, bookings, technician, staff, home-services) for maintainability.

### 3.4 Static-analysis notes (bandit)

All 12 Medium hits were manually verified as **false positives**:
- B608 SQL string building (`app.py:943,978`, `database.py:486-498`) — only builds `?` placeholder lists; values are parameterized.
- B608 `app.py:3921` — column names come from a fixed dict, not user input.
- B608 `database.py:631` — column list from internal schema.
- B310 `urlopen` (`app.py:1321,2353,3685`) — fixed Google/HTTPSMS URLs or host-allow-listed storage URLs.
- B104 `0.0.0.0` bind — dev entrypoint only.

### 3.5 Testing & CI

- 🟠 **Backend tests are not run in CI.** `build-apks.yml` only builds APKs; add a `pytest` job on PRs (plus `pip-audit`).
- 🟠 Coverage gaps: `app.py` is 54% covered. Untested areas include payments (`/payment`), parts/inventory, stats/reports, complaints, staff management, document proxy, Postgres code path.
- 🟠 Flutter apps: no `flutter analyze` / `flutter test` in CI; only one test in the whole Flutter codebase.
- 🟡 CI builds/publishes a GitHub release on **every push to `main`** — release noise; consider tag-triggered releases.
- ✅ CodeQL workflow present.

### 3.6 Repository hygiene

- 🟡 `SECURITY.md` is the unedited GitHub template (fake version table, placeholder text). Fill in a real contact/process.
- 🟡 `careplus_flutter/android/app/src/main/java/.../GeneratedPluginRegistrant.java` is committed (generated file).
- 🟡 `pubspec.lock` committed for the 3 WebView apps but not for the 3 main apps — commit lockfiles for apps consistently.

## 4. Prioritized action list

1. Bump `PyJWT` to 2.15.0.
2. Remove keystores from repo, rotate upload key, supply via CI secrets; stop debug-signed release fallback.
3. Fix `_client_ip` XFF trust (ProxyFix).
4. Make `DATABASE_URL` and `JWT_SECRET` mandatory in production; move rate-limit/OTP state to shared storage or pin 1 worker.
5. Add `pytest` + `pip-audit` (and `flutter analyze`) jobs to CI.
6. Restrict `/api/reset` to owner; add CSP; escape `homeservices.html` output; 6-digit OTP.
7. Raise coverage on payments, inventory, reports; replace `utcnow()`; split `app.py`.
