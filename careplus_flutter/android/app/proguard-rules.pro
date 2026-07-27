# Flutter's own classes must never be stripped or renamed.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Uncomment as you add these backends — reflection-heavy SDKs need explicit keeps.
# -keep class com.google.firebase.** { *; }
# -keep class com.razorpay.** { *; }
# -keep class com.google.android.gms.maps.** { *; }
