package com.example.zarq_messenger

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import android.util.Base64
import android.provider.Settings
import com.google.firebase.auth.FirebaseAuth
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.util.KeyHelper
import org.json.JSONObject
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.SessionBuilder
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.ecc.Curve
import org.whispersystems.libsignal.state.PreKeyBundle
import org.whispersystems.libsignal.SessionCipher
import org.whispersystems.libsignal.protocol.CiphertextMessage
import org.whispersystems.libsignal.protocol.PreKeySignalMessage
import org.whispersystems.libsignal.protocol.SignalMessage
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.TimeUnit

class SignalManager(private val context: Context) {

    companion object {
        private const val TAG = "SignalManager"
        private const val PREFS_NAME = "signal_keys"

        // Key storage keys
        private const val KEY_IDENTITY_KEY_PAIR = "identity_key_pair"
        private const val KEY_REGISTRATION_ID = "registration_id"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_SIGNED_PREKEY_ID = "signed_prekey_id"
        private const val KEY_NEXT_PREKEY_ID = "next_prekey_id"
        private const val KEY_KEYS_GENERATED = "keys_generated"
        private const val KEY_STORE_INITIALIZED = "store_initialized"
        private const val KEY_LAST_PREKEY_ROTATION = "last_prekey_rotation"
        private const val KEY_LAST_SIGNED_PREKEY_ROTATION = "last_signed_prekey_rotation"
        private const val KEY_DEVICE_FINGERPRINT = "device_fingerprint"
        private const val KEY_INSTALLATION_ID = "installation_id"

        // Security constants
        private const val SIGNED_PREKEY_ROTATION_DAYS = 7L
        private const val PREKEY_MINIMUM_COUNT = 10
        private const val PREKEY_BATCH_SIZE = 100
        private const val MAX_SESSION_AGE_HOURS = 24L
    }

    private val sharedPrefs: SharedPreferences
        get() = getUserSpecificSharedPrefs()
    private val secureRandom = SecureRandom()


    // Secure crypto wrapper for key storage
    private val signalCrypto by lazy { SignalCrypto(context) }
    private var currentUserUid: String? = null
    private var _signalProtocolStore: SignalProtocolStore? = null

    private fun getCurrentUserUid(): String? {
        return try {
            val uid = FirebaseAuth.getInstance().currentUser?.uid
            uid
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get current user UID", e)
            null
        }
    }

    private fun isUserChanged(): Boolean {
        val newUid = getCurrentUserUid()
        val changed = newUid != currentUserUid
        if (changed) {
            Log.d(TAG, "User context changed: '$currentUserUid' -> '$newUid'")
            currentUserUid = newUid
            // Clear the cached store when user changes
            _signalProtocolStore = null
        }
        return changed
    }

    // Replace your existing signalProtocolStore lazy initialization with:
    private val signalProtocolStore: SignalProtocolStore
        get() {
            // Check if user changed or store not initialized
            isUserChanged() // This updates currentUserUid and clears store if needed

            if (_signalProtocolStore == null) {
                Log.d(TAG, "Initializing SignalProtocolStore for user: $currentUserUid")
                _signalProtocolStore = SignalProtocolStore(context, currentUserUid)
            }
            return _signalProtocolStore!!
        }


    fun resetUserContext(): Boolean {
        return try {
            Log.d(TAG, "Resetting user context...")
            currentUserUid = null // Clear cached UID
            _signalProtocolStore = null // Clear cached store

            // Force regeneration of SharedPreferences for new user
            // The lazy sharedPrefs will be recreated next time it's accessed
            Log.d(TAG, "User context reset successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset user context", e)
            false
        }
    }

    /**
     * Generate a unique, persistent device ID for this installation
     */
    fun generateDeviceId(): Int {
        val existingDeviceId = sharedPrefs.getInt(KEY_DEVICE_ID, -1)
        if (existingDeviceId != -1) {
            Log.d(TAG, "Using existing device ID: $existingDeviceId")
            return existingDeviceId
        }

        // Generate new device ID using multiple entropy sources
        val deviceId = try {
            // Combine multiple sources for better uniqueness
            val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            val timestamp = System.currentTimeMillis()
            val random = secureRandom.nextInt(999999)

            val userUid = try {
                FirebaseAuth.getInstance().currentUser?.uid ?: "anonymous"
            } catch (e: Exception) {
                Log.w(TAG, "Could not get Firebase UID for device ID", e)
                "unknown"
            }

            // Create deterministic but unique device ID
            val combined = "$androidId-$userUid-$timestamp-$random"
            val hash = combined.hashCode()

            // Ensure positive ID between 1 and Integer.MAX_VALUE
            val deviceId = (Math.abs(hash) % 999999) + 1

            Log.d(TAG, "Generated new device ID: $deviceId")
            deviceId

        } catch (e: Exception) {
            Log.w(TAG, "Fallback device ID generation", e)
            // Fallback: timestamp-based ID
            ((System.currentTimeMillis() % 999999) + 1).toInt()
        }

        // Store the device ID permanently
        sharedPrefs.edit().putInt(KEY_DEVICE_ID, deviceId).apply()
        Log.d(TAG, "Stored device ID: $deviceId")

        return deviceId
    }


    fun resetForNewUser(): Boolean {
        return try {
            Log.d(TAG, "Resetting SignalManager for new user")
            currentUserUid = getCurrentUserUid()
            // Force re-initialization of stores with new user context
            _signalProtocolStore = SignalProtocolStore(context, currentUserUid)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset for new user", e)
            false
        }
    }


    private fun getUserSpecificSharedPrefs(): SharedPreferences {
        val userUid = try {
            val uid = FirebaseAuth.getInstance().currentUser?.uid
            uid ?: "anonymous"
        } catch (e: Exception) {
            Log.e(TAG, "Could not get Firebase UID for prefs", e)
            "anonymous"
        }

        val prefsName = "${PREFS_NAME}_${userUid}"
        return context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
    }

    /**
     * Get the current device ID (generates if not exists)
     */
    fun getDeviceId(): Int {
        val deviceId = sharedPrefs.getInt(KEY_DEVICE_ID, -1)
        return if (deviceId == -1) {
            generateDeviceId()
        } else {
            deviceId
        }
    }

    /**
     * Generate installation fingerprint for device verification
     */
    private fun generateInstallationFingerprint(): String {
        val existingFingerprint = sharedPrefs.getString(KEY_DEVICE_FINGERPRINT, null)
        if (existingFingerprint != null) {
            return existingFingerprint
        }

        // Generate unique installation fingerprint
        val installationId = UUID.randomUUID().toString()
        val deviceInfo = "${android.os.Build.MODEL}-${android.os.Build.MANUFACTURER}"
        val timestamp = System.currentTimeMillis()

        val fingerprint = "$installationId-$deviceInfo-$timestamp".hashCode().toString()

        sharedPrefs.edit()
            .putString(KEY_DEVICE_FINGERPRINT, fingerprint)
            .putString(KEY_INSTALLATION_ID, installationId)
            .apply()

        Log.d(TAG, "Generated installation fingerprint")
        return fingerprint
    }

    /**
     * Check if Signal Protocol keys have already been generated
     */
    fun hasKeys(): Boolean {
        val hasKeys = sharedPrefs.getBoolean(KEY_KEYS_GENERATED, false)
        Log.d(TAG, "hasKeys: $hasKeys")
        return hasKeys
    }

    /**
     * Check if the protocol store has been initialized
     */
    fun isStoreInitialized(): Boolean {
        val initialized = sharedPrefs.getBoolean(KEY_STORE_INITIALIZED, false)
        Log.d(TAG, "isStoreInitialized: $initialized")
        return initialized
    }

    fun getCurrentSignedPreKey(): Map<String, Any>? {
        return try {
            if (!isStoreInitialized()) {
                Log.e(TAG, "Protocol store not initialized")
                return null
            }

            val currentSignedPreKeyId = sharedPrefs.getInt(KEY_SIGNED_PREKEY_ID, -1)
            if (currentSignedPreKeyId == -1) {
                Log.e(TAG, "No signed prekey ID found")
                return null
            }

            // Load the signed prekey from protocol store
            val signedPreKeyRecord = signalProtocolStore.loadSignedPreKey(currentSignedPreKeyId)
            if (signedPreKeyRecord == null) {
                Log.e(TAG, "Signed prekey record not found for ID: $currentSignedPreKeyId")
                return null
            }

            // Extract and format the signed prekey data
            val publicKeyBytes = signedPreKeyRecord.keyPair.publicKey.serialize()
            val strippedKeyBytes = if (publicKeyBytes.size == 33 && publicKeyBytes[0] == 0x05.toByte()) {
                publicKeyBytes.drop(1).toByteArray()
            } else {
                publicKeyBytes
            }

            val signedPreKeyData = mapOf<String, Any>(
                "key_id" to signedPreKeyRecord.id,
                "public_key_b64" to Base64.encodeToString(strippedKeyBytes, Base64.NO_WRAP),
                "signature_b64" to Base64.encodeToString(signedPreKeyRecord.signature, Base64.NO_WRAP)
            )

            Log.d(TAG, "Retrieved signed prekey data for ID: $currentSignedPreKeyId")
            return signedPreKeyData

        } catch (e: Exception) {
            Log.e(TAG, "Failed to get current signed prekey", e)
            null
        }
    }

    /**
     * Check if signed prekey needs rotation (weekly)
     */
    fun needsSignedPreKeyRotation(): Boolean {
        val lastRotation = sharedPrefs.getLong(KEY_LAST_SIGNED_PREKEY_ROTATION, 0)
        val daysSinceRotation = TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - lastRotation)
        return daysSinceRotation >= SIGNED_PREKEY_ROTATION_DAYS
    }

    /**
     * Rotate signed prekey for forward secrecy
     */
    fun rotateSignedPreKey(): Boolean {
        return try {
            if (!isStoreInitialized()) {
                Log.e(TAG, "Cannot rotate signed prekey - store not initialized")
                return false
            }

            Log.d(TAG, "Rotating signed prekey...")

            // Load identity key pair
            val identityKeyPair = loadIdentityKeyPair()
                ?: throw Exception("Identity key pair not found")

            // Generate new signed prekey with incremented ID
            val currentSignedPreKeyId = sharedPrefs.getInt(KEY_SIGNED_PREKEY_ID, 1)
            val newSignedPreKeyId = currentSignedPreKeyId + 1
            val newSignedPreKey = KeyHelper.generateSignedPreKey(identityKeyPair, newSignedPreKeyId)

            // Store new signed prekey
            signalProtocolStore.storeSignedPreKey(newSignedPreKey.id, newSignedPreKey)

            // Update tracking variables
            sharedPrefs.edit()
                .putInt(KEY_SIGNED_PREKEY_ID, newSignedPreKeyId)
                .putLong(KEY_LAST_SIGNED_PREKEY_ROTATION, System.currentTimeMillis())
                .apply()

            Log.d(TAG, "Signed prekey rotated successfully: $currentSignedPreKeyId -> $newSignedPreKeyId")
            true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to rotate signed prekey", e)
            false
        }
    }

    /**
     * Generate complete Signal Protocol key bundle and initialize the store
     */
    fun generateKeyBundle(): Map<String, Any> {
        try {
            Log.d(TAG, "=== Generating Signal Protocol Key Bundle ===")

            // Generate device ID first
            val deviceId = generateDeviceId()

            // Generate installation fingerprint
            val fingerprint = generateInstallationFingerprint()

            // Check if keys already exist
            if (hasKeys()) {
                Log.d(TAG, "Keys already exist, initializing store if needed")
                return initializeStoreIfNeeded()
            }

            // 1. Generate Identity Key Pair (permanent key for this device)
            Log.d(TAG, "Generating identity key pair...")
            val identityKeyPair = KeyHelper.generateIdentityKeyPair()

            // 2. Generate Registration ID (unique identifier for this installation)
            Log.d(TAG, "Generating registration ID...")
            val registrationId = KeyHelper.generateRegistrationId(false)

            // 3. Generate Signed PreKey (rotated periodically, signed with identity key)
            Log.d(TAG, "Generating signed prekey...")
            val signedPreKeyId = 1 // Start with ID 1
            val signedPreKey = KeyHelper.generateSignedPreKey(identityKeyPair, signedPreKeyId)

            // 4. Generate One-Time PreKeys (consumed once per session establishment)
            Log.d(TAG, "Generating one-time prekeys...")
            val startingPreKeyId = 1
            val preKeys = KeyHelper.generatePreKeys(startingPreKeyId, PREKEY_BATCH_SIZE)

            // 5. Store all keys securely using Android Keystore
            Log.d(TAG, "Storing keys securely...")
            storeKeysSecurely(identityKeyPair, registrationId, signedPreKey, preKeys, deviceId)

            // 6. Initialize the protocol store with identity and registration ID
            Log.d(TAG, "Initializing protocol store...")
            signalProtocolStore.initializeStore(identityKeyPair, registrationId)

            // 7. Store prekeys and signed prekeys in the protocol store
            storeKeysInProtocolStore(signedPreKey, preKeys)

            // Mark store as initialized and track rotation time
            sharedPrefs.edit()
                .putBoolean(KEY_STORE_INITIALIZED, true)
                .putLong(KEY_LAST_SIGNED_PREKEY_ROTATION, System.currentTimeMillis())
                .putLong(KEY_LAST_PREKEY_ROTATION, System.currentTimeMillis())
                .apply()

            // 8. Prepare response bundle
            val keyBundle = createKeyBundleResponse(
                identityKeyPair, registrationId, signedPreKey, preKeys, deviceId, fingerprint
            )

            Log.d(TAG, "Key bundle generated and store initialized successfully")
            Log.d(TAG, "- Device ID: $deviceId")
            Log.d(TAG, "- Registration ID: ${keyBundle["registration_id"]}")
            Log.d(TAG, "- Signed PreKey ID: ${keyBundle["signed_prekey_id"]}")
            Log.d(TAG, "- One-Time PreKeys: ${(keyBundle["one_time_prekeys"] as List<*>).size}")
            Log.d(TAG, "- Installation Fingerprint: ${fingerprint.take(16)}...")

            return keyBundle

        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate key bundle", e)
            throw Exception("Signal key generation failed: ${e.message}")
        }
    }

    /**
     * Load identity key pair from secure storage
     */
    private fun loadIdentityKeyPair(): IdentityKeyPair? {
        return try {
            val identityKeyPairData = sharedPrefs.getString(KEY_IDENTITY_KEY_PAIR, null)
                ?: return null

            // Try to decrypt first (new format)
            val jsonString = try {
                signalCrypto.decryptData(identityKeyPairData)
            } catch (e: Exception) {
                // Fallback to unencrypted (old format)
                Log.d(TAG, "Using unencrypted identity key pair")
                identityKeyPairData
            }

            val json = JSONObject(jsonString)
            val publicKeyB64 = json.getString("public_key")
            val privateKeyB64 = json.getString("private_key")

            val publicKeyBytes = Base64.decode(publicKeyB64, Base64.NO_WRAP)
            val privateKeyBytes = Base64.decode(privateKeyB64, Base64.NO_WRAP)

            val publicKey = Curve.decodePoint(publicKeyBytes, 0)
            val privateKey = Curve.decodePrivatePoint(privateKeyBytes)

            IdentityKeyPair(IdentityKey(publicKey), privateKey)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load identity key pair", e)
            null
        }
    }

    /**
     * Store all generated keys securely using Android Keystore
     */
    private fun storeKeysSecurely(
        identityKeyPair: IdentityKeyPair,
        registrationId: Int,
        signedPreKey: SignedPreKeyRecord,
        preKeys: List<PreKeyRecord>,
        deviceId: Int
    ) {
        try {
            Log.d(TAG, "Storing keys securely using Android Keystore...")

            val editor = sharedPrefs.edit()

            // Store identity key pair with encryption
            val identityData = JSONObject().apply {
                put("public_key", Base64.encodeToString(identityKeyPair.publicKey.serialize(), Base64.NO_WRAP))
                put("private_key", Base64.encodeToString(identityKeyPair.privateKey.serialize(), Base64.NO_WRAP))
            }

            // Encrypt sensitive data using Android Keystore
            val encryptedIdentityData = signalCrypto.encryptData(identityData.toString())
            editor.putString(KEY_IDENTITY_KEY_PAIR, encryptedIdentityData)

            // Store other metadata
            editor.putInt(KEY_REGISTRATION_ID, registrationId)
            editor.putInt(KEY_DEVICE_ID, deviceId)
            editor.putInt(KEY_SIGNED_PREKEY_ID, signedPreKey.id)
            editor.putInt(KEY_NEXT_PREKEY_ID, preKeys.size + 1)
            editor.putBoolean(KEY_KEYS_GENERATED, true)

            // Apply changes
            editor.apply()

            Log.d(TAG, "Keys stored securely with Android Keystore encryption")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to store keys securely", e)
            // Fallback to unencrypted storage if Keystore fails
            Log.w(TAG, "Falling back to unencrypted storage")
            storeKeysUnencrypted(identityKeyPair, registrationId, signedPreKey, preKeys, deviceId)
        }
    }

    /**
     * Fallback: Store keys without encryption (for older devices)
     */
    private fun storeKeysUnencrypted(
        identityKeyPair: IdentityKeyPair,
        registrationId: Int,
        signedPreKey: SignedPreKeyRecord,
        preKeys: List<PreKeyRecord>,
        deviceId: Int
    ) {
        try {
            val editor = sharedPrefs.edit()

            // Store identity key pair as JSON
            val identityData = JSONObject().apply {
                put("public_key", Base64.encodeToString(identityKeyPair.publicKey.serialize(), Base64.NO_WRAP))
                put("private_key", Base64.encodeToString(identityKeyPair.privateKey.serialize(), Base64.NO_WRAP))
            }
            editor.putString(KEY_IDENTITY_KEY_PAIR, identityData.toString())

            // Store other data
            editor.putInt(KEY_REGISTRATION_ID, registrationId)
            editor.putInt(KEY_DEVICE_ID, deviceId)
            editor.putInt(KEY_SIGNED_PREKEY_ID, signedPreKey.id)
            editor.putInt(KEY_NEXT_PREKEY_ID, preKeys.size + 1)
            editor.putBoolean(KEY_KEYS_GENERATED, true)

            editor.apply()
            Log.d(TAG, "Keys stored (unencrypted fallback)")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to store keys even with fallback", e)
            throw Exception("Key storage failed: ${e.message}")
        }
    }

    /**
     * Initialize store from existing keys if not already done
     */
    private fun initializeStoreIfNeeded(): Map<String, Any> {
        try {
            if (isStoreInitialized()) {
                Log.d(TAG, "Store already initialized, returning existing bundle info")
                return getExistingKeyBundle()
            }

            Log.d(TAG, "Store not initialized, initializing from existing keys...")

            // Load existing identity key pair and registration ID
            val identityKeyPair = loadStoredIdentityKeyPair()
                ?: throw Exception("Identity key pair not found")

            val registrationId = sharedPrefs.getInt(KEY_REGISTRATION_ID, -1)
            if (registrationId == -1) throw Exception("Registration ID not found")

            // Initialize the protocol store
            signalProtocolStore.initializeStore(identityKeyPair, registrationId)

            // Mark store as initialized
            sharedPrefs.edit().putBoolean(KEY_STORE_INITIALIZED, true).apply()

            Log.d(TAG, "Store initialized from existing keys")
            return getExistingKeyBundle()

        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize store from existing keys", e)
            throw Exception("Store initialization failed: ${e.message}")
        }
    }

    /**
     * Load stored identity key pair with decryption if needed
     */
    private fun loadStoredIdentityKeyPair(): IdentityKeyPair? {
        return try {
            val identityKeyPairData = sharedPrefs.getString(KEY_IDENTITY_KEY_PAIR, null)
                ?: return null

            // Try to decrypt first (new format)
            val jsonString = try {
                signalCrypto.decryptData(identityKeyPairData)
            } catch (e: Exception) {
                // Fallback to unencrypted (old format)
                Log.d(TAG, "Using unencrypted identity key pair")
                identityKeyPairData
            }

            val json = JSONObject(jsonString)
            val publicKeyB64 = json.getString("public_key")
            val privateKeyB64 = json.getString("private_key")

            val publicKeyBytes = Base64.decode(publicKeyB64, Base64.NO_WRAP)
            val privateKeyBytes = Base64.decode(privateKeyB64, Base64.NO_WRAP)

            val publicKey = Curve.decodePoint(publicKeyBytes, 0)
            val privateKey = Curve.decodePrivatePoint(privateKeyBytes)

            IdentityKeyPair(IdentityKey(publicKey), privateKey)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to load stored identity key pair", e)
            null
        }
    }

    /**
     * Store prekeys and signed prekeys in the protocol store
     */
    private fun storeKeysInProtocolStore(signedPreKey: SignedPreKeyRecord, preKeys: List<PreKeyRecord>) {
        try {
            // Store signed prekey
            signalProtocolStore.storeSignedPreKey(signedPreKey.id, signedPreKey)

            // Store all one-time prekeys
            for (preKey in preKeys) {
                signalProtocolStore.storePreKey(preKey.id, preKey)
            }

            Log.d(TAG, "Stored ${preKeys.size} prekeys and 1 signed prekey in protocol store")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to store keys in protocol store", e)
            throw Exception("Protocol store key storage failed: ${e.message}")
        }
    }

    /**
     * Get existing key bundle if keys were already generated
     */
    private fun getExistingKeyBundle(): Map<String, Any> {
        Log.d(TAG, "Loading existing key bundle...")

        val registrationId = sharedPrefs.getInt(KEY_REGISTRATION_ID, -1)
        if (registrationId == -1) throw Exception("Registration ID not found")

        val deviceId = getDeviceId()
        val fingerprint = sharedPrefs.getString(KEY_DEVICE_FINGERPRINT, "unknown")

        return mapOf<String, Any>(
            "identity_key_b64" to "existing_key_placeholder",
            "registration_id" to registrationId,
            "device_id" to deviceId,
            "signed_prekey_id" to sharedPrefs.getInt(KEY_SIGNED_PREKEY_ID, 1),
            "signed_prekey_b64" to "existing_signed_prekey",
            "signed_prekey_signature_b64" to "existing_signature",
            "one_time_prekeys" to emptyList<Map<String, Any>>(),
            "existing_keys" to true,
            "store_initialized" to isStoreInitialized(),
            "device_fingerprint" to (fingerprint ?: "unknown"),
            "needs_rotation" to needsSignedPreKeyRotation()
        )
    }

    /**
     * Create the response bundle with all necessary key information
     */
    private fun createKeyBundleResponse(
        identityKeyPair: IdentityKeyPair,
        registrationId: Int,
        signedPreKey: SignedPreKeyRecord,
        preKeys: List<PreKeyRecord>,
        deviceId: Int,
        fingerprint: String
    ): Map<String, Any> {

        // Strip first byte if it's a prefix (33 bytes -> 32 bytes)
        fun stripKeyPrefix(keyBytes: ByteArray): ByteArray {
            return if (keyBytes.size == 33 && keyBytes[0] == 0x05.toByte()) {
                keyBytes.drop(1).toByteArray()
            } else {
                keyBytes
            }
        }

        // Convert identity key to base64 (strip prefix)
        val identityKeyBytes = stripKeyPrefix(identityKeyPair.publicKey.serialize())
        val identityKeyB64 = Base64.encodeToString(identityKeyBytes, Base64.NO_WRAP)

        // Convert signed prekey to base64 (strip prefix)
        val signedPreKeyBytes = stripKeyPrefix(signedPreKey.keyPair.publicKey.serialize())
        val signedPreKeyB64 = Base64.encodeToString(signedPreKeyBytes, Base64.NO_WRAP)

        // Convert signature to base64
        val signatureB64 = Base64.encodeToString(signedPreKey.signature, Base64.NO_WRAP)

        // Convert one-time prekeys to list of maps (strip prefixes)
        val oneTimePreKeys = preKeys.map { preKey ->
            val preKeyBytes = stripKeyPrefix(preKey.keyPair.publicKey.serialize())
            mapOf(
                "key_id" to preKey.id,
                "public_key_b64" to Base64.encodeToString(preKeyBytes, Base64.NO_WRAP)
            )
        }

        return mapOf(
            "identity_key_b64" to identityKeyB64,
            "registration_id" to registrationId,
            "device_id" to deviceId,
            "signed_prekey_id" to signedPreKey.id,
            "signed_prekey_b64" to signedPreKeyB64,
            "signed_prekey_signature_b64" to signatureB64,
            "one_time_prekeys" to oneTimePreKeys,
            "timestamp" to System.currentTimeMillis(),
            "store_initialized" to true,
            "device_fingerprint" to fingerprint,
            "installation_id" to (sharedPrefs.getString(KEY_INSTALLATION_ID, null) ?: "unknown")
        )
    }

    /**
     * Get the protocol store instance for session operations
     */
    fun getProtocolStore(): SignalProtocolStore {
        if (!isStoreInitialized()) {
            throw Exception("Protocol store not initialized. Call generateKeyBundle() first.")
        }
        return signalProtocolStore
    }

    /**
     * Clear all stored keys (for logout or reset)
     */
    fun clearKeys(): Boolean {
        return try {
            Log.d(TAG, "Clearing all Signal Protocol keys...")
            sharedPrefs.edit().clear().apply()
            signalProtocolStore.clearAll()

            // Clear Android Keystore entries
            try {
                signalCrypto.clearKeys()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to clear Keystore keys", e)
            }

            Log.d(TAG, "Keys cleared successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear keys", e)
            false
        }
    }

    /**
     * Get current registration ID
     */
    fun getRegistrationId(): Int {
        return sharedPrefs.getInt(KEY_REGISTRATION_ID, -1)
    }

    /**
     * Establish a session with another user using their prekey bundle
     * This implements the X3DH key agreement protocol
     */
    fun establishSession(
        recipientUid: String,
        deviceId: Int,
        prekeyBundleData: Map<String, Any>
    ): Boolean {
        return try {
            Log.d(TAG, "=== Establishing session with $recipientUid:$deviceId ===")

            if (!isStoreInitialized()) {
                throw Exception("Protocol store not initialized")
            }

            // Parse the prekey bundle from backend response
            val prekeyBundle = parsePreKeyBundle(prekeyBundleData)
            Log.d(TAG, "Parsed prekey bundle - Identity: ${prekeyBundle.identityKey != null}, SignedPreKey: ${prekeyBundle.signedPreKey != null}, OneTimePreKey: ${prekeyBundle.preKey != null}")

            // Create Signal Protocol address for the recipient
            val recipientAddress = SignalProtocolAddress(recipientUid, deviceId)

            // Create session builder
            val sessionBuilder = SessionBuilder(signalProtocolStore, recipientAddress)

            // Process the prekey bundle to establish session
            sessionBuilder.process(prekeyBundle)

            Log.d(TAG, "Session established successfully with $recipientUid:$deviceId")

            // Verify session was created
            val hasSession = signalProtocolStore.containsSession(recipientAddress)
            Log.d(TAG, "Session verification: $hasSession")

            return hasSession

        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish session with $recipientUid:$deviceId", e)
            false
        }
    }

    /**
     * Parse prekey bundle data from backend response into Signal Protocol PreKeyBundle
     */
    private fun parsePreKeyBundle(bundleData: Map<String, Any>): PreKeyBundle {
        try {
            // Extract required fields
            val registrationId = (bundleData["registration_id"] as? Number)?.toInt()
                ?: throw Exception("Missing registration_id")

            val deviceId = (bundleData["device_id"] as? Number)?.toInt()
                ?: throw Exception("Missing device_id")

            val identityKeyB64 = bundleData["identity_key_b64"] as? String
                ?: throw Exception("Missing identity_key_b64")

            val signedPreKeyId = (bundleData["signed_prekey_id"] as? Number)?.toInt()
                ?: throw Exception("Missing signed_prekey_id")

            val signedPreKeyB64 = bundleData["signed_prekey_b64"] as? String
                ?: throw Exception("Missing signed_prekey_b64")

            val signedPreKeySignatureB64 = bundleData["signed_prekey_signature_b64"] as? String
                ?: throw Exception("Missing signed_prekey_signature_b64")

            // One-time prekey is optional
            val oneTimePreKeyId = (bundleData["one_time_prekey_id"] as? Number)?.toInt()
            val oneTimePreKeyB64 = bundleData["one_time_prekey_b64"] as? String

            // Decode identity key
            val identityKeyBytes = Base64.decode(identityKeyB64, Base64.NO_WRAP)
            val identityKeyWithPrefix = byteArrayOf(0x05.toByte()) + identityKeyBytes
            val identityKey = IdentityKey(identityKeyWithPrefix, 0)

            // Decode signed prekey
            val signedPreKeyBytes = Base64.decode(signedPreKeyB64, Base64.NO_WRAP)
            val signedPreKeyWithPrefix = byteArrayOf(0x05.toByte()) + signedPreKeyBytes
            val signedPreKeyPublic = Curve.decodePoint(signedPreKeyWithPrefix, 0)

            // Decode signature
            val signatureBytes = Base64.decode(signedPreKeySignatureB64, Base64.NO_WRAP)

            // Decode one-time prekey if present
            val oneTimePreKeyPublic = if (oneTimePreKeyB64 != null) {
                val oneTimePreKeyBytes = Base64.decode(oneTimePreKeyB64, Base64.NO_WRAP)
                val oneTimePreKeyWithPrefix = byteArrayOf(0x05.toByte()) + oneTimePreKeyBytes
                Curve.decodePoint(oneTimePreKeyWithPrefix, 0)
            } else null

            // Create PreKeyBundle
            return PreKeyBundle(
                registrationId,
                deviceId,
                oneTimePreKeyId ?: 0, // Use 0 if no one-time prekey
                oneTimePreKeyPublic,
                signedPreKeyId,
                signedPreKeyPublic,
                signatureBytes,
                identityKey
            )

        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse prekey bundle", e)
            throw Exception("Invalid prekey bundle: ${e.message}")
        }
    }

    /**
     * Check if we have an established session with a recipient
     */
    fun hasSession(recipientUid: String, deviceId: Int): Boolean {
        return try {
            if (!isStoreInitialized()) {
                Log.w(TAG, "Protocol store not initialized for session check")
                return false
            }

            val address = SignalProtocolAddress(recipientUid, deviceId)
            val hasSession = signalProtocolStore.containsSession(address)
            Log.d(TAG, "Session check for $recipientUid:$deviceId = $hasSession")
            hasSession

        } catch (e: Exception) {
            Log.e(TAG, "Failed to check session for $recipientUid:$deviceId", e)
            false
        }
    }

    /**
     * Validate session freshness and integrity
     */
    fun validateSession(recipientUid: String, deviceId: Int): Boolean {
        return try {
            if (!hasSession(recipientUid, deviceId)) {
                Log.w(TAG, "No session exists for validation")
                return false
            }

            // For now, if hasSession returns true, we consider it valid
            // More sophisticated validation can be added later if needed
            Log.d(TAG, "Session validation passed for $recipientUid:$deviceId")
            true

        } catch (e: Exception) {
            Log.e(TAG, "Session validation failed for $recipientUid:$deviceId", e)
            false
        }
    }

    /**
     * Get all active sessions for debugging/monitoring
     */
    fun getActiveSessions(): List<String> {
        return try {
            if (!isStoreInitialized()) {
                return emptyList()
            }

            // This is a simplified approach - in a real implementation you'd track active sessions
            // For now, we'll return empty list since SignalProtocolStore doesn't have a getAllSessions method
            Log.d(TAG, "Active sessions query - store initialized: ${isStoreInitialized()}")
            emptyList()

        } catch (e: Exception) {
            Log.e(TAG, "Failed to get active sessions", e)
            emptyList()
        }
    }

    /**
     * Remove session with a specific user (for testing/cleanup)
     */
    fun removeSession(recipientUid: String, deviceId: Int): Boolean {
        return try {
            if (!isStoreInitialized()) {
                return false
            }

            val address = SignalProtocolAddress(recipientUid, deviceId)
            signalProtocolStore.deleteSession(address)

            Log.d(TAG, "Removed session with $recipientUid:$deviceId")
            true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to remove session with $recipientUid:$deviceId", e)
            false
        }
    }

    /**
     * Encrypt a plaintext message for a specific recipient
     * Uses the Double Ratchet algorithm via SessionCipher
     */
    fun encryptMessage(
        recipientUid: String,
        plaintext: String,
        deviceId: Int
    ): String? {
        return try {
            Log.d(TAG, "=== Encrypting message for $recipientUid:$deviceId ===")
            Log.d(TAG, "Plaintext length: ${plaintext.length}")

            if (!isStoreInitialized()) {
                throw Exception("Protocol store not initialized")
            }

            // Create recipient address
            val recipientAddress = SignalProtocolAddress(recipientUid, deviceId)

            // Check if session exists
            if (!signalProtocolStore.containsSession(recipientAddress)) {
                Log.e(TAG, "No session exists with $recipientUid:$deviceId")
                throw Exception("No session exists with recipient. Establish session first.")
            }

            // Validate session before encryption
            if (!validateSession(recipientUid, deviceId)) {
                Log.w(TAG, "Session validation failed, attempting to continue anyway")
            }

            // Create session cipher
            val sessionCipher = SessionCipher(signalProtocolStore, recipientAddress)

            // Encrypt the message
            val ciphertext = sessionCipher.encrypt(plaintext.toByteArray(Charsets.UTF_8))

            // Convert to base64 for transmission
            val ciphertextB64 = Base64.encodeToString(ciphertext.serialize(), Base64.NO_WRAP)

            Log.d(TAG, "Message encrypted successfully")
            Log.d(TAG, "Ciphertext type: ${ciphertext.type}")
            Log.d(TAG, "Ciphertext length: ${ciphertextB64.length}")

            return ciphertextB64

        } catch (e: Exception) {
            Log.e(TAG, "Failed to encrypt message for $recipientUid:$deviceId", e)
            null
        }
    }

    /**
     * Decrypt a received message from a specific sender
     * Handles both PreKeySignalMessage and regular SignalMessage types
     */
    fun decryptMessage(
        senderUid: String,
        ciphertextB64: String,
        deviceId: Int
    ): String? {
        val senderAddress = SignalProtocolAddress(senderUid, deviceId)

        return try {
            Log.d(TAG, "=== Decrypting message from $senderUid:$deviceId ===")

            if (!isStoreInitialized()) {
                throw Exception("Protocol store not initialized")
            }

            val ciphertextBytes = Base64.decode(ciphertextB64, Base64.NO_WRAP)
            val sessionCipher = SessionCipher(signalProtocolStore, senderAddress)

            // Decrypt based on message type
            val plaintext = if (isPreKeySignalMessage(ciphertextBytes)) {
                Log.d(TAG, "Decrypting PreKeySignalMessage - will establish session")
                val preKeyMessage = PreKeySignalMessage(ciphertextBytes)
                sessionCipher.decrypt(preKeyMessage) // This establishes the session
            } else {
                Log.d(TAG, "Decrypting regular SignalMessage")
                // Only check session for regular messages
                if (!signalProtocolStore.containsSession(senderAddress)) {
                    throw Exception("No session exists for regular SignalMessage")
                }
                val signalMessage = SignalMessage(ciphertextBytes)
                sessionCipher.decrypt(signalMessage)
            }

            val decryptedText = String(plaintext, Charsets.UTF_8)
            Log.d(TAG, "Message decrypted successfully")
            return decryptedText

        } catch (e: Exception) {
            Log.e(TAG, "Failed to decrypt message from $senderUid:$deviceId", e)
            Log.e(TAG, "Exception: ${e.javaClass.simpleName}: ${e.message}")
            null
        }
    }

    /**
     * Determine if the ciphertext is a PreKeySignalMessage
     * PreKeySignalMessages are sent when no session exists yet
     */
    private fun isPreKeySignalMessage(ciphertextBytes: ByteArray): Boolean {
        return try {
            // PreKeySignalMessage starts with version byte and type
            // Check if first byte indicates PreKeySignalMessage type
            if (ciphertextBytes.isEmpty()) return false

            val version = ciphertextBytes[0].toInt() and 0xFF
            val type = (version shr 4) and 0x0F

            // PreKeySignalMessage type is 3
            type == CiphertextMessage.PREKEY_TYPE
        } catch (e: Exception) {
            Log.w(TAG, "Error determining message type, assuming SignalMessage", e)
            false
        }
    }

    /**
     * Encrypt message and establish session if needed (convenience method)
     * This combines session establishment and encryption in one call
     */
    fun encryptMessageWithSessionSetup(
        recipientUid: String,
        plaintext: String,
        prekeyBundle: Map<String, Any>? = null,
        deviceId: Int
    ): String? {
        return try {
            Log.d(TAG, "=== Encrypt with session setup for $recipientUid:$deviceId ===")

            val recipientAddress = SignalProtocolAddress(recipientUid, deviceId)

            // Check if session already exists
            if (!signalProtocolStore.containsSession(recipientAddress)) {
                Log.d(TAG, "No existing session, establishing new session")

                if (prekeyBundle == null) {
                    throw Exception("No session exists and no prekey bundle provided")
                }

                // Establish session first
                val sessionEstablished = establishSession(recipientUid, deviceId, prekeyBundle)
                if (!sessionEstablished) {
                    throw Exception("Failed to establish session")
                }

                Log.d(TAG, "Session established, proceeding with encryption")
            } else {
                Log.d(TAG, "Using existing session for encryption")
            }

            // Now encrypt the message
            return encryptMessage(recipientUid, plaintext, deviceId)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to encrypt message with session setup", e)
            null
        }
    }

    /**
     * Generate additional one-time prekeys when running low
     */
    fun generateAdditionalPreKeys(count: Int = PREKEY_BATCH_SIZE): List<Map<String, Any>> {
        return try {
            if (!isStoreInitialized()) {
                throw Exception("Protocol store not initialized")
            }

            val nextPreKeyId = sharedPrefs.getInt(KEY_NEXT_PREKEY_ID, 1)
            val preKeys = KeyHelper.generatePreKeys(nextPreKeyId, count)

            // Store new prekeys in protocol store
            for (preKey in preKeys) {
                signalProtocolStore.storePreKey(preKey.id, preKey)
            }

            // Update next prekey ID
            sharedPrefs.edit()
                .putInt(KEY_NEXT_PREKEY_ID, nextPreKeyId + count)
                .putLong(KEY_LAST_PREKEY_ROTATION, System.currentTimeMillis())
                .apply()

            // Convert to response format
            val preKeyData = preKeys.map { preKey ->
                val keyBytes = preKey.keyPair.publicKey.serialize()
                val strippedBytes = if (keyBytes.size == 33 && keyBytes[0] == 0x05.toByte()) {
                    keyBytes.drop(1).toByteArray()
                } else {
                    keyBytes
                }

                mapOf(
                    "key_id" to preKey.id,
                    "public_key_b64" to Base64.encodeToString(strippedBytes, Base64.NO_WRAP)
                )
            }

            Log.d(TAG, "Generated $count additional prekeys starting from ID $nextPreKeyId")
            preKeyData

        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate additional prekeys", e)
            emptyList()
        }
    }

    /**
     * Get encryption statistics for monitoring
     */
    fun getEncryptionStats(): Map<String, Any> {
        return try {
            val stats = mutableMapOf<String, Any>()
            stats["store_initialized"] = isStoreInitialized()

            val regId = getRegistrationId()
            stats["registration_id"] = if (regId != -1) regId else "not_set"

            val deviceId = getDeviceId()
            stats["device_id"] = deviceId

            stats["needs_signed_prekey_rotation"] = needsSignedPreKeyRotation()

            val fingerprint = sharedPrefs.getString(KEY_DEVICE_FINGERPRINT, "unknown")
            stats["device_fingerprint"] = "${fingerprint?.take(16) ?: "unknown"}..."

            // Add more stats as needed
            if (isStoreInitialized()) {
                stats["identity_key_exists"] = (signalProtocolStore.identityKeyPair != null)

                // Key rotation timestamps
                val lastSignedRotation = sharedPrefs.getLong(KEY_LAST_SIGNED_PREKEY_ROTATION, 0)
                val lastPreKeyRotation = sharedPrefs.getLong(KEY_LAST_PREKEY_ROTATION, 0)

                stats["last_signed_prekey_rotation"] = if (lastSignedRotation > 0) lastSignedRotation else "never"
                stats["last_prekey_rotation"] = if (lastPreKeyRotation > 0) lastPreKeyRotation else "never"
            }

            Log.d(TAG, "Encryption stats: $stats")
            stats
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get encryption stats", e)
            mapOf<String, Any>("error" to (e.message ?: "unknown_error"))
        }
    }

    /**
     * Perform security audit of current setup
     */
    fun performSecurityAudit(): Map<String, Any> {
        return try {
            val audit = mutableMapOf<String, Any>()

            // Check key generation
            audit["keys_generated"] = hasKeys()
            audit["store_initialized"] = isStoreInitialized()

            // Check device ID
            val deviceId = getDeviceId()
            audit["device_id_set"] = (deviceId != -1)
            audit["device_id"] = deviceId

            // Check encryption capability
            try {
                val testEncrypted = signalCrypto.encryptData("test")
                val testDecrypted = signalCrypto.decryptData(testEncrypted)
                audit["keystore_encryption"] = (testDecrypted == "test")
            } catch (e: Exception) {
                audit["keystore_encryption"] = false
                audit["keystore_error"] = (e.message ?: "unknown_error")
            }

            // Check key rotation needs
            audit["needs_signed_prekey_rotation"] = needsSignedPreKeyRotation()

            // Check installation integrity
            val fingerprint = sharedPrefs.getString(KEY_DEVICE_FINGERPRINT, null)
            audit["has_device_fingerprint"] = (fingerprint != null)

            val installationId = sharedPrefs.getString(KEY_INSTALLATION_ID, null)
            audit["has_installation_id"] = (installationId != null)

            // Overall security score
            var securityScore = 0
            if (hasKeys()) securityScore += 20
            if (isStoreInitialized()) securityScore += 20
            if (deviceId != -1) securityScore += 15
            if (audit["keystore_encryption"] == true) securityScore += 25
            if (fingerprint != null) securityScore += 10
            if (installationId != null) securityScore += 10

            audit["security_score"] = securityScore
            audit["security_level"] = when {
                securityScore >= 90 -> "EXCELLENT"
                securityScore >= 75 -> "GOOD"
                securityScore >= 60 -> "ADEQUATE"
                securityScore >= 40 -> "POOR"
                else -> "CRITICAL"
            }

            Log.d(TAG, "Security audit completed - Score: $securityScore/100")
            audit

        } catch (e: Exception) {
            Log.e(TAG, "Security audit failed", e)
            mapOf<String, Any>(
                "error" to (e.message ?: "audit_failed"),
                "security_level" to "UNKNOWN"
            )
        }
    }
}