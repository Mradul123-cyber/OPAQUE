package com.zarq.messenger

import android.content.Context
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Persistent file logger — writes logs to internal storage so they survive
 * process death, app close, and notification-triggered background execution.
 *
 * Log file location (pull with adb):
 *   adb exec-out run-as com.zarq.messenger cat files/zarq_debug.log
 * Or copy to Downloads:
 *   adb shell "run-as com.zarq.messenger cp /data/data/com.zarq.messenger/files/zarq_debug.log /sdcard/Download/zarq_debug.log"
 *   adb pull /sdcard/Download/zarq_debug.log
 */
object FileLogger {

    private const val LOG_FILE_NAME = "zarq_debug.log"
    private const val MAX_FILE_SIZE_BYTES = 2 * 1024 * 1024L // 2 MB rotate

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    fun d(context: Context, tag: String, message: String) {
        write(context, "D", tag, message)
    }

    fun w(context: Context, tag: String, message: String) {
        write(context, "W", tag, message)
    }

    fun e(context: Context, tag: String, message: String, throwable: Throwable? = null) {
        write(context, "E", tag, message)
        throwable?.let {
            write(context, "E", tag, "  Exception: ${it.javaClass.name}: ${it.message}")
            it.stackTrace.take(10).forEach { frame ->
                write(context, "E", tag, "    at $frame")
            }
        }
    }

    fun clear(context: Context) {
        try {
            getLogFile(context).writeText("")
        } catch (e: Exception) { /* ignore */ }
    }

    fun getLogFilePath(context: Context): String = getLogFile(context).absolutePath

    private fun write(context: Context, level: String, tag: String, message: String) {
        try {
            val file = getLogFile(context)

            // Rotate if too large
            if (file.exists() && file.length() > MAX_FILE_SIZE_BYTES) {
                val backup = File(file.parent, "zarq_debug_old.log")
                file.renameTo(backup)
            }

            val timestamp = dateFormat.format(Date())
            val line = "$timestamp $level/$tag: $message\n"

            FileWriter(file, true).use { it.write(line) }
        } catch (e: Exception) {
            // Never crash — logging must be silent on failure
        }
    }

    private fun getLogFile(context: Context): File {
        return File(context.filesDir, LOG_FILE_NAME)
    }
}
