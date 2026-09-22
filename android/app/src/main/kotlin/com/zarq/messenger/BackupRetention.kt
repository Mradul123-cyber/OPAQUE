package com.zarq.messenger

import android.content.Context
import android.net.Uri
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.security.MessageDigest

/** Only files recorded after verified publication are eligible for automatic pruning. */
object BackupRetention {
    private fun prefs(context: Context, uid: String) = context.getSharedPreferences("backup_retention_$uid", Context.MODE_PRIVATE)
    private fun open(context: Context, uri: String): InputStream = if (uri.startsWith("file:")) {
        LegacyBackupStorage.file(context, uri).inputStream()
    } else context.contentResolver.openInputStream(Uri.parse(uri)) ?: throw java.io.IOException("Backup cannot be read")

    private fun digest(input: InputStream, checkRunning: () -> Unit): Pair<Long, String> = input.use {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        var size = 0L
        while (true) {
            checkRunning()
            val count = it.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count); size += count
        }
        size to digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    fun verify(context: Context, uri: String, source: File, checkRunning: () -> Unit): Pair<Long, String> {
        val expected = digest(source.inputStream(), checkRunning)
        val actual = digest(open(context, uri), checkRunning)
        if (expected.first < 60 || actual != expected) throw java.io.IOException("Saved backup verification failed")
        return actual
    }

    fun record(context: Context, uid: String, uri: String, name: String, verified: Pair<Long, String>) {
        val p = prefs(context, uid)
        val entries = JSONArray(p.getString("verified", "[]"))
        entries.put(JSONObject().put("uri", uri).put("name", name).put("size", verified.first)
            .put("sha256", verified.second).put("created", System.currentTimeMillis()))
        if (!p.edit().putString("verified", entries.toString()).commit()) throw java.io.IOException("Could not record backup")
    }

    fun prune(context: Context, uid: String, checkRunning: () -> Unit) {
        val p = prefs(context, uid)
        val entries = JSONArray(p.getString("verified", "[]"))
        val ordered = (0 until entries.length()).map { entries.getJSONObject(it) }
            .sortedByDescending { it.getLong("created") }
        val available = MediaStoreHelper.listBackups(context).associateBy { it["uri"] as String }
        val remaining = JSONArray()
        val prefix = "auto_backup_" + MessageDigest.getInstance("SHA-256").digest(uid.toByteArray())
            .joinToString("") { "%02x".format(it) }.take(16) + "_"
        var verifiedKept = 0
        for (entry in ordered) {
            checkRunning()
            val uri = entry.getString("uri")
            val info = available[uri]
            // Missing/renamed files are retained in the ledger and never deleted by guessing.
            if (info == null || info["name"] != entry.getString("name") || !entry.getString("name").startsWith(prefix)) {
                remaining.put(entry); continue
            }
            val valid = try {
                val actual = digest(open(context, uri), checkRunning)
                actual.first == entry.getLong("size") && actual.second == entry.getString("sha256")
            } catch (e: java.util.concurrent.CancellationException) { throw e }
              catch (e: Exception) { Log.w("BackupRetention", "Could not verify older backup", e); false }
            if (!valid || verifiedKept < 2) {
                if (valid) verifiedKept++
                remaining.put(entry); continue
            }
            val deleted = synchronized(NativeBackupGuard.lock) {
                checkRunning()
                MediaStoreHelper.deleteBackup(context, uri)
            }
            if (!deleted) remaining.put(entry)
        }
        // If cleanup is interrupted, the old ledger is safe to revisit on the next run.
        checkRunning()
        if (!p.edit().putString("verified", remaining.toString()).commit()) throw java.io.IOException("Could not update retention status")
    }
}
