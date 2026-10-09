package com.debrify.app.tv

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleSourceBoundaryCharacterizationTest : TvPhase14OriginalTest() {
    private fun arguments() = TvPhase14SubtitleFetchShadow.invocations.last()
    private fun retry() = call("retryAddonSubtitles", arrayOf(stringType), "a")
    private fun expect(type: String, imdb: String, season: Int?, episode: Int?) =
        assertEquals(TvPhase14SubtitleFetchShadow.FetchArguments(type, imdb, season, episode), arguments())
    private fun matchingEmbedded(language: String = "en"): Tracks.Group {
        set("userManuallySelectedSubtitle", false)
        (field("subtitleTrackReadiness") as SubtitleTrackReadiness).onReady()
        pref("player_default_subtitle_language", "en")
        val group = Tracks.Group(TrackGroup(Format.Builder().setSampleMimeType("text/vtt").setLanguage(language).build()),
            false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false))
        tracks = Tracks(listOf(group))
        return group
    }
    @Test fun movieFanoutDropsSeasonAndEpisodeEvenWhenItemCarriesBoth() {
        installAddons(addon()); val response = response(); known(type = "movie", item = item().copy(season = 2, episode = 6)); entered(response)
        expect("movie", "tt140", null, null); complete(response, jobs().single())
    }
    @Test fun movieRetryDropsItemAndRememberedSeriesNumbers() {
        model().items[0] = item().copy(season = 2, episode = 6)
        set("manualSubtitleType", "movie"); set("manualSubtitleSeason", 7); set("manualSubtitleEpisode", 9)
        slots().add(AddonSubtitleResult(addon(), AddonSubtitleStatus.FAILED))
        val response = response(); retry(); entered(response)
        expect("movie", "tt140", null, null); complete(response, jobs().single())
    }
    @Test fun movieManualIdentityDropsItemAndRequestedSeriesNumbers() {
        installAddons(addon()); model().items[0] = item().copy(season = 2, episode = 6)
        val response = response(); apply(result(), 7, 9); entered(response)
        expect("movie", "tt141", null, null); assertNull(field("manualSubtitleSeason")); assertNull(field("manualSubtitleEpisode"))
        complete(response, jobs().single())
    }
    @Test fun seriesRetryKeepsManualSeasonAndItemEpisodeFallback() {
        model().contentType = "SERIES"; model().items[0] = item().copy(season = 2, episode = 6)
        set("manualSubtitleSeason", 7); set("manualSubtitleEpisode", null)
        slots().add(AddonSubtitleResult(addon(), AddonSubtitleStatus.FAILED))
        val response = response(); retry(); entered(response)
        expect("series", "tt140", 7, 6); complete(response, jobs().single())
    }
    @Test fun absentSeriesNumbersStayNullAtTheServiceBoundary() {
        installAddons(addon()); val response = response(); known(type = "series", item = item().copy(season = null, episode = null)); entered(response)
        expect("series", "tt140", null, null); complete(response, jobs().single())
    }
    @Test fun emptyManualIdLeavesMatchingEmbeddedCandidateEligible() {
        val group = matchingEmbedded(); set("manualSubtitleImdbId", ""); autoSelect()
        assertEquals(listOf(0), ts().parameters.overrides[group.mediaTrackGroup]?.trackIndices)
    }
    @Test fun emptyManualIdStillHonorsCustomSeriesEarlyReturn() {
        model().imdbId = "custom-series:local"; set("manualSubtitleImdbId", "")
        set("injectedSubtitles", listOf(subtitle())); set("subtitleAddonDiscoveryReady", false)
        fetch(); assertFalse(discovery()); assertTrue(slots().isEmpty()); assertTrue(flat().isEmpty())
        assertTrue(endpoint.requests.isEmpty())
    }
    @Test fun emptyManualIdStillSeedsInjectedCaptions() {
        set("manualSubtitleImdbId", ""); set("injectedSubtitles", listOf(subtitle()))
        fetch(); assertEquals(listOf(subtitle()), flat()); assertEquals("injected", slots().single().addon.id)
        assertEquals(true, field("suppressSubtitleAutoSelect"))
    }
    @Test fun emptyManualIdUsesPayloadImdbForNormalFetch() {
        installAddons(addon()); set("manualSubtitleImdbId", "")
        val response = response(); fetch(); entered(response)
        expect("movie", "tt140", null, null); complete(response, jobs().single())
    }
    @Test fun retryKeepsAnExplicitEmptyManualIdInsteadOfPayloadFallback() {
        set("manualSubtitleImdbId", ""); slots().add(AddonSubtitleResult(addon(), AddonSubtitleStatus.FAILED))
        val response = response(); retry(); entered(response)
        expect("movie", "", null, null); assertEquals("https://phase14.invalid/a/subtitles/movie/.json", response.arguments[1])
        complete(response, jobs().single())
    }
    @Test fun emptyManualDisplayLabelFallsBackToDetectedTitle() {
        set("manualSubtitleDisplayLabel", ""); assertEquals("Detected: Film", identityLabel())
    }
    @Test fun absentLanguagePreferenceUsesEnglishAliasesAndRegionalTagsBeforeOtherTracks() {
        for (language in listOf("en", "eng", "English", "EN-us", "en_GB", "eng_sdh", "en-unknown")) {
            matchingEmbedded(); pref("player_default_subtitle_language", null)
            val group = Tracks.Group(TrackGroup(
                Format.Builder().setSampleMimeType("text/vtt").setLanguage("fr").build(),
                Format.Builder().setSampleMimeType("text/vtt").setLanguage(language).build()),
                false, intArrayOf(C.FORMAT_HANDLED, C.FORMAT_HANDLED), booleanArrayOf(false, false))
            tracks = Tracks(listOf(group)); autoSelect()
            assertEquals(language, listOf(1), ts().parameters.overrides[group.mediaTrackGroup]?.trackIndices)
        }
    }
    @Test fun emptyManualIdDoesNotProduceTheManualEmptyAddonToast() {
        installAddons(addon()); set("manualSubtitleImdbId", ""); org.robolectric.shadows.ShadowToast.reset()
        val response = response(value = emptyList()); known(); entered(response); complete(response, jobs().single())
        assertFalse(loading()); assertTrue(flat().isEmpty()); assertNull(org.robolectric.shadows.ShadowToast.getTextOfLatestToast())
    }
    @Test fun retryKeepsEmptyManualTypeAsMovieRatherThanPayloadSeries() {
        model().contentType = "series"; model().items[0] = item().copy(season = 2, episode = 6)
        set("manualSubtitleType", ""); slots().add(AddonSubtitleResult(addon(), AddonSubtitleStatus.FAILED))
        val response = response(); retry(); entered(response)
        expect("movie", "tt140", null, null); complete(response, jobs().single())
    }
}
