package com.debrify.app.tv

import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleSourcesMenuCharacterizationTest : TvPhase14OriginalTest() {
    private fun slot(id: String = "a", status: AddonSubtitleStatus = AddonSubtitleStatus.OK,
        subs: List<com.debrify.app.subtitle.StremioSubtitle> = emptyList(), error: String? = null) =
        AddonSubtitleResult(addon(id), status, subs, error)
    private fun select(result: SubtitleCatalogResult) = call("umPickSearchResult", arrayOf(SubtitleCatalogResult::class.java), result)
    @Test fun subtitleRailPinsTagsBadgesSelectionAndIdentityHeading() {
        slots().add(slot("a", AddonSubtitleStatus.LOADING)); slots().add(slot("b", subs = listOf(subtitle(addon = "b")))); slots().add(slot("c", AddonSubtitleStatus.FAILED))
        flat().add(subtitle(addon = "b")); set("currentStremioSubtitleIndex", 0); set("manualSubtitleDisplayLabel", "  Corrected title  ")
        val model = menuModel(0)
        assertEquals("Subtitles for Corrected title", model.col2Title)
        assertEquals(listOf("Embedded", "Addon a", "Addon b", "Addon c", "Fix movie", "Appearance", "Timing"), model.col2.map { it.title })
        assertEquals(listOf("emb", "addon:a", "addon:b", "addon:c", "search", "appearance", "timing"), model.col2.map { it.tag })
        assertEquals(listOf(null, "…", "1", "⚠", null, null, null), model.col2.map { it.value })
        assertEquals(listOf(false, false, true, false, false, false, false), model.col2.map { it.selected })
        assertTrue(model.col2[4].accent); assertFalse(model.previewVisible)
    }
    @Test fun missingActiveSubtitleMarksEmbeddedSelected() {
        set("currentStremioSubtitleIndex", 99); assertTrue(menuModel(0).col2[0].selected)
        flat().add(subtitle()); set("currentStremioSubtitleIndex", 0); assertFalse(menuModel(0).col2[0].selected)
    }
    @Test fun embeddedAppearanceAndTimingDispatchToExistingSubtitleController() {
        var model = menuModel(0); assertEquals("Track", model.col3Title); assertEquals(rows("umEmbeddedTrackRows").map { it.title }, model.col3.map { it.title })
        model = menuModel(2); assertEquals("Appearance · live", model.col3Title); assertTrue(model.previewVisible); assertEquals(rows("umAppearanceRows").map { it.title }, model.col3.map { it.title })
        model = menuModel(3); assertEquals("Timing", model.col3Title); assertFalse(model.previewVisible); assertEquals(rows("umTimingRows").map { it.title }, model.col3.map { it.title })
    }
    @Test fun searchModeChangesToRowsOnlyWhenSeriesPromptPending() {
        var model = menuModel(1); assertEquals("Fix movie", model.col3Title); assertEquals(UnifiedMenuController.Col3Mode.SEARCH, model.col3Mode)
        set("pendingSeriesResult", result("series")); model = menuModel(1); assertEquals(UnifiedMenuController.Col3Mode.ROWS, model.col3Mode)
        assertEquals(listOf("Season  ◀ ▶", "Episode  ◀ ▶", "Fetch subtitles"), model.col3.map { it.title })
    }
    @Test fun addonColumnUsesCurrentAddonNameAndMissingColumnHasEmptyRows() {
        slots().add(slot(subs = listOf(subtitle()))); assertEquals("Addon a", menuModel(1).col3Title)
        assertEquals(rows("umAddonTrackRows", "a").map { it.title }, menuModel(1).col3.map { it.title })
        val model = menuModel(99); assertEquals("", model.col3Title); assertTrue(model.col3.isEmpty())
    }
    @Test fun unknownAddonProducesNoRows() = assertTrue(rows("umAddonTrackRows", "missing").isEmpty())
    @Test fun loadingAddonRowIsExactDisabledPlaceholder() {
        slots().add(slot(status = AddonSubtitleStatus.LOADING)); val row = rows("umAddonTrackRows", "a").single()
        assertEquals("Loading…", row.title); assertFalse(row.enabled); assertNull(row.onOk)
    }
    @Test fun failedAddonRowsPinRetryActionAndFortyEightCharacterErrorLimit() {
        val error = "x".repeat(49); slots().add(slot(status = AddonSubtitleStatus.FAILED, error = error))
        var rows = rows("umAddonTrackRows", "a"); assertEquals(listOf("Failed — retry this addon", "x".repeat(48)), rows.map { it.title })
        assertTrue(rows[0].accent); assertTrue(rows[0].enabled); assertNotNull(rows[0].onOk); assertFalse(rows[1].enabled)
        val response = response(); rows[0].onOk!!.invoke(); entered(response); complete(response, jobs().single())
        slots()[0] = slot(status = AddonSubtitleStatus.FAILED, error = " "); rows = rows("umAddonTrackRows", "a"); assertEquals(1, rows.size)
    }
    @Test fun failedAddonWithNullErrorShowsOnlyRetry() {
        slots().add(slot(status = AddonSubtitleStatus.FAILED)); assertEquals(listOf("Failed — retry this addon"), rows("umAddonTrackRows", "a").map { it.title })
    }
    @Test fun emptySuccessfulAddonHasExactDisabledPlaceholder() {
        slots().add(slot()); val row = rows("umAddonTrackRows", "a").single()
        assertEquals("No subtitles from this addon", row.title); assertFalse(row.enabled); assertNull(row.onOk)
    }
    @Test fun addonTrackRowsPinDisplayLanguageTagsAndBothSelectionOperands() {
        val first = subtitle(lang = "eng"); val second = subtitle("https://phase14.invalid/second.srt", lang = "spa", label = "Spanish")
        slots().add(slot(subs = listOf(first, second))); flat().addAll(listOf(first, second)); set("currentStremioSubtitleIndex", 1)
        var rows = rows("umAddonTrackRows", "a"); assertEquals(listOf(first.displayName, second.displayName), rows.map { it.title })
        assertEquals(listOf("ENG", "SPA"), rows.map { it.value }); assertEquals(listOf("subtitle:${first.url}", "subtitle:${second.url}"), rows.map { it.tag })
        assertEquals(listOf(false, true), rows.map { it.selected })
        flat()[1] = second.copy(addonId = "other"); rows = rows("umAddonTrackRows", "a"); assertEquals(listOf(false, false), rows.map { it.selected })
    }
    @Test fun addonTrackActionSelectsByUrlThroughExistingSubtitleController() {
        val sub = subtitle(); slots().add(slot(subs = listOf(sub))); flat().add(sub)
        @Suppress("UNCHECKED_CAST") val cache = TvPlayerOriginalAccess.field(com.debrify.app.util.SubtitleCueCache, "cache") as MutableMap<String, List<com.debrify.app.util.SubtitleCue>>
        cache[sub.url] = listOf(com.debrify.app.util.SubtitleCue(0, 1000, "cached")); flag("subtitle_auto_sync_enabled", false)
        rows("umAddonTrackRows", "a").single().onOk!!.invoke()
        assertEquals(0, field("currentStremioSubtitleIndex")); assertEquals(sub.url, field("activeExternalSubtitleUrl")); assertEquals(true, field("userManuallySelectedSubtitle"))
    }
    @Test fun pendingSeasonAndEpisodeAdjustmentsPinInclusiveOneNinetyNineAndNineNinetyNineBounds() {
        set("pendingSeriesResult", result("series")); var rows = rows("umSearchRows")
        assertEquals(listOf("1", "1", null), rows.map { it.value }); assertTrue(rows[0].adjustable); assertTrue(rows[1].adjustable); assertTrue(rows[2].accent)
        rows[0].onAdjust!!.invoke(-10); rows[1].onAdjust!!.invoke(-10); assertEquals(1, field("pendingSeason")); assertEquals(1, field("pendingEpisode"))
        rows[0].onAdjust!!.invoke(200); rows[1].onAdjust!!.invoke(2000); assertEquals(99, field("pendingSeason")); assertEquals(999, field("pendingEpisode"))
        rows = rows("umSearchRows"); assertEquals(listOf("99", "999", null), rows.map { it.value })
    }
    @Test fun pendingFetchActionReadsCurrentResultAndNumbersThenClearsAndHidesMenu() {
        menu().show("subs", "search"); set("pendingSeriesResult", result("series")); set("pendingSeason", 3); set("pendingEpisode", 5)
        val row = rows("umSearchRows").last(); row.onOk!!.invoke()
        assertNull(field("pendingSeriesResult")); assertEquals(3, field("manualSubtitleSeason")); assertEquals(5, field("manualSubtitleEpisode")); assertFalse(menu().isVisible)
    }
    @Test fun pendingFetchActionRechecksResultAtInvocationTimeAndStillHidesWhenCleared() {
        menu().show("subs", "search"); set("pendingSeriesResult", result("series")); val row = rows("umSearchRows").last(); val before = token()
        set("pendingSeriesResult", null); row.onOk!!.invoke(); assertEquals(before, token()); assertFalse(menu().isVisible)
    }
    @Test fun searchRowsPutDisabledStatusBeforeCatalogResultsAndExposeActions() {
        set("subtitleSearchStatus", "Server declined"); set("subtitleSearchResults", listOf(result(), result("series", "Show")))
        val rows = rows("umSearchRows"); assertEquals(listOf("Server declined", "Found film (2024)", "Show (2024)"), rows.map { it.title })
        assertFalse(rows[0].enabled); assertNull(rows[0].onOk); assertEquals("Movie · Catalog · tt141", rows[1].value); assertNotNull(rows[1].onOk)
        rows[1].onOk!!.invoke(); assertEquals("tt141", field("manualSubtitleImdbId")); assertEquals("movie", field("manualSubtitleType"))
    }
    @Test fun emptySearchStatusDoesNotCreateAPlaceholderRow() {
        set("subtitleSearchStatus", ""); set("subtitleSearchResults", emptyList<SubtitleCatalogResult>()); assertTrue(rows("umSearchRows").isEmpty())
    }
    @Test fun resolvedSeriesSelectionUsesCurrentNumbersAndHidesMenu() {
        menu().show("subs", "search"); model().items[0] = item().copy(season = 6, episode = 9); select(result("series"))
        assertEquals(6, field("manualSubtitleSeason")); assertEquals(9, field("manualSubtitleEpisode")); assertFalse(menu().isVisible)
    }
    @Test fun unresolvedSeriesSelectionStoresPromptWithCoercedItemNumbersAndRenders() {
        menu().show("subs", "search"); model().items[0] = item().copy(season = 0, episode = -2); val result = result("series")
        select(result); assertEquals(result, field("pendingSeriesResult")); assertEquals(1, field("pendingSeason")); assertEquals(1, field("pendingEpisode")); assertTrue(menu().isVisible)
        val rendered = TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model
        assertEquals(UnifiedMenuController.Col3Mode.ROWS, rendered.col3Mode); assertEquals(listOf("Season  ◀ ▶", "Episode  ◀ ▶", "Fetch subtitles"), rendered.col3.map { it.title })
    }
    @Test fun unresolvedSeriesWithoutItemUsesLiveManualNumbersOrOne() {
        set("payload", null); set("manualSubtitleSeason", 8); set("manualSubtitleEpisode", 15); select(result("series"))
        assertEquals(8, field("pendingSeason")); assertEquals(15, field("pendingEpisode"))
        set("manualSubtitleSeason", null); set("manualSubtitleEpisode", null); select(result("series")); assertEquals(1, field("pendingSeason")); assertEquals(1, field("pendingEpisode"))
    }
    @Test fun movieSelectionAppliesIdentityAndHidesMenu() {
        menu().show("subs", "search"); select(result()); assertEquals("tt141", field("manualSubtitleImdbId")); assertFalse(menu().isVisible)
    }
    @Test fun unifiedSearchStartClearsOldResultsAndPendingSeriesThenRendersLoading() {
        menu().show("subs", "search"); set("subtitleSearchResults", listOf(result())); set("pendingSeriesResult", result("series"))
        menuCallbacks().onSearchSubmit("new query")
        assertEquals("Searching…", field("subtitleSearchStatus")); assertEquals(emptyList<SubtitleCatalogResult>(), field("subtitleSearchResults")); assertNull(field("pendingSeriesResult"))
        assertEquals(mapOf("query" to "new query"), catalogRequest().call.arguments)
        val rendered = TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model
        assertEquals(UnifiedMenuController.Col3Mode.SEARCH, rendered.col3Mode); assertEquals("Searching…", rendered.col3.single().title)
    }
    @Test fun unifiedSearchRepliesPinEmptyResultsAndServerTextAndRepaint() {
        menu().show("subs", "search"); menuCallbacks().onSearchSubmit("query"); endpoint.success("searchSubtitleCatalogs", emptyList<Any>())
        assertEquals("No matches — try a different title", field("subtitleSearchStatus"))
        assertEquals("No matches — try a different title", (TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model).col3.single().title)
        menuCallbacks().onSearchSubmit("query"); endpoint.error("searchSubtitleCatalogs", "Server declined")
        assertEquals("Server declined", field("subtitleSearchStatus")); assertEquals("Server declined", (TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model).col3.single().title)
    }
    @Test fun unifiedSearchInitialQueryUsesCurrentItemAndHandlesMissingItem() {
        assertEquals("Film", menuCallbacks().searchInitialQuery()); set("payload", null); assertEquals("", menuCallbacks().searchInitialQuery())
    }
    @Test fun refreshUpdatesVisibleUnifiedMenuAndLegacySubtitlePanelIndependently() {
        menu().show("subs", "search"); call("showSubtitleSettingsPanel", emptyArray())
        set("subtitleSearchStatus", "fresh state"); set("manualSubtitleDisplayLabel", "Fresh identity"); set("isLoadingStremioSubtitles", true)
        @Suppress("UNCHECKED_CAST") val tracks = field("subtitleTracks") as MutableList<Pair<String, androidx.media3.common.TrackSelectionOverride?>>
        tracks.clear()
        call("refreshSubtitleUiForLoading", emptyArray())
        assertEquals("fresh state", (TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model).col3.single().title)
        assertEquals(listOf("Off", "⏳ Loading external subtitles..."), tracks.map { it.first })
        val panel = field("subtitlePanel") as SubtitlePanelController
        assertEquals("Subtitles for Fresh identity", (TvPlayerOriginalAccess.field(panel, "identityLabel") as android.widget.TextView).text.toString())
        menu().hide(); call("hideSubtitleSettingsPanel", emptyArray()); val before = TvPlayerOriginalAccess.field(menu(), "model"); set("subtitleSearchStatus", "hidden state"); tracks.clear()
        call("refreshSubtitleUiForLoading", emptyArray()); assertSame(before, TvPlayerOriginalAccess.field(menu(), "model")); assertTrue(tracks.isEmpty())
    }
}
