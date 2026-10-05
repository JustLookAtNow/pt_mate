package com.github.justlookatnow.ptmate

/*
 * The legacy cipher formats implemented here are derived from
 * flutter_secure_storage 10.3.1.
 *
 * BSD 3-Clause License
 * Copyright 2017 German Saprykin. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holder nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * This importer is intentionally read-only. It never generates a legacy key,
 * wraps a key, writes ciphertext, or changes the legacy preference files.
 */

import android.content.Context
import android.os.Build
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.PrivateKey
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec

internal class LegacySecureStorageImporter(
    private val source: LegacySecureStorageReadSource,
    private val decodeBase64: (String) -> ByteArray = {
        Base64.decode(it, Base64.DEFAULT)
    },
) {
    constructor(context: Context) : this(AndroidLegacySecureStorageReadSource(context))

    fun readAll(profile: String): LegacySecureStorageImportResult {
        if (profile !in setOf("pkcs1Gcm", "pkcs1Cbc")) {
            return LegacySecureStorageImportResult.failure("legacy_profile_required")
        }

        return try {
            val aesKey = when (val key = source.readAesKey(profile)) {
                LegacyAesKeyReadResult.MissingPrivateKey ->
                    return LegacySecureStorageImportResult.failure("legacy_private_key_missing")
                LegacyAesKeyReadResult.MissingWrappedKey ->
                    return LegacySecureStorageImportResult.failure("legacy_wrapped_key_missing")
                is LegacyAesKeyReadResult.Ready -> key.bytes
            }

            val values = linkedMapOf<String, String>()
            val entries = source.readEncryptedEntries()
            for ((storedKey, storedValue) in entries) {
                if (storedValue !is String || !storedKey.startsWith("${KEY_PREFIX}_")) {
                    return LegacySecureStorageImportResult.failure("legacy_entry_invalid")
                }
                val logicalKey = storedKey.removePrefix("${KEY_PREFIX}_")
                if (logicalKey.isEmpty()) {
                    return LegacySecureStorageImportResult.failure("legacy_entry_invalid")
                }
                val ciphertext = decodeBase64(storedValue)
                val plaintext = when (profile) {
                    "pkcs1Gcm" -> LegacySecureStorageCipher.decryptGcm(aesKey, ciphertext)
                    else -> LegacySecureStorageCipher.decryptCbc(aesKey, ciphertext)
                }
                values[logicalKey] = String(plaintext, StandardCharsets.UTF_8)
            }
            LegacySecureStorageImportResult(
                status = "ready",
                profile = profile,
                values = values,
            )
        } catch (_: Throwable) {
            LegacySecureStorageImportResult.failure("legacy_decryption_failed")
        }
    }

    private companion object {
        const val KEY_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    }
}

/** The importer receives read capabilities only; no legacy write API exists. */
internal interface LegacySecureStorageReadSource {
    fun readAesKey(profile: String): LegacyAesKeyReadResult
    fun readEncryptedEntries(): Map<String, *>
}

internal sealed interface LegacyAesKeyReadResult {
    data class Ready(val bytes: ByteArray) : LegacyAesKeyReadResult
    data object MissingPrivateKey : LegacyAesKeyReadResult
    data object MissingWrappedKey : LegacyAesKeyReadResult
}

private class AndroidLegacySecureStorageReadSource(
    private val context: Context,
) : LegacySecureStorageReadSource {
    override fun readAesKey(profile: String): LegacyAesKeyReadResult {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE_PROVIDER).apply { load(null) }
        val privateKey = keyStore.getKey(legacyAlias(), null) as? PrivateKey
            ?: return LegacyAesKeyReadResult.MissingPrivateKey
        val wrappedKeyName = if (profile == "pkcs1Gcm") GCM_WRAPPED_KEY else CBC_WRAPPED_KEY
        val wrappedKeyText = context.getSharedPreferences(
            SECURE_STORAGE_KEY_PREFS,
            Context.MODE_PRIVATE,
        ).getString(wrappedKeyName, null)
            ?: return LegacyAesKeyReadResult.MissingWrappedKey
        val provider = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            "AndroidOpenSSL"
        } else {
            "AndroidKeyStoreBCWorkaround"
        }
        val unwrapped = Cipher.getInstance("RSA/ECB/PKCS1Padding", provider).run {
            init(Cipher.UNWRAP_MODE, privateKey)
            unwrap(
                Base64.decode(wrappedKeyText, Base64.DEFAULT),
                "AES",
                Cipher.SECRET_KEY,
            ) as javax.crypto.SecretKey
        }
        return LegacyAesKeyReadResult.Ready(unwrapped.encoded)
    }

    override fun readEncryptedEntries(): Map<String, *> =
        context.getSharedPreferences(
            SECURE_STORAGE_DATA_PREFS,
            Context.MODE_PRIVATE,
        ).all

    private fun legacyAlias(): String =
        "${context.packageName}.FlutterSecureStoragePluginKey"

    private companion object {
        const val ANDROID_KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val SECURE_STORAGE_DATA_PREFS = "FlutterSecureStorage"
        const val SECURE_STORAGE_KEY_PREFS = "FlutterSecureKeyStorage"
        const val GCM_WRAPPED_KEY =
            "AESVGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
        const val CBC_WRAPPED_KEY =
            "VGhpcyBpcyB0aGUga2V5IGZvciBhIHNlY3VyZSBzdG9yYWdlIEFFUyBLZXkK"
    }
}

internal object LegacySecureStorageCipher {
    fun decryptGcm(key: ByteArray, input: ByteArray): ByteArray {
        require(input.size > GCM_IV_SIZE) { "legacy_gcm_payload_too_short" }
        val iv = input.copyOfRange(0, GCM_IV_SIZE)
        val payload = input.copyOfRange(GCM_IV_SIZE, input.size)
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(
                Cipher.DECRYPT_MODE,
                javax.crypto.spec.SecretKeySpec(key, "AES"),
                GCMParameterSpec(128, iv),
            )
            doFinal(payload)
        }
    }

    fun decryptCbc(key: ByteArray, input: ByteArray): ByteArray {
        require(input.size > CBC_IV_SIZE) { "legacy_cbc_payload_too_short" }
        val iv = input.copyOfRange(0, CBC_IV_SIZE)
        val payload = input.copyOfRange(CBC_IV_SIZE, input.size)
        // PKCS#5 and PKCS#7 padding are byte-for-byte identical for AES's
        // 16-byte block size. PKCS5 is also available to local JVM tests.
        return Cipher.getInstance("AES/CBC/PKCS5Padding").run {
            init(
                Cipher.DECRYPT_MODE,
                javax.crypto.spec.SecretKeySpec(key, "AES"),
                IvParameterSpec(iv),
            )
            doFinal(payload)
        }
    }

    private const val GCM_IV_SIZE = 12
    private const val CBC_IV_SIZE = 16
}

internal data class LegacySecureStorageImportResult(
    val status: String,
    val profile: String? = null,
    val values: Map<String, String> = emptyMap(),
    val failureCode: String? = null,
) {
    fun toMethodChannelMap(): Map<String, Any?> = mapOf(
        "status" to status,
        "profile" to profile,
        "values" to values,
        "failureCode" to failureCode,
    )

    companion object {
        fun failure(code: String) = LegacySecureStorageImportResult(
            status = "unavailable",
            failureCode = code,
        )
    }
}
