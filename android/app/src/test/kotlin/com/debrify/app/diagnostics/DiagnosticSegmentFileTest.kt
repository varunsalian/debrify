package com.debrify.app.diagnostics

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class DiagnosticSegmentFileTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun wrappedCrashKeepsTheUnderlyingStackWithoutPrivateMessages() {
        val cause = IllegalStateException("PRIVATE_MEDIA_TITLE")
        cause.stackTrace = arrayOf(StackTraceElement("Player", "onDestroy", "Player.kt", 42))
        val error = RuntimeException("PRIVATE_URL", cause)
        val description = DiagnosticFailure.describe(error)
        assertTrue(description.contains("java.lang.RuntimeException"))
        assertTrue(description.contains("java.lang.IllegalStateException"))
        assertTrue(description.contains("Player.onDestroy(Player.kt:42)"))
        assertFalse(description.contains("PRIVATE"))
    }

    @Test fun criticalRecordSurvivesAbruptProcessTermination() {
        val file = temporary.newFile()
        val classpath = listOf(
            DiagnosticSegmentCrashProbe::class.java,
            DiagnosticSegmentFile::class.java,
            kotlin.Unit::class.java,
        ).map { java.io.File(it.protectionDomain.codeSource.location.toURI()).path }
            .distinct().joinToString(java.io.File.pathSeparator)
        val process = ProcessBuilder(
            java.io.File(System.getProperty("java.home"), "bin/java").path,
            "-cp", classpath, DiagnosticSegmentCrashProbe::class.java.name, file.path,
        ).redirectErrorStream(true).start()
        val exited = process.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)
        if (!exited) process.destroyForcibly()
        assertTrue("Crash probe timed out", exited)
        assertEquals(process.inputStream.bufferedReader().readText(), 17, process.exitValue())
        assertTrue(file.readText().contains("before_abrupt_exit"))
    }

    @Test fun durableAppendIsReadableImmediatelyAndIsolatesTornTail() {
        val file = temporary.newFile()
        file.writeText("{\"interrupted\":")
        DiagnosticSegmentFile.append(file, "{\"event\":\"destroy\"}", true, 4096)
        assertEquals(listOf("{\"interrupted\":", "{\"event\":\"destroy\"}"),
            file.readLines().filter { it.isNotBlank() })
    }

    @Test fun trimKeepsCompleteNewestRecordsWithinBudget() {
        val file = temporary.newFile()
        repeat(100) {
            DiagnosticSegmentFile.append(file, "{\"index\":$it}", true, 256)
        }
        assertTrue(file.length() <= 256)
        val lines = file.readLines().filter { it.isNotBlank() }
        assertEquals("{\"index\":99}", lines.last())
        assertTrue(lines.all { it.startsWith("{") && it.endsWith("}") })
        assertFalse(java.io.File(file.path + ".tmp").exists())
    }
}

object DiagnosticSegmentCrashProbe {
    @JvmStatic fun main(args: Array<String>) {
        DiagnosticSegmentFile.append(java.io.File(args[0]),
            "{\"event\":\"before_abrupt_exit\"}", true, 4096)
        Runtime.getRuntime().halt(17)
    }
}
