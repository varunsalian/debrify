package com.debrify.app.tv

import android.view.View
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsHideRaceCharacterizationTest(override val skin: TvControlsSkin) : TvPhase16OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}") fun skins(): List<Array<Any>> =
            TvControlsSkin.entries.map { arrayOf<Any>(it) }
    }
    @Test fun visibleHideResetsAnOttTitleAndUsesItsExactExitCurveAndLift() {
        showDock(); step(301)
        v("titleView").visibility = View.GONE; v("titleOttContainer").visibility = View.VISIBLE
        v("titleContainer").visibility = View.VISIBLE; v("titleContainer").alpha = 1f
        hideDock()
        assertEquals(250L, v("controlsOverlay").animate().duration)
        assertEquals(250L, v("titleContainer").animate().duration)
        TvControlsEndActions.curve(v("controlsOverlay"), AccelerateInterpolator(1.2f))
        step(125)
        val fraction = AccelerateInterpolator(1.2f).getInterpolation(0.5f)
        assertEquals("hide alpha before reset", 1f - fraction, v("controlsOverlay").alpha, 0.005f)
        assertEquals("hide lift before reset", 20f * fraction, v("controlsOverlay").translationY, 0.08f)
        assertEquals(0.5f, v("titleContainer").alpha, 0.02f)
        assertEquals(View.VISIBLE, v("controlsOverlay").visibility)
        step(126)
        assertEquals(View.GONE, v("controlsOverlay").visibility)
        assertEquals(0f, v("controlsOverlay").alpha, 0f); assertEquals(0f, v("controlsOverlay").translationY, 0f)
        assertEquals(View.GONE, v("titleContainer").visibility)
        assertEquals("simple title restored", View.VISIBLE, v("titleView").visibility)
        assertEquals(View.GONE, v("titleOttContainer").visibility)
    }
    @Test fun capturedHideEndActionLeavesAReshownDockUntouched() {
        showDock(); step(301); hideDock()
        val oldEnd = TvControlsEndActions.capture(v("controlsOverlay"))
        step(100); showDock(); step(301)
        assertTrue(field("controlsMenuVisible") as Boolean)
        oldEnd.run()
        assertEquals("late hide preserves reveal", View.VISIBLE, v("controlsOverlay").visibility)
        assertEquals(1f, v("controlsOverlay").alpha, 0f)
        assertEquals(0f, v("controlsOverlay").translationY, 0f)
    }
    @Test fun capturedHideEndActionNormalizesEveryPropertyWhileStillHidden() {
        showDock(); step(301); hideDock()
        val end = TvControlsEndActions.capture(v("controlsOverlay")); v("controlsOverlay").animate().cancel()
        v("controlsOverlay").visibility = View.INVISIBLE; v("controlsOverlay").alpha = 0.4f; v("controlsOverlay").translationY = 33f
        end.run()
        assertEquals(View.GONE, v("controlsOverlay").visibility)
        assertEquals(0f, v("controlsOverlay").alpha, 0f); assertEquals(0f, v("controlsOverlay").translationY, 0f)
    }
    @Test fun capturedShowEndActionNormalizesAlphaAndLiftEvenAfterAHide() {
        showDock(); val end = TvControlsEndActions.capture(v("controlsOverlay")); hideDock()
        v("controlsOverlay").animate().cancel(); v("controlsOverlay").alpha = 0.4f; v("controlsOverlay").translationY = 33f
        end.run()
        assertFalse(field("controlsMenuVisible") as Boolean)
        assertEquals(1f, v("controlsOverlay").alpha, 0f); assertEquals(0f, v("controlsOverlay").translationY, 0f)
    }
    @Test fun capturedTitleEndActionResetsModeEvenAfterAReshow() {
        showDock(); step(301); hideDock(); val end = TvControlsEndActions.capture(v("titleContainer"))
        showDock(); v("titleView").visibility = View.GONE; v("titleOttContainer").visibility = View.VISIBLE
        v("titleContainer").visibility = View.VISIBLE
        end.run()
        assertEquals(View.GONE, v("titleContainer").visibility)
        assertEquals(View.VISIBLE, v("titleView").visibility); assertEquals(View.GONE, v("titleOttContainer").visibility)
    }
    @Test fun freshShowKeepsTheExactEntranceCurveAndEndsAtFullAlphaAndZeroLift() {
        showDock(); TvControlsEndActions.curve(v("controlsOverlay"), DecelerateInterpolator(1.5f))
        assertEquals(300L, v("controlsOverlay").animate().duration)
        step(299); assertEquals(1f, v("controlsOverlay").alpha, 0.001f)
        assertEquals(0f, v("controlsOverlay").translationY, 0.001f)
    }
}
