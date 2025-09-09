package com.example.zarq_messenger

import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.random.Random

/**
 * PreKeyManager - manages one-time prekeys and signed-prekey rotation.
 *
 * Uses SignalProtocolManager to generate keys and SignalStore to persist public blobs.
 * This class does NOT contact server itself; caller should upload bundles returned by exportPreKeyBundle().
 */
class PreKeyManager(
  private val context: android.content.Context,
  private val uid: String,
  private val signalStore: SignalStore,
  private val protocolManager: SignalProtocolManager
) {
  private val TAG = "PreKeyManager"

  // Configuration: refill threshold and batch size.
  private val oneTimeThreshold = 10
  private val oneTimeBatch = 50
  private val signedPreKeyIdRangeStart = 1000

  /**
   * Ensure we have enough one-time prekeys locally. Generates more if below threshold.
   * Returns true if no error.
   */
  suspend fun ensureOneTimePreKeys(): Boolean = withContext(Dispatchers.IO) {
    try {
      val ids = signalStore.listPreKeyIds(uid)
      if (ids.size >= oneTimeThreshold) {
        Log.d(TAG, "PreKey pool sufficient: ${ids.size}")
        return@withContext true
      }

      // Choose start id: find max existing id and add 1
      val start = (ids.maxOrNull() ?: 0) + 1
      val startId = if (start < 1) 1 else start
      val success = protocolManager.generatePreKeys(uid, startId, oneTimeBatch)
      Log.d(TAG, "Generated prekeys start=$startId count=$oneTimeBatch success=$success")
      return@withContext success
    } catch (e: Exception) {
      Log.e(TAG, "ensureOneTimePreKeys failed: ${e.message}", e)
      return@withContext false
    }
  }

  /**
   * Generate a new signed-prekey with a random id (or provided id).
   * Returns signedPreKeyId on success or null on failure.
   */
  suspend fun rotateSignedPreKey(proposedId: Int? = null): Int? = withContext(Dispatchers.IO) {
    try {
      val id = proposedId ?: (signedPreKeyIdRangeStart + Random.nextInt(0, 100000))
      val ok = protocolManager.generateSignedPreKey(uid, id)
      if (!ok) {
        Log.e(TAG, "rotateSignedPreKey: failed to generate signed prekey id=$id")
        return@withContext null
      }
      Log.d(TAG, "rotateSignedPreKey: generated id=$id")
      return@withContext id
    } catch (e: Exception) {
      Log.e(TAG, "rotateSignedPreKey error: ${e.message}", e)
      return@withContext null
    }
  }

  /**
   * Consume a one-time prekey: picks the lowest id, removes it locally and returns (id, base64Pub).
   * Caller MUST notify server to mark this prekey as consumed (or server should atomically serve/consume).
   */
  suspend fun consumeOneTimePreKey(): Pair<Int, String>? = withContext(Dispatchers.IO) {
    try {
      val ids = signalStore.listPreKeyIds(uid).sorted()
      if (ids.isEmpty()) {
        Log.w(TAG, "No one-time prekeys available for $uid")
        return@withContext null
      }

      val useId = ids.first()
      val pubB64 = signalStore.loadPreKeyBase64(uid, useId) ?: run {
        Log.w(TAG, "PreKey $useId missing its data")
        return@withContext null
      }

      // Remove it locally (server should also mark consumed)
      signalStore.removePreKey(uid, useId)
      Log.d(TAG, "Consumed one-time prekey id=$useId for $uid")
      return@withContext Pair(useId, pubB64)
    } catch (e: Exception) {
      Log.e(TAG, "consumeOneTimePreKey error: ${e.message}", e)
      return@withContext null
    }
  }

  /**
   * Convenience: create/rotate keys and return the bundle JSON to upload to your server.
   * - Generates identity if missing.
   * - Ensures signed prekey exists (rotates if forced).
   * - Ensures enough one-time prekeys.
   * - Returns exportPreKeyBundle() JSON (or null on failure).
   */
  suspend fun prepareAndExportBundle(forceRotateSigned: Boolean = false): String? = withContext(Dispatchers.IO) {
    try {
      // Ensure identity exists (if not, create)
      val idPub = signalStore.loadPublicKeyBase64(uid, "identity")
      if (idPub == null) {
        val ok = protocolManager.generateIdentity(uid)
        if (!ok) {
          Log.e(TAG, "prepareAndExportBundle: failed to generate identity")
          return@withContext null
        }
      }

      // Rotate signed prekey if forced or none exists
      val existingSigned = signalStore.loadSignedPreKeyBase64(uid, 1) // naive check for id 1
      if (forceRotateSigned || existingSigned == null) {
        val newId = rotateSignedPreKey() ?: return@withContext null
        Log.d(TAG, "prepareAndExportBundle: signed prekey id=$newId ready")
      }

      // Ensure one-time prekeys
      val ensured = ensureOneTimePreKeys()
      if (!ensured) {
        Log.w(TAG, "prepareAndExportBundle: failed to ensure one-time prekeys")
      }

      // Export bundle via protocol manager
      return@withContext protocolManager.exportPreKeyBundle(uid)
    } catch (e: Exception) {
      Log.e(TAG, "prepareAndExportBundle error: ${e.message}", e)
      return@withContext null
    }
  }
}
