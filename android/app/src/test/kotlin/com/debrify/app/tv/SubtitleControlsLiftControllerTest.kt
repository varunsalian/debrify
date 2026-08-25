package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class SubtitleControlsLiftControllerTest {
    @Test
    fun `raises a low subtitle above controls and margin`() {
        val result = SubtitleControlsLiftController.targetLiftPx(
            subtitleHeightPx = 1000,
            clearanceHeightPx = 180,
            clearanceMarginPx = 20,
        )

        assertEquals(200f, result, 0.0001f)
    }

    @Test
    fun `uses full clearance so explicitly positioned cues move too`() {
        val result = SubtitleControlsLiftController.targetLiftPx(
            subtitleHeightPx = 1000,
            clearanceHeightPx = 120,
            clearanceMarginPx = 20,
        )

        assertEquals(140f, result, 0.0001f)
    }

    @Test
    fun `keeps the saved position until layout has a height`() {
        val result = SubtitleControlsLiftController.targetLiftPx(
            subtitleHeightPx = 0,
            clearanceHeightPx = 180,
            clearanceMarginPx = 20,
        )

        assertEquals(0f, result, 0.0001f)
    }

    @Test
    fun `compensates padding so an already high default cue stays put`() {
        val result = SubtitleControlsLiftController.compensatedPaddingFraction(
            basePaddingFraction = 0.25f,
            subtitleHeightPx = 1000,
            liftPx = 140f,
        )

        assertEquals(0.11f, result, 0.0001f)
    }
}
