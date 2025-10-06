plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.zarq_messenger"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    packagingOptions {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt"
            )
        }
    }

    defaultConfig {
        applicationId = "com.example.zarq_messenger"
        minSdk = 26  // Android 8.0 Oreo - Recommended for full feature support
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

            // Enable ProGuard/R8 for release builds
            isMinifyEnabled = true  // Enable code shrinking
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"  // Your custom rules file
            )
        }

        // Optional: For testing ProGuard in debug
        debug {
            isMinifyEnabled = false  // Keep false for debug
            // proguardFiles(...) // Don't use ProGuard in debug for faster builds
        }
    }
    testOptions {
        unitTests {
            isReturnDefaultValues = true
            all {
                it.enabled = false  // Skip all unit tests
            }
        }
    }
}


flutter {
    source = "../.."
}


dependencies {
    // Your existing Firebase dependencies (keep these)
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging:24.1.2")

    // Your existing utilities (keep these)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-urlconnection:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.json:json:20240303")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")

    // COMPATIBLE Signal Protocol Libraries
    // Using the stable, well-tested Java implementation

    implementation("org.whispersystems:signal-protocol-java:2.8.1")
    implementation("org.whispersystems:signal-protocol-android:2.8.1")
    implementation("org.whispersystems:curve25519-android:0.5.0")


    // Security for key storage
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Glide for image loading
    implementation("com.github.bumptech.glide:glide:4.16.0")

    //implementation("org.whispersystems:curve25519-java:0.5.0")
}
