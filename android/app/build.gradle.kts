import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties (android/key.properties)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // Keep these the same to avoid future headaches
    namespace = "cz.tripco.app"

    // Pin SDK for Google Play compliance (Android 15 = API 35)
    compileSdk = 36

    // Keep NDK from Flutter if needed by plugins
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "cz.tripco.app"

        // Min SDK (change if you truly need higher)
        minSdk = flutter.minSdkVersion

        // Target SDK for Google Play
        targetSdk = 36

        // Keep versions driven from pubspec.yaml (version: x.y.z+N)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only create release signing if key.properties exists
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // IMPORTANT: Use your release signing (not debug)
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // If you forget key.properties, fail clearly instead of silently producing bad artifacts
                throw GradleException("Missing android/key.properties. Create it to sign the release build.")
            }

            // Optional: keep disabled for now (easier publishing). You can enable later.
            isMinifyEnabled = false
            isShrinkResources = false

            // If you later enable minify, you'll add proguard rules here.
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }

        debug {
            // debug signing handled automatically
        }
    }
}

flutter {
    source = "../.."
}
