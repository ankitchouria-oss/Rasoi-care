# Rasoi Care Admin

The owner/staff-facing operations, analytics and reports app — separate from
the customer app (`careplus_flutter`) and the technician app
(`careplus_partner`), with its own login and Android package id
(`com.rasoicare.care_plus_admin`).

Flow: splash → phone number → sign in as **Owner** or **Staff member** → OTP
→ dashboard (Overview, Reports, Bookings, Team, Stock).

## Run it

```bash
flutter pub get
flutter run            # debug
flutter build apk --release
```

Sign-in currently uses `MockAuthService` (`lib/data/auth/`) — any 10-digit
phone number "sends", and the OTP screen auto-fills the demo code `4402`.
The role (Owner/Staff) is chosen on the phone-number screen and gates
sensitive sections; swap in a real `AuthService` + role lookup there when
this app is wired to an actual staff directory.

## Role gating

- **Owner** sees everything: the Reports tab's Financial P&L (gross
  revenue, technician payouts, parts cost, discounts, refunds, net margin)
  and the Account screen's "Staff & access" tool (invite staff, assign
  roles, suspend/reinstate accounts).
- **Staff member** gets the same Overview/Reports/Bookings/Team/Stock
  screens minus the Financial P&L section (replaced with an "Owner only"
  notice) and without the Staff & access entry point.

## Structure

- `lib/core/theme`, `lib/core/widgets` — the Care+ design system (copied
  from `careplus_flutter`, not shared as a package, since these are
  independent Flutter projects). `lib/core/widgets/charts.dart` adds three
  hand-rolled chart primitives used across Reports — `SparkLineChart`
  (trend lines), `DonutChart` (segment mixes), `HBarRow` (ranked/breakdown
  bars) — no charting package dependency, matching how `CareDial` is built
  elsewhere in the system.
- `lib/data/models.dart`, `lib/data/repository.dart` — overview KPIs,
  bookings queue, team roster, stock/burn-rate forecast, staff accounts,
  and the `ReportBundle` used by Reports (revenue/rating trend, category
  revenue, technician leaderboard, customer segments, SLA/complaints,
  payment mix, coupon usage, financial P&L) for week/month/quarter ranges.
  Swap `MockAdminRepository` for a real backend in `lib/state/providers.dart`.
- `lib/features/auth` — splash, phone + role toggle, OTP screens.
- `lib/features/dashboard` — the five tab screens plus the account and
  staff-access screens.
