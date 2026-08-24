package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StartupFailoverCursorTest {
    @Test
    fun `walks forward in provider order without wrapping`() {
        val cursor = StartupFailoverCursor(startIndex = 1, maxAttempts = 5)

        assertEquals(1, cursor.beginInitial(sourceCount = 4))
        assertEquals(2, cursor.nextIndex(sourceCount = 4) { true })
        assertEquals(3, cursor.nextIndex(sourceCount = 4) { true })
        assertNull(cursor.nextIndex(sourceCount = 4) { true })
    }

    @Test
    fun `skips ineligible rows and respects the attempt cap`() {
        val cursor = StartupFailoverCursor(startIndex = 0, maxAttempts = 2)

        assertEquals(0, cursor.beginInitial(sourceCount = 5))
        assertEquals(3, cursor.nextIndex(sourceCount = 5) { it >= 3 })
        assertNull(cursor.nextIndex(sourceCount = 5) { true })
        assertEquals(2, cursor.attempts)
    }

    @Test
    fun `first rendered frame permanently commits the candidate`() {
        val cursor = StartupFailoverCursor(startIndex = 0, maxAttempts = 5)

        assertEquals(0, cursor.beginInitial(sourceCount = 3))
        cursor.commit()

        assertTrue(cursor.committed)
        assertNull(cursor.nextIndex(sourceCount = 3) { true })
    }

    @Test
    fun `disabled retry policy permits only the initial source`() {
        val cursor = StartupFailoverCursor(startIndex = 0, maxAttempts = 1)

        assertEquals(0, cursor.beginInitial(sourceCount = 3))
        assertNull(cursor.nextIndex(sourceCount = 3) { true })
    }

    @Test
    fun `late initial resolver generation is rejected after failover`() {
        assertTrue(isCurrentStartupGeneration(captured = 4, current = 4))
        assertEquals(false, isCurrentStartupGeneration(captured = 4, current = 6))
    }

    @Test
    fun `renamed AIOStreams addon retains error slate provenance`() {
        assertTrue(
            isAioStreamsErrorSlate(
                addonId = "com.aiostreams.renamed.user",
                sourceName = "My Streams",
                displayName = "4K release",
                url = "https://opaque-cdn.example/video",
                durationMs = 120_000L,
            )
        )
    }

    @Test
    fun `startup playlist must contain the exact requested episode`() {
        val episodes = listOf(1 to 1, 2 to 4, null to null)

        assertTrue(containsExactEpisode(episodes, season = 2, episode = 4))
        assertEquals(
            false,
            containsExactEpisode(episodes, season = 2, episode = 5),
        )
    }

    @Test
    fun `multi-file packs must prove the episode but singletons are trusted`() {
        val pack = listOf(2 to 1, 2 to 2, 2 to 3)
        assertEquals(
            false,
            startupPlaylistSatisfiesEpisode(pack, season = 2, episode = 5),
        )
        assertTrue(startupPlaylistSatisfiesEpisode(pack, season = 2, episode = 3))

        // A single-file torrent with an unparseable name (null S/E) was still
        // episode-scoped by the search that matched it.
        val singleton = listOf<Pair<Int?, Int?>>(null to null)
        assertTrue(
            startupPlaylistSatisfiesEpisode(singleton, season = 2, episode = 5),
        )
    }
}
