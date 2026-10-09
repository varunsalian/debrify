package com.debrify.app.tv

import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsMetadataBoundaryCharacterizationTest : TvPhase16OriginalTest() {
    private fun metadata(season: Int?, episode: Int?, kind: String = "series", title: String = "") {
        set("payload", PlaybackPayload("Show", null, kind, mutableListOf(p2Item("", season = season, episode = episode)), 0, "Show"))
        set("currentIndex", 0); tv("titleView").text = title
        v("titleView").visibility = View.INVISIBLE; v("titleOttContainer").visibility = View.INVISIBLE
        showDock()
    }
    private fun simple(titleVisible: Boolean) {
        assertEquals(View.VISIBLE, v("titleView").visibility); assertEquals(View.GONE, v("titleOttContainer").visibility)
        assertEquals(if (titleVisible) View.VISIBLE else View.GONE, v("titleContainer").visibility)
    }
    @Test fun seasonOnlySeriesWithBlankTitleNeverUsesTheOttSeriesHeader() { metadata(2, null); simple(false) }
    @Test fun episodeOnlySeriesWithBlankTitleNeverUsesTheOttSeriesHeader() { metadata(null, 7); simple(false) }
    @Test fun missingSeriesNumbersWithTitleUsesTheSimpleHeader() { metadata(null, null, title = "Film"); simple(true) }
    @Test fun movieWithBothNumbersUsesTheSimpleHeader() { metadata(2, 7, "movie"); simple(false) }
    @Test fun mixedCaseSeriesWithBothNumbersUsesTheOttHeaderWithoutSimpleText() {
        metadata(2, 7, "SeRiEs")
        assertEquals(View.GONE, v("titleView").visibility); assertEquals(View.VISIBLE, v("titleOttContainer").visibility)
        assertEquals(View.VISIBLE, v("titleContainer").visibility); assertEquals(1f, v("titleContainer").alpha, 0f)
    }
    @Test fun immediateTitleHideResetsEveryPresentationPropertyFromAnInvisibleSimpleTitle() {
        v("titleContainer").visibility = View.VISIBLE; v("titleContainer").alpha = 0.7f
        v("titleView").visibility = View.INVISIBLE; v("titleOttContainer").visibility = View.VISIBLE
        runOriginal("hideTitleImmediately")
        assertEquals(View.GONE, v("titleContainer").visibility); assertEquals(0f, v("titleContainer").alpha, 0f)
        assertEquals(View.VISIBLE, v("titleView").visibility); assertEquals(View.GONE, v("titleOttContainer").visibility)
    }
    @Test fun visibleControlsLeaveTheFloatingLiveBannerUntilItsOwnTimeout() {
        iptv(); showDock(); step(301)
        runOriginal("showIptvZapBanner", channel(), false)
        step(161); assertTrue(field("controlsMenuVisible") as Boolean)
        assertFalse(field("iptvZapBannerDocked") as Boolean); assertEquals(View.VISIBLE, v("iptvZapBanner").visibility)
        val entry = field("iptvZapBannerEntry"); hideDock(); step(251)
        assertSame("floating channel identity retained", entry, field("iptvZapBannerEntry"))
        assertEquals(View.VISIBLE, v("iptvZapBanner").visibility)
        step(4499 - 161 - 251); assertEquals(View.VISIBLE, v("iptvZapBanner").visibility)
        step(181); assertEquals(View.GONE, v("iptvZapBanner").visibility)
    }
}
