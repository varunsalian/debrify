package com.debrify.app.tv

import com.debrify.app.util.AlignResult
import com.debrify.app.util.SubtitleSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvAutoSyncScheduleCharacterizationTest : TvPhase4OriginalTest() {
    @Test fun ladderPollsEveryEightSecondsAndUsesAllFourInclusiveAnchoredRungs() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(true)
        setup(); active(); pref(true); TvPhase4AudioTapShadow.anchoredMs = 0.0; invoke("startAutoSyncLadder")
        for ((index, seconds) in listOf(20, 45, 90, 180).withIndex()) {
            TvPhase4AudioTapShadow.anchoredMs = seconds * 1000.0 - 1
            advance(7999); assertTrue(jobs().isEmpty()); advance(1); assertTrue(jobs().isEmpty())
            assertEquals(index, field("autoSyncLadderIdx"))
            TvPhase4AudioTapShadow.anchoredMs = seconds * 1000.0
            val response = TvPhase4Response<AlignResult>(AlignResult.NoMatch(seconds)); pending.add(response)
            TvPhase4AlignerShadow.responses.add(response)
            advance(7999); assertTrue("rung=$index at=${android.os.SystemClock.uptimeMillis()} index=${field("autoSyncLadderIdx")}", jobs().isEmpty()); advance(1); entered(response)
            assertEquals(index + 1, field("autoSyncLadderIdx")); complete(response, job())
        }
        assertEquals("✕  COULDN'T SYNC AUTOMATICALLY", label()); advance(8000); assertTrue(jobs().isEmpty())
    }
    @Test fun preferenceIsOffByDefaultAndReadAgainWhenArmingLadderOrVerify() {
        setup(); active(); invoke("startAutoSyncLadder"); assertNull(field("autoSyncLadderTick"))
        invoke("scheduleAutoSyncVerify"); assertNull(field("autoSyncVerifyTick"))
        pref(true); invoke("startAutoSyncLadder"); assertNotNull(field("autoSyncLadderTick"))
        invoke("scheduleAutoSyncVerify"); assertNotNull(field("autoSyncVerifyTick"))
        pref(false); invoke("startAutoSyncLadder"); invoke("scheduleAutoSyncVerify")
        assertNull(field("autoSyncLadderTick")); assertNull(field("autoSyncVerifyTick"))
    }
    @Test fun manualOffsetAndRunningWorkPreventLadderAttempts() {
        setup(); active(); pref(true); SubtitleSettings.setSyncOffsetMs(activity, 100)
        invoke("startAutoSyncLadder"); assertNull(field("autoSyncPill")); advance(8000)
        assertEquals(0, field("autoSyncLadderIdx")); assertTrue(jobs().isEmpty())
        SubtitleSettings.resetSyncOffset(); set("autoSyncRunning", true); advance(8000)
        assertEquals(0, field("autoSyncLadderIdx")); assertTrue(jobs().isEmpty())
    }
    @Test fun doneOrInactiveSubtitleStopsLadderAndCancellationRemovesFuturePolls() {
        setup(); active(); pref(true); TvPhase4AudioTapShadow.anchoredMs = 0.0
        invoke("startAutoSyncLadder"); set("externalSubtitleActive", false); advance(8000)
        set("externalSubtitleActive", true); TvPhase4AudioTapShadow.anchoredMs = 180_000.0; advance(8000)
        assertEquals(0, field("autoSyncLadderIdx")); assertTrue(jobs().isEmpty())
        TvPhase4AudioTapShadow.anchoredMs = 0.0; invoke("startAutoSyncLadder"); invoke("cancelAutoSyncLadder")
        assertNull(field("autoSyncLadderTick")); assertEquals(true, field("autoSyncLadderDone"))
        advance(16_000); assertTrue(jobs().isEmpty())
    }
    @Test fun verifySchedulesNinetyThenOneHundredTwentySecondsAndHonoursSelfIdentity() {
        setup(); active(); pref(true); SubtitleSettings.setSyncOffsetMs(activity, 1000); set("autoSyncAppliedOffsetMs", 1000L)
        invoke("scheduleAutoSyncVerify")
        val first = TvPhase4Response<AlignResult>(AlignResult.NoMatch(60)); pending.add(first); TvPhase4AlignerShadow.responses.add(first)
        advance(89_999); assertTrue(jobs().isEmpty()); advance(1); entered(first); complete(first, job())
        val second = TvPhase4Response<AlignResult>(AlignResult.NoMatch(60)); pending.add(second); TvPhase4AlignerShadow.responses.add(second)
        advance(119_999); assertTrue(jobs().isEmpty()); advance(1); entered(second); complete(second, job())
        assertEquals(2, field("autoSyncVerifyMisses")); invoke("cancelAutoSyncVerify")
        assertNull(field("autoSyncVerifyTick")); assertEquals(0, field("autoSyncVerifyMisses"))
        advance(240_000); assertTrue(jobs().isEmpty())
    }
    @Test fun onStopSuspendsOnlyExternalTickerWhilePendingAutoSyncContinues() {
        setup(created = true); active(); invoke("startExternalSubtitleTicker")
        val (response, job) = beginAlign(); val scope = field("subtitleScope") as CoroutineScope
        lifecycle.pause().stop()
        assertFalse("onStop does not cancel subtitle work", scope.coroutineContext[Job]!!.isCancelled)
        complete(response, job); assertEquals(1200L, field("autoSyncAppliedOffsetMs"))
        assertEquals("✓  SUBTITLES SYNCED", label())
        val stoppedText = text(); probe.position = 2500; advance(250); assertEquals(stoppedText, text())
        lifecycle.start().resume(); assertEquals(listOf("first\nsecond"), text())
        lifecycle.pause().stop().destroy()
    }
    @Test fun onStopKeepsLadderPollAndPillDismissAliveButDestroyClearsSharedHandler() {
        setup(created = true); active(); pref(true); TvPhase4AudioTapShadow.anchoredMs = 0.0
        invoke("startAutoSyncLadder"); val handler = field("externalSubtitleHandler") as android.os.Handler
        var borrowedTick = false; handler.postDelayed({ borrowedTick = true }, 10_000)
        lifecycle.pause().stop(); advance(5000)
        assertEquals(false, field("autoSyncPillAnnounceShowing")); assertNotNull(field("autoSyncLadderTick"))
        lifecycle.destroy(); advance(20_000); assertFalse("destroy clears shared callbacks", borrowedTick)
        assertTrue((field("subtitleScope") as CoroutineScope).coroutineContext[Job]!!.isCancelled)
    }
}
