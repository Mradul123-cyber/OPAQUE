package com.zarq.messenger

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class NotificationActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "NotificationActions"
        private val BASE_URL = AppConfig.BASE_URL
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val conversationId = intent.getIntExtra("conversation_id", -1)
        val messageId = intent.getIntExtra("message_id", -1)

        Log.d(TAG, "Action received: $action, conversation: $conversationId, message: $messageId")

        when (action) {
            ZarqNotificationService.ACTION_MARK_READ -> {
                val pendingResult = goAsync()
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        withTimeout(15000) {
                            handleMarkAsRead(context, conversationId, messageId)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in handleMarkAsRead: ${e.message}", e)
                    } finally {
                        pendingResult.finish()
                    }
                }
            }
            ZarqNotificationService.ACTION_REPLY -> {
                val pendingResult = goAsync()
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        withTimeout(25000) {
                            handleQuickReply(context, intent, conversationId, messageId)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in handleQuickReply: ${e.message}", e)
                    } finally {
                        pendingResult.finish()
                    }
                }
            }
            ZarqNotificationService.ACTION_ANSWER_CALL -> {
                handleAnswerCall(context, intent)
            }
            ZarqNotificationService.ACTION_DECLINE_CALL -> {
                val pendingResult = goAsync()
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        withTimeout(10000) {
                            handleDeclineCall(context, intent)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in handleDeclineCall: ${e.message}", e)
                    } finally {
                        pendingResult.finish()
                    }
                }
            }
        }
    }

    /**
     * Handle Mark as Read: Updates local database immediately, dismisses notification, and syncs with backend
     */
    private suspend fun handleMarkAsRead(context: Context, conversationId: Int, messageId: Int) {
        Log.d(TAG, "Marking conversation $conversationId as read")

        // 1. Immediately dismiss notification from shade for responsive UX
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId)

        // 2. Mark locally in SQLCipher DB
        val myUid = FirebaseAuth.getInstance().currentUser?.uid
        if (myUid != null) {
            try {
                val signalManager = SignalManager(context)
                val dbKey = signalManager.getDatabaseEncryptionKey()
                if (dbKey != null) {
                    val sqlHelper = SQLCipherHelper(context)
                    val rows = sqlHelper.markConversationReadLocally(myUid, dbKey, conversationId)
                    Log.d(TAG, "Marked $rows messages as read locally in conversation $conversationId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update local DB on mark as read: ${e.message}", e)
            }
        }

        // 3. Inform backend
        try {
            val success = markConversationAsReadOnBackend(conversationId)
            Log.d(TAG, "Backend mark as read result: $success")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send mark as read to backend: ${e.message}", e)
        }
    }

    private suspend fun markConversationAsReadOnBackend(conversationId: Int): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val authToken = getFirebaseAuthToken()
                if (authToken == null) {
                    Log.e(TAG, "No auth token available for mark as read")
                    return@withContext false
                }

                val url = URL("$BASE_URL/v1/conversations/$conversationId/mark_read")
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $authToken")
                    doOutput = false
                    connectTimeout = 7000
                    readTimeout = 7000
                }

                val responseCode = connection.responseCode
                Log.d(TAG, "Mark as read response: $responseCode")
                connection.disconnect()
                responseCode in 200..299
            } catch (e: Exception) {
                Log.e(TAG, "Network error marking as read: ${e.message}", e)
                false
            }
        }
    }

    /**
     * Handle encrypted quick reply directly in receiver without background service start restrictions
     */
    private suspend fun handleQuickReply(context: Context, intent: Intent, conversationId: Int, messageId: Int) {
        Log.d(TAG, "Processing direct quick reply for conversation $conversationId")

        val replyText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(ZarqNotificationService.KEY_TEXT_REPLY)?.toString()

        if (replyText.isNullOrEmpty()) {
            Log.w(TAG, "Quick reply text is empty")
            return
        }

        val recipientUid = intent.getStringExtra("recipient_uid")
        val senderUid = intent.getStringExtra("sender_uid")
        val currentUser = FirebaseAuth.getInstance().currentUser
        val myUid = currentUser?.uid
        val senderName = intent.getStringExtra("sender_name") ?: "User"
        val isGroup = intent.getBooleanExtra("is_group", false)

        if (recipientUid.isNullOrEmpty() || senderUid.isNullOrEmpty() || myUid.isNullOrEmpty()) {
            Log.e(TAG, "Missing UIDs for quick reply: recipientUid=$recipientUid, senderUid=$senderUid, myUid=$myUid")
            showErrorNotification(context, conversationId, "Authentication required - tap to open app")
            return
        }

        val encryptForUid = if (myUid == senderUid) recipientUid else senderUid
        var targetDeviceId = intent.getIntExtra("sender_device_id", -1)

        val signalManager = SignalManager(context)
        if (!signalManager.hasKeys() || !signalManager.isStoreInitialized()) {
            Log.e(TAG, "SignalManager encryption not ready")
            showErrorNotification(context, conversationId, "Encryption not ready - tap to open app")
            return
        }

        // Resolve recipient device ID if missing
        if (targetDeviceId <= 0) {
            targetDeviceId = getRecipientDeviceId(encryptForUid) ?: 1
        }

        // Encrypt reply message using Signal Protocol
        val encryptedContent = try {
            if (isGroup) {
                signalManager.encryptGroupMessage(
                    groupId = conversationId.toString(),
                    plaintext = replyText
                )
            } else {
                val hasSession = signalManager.hasSession(encryptForUid, targetDeviceId)
                if (hasSession) {
                    signalManager.encryptMessage(
                        recipientUid = encryptForUid,
                        plaintext = replyText,
                        deviceId = targetDeviceId
                    )
                } else {
                    val prekeyBundle = fetchPrekeyBundle(encryptForUid, targetDeviceId)
                    if (prekeyBundle != null) {
                        signalManager.encryptMessageWithSessionSetup(
                            recipientUid = encryptForUid,
                            plaintext = replyText,
                            prekeyBundle = prekeyBundle,
                            deviceId = targetDeviceId
                        )
                    } else {
                        Log.e(TAG, "Could not fetch prekey bundle for $encryptForUid:$targetDeviceId")
                        null
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Encryption exception: ${e.message}", e)
            null
        }

        if (encryptedContent == null) {
            Log.e(TAG, "Failed to encrypt quick reply message")
            showErrorNotification(context, conversationId, "Failed to encrypt - tap to open app")
            return
        }

        // Send to backend
        val (sendSuccess, serverMessageId) = sendEncryptedMessage(conversationId, encryptedContent)
        if (sendSuccess && serverMessageId != null) {
            val dbKey = signalManager.getDatabaseEncryptionKey()
            val isoTimestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date())

            if (dbKey != null) {
                try {
                    val sqlHelper = SQLCipherHelper(context)
                    sqlHelper.insertSentQuickReply(
                        userUid = myUid,
                        dbPassword = dbKey,
                        messageId = serverMessageId,
                        conversationId = conversationId,
                        myUid = myUid,
                        myUsername = "Me",
                        plaintext = replyText,
                        contentB64 = encryptedContent,
                        timestamp = isoTimestamp
                    )
                    Log.d(TAG, "Saved quick reply $serverMessageId to local DB")
                } catch (e: Exception) {
                    Log.e(TAG, "Error saving quick reply to local DB: ${e.message}", e)
                }
            }

            // Also save to shared prefs for optimistic UI synchronization
            storeLocalSentMessage(context, conversationId, replyText, myUid, serverMessageId)

            // Update notification with sent status and inline message
            showReplySentNotification(context, conversationId, senderName, replyText)
        } else {
            Log.e(TAG, "Failed to send quick reply message to backend")
            showErrorNotification(context, conversationId, "Failed to send reply - tap to open app")
        }
    }

    private suspend fun fetchPrekeyBundle(recipientUid: String, deviceId: Int): Map<String, Any>? {
        return withContext(Dispatchers.IO) {
            try {
                val token = getFirebaseAuthToken() ?: return@withContext null
                val url = URL("$BASE_URL/v1/prekey_bundle?uid=$recipientUid&device_id=$deviceId")
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Accept", "application/json")
                    connectTimeout = 7000
                    readTimeout = 7000
                }

                if (connection.responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    val map = mutableMapOf<String, Any>()
                    json.keys().forEach { key ->
                        map[key] = json.get(key)
                    }
                    connection.disconnect()
                    map
                } else {
                    connection.disconnect()
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
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    setRequestProperty("Authorization", "Bearer $token")
                    connectTimeout = 7000
                    readTimeout = 7000
                }

                if (connection.responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    connection.disconnect()
                    json.getInt("device_id")
                } else {
                    connection.disconnect()
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
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                    doOutput = true
                    connectTimeout = 10000
                    readTimeout = 10000
                }

                val payload = JSONObject().apply {
                    put("conversation_id", conversationId)
                    put("content_b64", encryptedContent)
                    put("message_type", "chat")
                }

                connection.outputStream.use {
                    it.write(payload.toString().toByteArray())
                }

                val responseCode = connection.responseCode
                Log.d(TAG, "Backend send response code: $responseCode")

                if (responseCode in 200..299) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    val messageId = json.optInt("message_id", -1)
                    connection.disconnect()
                    if (messageId != -1) Pair(true, messageId) else Pair(false, null)
                } else {
                    connection.disconnect()
                    Pair(false, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send message: ${e.message}", e)
                Pair(false, null)
            }
        }
    }

    private fun storeLocalSentMessage(context: Context, conversationId: Int, messageText: String, myUid: String, messageId: Int) {
        try {
            val sharedPrefs = context.getSharedPreferences("zarq_sent_messages_$myUid", Context.MODE_PRIVATE)
            val messageData = JSONObject().apply {
                put("conversation_id", conversationId)
                put("content", messageText)
                put("sender_uid", myUid)
                put("message_id", messageId)
                put("stored_at", System.currentTimeMillis())
            }
            sharedPrefs.edit().putString("msg_$messageId", messageData.toString()).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to store local sent message prefs: ${e.message}")
        }
    }

    private fun showReplySentNotification(context: Context, conversationId: Int, senderName: String, replyText: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val userPerson = Person.Builder().setName("You").build()
        val messagingStyle = NotificationCompat.MessagingStyle(userPerson)
            .addMessage(
                NotificationCompat.MessagingStyle.Message(
                    replyText,
                    System.currentTimeMillis(),
                    userPerson
                )
            )

        val notification = NotificationCompat.Builder(context, "zarq_messages")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setStyle(messagingStyle)
            .setContentTitle(senderName)
            .setContentText("You: $replyText")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .setTimeoutAfter(3000)
            .build()

        notificationManager.notify(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId, notification)

        Handler(Looper.getMainLooper()).postDelayed({
            notificationManager.cancel(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId)
        }, 3000)
    }

    private fun showErrorNotification(context: Context, conversationId: Int, errorMessage: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("conversation_id", conversationId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            conversationId,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val errorNotification = NotificationCompat.Builder(context, "zarq_messages")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Quick reply failed")
            .setContentText(errorMessage)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId, errorNotification)
    }

    /**
     * Get Firebase Auth token with automatic forced-refresh retry
     */
    private suspend fun getFirebaseAuthToken(): String? {
        return withContext(Dispatchers.IO) {
            try {
                val user = FirebaseAuth.getInstance().currentUser ?: return@withContext null
                val task = user.getIdToken(false)
                val result = task.await()
                result.token
            } catch (e: Exception) {
                // If cached token failed, try forced refresh
                try {
                    val user = FirebaseAuth.getInstance().currentUser ?: return@withContext null
                    val task = user.getIdToken(true)
                    val result = task.await()
                    result.token
                } catch (e2: Exception) {
                    Log.e(TAG, "Failed to get auth token after refresh: ${e2.message}", e2)
                    null
                }
            }
        }
    }

    private fun handleAnswerCall(context: Context, intent: Intent) {
        val callerUid = intent.getStringExtra("caller_uid") ?: return
        val callerName = intent.getStringExtra("caller_name") ?: "Unknown"
        val callType = intent.getStringExtra("call_type") ?: "voice"

        Log.d(TAG, "Answering call from $callerName ($callerUid)")

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            putExtra("incoming_call", true)
            putExtra("answer_call", true)
            putExtra("caller_uid", callerUid)
            putExtra("caller_name", callerName)
            putExtra("call_type", callType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        context.startActivity(launchIntent)

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ZarqNotificationService.CALL_NOTIFICATION_ID)
    }

    private fun handleDeclineCall(context: Context, intent: Intent) {
        val callerUid = intent.getStringExtra("caller_uid") ?: return
        val callerName = intent.getStringExtra("caller_name") ?: "Unknown"

        Log.d(TAG, "Declining call from $callerName ($callerUid)")

        // Dismiss notification immediately
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ZarqNotificationService.CALL_NOTIFICATION_ID)

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val authToken = getFirebaseAuthToken()
                if (authToken != null) {
                    sendCallRejection(callerUid, authToken)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error sending call rejection: ${e.message}")
            }
        }
    }

    private suspend fun sendCallRejection(callerUid: String, authToken: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val url = URL("$BASE_URL/v1/calls/reject")
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $authToken")
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 5000
                }

                val jsonPayload = JSONObject().apply {
                    put("recipient_uid", callerUid)
                }

                connection.outputStream.use { os ->
                    os.write(jsonPayload.toString().toByteArray())
                    os.flush()
                }

                val responseCode = connection.responseCode
                connection.disconnect()
                responseCode in 200..299
            } catch (e: Exception) {
                Log.e(TAG, "Network error sending call rejection: ${e.message}")
                false
            }
        }
    }
}