package com.example.zarq_messenger

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import org.json.JSONObject
import okhttp3.*
import kotlinx.coroutines.tasks.await
import java.util.concurrent.ConcurrentHashMap
import android.util.Base64
import okhttp3.MediaType.Companion.toMediaType
import java.net.URLEncoder

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.zarq/signal"

    // Lazy initialization of Signal components
    private val signalStore by lazy { SignalStore(this) }
    private val protocolManager by lazy { SignalProtocolManager(this, signalStore, SignalCrypto) }

    // Session managers per user (cached)
    private val sessionManagers = ConcurrentHashMap<String, SessionManager>()
    private val okHttpClient = OkHttpClient()

    // Track current user for testing
    private var currentUserUid: String? = null

    companion object {
        private const val NAVIGATION_CHANNEL = "com.zarq/navigation"
        private const val TAG = "MainActivity"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
        var flutterEngineInstance: FlutterEngine? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngineInstance = flutterEngine

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> {
                        Log.d("MainActivity", "Ping received from Flutter")
                        result.success("pong")
                    }
                    "generateKeyBundle" -> {
                        Log.d("MainActivity", "generateKeyBundle called - generating REAL keys!")
                        generateRealKeyBundle(result)
                    }
                    "initSession" -> {
                        Log.d("MainActivity", "initSession called")
                        initSessionWithSessionManager(call, result)
                    }
                    "encryptMessage" -> {
                        Log.d("MainActivity", "encryptMessage called")
                        encryptMessageWithSessionManager(call, result)
                    }
                    "decryptMessage" -> {
                        Log.d("MainActivity", "decryptMessage called")
                        decryptMessage(call, result)
                    }
                    "clearSession" -> {
                        Log.d("MainActivity", "clearSession called")
                        clearSessionForUser(call, result)
                    }
                    "hasSession" -> {
                        Log.d("MainActivity", "hasSession called")
                        hasSessionForUser(call, result)
                    }
                    "hasKeys" -> {
                        Log.d("MainActivity", "hasKeys called")
                        hasKeysForUser(call, result)
                    }
                    "restoreSessionState" -> {
                        Log.d("MainActivity", "restoreSessionState called")
                        restoreSessionStateForUser(call, result)
                    }
                    "getFCMToken" -> {
                        val sharedPrefs = getSharedPreferences("zarq_fcm", Context.MODE_PRIVATE)
                        val token = sharedPrefs.getString("fcm_token", null)
                        result.success(token)
                    }
                    "getAuthToken" -> {
                        // Get current Firebase Auth token
                        val user = FirebaseAuth.getInstance().currentUser
                        user?.getIdToken(true)?.addOnCompleteListener { task ->
                            if (task.isSuccessful) {
                                result.success(task.result?.token)
                            } else {
                                result.error("AUTH_ERROR", "Failed to get auth token", null)
                            }
                        } ?: result.error("NO_USER", "No authenticated user", null)
                    }
                    "getStoredSentMessages" -> {
                        getStoredSentMessages(call, result)
                    }

                    "getSessionStats" -> {
                        Log.d("MainActivity", "getSessionStats called")
                        getSessionStatsForUser(call, result)
                    }
                    "setCurrentUser" -> {
                        val uid = call.argument<String>("uid")
                        currentUserUid = uid
                        Log.d("MainActivity", "Set current user for testing: $uid")
                        result.success(true)
                    }

                    "captureSessionContext" -> {
                        Log.d("MainActivity", "captureSessionContext called")
                        captureSessionContext(call, result)
                    }
                    "applySessionContext" -> {
                        Log.d("MainActivity", "applySessionContext called")
                        applySessionContext(call, result)
                    }

                    "checkUserSetup" -> {
                        val uid = call.argument<String>("uid")
                        if (uid != null) {
                            runBlocking {
                                try {
                                    val hasSetup = protocolManager.checkUserSetup(uid)
                                    result.success(hasSetup)
                                } catch (e: Exception) {
                                    result.error("SETUP_CHECK_ERROR", e.message, null)
                                }
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing UID", null)
                        }
                    }
                    "setupUser" -> {
                        val uid = call.argument<String>("uid")
                        if (uid != null) {
                            runBlocking {
                                try {
                                    val success = protocolManager.setupUser(uid)
                                    result.success(success)
                                } catch (e: Exception) {
                                    result.error("SETUP_ERROR", e.message, null)
                                }
                            }
                        } else {
                            result.error("INVALID_ARGS", "Missing UID", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        Log.d("MainActivity", "MethodChannel ready on $CHANNEL")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                Log.w("MainActivity", "Fetching FCM registration token failed", task.exception)
                return@addOnCompleteListener
            }

            val token = task.result
            Log.d("MainActivity", "FCM Token retrieved: ${token?.substring(0, 20)}...")
        }

        Log.d(TAG, "MainActivity onCreate")

        requestNotificationPermission()
        // Handle notification intent when app is launched
        handleNotificationIntent(intent)

        // Set up navigation channel for Kotlin-Flutter communication
        setupNavigationChannel()
    }


    /**
     * Get session statistics for debugging
     */
    private fun getSessionStatsForUser(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid") ?: currentUserUid ?: ""

            if (myUid.isEmpty()) {
                result.error("NO_USER", "No current user set for testing", null)
                return
            }

            val sessionManager = sessionManagers[myUid]
            if (sessionManager == null) {
                result.success(mapOf(
                    "error" to "No session manager found for user",
                    "myUid" to myUid
                ))
                return
            }

            val stats = sessionManager.getSessionStats()
            Log.d("MainActivity", "Session stats for $myUid: $stats")
            result.success(stats)

        } catch (e: Exception) {
            Log.e("MainActivity", "getSessionStatsForUser error: ${e.message}", e)
            result.error("STATS_FAILED", e.message ?: "Unknown error", null)
        }
    }


    // ===== EXISTING METHODS (unchanged) =====

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
                Log.d("MainActivity", "Notification permission granted")
            } else {
                Log.w("MainActivity", "Notification permission denied")
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

    /**
     * Get or create SessionManager for a user
     */
    private fun getSessionManager(uid: String): SessionManager {
        return sessionManagers.getOrPut(uid) {
            try {
                Log.d("MainActivity", "Creating SessionManager for: $uid")
                val preKeyManager = PreKeyManager(this, uid, signalStore, protocolManager)
                val sessionManager = SessionManager(this, uid, signalStore, protocolManager, preKeyManager)
                Log.d("MainActivity", "SessionManager created successfully for: $uid")
                sessionManager
            } catch (e: Exception) {
                Log.e("MainActivity", "Failed to create SessionManager for $uid: ${e.message}", e)
                throw e  // Re-throw so getOrPut doesn't cache null
            }
        }
    }

    private fun restoreSessionStateForUser(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val recipientUid = call.argument<String>("recipientUid")

            if (myUid == null || recipientUid == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            // Check if session data exists in storage
            val sessionExists = signalStore.loadSessionBlobBase64(recipientUid, 1) != null

            if (sessionExists) {
                // Ensure SessionManager is in cache
                getSessionManager(myUid)
                Log.d("MainActivity", "Session state restored for $myUid -> $recipientUid")
                result.success(true)
            } else {
                Log.d("MainActivity", "No session data found for $myUid -> $recipientUid")
                result.success(false)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error restoring session state: ${e.message}", e)
            result.success(false)
        }
    }

    private fun hasKeysForUser(call: MethodCall, result: MethodChannel.Result) {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser
            if (currentUser == null) {
                result.success(false)
                return
            }

            val uid = currentUser.uid
            Log.d("MainActivity", "Checking if keys exist for UID: $uid")

            // Check if essential keys exist in SignalStore
            val hasIdentity = signalStore.loadPublicKeyBase64(uid, "identity") != null
            val hasRegId = signalStore.loadPublicKeyBase64(uid, "regid") != null
            val signedPreKeyIds = signalStore.listSignedPreKeyIds(uid)
            val preKeyIds = signalStore.listPreKeyIds(uid)

            val hasKeys = hasIdentity && hasRegId && signedPreKeyIds.isNotEmpty() && preKeyIds.isNotEmpty()

            Log.d("MainActivity", "Keys check: identity=$hasIdentity, regId=$hasRegId, signedPreKeys=${signedPreKeyIds.size}, preKeys=${preKeyIds.size}")
            Log.d("MainActivity", "Final result: hasKeys=$hasKeys")

            result.success(hasKeys)

        } catch (e: Exception) {
            Log.e("MainActivity", "Error checking keys: ${e.message}", e)
            result.success(false)
        }
    }

    private fun hasSessionForUser(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val recipientUid = call.argument<String>("recipientUid")

            if (myUid == null || recipientUid == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            Log.d("MainActivity", "=== SESSION CHECK START ===")
            Log.d("MainActivity", "Checking session existence: $myUid -> $recipientUid")
            Log.d("MainActivity", "Total cached SessionManagers: ${sessionManagers.size}")

            // Log all cached session managers
            sessionManagers.keys.forEach { uid ->
                Log.d("MainActivity", "Cached SessionManager for UID: $uid")
            }

            runBlocking {
                try {
                    // Check if we have a session manager for this user
                    val sessionManager = sessionManagers[myUid]
                    if (sessionManager == null) {
                        Log.w("MainActivity", "❌ No SessionManager found for $myUid")
                        Log.d("MainActivity", "Available SessionManagers: ${sessionManagers.keys}")
                        result.success(false)
                        return@runBlocking
                    } else {
                        Log.d("MainActivity", "✅ SessionManager exists for $myUid")
                    }

                    // Get session stats if available
                    try {
                        val stats = sessionManager.getSessionStats()
                        Log.d("MainActivity", "Session stats for $myUid: $stats")
                    } catch (e: Exception) {
                        Log.w("MainActivity", "Could not get session stats: ${e.message}")
                    }

                    Log.d("MainActivity", "Testing session with encryption test...")

                    // Test if session exists by attempting a simple encryption
                    val testResult = protocolManager.encrypt(
                        myUid = myUid,
                        recipientUid = recipientUid,
                        recipientDeviceId = 1,
                        plaintext = "test".toByteArray()
                    )

                    val hasSession = testResult != null

                    if (hasSession) {
                        Log.d("MainActivity", "✅ Session exists and working: $myUid -> $recipientUid")
                        Log.d("MainActivity", "Test encryption successful (${testResult?.length} chars)")
                    } else {
                        Log.w("MainActivity", "❌ Session test failed: encryption returned null")
                    }

                    Log.d("MainActivity", "=== SESSION CHECK END: $hasSession ===")
                    result.success(hasSession)

                } catch (e: Exception) {
                    Log.e("MainActivity", "❌ Session test exception: ${e.message}")
                    Log.e("MainActivity", "Exception type: ${e.javaClass.simpleName}")
                    Log.e("MainActivity", "Stack trace: ${e.stackTrace.take(3).joinToString()}")
                    Log.d("MainActivity", "=== SESSION CHECK END: false (exception) ===")
                    result.success(false)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "hasSessionForUser error: ${e.message}", e)
            result.success(false)
        }
    }

    private fun generateRealKeyBundle(result: MethodChannel.Result) {
        try {
            // Get current Firebase user UID
            val currentUser = FirebaseAuth.getInstance().currentUser
            if (currentUser == null) {
                result.error("NO_USER", "No authenticated Firebase user", null)
                return
            }
            val uid = currentUser.uid
            currentUserUid = uid // Set for testing
            Log.d("MainActivity", "Generating keys for UID: $uid")

            runBlocking {
                try {
                    // Initialize PreKeyManager
                    val preKeyManager = PreKeyManager(
                        context = this@MainActivity,
                        uid = uid,
                        signalStore = signalStore,
                        protocolManager = protocolManager
                    )

                    // Generate complete key bundle (identity + signed prekey + one-time prekeys)
                    val bundleJson = preKeyManager.prepareAndExportBundle(forceRotateSigned = true)

                    if (bundleJson == null) {
                        result.error("KEY_GEN_FAILED", "Failed to generate key bundle", null)
                        return@runBlocking
                    }

                    // Parse the JSON bundle from PreKeyManager
                    val bundle = JSONObject(bundleJson)
                    Log.d("MainActivity", "Generated bundle JSON: $bundleJson")

                    // Get registration ID (stored as base64 in SignalStore)
                    val regIdB64 = signalStore.loadPublicKeyBase64(uid, "regid")
                    val registrationId = if (regIdB64 != null) {
                        val regBytes = Base64.decode(regIdB64, Base64.NO_WRAP)
                        byteArrayToInt(regBytes)
                    } else {
                        Log.w("MainActivity", "No registration ID found, using default")
                        123456 // fallback
                    }

                    // Get the FULL SERIALIZED signed prekey record
                    val signedPreKeyId = bundle.getInt("signedPreKeyId")
                    val fullSignedPreKeyB64 = signalStore.loadSignedPreKeyBase64(uid, signedPreKeyId)

                    if (fullSignedPreKeyB64 == null) {
                        result.error("SIGNED_PREKEY_MISSING", "Full signed prekey record not found", null)
                        return@runBlocking
                    }

                    // Get the FULL SERIALIZED one-time prekey record
                    val oneTimePreKeysList = mutableListOf<Map<String, Any>>()
                    val preKeyIds = signalStore.listPreKeyIds(uid)
                    val preKeysToSend = preKeyIds.take(100) // Send up to 100 prekeys

                    for (keyId in preKeysToSend) {
                        val fullPreKeyB64 = signalStore.loadPreKeyBase64(uid, keyId)
                        if (fullPreKeyB64 != null) {
                            oneTimePreKeysList.add(mapOf(
                                "key_id" to keyId,
                                "public_key_b64" to fullPreKeyB64
                            ))
                        }
                    }

                    Log.d("MainActivity", "Sending ${oneTimePreKeysList.size} one-time prekeys to server")


                    // Format response to send FULL SERIALIZED RECORDS (not just public keys)
                    val response = mapOf(
                        "identity_key_b64" to bundle.getString("identity"),
                        "registration_id" to registrationId,
                        "signed_prekey_id" to signedPreKeyId,
                        "signed_prekey_b64" to fullSignedPreKeyB64,
                        "signed_prekey_signature_b64" to bundle.getString("signedPreKeySignature"),
                        "one_time_prekeys" to oneTimePreKeysList // Send multiple prekeys
                    )

                    Log.d("MainActivity", "Successfully generated real key bundle with ${response.size} fields")
                    Log.d("MainActivity", "Signed prekey record size: ${fullSignedPreKeyB64.length} chars")

                    result.success(response)

                } catch (e: Exception) {
                    Log.e("MainActivity", "Error in key generation coroutine: ${e.message}", e)
                    result.error("CRYPTO_ERROR", "Cryptographic error: ${e.message}", null)
                }
            }

        } catch (e: Exception) {
            Log.e("MainActivity", "Error generating key bundle: ${e.message}", e)
            result.error("UNEXPECTED_ERROR", "Unexpected error: ${e.message}", null)
        }
    }

    private fun initSessionWithSessionManager(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val recipientUid = call.argument<String>("recipientUid")

            if (myUid == null || recipientUid == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            currentUserUid = myUid
            Log.d("MainActivity", "Initializing session: $myUid -> $recipientUid")

            runBlocking {
                try {
                    val sessionManager = getSessionManager(myUid)
                    val success = sessionManager.ensureSession(recipientUid)

                    Log.d("MainActivity", "Session establishment result: $success")
                    result.success(success)

                } catch (e: Exception) {
                    Log.e("MainActivity", "Session initialization error: ${e.message}", e)
                    result.error("SESSION_INIT_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "initSessionWithSessionManager error: ${e.message}", e)
            result.error("UNEXPECTED_ERROR", e.message, null)
        }
    }

    private fun encryptMessageWithSessionManager(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val recipientUid = call.argument<String>("recipientUid")
            val plaintext = call.argument<String>("plaintext")
            val recipientDeviceId = call.argument<Int>("recipientDeviceId") ?: 1

            if (myUid == null || recipientUid == null || plaintext == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            currentUserUid = myUid
            Log.d("MainActivity", "Encrypting message: $myUid -> $recipientUid")

            runBlocking {
                try {
                    val sessionManager = getSessionManager(myUid)

                    // Ensure session exists
                    val sessionReady = sessionManager.ensureSession(recipientUid, recipientDeviceId)
                    if (!sessionReady) {
                        Log.e("MainActivity", "Failed to establish session for encryption")
                        result.error("SESSION_NOT_READY", "Unable to establish session", null)
                        return@runBlocking
                    }

                    // Encrypt the message
                    val ciphertextB64 = protocolManager.encrypt(
                        myUid = myUid,
                        recipientUid = recipientUid,
                        recipientDeviceId = recipientDeviceId,
                        plaintext = plaintext.toByteArray()
                    )

                    if (ciphertextB64 != null) {
                        Log.d("MainActivity", "Message encrypted successfully (${ciphertextB64.length} chars)")
                        result.success(ciphertextB64)
                    } else {
                        Log.e("MainActivity", "Encryption failed")
                        result.error("ENCRYPTION_FAILED", "Failed to encrypt message", null)
                    }

                } catch (e: Exception) {
                    Log.e("MainActivity", "Encryption error: ${e.message}", e)
                    result.error("ENCRYPTION_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "encryptMessageWithSessionManager error: ${e.message}", e)
            result.error("UNEXPECTED_ERROR", e.message, null)
        }
    }

    /**
     * Decrypt a received message
     */
    private fun decryptMessage(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val senderUid = call.argument<String>("senderUid")
            val ciphertextB64 = call.argument<String>("ciphertextB64")
            val senderDeviceId = call.argument<Int>("senderDeviceId") ?: 1

            if (myUid == null || senderUid == null || ciphertextB64 == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            currentUserUid = myUid // Set for testing
            Log.d("MainActivity", "Decrypting message from $senderUid (device $senderDeviceId) to $myUid")

            runBlocking {
                try {
                    val plaintextBytes = protocolManager.decrypt(
                        myUid = myUid,
                        senderUid = senderUid,
                        senderDeviceId = senderDeviceId,
                        wireBase64 = ciphertextB64
                    )

                    if (plaintextBytes != null) {
                        val plaintext = String(plaintextBytes)
                        Log.d("MainActivity", "Message decrypted successfully: $plaintext")
                        result.success(plaintext)
                    } else {
                        Log.e("MainActivity", "Decryption returned null")
                        result.error("DECRYPTION_FAILED", "Failed to decrypt message", null)
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "Decryption error: ${e.message}", e)
                    result.error("DECRYPTION_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "decryptMessage error: ${e.message}", e)
            result.error("UNEXPECTED_ERROR", e.message, null)
        }
    }

    /**
     * Clear session for recovery or logout
     */
    private fun clearSessionForUser(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val recipientUid = call.argument<String>("recipientUid")
            val clearAll = call.argument<Boolean>("clearAll") ?: false

            if (myUid == null) {
                result.error("INVALID_ARGS", "Missing myUid", null)
                return
            }

            currentUserUid = myUid // Set for testing

            runBlocking {
                try {
                    val sessionManager = getSessionManager(myUid)

                    if (clearAll) {
                        sessionManager.clearAllSessions()
                        sessionManagers.remove(myUid) // Remove from cache
                        Log.d("MainActivity", "Cleared all sessions for $myUid")
                    } else if (recipientUid != null) {
                        sessionManager.clearSession(recipientUid, 1)
                        Log.d("MainActivity", "Cleared session: $myUid -> $recipientUid")
                    }

                    result.success(true)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error clearing session: ${e.message}", e)
                    result.error("CLEAR_SESSION_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "clearSessionForUser error: ${e.message}", e)
            result.error("UNEXPECTED_ERROR", e.message, null)
        }
    }



    /**
     * Convert byte array to int (big-endian)
     */
    private fun byteArrayToInt(bytes: ByteArray): Int {
        if (bytes.size < 4) return 0
        return (bytes[0].toInt() and 0xFF shl 24) or
                (bytes[1].toInt() and 0xFF shl 16) or
                (bytes[2].toInt() and 0xFF shl 8) or
                (bytes[3].toInt() and 0xFF)
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

    private fun setupNavigationChannel() {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            val channel = MethodChannel(messenger, NAVIGATION_CHANNEL)

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

    private fun getStoredSentMessages(call: MethodCall, result: MethodChannel.Result) {
        try {
            val conversationId = call.argument<Int>("conversation_id")

            if (conversationId == null) {
                result.error("INVALID_ARGS", "Missing conversation_id", null)
                return
            }

            val sharedPrefs = getSharedPreferences("zarq_sent_messages", Context.MODE_PRIVATE)
            val allMessages = mutableListOf<Map<String, Any>>()

            // Get all stored messages
            val allPrefs = sharedPrefs.all
            for ((key, value) in allPrefs) {
                if (key.startsWith("msg_") && value is String) {
                    try {
                        val messageJson = JSONObject(value)
                        val msgConversationId = messageJson.getInt("conversation_id")

                        if (msgConversationId == conversationId) {
                            allMessages.add(mapOf(
                                "id" to messageJson.getLong("id"),
                                "conversation_id" to msgConversationId,
                                "content" to messageJson.getString("content"),
                                "timestamp" to messageJson.getLong("timestamp")
                            ))
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error parsing stored message: $e")
                    }
                }
            }

            // Sort by timestamp
            allMessages.sortBy { it["timestamp"] as Long }

            Log.d("MainActivity", "Found ${allMessages.size} stored sent messages for conversation $conversationId")
            result.success(allMessages)

        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting stored sent messages: ${e.message}", e)
            result.error("STORAGE_ERROR", e.message, null)
        }
    }

    suspend fun fetchPrekeyBundle(targetUid: String, deviceId: Int): Map<String, Any>? = withContext(Dispatchers.IO) {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser
            if (currentUser == null) {
                Log.e("MainActivity", "No authenticated user for prekey bundle fetch")
                return@withContext null
            }

            Log.d("MainActivity", "fetchPrekeyBundle: Current user UID = ${currentUser.uid}")
            Log.d("MainActivity", "fetchPrekeyBundle: Getting fresh token...")

            val token = currentUser.getIdToken(true).await()
            val url = "http://192.168.29.81:8080/v1/prekey_bundle?uid=$targetUid&device_id=$deviceId"

            Log.d("MainActivity", "Fetching prekey bundle: $url")

            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $token")
                .get()
                .build()

            val response = okHttpClient.newCall(request).execute()

            if (response.isSuccessful) {
                val responseBody = response.body?.string()
                if (responseBody != null) {
                    val jsonObject = JSONObject(responseBody)
                    val result = mutableMapOf<String, Any>()

                    // Parse the response to match your expected format
                    result["firebase_uid"] = jsonObject.optString("firebase_uid", targetUid)
                    result["device_id"] = jsonObject.optInt("device_id", deviceId)
                    result["identity_key_b64"] = jsonObject.optString("identity_key_b64", "")
                    result["registration_id"] = jsonObject.optInt("registration_id", 0)

                    // Handle signed prekey object
                    val signedPrekey = jsonObject.optJSONObject("signed_prekey")
                    if (signedPrekey != null) {
                        result["signed_prekey"] = mapOf(
                            "key_id" to signedPrekey.optInt("key_id", 0),
                            "public_key_b64" to signedPrekey.optString("public_key_b64", ""),
                            "signature_b64" to signedPrekey.optString("signature_b64", "")
                        )
                    }

                    // Handle one-time prekey
                    val oneTimePrekey = jsonObject.optString("one_time_prekey_b64")
                    if (oneTimePrekey.isNotEmpty()) {
                        result["one_time_prekey_b64"] = oneTimePrekey
                    }

                    Log.d("MainActivity", "Successfully fetched prekey bundle for $targetUid")
                    return@withContext result
                }
            } else {
                Log.e("MainActivity", "Prekey bundle fetch failed: ${response.code} - ${response.message}")
            }

        } catch (e: Exception) {
            Log.e("MainActivity", "Error fetching prekey bundle: ${e.message}", e)
        }

        return@withContext null
    }

    suspend fun storeSharedSession(sessionKey: String, sessionData: ByteArray): Boolean = withContext(Dispatchers.IO) {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser
            if (currentUser == null) {
                Log.e("MainActivity", "No authenticated user for session storage")
                return@withContext false
            }

            val token = currentUser.getIdToken(false).await()
            val sessionDataB64 = Base64.encodeToString(sessionData, Base64.NO_WRAP)

            val requestBody = JSONObject().apply {
                put("session_key", sessionKey)
                put("session_data", sessionDataB64)
            }

            val request = Request.Builder()
                .url("http://192.168.29.81:8080/v1/sessions")
                .addHeader("Authorization", "Bearer $token")
                .addHeader("Content-Type", "application/json")
                .post(RequestBody.create("application/json".toMediaType(), requestBody.toString()))
                .build()

            val response = okHttpClient.newCall(request).execute()

            Log.d("MainActivity", "storeSharedSession result: ${response.code}")
            return@withContext response.isSuccessful

        } catch (e: Exception) {
            Log.e("MainActivity", "Error storing shared session: ${e.message}", e)
            return@withContext false
        }
    }

    suspend fun loadSharedSession(sessionKey: String): ByteArray? = withContext(Dispatchers.IO) {
        try {
            val currentUser = FirebaseAuth.getInstance().currentUser
            if (currentUser == null) {
                Log.e("MainActivity", "No authenticated user for session loading")
                return@withContext null
            }

            val token = currentUser.getIdToken(false).await()
            val url = "http://192.168.29.81:8080/v1/sessions?session_key=${URLEncoder.encode(sessionKey, "UTF-8")}"

            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $token")
                .get()
                .build()

            val response = okHttpClient.newCall(request).execute()

            if (response.isSuccessful) {
                val responseBody = response.body?.string()
                if (responseBody != null) {
                    val jsonObject = JSONObject(responseBody)
                    val sessionDataB64 = jsonObject.getString("session_data")
                    return@withContext Base64.decode(sessionDataB64, Base64.NO_WRAP)
                }
            } else if (response.code == 404) {
                Log.d("MainActivity", "Session not found: $sessionKey")
                return@withContext null
            } else {
                Log.e("MainActivity", "loadSharedSession failed: ${response.code}")
            }

            return@withContext null

        } catch (e: Exception) {
            Log.e("MainActivity", "Error loading shared session: ${e.message}", e)
            return@withContext null
        }
    }

    private fun captureSessionContext(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val recipientUid = call.argument<String>("recipientUid")
            val recipientDeviceId = call.argument<Int>("recipientDeviceId") ?: 1

            if (myUid == null || recipientUid == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            Log.d("MainActivity", "captureSessionContext: $myUid -> $recipientUid")

            runBlocking {
                try {
                    val sessionManager = getSessionManager(myUid)
                    val sessionContextB64 = protocolManager.captureSessionContext(myUid, recipientUid, recipientDeviceId)

                    if (sessionContextB64 != null) {
                        Log.d("MainActivity", "Session context captured successfully")
                        result.success(sessionContextB64)
                    } else {
                        Log.e("MainActivity", "Failed to capture session context")
                        result.success(null)
                    }
                } catch (e: Exception) {
                    Log.e("MainActivity", "captureSessionContext error: ${e.message}", e)
                    result.error("CAPTURE_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "captureSessionContext outer error: ${e.message}", e)
            result.error("UNEXPECTED_ERROR", e.message, null)
        }
    }

    private fun applySessionContext(call: MethodCall, result: MethodChannel.Result) {
        try {
            val myUid = call.argument<String>("myUid")
            val senderUid = call.argument<String>("senderUid")
            val sessionContextB64 = call.argument<String>("sessionContextB64")
            val senderDeviceId = call.argument<Int>("senderDeviceId") ?: 1

            if (myUid == null || senderUid == null || sessionContextB64 == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            Log.d("MainActivity", "applySessionContext: $myUid <- $senderUid")

            runBlocking {
                try {
                    val sessionManager = getSessionManager(myUid)
                    val success = protocolManager.applySessionContext(myUid, senderUid, senderDeviceId, sessionContextB64)

                    Log.d("MainActivity", "Session context applied: $success")
                    result.success(success)
                } catch (e: Exception) {
                    Log.e("MainActivity", "applySessionContext error: ${e.message}", e)
                    result.error("APPLY_ERROR", e.message, null)
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "applySessionContext outer error: ${e.message}", e)
            result.error("UNEXPECTED_ERROR", e.message, null)
        }
    }
}