package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvGuideStateSweepTest : TvPhase11OriginalTest() {
    private val tokenNames = listOf("iptvUiContextToken", "iptvBrowseToken", "iptvZapRequestToken")
    private fun tokens() = tokenNames.associateWith { field(it) as Int }
    private fun incremented(before: Map<String, Int>) = before.forEach { (n, v) -> assertEquals(n, v + 1, field(n)) }
    private fun text(name: String) = (field(name) as TextView).text.toString()
    private fun clearedSearch() {
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        assertNull(field("iptvSearchSavedCategory"))
        assertTrue((field("iptvSearchSavedChannels") as List<*>).isEmpty())
        assertTrue((field("iptvSearchSavedCategories") as List<*>).isEmpty())
        assertFalse(field("iptvSearchSavedUsesZapWindow") as Boolean)
        assertFalse(field("iptvSearchSavedZapOwnsUiContext") as Boolean)
    }

    @Test fun beginSearchCopiesAdapterAndCategoryStateAndRetiresAllWork() {
        val visible = mutableListOf(channel().copy(name = "Visible", logoUrl = null))
        adapter().updateChannels(visible)
        val categories = mutableListOf("News", "Sports")
        set("iptvCategories", categories); set("iptvGuideUsesZapWindow", true)
        set("iptvZapOwnsUiContext", true); set("iptvZapRequestInFlight", true)
        queue().add(-1); (field("iptvBrowseLoading") as View).visibility = View.VISIBLE
        val before = tokens()
        call("beginIptvAllCategorySearch", emptyArray())
        incremented(before)
        assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        assertEquals("News", field("iptvSearchSavedCategory"))
        assertEquals(visible, field("iptvSearchSavedChannels"))
        assertNotSame(visible, field("iptvSearchSavedChannels"))
        assertEquals(categories, field("iptvSearchSavedCategories"))
        assertNotSame(categories, field("iptvSearchSavedCategories"))
        assertTrue(field("iptvSearchSavedUsesZapWindow") as Boolean)
        assertTrue(field("iptvSearchSavedZapOwnsUiContext") as Boolean)
        assertFalse(field("iptvZapOwnsUiContext") as Boolean)
        assertFalse(field("iptvZapRequestInFlight") as Boolean)
        assertTrue(queue().isEmpty()); assertNull(field("iptvSelectedCategory"))
        assertEquals(View.GONE, (field("iptvBrowseLoading") as View).visibility)
        assertEquals("All categories", text("iptvCategoryButton"))
        categories.add("Later"); visible.clear()
        assertEquals(listOf("News", "Sports"), field("iptvSearchSavedCategories"))
        assertEquals(1, (field("iptvSearchSavedChannels") as List<*>).size)
    }

    @Test fun beginSearchGuardsNonLiveAndRepeatedEntryAndUsesBrowseFallback() {
        set("iptvContentType", "vod"); val before = tokens()
        call("beginIptvAllCategorySearch", emptyArray())
        assertEquals(before, tokens()); assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        set("iptvContentType", "live"); set("iptvChannelAdapter", null)
        val visible = browseChannels()
        call("beginIptvAllCategorySearch", emptyArray())
        assertEquals(visible, field("iptvSearchSavedChannels")); assertNotSame(visible, field("iptvSearchSavedChannels"))
        val saved = field("iptvSearchSavedChannels"); val entered = tokens()
        set("iptvSelectedCategory", "Changed")
        call("beginIptvAllCategorySearch", emptyArray())
        assertEquals(entered, tokens()); assertSame(saved, field("iptvSearchSavedChannels"))
        assertEquals("News", field("iptvSearchSavedCategory"))
    }

    @Test fun restoreSearchCopiesSavedStateBeforeClearingAndInvalidatesLateBrowse() {
        val original = channels().toMutableList()
        set("iptvGuideUsesZapWindow", true); set("iptvZapPagingActive", true)
        call("beginIptvAllCategorySearch", emptyArray())
        val savedChannels = field("iptvSearchSavedChannels")
        val savedCategories = field("iptvSearchSavedCategories")
        browse("late"); val request = messenger.requests.lastIndex
        set("iptvBrowseChannels", mutableListOf<IptvChannelEntry>())
        adapter().updateChannels(emptyList())
        set("iptvCategories", mutableListOf("Wrong")); search().setText("wrong")
        queue().add(1); set("iptvZapRequestInFlight", true)
        (field("iptvGuideCurrentName") as TextView).text = "Wrong"
        val before = tokens()
        assertEquals(true, call("restoreIptvCategoryAfterSearch", emptyArray()))
        incremented(before); clearedSearch()
        assertEquals("News", field("iptvSelectedCategory"))
        assertEquals(listOf("News", "Movies"), field("iptvCategories"))
        assertNotSame(savedCategories, field("iptvCategories"))
        assertEquals(original, browseChannels()); assertNotSame(savedChannels, browseChannels())
        assertEquals(original, adapter().entriesSnapshot())
        assertTrue(field("iptvGuideUsesZapWindow") as Boolean)
        assertTrue(field("iptvZapOwnsUiContext") as Boolean)
        assertFalse(field("iptvZapRequestInFlight") as Boolean); assertTrue(queue().isEmpty())
        assertEquals(View.GONE, (field("iptvBrowseLoading") as View).visibility)
        assertEquals("", search().text.toString()); assertEquals("News", text("iptvCategoryButton"))
        assertEquals(original[0].displayName, text("iptvGuideCurrentName"))
        reply(request = request)
        assertEquals(original, browseChannels())
    }

    @Test fun restoreSearchPreservesFalseFlagsAndBootstrapsOnlySavedOwner() {
        for ((owner, paging, expectedRequest) in listOf(Triple(false, false, false), Triple(true, true, false), Triple(true, false, true))) {
            set("iptvAllCategorySearchActive", true); set("iptvSearchSavedCategory", "Movies")
            set("iptvSearchSavedChannels", channels().toMutableList())
            set("iptvSearchSavedCategories", mutableListOf("Movies"))
            set("iptvSearchSavedUsesZapWindow", false); set("iptvSearchSavedZapOwnsUiContext", owner)
            set("iptvZapPagingActive", paging); set("iptvGuideUsesZapWindow", true)
            clearTransport()
            assertEquals(true, call("restoreIptvCategoryAfterSearch", emptyArray()))
            assertEquals(owner, field("iptvZapOwnsUiContext")); assertFalse(field("iptvGuideUsesZapWindow") as Boolean)
            assertEquals(expectedRequest, requests("requestIptvBrowse").isNotEmpty())
            if (expectedRequest) assertEquals(channels()[0].url, args("requestIptvBrowse")["anchorUrl"])
            set("iptvZapRequestInFlight", false)
        }
        val before = tokens(); assertEquals(false, call("restoreIptvCategoryAfterSearch", emptyArray()))
        assertEquals(before, tokens())
    }

    @Test fun commitAndClearReplaceAllSavedCollectionsWithoutChangingPlayback() {
        val old = channels()
        call("beginIptvAllCategorySearch", emptyArray())
        val savedChannels = field("iptvSearchSavedChannels") as List<*>
        val savedCategories = field("iptvSearchSavedCategories") as List<*>
        call("commitIptvAllCategorySearch", emptyArray()); clearedSearch()
        assertEquals(2, savedChannels.size); assertEquals(2, savedCategories.size)
        assertNotSame(savedChannels, field("iptvSearchSavedChannels"))
        assertNotSame(savedCategories, field("iptvSearchSavedCategories"))
        assertSame(old, channels())
        set("iptvSearchSavedCategory", "Inactive sentinel")
        call("commitIptvAllCategorySearch", emptyArray())
        assertEquals("Inactive sentinel", field("iptvSearchSavedCategory"))
        call("clearIptvAllCategorySearchState", emptyArray()); clearedSearch()
    }

    @Test fun browserChromePinsEveryTitleCategoryCountAndLiveSelection() {
        set("iptvSourceName", "Renamed"); set("iptvSelectedCategory", null)
        for ((type, label) in listOf("live" to "Live television", "vod" to "Movies", "series" to "Series", "episodes" to "Episodes", "other" to "Live television")) {
            set("iptvContentType", type)
            call("refreshIptvBrowserChrome", arrayOf(stringType), null)
            assertEquals(label, text("iptvGuideTitle")); assertEquals("Renamed", text("iptvSourceButton"))
            assertEquals("All categories", text("iptvCategoryButton")); assertEquals("2 items", text("iptvGuideCountText"))
            assertEquals(type == "live", activity.findViewById<View>(R.id.iptv_mode_live).isSelected)
            assertEquals(if (type == "live") View.VISIBLE else View.GONE, activity.findViewById<View>(R.id.iptv_nav_browse).visibility)
        }
        set("iptvSelectedCategory", "Sports")
        call("refreshIptvBrowserChrome", arrayOf(stringType), "Explicit title")
        assertEquals("Sports", text("iptvCategoryButton")); assertEquals("Explicit title", text("iptvGuideTitle"))
    }

    @Test fun catalogVisibilityPinsEachLiveAndSourceGate() {
        val sources = field("iptvSources")
        val mainControls = listOf(R.id.iptv_nav_browse, R.id.iptv_nav_search, R.id.iptv_filter_bar)
        val sourceControls = listOf(R.id.iptv_nav_favorites, R.id.iptv_nav_sources, R.id.iptv_source_button)
        for ((type, hasSources) in listOf("live" to true, "live" to false, "vod" to true, "series" to false)) {
            set("iptvContentType", type); set("iptvSources", if (hasSources) sources else mutableListOf<IptvSourceEntry>())
            for (id in mainControls + sourceControls) activity.findViewById<View>(id).visibility = View.INVISIBLE
            call("updateIptvCatalogControlVisibility", emptyArray())
            for (id in mainControls) assertEquals(id.toString(), if (type == "live") View.VISIBLE else View.GONE, activity.findViewById<View>(id).visibility)
            for (id in sourceControls) assertEquals(id.toString(), if (type == "live" && hasSources) View.VISIBLE else View.GONE, activity.findViewById<View>(id).visibility)
        }
    }

    @Test fun contentTypeSelectionCommitsSearchAndRefreshesRequestButSameTypeRestores() {
        call("beginIptvAllCategorySearch", emptyArray()); search().setText("query")
        set("iptvSelectedCategory", "Stale selected category")
        call("selectIptvContentType", arrayOf(stringType), "vod")
        clearedSearch(); assertEquals("vod", field("iptvContentType")); assertNull(field("iptvSelectedCategory"))
        assertEquals("", search().text.toString()); assertEquals("Movies", text("iptvGuideTitle"))
        assertEquals("vod", args("requestIptvBrowse")["contentType"]); assertEquals("", args("requestIptvBrowse")["query"])
        set("iptvContentType", "live"); set("iptvSelectedCategory", "News"); set("iptvZapPagingActive", true)
        call("beginIptvAllCategorySearch", emptyArray()); clearTransport()
        call("selectIptvContentType", arrayOf(stringType), "live")
        assertEquals("News", field("iptvSelectedCategory")); clearedSearch()
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun sourceSelectionPinsEveryTypeArmAndAllResetEffects() {
        data class Case(val initial: String, val source: IptvSourceEntry, val expected: String)
        val cases = listOf(
            Case("live", IptvSourceEntry("continue", "Continue", false, true, false), "vod"),
            Case("vod", IptvSourceEntry("favorites", "Favorites", true, false, false), "live"),
            Case("vod", IptvSourceEntry("list", "List", false, false, false, isList = true), "live"),
            Case("episodes", IptvSourceEntry("xt", "Xtream", false, false, true), "series"),
            Case("episodes", IptvSourceEntry("ordinary", "Ordinary", false, false, false), "live"),
            Case("series", IptvSourceEntry("ordinary", "Ordinary", false, false, false), "live"),
            Case("series", IptvSourceEntry("xt", "Xtream", false, false, true), "series"),
            Case("vod", IptvSourceEntry("ordinary", "Ordinary", false, false, false), "vod"))
        for (c in cases) {
            set("iptvContentType", "live"); call("beginIptvAllCategorySearch", emptyArray())
            set("iptvContentType", c.initial); set("iptvSelectedCategory", "Stale")
            val borrowed = mutableListOf("Stale"); set("iptvCategories", borrowed); search().setText("stale")
            call("selectIptvSource", arrayOf(IptvSourceEntry::class.java), c.source)
            clearedSearch(); assertEquals(c.source.id, field("iptvSourceId")); assertEquals(c.source.name, field("iptvSourceName"))
            assertNull(field("iptvSelectedCategory")); assertTrue(borrowed.isEmpty())
            assertEquals(c.expected, field("iptvContentType")); assertEquals("", search().text.toString())
            assertEquals(c.source.name, text("iptvSourceButton"))
            assertEquals(c.source.id, args("requestIptvBrowse")["sourceId"])
            assertEquals(c.expected, args("requestIptvBrowse")["contentType"])
            assertEquals("", args("requestIptvBrowse")["query"])
        }
    }

    @Test fun showGuideHidesBannerAndEpgRefreshesChromeAndFocusesCurrentRow() {
        val current = channels()[1]; channels().forEach { it.isCurrent = it === current }
        set("currentIptvIndex", 1); adapter().updateChannels(channels())
        call("showIptvZapBanner", arrayOf(IptvChannelEntry::class.java, boolType), current, false)
        set("iptvEpgVisible", true); (field("iptvEpgPanel") as View).visibility = View.VISIBLE
        (field("iptvGuideCurrentName") as TextView).text = "Wrong"
        (field("iptvGuideTitle") as TextView).text = "Wrong"
        show()
        assertNull(field("iptvZapBannerEntry")); assertFalse(field("iptvEpgVisible") as Boolean)
        assertEquals(View.GONE, (field("iptvEpgPanel") as View).visibility)
        assertEquals(current.displayName, text("iptvGuideCurrentName")); assertEquals("Live television", text("iptvGuideTitle"))
        val overlay = field("iptvGuideOverlay") as View
        assertEquals(0f, overlay.alpha, 0f); assertEquals(200L, overlay.animate().duration)
        advance(240)
        val holder = guideList().findViewHolderForAdapterPosition(1)
        assertNotNull(holder); assertTrue("show focuses current row through delayed post", holder!!.itemView.hasFocus())
        assertEquals(1f, overlay.alpha, 0f)
    }

    @Test fun showGuideGuardsNonLiveAndMissingCurrentAndToggleRunsBothBranches() {
        channels()[0] = channels()[0].copy(isLive = false)
        show(); assertFalse(field("iptvGuideVisible") as Boolean)
        set("currentIptvIndex", 99); show(); assertFalse(field("iptvGuideVisible") as Boolean)
        set("currentIptvIndex", 1)
        call("toggleIptvGuide", emptyArray()); assertTrue(field("iptvGuideVisible") as Boolean)
        call("toggleIptvGuide", emptyArray()); assertFalse(field("iptvGuideVisible") as Boolean)
        advance(200); assertEquals(View.GONE, (field("iptvGuideOverlay") as View).visibility)
    }

    @Test fun hideGuideRestoresSearchAndClosesEpgBeforeItsAnimationCompletes() {
        show(); set("iptvZapPagingActive", true); call("beginIptvAllCategorySearch", emptyArray())
        set("iptvEpgVisible", true); (field("iptvEpgPanel") as View).visibility = View.VISIBLE
        hide()
        clearedSearch(); assertEquals("News", field("iptvSelectedCategory")); assertFalse(field("iptvGuideVisible") as Boolean)
        assertFalse(field("iptvEpgVisible") as Boolean); assertEquals(View.GONE, (field("iptvEpgPanel") as View).visibility)
        advance(200)
        assertEquals(0f, (field("iptvGuideOverlay") as View).alpha, 0f)
        assertEquals(View.GONE, (field("iptvGuideOverlay") as View).visibility)
    }

    @Test fun focusCurrentRowIsDeferredAndUsesAdapterPosition() {
        show(); advance(250)
        val current = channels()[1]; channels().forEach { it.isCurrent = it === current }
        adapter().updateChannels(channels()); idle()
        assertTrue(search().requestFocus())
        call("focusCurrentIptvGuideRow", emptyArray())
        assertTrue("outer post defers focus", search().hasFocus())
        idle()
        val holder = guideList().findViewHolderForAdapterPosition(1)
        assertNotNull(holder); assertTrue("nested post focuses actual current row", holder!!.itemView.hasFocus())
    }
}
