package com.debrify.app.tv

import android.view.View
import android.widget.TextView
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
internal class TvIptvSessionSweepTest : TvPhase11OriginalTest() {
    @Test fun beginCategorySessionPinsAllCapturedScopeAndInvalidationsBeforeAnchorRequest() {
        val selected = channel(url = "https://selected.invalid").copy(name = "Selected", group = "  Movies  ", index = 88, logoUrl = null)
        adapter().updateChannels(mutableListOf(selected))
        call("beginIptvAllCategorySearch", emptyArray())
        set("iptvSourceId", "Browse id"); set("iptvSourceName", "Browse name")
        set("iptvZapSourceId", "Old id"); set("iptvZapSourceName", "Old name"); set("iptvZapContentType", "vod")
        set("iptvCategories", mutableListOf("News", "Movies")); search().setText("temporary")
        set("iptvZapCategories", mutableListOf("Old zap category"))
        set("iptvGuideUsesZapWindow", true); set("iptvZapRequestInFlight", true); queue().add(-1)
        set("iptvZapCategoryTotal", 99)
        set("iptvZapCachedChannels", mutableListOf(channel())); set("iptvZapCachedOffset", 20)
        val before = listOf("iptvUiContextToken", "iptvBrowseToken", "iptvZapRequestToken").associateWith { field(it) as Int }
        call("beginIptvCategoryZapSession", arrayOf(IptvChannelEntry::class.java), selected)
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        assertNull(field("iptvSearchSavedCategory")); assertTrue((field("iptvSearchSavedChannels") as List<*>).isEmpty())
        assertEquals(before.getValue("iptvUiContextToken") + 1, field("iptvUiContextToken"))
        assertEquals(before.getValue("iptvBrowseToken") + 1, field("iptvBrowseToken"))
        assertEquals(before.getValue("iptvZapRequestToken") + 2, field("iptvZapRequestToken"))
        assertTrue(field("iptvZapOwnsUiContext") as Boolean); assertTrue(field("iptvZapPagingActive") as Boolean)
        assertTrue(field("iptvZapRequestInFlight") as Boolean); assertTrue(queue().isEmpty())
        assertEquals("Movies", field("iptvSelectedCategory")); assertEquals("Movies", field("iptvZapCategory"))
        assertEquals("Browse id", field("iptvZapSourceId")); assertEquals("Browse name", field("iptvZapSourceName"))
        assertEquals("live", field("iptvZapContentType")); assertEquals(listOf("News", "Movies"), field("iptvZapCategories"))
        assertNotSame(field("iptvCategories"), field("iptvZapCategories")); assertEquals(1, field("iptvZapCategoryTotal"))
        assertEquals("", search().text.toString()); assertFalse(field("iptvGuideUsesZapWindow") as Boolean)
        assertTrue((field("iptvZapCachedChannels") as List<*>).isEmpty()); assertEquals(0, field("iptvZapCachedOffset"))
        assertEquals("Movies", (field("iptvCategoryButton") as TextView).text.toString())
        assertEquals(88, selected.index); assertNotSame(selected, channels()[0]); assertEquals(selected.url, channels()[0].url)
        assertEquals("Browse id", args("requestIptvBrowse")["sourceId"])
        assertEquals("Movies", args("requestIptvBrowse")["category"]); assertEquals(selected.url, args("requestIptvBrowse")["anchorUrl"])
    }

    @Test fun categorySessionAcceptedWindowDrainsThenPrefetchesAdjacent() {
        val selected = channels()[0]
        call("beginIptvCategoryZapSession", arrayOf(IptvChannelEntry::class.java), selected)
        queue().add(1)
        reply(value = response("channels" to listOf(rawChannel(), rawChannel("Beta", 2)), "totalChannels" to 2))
        assertEquals(1, field("currentIptvIndex")); assertEquals("Beta", channels()[1].name)
        assertTrue(queue().isEmpty()); assertEquals(2, field("iptvZapCategoryTotal"))
        assertTrue(field("iptvGuideUsesZapWindow") as Boolean)
        assertEquals("Movies", args("requestIptvBrowse")["category"])
    }

    @Test fun categorySessionReplyWithoutInputsStartsForwardOrAdjacentPrefetch() {
        for (total in listOf(100, 2)) {
            set("iptvZapRequestInFlight", false); clearTransport()
            val selected = channels()[0]
            call("beginIptvCategoryZapSession", arrayOf(IptvChannelEntry::class.java), selected)
            reply(value = response("channels" to listOf(rawChannel(), rawChannel("Beta", 2)), "totalChannels" to total))
            assertEquals(2, requests("requestIptvBrowse").size)
            assertEquals(if (total == 100) "News" else "Movies", args("requestIptvBrowse")["category"])
            assertEquals(if (total == 100) 2 else 0, args("requestIptvBrowse")["offset"])
        }
    }

    @Test fun categorySessionRejectsSameUrlDifferentNameAndEmptyPageViaFallback() {
        for (rows in listOf(emptyList<Map<String, Any?>>(), listOf(rawChannel("Renamed", 1)))) {
            val chosen = channel(url = "https://phase11.invalid/1").copy(name = "Alpha", logoUrl = null, group = "  ")
            val neighbour = chosen.copy(name = "Neighbour", url = "https://neighbour.invalid")
            adapter().updateChannels(mutableListOf(chosen, neighbour))
            set("iptvZapRequestInFlight", false)
            call("beginIptvCategoryZapSession", arrayOf(IptvChannelEntry::class.java), chosen)
            assertNull(args("requestIptvBrowse")["category"])
            reply(value = response("channels" to rows))
            assertFalse(field("iptvZapPagingActive") as Boolean); assertFalse(field("iptvGuideUsesZapWindow") as Boolean)
            assertEquals(chosen.url, channels()[0].url); assertEquals("Alpha", channels()[0].name)
            assertEquals(listOf("Alpha", "Neighbour"), channels().map { it.name })
            assertEquals(0, channels()[0].index); assertTrue(channels()[0].isCurrent)
        }
    }

    @Test fun bootstrapPinsLiveTypeAndTrimmedGroupOrSelectedFallback() {
        val entry = channels()[0]
        call("bootstrapInitialIptvZapPaging", arrayOf(IptvChannelEntry::class.java), entry.copy(isLive = false))
        assertTrue(messenger.requests.isEmpty())
        set("iptvContentType", "vod"); call("bootstrapInitialIptvZapPaging", arrayOf(IptvChannelEntry::class.java), entry)
        assertTrue(messenger.requests.isEmpty())
        set("iptvContentType", "live"); set("iptvSelectedCategory", "Selected fallback")
        call("bootstrapInitialIptvZapPaging", arrayOf(IptvChannelEntry::class.java), entry.copy(group = " "))
        assertEquals("Selected fallback", args("requestIptvBrowse")["category"])
        assertEquals("Selected fallback", field("iptvZapCategory"))
        set("iptvZapRequestInFlight", false)
        call("bootstrapInitialIptvZapPaging", arrayOf(IptvChannelEntry::class.java), entry.copy(group = "  Movies  "))
        assertEquals("Movies", field("iptvSelectedCategory")); assertEquals("Movies", field("iptvZapCategory"))
        assertEquals("Movies", (field("iptvCategoryButton") as TextView).text.toString())
    }

    @Test fun bootstrapReplyReanchorsChangedLiveIdentityButDoesNotReanchorVod() {
        for (live in listOf(true, false)) {
            set("iptvZapRequestInFlight", false); clearTransport(); set("currentIptvIndex", 0)
            call("bootstrapInitialIptvZapPaging", arrayOf(IptvChannelEntry::class.java), channels()[0])
            val firstRequest = messenger.requests.lastIndex
            channels()[1] = channels()[1].copy(isLive = live); set("currentIptvIndex", 1)
            reply(value = response("channels" to listOf(rawChannel())), request = firstRequest)
            assertEquals(if (live) 2 else 1, requests("requestIptvBrowse").size)
            if (live) assertEquals(channels()[1].url, args("requestIptvBrowse")["anchorUrl"])
        }
    }

    @Test fun bootstrapMatchingReplyInstallsUpdatesControlsAndStartsForwardPrefetch() {
        for (total in listOf(80, 41)) {
            set("iptvZapRequestInFlight", false); set("iptvZapPagingActive", false); clearTransport()
            val selected = channels()[0]
            call("bootstrapInitialIptvZapPaging", arrayOf(IptvChannelEntry::class.java), selected)
            (field("iptvNextButton") as View).visibility = View.GONE
            reply(value = response("channels" to listOf(rawChannel()), "pageOffset" to 40, "totalChannels" to total))
            assertTrue(field("iptvZapPagingActive") as Boolean); assertEquals(40, channels()[0].index)
            assertEquals(total, field("iptvZapCategoryTotal")); assertEquals(View.VISIBLE, (field("iptvNextButton") as View).visibility)
            assertEquals(if (total == 80) 41 else 0, args("requestIptvBrowse")["offset"])
            assertEquals(if (total == 80) "News" else "Movies", args("requestIptvBrowse")["category"])
        }
    }

    @Test fun fallbackRejectsChangedIdentityAndAppendsMissingSelectionAndUpdatesAdapter() {
        val selected = channels()[0]; val old = channels()
        selected.isCurrent = false
        call("restoreIptvZapBootstrapFallback", arrayOf(IptvChannelEntry::class.java, listType), selected.copy(name = "Changed"), emptyList<IptvChannelEntry>())
        assertSame(old, channels())
        set("iptvZapPagingActive", true); set("iptvZapRequestInFlight", true); queue().add(1)
        set("iptvGuideUsesZapWindow", true); (field("iptvGuideCountText") as TextView).text = "Wrong count"
        val fallback = listOf(selected.copy(name = "Different", index = 88, isCurrent = true))
        call("restoreIptvZapBootstrapFallback", arrayOf(IptvChannelEntry::class.java, listType), selected, fallback)
        assertFalse(field("iptvZapPagingActive") as Boolean); assertFalse(field("iptvZapRequestInFlight") as Boolean); assertTrue(queue().isEmpty())
        assertEquals(listOf(0, 1), channels().map { it.index }); assertEquals(listOf(false, true), channels().map { it.isCurrent })
        assertSame(selected, channels()[1]); assertEquals(1, field("currentIptvIndex"))
        assertEquals(channels(), browseChannels()); assertNotSame(channels(), browseChannels()); assertFalse(field("iptvGuideUsesZapWindow") as Boolean)
        assertEquals(channels(), adapter().entriesSnapshot())
        assertEquals("2 items", (field("iptvGuideCountText") as TextView).text.toString())
    }

    @Test fun fallbackEmptyRowsUsesSelectedAndUrlMismatchDoesNotReplace() {
        val selected = channels()[0]
        call("restoreIptvZapBootstrapFallback", arrayOf(IptvChannelEntry::class.java, listType), selected, emptyList<IptvChannelEntry>())
        assertEquals(1, channels().size); assertSame(selected, channels()[0]); assertEquals(0, selected.index); assertTrue(selected.isCurrent)
        val old = channels()
        call("restoreIptvZapBootstrapFallback", arrayOf(IptvChannelEntry::class.java, listType), selected.copy(url = "https://other.invalid"), emptyList<IptvChannelEntry>())
        assertSame(old, channels())
    }

    @Test fun browsePayloadPinsEveryExplicitArgumentAndBridgeAbsentLeavesOwnersUntouched() {
        call("requestIptvBrowse", arrayOf(stringType, stringType, stringType, stringType, stringType), "seriesEpisodes", "explicit query", "xtream-series://42", "Show", "Override")
        assertEquals(mapOf("action" to "seriesEpisodes", "query" to "explicit query", "channelUrl" to "xtream-series://42", "title" to "Show", "sourceId" to "Override", "contentType" to "live", "category" to "News"), args("requestIptvBrowse"))
        val before = listOf("iptvUiContextToken", "iptvBrowseToken", "iptvZapRequestToken", "iptvZapRequestInFlight", "iptvZapOwnsUiContext").associateWith { field(it) }
        val bridge = com.debrify.app.MainActivity.getAndroidTvPlayerChannel(); queue().add(1)
        try {
            com.debrify.app.MainActivity.setAndroidTvPlayerChannel(null); browse()
            assertEquals(before, before.keys.associateWith { field(it) }); assertEquals(listOf(1), queue().toList())
        } finally { com.debrify.app.MainActivity.setAndroidTvPlayerChannel(bridge) }
    }

    @Test fun browseAcceptedReplyPinsAllMetadataTitleFallbackAndNullResponse() {
        set("iptvGuideUsesZapWindow", true)
        browse(); reply(value = response("sourceId" to "Reply id", "sourceName" to "Reply name", "contentType" to "series", "selectedCategory" to "Movies", "title" to "Explicit title"))
        assertEquals("Reply id", field("iptvSourceId")); assertEquals("Reply name", field("iptvSourceName")); assertEquals("series", field("iptvContentType"))
        assertEquals("Movies", field("iptvSelectedCategory")); assertFalse(field("iptvGuideUsesZapWindow") as Boolean)
        assertEquals(browseChannels(), adapter().entriesSnapshot()); assertEquals("Explicit title", (field("iptvGuideTitle") as TextView).text.toString())
        call("requestIptvBrowse", arrayOf(stringType, stringType, stringType, stringType, stringType), "browse", "", null, "Request title", null)
        reply(value = emptyMap<String, Any?>())
        assertEquals("Request title", (field("iptvGuideTitle") as TextView).text.toString()); assertTrue(browseChannels().isEmpty())
        assertEquals("Reply id", field("iptvSourceId")); assertEquals("Movies", field("iptvSelectedCategory"))
        val old = browseChannels(); browse(); reply(value = null)
        assertSame(old, browseChannels()); assertEquals(View.GONE, (field("iptvBrowseLoading") as View).visibility)
        browse(); reply("error", message = "Provider detail")
        assertEquals("Provider detail", ShadowToast.getTextOfLatestToast())
    }

    @Test fun browseEmptySourceAndTypeAreAcceptedButEmptyCategoryPreservesSelection() {
        browse(); reply(value = response("sourceId" to "", "sourceName" to "", "contentType" to "", "selectedCategory" to ""))
        assertEquals("", field("iptvSourceId")); assertEquals("", field("iptvSourceName")); assertEquals("", field("iptvContentType"))
        assertEquals("News", field("iptvSelectedCategory")); assertEquals("", (field("iptvSourceButton") as TextView).text.toString())
        assertEquals("Live television", (field("iptvGuideTitle") as TextView).text.toString())
    }

    @Test fun browseDefaultPinsEmptyMissingSearchAndTrimmedTextAtCallTime() {
        val box = search()
        for ((text, expected) in listOf("" to "", "  first  " to "first", " second " to "second")) {
            box.setText(text); browseDefault()
            assertEquals(expected, args("requestIptvBrowse")["query"])
        }
        set("iptvGuideSearch", null)
        try {
            browseDefault()
            assertEquals("", args("requestIptvBrowse")["query"])
        } finally {
            set("iptvGuideSearch", box)
        }
    }

}
