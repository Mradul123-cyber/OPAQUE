package com.example.zarq_messenger

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Base64
import android.util.Log
import androidx.core.app.RemoteInput
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NotificationActions"
        private const val BASE_URL = "http://192.168.29.81:8080" // Update with your server URL
    }

    override fun onReceive(context: Context, intent: Intent) {
        val conversationId = intent.getIntExtra("conversation_id", -1)
        val messageId = intent.getIntExtra("message_id", -1)

        Log.d(TAG, "Action received: ${intent.action}, conversation: $conversationId")

        when (intent.action) {
            ZarqNotificationService.ACTION_MARK_READ -> {
                handleMarkAsRead(context, conversationId, messageId)
            }
            ZarqNotificationService.ACTION_REPLY -> {
                handleQuickReply(context, intent, conversationId, messageId)
            }
        }

        dismissNotification(context, conversationId)
    }

    /**
     * Handle encrypted quick reply
     */
    private fun handleQuickReply(context: Context, intent: Intent, conversationId: Int, messageId: Int) {
        Log.d(TAG, "Processing quick reply for conversation $conversationId")

        // Extract reply text from RemoteInput
        val replyText = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(ZarqNotificationService.KEY_TEXT_REPLY)

        if (replyText.isNullOrEmpty()) {
            Log.w(TAG, "Quick reply text is empty")
            return
        }

        // Extract UIDs from intent extras (passed from ZarqNotificationService)
        val recipientUid = intent.getStringExtra("recipient_uid")
        val senderUid = intent.getStringExtra("sender_uid")

        // Get current user UID
        val currentUser = FirebaseAuth.getInstance().currentUser
        val myUid = currentUser?.uid

        if (recipientUid.isNullOrEmpty() || senderUid.isNullOrEmpty() || myUid.isNullOrEmpty()) {
            Log.e(TAG, "Missing UIDs for quick reply: recipientUid=$recipientUid, senderUid=$senderUid, myUid=$myUid")
            return
        }

        // Determine who to encrypt for (the other person in the conversation)
        val encryptForUid = if (myUid == senderUid) {
            recipientUid // I'm replying to someone who sent me a message
        } else {
            senderUid // I'm replying in a conversation where I'm the recipient
        }

        Log.d(TAG, "Quick reply: $myUid -> $encryptForUid, text: '${replyText.take(20)}...'")

        // Start SignalQuickReplyService to handle encryption and sending
        val serviceIntent = Intent(context, SignalQuickReplyService::class.java).apply {
            putExtra("conversation_id", conversationId)
            putExtra("reply_text", replyText.toString())
            putExtra("recipient_uid", encryptForUid)
            putExtra("my_uid", myUid)
        }

        try {
            context.startService(serviceIntent)
            Log.d(TAG, "SignalQuickReplyService started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start SignalQuickReplyService: ${e.message}", e)
        }
    }

    private fun handleMarkAsRead(context: Context, conversationId: Int, messageId: Int) {
        Log.d(TAG, "Marking conversation $conversationId as read")

        // Launch coroutine for network call
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val success = markConversationAsRead(conversationId)
                withContext(Dispatchers.Main) {
                    if (success) {
                        Log.d(TAG, "Successfully marked as read")
                        showConfirmationNotification(context, "Marked as read")
                    } else {
                        Log.e(TAG, "Failed to mark as read")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error marking as read: ${e.message}")
            }
        }
    }

    private suspend fun markConversationAsRead(conversationId: Int): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                // Get Firebase Auth token
                val authToken = getFirebaseAuthToken()
                if (authToken == null) {
                    Log.e(TAG, "No auth token available for mark as read")
                    return@withContext false
                }

                val url = URL("$BASE_URL/v1/conversations/$conversationId/mark_read")
                val connection = url.openConnection() as HttpURLConnection

                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $authToken")
                    doOutput = false
                    connectTimeout = 5000
                    readTimeout = 5000
                }

                val responseCode = connection.responseCode
                Log.d(TAG, "Mark as read response: $responseCode")

                connection.disconnect()
                responseCode in 200..299

            } catch (e: Exception) {
                Log.e(TAG, "Network error marking as read: ${e.message}")
                false
            }
        }
    }

    private suspend fun getFirebaseAuthToken(): String? {
        return try {
            // This is a simplified approach - in production you'd want better token management
            withContext(Dispatchers.Main) {
                val user = FirebaseAuth.getInstance().currentUser
                user?.getIdToken(false)?.await()?.token
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get auth token: ${e.message}")
            null
        }
    }

    private fun showConfirmationNotification(context: Context, message: String) {
        // This could show a brief confirmation notification
        Log.d(TAG, "Confirmation: $message")

        // Optional: Show a toast or brief notification
        // You can implement this if you want visual feedback
    }

    private fun dismissNotification(context: Context, conversationId: Int) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId)
        Log.d(TAG, "Dismissed notification for conversation: $conversationId")
    }
}