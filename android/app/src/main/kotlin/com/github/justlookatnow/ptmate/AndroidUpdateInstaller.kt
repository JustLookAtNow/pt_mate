package com.github.justlookatnow.ptmate

import android.app.Activity
import android.content.Intent
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File

/** Keeps completed updates across activity/process recreation; never opens UI in background. */
class AndroidUpdateInstaller(private val activity: Activity) {
    private val preferences = activity.getSharedPreferences("app_update_install", 0)
    private val directory get() = File(activity.filesDir, "ota_update")
    var resumed = false

    private fun apkFile(filename: String): File {
        require(filename.matches(Regex("pt_mate-[0-9A-Za-z._-]+-arm64-v8a\\.apk"))) {
            "Invalid update filename"
        }
        return File(directory, filename)
    }

    fun downloadPath(filename: String): String {
        directory.mkdirs()
        return apkFile(filename).absolutePath + ".part"
    }

    @Suppress("DEPRECATION")
    private fun isUsable(file: File): Boolean {
        if (!file.isFile || file.length() == 0L) return false
        val manager = activity.packageManager
        val archive = manager.getPackageArchiveInfo(file.absolutePath, 0) ?: return false
        if (archive.packageName != activity.packageName) return false
        val installed = manager.getPackageInfo(activity.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            archive.longVersionCode > installed.longVersionCode
        } else {
            archive.versionCode > installed.versionCode
        }
    }

    fun completeDownload(filename: String): Boolean {
        val file = apkFile(filename)
        val partial = File(file.absolutePath + ".part")
        check(partial.renameTo(file)) { "无法保存更新包" }
        check(isUsable(file)) { "更新包无效或版本不高于当前版本" }
        check(preferences.edit().putString("filename", filename).putBoolean("pending", true).commit()) {
            "无法保存待安装任务"
        }
        return openPendingInstallation()
    }

    fun tryInstallDownloaded(filename: String): Boolean {
        if (preferences.getString("filename", null) != filename) return false
        if (!isUsable(apkFile(filename))) {
            preferences.edit().clear().apply()
            return false
        }
        preferences.edit().putBoolean("pending", true).commit()
        openPendingInstallation()
        return true
    }

    fun openPendingInstallation(): Boolean {
        if (!resumed || !preferences.getBoolean("pending", false)) return false
        val filename = preferences.getString("filename", null) ?: return false
        val file = apkFile(filename)
        if (!isUsable(file)) {
            preferences.edit().clear().apply()
            return false
        }
        // Keep the task pending if permission was revoked during the download.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            return false
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.ota_update_provider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // Clear only the automatic retry; keep the completed APK for an explicit retry.
        preferences.edit().putBoolean("pending", false).commit()
        try {
            activity.startActivity(intent)
        } catch (error: Exception) {
            preferences.edit().putBoolean("pending", true).commit()
            throw error
        }
        return true
    }

    fun clear() {
        preferences.edit().clear().commit()
    }
}
