package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvUpNextCharacterizationTest : TvPhase3OriginalTest() {
    private fun setup(): PlayerProbe {
        bindViews(); series().nextEpisodeMap = mapOf(0 to 1)
        return PlayerProbe(position = 575_000L).also { set("player", it.player) }
    }
    private fun visible() = field("upNextVisible") as Boolean
    private fun ticker() = (field("upNextTicker") as Runnable).run()

    @Test fun exactMinimumDurationRemainingThresholdAndPlaybackGatesKeepTheCardHiddenOrShown() {
        val p = setup()
        for ((duration, remaining, expected) in listOf(Triple(300_000L, 25_000L, false),
            Triple(300_001L, 25_001L, false), Triple(300_001L, 0L, false), Triple(300_001L, 25_000L, true))) {
            p.duration = duration; p.position = duration - remaining
            invoke("maybeShowUpNext"); assertEquals("duration=$duration remaining=$remaining", expected, visible())
        }
        invoke("hideUpNextCard")
        p.duration = 600_000L; p.position = 575_000L
        p.playing = false; invoke("maybeShowUpNext"); assertFalse(visible())
        p.playing = true; p.state = androidx.media3.common.Player.STATE_BUFFERING
        invoke("maybeShowUpNext"); assertFalse(visible())
        p.state = androidx.media3.common.Player.STATE_READY
        for (flag in listOf("isIptvMode", "isStremioTvMode", "controlsMenuVisible", "playlistVisible", "seekbarVisible")) {
            set(flag, true); invoke("maybeShowUpNext"); assertFalse(flag, visible()); set(flag, false)
        }
    }

    @Test fun showTitlePosterGoneAndDismissalAreWiredToCurrentIndex() {
        setup(); invoke("showUpNextCard", 1)
        assertTrue(visible()); assertEquals(View.VISIBLE, (field("upNextCard") as View).visibility)
        assertEquals("S01E02 · Second", (field("upNextTitle") as TextView).text.toString())
        assertEquals(View.GONE, (field("upNextPoster") as View).visibility)
        invoke("dismissUpNext"); assertFalse(visible()); assertEquals(0, field("upNextDismissedForIndex"))
        invoke("maybeShowUpNext"); assertFalse(visible())
        advance(220); assertEquals(View.GONE, (field("upNextCard") as View).visibility)
    }

    @Test fun tickerRoundsUpAndRepostsAtFiveHundredMillisecondsAndObservesReplacementPlayer() {
        setup(); invoke("showUpNextCard", 1); idle()
        val label = field("upNextCountdown") as TextView
        assertEquals("Starting in 25s", label.text.toString())
        val handler = field("upNextHandler") as android.os.Handler
        val runnable = field("upNextTicker") as Runnable
        handler.removeCallbacks(runnable); runnable.run()
        var message = TvPlayerOriginalAccess.field(android.os.Looper.getMainLooper().queue, "mMessages") as android.os.Message?
        while (message != null && message.callback !== runnable) message = TvPlayerOriginalAccess.field(message, "next") as android.os.Message?
        assertNotNull("ticker posts itself", message)
        assertEquals(500L, message!!.getWhen() - android.os.SystemClock.uptimeMillis())
        set("player", PlayerProbe(position = 590_001L).player)
        handler.removeCallbacks(runnable); runnable.run()
        assertEquals("Starting in 10s", label.text.toString())
        invoke("hideUpNextCard"); set("player", PlayerProbe(position = 590_999L).player)
        advance(500); assertEquals("Starting in 10s", label.text.toString())
    }

    @Test fun tickerKeepsThirtySecondsButHidesBeyondSeekBackToleranceAndOnOverlay() {
        val p = setup(); invoke("showUpNextCard", 1)
        p.position = p.duration - 30_000L; ticker(); assertTrue(visible())
        p.position--; ticker(); assertFalse(visible())
        invoke("showUpNextCard", 1); set("controlsMenuVisible", true); ticker(); assertFalse(visible())
    }

    @Test fun tickerTriggersAtSevenHundredFiftyMillisecondsAndExplicitTriggerHonoursSleepLatch() {
        val p = setup(); set("sleepStopLatched", true); invoke("showUpNextCard", 1)
        set("payload", null)
        p.position = p.duration - 751L; ticker(); assertTrue(field("isAutoAdvancing") == false)
        assertEquals(0, field("mediaPreparationGeneration"))
        p.position++; ticker()
        // The real playItem auto-advance gate consumes isAutoAdvancing and returns.
        assertEquals(false, field("isAutoAdvancing")); assertEquals(0, field("currentIndex"))
        assertEquals(true, field("sleepStopLatched"))
        assertEquals(1, field("mediaPreparationGeneration"))
        invoke("triggerUpNext"); assertEquals(0, field("currentIndex"))
    }

    @Test fun visibleCardBackAndSelectConsumeBothKeyActionsAndOnlyDownDispatches() {
        setup(); set("sleepStopLatched", true); invoke("showUpNextCard", 1)
        set("payload", null)
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)))
        assertTrue(visible()); assertEquals(-1, field("upNextDismissedForIndex"))
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER)))
        assertEquals(0, field("currentIndex")); assertEquals(false, field("isAutoAdvancing"))
        assertEquals(1, field("mediaPreparationGeneration"))
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
        assertFalse(visible()); assertEquals(0, field("upNextDismissedForIndex"))
    }
}
