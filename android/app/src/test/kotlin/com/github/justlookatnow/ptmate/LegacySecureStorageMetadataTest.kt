package com.github.justlookatnow.ptmate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LegacySecureStorageMetadataTest {
    @Test
    fun clearsDeletedRevisionReferencesButPreservesUserSettings() {
        val entries = mutableMapOf(
            "flutter.secureStorage.transaction.sensitiveManifest.v1" to "old-revision",
            "flutter.secureStorage.pendingCompanionPreferences.v1" to "old-journal",
            "flutter.secureStorage.encryptedEntriesExpected.v1" to "true",
            "flutter.site.configs" to "sites",
            "flutter.themeMode" to "dark",
        )
        assertTrue(LegacySecureStorageMetadata.clear(
            commitRemoval = { keys -> keys.forEach { entries.remove(it) }; true },
            contains = entries::containsKey,
        ))
        assertEquals(mapOf("flutter.site.configs" to "sites", "flutter.themeMode" to "dark"), entries)
    }

    @Test
    fun rejectsFailedCommitEvenIfMemoryAlreadyChanged() {
        assertFalse(LegacySecureStorageMetadata.clear({ false }, { false }))
    }

    @Test
    fun rejectsCommitThatLeavesStaleJournal() {
        assertFalse(LegacySecureStorageMetadata.clear(
            { true },
            { it == "flutter.secureStorage.pendingCompanionPreferences.v1" },
        ))
    }
}
