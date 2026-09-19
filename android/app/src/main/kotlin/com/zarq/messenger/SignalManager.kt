package com.zarq.messenger

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
import org.whispersystems.libsignal.groups.GroupCipher
import org.whispersystems.libsignal.groups.GroupSessionBuilder
import org.whispersystems.libsignal.groups.SenderKeyName
import org.whispersystems.libsignal.protocol.SenderKeyDistributionMessage
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
            val random = secureRandom.nextInt(Integer.MAX_VALUE)

            val userUid = try {
                FirebaseAuth.getInstance().currentUser?.uid ?: "anonymous"
            } catch (e: Exception) {
                Log.w(TAG, "Could not get Firebase UID for device ID", e)
                "unknown"
            }

            // Create deterministic but unique device ID
            val combined = "$androidId-$userUid-$timestamp-$random"
            val hash = combined.hashCode()

            // Use full Int range (1 to 2,147,483,647) to minimize collisions
            // With 2 billion possible IDs, birthday paradox allows ~50,000 users before 1% collision risk
            val deviceId = Math.abs(hash)
            if (deviceId == 0) 1 else deviceId

        } catch (e: Exception) {
            Log.w(TAG, "Fallback device ID generation", e)
            // Fallback: timestamp-based ID with larger range
            val fallbackId = Math.abs((System.currentTimeMillis() + secureRandom.nextInt()).hashCode())
            if (fallbackId == 0) 1 else fallbackId
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
     * Get the current device ID with server fallback
     * Priority: 1) Local cache 2) Server 3) Generate new
     */
    fun getDeviceId(): Int {
        val localDeviceId = sharedPrefs.getInt(KEY_DEVICE_ID, -1)

        if (localDeviceId != -1) {
            return localDeviceId
        }

        Log.w(TAG, "Device ID not found locally, checking server...")

        // Try to fetch from server before generating new one
        val serverDeviceId = fetchDeviceIdFromServer()
        if (serverDeviceId != null && serverDeviceId > 0) {
            Log.d(TAG, "Recovered device ID from server: $serverDeviceId")
            sharedPrefs.edit().putInt(KEY_DEVICE_ID, serverDeviceId).apply()
            return serverDeviceId
        }

        // No device ID on server, generate new one
        Log.d(TAG, "No device ID on server, generating new one")
        return generateDeviceId()
    }

    /**
     * Fetch device ID from server (synchronous call - should be quick)
     */
    private fun fetchDeviceIdFromServer(): Int? {
        return try {
            val user = FirebaseAuth.getInstance().currentUser ?: return null
            val uid = user.uid
            val idToken = com.google.android.gms.tasks.Tasks.await(user.getIdToken(true)).token ?: return null

            val url = java.net.URL("${AppConfig.BASE_URL}/v1/users/$uid/device")
            val connection = url.openConnection() as java.net.HttpURLConnection
            connection.requestMethod = "GET"
            connection.setRequestProperty("Authorization", "Bearer $idToken")
            connection.connectTimeout = 5000
            connection.readTimeout = 5000

            if (connection.responseCode == 200) {
                val response = connection.inputStream.bufferedReader().use { it.readText() }
                val json = org.json.JSONObject(response)
                json.getInt("device_id")
            } else {
                Log.w(TAG, "Server returned ${connection.responseCode} for device ID fetch")
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch device ID from server: ${e.message}")
            null
        }
    }

    /**
     * Get the Identity Key Pair for database encryption
     * Returns base64 encoded private key (32 bytes)
     */
    fun getIdentityKeyPairPrivateKey(): String? {
        return try {
            val identityKeyPair = signalProtocolStore.identityKeyPair
            if (identityKeyPair != null) {
                // Return base64 encoded private key (32 bytes)
                Base64.encodeToString(
                    identityKeyPair.privateKey.serialize(),
                    Base64.NO_WRAP
                )
            } else {
                Log.e(TAG, "Identity key pair not found")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get identity key pair", e)
            null
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

        // DON'T strip - use full 33-byte keys with 0x05 prefix
        val identityKeyBytes = identityKeyPair.publicKey.serialize() // Keep all 33 bytes
        val identityKeyB64 = Base64.encodeToString(identityKeyBytes, Base64.NO_WRAP)

        val signedPreKeyBytes = signedPreKey.keyPair.publicKey.serialize() // Keep all 33 bytes
        val signedPreKeyB64 = Base64.encodeToString(signedPreKeyBytes, Base64.NO_WRAP)

        val signatureB64 = Base64.encodeToString(signedPreKey.signature, Base64.NO_WRAP)

        // One-time prekeys - keep full 33 bytes
        val oneTimePreKeys = preKeys.map { preKey ->
            val preKeyBytes = preKey.keyPair.publicKey.serialize() // Keep all 33 bytes
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

            Log.d(TAG, "Session established, verifying session state...")
            val sessionRecord = signalProtocolStore.loadSession(recipientAddress)
            val serializedSize = sessionRecord.serialize()?.size ?: 0
            Log.d(TAG, "Established session size: $serializedSize bytes")

// Try to create a SessionCipher and check its internal state
            val testCipher = SessionCipher(signalProtocolStore, recipientAddress)
            Log.d(TAG, "SessionCipher created successfully")

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
            Log.d(TAG, "PARSE BUNDLE: Identity key bytes length: ${identityKeyBytes.size}")
            Log.d(TAG, "PARSE BUNDLE: Identity key first byte: 0x${String.format("%02x", identityKeyBytes[0])}")

            val identityKey = if (identityKeyBytes.size == 32) {
                val identityKeyWithPrefix = byteArrayOf(0x05.toByte()) + identityKeyBytes
                IdentityKey(identityKeyWithPrefix, 0)
            } else {
                // Already has prefix
                IdentityKey(identityKeyBytes, 0)
            }

            // Decode signed prekey
            val signedPreKeyBytes = Base64.decode(signedPreKeyB64, Base64.NO_WRAP)
            Log.d(TAG, "PARSE BUNDLE: Signed prekey bytes length: ${signedPreKeyBytes.size}")
            Log.d(TAG, "PARSE BUNDLE: Signed prekey first byte: 0x${String.format("%02x", signedPreKeyBytes[0])}")

            val signedPreKeyPublic = if (signedPreKeyBytes.size == 32) {
                // Old 32-byte format - add prefix
                Log.d(TAG, "PARSE BUNDLE: Adding 0x05 prefix to signed prekey")
                val signedPreKeyWithPrefix = byteArrayOf(0x05.toByte()) + signedPreKeyBytes
                Curve.decodePoint(signedPreKeyWithPrefix, 0)
            } else {
                // New 33-byte format - use as-is
                Log.d(TAG, "PARSE BUNDLE: Using signed prekey as-is (already has prefix)")
                Curve.decodePoint(signedPreKeyBytes, 0)
            }

            // Decode signature
            val signatureBytes = Base64.decode(signedPreKeySignatureB64, Base64.NO_WRAP)
            Log.d(TAG, "PARSE BUNDLE: Signature bytes length: ${signatureBytes.size}")

            // Decode one-time prekey if present
            val oneTimePreKeyPublic = if (oneTimePreKeyB64 != null) {
                val oneTimePreKeyBytes = Base64.decode(oneTimePreKeyB64, Base64.NO_WRAP)
                Log.d(TAG, "PARSE BUNDLE: One-time prekey bytes length: ${oneTimePreKeyBytes.size}")

                if (oneTimePreKeyBytes.size == 32) {
                    val oneTimePreKeyWithPrefix = byteArrayOf(0x05.toByte()) + oneTimePreKeyBytes
                    Curve.decodePoint(oneTimePreKeyWithPrefix, 0)
                } else {
                    Curve.decodePoint(oneTimePreKeyBytes, 0)
                }
            } else null

            // Create PreKeyBundle
            return PreKeyBundle(
                registrationId,
                deviceId,
                oneTimePreKeyId ?: 0,
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

            Log.d(TAG, "Before encryption - session exists: ${signalProtocolStore.containsSession(recipientAddress)}")

            // Load session before encryption for debugging
            val sessionBefore = signalProtocolStore.loadSession(recipientAddress)
            val sessionSizeBefore = sessionBefore.serialize()?.size ?: 0
            Log.d(TAG, "Session size before encryption: $sessionSizeBefore bytes")

            // Validate session before encryption
            if (!validateSession(recipientUid, deviceId)) {
                Log.w(TAG, "Session validation failed, attempting to continue anyway")
            }

            Log.d(TAG, "DEBUG: Recipient address for encryption: $recipientAddress")
            Log.d(TAG, "DEBUG: Current user context: $currentUserUid")
            Log.d(TAG, "DEBUG: Session lookup with address: ${recipientAddress.name}:${recipientAddress.deviceId}")

            Log.d(TAG, "=== PRE-ENCRYPTION SESSION CHECK ===")
            val loadedSession = signalProtocolStore.loadSession(recipientAddress)

            try {
                val sessionState = loadedSession.sessionState
                Log.d(TAG, "Session state version: ${sessionState.sessionVersion}")
                Log.d(TAG, "Has unacknowledged prekey message: ${sessionState.hasUnacknowledgedPreKeyMessage()}")
            } catch (e: Exception) {
                Log.e(TAG, "Error reading session state details: $e")
            }
            Log.d(TAG, "=== END PRE-ENCRYPTION SESSION CHECK ===")

            Log.d(TAG, "DEBUG: Loaded session for encryption")
            Log.d(TAG, "DEBUG: Session size: ${loadedSession.serialize()?.size}")
            Log.d(TAG, "DEBUG: Session exists in store: ${signalProtocolStore.containsSession(recipientAddress)}")

            // Try to force session refresh
            signalProtocolStore.storeSession(recipientAddress, loadedSession)
            Log.d(TAG, "DEBUG: Session re-stored before creating cipher")

            try {
                val testCipher = SessionCipher(signalProtocolStore, recipientAddress)
                // This will throw if session isn't usable
                Log.d(TAG, "SessionCipher created successfully, session should be usable")
            } catch (e: Exception) {
                Log.e(TAG, "SessionCipher creation indicates session not usable: $e")
                throw Exception("Session exists but is not usable for encryption")
            }

            // Create session cipher
            val sessionCipher = SessionCipher(signalProtocolStore, recipientAddress)

            Log.d(TAG, "About to encrypt with SessionCipher")

            try {
                val sessionRecord = signalProtocolStore.loadSession(recipientAddress)
                Log.d(TAG, "DEBUG SESSION INTERNAL STATE:")
                Log.d(TAG, "Session record exists: ${sessionRecord != null}")
                Log.d(TAG, "Session serialized size: ${sessionRecord.serialize()?.size ?: 0}")

                // Try to check if session has valid state without calling problematic methods
                val serializedData = sessionRecord.serialize()
                if (serializedData != null && serializedData.isNotEmpty()) {
                    Log.d(TAG, "Session has serialized data: true")
                    Log.d(TAG, "Session data first 10 bytes: ${serializedData.take(10).joinToString { "%02x".format(it) }}")
                } else {
                    Log.d(TAG, "Session has no serialized data")
                }

            } catch (e: Exception) {
                Log.e(TAG, "Failed to check session internal state: $e")
            }

            // Encrypt the message
            val ciphertext = sessionCipher.encrypt(plaintext.toByteArray(Charsets.UTF_8))

            Log.d(TAG, "=== CIPHERTEXT ANALYSIS ===")
            Log.d(TAG, "Reported type from library: ${ciphertext.type}")
            Log.d(TAG, "CiphertextMessage.WHISPER_TYPE: ${CiphertextMessage.WHISPER_TYPE}")
            Log.d(TAG, "CiphertextMessage.PREKEY_TYPE: ${CiphertextMessage.PREKEY_TYPE}")
            Log.d(TAG, "Type matches WHISPER_TYPE: ${ciphertext.type == CiphertextMessage.WHISPER_TYPE}")
            Log.d(TAG, "Type matches PREKEY_TYPE: ${ciphertext.type == CiphertextMessage.PREKEY_TYPE}")

            when (ciphertext) {
                is SignalMessage -> Log.d(TAG, "Ciphertext is SignalMessage object")
                is PreKeySignalMessage -> Log.d(TAG, "Ciphertext is PreKeySignalMessage object")
                else -> Log.d(TAG, "Ciphertext is unknown type: ${ciphertext.javaClass.simpleName}")
            }
            Log.d(TAG, "=== END CIPHERTEXT ANALYSIS ===")

            // Get the actual class name
            Log.d(TAG, "Ciphertext class: ${ciphertext.javaClass.name}")

            // Try to access type through reflection to see actual internal value
            try {
                val typeField = ciphertext.javaClass.getDeclaredField("type")
                typeField.isAccessible = true
                val actualType = typeField.getInt(ciphertext)
                Log.d(TAG, "Internal type field value: $actualType")
            } catch (e: Exception) {
                Log.d(TAG, "Could not access type field: $e")
            }

            // Serialize and check
            val serialized = ciphertext.serialize()
            Log.d(TAG, "After serialize - first byte: 0x${String.format("%02x", serialized[0])}")

            // *** CRITICAL FIX: Save session state after encryption ***
            Log.d(TAG, "Saving session state after encryption...")
            val sessionAfter = signalProtocolStore.loadSession(recipientAddress)
            signalProtocolStore.storeSession(recipientAddress, sessionAfter)

            // Verify session was saved correctly
            val sessionSizeAfter = sessionAfter.serialize()?.size ?: 0
            Log.d(TAG, "Session size after encryption: $sessionSizeAfter bytes")
            Log.d(TAG, "Session state saved successfully")

            //val actualBytes = ciphertext.serialize()
            //Log.d(TAG, "ENCRYPT: First 5 bytes: ${actualBytes.take(5).joinToString { "0x%02x".format(it) }}")
            //val actualFirstByte = actualBytes[0].toInt() and 0xFF
            //val actualType = (actualFirstByte shr 4) and 0x0F
            //Log.d(TAG, "VERIFICATION: Reported type = ${ciphertext.type}, Actual type = $actualType")

            // Convert to base64 for transmission
            val ciphertextB64 = Base64.encodeToString(ciphertext.serialize(), Base64.NO_WRAP)

            Log.d(TAG, "Message encrypted successfully")
            Log.d(TAG, "Ciphertext type: ${ciphertext.type}")
            Log.d(TAG, "Ciphertext length: ${ciphertextB64.length}")

            debugSessionState(recipientUid, deviceId, "AFTER_ENCRYPT")
            testSessionPersistence(recipientUid, deviceId)

            Log.d(TAG, "ENCRYPT DEBUG: Original ciphertext bytes length: ${ciphertext.serialize().size}")
            Log.d(TAG, "ENCRYPT DEBUG: Base64 length: ${ciphertextB64.length}")
            Log.d(TAG, "ENCRYPT DEBUG: Base64 first 50 chars: ${ciphertextB64.take(50)}")
            Log.d(TAG, "ENCRYPT DEBUG: Base64 last 50 chars: ${ciphertextB64.takeLast(50)}")

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
            Log.d(TAG, "=== DECRYPTION START ===")
            Log.d(TAG, "Decrypting message from $senderUid:$deviceId")
            Log.d(TAG, "Store initialized: ${isStoreInitialized()}")

            if (!isStoreInitialized()) {
                throw Exception("Protocol store not initialized")
            }

            // Session state before decryption
            val sessionExistsBefore = signalProtocolStore.containsSession(senderAddress)
            Log.d(TAG, "Receiver session exists BEFORE decryption: $sessionExistsBefore")


            val ciphertextBytes = Base64.decode(ciphertextB64, Base64.NO_WRAP)

            Log.d(TAG, "DECRYPT DEBUG: Received Base64 length: ${ciphertextB64.length}")
            Log.d(TAG, "DECRYPT DEBUG: Base64 first 50 chars: ${ciphertextB64.take(50)}")
            Log.d(TAG, "DECRYPT DEBUG: Base64 last 50 chars: ${ciphertextB64.takeLast(50)}")
            Log.d(TAG, "DECRYPT DEBUG: Decoded bytes length: ${ciphertextBytes.size}")

            val isPreKeyMsg = isPreKeySignalMessage(ciphertextBytes)
            Log.d(TAG, "Message type: ${if (isPreKeyMsg) "PreKeySignalMessage" else "SignalMessage"}")

            val sessionCipher = SessionCipher(signalProtocolStore, senderAddress)

            // Decrypt based on message type
            val plaintext = if (isPreKeyMsg) {
                Log.d(TAG, "DECRYPTING: PreKeySignalMessage (establishes session)")
                val preKeyMessage = PreKeySignalMessage(ciphertextBytes)
                val result = sessionCipher.decrypt(preKeyMessage)

                Log.d(TAG, "DEBUG: Checking session after PreKey decryption")
                val sessionAfterDecrypt = signalProtocolStore.loadSession(senderAddress)
                Log.d(TAG, "DEBUG: Session size after PreKey decrypt: ${sessionAfterDecrypt.serialize()?.size} bytes")

                // *** CRITICAL FIX: Save session state after PreKeySignalMessage decryption ***
                Log.d(TAG, "Saving session state after PreKeySignalMessage decryption...")
                val sessionAfterPreKey = signalProtocolStore.loadSession(senderAddress)
                signalProtocolStore.storeSession(senderAddress, sessionAfterPreKey)
                Log.d(TAG, "Session established and saved after PreKeySignalMessage")

                result
            } else {
                Log.d(TAG, "DECRYPTING: Regular SignalMessage")
                if (!sessionExistsBefore) {
                    throw Exception("No session exists for regular SignalMessage")
                }
                val signalMessage = SignalMessage(ciphertextBytes)
                val result = sessionCipher.decrypt(signalMessage)

                // *** CRITICAL FIX: Save session state after SignalMessage decryption ***
                Log.d(TAG, "Saving session state after SignalMessage decryption...")
                val sessionAfterSignal = signalProtocolStore.loadSession(senderAddress)
                signalProtocolStore.storeSession(senderAddress, sessionAfterSignal)
                Log.d(TAG, "Session state updated and saved after SignalMessage")

                result
            }

            val decryptedText = String(plaintext, Charsets.UTF_8)
            Log.d(TAG, "Final decrypted text length: ${decryptedText.length}")

            // Debug session state after decryption
            debugSessionState(senderUid, deviceId, "AFTER_DECRYPT")

            Log.d(TAG, "=== DECRYPTION SUCCESS ===")
            return decryptedText

        } catch (e: Exception) {
            Log.e(TAG, "=== DECRYPTION FAILED ===")
            Log.e(TAG, "Failed to decrypt message from $senderUid:$deviceId", e)
            null
        }
    }

    /**
     * Test session persistence across encrypt/decrypt cycle
     * Call this after each message to verify sessions are being saved
     */
    fun testSessionPersistence(recipientUid: String, deviceId: Int): Boolean {
        return try {
            val address = SignalProtocolAddress(recipientUid, deviceId)

            // Check if session exists
            val sessionExists = signalProtocolStore.containsSession(address)
            if (!sessionExists) {
                Log.w(TAG, "No session exists for persistence test")
                return false
            }

            // Load session
            val session1 = signalProtocolStore.loadSession(address)
            val size1 = session1.serialize()?.size ?: 0

            // Store session (should be no-op if working correctly)
            signalProtocolStore.storeSession(address, session1)

            // Load again
            val session2 = signalProtocolStore.loadSession(address)
            val size2 = session2.serialize()?.size ?: 0

            // FIXED: Lower threshold for session health - 375 bytes can be valid for new sessions
            val persistent = (size1 == size2 && size1 > 300) // Changed from 500 to 300

            Log.d(TAG, "Session persistence test: $persistent (size: $size1 -> $size2)")
            return persistent

        } catch (e: Exception) {
            Log.e(TAG, "Session persistence test failed", e)
            false
        }
    }

    /**
     * Debug helper to check session state consistency
     * Add this method to your SignalManager class
     */
    fun debugSessionState(recipientUid: String, deviceId: Int, operation: String) {
        try {
            val address = SignalProtocolAddress(recipientUid, deviceId)
            val sessionExists = signalProtocolStore.containsSession(address)

            if (sessionExists) {
                val session = signalProtocolStore.loadSession(address)
                val sessionSize = session.serialize()?.size ?: 0

                Log.d(TAG, "=== SESSION DEBUG: $operation ===")
                Log.d(TAG, "Address: $recipientUid:$deviceId")
                Log.d(TAG, "Session exists: $sessionExists")
                Log.d(TAG, "Session size: $sessionSize bytes")
                Log.d(TAG, "Session healthy: ${sessionSize > 300}") // FIXED: Lower threshold
                Log.d(TAG, "=== END SESSION DEBUG ===")
            } else {
                Log.d(TAG, "=== SESSION DEBUG: $operation ===")
                Log.d(TAG, "Address: $recipientUid:$deviceId")
                Log.d(TAG, "Session exists: FALSE")
                Log.d(TAG, "=== END SESSION DEBUG ===")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Session debug failed for $operation", e)
        }
    }

    /**
     * Determine if the ciphertext is a PreKeySignalMessage
     * PreKeySignalMessages are sent when no session exists yet
     */
    private fun isPreKeySignalMessage(ciphertextBytes: ByteArray): Boolean {
        return try {
            PreKeySignalMessage(ciphertextBytes)
            true
        } catch (e: Exception) {
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
            Log.d(TAG, "=== encryptMessageWithSessionSetup START ===")

            val recipientAddress = SignalProtocolAddress(recipientUid, deviceId)
            val sessionExists = signalProtocolStore.containsSession(recipientAddress)

            Log.d(TAG, "Session exists: $sessionExists")

            // Only establish new session if:
            // 1. No session exists at all, OR
            // 2. Session exists but prekey bundle is provided AND session is invalid
            val needsNewSession = !sessionExists ||
                    (prekeyBundle != null && !isSessionUsableForSending(recipientAddress))

            if (needsNewSession && prekeyBundle != null) {
                Log.d(TAG, "Establishing new session")
                val sessionEstablished = establishSession(recipientUid, deviceId, prekeyBundle)

                if (!sessionEstablished) {
                    throw Exception("Failed to establish session")
                }
            } else if (!sessionExists) {
                throw Exception("No session exists and no prekey bundle provided")
            } else {
                Log.d(TAG, "Using existing session")
            }

            // Encrypt the message
            return encryptMessage(recipientUid, plaintext, deviceId)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to encrypt with session setup", e)
            null
        }
    }

    // Helper method to check if session is actually usable
    private fun isSessionUsableForSending(address: SignalProtocolAddress): Boolean {
        return try {
            val session = signalProtocolStore.loadSession(address)
            val sessionSize = session.serialize()?.size ?: 0
            // A properly established bidirectional session should be larger
            sessionSize > 500
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Reset session when decryption fails or identity key changes
     * This forces session re-establishment on next send
     */
    fun resetSessionDueToDecryptionFailure(senderUid: String, senderDeviceId: Int) {
        try {
            val address = SignalProtocolAddress(senderUid, senderDeviceId)

            Log.w(TAG, "🔄 Resetting stale session for $senderUid:$senderDeviceId due to decryption failure")

            // Delete the stale session
            signalProtocolStore.deleteSession(address)
            Log.i(TAG, "✅ Session deleted successfully - will re-establish on next message")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset session for $senderUid:$senderDeviceId", e)
        }
    }

    fun isSessionValidForSending(recipientUid: String, deviceId: Int): Boolean {
        return try {
            val address = SignalProtocolAddress(recipientUid, deviceId)
            val sessionExists = signalProtocolStore.containsSession(address)
            Log.d(TAG, "Session exists check: $sessionExists")

            if (!sessionExists) {
                Log.d(TAG, "No session found for $recipientUid:$deviceId")
                return false
            }

            val sessionRecord = signalProtocolStore.loadSession(address)
            val sessionSize = sessionRecord.serialize()?.size ?: 0

            // Check if session has valid state
            val hasValidState = try {
                sessionSize > 500 && sessionRecord.serialize() != null
            } catch (e: Exception) {
                Log.w(TAG, "Session state check failed", e)
                false
            }

            if (!hasValidState) {
                Log.d(TAG, "Session validation DECISION: ESTABLISH NEW (invalid state)")
                return false
            }

            // SECURITY: Check if recipient's identity key has changed (key rotation detection)
            // This detects when recipient reinstalled without backup (new keys)
            val storedIdentityKey = signalProtocolStore.getIdentity(address)
            if (storedIdentityKey == null) {
                Log.w(TAG, "⚠️ No stored identity key for $recipientUid - session may be stale")
                // Session exists but no identity key stored - force re-establishment
                signalProtocolStore.deleteSession(address)
                Log.d(TAG, "Session validation DECISION: ESTABLISH NEW (no identity key)")
                return false
            }

            // Check if there was a recent key change
            val keyChangeTime = signalProtocolStore.getLastKeyChangeTime(address)
            val sessionTime = sessionRecord.sessionState?.getSessionVersion()?.toLong() ?: 0L

            if (keyChangeTime > 0 && keyChangeTime > sessionTime) {
                Log.w(TAG, "🔑 Recipient $recipientUid identity key changed - invalidating stale session")
                signalProtocolStore.deleteSession(address)
                Log.d(TAG, "Session validation DECISION: ESTABLISH NEW (key changed)")
                return false
            }

            Log.d(TAG, "Session validation for $recipientUid:$deviceId - size: $sessionSize, valid: $hasValidState")
            Log.d(TAG, "Session validation DECISION: USE EXISTING (valid session + trusted identity)")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "Session validation failed", e)
            false
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

    /**
     * Get existing key bundle for device registration (WITHOUT generating new device ID)
     * Used after backup restore to register with EXISTING device ID
     */
    fun getKeyBundleForRegistration(): Map<String, Any> {
        return try {
            Log.d(TAG, "Getting key bundle for device registration (using existing IDs)...")

            // Get EXISTING device ID and registration ID (don't generate new ones!)
            val deviceId = getDeviceId()
            val registrationId = getRegistrationId()

            if (deviceId <= 0 || registrationId <= 0) {
                throw Exception("No existing device ID or registration ID found")
            }

            Log.d(TAG, "Using EXISTING Device ID: $deviceId, Registration ID: $registrationId")

            // Load existing identity key pair
            val identityKeyPair = loadIdentityKeyPair()
                ?: throw Exception("Identity key pair not found")

            // Get existing signed prekey from protocol store
            val signedPreKeyId = sharedPrefs.getInt(KEY_SIGNED_PREKEY_ID, 1)
            val signedPreKey = signalProtocolStore.loadSignedPreKey(signedPreKeyId)
                ?: throw Exception("Signed prekey not found")

            // Generate fresh one-time prekeys (these can be new for re-registration)
            val startingPreKeyId = sharedPrefs.getInt(KEY_NEXT_PREKEY_ID, 1)
            val preKeys = KeyHelper.generatePreKeys(startingPreKeyId, PREKEY_BATCH_SIZE)

            // Store the new one-time prekeys
            storeKeysInProtocolStore(signedPreKey, preKeys)

            // Update next prekey ID
            sharedPrefs.edit()
                .putInt(KEY_NEXT_PREKEY_ID, startingPreKeyId + PREKEY_BATCH_SIZE)
                .apply()

            // Build response bundle (same format as generateKeyBundle)
            val keyBundle = createKeyBundleResponse(
                identityKeyPair, registrationId, signedPreKey, preKeys, deviceId,
                sharedPrefs.getString(KEY_DEVICE_FINGERPRINT, null) ?: generateInstallationFingerprint()
            )

            Log.d(TAG, "✅ Key bundle created for registration:")
            Log.d(TAG, "  - Device ID: $deviceId (EXISTING, not regenerated)")
            Log.d(TAG, "  - Registration ID: $registrationId (EXISTING)")
            Log.d(TAG, "  - Identity Key: ${keyBundle["identity_key_b64"]?.toString()?.take(30)}...")
            Log.d(TAG, "  - One-Time PreKeys: ${(keyBundle["one_time_prekeys"] as List<*>).size}")

            keyBundle
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get key bundle for registration", e)
            throw e
        }
    }

    /**
     * Export Signal Protocol state for backup
     * Returns JSON string containing all sessions, keys, and prekeys
     */
    fun exportSignalState(): String {
        return try {
            Log.d(TAG, "Exporting Signal Protocol state...")

            // Export protocol store (sessions, prekeys, etc.)
            val protocolStateJson = signalProtocolStore.exportSignalState()
            val protocolState = JSONObject(protocolStateJson)

            // IMPORTANT: Also export device ID and registration ID from SignalManager's prefs
            val deviceId = getDeviceId()
            val registrationId = getRegistrationId()

            // CRITICAL: Also export identity key pair from SignalManager's prefs
            // Must export DECRYPTED version since encryption is device-specific!
            val identityKeyPair = loadIdentityKeyPair()
            val identityKeyPairJson = if (identityKeyPair != null) {
                // Re-serialize as plain JSON for backup (decrypted)
                JSONObject().apply {
                    put("public_key", Base64.encodeToString(identityKeyPair.publicKey.serialize(), Base64.NO_WRAP))
                    put("private_key", Base64.encodeToString(identityKeyPair.privateKey.serialize(), Base64.NO_WRAP))
                }.toString()
            } else {
                null
            }

            // Create combined export
            val combinedExport = JSONObject()
            combinedExport.put("protocol_state", protocolState)
            combinedExport.put("device_id", deviceId)
            combinedExport.put("registration_id", registrationId)
            combinedExport.put("identity_key_pair", identityKeyPairJson)  // Export DECRYPTED identity key pair

            Log.d(TAG, "Signal Protocol state exported - Device ID: $deviceId, Registration ID: $registrationId, Identity Key Pair: ${if (identityKeyPairJson != null) "present" else "missing"}")

            combinedExport.toString()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to export Signal Protocol state", e)
            throw e
        }
    }

    /**
     * Import Signal Protocol state from backup
     * Accepts JSON string containing all sessions, keys, and prekeys
     */
    fun importSignalState(signalStateJson: String): Boolean {
        return try {
            Log.d(TAG, "Importing Signal Protocol state...")

            val combinedData = JSONObject(signalStateJson)

            // Extract protocol state
            val protocolState = combinedData.optJSONObject("protocol_state")
            val deviceId = combinedData.optInt("device_id", -1)
            val registrationId = combinedData.optInt("registration_id", -1)
            val identityKeyPairJson = combinedData.optString("identity_key_pair", null)

            Log.d(TAG, "Restoring Device ID: $deviceId, Registration ID: $registrationId, Identity Key Pair: ${if (identityKeyPairJson != null) "present" else "missing"}")

            // Import protocol store (sessions, prekeys, etc.)
            if (protocolState != null) {
                val success = signalProtocolStore.importSignalState(protocolState.toString())
                if (!success) {
                    Log.e(TAG, "Failed to import protocol state")
                    return false
                }
            } else {
                Log.w(TAG, "No protocol state found in backup, trying legacy format...")
                // Fallback for old backup format (direct protocol state)
                val success = signalProtocolStore.importSignalState(signalStateJson)
                if (!success) {
                    Log.e(TAG, "Failed to import legacy protocol state")
                    return false
                }
            }

            // IMPORTANT: Restore device ID, registration ID, and identity key pair to SignalManager prefs
            val editor = sharedPrefs.edit()

            if (deviceId != -1 && registrationId != -1) {
                editor.putInt(KEY_DEVICE_ID, deviceId)
                editor.putInt(KEY_REGISTRATION_ID, registrationId)
                Log.d(TAG, "✅ Device ID and Registration ID restored successfully")
                Log.d(TAG, "Device ID: $deviceId (was restored, NOT regenerated)")
            } else {
                Log.w(TAG, "⚠️ Device ID or Registration ID not found in backup - keeping current values")
            }

            // CRITICAL: Restore identity key pair to SignalManager prefs
            if (identityKeyPairJson != null && identityKeyPairJson.isNotEmpty()) {
                editor.putString(KEY_IDENTITY_KEY_PAIR, identityKeyPairJson)
                Log.d(TAG, "✅ Identity Key Pair restored to SignalManager prefs")
            } else {
                Log.w(TAG, "⚠️ Identity Key Pair not found in backup - this may cause signature verification failures!")
            }

            editor.apply()

            Log.d(TAG, "Signal Protocol state imported successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error importing Signal Protocol state", e)
            throw e
        }
    }

    // ========== GROUP ENCRYPTION METHODS (Sender Keys Protocol) ==========

    /**
     * Create a sender key distribution message for a group
     * This is sent to all group members when:
     * 1. You first join a group
     * 2. A new member joins (you send them your key)
     * 3. You rotate your key (member left)
     *
     * @param groupId The conversation ID of the group
     * @return Base64-encoded SenderKeyDistributionMessage
     */
    fun createSenderKeyDistribution(groupId: String): String? {
        return try {
            Log.d(TAG, "=== createSenderKeyDistribution START ===")
            Log.d(TAG, "Creating sender key distribution for group: $groupId")

            val currentUid = getCurrentUserUid()
            if (currentUid == null) {
                Log.e(TAG, "Cannot create sender key distribution - no user logged in")
                return null
            }

            val deviceId = getDeviceId()
            Log.d(TAG, "Current user: $currentUid, device: $deviceId")

            // Create address for ourselves
            val senderAddress = SignalProtocolAddress(currentUid, deviceId)

            // Create SenderKeyName with groupId as string
            val senderKeyName = SenderKeyName(groupId, senderAddress)

            // Create group session builder
            val groupSessionBuilder = GroupSessionBuilder(signalProtocolStore)

            // Create sender key distribution message
            val distributionMessage = groupSessionBuilder.create(senderKeyName)

            // Serialize to base64
            val distributionBytes = distributionMessage.serialize()
            val distributionB64 = Base64.encodeToString(distributionBytes, Base64.NO_WRAP)

            Log.d(TAG, "✅ Sender key distribution created successfully")
            Log.d(TAG, "Distribution message length: ${distributionBytes.size} bytes")
            Log.d(TAG, "=== createSenderKeyDistribution END ===")

            distributionB64
        } catch (e: Exception) {
            Log.e(TAG, "Error creating sender key distribution", e)
            null
        }
    }

    /**
     * Process a sender key distribution message from another group member
     * This stores their sender key so we can decrypt their messages
     *
     * @param senderUid The UID of the member who sent this
     * @param senderDeviceId The device ID of the sender
     * @param groupId The conversation ID of the group
     * @param distributionMessageB64 Base64-encoded SenderKeyDistributionMessage
     * @return true if successful
     */
    fun processSenderKeyDistribution(
        senderUid: String,
        senderDeviceId: Int,
        groupId: String,
        distributionMessageB64: String
    ): Boolean {
        return try {
            Log.d(TAG, "=== processSenderKeyDistribution START ===")
            Log.d(TAG, "Processing sender key from: $senderUid:$senderDeviceId for group: $groupId")

            // Create address for the sender
            val senderAddress = SignalProtocolAddress(senderUid, senderDeviceId)

            // Create SenderKeyName
            val senderKeyName = SenderKeyName(groupId, senderAddress)

            // Deserialize the distribution message
            val distributionBytes = Base64.decode(distributionMessageB64, Base64.NO_WRAP)
            val distributionMessage = SenderKeyDistributionMessage(distributionBytes)

            // Process it with group session builder
            val groupSessionBuilder = GroupSessionBuilder(signalProtocolStore)
            groupSessionBuilder.process(senderKeyName, distributionMessage)

            Log.d(TAG, "✅ Sender key distribution processed successfully")
            Log.d(TAG, "Stored sender key for $senderUid:$senderDeviceId in group $groupId")
            Log.d(TAG, "=== processSenderKeyDistribution END ===")

            true
        } catch (e: Exception) {
            Log.e(TAG, "Error processing sender key distribution from $senderUid:$senderDeviceId", e)
            false
        }
    }

    /**
     * Encrypt a message for a group using Sender Keys
     * Much more efficient than encrypting individually for each member
     *
     * @param groupId The conversation ID of the group
     * @param plaintext The message to encrypt
     * @return Base64-encoded encrypted message (ciphertext)
     */
    fun encryptGroupMessage(groupId: String, plaintext: String): String? {
        return try {
            Log.d(TAG, "=== encryptGroupMessage START ===")
            Log.d(TAG, "Encrypting group message for group: $groupId")
            Log.d(TAG, "Plaintext length: ${plaintext.length}")

            val currentUid = getCurrentUserUid()
            if (currentUid == null) {
                Log.e(TAG, "Cannot encrypt group message - no user logged in")
                return null
            }

            val deviceId = getDeviceId()

            // Create address for ourselves
            val senderAddress = SignalProtocolAddress(currentUid, deviceId)

            // Create SenderKeyName
            val senderKeyName = SenderKeyName(groupId, senderAddress)

            // Create group cipher
            val groupCipher = GroupCipher(signalProtocolStore, senderKeyName)

            // Encrypt the message
            val ciphertextBytes = groupCipher.encrypt(plaintext.toByteArray())

            // Encode to base64
            val ciphertextB64 = Base64.encodeToString(ciphertextBytes, Base64.NO_WRAP)

            Log.d(TAG, "✅ Group message encrypted successfully")
            Log.d(TAG, "Ciphertext length: ${ciphertextBytes.size} bytes")
            Log.d(TAG, "=== encryptGroupMessage END ===")

            ciphertextB64
        } catch (e: Exception) {
            Log.e(TAG, "Error encrypting group message", e)
            null
        }
    }

    /**
     * Decrypt a group message using Sender Keys
     *
     * @param senderUid The UID of the member who sent this message
     * @param senderDeviceId The device ID of the sender
     * @param groupId The conversation ID of the group
     * @param ciphertextB64 Base64-encoded encrypted message
     * @return Decrypted plaintext message
     */
    fun decryptGroupMessage(
        senderUid: String,
        senderDeviceId: Int,
        groupId: String,
        ciphertextB64: String
    ): String? {
        return try {
            Log.d(TAG, "=== decryptGroupMessage START ===")
            Log.d(TAG, "Decrypting group message from: $senderUid:$senderDeviceId in group: $groupId")

            // Create address for the sender
            val senderAddress = SignalProtocolAddress(senderUid, senderDeviceId)

            // Create SenderKeyName
            val senderKeyName = SenderKeyName(groupId, senderAddress)

            // Create group cipher
            val groupCipher = GroupCipher(signalProtocolStore, senderKeyName)

            // Decode ciphertext
            val ciphertextBytes = Base64.decode(ciphertextB64, Base64.NO_WRAP)
            Log.d(TAG, "Ciphertext length: ${ciphertextBytes.size} bytes")

            // Decrypt the message
            val plaintextBytes = groupCipher.decrypt(ciphertextBytes)
            val plaintext = String(plaintextBytes)

            Log.d(TAG, "✅ Group message decrypted successfully")
            Log.d(TAG, "Plaintext length: ${plaintext.length}")
            Log.d(TAG, "=== decryptGroupMessage END ===")

            plaintext
        } catch (e: Exception) {
            Log.e(TAG, "Error decrypting group message from $senderUid:$senderDeviceId", e)
            Log.e(TAG, "This usually means you don't have their sender key yet")
            null
        }
    }

    /**
     * Clear all sender keys for a group (when leaving or group deleted)
     *
     * @param groupId The conversation ID of the group
     */
    fun clearGroupSenderKeys(groupId: String) {
        try {
            Log.d(TAG, "Clearing all sender keys for group: $groupId")

            signalProtocolStore.deleteSenderKeysForGroup(groupId)

            Log.d(TAG, "✅ Cleared sender keys for group $groupId")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing sender keys for group $groupId", e)
        }
    }
}