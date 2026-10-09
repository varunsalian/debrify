package com.debrify.app.tv

import com.debrify.app.subtitle.AddonSubtitleStatus
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleFetchRoutingCharacterizationTest : TvPhase14OriginalTest() {
    private fun dirty() {
        flat().add(subtitle()); set("currentStremioSubtitleIndex", 0)
        set("isLoadingStremioSubtitles", true); set("subtitleAddonDiscoveryReady", false)
    }
    private fun cleared() {
        assertTrue(flat().isEmpty()); assertEquals(-1, field("currentStremioSubtitleIndex"))
        assertFalse(loading()); assertTrue(discovery()); assertTrue(endpoint.requests.isEmpty())
    }
    @Test fun noPayloadLeavesSubtitleStateAndDoesNotRequestMetadata() {
        dirty(); set("payload", null); fetch(p2Item())
        assertEquals(listOf(subtitle()), flat()); assertTrue(loading()); assertFalse(discovery())
        assertTrue(endpoint.requests.isEmpty())
    }
    @Test fun customSeriesWithoutManualIdentityReturnsBeforeInjectedSeeding() {
        dirty(); model().imdbId = "custom-series:local"; set("injectedSubtitles", listOf(subtitle("https://phase14.invalid/injected.vtt")))
        fetch(); assertEquals(listOf(subtitle()), flat()); assertTrue(slots().isEmpty()); assertFalse(discovery())
        assertTrue(endpoint.requests.isEmpty())
    }
    @Test fun customSeriesWithManualIdentityUsesTheManualFetch() {
        dirty(); model().imdbId = "custom-series:local"; set("manualSubtitleImdbId", "tt-manual")
        fetch(); assertTrue(discovery()); assertFalse(loading())
    }
    @Test fun injectedGroupUsesFirstSourceFiltersFormatsAndSuppressesAutoSelection() {
        slots().add(com.debrify.app.subtitle.AddonSubtitleResult(addon("old"), AddonSubtitleStatus.OK, listOf(subtitle("https://phase14.invalid/stale.srt"))))
        menu().show("subs", "search")
        val first = subtitle().copy(source = "Launch captions")
        set("injectedSubtitles", listOf(first, subtitle("https://phase14.invalid/unsupported.ttml"), subtitle("https://phase14.invalid/next.vtt")))
        dirty(); fetch()
        assertEquals(true, field("suppressSubtitleAutoSelect")); assertFalse(loading()); assertTrue(discovery())
        assertEquals(1, slots().size); assertEquals("injected", slots().single().addon.id); assertEquals("Launch captions", slots().single().addon.name)
        assertEquals(listOf("subtitles"), slots().single().addon.resources)
        assertTrue((TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model).col2.any { it.title == "Launch captions" && it.value == "2" })
        assertTrue(slots().single().addon.types.isEmpty()); assertEquals("", slots().single().addon.baseUrl)
        assertEquals(AddonSubtitleStatus.OK, slots().single().status)
        assertEquals(listOf(first, subtitle("https://phase14.invalid/next.vtt")), flat())
        assertTrue(endpoint.requests.isEmpty())
    }
    @Test fun injectedGroupPrecedesMergedAudioGuard() {
        set("injectedSubtitles", listOf(subtitle())); fetch(item().copy(audioUrl = "https://phase14.invalid/audio"))
        assertEquals(listOf(subtitle()), flat()); assertEquals("injected", slots().single().addon.id)
    }
    @Test fun manualIdentityBypassesInjectedSeeding() {
        set("injectedSubtitles", listOf(subtitle())); set("manualSubtitleImdbId", "tt-manual")
        fetch(); assertTrue(slots().isEmpty()); assertTrue(flat().isEmpty())
        assertEquals(false, field("suppressSubtitleAutoSelect")); assertTrue(discovery())
    }
    @Test fun mergedAudioClearsSelectionAndLoadingEvenWithManualIdentity() {
        set("manualSubtitleImdbId", "tt-manual")
        for (audio in listOf("audio", " ")) { dirty(); fetch(item().copy(audioUrl = audio)); cleared() }
    }
    @Test fun blankAudioUrlDoesNotSkipAddonFetch() {
        installAddons(addon()); dirty(); val response = response(); fetch(item().copy(audioUrl = "")); entered(response)
        val job = jobs().single(); assertTrue(discovery()); complete(response, job)
        assertEquals(listOf(subtitle()), flat()); assertFalse(loading())
    }
    @Test fun seriesRoutingIsCaseInsensitiveAndEmptyImdbClears() {
        dirty(); model().contentType = "SeRiEs"; model().imdbId = ""; fetch(); cleared()
    }
    @Test fun seriesSharedImdbCarriesSeasonAndEpisodeToTheRealWorker() {
        installAddons(addon()); model().contentType = "SERIES"; model().imdbId = "tt-shared"
        val response = response(); fetch(item().copy(season = 2, episode = 6)); entered(response)
        val job = jobs().single()
        assertEquals("https://phase14.invalid/a/subtitles/series/tt-shared:2:6.json", response.arguments[1])
        complete(response, job); assertFalse(loading())
    }
    @Test fun manualSeriesOverridesSeasonAndEpisode() {
        installAddons(addon()); set("manualSubtitleImdbId", "tt-manual"); set("manualSubtitleType", "series")
        set("manualSubtitleSeason", 7); set("manualSubtitleEpisode", 9)
        val response = response(); fetch(item().copy(season = 2, episode = 6)); entered(response)
        val job = jobs().single()
        assertEquals("https://phase14.invalid/a/subtitles/series/tt-manual:7:9.json", response.arguments[1]); complete(response, job)
    }
    @Test fun manualSeriesFallsBackToItemNumbersPerInvocation() {
        installAddons(addon()); set("manualSubtitleImdbId", "tt-manual"); set("manualSubtitleType", "series")
        val response = response(); fetch(item().copy(season = 4, episode = 8)); entered(response)
        val job = jobs().single()
        assertEquals("https://phase14.invalid/a/subtitles/series/tt-manual:4:8.json", response.arguments[1]); complete(response, job)
    }
    @Test fun manualNonSeriesIdentityUsesMovieWithoutEpisodeNumbers() {
        installAddons(addon()); set("manualSubtitleImdbId", "tt-manual"); set("manualSubtitleType", "SERIES")
        set("manualSubtitleSeason", 7); set("manualSubtitleEpisode", 9)
        val response = response(); fetch(item().copy(season = 2, episode = 6)); entered(response)
        val job = jobs().single()
        assertEquals("https://phase14.invalid/a/subtitles/movie/tt-manual.json", response.arguments[1]); complete(response, job)
    }
    @Test fun cachedNullImdbClearsWithoutRequestingAgain() {
        dirty(); model().perItemImdbIds[item().index] = null; fetch(); cleared()
    }
    @Test fun cachedEmptyImdbClearsWithoutRequestingAgain() {
        dirty(); model().perItemImdbIds[item().index] = ""; fetch(); cleared()
    }
    @Test fun cachedPerItemImdbWinsOverSingleItemFallback() {
        installAddons(addon()); model().perItemImdbIds[item().index] = "tt-cached"
        val response = response(); fetch(); entered(response)
        val job = jobs().single()
        assertEquals("https://phase14.invalid/a/subtitles/movie/tt-cached.json", response.arguments[1]); complete(response, job)
        assertTrue(endpoint.requests.isEmpty())
    }
    @Test fun singleItemPayloadImdbDoesNotSendMetadataLookup() {
        installAddons(addon()); val response = response(); fetch(); entered(response)
        val job = jobs().single()
        assertEquals("https://phase14.invalid/a/subtitles/movie/tt140.json", response.arguments[1]); complete(response, job)
        assertTrue(endpoint.requests.isEmpty())
    }
    @Test fun multiItemPayloadImdbStillRequestsPerItemMetadata() {
        model().items.add(item().copy(index = 1)); fetch()
        assertEquals(mapOf("index" to 0, "filename" to "Film.mkv"), endpoint.request("requestMovieMetadata").call.arguments)
        assertTrue(loading())
    }
    @Test fun metadataInlineNullReplyCachesTheMissAndClearsLoading() {
        model().imdbId = null; dirty(); fetch(); endpoint.success("requestMovieMetadata", null)
        assertTrue(model().perItemImdbIds.containsKey(0)); assertNull(model().perItemImdbIds[0])
        assertTrue(flat().isEmpty()); assertEquals(-1, field("currentStremioSubtitleIndex"))
        assertFalse(loading()); assertTrue(discovery())
    }
    @Test fun metadataQueuedReplyWaitsThenCachesAndFetches() {
        model().imdbId = null; fetch(); endpoint.success("requestMovieMetadata", mapOf("imdbId" to "tt-reply"), TvPhase14EndpointMessenger.Delivery.QUEUED_MAIN)
        assertTrue(loading()); assertFalse(model().perItemImdbIds.containsKey(0)); idle()
        assertEquals("tt-reply", model().perItemImdbIds[0]); assertFalse(loading()); assertTrue(discovery())
    }
    @Test fun metadataErrorAndNotImplementedCacheNull() {
        model().imdbId = null; fetch(); endpoint.error("requestMovieMetadata", "Server declined")
        assertTrue(model().perItemImdbIds.containsKey(0)); assertFalse(loading())
        model().perItemImdbIds.clear(); fetch(); endpoint.unavailable("requestMovieMetadata")
        assertTrue(model().perItemImdbIds.containsKey(0)); assertNull(model().perItemImdbIds[0]); assertFalse(loading())
    }
    @Test fun supersededMetadataReplyDoesNotWriteCapturedCacheOrSubtitleState() {
        model().imdbId = null; fetch(); val captured = model(); set("addonSubtitleFetchToken", token() + 1)
        endpoint.success("requestMovieMetadata", mapOf("imdbId" to "tt-stale"))
        assertFalse(captured.perItemImdbIds.containsKey(0)); assertTrue(loading())
    }
    @Test fun knownImdbWithNullBorrowedServiceClearsSlotsAndFinishesDiscovery() {
        slots().add(com.debrify.app.subtitle.AddonSubtitleResult(addon(), AddonSubtitleStatus.LOADING))
        dirty(); set("stremioSubtitleService", null); known()
        assertTrue(slots().isEmpty()); assertTrue(flat().isEmpty()); assertFalse(loading()); assertTrue(discovery())
    }
    @Test fun resolvedMetadataStartsAddonWorkerWithCapturedItemAndCachesItsImdb() {
        installAddons(addon()); model().imdbId = null; val response = response()
        fetch(); endpoint.success("requestMovieMetadata", mapOf("imdbId" to "tt-resolved")); entered(response)
        val job = jobs().single(); assertEquals("tt-resolved", model().perItemImdbIds[0])
        assertEquals("https://phase14.invalid/a/subtitles/movie/tt-resolved.json", response.arguments[1])
        complete(response, job); assertEquals(listOf(subtitle()), flat()); assertFalse(loading())
    }
}
