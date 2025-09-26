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