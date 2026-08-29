pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localPropertiesFile = file("local.properties")

            val flutterSdk = if (localPropertiesFile.exists()) {
                localPropertiesFile.inputStream().use { properties.load(it) }
                properties.getProperty("flutter.sdk")
            } else {
                // local.properties is gitignored (holds machine-local paths and
                // secrets), so a fresh CI checkout never has it — fall back to
                // an env var or the conventional CI install path instead of
                // crashing.
                System.getenv("FLUTTER_SDK") ?: "/opt/hostedtoolcache/flutter"
            }

            require(flutterSdk != null) { "flutter.sdk not found in local.properties or FLUTTER_SDK environment variable" }
            flutterSdk
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
