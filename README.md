# RasoiCare backend

Serves three separate apps — Customer, Technician, and Admin — each its
own page (`/customer`, `/technician`, `/admin`), plus a landing hub at
`/`, and the REST API every app (web and native) calls. It's a Node.js
(Express) server backed by MySQL, built to run as a **Hostinger Node.js
web app** with the MySQL database Hostinger provides on the same server.
An action on one device (e.g. a technician marking a job complete) is
visible on another (e.g. the customer's phone) as soon as it polls the API.

## Files

- `server/app.js` — the Express app and all API routes
- `server/db.js` — schema, seed data, MySQL/SQLite connection helper
- `server/index.js` — entry point (`npm start`)
- `server/scripts/migrate-from-postgres.js` — one-time copy of the old
  Render/Postgres data into MySQL
- `tests/` — API tests (`npm test`)
- `package.json` — dependencies and scripts

## Run it locally

Needs Node.js 22.5 or newer (for the built-in SQLite used locally).

```bash
npm install
npm start
```

Starts on `http://127.0.0.1:8420`. With no database configured it uses a
local SQLite file (`rasoicare.db`, created automatically) — zero setup.

```bash
curl http://127.0.0.1:8420/api/health
npm test
```

## Deploy on Hostinger

Hostinger's **Business** and **Cloud** web hosting plans run Node.js web
apps (shared Premium hosting doesn't — it only runs PHP). Python isn't
supported on Hostinger web hosting, which is why the backend was ported
from Flask to Node.js.

1. **Create the database.** hPanel → **Databases → MySQL Databases** →
   create a database and user. Note the database name, user and password.
2. **Create the Node.js app.** In hPanel, add a new website as a
   **Node.js app** and import this GitHub repository (or upload a zip).
   - Framework: Express · Node.js version: 22.x
   - Entry file: `server/index.js` · Build command: `npm install`
3. **Set environment variables** on the app:

   | Variable | Value |
   |---|---|
   | `DB_HOST` | `127.0.0.1` (the database runs on the same server) |
   | `DB_PORT` | `3306` |
   | `DB_NAME` / `DB_USER` / `DB_PASSWORD` | from step 1 |
   | `JWT_SECRET` | a long random string — keeps sign-ins valid across restarts |
   | `STAFF_SEED_OWNER_PIN` / `STAFF_SEED_STAFF_PIN` | real PINs for the seeded owner/staff logins (set before first boot) |
   | `FIREBASE_PROJECT_ID` | optional, defaults to `rasoi-care` |
   | `HTTPSMS_API_KEY` / `HTTPSMS_FROM_NUMBER` | optional, enables SMS (OTP and start codes) |

   Use `127.0.0.1`, not `localhost` and not the `srvNNNN.hstgr.io` host —
   that one is only for connections from outside Hostinger.
4. **Deploy.** On first boot the server creates every table and seeds the
   catalog and the owner/staff logins. Check `https://<your-domain>/api/health`.
5. **Point the apps at the new URL.** The apps still default to the old
   Render address — update it and rebuild:
   - `careplus_flutter`, `careplus_partner`, `careplus_admin`:
     `lib/data/api/api_config.dart` (or pass
     `--dart-define=API_BASE_URL=https://<your-domain>`)
   - `rasoi_web_customer`, `rasoi_web_partner`, `rasoi_web_admin`:
     `kBackendBaseUrl` in `lib/main.dart`

### Moving existing data off Render/Postgres

If the old deployment had a `DATABASE_URL` Postgres database, copy it
across once (from your own machine). First allow your IP under hPanel →
**Databases → Remote MySQL**, then:

```bash
npm install pg
SOURCE_DATABASE_URL='postgresql://user:pass@host/db' \
DB_HOST=srvNNNN.hstgr.io DB_USER=... DB_PASSWORD=... DB_NAME=... \
npm run migrate:from-postgres
```

It creates the schema, then copies every table; re-running it is safe.
Existing passwords and PINs keep working — hashes use the same format as
the old backend.

### Notes

- Job photos are stored in the database as base64 (the API accepts up
  to ~12MB each), so MySQL's `max_allowed_packet` has to be larger than
  the biggest photo. If very large uploads fail, check that setting.
- Rate limits and OTP codes live in memory: one Node process per app,
  reset on restart.

## The three apps

`customer.html`, `technician.html` and `admin.html` are each served
directly by the server at `/customer`, `/technician` and `/admin` (see the
static page routes in `server/app.js`). They call the API same-origin — no
`API_BASE` to configure — so once the app is deployed, all three URLs work
immediately off that one address, e.g. `https://<your-domain>/customer`.

Open `/customer` and `/technician` on two different devices (or have a
customer and a technician open them independently) — they're both
talking to the same server, so actions genuinely sync between them: a
booking placed on `/customer` shows up in the `/technician` job feed
within seconds, and advancing it there is reflected live on the
customer's tracking screen and on `/admin`.

Customer sign-in is phone-number first (OTP is simulated — the demo
code `4402` auto-fills) but backed by real `/api/auth/*` JWT accounts
under the hood. The technician and admin apps have no login screen by
design (see `/api/bookings` in `server/app.js`) — they
show the operations-wide view, not a scoped one.

### Technicians: areas, verification and auto-routing

Every technician has a service `area` (a locality string like "Gangapur
Road") and a `verified` flag. Admin adds new hires from the Team tab —
they start unverified and offline, invisible to auto-routing and the
technician job feed, until admin reviews and verifies them (which also
brings them online).

When a customer books a service, `POST /api/bookings` in `server/app.js` auto-picks
a technician: a verified, online technician in the same area and
category first, then any verified/online technician in that category,
then any technician in that category at all (never a mismatched
specialty) as a last resort. Admin can always override the pick from a
booking's detail sheet, where the technician list is sorted with
same-area matches first.

### Admin: staff accounts, reports and stock

`/admin` is now gated by a real sign-in screen — phone + PIN, backed by a
`staff` table (separate from the customer `users` table). Two roles:

- **Owner** — sees everything, including the Reports tab's Financial P&amp;L
  card, and can invite/suspend/reinstate staff and promote/demote roles
  from the Settings tab.
- **Staff** — sees Overview, Bookings, Team, Reports (minus P&amp;L), and
  Stock, but the Settings tab is read-only (no invite button, no role
  controls).

Demo logins (seeded once, left alone by `/api/reset`): **Owner** —
`9822000001` / PIN `1234`. **Staff** — `9822000002` / PIN `1234`.

The **Reports** tab is built entirely from real data — no mock numbers —
switchable between week/month/quarter: a revenue trend bar chart, revenue
by appliance category, a technician leaderboard (jobs + revenue in the
period), and a complaint status breakdown. The owner-only P&amp;L
(gross revenue, technician payout, net margin) uses one clearly-labeled
assumption — a 65% payout rate (`TECH_PAYOUT_RATE` in `server/app.js`) — since
there's no real payroll ledger to draw from; everything else on the tab
is a direct aggregation of the same `bookings`/`complaints`/`technicians`
tables the rest of the app uses.

The **Stock** tab now tracks a real `inventory` table (spare parts by
SKU, quantity, reorder level) instead of a hardcoded illustrative list —
admin/staff can add items and restock them, and a banner surfaces
anything below its reorder level.

## WebView Android apps (`rasoi_web_customer`, `rasoi_web_partner`, `rasoi_web_admin`)

Three thin Flutter/WebView wrapper apps, one per role, each one loading the
real web app above (`/customer`, `/technician`, `/admin`) inside a native
Android shell instead of a browser tab. This is separate from the fuller
native Flutter apps in `careplus_flutter`/`careplus_partner`/`careplus_admin`
— these wrappers exist so the exact same server-rendered pages (and every
future change to `customer.html`/`technician.html`/`admin.html`) show up in
an installable APK with no rebuild required on the web side.

Each app has one thing to configure before it's useful: `kBackendBaseUrl` at
the top of `lib/main.dart`, currently a placeholder. Once this backend is
deployed (see "Deploy it for real" above), set it to that public URL and
rebuild:

```bash
cd rasoi_web_customer   # or rasoi_web_partner / rasoi_web_admin
flutter build apk --release
```

Until `kBackendBaseUrl` is set, the app shows an in-app notice instead of a
blank/broken WebView, explaining what to configure.

## API reference

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Check the server is up |
| POST | `/api/auth/register` / `/api/auth/login` | Real JWT accounts — the customer app derives email/password from the phone number |
| GET | `/api/appliances`, `/api/services` | The real catalog customer.html browses and prices bookings from |
| GET | `/api/bookings` | List bookings — only the caller's own with a Bearer token, all of them without one (what technician.html/admin.html use) |
| GET | `/api/bookings/<id>` | Get one booking |
| POST | `/api/bookings` | Create a booking — `{service_id}` (catalog price looked up server-side) or the legacy `{category, service, price, bachatSlot?}` shape |
| PATCH | `/api/bookings/<id>/advance` | Move a booking to its next status |
| PATCH | `/api/bookings/<id>/assign` | Assign or reassign the technician on a booking `{technician_id}` — what admin.html's booking detail sheet calls |
| POST | `/api/bookings/<id>/rating` | Submit ratings `{serviceRating, techRating, raiseComplaint?, complaintText?}` |
| GET | `/api/complaints` | List all complaints |
| PATCH | `/api/complaints/<id>` | Update `{response?, status?}` |
| GET | `/api/technicians` | List all technicians with live rating/job counts |
| POST | `/api/technicians` | Admin adds a technician `{name, category, area}` — starts unverified and offline |
| PATCH | `/api/technicians/<id>/verify` | Admin verifies a technician, bringing them online and into auto-routing |
| POST | `/api/staff/login` | Owner/staff sign-in `{phone, pin}` — returns a staff JWT (separate from customer auth) |
| GET | `/api/staff/me` | Current staff account (requires staff Bearer token) |
| GET | `/api/staff` | List owner/staff accounts (requires staff Bearer token) |
| POST | `/api/staff` | Owner-only: invite a staff member `{name, phone, pin, role}` |
| PATCH | `/api/staff/<id>` | Owner-only: change `{role, active}` |
| GET | `/api/inventory` | List spare-parts stock |
| POST | `/api/inventory` | Add a stock item `{name, sku, category, quantity, reorderLevel}` (requires staff Bearer token) |
| PATCH | `/api/inventory/<id>` | Update `{quantity, reorderLevel}` (requires staff Bearer token) |
| GET | `/api/stats/overview` | KPIs for the admin dashboard |
| GET | `/api/stats/reports?period=week\|month\|quarter` | Revenue/rating trends, technician leaderboard, complaint breakdown, owner-only P&L (requires staff Bearer token) |
| POST | `/api/reset` | Reset all data back to seed state |
