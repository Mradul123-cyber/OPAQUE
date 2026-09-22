package com.zarq.messenger

import android.content.Context
import androidx.work.*
import com.google.firebase.auth.FirebaseAuth
import java.util.Calendar
import java.util.concurrent.TimeUnit
import java.util.concurrent.CancellationException

/** Durable account-scoped status; schedule operations run off the platform thread. */
object NativeBackupRuntime {
    val executionLock = java.util.concurrent.locks.ReentrantLock()
    private fun state(context: Context, uid: String) = context.getSharedPreferences("backup_status_$uid", Context.MODE_PRIVATE)

    fun report(context: Context, uid: String, run: String, status: String, message: String, progress: Int = 0) {
        val p = state(context, uid)
        val editor = p.edit().putString("run", run).putString("status", status)
            .putString("message", message).putInt("progress", progress)
        if (status == "success") editor.putLong("lastSuccess", System.currentTimeMillis())
        check(editor.commit()) { "Could not save backup status" }
    }

    fun checkRunning(context: Context, uid: String, generation: String, run: String, stopped: () -> Boolean) {
        if (stopped() || Thread.currentThread().isInterrupted ||
            !NativeBackupGuard.valid(context, uid, generation) ||
            state(context, uid).getString("cancelledRun", null) == run) {
            throw CancellationException("Backup stopped")
        }
    }

    fun cancelRun(context: Context, uid: String, run: String): Boolean = synchronized(NativeBackupGuard.lock) {
        val p = state(context, uid)
        if (p.getString("run", null) != run || p.getString("status", null) != "running") return@synchronized false
        check(p.edit().putString("cancelledRun", run).putString("status", "cancelling")
            .putString("message", "Stopping automatic backup…").commit())
        true
    }

    fun schedule(context: Context, uid: String, password: String, passphrase: String, hour: Int, minute: Int, interval: Int): Boolean = synchronized(NativeBackupGuard.lock) {
        require(hour in 0..23 && minute in 0..59 && interval in listOf(24, 168, 720))
        check(FirebaseAuth.getInstance().currentUser?.uid == uid) { "Account changed" }
        if (!LegacyBackupStorage.hasPermission(context)) throw SecurityException("Storage permission required")
        val wm = WorkManager.getInstance(context)
        val p = NativeBackupGuard.prefs(context)
        val fingerprint = java.security.MessageDigest.getInstance("SHA-256")
            .digest("$uid|$password|$passphrase|$hour|$minute|$interval".toByteArray())
            .joinToString("") { "%02x".format(it) }
        val existing = wm.getWorkInfosForUniqueWork(AutoBackupWorker.WORK_NAME).get().any { !it.state.isFinished }
        if (existing && p.getString("schedule_fingerprint", null) == fingerprint &&
            p.getBoolean("auto_backup_enabled", false)) return@synchronized true
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        val generation = NativeBackupGuard.configure(context, uid, password, passphrase)
        try {
            val request = PeriodicWorkRequestBuilder<AutoBackupWorker>(interval.toLong(), TimeUnit.HOURS)
                .setInputData(workDataOf("userUid" to uid, "generation" to generation))
                .setInitialDelay((target.timeInMillis - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .addTag(AutoBackupWorker.WORK_NAME).addTag("backup_generation_$generation").build()
            // Identical settings return above. Only an explicit configuration change replaces work.
            wm.enqueueUniquePeriodicWork(AutoBackupWorker.WORK_NAME, ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE, request).result.get()
            check(p.edit().putString("schedule_fingerprint", fingerprint).commit())
            true
        } catch (e: Exception) {
            NativeBackupGuard.disable(context)
            throw e
        }
    }

    fun status(context: Context): Map<String, Any?> {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return mapOf("enabled" to false)
        val p = NativeBackupGuard.prefs(context)
        val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork(AutoBackupWorker.WORK_NAME).get()
            .firstOrNull { !it.state.isFinished && (p.getString("schedule_fingerprint", null) == null ||
                it.tags.contains("backup_generation_${p.getString("backup_generation", "")}")) }
        val saved = state(context, uid)
        val enabled = p.getString("user_uid", null) == uid && p.getBoolean("auto_backup_enabled", false) && work != null
        var status = saved.getString("status", "idle") ?: "idle"
        var message = saved.getString("message", "") ?: ""
        val testRunning = WorkManager.getInstance(context).getWorkInfosForUniqueWork("test_native_backup").get()
            .any { it.state == WorkInfo.State.RUNNING }
        if (status in listOf("running", "cancelling") && work?.state != WorkInfo.State.RUNNING && !testRunning) {
            status = if (enabled) "queued" else "cancelled"
            message = if (enabled) "Waiting for Android to run the backup" else "Automatic backup stopped"
        }
        val next = work?.nextScheduleTimeMillis?.takeIf { enabled && it != Long.MAX_VALUE }
        return mapOf("userUid" to uid, "enabled" to enabled, "status" to status,
            "message" to message, "progress" to saved.getInt("progress", 0),
            "run" to saved.getString("run", ""), "lastSuccess" to saved.getLong("lastSuccess", 0),
            "nextRun" to next, "needsStoragePermission" to !LegacyBackupStorage.hasPermission(context))
    }
}
