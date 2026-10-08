package com.debrify.app.tv

import android.os.SystemClock
import androidx.media3.common.Player
import com.debrify.app.MainActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvProgressReporterCharacterizationTest : TvPhase5OriginalTest() {
    @Test fun periodicPausedAndCompletedPayloadsPreserveEveryArgumentAndStableDuration() {
        val model = movie("series", local = true); probe.state = Player.STATE_BUFFERING; probe.playing = false
        set("maxStableDurationMs", 200_000L); set("currentStremioSourceIndex", 3)
        set("playbackSpeedIndex", 4); set("resizeModeIndex", 2)
        (field("progressRunnable") as Runnable).run()
        val expected = mapOf("contentType" to "series", "itemIndex" to 0, "resumeId" to "resume", "sourceIndex" to 3,
            "positionMs" to 25_000, "durationMs" to 200_000, "season" to 2, "episode" to 4, "speed" to 1.5,
            "aspect" to "zoom", "completed" to false, "completionReached" to false, "localCompleted" to false,
            "localCompletionEligible" to false, "localCompletionReached" to false, "localCompletionTracking" to true,
            "completionThreshold" to 90, "url" to "https://example.test/a", "isPlaying" to false, "isBuffering" to true,
            "sourcePersistenceSessionId" to field("sourcePersistenceSessionId"))
        assertEquals("exact paused periodic bridge map", expected, progress())
        assertEquals(25_000L, model.items[0].resumePositionMs); assertEquals(200_000L, model.items[0].durationMs)
        invoke("sendProgress", true)
        assertEquals(200_000, progress()["positionMs"]); assertEquals(true, progress()["completed"])
        assertEquals(true, progress()["completionReached"])
        for (type in listOf("single", "collection")) {
            movie(type); invoke("sendProgress", false)
            assertEquals("exact $type bridge map", expected + mapOf("contentType" to type, "season" to null,
                "episode" to null, "localCompletionTracking" to false, "completionThreshold" to 80), progress())
        }
    }

    @Test fun visiblePlaylistRefreshObservesUpdatedItemBeforeDeliveryAndHiddenPlaylistDoesNotRefresh() {
        val model = movie(); val order = mutableListOf<String>()
        set("playlistAdapter", object : PlaylistOverlayAdapter {
            override fun setActiveIndex(index: Int) = Unit
            override fun getActiveItemPosition() = 0
            override fun updateCurrentProgress() {
                assertEquals("payload updated before refresh", 25_000L, model.items[0].resumePositionMs)
                assertEquals(100_000L, model.items[0].durationMs); order.add("refresh")
            }
        })
        set("playlistVisible", true)
        messenger.onSend = { if (it.call.method == "torrentPlaybackProgress") {
            assertEquals("refresh before bridge delivery", listOf("refresh"), order); order.add("delivery")
        } }
        invoke("sendProgress", false); assertEquals(listOf("refresh", "delivery"), order)
        messenger.onSend = null; set("playlistVisible", false); invoke("sendProgress", false)
        assertEquals(listOf("refresh", "delivery"), order)
    }

    @Test fun localCompletionUsesRawPositionInclusiveThresholdAndCumulativeDeduplication() {
        movie(local = true); probe.position = 79_999; invoke("sendProgress", false)
        assertEquals(false, progress()["localCompleted"])
        probe.position = 80_000; invoke("sendProgress", false)
        assertEquals(true, progress()["localCompleted"]); assertEquals(true, progress()["localCompletionReached"])
        invoke("sendProgress", false); assertEquals(false, progress()["localCompleted"])
        probe.position = 1; invoke("sendProgress", false)
        assertEquals(false, progress()["localCompletionEligible"]); assertEquals(true, progress()["localCompletionReached"])
        assertEquals(80, progress()["completionThreshold"])
    }

    @Test fun heldResumeTargetNeverFabricatesLocalCompletionAndCompletionUsesDuration() {
        movie(local = true); set("resumeHoldTargetMs", 95_000L); set("resumeHoldArmedAtMs", SystemClock.elapsedRealtime())
        invoke("sendProgress", false)
        assertEquals(95_000, progress()["positionMs"]); assertEquals(false, progress()["localCompletionEligible"])
        invoke("sendProgress", true); assertEquals(100_000, progress()["positionMs"])
    }

    @Test fun startupManualSwitchExhaustionAndMissingItemGuardsSuppressAllReports() {
        val model = movie()
        set("isStremioTvMode", true); set("startupSourcesExhausted", true); invoke("sendProgress", true)
        assertTrue(messenger.requests.isEmpty()); set("startupSourcesExhausted", false)
        val cursor = StartupFailoverCursor(0, 2); cursor.beginInitial(2); set("startupFailoverCursor", cursor)
        invoke("sendProgress", false); assertTrue(messenger.requests.isEmpty()); cursor.commit()
        set("manualSourceRestoreInProgress", true); invoke("sendProgress", true); assertTrue(messenger.requests.isEmpty())
        set("manualSourceRestoreInProgress", false)
        set("manualSourceSwitchSnapshot", ManualSourceSwitchSnapshot(0, 0, "single", model.items.toList(), emptyMap(), emptyMap(), null, emptyMap(), null))
        invoke("sendProgress", false); assertTrue(messenger.requests.isEmpty()); set("manualSourceSwitchSnapshot", null)
        set("currentIndex", 8); invoke("sendProgress", false); assertTrue(messenger.requests.isEmpty())
        set("payload", null); invoke("sendProgress", false); assertTrue(messenger.requests.isEmpty())
        set("payload", model); set("currentIndex", 0); invoke("sendProgress", false)
        assertEquals(1, requests("torrentPlaybackProgress").size)
    }

    @Test fun parsePayloadResetsBothPerItemCompletionSetsAndThresholdSelection() {
        movie("series", local = true); probe.position = 100_000; invoke("sendProgress", true)
        assertEquals(setOf("series:2:4"), field("locallyCompletedItemKeys"))
        assertEquals(setOf("series:2:4"), field("recoveryCompletedItemKeys"))
        call("parsePayload", arrayOf(stringType), "{\"contentType\":\"collection\",\"items\":[{\"title\":\"New\",\"url\":\"https://example.test/new\"}]}")
        assertEquals(emptySet<String>(), field("locallyCompletedItemKeys")); assertEquals(emptySet<String>(), field("recoveryCompletedItemKeys"))
        movie("collection", local = true); invoke("sendProgress", false)
        assertEquals(80, progress()["completionThreshold"]); assertEquals(setOf("index:0"), field("locallyCompletedItemKeys"))
    }

    @Test fun iptvVodPayloadIsExactAndLiveInvalidDurationPositionAndIndexAreSkipped() {
        val entry = iptv(channel(live = false)); invoke("sendProgress", false)
        assertEquals(mapOf("mode" to "iptv", "itemIndex" to 0, "url" to entry.url, "title" to "Cinema", "positionMs" to 25_000,
            "durationMs" to 100_000, "speed" to 1.0, "aspect" to "fill", "completed" to false, "isPlaying" to true,
            "sourcePersistenceSessionId" to field("sourcePersistenceSessionId")), progress())
        invoke("sendProgress", true); assertEquals(100_000, progress()["positionMs"])
        val count = messenger.requests.size
        iptv(channel()); invoke("sendProgress", true)
        iptv(channel(live = false)); probe.duration = 0; invoke("sendProgress", false)
        probe.duration = 100_000; probe.position = 0; invoke("sendProgress", false)
        set("currentIptvIndex", 2); invoke("sendProgress", true)
        assertEquals(count, messenger.requests.size); drainWriter(); assertNull(journal())
    }

    @Test fun ordinaryTicksQueueRecoveryWhileFinalCompletedAndLocalCompletionPersistBeforeDelivery() {
        movie(local = true)
        val barrier = blockWriter()
        invoke("sendProgress", false); assertNull("ordinary checkpoint waits behind writer barrier", journal())
        probe.position = 80_000
        messenger.onSend = { request -> if (request.call.method == "torrentPlaybackProgress") {
            assertEquals("completion persisted before delivery with writer blocked", 80_000L,
                requireJournal().getJSONArray("completions").getJSONObject(0).getLong("positionMs"))
        } }
        invoke("sendProgress", false)
        messenger.onSend = null; barrier.close(); drainWriter()
        assertEquals(2L, field("recoverySequence")); assertEquals(2L, requireJournal().getJSONArray("completions").getJSONObject(0).getLong("sequence"))
        probe.position = 100_000; val barrier2 = blockWriter(); invoke("sendProgress", true)
        assertEquals(true, requireJournal().getJSONArray("latest").length() == 0)
        barrier2.close()
    }

    @Test fun completedCheckpointPersistsBeforeDeliveryDespiteBlockedWriter() {
        movie("series"); val barrier = blockWriter()
        messenger.onSend = { request -> if (request.call.method == "torrentPlaybackProgress") {
            val saved = requireJournal().getJSONArray("completions").getJSONObject(0)
            assertTrue("completed persisted before bridge callback", saved.getBoolean("completed"))
            assertEquals(100_000L, saved.getLong("positionMs"))
        } }
        invoke("sendProgress", true); assertEquals(1, requireJournal().getJSONArray("completions").length())
        barrier.close()
    }

    @Test fun recoverySnapshotPinsIdentityDefaultsAndAllCumulativeFlags() {
        movie(); set("finalProgressSnapshot", true)
        val map = hashMapOf<String, Any?>("positionMs" to 1234L, "durationMs" to 5678L, "resumeId" to "resume",
            "url" to "https://example.test/a", "completionReached" to true, "localCompletionReached" to true,
            "localCompletionEligible" to true, "localCompletionTracking" to true)
        call("deliverProgress", arrayOf(HashMap::class.java), map)
        val saved = requireJournal().getJSONArray("completions").getJSONObject(0)
        assertEquals(field("sourcePersistenceSessionId"), saved.getInt("sessionId")); assertEquals(1L, saved.getLong("sequence"))
        assertEquals("phase5-owner", saved.getString("profileId")); assertEquals(3, saved.getInt("dataGeneration"))
        assertEquals("Film", saved.getString("title")); assertEquals("Show", saved.getString("seriesTitle")); assertEquals("tt5", saved.getString("imdbId"))
        assertEquals(field("recoveryStartedAtMs"), saved.getLong("startedAtMs")); assertTrue(saved.getLong("updatedAtMs") > 0)
        assertEquals("single", saved.getString("contentType")); assertEquals(0, saved.getInt("itemIndex")); assertEquals(1.0, saved.getDouble("speed"), 0.0)
        assertEquals("contain", saved.getString("aspect")); assertEquals(80, saved.getInt("completionThreshold"))
        for (name in listOf("completed", "localCompleted")) assertFalse(saved.getBoolean(name))
        for (name in listOf("completionReached", "localCompletionReached", "localCompletionEligible", "localCompletionTracking")) assertTrue(name, saved.getBoolean(name))
    }

    @Test fun recoveryGuardsSkipWrongModeOwnerGenerationSessionAndInvalidNumbers() {
        set("finalProgressSnapshot", true)
        val map = hashMapOf<String, Any?>("positionMs" to 10L, "durationMs" to 100L)
        fun stage() = call("stageRecoveryCheckpoint", arrayOf(mapType, longType, boolType), map, 1L, true)
        set("isIptvMode", true); stage(); assertNull(journal()); set("isIptvMode", false)
        map["mode"] = "iptv"; stage(); assertNull(journal()); map.remove("mode")
        set("recoveryProfileId", null); stage(); assertNull(journal()); set("recoveryProfileId", "phase5-owner")
        set("recoveryDataGeneration", 0); stage(); assertNull(journal()); set("recoveryDataGeneration", 3)
        val session = field("sourcePersistenceSessionId"); set("sourcePersistenceSessionId", 0); stage(); assertNull(journal()); set("sourcePersistenceSessionId", session)
        map["positionMs"] = 0L; stage(); assertNull(journal()); map["positionMs"] = 10L
        map["durationMs"] = 0L; stage(); assertNull(journal()); map["durationMs"] = 100L
        stage(); assertNotNull(journal())
    }

    @Test fun delayedOutOfOrderTrueAcksRemoveOnlyTheirExactRecoverySequences() {
        val model = movie("series"); invoke("sendProgress", true); val first = requestIndex("torrentPlaybackProgress")
        model.items[0] = model.items[0].copy(episode = 5)
        probe.position = 10_000; invoke("sendProgress", false); val second = requestIndex("torrentPlaybackProgress"); drainWriter()
        assertEquals(0, field("progressAckCount"))
        messenger.success(true, second); idle(); drainWriter()
        assertEquals(1, requireJournal().getJSONArray("completions").length()); assertEquals(0, requireJournal().getJSONArray("latest").length())
        assertEquals(1, field("progressAckCount")); assertTrue(field("lastProgressAckAt") as Long > 0)
        messenger.success(true, first); idle(); drainWriter(); assertNull(journal()); assertEquals(2, field("progressAckCount"))
    }

    @Test fun falseErrorMissingAndThrowingDeliveryNeverAcknowledgeRecovery() {
        movie(); set("finalProgressSnapshot", true)
        invoke("sendProgress", false); messenger.success(false); idle(); drainWriter()
        invoke("sendProgress", false); messenger.error(); idle(); drainWriter()
        invoke("sendProgress", false); messenger.notImplemented(); idle(); drainWriter()
        messenger.throwOnSend = true; invoke("sendProgress", false); messenger.throwOnSend = false
        assertEquals(0, field("progressAckCount")); assertEquals(0L, field("lastProgressAckAt")); assertNotNull(journal())
        assertEquals(4, field("progressSentCount"))
    }

    @Test fun loggingSamplesAtSixtySecondsAndBridgeChangesAndForcesCompletedFinal() {
        movie(); invoke("sendProgress", false); val first = field("lastProgressLogAt")
        advance(59_999); invoke("sendProgress", false); assertEquals(first, field("lastProgressLogAt"))
        advance(1); invoke("sendProgress", false); val boundary = field("lastProgressLogAt"); assertNotEquals(first, boundary)
        advance(1); MainActivity.setAndroidTvPlayerChannel(null); invoke("sendProgress", false)
        assertEquals(false, field("lastProgressBridgeAvailable")); assertNotEquals(boundary, field("lastProgressLogAt"))
        MainActivity.setAndroidTvPlayerChannel(MethodChannel(messenger, "com.debrify.app/android_tv_player"))
        advance(1); invoke("sendProgress", false); val restored = field("lastProgressLogAt")
        advance(1); invoke("sendProgress", true); assertNotEquals(restored, field("lastProgressLogAt"))
        val completed = field("lastProgressLogAt"); advance(1); set("finalProgressSnapshot", true); invoke("sendProgress", false)
        assertNotEquals(completed, field("lastProgressLogAt"))
    }

    @Test fun sleepReportsBeforePausingAndFinishPersistsOnceBeforeHandoff() {
        movie(); val barrier = blockWriter()
        invoke("fireSleepTimer"); assertEquals(false, progress()["completed"]); assertEquals(listOf("pause"), probe.events)
        assertNull("sleep remains an ordinary asynchronous checkpoint", journal())
        probe.position = 31_000
        messenger.onSend = { request -> if (request.call.method == "torrentPlaybackProgress")
            assertEquals(31_000, requireJournal().getJSONArray("latest").getJSONObject(0).getInt("positionMs")) }
        activity.finish(); activity.finish()
        assertEquals(2, requests("torrentPlaybackProgress").size); assertEquals(false, field("finalProgressSnapshot"))
        assertEquals(true, field("finishProgressAttempted")); barrier.close()
    }

    @Test fun stopAndDestroySynchronouslyPersistBeforePauseAndReleaseThenAcceptLateAck() {
        createLifecycle(); movie(); val barrier = blockWriter()
        probe.onEvent = { event -> if (event in listOf("pause", "release"))
            assertEquals("snapshot exists before $event", 25_000, requireJournal().getJSONArray("latest").getJSONObject(0).getInt("positionMs")) }
        lifecycle.pause().stop(); assertEquals(false, field("finalProgressSnapshot")); assertEquals(listOf("pause"), probe.events)
        lifecycle.destroy(); assertTrue(activity.isDestroyed); assertEquals(false, field("finalProgressSnapshot")); assertNull(field("player"))
        assertEquals(listOf("pause", "release"), probe.events)
        val last = requestIndex("torrentPlaybackProgress"); barrier.close(); drainWriter()
        messenger.success(true, last); idle(); drainWriter()
        assertNull("activity teardown does not invalidate recovery ACK", journal()); assertEquals(1, field("progressAckCount"))
    }

    @Test fun playerReadFailureLeavesStopFlagSetButFinishAndDestroyFinallyClearIt() {
        movie(); probe.failPosition = true
        fun failed(name: String) {
            var thrown: Throwable? = null
            try { invoke(name) } catch (error: Throwable) { thrown = error }
            while (thrown is java.lang.reflect.InvocationTargetException) thrown = thrown.targetException
            assertTrue("player-read failure outside deliverProgress in $name: $thrown", thrown is IllegalStateException)
            assertEquals("phase5 player read failed", thrown!!.message)
        }
        failed("onStop"); assertEquals("onStop has no finally", true, field("finalProgressSnapshot"))
        set("finalProgressSnapshot", false); failed("finish"); assertEquals(false, field("finalProgressSnapshot"))
        assertEquals(false, field("finishProgressAttempted")); failed("onDestroy"); assertEquals(false, field("finalProgressSnapshot"))
        assertTrue(requests("torrentPlaybackProgress").isEmpty()); assertTrue(probe.events.isEmpty())
    }

    @Test fun maintenanceAndActivityMapsKeepReadyPredicatesAndActiveOnlyFollowup() {
        invoke("sendPlaybackActivityState", true)
        assertEquals(listOf("torrentPlaybackActivityState", "torrentPlaybackMaintenanceState"), messenger.requests.map { it.call.method })
        assertEquals(mapOf("sourcePersistenceSessionId" to field("sourcePersistenceSessionId"), "active" to true), messenger.requests[0].call.arguments)
        assertEquals(mapOf("sourcePersistenceSessionId" to field("sourcePersistenceSessionId"), "ready" to true), messenger.requests[1].call.arguments)
        probe.state = Player.STATE_BUFFERING; invoke("sendPlaybackMaintenanceState"); assertEquals(false, (messenger.requests.last().call.arguments as Map<*, *>)["ready"])
        probe.state = Player.STATE_READY; probe.playing = false; invoke("sendPlaybackMaintenanceState"); assertEquals(false, (messenger.requests.last().call.arguments as Map<*, *>)["ready"])
        val count = messenger.requests.size; invoke("sendPlaybackActivityState", false); assertEquals(count + 1, messenger.requests.size)
        messenger.throwOnSend = true; invoke("sendPlaybackActivityState", true); messenger.throwOnSend = false
    }
}
