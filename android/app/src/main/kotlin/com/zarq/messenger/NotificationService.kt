package com.zarq.messenger

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import androidx.core.graphics.drawable.IconCompat
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

class ZarqNotificationService : FirebaseMessagingService() {

    companion object {
        const val DIRECT_CHANNEL_ID = "zarq_direct_messages"
        const val GROUP_CHANNEL_ID = "zarq_group_messages"
        const val OLD_CHANNEL_ID = "zarq_messages"
        const val CALL_CHANNEL_ID = "zarq_calls"
        const val GROUP_KEY_MESSAGES = "com.zarq.messenger.MESSAGES"
        const val SUMMARY_NOTIFICATION_ID = 1000
        const val NOTIFICATION_ID_BASE = 1001
        const val CALL_NOTIFICATION_ID = 9999
        private const val TAG = "ZarqNotifications"

        // Action constants
        const val ACTION_MARK_READ = "MARK_READ"
        const val ACTION_REPLY = "REPLY"
        const val ACTION_ANSWER_CALL = "ANSWER_CALL"
        const val ACTION_DECLINE_CALL = "DECLINE_CALL"
        const val KEY_TEXT_REPLY = "KEY_TEXT_REPLY"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "ZarqNotificationService created")
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        Log.d(TAG, "=== FCM Message Received ===")
        Log.d(TAG, "Message ID: ${remoteMessage.messageId}")
        Log.d(TAG, "From: ${remoteMessage.from}")
        Log.d(TAG, "Data payload: ${remoteMessage.data}")
        Log.d(TAG, "Notification payload: ${remoteMessage.notification}")

        // Check notification type
        val notificationType = remoteMessage.data["type"]

        when (notificationType) {
            "incoming_call" -> {
                Log.d(TAG, "Incoming call notification received")
                showIncomingCallNotification(remoteMessage)
            }
            "new_message" -> {
                val conversationId = remoteMessage.data["conversation_id"]?.toIntOrNull()
                // Only suppress notification if user is actively chatting in this exact conversation
                val isActivelyViewingThisChat = isAppInForeground() && conversationId != null && MainActivity.activeConversationId == conversationId

                if (isActivelyViewingThisChat) {
                    Log.d(TAG, "App in foreground and actively viewing conversation $conversationId, skipping notification")
                } else {
                    Log.d(TAG, "Showing message notification for conversation $conversationId")
                    showNotification(remoteMessage)
                }
            }
            else -> {
                Log.d(TAG, "Unknown notification type: $notificationType")
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "FCM token refreshed: $token")

        val sharedPrefs = getSharedPreferences("zarq_fcm", Context.MODE_PRIVATE)
        sharedPrefs.edit()
            .putString("fcm_token", token)
            .putBoolean("token_needs_upload", true)
            .apply()

        Log.d(TAG, "FCM token stored locally — ready for upload")
    }

    private fun formatMessagePreview(plaintext: String?, messageType: String): String {
        if (plaintext.isNullOrEmpty()) {
            return when (messageType) {
                "image" -> "📷 Photo"
                "video" -> "🎥 Video"
                "audio" -> "🎵 Voice message"
                "file", "document" -> "📄 Document"
                "location" -> "📍 Location"
                else -> "New message"
            }
        }

        // Check if plaintext is structured JSON (Opaque media payload)
        if (plaintext.startsWith("{") && plaintext.endsWith("}")) {
            try {
                val json = JSONObject(plaintext)
                val type = json.optString("type", json.optString("opaque_type", ""))
                val caption = json.optString("caption", "")
                val fileName = json.optString("file_name", json.optString("name", ""))

                return when (type) {
                    "image" -> if (caption.isNotEmpty()) "📷 $caption" else "📷 Photo"
                    "video" -> if (caption.isNotEmpty()) "🎥 $caption" else "🎥 Video"
                    "audio" -> "🎵 Voice message"
                    "document", "file" -> if (fileName.isNotEmpty()) "📄 $fileName" else "📄 Document"
                    "location" -> "📍 Location shared"
                    else -> json.optString("content", json.optString("text", plaintext))
                }
            } catch (_: Exception) {}
        }

        return plaintext
    }

    private fun showNotification(remoteMessage: RemoteMessage) {
        val conversationId = remoteMessage.data["conversation_id"]?.toIntOrNull() ?: return
        val messageId = remoteMessage.data["message_id"]?.toIntOrNull() ?: 0
        val senderName = remoteMessage.data["sender_username"] ?: "Unknown"
        val senderUid = remoteMessage.data["sender_uid"]
        val recipientUid = remoteMessage.data["recipient_uid"]
        val contentB64 = remoteMessage.data["content_b64"]
        val senderDeviceId = remoteMessage.data["sender_device_id"]?.toIntOrNull() ?: 1
        val isGroup = remoteMessage.data["is_group"]?.toBoolean() ?: false
        val groupName = remoteMessage.data["group_name"]?.takeIf { it.isNotBlank() }
        val senderAvatarUrl = remoteMessage.data["sender_avatar"]?.takeIf { it.isNotBlank() }
        val groupAvatarUrl = remoteMessage.data["group_avatar"]?.takeIf { it.isNotBlank() }
        val messageType = remoteMessage.data["msg_type"] ?: "chat"

        // Check if conversation is muted
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isMuted = prefs.getBoolean("flutter.muted_$conversationId", false)

        if (isMuted) {
            Log.d(TAG, "Conversation $conversationId is muted, skipping notification")
            return
        }

        val currentUser = FirebaseAuth.getInstance().currentUser
        val myUid = currentUser?.uid

        if (senderUid != null && senderUid == myUid) {
            Log.d(TAG, "Suppressing notification for own message from $senderUid")
            return
        }

        Log.d(TAG, "=== Processing notification for conversation $conversationId (message $messageId) ===")

        // 1. Attempt Native E2EE Signal Decryption
        var decryptedPlaintext: String? = null
        val signalManager = SignalManager(applicationContext)

        if (!contentB64.isNullOrEmpty() && !senderUid.isNullOrEmpty()) {
            try {
                if (signalManager.hasKeys() && signalManager.isStoreInitialized()) {
                    decryptedPlaintext = if (isGroup) {
                        signalManager.decryptGroupMessage(
                            groupId = conversationId.toString(),
                            senderUid = senderUid,
                            senderDeviceId = senderDeviceId,
                            ciphertextB64 = contentB64
                        )
                    } else {
                        signalManager.decryptMessage(
                            senderUid = senderUid,
                            ciphertextB64 = contentB64,
                            deviceId = senderDeviceId
                        )
                    }

                    // If group message decryption failed (e.g. freshly reinstalled app, missing sender key)
                    if (decryptedPlaintext == null && isGroup) {
                        Log.d(TAG, "Group message decryption returned null for group $conversationId. Attempting to fetch sender keys from backend...")
                        val fetched = fetchAndProcessGroupSenderKeys(conversationId.toString(), signalManager)
                        if (fetched) {
                            Log.d(TAG, "Fetched sender keys from backend. Retrying group decryption...")
                            decryptedPlaintext = signalManager.decryptGroupMessage(
                                groupId = conversationId.toString(),
                                senderUid = senderUid,
                                senderDeviceId = senderDeviceId,
                                ciphertextB64 = contentB64
                            )
                            if (decryptedPlaintext != null) {
                                Log.d(TAG, "Successfully decrypted group message after fetching sender keys!")
                            }
                        }
                    }

                    if (decryptedPlaintext == SignalManager.DUPLICATE_MESSAGE_MARKER) {
                        Log.d(TAG, "Message $messageId already decrypted previously")
                        decryptedPlaintext = null
                    } else if (decryptedPlaintext != null) {
                        Log.d(TAG, "Successfully decrypted message in notification service")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Decryption error in notification: ${e.message}", e)
            }
        }

        // 2. Format user-friendly message preview
        val displayMessageText = formatMessagePreview(decryptedPlaintext, messageType)

        // 3. Persist decrypted message into local SQLCipher database so Flutter has it immediately
        if (decryptedPlaintext != null && myUid != null && messageId > 0) {
            try {
                val dbKey = signalManager.getDatabaseEncryptionKey()
                if (dbKey != null) {
                    val sqlHelper = SQLCipherHelper(applicationContext)
                    val isoTimestamp = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                        timeZone = java.util.TimeZone.getTimeZone("UTC")
                    }.format(java.util.Date())

                    sqlHelper.insertDecryptedMessage(
                        userUid = myUid,
                        dbPassword = dbKey,
                        messageId = messageId,
                        conversationId = conversationId,
                        senderUid = senderUid ?: "",
                        username = senderName,
                        plaintext = decryptedPlaintext,
                        contentB64 = contentB64,
                        senderDeviceId = senderDeviceId,
                        timestamp = isoTimestamp
                    )
                    Log.d(TAG, "Persisted decrypted message $messageId directly into local SQLCipher DB")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to persist decrypted message locally: ${e.message}", e)
            }
        }

        // 4. Create Main Tap Intent
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("conversation_id", conversationId)
            putExtra("message_id", messageId)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        val mainPendingIntent = PendingIntent.getActivity(
            this,
            conversationId,
            mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 5. Create Mark as Read Intent
        val markReadIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = ACTION_MARK_READ
            putExtra("conversation_id", conversationId)
            putExtra("message_id", messageId)
        }

        val markReadPendingIntent = PendingIntent.getBroadcast(
            this,
            conversationId + 1000,
            markReadIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 6. Create Direct Quick Reply Action
        val replyIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = ACTION_REPLY
            putExtra("conversation_id", conversationId)
            putExtra("message_id", messageId)
            putExtra("sender_uid", senderUid)
            putExtra("recipient_uid", recipientUid)
            putExtra("sender_device_id", senderDeviceId)
            putExtra("is_group", isGroup)
            putExtra("sender_name", senderName)
            if (groupName != null) {
                putExtra("group_name", groupName)
            }
        }

        val replyPendingIntent = PendingIntent.getBroadcast(
            this,
            conversationId + 2000,
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        val remoteInput = RemoteInput.Builder(KEY_TEXT_REPLY)
            .setLabel("Reply...")
            .build()

        // 7. Load Circular Avatars & Target Channel
        val targetChannelId = if (isGroup) GROUP_CHANNEL_ID else DIRECT_CHANNEL_ID
        val senderAvatarBitmap = getCircularAvatar(applicationContext, senderAvatarUrl, senderName)
        val senderAvatarIcon = IconCompat.createWithBitmap(senderAvatarBitmap)
        val largeHeaderBitmap = if (isGroup) {
            getCircularAvatar(applicationContext, groupAvatarUrl, groupName ?: "Group")
        } else {
            senderAvatarBitmap
        }

        // 8. Fetch Recent Unread Messages for Conversation (Multi-Message Stacking)
        val sqlHelper = SQLCipherHelper(applicationContext)
        val unreadHistory = try {
            val dbKey = signalManager.getDatabaseEncryptionKey()
            if (dbKey != null && myUid != null) {
                sqlHelper.getRecentUnreadMessages(myUid, dbKey, conversationId, limit = 7)
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.d(TAG, "Could not query unread messages for conversation $conversationId: ${e.message}")
            emptyList()
        }

        // 9. Build Modern MessagingStyle Notification
        val userPerson = androidx.core.app.Person.Builder()
            .setName("Me")
            .setKey(myUid ?: "me")
            .build()

        val senderPerson = androidx.core.app.Person.Builder()
            .setName(senderName)
            .setKey(senderUid ?: "sender")
            .setIcon(senderAvatarIcon)
            .build()

        val resolvedGroupTitle = if (isGroup) (groupName ?: "Group") else null
        val messagingStyle = NotificationCompat.MessagingStyle(userPerson)
            .setConversationTitle(resolvedGroupTitle)
            .setGroupConversation(isGroup)

        if (unreadHistory.isNotEmpty()) {
            for (historyItem in unreadHistory) {
                val isMe = (historyItem.senderUid == myUid)
                val msgPerson = if (isMe) {
                    userPerson
                } else if (historyItem.senderUid == senderUid) {
                    senderPerson
                } else {
                    val itemAvatar = getCircularAvatar(applicationContext, null, historyItem.username)
                    androidx.core.app.Person.Builder()
                        .setName(historyItem.username)
                        .setKey(historyItem.senderUid)
                        .setIcon(IconCompat.createWithBitmap(itemAvatar))
                        .build()
                }
                val formattedHistoryText = formatMessagePreview(historyItem.content, "chat")
                messagingStyle.addMessage(
                    NotificationCompat.MessagingStyle.Message(
                        formattedHistoryText,
                        historyItem.timestampMs,
                        msgPerson
                    )
                )
            }
        } else {
            messagingStyle.addMessage(
                NotificationCompat.MessagingStyle.Message(
                    displayMessageText,
                    System.currentTimeMillis(),
                    senderPerson
                )
            )
        }

        // 10. Lock Screen Privacy Public Version
        val publicTitle = if (isGroup) (groupName ?: "Group") else senderName
        val publicText = if (isGroup) "New message in $publicTitle" else "New message"
        val publicNotification = NotificationCompat.Builder(this, targetChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(publicTitle)
            .setContentText(publicText)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(mainPendingIntent)
            .setAutoCancel(true)
            .build()

        // 11. Conversation Notification
        val notification = NotificationCompat.Builder(this, targetChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setLargeIcon(largeHeaderBitmap)
            .setStyle(messagingStyle)
            .setContentTitle(if (isGroup) (groupName ?: "Group") else senderName)
            .setContentText(if (isGroup) "$senderName: $displayMessageText" else displayMessageText)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicNotification)
            .setGroup(GROUP_KEY_MESSAGES)
            .setAutoCancel(true)
            .setContentIntent(mainPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_agenda,
                "Mark Read",
                markReadPendingIntent
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_send,
                    "Reply",
                    replyPendingIntent
                ).addRemoteInput(remoteInput).build()
            )
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(if (isGroup) longArrayOf(0, 200, 150, 200) else longArrayOf(0, 250, 250, 250))
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID_BASE + conversationId, notification)

        // 12. Post / Update Group Summary Notification for Bundling
        val summaryNotification = NotificationCompat.Builder(this, targetChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setStyle(NotificationCompat.InboxStyle().setSummaryText("Messages"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setGroup(GROUP_KEY_MESSAGES)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(SUMMARY_NOTIFICATION_ID, summaryNotification)

        Log.d(TAG, "Notification posted with MessagingStyle for conversation: $conversationId")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 1. Direct Messages channel
            val directChannel = NotificationChannel(
                DIRECT_CHANNEL_ID,
                "Direct Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "1-on-1 personal message notifications"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 250, 250)
                setShowBadge(true)
            }

            // 2. Group Messages channel
            val groupChannel = NotificationChannel(
                GROUP_CHANNEL_ID,
                "Group Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Group conversation notifications"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 200, 150, 200)
                setShowBadge(true)
            }

            // 3. Calls channel (max importance for full-screen notifications)
            val callChannel = NotificationChannel(
                CALL_CHANNEL_ID,
                "Zarq Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming call notifications"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000)
                setShowBadge(true)
            }

            notificationManager.createNotificationChannel(directChannel)
            notificationManager.createNotificationChannel(groupChannel)
            notificationManager.createNotificationChannel(callChannel)
            Log.d(TAG, "Notification channels created (direct, group, calls)")
        }
    }

    /**
     * Load or generate a circular avatar bitmap.
     * Checks disk cache first, downloads with a 2-second timeout if missing, or generates initials circle.
     */
    private fun getCircularAvatar(context: Context, avatarUrl: String?, titleOrName: String): Bitmap {
        val sizePx = (48 * context.resources.displayMetrics.density).toInt().coerceAtLeast(96)

        if (!avatarUrl.isNullOrBlank()) {
            try {
                val cacheDir = java.io.File(context.cacheDir, "avatar_cache").apply { if (!exists()) mkdirs() }
                val cacheKey = java.security.MessageDigest.getInstance("MD5")
                    .digest(avatarUrl.toByteArray())
                    .joinToString("") { "%02x".format(it) }
                val cachedFile = java.io.File(cacheDir, "$cacheKey.png")

                var bitmap: Bitmap? = null
                if (cachedFile.exists() && cachedFile.length() > 0) {
                    bitmap = BitmapFactory.decodeFile(cachedFile.absolutePath)
                }

                if (bitmap == null) {
                    val conn = (URL(avatarUrl).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 2000
                        readTimeout = 2000
                        doInput = true
                    }
                    if (conn.responseCode in 200..299) {
                        conn.inputStream.use { input ->
                            val bytes = input.readBytes()
                            bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            if (bitmap != null) {
                                try {
                                    java.io.FileOutputStream(cachedFile).use { fos ->
                                        fos.write(bytes)
                                    }
                                } catch (_: Exception) {}
                            }
                        }
                    }
                    conn.disconnect()
                }

                if (bitmap != null) {
                    return toCircularBitmap(bitmap, sizePx)
                }
            } catch (e: Exception) {
                Log.d(TAG, "Avatar fetch skipped or timed out: ${e.message}")
            }
        }

        // Fallback: Initials Avatar
        return createInitialsAvatar(titleOrName, sizePx)
    }

    private fun toCircularBitmap(src: Bitmap, targetSize: Int): Bitmap {
        val output = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint().apply {
            isAntiAlias = true
            isFilterBitmap = true
        }

        val minEdge = Math.min(src.width, src.height)
        val srcRect = Rect(
            (src.width - minEdge) / 2,
            (src.height - minEdge) / 2,
            (src.width + minEdge) / 2,
            (src.height + minEdge) / 2
        )
        val dstRect = Rect(0, 0, targetSize, targetSize)

        canvas.drawCircle(targetSize / 2f, targetSize / 2f, targetSize / 2f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(src, srcRect, dstRect, paint)
        return output
    }

    private fun createInitialsAvatar(name: String, size: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val colors = intArrayOf(
            0xFF1E88E5.toInt(), 0xFF43A047.toInt(), 0xFFE53935.toInt(), 0xFF8E24AA.toInt(),
            0xFFFB8C00.toInt(), 0xFF00ACC1.toInt(), 0xFF3949AB.toInt(), 0xFFD81B60.toInt()
        )
        val color = colors[Math.abs(name.hashCode()) % colors.size]

        val bgPaint = Paint().apply {
            isAntiAlias = true
            this.color = color
            style = Paint.Style.FILL
        }
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, bgPaint)

        val initials = name.trim().take(1).uppercase(Locale.US).ifEmpty { "Z" }
        val textPaint = Paint().apply {
            isAntiAlias = true
            this.color = Color.WHITE
            textSize = size * 0.45f
            textAlign = Paint.Align.CENTER
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
        }
        val yPos = (canvas.height / 2f) - ((textPaint.descent() + textPaint.ascent()) / 2f)
        canvas.drawText(initials, size / 2f, yPos, textPaint)
        return bitmap
    }

    private fun isAppInForeground(): Boolean {
        return try {
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (keyguardManager?.isKeyguardLocked == true) {
                return false
            }

            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager?.isInteractive == false) {
                return false
            }

            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            val appProcesses = activityManager.runningAppProcesses ?: return false
            val currentProcessName = packageName
            for (appProcess in appProcesses) {
                if (appProcess.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                    appProcess.processName == currentProcessName) {
                    return true
                }
            }
            false
        } catch (e: Exception) {
            Log.e(TAG, "Error checking foreground state", e)
            false
        }
    }

    private fun showIncomingCallNotification(remoteMessage: RemoteMessage) {
        val callerUid = remoteMessage.data["caller_uid"] ?: return
        val callerName = remoteMessage.data["caller_name"] ?: "Unknown Caller"
        val callType = remoteMessage.data["call_type"] ?: "voice"

        Log.d(TAG, "=== Creating incoming call notification ===")
        Log.d(TAG, "Caller: $callerName")
        Log.d(TAG, "Caller UID: $callerUid")
        Log.d(TAG, "Call Type: $callType")

        // Create full-screen intent to launch the app
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("incoming_call", true)
            putExtra("answer_call", false) // false - user should choose to answer or decline
            putExtra("caller_uid", callerUid)
            putExtra("caller_name", callerName)
            putExtra("call_type", callType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        val fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            CALL_NOTIFICATION_ID,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create answer action - Launch MainActivity directly for better reliability
        val answerIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("incoming_call", true)
            putExtra("answer_call", true) // KEY: Auto-answer when launched from Answer button
            putExtra("caller_uid", callerUid)
            putExtra("caller_name", callerName)
            putExtra("call_type", callType)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        val answerPendingIntent = PendingIntent.getActivity(
            this,
            CALL_NOTIFICATION_ID + 1,
            answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create decline action
        val declineIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = ACTION_DECLINE_CALL
            putExtra("caller_uid", callerUid)
            putExtra("caller_name", callerName)
        }

        val declinePendingIntent = PendingIntent.getBroadcast(
            this,
            CALL_NOTIFICATION_ID + 2,
            declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Build full-screen call notification
        val notification = NotificationCompat.Builder(this, CALL_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher) // 🔧 FIX: Use app icon instead of default call icon
            .setContentTitle("Incoming ${callType} call")
            .setContentText(callerName)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setOngoing(true) // Can't be dismissed by swiping
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .addAction(
                android.R.drawable.ic_menu_call,
                "Answer",
                answerPendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline",
                declinePendingIntent
            )
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(longArrayOf(0, 1000, 500, 1000))
            .setSound(android.provider.Settings.System.DEFAULT_RINGTONE_URI)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(CALL_NOTIFICATION_ID, notification)

        Log.d(TAG, "Incoming call notification displayed for $callerName")
    }

    /**
     * Fetch and process missing sender keys from backend for group message decryption in background
     */
    private fun fetchAndProcessGroupSenderKeys(groupId: String, signalManager: SignalManager): Boolean {
        return try {
            val user = FirebaseAuth.getInstance().currentUser ?: return false
            val tokenTask = user.getIdToken(false)
            val tokenResult = com.google.android.gms.tasks.Tasks.await(tokenTask)
            val token = tokenResult.token ?: return false

            val targetUrl = "${AppConfig.BASE_URL}/groups/$groupId/sender-keys"
            Log.d(TAG, "Fetching sender keys for group $groupId from $targetUrl")
            val connection = (URL(targetUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                setRequestProperty("Authorization", "Bearer $token")
                connectTimeout = 7000
                readTimeout = 7000
            }

            val responseCode = connection.responseCode
            if (responseCode in 200..299) {
                val responseBody = connection.inputStream.bufferedReader().readText()
                connection.disconnect()

                val jsonArray = org.json.JSONArray(responseBody)
                var count = 0
                for (i in 0 until jsonArray.length()) {
                    val item = jsonArray.getJSONObject(i)
                    val sUid = item.optString("sender_uid")
                    val devId = item.optInt("device_id", 1)
                    val distribution = item.optString("sender_key_distribution")

                    if (sUid.isNotEmpty() && sUid != user.uid && distribution.isNotEmpty()) {
                        val success = signalManager.processSenderKeyDistribution(
                            senderUid = sUid,
                            senderDeviceId = devId,
                            groupId = groupId,
                            distributionMessageB64 = distribution
                        )
                        if (success) count++
                    }
                }
                Log.d(TAG, "Processed $count group sender keys from backend for group $groupId")
                count > 0
            } else {
                val errorBody = connection.errorStream?.bufferedReader()?.readText() ?: "(no body)"
                Log.w(TAG, "Failed to fetch sender keys: HTTP $responseCode - $errorBody")
                connection.disconnect()
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching sender keys for group $groupId: ${e.message}", e)
            false
        }
    }

}