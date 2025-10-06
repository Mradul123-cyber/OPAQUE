package com.example.zarq_messenger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class BackupNotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "zarq_backup_channel"
        const val CHANNEL_NAME = "Backup Notifications"
        const val SUCCESS_NOTIFICATION_ID = 1001
        const val FAILURE_NOTIFICATION_ID = 1002
        const val BATTERY_WARNING_NOTIFICATION_ID = 1003
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

    fun showSuccessNotification(backupType: String) {
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
            .setSmallIcon(android.R.drawable.ic_menu_save) // Use your app icon
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
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
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
            .setSmallIcon(android.R.drawable.ic_dialog_info)
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
}
