package com.github.justlookatnow.ptmate

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

    private companion object {
        const val CHANNEL = "pt_mate/android_install_permission"
    }
}
