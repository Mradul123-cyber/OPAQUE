# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# ===== SIGNAL PROTOCOL PROTECTION =====
# Keep WhisperSystems Signal Protocol classes (correct package)
-keep class org.whispersystems.** { *; }
-dontwarn org.whispersystems.**

# Keep all libsignal classes and methods
-keep class org.whispersystems.libsignal.** { *; }
-keep class org.whispersystems.curve25519.** { *; }

# Keep protocol buffer classes
-keep class * extends com.google.protobuf.** { *; }
-keep class com.google.protobuf.** { *; }

# Keep serialization methods
-keepclassmembers class * {
    *** serialize();
    *** deserialize(...);
}

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# ===== SQLCIPHER PROTECTION =====
# Keep SQLCipher classes and native methods
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }
-dontwarn net.sqlcipher.**

# Keep all SQLCipher native methods
-keepclasseswithmembernames class net.sqlcipher.** {
    native <methods>;
}

# ===== ROOM DATABASE PROTECTION =====
# (Room not added yet - will add these rules when we implement Room later)
# -keep class * extends androidx.room.RoomDatabase
# -keep @androidx.room.Entity class *
# -keep @androidx.room.Dao class *

# ===== GSON PROTECTION =====
# Keep Gson classes for JSON serialization
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }

# Keep data classes used with Gson
-keep class com.example.zarq_messenger.data.** { *; }

# ===== KOTLIN COROUTINES =====
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ===== FIREBASE PROTECTION =====
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# ===== OKHTTP PROTECTION =====
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# ===== GENERAL ANDROID PROTECTION =====
# Keep Android components
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# Keep Flutter method channels
-keep class io.flutter.** { *; }
-keep class com.example.zarq_messenger.MainActivity { *; }

# Ignore missing Play Core classes
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }


# ===== WORKMANAGER PLUGIN PROTECTION =====
# Keep workmanager plugin classes for background tasks
-keep class be.tramckrijte.workmanager.** { *; }
-keep class androidx.work.** { *; }
-dontwarn be.tramckrijte.workmanager.**
-dontwarn androidx.work.**

# Keep our custom alarm receiver and workers
-keep class com.zarq.messenger.AutoBackupAlarmReceiver { *; }
-keep class com.zarq.messenger.BackupNotificationHelper { *; }

# Keep WorkManager ListenableWorker implementations
-keep class * extends androidx.work.ListenableWorker {
    public <init>(...);
}