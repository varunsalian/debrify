package com.debrify.app.tv

import android.net.Uri
import androidx.media3.common.Timeline
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase19DiagnosticsShadow::class, TvPhase19GateShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvMediaPipelineAnalyticsTest : TvPhase19PipelineTest() {
    @org.junit.Before fun resetTrace() { TvPhase19CallbackTrace.events.clear(); TvPhase19CallbackTrace.onManual = null }
    private fun time() = AnalyticsListener.EventTime(0, Timeline.EMPTY, 0, null, 0, Timeline.EMPTY, 0, null, 0, 0)
    private fun diag() = field("iptvDiagAnalyticsListener") as AnalyticsListener
    @Test fun firstFrameClearsRestoreRestartsTickerThenCommitsBothGates() {
        val diagnostics = field("iptvTuneDiagnostics") as IptvTuneDiagnostics
        diagnostics.onTuneStart("Test", "https://p19.test/live", true, false)
        set("manualSourceRestoreInProgress", true)
        val handler = field("progressHandler") as android.os.Handler
        handler.removeCallbacksAndMessages(null)
        TvPhase19CallbackTrace.events.clear()
        TvPhase19CallbackTrace.onManual = { assertFalse(field("manualSourceRestoreInProgress") as Boolean); assertTrue("ticker restarted before manual commit", TvPlaylistUiQueue.pending(handler, field("progressRunnable") as Runnable)) }
        diag().onRenderedFirstFrame(time(), Any(), 123)
        assertEquals(listOf("server:first_frame", "diagnostic", "manual commit", "startup commit"), TvPhase19CallbackTrace.events)
        assertFalse(field("manualSourceRestoreInProgress") as Boolean)
        assertTrue("restore restarts progress", TvPlaylistUiQueue.pending(handler, field("progressRunnable") as Runnable))
        assertEquals(true, required(diagnostics, "firstFrameLogged"))
    }
    @Test fun firstFrameWithoutRestoreDoesNotRestartAnAbsentTicker() {
        set("manualSourceRestoreInProgress", false)
        val handler = field("progressHandler") as android.os.Handler; handler.removeCallbacksAndMessages(null)
        TvPhase19CallbackTrace.events.clear(); diag().onRenderedFirstFrame(time(), Any(), 123)
        assertEquals(listOf("server:first_frame", "diagnostic", "manual commit", "startup commit"), TvPhase19CallbackTrace.events)
        assertFalse(TvPlaylistUiQueue.pending(handler, field("progressRunnable") as Runnable))
    }
    @Test fun loadCompletedForwardsTheExactByteCount() {
        val diagnostics = field("iptvTuneDiagnostics") as IptvTuneDiagnostics
        diagnostics.onTuneStart("Test", "https://p19.test/live", true, false)
        val spec = androidx.media3.datasource.DataSpec(Uri.parse("https://p19.test/live"))
        diag().onLoadCompleted(time(), LoadEventInfo(1, spec, spec.uri, emptyMap(), 2, 3, 12345), MediaLoadData(1))
        assertEquals(12345L, required(diagnostics, "bytesLoaded"))
        diag().onLoadCompleted(time(), LoadEventInfo(2, spec, spec.uri, emptyMap(), 2, 3, 5), MediaLoadData(1))
        assertEquals(12350L, required(diagnostics, "bytesLoaded"))
    }
    @Test fun playbackAndAnalyticsListenersAreAttachedInOrder() {
        buildPipeline()
        val holders = required(required(built, "listeners"), "listeners") as Set<*>
        val listenerOrder = holders.map { required(it!!, "listener") }
        assertTrue(listenerOrder.indexOf(field("playbackListener")) >= 0)
        assertTrue(listenerOrder.indexOf(field("playbackListener")) < listenerOrder.indexOf(field("subtitleListener")))
        val collector = required(built, "analyticsCollector")
        val analytics = (required(required(collector, "listeners"), "listeners") as Set<*>).map { required(it!!, "listener") }
        val decoder = required(field("displayController")!!, "decoderAnalyticsListener")
        assertTrue(analytics.indexOf(decoder) >= 0)
        assertTrue(analytics.indexOf(decoder) < analytics.indexOf(field("iptvDiagAnalyticsListener")))
    }
}
