package com.github.justlookatnow.ptmate

import android.content.Context

internal enum class LegacyMigrationPhase {
    backupConfirmed,
    legacyCleared,
    targetInitialized,
    restored,
}

internal enum class LegacyMigrationTarget {
    oaepGcm,
    plaintext,
}

internal class LegacySecureStorageMigrationState(
    context: Context,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun read(): Map<String, Any?> {
        val phase = preferences.getString(PHASE, null)
        val target = preferences.getString(TARGET, null)
        return mapOf(
            "status" to if (phase == null) "none" else "pending",
            "phase" to phase,
            "target" to target,
            "failureCode" to null,
        )
    }

    fun begin(target: String): Boolean {
        if (LegacyMigrationTarget.entries.none { it.name == target }) return false
        val currentTarget = preferences.getString(TARGET, null)
        if (currentTarget != null && currentTarget != target) return false
        if (preferences.getString(PHASE, null) != null) return currentTarget == target
        return preferences.edit()
            .putString(TARGET, target)
            .putString(PHASE, LegacyMigrationPhase.backupConfirmed.name)
            .commit() && matches(LegacyMigrationPhase.backupConfirmed, target)
    }

    fun advance(phase: LegacyMigrationPhase): Boolean {
        if (preferences.getString(TARGET, null) == null) return false
        val current = currentPhase()
        if (current != null && current.ordinal > phase.ordinal) return false
        if (current == phase) return true
        return preferences.edit().putString(PHASE, phase.name).commit() &&
            preferences.getString(PHASE, null) == phase.name
    }

    fun target(): String? = preferences.getString(TARGET, null)

    fun currentPhase(): LegacyMigrationPhase? =
        LegacyMigrationPhase.entries.firstOrNull {
            it.name == preferences.getString(PHASE, null)
        }

    fun hasPendingMigration(): Boolean = preferences.getString(PHASE, null) != null

    fun clear(): Boolean = preferences.edit().clear().commit() && preferences.all.isEmpty()

    private fun matches(phase: LegacyMigrationPhase, target: String): Boolean =
        preferences.getString(PHASE, null) == phase.name &&
            preferences.getString(TARGET, null) == target

    private companion object {
        const val PREFERENCES = "ptmate.android.legacy_migration.v1"
        const val PHASE = "phase"
        const val TARGET = "target"
    }
}
