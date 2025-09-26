# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# ===== SIGNAL PROTOCOL PROTECTION =====
# Keep all Signal Protocol classes and methods
-keep class org.signal.** { *; }
-dontwarn org.signal.**

# Keep libsignal native methods
-keep class org.signal.libsignal.protocol.** { *; }
-keep class org.signal.libsignal.zkgroup.** { *; }
-keep class org.signal.libsignal.metadata.** { *; }

# Keep native method signatures
-keepclasseswithmembernames class * {
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