plugins {
    id("com.android.application")
    id("kotlin-android")
}

android {
    namespace = "com.example.mindtwin.wear"
    compileSdk = 33

    defaultConfig {
        applicationId = "com.example.mindtwin.wear"
        minSdk = 30 // Target Wear OS 3 (Galaxy Watch 4)
        targetSdk = 33
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
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

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.1"
    }
}

dependencies {
    // Wear OS & Play Services
    implementation("com.google.android.gms:play-services-wearable:18.1.0")
    implementation("androidx.health:health-services-client:1.1.0-alpha02")

    // Kotlin Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.6.4")

    // Compose Wear OS
    implementation("androidx.wear.compose:compose-material:1.2.0")
    implementation("androidx.wear.compose:compose-foundation:1.2.0")
    
    // Jetpack Compose Integration
    implementation("androidx.activity:activity-compose:1.7.2")
    implementation("androidx.compose.ui:ui:1.5.1")
    implementation("androidx.compose.ui:ui-tooling-preview:1.5.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.6.1")
}
