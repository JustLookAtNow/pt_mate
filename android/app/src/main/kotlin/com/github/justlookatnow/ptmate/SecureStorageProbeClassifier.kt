package com.github.justlookatnow.ptmate

/**
 * Pure Kotlin classifier for the read-only Android secure-storage probe.
 *
 * Android-specific preference access stays in [MainActivity]. Keeping the marker selection and
 * state classification here makes every historical storage combination JVM-testable without
 * initializing flutter_secure_storage or touching the Android Keystore.
 */
internal object SecureStorageProbeClassifier {
    const val KEY_ALGORITHM_MARKER = "FlutterSecureSAlgorithmKey"
    const val STORAGE_ALGORITHM_MARKER = "FlutterSecureSAlgorithmStorage"

    const val KEY_CIPHER_OAEP = "RSA_ECB_OAEPwithSHA_256andMGF1Padding"
    const val KEY_CIPHER_PKCS1 = "RSA_ECB_PKCS1Padding"
    const val STORAGE_CIPHER_GCM = "AES_GCM_NoPadding"
    const val STORAGE_CIPHER_CBC = "AES_CBC_PKCS7Padding"

    private const val ANDROID_M_API_LEVEL = 23

    fun classify(input: SecureStorageProbeInput): SecureStorageProbeResult {
        val expectsEncryptedEntries =
            input.expectsEncryptedEntries || input.hasPriorFlutterPreferences
        val keyMarker = readAlgorithmMarker(
            input.namespacedConfig,
            input.legacyConfig,
            KEY_ALGORITHM_MARKER,
        )
        val storageMarker = readAlgorithmMarker(
            input.namespacedConfig,
            input.legacyConfig,
            STORAGE_ALGORITHM_MARKER,
        )

        if (keyMarker is AlgorithmMarker.Invalid || storageMarker is AlgorithmMarker.Invalid) {
            return input.result(
                status = "inconsistent",
                profile = "inconsistent",
                failureCode = "invalid_algorithm_marker",
            )
        }

        if ((keyMarker is AlgorithmMarker.Missing) != (storageMarker is AlgorithmMarker.Missing)) {
            return input.result(
                status = "inconsistent",
                profile = "inconsistent",
                keyCipher = (keyMarker as? AlgorithmMarker.Present)?.value,
                storageCipher = (storageMarker as? AlgorithmMarker.Present)?.value,
                failureCode = "partial_algorithm_marker",
            )
        }

        if (keyMarker is AlgorithmMarker.Missing && storageMarker is AlgorithmMarker.Missing) {
            if (!input.hasEncryptedEntries && !input.hasWrappedKeys) {
                if (expectsEncryptedEntries) {
                    return SecureStorageProbeResult(
                        status = "inconsistent",
                        profile = "inconsistent",
                        failureCode = "secure_storage_missing_requires_restore",
                    )
                }
                return SecureStorageProbeResult(
                    status = "fresh",
                    profile = "fresh",
                )
            }

            // flutter_secure_storage <= 9.2.4 did not persist algorithm markers. Its only
            // possible default was RSA PKCS#1 + AES-CBC, identifiable by the active CBC key slot.
            // Marker-less GCM or biometric data remains ambiguous and must never be guessed.
            if (input.hasActiveCbcWrappedKey &&
                !input.hasActiveGcmWrappedKey &&
                !input.hasActiveBiometricWrappedKey
            ) {
                if (expectsEncryptedEntries && !input.hasEncryptedEntries) {
                    return input.result(
                        status = "inconsistent",
                        profile = "inconsistent",
                        keyCipher = KEY_CIPHER_PKCS1,
                        storageCipher = STORAGE_CIPHER_CBC,
                        failureCode = "secure_storage_data_missing_requires_restore",
                    )
                }
                return input.result(
                    status = "ready",
                    profile = "pkcs1Cbc",
                    keyCipher = KEY_CIPHER_PKCS1,
                    storageCipher = STORAGE_CIPHER_CBC,
                )
            }

            return input.result(
                status = "inconsistent",
                profile = "inconsistent",
                failureCode = "missing_algorithm_markers",
            )
        }

        val keyCipher = (keyMarker as AlgorithmMarker.Present).value
        val storageCipher = (storageMarker as AlgorithmMarker.Present).value
        val profile = when {
            keyCipher == KEY_CIPHER_OAEP && storageCipher == STORAGE_CIPHER_GCM -> "oaepGcm"
            keyCipher == KEY_CIPHER_PKCS1 && storageCipher == STORAGE_CIPHER_GCM -> "pkcs1Gcm"
            keyCipher == KEY_CIPHER_PKCS1 && storageCipher == STORAGE_CIPHER_CBC -> "pkcs1Cbc"
            else -> null
        }

        if (profile == null) {
            return input.result(
                status = "unsupported",
                profile = "unsupported",
                keyCipher = keyCipher,
                storageCipher = storageCipher,
                failureCode = "unsupported_algorithm",
            )
        }

        if (input.sdkInt < ANDROID_M_API_LEVEL && profile != "pkcs1Cbc") {
            return input.result(
                status = "unsupported",
                profile = "unsupported",
                keyCipher = keyCipher,
                storageCipher = storageCipher,
                failureCode = "algorithm_not_supported",
            )
        }

        val hasExpectedActiveWrappedKey = when (profile) {
            "pkcs1Cbc" -> input.hasActiveCbcWrappedKey
            else -> input.hasActiveGcmWrappedKey
        }
        if (expectsEncryptedEntries && !input.hasEncryptedEntries) {
            return input.result(
                status = "inconsistent",
                profile = "inconsistent",
                keyCipher = keyCipher,
                storageCipher = storageCipher,
                failureCode = "secure_storage_data_missing_requires_restore",
            )
        }
        if (input.hasEncryptedEntries && !hasExpectedActiveWrappedKey) {
            return input.result(
                status = "inconsistent",
                profile = "inconsistent",
                keyCipher = keyCipher,
                storageCipher = storageCipher,
                failureCode = "missing_wrapped_key",
            )
        }

        return input.result(
            status = "ready",
            profile = profile,
            keyCipher = keyCipher,
            storageCipher = storageCipher,
        )
    }

    /** A namespaced value is authoritative even when malformed; only absence permits fallback. */
    internal fun readAlgorithmMarker(
        namespacedConfig: Map<String, *>,
        legacyConfig: Map<String, *>,
        marker: String,
    ): AlgorithmMarker {
        val value = when {
            namespacedConfig.containsKey(marker) -> namespacedConfig[marker]
            legacyConfig.containsKey(marker) -> legacyConfig[marker]
            else -> return AlgorithmMarker.Missing
        }
        return if (value is String && value.isNotBlank()) {
            AlgorithmMarker.Present(value)
        } else {
            AlgorithmMarker.Invalid
        }
    }

    internal sealed interface AlgorithmMarker {
        data object Missing : AlgorithmMarker

        data object Invalid : AlgorithmMarker

        data class Present(val value: String) : AlgorithmMarker
    }
}

internal data class SecureStorageProbeInput(
    val namespacedConfig: Map<String, *> = emptyMap<String, Any?>(),
    val legacyConfig: Map<String, *> = emptyMap<String, Any?>(),
    val sdkInt: Int,
    val hasEncryptedEntries: Boolean = false,
    val hasWrappedKeys: Boolean = false,
    val hasActiveGcmWrappedKey: Boolean = false,
    val hasActiveCbcWrappedKey: Boolean = false,
    val hasActiveBiometricWrappedKey: Boolean = false,
    val hasPriorFlutterPreferences: Boolean = false,
    val expectsEncryptedEntries: Boolean = false,
)

internal data class SecureStorageProbeResult(
    val status: String,
    val profile: String,
    val keyCipher: String? = null,
    val storageCipher: String? = null,
    val hasEncryptedEntries: Boolean = false,
    val hasWrappedKeys: Boolean = false,
    val failureCode: String? = null,
) {
    fun toMethodChannelMap(): Map<String, Any?> = mapOf(
        "status" to status,
        "profile" to profile,
        "keyCipher" to keyCipher,
        "storageCipher" to storageCipher,
        "hasEncryptedEntries" to hasEncryptedEntries,
        "hasWrappedKeys" to hasWrappedKeys,
        "failureCode" to failureCode,
    )
}

private fun SecureStorageProbeInput.result(
    status: String,
    profile: String,
    keyCipher: String? = null,
    storageCipher: String? = null,
    failureCode: String? = null,
): SecureStorageProbeResult = SecureStorageProbeResult(
    status = status,
    profile = profile,
    keyCipher = keyCipher,
    storageCipher = storageCipher,
    hasEncryptedEntries = hasEncryptedEntries,
    hasWrappedKeys = hasWrappedKeys,
    failureCode = failureCode,
)
