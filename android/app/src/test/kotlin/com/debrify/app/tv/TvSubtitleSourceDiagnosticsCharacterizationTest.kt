package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleSourceDiagnosticsCharacterizationTest : TvPhase14OriginalTest() {
    private fun messages() = ShadowLog.getLogsForTag("StremioSubs").map { it.msg }
    @Test fun manualFetchDiagnosticPinsIdentityTypeAndEffectiveEpisodeNumbers() {
        set("manualSubtitleImdbId", "tt-manual"); set("manualSubtitleType", "series"); set("manualSubtitleSeason", 2); set("manualSubtitleEpisode", 7)
        fetch(); assertTrue(messages().contains("Using manual subtitle identity tt-manual type=series S2E7"))
    }
    @Test fun cachedHitMissAndSingleFallbackDiagnosticsAreExact() {
        model().perItemImdbIds[0] = "tt-cached"; fetch(); assertTrue(messages().contains("Using cached IMDB ID tt-cached for item 0"))
        model().perItemImdbIds[0] = null; fetch(); assertTrue(messages().contains("No cached IMDB ID for item 0 (previously not found)"))
        model().perItemImdbIds.clear(); fetch(); assertTrue(messages().contains("Single item, using payload IMDB ID: tt140"))
    }
    @Test fun metadataRequestReplyAndStaleGenerationDiagnosticsAreExact() {
        model().imdbId = null; fetch(); assertTrue(messages().contains("Requesting IMDB ID from Flutter for item 0"))
        endpoint.success("requestMovieMetadata", null); assertTrue(messages().contains("Received IMDB ID from Flutter: null for item 0"))
        model().perItemImdbIds.clear(); fetch(); set("addonSubtitleFetchToken", token() + 1); endpoint.success("requestMovieMetadata", mapOf("imdbId" to "tt-late"))
        assertTrue(messages().contains("Content changed during metadata lookup, discarding IMDB result for item 0"))
    }
    @Test fun catalogServerAndUnavailableAndSendExceptionDiagnosticsAreExact() {
        showSearch(); searchButton().performClick(); endpoint.error("searchSubtitleCatalogs", "Server declined")
        assertTrue(messages().contains("Subtitle catalog search failed: server - Server declined"))
        searchButton().performClick(); endpoint.unavailable("searchSubtitleCatalogs"); assertTrue(messages().contains("Subtitle catalog search is not implemented"))
        endpoint.throwingEndpoints.add("searchSubtitleCatalogs"); searchButton().performClick(); assertTrue(messages().contains("Subtitle catalog search exception"))
    }
    @Test fun exhaustedAddonFailureDiagnosticRetainsServerMessage() {
        installAddons(addon()); repeat(3) { response(failure = IllegalStateException("server exploded"), released = true) }
        known(); idle(); settle(jobs().single()); assertTrue(messages().contains("Addon a subtitle fetch failed: server exploded"))
    }
}
