package com.debrify.app.tv

import android.widget.Toast
import com.debrify.app.diagnostics.DiagnosticFileLog
import org.json.JSONObject
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
internal class TvStartupGateRecoveryCharacterizationTest : TvPhase9OriginalTest() {
    @Test fun failureReportsSessionAndSkipsExternalDuplicateAndPreviouslyFailedReleases() {
        val original = source(0)
        sources().clear(); sources().addAll(listOf(original,
            StremioSource.fromJson(JSONObject().put("name", "external").put("stream_type", "externalUrl"), 1),
            StremioSource.fromJson(JSONObject().put("name", "Source 0").put("stream_type", "torrent"), 2), source(3)))
        set("sourcePersistenceSessionId", 91); begin(4); fail("decode-test")
        assertEquals(mapOf("sourcePersistenceSessionId" to 91, "sourceIndex" to 0, "reason" to "decode-test"), requestMap("startupSourceFailed"))
        assertEquals("eligible next source skips external and duplicate", 3, selected())
        assertEquals(setOf(original.failureKey("decode-test")), field("startupFailedReleases"))
        assertEquals(false, field("startupFailoverDispatching")); assertEquals(2, candidate().attempts)
    }

    @Test fun decodingFailureKeyExcludesAlternateTransportOfSameReliableRelease() {
        fun release(i: Int, type: String) = StremioSource.fromJson(JSONObject().put("name", "release.mkv")
            .put("stream_type", type).put("stremio_addon_id", "addon").put("infohash", "a".repeat(40))
            .put("direct_url", "https://gate.invalid/$i"), i)
        sources().clear(); sources().addAll(listOf(release(0, "torrent"), release(1, "directUrl"), source(2)))
        begin(3); fail("player:ERROR_CODE_DECODING_FAILED")
        assertEquals("decoder rejection spans transport twins", 2, selected())
    }

    @Test fun pikpakCountsAcquisitionBeforeResolveAndNeverTriesASecondTorrent() {
        model().items[0] = model().items[0].copy(provider = "pikpak")
        set("startupResolverProvider", "PiKpAk"); begin(3)
        assertEquals(true, field("startupPikPakTorrentAcquisitionAttempted"))
        fail("test"); assertTrue("second torrent is not acquired", activity.isFinishing)
        assertTrue(requests("requestStremioSourceResolve").isEmpty())
    }

    @Test fun recoveryFetchKeepsCursorAliveAndIts30SecondFallbackExhausts() {
        sources().clear(); sources().add(source(0, "https://gate.invalid/saved"))
        set("movieMoreSources", true); set("startupRecoveryAvailable", true); begin(3)
        val cursor = candidate(); fail("saved-failed")
        assertSame(cursor, field("startupFailoverCursor")); assertFalse(activity.isFinishing)
        assertEquals(true, field("startupRecoveryFetching")); assertEquals(false, field("startupRecoveryAvailable"))
        assertEquals(mapOf("mode" to "startup:begin", "season" to null, "episode" to null), requestMap("requestMoreTorrentSources"))
        advance(29_999); assertFalse(activity.isFinishing)
        advance(1); assertEquals("fallback fires at 30000 ms", false, field("startupRecoveryFetching")); tick(32); assertTrue("30 second recovery fallback finishes " + debugState(), activity.isFinishing)
        assertEquals(false, field("startupRecoveryFetching")); assertEquals(true, field("startupSourcesExhausted"))
        assertEquals("No playable source could be started", ShadowToast.getTextOfLatestToast())
    }

    @Test fun recoveryResultsDoNotReportOrBlacklistAnAdditionalFailedSource() {
        begin(2); set("startupRecoveryCandidateIndices", listOf(1)); fail("recovery-results")
        assertTrue("recovery handoff is not a source failure", requests("startupSourceFailed").isEmpty())
        assertEquals(emptySet<List<Any?>>(), field("startupFailedReleases")); assertEquals(1, selected())
    }

    @Test fun exhaustionWithRecoveryAvailableRetainsItsDistinctToastAndResultFlags() {
        begin(); set("startupRecoveryAvailable", true); fail("fatal")
        assertTrue(activity.isFinishing)
        assertEquals("Saved source failed. Looking for another source…", ShadowToast.getTextOfLatestToast())
        assertEquals(Toast.LENGTH_LONG, ShadowToast.getLatestToast().duration)
        invoke("sendFinished")
        assertEquals(mapOf("sourcePersistenceSessionId" to field("sourcePersistenceSessionId"),
            "startupSourcesExhausted" to true, "startupRecoveryConsumed" to true), requestMap("torrentPlaybackFinished"))
    }

    private fun exhaustion(tv: Boolean) {
        val session = TvPlaybackRecoveryStore.allocateSessionId(activity.filesDir)
        TvPlaybackRecoveryStore.begin(activity.filesDir, session)
        set("sourcePersistenceSessionId", session); set("recoveryProfileId", "gate-owner"); set("recoveryDataGeneration", 4)
        set("recoveryTitle", "Film"); PlaybackReturnHandoff.begin(session, "gate-owner", 4)
        if (tv) { sources()[0] = aio(); set("isStremioTvMode", true) }
        begin(); fail("exhaust")
        assertTrue("actual Activity.finish override executed", activity.isFinishing)
        assertEquals(true, field("finishProgressAttempted")); assertEquals(false, field("finalProgressSnapshot"))
        assertNull(field("startupFailoverCursor")); assertEquals(true, field("startupSourcesExhausted"))
        assertEquals(false, field("startupFailoverDispatching"))
        assertEquals(session, PlaybackReturnHandoff.consumeSession("gate-owner", 4))
        assertEquals(null, PlaybackReturnHandoff.consumeSession("gate-owner", 4))
        val reports = requests("torrentPlaybackProgress")
        assertEquals("exhausted progress differs for VOD and TV", if (tv) 0 else 1, reports.size)
        drainWriter()
        val checkpoint = TvPlaybackRecoveryStore.read(activity.filesDir)
        if (tv) assertNull("TV exhaustion has no checkpoint", checkpoint) else {
            assertNotNull("VOD finish writes checkpoint synchronously", checkpoint)
            val saved = JSONObject(checkpoint!!).getJSONArray("latest").getJSONObject(0); assertEquals(25_000L, saved.getLong("positionMs"))
            assertEquals(600_000L, saved.getLong("durationMs")); assertEquals(session, saved.getInt("sessionId"))
            assertEquals(false, requestMap("torrentPlaybackProgress")["completed"])
        }
        assertEquals(1, diagnosticEvents().count { it.optString("event") == "finish_requested" })
        activity.finish(); assertEquals("finish progress is one-shot", reports.size, requests("torrentPlaybackProgress").size)
        invoke("sendFinished")
        assertEquals(mapOf("sourcePersistenceSessionId" to session, "startupSourcesExhausted" to true,
            "startupRecoveryConsumed" to true), requestMap("torrentPlaybackFinished"))
    }
    @Test fun ordinaryVodExhaustionRunsFinishOverrideReportsCheckpointAndHandoff() = exhaustion(false)
    @Test fun stremioTvExhaustionRunsFinishOverrideSuppressesCheckpointButKeepsHandoff() = exhaustion(true)

    @Test fun staleOrCommittedResolutionFailureHasNoEffectOrBridgeReport() {
        begin(); assertEquals(false, resolveFailure(1)); assertFalse(activity.isFinishing)
        assertTrue(requests("startupSourceFailed").isEmpty())
        invoke("commitStartupCandidate"); messenger.requests.clear()
        assertEquals(false, resolveFailure(0)); assertTrue(requests("startupSourceFailed").isEmpty())
        assertFalse(activity.isFinishing)
    }

    @Test fun sourceFieldsSanitizeTransportBoundLengthAndNeverIncludeIdentityOrUrl() {
        sources()[0] = StremioSource.fromJson(JSONObject().put("name", "private title").put("stream_type", "ToR Rent /" + "Z".repeat(40))
            .put("stremio_addon_id", "addon").put("source", "mediaserver:private").put("direct_url", "https://secret.invalid/token"), 0)
        begin()
        val log = org.robolectric.shadows.ShadowLog.getLogsForTag("DebrifyStartupGate").last { it.msg.contains("event=candidate_open") }.msg
        assertTrue(log.contains("type=tor_rent__" + "z".repeat(22)))
        assertTrue(log.contains("addonPresent=true sourcePresent=true mediaServer=true"))
        assertFalse(log.contains("private")); assertFalse(log.contains("secret.invalid"))
    }

    @Test fun sourceSelectionAndMediaServerRecordsReachTheRealDiagnosticWriter() {
        sources()[0] = StremioSource.fromJson(JSONObject().put("name", "Server").put("stream_type", "directUrl")
            .put("direct_url", "https://gate.invalid/server").put("source", "mediaserver:id"), 0)
        set("manualSourceRestoreInProgress", true)
        (field("playbackListener") as androidx.media3.common.Player.Listener)
            .onPlayerError(androidx.media3.common.PlaybackException("test", null, 7))
        manual(); reject("resolve:test")
        val events = diagnosticEvents()
        val mediaRows = events.filter { it.optString("source") == "media_server" && it.optString("event") == "player_error" }
        assertEquals("one media-server record reaches writer", 1, mediaRows.size)
        assertEquals("player=exo index=0 errorCode=7 httpStatus=null", mediaRows.first().getString("message"))
        val selectionRows = events.filter { it.optString("source") == "source_selection" && it.optString("event") == "player_switch_rejected" }
        assertEquals("one source-selection record reaches writer", 1, selectionRows.size)
        assertEquals("SourceSelect: event=player_switch_rejected player=exo index=1 previous=0 season=null episode=null transport=torrent reason=resolve:test mediaServer=false", selectionRows.first().getString("message"))
    }

    @Test fun parsePayloadClampsAttemptsResetsEmptyProviderAndDefaultsGatePolicy() {
        for ((raw, expected) in listOf(-1 to 1, 0 to 1, 10 to 10, 11 to 10)) {
            val input = JSONObject().put("items", org.json.JSONArray().put(JSONObject().put("title", "Film").put("url", "https://gate.invalid")))
                .put("startupMaxAttempts", raw).put("startupResolverProvider", "")
            assertNotNull(call("parsePayload", arrayOf(stringType), input.toString()))
            assertEquals(expected, field("startupMaxAttempts")); assertNull(field("startupResolverProvider"))
            assertEquals(false, field("startupTryNextOnFailure")); assertEquals(false, field("startupRecoveryAvailable"))
            assertEquals(false, field("startupHasRemainingSavedSources"))
        }
    }
}
