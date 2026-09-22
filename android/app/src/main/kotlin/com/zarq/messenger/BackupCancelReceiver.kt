package com.zarq.messenger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class BackupCancelReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_CANCEL_BACKUP = "com.zarq.messenger.CANCEL_BACKUP"
        private const val TAG = "BackupCancelReceiver"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == ACTION_CANCEL_BACKUP) {
            Log.d(TAG, "Backup cancellation requested via notification")

            val nativeRun = intent.getStringExtra("native_run")
            val nativeUid = intent.getStringExtra("native_uid")
            if (context != null && nativeRun != null && nativeUid != null) {
                val pending = goAsync()
                val app = context.applicationContext
                Thread {
                    try { NativeBackupRuntime.cancelRun(app, nativeUid, nativeRun) }
                    finally { pending.finish() }
                }.start()
                return
            }
            // Manual Flutter operations keep their existing cancellation route.
            // Try to notify Flutter via MethodChannel
            MainActivity.flutterEngineInstance?.dartExecutor?.binaryMessenger?.let { messenger ->
                val channel = MethodChannel(messenger, "com.zarq/backup")

                Log.d(TAG, "Invoking cancelBackup on Flutter")
                channel.invokeMethod("cancelBackup", null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        Log.d(TAG, "✅ Cancel backup event sent successfully to Flutter")
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.e(TAG, "❌ Cancel backup error: $errorCode - $errorMessage")
                    }

                    override fun notImplemented() {
                        Log.w(TAG, "⚠️ cancelBackup not implemented in Flutter yet")
                    }
                })
            } ?: run {
                Log.e(TAG, "❌ Flutter engine not available for backup cancellation")
            }

            // Cancel the progress notification
            context?.let {
                val helper = BackupNotificationHelper(it)
                helper.cancelAllBackupNotifications()
            }
        }
    }
}
