// GENERATED PLACEHOLDER — replace by running `flutterfire configure`.
//
// This file exists so the project compiles and runs in mock-auth mode out of
// the box. The values below are not real; Firebase.initializeApp() will fail
// with them, and main.dart deliberately catches that failure and falls back
// to MockAuthService so the app still works without any setup.
//
// This app registers as a SEPARATE Android app (different package name)
// under the SAME Firebase project as careplus_flutter — Firebase projects
// support multiple app registrations. To go live:
//   1. Open your Firebase project at https://console.firebase.google.com
//   2. Project settings → Add app → Android → package name
//      "com.rasoicare.care_plus_partner" → register → download
//      google-services.json, or just copy the four values shown
//      (apiKey/appId/messagingSenderId/projectId) into the `android` block
//      below by hand.
//   3. Enable Authentication → Sign-in method → Phone, Email/Password, Google
//      (if not already enabled for the project — this is project-wide, not
//      per-app, so you likely only need to do this once).
//   4. Add this app's SHA-1/SHA-256 fingerprint under Project settings →
//      this Android app, or Phone auth / Google Sign-in will silently fail.
//   5. For Google Sign-in, set FirebaseConfig.googleServerClientId in
//      lib/data/auth/firebase_config.dart if you hit a
//      DEVELOPER_ERROR/sign_in_failed on Android.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for this platform.',
        );
    }
  }

  static const web = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'rasoi-care',
  );

  static const android = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'rasoi-care',
  );

  static const ios = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'rasoi-care',
    iosBundleId: 'com.rasoicare.carePlusPartner',
  );
}
