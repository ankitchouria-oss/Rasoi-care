import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/local.properties already exists (gitignored) for sdk.dir/flutter.sdk
// — MAPS_API_KEY and the release keystore password both live in the same file.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

android {
    namespace = "com.rasoicare.care_plus_partner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Mirrors careplus_flutter/android/app/build.gradle.kts — some real
    // devices/OEM skins crash on the default extractNativeLibs=false release
    // packaging, so force the same legacy (extract-to-disk) packaging debug
    // builds already use.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.rasoicare.care_plus_partner"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Native GoogleMap widget (job-tracking screen) reads its key from
        // this manifest placeholder — same wiring as careplus_flutter's
        // build.gradle.kts. MAPS_API_KEY lives in local.properties
        // (gitignored, not committed); defaults to empty so the build never
        // fails for its absence — see lib/core/config/maps_config.dart.
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
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Installs src/main/baseline-prof.txt onto the device at first run so it
    // actually speeds up startup on a sideloaded/test build — without this,
    // a baseline profile only takes effect via Play Store's cloud
    // compilation, which a build like this one never gets.
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
}
