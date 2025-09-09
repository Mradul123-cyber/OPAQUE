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
  }

  private fun read(uid: String, name: String): ByteArray? {
    val f = File(userDir(uid), name)
    return if (f.exists()) f.readBytes() else null
  }

  private fun delete(uid: String, name: String) {
    val f = File(userDir(uid), name)
    if (f.exists()) f.delete()
  }

  // ----------------------
  // Public key helpers
  // ----------------------
  fun savePublicKey(uid: String, tag: String, publicBase64: String): Boolean {
    return try {
      val bytes = Base64.decode(publicBase64, Base64.NO_WRAP)
      write(uid, "pub_$tag", bytes)
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
  fun savePreKey(uid: String, keyId: Int, publicBase64: String): Boolean =
    savePublicKey(uid, "prekey_$keyId", publicBase64)

  fun loadPreKeyBase64(uid: String, keyId: Int): String? =
    loadPublicKeyBase64(uid, "prekey_$keyId")

  fun removePreKey(uid: String, keyId: Int) =
    removePublicKey(uid, "prekey_$keyId")

  fun saveSignedPreKey(uid: String, keyId: Int, publicBase64: String): Boolean =
    savePublicKey(uid, "signedpre_$keyId", publicBase64)

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
  // Utilities
  // ----------------------
  fun listPreKeyIds(uid: String): List<Int> {
    return userDir(uid).listFiles()
      ?.mapNotNull { f ->
        val n = f.name
        when {
          n.startsWith("prekey_") -> n.removePrefix("prekey_").toIntOrNull()
          else -> null
        }
      } ?: emptyList()
  }

  fun clearAll(uid: String) {
    val dir = userDir(uid)
    dir.listFiles()?.forEach { it.delete() }
  }

  fun listSignedPreKeyIds(uid: String): List<Int> {
    return userDir(uid).listFiles()
      ?.mapNotNull { f ->
        val n = f.name
        when {
          n.startsWith("signedpre_") -> n.removePrefix("signedpre_").toIntOrNull()
          else -> null
        }
      } ?: emptyList()
  }
}
