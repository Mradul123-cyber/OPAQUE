package com.zarq.messenger

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class ZarqNotificationService : FirebaseMessagingService() {

    companion object {
        private const val CHANNEL_ID = "zarq_messages"
        private const val CALL_CHANNEL_ID = "zarq_calls"
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
        val messageType = remoteMessage.data["message_type"] ?: "chat"

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

                    if (decryptedPlaintext == SignalManager.DUPLICATE_MESSAGE_MARKER) {
                        Log.d(TAG, "Message $messageId already decrypted previously")
                        decryptedPlaintext = null
                    } else {
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

        // 7. Build Modern MessagingStyle Notification
        val userPerson = androidx.core.app.Person.Builder()
            .setName("Me")
            .setKey(myUid ?: "me")
            .build()

        val senderPerson = androidx.core.app.Person.Builder()
            .setName(senderName)
            .setKey(senderUid ?: "sender")
            .build()

        val messagingStyle = NotificationCompat.MessagingStyle(userPerson)
            .setConversationTitle(if (isGroup) senderName else null)
            .setGroupConversation(isGroup)
            .addMessage(
                NotificationCompat.MessagingStyle.Message(
                    displayMessageText,
                    System.currentTimeMillis(),
                    senderPerson
                )
            )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setStyle(messagingStyle)
            .setContentTitle(senderName)
            .setContentText(displayMessageText)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
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
            .setVibrate(longArrayOf(0, 250, 250, 250))
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID_BASE + conversationId, notification)

        Log.d(TAG, "Notification posted with MessagingStyle for conversation: $conversationId")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Messages channel
            val messageChannel = NotificationChannel(
                CHANNEL_ID,
                "Zarq Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New message notifications"
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 250, 250)
                setShowBadge(true)
            }

            // Calls channel (max importance for full-screen notifications)
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

            notificationManager.createNotificationChannel(messageChannel)
            notificationManager.createNotificationChannel(callChannel)
            Log.d(TAG, "Notification channels created (messages + calls)")
        }
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

}