# Flutter's own classes must never be stripped or renamed.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# firebase_core/firebase_auth are already wired in (see lib/data/firebase/) —
# Firebase self-initializes via a ContentProvider before Flutter's engine even
# starts, using reflection to discover its components. Without this keep, R8
# strips/renames classes that provider needs, crashing the app on launch
# before main()'s Firebase.initializeApp() try/catch ever runs.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Uncomment as you add these backends — reflection-heavy SDKs need explicit keeps.
# -keep class com.razorpay.** { *; }

# Flutter's engine references Play Core's deferred-components API (dynamic
# feature delivery), which this app doesn't use and doesn't depend on — R8
# can't resolve these classes at all, so just silence the warnings.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
