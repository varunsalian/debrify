package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.TimeUnit

class TvPlaybackRecoveryStoreTest {
    @get:Rule val temp = TemporaryFolder()
    private lateinit var files: File
    private var session = 0

    @Before fun setup() {
        files = temp.newFolder()
        session = TvPlaybackRecoveryStore.allocateSessionId(files)
        TvPlaybackRecoveryStore.begin(files, session)
    }

    private fun checkpoint(sequence: Long, episode: Int = 4, completed: Boolean = false,
                           sessionId: Int = session, type: String = "series") = JSONObject()
        .put("version", 1).put("sessionId", sessionId).put("sequence", sequence)
        .put("profileId", "adult").put("dataGeneration", 3)
        .put("updatedAtMs", System.currentTimeMillis()).put("contentType", type)
        .put("seriesTitle", "Example Show").put("season", 2).put("episode", episode)
        .put("itemIndex", episode - 1).put("resumeId", "episode-$episode")
        .put("completed", completed).put("positionMs", 5000).put("durationMs", 100000)

    private fun stage(record: JSONObject) = TvPlaybackRecoveryStore.stage(files, record.toString())
    private fun journal() = JSONObject(TvPlaybackRecoveryStore.read(files)!!)

    @Test fun bingeKeepsEveryCompletionAndLatestPosition() {
        stage(checkpoint(1, completed = true))
        stage(checkpoint(2, episode = 5))
        stage(checkpoint(3, episode = 5, completed = true))
        stage(checkpoint(4, episode = 6))
        val saved = journal()
        assertEquals(2, saved.getJSONArray("completions").length())
        assertEquals(4, saved.getJSONArray("completions").getJSONObject(0).getInt("episode"))
        assertEquals(5, saved.getJSONArray("completions").getJSONObject(1).getInt("episode"))
        assertEquals(6, saved.getJSONArray("latest").getJSONObject(0).getInt("episode"))
    }

    @Test fun collectionAutoAdvanceAlsoRetainsCompletions() {
        stage(checkpoint(1, completed = true, type = "collection"))
        stage(checkpoint(2, episode = 5, type = "collection"))
        assertEquals(1, journal().getJSONArray("completions").length())
        assertEquals(1, journal().getJSONArray("latest").length())
    }

    @Test fun ackOfNextEpisodeDoesNotConsumeEarlierCompletion() {
        stage(checkpoint(1, completed = true))
        stage(checkpoint(2, episode = 5))
        TvPlaybackRecoveryStore.acknowledge(files, session, 2)
        assertEquals(1, journal().getJSONArray("completions").length())
        assertEquals(0, journal().getJSONArray("latest").length())
    }

    @Test fun cumulativeFlagsDoNotRecreateAcknowledgedCompletion() {
        stage(checkpoint(1, completed = true))
        TvPlaybackRecoveryStore.acknowledge(files, session, 1)
        stage(checkpoint(2).put("completionReached", true))
        assertNull(TvPlaybackRecoveryStore.read(files))
    }

    @Test fun oldQueuedPositionCannotRecreateAcknowledgedExitSnapshot() {
        stage(checkpoint(10)) // synchronous finish overtakes an old queued tick
        TvPlaybackRecoveryStore.acknowledge(files, session, 10)
        stage(checkpoint(9))
        assertNull(TvPlaybackRecoveryStore.read(files))
    }

    @Test fun pendingJournalSurvivesNextLaunchAndRejectsOldActivityWrites() {
        stage(checkpoint(1, completed = true))
        stage(checkpoint(2, episode = 5))
        val newSession = TvPlaybackRecoveryStore.allocateSessionId(files)
        TvPlaybackRecoveryStore.begin(files, newSession)
        stage(checkpoint(100, episode = 9))
        stage(checkpoint(1, episode = 6, sessionId = newSession))
        val saved = journal()
        assertEquals(1, saved.getJSONArray("completions").length())
        assertEquals(2, saved.getJSONArray("latest").length())
        assertEquals(5, saved.getJSONArray("latest").getJSONObject(0).getInt("episode"))
        assertEquals(6, saved.getJSONArray("latest").getJSONObject(1).getInt("episode"))
    }

    @Test fun asynchronousAckOutlivesActivityAndFollowsQueuedStage() {
        TvPlaybackRecoveryStore.stageAsync(files, checkpoint(1).toString())
        // The activity owns neither this queue nor its lifetime.
        TvPlaybackRecoveryStore.acknowledgeAsync(files, session, 1).get(5, TimeUnit.SECONDS)
        assertNull(TvPlaybackRecoveryStore.read(files))
    }

    @Test fun allocationSurvivesHostRecreationAndAvoidsRetainedSessions() {
        stage(checkpoint(1, sessionId = session))
        val next = TvPlaybackRecoveryStore.allocateSessionId(files)
        val another = TvPlaybackRecoveryStore.allocateSessionId(files)
        assertNotEquals(session, next)
        assertNotEquals(next, another)
    }

    @Test fun unreadableJournalDoesNotBlockSessionAllocationOrBegin() {
        // A directory at the journal path deterministically fails readText,
        // unlike chmod which is ineffective when tests run with elevated access.
        val blockedJournal = File(files, "tv_playback_recovery.json")
        assertTrue(blockedJournal.mkdir())
        var failures = 0
        val first = TvPlaybackRecoveryStore.allocateSessionId(files) { failures++ }
        val second = TvPlaybackRecoveryStore.allocateSessionId(files) { failures++ }
        assertEquals(2, failures)
        assertTrue(first > 0)
        assertTrue(second > 0)
        assertNotEquals(first, second)
        TvPlaybackRecoveryStore.begin(files, second)
        assertTrue(blockedJournal.isDirectory) // allocation never destroys it
        assertTrue(blockedJournal.delete())
        stage(checkpoint(1, sessionId = second))
        assertEquals(second, journal().getJSONArray("latest").getJSONObject(0).getInt("sessionId"))
    }

    @Test fun failedRecoveryLoggingCannotBlockAllocation() {
        assertTrue(File(files, "tv_playback_recovery.json").mkdir())
        val allocated = TvPlaybackRecoveryStore.allocateSessionId(files) {
            throw IllegalStateException("diagnostics unavailable")
        }
        assertTrue(allocated > 0)
    }

    @Test fun legacyCompletionIsMigratedAndCanBeAcknowledged() {
        File(files, "tv_playback_recovery.json").writeText(checkpoint(1, completed = true).toString())
        assertEquals(1, journal().getJSONArray("completions").length())
        TvPlaybackRecoveryStore.acknowledge(files, session, 1)
        assertNull(TvPlaybackRecoveryStore.read(files))
    }

    @Test fun malformedExpiredAndIptvRecordsAreDiscarded() {
        val file = File(files, "tv_playback_recovery.json")
        file.writeText("{broken")
        assertNull(TvPlaybackRecoveryStore.read(files))
        assertFalse(file.exists())
        file.writeText(checkpoint(1).put("updatedAtMs", 1).toString())
        assertNull(TvPlaybackRecoveryStore.read(files))
        stage(checkpoint(1, type = "single").put("mode", "iptv"))
        assertNull(TvPlaybackRecoveryStore.read(files))
    }

    @Test fun failedReplacementPreservesLastCheckpointAndAllowsRetry() {
        stage(checkpoint(1))
        val blockedTemp = File(files, "tv_playback_recovery.json.tmp")
        assertTrue(blockedTemp.mkdir())
        // Make temp.delete fail too so the replacement remains blocked.
        val blocker = File(blockedTemp, "blocker").apply { writeText("test") }
        stage(checkpoint(2, completed = true))
        val saved = JSONObject(File(files, "tv_playback_recovery.json").readText())
        assertEquals(1L, saved.getJSONArray("latest").getJSONObject(0).getLong("sequence"))
        // A failed write must not publish its mutation into the hot cache.
        assertEquals(0, journal().getJSONArray("completions").length())
        assertEquals(1L, journal().getJSONArray("latest").getJSONObject(0).getLong("sequence"))
        assertTrue(blocker.delete())
        assertTrue(blockedTemp.delete())
        stage(checkpoint(2, completed = true))
        assertEquals(1, journal().getJSONArray("completions").length())
    }

    @Test fun jsonNullIsNeverCoercedIntoAMediaIdentity() {
        val payload = JSONObject("""{"imdbId":null,"seriesTitle":null,"title":"Movie"}""")
        assertTrue(payload.isNull("imdbId"))
        assertNull(payload.nullableString("imdbId"))
        assertNull(payload.nullableString("seriesTitle"))
        assertNull(payload.nullableString("missing"))
        assertNull(JSONObject().put("imdbId", 123).nullableString("imdbId"))
        assertNull(JSONObject().put("imdbId", " ").nullableString("imdbId"))
        assertEquals("Movie", payload.nullableString("title"))
        assertEquals("tt1234", JSONObject().put("imdbId", "tt1234").nullableString("imdbId"))
    }

    @Test fun unidentifiedMoviesKeepTheirLatestPositionInsteadOfDedupingCompletion() {
        for ((index, id) in listOf(JSONObject.NULL, "null").withIndex()) {
            val sequence = index * 2L + 1
            stage(checkpoint(sequence, type = "single", completed = true)
                .put("imdbId", id).put("localCompletionTracking", true))
            stage(checkpoint(sequence + 1, type = "single", completed = true)
                .put("imdbId", id).put("localCompletionTracking", true).put("positionMs", 99000))
            assertEquals(0, journal().getJSONArray("completions").length())
            assertEquals(99000, journal().getJSONArray("latest").getJSONObject(0).getInt("positionMs"))
        }
    }

    @Test fun hotTicksReuseParsedJournalAndAckDurablyRetainsOtherRecords() {
        stage(checkpoint(1, completed = true)) // retained while newer ticks are ACKed
        TvPlaybackRecoveryStore.clearMemoryCache()
        val reads = TvPlaybackRecoveryStore.diskReadCount
        val syncs = TvPlaybackRecoveryStore.diskSyncCount
        for (sequence in 2L..10L) {
            stage(checkpoint(sequence, episode = 5))
            assertTrue(TvPlaybackRecoveryStore.acknowledge(files, session, sequence))
            assertEquals(1, journal().getJSONArray("completions").length())
        }
        assertEquals(reads + 1, TvPlaybackRecoveryStore.diskReadCount)
        assertEquals(syncs + 18, TvPlaybackRecoveryStore.diskSyncCount)
        // A cold reader must see ACK cleanup, not just the in-memory snapshot.
        TvPlaybackRecoveryStore.clearMemoryCache()
        assertEquals(1, journal().getJSONArray("completions").length())
        assertEquals(0, journal().getJSONArray("latest").length())
    }

    @Test fun ordinaryTicksAndAcksOnlySyncTheNewCheckpoint() {
        val reads = TvPlaybackRecoveryStore.diskReadCount
        val syncs = TvPlaybackRecoveryStore.diskSyncCount
        for (sequence in 1L..10L) {
            stage(checkpoint(sequence))
            assertTrue(TvPlaybackRecoveryStore.acknowledge(files, session, sequence))
            assertNull(TvPlaybackRecoveryStore.read(files))
        }
        assertEquals(reads, TvPlaybackRecoveryStore.diskReadCount)
        assertEquals(syncs + 10, TvPlaybackRecoveryStore.diskSyncCount)
    }

    @Test fun unchangedReadsLaunchesAndMissingAcksDoNotRewriteTheJournal() {
        stage(checkpoint(1))
        val syncs = TvPlaybackRecoveryStore.diskSyncCount
        repeat(3) {
            assertNotNull(TvPlaybackRecoveryStore.read(files))
            assertTrue(TvPlaybackRecoveryStore.acknowledge(files, session, 999))
            TvPlaybackRecoveryStore.begin(files, TvPlaybackRecoveryStore.allocateSessionId(files))
        }
        assertEquals(syncs, TvPlaybackRecoveryStore.diskSyncCount)
    }

    @Test fun failedAckKeepsBothTheDiskAndCacheRetryable() {
        stage(checkpoint(1, completed = true))
        stage(checkpoint(2, episode = 5))
        val blockedTemp = File(files, "tv_playback_recovery.json.tmp")
        assertTrue(blockedTemp.mkdir())
        val blocker = File(blockedTemp, "blocker").apply { writeText("test") }
        assertFalse(TvPlaybackRecoveryStore.acknowledge(files, session, 2))
        assertEquals(1, journal().getJSONArray("latest").length())
        assertTrue(blocker.delete())
        assertTrue(blockedTemp.delete())
        assertTrue(TvPlaybackRecoveryStore.acknowledge(files, session, 2))
        TvPlaybackRecoveryStore.clearMemoryCache()
        assertEquals(1, journal().getJSONArray("completions").length())
        assertEquals(0, journal().getJSONArray("latest").length())
    }

    @Test fun discardInvalidatesTheHotCacheWithoutDeletingANewerCheckpoint() {
        stage(checkpoint(1))
        val first = TvPlaybackRecoveryStore.read(files)!!
        stage(checkpoint(2))
        assertFalse(TvPlaybackRecoveryStore.discard(files, first))
        assertEquals(2L, journal().getJSONArray("latest").getJSONObject(0).getLong("sequence"))
        assertTrue(TvPlaybackRecoveryStore.discard(files, TvPlaybackRecoveryStore.read(files)!!))
        assertNull(TvPlaybackRecoveryStore.read(files))
    }
}
