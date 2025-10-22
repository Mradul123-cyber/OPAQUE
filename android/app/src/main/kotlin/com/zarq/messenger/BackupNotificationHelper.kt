package com.zarq.messenger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class BackupNotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "zarq_backup_channel"
        const val CHANNEL_NAME = "Backup Notifications"
        const val SUCCESS_NOTIFICATION_ID = 1001
        const val FAILURE_NOTIFICATION_ID = 1002
        const val BATTERY_WARNING_NOTIFICATION_ID = 1003
        const val PROGRESS_NOTIFICATION_ID = 1004
    }

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications for backup status"
                enableVibration(true)
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun showProgressNotification(status: String, progress: Int) {
        // Create cancel action intent
        val cancelIntent = Intent(context, BackupCancelReceiver::class.java).apply {
            action = BackupCancelReceiver.ACTION_CANCEL_BACKUP
        }

        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Backup/Restore in Progress")
            .setContentText(status)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true) // Cannot be dismissed
            .setProgress(100, progress, false) // Determinate progress bar
            .setAutoCancel(false)
            .addAction(
                R.drawable.ic_launcher_foreground, // Use a cancel icon if available
                "Cancel",
                cancelPendingIntent
            )
            .build()

        with(NotificationManagerCompat.from(context)) {
            notify(PROGRESS_NOTIFICATION_ID, notification)
        }
    }

    fun showSuccessNotification(backupType: String) {
        // Cancel progress notification first
        with(NotificationManagerCompat.from(context)) {
            cancel(PROGRESS_NOTIFICATION_ID)
        }

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Backup Completed")
            .setContentText("Your $backupType backup was created successfully")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        with(NotificationManagerCompat.from(context)) {
            notify(SUCCESS_NOTIFICATION_ID, notification)
        }
    }

    fun showFailureNotification(backupType: String, errorMessage: String) {
        // Cancel progress notification first
        with(NotificationManagerCompat.from(context)) {
            cancel(PROGRESS_NOTIFICATION_ID)
        }

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("open_backup_screen", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Backup Failed")
            .setContentText("$backupType backup failed: $errorMessage")
            .setStyle(NotificationCompat.BigTextStyle().bigText("$backupType backup failed: $errorMessage"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        with(NotificationManagerCompat.from(context)) {
            notify(FAILURE_NOTIFICATION_ID, notification)
        }
    }

    fun showBatteryOptimizationWarning() {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("open_battery_settings", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Auto-Backup Optimization")
            .setContentText("Disable battery optimization for reliable auto-backups")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("For reliable auto-backups, please disable battery optimization for Zarq Messenger. Tap to learn more."))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        with(NotificationManagerCompat.from(context)) {
            notify(BATTERY_WARNING_NOTIFICATION_ID, notification)
        }
    }

    fun cancelAllBackupNotifications() {
        with(NotificationManagerCompat.from(context)) {
            cancel(SUCCESS_NOTIFICATION_ID)
            cancel(FAILURE_NOTIFICATION_ID)
            cancel(BATTERY_WARNING_NOTIFICATION_ID)
            cancel(PROGRESS_NOTIFICATION_ID)
        }
    }

    fun isBatteryOptimizationDisabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(context.packageName)
        } else {
            true // Battery optimization doesn't exist on older versions
        }
    }

    fun requestBatteryOptimizationExemption(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Open app's battery settings page directly
                // This allows user to configure BOTH:
                // 1. Battery optimization (set to "Unrestricted")
                // 2. Background activity (enable it)
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                android.util.Log.d("BackupNotification", "Opened app settings - user needs to:")
                android.util.Log.d("BackupNotification", "1. Tap 'Battery' → Set to 'Unrestricted'")
                android.util.Log.d("BackupNotification", "2. Enable 'Allow background activity'")
                false // User needs to configure manually
            } else {
                true // Not needed on older versions
            }
        } catch (e: Exception) {
            android.util.Log.e("BackupNotification", "Error opening app settings: $e")
            false
        }
    }
}
