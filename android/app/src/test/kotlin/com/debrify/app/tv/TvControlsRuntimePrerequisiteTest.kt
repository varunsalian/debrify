package com.debrify.app.tv

import android.animation.ValueAnimator
import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsRuntimePrerequisiteTest : TvPhase16OriginalTest() {
    @Test fun pausedFramesAdvanceTheOriginalScrubAnimator() {
        drawScrub()
        val animator = field("cinemaProgressAnimator") as ValueAnimator
        assertEquals("original scrub duration", 80L, animator.duration)
        frame(animator)
        assertEquals(0.25f, animator.animatedValue as Float, 0.001f)
        advance(20); frame(animator)
        val middle = animator.animatedValue as Float
        assertTrue("paused frame stepping reaches an intermediate scrub value", middle > 0.25f && middle < 0.5f)
        assertEquals((1000 * middle).toInt(), v("debrifyProgressLine").layoutParams.width)
        advance(60); frame(animator)
        assertEquals(0.5f, animator.animatedValue as Float, 0.001f)
        assertEquals(500, v("debrifyProgressLine").layoutParams.width)
        assertFalse(animator.isRunning)
    }
    private fun frame(animator: ValueAnimator) {
        // Dispatch the real framework frame callback at the controlled main-loop
        // clock. Bootstrap leaves Robolectric's native vsync callback stalled;
        // interpolators/listeners/end handling remain the original implementation.
        ValueAnimator::class.java.getDeclaredMethod("doAnimationFrame", Long::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(animator, android.os.SystemClock.uptimeMillis())
    }
    @Test fun originalSeekAndPlayPauseReachTheRecordingPlayerInOrder() {
        runOriginal("seekBy", 10_000L)
        runOriginal("togglePlayPause")
        runOriginal("togglePlayPause")
        assertEquals(listOf("seek:35000", "pause", "play"), probe.events)
        assertEquals("Pause", tv("pauseButton").text.toString())
        assertTrue(reads.contains("position")); assertTrue(reads.contains("duration"))
        assertEquals(35_000L, probe.position); assertTrue(playIntent)
    }
}
