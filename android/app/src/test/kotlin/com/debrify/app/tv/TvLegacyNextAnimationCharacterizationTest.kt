package com.debrify.app.tv

import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvLegacyNextAnimationCharacterizationTest : TvPhase16OriginalTest() {
    @Test fun legacyEntranceAndExitReachTheirOriginalAlphaTargetsBeforeTheEndAction() {
        runOriginal("showSeekbar"); assertEquals(200L, v("seekbarOverlay").animate().duration)
        step(199); assertEquals(1f, v("seekbarOverlay").alpha, 0.001f)
        step(2); runOriginal("hideSeekbar"); assertEquals(150L, v("seekbarOverlay").animate().duration)
        step(149); assertEquals(0f, v("seekbarOverlay").alpha, 0.001f)
        assertEquals(View.VISIBLE, v("seekbarOverlay").visibility); assertEquals(listOf("pause"), probe.events)
        step(2); assertEquals(View.GONE, v("seekbarOverlay").visibility); assertEquals(listOf("pause", "play"), probe.events)
    }
    @Test fun capturedLegacyExitStillHidesAndResumesAfterAnotherReveal() {
        runOriginal("showSeekbar"); step(201); runOriginal("hideSeekbar")
        val end = TvControlsEndActions.capture(v("seekbarOverlay")); v("seekbarOverlay").animate().cancel()
        runOriginal("showSeekbar"); probe.events.clear(); end.run()
        assertTrue(field("seekbarVisible") as Boolean); assertEquals(View.GONE, v("seekbarOverlay").visibility)
        assertEquals(listOf("play"), probe.events)
    }
    @Test fun capturedLegacyExitWithNoPlayerHidesWithoutAnExceptionOrPlayback() {
        runOriginal("showSeekbar"); step(201); runOriginal("hideSeekbar")
        val end = TvControlsEndActions.capture(v("seekbarOverlay")); v("seekbarOverlay").animate().cancel()
        set("player", null); probe.events.clear(); val result = runCatching { end.run() }
        assertTrue(result.isSuccess); assertEquals(View.GONE, v("seekbarOverlay").visibility); assertTrue(probe.events.isEmpty())
    }
    @Test fun nextEntranceAndExitReachTheirTargetsBeforeTheResetAndPreserveExactDurations() {
        runOriginal("fadeInNextOverlay"); assertEquals(220L, v("nextOverlay").animate().duration)
        step(219); assertEquals(1f, v("nextOverlay").alpha, 0.001f)
        step(2); runOriginal("hideNextOverlay"); assertEquals(160L, v("nextOverlay").animate().duration)
        step(159); assertEquals(0f, v("nextOverlay").alpha, 0.001f)
        assertEquals(View.VISIBLE, v("nextOverlay").visibility)
        step(2); assertEquals(View.GONE, v("nextOverlay").visibility); assertEquals(1f, v("nextOverlay").alpha, 0f)
    }
    @Test fun capturedNextExitResetsVisibilityAndAlphaEvenAfterAnotherReveal() {
        runOriginal("fadeInNextOverlay"); step(221); runOriginal("hideNextOverlay")
        val end = TvControlsEndActions.capture(v("nextOverlay")); runOriginal("fadeInNextOverlay")
        v("nextOverlay").alpha = 0.4f; end.run()
        assertEquals(View.GONE, v("nextOverlay").visibility); assertEquals(1f, v("nextOverlay").alpha, 0f)
    }
}
