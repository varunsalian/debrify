package com.debrify.app.tv

import android.util.Log
import androidx.media3.common.Format
import androidx.media3.common.Timeline
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.MediaSource
import com.debrify.app.diagnostics.DiagnosticFileLog
import com.debrify.app.diagnostics.DiagnosticWorkQueue
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Both public AnalyticsListener callbacks and the real serialized diagnostic writer. */
@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvDecoderDisplayCharacterizationTest : TvPhase15OriginalTest() {
    private var logContext: Any? = null
    private var logAccepting: Any? = null
    private fun listener() = field("decoderAnalyticsListener") as AnalyticsListener
    private fun time(generation: Long? = null) = AnalyticsListener.EventTime(0, Timeline.EMPTY, 0,
        generation?.let { MediaSource.MediaPeriodId("period", it) }, 0, Timeline.EMPTY, 0, null, 0, 0)
    private fun format(mime: String = "video/avc", width: Int = 1920, height: Int = 1080) =
        Format.Builder().setSampleMimeType(mime).setWidth(width).setHeight(height).setFrameRate(24f).build()
    private fun input(value: Format) = listener().onVideoInputFormatChanged(time(), value, null)
    private fun decoder(name: String = "c2.android.avc.decoder", generation: Long? = null) =
        listener().onVideoDecoderInitialized(time(generation), name, 18, 9)
    private fun drain() {
        val latch = CountDownLatch(1)
        assertTrue((TvPlayerOriginalAccess.field(DiagnosticFileLog, "executor") as DiagnosticWorkQueue).submit { latch.countDown() })
        assertTrue("bounded diagnostic writer barrier", latch.await(5, TimeUnit.SECONDS))
    }
    private fun logs() = ShadowLog.getLogsForTag("DEBRIFY_PLAYER_DECODER").map { it.msg }
    private fun saved() = activity.filesDir.resolve("diagnostics").walkTopDown()
        .filter { it.isFile && it.extension == "jsonl" }.flatMap { it.readLines().asSequence() }
        .filter { it.isNotBlank() }.map(::JSONObject).filter { it.optString("event") == "decoder_initialized" }.toList()
    @Before fun captureDiagnostics() {
        logContext = TvPlayerOriginalAccess.field(DiagnosticFileLog, "applicationContext")
        logAccepting = TvPlayerOriginalAccess.field(DiagnosticFileLog, "accepting")
        TvPlayerOriginalAccess.set(DiagnosticFileLog, "applicationContext", activity.applicationContext)
        TvPlayerOriginalAccess.set(DiagnosticFileLog, "accepting", true)
        drain(); activity.filesDir.resolve("diagnostics").deleteRecursively(); ShadowLog.clear()
    }
    @After fun restoreDiagnostics() {
        drain(); TvPlayerOriginalAccess.set(DiagnosticFileLog, "applicationContext", logContext)
        TvPlayerOriginalAccess.set(DiagnosticFileLog, "accepting", logAccepting); TvPhase15Effects.onRelease = null
    }
    @Test fun inputFormatIsCachedForDecoderLoggingWhenPlayerHasNoFormat() {
        input(format()); decoder(generation = 42); drain()
        val expected = "generation=42 phase=stable status=software platform=android_tv backend=media3 codec=video/avc decoder=c2.android.avc.decoder output=surface_view resolution=1920x1080"
        assertEquals(listOf(expected), logs()); assertEquals(Log.INFO, ShadowLog.getLogsForTag("DEBRIFY_PLAYER_DECODER").single().type)
        assertEquals(1, saved().size); assertEquals(expected, saved().single().getString("message"))
        assertEquals("android_tv_player", saved().single().getString("source")); assertEquals("info", saved().single().getString("level"))
    }
    @Test fun playerFormatTakesPrecedenceOverTheCachedInputAndIsReadPerCallback() {
        input(format()); videoFormat = format("video/hevc", 3840, 2160); decoder("OMX.vendor.hevc.decoder", 7)
        videoFormat = format("video/vp9", 1280, 720); decoder("OMX.vendor.vp9.decoder", 8)
        assertEquals(listOf(
            "generation=7 phase=stable status=unknown platform=android_tv backend=media3 codec=video/hevc decoder=OMX.vendor.hevc.decoder output=surface_view resolution=3840x2160",
            "generation=8 phase=stable status=unknown platform=android_tv backend=media3 codec=video/vp9 decoder=OMX.vendor.vp9.decoder output=surface_view resolution=1280x720"), logs())
    }
    @Test fun absentFormatAndPeriodUseUnknownCodecZeroResolutionAndMinusOneGeneration() {
        set("player", null); decoder("vendor.broken")
        assertEquals(listOf("generation=-1 phase=stable status=unknown platform=android_tv backend=media3 codec=unknown decoder=vendor.broken output=surface_view resolution=0x0"), logs())
    }
    @Test fun laterInputFormatReplacesTheCacheEvenWhenTheDisplayControllerIsAbsent() {
        set("displayModeController", null); input(format()); input(format("video/av01", 720, 480)); decoder()
        assertTrue(logs().single().endsWith("codec=video/av01 decoder=c2.android.avc.decoder output=surface_view resolution=720x480"))
    }
    @Test fun inputCallbackForwardsAnIncompleteFormatToClearTheOldDisplayPreference() {
        val display = TvDisplayModeController(activity, TvContentDisplayMatchMode.FRAME_RATE)
        assertNotNull("real controller has a display mode", TvPlayerOriginalAccess.field(display, "baseMode"))
        set("displayModeController", display)
        activity.window.attributes = activity.window.attributes.apply { preferredDisplayModeId = 97 }
        input(Format.Builder().build())
        assertEquals(0, activity.window.attributes.preferredDisplayModeId)
    }
    @Test fun destroyClearsAndDropsDisplayOwnershipBeforeReleasingEffectsAndPlayer() {
        val display = TvDisplayModeController(activity, TvContentDisplayMatchMode.FRAME_RATE)
        set("displayModeController", display)
        activity.window.attributes = activity.window.attributes.apply { preferredDisplayModeId = 97 }
        set("nightModeIndex", 1); initialize()
        val order = mutableListOf<String>()
        TvPhase15Effects.onRelease = {
            assertEquals("window was reset before effect teardown", 0, activity.window.attributes.preferredDisplayModeId)
            assertNull("display reference dropped before effect teardown", field("displayModeController"))
            order.add("effect")
        }
        probe.onEvent = { if (it == "release") order.add("player") }
        destroyNow()
        assertEquals(listOf("effect", "player"), order); assertNull(effect())
    }
    @Test fun pauseAndStopLeaveTheDisplayPreferenceOwnedUntilDestroy() {
        val display = TvDisplayModeController(activity, TvContentDisplayMatchMode.FRAME_RATE)
        set("displayModeController", display)
        activity.window.attributes = activity.window.attributes.apply { preferredDisplayModeId = 97 }
        lifecycle.pause().stop()
        assertSame(display, field("displayModeController")); assertEquals(97, activity.window.attributes.preferredDisplayModeId)
        destroyNow(); assertNull(field("displayModeController")); assertEquals(0, activity.window.attributes.preferredDisplayModeId)
    }
}
