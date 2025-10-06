package com.example.zarq_messenger

import android.Manifest
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.messaging.FirebaseMessaging
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    // Method channels
    private val SIGNAL_CHANNEL = "com.zarq/signal"
    private val NAVIGATION_CHANNEL = "com.zarq/navigation"
    private val BACKUP_CHANNEL = "com.zarq/backup"
    private val OVERLAY_CHANNEL = "com.zarq/overlay"

    companion object {
        private const val TAG = "MainActivity"
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
        var flutterEngineInstance: FlutterEngine? = null
    }

    // Store pending incoming call to process after Flutter is ready
    private var pendingIncomingCall: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngineInstance = flutterEngine

        // Set up Signal Protocol Method Channel
        setupSignalMethodChannel(flutterEngine)

        // Set up existing navigation and utility channels
        setupUtilityMethodChannel(flutterEngine)
        setupNavigationChannel(flutterEngine)
        setupBackupMethodChannel(flutterEngine)
        setupPipChannel(flutterEngine)
        setupOverlayChannel(flutterEngine)

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

    // Initialize managers
    private val signalManager by lazy { SignalManager(this) }
    private val backupNotificationHelper by lazy { BackupNotificationHelper(this) }

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

            "getIdentityKeyPrivateKey" -> {
                try {
                    Log.d(TAG, "getIdentityKeyPrivateKey called for database encryption")
                    val privateKey = signalManager.getIdentityKeyPairPrivateKey()
                    if (privateKey != null) {
                        result.success(privateKey)
                    } else {
                        result.error("IDENTITY_KEY_ERROR", "Identity key not found", null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "getIdentityKeyPrivateKey error: $e")
                    result.error("IDENTITY_KEY_ERROR", e.message, null)
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

                    Log.d(TAG, "MainActivity: Encrypting for $recipientUid:$deviceId")
                    val ciphertext = signalManager.encryptMessage(recipientUid, plaintext, deviceId)

                    // Add debug session state after encryption
                    if (ciphertext != null) {
                        signalManager.debugSessionState(recipientUid, deviceId, "AFTER_ENCRYPT")
                        signalManager.testSessionPersistence(recipientUid, deviceId)
                    }

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
                    val senderDeviceId = call.argument<Int>("senderDeviceId")
                        ?: throw Exception("Missing senderDeviceId")

                    Log.d(TAG, "MainActivity: Decrypting from $senderUid:$senderDeviceId")
                    val plaintext = signalManager.decryptMessage(senderUid, ciphertextB64, senderDeviceId)

                    // Add debug session state after decryption
                    if (plaintext != null) {
                        signalManager.debugSessionState(senderUid, senderDeviceId, "AFTER_DECRYPT")
                    }

                    result.success(plaintext)
                } catch (e: Exception) {
                    Log.e(TAG, "decryptMessage error: $e")
                    result.error("DECRYPT_MESSAGE_ERROR", e.message, null)
                }
            }

            "isSessionValidForSending" -> {
                try {
                    val recipientUid = call.argument<String>("recipientUid") ?: throw Exception("Missing recipientUid")
                    val deviceId = call.argument<Int>("deviceId") ?: throw Exception("Missing deviceId")

                    val isValid = signalManager.isSessionValidForSending(recipientUid, deviceId)
                    result.success(isValid)
                } catch (e: Exception) {
                    result.error("SESSION_VALIDATION_ERROR", e.message, null)
                }
            }

            "resetSessionDueToDecryptionFailure" -> {
                try {
                    Log.d(TAG, "resetSessionDueToDecryptionFailure called")
                    val senderUid = call.argument<String>("senderUid") ?: throw Exception("Missing senderUid")
                    val senderDeviceId = call.argument<Int>("senderDeviceId") ?: throw Exception("Missing senderDeviceId")

                    signalManager.resetSessionDueToDecryptionFailure(senderUid, senderDeviceId)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "resetSessionDueToDecryptionFailure error: $e")
                    result.error("SESSION_RESET_ERROR", e.message, null)
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

                    Log.d(TAG, "MainActivity: EncryptWithSetup for $recipientUid:$deviceId, hasBundle: ${prekeyBundle != null}")
                    val ciphertext = signalManager.encryptMessageWithSessionSetup(recipientUid, plaintext, prekeyBundle, deviceId)

                    // Add debug session state after setup and encryption
                    if (ciphertext != null) {
                        signalManager.debugSessionState(recipientUid, deviceId, "AFTER_SETUP_AND_ENCRYPT")
                    }

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

            "getLocalSentMessage" -> {
                try {
                    val messageId = call.argument<Int>("messageId") ?: -1
                    val myUid = FirebaseAuth.getInstance().currentUser?.uid

                    Log.d(TAG, "=== RETRIEVING LOCAL MESSAGE ===")
                    Log.d(TAG, "MessageId: $messageId")
                    Log.d(TAG, "MyUid: $myUid")

                    if (myUid == null) {
                        Log.d(TAG, "No user logged in")
                        result.success(null)
                        return
                    }

                    val sharedPrefs = getSharedPreferences("zarq_sent_messages_$myUid", MODE_PRIVATE)
                    val key = "msg_${messageId}"
                    Log.d(TAG, "Looking for key: $key")

                    // Debug: List all keys in SharedPreferences
                    val allKeys = sharedPrefs.all.keys
                    Log.d(TAG, "All stored keys: $allKeys")

                    val messageJson = sharedPrefs.getString(key, null)

                    if (messageJson != null) {
                        Log.d(TAG, "Found message: $messageJson")
                        val json = JSONObject(messageJson)
                        result.success(json.getString("content"))
                    } else {
                        Log.d(TAG, "Message not found for key: $key")
                        result.success(null)
                    }
                    Log.d(TAG, "=== END RETRIEVING ===")
                } catch (e: Exception) {
                    Log.e(TAG, "Error retrieving local message", e)
                    result.error("ERROR", e.message, null)
                }
            }

            "getLocalSentMessagesBatch" -> {
                try {
                    val messageIds = call.argument<List<Int>>("messageIds") ?: emptyList()
                    val myUid = FirebaseAuth.getInstance().currentUser?.uid

                    Log.d(TAG, "=== BATCH RETRIEVING ${messageIds.size} MESSAGES ===")

                    if (myUid == null) {
                        Log.d(TAG, "No user logged in")
                        result.success(emptyMap<Int, String>())
                        return
                    }

                    val sharedPrefs = getSharedPreferences("zarq_sent_messages_$myUid", MODE_PRIVATE)
                    val resultMap = mutableMapOf<Int, String>()

                    for (msgId in messageIds) {
                        val key = "msg_${msgId}"
                        val messageJson = sharedPrefs.getString(key, null)

                        if (messageJson != null) {
                            try {
                                val json = JSONObject(messageJson)
                                resultMap[msgId] = json.getString("content")
                                Log.d(TAG, "Found message $msgId")
                            } catch (e: Exception) {
                                Log.e(TAG, "Error parsing message $msgId: ${e.message}")
                            }
                        }
                    }

                    Log.d(TAG, "Returning ${resultMap.size} messages from batch")
                    Log.d(TAG, "=== END BATCH RETRIEVING ===")

                    result.success(resultMap)
                } catch (e: Exception) {
                    Log.e(TAG, "Error batch retrieving messages", e)
                    result.error("ERROR", e.message, null)
                }
            }

            "getKeyBundleForRegistration" -> {
                try {
                    Log.d(TAG, "getKeyBundleForRegistration called")
                    val keyBundle = signalManager.getKeyBundleForRegistration()
                    result.success(keyBundle)
                } catch (e: Exception) {
                    Log.e(TAG, "getKeyBundleForRegistration error: $e")
                    result.error("GET_KEY_BUNDLE_ERROR", e.message, null)
                }
            }

            "exportSignalState" -> {
                try {
                    Log.d(TAG, "exportSignalState called")
                    val signalState = signalManager.exportSignalState()
                    result.success(signalState)
                } catch (e: Exception) {
                    Log.e(TAG, "exportSignalState error: $e")
                    result.error("EXPORT_SIGNAL_STATE_ERROR", e.message, null)
                }
            }

            "importSignalState" -> {
                try {
                    Log.d(TAG, "importSignalState called")
                    val signalStateJson = call.argument<String>("signalState")
                        ?: throw Exception("Missing signalState parameter")
                    val success = signalManager.importSignalState(signalStateJson)
                    result.success(success)
                } catch (e: Exception) {
                    Log.e(TAG, "importSignalState error: $e")
                    result.error("IMPORT_SIGNAL_STATE_ERROR", e.message, null)
                }
            }

            // ========== GROUP ENCRYPTION METHODS ==========
            "createSenderKeyDistribution" -> {
                try {
                    Log.d(TAG, "createSenderKeyDistribution called")
                    val groupId = call.argument<String>("groupId")
                        ?: throw Exception("Missing groupId")

                    val distributionMessage = signalManager.createSenderKeyDistribution(groupId)
                    result.success(distributionMessage)
                } catch (e: Exception) {
                    Log.e(TAG, "createSenderKeyDistribution error", e)
                    result.error("SENDER_KEY_ERROR", e.message, null)
                }
            }

            "processSenderKeyDistribution" -> {
                try {
                    Log.d(TAG, "processSenderKeyDistribution called")
                    val senderUid = call.argument<String>("senderUid")
                        ?: throw Exception("Missing senderUid")
                    val senderDeviceId = call.argument<Int>("senderDeviceId")
                        ?: throw Exception("Missing senderDeviceId")
                    val groupId = call.argument<String>("groupId")
                        ?: throw Exception("Missing groupId")
                    val distributionMessage = call.argument<String>("distributionMessage")
                        ?: throw Exception("Missing distributionMessage")

                    val success = signalManager.processSenderKeyDistribution(
                        senderUid, senderDeviceId, groupId, distributionMessage
                    )
                    result.success(success)
                } catch (e: Exception) {
                    Log.e(TAG, "processSenderKeyDistribution error", e)
                    result.error("SENDER_KEY_ERROR", e.message, null)
                }
            }

            "encryptGroupMessage" -> {
                try {
                    Log.d(TAG, "encryptGroupMessage called")
                    val groupId = call.argument<String>("groupId")
                        ?: throw Exception("Missing groupId")
                    val plaintext = call.argument<String>("plaintext")
                        ?: throw Exception("Missing plaintext")

                    val ciphertext = signalManager.encryptGroupMessage(groupId, plaintext)
                    result.success(ciphertext)
                } catch (e: Exception) {
                    Log.e(TAG, "encryptGroupMessage error", e)
                    result.error("ENCRYPTION_ERROR", e.message, null)
                }
            }

            "decryptGroupMessage" -> {
                try {
                    Log.d(TAG, "decryptGroupMessage called")
                    val senderUid = call.argument<String>("senderUid")
                        ?: throw Exception("Missing senderUid")
                    val senderDeviceId = call.argument<Int>("senderDeviceId")
                        ?: throw Exception("Missing senderDeviceId")
                    val groupId = call.argument<String>("groupId")
                        ?: throw Exception("Missing groupId")
                    val ciphertext = call.argument<String>("ciphertext")
                        ?: throw Exception("Missing ciphertext")

                    val plaintext = signalManager.decryptGroupMessage(
                        senderUid, senderDeviceId, groupId, ciphertext
                    )
                    result.success(plaintext)
                } catch (e: Exception) {
                    Log.e(TAG, "decryptGroupMessage error", e)
                    result.error("DECRYPTION_ERROR", e.message, null)
                }
            }

            "clearGroupSenderKeys" -> {
                try {
                    Log.d(TAG, "clearGroupSenderKeys called")
                    val groupId = call.argument<String>("groupId")
                        ?: throw Exception("Missing groupId")

                    signalManager.clearGroupSenderKeys(groupId)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "clearGroupSenderKeys error", e)
                    result.error("SENDER_KEY_ERROR", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }



    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d(TAG, "============================================")
        Log.d(TAG, "MainActivity onCreate CALLED")
        Log.d(TAG, "Intent action: ${intent.action}")
        Log.d(TAG, "Intent extras: ${intent.extras?.keySet()?.joinToString()}")
        Log.d(TAG, "============================================")

        // Initialize FCM token
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                Log.w(TAG, "Fetching FCM registration token failed", task.exception)
                return@addOnCompleteListener
            }

            val token = task.result
            Log.d(TAG, "FCM Token retrieved: ${token?.substring(0, 20)}...")
        }

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

        Log.d(TAG, "============================================")
        Log.d(TAG, "MainActivity onNewIntent CALLED")
        Log.d(TAG, "Intent action: ${intent.action}")
        Log.d(TAG, "Intent extras: ${intent.extras?.keySet()?.joinToString()}")
        Log.d(TAG, "============================================")

        // Handle notification intent when app is already running
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    override fun onResume() {
        super.onResume()

        // Clear all notifications when app is opened
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()

        Log.d(TAG, "Cleared all notifications on app resume")

        // Retry sending pending incoming call if exists (with delay for Flutter to be ready)
        if (pendingIncomingCall != null) {
            Log.d(TAG, "onResume: Found pending incoming call, retrying after delay...")
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                sendIncomingCallToFlutter()
            }, 500)
        }
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) {
            Log.d(TAG, "Intent is null")
            return
        }

        // Check for incoming call intent
        val isIncomingCall = intent.getBooleanExtra("incoming_call", false)
        if (isIncomingCall) {
            val callerUid = intent.getStringExtra("caller_uid")
            val callerName = intent.getStringExtra("caller_name")
            val callType = intent.getStringExtra("call_type")
            val answerCall = intent.getBooleanExtra("answer_call", false)

            Log.d(TAG, "Incoming call intent detected - Caller: $callerName, Type: $callType, AutoAnswer: $answerCall")

            if (callerUid != null && callerName != null && callType != null) {
                handleIncomingCall(callerUid, callerName, callType, answerCall)

                // Clear the intent extras to prevent re-processing
                intent.removeExtra("incoming_call")
                intent.removeExtra("caller_uid")
                intent.removeExtra("caller_name")
                intent.removeExtra("call_type")
                intent.removeExtra("answer_call")
            }
            return
        }

        // Handle normal message notification
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

    private fun handleIncomingCall(callerUid: String, callerName: String, callType: String, autoAnswer: Boolean) {
        val arguments = mapOf(
            "type" to "incoming_call",
            "caller_uid" to callerUid,
            "caller_name" to callerName,
            "call_type" to callType,
            "auto_answer" to autoAnswer,
            "timestamp" to System.currentTimeMillis()
        )

        Log.d(TAG, "=== INCOMING CALL ===")
        Log.d(TAG, "Caller: $callerName ($callerUid)")
        Log.d(TAG, "Type: $callType, AutoAnswer: $autoAnswer")

        // Store for processing after Flutter is ready
        pendingIncomingCall = arguments
        Log.d(TAG, "Stored pending incoming call, will process when Flutter is ready")

        // Try to send immediately (in case Flutter is already ready)
        sendIncomingCallToFlutter()
    }

    private fun sendIncomingCallToFlutter() {
        val callData = pendingIncomingCall ?: return

        Log.d(TAG, "Attempting to send incoming call to Flutter...")

        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            val channel = MethodChannel(messenger, NAVIGATION_CHANNEL)

            Log.d(TAG, "Invoking handleIncomingCall on Flutter: $callData")

            // Invoke Flutter method
            channel.invokeMethod("handleIncomingCall", callData, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d(TAG, "✅ Incoming call event sent successfully to Flutter: $result")
                    pendingIncomingCall = null // Clear after success
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "❌ Incoming call error: $errorCode - $errorMessage")
                    // Keep pending for retry
                }

                override fun notImplemented() {
                    Log.w(TAG, "⚠️ handleIncomingCall not implemented in Flutter yet")
                    // Keep pending for retry
                }
            })
        } ?: run {
            Log.e(TAG, "❌ Flutter engine not available yet for incoming call")
            // Keep pending for retry
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

        // Retry sending pending incoming call after a delay (Flutter needs time to initialize)
        if (pendingIncomingCall != null) {
            Log.d(TAG, "Found pending incoming call, will retry after 1 second...")
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                Log.d(TAG, "Retrying to send pending incoming call to Flutter...")
                sendIncomingCallToFlutter()
            }, 1000) // 1 second delay
        }
    }

    private fun setupBackupMethodChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showBackupSuccessNotification" -> {
                        val backupType = call.argument<String>("backupType") ?: "Auto"
                        backupNotificationHelper.showSuccessNotification(backupType)
                        result.success(true)
                    }
                    "showBackupFailureNotification" -> {
                        val backupType = call.argument<String>("backupType") ?: "Auto"
                        val errorMessage = call.argument<String>("errorMessage") ?: "Unknown error"
                        backupNotificationHelper.showFailureNotification(backupType, errorMessage)
                        result.success(true)
                    }
                    "showBatteryOptimizationWarning" -> {
                        backupNotificationHelper.showBatteryOptimizationWarning()
                        result.success(true)
                    }
                    "cancelBackupNotifications" -> {
                        backupNotificationHelper.cancelAllBackupNotifications()
                        result.success(true)
                    }
                    "isBatteryOptimizationDisabled" -> {
                        val isDisabled = backupNotificationHelper.isBatteryOptimizationDisabled()
                        result.success(isDisabled)
                    }
                    else -> result.notImplemented()
                }
            }
        Log.d(TAG, "Backup method channel ready on $BACKUP_CHANNEL")
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

    // ===== PICTURE-IN-PICTURE MODE =====

    private var isInCall = false

    private fun setupPipChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarq/pip")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        Log.d(TAG, "enterPip called from Flutter")
                        isInCall = true
                        enterPipMode()
                        result.success(true)
                    }
                    "setCallState" -> {
                        isInCall = call.argument<Boolean>("isInCall") ?: false
                        Log.d(TAG, "Call state updated: isInCall=$isInCall")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        Log.d(TAG, "PiP channel configured")
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        Log.d(TAG, "User leaving app - isInCall: $isInCall")

        // Disabled automatic PiP - overlay will be visible when user returns to app
        // For true floating overlay over other apps, would need SYSTEM_ALERT_WINDOW permission
        // and a foreground service with WindowManager overlay (complex native implementation)
    }

    private fun enterPipMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()

                val success = enterPictureInPictureMode(params)
                Log.d(TAG, "PiP mode entered: $success")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to enter PiP mode: ${e.message}")
            }
        } else {
            Log.w(TAG, "PiP not supported on this Android version")
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        Log.d(TAG, "PiP mode changed: $isInPictureInPictureMode")
    }

    // ===== SYSTEM OVERLAY =====

    private fun setupOverlayChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showSystemOverlay" -> {
                        val callerName = call.argument<String>("callerName") ?: "Unknown"
                        val isVideo = call.argument<Boolean>("isVideo") ?: false
                        val avatarUrl = call.argument<String>("avatarUrl")
                        val isMuted = call.argument<Boolean>("isMuted") ?: false
                        Log.d(TAG, "showSystemOverlay called: $callerName, video=$isVideo, muted=$isMuted")

                        if (checkOverlayPermission()) {
                            val intent = Intent(this, CallOverlayService::class.java).apply {
                                putExtra("callerName", callerName)
                                putExtra("isVideo", isVideo)
                                putExtra("avatarUrl", avatarUrl)
                                putExtra("isMuted", isMuted)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } else {
                            result.error("NO_PERMISSION", "SYSTEM_ALERT_WINDOW permission not granted", null)
                        }
                    }
                    "hideSystemOverlay" -> {
                        Log.d(TAG, "hideSystemOverlay called")
                        CallOverlayService.stop(this)
                        result.success(true)
                    }
                    "checkOverlayPermission" -> {
                        val hasPermission = checkOverlayPermission()
                        Log.d(TAG, "checkOverlayPermission: $hasPermission")
                        result.success(hasPermission)
                    }
                    "requestOverlayPermission" -> {
                        Log.d(TAG, "requestOverlayPermission called")
                        requestOverlayPermission()
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
        Log.d(TAG, "Overlay channel configured on $OVERLAY_CHANNEL")
    }

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else {
            true // Permission not required below Android M
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, 1234)
                Log.d(TAG, "Requesting overlay permission")
            }
        }
    }
}