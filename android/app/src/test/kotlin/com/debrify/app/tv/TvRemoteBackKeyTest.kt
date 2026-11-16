package com.debrify.app.tv

import android.view.KeyEvent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** A keyboard-style remote's Back (Escape) and gamepad B close what Back closes. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvRemoteBackKeyTest : TvPhase7OriginalTest() {
    private fun showGuide() {
        standard(); set("stremioTvGuideVisible", true); invoke("hideGuideWhenReady")
    }

    @Test fun escapeAndGamepadBCloseTheGuideLikeBack() {
        for (code in listOf(KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BUTTON_B)) {
            showGuide()
            assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code)))
            assertFalse("key $code closes the guide", visible())
        }
    }

    @Test fun ctrlEscapeIsNotBack() {
        showGuide()
        activity.dispatchKeyEvent(
            KeyEvent(0L, 0L, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ESCAPE, 0,
                KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON),
        )
        assertTrue("Ctrl+Escape leaves the guide open", visible())
    }
}
