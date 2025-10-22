package com.zarq.messenger

import android.app.IntentService
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
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
        private const val BASE_URL = "https://api.zarqmessenger.com"
    }


    override fun onHandleIntent(intent: Intent?) {
        if (intent == null) return

        val conversationId = intent.getIntExtra("conversation_id", -1)
        val replyText = intent.getStringExtra("reply_text") ?: return
        val recipientUid = intent.getStringExtra("recipient_uid") ?: return
        val myUid = intent.getStringExtra("my_uid") ?: return

        Log.d(TAG, "Processing quick reply: $myUid -> $recipientUid")

        runBlocking {
            try {
                val currentUser = FirebaseAuth.getInstance().currentUser
                if (currentUser == null || currentUser.uid != myUid) {
                    showErrorNotification("Authentication required - open app to reply")
                    return@runBlocking
                }

                val recipientDeviceId = getRecipientDeviceId(recipientUid)
                if (recipientDeviceId == null) {
                    showErrorNotification("Failed to get recipient device")
                    return@runBlocking
                }

                val signalManager = SignalManager(applicationContext)

                if (!signalManager.hasKeys() || !signalManager.isStoreInitialized()) {
                    showErrorNotification("Encryption not ready - open app to reply")
                    return@runBlocking
                }

                val hasSession = signalManager.hasSession(recipientUid, recipientDeviceId)

                val encryptedMessage = if (hasSession) {
                    signalManager.encryptMessage(
                        recipientUid = recipientUid,
                        plaintext = replyText,
                        deviceId = recipientDeviceId
                    )
                } else {
                    val prekeyBundle = fetchPrekeyBundle(recipientUid, recipientDeviceId)
                    if (prekeyBundle == null) {
                        showErrorNotification("Session setup required - open app to reply")
                        return@runBlocking
                    }

                    signalManager.encryptMessageWithSessionSetup(
                        recipientUid = recipientUid,
                        plaintext = replyText,
                        prekeyBundle = prekeyBundle,
                        deviceId = recipientDeviceId
                    )
                }

                if (encryptedMessage == null) {
                    showErrorNotification("Failed to encrypt - open app to reply")
                    return@runBlocking
                }

                // CHANGED: Get message ID from server response
                val (success, messageId) = sendEncryptedMessage(conversationId, encryptedMessage)

                if (success && messageId != null) {
                    storeLocalSentMessage(conversationId, replyText, myUid, messageId)
                    showSuccessNotification("Reply sent securely")

                } else {
                    showErrorNotification("Failed to send message")
                }

            } catch (e: Exception) {
                Log.e(TAG, "Quick reply failed: ${e.message}", e)
                showErrorNotification("Open app to reply securely")
            }
        }
    }

    private suspend fun fetchPrekeyBundle(recipientUid: String, deviceId: Int): Map<String, Any>? {
        return withContext(Dispatchers.IO) {
            try {
                val token = getFirebaseAuthToken() ?: return@withContext null
                val url = URL("$BASE_URL/v1/prekey_bundle?uid=$recipientUid&device_id=$deviceId")
                val connection = url.openConnection() as HttpURLConnection

                connection.apply {
                    requestMethod = "GET"
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Accept", "application/json")
                    connectTimeout = 5000
                    readTimeout = 5000
                }

                if (connection.responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)

                    // Convert JSONObject to Map
                    val map = mutableMapOf<String, Any>()
                    json.keys().forEach { key ->
                        map[key] = json.get(key)
                    }
                    map
                } else {
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to fetch prekey bundle: ${e.message}")
                null
            }
        }
    }


    private suspend fun getRecipientDeviceId(recipientUid: String): Int? {
        return withContext(Dispatchers.IO) {
            try {
                val token = getFirebaseAuthToken() ?: return@withContext null
                val url = URL("$BASE_URL/v1/users/$recipientUid/device")
                val connection = url.openConnection() as HttpURLConnection

                connection.apply {
                    requestMethod = "GET"
                    setRequestProperty("Authorization", "Bearer $token")
                    connectTimeout = 5000
                    readTimeout = 5000
                }

                if (connection.responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    json.getInt("device_id")
                } else {
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get device ID: ${e.message}")
                null
            }
        }
    }

    private suspend fun sendEncryptedMessage(conversationId: Int, encryptedContent: String): Pair<Boolean, Int?> {
        return withContext(Dispatchers.IO) {
            try {
                val token = getFirebaseAuthToken() ?: return@withContext Pair(false, null)
                val url = URL("$BASE_URL/v1/messages/send")
                val connection = url.openConnection() as HttpURLConnection

                val payload = JSONObject().apply {
                    put("conversation_id", conversationId)
                    put("content_b64", encryptedContent)
                    put("message_type", "chat")
                }

                Log.d(TAG, "Sending payload: $payload")

                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                    doOutput = true
                }

                connection.outputStream.use {
                    it.write(payload.toString().toByteArray())
                }

                val responseCode = connection.responseCode
                Log.d(TAG, "Backend response code: $responseCode")

                if (responseCode in 200..299) {
                    val response = connection.inputStream.bufferedReader().readText()
                    Log.d(TAG, "Backend response: $response")

                    // Parse message ID from response
                    val json = JSONObject(response)
                    val messageId = json.optInt("message_id", -1)

                    if (messageId != -1) {
                        Pair(true, messageId)
                    } else {
                        Log.e(TAG, "No message_id in response")
                        Pair(false, null)
                    }
                } else {
                    val errorResponse = connection.errorStream?.bufferedReader()?.readText()
                    Log.e(TAG, "Backend error: $errorResponse")
                    Pair(false, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send message: ${e.message}", e)
                Pair(false, null)
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
    private fun storeLocalSentMessage(conversationId: Int, messageText: String, myUid: String, messageId: Int) {
        val sharedPrefs = getSharedPreferences("zarq_sent_messages_$myUid", MODE_PRIVATE)

        val messageData = JSONObject().apply {
            put("conversation_id", conversationId)
            put("content", messageText)
            put("sender_uid", myUid)
            put("message_id", messageId)
            put("stored_at", System.currentTimeMillis())
        }

        val key = "msg_${messageId}"
        sharedPrefs.edit()
            .putString(key, messageData.toString())
            .apply()

        Log.d(TAG, "=== STORED LOCAL MESSAGE ===")
        Log.d(TAG, "Key: $key")
        Log.d(TAG, "MessageId: $messageId")
        Log.d(TAG, "ConversationId: $conversationId")
        Log.d(TAG, "Content: ${messageText.take(20)}...")
        Log.d(TAG, "=== END STORED ===")
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

}