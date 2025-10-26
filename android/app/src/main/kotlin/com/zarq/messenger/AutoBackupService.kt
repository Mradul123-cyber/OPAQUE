package com.zarq.messenger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that executes auto-backup when triggered by AlarmManager
 * Runs as foreground service to bypass Android background activity launch restrictions
 */
class AutoBackupService : Service() {

    companion object {
        private const val TAG = "AutoBackupService"
        private const val NOTIFICATION_ID = 9999
        private const val CHANNEL_ID = "auto_backup_service_channel"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🔥 AutoBackupService started - executing backup now")

        // CRITICAL: Start as foreground service IMMEDIATELY to bypass background restrictions
        startForeground(NOTIFICATION_ID, createNotification())

        // Execute backup in a background thread
        Thread {
            try {
                executeBackup()
                // Keep service running for a bit to ensure notification is visible
                Thread.sleep(10000) // Show notification for 10 seconds (enough time for video capture)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error executing backup: ${e.message}", e)
            } finally {
                // Stop foreground service
                stopForeground(true)
                stopSelf(startId)
            }
        }.start()

        return START_NOT_STICKY
    }

    private fun createNotification(): Notification {
        // Create notification channel for Android 8.0+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Auto Backup Service",
                NotificationManager.IMPORTANCE_DEFAULT // Changed from LOW to DEFAULT for better visibility
            ).apply {
                description = "Scheduled auto-backup notifications"
                setShowBadge(true)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }

        // Build notification with current time
        val currentTime = java.text.SimpleDateFormat("hh:mm:ss a", java.util.Locale.getDefault())
            .format(java.util.Date())

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Auto Backup Triggered")
            .setContentText("Scheduled backup triggered at $currentTime")
            .setSubText("Backup will start when you open the app")
            .setSmallIcon(R.mipmap.ic_launcher) // Use app icon instead of deprecated system icon
            .setPriority(NotificationCompat.PRIORITY_HIGH) // Changed to HIGH for maximum visibility
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // Show on lock screen
            .build()
    }

    private fun executeBackup() {
        Log.d(TAG, "📦 Starting MainActivity to execute backup")

        try {
            // Create intent to start MainActivity with backup trigger flag
            val intent = Intent(applicationContext, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("trigger_auto_backup", true)
                action = "com.zarq.messenger.TRIGGER_BACKUP"
            }

            // As a foreground service, we can now launch activities even from background!
            applicationContext.startActivity(intent)

            Log.d(TAG, "✅ MainActivity launch intent sent - backup will execute via Flutter")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting MainActivity: ${e.message}", e)

            // Fallback: show notification that backup failed
            val backupHelper = BackupNotificationHelper(applicationContext)
            backupHelper.showFailureNotification("Auto", "Failed to start backup: ${e.message}")
        }
    }
}
