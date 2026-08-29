# Flutter's own classes must never be stripped or renamed.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# firebase_core/firebase_auth are wired in (see lib/data/auth/) — Firebase
# self-initializes via a ContentProvider before Flutter's engine even
# starts, using reflection to discover its components. Without this keep,
# R8 strips/renames classes that provider needs, crashing the app on
# launch before main()'s Firebase.initializeApp() try/catch ever runs.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Phone-auth verification (Firebase Auth's Play Integrity + reCAPTCHA
# fallback) lives in these two packages, which are NOT under
# com.google.android.gms — careplus_flutter's first minified build crashed
# the phone sign-in path specifically because these were still being
# stripped despite the gms/firebase keeps above.
-keep class com.google.android.play.core.integrity.** { *; }
-keep class com.google.android.recaptcha.** { *; }

# google_sign_in's native Credential Manager / legacy GoogleSignIn API surface.
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }

# Firebase/Gson-style (de)serialization is reflection-driven and needs
# these attributes preserved, or model/field lookups silently return
# null/throw at runtime instead of failing the build.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# smart_auth (SMS-autofill for the OTP screen) talks to the SMS Retriever
# API under this package.
-keep class com.google.android.gms.auth.api.phone.** { *; }

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
