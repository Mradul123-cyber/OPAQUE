package com.example.zarq_messenger

import android.app.IntentService
import android.content.Intent
import android.util.Log
import android.util.Base64
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

class SignalQuickReplyService : IntentService("SignalQuickReplyService") {

    companion object {
        private const val TAG = "QuickReplyService"
        private const val BASE_URL = "http://192.168.29.81:8080" // Update with your server URL
    }

    // Signal Protocol components (same as MainActivity)
    private val signalStore by lazy { SignalStore(this) }
    private val protocolManager by lazy { SignalProtocolManager(this, signalStore, SignalCrypto) }

    // Session managers cache (same as MainActivity)
    private val sessionManagers = ConcurrentHashMap<String, SessionManager>()

    override fun onHandleIntent(intent: Intent?) {
        if (intent == null) {
            Log.e(TAG, "Received null intent")
            return
        }

        val conversationId = intent.getIntExtra("conversation_id", -1)
        val replyText = intent.getStringExtra("reply_text")
        val recipientUid = intent.getStringExtra("recipient_uid")
        val myUid = intent.getStringExtra("my_uid")

        if (conversationId == -1 || replyText.isNullOrEmpty() || recipientUid.isNullOrEmpty() || myUid.isNullOrEmpty()) {
            Log.e(TAG, "Invalid intent data: conversationId=$conversationId, replyText=$replyText, recipientUid=$recipientUid, myUid=$myUid")
            return
        }

        Log.d(TAG, "Processing quick reply: $myUid -> $recipientUid, conversation: $conversationId")

        // Use coroutine for async processing
        runBlocking {
            try {
                sendEncryptedQuickReply(conversationId, replyText, recipientUid, myUid)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send encrypted quick reply: ${e.message}", e)
                showErrorNotification("Failed to send message")
            }
        }
    }

    /**
     * Get or create SessionManager for a user (same logic as MainActivity)
     */
    private fun getSessionManager(uid: String): SessionManager {
        return sessionManagers.getOrPut(uid) {
            val preKeyManager = PreKeyManager(this, uid, signalStore, protocolManager)
            SessionManager(this, uid, signalStore, protocolManager, preKeyManager)
        }
    }

    /**
     * Encrypt and send quick reply message
     */
    private suspend fun sendEncryptedQuickReply(conversationId: Int, text: String, recipientUid: String, myUid: String) {
        Log.d(TAG, "=== Starting encryption process ===")

        try {
            // STEP 1: Store message locally BEFORE encryption (for optimistic UI)
            val localMessageId = storeLocalSentMessage(conversationId, text, myUid)
            Log.d(TAG, "Stored local sent message with ID: $localMessageId")
            // Get session manager for current user
            val sessionManager = getSessionManager(myUid)

            // Check if session exists
            val hasSession = try {
                val testResult = protocolManager.encrypt(
                    myUid = myUid,
                    recipientUid = recipientUid,
                    recipientDeviceId = 1,
                    plaintext = "test".toByteArray()
                )
                testResult != null
            } catch (e: Exception) {
                Log.w(TAG, "Session test failed: ${e.message}")
                false
            }

            if (!hasSession) {
                Log.w(TAG, "No existing session found, quick reply cannot establish new sessions")
                showErrorNotification("Cannot send message: No secure connection")
                return
            }

            Log.d(TAG, "Session exists, proceeding with encryption...")

            // Encrypt the message using existing session
            val encryptedB64 = protocolManager.encrypt(
                myUid = myUid,
                recipientUid = recipientUid,
                recipientDeviceId = 1,
                plaintext = text.toByteArray()
            )

            if (encryptedB64 != null) {
                Log.d(TAG, "Message encrypted successfully (${encryptedB64.length} chars)")

                // Send to Go backend
                val (success, realMessageId) = sendToGoBackend(conversationId, encryptedB64)

                if (success && realMessageId != null) {
                    Log.d(TAG, "Quick reply sent successfully with real ID: $realMessageId")

                    updateLocalMessageId(localMessageId, realMessageId, conversationId)
                    // STEP 3: Notify main app that message was sent successfully
                    notifyMainAppOfSentMessage(conversationId, localMessageId, text, realMessageId)
                    showSuccessNotification("Message sent")
                } else {
                    Log.e(TAG, "Failed to send to backend")
                    showErrorNotification("Failed to send message")
                }
            } else {
                Log.e(TAG, "Encryption returned null")

                // Try session recovery
                Log.d(TAG, "Attempting session recovery...")
                val recovered = sessionManager.recoverSession(recipientUid, 1)

                if (recovered) {
                    // Retry encryption after recovery
                    val retryResult = protocolManager.encrypt(myUid, recipientUid, 1, text.toByteArray())
                    if (retryResult != null) {
                        Log.d(TAG, "Message encrypted after session recovery")
                        val (retrySuccess, retryRealMessageId) = sendToGoBackend(conversationId, retryResult)

                        if (retrySuccess && retryRealMessageId != null) {
                            updateLocalMessageId(localMessageId, retryRealMessageId, conversationId)
                            notifyMainAppOfSentMessage(conversationId, localMessageId, text, retryRealMessageId)
                            showSuccessNotification("Message sent")
                        } else {
                            showErrorNotification("Failed to send message")
                        }
                    } else {
                        showErrorNotification("Encryption failed")
                    }
                } else {
                    showErrorNotification("Cannot send: Connection error")
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Encryption error: ${e.message}", e)
            showErrorNotification("Encryption failed")
        }
    }

    /**
     * Send encrypted message to Go backend
     */
    private suspend fun sendToGoBackend(conversationId: Int, encryptedContentB64: String): Pair<Boolean, Int?> {
        return withContext(Dispatchers.IO) {
            try {
                // Get Firebase Auth token
                val authToken = getFirebaseAuthToken()
                if (authToken == null) {
                    Log.e(TAG, "No auth token available")
                    return@withContext Pair(false, null)
                }

                val url = URL("$BASE_URL/v1/messages/send")
                val connection = url.openConnection() as HttpURLConnection

                // Prepare JSON payload (same format as your Go backend expects)
                val payload = JSONObject().apply {
                    put("conversation_id", conversationId)
                    put("content_b64", encryptedContentB64)
                    put("message_type", "chat")
                }

                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $authToken")
                    doOutput = true
                    connectTimeout = 10000
                    readTimeout = 10000
                }

                // Send request
                connection.outputStream.use { os ->
                    os.write(payload.toString().toByteArray())
                    os.flush()
                }

                val responseCode = connection.responseCode
                Log.d(TAG, "Backend response: $responseCode")

                if (responseCode in 200..299) {
                    // Parse response to get real message ID
                    val responseBody = connection.inputStream.bufferedReader().use { it.readText() }
                    Log.d(TAG, "Response body: $responseBody")

                    val responseJson = JSONObject(responseBody)
                    val realMessageId = responseJson.getInt("message_id")

                    Log.d(TAG, "Real message ID from server: $realMessageId")
                    connection.disconnect()
                    return@withContext Pair(true, realMessageId)
                } else {
                    connection.disconnect()
                    return@withContext Pair(false, null)
                }

            } catch (e: Exception) {
                Log.e(TAG, "Network error sending to backend: ${e.message}", e)
                return@withContext Pair(false, null)
            }
        }
    }

    /**
     * Get Firebase Auth token (same logic as NotificationActionReceiver)
     */
    private suspend fun getFirebaseAuthToken(): String? {
        return try {
            withContext(Dispatchers.Main) {
                val user = FirebaseAuth.getInstance().currentUser
                user?.getIdToken(false)?.await()?.token
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get auth token: ${e.message}")
            null
        }
    }

    /**
     * Store sent message locally for optimistic UI
     */
    private fun storeLocalSentMessage(conversationId: Int, messageText: String, myUid: String): Long {
        val sharedPrefs = getSharedPreferences("zarq_sent_messages", MODE_PRIVATE)
        val messageId = System.currentTimeMillis()

        val messageData = mapOf(
            "id" to messageId,
            "conversation_id" to conversationId,
            "content" to messageText,
            "sender_uid" to myUid,
            "timestamp" to System.currentTimeMillis(),
            "type" to "quick_reply"
        )

        // Store as JSON string
        val messageJson = JSONObject(messageData).toString()
        sharedPrefs.edit()
            .putString("msg_$messageId", messageJson)
            .putLong("last_sent_${conversationId}", messageId)
            .apply()

        return messageId
    }

    /**
     * Notify main app about sent message via Intent
     */
    private fun notifyMainAppOfSentMessage(conversationId: Int, localMessageId: Long, messageText: String, realMessageId: Int) {
        try {
            val notifyIntent = Intent("com.example.zarq_messenger.MESSAGE_SENT").apply {
                putExtra("conversation_id", conversationId)
                putExtra("local_message_id", localMessageId)
                putExtra("real_message_id", realMessageId)  // ADD THIS
                putExtra("message_text", messageText)
                putExtra("sender_uid", FirebaseAuth.getInstance().currentUser?.uid)
                setPackage(packageName)
            }
            sendBroadcast(notifyIntent)
            Log.d(TAG, "Notified main app of sent message: local=$localMessageId, real=$realMessageId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify main app: ${e.message}")
        }
    }

    /**
     * Show success notification to user
     */
    private fun showSuccessNotification(message: String) {
        Log.d(TAG, "Success: $message")
        // Could show a brief toast notification here if desired
    }

    /**
     * Show error notification to user
     */
    private fun showErrorNotification(message: String) {
        Log.e(TAG, "Error: $message")
        // Could show a brief toast notification here if desired
    }

    private fun updateLocalMessageId(localMessageId: Long, realMessageId: Int, conversationId: Int) {
        try {
            val sharedPrefs = getSharedPreferences("zarq_sent_messages", MODE_PRIVATE)

            // Get the existing message data
            val existingMessageJson = sharedPrefs.getString("msg_$localMessageId", null)
            if (existingMessageJson != null) {
                val messageData = JSONObject(existingMessageJson)

                // Update the ID to real database ID
                messageData.put("id", realMessageId)

                // Remove old entry and add new one with real ID
                sharedPrefs.edit()
                    .remove("msg_$localMessageId")  // Remove old timestamp-based entry
                    .putString("msg_$realMessageId", messageData.toString())  // Add new real-ID entry
                    .putLong("last_sent_${conversationId}", realMessageId.toLong())  // Update latest ID
                    .apply()

                Log.d(TAG, "Updated local storage: $localMessageId -> $realMessageId")
            } else {
                Log.w(TAG, "Could not find local message with ID: $localMessageId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating local message ID: ${e.message}", e)
        }
    }
}