// Flip this on once a Google Maps API key exists. Until then every
// real-map/live-location UI element in the app stays gated off in favor of
// today's existing static placeholders — the app runs perfectly fine with
// zero Maps configuration, same "no config, graceful fallback" philosophy
// used for Firebase throughout this codebase (grep `Firebase.apps.isEmpty`).
//
// To go live once you have a key from the Google Cloud console (enable the
// "Maps SDK for Android", "Places API" and "Geocoding API" APIs on it):
//
//   1. Add the key to `android/local.properties` (already gitignored —
//      create the file if it doesn't exist):
//
//        MAPS_API_KEY=your-key-here
//
//      Then read it into `android/app/build.gradle.kts`'s `defaultConfig`
//      block and expose it as a manifest placeholder, the same mechanism
//      already used there for `${applicationName}`:
//
//        val localProperties = java.util.Properties()
//        val localPropertiesFile = rootProject.file("local.properties")
//        if (localPropertiesFile.exists()) {
//            localProperties.load(java.io.FileInputStream(localPropertiesFile))
//        }
//        manifestPlaceholders["mapsApiKey"] =
//            localProperties.getProperty("MAPS_API_KEY", "")
//
//      `AndroidManifest.xml` already declares the matching
//      `com.google.android.geo.API_KEY` meta-data tag sourced from that
//      placeholder, defaulting to an empty string so the app never crashes
//      from a missing manifest entry even before a key exists.
//
//   2. Rebuild with the flag below flipped on, and the same key passed
//      through for the app's direct Places/Geocoding HTTP calls (the
//      manifest entry above only covers the native `GoogleMap` widget
//      itself, not those REST calls):
//
//        flutter run --dart-define=MAPS_CONFIGURED=true --dart-define=MAPS_API_KEY=your-key-here
//
// Nothing else needs to change — every `GoogleMap`/marker/Places widget in
// this app is already written and simply waits behind `isConfigured`.
abstract final class MapsConfig {
  /// Flip to true once a Google Maps API key is set up (see above) —
  /// gates every real-map/live-location UI element vs. the existing
  /// static placeholder. Mirrors the Firebase.apps.isEmpty fallback
  /// pattern used throughout this codebase.
  static const isConfigured =
      bool.fromEnvironment('MAPS_CONFIGURED', defaultValue: false);

  /// The raw API key, for the address picker's direct HTTP calls to the
  /// Places Autocomplete and Geocoding REST APIs (the native `GoogleMap`
  /// widget instead reads its own key straight from the Android manifest —
  /// see above). Empty until passed at build time; every call site checks
  /// [isConfigured] first, so an empty key is never actually used.
  static const apiKey = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');
}
