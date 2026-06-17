package com.github.justlookatnow.ptmate

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstallPermissionGranted" -> {
                    result.success(canInstallPackages())
                }

                "openInstallPermissionSettings" -> {
                    result.success(openInstallPermissionSettings())
                }

                "clearDownloadedApks" -> {
                    result.success(clearDownloadedApks())
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCAL_DOWNLOADS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDownloadsDisplayPath" -> {
                    result.success(DOWNLOADS_DISPLAY_PATH)
                }

                "saveToDownloads" -> {
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (fileName.isNullOrBlank() || bytes == null) {
                        result.error("invalid_args", "fileName and bytes are required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        result.success(saveToDownloads(fileName, bytes, mimeType))
                    } catch (e: Exception) {
                        result.error("save_failed", e.message ?: "Failed to save file", null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }

        return try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun clearDownloadedApks(): Int {
        val otaDir = File(applicationInfo.dataDir, "files/ota_update")
        if (!otaDir.exists()) {
            return 0
        }
        return deleteChildrenRecursively(otaDir)
    }

    private fun deleteChildrenRecursively(directory: File): Int {
        var deletedCount = 0
        val children = directory.listFiles() ?: return 0
        for (child in children) {
            deletedCount += if (child.isDirectory) {
                val nestedCount = deleteChildrenRecursively(child)
                if (child.delete()) nestedCount + 1 else nestedCount
            } else {
                if (child.delete()) 1 else 0
            }
        }
        return deletedCount
    }

    private fun saveToDownloads(fileName: String, bytes: ByteArray, mimeType: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveToDownloadsWithMediaStore(fileName, bytes, mimeType)
        } else {
            saveToDownloadsLegacy(fileName, bytes)
        }
    }

    private fun saveToDownloadsWithMediaStore(
        fileName: String,
        bytes: ByteArray,
        mimeType: String,
    ): String {
        val resolver = contentResolver
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$DOWNLOADS_SUBDIRECTORY"
        val uniqueFileName = buildUniqueMediaStoreFileName(relativePath, fileName)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, uniqueFileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Unable to create Downloads entry")

        try {
            resolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
            } ?: throw IllegalStateException("Unable to open output stream")

            val completedValues = ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }
            resolver.update(uri, completedValues, null, null)
            return "$DOWNLOADS_DISPLAY_PATH/$uniqueFileName"
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun buildUniqueMediaStoreFileName(relativePath: String, fileName: String): String {
        var candidate = fileName
        var counter = 1
        while (mediaStoreFileExists(relativePath, candidate)) {
            candidate = appendFileNameCounter(fileName, counter)
            counter++
        }
        return candidate
    }

    private fun mediaStoreFileExists(relativePath: String, fileName: String): Boolean {
        val projection = arrayOf(MediaStore.Downloads._ID)
        val selection =
            "${MediaStore.Downloads.RELATIVE_PATH}=? AND ${MediaStore.Downloads.DISPLAY_NAME}=?"
        val selectionArgs = arrayOf("$relativePath/", fileName)
        contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null,
        )?.use { cursor ->
            return cursor.moveToFirst()
        }
        return false
    }

    private fun saveToDownloadsLegacy(fileName: String, bytes: ByteArray): String {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val targetDir = File(downloadsDir, DOWNLOADS_SUBDIRECTORY)
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalStateException("Unable to create ${targetDir.absolutePath}")
        }

        val targetFile = buildUniqueLegacyFile(targetDir, fileName)
        FileOutputStream(targetFile).use { output ->
            output.write(bytes)
        }
        return targetFile.absolutePath
    }

    private fun buildUniqueLegacyFile(directory: File, fileName: String): File {
        var candidate = File(directory, fileName)
        var counter = 1
        while (candidate.exists()) {
            candidate = File(directory, appendFileNameCounter(fileName, counter))
            counter++
        }
        return candidate
    }

    private fun appendFileNameCounter(fileName: String, counter: Int): String {
        val dotIndex = fileName.lastIndexOf('.')
        return if (dotIndex > 0) {
            "${fileName.substring(0, dotIndex)} ($counter)${fileName.substring(dotIndex)}"
        } else {
            "$fileName ($counter)"
        }
    }

    private companion object {
        const val CHANNEL = "pt_mate/android_install_permission"
        const val LOCAL_DOWNLOADS_CHANNEL = "pt_mate/local_downloads"
        const val DOWNLOADS_SUBDIRECTORY = "PT Mate"
        const val DOWNLOADS_DISPLAY_PATH = "Downloads/PT Mate"
    }
}
