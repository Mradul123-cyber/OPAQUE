package com.zarq.messenger

import android.content.Context
import com.google.firebase.auth.FirebaseAuth
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import androidx.work.WorkManager
import java.util.UUID

/** One account/configuration generation owns every scheduled backup. */
object NativeBackupGuard {
    val lock = Any()
    private var listener: FirebaseAuth.AuthStateListener? = null
    fun prefs(context: Context) = context.getSharedPreferences("zarq_prefs", Context.MODE_PRIVATE)
    fun secure(context: Context) = EncryptedSharedPreferences.create(
        context, "zarq_secure_prefs", MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)

    fun initialize(context: Context) {
        if (listener != null) return
        val app = context.applicationContext
        listener = FirebaseAuth.AuthStateListener { auth ->
            synchronized(lock) {
                val owner = prefs(app).getString("user_uid", null)
                if (owner != null && owner != auth.currentUser?.uid) disable(app)
            }
        }
        FirebaseAuth.getInstance().addAuthStateListener(listener!!)
    }

    fun configure(context: Context, uid: String, password: String, passphrase: String): String = synchronized(lock) {
        check(FirebaseAuth.getInstance().currentUser?.uid == uid) { "Backup account changed" }
        check(!BackupRestoreTransaction.pending(context)) { "Restore is in progress" }
        require(password.isNotBlank() && passphrase.isNotBlank())
        val generation = UUID.randomUUID().toString()
        check(secure(context).edit()
            .putString("database_password_$uid", password)
            .putString("auto_backup_passphrase_$uid", passphrase)
            .remove("database_password").remove("auto_backup_passphrase").commit())
        check(prefs(context).edit().putString("user_uid", uid)
            .putString("backup_generation", generation).putBoolean("auto_backup_enabled", true).commit())
        generation
    }

    fun valid(context: Context, uid: String, generation: String): Boolean {
        val p = prefs(context)
        return FirebaseAuth.getInstance().currentUser?.uid == uid &&
            p.getString("user_uid", null) == uid && p.getBoolean("auto_backup_enabled", false) &&
            p.getString("backup_generation", null) == generation && !BackupRestoreTransaction.pending(context)
    }

    fun disable(context: Context): Unit = synchronized(lock) {
        check(prefs(context).edit().putBoolean("auto_backup_enabled", false)
            .remove("backup_generation").commit())
        WorkManager.getInstance(context).cancelUniqueWork(AutoBackupWorker.WORK_NAME)
    }
}
