package com.debrify.app

import android.view.KeyEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class RemoteBackKeyTest {
    private fun key(
        action: Int,
        code: Int,
        meta: Int = 0,
        repeat: Int = 0,
        flags: Int = KeyEvent.FLAG_FROM_SYSTEM or KeyEvent.FLAG_LONG_PRESS,
    ) = KeyEvent(100L, 200L, action, code, repeat, meta, 7, 41, flags, 0x101)

    @Test fun escapeAndGamepadBBecomeBackKeepingTheirPress() {
        for (code in listOf(KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BUTTON_B)) {
            for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
                val back = RemoteBackKey.normalize(key(action, code, repeat = 2))
                assertEquals(KeyEvent.KEYCODE_BACK, back.keyCode)
                assertEquals(action, back.action)
                assertEquals(2, back.repeatCount)
                assertEquals(100L, back.downTime)
                assertEquals(200L, back.eventTime)
                assertEquals(7, back.deviceId)
                assertEquals(41, back.scanCode)
                assertEquals(0x101, back.source)
                // Long-press and cancel handling read these.
                assertEquals(
                    KeyEvent.FLAG_FROM_SYSTEM or KeyEvent.FLAG_LONG_PRESS,
                    back.flags,
                )
                assertEquals(0, back.metaState)
            }
        }
    }

    // The same instance, not a copy: Flutter recognises its re-dispatched
    // events by identity (see RemoteBackKey.normalize).
    @Test fun otherKeysAndModifiedEscapeAreUntouched() {
        for (event in listOf(
            key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK),
            key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER),
            key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BUTTON_A),
            key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ESCAPE, KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON),
            key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ESCAPE, KeyEvent.META_ALT_ON or KeyEvent.META_ALT_LEFT_ON),
            key(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ESCAPE, KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON),
        )) {
            assertSame(event, RemoteBackKey.normalize(event))
        }
    }
}
