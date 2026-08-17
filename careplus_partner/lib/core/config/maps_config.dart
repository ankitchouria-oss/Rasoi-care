// Mirrors careplus_flutter/lib/core/config/maps_config.dart — same
// "no config, graceful fallback" pattern used for Firebase throughout this
// codebase. TechJobScreen's map stays hidden (a static address line instead)
// until this is flipped on.
//
// To go live: add `MAPS_API_KEY=your-key` to android/local.properties
// (gitignored — already wired into build.gradle.kts's manifest placeholder),
// then build with:
//
//   flutter build apk --release --dart-define=MAPS_CONFIGURED=true \
//     --dart-define=MAPS_API_KEY=your-key
abstract final class MapsConfig {
  static const isConfigured =
      bool.fromEnvironment('MAPS_CONFIGURED', defaultValue: false);
  static const apiKey = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');
}
