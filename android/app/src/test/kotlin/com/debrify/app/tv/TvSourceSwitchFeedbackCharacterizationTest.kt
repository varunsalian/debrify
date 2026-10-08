package com.debrify.app.tv

import android.view.View
import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvSourceSwitchFeedbackCharacterizationTest : TvPhase8OriginalTest() {
    @Test fun classicBadgePinsShowAnimationAndImmediateHideCancelsIt() {
        invoke("showStremioSourceBadge")
        assertEquals(View.VISIBLE, badge().visibility); assertEquals(0f, badge().alpha, 0f); assertEquals(30f, badge().translationX, 0f)
        assertEquals(250L, badge().animate().duration)
        tick(300); assertEquals(1f, badge().alpha, 0f); assertEquals(0f, badge().translationX, 0f)
        invoke("hideStremioSourceBadgeImmediately")
        assertEquals(View.GONE, badge().visibility); assertEquals(0f, badge().alpha, 0f); assertEquals(0f, badge().translationX, 0f)
        tick(300); assertEquals(View.GONE, badge().visibility)
    }
    @Test fun hideBadgeEndActionUsesGoneAndResetsTranslation() {
        badge().visibility = View.VISIBLE; badge().alpha = 1f; invoke("hideStremioSourceBadge")
        assertEquals(200L, badge().animate().duration); assertEquals(View.VISIBLE, badge().visibility)
        tick(100); assertTrue(badge().alpha < 1f); assertTrue(badge().translationX > 0f)
        tick(160); assertEquals(View.GONE, badge().visibility); assertEquals(0f, badge().translationX, 0f)
    }
    @Test fun ottShowUsesButtonAvailabilityAndKeepsCornerBadgeHidden() {
        val button = androidx.appcompat.widget.AppCompatButton(activity); set("ottSourcesButton", button); set("ottSkinInstalled", true)
        badge().visibility = View.GONE; invoke("showStremioSourceBadge")
        assertEquals(View.VISIBLE, button.visibility); assertEquals(View.GONE, badge().visibility)
        sources().clear(); invoke("showStremioSourceBadge"); assertEquals(View.GONE, button.visibility)
    }
    @Test fun watcherReadyAndIdlePinMessagesAndIptvKeySuppressesError() {
        invoke("watchSourceSwitchOutcome", 1); probe.emit(Player.STATE_READY)
        assertEquals("✓ Source 1", pill().text.toString()); assertNull(field("sourceSwitchReadyListener")); assertNull(field("sourceSwitchTimeoutRunnable"))
        invoke("watchSourceSwitchOutcome", 1); probe.emit(Player.STATE_IDLE)
        assertEquals("Couldn't play Source 1 — pick another source", pill().text.toString())
        set("isIptvMode", true); set("iptvStremioChannelKey", "key")
        invoke("watchSourceSwitchOutcome", 1); probe.emit(Player.STATE_IDLE); tick(250)
        assertEquals(View.GONE, pill().visibility)
    }
    @Test fun watcherHasTenSecondDeadlineAndUnknownNameFallback() {
        invoke("showStatusPill", "waiting"); invoke("watchSourceSwitchOutcome", 99)
        tick(9999); assertNotNull(field("sourceSwitchReadyListener")); tick(1)
        assertNull(field("sourceSwitchReadyListener")); assertNull(field("sourceSwitchTimeoutRunnable")); tick(250)
        assertEquals(View.GONE, pill().visibility)
        invoke("watchSourceSwitchOutcome", 99); probe.emit(Player.STATE_READY); assertEquals("✓ source", pill().text.toString())
    }
    @Test fun cancelUsesCurrentPlayerAndRemovesTimeoutWhileDropClearsOnlyPendingFeedback() {
        invoke("showStatusPill", "waiting"); invoke("watchSourceSwitchOutcome", 1)
        val listener = field("sourceSwitchReadyListener"); val replacement = TvPhase8PlayerProbe(); set("player", replacement.player)
        invoke("cancelSourceSwitchWait")
        assertEquals(listOf(listener), replacement.removed); assertTrue(probe.removed.isEmpty()); assertTrue(probe.listeners.contains(listener))
        assertNull(field("sourceSwitchTimeoutRunnable")); tick(10_500); assertEquals(View.VISIBLE, pill().visibility)
        invoke("dropStaleSourceSwitchFeedback"); tick(250); assertEquals(View.VISIBLE, pill().visibility)
        invoke("watchSourceSwitchOutcome", 1); invoke("dropStaleSourceSwitchFeedback"); tick(250)
        assertEquals(View.GONE, pill().visibility); assertNull(field("sourceSwitchReadyListener"))
    }
    @Test fun destroyCancelsSourceWaitOnlyAfterReleaseWithNullPlayer() {
        invoke("watchSourceSwitchOutcome", 1); val listener = field("sourceSwitchReadyListener")
        probe.onEvent = { if (it == "release") assertSame("wait survives until player release", listener, field("sourceSwitchReadyListener")) }
        lifecycle.pause().stop().destroy()
        assertTrue(probe.events.contains("release")); assertNull(field("player")); assertNull(field("sourceSwitchReadyListener"))
        assertTrue("listener removal is the existing no-op after release", !probe.removed.contains(listener))
        assertNull(field("sourceSwitchTimeoutRunnable"))
    }
}
