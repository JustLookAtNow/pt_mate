package com.github.justlookatnow.ptmate

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
internal class SecureStorageProbeClassifierTest(
    private val case: ClassificationCase,
) {
    @Test
    fun classifyHistoricalStorageState() {
        assertEquals(case.expected, SecureStorageProbeClassifier.classify(case.input))
    }

    companion object {
        private const val SUPPORTED_SDK = 34
        private const val ANDROID_M_SDK = 23
        private const val PRE_M_SDK = 22

        private val oaepGcm = markerConfig(
            SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
            SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
        )
        private val pkcs1Gcm = markerConfig(
            SecureStorageProbeClassifier.KEY_CIPHER_PKCS1,
            SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
        )
        private val pkcs1Cbc = markerConfig(
            SecureStorageProbeClassifier.KEY_CIPHER_PKCS1,
            SecureStorageProbeClassifier.STORAGE_CIPHER_CBC,
        )

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> = listOf(
            case(
                name = "namespaced markers override conflicting global markers",
                input = input(
                    namespacedConfig = oaepGcm,
                    legacyConfig = pkcs1Cbc,
                ),
                expected = readyOaepGcm(),
            ),
            case(
                name = "global markers are used when namespace is absent",
                input = input(legacyConfig = pkcs1Gcm),
                expected = readyPkcs1Gcm(),
            ),
            case(
                name = "each absent namespaced marker falls back independently",
                input = input(
                    namespacedConfig = mapOf(
                        SecureStorageProbeClassifier.KEY_ALGORITHM_MARKER to
                            SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    ),
                    legacyConfig = pkcs1Gcm,
                ),
                expected = readyOaepGcm(),
            ),
            case(
                name = "storage namespace marker falls back to global key marker independently",
                input = input(
                    namespacedConfig = mapOf(
                        SecureStorageProbeClassifier.STORAGE_ALGORITHM_MARKER to
                            SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    ),
                    legacyConfig = pkcs1Cbc,
                ),
                expected = readyPkcs1Gcm(),
            ),
            case(
                name = "no markers and no secure artifacts is fresh",
                input = input(),
                expected = SecureStorageProbeResult(
                    status = "fresh",
                    profile = "fresh",
                ),
            ),
            case(
                name = "prior Flutter preferences without secure namespace requires restore",
                input = input(hasPriorFlutterPreferences = true),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    failureCode = "secure_storage_missing_requires_restore",
                ),
            ),
            case(
                name = "key marker without storage marker is partial",
                input = input(
                    namespacedConfig = mapOf(
                        SecureStorageProbeClassifier.KEY_ALGORITHM_MARKER to
                            SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    ),
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    failureCode = "partial_algorithm_marker",
                ),
            ),
            case(
                name = "storage marker without key marker is partial",
                input = input(
                    namespacedConfig = mapOf(
                        SecureStorageProbeClassifier.STORAGE_ALGORITHM_MARKER to
                            SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    ),
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    failureCode = "partial_algorithm_marker",
                ),
            ),
            case(
                name = "non string namespaced marker is invalid and blocks global fallback",
                input = input(
                    namespacedConfig = mapOf(
                        SecureStorageProbeClassifier.KEY_ALGORITHM_MARKER to 7,
                    ),
                    legacyConfig = oaepGcm,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    failureCode = "invalid_algorithm_marker",
                ),
            ),
            case(
                name = "blank marker is invalid",
                input = input(
                    namespacedConfig = mapOf(
                        SecureStorageProbeClassifier.KEY_ALGORITHM_MARKER to
                            SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                        SecureStorageProbeClassifier.STORAGE_ALGORITHM_MARKER to "",
                    ),
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    failureCode = "invalid_algorithm_marker",
                ),
            ),
            case(
                name = "markerless active CBC wrapped key infers PKCS1 CBC",
                input = input(
                    sdkInt = PRE_M_SDK,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveCbcWrappedKey = true,
                ),
                expected = readyPkcs1Cbc(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                ),
            ),
            case(
                name = "markerless CBC wrapped key without ciphertext remains historical PKCS1 CBC",
                input = input(
                    hasWrappedKeys = true,
                    hasActiveCbcWrappedKey = true,
                ),
                expected = readyPkcs1Cbc(hasWrappedKeys = true),
            ),
            case(
                name = "markerless CBC wrapper with expected ciphertext requires restore",
                input = input(
                    hasWrappedKeys = true,
                    hasActiveCbcWrappedKey = true,
                    expectsEncryptedEntries = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_PKCS1,
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_CBC,
                    hasWrappedKeys = true,
                    failureCode = "secure_storage_data_missing_requires_restore",
                ),
            ),
            case(
                name = "markerless ambiguous wrapped keys are inconsistent",
                input = input(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveGcmWrappedKey = true,
                    hasActiveCbcWrappedKey = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    failureCode = "missing_algorithm_markers",
                ),
            ),
            case(
                name = "markerless ciphertext without a wrapped key is inconsistent",
                input = input(
                    hasEncryptedEntries = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    hasEncryptedEntries = true,
                    failureCode = "missing_algorithm_markers",
                ),
            ),
            case(
                name = "markerless GCM wrapped key is not guessed",
                input = input(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveGcmWrappedKey = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    failureCode = "missing_algorithm_markers",
                ),
            ),
            case(
                name = "markerless biometric wrapped key is not guessed",
                input = input(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveBiometricWrappedKey = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    failureCode = "missing_algorithm_markers",
                ),
            ),
            case(
                name = "ciphertext without expected wrapped key is inconsistent",
                input = input(
                    namespacedConfig = oaepGcm,
                    hasEncryptedEntries = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    hasEncryptedEntries = true,
                    failureCode = "missing_wrapped_key",
                ),
            ),
            case(
                name = "prior Flutter preferences with markers but no encrypted data requires restore",
                input = input(
                    namespacedConfig = oaepGcm,
                    hasWrappedKeys = true,
                    hasActiveGcmWrappedKey = true,
                    hasPriorFlutterPreferences = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    hasWrappedKeys = true,
                    failureCode = "secure_storage_data_missing_requires_restore",
                ),
            ),
            case(
                name = "algorithm markers conflicting with active wrapped key are inconsistent",
                input = input(
                    namespacedConfig = oaepGcm,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveCbcWrappedKey = true,
                ),
                expected = SecureStorageProbeResult(
                    status = "inconsistent",
                    profile = "inconsistent",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    failureCode = "missing_wrapped_key",
                ),
            ),
            case(
                name = "OAEP GCM profile is ready",
                input = input(
                    namespacedConfig = oaepGcm,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveGcmWrappedKey = true,
                ),
                expected = readyOaepGcm(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                ),
            ),
            case(
                name = "prior Flutter preferences with complete OAEP GCM storage remain ready",
                input = input(
                    namespacedConfig = oaepGcm,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveGcmWrappedKey = true,
                    hasPriorFlutterPreferences = true,
                ),
                expected = readyOaepGcm(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                ),
            ),
            case(
                name = "OAEP GCM is supported at Android M boundary",
                input = input(
                    namespacedConfig = oaepGcm,
                    sdkInt = ANDROID_M_SDK,
                ),
                expected = readyOaepGcm(),
            ),
            case(
                name = "PKCS1 GCM profile is ready",
                input = input(
                    namespacedConfig = pkcs1Gcm,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveGcmWrappedKey = true,
                ),
                expected = readyPkcs1Gcm(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                ),
            ),
            case(
                name = "PKCS1 CBC profile remains ready below Android M",
                input = input(
                    namespacedConfig = pkcs1Cbc,
                    sdkInt = PRE_M_SDK,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveCbcWrappedKey = true,
                ),
                expected = readyPkcs1Cbc(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                ),
            ),
            case(
                name = "PKCS1 CBC profile remains ready on current Android",
                input = input(
                    namespacedConfig = pkcs1Cbc,
                    sdkInt = SUPPORTED_SDK,
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                    hasActiveCbcWrappedKey = true,
                ),
                expected = readyPkcs1Cbc(
                    hasEncryptedEntries = true,
                    hasWrappedKeys = true,
                ),
            ),
            case(
                name = "unknown algorithm pair is unsupported",
                input = input(
                    namespacedConfig = markerConfig(
                        keyCipher = "RSA_UNKNOWN",
                        storageCipher = "AES_UNKNOWN",
                    ),
                ),
                expected = SecureStorageProbeResult(
                    status = "unsupported",
                    profile = "unsupported",
                    keyCipher = "RSA_UNKNOWN",
                    storageCipher = "AES_UNKNOWN",
                    failureCode = "unsupported_algorithm",
                ),
            ),
            case(
                name = "OAEP CBC pair is unsupported",
                input = input(
                    namespacedConfig = markerConfig(
                        keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                        storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_CBC,
                    ),
                ),
                expected = SecureStorageProbeResult(
                    status = "unsupported",
                    profile = "unsupported",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_CBC,
                    failureCode = "unsupported_algorithm",
                ),
            ),
            case(
                name = "OAEP GCM is unsupported below Android M",
                input = input(
                    namespacedConfig = oaepGcm,
                    sdkInt = PRE_M_SDK,
                ),
                expected = SecureStorageProbeResult(
                    status = "unsupported",
                    profile = "unsupported",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    failureCode = "algorithm_not_supported",
                ),
            ),
            case(
                name = "PKCS1 GCM is unsupported below Android M",
                input = input(
                    namespacedConfig = pkcs1Gcm,
                    sdkInt = PRE_M_SDK,
                ),
                expected = SecureStorageProbeResult(
                    status = "unsupported",
                    profile = "unsupported",
                    keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_PKCS1,
                    storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
                    failureCode = "algorithm_not_supported",
                ),
            ),
        )

        private fun case(
            name: String,
            input: SecureStorageProbeInput,
            expected: SecureStorageProbeResult,
        ): Array<Any> = arrayOf(ClassificationCase(name, input, expected))

        private fun input(
            namespacedConfig: Map<String, *> = emptyMap<String, Any?>(),
            legacyConfig: Map<String, *> = emptyMap<String, Any?>(),
            sdkInt: Int = SUPPORTED_SDK,
            hasEncryptedEntries: Boolean = false,
            hasWrappedKeys: Boolean = false,
            hasActiveGcmWrappedKey: Boolean = false,
            hasActiveCbcWrappedKey: Boolean = false,
            hasActiveBiometricWrappedKey: Boolean = false,
            hasPriorFlutterPreferences: Boolean = false,
            expectsEncryptedEntries: Boolean = false,
        ) = SecureStorageProbeInput(
            namespacedConfig = namespacedConfig,
            legacyConfig = legacyConfig,
            sdkInt = sdkInt,
            hasEncryptedEntries = hasEncryptedEntries,
            hasWrappedKeys = hasWrappedKeys,
            hasActiveGcmWrappedKey = hasActiveGcmWrappedKey,
            hasActiveCbcWrappedKey = hasActiveCbcWrappedKey,
            hasActiveBiometricWrappedKey = hasActiveBiometricWrappedKey,
            hasPriorFlutterPreferences = hasPriorFlutterPreferences,
            expectsEncryptedEntries = expectsEncryptedEntries,
        )

        private fun markerConfig(
            keyCipher: String,
            storageCipher: String,
        ): Map<String, String> = mapOf(
            SecureStorageProbeClassifier.KEY_ALGORITHM_MARKER to keyCipher,
            SecureStorageProbeClassifier.STORAGE_ALGORITHM_MARKER to storageCipher,
        )

        private fun readyOaepGcm(
            hasEncryptedEntries: Boolean = false,
            hasWrappedKeys: Boolean = false,
        ) = SecureStorageProbeResult(
            status = "ready",
            profile = "oaepGcm",
            keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_OAEP,
            storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
            hasEncryptedEntries = hasEncryptedEntries,
            hasWrappedKeys = hasWrappedKeys,
        )

        private fun readyPkcs1Gcm(
            hasEncryptedEntries: Boolean = false,
            hasWrappedKeys: Boolean = false,
        ) = SecureStorageProbeResult(
            status = "ready",
            profile = "pkcs1Gcm",
            keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_PKCS1,
            storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_GCM,
            hasEncryptedEntries = hasEncryptedEntries,
            hasWrappedKeys = hasWrappedKeys,
        )

        private fun readyPkcs1Cbc(
            hasEncryptedEntries: Boolean = false,
            hasWrappedKeys: Boolean = false,
        ) = SecureStorageProbeResult(
            status = "ready",
            profile = "pkcs1Cbc",
            keyCipher = SecureStorageProbeClassifier.KEY_CIPHER_PKCS1,
            storageCipher = SecureStorageProbeClassifier.STORAGE_CIPHER_CBC,
            hasEncryptedEntries = hasEncryptedEntries,
            hasWrappedKeys = hasWrappedKeys,
        )
    }
}

internal data class ClassificationCase(
    private val name: String,
    val input: SecureStorageProbeInput,
    val expected: SecureStorageProbeResult,
) {
    override fun toString(): String = name
}
