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

        val msg = "Action received: $action, conversation: $conversationId, message: $messageId"
        Log.d(TAG, msg)
        FileLogger.d(context, TAG, msg)
        FileLogger.d(context, TAG, "--- Log file: ${FileLogger.getLogFilePath(context)} ---")

        when (action) {
            ZarqNotificationService.ACTION_MARK_READ -> {
                val pendingResult = goAsync()
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        withTimeout(15000) {
                            handleMarkAsRead(context, conversationId, messageId)
                        }
                    } catch (e: Exception) {
                        val err = "Error in handleMarkAsRead: ${e.message}"
                        Log.e(TAG, err, e)
                        FileLogger.e(context, TAG, err, e)
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
                        val err = "Error in handleQuickReply: ${e.message}"
                        Log.e(TAG, err, e)
                        FileLogger.e(context, TAG, err, e)
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
                        val err = "Error in handleDeclineCall: ${e.message}"
                        Log.e(TAG, err, e)
                        FileLogger.e(context, TAG, err, e)
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
        fun fl(msg: String) { Log.d(TAG, msg); FileLogger.d(context, TAG, msg) }

        fl("━━━ [MARK_READ] START conversationId=$conversationId messageId=$messageId ━━━")

        // 1. Immediately dismiss notification
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ZarqNotificationService.NOTIFICATION_ID_BASE + conversationId)
        fl("[MARK_READ] Notification dismissed for conversationId=$conversationId")

        // 2. Mark locally in SQLCipher DB and sync with backend
        syncConversationMarkAsRead(context, conversationId)

        fl("━━━ [MARK_READ] END ━━━")
    }

    /**
     * Mark all unread messages in conversation as read both locally in SQLCipher and on backend
     */
    private suspend fun syncConversationMarkAsRead(context: Context, conversationId: Int) {
        fun fl(msg: String) { Log.d(TAG, msg); FileLogger.d(context, TAG, msg) }
        fun fle(msg: String, t: Throwable? = null) { Log.e(TAG, msg, t); FileLogger.e(context, TAG, msg, t) }

        // 1. Mark locally in SQLCipher DB
        val currentUser = FirebaseAuth.getInstance().currentUser
        val myUid = currentUser?.uid
        if (myUid != null) {
            try {
                val signalManager = SignalManager(context)
                val dbKey = signalManager.getDatabaseEncryptionKey()
                if (dbKey != null) {
                    val sqlHelper = SQLCipherHelper(context)
                    val rows = sqlHelper.markConversationReadLocally(myUid, dbKey, conversationId)
                    fl("[MARK_READ] Local DB: marked $rows messages as read in conversation $conversationId")
                } else {
                    fle("[MARK_READ] dbKey is null — skipping local DB update")
                }
            } catch (e: Exception) {
                fle("[MARK_READ] Local DB error: ${e.message}", e)
            }
        } else {
            fle("[MARK_READ] myUid is null — skipping local DB update")
        }

        // 2. Inform backend
        try {
            val authToken = getFirebaseAuthToken(context)
            if (authToken == null) {
                fle("[MARK_READ] Cannot call backend — auth token is null")
                return
            }

            val targetUrl = "$BASE_URL/v1/conversations/$conversationId/mark_read"
            fl("[MARK_READ] POST $targetUrl")
            val url = URL(targetUrl)
            val connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $authToken")
                doOutput = false
                connectTimeout = 7000
                readTimeout = 7000
            }

            val responseCode = connection.responseCode
            val responseBody = try {
                if (responseCode in 200..299)
                    connection.inputStream.bufferedReader().readText()
                else
                    connection.errorStream?.bufferedReader()?.readText() ?: "(no error body)"
            } catch (ex: Exception) { "(could not read body: ${ex.message})" }

            fl("[MARK_READ] Backend response: HTTP $responseCode — body: $responseBody")
            connection.disconnect()

            if (responseCode in 200..299) {
                fl("[MARK_READ] ✅ Backend marked read successfully")
            } else {
                fle("[MARK_READ] ❌ Backend returned error HTTP $responseCode")
            }
        } catch (e: Exception) {
            fle("[MARK_READ] ❌ Network exception: ${e.javaClass.simpleName} — ${e.message}", e)
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
        fun fl(msg: String) { Log.d(TAG, msg); FileLogger.d(context, TAG, msg) }
        fun fle(msg: String, t: Throwable? = null) { Log.e(TAG, msg, t); FileLogger.e(context, TAG, msg, t) }

        fl("━━━ [QUICK_REPLY] START conversationId=$conversationId ━━━")

        val replyText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(ZarqNotificationService.KEY_TEXT_REPLY)?.toString()

        if (replyText.isNullOrEmpty()) {
            fle("[QUICK_REPLY] Reply text is empty — aborting")
            return
        }
        fl("[QUICK_REPLY] Reply text length=${replyText.length}")

        val recipientUid = intent.getStringExtra("recipient_uid")
        val senderUid = intent.getStringExtra("sender_uid")
        val currentUser = FirebaseAuth.getInstance().currentUser
        val myUid = currentUser?.uid
        val senderName = intent.getStringExtra("sender_name") ?: "User"
        val isGroup = intent.getBooleanExtra("is_group", false)

        fl("[QUICK_REPLY] Intent extras → recipientUid=$recipientUid senderUid=$senderUid myUid=$myUid isGroup=$isGroup senderName=$senderName")

        if (recipientUid.isNullOrEmpty() || senderUid.isNullOrEmpty() || myUid.isNullOrEmpty()) {
            fle("[QUICK_REPLY] ❌ Missing UIDs — recipientUid=$recipientUid senderUid=$senderUid myUid=$myUid")
            showErrorNotification(context, conversationId, "Authentication required - tap to open app")
            return
        }

        val encryptForUid = if (myUid == senderUid) recipientUid else senderUid
        var targetDeviceId = intent.getIntExtra("sender_device_id", -1)
        fl("[QUICK_REPLY] encryptForUid=$encryptForUid targetDeviceId(from intent)=$targetDeviceId")

        val signalManager = SignalManager(context)
        val hasKeys = signalManager.hasKeys()
        val isStoreInit = signalManager.isStoreInitialized()
        fl("[QUICK_REPLY] SignalManager hasKeys=$hasKeys isStoreInitialized=$isStoreInit")
        if (!hasKeys || !isStoreInit) {
            fle("[QUICK_REPLY] ❌ SignalManager not ready — hasKeys=$hasKeys isStoreInit=$isStoreInit")
            showErrorNotification(context, conversationId, "Encryption not ready - tap to open app")
            return
        }

        // Resolve recipient device ID if missing
        if (targetDeviceId <= 0) {
            fl("[QUICK_REPLY] targetDeviceId not in intent, fetching from backend for uid=$encryptForUid")
            targetDeviceId = getRecipientDeviceId(context, encryptForUid) ?: 1
            fl("[QUICK_REPLY] resolved targetDeviceId=$targetDeviceId")
        }

        // Encrypt reply message using Signal Protocol
        fl("[QUICK_REPLY] Starting encryption — isGroup=$isGroup encryptForUid=$encryptForUid deviceId=$targetDeviceId")
        val encryptedContent = try {
            if (isGroup) {
                fl("[QUICK_REPLY] Using group encryption for conversationId=$conversationId")
                var ciphertext = signalManager.encryptGroupMessage(
                    groupId = conversationId.toString(),
                    plaintext = replyText
                )
                if (ciphertext == null) {
                    fl("[QUICK_REPLY] encryptGroupMessage failed (no sender key). Creating and distributing sender key...")
                    val distributed = setupAndDistributeSenderKey(context, conversationId.toString(), signalManager)
                    if (distributed) {
                        fl("[QUICK_REPLY] Sender key distributed successfully, retrying encryptGroupMessage...")
                        ciphertext = signalManager.encryptGroupMessage(
                            groupId = conversationId.toString(),
                            plaintext = replyText
                        )
                    } else {
                        fle("[QUICK_REPLY] ❌ Failed to distribute sender key for group $conversationId")
                    }
                }
                ciphertext
            } else {
                val hasSession = signalManager.hasSession(encryptForUid, targetDeviceId)
                fl("[QUICK_REPLY] hasSession($encryptForUid, $targetDeviceId)=$hasSession")
                if (hasSession) {
                    fl("[QUICK_REPLY] Encrypting with existing session")
                    signalManager.encryptMessage(
                        recipientUid = encryptForUid,
                        plaintext = replyText,
                        deviceId = targetDeviceId
                    )
                } else {
                    fl("[QUICK_REPLY] No session — fetching prekey bundle for $encryptForUid:$targetDeviceId")
                    val prekeyBundle = fetchPrekeyBundle(context, encryptForUid, targetDeviceId)
                    if (prekeyBundle != null) {
                        fl("[QUICK_REPLY] Got prekey bundle (keys=${prekeyBundle.keys}), setting up session")
                        signalManager.encryptMessageWithSessionSetup(
                            recipientUid = encryptForUid,
                            plaintext = replyText,
                            prekeyBundle = prekeyBundle,
                            deviceId = targetDeviceId
                        )
                    } else {
                        fle("[QUICK_REPLY] ❌ Could not fetch prekey bundle for $encryptForUid:$targetDeviceId")
                        null
                    }
                }
            }
        } catch (e: Exception) {
            fle("[QUICK_REPLY] ❌ Encryption exception: ${e.javaClass.simpleName} — ${e.message}", e)
            null
        }

        if (encryptedContent == null) {
            fle("[QUICK_REPLY] ❌ encryptedContent is null — cannot send")
            showErrorNotification(context, conversationId, "Failed to encrypt - tap to open app")
            return
        }
        fl("[QUICK_REPLY] Encryption success — encryptedContent length=${encryptedContent.length}")

        fl("[QUICK_REPLY] Sending encrypted message to backend for conversationId=$conversationId")
        val (sendSuccess, serverMessageId) = sendEncryptedMessage(context, conversationId, encryptedContent)
        fl("[QUICK_REPLY] sendEncryptedMessage result — success=$sendSuccess serverMessageId=$serverMessageId")

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
                    fl("[QUICK_REPLY] ✅ Saved quick reply $serverMessageId to local DB")
                } catch (e: Exception) {
                    fle("[QUICK_REPLY] Error saving quick reply to local DB: ${e.message}", e)
                }
            } else {
                fle("[QUICK_REPLY] dbKey null — skipping local DB insert")
            }

            storeLocalSentMessage(context, conversationId, replyText, myUid, serverMessageId)
            showReplySentNotification(context, conversationId, senderName, replyText)
            fl("[QUICK_REPLY] ✅ Quick reply complete — messageId=$serverMessageId")

            // Automatically mark conversation messages as read since user replied
            fl("[QUICK_REPLY] Marking conversation $conversationId as read...")
            syncConversationMarkAsRead(context, conversationId)
        } else {
            fle("[QUICK_REPLY] ❌ Failed to send — success=$sendSuccess serverMessageId=$serverMessageId")
            showErrorNotification(context, conversationId, "Failed to send reply - tap to open app")
        }

        fl("━━━ [QUICK_REPLY] END ━━━")
    }

    private suspend fun fetchPrekeyBundle(context: Context, recipientUid: String, deviceId: Int): Map<String, Any>? {
        return withContext(Dispatchers.IO) {
            try {
                val token = getFirebaseAuthToken(context)
                if (token == null) {
                    Log.e(TAG, "[PREKEY] Auth token null"); FileLogger.e(context, TAG, "[PREKEY] Auth token null")
                    return@withContext null
                }
                val targetUrl = "$BASE_URL/v1/prekey_bundle?uid=$recipientUid&device_id=$deviceId"
                Log.d(TAG, "[PREKEY] GET $targetUrl"); FileLogger.d(context, TAG, "[PREKEY] GET $targetUrl")
                val connection = (URL(targetUrl).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Accept", "application/json")
                    connectTimeout = 7000; readTimeout = 7000
                }
                val responseCode = connection.responseCode
                Log.d(TAG, "[PREKEY] HTTP $responseCode"); FileLogger.d(context, TAG, "[PREKEY] HTTP $responseCode")
                if (responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    val map = mutableMapOf<String, Any>()
                    json.keys().forEach { key -> map[key] = json.get(key) }
                    connection.disconnect()
                    val msg = "[PREKEY] ✅ Bundle keys=${map.keys}"
                    Log.d(TAG, msg); FileLogger.d(context, TAG, msg)
                    map
                } else {
                    val errBody = connection.errorStream?.bufferedReader()?.readText() ?: "(no body)"
                    val msg = "[PREKEY] ❌ HTTP $responseCode — $errBody"
                    Log.e(TAG, msg); FileLogger.e(context, TAG, msg)
                    connection.disconnect(); null
                }
            } catch (e: Exception) {
                val msg = "[PREKEY] ❌ ${e.javaClass.simpleName}: ${e.message}"
                Log.e(TAG, msg, e); FileLogger.e(context, TAG, msg, e); null
            }
        }
    }

    private suspend fun getRecipientDeviceId(context: Context, recipientUid: String): Int? {
        return withContext(Dispatchers.IO) {
            try {
                val token = getFirebaseAuthToken(context)
                if (token == null) {
                    Log.e(TAG, "[DEVICE_ID] Auth token null"); FileLogger.e(context, TAG, "[DEVICE_ID] Auth token null")
                    return@withContext null
                }
                val targetUrl = "$BASE_URL/v1/users/$recipientUid/device"
                Log.d(TAG, "[DEVICE_ID] GET $targetUrl"); FileLogger.d(context, TAG, "[DEVICE_ID] GET $targetUrl")
                val connection = (URL(targetUrl).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    setRequestProperty("Authorization", "Bearer $token")
                    connectTimeout = 7000; readTimeout = 7000
                }
                val responseCode = connection.responseCode
                Log.d(TAG, "[DEVICE_ID] HTTP $responseCode"); FileLogger.d(context, TAG, "[DEVICE_ID] HTTP $responseCode")
                if (responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().readText()
                    val deviceId = JSONObject(response).getInt("device_id")
                    connection.disconnect()
                    val msg = "[DEVICE_ID] ✅ device_id=$deviceId for uid=$recipientUid"
                    Log.d(TAG, msg); FileLogger.d(context, TAG, msg)
                    deviceId
                } else {
                    val errBody = connection.errorStream?.bufferedReader()?.readText() ?: "(no body)"
                    val msg = "[DEVICE_ID] ❌ HTTP $responseCode — $errBody"
                    Log.e(TAG, msg); FileLogger.e(context, TAG, msg)
                    connection.disconnect(); null
                }
            } catch (e: Exception) {
                val msg = "[DEVICE_ID] ❌ ${e.javaClass.simpleName}: ${e.message}"
                Log.e(TAG, msg, e); FileLogger.e(context, TAG, msg, e); null
            }
        }
    }

    private suspend fun setupAndDistributeSenderKey(
        context: Context,
        groupId: String,
        signalManager: SignalManager
    ): Boolean {
        return withContext(Dispatchers.IO) {
            fun fl(msg: String) { Log.d(TAG, msg); FileLogger.d(context, TAG, msg) }
            fun fle(msg: String, t: Throwable? = null) { Log.e(TAG, msg, t); FileLogger.e(context, TAG, msg, t) }

            try {
                fl("[SENDER_KEY] Creating sender key distribution for group $groupId")
                val distributionB64 = signalManager.createSenderKeyDistribution(groupId)
                if (distributionB64.isNullOrEmpty()) {
                    fle("[SENDER_KEY] Failed to create sender key distribution locally")
                    return@withContext false
                }

                val token = getFirebaseAuthToken(context)
                if (token.isNullOrEmpty()) {
                    fle("[SENDER_KEY] Auth token is null")
                    return@withContext false
                }

                val myDeviceId = signalManager.getDeviceId()
                val targetUrl = "$BASE_URL/groups/$groupId/sender-keys/distribute"
                fl("[SENDER_KEY] Uploading sender key to $targetUrl (deviceId=$myDeviceId)")

                val connection = (URL(targetUrl).openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                    doOutput = true
                    connectTimeout = 7000
                    readTimeout = 7000
                }

                val payload = JSONObject().apply {
                    put("sender_key_distribution", distributionB64)
                    put("device_id", myDeviceId)
                }

                connection.outputStream.use { it.write(payload.toString().toByteArray()) }

                val responseCode = connection.responseCode
                connection.disconnect()

                if (responseCode in 200..299) {
                    fl("[SENDER_KEY] ✅ Sender key distributed successfully to group $groupId")
                    true
                } else {
                    fle("[SENDER_KEY] ❌ Failed to distribute sender key: HTTP $responseCode")
                    false
                }
            } catch (e: Exception) {
                fle("[SENDER_KEY] ❌ Exception distributing sender key: ${e.message}", e)
                false
            }
        }
    }

    private suspend fun sendEncryptedMessage(context: Context, conversationId: Int, encryptedContent: String): Pair<Boolean, Int?> {
        return withContext(Dispatchers.IO) {
            try {
                val token = getFirebaseAuthToken(context)
                if (token == null) {
                    val msg = "[SEND_MSG] ❌ Auth token null"
                    Log.e(TAG, msg); FileLogger.e(context, TAG, msg)
                    return@withContext Pair(false, null)
                }
                val msg0 = "[SEND_MSG] Auth token OK — posting to $BASE_URL/v1/messages/send"
                Log.d(TAG, msg0); FileLogger.d(context, TAG, msg0)

                val connection = (URL("$BASE_URL/v1/messages/send").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                    doOutput = true; connectTimeout = 10000; readTimeout = 10000
                }
                val payload = JSONObject().apply {
                    put("conversation_id", conversationId)
                    put("content_b64", encryptedContent)
                    put("message_type", "chat")
                }
                val msg1 = "[SEND_MSG] Payload keys=${payload.keys().asSequence().toList()} conversationId=$conversationId"
                Log.d(TAG, msg1); FileLogger.d(context, TAG, msg1)

                connection.outputStream.use { it.write(payload.toString().toByteArray()) }

                val responseCode = connection.responseCode
                val responseBody = try {
                    if (responseCode in 200..299) connection.inputStream.bufferedReader().readText()
                    else connection.errorStream?.bufferedReader()?.readText() ?: "(no error body)"
                } catch (ex: Exception) { "(could not read body: ${ex.message})" }

                val msg2 = "[SEND_MSG] HTTP $responseCode — body: $responseBody"
                Log.d(TAG, msg2); FileLogger.d(context, TAG, msg2)

                if (responseCode in 200..299) {
                    val messageId = JSONObject(responseBody).optInt("message_id", -1)
                    connection.disconnect()
                    if (messageId != -1) {
                        val msg3 = "[SEND_MSG] ✅ message_id=$messageId"
                        Log.d(TAG, msg3); FileLogger.d(context, TAG, msg3)
                        Pair(true, messageId)
                    } else {
                        val msg3 = "[SEND_MSG] ❌ message_id missing from response"
                        Log.e(TAG, msg3); FileLogger.e(context, TAG, msg3)
                        Pair(false, null)
                    }
                } else {
                    connection.disconnect()
                    val msg3 = "[SEND_MSG] ❌ Backend error HTTP $responseCode"
                    Log.e(TAG, msg3); FileLogger.e(context, TAG, msg3)
                    Pair(false, null)
                }
            } catch (e: Exception) {
                val msg = "[SEND_MSG] ❌ ${e.javaClass.simpleName}: ${e.message}"
                Log.e(TAG, msg, e); FileLogger.e(context, TAG, msg, e)
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
     * Get Firebase Auth token with automatic forced-refresh retry.
     * context is optional — when provided, also logs to file.
     */
    private suspend fun getFirebaseAuthToken(context: Context? = null): String? {
        return withContext(Dispatchers.IO) {
            fun fl(msg: String) { Log.d(TAG, msg); context?.let { FileLogger.d(it, TAG, msg) } }
            fun fle(msg: String, t: Throwable? = null) { Log.e(TAG, msg, t); context?.let { FileLogger.e(it, TAG, msg, t) } }

            val user = FirebaseAuth.getInstance().currentUser
            fl("[AUTH_TOKEN] currentUser=${user?.uid ?: "NULL"}")
            if (user == null) {
                fle("[AUTH_TOKEN] ❌ No Firebase user — not logged in")
                return@withContext null
            }
            try {
                val result = user.getIdToken(false).await()
                val token = result.token
                fl("[AUTH_TOKEN] ✅ Cached token OK (len=${token?.length})")
                token
            } catch (e: Exception) {
                fl("[AUTH_TOKEN] Cached token failed (${e.message}), trying forced refresh...")
                try {
                    val result = user.getIdToken(true).await()
                    val token = result.token
                    fl("[AUTH_TOKEN] ✅ Refreshed token OK (len=${token?.length})")
                    token
                } catch (e2: Exception) {
                    fle("[AUTH_TOKEN] ❌ Both cached and refresh failed: ${e2.message}", e2)
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