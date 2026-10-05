package com.github.justlookatnow.ptmate

import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LegacySecureStorageImporterTest {
    @Test
    fun `imports fixed PKCS1 GCM ciphertext fixture`() {
        val source = FakeReadSource(
            keyResult = LegacyAesKeyReadResult.Ready(AES_KEY),
            entries = mapOf(
                storedKey("site.cookie.demo") to
                    "CgsMDQ4PEBESExQV6qZOZGaBY6o4b4Swym4f11pMlXma70w3WGkX5/fhrRxj",
            ),
        )

        val result = importer(source).readAll("pkcs1Gcm")

        assertEquals("ready", result.status)
        assertEquals("legacy-gcm-凭据", result.values["site.cookie.demo"])
        assertEquals(1, source.keyReadCount)
        assertEquals(1, source.entriesReadCount)
    }

    @Test
    fun `imports fixed PKCS1 CBC ciphertext fixture`() {
        val source = FakeReadSource(
            keyResult = LegacyAesKeyReadResult.Ready(AES_KEY),
            entries = mapOf(
                storedKey("downloader.password.demo") to
                    "EBESExQVFhcYGRobHB0eH7ZvKrieZkmS8QbarM6NBnEzNKpVPQZGs0/EiS/45RwC",
            ),
        )

        val result = importer(source).readAll("pkcs1Cbc")

        assertEquals("ready", result.status)
        assertEquals("legacy-cbc-credential", result.values["downloader.password.demo"])
    }

    @Test
    fun `wrong key rejects the whole snapshot`() {
        val source = FakeReadSource(
            keyResult = LegacyAesKeyReadResult.Ready(ByteArray(16) { 0x7f }),
            entries = mapOf(
                storedKey("site.cookie.demo") to
                    "CgsMDQ4PEBESExQV6qZOZGaBY6o4b4Swym4f11pMlXma70w3WGkX5/fhrRxj",
            ),
        )

        val result = importer(source).readAll("pkcs1Gcm")

        assertEquals("unavailable", result.status)
        assertEquals("legacy_decryption_failed", result.failureCode)
        assertTrue(result.values.isEmpty())
    }

    @Test
    fun `one damaged entry rejects all previously decrypted entries`() {
        val source = FakeReadSource(
            keyResult = LegacyAesKeyReadResult.Ready(AES_KEY),
            entries = linkedMapOf(
                storedKey("site.cookie.demo") to
                    "CgsMDQ4PEBESExQV6qZOZGaBY6o4b4Swym4f11pMlXma70w3WGkX5/fhrRxj",
                storedKey("site.apiKey.demo") to "AAECAwQ=",
            ),
        )

        val result = importer(source).readAll("pkcs1Gcm")

        assertEquals("unavailable", result.status)
        assertEquals("legacy_decryption_failed", result.failureCode)
        assertTrue(result.values.isEmpty())
    }

    @Test
    fun `missing legacy alias is reported without reading ciphertext`() {
        val source = FakeReadSource(
            keyResult = LegacyAesKeyReadResult.MissingPrivateKey,
            entries = emptyMap<String, String>(),
        )

        val result = importer(source).readAll("pkcs1Gcm")

        assertEquals("legacy_private_key_missing", result.failureCode)
        assertEquals(1, source.keyReadCount)
        assertEquals(0, source.entriesReadCount)
    }

    @Test
    fun `missing wrapped key is reported without reading ciphertext`() {
        val source = FakeReadSource(
            keyResult = LegacyAesKeyReadResult.MissingWrappedKey,
            entries = emptyMap<String, String>(),
        )

        val result = importer(source).readAll("pkcs1Cbc")

        assertEquals("legacy_wrapped_key_missing", result.failureCode)
        assertEquals(1, source.keyReadCount)
        assertEquals(0, source.entriesReadCount)
    }

    @Test
    fun `read source exposes no legacy mutation and unsupported profile reads nothing`() {
        val source = FakeReadSource(
            keyResult = LegacyAesKeyReadResult.Ready(AES_KEY),
            entries = emptyMap<String, String>(),
        )

        val result = importer(source).readAll("oaepGcm")

        assertEquals("legacy_profile_required", result.failureCode)
        assertEquals(0, source.keyReadCount)
        assertEquals(0, source.entriesReadCount)
        assertEquals(
            setOf("readAesKey", "readEncryptedEntries"),
            LegacySecureStorageReadSource::class.java.declaredMethods.map { it.name }.toSet(),
        )
    }

    private fun importer(source: LegacySecureStorageReadSource) =
        LegacySecureStorageImporter(source, Base64.getDecoder()::decode)

    private fun storedKey(logicalKey: String) = "${KEY_PREFIX}_$logicalKey"

    private class FakeReadSource(
        private val keyResult: LegacyAesKeyReadResult,
        private val entries: Map<String, *>,
    ) : LegacySecureStorageReadSource {
        var keyReadCount = 0
            private set
        var entriesReadCount = 0
            private set

        override fun readAesKey(profile: String): LegacyAesKeyReadResult {
            keyReadCount++
            return keyResult
        }

        override fun readEncryptedEntries(): Map<String, *> {
            entriesReadCount++
            return entries
        }
    }

    private companion object {
        val AES_KEY: ByteArray = byteArrayOf(
            0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
            0x88.toByte(), 0x99.toByte(), 0xaa.toByte(), 0xbb.toByte(),
            0xcc.toByte(), 0xdd.toByte(), 0xee.toByte(), 0xff.toByte(),
        )
        const val KEY_PREFIX =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    }
}
