import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Same keystore as the phone app (android/key.properties, gitignored). The Wearable Data Layer
// only delivers data between apps with the SAME applicationId AND the SAME signing key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.mindtwin.wear"
    compileSdk = 36

    defaultConfig {
        // MUST equal the phone `patient` flavor applicationId (android/app/build.gradle.kts).
        applicationId = "com.mindtwin.patient"
        minSdk = 30 // Wear OS 3 (Galaxy Watch4)
        targetSdk = 36
        // When publishing phone + watch in one Play listing, the watch versionCode must differ
        // from the phone's (Flutter versionCode from pubspec). Keep this above the phone's.
        versionCode = 1000001
        versionName = "1.0.0"
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // storeFile is resolved relative to android/app to match the phone module.
                storeFile = rootProject.file("app").resolve(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // FALLBACK ONLY (no android/key.properties): debug key. Works only when the phone
                // app was built on the same machine with the same debug key.
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Wear OS & Play Services
    implementation("com.google.android.gms:play-services-wearable:18.1.0")
    implementation("androidx.health:health-services-client:1.1.0-alpha02")
    implementation("androidx.core:core-ktx:1.13.1")

    // Kotlin Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.6.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.6.4")

    // Compose Wear OS
    implementation("androidx.wear.compose:compose-material:1.2.0")
    implementation("androidx.wear.compose:compose-foundation:1.2.0")

    // Jetpack Compose Integration
    implementation("androidx.activity:activity-compose:1.7.2")
    implementation("androidx.fragment:fragment-ktx:1.6.2")
    implementation("androidx.compose.ui:ui:1.5.1")
    implementation("androidx.compose.ui:ui-tooling-preview:1.5.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.6.1")
}
