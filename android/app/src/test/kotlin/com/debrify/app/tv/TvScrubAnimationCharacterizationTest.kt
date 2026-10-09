package com.debrify.app.tv

import android.animation.ValueAnimator
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvScrubAnimationCharacterizationTest(override val skin: TvControlsSkin) : TvPhase16OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}") fun skins(): List<Array<Any>> =
            TvControlsSkin.entries.map { arrayOf<Any>(it) }
    }
    @Test fun thumbEntrancePinsOvershootAlphaAndBothAxesBeforeTheSettle() {
        enterScrub(); val thumb = v("cinemaProgressThumb")
        assertEquals(0f, thumb.alpha, 0f); assertEquals(0.6f, thumb.scaleX, 0f); assertEquals(0.6f, thumb.scaleY, 0f)
        assertEquals(200L, thumb.animate().duration); TvControlsEndActions.curve(thumb, OvershootInterpolator(2f))
        step(100); val fraction = OvershootInterpolator(2f).getInterpolation(0.5f)
        assertEquals(fraction, thumb.alpha, 0.01f)
        assertEquals(0.6f + 0.55f * fraction, thumb.scaleX, 0.01f)
        assertEquals(0.6f + 0.55f * fraction, thumb.scaleY, 0.01f)
        step(101); assertEquals(100L, thumb.animate().duration)
        step(101); assertEquals(1f, thumb.scaleX, 0.001f); assertEquals(1f, thumb.scaleY, 0.001f)
    }
    @Test fun capturedEntranceEndActionSchedulesTheOriginalSettleWithoutASeekModeGuard() {
        enterScrub(); val thumb = v("cinemaProgressThumb"); val end = TvControlsEndActions.capture(thumb)
        thumb.animate().cancel(); set("cinemaSeekMode", false); thumb.scaleX = 1.4f; thumb.scaleY = 1.6f
        end.run(); assertEquals(100L, thumb.animate().duration); TvControlsEndActions.curve(thumb, OvershootInterpolator(2f))
        step(101); assertEquals(1f, thumb.scaleX, 0.001f); assertEquals(1f, thumb.scaleY, 0.001f)
    }
    @Test fun thumbExitPinsAlphaBothAxesAndEasingBeforeTheInvisibleReset() {
        enterScrub(); step(302); exitScrub(); val thumb = v("cinemaProgressThumb")
        assertEquals(150L, thumb.animate().duration); TvControlsEndActions.curve(thumb, DecelerateInterpolator())
        step(75); assertEquals(0.25f, thumb.alpha, 0.005f)
        assertEquals(0.475f, thumb.scaleX, 0.005f); assertEquals(0.475f, thumb.scaleY, 0.005f)
        assertEquals(View.VISIBLE, thumb.visibility)
        step(76); assertEquals(View.INVISIBLE, thumb.visibility); assertEquals(0f, thumb.alpha, 0.001f)
        assertEquals(1f, thumb.scaleX, 0f); assertEquals(1f, thumb.scaleY, 0f)
    }
    @Test fun capturedExitEndActionResetsBothAxesEvenIfScrubbingWasReentered() {
        enterScrub(); step(302); exitScrub(); val thumb = v("cinemaProgressThumb"); val end = TvControlsEndActions.capture(thumb)
        thumb.animate().cancel(); set("cinemaSeekMode", true)
        thumb.visibility = View.VISIBLE; thumb.scaleX = 1.4f; thumb.scaleY = 1.6f
        end.run(); assertEquals(View.INVISIBLE, thumb.visibility)
        assertEquals(1f, thumb.scaleX, 0f); assertEquals(1f, thumb.scaleY, 0f)
    }
    @Test fun progressAnimatorKeepsItsEightyMsCurveAndBothEndpoints() {
        v("cinemaProgressThumb").layout(0, 0, 20, 20); drawScrub(50_000)
        val animator = field("cinemaProgressAnimator") as ValueAnimator
        assertEquals(80L, animator.duration); assertEquals(0.25f, animator.animatedValue as Float, 0f)
        for (fraction in listOf(0.25f, 0.5f, 0.75f))
            assertEquals(DecelerateInterpolator().getInterpolation(fraction), animator.interpolator.getInterpolation(fraction), 0.00001f)
        step(80); assertEquals(0.5f, animator.animatedValue as Float, 0.001f)
        assertEquals(500, v("debrifyProgressLine").layoutParams.width); assertEquals(490f, v("cinemaProgressThumb").translationX, 0.01f)
    }
}
