package com.debrify.app.tv

import android.animation.ValueAnimator
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvRingRepaintCharacterizationTest {
    @Test fun colorAssignmentRequestsRepaintEvenForTheSameColor() {
        val ring = AutoSyncRingView(RuntimeEnvironment.getApplication())
        val shadow = shadowOf(ring)
        repeat(2) {
            shadow.clearWasInvalidated(); ring.arcColor = AutoSyncColors.OK
            assertTrue("color setter requests repaint", shadow.wasInvalidated())
        }
    }
    @Test fun animatorFrameRequestsRepaint() {
        val ring = AutoSyncRingView(RuntimeEnvironment.getApplication())
        val animator = TvPlayerOriginalAccess.field(ring, "pulseAnimator") as ValueAnimator
        ring.setPulsing(true)
        try {
            shadowOf(ring).clearWasInvalidated(); animator.currentPlayTime = 900L
            assertTrue("animation update requests repaint", shadowOf(ring).wasInvalidated())
        } finally { ring.setPulsing(false) }
    }
    @Test fun stoppingResetsAndRequestsRepaint() {
        val ring = AutoSyncRingView(RuntimeEnvironment.getApplication())
        val animator = TvPlayerOriginalAccess.field(ring, "pulseAnimator") as ValueAnimator
        ring.setPulsing(true); animator.currentPlayTime = 900L
        shadowOf(ring).clearWasInvalidated(); ring.setPulsing(false)
        assertEquals(0f, TvPlayerOriginalAccess.field(ring, "pulse"))
        assertTrue("stop/reset requests repaint", shadowOf(ring).wasInvalidated())
    }
}
