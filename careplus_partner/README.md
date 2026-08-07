# Rasoi Care Partner

The technician-facing app — separate from `careplus_flutter` (the customer
app), with its own login and its own Android package id
(`com.rasoicare.care_plus_partner`), so it installs and updates
independently of the customer app.

Flow: splash → phone number → OTP → job feed → job detail (checklist,
photos, parts) → close job (signature, payment collection, invoice).

## Run it

```bash
flutter pub get
flutter run            # debug
flutter build apk --release
```

Sign-in currently uses `MockAuthService` (`lib/data/auth/`) — any 10-digit
phone number "sends", and the OTP screen auto-fills the demo code `4402`.
Swap in a real `AuthService` implementation there when this app is wired to
an actual technician roster.

## Structure

- `lib/core/theme`, `lib/core/widgets` — the same Care+ design system used by
  the customer app (copied, not shared as a package, since these are two
  independent Flutter projects).
- `lib/data/models.dart`, `lib/data/repository.dart` — the technician-only
  subset of the domain model (job stats, route, checklist, invoice). Swap
  `MockPartnerRepository` for a real backend in `lib/state/providers.dart`.
- `lib/features/auth` — splash, phone, OTP screens.
- `lib/features/jobs` — job feed, job detail, close-job + signature pad.
