plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.util.Base64

// Load secrets from local.properties (not committed)
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

// AdMob App ID (Android) with safe default to Google test ID
val admobAppIdAndroid: String =
    localProps.getProperty("ADMOB_APP_ID_ANDROID") ?: "ca-app-pub-3940256099942544~3347511713"

// AdMob Banner Unit (Android) for release builds; debug will use test ID in Dart
val admobBannerAndroid: String? = localProps.getProperty("ADMOB_BANNER_ANDROID")

android {
    namespace = "dev.golfapp.swinggroove"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.golfapp.swinggroove"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Provide AdMob App ID to AndroidManifest via placeholder
        manifestPlaceholders["GAD_APPLICATION_ID"] = admobAppIdAndroid
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Inject ADMOB_BANNER_ANDROID into Dart defines automatically for release
            val current =
                (project.findProperty("dart-defines") as String?)?.split(',')?.toMutableList()
                    ?: mutableListOf()
            if (!admobBannerAndroid.isNullOrBlank()) {
                val encoded = Base64.getEncoder()
                    .encodeToString("ADMOB_BANNER_ANDROID=$admobBannerAndroid".toByteArray())
                current.add(encoded)
            }
            project.extensions.extraProperties.set("dart-defines", current.joinToString(","))
        }
    }
}

flutter {
    source = "../.."
}
