import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must come after Android and Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/local.properties already exists (gitignored) for sdk.dir/flutter.sdk
// — MAPS_API_KEY lives in the same file. See lib/core/config/maps_config.dart.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

android {
    namespace = "com.careplus.care_plus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Release builds default to extractNativeLibs=false (native libs load
    // straight out of the compressed APK) — some real devices/OEM skins
    // don't handle that reliably and crash on launch. Debug builds don't hit
    // this because they extract to disk instead. Force the same legacy
    // (extract-to-disk) packaging release uses in debug too.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Bump this if you already published under a different id.
        applicationId = "com.careplus.care_plus"
        minSdk = flutter.minSdkVersion // Flutter's managed floor; auto-migrated to this on every build
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Google Maps API key → AndroidManifest.xml's com.google.android.geo.API_KEY
        // meta-data, via the ${mapsApiKey} manifest placeholder — same wiring
        // mechanism as Flutter's own ${applicationName} placeholder already used
        // in that manifest. Empty string until android/local.properties has a
        // MAPS_API_KEY=... line, so builds never fail for its absence. See
        // lib/core/config/maps_config.dart for the full setup steps.
        manifestPlaceholders["mapsApiKey"] =
            localProperties.getProperty("MAPS_API_KEY", "")
    }

    signingConfigs {
        create("release") {
            // Real values come from android/local.properties (gitignored,
            // same file MAPS_API_KEY lives in — never committed) so the
            // keystore password isn't sitting in git. The .jks file itself
            // stays committed on purpose: regenerating it would invalidate
            // the SHA fingerprints already registered with Firebase,
            // breaking phone-auth SMS delivery. Falls back to the debug key
            // below when the password isn't set, so
            // `flutter build apk --release` still succeeds locally without it.
            val storePasswordValue = localProperties.getProperty("KEYSTORE_STORE_PASSWORD")
                ?: System.getenv("RASOI_KEYSTORE_STORE_PASSWORD")
            val keyPasswordValue = localProperties.getProperty("KEYSTORE_KEY_PASSWORD")
                ?: System.getenv("RASOI_KEYSTORE_KEY_PASSWORD")
            if (storePasswordValue != null && keyPasswordValue != null) {
                keyAlias = "rasoicare"
                keyPassword = keyPasswordValue
                storeFile = file("rasoi-care-upload.jks")
                storePassword = storePasswordValue
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug signing config until the keystore
            // password is available (see signingConfigs above), so
            // `flutter build apk --release` works out of the box for testing.
            signingConfig = if (signingConfigs.getByName("release").storeFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Re-enabled with additional keep rules for Play Integrity/
            // reCAPTCHA (phone auth) and Google Sign-In — see
            // proguard-rules.pro for why those specifically, on top of the
            // existing Firebase/gms keeps, were the likely gap last time
            // this crashed on a real device. Needs a real-device smoke test
            // (sign-in, phone OTP, maps, camera) before trusting it, since a
            // successful build here doesn't rule out a runtime R8 strip.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
