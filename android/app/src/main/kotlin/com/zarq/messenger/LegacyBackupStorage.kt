package com.zarq.messenger

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.net.Uri
import java.io.File
import java.io.InputStream

/** Android 8/9 shared Downloads support. Files survive app uninstall. */
object LegacyBackupStorage {
    fun hasPermission(context: Context) = Build.VERSION.SDK_INT >= 29 ||
        context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    private fun folder(context: Context): File {
        if (!hasPermission(context)) throw SecurityException("Storage permission required")
        return File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Zarq_Backups")
    }
    fun save(context: Context, input: InputStream, name: String, checkRunning: () -> Unit = {}): String {
        require(name == File(name).name && name.endsWith(".encrypted"))
        val dir = folder(context)
        check(dir.isDirectory || dir.mkdirs()) { "Backup folder unavailable" }
        val target = File(dir, name)
        check(!target.exists()) { "Backup already exists" }
        val temp = File(dir, "$name.${java.util.UUID.randomUUID()}.partial")
        try {
            temp.outputStream().use { out ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    checkRunning()
                    val count = input.read(buffer)
                    if (count < 0) break
                    out.write(buffer, 0, count)
                }
                out.fd.sync()
            }
            checkRunning()
            if (!temp.renameTo(target)) throw java.io.IOException("Could not save backup")
            return Uri.fromFile(target).toString()
        } finally { temp.delete() }
    }
    fun list(context: Context): List<Map<String, Any>> = folder(context).listFiles()
        ?.filter { it.isFile && it.name.endsWith(".encrypted") }
        ?.map { mapOf("uri" to Uri.fromFile(it).toString(), "name" to it.name,
            "size" to it.length(), "dateModified" to it.lastModified()) } ?: emptyList()
    fun file(context: Context, uri: String): File {
        val parsed = Uri.parse(uri)
        require(parsed.scheme == "file")
        val file = File(requireNotNull(parsed.path)).canonicalFile
        require(file.parentFile == folder(context).canonicalFile && file.name.endsWith(".encrypted"))
        return file
    }
}
