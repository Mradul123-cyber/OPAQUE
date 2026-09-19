package com.zarq.messenger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
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
                // Check if we should show notification (app in background)
                if (!isAppInForeground()) {
                    Log.d(TAG, "App in background, showing message notification")
                    showNotification(remoteMessage)
                } else {
                    Log.d(TAG, "App in foreground, skipping notification display")
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

        // Store token locally for later upload
        val sharedPrefs = getSharedPreferences("zarq_fcm", Context.MODE_PRIVATE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.GINGERBREAD) {
            sharedPrefs.edit()
                .putString("fcm_token", token)
                .putBoolean("token_needs_upload", true)
                .apply()
        }

        Log.d(TAG, "FCM token stored locally, will upload when auth token available")

        // Try to upload immediately (will fail without auth, but that's okay)
        sendTokenToServer(token)
    }

    private fun showNotification(remoteMessage: RemoteMessage) {
        val conversationId = remoteMessage.data["conversation_id"]?.toIntOrNull() ?: return
        val messageId = remoteMessage.data["message_id"]?.toIntOrNull() ?: 0
        val senderName = remoteMessage.data["sender_username"] ?: "Unknown"
        val messageText = "You have a new message" // Don't show encrypted content

        // Check if conversation is muted
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isMuted = prefs.getBoolean("flutter.muted_$conversationId", false)

        if (isMuted) {
            Log.d(TAG, "Conversation $conversationId is muted, skipping notification")
            return
        }

        // EXTRACT UIDs FROM FCM DATA - THESE ARE CRITICAL FOR QUICK REPLY
        val senderUid = remoteMessage.data["sender_uid"]
        val recipientUid = remoteMessage.data["recipient_uid"]
        val currentUser = FirebaseAuth.getInstance().currentUser
        val myUid = currentUser?.uid

        if (senderUid == myUid) {
            Log.d(TAG, "Suppressing notification for own message from $senderUid")
            return
        }

        Log.d(TAG, "=== Creating notification ===")
        Log.d(TAG, "Conversation ID: $conversationId")
        Log.d(TAG, "Message ID: $messageId")
        Log.d(TAG, "Sender: $senderName")
        Log.d(TAG, "Sender UID: $senderUid")
        Log.d(TAG, "Recipient UID: $recipientUid")

        if (senderUid.isNullOrEmpty() || recipientUid.isNullOrEmpty()) {
            Log.w(TAG, "Missing sender or recipient UID, quick reply won't work properly")
        }

        // Create main tap intent
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            putExtra("conversation_id", conversationId)
            putExtra("message_id", messageId)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        Log.d(TAG, "Intent created with extras: conversation_id=$conversationId, message_id=$messageId")

        val mainPendingIntent = PendingIntent.getActivity(
            this,
            conversationId,
            mainIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create mark as read action
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

        // Create quick reply action - NOW WITH UIDs FOR ENCRYPTION
        val replyIntent = Intent(this, NotificationActionReceiver::class.java).apply {
            action = ACTION_REPLY
            putExtra("conversation_id", conversationId)
            putExtra("message_id", messageId)

            // CRITICAL: Add UIDs so NotificationActionReceiver can determine encryption target
            putExtra("sender_uid", senderUid)
            putExtra("recipient_uid", recipientUid)
        }

        val replyPendingIntent = PendingIntent.getBroadcast(
            this,
            conversationId + 2000,
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        // Create remote input for quick reply
        val remoteInput = RemoteInput.Builder(KEY_TEXT_REPLY)
            .setLabel("Type a message...")
            .build()

        // Build notification
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher) // Use app icon
            .setContentTitle(senderName)
            .setContentText(messageText)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setContentIntent(mainPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_agenda, // Default check-like icon
                "Mark Read",
                markReadPendingIntent
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    android.R.drawable.ic_menu_send, // Default send icon
                    "Reply",
                    replyPendingIntent
                ).addRemoteInput(remoteInput).build()
            )
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVibrate(longArrayOf(0, 250, 250, 250))
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID_BASE + conversationId, notification)

        Log.d(TAG, "Notification displayed for conversation: $conversationId with encryption UIDs")
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
        // Simple check - you can enhance this with proper app state tracking
        return false // For now, always show notifications
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

    private fun sendTokenToServer(token: String) {
        Log.d(TAG, "Uploading FCM token to server: $token")

        // Launch coroutine for network call
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val url = URL("\${AppConfig.BASE_URL}/v1/fcm/token")
                val connection = url.openConnection() as HttpURLConnection

                // Your Go server expects: {"fcm_token": "...", "device_id": 1, "platform": "android"}
                val jsonPayload = JSONObject().apply {
                    put("fcm_token", token)
                    put("device_id", 1)
                    put("platform", "android")
                }

                connection.apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/json")
                    // TODO: Add Firebase Auth token when available
                    // setRequestProperty("Authorization", "Bearer $firebaseAuthToken")
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 5000
                }

                connection.outputStream.use { os ->
                    os.write(jsonPayload.toString().toByteArray())
                    os.flush()
                }

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    Log.d(TAG, "FCM token uploaded successfully: $responseCode")
                } else {
                    Log.e(TAG, "FCM token upload failed: $responseCode")
                }

                connection.disconnect()

            } catch (e: Exception) {
                Log.e(TAG, "Failed to upload FCM token: ${e.message}")
            }
        }
    }
}