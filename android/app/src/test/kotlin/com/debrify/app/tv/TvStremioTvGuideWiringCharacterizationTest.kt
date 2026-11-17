package com.debrify.app.tv

import android.view.KeyEvent
import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Original production callers, in addition to direct guide entry points. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvStremioTvGuideWiringCharacterizationTest : TvPhase7OriginalTest() {
    @Test fun nextButtonAndEndedDispatchDifferentFinishArguments() {
        standard(); payload()
        invoke("playNext")
        assertEquals(1, requests("requestStremioTvNext").size)
        messenger.error(index("requestStremioTvNext")); pump()
        assertEquals("manual Next retains activity on failure", false, field("finishProgressAttempted"))
        (field("playbackListener") as Player.Listener).onPlaybackStateChanged(Player.STATE_ENDED)
        assertEquals("ENDED requests the following programme", 2, requests("requestStremioTvNext").size)
        messenger.error(index("requestStremioTvNext")); pump()
        assertEquals("automatic Next failure dispatches finish override", true, field("finishProgressAttempted"))
    }

    @Test fun guideKeyRoutingConsumesLeftKeepsHeldUpOnTheFirstRowAndClosesOnBack() {
        standard(); invoke("showStremioTvGuide"); layout(); pump(); layout()
        val row = list().findViewHolderForAdapterPosition(0)!!.itemView
        row.requestFocus(); shadowOf(activity).setCurrentFocus(row)
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_LEFT)))
        assertTrue(activity.dispatchKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP, 3)))
        assertTrue("held Up stays on the first row", row.hasFocus())
        assertFalse("held Up no longer jumps to search", view("stremioTvGuideSearch").hasFocus())
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
        assertFalse("Back closes the guide through its production caller", visible())
    }

    @Test fun theHoldThatOpensTheGuideDoesNotScrollIt() {
        standard(); layout(); pump()
        assertTrue(activity.dispatchKeyEvent(KeyEvent(500, 500, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP, 0)))
        assertTrue("UP opens the guide", visible())
        layout(); pump(); layout()
        // Below the first row, so only the opening-hold rule can consume it.
        val row = list().findViewHolderForAdapterPosition(1)!!.itemView
        row.requestFocus(); shadowOf(activity).setCurrentFocus(row)
        assertTrue("its repeats are consumed", activity.dispatchKeyEvent(KeyEvent(500, 800, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP, 3)))
        assertTrue("focus stays on the row", row.hasFocus())
        assertFalse("a later hold is left to the list", activity.dispatchKeyEvent(KeyEvent(900, 1200, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP, 3)))
    }

    @Test fun guideVisibilityBlocksCleanPlaybackStateWithoutOtherOverlays() {
        standard()
        assertEquals(true, invoke("isCleanPlaybackState"))
        set("stremioTvGuideVisible", true)
        assertEquals("guide visibility blocks clean playback state", false, invoke("isCleanPlaybackState"))
        set("stremioTvGuideVisible", false); assertEquals(true, invoke("isCleanPlaybackState"))
    }
}
