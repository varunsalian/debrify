package com.debrify.app.tv

import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import com.debrify.app.util.OffsetRenderersFactory
import com.debrify.app.util.SubtitleSettings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleManualIdentityCharacterizationTest : TvPhase14OriginalTest() {
    @Test fun resetClearsEveryOwnedSelectionIdentitySlotAndFailureState() {
        @Suppress("UNCHECKED_CAST") val oldTracks = field("subtitleTracks") as MutableList<Pair<String, androidx.media3.common.TrackSelectionOverride?>>
        oldTracks.clear(); oldTracks.add("old embedded track" to null)
        val readiness = field("subtitleTrackReadiness") as SubtitleTrackReadiness
        readiness.onReady(); assertTrue(readiness.canSelect(true))
        flat().add(subtitle()); slots().add(com.debrify.app.subtitle.AddonSubtitleResult(addon(), com.debrify.app.subtitle.AddonSubtitleStatus.OK, listOf(subtitle())))
        tokens()["a"] = 4
        @Suppress("UNCHECKED_CAST") val failed = field("failedSubtitleUrls") as MutableSet<String>
        failed.add(subtitle().url)
        set("subtitleSearchResults", listOf(result())); set("subtitleSearchStatus", "old"); set("pendingSeriesResult", result("series"))
        set("currentStremioSubtitleIndex", 0); set("isLoadingStremioSubtitles", true); set("subtitleAddonDiscoveryReady", true)
        set("suppressSubtitleAutoSelect", true); set("manualSubtitleImdbId", "tt-old"); set("manualSubtitleType", "series")
        set("manualSubtitleSeason", 2); set("manualSubtitleEpisode", 3); set("manualSubtitleDisplayLabel", "old")
        set("externalSubtitleActive", true); val before = token(); reset()
        assertTrue(flat().isEmpty()); assertTrue(slots().isEmpty()); assertTrue(tokens().isEmpty()); assertTrue(failed.isEmpty()); assertTrue(oldTracks.isEmpty())
        assertEquals(emptyList<SubtitleCatalogResult>(), field("subtitleSearchResults")); assertEquals("", field("subtitleSearchStatus")); assertNull(field("pendingSeriesResult"))
        assertEquals(-1, field("currentStremioSubtitleIndex")); assertFalse(loading()); assertFalse(discovery())
        assertEquals(false, field("userManuallySelectedSubtitle")); assertEquals(false, field("suppressSubtitleAutoSelect")); assertEquals(false, field("externalSubtitleActive"))
        for (name in listOf("manualSubtitleImdbId", "manualSubtitleType", "manualSubtitleSeason", "manualSubtitleEpisode", "manualSubtitleDisplayLabel")) assertNull(name, field(name))
        assertEquals(before + 1, token()); assertFalse((field("subtitleTrackReadiness") as SubtitleTrackReadiness).canSelect(true))
    }
    @Test fun resetKeepsInjectedCaptionsAndPendingNumberChoicesAndBorrowedObjects() {
        val scope = scope(); val service = field("stremioSubtitleService"); val readiness = field("subtitleTrackReadiness")
        val injected = mutableListOf(subtitle()); val retained = injected.toList(); set("injectedSubtitles", injected); set("pendingSeason", 8); set("pendingEpisode", 13)
        reset(); assertSame(injected, field("injectedSubtitles")); assertEquals(retained, injected); assertEquals(8, field("pendingSeason")); assertEquals(13, field("pendingEpisode"))
        assertSame(scope, scope()); assertSame(service, field("stremioSubtitleService")); assertSame(readiness, field("subtitleTrackReadiness"))
        assertTrue(scope.coroutineContext[kotlinx.coroutines.Job]!!.isActive)
    }
    @Test fun resetPushesZeroOffsetIntoEmbeddedRendererAndCurrentIdentitySettings() {
        val factory = field("offsetRenderersFactory") as OffsetRenderersFactory
        factory.setOffsetUs(750_000); SubtitleSettings.setSyncOffsetMs(activity, 750)
        reset(); assertEquals(0L, factory.currentOffsetUs); assertEquals(0L, SubtitleSettings.getSyncOffsetMs(activity))
    }
    @Test fun resetDisablesTextWhenPreferenceIsOff() {
        pref("player_default_subtitle_language", "off"); reset(); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        pref("player_default_subtitle_language", "en"); reset(); assertFalse(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun resetDisablesTextForForeignAudioOnly() {
        flag("subtitle_only_foreign_audio", true); reset(); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        flag("subtitle_only_foreign_audio", false); reset(); assertFalse(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun resetDisablesTextForForcedOnly() {
        flag("subtitle_forced_only", true); reset(); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        flag("subtitle_forced_only", false); reset(); assertFalse(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun resetWithoutSelectorStillClearsIdentityAndBumpsToken() {
        set("trackSelector", null); set("manualSubtitleImdbId", "tt-old"); val before = token(); reset()
        assertNull(field("manualSubtitleImdbId")); assertEquals(before + 1, token()); assertFalse(discovery())
    }
    @Test fun currentSearchItemPrefersPayloadEvenInIptvMode() {
        val original = item(); iptv(channel()); assertSame(original, searchItem())
    }
    @Test fun currentSearchItemSynthesizesAllIptvMetadataFieldsAndTimestamp() {
        set("payload", null); val entry = channel().copy(index = 77, name = "Channel name", group = "Group")
        iptv(entry); val before = System.currentTimeMillis(); val actual = searchItem(); assertNotNull("Search item is synthesized", actual); val item = actual!!; val after = System.currentTimeMillis()
        assertEquals("iptv:77", item.id); assertEquals("Channel name", item.title); assertEquals(entry.url, item.url)
        assertEquals(entry.logoUrl, item.artwork); assertEquals("Group", item.description); assertEquals("iptv", item.provider)
        assertEquals(0, item.index); assertEquals(0L, item.resumePositionMs); assertEquals(0L, item.durationMs)
        assertNull(item.season); assertNull(item.episode); assertNull(item.hdVideoUrl); assertNull(item.audioUrl)
        assertNull(item.resumeId); assertNull(item.sizeBytes); assertNull(item.rating)
        assertTrue("synthesized timestamp uses evaluation-time wall clock", item.updatedAt in before..after)
    }
    @Test fun currentSearchItemFallsBackToTrimmedPlayerTitleOutsidePayloadBounds() {
        set("currentIndex", 8); currentMedia = MediaItem.Builder().setUri("https://phase14.invalid/file.mkv")
            .setMediaMetadata(MediaMetadata.Builder().setTitle("  Player title  ").build()).build()
        val before = System.currentTimeMillis(); val actual = searchItem(); assertNotNull("Search item is synthesized", actual); val item = actual!!; val after = System.currentTimeMillis()
        assertEquals("Player title", item.title); assertEquals("current:${"Player title".hashCode()}", item.id)
        assertEquals(8, item.index); assertEquals("https://phase14.invalid/file.mkv", item.url); assertNull(item.provider)
        assertNull(item.artwork); assertNull(item.description); assertNull(item.season); assertNull(item.episode)
        assertEquals(0L, item.resumePositionMs); assertEquals(0L, item.durationMs); assertTrue(item.updatedAt in before..after)
    }
    @Test fun blankPlayerTitleFallsBackToUrlFilenameWithoutQuery() {
        set("payload", null); currentMedia = MediaItem.Builder().setUri("https://phase14.invalid/path/Release.mkv?token=x")
            .setMediaMetadata(MediaMetadata.Builder().setTitle("  ").build()).build()
        assertEquals("Release.mkv", searchItem()!!.title)
    }
    @Test fun missingPayloadIptvIndexAndPlayerItemYieldNoSearchItem() {
        set("payload", null); iptv(channel()); set("currentIptvIndex", 5); assertNull(searchItem())
        set("isIptvMode", false); currentMedia = MediaItem.Builder().setUri("https://phase14.invalid/").build(); assertNull(searchItem())
        set("player", null); assertNull(searchItem())
    }
    @Test fun manualIdentityWithoutCurrentItemShowsExactToastAndLeavesToken() {
        set("payload", null); val before = token(); apply(); assertEquals(before, token())
        assertEquals("No current video to search", ShadowToast.getTextOfLatestToast())
    }
    @Test fun invalidSeriesNumbersOpenPromptBeforeChangingManualState() {
        val before = token(); apply(result("series"), 0, 2)
        assertNotNull("Invalid series numbers open the prompt", org.robolectric.shadows.ShadowDialog.getLatestDialog()); assertTrue(dialog().isShowing); assertEquals(before, token()); assertNull(field("manualSubtitleImdbId"))
    }
    @Test fun movieIdentityClearsSeriesNumbersAndRenderingAndDisablesText() {
        set("manualSubtitleSeason", 4); set("manualSubtitleEpisode", 9)
        call("showSubtitleSettingsPanel", emptyArray())
        val flatClearIndices = mutableListOf<Int>()
        val observedFlat = object : ArrayList<com.debrify.app.subtitle.StremioSubtitle>() {
            override fun clear() { flatClearIndices.add(field("currentStremioSubtitleIndex") as Int); super.clear() }
        }
        observedFlat.add(subtitle()); set("stremioSubtitles", observedFlat); set("currentStremioSubtitleIndex", 0)
        val renderedTracks = mutableListOf<List<String>>()
        val observedTracks = object : ArrayList<Pair<String, androidx.media3.common.TrackSelectionOverride?>>() {
            override fun clear() { renderedTracks.add(map { it.first }); super.clear() }
        }
        observedTracks.add("old panel" to null); set("subtitleTracks", observedTracks)
        set("externalSubtitleActive", true); val before = token(); apply(result(), 4, 9)
        assertEquals("Clear old captions before resetting selection, then rebuild the new identity", listOf(0, -1), flatClearIndices)
        assertEquals("Visible panel rebuilds once before and once after discovery", 2, renderedTracks.size)
        assertEquals("Visible panel renders loading before discovery replaces that snapshot", listOf("Off", "⏳ Loading external subtitles..."), renderedTracks[1])
        assertEquals(before + 1, token()); assertEquals("tt141", field("manualSubtitleImdbId")); assertEquals("movie", field("manualSubtitleType"))
        assertNull(field("manualSubtitleSeason")); assertNull(field("manualSubtitleEpisode")); assertEquals("Found film (2024)", field("manualSubtitleDisplayLabel"))
        assertEquals(false, field("externalSubtitleActive")); assertEquals(false, field("userManuallySelectedSubtitle")); assertTrue(flat().isEmpty())
        assertEquals(-1, field("currentStremioSubtitleIndex")); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        assertEquals("Searching subtitles for Found film", ShadowToast.getTextOfLatestToast()); assertFalse(loading()); assertTrue(discovery())
    }
    @Test fun seriesManualIdentityCarriesExactImdbAndNumbersToWorkerAndDisplayLabel() {
        installAddons(addon()); val response = response(); apply(result("series"), 2, 12); entered(response)
        val job = jobs().single(); assertEquals("series", field("manualSubtitleType")); assertEquals(2, field("manualSubtitleSeason")); assertEquals(12, field("manualSubtitleEpisode"))
        assertEquals("Found film (2024) S2E12", field("manualSubtitleDisplayLabel")); assertEquals("https://phase14.invalid/a/subtitles/series/tt141:2:12.json", response.arguments[1])
        complete(response, job)
    }
    @Test fun nonSeriesCatalogTypeBecomesMovie() {
        apply(result("SERIES"), 2, 12); assertEquals("movie", field("manualSubtitleType")); assertNull(field("manualSubtitleSeason")); assertNull(field("manualSubtitleEpisode"))
    }
    @Test fun identityLabelTrimsManualOverrideAndUsesSubtitlePrefix() {
        set("manualSubtitleDisplayLabel", "  Manual title  "); assertEquals("Subtitles for Manual title", identityLabel())
    }
    @Test fun blankManualLabelUsesDetectedCleanedPayloadTitle() {
        set("manualSubtitleDisplayLabel", "  "); model().items[0] = item().copy(title = "Show.S02E04.1080p.mkv")
        assertEquals("Detected: Show", identityLabel())
    }
    @Test fun identityLabelWithoutAnyItemIsExactUnavailableText() {
        set("payload", null); assertEquals("Detected title unavailable", identityLabel())
    }
    @Test fun manualIdentityKeepsHiddenPanelTrackSnapshotUntouched() {
        call("hideSubtitleSettingsPanel", emptyArray())
        @Suppress("UNCHECKED_CAST") val tracks = field("subtitleTracks") as MutableList<Pair<String, androidx.media3.common.TrackSelectionOverride?>>
        tracks.clear(); apply(); assertEquals("tt141", field("manualSubtitleImdbId")); assertTrue(tracks.isEmpty())
    }
}
