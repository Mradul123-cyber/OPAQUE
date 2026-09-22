package com.zarq.messenger

import android.util.Log
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM encryption for backup files
 * Matches Flutter PointyCastle implementation for compatibility
 */
object BackupEncryption {
    private const val TAG = "BackupEncryption"

    // Encryption constants (must match Flutter implementation)
    private const val PBKDF2_ITERATIONS = 100000
    private const val AES_KEY_SIZE = 256 // bits
    private const val SALT_SIZE = 32 // bytes
    private const val NONCE_SIZE = 12 // bytes (GCM standard)
    private const val AUTH_TAG_SIZE = 128 // bits (16 bytes)

    /** Stream JSON directly into an encrypted private temporary file; no plaintext file. */
    fun writeEncrypted(file: java.io.File, passphrase: String, checkRunning: () -> Unit,
        writePlaintext: (java.io.OutputStream) -> Unit) {
        val salt = ByteArray(SALT_SIZE)
        val nonce = ByteArray(NONCE_SIZE)
        SecureRandom().apply { nextBytes(salt); nextBytes(nonce) }
        checkRunning()
        val key = deriveKey(passphrase, salt)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(AUTH_TAG_SIZE, nonce))
            java.io.FileOutputStream(file).use { output ->
                output.write(salt); output.write(nonce)
                val encrypting = object : java.io.OutputStream() {
                    override fun write(value: Int) = write(byteArrayOf(value.toByte()), 0, 1)
                    override fun write(data: ByteArray, offset: Int, length: Int) {
                        checkRunning()
                        cipher.update(data, offset, length)?.let { output.write(it) }
                    }
                    override fun flush() = output.flush()
                }
                writePlaintext(encrypting)
                checkRunning()
                output.write(cipher.doFinal())
                output.fd.sync()
            }
        } finally { key.fill(0) }
    }

    /**
     * Encrypt backup data with AES-256-GCM
     *
     * Format: [32 bytes: salt][12 bytes: nonce][n bytes: ciphertext + 16 bytes auth tag]
     *
     * @param plaintext The backup JSON as bytes
     * @param passphrase User's backup passphrase
     * @return Encrypted bytes with salt and nonce prepended
     */
    fun encrypt(plaintext: ByteArray, passphrase: String): ByteArray {
        try {
            Log.d(TAG, "Starting encryption (${plaintext.size} bytes)...")

            // Generate random salt and nonce
            val salt = ByteArray(SALT_SIZE)
            val nonce = ByteArray(NONCE_SIZE)
            SecureRandom().apply {
                nextBytes(salt)
                nextBytes(nonce)
            }

            // Derive encryption key from passphrase using PBKDF2
            val key = deriveKey(passphrase, salt)

            // Encrypt with AES-256-GCM
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val secretKey = SecretKeySpec(key, "AES")
            val gcmSpec = GCMParameterSpec(AUTH_TAG_SIZE, nonce)

            cipher.init(Cipher.ENCRYPT_MODE, secretKey, gcmSpec)
            val ciphertext = cipher.doFinal(plaintext)

            // Format: [salt][nonce][ciphertext+authTag]
            val result = ByteArray(SALT_SIZE + NONCE_SIZE + ciphertext.size)
            System.arraycopy(salt, 0, result, 0, SALT_SIZE)
            System.arraycopy(nonce, 0, result, SALT_SIZE, NONCE_SIZE)
            System.arraycopy(ciphertext, 0, result, SALT_SIZE + NONCE_SIZE, ciphertext.size)

            Log.d(TAG, "✅ Encryption successful (${result.size} bytes)")
            return result

        } catch (e: Exception) {
            Log.e(TAG, "❌ Encryption failed: ${e.message}", e)
            throw e
        }
    }

    /**
     * Derive encryption key from passphrase using PBKDF2-HMAC-SHA256
     *
     * @param passphrase User's passphrase
     * @param salt Random salt
     * @return 32-byte AES-256 key
     */
    private fun deriveKey(passphrase: String, salt: ByteArray): ByteArray {
        try {
            val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
            val spec = PBEKeySpec(
                passphrase.toCharArray(),
                salt,
                PBKDF2_ITERATIONS,
                AES_KEY_SIZE
            )
            val key = factory.generateSecret(spec).encoded

            Log.d(TAG, "Key derived successfully (${key.size} bytes)")
            return key

        } catch (e: Exception) {
            Log.e(TAG, "Key derivation failed: ${e.message}", e)
            throw e
        }
    }

    /**
     * Decrypt backup data with AES-256-GCM
     *
     * @param encryptedData Encrypted bytes with salt and nonce prepended
     * @param passphrase User's backup passphrase
     * @return Decrypted plaintext bytes
     */
    fun decrypt(encryptedData: ByteArray, passphrase: String): ByteArray {
        try {
            Log.d(TAG, "Starting decryption (${encryptedData.size} bytes)...")

            // Extract salt, nonce, and ciphertext
            val salt = encryptedData.copyOfRange(0, SALT_SIZE)
            val nonce = encryptedData.copyOfRange(SALT_SIZE, SALT_SIZE + NONCE_SIZE)
            val ciphertext = encryptedData.copyOfRange(SALT_SIZE + NONCE_SIZE, encryptedData.size)

            // Derive decryption key
            val key = deriveKey(passphrase, salt)

            // Decrypt with AES-256-GCM
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val secretKey = SecretKeySpec(key, "AES")
            val gcmSpec = GCMParameterSpec(AUTH_TAG_SIZE, nonce)

            cipher.init(Cipher.DECRYPT_MODE, secretKey, gcmSpec)
            val plaintext = cipher.doFinal(ciphertext)

            Log.d(TAG, "✅ Decryption successful (${plaintext.size} bytes)")
            return plaintext

        } catch (e: Exception) {
            Log.e(TAG, "❌ Decryption failed: ${e.message}", e)
            throw e
        }
    }
}
