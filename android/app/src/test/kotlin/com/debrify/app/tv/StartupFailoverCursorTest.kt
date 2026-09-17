package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StartupFailoverCursorTest {
    @Test fun `recovery whitelist leaves manual-only rows unattempted`() {
        val cursor = StartupFailoverCursor(0, 5)
        assertEquals(0, cursor.beginInitial(1))
        assertEquals(2, cursor.nextIndex(4, listOf(2)) { true })
        assertNull(cursor.nextIndex(4, listOf(2)) { true })
        assertEquals(2, cursor.attempts)
    }

    @Test fun `episode stage can visit earlier manual indices without retrying attempts`() {
        val cursor = StartupFailoverCursor(0, 4)
        cursor.beginInitial(1)
        assertEquals(3, cursor.nextIndex(4, listOf(3, 2)) { true })
        assertEquals(2, cursor.nextIndex(4, listOf(3, 2)) { true })
        assertEquals(1, cursor.nextIndex(5, listOf(3, 1, 4)) { true })
        assertNull(cursor.nextIndex(5, listOf(4)) { true })
        assertEquals(4, cursor.attempts)
    }

    @Test fun `empty pack stage does not spend the episode retry budget`() {
        val cursor = StartupFailoverCursor(0, 2)
        cursor.beginInitial(1)
        assertNull(cursor.nextIndex(3, emptyList()) { true })
        assertEquals(1, cursor.attempts)
        assertEquals(2, cursor.nextIndex(3, listOf(2)) { true })
    }
    @Test fun `nonempty recovery exhausts once even below attempt cap`() {
        // Duplicate-only responses and the PikPak guard must not restart search.
        assertTrue(startupRecoveryIsConsumed(false, true, 2, 5))
        assertTrue(startupRecoveryIsConsumed(false, true, 1, 5))
    }

    @Test fun `empty or failed recovery preserves fallback within budget`() {
        assertEquals(false, startupRecoveryIsConsumed(false, false, 1, 5))
        assertTrue(startupRecoveryIsConsumed(false, false, 5, 5))
    }

    @Test fun `remaining saved pins retain their recovery stage`() {
        assertEquals(false, startupRecoveryIsConsumed(true, false, 1, 1))
        assertEquals(false, startupRecoveryIsConsumed(true, true, 5, 5))
    }
    @Test fun `independent addon configurations remain eligible`() {
        assertTrue(startupFailureKey("config-one", "File.mkv", 42, "directUrl", videoId = "tt1:1:1") !=
            startupFailureKey("config-two", "File.mkv", 42, "directUrl", videoId = "tt1:1:1"))
    }
    @Test fun `transient failure keeps alternate transport eligible`() {
        val direct = startupFailureKey("addon", "File.mkv", 42L, "directUrl", "timeout")
        val torrent = startupFailureKey("addon", "File.mkv", 42L, "torrent")
        assertTrue(direct != torrent)
        assertEquals(startupFailureKey("addon", "File.mkv", 42L, null, videoId = "tt1:1:1"),
            startupFailureKey("addon", "File.mkv", 42L, "directUrl", "player:ERROR_CODE_DECODING_FAILED", videoId = "tt1:1:1"))
    }
    @Test fun `ambiguous labels and distinct hashes do not collide`() {
        assertTrue(startupFailureKey("addon", "Unknown", 0, "directUrl", url = "https://one") !=
            startupFailureKey("addon", "Unknown", 0, "directUrl", url = "https://two"))
        assertTrue(startupFailureKey("addon", "Unknown", 0, "torrent", infohash = "a".repeat(40)) !=
            startupFailureKey("addon", "Unknown", 0, "torrent", infohash = "b".repeat(40)))
        assertEquals(startupFailureKey("addon", "File.mkv", 42, "directUrl", videoId = "tt1:1:1", url = "https://old"),
            startupFailureKey("addon", "File.mkv", 42, "directUrl", videoId = "tt1:1:1", url = "https://new"))
    }
    @Test fun `empty recovery preserves fallback but spent budget consumes it`() {
        assertEquals(false, startupBudgetConsumed(1, 5))
        assertEquals(true, startupBudgetConsumed(5, 5))
        assertEquals(true, startupBudgetConsumed(1, 1))
    }
    @Test fun `expanding saved source results keeps attempts and does not retry the failed release`() {
        val cursor = StartupFailoverCursor(startIndex = 0, maxAttempts = 3)
        assertEquals(0, cursor.beginInitial(1))
        assertNull(cursor.nextIndex(1) { true })
        // Fetch appended a refreshed URL for the failed release at index 1.
        assertEquals(2, cursor.nextIndex(5) { it != 1 })
        assertEquals(3, cursor.nextIndex(5) { it != 1 })
        assertNull(cursor.nextIndex(5) { true })
        assertEquals(3, cursor.attempts)
    }
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
