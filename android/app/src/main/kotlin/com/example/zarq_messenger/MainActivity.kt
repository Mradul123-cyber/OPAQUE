package com.example.zarq_messenger

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.messaging.FirebaseMessaging

class MainActivity : FlutterActivity() {

    // Method channels
    private val SIGNAL_CHANNEL = "com.zarq/signal"
    private val NAVIGATION_CHANNEL = "com.zarq/navigation"

    companion object {
        private const val TAG = "MainActivity"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
        var flutterEngineInstance: FlutterEngine? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngineInstance = flutterEngine

        // Set up Signal Protocol Method Channel
        setupSignalMethodChannel(flutterEngine)

        // Set up existing navigation and utility channels
        setupUtilityMethodChannel(flutterEngine)
        setupNavigationChannel(flutterEngine)

        Log.d(TAG, "All method channels configured")
    }

    private fun setupSignalMethodChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIGNAL_CHANNEL)
            .setMethodCallHandler { call, result ->
                handleSignalMethods(call, result)
            }
        Log.d(TAG, "Signal method channel ready on $SIGNAL_CHANNEL")
    }

    private fun setupUtilityMethodChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarq/utility")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> {
                        Log.d(TAG, "Ping received from Flutter")
                        result.success("pong")
                    }
                    "getFCMToken" -> {
                        val sharedPrefs = getSharedPreferences("zarq_fcm", Context.MODE_PRIVATE)
                        val token = sharedPrefs.getString("fcm_token", null)
                        result.success(token)
                    }
                    "getAuthToken" -> {
                        val user = FirebaseAuth.getInstance().currentUser
                        user?.getIdToken(true)?.addOnCompleteListener { task ->
                            if (task.isSuccessful) {
                                result.success(task.result?.token)
                            } else {
                                result.error("AUTH_ERROR", "Failed to get auth token", null)
                            }
                        } ?: result.error("NO_USER", "No authenticated user", null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // Initialize SignalManager
    private val signalManager by lazy { SignalManager(this) }

    private fun handleSignalMethods(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> {
                Log.d(TAG, "Signal ping received")
                result.success("Signal pong")
            }

            "hasKeys" -> {
                try {
                    Log.d(TAG, "hasKeys called")
                    val hasKeys = signalManager.hasKeys()
                    result.success(hasKeys)
                } catch (e: Exception) {
                    Log.e(TAG, "hasKeys error: $e")
                    result.error("HAS_KEYS_ERROR", e.message, null)
                }
            }

            "generateKeyBundle" -> {
                try {
                    Log.d(TAG, "generateKeyBundle called")
                    val keyBundle = signalManager.generateKeyBundle()
                    result.success(keyBundle)
                } catch (e: Exception) {
                    Log.e(TAG, "generateKeyBundle error: $e")
                    result.error("KEY_GENERATION_ERROR", e.message, null)
                }
            }

            "getDeviceId" -> {
                try {
                    Log.d(TAG, "getDeviceId called")
                    val deviceId = signalManager.getDeviceId()
                    result.success(deviceId)
                } catch (e: Exception) {
                    Log.e(TAG, "getDeviceId error: $e")
                    result.error("DEVICE_ID_ERROR", e.message, null)
                }
            }

            "getRegistrationId" -> {
                try {
                    Log.d(TAG, "getRegistrationId called")
                    val registrationId = signalManager.getRegistrationId()
                    if (registrationId != -1) {
                        result.success(registrationId)
                    } else {
                        result.error("NO_REGISTRATION_ID", "Registration ID not found", null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "getRegistrationId error: $e")
                    result.error("REGISTRATION_ID_ERROR", e.message, null)
                }
            }

            "clearKeys" -> {
                try {
                    Log.d(TAG, "clearKeys called")
                    val success = signalManager.clearKeys()
                    result.success(success)
                } catch (e: Exception) {
                    Log.e(TAG, "clearKeys error: $e")
                    result.error("CLEAR_KEYS_ERROR", e.message, null)
                }
            }

            "performSecurityAudit" -> {
                try {
                    Log.d(TAG, "performSecurityAudit called")
                    val audit = signalManager.performSecurityAudit()
                    result.success(audit)
                } catch (e: Exception) {
                    Log.e(TAG, "performSecurityAudit error: $e")
                    result.error("SECURITY_AUDIT_ERROR", e.message, null)
                }
            }

            "rotateSignedPreKey" -> {
                try {
                    Log.d(TAG, "rotateSignedPreKey called")
                    val success = signalManager.rotateSignedPreKey()
                    result.success(success)
                } catch (e: Exception) {
                    Log.e(TAG, "rotateSignedPreKey error: $e")
                    result.error("ROTATE_SIGNED_PREKEY_ERROR", e.message, null)
                }
            }

            "generateAdditionalPreKeys" -> {
                try {
                    Log.d(TAG, "generateAdditionalPreKeys called")
                    val count = call.argument<Int>("count") ?: 100
                    val preKeys = signalManager.generateAdditionalPreKeys(count)
                    result.success(preKeys)
                } catch (e: Exception) {
                    Log.e(TAG, "generateAdditionalPreKeys error: $e")
                    result.error("GENERATE_PREKEYS_ERROR", e.message, null)
                }
            }

            "establishSession" -> {
                try {
                    Log.d(TAG, "establishSession called")
                    val recipientUid = call.argument<String>("recipientUid")
                        ?: throw Exception("Missing recipientUid")
                    val deviceId = call.argument<Int>("deviceId") ?: signalManager.getDeviceId()
                    val prekeyBundle = call.argument<Map<String, Any>>("prekeyBundle")
                        ?: throw Exception("Missing prekeyBundle")

                    val success = signalManager.establishSession(recipientUid, deviceId, prekeyBundle)
                    result.success(success)
                } catch (e: Exception) {
                    Log.e(TAG, "establishSession error: $e")
                    result.error("ESTABLISH_SESSION_ERROR", e.message, null)
                }
            }

            "hasSession" -> {
                try {
                    Log.d(TAG, "hasSession called")
                    val recipientUid = call.argument<String>("recipientUid")
                        ?: throw Exception("Missing recipientUid")
                    val deviceId = call.argument<Int>("deviceId") ?: signalManager.getDeviceId()

                    val hasSession = signalManager.hasSession(recipientUid, deviceId)
                    result.success(hasSession)
                } catch (e: Exception) {
                    Log.e(TAG, "hasSession error: $e")
                    result.error("HAS_SESSION_ERROR", e.message, null)
                }
            }

            "validateSession" -> {
                try {
                    Log.d(TAG, "validateSession called")
                    val recipientUid = call.argument<String>("recipientUid")
                        ?: throw Exception("Missing recipientUid")
                    val deviceId = call.argument<Int>("deviceId") ?: signalManager.getDeviceId()

                    val isValid = signalManager.validateSession(recipientUid, deviceId)
                    result.success(isValid)
                } catch (e: Exception) {
                    Log.e(TAG, "validateSession error: $e")
                    result.error("VALIDATE_SESSION_ERROR", e.message, null)
                }
            }

            "removeSession" -> {
                try {
                    Log.d(TAG, "removeSession called")
                    val recipientUid = call.argument<String>("recipientUid")
                        ?: throw Exception("Missing recipientUid")
                    val deviceId = call.argument<Int>("deviceId") ?: signalManager.getDeviceId()

                    val success = signalManager.removeSession(recipientUid, deviceId)
                    result.success(success)
                } catch (e: Exception) {
                    Log.e(TAG, "removeSession error: $e")
                    result.error("REMOVE_SESSION_ERROR", e.message, null)
                }
            }

            "encryptMessage" -> {
                try {
                    Log.d(TAG, "encryptMessage called")
                    val recipientUid = call.argument<String>("recipientUid")
                        ?: throw Exception("Missing recipientUid")
                    val plaintext = call.argument<String>("plaintext")
                        ?: throw Exception("Missing plaintext")
                    val deviceId = call.argument<Int>("deviceId") ?: signalManager.getDeviceId()

                    val ciphertext = signalManager.encryptMessage(recipientUid, plaintext, deviceId)
                    result.success(ciphertext)
                } catch (e: Exception) {
                    Log.e(TAG, "encryptMessage error: $e")
                    result.error("ENCRYPT_MESSAGE_ERROR", e.message, null)
                }
            }

            "decryptMessage" -> {
                try {
                    Log.d(TAG, "decryptMessage called")
                    val senderUid = call.argument<String>("senderUid")
                        ?: throw Exception("Missing senderUid")
                    val ciphertextB64 = call.argument<String>("ciphertextB64")
                        ?: throw Exception("Missing ciphertextB64")
                    val deviceId = call.argument<Int>("deviceId") ?: signalManager.getDeviceId()

                    val plaintext = signalManager.decryptMessage(senderUid, ciphertextB64, deviceId)
                    result.success(plaintext)
                } catch (e: Exception) {
                    Log.e(TAG, "decryptMessage error: $e")
                    result.error("DECRYPT_MESSAGE_ERROR", e.message, null)
                }
            }

            "encryptMessageWithSessionSetup" -> {
                try {
                    Log.d(TAG, "encryptMessageWithSessionSetup called")
                    val recipientUid = call.argument<String>("recipientUid")
                        ?: throw Exception("Missing recipientUid")
                    val plaintext = call.argument<String>("plaintext")
                        ?: throw Exception("Missing plaintext")
                    val prekeyBundle = call.argument<Map<String, Any>?>("prekeyBundle")
                    val deviceId = call.argument<Int>("deviceId") ?: signalManager.getDeviceId()

                    val ciphertext = signalManager.encryptMessageWithSessionSetup(recipientUid, plaintext, prekeyBundle, deviceId)
                    result.success(ciphertext)
                } catch (e: Exception) {
                    Log.e(TAG, "encryptMessageWithSessionSetup error: $e")
                    result.error("ENCRYPT_WITH_SETUP_ERROR", e.message, null)
                }
            }

            "getEncryptionStats" -> {
                try {
                    Log.d(TAG, "getEncryptionStats called")
                    val stats = signalManager.getEncryptionStats()
                    result.success(stats)
                } catch (e: Exception) {
                    Log.e(TAG, "getEncryptionStats error: $e")
                    result.error("ENCRYPTION_STATS_ERROR", e.message, null)
                }
            }

            "resetUserContext" -> {
                try {
                    Log.d(TAG, "resetUserContext called")
                    val success = signalManager.resetUserContext()
                    result.success(success)
                } catch (e: Exception) {
                    Log.e(TAG, "resetUserContext error: $e")
                    result.error("RESET_USER_CONTEXT_ERROR", e.message, null)
                }
            }

            "debugDecryption" -> {
                try {
                    val ciphertext = call.argument<String>("ciphertext") ?: ""
                    val bytes = Base64.decode(ciphertext, Base64.NO_WRAP)
                    Log.d(TAG, "Ciphertext bytes length: ${bytes.size}")
                    Log.d(TAG, "First bytes: ${bytes.take(10).joinToString { "%02x".format(it) }}")
                    result.success("Debug logged")
                } catch (e: Exception) {
                    Log.e(TAG, "Debug error: $e")
                    result.success("Debug failed: ${e.message}")
                }
            }

            // Keep existing placeholder methods for backward compatibility
            "getPreKeyBundle" -> {
                Log.d(TAG, "getPreKeyBundle called - redirecting to generateKeyBundle")
                try {
                    val keyBundle = signalManager.generateKeyBundle()
                    result.success(keyBundle)
                } catch (e: Exception) {
                    result.error("KEY_GENERATION_ERROR", e.message, null)
                }
            }

            "initializeProtocol" -> {
                Log.d(TAG, "initializeProtocol called - redirecting to generateKeyBundle if needed")
                try {
                    if (!signalManager.hasKeys()) {
                        val keyBundle = signalManager.generateKeyBundle()
                        result.success(mapOf("initialized" to true, "key_bundle" to keyBundle))
                    } else {
                        result.success(mapOf("initialized" to true, "existing_keys" to true))
                    }
                } catch (e: Exception) {
                    result.error("INITIALIZATION_ERROR", e.message, null)
                }
            }

            "getCurrentSignedPreKey" -> {
                try {
                    Log.d(TAG, "getCurrentSignedPreKey called")
                    val signedPreKeyData = signalManager.getCurrentSignedPreKey()
                    result.success(signedPreKeyData)
                } catch (e: Exception) {
                    Log.e(TAG, "getCurrentSignedPreKey error: $e")
                    result.error("GET_SIGNED_PREKEY_ERROR", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }



    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize FCM token
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                Log.w(TAG, "Fetching FCM registration token failed", task.exception)
                return@addOnCompleteListener
            }

            val token = task.result
            Log.d(TAG, "FCM Token retrieved: ${token?.substring(0, 20)}...")
        }

        Log.d(TAG, "MainActivity onCreate")

        // Request notification permission
        requestNotificationPermission()

        // Handle notification intent when app is launched
        handleNotificationIntent(intent)
    }

    // ===== NOTIFICATION HANDLING (UNCHANGED) =====

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "Notification permission granted")
            } else {
                Log.w(TAG, "Notification permission denied")
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "MainActivity onNewIntent")

        // Handle notification intent when app is already running
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) {
            Log.d(TAG, "Intent is null")
            return
        }

        val conversationId = intent.getIntExtra("conversation_id", -1)
        val messageId = intent.getIntExtra("message_id", -1)

        Log.d(TAG, "Raw intent extras: ${intent.extras?.keySet()}")
        Log.d(TAG, "Conversation ID from intent: $conversationId")
        Log.d(TAG, "Message ID from intent: $messageId")

        if (conversationId != -1) {
            Log.d(TAG, "Valid conversation ID found, calling navigateToConversation")
            navigateToConversation(conversationId, messageId)

            // Clear the intent extras to prevent re-navigation
            intent.removeExtra("conversation_id")
            intent.removeExtra("message_id")
        } else {
            Log.w(TAG, "No valid conversation ID in intent")
        }
    }

    private fun setupNavigationChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAVIGATION_CHANNEL)

        // Set up method call handler for Flutter -> Kotlin communication
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "logNavigationEvent" -> {
                    val event = call.argument<String>("event")
                    Log.d(TAG, "Flutter navigation event: $event")
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        Log.d(TAG, "Navigation channel set up successfully")
    }

    private fun navigateToConversation(conversationId: Int, messageId: Int) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            val channel = MethodChannel(messenger, NAVIGATION_CHANNEL)

            val arguments = mapOf(
                "conversation_id" to conversationId,
                "message_id" to messageId,
                "timestamp" to System.currentTimeMillis()
            )

            Log.d(TAG, "Sending navigation command to Flutter: $arguments")

            // Invoke Flutter method
            channel.invokeMethod("openConversation", arguments, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d(TAG, "Navigation command sent successfully")
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "Navigation error: $errorCode - $errorMessage")
                }

                override fun notImplemented() {
                    Log.w(TAG, "Navigation method not implemented in Flutter")
                }
            })
        } ?: run {
            Log.e(TAG, "Flutter engine not available for navigation")
        }
    }
}