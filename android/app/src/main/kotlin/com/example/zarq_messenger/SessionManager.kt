package com.example.zarq_messenger

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

class SessionManager(
    private val context: Context,
    private val uid: String,
    private val signalStore: SignalStore,
    private val protocolManager: SignalProtocolManager,
    private val preKeyManager: PreKeyManager
) {
    private val TAG = "SessionManager"

    // Track active sessions in memory
    private val activeSessions = ConcurrentHashMap<String, SessionInfo>()
    private val maxRetryAttempts = 3

    data class SessionInfo(
        val recipientUid: String,
        val deviceId: Int,
        val established: Boolean,
        val lastUsed: Long,
        val retryCount: Int = 0
    )

    /**
     * Initialize or recover a session with a recipient
     */
    suspend fun ensureSession(recipientUid: String, deviceId: Int = 1): Boolean = withContext(Dispatchers.IO) {
        val sessionKey = "$recipientUid:$deviceId"

        try {
            // Check if we have an active session
            val existingSession = activeSessions[sessionKey]
            if (existingSession?.established == true) {
                Log.d(TAG, "Using existing session for $recipientUid")
                return@withContext true
            }

            // Check if session exists in libsignal store
            if (hasLibsignalSession(recipientUid, deviceId)) {
                Log.d(TAG, "Found existing libsignal session for $recipientUid")
                activeSessions[sessionKey] = SessionInfo(recipientUid, deviceId, true, System.currentTimeMillis())
                return@withContext true
            }

            Log.d(TAG, "No session found, establishing new session for $recipientUid")
            return@withContext establishNewSession(recipientUid, deviceId)

        } catch (e: Exception) {
            Log.e(TAG, "ensureSession failed for $recipientUid: ${e.message}", e)
            return@withContext false
        }
    }

    /**
     * Establish a new session with basic error handling
     */
    private suspend fun establishNewSession(recipientUid: String, deviceId: Int): Boolean {
        val sessionKey = "$recipientUid:$deviceId"
        val currentSession = activeSessions[sessionKey]
        val retryCount = currentSession?.retryCount ?: 0

        Log.d(TAG, "establishNewSession: Starting for $recipientUid (attempt ${retryCount + 1})")

        if (retryCount >= maxRetryAttempts) {
            Log.e(TAG, "establishNewSession: Max retry attempts reached for $recipientUid")
            return false
        }

        try {
            // Ensure prekeys
            Log.d(TAG, "establishNewSession: Ensuring prekeys...")
            preKeyManager.ensureOneTimePreKeys()

            // Fetch bundle
            Log.d(TAG, "establishNewSession: Fetching prekey bundle for $recipientUid...")
            val bundle = fetchPrekeyBundleWithRetry(recipientUid, deviceId)
            if (bundle == null) {
                Log.e(TAG, "establishNewSession: FAILED - No prekey bundle for $recipientUid")
                return false
            }
            Log.d(TAG, "establishNewSession: Bundle fetched successfully, length: ${bundle.length}")

            // Initialize session
            Log.d(TAG, "establishNewSession: Initializing session with bundle...")
            val success = protocolManager.initSessionWithBundle(uid, recipientUid, bundle)
            Log.d(TAG, "establishNewSession: Session init result: $success")

            if (success) {
                activeSessions[sessionKey] = SessionInfo(recipientUid, deviceId, true, System.currentTimeMillis())
                Log.d(TAG, "establishNewSession: SUCCESS - Session established with $recipientUid")
                return true
            } else {
                activeSessions[sessionKey] = SessionInfo(recipientUid, deviceId, false, System.currentTimeMillis(), retryCount + 1)
                return false
            }

        } catch (e: Exception) {
            Log.e(TAG, "establishNewSession: EXCEPTION for $recipientUid: ${e.message}", e)
            activeSessions[sessionKey] = SessionInfo(recipientUid, deviceId, false, System.currentTimeMillis(), retryCount + 1)
            return false
        }
    }

    /**
     * Simple session clearing
     */
    suspend fun clearSession(recipientUid: String, deviceId: Int) = withContext(Dispatchers.IO) {
        val sessionKey = "$recipientUid:$deviceId"

        try {
            Log.d(TAG, "clearSession: Clearing session for $recipientUid:$deviceId")

            // Remove from memory
            activeSessions.remove(sessionKey)

            // Remove from storage using LibsignalStore
            val libStore = LibsignalStore(context, signalStore, uid)
            val address = org.whispersystems.libsignal.SignalProtocolAddress(recipientUid, deviceId)
            libStore.deleteSession(address)

            Log.d(TAG, "clearSession: Session cleared for $recipientUid:$deviceId")

        } catch (e: Exception) {
            Log.e(TAG, "clearSession failed for $recipientUid:$deviceId: ${e.message}", e)
        }
    }

    /**
     * Clear all sessions
     */
    suspend fun clearAllSessions() = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "clearAllSessions: Starting for $uid")

            // Clear memory
            activeSessions.clear()

            // Clear storage using LibsignalStore
            val libStore = LibsignalStore(context, signalStore, uid)

            // Get all recipients from memory (limited but better than nothing)
            val allRecipients = mutableSetOf<String>()
            // Since we cleared memory, we'll just clear the current user's storage
            signalStore.clearAll(uid)

            Log.d(TAG, "clearAllSessions: Completed for $uid")

        } catch (e: Exception) {
            Log.e(TAG, "clearAllSessions failed: ${e.message}", e)
        }
    }

    /**
     * Check if session exists in libsignal store
     */
    private fun hasLibsignalSession(recipientUid: String, deviceId: Int): Boolean {
        return try {
            val libStore = LibsignalStore(context, signalStore, uid)
            val address = org.whispersystems.libsignal.SignalProtocolAddress(recipientUid, deviceId)
            libStore.containsSession(address)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking session existence: ${e.message}", e)
            false
        }
    }

    /**
     * Fetch prekey bundle with retry logic
     */
    private suspend fun fetchPrekeyBundleWithRetry(recipientUid: String, deviceId: Int, maxRetries: Int = 2): String? {
        Log.d(TAG, "fetchPrekeyBundleWithRetry: Starting for $recipientUid:$deviceId")

        for (attempt in 1..maxRetries) {
            try {
                val activity = context as? MainActivity
                if (activity == null) {
                    Log.e(TAG, "Context is not MainActivity")
                    return null
                }

                val bundleMap = activity.fetchPrekeyBundle(recipientUid, deviceId)
                if (bundleMap != null) {
                    val jsonObject = org.json.JSONObject()
                    bundleMap.forEach { (key, value) ->
                        when (value) {
                            is Map<*, *> -> {
                                val nestedJson = org.json.JSONObject()
                                (value as Map<String, Any>).forEach { (nestedKey, nestedValue) ->
                                    nestedJson.put(nestedKey, nestedValue)
                                }
                                jsonObject.put(key, nestedJson)
                            }
                            else -> jsonObject.put(key, value)
                        }
                    }
                    return jsonObject.toString()
                }

            } catch (e: Exception) {
                Log.w(TAG, "Attempt $attempt failed: ${e.message}", e)
            }
        }

        return null
    }

    /**
     * Get basic session statistics
     */
    fun getSessionStats(): Map<String, Any> {
        return mapOf(
            "activeSessionCount" to activeSessions.size,
            "activeSessions" to activeSessions.keys.toList(),
            "preKeyCount" to signalStore.listPreKeyIds(uid).size,
            "signedPreKeyCount" to signalStore.listSignedPreKeyIds(uid).size
        )
    }
}