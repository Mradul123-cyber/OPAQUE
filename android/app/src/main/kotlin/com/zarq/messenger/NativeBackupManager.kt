package com.zarq.messenger

import android.content.Context
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

/**
 * Native Kotlin backup manager for auto-backup
 * Performs WhatsApp-style silent backup without launching Flutter
 */
class NativeBackupManager(private val context: Context) {

    companion object {
        private const val TAG = "NativeBackupManager"
        private const val BACKUP_VERSION = "2.1.0"
        private const val PREFS_NAME = "zarq_prefs"
        private const val ENCRYPTED_PREFS_NAME = "zarq_secure_prefs"
    }

    /**
     * Perform complete native backup
     * This is the main entry point called by AutoBackupWorker
     *
     * @return true after verified publication; failures throw to the worker
     */
    fun performBackup(expectedUid: String, generation: String,
        checkStopped: () -> Unit = {}, progress: (String, Int) -> Unit = { _, _ -> },
        onSaved: () -> Unit = {}): Boolean {
        fun checkRunning() {
            checkStopped()
            if (!NativeBackupGuard.valid(context, expectedUid, generation))
                throw java.util.concurrent.CancellationException("Backup account changed")
        }
        checkRunning()
        val passphrase = getBackupPassphrase(expectedUid) ?: error("Backup passphrase unavailable")
        val dbPassword = getDatabasePassword(expectedUid) ?: error("Database key unavailable")
        progress("Preparing recovery data…", 5)
        val signalState = exportSignalProtocolState()
        checkRunning()
        val state = org.json.JSONObject(signalState.data)
        check(state.getInt("device_id") > 0 && state.getInt("registration_id") > 0)
        check(state.optJSONObject("protocol_state") != null && !state.isNull("identity_key_pair"))
        val identity = org.json.JSONObject(state.getString("identity_key_pair"))
        val privateKey = android.util.Base64.decode(identity.getString("private_key"), android.util.Base64.NO_WRAP)
        check(privateKey.size == 32)
        check(android.util.Base64.decode(identity.getString("public_key"), android.util.Base64.NO_WRAP).size == 33)
        val derivedPassword = java.security.MessageDigest.getInstance("SHA-256")
            .digest(privateKey + "zarq_database_encryption_v1".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        check(derivedPassword == dbPassword) { "Database and recovery identity do not match" }
        val account = java.security.MessageDigest.getInstance("SHA-256").digest(expectedUid.toByteArray())
            .joinToString("") { "%02x".format(it) }.take(16)
        val name = "auto_backup_${account}_${System.currentTimeMillis()}_${UUID.randomUUID()}.encrypted"
        val staging = java.io.File(context.cacheDir, "opaque-auto-backup-stage")
        if (!staging.isDirectory && !staging.mkdirs()) throw java.io.IOException("Backup staging unavailable")
        // This private folder contains only this pipeline's encrypted temporary files.
        // Worker execution is serialized, so leftovers can only be from interrupted runs.
        staging.listFiles()?.filter { it.isFile && it.name.startsWith("stage-") && it.name.endsWith(".encrypted") }
            ?.forEach { it.delete() }
        val temp = java.io.File.createTempFile("stage-", ".encrypted", staging)
        try {
            progress("Encrypting messages…", 15)
            BackupEncryption.writeEncrypted(temp, passphrase, ::checkRunning) { encryptedOutput ->
                val writer = com.google.gson.stream.JsonWriter(java.io.OutputStreamWriter(encryptedOutput, Charsets.UTF_8))
                writer.serializeNulls = true
                writer.beginObject()
                writer.name("version").value(BACKUP_VERSION)
                writer.name("timestamp").value(System.currentTimeMillis())
                writer.name("userUid").value(expectedUid)
                writer.name("deviceId").value(state.getInt("device_id").toString())
                writer.name("messages").beginArray()
                val conversations = linkedMapOf<Long, Conversation>()
                val gson = com.google.gson.GsonBuilder().serializeNulls().create()
                SQLCipherHelper(context).visitMessages(expectedUid, dbPassword, ::checkRunning) { row ->
                    gson.toJson(row, Map::class.java, writer)
                    val id = (row["conversationId"] as Number).toLong()
                    conversations[id] = Conversation(id, row["timestamp"] as String,
                        row["username"] as String, row["senderUid"] as? String ?: "")
                }
                writer.endArray()
                writer.name("conversations").beginArray()
                for (conversation in conversations.values) {
                    checkRunning(); gson.toJson(conversation, Conversation::class.java, writer)
                }
                writer.endArray()
                writer.name("signalProtocolState")
                gson.toJson(signalState, SignalProtocolState::class.java, writer)
                writer.name("attachments").beginArray().endArray()
                writer.endObject(); writer.flush()
            }
            checkRunning()
            progress("Saving backup…", 75)
            val uri = MediaStoreHelper.saveFile(context, temp, name, ::checkRunning)
            var canPrune = false
            try {
                progress("Checking saved backup…", 90)
                val verified = BackupRetention.verify(context, uri, temp, ::checkRunning)
                synchronized(NativeBackupGuard.lock) {
                    checkRunning()
                    try {
                        BackupRetention.record(context, expectedUid, uri, name, verified)
                        canPrune = true
                    } catch (e: Exception) {
                        Log.w(TAG, "Verified backup retained; retention record unavailable", e)
                    }
                    onSaved()
                }
            } catch (e: Exception) {
                MediaStoreHelper.deleteBackup(context, uri)
                throw e
            }
            // Pruning cannot turn an already verified backup into a failed operation.
            try { if (canPrune) BackupRetention.prune(context, expectedUid, ::checkRunning) }
            catch (e: Exception) { Log.w(TAG, "Backup saved; older-file cleanup deferred", e) }
        } finally { temp.delete() }
        return true
    }

    /**
     * Export Signal Protocol state from SignalManager
     */
    private fun exportSignalProtocolState(): SignalProtocolState {
        return try {
            val signalManager = SignalManager(context)
            val signalStateJson = signalManager.exportSignalState()

            SignalProtocolState(
                data = signalStateJson,
                exportedAt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
            )
        } catch (e: Exception) {
            throw IllegalStateException("Required security data could not be exported", e)
        }
    }

    /**
     * Get backup passphrase from EncryptedSharedPreferences
     * This is stored when user enables auto-backup in Flutter
     */
    private fun getBackupPassphrase(userUid: String): String? {
        return try {
            val encryptedPrefs = androidx.security.crypto.EncryptedSharedPreferences.create(
                context,
                ENCRYPTED_PREFS_NAME,
                androidx.security.crypto.MasterKey.Builder(context)
                    .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                    .build(),
                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            encryptedPrefs.getString("auto_backup_passphrase_$userUid", null)
        } catch (e: Exception) {
            // Log.e(TAG, "Error reading passphrase: ${e.message}", e)
            null
        }
    }

    /**
     * Get database password from EncryptedSharedPreferences
     */
    private fun getDatabasePassword(userUid: String): String? {
        return try {
            val encryptedPrefs = androidx.security.crypto.EncryptedSharedPreferences.create(
                context,
                ENCRYPTED_PREFS_NAME,
                androidx.security.crypto.MasterKey.Builder(context)
                    .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                    .build(),
                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            encryptedPrefs.getString("database_password_$userUid", null)
        } catch (e: Exception) {
            // Log.e(TAG, "Error reading database password: ${e.message}", e)
            null
        }
    }

}
