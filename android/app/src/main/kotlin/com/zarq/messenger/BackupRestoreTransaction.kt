package com.zarq.messenger

import android.content.Context
import android.content.SharedPreferences
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject
import java.io.File

/** Crash journal contains device-local encrypted rollback state, never a portable backup. */
object BackupRestoreTransaction {
    private const val KEY = "restore_rollback_journal"
    fun pending(context: Context) = NativeBackupGuard.prefs(context).getBoolean("restore_pending", false)

    private fun snapshot(prefs: SharedPreferences): JSONObject {
        val data = JSONObject()
        for ((key, value) in prefs.all) {
            val type = when (value) {
                is String -> "string"; is Int -> "int"; is Long -> "long"
                is Boolean -> "bool"; is Float -> "float"
                else -> error("Unsupported Signal preference type")
            }
            data.put(key, JSONObject().put("type", type).put("value", value))
        }
        return data
    }

    private fun restore(prefs: SharedPreferences, data: JSONObject) {
        val editor = prefs.edit().clear()
        for (key in data.keys()) {
            val item = data.getJSONObject(key)
            when (item.getString("type")) {
                "string" -> editor.putString(key, item.getString("value"))
                "int" -> editor.putInt(key, item.getInt("value"))
                "long" -> editor.putLong(key, item.getLong("value"))
                "bool" -> editor.putBoolean(key, item.getBoolean("value"))
                "float" -> editor.putFloat(key, item.getDouble("value").toFloat())
                else -> error("Invalid rollback preference type")
            }
        }
        check(editor.commit()) { "Could not restore security state" }
    }

    fun begin(context: Context, uid: String, state: String): Unit = synchronized(NativeBackupGuard.lock) {
        check(FirebaseAuth.getInstance().currentUser?.uid == uid) { "Restore account changed" }
        check(!pending(context)) { "An earlier restore requires recovery" }
        val db = context.getDatabasePath("zarq_messages_$uid.db")
        val stage = File(db.path + ".restore-stage")
        val rollback = File(db.path + ".restore-rollback")
        if (rollback.exists()) check(rollback.delete()) { "Could not replace previous rollback copy" }
        check(stage.isFile) { "Restore files are not ready" }
        check(!File(db.path + "-wal").exists() || File(db.path + "-wal").length() == 0L) { "Database must be checkpointed and closed" }
        val parsed = JSONObject(state)
        check(parsed.has("protocol_state") && parsed.has("identity_key_pair")) { "Missing recovery keys" }
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val journal = JSONObject().put("uid", uid).put("hadDatabase", db.exists())
            .put("hadReregistrationFlag", flutterPrefs.contains("flutter.needs_device_reregistration"))
            .put("reregistrationFlag", flutterPrefs.getBoolean("flutter.needs_device_reregistration", false))
            .put("keys", snapshot(context.getSharedPreferences("signal_keys_$uid", Context.MODE_PRIVATE)))
            .put("protocol", snapshot(context.getSharedPreferences("signal_protocol_store_$uid", Context.MODE_PRIVATE)))
        check(NativeBackupGuard.secure(context).edit().putString(KEY, journal.toString()).commit())
        check(NativeBackupGuard.prefs(context).edit().putBoolean("restore_pending", true).commit())
        NativeBackupGuard.disable(context)
        try {
            if (db.exists()) check(db.renameTo(rollback)) { "Could not retain original database" }
            check(stage.renameTo(db)) { "Could not install staged database" }
            check(SignalManager(context).importSignalState(state)) { "Security state import failed" }
        } catch (e: Exception) {
            recover(context)
            throw e
        }
    }

    fun finish(context: Context): Unit = synchronized(NativeBackupGuard.lock) {
        val raw = NativeBackupGuard.secure(context).getString(KEY, null) ?: error("No restore journal")
        val journal = JSONObject(raw)
        check(FirebaseAuth.getInstance().currentUser?.uid == journal.getString("uid"))
        // Mark committed durably before cleanup. A crash here keeps the new database.
        check(NativeBackupGuard.secure(context).edit().putString(KEY, journal.put("committed", true).toString()).commit())
        recover(context)
    }

    fun recover(context: Context): Unit = synchronized(NativeBackupGuard.lock) {
        if (!pending(context)) return@synchronized
        val raw = NativeBackupGuard.secure(context).getString(KEY, null) ?: error("Recovery journal unavailable; original data retained")
        val journal = JSONObject(raw)
        val uid = journal.getString("uid")
        val db = context.getDatabasePath("zarq_messages_$uid.db")
        val rollback = File(db.path + ".restore-rollback")
        if (!journal.optBoolean("committed", false)) {
            if (rollback.exists()) {
                // Repeated recovery is safe: retain rollback until keys and marker are restored.
                if (db.exists()) check(db.delete())
                File(db.path + "-wal").delete(); File(db.path + "-shm").delete()
                java.io.FileOutputStream(db).use { output ->
                    rollback.inputStream().use { input -> input.copyTo(output) }
                    output.fd.sync()
                }
            } else if (!journal.getBoolean("hadDatabase")) {
                if (db.exists()) check(db.delete())
                File(db.path + "-wal").delete(); File(db.path + "-shm").delete()
            }
            restore(context.getSharedPreferences("signal_keys_$uid", Context.MODE_PRIVATE), journal.getJSONObject("keys"))
            restore(context.getSharedPreferences("signal_protocol_store_$uid", Context.MODE_PRIVATE), journal.getJSONObject("protocol"))
            val editor = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            if (journal.optBoolean("hadReregistrationFlag")) {
                editor.putBoolean("flutter.needs_device_reregistration", journal.optBoolean("reregistrationFlag"))
            } else {
                editor.remove("flutter.needs_device_reregistration")
            }
            check(editor.commit()) { "Could not restore registration marker" }
        }
        check(NativeBackupGuard.prefs(context).edit().putBoolean("restore_pending", false).commit())
        // Keep the encrypted rollback file until the next restore explicitly replaces it.
        NativeBackupGuard.secure(context).edit().remove(KEY).commit()
        File(db.path + ".restore-stage").delete()
        Unit
    }
}
