package com.example.zarq_messenger

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec


object SignalCrypto {
  private const val TAG = "SignalCrypto"
  private const val KEYSTORE_ALIAS = "zarq_wrap_key_v1"
  private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
  private const val WRAPPED_DIR = "zarq_keys"
  private const val AES_KEY_SIZE_BITS = 256
  private const val GCM_TAG_LEN_BITS = 128
  private val secureRandom = SecureRandom()

  // -------------------------
  // Public helper APIs
  // -------------------------

  /** Save raw private key bytes for uid (wrapped with keystore AES). Returns true on success. */
  fun saveIdentityPrivateKey(context: Context, uid: String, rawPrivateKey: ByteArray): Boolean {
    return try {
      val wrapped = wrapWithKeystore(rawPrivateKey)
      val f = getWrappedKeyFile(context, uid)
      f.parentFile?.mkdirs()
      f.writeBytes(wrapped)
      Log.d(TAG, "Saved wrapped private key for uid=$uid (bytes=${wrapped.size})")
      true
    } catch (e: Exception) {
      Log.e(TAG, "saveIdentityPrivateKey failed: ${e.message}", e)
      false
    }
  }

  /** Load raw private key bytes for uid, or null if not present / unwrap failed. */
  fun loadIdentityPrivateKey(context: Context, uid: String): ByteArray? {
    return try {
      val raw = unwrapPrivateKeyForUid(context, uid)
      if (raw == null) {
        Log.d(TAG, "No wrapped private key for uid=$uid")
      } else {
        Log.d(TAG, "Loaded private key for uid=$uid (len=${raw.size})")
      }
      raw
    } catch (e: Exception) {
      Log.e(TAG, "loadIdentityPrivateKey failed: ${e.message}", e)
      null
    }
  }

  /** Delete wrapped private key file for uid (best-effort). */
  fun deleteIdentityPrivateKey(context: Context, uid: String) {
    try {
      val f = getWrappedKeyFile(context, uid)
      if (f.exists()) f.delete()
      Log.d(TAG, "Deleted wrapped private key for uid=$uid")
    } catch (e: Exception) {
      Log.e(TAG, "deleteIdentityPrivateKey failed: ${e.message}", e)
    }
  }

  /** Save public key bytes (raw) to files for easy retrieval by other native code or for exporting. */
  fun savePublicKey(context: Context, uid: String, publicBytes: ByteArray) {
    try {
      val f = getPublicKeyFile(context, uid)
      f.parentFile?.mkdirs()
      f.writeBytes(publicBytes)
      Log.d(TAG, "Saved public key for uid=$uid (len=${publicBytes.size})")
    } catch (e: Exception) {
      Log.e(TAG, "savePublicKey failed: ${e.message}", e)
    }
  }

  fun loadPublicKey(context: Context, uid: String): ByteArray? {
    val f = getPublicKeyFile(context, uid)
    return if (f.exists()) f.readBytes() else null
  }

  // -------------------------
  // Internal helpers
  // -------------------------

  private fun getWrappedKeyFile(context: Context, uid: String): File {
    val dir = File(context.filesDir, WRAPPED_DIR)
    return File(dir, "$uid.priv")
  }

  private fun getPublicKeyFile(context: Context, uid: String): File {
    val dir = File(context.filesDir, WRAPPED_DIR)
    return File(dir, "$uid.pub")
  }

  /**
   * Wrap raw private key bytes with an AES-GCM key stored in AndroidKeyStore.
   * Return format: [4-byte ivLength][iv][ciphertext]
   */
  private fun wrapWithKeystore(rawPriv: ByteArray): ByteArray {
    val key = getOrCreateKeystoreAesKey()
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    val iv = ByteArray(12).also { secureRandom.nextBytes(it) }
    val spec = GCMParameterSpec(GCM_TAG_LEN_BITS, iv)
    cipher.init(Cipher.ENCRYPT_MODE, key, spec)
    val ct = cipher.doFinal(rawPriv)

    // store iv length + iv + ciphertext
    val bb = ByteBuffer.allocate(4 + iv.size + ct.size)
    bb.putInt(iv.size)
    bb.put(iv)
    bb.put(ct)
    return bb.array()
  }

  /** Unwrap the wrapped bytes and return the raw private key bytes. */
  private fun unwrapPrivateKeyForUid(context: Context, uid: String): ByteArray? {
    val f = getWrappedKeyFile(context, uid)
    if (!f.exists()) return null
    val wrapped = f.readBytes()
    val bb = ByteBuffer.wrap(wrapped)
    val ivLen = bb.int
    if (ivLen <= 0 || ivLen > 1024) throw IllegalStateException("invalid iv length")
    val iv = ByteArray(ivLen)
    bb.get(iv)
    val ct = ByteArray(bb.remaining())
    bb.get(ct)

    val key = getOrCreateKeystoreAesKey()
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    val spec = GCMParameterSpec(GCM_TAG_LEN_BITS, iv)
    cipher.init(Cipher.DECRYPT_MODE, key, spec)
    return cipher.doFinal(ct)
  }

  /** Create or obtain an AES key stored in AndroidKeyStore for wrapping private keys. */
  private fun getOrCreateKeystoreAesKey(): SecretKey {
    try {
      val ks = KeyStore.getInstance(KEYSTORE_PROVIDER)
      ks.load(null)
      if (ks.containsAlias(KEYSTORE_ALIAS)) {
        val entry = ks.getEntry(KEYSTORE_ALIAS, null) as KeyStore.SecretKeyEntry
        return entry.secretKey
      }

      val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
      val spec = KeyGenParameterSpec.Builder(
        KEYSTORE_ALIAS,
        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
      )
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(AES_KEY_SIZE_BITS)
        .setUserAuthenticationRequired(false)
        .build()
      kg.init(spec)
      return kg.generateKey()
    } catch (e: Exception) {
      throw RuntimeException("getOrCreateKeystoreAesKey failed: ${e.message}", e)
    }
  }
}
