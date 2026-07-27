// GENERATED PLACEHOLDER — replace by running `flutterfire configure`.
//
// This file exists so the project compiles and runs in mock-auth mode out of
// the box. The values below are not real; Firebase.initializeApp() will fail
// with them, and main.dart deliberately catches that failure and falls back
// to MockAuthService so the app still works without any setup.
//
// To go live:
//   1. Create a Firebase project at https://console.firebase.google.com
//   2. Enable Authentication → Sign-in method → Phone
//   3. From the project root: `dart pub global activate flutterfire_cli`
//      then `flutterfire configure` — this OVERWRITES this file with your
//      real projectId/apiKey/appId per platform, and (for Android) drops in
//      google-services.json and wires the Gradle plugin automatically.
//   4. For phone auth specifically, also add your app's SHA-1/SHA-256
//      fingerprints in the Firebase console (Project settings → your Android
//      app) or verification will fail even with a correct config.
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
    projectId: 'careplus-placeholder',
  );

  static const android = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'careplus-placeholder',
  );

  static const ios = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'careplus-placeholder',
    iosBundleId: 'com.careplus.carePlus',
  );
}
