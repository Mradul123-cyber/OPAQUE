package com.zarq.messenger

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import java.text.SimpleDateFormat
import java.util.*

/**
 * Native Kotlin backup manager for auto-backup
 * Performs WhatsApp-style silent backup without launching Flutter
 */
class NativeBackupManager(private val context: Context) {

    companion object {
        private const val TAG = "NativeBackupManager"
        private const val BACKUP_VERSION = "2.0.0"
        private const val PREFS_NAME = "zarq_prefs"
        private const val ENCRYPTED_PREFS_NAME = "zarq_secure_prefs"
    }

    /**
     * Perform complete native backup
     * This is the main entry point called by AutoBackupWorker
     *
     * @return true if backup successful, false otherwise
     */
    fun performBackup(): Boolean {
        return try {
            // Log.d(TAG, "")
            // Log.d(TAG, "╔════════════════════════════════════════════╗")
            // Log.d(TAG, "║  🚀 NATIVE AUTO-BACKUP STARTED            ║")
            // Log.d(TAG, "╚════════════════════════════════════════════╝")
            // Log.d(TAG, "")

            // Show START notification with sound
            BackupNotificationHelper(context).showStartNotification("Backup")

            val startTime = System.currentTimeMillis()

            // 1. Get user UID
            val userUid = getUserUid()
            if (userUid == null) {
                // Log.e(TAG, "❌ No user UID found - cannot backup")
                // Log.e(TAG, "❌ Please enable auto-backup in settings first!")
                BackupNotificationHelper(context).showFailureNotification(
                    "Auto",
                    "No user UID found. Enable auto-backup in settings first."
                )
                return false
            }
            // Log.d(TAG, "✅ User UID: $userUid")

            // 2. Get backup passphrase from encrypted storage
            val passphrase = getBackupPassphrase()
            if (passphrase == null) {
                // Log.e(TAG, "❌ No backup passphrase found - cannot backup")
                // Log.e(TAG, "❌ Please enable auto-backup in settings first!")
                BackupNotificationHelper(context).showFailureNotification(
                    "Auto",
                    "No passphrase found. Enable auto-backup in settings first."
                )
                return false
            }
            // Log.d(TAG, "✅ Passphrase retrieved")

            // 3. Get database password
            val dbPassword = getDatabasePassword()
            if (dbPassword == null) {
                // Log.e(TAG, "❌ No database password found - cannot backup")
                // Log.e(TAG, "❌ Please enable auto-backup in settings first!")
                BackupNotificationHelper(context).showFailureNotification(
                    "Auto",
                    "No database password found. Enable auto-backup in settings first."
                )
                return false
            }
            // Log.d(TAG, "✅ Database password retrieved")

            // 4. Export messages from SQLCipher database
            // Log.d(TAG, "📦 Exporting messages from database...")
            BackupNotificationHelper(context).showProgressNotification("Collecting messages...", 20)
            val messages = SQLCipherHelper(context).exportMessages(userUid, dbPassword)
            // Log.d(TAG, "✅ Exported ${messages.size} messages")

            // 5. Derive conversations from messages
            // Log.d(TAG, "🔄 Deriving conversations...")
            BackupNotificationHelper(context).showProgressNotification("Processing conversations...", 40)
            val conversations = deriveConversations(messages)
            // Log.d(TAG, "✅ Derived ${conversations.size} conversations")

            // 6. Export Signal Protocol state
            // Log.d(TAG, "🔐 Exporting Signal Protocol state...")
            BackupNotificationHelper(context).showProgressNotification("Exporting security data...", 50)
            val signalState = exportSignalProtocolState()
            // Log.d(TAG, "✅ Signal Protocol state exported")

            // 7. Create BackupData object
            val backupData = BackupData(
                version = BACKUP_VERSION,
                timestamp = System.currentTimeMillis(),
                userUid = userUid,
                deviceId = getDeviceId(),
                messages = messages,
                conversations = conversations,
                signalProtocolState = signalState,
                attachments = emptyList() // WhatsApp approach: media NOT included!
            )

            // 8. Convert to JSON
            // Log.d(TAG, "📝 Converting to JSON...")
            BackupNotificationHelper(context).showProgressNotification("Preparing backup data...", 60)
            val json = Gson().toJson(backupData)
            val jsonBytes = json.toByteArray(Charsets.UTF_8)
            // Log.d(TAG, "✅ JSON size: ${jsonBytes.size} bytes (${formatBytes(jsonBytes.size)})")

            // 9. Encrypt with AES-256-GCM
            // Log.d(TAG, "🔒 Encrypting backup...")
            BackupNotificationHelper(context).showProgressNotification("Encrypting backup...", 70)
            val encryptedBytes = BackupEncryption.encrypt(jsonBytes, passphrase)
            // Log.d(TAG, "✅ Encrypted size: ${encryptedBytes.size} bytes (${formatBytes(encryptedBytes.size)})")

            // 10. Generate filename with auto_backup prefix for easy identification
            val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH-mm-ss", Locale.getDefault()).format(Date())
            val fileName = "auto_backup_$timestamp.encrypted"

            // 11. Clean up old auto-backups BEFORE saving new one (keep only 2 most recent)
            // Log.d(TAG, "🧹 Cleaning up old auto-backups...")
            cleanupOldAutoBackups(context)

            // 12. Save to MediaStore Downloads
            // Log.d(TAG, "💾 Saving to MediaStore...")
            BackupNotificationHelper(context).showProgressNotification("Saving to storage...", 90)
            val success = MediaStoreHelper.saveBackup(context, encryptedBytes, fileName)

            if (success) {
                val duration = System.currentTimeMillis() - startTime
                // Log.d(TAG, "")
                // Log.d(TAG, "╔════════════════════════════════════════════╗")
                // Log.d(TAG, "║  ✅ BACKUP COMPLETED SUCCESSFULLY         ║")
                // Log.d(TAG, "╠════════════════════════════════════════════╣")
                // Log.d(TAG, "║  File: $fileName")
                // Log.d(TAG, "║  Location: ${MediaStoreHelper.getDisplayPath(fileName)}")
                // Log.d(TAG, "║  Size: ${formatBytes(encryptedBytes.size)}")
                // Log.d(TAG, "║  Messages: ${messages.size}")
                // Log.d(TAG, "║  Duration: ${duration}ms")
                // Log.d(TAG, "╚════════════════════════════════════════════╝")
                // Log.d(TAG, "")
            } else {
                // Log.e(TAG, "❌ Failed to save backup to MediaStore")
            }

            success

        } catch (e: Exception) {
            // Log.e(TAG, "")
            // Log.e(TAG, "╔════════════════════════════════════════════╗")
            // Log.e(TAG, "║  ❌ BACKUP FAILED                          ║")
            // Log.e(TAG, "╠════════════════════════════════════════════╣")
            // Log.e(TAG, "║  Error: ${e.message}")
            // Log.e(TAG, "╚════════════════════════════════════════════╝")
            // Log.e(TAG, "", e)
            false
        }
    }

    /**
     * Derive conversations from messages
     */
    private fun deriveConversations(messages: List<Message>): List<Conversation> {
        val conversationMap = mutableMapOf<Int, Conversation>()

        for (message in messages) {
            val convId = message.conversationId
            if (!conversationMap.containsKey(convId)) {
                conversationMap[convId] = Conversation(
                    conversationId = convId,
                    lastMessageTimestamp = message.timestamp,
                    username = message.username,
                    senderUid = message.senderUid
                )
            }
        }

        return conversationMap.values.toList()
    }

    /**
     * Export Signal Protocol state from SignalManager
     */
    private fun exportSignalProtocolState(): SignalProtocolState {
        return try {
            val signalManager = SignalManager(context)
            val signalStateJson = signalManager.exportSignalState()

            SignalProtocolState(
                data = signalStateJson,
                exportedAt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
            )
        } catch (e: Exception) {
            // Log.w(TAG, "⚠️ Failed to export Signal state: ${e.message}")
            // Return empty state on error (backup will work but sessions need re-establishment)
            SignalProtocolState(
                data = "{}",
                exportedAt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(Date())
            )
        }
    }

    /**
     * Get current user UID from SharedPreferences
     */
    private fun getUserUid(): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val userUid = prefs.getString("user_uid", null)

        // Debug: List all keys in SharedPreferences
        // Log.d(TAG, "🔍 DEBUG: Checking SharedPreferences for user_uid")
        // Log.d(TAG, "🔍 DEBUG: SharedPreferences name: $PREFS_NAME")
        // Log.d(TAG, "🔍 DEBUG: All keys in prefs: ${prefs.all.keys}")
        // Log.d(TAG, "🔍 DEBUG: user_uid value: $userUid")

        return userUid
    }

    /**
     * Get device ID from SharedPreferences
     */
    private fun getDeviceId(): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString("device_id", "unknown") ?: "unknown"
    }

    /**
     * Get backup passphrase from EncryptedSharedPreferences
     * This is stored when user enables auto-backup in Flutter
     */
    private fun getBackupPassphrase(): String? {
        return try {
            val encryptedPrefs = androidx.security.crypto.EncryptedSharedPreferences.create(
                context,
                ENCRYPTED_PREFS_NAME,
                androidx.security.crypto.MasterKey.Builder(context)
                    .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                    .build(),
                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            encryptedPrefs.getString("auto_backup_passphrase", null)
        } catch (e: Exception) {
            // Log.e(TAG, "Error reading passphrase: ${e.message}", e)
            null
        }
    }

    /**
     * Get database password from EncryptedSharedPreferences
     */
    private fun getDatabasePassword(): String? {
        return try {
            val encryptedPrefs = androidx.security.crypto.EncryptedSharedPreferences.create(
                context,
                ENCRYPTED_PREFS_NAME,
                androidx.security.crypto.MasterKey.Builder(context)
                    .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                    .build(),
                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            encryptedPrefs.getString("database_password", null)
        } catch (e: Exception) {
            // Log.e(TAG, "Error reading database password: ${e.message}", e)
            null
        }
    }

    /**
     * Format bytes to human-readable string
     */
    private fun formatBytes(bytes: Int): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> "${bytes / 1024} KB"
            else -> "${bytes / (1024 * 1024)} MB"
        }
    }

    /**
     * Clean up old auto-backups, keeping only the 2 most recent
     * Manual backups (starting with "backup_") are NOT deleted
     */
    private fun cleanupOldAutoBackups(context: Context) {
        try {
            // Log.d(TAG, "🧹 Cleaning up old auto-backups...")

            // List all backup files from MediaStore
            val allBackups = MediaStoreHelper.listBackups(context)

            // Filter only auto-backups (filename starts with "auto_backup_")
            val autoBackups = allBackups.filter { backup ->
                val name = backup["name"] as? String ?: ""
                name.startsWith("auto_backup_")
            }.toMutableList()

            // Log.d(TAG, "📊 Found ${autoBackups.size} auto-backup files")

            // If 2 or fewer auto-backups exist, don't delete anything
            if (autoBackups.size <= 2) {
                // Log.d(TAG, "✅ Only ${autoBackups.size} auto-backups, no cleanup needed")
                return
            }

            // Sort by modification time (newest first)
            autoBackups.sortByDescending { backup ->
                backup["dateModified"] as? Long ?: 0L
            }

            // Keep only the 2 most recent, delete the rest
            val backupsToDelete = autoBackups.drop(2)
            // Log.d(TAG, "🗑️ Deleting ${backupsToDelete.size} old auto-backups (keeping 2 most recent)")

            for (backup in backupsToDelete) {
                try {
                    val uri = backup["uri"] as? String
                    val name = backup["name"] as? String
                    if (uri != null) {
                        val deleted = MediaStoreHelper.deleteBackup(context, uri)
                        if (deleted) {
                            // Log.d(TAG, "  ✅ Deleted old auto-backup: $name")
                        } else {
                            // Log.w(TAG, "  ❌ Failed to delete: $name")
                        }
                    }
                } catch (e: Exception) {
                    // Log.w(TAG, "  ❌ Error deleting backup: ${e.message}")
                }
            }

            // Log.d(TAG, "✅ Auto-backup cleanup complete")
        } catch (e: Exception) {
            // Log.e(TAG, "❌ Error during cleanup: ${e.message}", e)
            // Don't rethrow - cleanup failure shouldn't stop backup creation
        }
    }
}
