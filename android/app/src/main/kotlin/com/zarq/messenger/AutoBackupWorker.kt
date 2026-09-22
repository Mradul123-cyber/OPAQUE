package com.zarq.messenger

import android.content.Context
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.UUID
import java.util.concurrent.CancellationException

class AutoBackupWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    companion object { const val WORK_NAME = "native_auto_backup" }
    private val run = UUID.randomUUID().toString()
    override fun doWork(): Result {
        val uid = inputData.getString("userUid") ?: return Result.failure()
        val generation = inputData.getString("generation") ?: return Result.failure()
        if (!NativeBackupGuard.valid(applicationContext, uid, generation)) return Result.success()
        if (!NativeBackupRuntime.executionLock.tryLock()) return Result.retry()
        val notifications = BackupNotificationHelper(applicationContext, native = true)
        fun notifySafely(action: () -> Unit) { try { action() } catch (e: SecurityException) { Log.w(WORK_NAME, "Notifications not permitted", e) } }
        fun checkRunning() = NativeBackupRuntime.checkRunning(applicationContext, uid, generation, run) { isStopped }
        try {
            checkRunning()
            NativeBackupManager(applicationContext).performBackup(uid, generation, ::checkRunning,
                { message, progress ->
                    synchronized(NativeBackupGuard.lock) {
                        checkRunning()
                        NativeBackupRuntime.report(applicationContext, uid, run, "running", message, progress)
                        notifySafely { notifications.showProgressNotification(message, progress, uid, run) }
                    }
                }, {
                    NativeBackupRuntime.report(applicationContext, uid, run, "success", "Automatic backup completed", 100)
                })
            notifySafely { notifications.showSuccessNotification("Auto") }
            return Result.success()
        } catch (e: CancellationException) {
            NativeBackupRuntime.report(applicationContext, uid, run, "cancelled", "Automatic backup stopped")
            notifySafely { notifications.cancelAllBackupNotifications() }
            return Result.success()
        } catch (e: Exception) {
            Log.e(WORK_NAME, "Automatic backup failed", e)
            if (isStopped || !NativeBackupGuard.valid(applicationContext, uid, generation)) {
                NativeBackupRuntime.report(applicationContext, uid, run, "cancelled", "Automatic backup stopped")
                notifySafely { notifications.cancelAllBackupNotifications() }
                return Result.success()
            }
            val transient = e is java.io.IOException || e.javaClass.simpleName.contains("Locked") || e.javaClass.simpleName.contains("Busy")
            val retry = transient && runAttemptCount < 2
            val message = when {
                retry -> "Backup could not finish. Android will retry shortly."
                e is SecurityException -> "Allow storage access, then enable automatic backups again."
                transient -> "Backup could not finish after three attempts. Check free space and try again."
                else -> "Automatic backup needs attention. Open the app and enable it again."
            }
            NativeBackupRuntime.report(applicationContext, uid, run, if (retry) "retrying" else "failed", message)
            if (!transient) synchronized(NativeBackupGuard.lock) {
                if (NativeBackupGuard.valid(applicationContext, uid, generation)) NativeBackupGuard.disable(applicationContext)
            }
            notifySafely { notifications.showFailureNotification("Auto", message) }
            return if (retry) Result.retry() else Result.success()
        } finally { NativeBackupRuntime.executionLock.unlock() }
    }
}
