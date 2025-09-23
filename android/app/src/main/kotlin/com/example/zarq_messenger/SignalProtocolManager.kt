package com.example.zarq_messenger

import android.content.Context
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.SessionBuilder
import org.whispersystems.libsignal.SessionCipher
import org.whispersystems.libsignal.protocol.PreKeySignalMessage
import org.whispersystems.libsignal.protocol.SignalMessage
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.state.SessionRecord
import org.whispersystems.libsignal.state.PreKeyStore
import org.whispersystems.libsignal.state.SignedPreKeyStore
import org.whispersystems.libsignal.state.SessionStore
import org.whispersystems.libsignal.state.IdentityKeyStore
import org.whispersystems.libsignal.state.SignalProtocolStore
import org.whispersystems.libsignal.state.PreKeyBundle
import org.whispersystems.libsignal.state.IdentityKeyStore.Direction
import org.whispersystems.libsignal.util.KeyHelper
import org.json.JSONObject
import java.lang.Exception

class SignalProtocolManager(
    private val context: Context,
    private val store: SignalStore,
    private val crypto: SignalCrypto
) {
    private val TAG = "SignalProtocolManager"
    private val deviceId: Int = 1

    fun normalizeSessionKey(user1: String, user2: String, deviceId: Int): String {
        val users = listOf(user1, user2).sorted()
        return "${users[0]}_${users[1]}_$deviceId"
    }
    // -------------------------
    // Identity & Key generation
    // -------------------------
    suspend fun generateIdentity(uid: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val identityKeyPair = KeyHelper.generateIdentityKeyPair()
            val registrationId = KeyHelper.generateRegistrationId(false)

            // persist private identity bytes (serialize)
            val privBytes = identityKeyPair.serialize()
            crypto.saveIdentityPrivateKey(context, uid, privBytes)

            // persist public identity bytes to SignalStore (base64)
            val pubBytes = identityKeyPair.publicKey.serialize()
            val pubB64 = Base64.encodeToString(pubBytes, Base64.NO_WRAP)
            store.savePublicKey(uid, "identity", pubB64)

            // store registrationId as a file
            store.savePublicKey(uid, "regid", Base64.encodeToString(intToByteArray(registrationId), Base64.NO_WRAP))

            Log.d(TAG, "Identity generated for $uid (regId=$registrationId)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "generateIdentity error: ${e.message}", e)
            false
        }
    }

    suspend fun generateSignedPreKey(uid: String, signedPreKeyId: Int): Boolean = withContext(Dispatchers.IO) {
        try {
            // load identity private bytes
            val idPriv = crypto.loadIdentityPrivateKey(context, uid) ?: return@withContext false
            val identityKeyPair = IdentityKeyPair(idPriv)

            // generate signed prekey using libsignal KeyHelper
            val signedPreKeyPair = KeyHelper.generateSignedPreKey(identityKeyPair, signedPreKeyId)
            val signedPreKeyRecord = SignedPreKeyRecord(signedPreKeyId, System.currentTimeMillis(), signedPreKeyPair.keyPair, signedPreKeyPair.signature)

            Log.d(TAG, "SignedPreKey created: id=${signedPreKeyRecord.id}, timestamp=${signedPreKeyRecord.timestamp}")

            val spkSerialized: ByteArray = signedPreKeyRecord.serialize()
            val spkB64 = Base64.encodeToString(spkSerialized, Base64.NO_WRAP)

            Log.d(TAG, "SignedPreKey serialized: ${spkSerialized.size} bytes")
            Log.d(TAG, "SignedPreKey base64 length: ${spkB64.length}")

            store.saveSignedPreKey(uid, signedPreKeyId, spkB64)
            Log.d(TAG, "SignedPreKey generated for $uid id=$signedPreKeyId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "generateSignedPreKey error: ${e.message}", e)
            false
        }
    }

    suspend fun generatePreKeys(uid: String, startId: Int = 1, count: Int = 50): Boolean = withContext(Dispatchers.IO) {
        try {
            val preKeyRecords = KeyHelper.generatePreKeys(startId, count)
            for (rec in preKeyRecords) {
                val serialized = rec.serialize()
                val id = rec.id
                store.savePreKey(uid, id, Base64.encodeToString(serialized, Base64.NO_WRAP))
            }
            Log.d(TAG, "Generated $count prekeys for $uid starting at $startId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "generatePreKeys error: ${e.message}", e)
            false
        }
    }

    /**
     * Build an exportable PreKeyBundle JSON for server upload.
     * FIXED: Properly handle the bundle creation and ensure all required fields are present
     */
    suspend fun exportPreKeyBundle(uid: String): String? = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "exportPreKeyBundle: Starting export for uid=$uid")

            // 1. Get identity key
            val identityB64 = store.loadPublicKeyBase64(uid, "identity")
            if (identityB64 == null) {
                Log.e(TAG, "exportPreKeyBundle: No identity key found for uid=$uid")
                return@withContext null
            }
            Log.d(TAG, "exportPreKeyBundle: Found identity key")

            // 2. Get registration ID
            val regIdB64 = store.loadPublicKeyBase64(uid, "regid")
            val registrationId = if (regIdB64 != null) {
                val regBytes = Base64.decode(regIdB64, Base64.NO_WRAP)
                byteArrayToInt(regBytes)
            } else {
                Log.w(TAG, "exportPreKeyBundle: No registration ID found, using default")
                0
            }
            Log.d(TAG, "exportPreKeyBundle: Registration ID = $registrationId")

            // 3. Get signed prekey (find the most recently created one)
            val signedIds = store.listSignedPreKeyIds(uid)
            if (signedIds.isEmpty()) {
                Log.e(TAG, "exportPreKeyBundle: No signed prekeys found")
                return@withContext null
            }
            val spkId = signedIds.maxOrNull() ?: signedIds.first()
            Log.d(TAG, "exportPreKeyBundle: Using signed prekey ID=$spkId from available IDs: $signedIds")

            // Load the signed prekey record to extract public key and signature
            val spkB64 = store.loadSignedPreKeyBase64(uid, spkId)
            if (spkB64 == null) {
                Log.e(TAG, "exportPreKeyBundle: Signed prekey $spkId not found")
                return@withContext null
            }

            val spkBytes = Base64.decode(spkB64, Base64.NO_WRAP)
            val spkRecord = SignedPreKeyRecord(spkBytes)
            val spkPublicB64 = Base64.encodeToString(spkRecord.keyPair.publicKey.serialize(), Base64.NO_WRAP)
            val spkSignatureB64 = Base64.encodeToString(spkRecord.signature, Base64.NO_WRAP)
            Log.d(TAG, "exportPreKeyBundle: Extracted signed prekey public key and signature")

            // 4. Get one-time prekey (pick the lowest ID)
            val preIds = store.listPreKeyIds(uid).sorted()
            if (preIds.isEmpty()) {
                Log.e(TAG, "exportPreKeyBundle: No one-time prekeys found")
                return@withContext null
            }
            val usePreId = preIds.first()
            Log.d(TAG, "exportPreKeyBundle: Using one-time prekey ID=$usePreId from ${preIds.size} available")

            // Load the prekey record to extract public key
            val preB64 = store.loadPreKeyBase64(uid, usePreId)
            if (preB64 == null) {
                Log.e(TAG, "exportPreKeyBundle: One-time prekey $usePreId not found")
                return@withContext null
            }

            val preBytes = Base64.decode(preB64, Base64.NO_WRAP)
            val preRecord = PreKeyRecord(preBytes)
            val prePublicB64 = Base64.encodeToString(preRecord.keyPair.publicKey.serialize(), Base64.NO_WRAP)
            Log.d(TAG, "exportPreKeyBundle: Extracted one-time prekey public key")

            // 5. Build the JSON bundle
            val json = JSONObject().apply {
                put("identity", identityB64)
                put("registration_id", registrationId)
                put("signedPreKeyId", spkId)
                put("signedPreKey", spkPublicB64)
                put("signedPreKeySignature", spkSignatureB64)
                put("oneTimePreKeyId", usePreId)
                put("oneTimePreKey", prePublicB64)
                put("deviceId", deviceId)
            }

            val result = json.toString()
            Log.d(TAG, "exportPreKeyBundle: Successfully created bundle JSON (${result.length} chars)")
            return@withContext result

        } catch (e: Exception) {
            Log.e(TAG, "exportPreKeyBundle error: ${e.message}", e)
            null
        }
    }

    // -------------------------
    // Session init (X3DH) + encrypt/decrypt
    // -------------------------

    /**
     * Initialize a session with a remote PreKeyBundle JSON.
     * FIXED: Use correct field names that match server response and handle proper key deserialization
     */
    suspend fun initSessionWithBundle(myUid: String, recipientUid: String, bundleJson: String): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "initSessionWithBundle: parsing bundle JSON")
            val obj = JSONObject(bundleJson)

            // Use field names that match server response
            val remoteIdentityB64 = obj.getString("identity_key_b64")
            val remoteRegId = obj.getInt("registration_id")
            val remoteDeviceId = obj.getInt("device_id")

            // Handle signed prekey - it's an object in server response
            val signedPreKeyObj = obj.getJSONObject("signed_prekey")
            val remoteSpkId = signedPreKeyObj.getInt("key_id")
            val remoteSpkB64 = signedPreKeyObj.getString("public_key_b64")
            val remoteSpkSigB64 = signedPreKeyObj.getString("signature_b64")

            // Handle one-time prekey - direct fields in server response
            val remoteOnePreB64 = obj.optString("one_time_prekey_b64")
            if (remoteOnePreB64.isEmpty()) {
                Log.w(TAG, "initSessionWithBundle: No one-time prekey available")
                return@withContext false
            }

            Log.d(TAG, "initSessionWithBundle: Parsed bundle - identity=${remoteIdentityB64.length} chars, regId=$remoteRegId, deviceId=$remoteDeviceId, spkId=$remoteSpkId")

            // Decode bytes
            val remoteIdentity = Base64.decode(remoteIdentityB64, Base64.NO_WRAP)
            val remoteSpkBytes = Base64.decode(remoteSpkB64, Base64.NO_WRAP)
            val remoteSpkSig = Base64.decode(remoteSpkSigB64, Base64.NO_WRAP)
            val remoteOnePreBytes = Base64.decode(remoteOnePreB64, Base64.NO_WRAP)

            // DEBUG LOGS BEFORE DESERIALIZING
            Log.d(TAG, "Attempting to deserialize signed prekey:")
            Log.d(TAG, "Signed prekey base64 length: ${remoteSpkB64.length}")
            Log.d(TAG, "Signed prekey decoded bytes length: ${remoteSpkBytes.size}")
            Log.d(TAG, "Signed prekey first 10 bytes: ${remoteSpkBytes.take(10).joinToString { "%02x".format(it) }}")

            // Create libsignal keys from the raw bytes
            val remoteIdentityKey = IdentityKey(remoteIdentity, 0)

            // Handle signed prekey deserialization with proper error handling
            val remoteSpkRecord = try {
                SignedPreKeyRecord(remoteSpkBytes)
            } catch (e: Exception) {
                Log.e(TAG, "SignedPreKeyRecord deserialization failed with ${remoteSpkBytes.size} bytes")
                Log.e(TAG, "Failed bytes (hex): ${remoteSpkBytes.joinToString { "%02x".format(it) }}")
                throw e
            }
            Log.d(TAG, "SignedPreKeyRecord deserialized successfully")

            val remoteSpkPublic = remoteSpkRecord.keyPair.publicKey

            // DEBUG LOGS FOR ONE-TIME PREKEY
            Log.d(TAG, "Attempting to deserialize one-time prekey:")
            Log.d(TAG, "One-time prekey base64 length: ${remoteOnePreB64.length}")
            Log.d(TAG, "One-time prekey decoded bytes length: ${remoteOnePreBytes.size}")
            Log.d(TAG, "One-time prekey first 10 bytes: ${remoteOnePreBytes.take(10).joinToString { "%02x".format(it) }}")

            val remoteOnePreRecord = try {
                PreKeyRecord(remoteOnePreBytes)
            } catch (e: Exception) {
                Log.e(TAG, "PreKeyRecord deserialization failed with ${remoteOnePreBytes.size} bytes")
                Log.e(TAG, "Failed bytes (hex): ${remoteOnePreBytes.joinToString { "%02x".format(it) }}")
                throw e
            }
            Log.d(TAG, "PreKeyRecord deserialized successfully")

            val remoteOnePrePublic = remoteOnePreRecord.keyPair.publicKey

            // Build libsignal PreKeyBundle
            val libStore = LibsignalStore(context, store, myUid)

            val preKeyBundle = PreKeyBundle(
                remoteRegId,
                remoteDeviceId,
                1, // one-time prekey id
                remoteOnePrePublic,
                remoteSpkId,
                remoteSpkPublic,
                remoteSpkSig,
                remoteIdentityKey
            )

            // Create SessionBuilder & process bundle
            val address = SignalProtocolAddress(recipientUid, remoteDeviceId)
            val sessionBuilder = SessionBuilder(libStore, address)
            sessionBuilder.process(preKeyBundle)

            val sessionExists = libStore.containsSession(address)
            Log.d(TAG, "initSessionWithBundle: Session created and stored = $sessionExists")

// Also check what gets saved to SignalStore
            val sessionIds = store.listSessionDeviceIds(recipientUid)
            Log.d(TAG, "initSessionWithBundle: Session device IDs for $recipientUid: $sessionIds")

            Log.d(TAG, "X3DH session initialized: $myUid -> $recipientUid (device $remoteDeviceId)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "initSessionWithBundle error: ${e.message}", e)
            false
        }
    }

    /**
     * Encrypt plaintext for a recipient/device. Returns Base64 of outgoing serialized bytes.
     */
    suspend fun encrypt(myUid: String, recipientUid: String, recipientDeviceId: Int = 1, plaintext: ByteArray): String? = withContext(Dispatchers.IO) {
        try {
            val libStore = LibsignalStore(context, store, myUid)
            val address = SignalProtocolAddress(recipientUid, recipientDeviceId)
            val cipher = SessionCipher(libStore, address)
            val ciphertextMessage = cipher.encrypt(plaintext)
            val wire = ciphertextMessage.serialize()
            return@withContext Base64.encodeToString(wire, Base64.NO_WRAP)
        } catch (e: Exception) {
            Log.e(TAG, "encrypt error: ${e.message}", e)
            null
        }
    }

    /**
     * Decrypt a Base64 wire-format message for myUid from senderUid/device.
     */
    suspend fun decrypt(myUid: String, senderUid: String, senderDeviceId: Int = 1, wireBase64: String): ByteArray? = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "decrypt: Starting $myUid <- $senderUid:$senderDeviceId")

            val libStore = LibsignalStore(context, store, myUid)
            val address = SignalProtocolAddress(senderUid, senderDeviceId)

            // Check if session exists
            val sessionExists = libStore.containsSession(address)
            Log.d(TAG, "decrypt: Session exists = $sessionExists")

            if (!sessionExists) {
                Log.e(TAG, "decrypt: No session found for $senderUid:$senderDeviceId")
                return@withContext null
            }

            val cipher = SessionCipher(libStore, address)
            val wire = Base64.decode(wireBase64, Base64.NO_WRAP)

            Log.d(TAG, "decrypt: Wire data length = ${wire.size}")

            // Decide message type: PreKeySignalMessage vs SignalMessage
            return@withContext try {
                Log.d(TAG, "decrypt: Trying PreKeySignalMessage")
                val preKeyMsg = PreKeySignalMessage(wire)
                val result = cipher.decrypt(preKeyMsg)
                Log.d(TAG, "decrypt: PreKeySignalMessage SUCCESS")
                result
            } catch (e: Exception) {
                Log.d(TAG, "decrypt: PreKeySignalMessage failed: ${e.message}")
                Log.d(TAG, "decrypt: Trying SignalMessage")
                val sigMsg = SignalMessage(wire)
                val result = cipher.decrypt(sigMsg)
                Log.d(TAG, "decrypt: SignalMessage SUCCESS")
                result
            }
        } catch (e: Exception) {
            Log.e(TAG, "decrypt error: ${e.message}", e)
            null
        }
    }

    /**
     * Capture current session context for preservation with message
     */
    suspend fun captureSessionContext(myUid: String, recipientUid: String, recipientDeviceId: Int = 1): String? = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "=== CAPTURE SESSION CONTEXT DEBUG ===")
            Log.d(TAG, "captureSessionContext: $myUid -> $recipientUid")

            val libStore = LibsignalStore(context, store, myUid)
            val address = SignalProtocolAddress(recipientUid, recipientDeviceId)

            // Debug session existence
            val sessionExists = libStore.containsSession(address)
            Log.d(TAG, "Session exists in libStore: $sessionExists")

            if (!sessionExists) {
                Log.e(TAG, "captureSessionContext: No session exists for $recipientUid")
                return@withContext null
            }

            // Load and verify session record
            val sessionRecord = libStore.loadSession(address)
            val sessionBytes = sessionRecord.serialize()
            Log.d(TAG, "Session record loaded, size: ${sessionBytes.size} bytes")

            if (sessionBytes.isEmpty()) {
                Log.e(TAG, "Session record is empty!")
                return@withContext null
            }

            val sessionContextB64 = Base64.encodeToString(sessionBytes, Base64.NO_WRAP)
            Log.d(TAG, "Session context encoded to base64: ${sessionContextB64.length} characters")
            Log.d(TAG, "=== END CAPTURE DEBUG ===")

            return@withContext sessionContextB64

        } catch (e: Exception) {
            Log.e(TAG, "captureSessionContext error: ${e.message}", e)
            return@withContext null
        }
    }

    /**
     * Apply captured session context for decryption
     */
    suspend fun applySessionContext(myUid: String, senderUid: String, senderDeviceId: Int = 1, sessionContextB64: String): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "applySessionContext: Applying session context for $myUid <- $senderUid")

            val sessionBytes = Base64.decode(sessionContextB64, Base64.NO_WRAP)
            val sessionRecord = SessionRecord(sessionBytes)

            val libStore = LibsignalStore(context, store, myUid)
            val address = SignalProtocolAddress(senderUid, senderDeviceId)

            // Store the session context temporarily for decryption
            libStore.storeSession(address, sessionRecord)

            Log.d(TAG, "applySessionContext: Successfully applied session context (${sessionBytes.size} bytes)")
            return@withContext true

        } catch (e: Exception) {
            Log.e(TAG, "applySessionContext error: ${e.message}", e)
            return@withContext false
        }
    }

    suspend fun checkUserSetup(uid: String): Boolean = withContext(Dispatchers.IO) {
        try {
            // Check if user has identity key
            val identityExists = store.loadPublicKeyBase64(uid, "identity") != null
            Log.d(TAG, "checkUserSetup for $uid: $identityExists")
            return@withContext identityExists
        } catch (e: Exception) {
            Log.e(TAG, "checkUserSetup error: ${e.message}", e)
            return@withContext false
        }
    }

    suspend fun setupUser(uid: String): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Setting up Signal Protocol for user: $uid")

            // Generate identity
            if (!generateIdentity(uid)) {
                Log.e(TAG, "Failed to generate identity for $uid")
                return@withContext false
            }

            // Generate signed prekey
            if (!generateSignedPreKey(uid, 1)) {
                Log.e(TAG, "Failed to generate signed prekey for $uid")
                return@withContext false
            }

            // Generate prekeys
            if (!generatePreKeys(uid, 1, 50)) {
                Log.e(TAG, "Failed to generate prekeys for $uid")
                return@withContext false
            }

            Log.d(TAG, "Signal Protocol setup completed for $uid")
            return@withContext true

        } catch (e: Exception) {
            Log.e(TAG, "setupUser error: ${e.message}", e)
            return@withContext false
        }
    }

    // -------------------------
    // Helper conversions
    // -------------------------
    private fun intToByteArray(value: Int): ByteArray {
        return byteArrayOf(
            (value shr 24 and 0xFF).toByte(),
            (value shr 16 and 0xFF).toByte(),
            (value shr 8 and 0xFF).toByte(),
            (value and 0xFF).toByte()
        )
    }

    private fun byteArrayToInt(bytes: ByteArray): Int {
        if (bytes.size < 4) return 0
        return (bytes[0].toInt() and 0xFF shl 24) or
                (bytes[1].toInt() and 0xFF shl 16) or
                (bytes[2].toInt() and 0xFF shl 8) or
                (bytes[3].toInt() and 0xFF)
    }
}

class LibsignalStore(
    private val context: Context,
    private val signalStore: SignalStore,
    private val myUid: String
) : SignalProtocolStore {
    private val TAG = "LibsignalStore"

    companion object {
        fun normalizeSessionKey(user1: String, user2: String, deviceId: Int): String {
            val users = listOf(user1, user2).sorted()
            return "${users[0]}_${users[1]}_$deviceId"
        }
    }

    // IdentityKeyStore
    override fun getIdentityKeyPair(): IdentityKeyPair {
        val priv = SignalCrypto.loadIdentityPrivateKey(context, myUid)
            ?: throw IllegalStateException("No identity private key for $myUid")
        return IdentityKeyPair(priv)
    }

    override fun getLocalRegistrationId(): Int {
        val regB64 = signalStore.loadPublicKeyBase64(myUid, "regid") ?: return 0
        return try {
            val arr = Base64.decode(regB64, Base64.NO_WRAP)
            byteArrayToInt(arr)
        } catch (e: Exception) {
            0
        }
    }

    override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey): Boolean {
        return true // Allow identity changes for now
    }

    override fun isTrustedIdentity(address: SignalProtocolAddress, identityKey: IdentityKey, direction: Direction?): Boolean {
        return true // Trust all identities for now - production should verify
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? {
        return null // Not used in this implementation
    }

    // PreKeyStore
    override fun loadPreKey(preKeyId: Int): PreKeyRecord {
        val b64 = signalStore.loadPreKeyBase64(myUid, preKeyId)
            ?: throw IllegalStateException("PreKey $preKeyId not found")
        val bytes = Base64.decode(b64, Base64.NO_WRAP)
        return PreKeyRecord(bytes)
    }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) {
        val b64 = Base64.encodeToString(record.serialize(), Base64.NO_WRAP)
        signalStore.savePreKey(myUid, preKeyId, b64)
    }

    override fun containsPreKey(preKeyId: Int): Boolean {
        return signalStore.loadPreKeyBase64(myUid, preKeyId) != null
    }

    override fun removePreKey(preKeyId: Int) {
        signalStore.removePreKey(myUid, preKeyId)
    }

    // SignedPreKeyStore
    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord {
        val b64 = signalStore.loadSignedPreKeyBase64(myUid, signedPreKeyId)
            ?: throw IllegalStateException("SignedPreKey $signedPreKeyId not found")
        val bytes = Base64.decode(b64, Base64.NO_WRAP)
        return SignedPreKeyRecord(bytes)
    }

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> {
        val results = mutableListOf<SignedPreKeyRecord>()
        try {
            val ids = signalStore.listSignedPreKeyIds(myUid)
            for (id in ids) {
                val b64 = signalStore.loadSignedPreKeyBase64(myUid, id) ?: continue
                val bytes = Base64.decode(b64, Base64.NO_WRAP)
                results.add(SignedPreKeyRecord(bytes))
            }
        } catch (e: Exception) {
            Log.e(TAG, "loadSignedPreKeys failed: ${e.message}", e)
        }
        return results
    }

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) {
        val b64 = Base64.encodeToString(record.serialize(), Base64.NO_WRAP)
        signalStore.saveSignedPreKey(myUid, signedPreKeyId, b64)
    }

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean {
        return signalStore.loadSignedPreKeyBase64(myUid, signedPreKeyId) != null
    }

    override fun removeSignedPreKey(signedPreKeyId: Int) {
        signalStore.removeSignedPreKey(myUid, signedPreKeyId)
    }

    // SessionStore

    override fun loadSession(recipient: SignalProtocolAddress): SessionRecord {
        val b64 = signalStore.loadSessionBlobBase64(recipient.name, recipient.deviceId.toLong())
            ?: return SessionRecord()
        val bytes = Base64.decode(b64, Base64.NO_WRAP)
        return SessionRecord(bytes)
    }


    override fun getSubDeviceSessions(name: String): MutableList<Int> {
        val ids = signalStore.listSessionDeviceIds(name)
        return ids.map { it.toInt() }.toMutableList()
    }

    override fun storeSession(recipient: SignalProtocolAddress, record: SessionRecord) {
        val b64 = Base64.encodeToString(record.serialize(), Base64.NO_WRAP)
        signalStore.saveSessionBlob(recipient.name, recipient.deviceId.toLong(), b64)
        Log.d(TAG, "storeSession: Stored session for ${recipient.name}:${recipient.deviceId}")
    }

    override fun containsSession(recipient: SignalProtocolAddress): Boolean {
        val ids = signalStore.listSessionDeviceIds(recipient.name)
        return ids.contains(recipient.deviceId.toLong())
    }

    override fun deleteSession(recipient: SignalProtocolAddress) {
        try {
            signalStore.removeSession(recipient.name, recipient.deviceId.toLong())
            Log.d(TAG, "deleteSession: Deleted session for ${recipient.name}:${recipient.deviceId}")
        } catch (e: Exception) {
            Log.e(TAG, "deleteSession failed for ${recipient.name}:${recipient.deviceId}: ${e.message}", e)
        }
    }

    override fun deleteAllSessions(name: String) {
        try {
            val deviceIds = signalStore.listSessionDeviceIds(name)
            for (deviceId in deviceIds) {
                signalStore.removeSession(name, deviceId)
            }
            Log.d(TAG, "deleteAllSessions: Deleted all sessions for $name")
        } catch (e: Exception) {
            Log.e(TAG, "deleteAllSessions failed for $name: ${e.message}", e)
        }
    }

    private fun byteArrayToInt(bytes: ByteArray): Int {
        if (bytes.size < 4) return 0
        return (bytes[0].toInt() and 0xFF shl 24) or
                (bytes[1].toInt() and 0xFF shl 16) or
                (bytes[2].toInt() and 0xFF shl 8) or
                (bytes[3].toInt() and 0xFF)
    }
}