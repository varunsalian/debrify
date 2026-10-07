package com.debrify.app.tv

import android.view.View
import com.debrify.app.util.AlignResult
import com.debrify.app.util.SubtitleSettings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPhase4MessageDeadlineCharacterizationTest : TvPhase4OriginalTest() {
    private fun ready() {
        setup(); org.robolectric.shadows.ShadowChoreographer.setPaused(true)
    }
    private fun deadline(text: String, milliseconds: Long) {
        val pill = field("autoSyncPill") as View
        assertEquals(text, label()); assertEquals(View.VISIBLE, pill.visibility)
        assertEquals(220L, pill.animate().duration)
        advance(milliseconds - 1); assertEquals("before $milliseconds ms", 220L, pill.animate().duration)
        advance(1); assertEquals("at $milliseconds ms", 240L, pill.animate().duration)
        assertEquals(false, field("autoSyncPillWindowActive"))
    }
    private fun result(outcome: AlignResult, auto: Boolean = false) {
        active(); val (response, job) = beginAlign(outcome, auto = auto); complete(response, job)
    }
    @Test fun missingSubtitleMessageHidesAtThreeThousandFiveHundredMilliseconds() {
        ready(); invoke("runSubtitleAutoSync", false)
        deadline("✕  PICK AN ADDON SUBTITLE FIRST", 3500)
    }
    @Test fun unavailablePcmMessageHidesAtFourSeconds() {
        ready(); active(); TvPhase4AudioTapShadow.segments = emptyList(); TvPhase4AudioTapShadow.recent = false
        invoke("runSubtitleAutoSync", false); deadline("✕  CAN'T ANALYZE THIS STREAM'S AUDIO", 4000)
    }
    @Test fun replacedSubtitleMessageHidesAtThreeSeconds() {
        ready(); active(); val (response, job) = beginAlign()
        set("activeExternalSubtitleUrl", "replacement"); complete(response, job)
        deadline("SUBTITLE CHANGED — TRY AGAIN", 3000)
    }
    @Test fun syncedMessageHidesAtThreeSeconds() {
        ready(); result(AlignResult.Synced(1200, 1.0, 60)); deadline("✓  SUBTITLES SYNCED", 3000)
    }
    @Test fun driftingMessageHidesAtFourThousandFiveHundredMilliseconds() {
        ready(); result(AlignResult.Drift(1.04, 500)); deadline("✕  SUBS DRIFT ON THIS FILE", 4500)
        assertEquals("drifting", field("autoSyncResultLabel"))
    }
    @Test fun manualNoMatchMessageHidesAtFourThousandFiveHundredMilliseconds() {
        ready(); result(AlignResult.NoMatch(60)); deadline("✕  NO CONFIDENT MATCH", 4500)
        assertEquals("no match", field("autoSyncResultLabel"))
    }
    @Test fun automaticNoMatchFinalMessageHidesAtFiveSeconds() {
        ready(); set("autoSyncLadderIdx", 4); result(AlignResult.NoMatch(60), true)
        deadline("✕  COULDN'T SYNC AUTOMATICALLY", 5000)
    }
    @Test fun automaticInsufficientAudioFinalMessageHidesAtFiveSeconds() {
        ready(); set("autoSyncLadderIdx", 4); result(AlignResult.NotEnoughAudio(7), true)
        deadline("✕  COULDN'T SYNC AUTOMATICALLY", 5000)
        assertEquals("7s heard", field("autoSyncResultLabel"))
    }
    @Test fun manualInsufficientAudioMessageHidesAtThreeThousandFiveHundredMilliseconds() {
        ready(); result(AlignResult.NotEnoughAudio(7))
        deadline("KEEP WATCHING A LITTLE, THEN TRY AGAIN", 3500)
    }
    @Test fun periodicResyncMessageHidesAtThreeSeconds() {
        ready(); active(); probe.position = 400_000
        SubtitleSettings.setSyncOffsetMs(activity, 1000); set("autoSyncAppliedOffsetMs", 1000L)
        val (response, job) = verifyBegin(AlignResult.Synced(401, 1.0, 60)); complete(response, job)
        deadline("↻  RE-SYNCED", 3000)
    }
    @Test fun restoredOffsetMessageHidesAtThreeSeconds() {
        ready(); active(); SubtitleSettings.setSyncOffsetMs(activity, -750)
        invoke("stopExternalSubtitleRendering"); SubtitleSettings.resetSyncOffset(); pref(true)
        call("onExternalSubtitleLoaded", arrayOf(com.debrify.app.subtitle.StremioSubtitle::class.java, listType, intType), subtitle(), cues, -1)
        assertEquals(-750L, SubtitleSettings.getSyncOffsetMs(activity))
        assertEquals("↻ ${SubtitleSettings.formatSyncOffset(-750)}", field("autoSyncResultLabel"))
        deadline("↻  SYNC RESTORED", 3000)
    }
    @Test fun manualBusyMessageHasNoHideDeadlineWhileAlignmentIsPending() {
        ready(); active(); val (response, job) = beginAlign()
        assertEquals("SYNCING SUBTITLES…", label()); advance(10_000)
        assertEquals(220L, (field("autoSyncPill") as View).animate().duration)
        assertEquals(View.VISIBLE, (field("autoSyncPill") as View).visibility)
        complete(response, job)
    }
    @Test fun automaticCheckingMessageHasNoHideDeadlineWhileAlignmentIsPending() {
        ready(); active(); invoke("openAutoSyncPillWindow")
        val (response, job) = beginAlign(auto = true)
        assertEquals("CHECKING…", label()); advance(10_000)
        assertEquals(220L, (field("autoSyncPill") as View).animate().duration)
        assertEquals(View.VISIBLE, (field("autoSyncPill") as View).visibility)
        complete(response, job)
    }
}
