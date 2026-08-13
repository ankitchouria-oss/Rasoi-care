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

Sign-in supports phone OTP, email/password, and Google, all going through
`lib/data/auth/`. By default `Firebase.initializeApp()` (in `main.dart`)
fails against the placeholder config in `lib/firebase_options.dart`, so the
app falls back to `MockAuthService`: any 10-digit phone number "sends", the
OTP screen auto-fills the demo code `4402`, and email/Google "succeed"
instantly without a network call. The role (Owner/Staff) is chosen on the
sign-in screen for every method and gates sensitive sections client-side —
there's no server-side role directory yet, so treat this the same as the
existing mock: fine for a demo, not a real access-control boundary.

**To go live**, register a third Android app under the same Firebase
project as `careplus_flutter`/`careplus_partner` — Project settings → Add
app → Android → package name `com.rasoicare.care_plus_admin` — then either
run `flutterfire configure` from this folder or copy the four values
(apiKey/appId/messagingSenderId/projectId) into `lib/firebase_options.dart`
by hand. Add this app's SHA-1/SHA-256 fingerprint under that Android app's
settings (Phone auth and Google Sign-in both need it), and enable
Phone/Email-Password/Google in Authentication → Sign-in method if you
haven't already for the project. Once `Firebase.initializeApp()` succeeds,
`authServiceProvider` (`lib/state/auth_providers.dart`) switches to
`FirebaseAuthService` automatically — no other code changes. A best-effort
`staff/{uid}` Firestore document (phone, email, role, last sign-in) is
written on every successful sign-in via `StaffProfileService`
(`lib/data/firestore/`).

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
