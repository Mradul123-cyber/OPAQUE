package com.zarq.messenger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
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

            // Start the backup service instead of trying to load WorkManager plugin class
            try {
                val serviceIntent = Intent(context, AutoBackupService::class.java)
                context.startService(serviceIntent)

                Log.d(TAG, "✅ AutoBackupService started successfully!")
                Log.d(TAG, "🔄 Backup will execute in background service")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error starting backup service: ${e.message}", e)
            }
        }
    }
}
