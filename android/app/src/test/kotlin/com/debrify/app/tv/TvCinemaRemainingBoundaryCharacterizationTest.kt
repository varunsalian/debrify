package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvCinemaRemainingBoundaryCharacterizationTest(override val skin: TvControlsSkin) : TvPhase16OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}") fun skins(): List<Array<Any>> =
            TvControlsSkin.entries.filter { it != TvControlsSkin.CLASSIC }.map { arrayOf<Any>(it) }
    }
    @Test fun remainingTimeClampsAtZeroAtAndBeyondTheDuration() {
        drawScrub(position = 99_000L, duration = 100_000L)
        assertEquals("-00:01", tv("debrifyTimeTotal").text.toString())
        drawScrub(position = 100_000L, duration = 100_000L)
        assertEquals("-00:00", tv("debrifyTimeTotal").text.toString())
        drawScrub(position = 161_000L, duration = 100_000L)
        assertEquals("remaining time beyond duration", "-00:00", tv("debrifyTimeTotal").text.toString())
    }
}
