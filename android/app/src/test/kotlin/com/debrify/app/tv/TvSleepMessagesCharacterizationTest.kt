package com.debrify.app.tv

import android.widget.Toast
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSleepMessagesCharacterizationTest : TvPhase3OriginalTest() {
    private fun toast(text: String, duration: Int) {
        assertEquals(text, ShadowToast.getTextOfLatestToast()); assertEquals(duration, ShadowToast.getLatestToast().duration)
    }
    @Test fun countdownEndOfItemCancelAndFireKeepExactToastTextsAndDurations() {
        bindViews(); series(); invoke("startSleepCountdown", 10)
        toast("Sleep timer set for 10 minutes", Toast.LENGTH_SHORT)
        invoke("armSleepAtEndOfItem"); toast("Sleep timer: stopping at the end of this episode", Toast.LENGTH_SHORT)
        invoke("cancelSleepTimer", true); toast("Sleep timer off", Toast.LENGTH_SHORT)
        invoke("fireSleepTimer"); toast("Sleep timer ended — paused", Toast.LENGTH_LONG)
    }
}
