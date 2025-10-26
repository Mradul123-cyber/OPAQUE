package com.zarq.messenger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager

/**
 * AlarmManager receiver that triggers auto-backup at exact scheduled time
 * This ensures backups run at the exact time user expects (like WhatsApp)
 */
class AutoBackupAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AutoBackupAlarm"
        const val ACTION_TRIGGER_BACKUP = "com.zarq.messenger.TRIGGER_AUTO_BACKUP"
        private const val NOTIFICATION_ID = 8888
        private const val CHANNEL_ID = "auto_backup_alarm_channel"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TRIGGER_BACKUP) {
            Log.d(TAG, "")
            Log.d(TAG, "╔════════════════════════════════════════════════════════════╗")
            Log.d(TAG, "║ 🔔 AUTO-BACKUP ALARM TRIGGERED AT EXACT TIME!             ║")
            Log.d(TAG, "╠════════════════════════════════════════════════════════════╣")
            Log.d(TAG, "║ Time: ${java.util.Date()}")
            Log.d(TAG, "║ Timestamp: ${System.currentTimeMillis()}")
            Log.d(TAG, "╚════════════════════════════════════════════════════════════╝")
            Log.d(TAG, "")

            // IMMEDIATELY show notification when alarm triggers
            showBackupTriggeredNotification(context)

            // Start the backup service as a foreground service (required for Android 8+)
            try {
                val serviceIntent = Intent(context, AutoBackupService::class.java)

                // CRITICAL: Must use startForegroundService for Android 8+ to show notification
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                    Log.d(TAG, "✅ AutoBackupService started as FOREGROUND service (Android 8+)")
                } else {
                    context.startService(serviceIntent)
                    Log.d(TAG, "✅ AutoBackupService started as regular service (Android < 8)")
                }

                Log.d(TAG, "🔄 Backup will execute in background service")
                Log.d(TAG, "📱 Notification should be visible now!")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error starting backup service: ${e.message}", e)
            }
        }
    }

    private fun showBackupTriggeredNotification(context: Context) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Create notification channel for Android 8.0+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Auto Backup Alarm",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications when auto-backup is triggered"
                    enableLights(true)
                    enableVibration(true)
                }
                notificationManager.createNotificationChannel(channel)
            }

            // Get current time
            val currentTime = java.text.SimpleDateFormat("hh:mm:ss a", java.util.Locale.getDefault())
                .format(java.util.Date())

            // Build and show notification
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle("Auto Backup Triggered")
                .setContentText("Scheduled backup alarm fired at $currentTime")
                .setSubText("Open app to start backup")
                .setSmallIcon(android.R.drawable.ic_menu_save) // Using system icon for compatibility
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .build()

            notificationManager.notify(NOTIFICATION_ID, notification)

            Log.d(TAG, "✅ Notification shown successfully!")
            Log.d(TAG, "📱 Check notification panel - 'Auto Backup Triggered' should be visible")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing notification: ${e.message}", e)
        }
    }
}
