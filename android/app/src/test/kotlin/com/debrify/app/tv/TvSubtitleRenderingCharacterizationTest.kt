package com.debrify.app.tv

import androidx.media3.common.C
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleSettings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleRenderingCharacterizationTest : TvPhase4OriginalTest() {
    @Test fun rendererOverlapsWholePrefixAndUsesInclusiveStartExclusiveEnd() {
        setup(); active(); set("externalSubtitleCues", listOf(SubtitleCue(0, 10_000, "long"), SubtitleCue(1000, 2000, "one"), SubtitleCue(2000, 3000, "two")))
        for ((position, expected) in listOf(0L to "long", 1000L to "long\none", 1999L to "long\none", 2000L to "long\ntwo", 3000L to "long", 10_000L to null)) {
            probe.position = position; invoke("renderExternalSubtitleCue")
            assertEquals("position=$position", expected?.let { listOf(it) }.orEmpty(), text())
        }
        assertNull(field("lastExternalCueText"))
    }
    @Test fun rendererReadsPositiveAndNegativeOffsetsAtEvaluationTimeAndAvoidsUnchangedRepaint() {
        setup(); active(); probe.position = 2000; invoke("renderExternalSubtitleCue")
        val originalCues = TvPlayerOriginalAccess.field(overlay, "cues")
        invoke("renderExternalSubtitleCue"); assertSame(originalCues, TvPlayerOriginalAccess.field(overlay, "cues"))
        SubtitleSettings.setSyncOffsetMs(activity, 1000); invoke("renderExternalSubtitleCue")
        assertEquals(listOf("first\nsecond"), text())
        SubtitleSettings.setSyncOffsetMs(activity, -1000); invoke("renderExternalSubtitleCue"); assertTrue(text().isEmpty())
    }
    @Test fun tickerRendersImmediatelyThenEveryTwoHundredFiftyMillisecondsAndDoesNotDuplicate() {
        setup(); active(); invoke("startExternalSubtitleTicker"); assertEquals(listOf("first"), text())
        probe.position = 2500; advance(249); assertEquals(listOf("first"), text()); advance(1); assertEquals(listOf("second"), text())
        val old = field("externalSubtitleTicker"); invoke("startExternalSubtitleTicker"); assertNotSame(old, field("externalSubtitleTicker"))
        set("externalSubtitleActive", false); probe.position = 0; advance(250); assertEquals(listOf("second"), text())
    }
    @Test fun stoppingRenderingInvalidatesFetchClearsCuesAndRestoresEmbeddedTrackType() {
        setup(); active(); pref(true); invoke("startAutoSyncLadder"); invoke("scheduleAutoSyncVerify")
        val ts = field("trackSelector") as DefaultTrackSelector
        ts.parameters = ts.parameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
        invoke("startExternalSubtitleTicker"); set("autoSyncAppliedOffsetMs", 1000L); val token = field("externalSubtitleLoadToken") as Int
        invoke("stopExternalSubtitleRendering")
        assertEquals(token + 1, field("externalSubtitleLoadToken")); assertNull(field("externalSubtitleTicker"))
        assertNull(field("autoSyncLadderTick")); assertNull(field("autoSyncVerifyTick")); assertNull(field("autoSyncAppliedOffsetMs"))
        assertEquals(false, field("externalSubtitleActive")); assertNull(field("activeExternalSubtitleUrl"))
        assertTrue((field("externalSubtitleCues") as List<*>).isEmpty()); assertTrue(text().isEmpty())
        assertFalse(ts.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun loadSuccessClearsOldEmbeddedLineDisablesEmbeddedTextAndRestoresRememberedOffsetBeforeLadder() {
        setup(); active(); SubtitleSettings.setSyncOffsetMs(activity, 750)
        invoke("stopExternalSubtitleRendering"); SubtitleSettings.resetSyncOffset(); pref(true)
        overlay.setCues(listOf(androidx.media3.common.text.Cue.Builder().setText("old embedded").build())); probe.position = 50_000
        call("onExternalSubtitleLoaded", arrayOf(com.debrify.app.subtitle.StremioSubtitle::class.java, listType, intType), subtitle(), cues, -1)
        assertTrue("no stale embedded line", text().isEmpty()); assertEquals(750L, SubtitleSettings.getSyncOffsetMs(activity))
        assertEquals(750L, field("autoSyncAppliedOffsetMs")); assertEquals("↻  SYNC RESTORED", label())
        assertEquals("↻ ${SubtitleSettings.formatSyncOffset(750)}", field("autoSyncResultLabel"))
        assertNotNull(field("autoSyncVerifyTick")); assertNotNull(field("autoSyncLadderTick"))
        assertTrue((field("trackSelector") as DefaultTrackSelector).parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        assertEquals(url, field("autoSyncResultUrl"))
    }
    @Test fun failedLoadWithoutPriorExternalRestoresEmbeddedTracksAndKeepsNoExternalState() {
        setup(); val ts = field("trackSelector") as DefaultTrackSelector
        ts.parameters = ts.parameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
        val (response, job) = beginFetch(parsed = emptyList()); set("currentStremioSubtitleIndex", 0); complete(response, job)
        assertEquals(-1, field("currentStremioSubtitleIndex")); assertFalse(ts.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        assertEquals(false, field("externalSubtitleActive")); assertNull(field("activeExternalSubtitleUrl"))
        assertEquals("Couldn't load English", (field("statusPill") as android.widget.TextView).text.toString())
    }
}
