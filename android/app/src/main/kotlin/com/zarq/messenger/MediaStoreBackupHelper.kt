package com.zarq.messenger

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream

/**
 * Helper class for saving and reading backup files using MediaStore Downloads API
 * This is the Google Play compliant way - no MANAGE_EXTERNAL_STORAGE needed!
 */
class MediaStoreBackupHelper(private val context: Context) {

    companion object {
        private const val TAG = "MediaStoreBackup"
        private const val BACKUP_FOLDER = "Zarq_Backups"
        private const val MIME_TYPE = "application/octet-stream"
    }

    /**
     * Save a backup file to MediaStore Downloads collection
     * Works on Android 10+ without any special permissions
     */
    fun saveBackupFile(sourceFile: File, fileName: String): String? {
        if (Build.VERSION.SDK_INT < 29) return sourceFile.inputStream().use { LegacyBackupStorage.save(context, it, fileName) }
        return try {
            Log.d(TAG, "📁 Saving backup file: $fileName")

            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, MIME_TYPE)

                // For Android 10+, set relative path to organize files
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$BACKUP_FOLDER")
                    put(MediaStore.Downloads.IS_PENDING, 1) // Mark as pending during write
                }
            }

            // Insert into MediaStore
            val uri = context.contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                contentValues
            )

            if (uri == null) {
                Log.e(TAG, "❌ Failed to create MediaStore entry")
                return null
            }

            // Write file content
            context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                FileInputStream(sourceFile).use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            }

            // Mark as complete
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear()
                contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
                context.contentResolver.update(uri, contentValues, null, null)
            }

            Log.d(TAG, "✅ Backup saved successfully: $uri")
            uri.toString()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving backup: ${e.message}", e)
            null
        }
    }

    /**
     * List all backup files from MediaStore Downloads
     * Returns list of backup file info (uri, name, size, modified time)
     */
    fun listBackupFiles(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < 29) return if (LegacyBackupStorage.hasPermission(context)) LegacyBackupStorage.list(context) else emptyList()
        val backupFiles = mutableListOf<Map<String, Any>>()

        try {
            Log.d(TAG, "📋 Listing backup files from MediaStore...")

            val projection = arrayOf(
                MediaStore.Downloads._ID,
                MediaStore.Downloads.DISPLAY_NAME,
                MediaStore.Downloads.SIZE,
                MediaStore.Downloads.DATE_MODIFIED,
                MediaStore.Downloads.RELATIVE_PATH
            )

            // Query ALL .encrypted files in our backup folder (not just files with "backup" in name)
            val selection = "${MediaStore.Downloads.DISPLAY_NAME} LIKE ? AND ${MediaStore.Downloads.RELATIVE_PATH} LIKE ? AND ${MediaStore.Downloads.IS_PENDING} = 0"
            val selectionArgs = arrayOf("%.encrypted", "%$BACKUP_FOLDER%")

            val sortOrder = "${MediaStore.Downloads.DATE_MODIFIED} DESC"

            context.contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->

                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.SIZE)
                val dateColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DATE_MODIFIED)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val name = cursor.getString(nameColumn)
                    val size = cursor.getLong(sizeColumn)
                    val dateModified = cursor.getLong(dateColumn)

                    val uri = Uri.withAppendedPath(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        id.toString()
                    )

                    // Filter to only include files from our backup folder
                    if (name.endsWith(".encrypted")) {
                        backupFiles.add(mapOf(
                            "uri" to uri.toString(),
                            "name" to name,
                            "size" to size,
                            "dateModified" to dateModified * 1000 // Convert to milliseconds
                        ))
                        Log.d(TAG, "  - Found: $name (${size / 1024}KB)")
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
     * Read backup file content from MediaStore URI
     */
    fun readBackupFile(uriString: String): ByteArray? {
        if (uriString.startsWith("file:")) return LegacyBackupStorage.file(context, uriString).readBytes()
        return try {
            val uri = Uri.parse(uriString)
            Log.d(TAG, "📖 Reading backup file: $uri")

            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                val bytes = inputStream.readBytes()
                Log.d(TAG, "✅ Read ${bytes.size} bytes")
                bytes
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reading backup: ${e.message}", e)
            null
        }
    }

    /**
     * Delete backup file from MediaStore
     */
    fun deleteBackupFile(uriString: String): Boolean {
        if (uriString.startsWith("file:")) return LegacyBackupStorage.file(context, uriString).delete()
        return try {
            val uri = Uri.parse(uriString)
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
     * Uses IS_PENDING flag for Android 10+ compatibility
     */
    fun renameBackupFile(uriString: String, newFileName: String): Boolean {
        if (uriString.startsWith("file:")) {
            require(newFileName == File(newFileName).name && newFileName.endsWith(".encrypted"))
            val original = LegacyBackupStorage.file(context, uriString)
            val target = File(original.parentFile, newFileName)
            return !target.exists() && original.renameTo(target)
        }
        return try {
            val uri = Uri.parse(uriString)
            Log.d(TAG, "✏️ Renaming backup file: $uri to $newFileName")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ requires using IS_PENDING flag for proper rename

                // Step 1: Set IS_PENDING to 1 (mark file as being modified)
                val pendingValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                context.contentResolver.update(uri, pendingValues, null, null)
                Log.d(TAG, "📝 Set IS_PENDING to 1")

                // Step 2: Update the DISPLAY_NAME only (do not modify RELATIVE_PATH)
                val renameValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, newFileName)
                    put(MediaStore.MediaColumns.DATE_MODIFIED, System.currentTimeMillis() / 1000)
                }
                val updated = context.contentResolver.update(uri, renameValues, null, null)
                Log.d(TAG, "📝 Updated DISPLAY_NAME")

                // Step 3: Clear IS_PENDING (mark file as ready)
                val clearPendingValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                context.contentResolver.update(uri, clearPendingValues, null, null)
                Log.d(TAG, "📝 Cleared IS_PENDING")

                if (updated > 0) {
                    Log.d(TAG, "✅ Backup renamed successfully")

                    // Notify MediaStore of the change
                    context.contentResolver.notifyChange(uri, null)

                    true
                } else {
                    Log.w(TAG, "⚠️ No rows updated")
                    false
                }
            } else {
                // Pre-Android 10 - simple update
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, newFileName)
                    put(MediaStore.MediaColumns.DATE_MODIFIED, System.currentTimeMillis() / 1000)
                }

                val updated = context.contentResolver.update(uri, values, null, null)
                if (updated > 0) {
                    Log.d(TAG, "✅ Backup renamed successfully")
                    context.contentResolver.notifyChange(uri, null)
                    true
                } else {
                    Log.w(TAG, "⚠️ No rows updated")
                    false
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error renaming backup: ${e.message}", e)
            false
        }
    }

    /**
     * Get backup file path for display purposes
     * Note: This is for display only, actual access should use URIs
     */
    fun getBackupDisplayPath(fileName: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${Environment.DIRECTORY_DOWNLOADS}/$BACKUP_FOLDER/$fileName"
        } else {
            "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)}/$BACKUP_FOLDER/$fileName"
        }
    }
}
