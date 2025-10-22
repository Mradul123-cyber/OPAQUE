package com.zarq.messenger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class SentMessageReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SentMessageReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "com.example.zarq_messenger.MESSAGE_SENT") {
            Log.d(TAG, "Received sent message broadcast")

            val conversationId = intent.getIntExtra("conversation_id", -1)
            val localMessageId = intent.getLongExtra("local_message_id", -1L)
            val realMessageId = intent.getIntExtra("real_message_id", -1)  // ADD THIS
            val messageText = intent.getStringExtra("message_text")
            val senderUid = intent.getStringExtra("sender_uid")

            if (conversationId == -1 || localMessageId == -1L || realMessageId == -1 || messageText == null || senderUid == null) {
                Log.e(TAG, "Invalid broadcast data received")
                return
            }

            Log.d(TAG, "Processing sent message: $messageText (local: $localMessageId, real: $realMessageId)")

            // Pass both IDs to Flutter
            notifyFlutter(conversationId, localMessageId, realMessageId, messageText, senderUid)
        }
    }

    private fun notifyFlutter(conversationId: Int, localMessageId: Long, realMessageId: Int, messageText: String, senderUid: String) {
        try {
            val flutterEngine = MainActivity.flutterEngineInstance
            if (flutterEngine != null) {
                val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zarq/sent_messages")

                val messageData = mapOf(
                    "conversation_id" to conversationId,
                    "local_message_id" to localMessageId,
                    "real_message_id" to realMessageId,  // ADD THIS
                    "message_text" to messageText,
                    "sender_uid" to senderUid,
                    "timestamp" to System.currentTimeMillis()
                )

                channel.invokeMethod("onMessageSent", messageData)
                Log.d(TAG, "Notified Flutter about sent message: local=$localMessageId, real=$realMessageId")
            } else {
                Log.w(TAG, "Flutter engine not available, cannot notify")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to notify Flutter: ${e.message}", e)
        }
    }


}
