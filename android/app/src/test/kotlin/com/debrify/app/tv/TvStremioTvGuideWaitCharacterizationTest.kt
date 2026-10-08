package com.debrify.app.tv

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
internal class TvStremioTvGuideWaitCharacterizationTest : TvPhase7OriginalTest() {
    private fun waitForReady() { standard(); set("stremioTvGuideVisible", true); invoke("hideGuideWhenReady") }

    @Test fun readyHidesAndCancelsWhileBufferingAndEndedDoNothing() {
        waitForReady(); val listener = field("guidePanelReadyListener")
        probe.emit(Player.STATE_BUFFERING); probe.emit(Player.STATE_ENDED)
        assertTrue(visible()); assertSame(listener, field("guidePanelReadyListener")); assertTrue(probe.removed.isEmpty())
        probe.emit(Player.STATE_READY)
        assertFalse("READY hides guide", visible()); assertEquals(listOf(listener), probe.removed)
        assertNull(field("guidePanelReadyListener")); assertNull(field("guidePanelTimeoutRunnable"))
        set("stremioTvGuideVisible", true); tick(10_000); assertTrue("READY removes timeout", visible())
    }

    @Test fun idleClearsAllSwitchingMarksAndNotifiesWhileKeepingGuideOpen() {
        waitForReady(); channels().forEach { it.isSwitchingChannel = true }
        val observer = TvPhase7AdapterObserver(); adapter().registerAdapterDataObserver(observer)
        probe.emit(Player.STATE_IDLE)
        assertTrue("IDLE keeps guide open", visible()); assertTrue("IDLE clears every switching mark", channels().none { it.isSwitchingChannel })
        assertEquals(listOf("all"), observer.events); assertTrue(probe.listeners.isEmpty())
        assertNull(field("guidePanelTimeoutRunnable")); tick(10_000); assertTrue(visible())
    }

    @Test fun timeoutStartsAt10000msAndCancelsListener() {
        waitForReady(); tick(9999)
        assertTrue("guide stays open until timeout", visible()); assertEquals(1, probe.listeners.size)
        tick(1)
        assertFalse("ten-second fallback hides guide", visible()); assertTrue(probe.listeners.isEmpty())
        assertNull(field("guidePanelReadyListener")); assertNull(field("guidePanelTimeoutRunnable"))
    }

    @Test fun repeatedWaitReplacesOldListenerAndCancelReadsCurrentPlayer() {
        waitForReady(); val old = field("guidePanelReadyListener") as Player.Listener
        tick(500); invoke("hideGuideWhenReady")
        assertEquals(listOf(old), probe.removed); assertEquals(1, probe.listeners.size)
        tick(9500); assertTrue("old timeout was cancelled", visible())
        val replacement = TvPhase7PlayerProbe(); val current = field("guidePanelReadyListener") as Player.Listener
        set("player", replacement.player); invoke("cancelGuideWait")
        assertEquals("cancel targets invocation-time player", listOf(current), replacement.removed)
        assertTrue("original retains listener when player changed", probe.listeners.contains(current))
        assertNull(field("guidePanelReadyListener")); assertNull(field("guidePanelTimeoutRunnable"))
        tick(1000); assertTrue("cancel removes replacement timeout", visible())
    }

    @Test fun hiddenGuideDoesNotRegisterWait() {
        standard(); invoke("hideGuideWhenReady")
        assertTrue("hidden guide has no listener", probe.listeners.isEmpty())
        assertNull(field("guidePanelReadyListener")); assertNull(field("guidePanelTimeoutRunnable"))
        tick(10_000); assertFalse(visible())
    }

    @Test fun destroyDoesNotBumpSwitchTokenOrExplicitlyCancelGuideWait() {
        waitForReady(); set("stremioTvSwitchToken", 17)
        val listener = field("guidePanelReadyListener"); val timeout = field("guidePanelTimeoutRunnable")
        lifecycle.pause().stop().destroy()
        assertEquals("destroy does not invalidate guide token", 17, field("stremioTvSwitchToken"))
        assertSame("listener field retained on destroy", listener, field("guidePanelReadyListener"))
        assertSame("timeout field retained on destroy", timeout, field("guidePanelTimeoutRunnable"))
        assertFalse("no explicit removal of guide listener", probe.removed.contains(listener))
        assertTrue(probe.events.contains("release")); assertNull(field("player"))
        tick(10_000)
        assertTrue("wholesale progress-handler cleanup removes pending timeout", visible())
        assertSame(timeout, field("guidePanelTimeoutRunnable"))
    }
}
