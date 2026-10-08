package com.debrify.app.tv

import androidx.media3.common.Player
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
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvSourceSwitchApplyCharacterizationTest : TvPhase8OriginalTest() {
    @Test fun directRebuildPreservesPositionMimeHeadersAndOriginalVolatileField() {
        sources()[1] = source(1, headers = mapOf("Authorization" to "phase8-test", "User-Agent" to "fixture"))
        val before = field("mediaPreparationGeneration") as Int; direct(mime = "video/mp4")
        assertEquals(listOf("media:https://phase8.invalid/new.mp4", "prepare", "seek:25000", "play", "listen:add"), probe.events)
        assertEquals("video/mp4", probe.media.single().localConfiguration!!.mimeType)
        assertEquals(before + 1, field("mediaPreparationGeneration")); assertEquals(1, field("currentStremioSourceIndex"))
        assertEquals("https://phase8.invalid/new.mp4", model().items.single().url); assertEquals(sources()[1].httpHeaders, model().items.single().httpHeaders)
        assertEquals(setOf("https://phase8.invalid:443") to sources()[1].httpHeaders, field("activeVodHeaders"))
        val reflected = AndroidTvTorrentPlayerActivity::class.java.getDeclaredField("activeVodHeaders")
        assertTrue(java.lang.reflect.Modifier.isVolatile(reflected.modifiers))
        assertEquals("Source 1", (field("titleView") as android.widget.TextView).text.toString())
    }
    @Test fun directHeldBookmarkOutranksLivePositionAndRestartsHoldWindow() {
        set("resumeHoldTargetMs", 70_000L); set("resumeHoldArmedAtMs", android.os.SystemClock.elapsedRealtime())
        tick(100); val before = field("resumeHoldArmedAtMs") as Long
        direct(); assertTrue(probe.events.contains("seek:70000")); assertTrue((field("resumeHoldArmedAtMs") as Long) > before)
        probe.events.clear(); probe.position = 0; set("resumeHoldTargetMs", 0L); direct()
        assertFalse(probe.events.any { it.startsWith("seek:") })
    }
    @Test fun directQualitySwitchKeepsSeparateAudioAndUsesMergedSource() {
        model().items[0] = model().items[0].copy(audioUrl = "https://phase8.invalid/audio.mp4")
        direct(); assertEquals(listOf("merged", "prepare", "seek:25000", "play", "listen:add"), probe.events)
        assertTrue(probe.media.isEmpty())
    }
    @Test fun iptvDirectSwitchUsesLiveLadderInsteadOfVodSeekAndHeaderState() {
        set("isIptvMode", true); set("iptvStremioChannelKey", "stremio-tv://phase8/live")
        set("iptvStremioCandidates", listOf(IptvStremioCandidate("https://phase8.invalid/a.ts", "A"), IptvStremioCandidate("https://phase8.invalid/b.ts", "B")))
        val before = field("activeVodHeaders"); direct("https://phase8.invalid/b.ts")
        assertEquals(1, field("iptvStremioCandidateIndex")); assertNotNull(field("iptvStremioStallRunnable"))
        assertTrue(probe.events.contains("media:https://phase8.invalid/b.ts")); assertFalse(probe.events.any { it.startsWith("seek:") })
        assertEquals(before, field("activeVodHeaders"))
    }
    @Test fun pikPakSwitchIncrementsRetryIdentityResetsStateAndCarriesBookmark() {
        set("pikPakRetryId", 40); set("pikPakRetryCount", 3); set("isPikPakRetrying", true)
        direct("https://phase8.mypikpak.com/play.mp4")
        assertEquals(42, field("pikPakRetryId")); assertEquals(0, field("pikPakRetryCount"))
        assertEquals(false, field("isPikPakRetrying")); assertTrue(probe.events.contains("seek:25000"))
        assertEquals(android.view.View.GONE, (field("pikPakReactivationIndicator") as android.view.View).visibility)
        // Polling closure is cancelled by retry-id advancement before fixture teardown.
        invoke("cancelPikPakRetry")
    }
    @Test fun retainedPikPakReprepareReadsLiveRetryIdAtFireTime() {
        model().items[0] = model().items[0].copy(url = "https://phase8.mypikpak.com/play.mp4")
        cursor(false); probe.error = androidx.media3.exoplayer.ExoPlaybackException.createForSource(java.io.IOException("fixture"), 2000)
        call("schedulePikPakGateReprepare", arrayOf(boxedIntType), null)
        val pending = field("pikPakGateReprepare") as Runnable
        set("pikPakRetryId", (field("pikPakRetryId") as Int) + 1); pending.run()
        assertFalse(probe.events.contains("prepare")); assertNull(field("pikPakGateReprepare"))
        call("schedulePikPakGateReprepare", arrayOf(boxedIntType), null)
        (field("pikPakGateReprepare") as Runnable).run(); assertEquals(listOf("prepare", "play"), probe.events)
    }
    @Test fun singletonMovieKeepsIdentityBookmarkAndSuppressesRemotePercent() {
        model().items[0] = model().items[0].copy(artwork = "poster", description = "description", rating = 8.0)
        pack(listOf(raw("New filename")))
        val item = model().items.single(); assertEquals("Film", item.title); assertEquals("poster", item.artwork)
        assertEquals("description", item.description); assertEquals(8.0, item.rating!!, 0.0)
        assertEquals(25_000L, item.resumePositionMs); assertEquals(25_000L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent"))
        assertEquals(true, field("percentSeekApplied")); assertEquals(1, field("currentStremioSourceIndex"))
    }
    @Test fun seriesReorderedPackMatchesEpisodeCarriesFetchedMetadataAndRequestsRefresh() {
        seriesItem(); pack(listOf(raw("Other", 3, 1), raw("File", 2, 4)))
        assertEquals(1, field("currentIndex")); val item = model().items[1]
        assertEquals("Fetched title", item.title); assertEquals("old art", item.artwork); assertEquals("old description", item.description)
        assertEquals(25_000L, item.resumePositionMs); idle(); assertEquals(1, requests("requestEpisodeMetadata").size)
        assertEquals(25_000L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent"))
    }
    @Test fun explicitDifferentEpisodeStartsWithOwnResumeAndSuppressFlagReachesPlayItem() {
        seriesItem(); pack(listOf(raw("Same", 2, 4), raw("Target", 2, 5)), 2, 5, suppress = true)
        assertEquals(1, field("currentIndex")); assertEquals(123L, model().items[1].resumePositionMs)
        assertEquals(0L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent"))
    }
    @Test fun missingEpisodeSkipsSpecialsUsesLongToastAndKeepsIncomingTrackerResume() {
        seriesItem(); pack(listOf(raw("Special", 0, 1), raw("Episode", 3, 1)))
        assertEquals(1, field("currentIndex")); assertEquals(123L, field("pendingSeekMs")); assertEquals(50.0, field("pendingItemTraktPercent"))
        assertEquals("S2E4 not in this source — playing from the start", ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_LONG, ShadowToast.getLatestToast().duration)
    }
    @Test fun exactEpisodeOrManualSnapshotRejectsWrongPackWithoutReplacingMedia() {
        seriesItem(); val old = model().items.toList(); pack(listOf(raw("Wrong", 3, 1), raw("Wrong2", 3, 2)), exact = true)
        assertEquals(old, model().items); assertTrue(probe.media.isEmpty()); assertEquals("Source does not contain this episode", pill().text.toString())
        call("beginManualSourceCandidate", arrayOf(intType), 1)
        pack(listOf(raw("Wrong", 3, 1), raw("Wrong2", 3, 2)))
        assertEquals(old.map { it.url }, model().items.map { it.url }); assertNull(field("manualSourceSwitchSnapshot"))
    }
    @Test fun singletonUnscopedSeriesInheritsCatalogEpisodeAndMetaEntryIsNotPlayable() {
        seriesItem(); pack(listOf(mapOf("__meta__" to true, "contentType" to "series"), "junk", raw("Unscoped")))
        assertEquals(1, model().items.size); assertEquals(2, model().items[0].season); assertEquals(4, model().items[0].episode)
        assertEquals("series", model().contentType); assertEquals(25_000L, field("pendingSeekMs"))
    }
    @Test fun collectionTitleMatchAndIndexFallbackKeepDifferentResumeContracts() {
        model().contentType = "collection"; pack(listOf(raw("Other"), raw("Film")))
        assertEquals(1, field("currentIndex")); assertEquals(25_000L, field("pendingSeekMs"))
        pack(listOf(raw("Unmatched0"), raw("Unmatched1")))
        assertEquals(1, field("currentIndex")); assertEquals(123L, field("pendingSeekMs")); assertEquals(50.0, field("pendingItemTraktPercent"))
    }
    @Test fun emptyParsedPackLeavesPayloadAndPinsUnavailableMessage() {
        val old = model().items.toList(); pack(listOf("junk", mapOf("__meta__" to true)))
        assertEquals(old, model().items); assertTrue(probe.media.isEmpty()); assertEquals("Source unavailable", pill().text.toString())
    }
    @Test fun startupPackDoesNotBurnLaunchPercentOrRegisterOutcomeWatcher() {
        cursor(false); pack(listOf(raw()))
        assertEquals(false, field("percentSeekApplied")); assertNull(field("sourceSwitchReadyListener"))
        assertNotNull(probe.media.single()); assertEquals(25_000L, field("pendingSeekMs"))
    }
    @Test fun shufflePackClearsBagPassesAttemptAndRestoresOutgoingPreparation() {
        val old = model().items.toList(); val attempt = attempt()
        @Suppress("UNCHECKED_CAST") val bag = field("shuffleBag") as MutableList<Int>; bag.addAll(listOf(3, 7))
        pack(listOf(raw()), attempt = attempt)
        assertTrue(bag.isEmpty()); assertEquals(true, attemptField(attempt, "mediaStarted"))
        assertEquals(field("mediaPreparationGeneration"), attemptField(attempt, "navigation"))
        @Suppress("UNCHECKED_CAST") val restore = attemptField(attempt, "restorePreparation") as (() -> Unit)
        restore(); assertEquals(old, model().items); assertEquals(0, field("currentIndex")); assertEquals(0, field("currentStremioSourceIndex"))
    }
    @Test fun defaultArgumentBridgesKeepDirectAndPlaylistCallShapes() {
        defaultCall("switchToStremioSource", arrayOf(stringType, intType, stringType, boolType), 12,
            "https://phase8.invalid/default.mp4", 1, null, false)
        assertNull(probe.media.single().localConfiguration!!.mimeType)
        probe.events.clear(); probe.media.clear();
        defaultCall("switchToSourcePlaylist", arrayOf(intType, listType, boxedIntType, boxedIntType, boolType, boolType, attemptType),
            124, 1, listOf(raw()), null, null, false, false, null)
        assertEquals(25_000L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent"))
        assertEquals(1, probe.media.size)
    }

}
