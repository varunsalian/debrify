package com.debrify.app.tv

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowValueAnimator
import org.robolectric.shadows.ShadowChoreographer
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvAutoSyncRingCharacterizationTest : TvPlayerAdapterHarness() {
    @Before fun boundAnimationFrames() {
        ShadowChoreographer.setPaused(true)
        ShadowChoreographer.setFrameDelay(Duration.ofMillis(16))
    }

    private fun ring(): View = Original.ring(
        Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java).get(), activity,
    ).also { it.layout(0, 0, 100, 80) }

    @Test fun pulseDurationRepeatRequestAndRepeatedStartKeepTheSameClock() {
        val ring = ring()
        val animator = Original.field(ring, "pulseAnimator") as ValueAnimator
        try {
            assertEquals(1800L, animator.duration)
            assertEquals(ValueAnimator.INFINITE, (shadowOf(animator) as ShadowValueAnimator).actualRepeatCount)
            Original.call(ring, "setPulsing", true)
            advance(900)
            assertTrue(animator.isStarted)
            // Seek the real animator to a deterministic frame. Robolectric's
            // global vsync clock can lag after other classes advance time.
            animator.currentPlayTime = 900
            assertEquals(0.5f, Original.field(ring, "pulse") as Float, 0.001f)
            animator.currentPlayTime = 0
            assertEquals(0f, Original.field(ring, "pulse") as Float, 0f)
            animator.currentPlayTime = 1800
            assertEquals(1f, Original.field(ring, "pulse") as Float, 0.001f)
            animator.currentPlayTime = 900
            val elapsed = animator.currentPlayTime
            Original.call(ring, "setPulsing", true)
            assertEquals(elapsed, animator.currentPlayTime)
        } finally {
            Original.call(ring, "setPulsing", false)
        }
    }

    @Test fun stopResetsPulseAndDetachCancelsTheOwnedAnimator() {
        val ring = ring()
        val animator = Original.field(ring, "pulseAnimator") as ValueAnimator
        parent.addView(ring)
        Original.call(ring, "setPulsing", true)
        advance(900)
        animator.currentPlayTime = 900
        assertTrue((Original.field(ring, "pulse") as Float) > 0f)
        Original.call(ring, "setPulsing", false)
        assertFalse(animator.isStarted)
        assertEquals(0f, Original.field(ring, "pulse"))
        Original.call(ring, "setPulsing", true)
        parent.removeView(ring)
        assertFalse(animator.isStarted)
    }

    private data class Circle(val x: Float, val y: Float, val radius: Float, val paint: Paint)
    private class RecordingCanvas : Canvas() {
        val circles = mutableListOf<Circle>()
        override fun drawCircle(cx: Float, cy: Float, radius: Float, paint: Paint) {
            circles += Circle(cx, cy, radius, Paint(paint))
        }
    }

    @Test fun haloAlphaAndArcColorAreSnapshotsBeforePaintReset() {
        val ring = ring()
        Original.set(ring, "pulse", 0.5f)
        Original.call(ring, "setArcColor", 0xFF123456.toInt())
        val canvas = RecordingCanvas()
        Original.call(ring, "onDraw", canvas)
        assertEquals(2, canvas.circles.size)
        assertEquals(41, canvas.circles[0].paint.alpha)
        // Legacy Paint exposes alpha separately from getColor's packed value.
        assertEquals(0x00123456, canvas.circles[0].paint.color and 0x00FFFFFF)
        assertEquals(255, canvas.circles[1].paint.alpha)
        assertEquals(0xFF123456.toInt(), canvas.circles[1].paint.color)
    }

    @Test fun haloStrokeGeometryAndSolidDotKeepIndependentPaintSnapshots() {
        val ring = ring()
        assertEquals(0xFF7BDCFF.toInt(), Original.get(ring, "arcColor"))
        Original.set(ring, "pulse", 0.5f)
        val canvas = RecordingCanvas()
        Original.call(ring, "onDraw", canvas)
        val halo = canvas.circles[0]
        assertEquals(50f, halo.x, 0f)
        assertEquals(40f, halo.y, 0f)
        assertEquals(33.75f, halo.radius, 0.001f)
        assertEquals(Paint.Style.STROKE, halo.paint.style)
        assertEquals(14f, halo.paint.strokeWidth, 0f)
        val dot = canvas.circles[1]
        assertEquals(Paint.Style.FILL, dot.paint.style)
        assertEquals(16f, dot.radius, 0f)
        Original.set(ring, "pulse", 0f)
        val stopped = RecordingCanvas()
        Original.call(ring, "onDraw", stopped)
        assertEquals(1, stopped.circles.size)
        assertEquals(Paint.Style.FILL, stopped.circles[0].paint.style)
    }

    @Test fun haloAppearsAboveZeroAndExpandsToFullRadiusWithZeroAlphaAtOne() {
        val ring = ring()
        for ((pulse, radius, alpha) in listOf(Triple(0.001f, 17.5325f, 81), Triple(1f, 50f, 0))) {
            Original.set(ring, "pulse", pulse)
            val canvas = RecordingCanvas()
            Original.call(ring, "onDraw", canvas)
            assertEquals(2, canvas.circles.size)
            assertEquals(radius, canvas.circles[0].radius, 0.001f)
            assertEquals(alpha, canvas.circles[0].paint.alpha)
            assertEquals(16f, canvas.circles[1].radius, 0f)
            assertEquals(255, canvas.circles[1].paint.alpha)
        }
    }

    @Test fun statusPaletteColorsKeepTheirOpaqueArgbValues() {
        val colors = Original.construct("AutoSyncColors")
        val ring = ring()
        for ((name, expected) in listOf("OK" to 0xFF82E0AD, "FAIL" to 0xFFE8C07B, "BUSY" to 0xFF7BDCFF)) {
            val color = Original.field(colors, name) as Int
            assertEquals(expected.toInt(), color)
            assertEquals(255, android.graphics.Color.alpha(color))
            Original.call(ring, "setArcColor", color)
            val canvas = RecordingCanvas()
            Original.call(ring, "onDraw", canvas)
            assertEquals(1, canvas.circles.size)
            assertEquals(expected.toInt(), canvas.circles[0].paint.color)
        }
    }
}
