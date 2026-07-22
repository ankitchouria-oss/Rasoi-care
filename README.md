# RasoiCare backend

Serves three separate apps — Customer, Technician, and Admin — each its
own page (`/customer`, `/technician`, `/admin`), plus a landing hub at
`/`. A real Flask + SQLite REST API is the server all three call, so an
action on one device
(e.g. a technician marking a job complete) is visible to another device
(e.g. the customer's phone) as soon as it polls the API.

This has been built and tested (every endpoint below was exercised with
real HTTP requests, including a full booking → accept → advance →
complete → rate → complaint → resolve cycle, and a check that data
survives a server restart). It currently only runs on `127.0.0.1` inside
a sandbox with no public address — follow "Deploy it for real" below to
get a URL that an actual phone can reach.

## Files

- `app.py` — the Flask app and all API routes
- `database.py` — SQLite schema, seed data, connection helper
- `requirements.txt` — Python dependencies
- `Procfile` — tells hosting platforms how to start the app in production

## Run it locally (to test on one machine)

```bash
pip install -r requirements.txt
python3 app.py
```

Starts on `http://127.0.0.1:8420`. Try it:

```bash
curl http://127.0.0.1:8420/api/health
curl http://127.0.0.1:8420/api/bookings
```

A `rasoicare.db` SQLite file is created automatically on first run, seeded
with the same starting data used across the prototype apps.

## Deploy it for real (so separate phones can reach it)

Any host that runs Python works. **Render** has the simplest free path:

1. Put this folder in a GitHub repo (or use Render's "deploy from a
   zip"/manual upload if you don't want to use git).
2. On [render.com](https://render.com) → **New → Web Service** → connect
   the repo.
3. Render auto-detects `requirements.txt` and `Procfile` — leave build
   command as `pip install -r requirements.txt` and start command as
   `gunicorn app:app --bind 0.0.0.0:$PORT` (already set in `Procfile`).
4. Deploy. Render gives you a public URL like
   `https://rasoicare-backend.onrender.com`.
5. Test it from anywhere: `curl https://rasoicare-backend.onrender.com/api/health`

**Railway** and **Fly.io** work the same way (both read `Procfile` /
auto-detect Flask). Pick whichever you already have an account with.

### Important: SQLite + free hosting tiers

Free web-service tiers on Render/Railway typically use an **ephemeral
disk** — if the service restarts or redeploys, the `rasoicare.db` file
can reset. That's fine for testing the deploy, but for anything real you
have two options:

- **Add a persistent disk** (small paid add-on on Render/Railway) so
  `rasoicare.db` survives restarts, or
- **Swap SQLite for a managed Postgres** — Render, Railway, and Supabase
  all offer a free Postgres instance. Only `database.py` would need to
  change (swap `sqlite3` for `psycopg2` and adjust the connection
  string); `app.py`'s routes stay identical since they only call the
  helper functions in `database.py`.

## Point the frontend at your deployed backend

Open `rasoicare-networked.html` and change the `API_BASE` value at the
top of the `<script>` block from `http://127.0.0.1:8420` to your real
URL, e.g. `https://rasoicare-backend.onrender.com`. There's also an
on-screen field to set this without editing the file, for quick testing.

Once that's pointed at a real deployed URL, open the file on two
different devices (or have a customer and a technician open it
independently) — they're now both talking to the same server, so
actions genuinely sync between them.

## API reference

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Check the server is up |
| GET | `/api/bookings` | List all bookings, most recent first |
| GET | `/api/bookings/<id>` | Get one booking |
| POST | `/api/bookings` | Create a booking `{category, service, price, bachatSlot?}` |
| PATCH | `/api/bookings/<id>/advance` | Move a booking to its next status |
| POST | `/api/bookings/<id>/rating` | Submit ratings `{serviceRating, techRating, raiseComplaint?, complaintText?}` |
| GET | `/api/complaints` | List all complaints |
| PATCH | `/api/complaints/<id>` | Update `{response?, status?}` |
| GET | `/api/technicians` | List all technicians with live rating/job counts |
| GET | `/api/stats/overview` | KPIs for the admin dashboard |
| POST | `/api/reset` | Reset all data back to seed state |
