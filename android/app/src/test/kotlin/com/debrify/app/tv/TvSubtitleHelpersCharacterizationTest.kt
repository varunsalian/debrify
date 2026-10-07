package com.debrify.app.tv

import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import com.google.common.collect.ImmutableList
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@androidx.annotation.OptIn(UnstableApi::class)
class TvSubtitleHelpersCharacterizationTest : TvPhase2OriginalTest() {
    @Test fun overrideLanguageUsesFirstIndexAndReturnsNullForMissingOrInvalidSelection() {
        fun language(value: TrackSelectionOverride?) = call("languageOfOverride", arrayOf(TrackSelectionOverride::class.java), value)
        val group = TrackGroup(Format.Builder().setLanguage("en").build(), Format.Builder().setLanguage("fr").build())
        assertNull(language(null))
        assertNull(language(TrackSelectionOverride(group, emptyList<Int>())))
        val selection = TrackSelectionOverride(group, listOf(1, 0)); assertEquals("fr", language(selection))
        assertNull(language(TrackSelectionOverride(TrackGroup(Format.Builder().build()), 0)))
        // Corrupt selection state models a stale/invalid override; the original catches lookup failures.
        TvPlayerOriginalAccess.set(selection, "trackIndices", ImmutableList.of(99))
        assertNull(language(selection))
    }

    @Test fun audioLabelsKeepLabelFallbackChannelAndBitrateBoundariesAndDefaultLocale() {
        fun label(format: Format) = call("buildAudioTrackLabel", arrayOf(Format::class.java), format)
        assertEquals("UND", label(Format.Builder().build()))
        assertEquals("EN", label(Format.Builder().setLanguage("en").setLabel("").build()))
        assertEquals("Main · 6ch · 128kbps", label(Format.Builder().setLanguage("en").setLabel("Main").setChannelCount(6).setAverageBitrate(128_999).build()))
        assertEquals("UND · 0ch · 0kbps", label(Format.Builder().setChannelCount(0).setAverageBitrate(999).build()))
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr"))
            assertEquals("İ", label(Format.Builder().setLanguage("i").build()))
        } finally { Locale.setDefault(previous) }
    }

    @Test fun subtitleLabelsKeepNamedLanguageAndUndOrEmptyFallback() {
        fun label(format: Format) = call("buildSubtitleTrackLabel", arrayOf(Format::class.java), format)
        assertEquals("UND", label(Format.Builder().build()))
        assertEquals("EN", label(Format.Builder().setLabel("").setLanguage("en").build()))
        assertEquals("English (en)", label(Format.Builder().setLabel("English").setLanguage("en").build()))
        assertEquals("Named (und)", label(Format.Builder().setLabel("Named").build()))
        val previous = Locale.getDefault()
        try { Locale.setDefault(Locale.forLanguageTag("tr")); assertEquals("İ", label(Format.Builder().setLanguage("i").build())) }
        finally { Locale.setDefault(previous) }
    }

    @Test fun searchSubtitleOptionUsesExactLabelEquality() {
        for ((label, expected) in listOf("Search Movie/Show Subtitles" to true, "Search Movie/Show Subtitles " to false, "search movie/show subtitles" to false, "" to false))
            assertEquals(expected, call("isSearchSubtitleOption", arrayOf(stringType), label))
    }

    @Test fun loadingSubtitleOptionUsesOnlyLeadingHourglass() {
        for ((label, expected) in listOf("⏳" to true, "⏳ Loading" to true, "x⏳" to false, "" to false))
            assertEquals(expected, call("isLoadingSubtitleOption", arrayOf(stringType), label))
    }

    @Test fun externalSubtitleOptionUsesOnlyLeadingDownloadPrefix() {
        for ((label, expected) in listOf("⬇" to true, "⬇ English" to true, "x⬇" to false, "" to false))
            assertEquals(expected, call("isExternalSubtitleOption", arrayOf(stringType), label))
    }

    @Test fun renderableSubtitleRejectsTtmlDfxpBeforeQueryButPreservesFragmentBehavior() {
        for ((url, expected) in listOf("https://h/a.TTML?token=x" to false, "a.dfxp" to false, "a.srt" to true,
            "a.ass?f=.ttml" to true, "a.ttml#frag" to true, "" to true))
            assertEquals(expected, call("isSideRenderableSubtitle", arrayOf(stringType), url))
    }

    @Test fun subtitleCatalogValidatesTypesAndPreservesOrderTrimAndFallbacks() {
        fun parse(value: Any?) = call("parseSubtitleCatalogResults", arrayOf(Any::class.java), value)
        assertEquals(emptyList<SubtitleCatalogResult>(), parse(null)); assertEquals(emptyList<SubtitleCatalogResult>(), parse("wrong"))
        assertEquals(emptyList<SubtitleCatalogResult>(), parse(emptyList<Any>()))
        val raw = listOf(null, 3, emptyMap<String, Any>(), mapOf("imdbId" to "TT1", "type" to "movie"),
            mapOf("imdbId" to "tt1", "type" to "tv"), mapOf("imdbId" to "tt1", "type" to 7),
            mapOf("imdbId" to "tt1", "type" to "MOVIE", "name" to " Film ", "year" to 2024, "source" to " Addon "),
            mapOf("imdbId" to "tt2", "type" to "SERIES", "name" to " ", "year" to "", "source" to " "),
            mapOf("imdbId" to "tt", "type" to "movie"))
        assertEquals(listOf(SubtitleCatalogResult("tt1", "movie", "Film", "2024", "Addon"),
            SubtitleCatalogResult("tt2", "series", "tt2", null, null), SubtitleCatalogResult("tt", "movie", "tt", null, null)), parse(raw))
    }

    @Test fun titleEpisodeParsingKeepsPatternPriorityWordBoundariesAndPositiveNumbers() {
        for (title in listOf("Film s02 e003", "Film 2x003", "Film Season 2 Episode 3", "season2Ep3", "Season 2 E 3"))
            assertEquals(title, SeasonEpisode(2, 3), call("parseSeasonEpisodeFromTitle", arrayOf(stringType), title))
        assertEquals(SeasonEpisode(1, 2), call("parseSeasonEpisodeFromTitle", arrayOf(stringType), "3x4 then S01E02"))
        for (title in listOf("", "S00E01", "S01E000", "S100E01", "S01E1000", "xS01E01", "S01E01x", "12x000"))
            assertNull(title, call("parseSeasonEpisodeFromTitle", arrayOf(stringType), title))
        assertEquals(SeasonEpisode(99, 999), call("parseSeasonEpisodeFromTitle", arrayOf(stringType), "S99E999"))
    }

    @Test fun subtitleEpisodePrefersBothPositiveMetadataOtherwiseParsesTitle() {
        fun resolve(item: PlaybackItem) = call("resolveSeasonEpisodeForSubtitle", arrayOf(PlaybackItem::class.java), item)
        assertEquals(SeasonEpisode(3, 4), resolve(p2Item("S01E02", season = 3, episode = 4)))
        for (item in listOf(p2Item("S01E02"), p2Item("S01E02", season = 3), p2Item("S01E02", episode = 4),
            p2Item("S01E02", season = 0, episode = 4), p2Item("S01E02", season = 3, episode = 0))) assertEquals(SeasonEpisode(1, 2), resolve(item))
        assertNull(resolve(p2Item("Film")))
    }

    @Test fun subtitleQueryRemovesPathExtensionEpisodeAndReleaseTagsOrKeepsOriginal() {
        for ((title, expected) in listOf("/folder/My.Show.S01E02.1080p.WEB-DL.x265.mkv?token=x" to "My Show",
            "Film_2x10_4K_HEVC_AAC.mkv" to "Film", "A...B__C.abcdef" to "A B C abcdef",
            "2160p.1080p.720p.480p.4k.uhd.hdr.webdl.webrip.bluray.brrip.hdtv.dvdrip.x264.x265.h264.h265.hevc.aac.dts.yify.mkv" to
                "2160p.1080p.720p.480p.4k.uhd.hdr.webdl.webrip.bluray.brrip.hdtv.dvdrip.x264.x265.h264.h265.hevc.aac.dts.yify.mkv",
            "" to "", "Film Season 1 Episode 2" to "Film Season 1 Episode 2"))
            assertEquals(expected, call("buildSubtitleSearchInitialQuery", arrayOf(PlaybackItem::class.java), p2Item(title)))
    }

    @Test fun manualSubtitleLabelAppendsEpisodeOnlyForSeriesWithBothNumbers() {
        val result = SubtitleCatalogResult("tt1", "series", "Show", "2024", null)
        fun label(type: String, season: Int?, episode: Int?) = call("buildManualSubtitleDisplayLabel",
            arrayOf(SubtitleCatalogResult::class.java, stringType, boxedIntType, boxedIntType), result, type, season, episode)
        assertEquals("Show (2024) S2E3", label("series", 2, 3)); assertEquals("Show (2024) S0E0", label("series", 0, 0))
        assertEquals("Show (2024)", label("movie", 2, 3)); assertEquals("Show (2024)", label("Series", 2, 3))
        assertEquals("Show (2024)", label("series", null, 3)); assertEquals("Show (2024)", label("series", 2, null))
    }
}
