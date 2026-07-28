import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must come after Android and Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.careplus.care_plus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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
    }

    signingConfigs {
        create("release") {
            // Wired up in §2 of the Android README — reads key.properties if
            // present, otherwise release builds fall back to the debug key
            // below so `flutter build apk --release` still succeeds locally.
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug signing config until key.properties exists,
            // so `flutter build apk --release` works out of the box for testing.
            val keystorePropertiesFile = rootProject.file("key.properties")
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Minification/shrinking disabled for now — it's been crashing the
            // release build on real devices (R8 strips something reflection-
            // based, most likely still Firebase-related, even after adding
            // -keep rules for com.google.firebase/gms). Re-enable once the
            // exact missing keep rule is found; app size doesn't matter for
            // sideloaded testing in the meantime.
            isMinifyEnabled = false
            isShrinkResources = false
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
