package com.zarq.messenger

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import java.io.IOException

/**
 * Helper class to save backup files to MediaStore Downloads
 * Google Play compliant - no MANAGE_EXTERNAL_STORAGE needed
 */
object MediaStoreHelper {

    private const val TAG = "MediaStoreHelper"
    private const val RELATIVE_PATH = "Download/Zarq_Backups"

    /**
     * Save backup file to MediaStore Downloads
     *
     * @param context Application context
     * @param data Encrypted backup data
     * @param fileName Backup file name (e.g., "backup_2025-01-15T02-00-00.encrypted")
     * @return true if successful, false otherwise
     */
    fun saveBackup(context: Context, data: ByteArray, fileName: String): Boolean {
        return try {
            Log.d(TAG, "Saving backup to MediaStore: $fileName (${data.size} bytes)")

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                Log.e(TAG, "MediaStore Downloads API requires Android 10+")
                return false
            }

            // Prepare content values
            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH)
                put(MediaStore.Downloads.IS_PENDING, 1) // Mark as pending while writing
            }

            val resolver = context.contentResolver

            // Insert into MediaStore
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)

            if (uri == null) {
                Log.e(TAG, "❌ Failed to create MediaStore entry")
                return false
            }

            Log.d(TAG, "MediaStore URI created: $uri")

            // Write data to file
            var success = false
            try {
                resolver.openOutputStream(uri)?.use { outputStream ->
                    outputStream.write(data)
                    outputStream.flush()
                    success = true
                }
            } catch (e: IOException) {
                Log.e(TAG, "❌ Error writing to MediaStore: ${e.message}", e)
                // Clean up failed entry
                resolver.delete(uri, null, null)
                return false
            }

            // Mark as complete (not pending anymore)
            if (success) {
                contentValues.clear()
                contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, contentValues, null, null)

                Log.d(TAG, "✅ Backup saved successfully to: $RELATIVE_PATH/$fileName")
                return true
            }

            false

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving backup: ${e.message}", e)
            false
        }
    }

    /**
     * Get display path for user information
     */
    fun getDisplayPath(fileName: String): String {
        return "$RELATIVE_PATH/$fileName"
    }

    /**
     * List all backup files from MediaStore Downloads
     * Returns list of backup file info (uri, name, size, dateModified)
     */
    fun listBackups(context: Context): List<Map<String, Any>> {
        val backupFiles = mutableListOf<Map<String, Any>>()

        try {
            Log.d(TAG, "📋 Listing backup files from MediaStore...")

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                Log.e(TAG, "MediaStore Downloads API requires Android 10+")
                return emptyList()
            }

            val projection = arrayOf(
                MediaStore.Downloads._ID,
                MediaStore.Downloads.DISPLAY_NAME,
                MediaStore.Downloads.SIZE,
                MediaStore.Downloads.DATE_MODIFIED,
                MediaStore.Downloads.RELATIVE_PATH
            )

            // Query only .encrypted files from Zarq_Backups folder
            val selection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                "${MediaStore.Downloads.DISPLAY_NAME} LIKE ? AND ${MediaStore.Downloads.RELATIVE_PATH} LIKE ?"
            } else {
                "${MediaStore.Downloads.DISPLAY_NAME} LIKE ?"
            }
            val selectionArgs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf("%.encrypted", "%Zarq_Backups%")
            } else {
                arrayOf("%.encrypted")
            }

            val sortOrder = "${MediaStore.Downloads.DATE_MODIFIED} DESC"

            Log.d(TAG, "🔍 Query parameters:")
            Log.d(TAG, "  Selection: $selection")
            Log.d(TAG, "  Args: ${selectionArgs.joinToString()}")
            Log.d(TAG, "  URI: ${MediaStore.Downloads.EXTERNAL_CONTENT_URI}")

            val resolver = context.contentResolver
            val cursor = resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )

            Log.d(TAG, "🔍 Query executed, cursor: ${if (cursor == null) "NULL" else "NOT NULL"}")

            if (cursor == null) {
                Log.e(TAG, "❌ Query returned null cursor")
                return emptyList()
            }

            Log.d(TAG, "📊 Query returned ${cursor.count} total results")

            cursor.use {
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.SIZE)
                val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DATE_MODIFIED)
                val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.RELATIVE_PATH)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val name = cursor.getString(nameColumn)
                    val size = cursor.getLong(sizeColumn)
                    val dateModified = cursor.getLong(dateColumn)
                    val relativePath = cursor.getString(pathColumn)

                    Log.d(TAG, "  📄 File: $name, Path: $relativePath, Ends with .encrypted: ${name.endsWith(".encrypted")}")

                    val uri = android.net.Uri.withAppendedPath(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        id.toString()
                    )

                    // Filter to only include .encrypted files from our backup folder
                    if (name.endsWith(".encrypted")) {
                        backupFiles.add(mapOf(
                            "uri" to uri.toString(),
                            "name" to name,
                            "size" to size,
                            "dateModified" to dateModified // Already in seconds, will convert in cleanup
                        ))
                        Log.d(TAG, "  ✅ Added: $name (${size / 1024}KB)")
                    }
                }
            }

            Log.d(TAG, "✅ Found ${backupFiles.size} backup files")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error listing backups: ${e.message}", e)
        }

        return backupFiles
    }

    /**
     * Delete backup file from MediaStore
     */
    fun deleteBackup(context: Context, uriString: String): Boolean {
        return try {
            val uri = android.net.Uri.parse(uriString)
            Log.d(TAG, "🗑️ Deleting backup file: $uri")

            val deleted = context.contentResolver.delete(uri, null, null)
            if (deleted > 0) {
                Log.d(TAG, "✅ Backup deleted successfully")
                true
            } else {
                Log.w(TAG, "⚠️ No rows deleted")
                false
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error deleting backup: ${e.message}", e)
            false
        }
    }

    /**
     * Rename backup file in MediaStore
     */
    fun renameBackup(context: Context, uriString: String, newFileName: String): Boolean {
        return try {
            val uri = android.net.Uri.parse(uriString)
            Log.d(TAG, "✏️ Renaming backup file: $uri to $newFileName")

            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, newFileName)
            }

            val updated = context.contentResolver.update(uri, values, null, null)
            if (updated > 0) {
                Log.d(TAG, "✅ Backup renamed successfully")
                true
            } else {
                Log.w(TAG, "⚠️ No rows updated")
                false
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error renaming backup: ${e.message}", e)
            false
        }
    }
}
