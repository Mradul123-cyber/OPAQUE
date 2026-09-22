package com.zarq.messenger

import android.content.Context
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.state.IdentityKeyStore
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.PreKeyStore
import org.whispersystems.libsignal.state.SessionRecord
import org.whispersystems.libsignal.state.SessionStore
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyStore
import org.whispersystems.libsignal.ecc.Curve
import org.whispersystems.libsignal.ecc.ECKeyPair
import org.whispersystems.libsignal.groups.state.SenderKeyRecord
import org.whispersystems.libsignal.groups.state.SenderKeyStore
import org.whispersystems.libsignal.groups.SenderKeyName
import org.whispersystems.libsignal.InvalidKeyIdException
import org.whispersystems.libsignal.state.SignalProtocolStore as LibSignalProtocolStore

/**
 * Unified implementation of all Signal Protocol storage interfaces:
 * - IdentityKeyStore: Manages identity keys and trust decisions
 * - PreKeyStore: Manages one-time prekeys
 * - SignedPreKeyStore: Manages signed prekeys
 * - SessionStore: Manages session state between users
 * - SenderKeyStore: Manages sender keys for group encryption
 */
class SignalProtocolStore(private val context: Context, userUid: String? = null) :
    IdentityKeyStore, PreKeyStore, SignedPreKeyStore, SessionStore, SenderKeyStore, LibSignalProtocolStore {

    companion object {
        private const val TAG = "SignalProtocolStore"

        // SharedPreferences keys
        private const val STORE_PREFS = "signal_protocol_store"
        private const val KEY_IDENTITY_PAIR = "identity_key_pair"
        private const val KEY_REGISTRATION_ID = "registration_id"
        private const val KEY_LOCAL_IDENTITY = "local_identity_key"

        // Prefixes for different data types
        private const val PREFIX_PREKEY = "prekey_"
        private const val PREFIX_SIGNED_PREKEY = "signed_prekey_"
        private const val PREFIX_SESSION = "session_"
        private const val PREFIX_SESSION_CREATED = "session_created_time_"
        private const val PREFIX_IDENTITY = "identity_"
        private const val PREFIX_KEY_CHANGE_TIME = "key_change_time_"
        private const val PREFIX_SENDER_KEY = "sender_key_"
    }

    private val prefs = if (userUid != null) {
        context.getSharedPreferences("${STORE_PREFS}_${userUid}", Context.MODE_PRIVATE)
    } else {
        // Fallback for backwards compatibility
        context.getSharedPreferences(STORE_PREFS, Context.MODE_PRIVATE)
    }

    private val storeLock = Any()

    fun getLastKeyChangeTime(address: SignalProtocolAddress): Long = synchronized(storeLock) {
        val key = PREFIX_KEY_CHANGE_TIME + address.name + "_" + address.deviceId
        prefs.getLong(key, 0)
    }

    private fun updateKeyChangeTime(address: SignalProtocolAddress) = synchronized(storeLock) {
        val key = PREFIX_KEY_CHANGE_TIME + address.name + "_" + address.deviceId
        prefs.edit().putLong(key, System.currentTimeMillis()).commit()
    }

    fun getSessionCreatedTime(address: SignalProtocolAddress): Long = synchronized(storeLock) {
        val key = PREFIX_SESSION_CREATED + address.name + "_" + address.deviceId
        val time = prefs.getLong(key, 0L)
        if (time == 0L && containsSession(address)) {
            val now = System.currentTimeMillis()
            prefs.edit().putLong(key, now).commit()
            return now
        }
        time
    }

    fun setSessionCreatedTime(address: SignalProtocolAddress, time: Long = System.currentTimeMillis()) = synchronized(storeLock) {
        val key = PREFIX_SESSION_CREATED + address.name + "_" + address.deviceId
        prefs.edit().putLong(key, time).commit()
    }

    // ===== IDENTITY KEY STORE IMPLEMENTATION =====

    override fun getIdentityKeyPair(): IdentityKeyPair? = synchronized(storeLock) {
        try {
            val jsonStr = prefs.getString(KEY_IDENTITY_PAIR, null) ?: return null
            val json = JSONObject(jsonStr)

            val publicKeyB64 = json.getString("public_key")
            val privateKeyB64 = json.getString("private_key")

            val publicKeyBytes = Base64.decode(publicKeyB64, Base64.NO_WRAP)
            val privateKeyBytes = Base64.decode(privateKeyB64, Base64.NO_WRAP)

            // Create ECKeyPair using Signal Protocol's Curve
            val publicKey = Curve.decodePoint(publicKeyBytes, 0)
            val privateKey = Curve.decodePrivatePoint(privateKeyBytes)
            val ecKeyPair = ECKeyPair(publicKey, privateKey)

            // Create IdentityKeyPair from ECKeyPair
            IdentityKeyPair(IdentityKey(publicKey), privateKey)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load identity key pair", e)
            null
        }
    }

    override fun getLocalRegistrationId(): Int = synchronized(storeLock) {
        prefs.getInt(KEY_REGISTRATION_ID, -1)
    }

    override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey): Boolean = synchronized(storeLock) {
        try {
            val key = PREFIX_IDENTITY + address.name  // Removed device_id here too
            val identityKeyB64 = Base64.encodeToString(identityKey.serialize(), Base64.NO_WRAP)

            // Check if this is a key change
            val existingKey = prefs.getString(key, null)
            if (existingKey != null && existingKey != identityKeyB64) {
                updateKeyChangeTime(address)
                Log.i(TAG, "Identity key changed for ${address.name}")
            }

            prefs.edit().putString(key, identityKeyB64).commit()
            Log.d(TAG, "Saved identity for ${address.name}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save identity for ${address.name}", e)
            false
        }
    }

    override fun isTrustedIdentity(address: SignalProtocolAddress, identityKey: IdentityKey, direction: IdentityKeyStore.Direction): Boolean = synchronized(storeLock) {
        try {
            // Track identity per USER, not per device (WhatsApp approach)
            val key = PREFIX_IDENTITY + address.name  // Removed device_id
            val storedKeyB64 = prefs.getString(key, null)

            if (storedKeyB64 == null) {
                // TOFU: Trust on first use
                Log.d(TAG, "First contact with ${address.name}, trusting identity key")
                return true
            }

            val storedKeyBytes = Base64.decode(storedKeyB64, Base64.NO_WRAP)
            val storedKey = IdentityKey(storedKeyBytes, 0)

            if (storedKey.equals(identityKey)) {
                // Same key, all good
                return true
            }

            // Key changed - apply WhatsApp-style smart trust rules
            Log.w(TAG, "Identity key changed for ${address.name} (app reinstall or new device)")
            return shouldAutoTrustNewKey(address, identityKey, direction)

        } catch (e: Exception) {
            Log.e(TAG, "Identity trust verification failed", e)
            return false
        }
    }

    private fun shouldAutoTrustNewKey(address: SignalProtocolAddress, newKey: IdentityKey, direction: IdentityKeyStore.Direction): Boolean {
        // 1. Auto-trust for outgoing messages (when YOU initiate contact or session)
        if (direction == IdentityKeyStore.Direction.SENDING) {
            Log.d(TAG, "Auto-trusting new identity for outgoing message to ${address.name}")
            return true
        }

        // 2. Auto-trust if NO session exists (e.g. initial message, new device, or after session reset)
        val sessionExists = containsSession(address)
        if (!sessionExists) {
            Log.d(TAG, "Auto-trusting new identity for incoming message from ${address.name}:${address.deviceId} - no active session exists")
            return true
        }

        // 3. Incoming PreKey message with a new identity key: the remote contact re-registered/reinstalled.
        // Purge the obsolete session so the new session can establish with the new identity key (WhatsApp/Signal model).
        Log.w(TAG, "Identity key changed for incoming session from ${address.name}:${address.deviceId}. Purging stale session and trusting new identity.")
        deleteSession(address)
        return true
    }

    /**
     * Check if this is a testing scenario where we should be more permissive
     * This allows single-device testing of encryption/decryption
     */

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? = synchronized(storeLock) {
        try {
            val key = PREFIX_IDENTITY + address.name
            val identityKeyB64 = prefs.getString(key, null) ?: return null
            val identityKeyBytes = Base64.decode(identityKeyB64, Base64.NO_WRAP)
            IdentityKey(identityKeyBytes, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get identity for ${address.name}", e)
            null
        }
    }

    // ===== PREKEY STORE IMPLEMENTATION =====

    override fun loadPreKey(preKeyId: Int): PreKeyRecord = synchronized(storeLock) {
        val key = PREFIX_PREKEY + preKeyId
        val recordB64 = prefs.getString(key, null)
            ?: throw InvalidKeyIdException("No prekey found with ID: $preKeyId")
        try {
            val recordBytes = Base64.decode(recordB64, Base64.NO_WRAP)
            PreKeyRecord(recordBytes)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to decode prekey $preKeyId", e)
            throw InvalidKeyIdException("Corrupted prekey record for ID: $preKeyId: ${e.message}")
        }
    }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) {
        synchronized(storeLock) {
            try {
                val key = PREFIX_PREKEY + preKeyId
                val recordB64 = Base64.encodeToString(record.serialize(), Base64.NO_WRAP)
                prefs.edit().putString(key, recordB64).commit()  // FIX: Use commit() to ensure disk write completes before upload
                Log.d(TAG, "Stored prekey $preKeyId")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to store prekey $preKeyId", e)
            }
        }
    }

    override fun containsPreKey(preKeyId: Int): Boolean = synchronized(storeLock) {
        val key = PREFIX_PREKEY + preKeyId
        prefs.contains(key)
    }

    override fun removePreKey(preKeyId: Int) {
        synchronized(storeLock) {
            try {
                val key = PREFIX_PREKEY + preKeyId
                val wasPresent = prefs.contains(key)
                prefs.edit().remove(key).commit()
                Log.d(TAG, "Removed prekey $preKeyId (was present: $wasPresent)")

                // Debug: Count remaining prekeys
                val remainingCount = prefs.all.keys.count { it.startsWith(PREFIX_PREKEY) }
                Log.d(TAG, "Remaining prekeys after removal: $remainingCount")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to remove prekey $preKeyId", e)
            }
        }
    }

    // ===== SIGNED PREKEY STORE IMPLEMENTATION =====

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord = synchronized(storeLock) {
        val key = PREFIX_SIGNED_PREKEY + signedPreKeyId
        val recordB64 = prefs.getString(key, null)
            ?: throw InvalidKeyIdException("No signed prekey found with ID: $signedPreKeyId")
        try {
            val recordBytes = Base64.decode(recordB64, Base64.NO_WRAP)
            SignedPreKeyRecord(recordBytes)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to decode signed prekey $signedPreKeyId", e)
            throw InvalidKeyIdException("Corrupted signed prekey record for ID: $signedPreKeyId: ${e.message}")
        }
    }

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> = synchronized(storeLock) {
        try {
            val records = mutableListOf<SignedPreKeyRecord>()
            for ((key, value) in prefs.all) {
                if (key.startsWith(PREFIX_SIGNED_PREKEY) && value is String) {
                    try {
                        val recordBytes = Base64.decode(value, Base64.NO_WRAP)
                        records.add(SignedPreKeyRecord(recordBytes))
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to load signed prekey from $key", e)
                    }
                }
            }
            Log.d(TAG, "Loaded ${records.size} signed prekeys")
            records
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load signed prekeys", e)
            emptyList()
        }
    }

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) {
        synchronized(storeLock) {
            try {
                val key = PREFIX_SIGNED_PREKEY + signedPreKeyId
                val recordB64 = Base64.encodeToString(record.serialize(), Base64.NO_WRAP)
                prefs.edit().putString(key, recordB64).commit()  // FIX: Use commit() to ensure disk write completes
                Log.d(TAG, "Stored signed prekey $signedPreKeyId")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to store signed prekey $signedPreKeyId", e)
            }
        }
    }

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean = synchronized(storeLock) {
        val key = PREFIX_SIGNED_PREKEY + signedPreKeyId
        prefs.contains(key)
    }

    override fun removeSignedPreKey(signedPreKeyId: Int) {
        synchronized(storeLock) {
            try {
                val key = PREFIX_SIGNED_PREKEY + signedPreKeyId
                prefs.edit().remove(key).commit()
                Log.d(TAG, "Removed signed prekey $signedPreKeyId")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to remove signed prekey $signedPreKeyId", e)
            }
        }
    }

    /**
     * Prune retired signed prekeys.
     * Keeps the current active signed prekey and the immediately preceding signed prekey
     * (as a grace period for in-flight messages), removing all older signed prekeys
     * to preserve forward secrecy and prevent storage bloat.
     */
    fun pruneOldSignedPreKeys(currentSignedPreKeyId: Int, keepPreviousCount: Int = 1) = synchronized(storeLock) {
        try {
            val minKeyToKeep = currentSignedPreKeyId - keepPreviousCount
            val editor = prefs.edit()
            var prunedCount = 0

            for (key in prefs.all.keys) {
                if (key.startsWith(PREFIX_SIGNED_PREKEY)) {
                    val idStr = key.removePrefix(PREFIX_SIGNED_PREKEY)
                    val id = idStr.toIntOrNull()
                    if (id != null && id < minKeyToKeep) {
                        editor.remove(key)
                        prunedCount++
                    }
                }
            }

            if (prunedCount > 0) {
                editor.commit()
                Log.i(TAG, "Pruned $prunedCount retired signed prekey(s) older than ID $minKeyToKeep")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to prune old signed prekeys", e)
        }
    }

    // ===== SESSION STORE IMPLEMENTATION =====

    override fun loadSession(address: SignalProtocolAddress): SessionRecord = synchronized(storeLock) {
        try {
            val key = PREFIX_SESSION + address.name + "_" + address.deviceId
            val recordB64 = prefs.getString(key, null)

            if (recordB64 != null) {
                val recordBytes = Base64.decode(recordB64, Base64.NO_WRAP)
                SessionRecord(recordBytes)
            } else {
                // Return fresh session record if none exists
                SessionRecord()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load session for ${address.name}:${address.deviceId}", e)
            SessionRecord()
        }
    }

    override fun getSubDeviceSessions(name: String): List<Int> = synchronized(storeLock) {
        try {
            val prefix = PREFIX_SESSION + name + "_"
            val deviceIds = mutableListOf<Int>()

            for (key in prefs.all.keys) {
                if (key.startsWith(prefix)) {
                    try {
                        val deviceId = key.substring(prefix.length).toInt()
                        deviceIds.add(deviceId)
                    } catch (e: NumberFormatException) {
                        Log.w(TAG, "Invalid device ID in session key: $key")
                    }
                }
            }

            Log.d(TAG, "Found ${deviceIds.size} sub-device sessions for $name")
            deviceIds
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get sub-device sessions for $name", e)
            emptyList()
        }
    }

    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord) {
        synchronized(storeLock) {
            try {
                val key = PREFIX_SESSION + address.name + "_" + address.deviceId
                val createdKey = PREFIX_SESSION_CREATED + address.name + "_" + address.deviceId

                // Debug: Check session before storing
                val sizeBefore = record.serialize()?.size ?: 0
                Log.d(TAG, "STORE SESSION: $address, size before: $sizeBefore")

                val recordB64 = Base64.encodeToString(record.serialize(), Base64.NO_WRAP)
                val editor = prefs.edit().putString(key, recordB64)
                if (!prefs.contains(createdKey)) {
                    editor.putLong(createdKey, System.currentTimeMillis())
                }
                editor.commit()  // FIX: Use commit() to ensure session is saved before use

                // Debug: Verify stored session can be loaded back
                val loadedRecord = loadSession(address)
                val sizeAfter = loadedRecord.serialize()?.size ?: 0
                Log.d(TAG, "STORE SESSION: $address, size after reload: $sizeAfter, corruption: ${sizeBefore != sizeAfter}")

                Log.d(TAG, "Stored session for ${address.name}:${address.deviceId}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to store session for ${address.name}:${address.deviceId}", e)
            }
        }
    }

    override fun containsSession(address: SignalProtocolAddress): Boolean = synchronized(storeLock) {
        val key = PREFIX_SESSION + address.name + "_" + address.deviceId
        prefs.contains(key)
    }

    override fun deleteSession(address: SignalProtocolAddress) {
        synchronized(storeLock) {
            try {
                val key = PREFIX_SESSION + address.name + "_" + address.deviceId
                val createdKey = PREFIX_SESSION_CREATED + address.name + "_" + address.deviceId
                prefs.edit().remove(key).remove(createdKey).commit()
                Log.d(TAG, "Deleted session for ${address.name}:${address.deviceId}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete session for ${address.name}:${address.deviceId}", e)
            }
        }
    }

    override fun deleteAllSessions(name: String) {
        synchronized(storeLock) {
            try {
                val prefix = PREFIX_SESSION + name + "_"
                val createdPrefix = PREFIX_SESSION_CREATED + name + "_"
                val editor = prefs.edit()

                for (key in prefs.all.keys) {
                    if (key.startsWith(prefix) || key.startsWith(createdPrefix)) {
                        editor.remove(key)
                    }
                }

                editor.commit()
                Log.d(TAG, "Deleted all sessions for $name")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete all sessions for $name", e)
            }
        }
    }

    // ===== UTILITY METHODS =====

    /**
     * Initialize the store with identity key pair and registration ID
     */
    fun initializeStore(identityKeyPair: IdentityKeyPair, registrationId: Int) = synchronized(storeLock) {
        try {
            val identityData = JSONObject().apply {
                put("public_key", Base64.encodeToString(identityKeyPair.publicKey.serialize(), Base64.NO_WRAP))
                put("private_key", Base64.encodeToString(identityKeyPair.privateKey.serialize(), Base64.NO_WRAP))
            }

            prefs.edit()
                .putString(KEY_IDENTITY_PAIR, identityData.toString())
                .putInt(KEY_REGISTRATION_ID, registrationId)
                .commit()

            Log.d(TAG, "Store initialized with registration ID: $registrationId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize store", e)
        }
    }


    /**
     * Clear all stored data
     */
    fun clearAll() = synchronized(storeLock) {
        try {
            prefs.edit().clear().commit()
            Log.d(TAG, "All store data cleared")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear store", e)
        }
    }

    /**
     * Export all Signal Protocol state for backup
     * Returns JSON string containing all keys, sessions, and prekeys
     */
    fun exportSignalState(): String = synchronized(storeLock) {
        try {
            val allData = JSONObject()
            var skippedPrekeys = 0

            // Export all SharedPreferences entries EXCEPT one-time prekeys
            // One-time prekeys should NEVER be backed up (violates forward secrecy)
            for ((key, value) in prefs.all) {
                // Skip one-time prekeys (they will be regenerated fresh on restore)
                if (key.startsWith(PREFIX_PREKEY)) {
                    skippedPrekeys++
                    continue
                }

                when (value) {
                    is String -> allData.put(key, value)
                    is Int -> allData.put(key, value)
                    is Long -> allData.put(key, value)
                    is Boolean -> allData.put(key, value)
                }
            }

            val result = allData.toString()
            Log.d(TAG, "Exported Signal state: ${prefs.all.size - skippedPrekeys} entries (skipped $skippedPrekeys one-time prekeys for forward secrecy)")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to export Signal state", e)
            throw IllegalStateException("Signal state export failed", e)
        }
    }

    /**
     * Import Signal Protocol state from backup
     * Accepts JSON string containing all keys, sessions, and prekeys
     */
    fun importSignalState(jsonString: String): Boolean = synchronized(storeLock) {
        try {
            val data = JSONObject(jsonString)
            val editor = prefs.edit()

            // Clear existing data first
            editor.clear()

            // Import all entries
            val keys = data.keys()
            var count = 0
            while (keys.hasNext()) {
                val key = keys.next()
                val value = data.get(key)

                when (value) {
                    is String -> editor.putString(key, value)
                    is Int -> editor.putInt(key, value)
                    is Long -> editor.putLong(key, value)
                    is Boolean -> editor.putBoolean(key, value)
                }
                count++
            }

            check(editor.commit()) { "Could not persist restored Signal state" }
            Log.d(TAG, "Imported Signal state: $count entries (one-time prekeys will be regenerated fresh)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to import Signal state", e)
            false
        }
    }

    // ===== SENDER KEY STORE IMPLEMENTATION (for Group Encryption) =====

    /**
     * Store a sender key for a specific sender in a group
     * Key format: sender_key_{groupId}_{senderName}_{deviceId}
     */
    override fun storeSenderKey(senderKeyName: SenderKeyName, record: SenderKeyRecord) {
        synchronized(storeLock) {
            try {
                val key = PREFIX_SENDER_KEY + senderKeyName.groupId + "_" + senderKeyName.sender.name + "_" + senderKeyName.sender.deviceId
                val recordB64 = Base64.encodeToString(record.serialize(), Base64.NO_WRAP)
                prefs.edit().putString(key, recordB64).commit()  // FIX: Use commit() for group encryption keys
                Log.d(TAG, "Stored sender key for ${senderKeyName.sender.name}:${senderKeyName.sender.deviceId} in group ${senderKeyName.groupId}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to store sender key for ${senderKeyName.sender.name}", e)
            }
        }
    }

    /**
     * Load a sender key for a specific sender in a group
     */
    override fun loadSenderKey(senderKeyName: SenderKeyName): SenderKeyRecord = synchronized(storeLock) {
        try {
            val key = PREFIX_SENDER_KEY + senderKeyName.groupId + "_" + senderKeyName.sender.name + "_" + senderKeyName.sender.deviceId
            val recordB64 = prefs.getString(key, null)

            if (recordB64 != null) {
                val recordBytes = Base64.decode(recordB64, Base64.NO_WRAP)
                SenderKeyRecord(recordBytes)
            } else {
                // Return fresh sender key record if none exists
                Log.d(TAG, "No sender key found for ${senderKeyName.sender.name}:${senderKeyName.sender.deviceId} in group ${senderKeyName.groupId}, creating new record")
                SenderKeyRecord()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load sender key for ${senderKeyName.sender.name}", e)
            SenderKeyRecord()
        }
    }

    /**
     * Delete all sender keys for a specific group (used when leaving a group)
     */
    fun deleteSenderKeysForGroup(groupId: String) = synchronized(storeLock) {
        try {
            val prefix = PREFIX_SENDER_KEY + groupId + "_"
            val editor = prefs.edit()
            var count = 0

            for (key in prefs.all.keys) {
                if (key.startsWith(prefix)) {
                    editor.remove(key)
                    count++
                }
            }

            editor.commit()
            Log.d(TAG, "Deleted $count sender keys for group $groupId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete sender keys for group $groupId", e)
        }
    }

    /**
     * Get all sender keys for debugging purposes
     */
    fun getSenderKeyDebugInfo(): Map<String, String> = synchronized(storeLock) {
        try {
            val result = mutableMapOf<String, String>()
            for ((key, value) in prefs.all) {
                if (key.startsWith(PREFIX_SENDER_KEY) && value is String) {
                    val parts = key.removePrefix(PREFIX_SENDER_KEY).split("_")
                    if (parts.size >= 3) {
                        val groupId = parts[0]
                        val senderUid = parts[1]
                        val deviceId = parts.getOrNull(2) ?: "unknown"
                        result["Group $groupId - Sender $senderUid:$deviceId"] = "Stored"
                    }
                }
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get sender key debug info", e)
            emptyMap()
        }
    }
}