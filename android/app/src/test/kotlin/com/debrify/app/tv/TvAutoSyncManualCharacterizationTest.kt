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
internal class TvAutoSyncManualCharacterizationTest : TvPhase4OriginalTest() {
    @Test fun syncedResultAppliesOffsetRemembersMenuOutcomeAndStopsLadder() {
        setup(); active(); val (response, job) = beginAlign(); complete(response, job)
        assertEquals(1200L, SubtitleSettings.getSyncOffsetMs(activity)); assertEquals(1200L, field("autoSyncAppliedOffsetMs"))
        assertEquals("✓ ${SubtitleSettings.formatSyncOffset(1200)}", field("autoSyncResultLabel"))
        assertEquals(url, field("autoSyncResultUrl")); assertEquals(true, field("autoSyncLadderDone"))
        assertEquals("✓  SUBTITLES SYNCED", label()); assertTrue(workerErrors.isEmpty())
        assertEquals(View.GONE, (field("autoSyncPillRing") as View).visibility)
    }
    @Test fun driftDeclinesOffsetAndEndsLadderWithHonestResult() {
        setup(); active(); val (response, job) = beginAlign(AlignResult.Drift(1.04, 500)); complete(response, job)
        assertEquals(0L, SubtitleSettings.getSyncOffsetMs(activity)); assertNull(field("autoSyncAppliedOffsetMs"))
        assertEquals("drifting", field("autoSyncResultLabel")); assertEquals(true, field("autoSyncLadderDone"))
        assertEquals("✕  SUBS DRIFT ON THIS FILE", label())
    }
    @Test fun noMatchDeclinesOffsetAndKeepsLadderEligible() {
        setup(); active(); val (response, job) = beginAlign(AlignResult.NoMatch(60)); complete(response, job)
        assertEquals(0L, SubtitleSettings.getSyncOffsetMs(activity)); assertEquals("no match", field("autoSyncResultLabel"))
        assertEquals(false, field("autoSyncLadderDone")); assertEquals("✕  NO CONFIDENT MATCH", label())
    }
    @Test fun notEnoughAudioRemembersSecondsAndAsksForMorePlayback() {
        setup(); active(); val (response, job) = beginAlign(AlignResult.NotEnoughAudio(7)); complete(response, job)
        assertEquals("7s heard", field("autoSyncResultLabel")); assertEquals("KEEP WATCHING A LITTLE, THEN TRY AGAIN", label())
        assertEquals(0L, SubtitleSettings.getSyncOffsetMs(activity))
    }
    @Test fun manualExceptionBecomesNoMatchAndClearsRunning() {
        setup(); active(); val (response, job) = beginAlign(failure = IllegalStateException("scripted")); complete(response, job)
        assertEquals("✕  NO CONFIDENT MATCH", label()); assertEquals(false, field("autoSyncRunning")); assertTrue(workerErrors.isEmpty())
    }
    @Test fun manualOomIsCaughtAsThrowableRatherThanEscaping() {
        setup(); active(); val (response, job) = beginAlign(failure = OutOfMemoryError("scripted OOM")); complete(response, job)
        assertTrue("OOM is converted to NoMatch", workerErrors.isEmpty())
        assertEquals("no match", field("autoSyncResultLabel")); assertEquals(false, field("autoSyncRunning"))
        assertEquals("✕  NO CONFIDENT MATCH", label())
    }
    @Test fun missingTapOrMissingCuesDeclinesManualButAutoStaysSilent() {
        setup(); invoke("runSubtitleAutoSync", true); assertNull(field("autoSyncPill"))
        invoke("runSubtitleAutoSync", false); assertEquals("✕  PICK AN ADDON SUBTITLE FIRST", label())
        active(); set("speechTap", null); invoke("runSubtitleAutoSync", false)
        assertEquals("✕  PICK AN ADDON SUBTITLE FIRST", label()); assertTrue(jobs().isEmpty())
    }
    @Test fun absentPcmWhilePlayingDeclinesAfterEightSecondRecentAudioRead() {
        setup(); active(); TvPhase4AudioTapShadow.segments = emptyList(); TvPhase4AudioTapShadow.recent = false
        invoke("runSubtitleAutoSync", true); assertNull(field("autoSyncPill"))
        invoke("runSubtitleAutoSync", false); assertEquals(8000L, TvPhase4AudioTapShadow.recentWindow)
        assertEquals("✕  CAN'T ANALYZE THIS STREAM'S AUDIO", label()); assertTrue(jobs().isEmpty())
    }
    @Test fun concurrentRunIsIgnoredAndDefaultArgumentUsesManualFace() {
        setup(); active(); val response = TvPhase4Response<AlignResult>(AlignResult.NoMatch(0)); pending.add(response)
        TvPhase4AlignerShadow.responses.add(response)
        defaultCall("runSubtitleAutoSync", arrayOf(boolType), 1, true)
        entered(response); val job = job()
        assertNotNull("manual default shows busy pill", field("autoSyncPillLabel"))
        assertEquals("SYNCING SUBTITLES…", label()); assertEquals(true, field("autoSyncRunning"))
        invoke("runSubtitleAutoSync", false); assertEquals(setOf(job), jobs())
        complete(response, job); assertEquals("✕  NO CONFIDENT MATCH", label())
    }
    @Test fun intermediateAutomaticMissIsQuietButFinalRungAnnouncesFailure() {
        setup(); active(); set("autoSyncLadderIdx", 1)
        val (first, firstJob) = beginAlign(AlignResult.NoMatch(60), auto = true); complete(first, firstJob)
        assertNull(field("autoSyncPill")); assertEquals("no match", field("autoSyncResultLabel"))
        set("autoSyncLadderIdx", 4)
        val (last, lastJob) = beginAlign(AlignResult.NoMatch(60), auto = true); complete(last, lastJob)
        assertEquals("✕  COULDN'T SYNC AUTOMATICALLY", label())
    }
    @Test fun automaticInsufficientAudioAnnouncesOnlyAtFinalRung() {
        setup(); active(); set("autoSyncLadderIdx", 3)
        val (first, firstJob) = beginAlign(AlignResult.NotEnoughAudio(5), auto = true); complete(first, firstJob)
        assertNull(field("autoSyncPill")); set("autoSyncLadderIdx", 4)
        val (last, lastJob) = beginAlign(AlignResult.NotEnoughAudio(5), auto = true); complete(last, lastJob)
        assertEquals("✕  COULDN'T SYNC AUTOMATICALLY", label()); assertEquals("5s heard", field("autoSyncResultLabel"))
    }
    @Test fun automaticCheckingFaceReturnsToQuietAfterSilentIntermediateResult() {
        setup(); active(); invoke("openAutoSyncPillWindow")
        val (response, job) = beginAlign(AlignResult.NoMatch(30), auto = true)
        assertEquals("CHECKING…", label()); assertEquals(android.graphics.Color.WHITE, (field("autoSyncPillRing") as AutoSyncRingView).arcColor)
        complete(response, job); advance(300)
        assertEquals(View.GONE, (field("autoSyncPill") as View).visibility); assertEquals(true, field("autoSyncPillWindowActive"))
    }
}
