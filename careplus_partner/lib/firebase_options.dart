// Android values are real — copied from the rasoi-care Firebase project's
// google-services.json (package com.rasoicare.care_plus_partner, a separate
// Android app registration under the same project as careplus_flutter). iOS
// is still a placeholder since no app is registered for that platform yet.
//
// main.dart calls Firebase.initializeApp() at startup inside a try/catch.
// With real Android values it succeeds, so authServiceProvider switches to
// FirebaseAuthService automatically — no other code changes.
//
// Still to do in the Firebase console for auth to fully work:
//   1. Authentication → Sign-in method → enable Email/Password (project-wide
//      — only needs doing once across all three apps).
//   2. Project settings → this Android app → add your SHA-1/SHA-256
//      fingerprint.
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
    apiKey: 'AIzaSyA0zbJ3DzbAWF6ExXtW2DcIsaZ8HG1dQD0',
    appId: '1:1064653219482:android:6865f3c584d89798e42123',
    messagingSenderId: '1064653219482',
    projectId: 'rasoi-care',
    storageBucket: 'rasoi-care.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'rasoi-care',
    iosBundleId: 'com.rasoicare.carePlusPartner',
  );
}
