package com.example.zarq_messenger

import android.content.Context
import android.util.Base64
import android.util.Log
import java.io.File


class SignalStore(private val ctx: Context) {
    private val TAG = "SignalStore"

    private fun userDir(uid: String): File {
        val dir = File(ctx.filesDir, "signal_store/$uid")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun write(uid: String, name: String, bytes: ByteArray) {
        val f = File(userDir(uid), name)
        f.writeBytes(bytes)
        Log.d(TAG, "Wrote file: ${f.absolutePath} (${bytes.size} bytes)")
    }

    private fun read(uid: String, name: String): ByteArray? {
        val f = File(userDir(uid), name)
        return if (f.exists()) {
            val bytes = f.readBytes()
            Log.d(TAG, "Read file: ${f.absolutePath} (${bytes.size} bytes)")
            bytes
        } else {
            Log.d(TAG, "File not found: ${f.absolutePath}")
            null
        }
    }

    private fun delete(uid: String, name: String) {
        val f = File(userDir(uid), name)
        if (f.exists()) {
            f.delete()
            Log.d(TAG, "Deleted file: ${f.absolutePath}")
        }
    }

    // ----------------------
    // Public key helpers
    // ----------------------
    fun savePublicKey(uid: String, tag: String, publicBase64: String): Boolean {
        return try {
            val bytes = Base64.decode(publicBase64, Base64.NO_WRAP)
            write(uid, "pub_$tag", bytes)
            Log.d(TAG, "Saved public key: uid=$uid, tag=$tag")
            true
        } catch (e: Exception) {
            Log.e(TAG, "savePublicKey failed: ${e.message}")
            false
        }
    }

    fun loadPublicKeyBase64(uid: String, tag: String): String? {
        val b = read(uid, "pub_$tag") ?: return null
        return Base64.encodeToString(b, Base64.NO_WRAP)
    }

    fun removePublicKey(uid: String, tag: String) {
        delete(uid, "pub_$tag")
    }

    // ----------------------
    // PreKey / SignedPreKey helpers
    // ----------------------
    fun savePreKey(uid: String, keyId: Int, publicBase64: String): Boolean {
        val result = savePublicKey(uid, "prekey_$keyId", publicBase64)
        if (result) {
            Log.d(TAG, "Saved prekey: uid=$uid, keyId=$keyId")
        }
        return result
    }

    fun loadPreKeyBase64(uid: String, keyId: Int): String? =
        loadPublicKeyBase64(uid, "prekey_$keyId")

    fun removePreKey(uid: String, keyId: Int) =
        removePublicKey(uid, "prekey_$keyId")

    fun saveSignedPreKey(uid: String, keyId: Int, publicBase64: String): Boolean {
        val result = savePublicKey(uid, "signedpre_$keyId", publicBase64)
        if (result) {
            Log.d(TAG, "Saved signed prekey: uid=$uid, keyId=$keyId")
        }
        return result
    }

    fun loadSignedPreKeyBase64(uid: String, keyId: Int): String? =
        loadPublicKeyBase64(uid, "signedpre_$keyId")

    fun removeSignedPreKey(uid: String, keyId: Int) =
        removePublicKey(uid, "signedpre_$keyId")

    // ----------------------
    // Session storage (opaque blobs from libsignal)
    // ----------------------
    fun saveSessionBlob(uid: String, deviceId: Long, sessionBlobBase64: String): Boolean {
        return try {
            val bytes = Base64.decode(sessionBlobBase64, Base64.NO_WRAP)
            write(uid, "session_${deviceId}", bytes)
            true
        } catch (e: Exception) {
            Log.e(TAG, "saveSessionBlob failed: ${e.message}")
            false
        }
    }

    fun loadSessionBlobBase64(uid: String, deviceId: Long): String? {
        val b = read(uid, "session_${deviceId}") ?: return null
        return Base64.encodeToString(b, Base64.NO_WRAP)
    }

    fun removeSession(uid: String, deviceId: Long) {
        delete(uid, "session_${deviceId}")
    }

    fun listSessionDeviceIds(uid: String): List<Long> {
        return userDir(uid).listFiles()
            ?.mapNotNull { f ->
                val n = f.name
                when {
                    n.startsWith("session_") -> n.removePrefix("session_").toLongOrNull()
                    else -> null
                }
            } ?: emptyList()
    }

    // ----------------------
    // PHASE 1.1: Enhanced Forward Secrecy Methods
    // ----------------------

    /**
     * Delete message keys for forward secrecy
     * Message keys are derived keys that libsignal may cache for message decryption
     */
    fun deleteMessageKeys(uid: String, deviceId: Long) {
        try {
            val dir = userDir(uid)
            val patterns = listOf(
                "msgkey_${deviceId}_",
                "messagekey_${deviceId}_",
                "derivekey_${deviceId}_",
                "chainkey_${deviceId}_"
            )

            var deletedCount = 0
            dir.listFiles()?.forEach { file ->
                val fileName = file.name
                if (patterns.any { pattern -> fileName.startsWith(pattern) }) {
                    if (file.delete()) {
                        deletedCount++
                        Log.d(TAG, "Deleted message key file: $fileName")
                    }
                }
            }

            Log.d(TAG, "deleteMessageKeys: Deleted $deletedCount message key files for $uid:$deviceId")
        } catch (e: Exception) {
            Log.e(TAG, "deleteMessageKeys failed for $uid:$deviceId: ${e.message}", e)
        }
    }

    /**
     * Delete ratchet state for forward secrecy
     * Ratchet state includes chain keys, root keys, and ratchet counters
     */
    fun deleteRatchetState(uid: String, deviceId: Long) {
        try {
            val dir = userDir(uid)
            val patterns = listOf(
                "ratchet_${deviceId}_",
                "rootkey_${deviceId}_",
                "sendkey_${deviceId}_",
                "recvkey_${deviceId}_",
                "counter_${deviceId}_",
                "ratchetstate_${deviceId}_"
            )

            var deletedCount = 0
            dir.listFiles()?.forEach { file ->
                val fileName = file.name
                if (patterns.any { pattern -> fileName.startsWith(pattern) }) {
                    if (file.delete()) {
                        deletedCount++
                        Log.d(TAG, "Deleted ratchet state file: $fileName")
                    }
                }
            }

            Log.d(TAG, "deleteRatchetState: Deleted $deletedCount ratchet files for $uid:$deviceId")
        } catch (e: Exception) {
            Log.e(TAG, "deleteRatchetState failed for $uid:$deviceId: ${e.message}", e)
        }
    }

    /**
     * Delete cached cryptographic material
     * This includes any derived keys, cached secrets, or temporary crypto state
     */
    fun deleteCachedCryptoMaterial(uid: String, deviceId: Long) {
        try {
            val dir = userDir(uid)
            val patterns = listOf(
                "cache_${deviceId}_",
                "derived_${deviceId}_",
                "temp_${deviceId}_",
                "secret_${deviceId}_",
                "kdf_${deviceId}_",
                "ephemeral_${deviceId}_"
            )

            var deletedCount = 0
            dir.listFiles()?.forEach { file ->
                val fileName = file.name
                if (patterns.any { pattern -> fileName.startsWith(pattern) }) {
                    if (file.delete()) {
                        deletedCount++
                        Log.d(TAG, "Deleted cached crypto file: $fileName")
                    }
                }
            }

            Log.d(TAG, "deleteCachedCryptoMaterial: Deleted $deletedCount cache files for $uid:$deviceId")
        } catch (e: Exception) {
            Log.e(TAG, "deleteCachedCryptoMaterial failed for $uid:$deviceId: ${e.message}", e)
        }
    }

    /**
     * COMPREHENSIVE: Delete all session-related data for perfect forward secrecy
     * This is the main method that should be called to ensure complete session clearing
     */
    fun deleteAllSessionRelatedData(uid: String, deviceId: Long) {
        try {
            Log.d(TAG, "deleteAllSessionRelatedData: Starting comprehensive deletion for $uid:$deviceId")

            // 1. Delete core session data (existing functionality)
            removeSession(uid, deviceId)

            // 2. Delete message keys for forward secrecy
            deleteMessageKeys(uid, deviceId)

            // 3. Delete ratchet state
            deleteRatchetState(uid, deviceId)

            // 4. Delete cached cryptographic material
            deleteCachedCryptoMaterial(uid, deviceId)

            // 5. Additional cleanup - delete any remaining device-specific files
            deleteRemainingDeviceFiles(uid, deviceId)

            Log.d(TAG, "deleteAllSessionRelatedData: Completed comprehensive deletion for $uid:$deviceId")

        } catch (e: Exception) {
            Log.e(TAG, "deleteAllSessionRelatedData failed for $uid:$deviceId: ${e.message}", e)
            throw e
        }
    }

    /**
     * Delete any remaining device-specific files that might contain crypto material
     */
    private fun deleteRemainingDeviceFiles(uid: String, deviceId: Long) {
        try {
            val dir = userDir(uid)
            val devicePattern = "_${deviceId}_"
            val deviceSuffix = "_${deviceId}"

            var deletedCount = 0
            dir.listFiles()?.forEach { file ->
                val fileName = file.name
                // Delete any file that contains the device ID and isn't already handled
                if ((fileName.contains(devicePattern) || fileName.endsWith(deviceSuffix)) &&
                    !fileName.startsWith("pub_") && // Preserve public keys
                    !fileName.startsWith("prekey_") && // Preserve prekeys
                    !fileName.startsWith("signedpre_")) { // Preserve signed prekeys

                    if (file.delete()) {
                        deletedCount++
                        Log.d(TAG, "Deleted remaining device file: $fileName")
                    }
                }
            }

            if (deletedCount > 0) {
                Log.d(TAG, "deleteRemainingDeviceFiles: Deleted $deletedCount additional files for $uid:$deviceId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "deleteRemainingDeviceFiles failed for $uid:$deviceId: ${e.message}", e)
        }
    }

    /**
     * Verify that session deletion was successful
     * Returns true if no session-related data remains
     */
    fun verifySessionDeletion(uid: String, deviceId: Long): Boolean {
        try {
            val dir = userDir(uid) // This is actually current user's directory
            val devicePattern = "_${deviceId}_"
            val deviceSuffix = "_${deviceId}"
            val sessionFile = "session_${deviceId}"

            val remainingFiles = dir.listFiles()?.filter { file ->
                val fileName = file.name
                // Only check session-specific files, ignore general prekeys
                fileName == sessionFile ||
                        (fileName.contains(devicePattern) || fileName.endsWith(deviceSuffix)) &&
                        !fileName.startsWith("pub_prekey_") && // Ignore general prekeys
                        !fileName.startsWith("pub_signedpre_") // Ignore general signed prekeys
            }?.map { it.name } ?: emptyList()

            val isClean = remainingFiles.isEmpty()

            if (isClean) {
                Log.d(TAG, "verifySessionDeletion: PASSED - No session data remains for $uid:$deviceId")
            } else {
                Log.w(TAG, "verifySessionDeletion: FAILED - Remaining files: $remainingFiles")
            }

            return isClean

        } catch (e: Exception) {
            Log.e(TAG, "verifySessionDeletion failed for $uid:$deviceId: ${e.message}", e)
            return false
        }
    }

    // ----------------------
    // Utilities with better logging
    // ----------------------
    fun listPreKeyIds(uid: String): List<Int> {
        val dir = userDir(uid)
        val files = dir.listFiles()
        Log.d(TAG, "listPreKeyIds: checking directory ${dir.absolutePath}")
        Log.d(TAG, "listPreKeyIds: found ${files?.size ?: 0} files")

        files?.forEach { file ->
            Log.d(TAG, "listPreKeyIds: file = ${file.name}")
        }

        val result = files?.mapNotNull { f ->
            val n = f.name
            when {
                n.startsWith("pub_prekey_") -> {
                    val id = n.removePrefix("pub_prekey_").toIntOrNull()
                    Log.d(TAG, "listPreKeyIds: found prekey file $n -> id=$id")
                    id
                }
                else -> null
            }
        } ?: emptyList()

        Log.d(TAG, "listPreKeyIds: returning ${result.size} prekey IDs: $result")
        return result
    }

    fun listSignedPreKeyIds(uid: String): List<Int> {
        val dir = userDir(uid)
        val files = dir.listFiles()
        Log.d(TAG, "listSignedPreKeyIds: checking directory ${dir.absolutePath}")
        Log.d(TAG, "listSignedPreKeyIds: found ${files?.size ?: 0} files")

        files?.forEach { file ->
            Log.d(TAG, "listSignedPreKeyIds: file = ${file.name}")
        }

        val result = files?.mapNotNull { f ->
            val n = f.name
            when {
                n.startsWith("pub_signedpre_") -> {
                    val id = n.removePrefix("pub_signedpre_").toIntOrNull()
                    Log.d(TAG, "listSignedPreKeyIds: found signed prekey file $n -> id=$id")
                    id
                }
                else -> null
            }
        } ?: emptyList()

        Log.d(TAG, "listSignedPreKeyIds: returning ${result.size} signed prekey IDs: $result")
        return result
    }

    fun clearAll(uid: String) {
        val dir = userDir(uid)
        val deleted = dir.listFiles()?.size ?: 0
        dir.listFiles()?.forEach { it.delete() }
        Log.d(TAG, "clearAll: deleted $deleted files for uid=$uid")
    }
}