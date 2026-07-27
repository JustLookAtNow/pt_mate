package com.github.justlookatnow.ptmate

import android.content.ContentValues
import android.content.Context
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
    private var secureStorageTestBootstrapFailureCode: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Test-only historical profiles must be committed before plugin
        // registration can initialize flutter_secure_storage. The production
        // applicationId can never satisfy this guard.
        secureStorageTestBootstrapFailureCode = bootstrapSecureStorageTestProfileIfNeeded()
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURE_STORAGE_PROFILE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "probeAndroidSecureStorage" -> {
                    result.success(probeAndroidSecureStorage())
                }

                "initializeFreshAndroidSecureStorage" -> {
                    result.success(initializeFreshAndroidSecureStorage())
                }

                "flushAndroidSecureStorage" -> {
                    result.success(flushAndroidSecureStorage())
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

    /**
     * Inspects only non-sensitive algorithm metadata, secure-artifact existence and filesystem
     * metadata for prior Flutter preferences. No encrypted key names or values leave the native
     * process, and this method never initializes or mutates secure storage.
     */
    private fun probeAndroidSecureStorage(): Map<String, Any?> {
        return try {
            val bootstrapFailure = secureStorageTestBootstrapFailureCode
            if (bootstrapFailure != null) {
                return SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    failureCode = bootstrapFailure,
                ).toMethodChannelMap()
            }
            validateSecureStorageTestProfile(
                SecureStorageProbeClassifier.classify(readSecureStorageProbeInput()),
            ).toMethodChannelMap()
        } catch (_: Exception) {
            SecureStorageProbeResult(
                status = "inconsistent",
                profile = "inconsistent",
                failureCode = "probe_failed",
            ).toMethodChannelMap()
        }
    }

    /**
     * Initializes only the two non-sensitive algorithm markers for a provably fresh namespace.
     *
     * flutter_secure_storage 10.3.1 interprets an absent marker pair as the historical
     * PKCS1/CBC profile even when no ciphertext has ever existed. With algorithm migration
     * deliberately disabled, asking it to open OAEP/GCM would otherwise fail once before the
     * plugin writes the requested markers. This guarded initialization avoids that false
     * migration path without creating, reading, deleting, or rewriting any encrypted value.
     */
    private fun initializeFreshAndroidSecureStorage(): Map<String, Any?> {
        return try {
            val before = SecureStorageProbeClassifier.classify(
                readSecureStorageProbeInput(),
            )
            if (before.status != "fresh" ||
                before.profile != "fresh" ||
                before.hasEncryptedEntries ||
                before.hasWrappedKeys
            ) {
                return SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    hasEncryptedEntries = before.hasEncryptedEntries,
                    hasWrappedKeys = before.hasWrappedKeys,
                    failureCode = "fresh_initialization_rejected",
                ).toMethodChannelMap()
            }

            val committed = getSharedPreferences(
                SECURE_STORAGE_NAMESPACED_CONFIG_PREFS,
                Context.MODE_PRIVATE,
            ).edit()
                .putString(
                    SecureStorageProbeClassifier.KEY_ALGORITHM_MARKER,
                    SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                )
                .putString(
                    SecureStorageProbeClassifier.STORAGE_ALGORITHM_MARKER,
                    SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                )
                .putBoolean(ENCRYPTED_PREFERENCES_MIGRATED_MARKER, true)
                .commit()
            if (!committed) {
                return SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    failureCode = "fresh_initialization_commit_failed",
                ).toMethodChannelMap()
            }

            val after = SecureStorageProbeClassifier.classify(
                readSecureStorageProbeInput(),
            )
            if (after.status != "ready" ||
                after.profile != "oaepGcm" ||
                after.keyCipher != SecureStorageProbeClassifier.KEY_CIPHER_OAEP ||
                after.storageCipher != SecureStorageProbeClassifier.STORAGE_CIPHER_GCM ||
                after.hasEncryptedEntries ||
                after.hasWrappedKeys
            ) {
                return SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    hasEncryptedEntries = after.hasEncryptedEntries,
                    hasWrappedKeys = after.hasWrappedKeys,
                    failureCode = "fresh_initialization_verification_failed",
                ).toMethodChannelMap()
            }
            after.toMethodChannelMap()
        } catch (_: Exception) {
            SecureStorageProbeResult(
                status = "inconsistent",
                profile = "inconsistent",
                failureCode = "fresh_initialization_failed",
            ).toMethodChannelMap()
        }
    }

    /**
     * Commits a historical algorithm pair only for a fresh, isolated debug application.
     * The subsequent public probe remains read-only and reports the actual persisted profile.
     */
    private fun bootstrapSecureStorageTestProfileIfNeeded(): String? {
        if (!isSecureStorageTestBuild()) return null
        val configuredProfile = BuildConfig.SECURE_STORAGE_TEST_PROFILE
        if (configuredProfile == "oaepGcm") return null

        return try {
            val before = SecureStorageProbeClassifier.classify(readSecureStorageProbeInput())
            if (before.status == "ready" && before.profile == configuredProfile) {
                return null
            }
            if (before.status != "fresh" ||
                before.profile != "fresh" ||
                before.hasEncryptedEntries ||
                before.hasWrappedKeys
            ) {
                return null
            }

            val algorithms = when (configuredProfile) {
                "pkcs1Gcm" ->
                    SecureStorageProbeClassifier.KEY_CIPHER_PKCS1 to
                        SecureStorageProbeClassifier.STORAGE_CIPHER_GCM
                "pkcs1Cbc" ->
                    SecureStorageProbeClassifier.KEY_CIPHER_PKCS1 to
                        SecureStorageProbeClassifier.STORAGE_CIPHER_CBC
                else -> return "secure_storage_test_profile_invalid"
            }
            val configPreferences = getSharedPreferences(
                SECURE_STORAGE_NAMESPACED_CONFIG_PREFS,
                Context.MODE_PRIVATE,
            )
            val committed = configPreferences.edit()
                .putString(
                    SecureStorageProbeClassifier.KEY_ALGORITHM_MARKER,
                    algorithms.first,
                )
                .putString(
                    SecureStorageProbeClassifier.STORAGE_ALGORITHM_MARKER,
                    algorithms.second,
                )
                .putBoolean(ENCRYPTED_PREFERENCES_MIGRATED_MARKER, true)
                .commit()
            if (!committed) {
                return "secure_storage_test_bootstrap_commit_failed"
            }

            val after = SecureStorageProbeClassifier.classify(readSecureStorageProbeInput())
            if (after.status != "ready" ||
                after.profile != configuredProfile ||
                after.hasEncryptedEntries ||
                after.hasWrappedKeys ||
                configPreferences.getBoolean(
                    ENCRYPTED_PREFERENCES_MIGRATED_MARKER,
                    false,
                ) != true
            ) {
                "secure_storage_test_bootstrap_verification_failed"
            } else {
                null
            }
        } catch (_: Exception) {
            "secure_storage_test_bootstrap_failed"
        }
    }

    /**
     * Waits until flutter_secure_storage's asynchronous SharedPreferences.apply() writes are
     * durably ordered before Dart switches the transaction manifest. No entry is read, changed,
     * deleted, or returned; a synchronous no-op commit only establishes the disk barrier.
     */
    private fun flushAndroidSecureStorage(): Map<String, Any?> {
        return try {
            val preferenceNames = listOf(
                SECURE_STORAGE_LEGACY_CONFIG_PREFS,
                SECURE_STORAGE_NAMESPACED_CONFIG_PREFS,
                SECURE_STORAGE_KEY_PREFS,
                SECURE_STORAGE_DATA_PREFS,
            )
            var committed = true
            for (preferenceName in preferenceNames) {
                if (!getSharedPreferences(preferenceName, Context.MODE_PRIVATE).edit().commit()) {
                    committed = false
                }
            }
            if (committed) {
                mapOf<String, Any?>(
                    "status" to "ready",
                    "failureCode" to null,
                )
            } else {
                mapOf<String, Any?>(
                    "status" to "unavailable",
                    "failureCode" to "secure_storage_flush_commit_failed",
                )
            }
        } catch (_: Exception) {
            mapOf<String, Any?>(
                "status" to "unavailable",
                "failureCode" to "secure_storage_flush_failed",
            )
        }
    }

    private fun readSecureStorageProbeInput(): SecureStorageProbeInput {
        val dataEntries =
            getSharedPreferences(SECURE_STORAGE_DATA_PREFS, Context.MODE_PRIVATE).all
        val wrappedKeyEntries =
            getSharedPreferences(SECURE_STORAGE_KEY_PREFS, Context.MODE_PRIVATE).all
        val namespacedConfig =
            getSharedPreferences(SECURE_STORAGE_NAMESPACED_CONFIG_PREFS, Context.MODE_PRIVATE).all
        val legacyConfig =
            getSharedPreferences(SECURE_STORAGE_LEGACY_CONFIG_PREFS, Context.MODE_PRIVATE).all
        val hasPriorFlutterPreferences = hasFlutterSharedPreferencesFile()

        // These preference files are dedicated to flutter_secure_storage. Treat
        // every entry as a secure artifact, including encrypted/unknown key names
        // from older or future plugin versions. Fresh initialization is allowed
        // only when both files are completely empty.
        val hasEncryptedEntries = dataEntries.isNotEmpty()
        val hasActiveGcmWrappedKey =
            wrappedKeyEntries.containsKey(SECURE_STORAGE_GCM_WRAPPED_KEY)
        val hasActiveCbcWrappedKey =
            wrappedKeyEntries.containsKey(SECURE_STORAGE_CBC_WRAPPED_KEY)
        val hasActiveBiometricWrappedKey =
            wrappedKeyEntries.containsKey(SECURE_STORAGE_BIOMETRIC_WRAPPED_KEY)
        val hasWrappedKeys = wrappedKeyEntries.isNotEmpty()
        // Do not open or enumerate FlutterSharedPreferences: old Android releases may still
        // contain plaintext fallback values there. File existence is enough to distinguish a
        // genuinely fresh install from an ambiguous used install whose secure artifacts vanished.
        // The latter must be recovered rather than silently initialized as a fresh namespace.
        val expectsEncryptedEntries = hasPriorFlutterPreferences

        return SecureStorageProbeInput(
            namespacedConfig = namespacedConfig,
            legacyConfig = legacyConfig,
            sdkInt = Build.VERSION.SDK_INT,
            hasEncryptedEntries = hasEncryptedEntries,
            hasWrappedKeys = hasWrappedKeys,
            hasActiveGcmWrappedKey = hasActiveGcmWrappedKey,
            hasActiveCbcWrappedKey = hasActiveCbcWrappedKey,
            hasActiveBiometricWrappedKey = hasActiveBiometricWrappedKey,
            hasPriorFlutterPreferences = hasPriorFlutterPreferences,
            expectsEncryptedEntries = expectsEncryptedEntries,
        )
    }

    private fun hasFlutterSharedPreferencesFile(): Boolean {
        val preferencesDirectory = File(applicationInfo.dataDir, "shared_prefs")
        val primary = File(preferencesDirectory, "$FLUTTER_SHARED_PREFERENCES.xml")
        val backup = File(preferencesDirectory, "$FLUTTER_SHARED_PREFERENCES.xml.bak")
        return primary.exists() || backup.exists()
    }

    /**
     * Allows a fresh, isolated debug application to initialize one of the historical profiles.
     * The Gradle-generated suffix and BuildConfig.DEBUG checks make this unreachable in production.
     */
    private fun validateSecureStorageTestProfile(
        actualProbe: SecureStorageProbeResult,
    ): SecureStorageProbeResult {
        if (!isSecureStorageTestBuild()) return actualProbe
        val configuredProfile = BuildConfig.SECURE_STORAGE_TEST_PROFILE
        if (configuredProfile == "oaepGcm" && actualProbe.status == "fresh") {
            return actualProbe
        }
        if (actualProbe.status == "ready" && actualProbe.profile == configuredProfile) {
            return actualProbe
        }
        if (actualProbe.status == "inconsistent" || actualProbe.status == "unsupported") {
            return actualProbe
        }
        return SecureStorageProbeResult(
            status = "inconsistent",
            profile = "inconsistent",
            hasEncryptedEntries = actualProbe.hasEncryptedEntries,
            hasWrappedKeys = actualProbe.hasWrappedKeys,
            failureCode = "secure_storage_test_profile_mismatch",
        )
    }

    private fun isSecureStorageTestBuild(): Boolean {
        if (!BuildConfig.DEBUG) return false
        val configuredProfile = BuildConfig.SECURE_STORAGE_TEST_PROFILE
        val configuredSuffix = BuildConfig.SECURE_STORAGE_TEST_APPLICATION_ID_SUFFIX
        return configuredProfile in SECURE_STORAGE_TEST_PROFILES &&
            configuredSuffix.isNotBlank() &&
            configuredSuffix.startsWith(SECURE_STORAGE_TEST_SUFFIX_PREFIX) &&
            packageName == BuildConfig.APPLICATION_ID &&
            BuildConfig.APPLICATION_ID.endsWith(configuredSuffix)
    }

    private companion object {
        const val CHANNEL = "pt_mate/android_install_permission"
        const val LOCAL_DOWNLOADS_CHANNEL = "pt_mate/local_downloads"
        const val SECURE_STORAGE_PROFILE_CHANNEL = "pt_mate/secure_storage_profile"
        const val DOWNLOADS_SUBDIRECTORY = "PT Mate"
        const val DOWNLOADS_DISPLAY_PATH = "Downloads/PT Mate"

        const val SECURE_STORAGE_DATA_PREFS = "FlutterSecureStorage"
        const val SECURE_STORAGE_KEY_PREFS = "FlutterSecureKeyStorage"
        const val FLUTTER_SHARED_PREFERENCES = "FlutterSharedPreferences"
        const val ENCRYPTED_PREFERENCES_MIGRATED_MARKER =
            "ENCRYPTED_PREFERENCES_MIGRATED"
        const val SECURE_STORAGE_LEGACY_CONFIG_PREFS = "FlutterSecureStorageConfiguration"
        const val SECURE_STORAGE_NAMESPACED_CONFIG_PREFS =
            "FlutterSecureStorageConfiguration:FlutterSecureStorage"
        const val SECURE_STORAGE_GCM_WRAPPED_KEY =
            "AESVGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
        const val SECURE_STORAGE_CBC_WRAPPED_KEY =
            "VGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
        const val SECURE_STORAGE_BIOMETRIC_WRAPPED_KEY =
            "BVGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
        const val SECURE_STORAGE_TEST_SUFFIX_PREFIX = ".securestoragetest."
        val SECURE_STORAGE_TEST_PROFILES = setOf("oaepGcm", "pkcs1Gcm", "pkcs1Cbc")
    }
}
