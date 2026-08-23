package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class LateEpisodeMetadataMergeTest {
    @Test
    fun currentRowNeverMovesBehindLivePlayback() {
        assertEquals(
            42_000L,
            mergeLateMetadataResumePosition(
                existingPositionMs = 12_000L,
                incomingPositionMs = 20_000L,
                livePositionMs = 42_000L,
                isCurrentItem = true,
            ),
        )
    }

    @Test
    fun currentRowCanAdoptFurtherCrossDeviceProgress() {
        assertEquals(
            60_000L,
            mergeLateMetadataResumePosition(
                existingPositionMs = 12_000L,
                incomingPositionMs = 60_000L,
                livePositionMs = 42_000L,
                isCurrentItem = true,
            ),
        )
    }

    @Test
    fun nonCurrentRowHonoursExplicitProgressClear() {
        assertEquals(
            0L,
            mergeLateMetadataResumePosition(
                existingPositionMs = 60_000L,
                incomingPositionMs = 0L,
                livePositionMs = 0L,
                isCurrentItem = false,
            ),
        )
        assertEquals(
            0L,
            mergeLateMetadataDuration(
                existingDurationMs = 3_000_000L,
                incomingDurationMs = 0L,
                liveDurationMs = 0L,
                isCurrentItem = false,
            ),
        )
    }

    @Test
    fun currentRowKeepsLiveDuration() {
        assertEquals(
            3_100_000L,
            mergeLateMetadataDuration(
                existingDurationMs = 3_000_000L,
                incomingDurationMs = 0L,
                liveDurationMs = 3_100_000L,
                isCurrentItem = true,
            ),
        )
    }
}
