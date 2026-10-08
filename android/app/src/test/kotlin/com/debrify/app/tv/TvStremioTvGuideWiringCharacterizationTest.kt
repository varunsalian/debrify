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

    @Test fun guideKeyRoutingConsumesLeftOffersSearchOnHeldUpAndClosesOnBack() {
        standard(); invoke("showStremioTvGuide"); layout(); pump(); layout()
        val row = list().findViewHolderForAdapterPosition(0)!!.itemView
        row.requestFocus(); shadowOf(activity).setCurrentFocus(row)
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_LEFT)))
        assertTrue(activity.dispatchKeyEvent(KeyEvent(0, 0, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP, 3)))
        assertTrue("held Up offers search focus", view("stremioTvGuideSearch").hasFocus())
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
        assertFalse("Back closes the guide through its production caller", visible())
    }

    @Test fun guideVisibilityBlocksCleanPlaybackStateWithoutOtherOverlays() {
        standard()
        assertEquals(true, invoke("isCleanPlaybackState"))
        set("stremioTvGuideVisible", true)
        assertEquals("guide visibility blocks clean playback state", false, invoke("isCleanPlaybackState"))
        set("stremioTvGuideVisible", false); assertEquals(true, invoke("isCleanPlaybackState"))
    }
}
