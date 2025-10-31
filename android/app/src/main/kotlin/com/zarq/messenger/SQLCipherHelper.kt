package com.zarq.messenger

import android.content.Context
import android.util.Log
import net.sqlcipher.database.SQLiteDatabase
import net.sqlcipher.database.SQLiteDatabaseHook

/**
 * Helper class to read data from SQLCipher encrypted database
 * Used for native backup without Flutter engine
 */
class SQLCipherHelper(private val context: Context) {

    companion object {
        private const val TAG = "SQLCipherHelper"
    }

    /**
     * Export all non-deleted messages from the database
     *
     * @param userUid Current user's Firebase UID
     * @param dbPassword SQLCipher database password
     * @return List of messages
     */
    fun exportMessages(userUid: String, dbPassword: String): List<Message> {
        val messages = mutableListOf<Message>()

        try {
            // Load SQLCipher native library
            SQLiteDatabase.loadLibs(context)

            // Open encrypted database with user-specific filename
            // Flutter uses: zarq_messages_[userUid].db
            val databaseName = "zarq_messages_$userUid.db"
            val dbPath = context.getDatabasePath(databaseName).absolutePath
            Log.d(TAG, "Opening database: $dbPath")

            // sqflite_sqlcipher uses the password as-is (string)
            // The password we have is a hex string (64 chars) from SHA-256
            // sqflite_sqlcipher with SQLCipher 4.x treats this as a passphrase and applies PBKDF2
            Log.d(TAG, "Database password length: ${dbPassword.length} characters")

            // Important: sqflite_sqlcipher passes the string directly to SQLCipher
            // which then applies PBKDF2-HMAC-SHA512 with 256000 iterations (SQLCipher 4.x default)
            // Match sqflite_sqlcipher's behavior: use cipher_migrate hook for compatibility
            val hook = object : SQLiteDatabaseHook {
                override fun preKey(database: SQLiteDatabase?) {}
                override fun postKey(database: SQLiteDatabase?) {
                    // Run cipher_migrate to handle older SQLCipher versions
                    database?.rawExecSQL("PRAGMA cipher_migrate;")
                }
            }

            // Use openDatabase with hook (same as sqflite_sqlcipher)
            val database = SQLiteDatabase.openDatabase(
                dbPath,
                dbPassword,  // Pass as String - sqflite_sqlcipher does this
                null,
                SQLiteDatabase.OPEN_READONLY,
                hook
            )

            Log.d(TAG, "✅ Database opened successfully")

            // Query messages excluding deleted ones
            // Matches Flutter query: excludes messages in deleted_messages table
            // and messages with "deleted" content
            database.use { db ->
                val cursor = db.rawQuery(
                    """
                    SELECT m.* FROM messages m
                    LEFT JOIN deleted_messages dm ON m.id = dm.message_id AND dm.user_uid = ?
                    WHERE dm.message_id IS NULL
                      AND m.content NOT LIKE 'This message was deleted%'
                      AND m.content NOT LIKE '%deleted this message%'
                    ORDER BY m.timestamp ASC
                    """,
                    arrayOf(userUid)
                )

                cursor.use { c ->
                    Log.d(TAG, "Query executed, processing ${c.count} messages...")

                    // Process cursor
                    if (c.moveToFirst()) {
                        do {
                            // Read status field directly (matches Flutter backup format)
                            val status = getStringOrNull(c, "status") ?: "sent"

                            messages.add(
                                Message(
                                    id = c.getInt(c.getColumnIndexOrThrow("id")),
                                    conversationId = c.getInt(c.getColumnIndexOrThrow("conversationId")),
                                    senderUid = c.getString(c.getColumnIndexOrThrow("senderUid")),
                                    username = c.getString(c.getColumnIndexOrThrow("username")),
                                    content = c.getString(c.getColumnIndexOrThrow("content")),
                                    timestamp = c.getString(c.getColumnIndexOrThrow("timestamp")),
                                    status = status,
                                    hasAttachment = c.getInt(c.getColumnIndexOrThrow("has_attachment")),
                                    attachmentId = getIntOrNull(c, "attachment_id"),
                                    attachmentType = getStringOrNull(c, "attachment_type"),
                                    replyToMessageId = getIntOrNull(c, "reply_to_message_id"),
                                    replyToMessageContent = getStringOrNull(c, "reply_to_message_content"),
                                    replyToSenderUsername = getStringOrNull(c, "reply_to_sender_username"),
                                    encryptedMediaKey = getStringOrNull(c, "encrypted_media_key"),
                                    mediaEncryptionIv = getStringOrNull(c, "media_encryption_iv"),
                                    mediaEncryptionType = getStringOrNull(c, "media_encryption_type"),
                                    groupId = getStringOrNull(c, "group_id"),
                                    recipientUid = getStringOrNull(c, "recipient_uid"),
                                    recipientDeviceId = getIntOrNull(c, "recipient_device_id"),
                                    senderDeviceId = getIntOrNull(c, "sender_device_id")
                                )
                            )
                        } while (c.moveToNext())
                    }
                }
            }

            Log.d(TAG, "✅ Exported ${messages.size} messages successfully")
            return messages

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error exporting messages: ${e.message}", e)
            throw e
        }
    }

    /**
     * Helper to get nullable integer from cursor
     */
    private fun getIntOrNull(cursor: android.database.Cursor, columnName: String): Int? {
        return try {
            val index = cursor.getColumnIndexOrThrow(columnName)
            if (cursor.isNull(index)) null else cursor.getInt(index)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Helper to get nullable string from cursor
     */
    private fun getStringOrNull(cursor: android.database.Cursor, columnName: String): String? {
        return try {
            val index = cursor.getColumnIndexOrThrow(columnName)
            if (cursor.isNull(index)) null else cursor.getString(index)
        } catch (e: Exception) {
            null
        }
    }
}
