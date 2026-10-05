package com.github.justlookatnow.ptmate

/** Metadata that must disappear with explicitly discarded legacy ciphertext. */
internal object LegacySecureStorageMetadata {
    private val keys = setOf(
        "flutter.secureStorage.transaction.sensitiveManifest.v1",
        "flutter.secureStorage.pendingCompanionPreferences.v1",
        "flutter.secureStorage.namespaceInitialized.v1",
        "flutter.secureStorage.encryptedEntriesExpected.v1",
        "flutter.cookieCloud.secrets.v2.pendingCleanup",
    )

    fun clear(
        commitRemoval: (Set<String>) -> Boolean,
        contains: (String) -> Boolean,
    ): Boolean = commitRemoval(keys) && keys.none(contains)
}
