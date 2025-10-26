package com.zarq.messenger

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
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
        private const val BASE_URL = "https://api.zarqmessenger.com"
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
            ZarqNotificationService.ACTION_ANSWER_CALL -> {
                handleAnswerCall(context, intent)
            }
            ZarqNotificationService.ACTION_DECLINE_CALL -> {
                handleDeclineCall(context, intent)
            }
        }
    }

    /**
     * Handle encrypted quick reply
     */
    private fun handleQuickReply(context: Context, intent: Intent, conversationId: Int, messageId: Int) {
        Log.d(TAG, "Processing quick reply for conversation $conversationId")

        val replyText = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(ZarqNotificationService.KEY_TEXT_REPLY)

        if (replyText.isNullOrEmpty()) {
            Log.w(TAG, "Quick reply text is empty")
            return
        }

        val recipientUid = intent.getStringExtra("recipient_uid")
        val senderUid = intent.getStringExtra("sender_uid")
        val currentUser = FirebaseAuth.getInstance().currentUser
        val myUid = currentUser?.uid

        if (recipientUid.isNullOrEmpty() || senderUid.isNullOrEmpty() || myUid.isNullOrEmpty()) {
            Log.e(TAG, "Missing UIDs for quick reply: recipientUid=$recipientUid, senderUid=$senderUid, myUid=$myUid")
            return
        }

        val encryptForUid = if (myUid == senderUid) {
            recipientUid
        } else {
            senderUid
        }

        Log.d(TAG, "Quick reply: $myUid -> $encryptForUid, text: '${replyText.take(20)}...'")

        val serviceIntent = Intent(context, SignalQuickReplyService::class.java).apply {
            putExtra("conversation_id", conversationId)
            putExtra("reply_text", replyText.toString())
            putExtra("recipient_uid", encryptForUid)
            putExtra("my_uid", myUid)
        }

        try {
            context.startService(serviceIntent)
            Log.d(TAG, "SignalQuickReplyService started successfully")

            // Dismiss notification immediately after starting service
            dismissNotificationWithSuccess(context, conversationId)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start SignalQuickReplyService: ${e.message}", e)
        }
    }

    private fun dismissNotificationWithSuccess(context: Context, conversationId: Int) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Show a brief "Reply sent" notification that auto-dismisses
        val successNotification = NotificationCompat.Builder(context, "zarq_messages")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Reply sent")
            .setContentText("Your message was sent securely")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .setTimeoutAfter(2000) // Auto-dismiss after 2 seconds
            .build()

        notificationManager.notify(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId, successNotification)

        // Cancel it after a delay
        Handler(Looper.getMainLooper()).postDelayed({
            notificationManager.cancel(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId)
        }, 2000)

        Log.d(TAG, "Notification updated to show success and will dismiss in 2 seconds")
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

                        // For mark as read, just cancel the notification immediately
                        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancel(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId)
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

    private fun handleAnswerCall(context: Context, intent: Intent) {
        val callerUid = intent.getStringExtra("caller_uid") ?: return
        val callerName = intent.getStringExtra("caller_name") ?: "Unknown"
        val callType = intent.getStringExtra("call_type") ?: "voice"

        Log.d(TAG, "Answering call from $callerName ($callerUid)")

        // Launch the app with call answer intent
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("incoming_call", true)
            putExtra("answer_call", true)
            putExtra("caller_uid", callerUid)
            putExtra("caller_name", callerName)
            putExtra("call_type", callType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        context.startActivity(launchIntent)

        // Dismiss the call notification
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ZarqNotificationService.CALL_NOTIFICATION_ID)

        Log.d(TAG, "App launched to answer call")
    }

    private fun handleDeclineCall(context: Context, intent: Intent) {
        val callerUid = intent.getStringExtra("caller_uid") ?: return
        val callerName = intent.getStringExtra("caller_name") ?: "Unknown"

        Log.d(TAG, "Declining call from $callerName ($callerUid)")

        // Send call_rejected signal to backend
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val authToken = getFirebaseAuthToken()
                if (authToken != null) {
                    sendCallRejection(callerUid, authToken)
                    Log.d(TAG, "Call rejection signal sent to backend")
                } else {
                    Log.e(TAG, "No auth token available for call rejection")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error sending call rejection: ${e.message}")
            }
        }

        // Dismiss the call notification immediately
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ZarqNotificationService.CALL_NOTIFICATION_ID)

        Log.d(TAG, "Call declined and notification dismissed")
    }

    private suspend fun sendCallRejection(callerUid: String, authToken: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val url = URL("$BASE_URL/v1/calls/reject")
                val connection = url.openConnection() as HttpURLConnection

                val jsonPayload = JSONObject().apply {
                    put("recipient_uid", callerUid)
                }

                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $authToken")
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 5000
                }

                connection.outputStream.use { os ->
                    os.write(jsonPayload.toString().toByteArray())
                    os.flush()
                }

                val responseCode = connection.responseCode
                Log.d(TAG, "Call rejection response: $responseCode")

                connection.disconnect()
                responseCode in 200..299

            } catch (e: Exception) {
                Log.e(TAG, "Network error sending call rejection: ${e.message}")
                false
            }
        }
    }

    private fun showConfirmationNotification(context: Context, message: String) {
        // This could show a brief confirmation notification
        Log.d(TAG, "Confirmation: $message")

        // Optional: Show a toast or brief notification
        // You can implement this if you want visual feedback
    }

}