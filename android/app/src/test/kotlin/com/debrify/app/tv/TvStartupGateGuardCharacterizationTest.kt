package com.debrify.app.tv

import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlaybackException
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStartupGateGuardCharacterizationTest : TvPhase9OriginalTest() {
    @Test fun watchdogRechecksLiveErrorStateBufferAndPlayerEligibility() {
        for (guard in listOf("error", "state", "buffer", "player")) {
            ReflectionHelpers.setField(activity, "mFinished", false)
            set("finishProgressAttempted", false)
            set("player", gatePlayer); probe.error = null; probe.state = Player.STATE_BUFFERING; buffered = 1
            begin(); advance(12_000)
            assertFalse("eligible loading data initially extends $guard case", activity.isFinishing)
            when (guard) {
                "error" -> probe.error = ExoPlaybackException.createForSource(IOException("failed"), PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)
                "state" -> probe.state = Player.STATE_READY
                "buffer" -> buffered = 0
                "player" -> set("player", null)
            }
            advance(3_000)
            assertTrue("recheck reads live $guard eligibility", activity.isFinishing)
            assertEquals("timeout", requestMap("startupSourceFailed")["reason"])
        }
    }

    @Test fun reprepareRejectsDestroyedActivityEvenWithMatchingChannelRetryAndLivePlayer() {
        model().items[0] = model().items[0].copy(provider = "pikpak")
        probe.error = ExoPlaybackException.createForSource(IOException("cold"), PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)
        lifecycle.pause().stop().destroy()
        assertTrue(activity.isDestroyed)
        ReflectionHelpers.setField(activity, "mFinished", false)
        set("isStremioTvMode", true); set("player", gatePlayer); probe.events.clear()
        call("schedulePikPakGateReprepare", arrayOf(boxedIntType), field("pikPakRetryId"))
        advance(4_000)
        assertFalse("destroyed host rejects a late reprepare request", probe.events.contains("prepare"))
        assertFalse(probe.events.contains("play")); assertNull(field("pikPakGateReprepare"))
    }
}
