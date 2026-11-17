import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. android/key.properties is gitignored and must contain:
//   storeFile=<path to .jks, relative to android/app or absolute>
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
// The SAME keystore must sign the phone patient app and the Wear OS app (android/wear),
// otherwise the Wearable Data Layer silently refuses to deliver data between them.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.example.mindtwin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications ^22.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Overridden per flavor below (see docs/DATA_MODEL.md "Separate apps").
        applicationId = "com.mindtwin.patient"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "app"
    productFlavors {
        create("patient") {
            dimension = "app"
            // MUST equal the Wear OS app's applicationId (android/wear/build.gradle.kts).
            applicationId = "com.mindtwin.patient"
            resValue("string", "app_name", "MindTwin")
            // Only the patient app receives Wear OS readings.
            manifestPlaceholders["wearListenerEnabled"] = "true"
        }
        create("therapist") {
            dimension = "app"
            applicationId = "com.mindtwin.therapist"
            resValue("string", "app_name", "MindTwin Clinician")
            manifestPlaceholders["wearListenerEnabled"] = "false"
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // FALLBACK ONLY: no android/key.properties found, so release builds are signed
                // with the local debug key. Such builds are NOT distributable, and the watch app
                // must then also be built on this same machine (same debug key) for the Data
                // Layer to work. Create key.properties before shipping.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.gms:play-services-wearable:18.1.0")
    // Opens the Play Store / MindTwin screen on the paired watch from the patient app
    // ("Link your watch" flow).
    implementation("androidx.wear:wear-remote-interactions:1.1.0")
    // RemoteActivityHelper returns a Guava ListenableFuture (API-only dependency upstream;
    // the standalone listenablefuture artifact resolves to an empty placeholder). R8 strips
    // the unused parts of Guava from release builds.
    implementation("com.google.guava:guava:33.3.1-android")
    // Native Firebase used by WearVitalsListenerService to write watch readings to Firestore
    // while the Flutter UI is not running. The BoM version MUST match the one FlutterFire uses
    // (firebase_core 3.15.2 -> FirebaseSDKVersion 33.16.0); bump together with firebase_core.
    implementation(platform("com.google.firebase:firebase-bom:33.16.0"))
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
}
