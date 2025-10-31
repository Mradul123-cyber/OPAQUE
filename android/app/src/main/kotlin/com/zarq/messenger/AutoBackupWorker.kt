package com.zarq.messenger

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * WorkManager worker for native auto-backup
 * Executes silently in background without launching app
 */
class AutoBackupWorker(
    context: Context,
    params: WorkerParameters
) : Worker(context, params) {

    companion object {
        private const val TAG = "AutoBackupWorker"
        const val WORK_NAME = "native_auto_backup"
    }

    override fun doWork(): Result {
        // Log.d(TAG, "")
        // Log.d(TAG, "══════════════════════════════════════════")
        // Log.d(TAG, "  AutoBackupWorker triggered")
        // Log.d(TAG, "  Time: ${java.util.Date()}")
        // Log.d(TAG, "══════════════════════════════════════════")
        // Log.d(TAG, "")

        return try {
            // Check if this is a test backup (has "test_backup" tag)
            val isTestBackup = tags.contains("test_backup")

            if (isTestBackup) {
                // Log.d(TAG, "🧪 Test backup mode - bypassing enabled check")
            } else {
                // For scheduled backups, check if auto-backup is enabled
                val prefs = applicationContext.getSharedPreferences("zarq_prefs", Context.MODE_PRIVATE)
                val autoBackupEnabled = prefs.getBoolean("auto_backup_enabled", false)

                if (!autoBackupEnabled) {
                    // Log.d(TAG, "⏭️  Auto-backup is disabled, skipping")
                    return Result.success()
                }
            }

            // Log.d(TAG, "✅ Proceeding with backup...")

            // Show notification that backup is starting
            BackupNotificationHelper(applicationContext).showProgressNotification(
                "Starting auto-backup...",
                0
            )

            // Execute native backup
            val backupManager = NativeBackupManager(applicationContext)
            val success = backupManager.performBackup()

            if (success) {
                Log.d(TAG, "")
                Log.d(TAG, "══════════════════════════════════════════")
                Log.d(TAG, "  ✅ AutoBackupWorker completed successfully")
                Log.d(TAG, "══════════════════════════════════════════")
                Log.d(TAG, "")

                // Show success notification
                BackupNotificationHelper(applicationContext).showSuccessNotification("Auto")

                Result.success()
            } else {
                Log.e(TAG, "")
                Log.e(TAG, "══════════════════════════════════════════")
                Log.e(TAG, "  ❌ AutoBackupWorker failed")
                Log.e(TAG, "  Will retry later...")
                Log.e(TAG, "══════════════════════════════════════════")
                Log.e(TAG, "")

                // Show failure notification
                BackupNotificationHelper(applicationContext).showFailureNotification(
                    "Auto",
                    "Backup failed, will retry"
                )

                Result.retry()
            }

        } catch (e: Exception) {
            Log.e(TAG, "")
            Log.e(TAG, "══════════════════════════════════════════")
            Log.e(TAG, "  ❌ AutoBackupWorker exception: ${e.message}")
            Log.e(TAG, "══════════════════════════════════════════")
            Log.e(TAG, "", e)

            // Show failure notification
            BackupNotificationHelper(applicationContext).showFailureNotification(
                "Auto",
                "Error: ${e.message}"
            )

            Result.failure()
        }
    }
}
