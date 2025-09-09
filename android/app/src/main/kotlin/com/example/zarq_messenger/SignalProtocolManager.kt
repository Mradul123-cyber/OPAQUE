package com.example.zarq_messenger

import android.content.Context
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
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
import com.example.zarq_messenger.SignalStore;

/**
 * SignalProtocolManager - wrapper around libsignal-protocol-java using SignalStore & SignalCrypto.
 *
 * Note: This file expects libsignal-protocol-java v2.8.1 in build.gradle.
 */
class SignalProtocolManager(
  private val context: Context,
  private val store: SignalStore,
  private val crypto: SignalCrypto
) {
  private val TAG = "SignalProtocolManager"

  // device id for this install. If you plan multi-device per account, make this unique per device.
  private val deviceId: Int = 1

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

      // store registrationId as a file (optional)
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
      val spkSerialized: ByteArray = signedPreKeyRecord.serialize()
      val spkB64 = Base64.encodeToString(spkSerialized, Base64.NO_WRAP)

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
        // PreKeyRecord has an id getter inside the record - reflectively decode if needed.
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
   * The bundle contains: identity pub (base64), signedPreKey id+pub+sig (base64), one-time prekey id+pub (base64), deviceId.
   * Caller should upload and (server) mark one-time prekey as reserved/consumed when someone uses it.
   */
  suspend fun exportPreKeyBundle(uid: String): String? = withContext(Dispatchers.IO) {
    try {
      val identityB64 = store.loadPublicKeyBase64(uid, "identity") ?: return@withContext null

      // pick a signedPreKey (take first available)
      val signedIds = store.listSignedPreKeyIds(uid).ifEmpty { listOf(1) } // fallback id 1
      val spkId = signedIds.first()
      val spkB64 = store.loadSignedPreKeyBase64(uid, spkId) ?: return@withContext null

      // pick a one-time prekey (first)
      val preIds = store.listPreKeyIds(uid)
      if (preIds.isEmpty()) return@withContext null
      val usePreId = preIds.first()
      val preB64 = store.loadPreKeyBase64(uid, usePreId) ?: return@withContext null

      val json = JSONObject()
      json.put("identity", identityB64)
      json.put("signedPreKeyId", spkId)
      json.put("signedPreKey", spkB64)
      json.put("oneTimePreKeyId", usePreId)
      json.put("oneTimePreKey", preB64)
      json.put("deviceId", deviceId)
      return@withContext json.toString()
    } catch (e: Exception) {
      Log.e(TAG, "exportPreKeyBundle error: ${e.message}", e)
      null
    }
  }

  // -------------------------
  // Session init (X3DH) + encrypt/decrypt
  // -------------------------

  /**
   * Initialize a session with a remote PreKeyBundle JSON (as exported above).
   * Uses SessionBuilder to process bundle and store session into libsignal store.
   */
  suspend fun initSessionWithBundle(myUid: String, recipientUid: String, bundleJson: String): Boolean = withContext(Dispatchers.IO) {
    try {
      val obj = JSONObject(bundleJson)
      val remoteIdentityB64 = obj.getString("identity")
      val remoteSpkB64 = obj.getString("signedPreKey")
      val remoteSpkId = obj.getInt("signedPreKeyId")
      val remoteOnePreId = obj.getInt("oneTimePreKeyId")
      val remoteOnePreB64 = obj.getString("oneTimePreKey")
      val remoteDeviceId = obj.getInt("deviceId")

      // decode bytes
      val remoteIdentity = Base64.decode(remoteIdentityB64, Base64.NO_WRAP)
      val remoteSpkBytes = Base64.decode(remoteSpkB64, Base64.NO_WRAP)
      val remoteOnePreBytes = Base64.decode(remoteOnePreB64, Base64.NO_WRAP)

      // Build libsignal PreKeyBundle
      // We need our own libsignal store instance that implements required interfaces
      val libStore = LibsignalStore(context, store, myUid)
      val registrationId = byteArrayToInt(Base64.decode(store.loadPublicKeyBase64(myUid, "regid") ?: Base64.encodeToString(intToByteArray(0), Base64.NO_WRAP), Base64.NO_WRAP))

      val preKeyBundle = PreKeyBundle(
        registrationId, // recipient reg id (we'll set 0 for sender side; libsignal needs the recipient's reg id)
        remoteDeviceId,
        remoteOnePreId,
        PreKeyRecord(remoteOnePreBytes).keyPair.publicKey,remoteSpkId,
        SignedPreKeyRecord(remoteSpkBytes).keyPair.publicKey,
        SignedPreKeyRecord(remoteSpkBytes).signature,
        IdentityKey(remoteIdentity,0)
      )
      // Create SessionBuilder & process bundle
      val address = SignalProtocolAddress(recipientUid, remoteDeviceId)
      val sessionBuilder = org.whispersystems.libsignal.SessionBuilder(libStore, address)
      sessionBuilder.process(preKeyBundle)

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
      val libStore = LibsignalStore(context, store, myUid)
      val address = SignalProtocolAddress(senderUid, senderDeviceId)
      val cipher = SessionCipher(libStore, address)
      val wire = Base64.decode(wireBase64, Base64.NO_WRAP)

      // Decide message type: PreKeySignalMessage vs SignalMessage
       return@withContext try {
        val preKeyMsg = PreKeySignalMessage(wire)
        cipher.decrypt(preKeyMsg)
      } catch (_: Exception) {
        val sigMsg = SignalMessage(wire)
        cipher.decrypt(sigMsg)
      }
    } catch (e: Exception) {
      Log.e(TAG, "decrypt error: ${e.message}", e)
      null
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

/**
 * LibsignalStore - minimal implementation delegating to SignalStore for persistence.
 *
 * It implements the small subset of behavior libsignal needs: identity keypair, prekeys,
 * signed prekeys, session records. For production, implement robust concurrency, migrations, and record GC.
 */
class LibsignalStore(
  private val context: Context,
  private val signalStore: SignalStore,
  private val myUid: String
) : SignalProtocolStore {
  private val TAG = "LibsignalStore"

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

  override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey):Boolean {
    return true
    // not used in this minimal store
  }

  override fun isTrustedIdentity(address: SignalProtocolAddress,
   identityKey: IdentityKey,
   direction: Direction?): Boolean {
    // allow for now - production should verify/notify on identity changes
    return true
  }

  override fun getIdentity(address: SignalProtocolAddress): IdentityKey? {
    // Not used in this minimal store
    return null
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

  // Return all SignedPreKeys stored for myUid
  override fun loadSignedPreKeys(): List<SignedPreKeyRecord> {
   val results = mutableListOf<SignedPreKeyRecord>()
   try {
    // If you have a way to list signed prekey ids, use it.
    // For now, scan for a few known ids (example: 1..100)
    for (id in 1..100) {
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
  }

  override fun containsSession(recipient: SignalProtocolAddress): Boolean {
    val ids = signalStore.listSessionDeviceIds(recipient.name)
    return ids.contains(recipient.deviceId.toLong())
  }

override fun deleteSession(recipient: SignalProtocolAddress) {
    signalStore.removeSession(recipient.name, recipient.deviceId.toLong())
}

override fun deleteAllSessions(name: String) {
  try {
    val ids = signalStore.listSessionDeviceIds(name)
    for (deviceId in ids) {
      signalStore.removeSession(name, deviceId)
    }
  } catch (e: Exception) {
    Log.e(TAG, "deleteAllSessions failed for $name: ${e.message}", e)
  }
}


  // (If compilation complains about missing methods, add stubs delegating to simple behaviors.)
  private fun byteArrayToInt(bytes: ByteArray): Int {
    if (bytes.size < 4) return 0
    return (bytes[0].toInt() and 0xFF shl 24) or
           (bytes[1].toInt() and 0xFF shl 16) or
           (bytes[2].toInt() and 0xFF shl 8) or
           (bytes[3].toInt() and 0xFF)
  }
}
