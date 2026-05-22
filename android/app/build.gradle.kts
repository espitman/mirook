plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.espitman.mirook.reader"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.espitman.mirook.reader"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    buildFeatures {
        compose = true
    }

    signingConfigs {
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = false
            enableV4Signing = false
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.animation:animation-android:1.7.6")
    implementation("androidx.compose.foundation:foundation-android:1.7.6")
    implementation("androidx.compose.material:material-icons-extended-android:1.7.5")
    implementation("androidx.compose.material3:material3-android:1.3.1")
    implementation("androidx.compose.ui:ui-android:1.7.6")
    implementation("androidx.compose.ui:ui-tooling-preview-android:1.7.6")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.5")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.5")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jsoup:jsoup:1.18.3")

    debugImplementation("androidx.compose.ui:ui-tooling-android:1.7.6")
    debugImplementation("androidx.compose.ui:ui-test-manifest:1.7.6")
}
