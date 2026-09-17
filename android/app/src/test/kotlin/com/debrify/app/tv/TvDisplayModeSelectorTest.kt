package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TvDisplayModeSelectorTest {
    private val base = TvDisplayModeCandidate(1, 3840, 2160, 60f)
    private val modes = listOf(
        base,
        TvDisplayModeCandidate(2, 3840, 2160, 23.976f),
        TvDisplayModeCandidate(3, 1920, 1080, 23.976f),
        TvDisplayModeCandidate(4, 1920, 1080, 50f),
        TvDisplayModeCandidate(5, 1280, 720, 59.94f),
    )

    @Test
    fun `frame rate only preserves configured resolution`() {
        val selected = TvDisplayModeSelector.select(
            base,
            modes,
            videoWidth = 1920,
            videoHeight = 800,
            videoFrameRate = 23.976f,
            matchResolution = false,
        )

        assertEquals(2, selected?.id)
    }

    @Test
    fun `full matching maps cropped cinema raster by width`() {
        val selected = TvDisplayModeSelector.select(
            base,
            modes,
            videoWidth = 1920,
            videoHeight = 800,
            videoFrameRate = 23.976f,
            matchResolution = true,
        )

        assertEquals(3, selected?.id)
    }

    @Test
    fun `integer refresh multiple is eligible`() {
        val selected = TvDisplayModeSelector.select(
            base,
            modes,
            videoWidth = 1920,
            videoHeight = 1080,
            videoFrameRate = 25f,
            matchResolution = true,
        )

        assertEquals(4, selected?.id)
    }

    @Test
    fun `unrelated refresh rates are not selected`() {
        val selected = TvDisplayModeSelector.select(
            base,
            listOf(base),
            videoWidth = 3840,
            videoHeight = 2160,
            videoFrameRate = 24f,
            matchResolution = true,
        )

        assertNull(selected)
    }
}
