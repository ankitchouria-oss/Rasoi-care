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

Sign-in supports phone OTP, email/password, and Google, all going through
`lib/data/auth/`. By default `Firebase.initializeApp()` (in `main.dart`)
fails against the placeholder config in `lib/firebase_options.dart`, so the
app falls back to `MockAuthService`: any 10-digit phone number "sends", the
OTP screen auto-fills the demo code `4402`, and email/Google "succeed"
instantly without a network call.

**To go live**, register a second Android app under the same Firebase
project as `careplus_flutter` — Project settings → Add app → Android →
package name `com.rasoicare.care_plus_partner` — then either run
`flutterfire configure` from this folder or copy the four values
(apiKey/appId/messagingSenderId/projectId) into `lib/firebase_options.dart`
by hand. Add this app's SHA-1/SHA-256 fingerprint under that Android app's
settings (Phone auth and Google Sign-in both need it), and enable
Phone/Email-Password/Google in Authentication → Sign-in method if you
haven't already for the project. Once `Firebase.initializeApp()` succeeds,
`authServiceProvider` (`lib/state/auth_providers.dart`) switches to
`FirebaseAuthService` automatically — no other code changes. A best-effort
`technicians/{uid}` Firestore document (phone, email, last sign-in) is
written on every successful sign-in via `TechnicianProfileService`
(`lib/data/firestore/`).

## Structure

- `lib/core/theme`, `lib/core/widgets` — the same Care+ design system used by
  the customer app (copied, not shared as a package, since these are two
  independent Flutter projects).
- `lib/data/models.dart`, `lib/data/repository.dart` — the technician-only
  subset of the domain model (job stats, route, checklist, invoice). Swap
  `MockPartnerRepository` for a real backend in `lib/state/providers.dart`.
- `lib/features/auth` — splash, phone, OTP screens.
- `lib/features/jobs` — job feed, job detail, close-job + signature pad.
