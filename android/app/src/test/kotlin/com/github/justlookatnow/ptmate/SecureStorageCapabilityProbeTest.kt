package com.github.justlookatnow.ptmate

import java.util.ArrayDeque
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

internal class SecureStorageCapabilityProbeTest {
    @Test
    fun reportsEveryFailedStepWithoutExposingSensitiveDetails() {
        for (failingStep in enumValues<SecureStorageCapabilityProbe.Step>()) {
            val probe = SecureStorageCapabilityProbe(
                clock(1_000_000L, 7_000_000L),
            )

            val result = probe.run(
                isExplicitlyUnsupported = { false },
                operation = {
                    enumValues<SecureStorageCapabilityProbe.Step>().forEach { candidate ->
                        step(candidate) {
                            if (candidate == failingStep) {
                                throw IllegalStateException(SENSITIVE_FAILURE_MESSAGE)
                            }
                        }
                    }
                },
            )

            assertEquals("unavailable", result["status"])
            assertEquals("capability_probe_failed", result["failureCode"])
            assertEquals(failingStep.wireName, result["failureStep"])
            assertEquals("IllegalStateException", result["failureType"])
            assertEquals(6L, result["elapsedMs"])
            assertEquals(
                setOf(
                    "status",
                    "failureCode",
                    "failureStep",
                    "failureType",
                    "elapsedMs",
                ),
                result.keys,
            )
            assertNoSensitiveDetails(result)
        }
    }

    @Test
    fun keepsUnsupportedStatusAndCodeForExplicitlyUnsupportedFailures() {
        var classifiedError: Throwable? = null
        val probe = SecureStorageCapabilityProbe(
            clock(3_000_000L, 5_000_000L),
        )

        val result = probe.run(
            isExplicitlyUnsupported = { error ->
                classifiedError = error
                error is IllegalArgumentException
            },
            operation = {
                step(SecureStorageCapabilityProbe.Step.OAEP_DECRYPT) {
                    throw IllegalArgumentException(SENSITIVE_FAILURE_MESSAGE)
                }
            },
        )

        assertTrue(classifiedError is IllegalArgumentException)
        assertEquals("unsupported", result["status"])
        assertEquals("unsupported_algorithm", result["failureCode"])
        assertEquals("oaepDecrypt", result["failureStep"])
        assertEquals("IllegalArgumentException", result["failureType"])
        assertEquals(2L, result["elapsedMs"])
        assertNoSensitiveDetails(result)
    }

    @Test
    fun reportsSuccessfulProbeElapsedTimeWithoutFailureDetails() {
        val probe = SecureStorageCapabilityProbe(
            clock(10_000_000L, 22_000_000L),
        )

        val result = probe.run(
            isExplicitlyUnsupported = { false },
            operation = {
                enumValues<SecureStorageCapabilityProbe.Step>().forEach { candidate ->
                    step(candidate) {}
                }
            },
        )

        assertEquals(
            mapOf(
                "status" to "supported",
                "failureCode" to null,
                "elapsedMs" to 12L,
            ),
            result,
        )
        assertFalse(result.containsKey("failureStep"))
        assertFalse(result.containsKey("failureType"))
    }

    @Test
    fun reportsZeroElapsedMillisecondsNormally() {
        val probe = SecureStorageCapabilityProbe(
            clock(42L, 42L),
        )

        val result = probe.run(
            isExplicitlyUnsupported = { false },
            operation = {},
        )

        assertEquals("supported", result["status"])
        assertEquals(0L, result["elapsedMs"])
        assertEquals(
            setOf("status", "failureCode", "elapsedMs"),
            result.keys,
        )
    }

    private fun assertNoSensitiveDetails(result: Map<String, Any?>) {
        val rendered = result.toString()
        assertFalse(rendered.contains(SENSITIVE_MESSAGE_TOKEN))
        assertFalse(rendered.contains(SENSITIVE_KEY_ALIAS))
        assertFalse(rendered.contains(EXCEPTION_STACK_MARKER))
        assertFalse(rendered.contains("at com.github.justlookatnow"))
        assertTrue(result.values.none { it is Throwable })
        assertTrue(
            result.keys.none { key ->
                listOf("message", "stack", "alias").any { part -> part in key }
            },
        )
    }

    private fun clock(vararg timestamps: Long): () -> Long {
        val remaining = ArrayDeque(timestamps.toList())
        return {
            check(remaining.isNotEmpty()) { "unexpected clock read" }
            remaining.removeFirst()
        }
    }

    private companion object {
        private const val SENSITIVE_MESSAGE_TOKEN = "sensitive-ciphertext-do-not-leak"
        private const val SENSITIVE_KEY_ALIAS = "sensitive-key-alias-do-not-leak"
        private const val EXCEPTION_STACK_MARKER = "sensitive-stack-marker-do-not-leak"
        private const val SENSITIVE_FAILURE_MESSAGE =
            "$SENSITIVE_MESSAGE_TOKEN $SENSITIVE_KEY_ALIAS $EXCEPTION_STACK_MARKER"
    }
}
