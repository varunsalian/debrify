package com.debrify.app.tv

import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvDockIdentityCharacterizationTest(override val skin: TvControlsSkin) : TvPhase16OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}") fun skins(): List<Array<Any>> =
            TvControlsSkin.entries.map { arrayOf<Any>(it) }
    }
    private fun series(item: PlaybackItem = p2Item("Fetched episode", season = 2, episode = 7)): PlaybackPayload =
        PlaybackPayload("release.name.mkv", null, "SeRiEs", mutableListOf(item), 0, null).also { set("payload", it); set("currentIndex", 0) }
    private fun title(item: PlaybackItem) = runOriginal("updateTitle", item)
    private fun visible(name: String) = assertEquals(View.VISIBLE, v(name).visibility)
    private fun gone(name: String) = assertEquals(View.GONE, v(name).visibility)
    @Test fun seriesTitlePinsPaddedBadgeFetchedEpisodeRatingAndPerSkinIdentity() {
        val item = p2Item("Fetched episode", season = 2, episode = 7).copy(rating = 8.65)
        series(item); set("ottShowName", "Show"); title(item)
        assertEquals("Fetched episode", tv("titleView").text.toString()); assertEquals("S02 E07", tv("ottEpisodeBadge").text.toString())
        visible("ottEpisodeBadge"); assertEquals("Fetched episode", tv("ottEpisodeTitle").text.toString())
        visible("ottRatingContainer"); assertEquals("8.7", tv("ottRating").text.toString()); gone("channelBadge")
        if (skin == TvControlsSkin.CLASSIC) return
        assertEquals(when (skin) { TvControlsSkin.BROADCAST -> "Show"; TvControlsSkin.OTT -> "Show — Fetched episode"; else -> "Fetched episode" }, tv("ottIdentityTitle").text.toString())
        if (skin != TvControlsSkin.TICKET && field("ottIdentitySubtitle") != null) visible("ottIdentitySubtitle")
        when (skin) {
            TvControlsSkin.FROST -> assertEquals("Show · Season 2", tv("ottIdentitySubtitle").text.toString())
            TvControlsSkin.MARQUEE -> { assertEquals("Season Two · Episode Seven", tv("ottIdentitySubtitle").text.toString()); assertEquals("Show", tv("ottIdentityOverline").text.toString()); visible("ottIdentityOverline") }
            TvControlsSkin.BROADCAST -> assertEquals("E7 — Fetched episode", tv("ottIdentitySubtitle").text.toString())
            TvControlsSkin.PULSE -> {
                assertTrue(tv("ottIdentitySubtitle").text is Spanned)
                val text = tv("ottIdentitySubtitle").text as Spanned
                assertEquals("Show · Season 2, Episode 7", text.toString())
                assertEquals(1, text.getSpans(0, text.length, ForegroundColorSpan::class.java).size)
                val color = text.getSpans(0, text.length, ForegroundColorSpan::class.java).single()
                assertEquals(0xFF9BA5FB.toInt(), color.foregroundColor); assertEquals(0, text.getSpanStart(color)); assertEquals(4, text.getSpanEnd(color)); assertEquals(Spanned.SPAN_EXCLUSIVE_EXCLUSIVE, text.getSpanFlags(color))
                assertEquals(1, text.getSpans(0, text.length, StyleSpan::class.java).size)
                val bold = text.getSpans(0, text.length, StyleSpan::class.java).single(); assertEquals(android.graphics.Typeface.BOLD, bold.style); assertEquals(4, text.getSpanEnd(bold))
            }
            TvControlsSkin.TICKET -> { assertEquals("S2 · E7", tv("ottIdentityBadge").text.toString()); visible("ottIdentityBadge"); visible("ottIdentityDivider"); assertEquals("Show", tv("ottIdentityOverline").text.toString()) }
            else -> assertEquals("S02 · E07", tv("ottIdentitySubtitle").text.toString())
        }
    }
    @Test fun blankEpisodeAndBlankShowUseTheOriginalPerSkinFallbacksWithoutReleaseFilename() {
        val item = p2Item(" ", season = 2, episode = 7); series(item); set("ottShowName", " "); title(item)
        assertEquals("S02E07", tv("titleView").text.toString()); assertEquals("Episode 7", tv("ottEpisodeTitle").text.toString())
        if (skin == TvControlsSkin.CLASSIC) return
        assertEquals("Episode 7", tv("ottIdentityTitle").text.toString())
        when (skin) {
            TvControlsSkin.FROST -> assertEquals("Season 2 · Episode 7", tv("ottIdentitySubtitle").text.toString())
            TvControlsSkin.MARQUEE -> gone("ottIdentityOverline")
            TvControlsSkin.BROADCAST, TvControlsSkin.OTT -> assertEquals("S02 · E07", tv("ottIdentitySubtitle").text.toString())
            TvControlsSkin.PULSE -> { assertEquals("Season 2, Episode 7", tv("ottIdentitySubtitle").text.toString()); assertEquals(0, (tv("ottIdentitySubtitle").text as Spanned).getSpans(0, tv("ottIdentitySubtitle").text.length, ForegroundColorSpan::class.java).size) }
            TvControlsSkin.TICKET -> gone("ottIdentityOverline")
            else -> Unit
        }
    }
    @Test fun missingEpisodeNumbersHideTheBadgeAndNonpositiveRatingContainer() {
        val item = p2Item("", season = null, episode = null).copy(rating = 0.0); series(item); title(item)
        assertEquals("release.name.mkv", tv("titleView").text.toString()); assertEquals("release.name.mkv", tv("ottEpisodeTitle").text.toString())
        gone("ottEpisodeBadge"); gone("ottRatingContainer")
        if (skin != TvControlsSkin.CLASSIC) { assertEquals("release.name.mkv", tv("ottIdentityTitle").text.toString()); field("ottIdentitySubtitle")?.let { gone("ottIdentitySubtitle") }; field("ottIdentityOverline")?.let { gone("ottIdentityOverline") }; field("ottIdentityBadge")?.let { gone("ottIdentityBadge") }; field("ottIdentityDivider")?.let { gone("ottIdentityDivider") } }
        title(item.copy(rating = -1.0)); gone("ottRatingContainer"); title(item.copy(rating = null)); gone("ottRatingContainer")
    }
    @Test fun guideTitleMatchesBothNumbersRejectsBlankAndOverridesTheFilename() {
        val item = p2Item("Filename", season = 2, episode = 7); val model = series(item)
        fun episode(season: Int, number: Int, text: String?) = GuideEpisode(season = season, episode = number, title = text, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false)
        model.guideEpisodes.addAll(listOf(episode(1, 7, "wrong season"), episode(2, 6, "wrong episode"), episode(2, 7, "Guide title")))
        title(item); assertEquals("Guide title", tv("titleView").text.toString()); assertEquals("Guide title", tv("ottEpisodeTitle").text.toString())
        assertEquals("Guide title", runOriginal("guideTitleFor", item)); model.guideEpisodes.clear(); model.guideEpisodes.add(episode(2, 7, " "))
        assertNull(runOriginal("guideTitleFor", item)); title(item); assertEquals("Filename", tv("titleView").text.toString())
        assertNull(runOriginal("guideTitleFor", item.copy(season = null))); assertNull(runOriginal("guideTitleFor", item.copy(episode = null)))
    }
    @Test fun movieAndInvalidCurrentIndexResetSeriesOnlyIdentityViews() {
        val item = p2Item("Movie"); val model = series(item); model.contentType = "movie"; title(item)
        assertEquals("Movie", tv("titleView").text.toString())
        if (skin == TvControlsSkin.CLASSIC) { tv("ottEpisodeTitle").text = "unchanged"; title(item); assertEquals("unchanged", tv("ottEpisodeTitle").text.toString()); return }
        assertEquals("Movie", tv("ottIdentityTitle").text.toString()); set("currentIndex", 99); runOriginal("updateOttIdentity")
        assertEquals("Movie", tv("ottIdentityTitle").text.toString()); field("ottIdentitySubtitle")?.let { gone("ottIdentitySubtitle") }
        set("payload", null); title(item.copy(title = "")); assertEquals("", tv("titleView").text.toString())
    }
    @Test fun qualityUsesOriginalReleaseNameCachesAndFallsBackToDecodedUrl() {
        val item = p2Item("Fetched title", "https://phase16.invalid/Other.1080p.mkv?token=1").copy(sourceTitle = "Film.2160p.DV.Atmos.mkv")
        @Suppress("UNCHECKED_CAST") val tags = runOriginal("dockTagsFor", item) as List<DockFormatTags.Tag>
        assertEquals(listOf("4K", "DV", "ATMOS"), tags.map { it.short }); assertEquals(item.sourceTitle, field("dockTagsCacheKey")); assertSame(tags, field("dockTagsCache"))
        assertSame(tags, runOriginal("dockTagsFor", item)); val fallback = item.copy(sourceTitle = " ", url = "https://phase16.invalid/Film%2E1080p%2EHDR.mkv?token=1")
        assertEquals(listOf("1080p", "HDR"), (runOriginal("dockTagsFor", fallback) as List<*>).map { (it as DockFormatTags.Tag).short })
        assertEquals("Fetched title", field("dockTagsCacheKey")); assertEquals(emptyList<Any>(), field("dockTagsCache"))
        assertEquals(emptyList<Any>(), runOriginal("dockTagsFor", fallback.copy(url = "https://h/")))
        assertEquals(emptyList<Any>(), runOriginal("dockTagsFor", fallback.copy(url = "https://h/Fetched title")))
        assertEquals(listOf("1080p"), (runOriginal("dockTagsFor", fallback.copy(url = "https://h/bad%GG.1080p.mkv")) as List<*>).map { (it as DockFormatTags.Tag).short })
    }
    @Test fun qualityRatingAndMetadataShowExactTextColorSpansAndHideAbsentValues() {
        val item = p2Item("Episode", season = 2, episode = 7).copy(sourceTitle = "Film.2160p.DV.Atmos.mkv", rating = 8.6)
        series(item); set("ottShowName", "Show"); title(item)
        @Suppress("UNCHECKED_CAST") val chips = field("ottQualityChips") as Array<android.widget.TextView?>
        if (skin == TvControlsSkin.CLASSIC || skin == TvControlsSkin.OTT) {
            assertTrue(chips.all { it == null }); set("dockTagsCacheKey", "untouched")
            call("updateOttExtras", arrayOf(PlaybackItem::class.java), item)
            assertEquals("untouched", field("dockTagsCacheKey")); return
        }
        if (skin == TvControlsSkin.MARQUEE) {
            val line = tv("ottMetaLine"); assertEquals("4K · DOLBY VISION · ATMOS — ★ 8.6", line.text.toString()); visible("ottMetaLine")
            assertTrue(line.text is Spanned); val text = line.text as Spanned; assertEquals(1, text.getSpans(0, text.length, ForegroundColorSpan::class.java).size)
                val color = text.getSpans(0, text.length, ForegroundColorSpan::class.java).single()
            assertEquals(0xFFEAC981.toInt(), color.foregroundColor); assertEquals(text.length - 5, text.getSpanStart(color)); assertEquals(text.length, text.getSpanEnd(color))
        } else {
            chips.filterNotNull().forEachIndexed { i, chip -> assertEquals(listOf("4K", "DV", "ATMOS")[i], chip.text.toString()); assertEquals(View.VISIBLE, chip.visibility) }
            assertEquals("★ 8.6", tv("ottRatingChip").text.toString()); visible("ottRatingChip")
            if (skin == TvControlsSkin.PULSE || skin == TvControlsSkin.FROST) { assertTrue(tv("ottRatingChip").text is Spanned); val text = tv("ottRatingChip").text as Spanned; assertEquals(1, text.getSpans(0, text.length, ForegroundColorSpan::class.java).size)
                val color = text.getSpans(0, text.length, ForegroundColorSpan::class.java).single(); assertEquals(if (skin == TvControlsSkin.PULSE) 0xFF818CF8.toInt() else 0xFFF5C518.toInt(), color.foregroundColor); assertEquals(0, text.getSpanStart(color)); assertEquals(1, text.getSpanEnd(color)) }
        }
        if (skin == TvControlsSkin.TICKET) assertEquals("Show · 4K · Dolby Vision", tv("ottIdentityOverline").text.toString())
        set("ottShowName", " "); call("updateOttExtras", arrayOf(PlaybackItem::class.java), null)
        chips.filterNotNull().forEach { assertEquals(View.GONE, it.visibility) }; field("ottRatingChip")?.let { gone("ottRatingChip") }; field("ottMetaLine")?.let { gone("ottMetaLine") }; if (skin == TvControlsSkin.TICKET) gone("ottIdentityOverline")
    }
    @Test fun marqueeMetadataSeparatesQualityOnlyRatingOnlyAndNeither() {
        if (field("ottMetaLine") == null) set("ottMetaLine", android.widget.TextView(activity))
        fun extras(item: PlaybackItem?) = call("updateOttExtras", arrayOf(PlaybackItem::class.java), item)
        extras(p2Item("Film.1080p")); assertEquals("1080P", tv("ottMetaLine").text.toString()); visible("ottMetaLine")
        extras(p2Item("Film").copy(rating = 8.6)); assertEquals("★ 8.6", tv("ottMetaLine").text.toString()); visible("ottMetaLine")
        extras(p2Item("Film").copy(rating = 0.0)); gone("ottMetaLine")
    }
    @Test fun ticketIdentityPublishesShowThenQualityAndOtherSkinsRetainTheirShowVisibility() {
        val item = p2Item("Episode", season = 2, episode = 7).copy(sourceTitle = "Film.2160p.DV")
        series(item); set("ottShowName", "Show")
        if (skin == TvControlsSkin.TICKET) {
            val changes = mutableListOf<String>(); tv("ottIdentityOverline").addTextChangedListener(object : android.text.TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { changes.add(s.toString()) }
                override fun afterTextChanged(s: android.text.Editable?) = Unit
            })
            title(item); assertEquals(listOf("Show", "Show · 4K · Dolby Vision"), changes)
            changes.clear(); set("ottShowName", " "); title(item); assertEquals(listOf("4K · Dolby Vision"), changes)
        } else {
            tv("titleView").text = "stale"; title(item); assertEquals("Episode", tv("titleView").text.toString()); field("ottIdentitySubtitle")?.let { visible("ottIdentitySubtitle") }
        }
    }

}
