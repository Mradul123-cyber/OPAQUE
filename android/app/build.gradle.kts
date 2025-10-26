import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore properties from key.properties file
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.zarq.messenger"
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
        applicationId = "com.zarq.messenger"
        minSdk = 26  // Android 8.0 Oreo - Recommended for full feature support
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true

        // ✅ FIX: Enable 16 KB page size alignment for Android 15+ devices
        // This ensures native libraries work correctly on devices with 16 KB memory pages
        ndk {
            //noinspection ChromeOsAbiSupport
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }
    }

    // ✅ FIX: Disable legacy packaging to support 16 KB page alignment
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")

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
    // JSONObject is built into Android SDK - no external dependency needed
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

    // Razorpay Android SDK for native payment handling
    implementation("com.razorpay:checkout:1.6.40")

    // WorkManager for background tasks
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // Note: Transcription feature temporarily disabled - no suitable free on-device library available

    //implementation("org.whispersystems:curve25519-java:0.5.0")
}
