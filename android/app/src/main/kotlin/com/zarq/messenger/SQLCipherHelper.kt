package com.zarq.messenger

import android.content.Context
import android.util.Log
import net.zetetic.database.sqlcipher.SQLiteDatabase
import net.zetetic.database.sqlcipher.SQLiteDatabaseHook
import net.zetetic.database.sqlcipher.SQLiteConnection

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
    fun exportMessages(userUid: String, dbPassword: String, checkRunning: () -> Unit = {}): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()
        visitMessages(userUid, dbPassword, checkRunning) { messages.add(it) }
        return messages
    }

    fun visitMessages(userUid: String, dbPassword: String, checkRunning: () -> Unit, onMessage: (Map<String, Any?>) -> Unit): Long {
        var count = 0L

        try {
            // Load SQLCipher native library
            System.loadLibrary("sqlcipher")

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
                override fun preKey(connection: SQLiteConnection?) {}
                override fun postKey(connection: SQLiteConnection?) {
                    // Run cipher_migrate to handle older SQLCipher versions
                    // Using executeForString as it works better than execute for PRAGMA statements
                    connection?.executeForString("PRAGMA cipher_migrate;", null, null)
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
                      AND NOT (m.content = 'This message was deleted' AND (m.is_encrypted = 0 OR m.encrypted_content IS NULL))
                      AND m.content NOT LIKE '{"type":"location"%'
                    ORDER BY m.timestamp ASC
                    """,
                    arrayOf(userUid)
                )

                cursor.use { c ->
                    Log.d(TAG, "Query executed, processing ${c.count} messages...")

                    // Process cursor
                    if (c.moveToFirst()) {
                        do {
                            checkRunning()
                            val row = linkedMapOf<String, Any?>()
                            for (index in 0 until c.columnCount) {
                                row[c.getColumnName(index)] = when (c.getType(index)) {
                                    android.database.Cursor.FIELD_TYPE_NULL -> null
                                    android.database.Cursor.FIELD_TYPE_INTEGER -> c.getLong(index)
                                    android.database.Cursor.FIELD_TYPE_FLOAT -> c.getDouble(index)
                                    android.database.Cursor.FIELD_TYPE_STRING -> c.getString(index)
                                    else -> error("Unsupported backup column: ${c.getColumnName(index)}")
                                }
                            }
                            onMessage(row)
                            count++
                        } while (c.moveToNext())
                    }
                }
            }

            Log.d(TAG, "Exported $count messages")
            return count

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error exporting messages: ${e.message}", e)
            throw e
        }
    }

    /**
     * Open encrypted database in read-write mode
     */
    fun openWritableDatabase(userUid: String, dbPassword: String): SQLiteDatabase {
        System.loadLibrary("sqlcipher")
        val databaseName = "zarq_messages_$userUid.db"
        val dbPath = context.getDatabasePath(databaseName).absolutePath
        val hook = object : SQLiteDatabaseHook {
            override fun preKey(connection: SQLiteConnection?) {}
            override fun postKey(connection: SQLiteConnection?) {
                connection?.executeForString("PRAGMA cipher_migrate;", null, null)
            }
        }
        return SQLiteDatabase.openDatabase(
            dbPath,
            dbPassword,
            null,
            SQLiteDatabase.OPEN_READWRITE,
            hook
        )
    }

    /**
     * Insert an incoming decrypted message directly into the local encrypted database
     */
    fun insertDecryptedMessage(
        userUid: String,
        dbPassword: String,
        messageId: Int,
        conversationId: Int,
        senderUid: String,
        username: String,
        plaintext: String,
        contentB64: String?,
        senderDeviceId: Int?,
        timestamp: String
    ): Boolean {
        return try {
            val db = openWritableDatabase(userUid, dbPassword)
            db.use { database ->
                val cv = android.content.ContentValues().apply {
                    put("id", messageId)
                    put("username", username)
                    put("content", plaintext)
                    put("timestamp", timestamp)
                    put("senderUid", senderUid)
                    put("conversationId", conversationId)
                    put("status", "delivered")
                    put("encrypted_content", contentB64)
                    put("is_encrypted", if (contentB64 != null) 1 else 0)
                    if (senderDeviceId != null) put("sender_device_id", senderDeviceId)
                    put("has_attachment", 0)
                    put("is_quick_reply", 0)
                }
                val result = database.insertWithOnConflict("messages", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
                Log.d(TAG, "Inserted decrypted message $messageId into local DB, rowId: $result")
                result != -1L
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to insert decrypted message into local DB: ${e.message}", e)
            false
        }
    }

    /**
     * Insert a sent quick reply into the local encrypted database
     */
    fun insertSentQuickReply(
        userUid: String,
        dbPassword: String,
        messageId: Int,
        conversationId: Int,
        myUid: String,
        myUsername: String,
        plaintext: String,
        contentB64: String?,
        timestamp: String
    ): Boolean {
        return try {
            val db = openWritableDatabase(userUid, dbPassword)
            db.use { database ->
                val cv = android.content.ContentValues().apply {
                    put("id", messageId)
                    put("username", myUsername)
                    put("content", plaintext)
                    put("timestamp", timestamp)
                    put("senderUid", myUid)
                    put("conversationId", conversationId)
                    put("status", "sent")
                    put("encrypted_content", contentB64)
                    put("is_encrypted", if (contentB64 != null) 1 else 0)
                    put("is_quick_reply", 1)
                    put("has_attachment", 0)
                }
                val result = database.insertWithOnConflict("messages", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
                Log.d(TAG, "Inserted sent quick reply $messageId into local DB, rowId: $result")
                result != -1L
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to insert sent quick reply into local DB: ${e.message}", e)
            false
        }
    }

    /**
     * Mark all messages in a conversation as read in the local encrypted database
     */
    fun markConversationReadLocally(userUid: String, dbPassword: String, conversationId: Int): Int {
        return try {
            val db = openWritableDatabase(userUid, dbPassword)
            db.use { database ->
                val cv = android.content.ContentValues().apply {
                    put("status", "read")
                }
                val rows = database.update("messages", cv, "conversationId = ? AND status != 'read'", arrayOf(conversationId.toString()))
                Log.d(TAG, "Marked $rows messages as read locally in conversation $conversationId")
                rows
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to mark conversation $conversationId read locally: ${e.message}", e)
            0
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
