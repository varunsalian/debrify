package com.debrify.app.tv

import android.net.Uri
import android.util.Log
import com.debrify.app.diagnostics.DiagnosticFileLog
import com.debrify.app.diagnostics.DiagnosticWorkQueue
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.MediaCodecInfoBuilder
import org.robolectric.shadows.ShadowLog
import org.robolectric.shadows.ShadowMediaCodecList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class TvStartupHelpersCharacterizationTest : TvPhase2OriginalTest() {
    @Test fun originsRequireHttpHostNormalizeCaseAndPreserveExplicitPorts() {
        for ((url, expected) in listOf("HTTP://Example.test/a" to "http://example.test:80", "https://EXAMPLE.test/a" to "https://example.test:443",
            "https://example.test:8443/a" to "https://example.test:8443", "http://u:p@host:0/a" to "http://host:0",
            "file:///a" to null, "//host/a" to null, "https:/a" to null, "" to null))
            assertEquals(expected, call("originKey", arrayOf(Uri::class.java), Uri.parse(url)))
    }

    @Test fun protectedOriginsSkipBlankAndNonHttpAndDeduplicateOriginsOnly() {
        assertEquals(emptySet<String>(), call("buildProtectedMediaOrigins", arrayOf(listType), emptyList<PlaybackItem>()))
        val urls = listOf(" ", "file:///a", "https://EXAMPLE.test/a", "https://example.test/b", "http://example.test/b", "https://example.test:8443/a")
        assertEquals(setOf("https://example.test:443", "http://example.test:80", "https://example.test:8443"),
            call("buildProtectedMediaOrigins", arrayOf(listType), urls.map { p2Item(url = it) }))
    }

    @Test fun diagnosticProviderPinsBlankSanitizationUsCaseAndThirtyTwoLimit() {
        for ((value, expected) in listOf(null to "-", "" to "-", "  " to "-", "TorBox.IP-TV_1" to "torbox.ip-tv_1",
            " A/Ü! " to "_a____", "A".repeat(33) to "a".repeat(32)))
            assertEquals(expected, call("diagnosticProvider", arrayOf(stringType), value))
    }

    @Test fun pikpakDetectionKeepsProviderCaseInsensitiveButUrlSubstringCaseSensitive() {
        assertEquals(false, call("isPikPakPlaybackItem", arrayOf(PlaybackItem::class.java), null))
        for ((item, expected) in listOf(p2Item(provider = "PIKPAK") to true, p2Item(url = "https://x.mypikpak.com/a") to true,
            p2Item(url = "https://MYPikpak.com/a") to false, p2Item(provider = "other") to false))
            assertEquals(expected, call("isPikPakPlaybackItem", arrayOf(PlaybackItem::class.java), item))
    }

    @Test fun decoderMarkersAreSoftwareAndPreQUnknownHasNoCodecLookup() {
        for (name in listOf("OMX.google.decoder", "OMX.android.decoder", "c2.android.avc", "C2.GOOGLE.AVC", "vendor.ffmpeg.decoder"))
            assertEquals("software", call("androidDecoderStatus", arrayOf(stringType), name))
        assertEquals("unknown", call("androidDecoderStatus", arrayOf(stringType), "vendor.hw"))
        assertEquals("unknown", call("androidDecoderStatus", arrayOf(stringType), ""))
    }

    @Test @Config(sdk = [29]) fun decoderQUsesCaseInsensitiveCodecFlagsAndUnknownFallback() {
        ShadowMediaCodecList.addCodec(MediaCodecInfoBuilder.newBuilder().setName("vendor.sw").setIsSoftwareOnly(true).setIsHardwareAccelerated(true).build())
        ShadowMediaCodecList.addCodec(MediaCodecInfoBuilder.newBuilder().setName("vendor.hw").setIsSoftwareOnly(false).setIsHardwareAccelerated(true).build())
        ShadowMediaCodecList.addCodec(MediaCodecInfoBuilder.newBuilder().setName("vendor.neither").setIsSoftwareOnly(false).setIsHardwareAccelerated(false).build())
        assertEquals("software", call("androidDecoderStatus", arrayOf(stringType), "VENDOR.SW"))
        assertEquals("hardware", call("androidDecoderStatus", arrayOf(stringType), "VENDOR.HW"))
        assertEquals("unknown", call("androidDecoderStatus", arrayOf(stringType), "vendor.neither"))
        assertEquals("unknown", call("androidDecoderStatus", arrayOf(stringType), "missing"))
        ShadowMediaCodecList.reset()
        ShadowMediaCodecList.addCodec(null) // A platform codec lookup failure is deliberately caught.
        assertEquals("unknown", call("androidDecoderStatus", arrayOf(stringType), "vendor.broken"))
    }

    @Test fun startupLogWritesStructuredEventsAndWarningOrDebugTag() {
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        val initialized = TvPlayerOriginalAccess.field(DiagnosticFileLog, "initialized") as AtomicBoolean
        val crashInstalled = TvPlayerOriginalAccess.field(DiagnosticFileLog, "crashHandlerInstalled") as AtomicBoolean
        val previousInitialized = initialized.get(); val previousCrashInstalled = crashInstalled.get()
        val previousContext = TvPlayerOriginalAccess.field(DiagnosticFileLog, "applicationContext")
        val previousAccepting = TvPlayerOriginalAccess.field(DiagnosticFileLog, "accepting")
        val previousPruned = TvPlayerOriginalAccess.field(DiagnosticFileLog, "lastPrunedSegment")
        try {
            initialized.set(false)
            DiagnosticFileLog.initialize(RuntimeEnvironment.getApplication())
            defaultCall("startupLog", arrayOf(stringType, boolType), 2, "normal", false)
            call("startupLog", arrayOf(stringType, boolType), "problem", true)
            val drained = CountDownLatch(1)
            (TvPlayerOriginalAccess.field(DiagnosticFileLog, "executor") as DiagnosticWorkQueue).submit { drained.countDown() }
            assertTrue("diagnostic queue must drain", drained.await(5, TimeUnit.SECONDS))
            val events = RuntimeEnvironment.getApplication().filesDir.resolve("diagnostics").walkTopDown()
                .filter { it.isFile && it.extension == "jsonl" }.flatMap { it.readLines().asSequence() }
                .filter { it.isNotBlank() }.map { JSONObject(it) }.filter { it.optString("event") == "startup_gate" }.toList()
            assertEquals(2, events.size)
            assertEquals(listOf("android_tv_player", "android_tv_player"), events.map { it.getString("source") })
            assertEquals(listOf("normal", "problem"), events.map { it.getString("message") })
            assertEquals(listOf("info", "warning"), events.map { it.getString("level") })
            val logs = ShadowLog.getLogsForTag("DebrifyStartupGate")
            assertEquals(listOf(Log.DEBUG, Log.WARN), logs.map { it.type })
            assertEquals(listOf("normal", "problem"), logs.map { it.msg })
        } finally {
            Thread.setDefaultUncaughtExceptionHandler(previousHandler)
            initialized.set(previousInitialized); crashInstalled.set(previousCrashInstalled)
            TvPlayerOriginalAccess.set(DiagnosticFileLog, "applicationContext", previousContext)
            TvPlayerOriginalAccess.set(DiagnosticFileLog, "accepting", previousAccepting)
            TvPlayerOriginalAccess.set(DiagnosticFileLog, "lastPrunedSegment", previousPruned)
        }
    }
}
