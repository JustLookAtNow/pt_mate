package com.github.justlookatnow.ptmate

/** Collects capability diagnostics without retaining exceptions or cryptographic material. */
internal class SecureStorageCapabilityProbe(
    private val nanoTime: () -> Long = System::nanoTime,
) {
    enum class Step(val wireName: String) {
        KEY_GENERATION("keyGeneration"),
        KEYSTORE_LOAD("keyStoreLoad"),
        CERTIFICATE_READ("certificateRead"),
        PRIVATE_KEY_READ("privateKeyRead"),
        SECRET_GENERATION("secretGeneration"),
        OAEP_ENCRYPT("oaepEncrypt"),
        OAEP_DECRYPT("oaepDecrypt"),
        GCM_ENCRYPT("gcmEncrypt"),
        GCM_DECRYPT("gcmDecrypt"),
    }

    private var currentStep: Step? = null

    fun <T> step(step: Step, operation: () -> T): T {
        currentStep = step
        return operation()
    }

    fun run(
        isExplicitlyUnsupported: (Throwable) -> Boolean,
        operation: SecureStorageCapabilityProbe.() -> Unit,
    ): Map<String, Any?> {
        val started = nanoTime()
        return try {
            operation()
            mapOf(
                "status" to "supported",
                "failureCode" to null,
                "elapsedMs" to (nanoTime() - started) / 1_000_000,
            )
        } catch (error: Throwable) {
            val unsupported = isExplicitlyUnsupported(error)
            mapOf(
                "status" to if (unsupported) "unsupported" else "unavailable",
                "failureCode" to if (unsupported) "unsupported_algorithm" else "capability_probe_failed",
                "failureStep" to currentStep?.wireName,
                "failureType" to error.javaClass.simpleName,
                "elapsedMs" to (nanoTime() - started) / 1_000_000,
            )
        }
    }
}
