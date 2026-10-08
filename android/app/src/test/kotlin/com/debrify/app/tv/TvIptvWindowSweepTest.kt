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
internal class TvIptvWindowSweepTest : TvPhase11OriginalTest() {
    private fun window(n: Int = 30, offset: Int = 200, current: Int = 15, total: Int = 1_000) {
        val entries = MutableList(n) { i -> channel(url = "https://window.invalid/$i").copy(name = "Row $i", index = offset + i, isCurrent = i == current, logoUrl = null) }
        set("iptvChannels", entries); set("iptvBrowseChannels", entries.toMutableList()); adapter().updateChannels(entries)
        set("currentIptvIndex", current); set("iptvZapPagingActive", true); set("iptvZapCategoryTotal", total)
        set("iptvZapOwnsUiContext", true); set("iptvZapRequestInFlight", false); set("iptvGuideUsesZapWindow", true)
        set("iptvZapCategory", "News"); set("iptvZapCategories", mutableListOf("News", "Movies", "Sports"))
        clearTransport()
    }
    private fun seedCache() {
        set("iptvZapCachedOriginCategory", "News"); set("iptvZapCachedDirection", -1)
        set("iptvZapCachedChannels", mutableListOf(channel().copy(logoUrl = null)))
        set("iptvZapCachedOffset", 40); set("iptvZapCachedTotal", 42)
        set("iptvZapCachedCategory", "Movies"); set("iptvZapCachedCategories", listOf("News", "Movies"))
    }
    private fun emptyCache() {
        assertNull(field("iptvZapCachedOriginCategory")); assertEquals(0, field("iptvZapCachedDirection"))
        assertTrue((field("iptvZapCachedChannels") as List<*>).isEmpty())
        assertEquals(0, field("iptvZapCachedOffset")); assertEquals(0, field("iptvZapCachedTotal"))
        assertNull(field("iptvZapCachedCategory")); assertEquals(emptyList<String>(), field("iptvZapCachedCategories"))
    }
    private fun merge(entries: MutableList<IptvChannelEntry>, offset: Int, total: Int = 1_500,
                      category: String? = "News", categories: List<String> = listOf("News", "New")) =
        call("mergeIptvZapPage", arrayOf(MutableList::class.java, intType, intType, stringType, listType), entries, offset, total, category, categories)

    @Test fun installPublishesEveryOwnerAndUiAndClearsOnlyChangedCategoryCache() {
        window(n = 2, offset = 0, current = 1, total = 2); seedCache()
        set("iptvCategories", mutableListOf("Before install"))
        val playing = channels()[1]
        call("showIptvZapBanner", arrayOf(IptvChannelEntry::class.java, boolType), playing, false)
        val entries = mutableListOf(playing.copy(isCurrent = false))
        (field("iptvGuideCurrentName") as TextView).text = "Wrong"
        (field("iptvGuideCountText") as TextView).text = "Wrong"
        set("iptvGuideUsesZapWindow", false)
        install(entries, 40, 50, "Movies")
        emptyCache(); assertSame(entries, channels()); assertNotSame(entries, browseChannels())
        assertEquals(entries, browseChannels()); assertEquals(entries, adapter().entriesSnapshot())
        assertEquals("Movies", field("iptvZapCategory")); assertEquals("Movies", field("iptvSelectedCategory"))
        assertEquals(50, field("iptvZapCategoryTotal")); assertEquals(listOf("News", "Movies"), field("iptvZapCategories"))
        assertEquals(listOf("News", "Movies"), field("iptvCategories")); assertEquals(0, field("currentIptvIndex"))
        assertTrue(field("iptvGuideUsesZapWindow") as Boolean); assertEquals(40, entries[0].index); assertTrue(entries[0].isCurrent)
        assertEquals(playing.displayName, (field("iptvGuideCurrentName") as TextView).text.toString())
        assertEquals("50 items", (field("iptvGuideCountText") as TextView).text.toString())
        assertSame(entries[0], field("iptvZapBannerEntry"))
        assertTrue((field("iptvZapBannerMeta") as TextView).text.toString().contains("41 of 50"))
        seedCache(); val cache = field("iptvZapCachedChannels")
        install(entries.toMutableList(), 40, 50, "Movies")
        assertSame("same category retains prefetched neighbor", cache, field("iptvZapCachedChannels"))
    }

    @Test fun installEmptyCategoriesRetainsBothListsAndFalsePreserveCheckpointsBeforeReplacement() {
        val outgoing = channel(live = false).copy(resumePositionMs = 1_000, logoUrl = null)
        set("iptvChannels", mutableListOf(outgoing)); set("currentIptvIndex", 0)
        val zapCategories = mutableListOf("Zap retained"); val categories = mutableListOf("Browse retained")
        set("iptvZapCategories", zapCategories); set("iptvCategories", categories)
        val incoming = mutableListOf(outgoing.copy(isCurrent = true), channel(url = "https://incoming.invalid").copy(isCurrent = true, logoUrl = null))
        call("installIptvZapWindow", arrayOf(MutableList::class.java, intType, intType, stringType, listType, boolType), incoming, 20, 99, null, emptyList<String>(), false)
        assertEquals(25_000L, outgoing.resumePositionMs); assertEquals(listOf(false, false), incoming.map { it.isCurrent })
        assertEquals(listOf(20, 21), incoming.map { it.index }); assertEquals(0, field("currentIptvIndex"))
        assertSame(zapCategories, field("iptvZapCategories")); assertSame(categories, field("iptvCategories"))
        assertNull(field("iptvSelectedCategory")); assertNull(field("iptvZapCategory"))
    }

    @Test fun installPlayingFallbackPinsNullAndNameMismatchAndEmptyWindow() {
        val playing = channels()[0]
        val mismatch = mutableListOf(playing.copy(name = "Changed", isCurrent = true), channel(url = "https://other.invalid").copy(isCurrent = true, logoUrl = null))
        install(mismatch)
        assertEquals(listOf(true, false), channels().map { it.isCurrent }); assertEquals(0, field("currentIptvIndex"))
        set("currentIptvIndex", 99)
        val noPlaying = mutableListOf(channel().copy(isCurrent = false, logoUrl = null))
        install(noPlaying); assertTrue(noPlaying[0].isCurrent)
        install(mutableListOf()); assertEquals(0, field("currentIptvIndex")); assertEquals(0, adapter().itemCount)
    }

    @Test fun mergePublishesBothCategoryListsCopiesBrowseAndRefreshesAdapterAndBanner() {
        window(n = 3, current = 1)
        val playing = channels()[1]
        call("showIptvZapBanner", arrayOf(IptvChannelEntry::class.java, boolType), playing, false)
        val replacement = playing.copy(isCurrent = false)
        val page = mutableListOf(replacement, channel(url = "https://merged.invalid").copy(name = "Merged", logoUrl = null))
        set("iptvGuideUsesZapWindow", false); (field("iptvGuideCountText") as TextView).text = "Wrong"
        merge(page, 201)
        assertEquals(listOf(200, 201, 202), channels().map { it.index }); assertSame(replacement, channels()[1])
        assertEquals(listOf(false, true, false), channels().map { it.isCurrent }); assertEquals(1, field("currentIptvIndex"))
        assertEquals(1_500, field("iptvZapCategoryTotal")); assertEquals(listOf("News", "New"), field("iptvZapCategories"))
        assertEquals(listOf("News", "New"), field("iptvCategories")); assertNotSame(field("iptvZapCategories"), field("iptvCategories"))
        assertEquals(channels(), browseChannels()); assertNotSame(channels(), browseChannels())
        assertEquals(channels(), adapter().entriesSnapshot()); assertTrue(field("iptvGuideUsesZapWindow") as Boolean)
        assertEquals("1500 items", (field("iptvGuideCountText") as TextView).text.toString())
        assertSame(replacement, field("iptvZapBannerEntry"))
        assertTrue((field("iptvZapBannerMeta") as TextView).text.toString().contains("202 of " + String.format(java.util.Locale.getDefault(), "%,d", 1_500)))
    }

    @Test fun mergeGuardsInactivePagingAndPreservesEmptyCategoryListsAndNameIdentity() {
        window(n = 2, current = 1); val old = channels()
        set("iptvZapPagingActive", false); merge(mutableListOf(channel()), 50)
        assertSame(old, channels()); assertEquals(1_000, field("iptvZapCategoryTotal"))
        set("iptvZapPagingActive", true)
        val categories = field("iptvCategories"); val zapCategories = field("iptvZapCategories")
        merge(mutableListOf(old[1].copy(name = "Renamed", isCurrent = true)), 201, categories = emptyList())
        assertEquals(listOf(false, false), channels().map { it.isCurrent }); assertEquals(0, field("currentIptvIndex"))
        assertSame(categories, field("iptvCategories")); assertSame(zapCategories, field("iptvZapCategories"))
    }

    @Test fun mergeSortsAbsolutePositionsAcrossHashBucketBoundary() {
        window(n = 3, offset = 63, current = 1)
        merge(mutableListOf(channels()[1].copy()), 64)
        assertEquals("absolute positions remain sorted across 63/64", listOf(63, 64, 65), channels().map { it.index })
        assertEquals(1, field("currentIptvIndex"))
    }

    @Test fun mergeBoundsHiddenWindowAndRecomputesCurrentAndAdapterPositions() {
        window(n = 800, offset = 0, current = 400)
        merge(mutableListOf(), 800)
        assertEquals(600, channels().size); assertEquals(100, channels().first().index); assertEquals(699, channels().last().index)
        assertEquals(300, field("currentIptvIndex")); assertEquals(channels(), browseChannels()); assertEquals(channels(), adapter().entriesSnapshot())
    }

    @Test fun hiddenBoundsPinSixHundredInclusiveAndBothClampEdges() {
        for ((current, expectedStart) in listOf(0 to 0, 299 to 0, 300 to 0, 400 to 100, 799 to 200)) {
            window(n = 800, offset = 0, current = current)
            val all = channels(); val bounded = call("boundedHiddenIptvZapWindow", arrayOf(MutableList::class.java), all) as List<*>
            assertEquals(600, bounded.size); assertEquals(expectedStart, (bounded.first() as IptvChannelEntry).index)
            assertEquals(expectedStart + 599, (bounded.last() as IptvChannelEntry).index); assertNotSame(all, bounded)
        }
        window(n = 600, offset = 0); val all = channels()
        assertSame(all, call("boundedHiddenIptvZapWindow", arrayOf(MutableList::class.java), all))
        window(n = 601, offset = 0); channels().forEach { it.isCurrent = false }
        val bounded = call("boundedHiddenIptvZapWindow", arrayOf(MutableList::class.java), channels()) as List<*>
        assertEquals(0, (bounded.first() as IptvChannelEntry).index); assertEquals(600, bounded.size)
    }

    @Test fun trimUpdatesCurrentBrowseAndOnlyWindowAdapterAndGuardsVisibleGuide() {
        for (windowAdapter in listOf(false, true)) {
            window(n = 800, offset = 0, current = 400); val adapterBefore = adapter().entriesSnapshot()
            set("iptvGuideUsesZapWindow", windowAdapter)
            call("trimHiddenIptvZapWindow", emptyArray())
            assertEquals(600, channels().size); assertEquals(300, field("currentIptvIndex"))
            assertEquals(channels(), browseChannels()); assertNotSame(channels(), browseChannels())
            assertEquals(if (windowAdapter) channels() else adapterBefore, adapter().entriesSnapshot())
        }
        window(n = 800); set("iptvGuideVisible", true); val before = channels()
        call("trimHiddenIptvZapWindow", emptyArray()); assertSame(before, channels())
        set("iptvGuideVisible", false); set("iptvZapPagingActive", false)
        call("trimHiddenIptvZapWindow", emptyArray()); assertSame(before, channels())
        window(n = 600); val small = channels(); call("trimHiddenIptvZapWindow", emptyArray()); assertSame(small, channels())
    }

    @Test fun prefetchGuardsPagingFlightEmptyAndBackwardAbsoluteOffset() {
        window(); set("iptvZapPagingActive", false); prefetch(1, true); assertTrue(messenger.requests.isEmpty())
        set("iptvZapPagingActive", true); set("iptvZapRequestInFlight", true); prefetch(1, true); assertTrue(messenger.requests.isEmpty())
        set("iptvZapRequestInFlight", false); set("iptvChannels", mutableListOf<IptvChannelEntry>()); prefetch(1, true); assertTrue(messenger.requests.isEmpty())
        window(offset = 450, current = 0); prefetch(-1, true); assertEquals(250, args("requestIptvBrowse")["offset"])
        window(offset = 0, current = 0); prefetch(-1, true); assertTrue(messenger.requests.isEmpty())
    }

    @Test fun prefetchCallbackMergesMetadataAndDrainsPendingInput() {
        window(n = 30, current = 18); prefetch(1)
        queue().add(-1)
        reply(value = response("channels" to listOf(rawChannel("New", 99)), "pageOffset" to 230,
            "totalChannels" to 231, "categories" to listOf("News", "New")))
        assertEquals(31, channels().size); assertEquals(231, field("iptvZapCategoryTotal"))
        assertEquals(listOf("News", "New"), field("iptvZapCategories")); assertTrue(queue().isEmpty())
        assertEquals("drain selects previous row after merge", 17, field("currentIptvIndex"))
    }

    @Test fun clearAndDisableResetEveryCacheFieldAndReplaceBorrowedLists() {
        seedCache(); val borrowed = field("iptvZapCachedChannels") as List<*>
        call("clearIptvZapBoundaryCache", emptyArray()); emptyCache()
        assertEquals(1, borrowed.size); assertNotSame(borrowed, field("iptvZapCachedChannels"))
        seedCache(); val token = field("iptvZapRequestToken") as Int
        set("iptvZapPagingActive", true); set("iptvZapRequestInFlight", true); queue().add(1)
        call("disableIptvZapPaging", emptyArray()); emptyCache()
        assertEquals(token + 1, field("iptvZapRequestToken")); assertFalse(field("iptvZapPagingActive") as Boolean)
        assertFalse(field("iptvZapRequestInFlight") as Boolean); assertTrue(queue().isEmpty())
    }

    @Test fun jumpPinsPayloadMetadataClampsBothSourcesAndBothContentOwners() {
        set("iptvZapSourceId", "Lookup source"); set("iptvContentType", "vod"); set("iptvZapContentType", "series")
        set("iptvZapOwnsUiContext", false); set("iptvZapPagingActive", false)
        val token = field("iptvZapRequestToken") as Int
        jump(7)
        assertEquals(token + 1, field("iptvZapRequestToken")); assertTrue(field("iptvZapRequestInFlight") as Boolean)
        assertEquals(mapOf("action" to "channelNumber", "sourceId" to "Lookup source", "contentType" to "live", "channelNumber" to 7, "limit" to 200), args("requestIptvBrowse"))
        reply(value = response("sourceId" to "New id", "sourceName" to "New name", "pageOffset" to -10,
            "totalChannels" to -20, "selectedCategory" to "Movies", "categories" to listOf("", 3, "Movies")))
        for (name in listOf("iptvSourceId", "iptvZapSourceId")) assertEquals("New id", field(name))
        for (name in listOf("iptvSourceName", "iptvZapSourceName")) assertEquals("New name", field(name))
        for (name in listOf("iptvContentType", "iptvZapContentType")) assertEquals("live", field(name))
        assertTrue(field("iptvZapOwnsUiContext") as Boolean); assertTrue(field("iptvZapPagingActive") as Boolean)
        assertEquals(0, channels()[0].index); assertEquals(0, field("iptvZapCategoryTotal"))
        assertEquals("Movies", field("iptvZapCategory")); assertEquals(listOf("Movies"), field("iptvCategories"))
        assertEquals(7, channels()[field("currentIptvIndex") as Int].channelNumber)
    }

    @Test fun jumpInvalidRepliesAndErrorKindsDrainPendingInputsAfterRetiringFlight() {
        for ((kind, value, expected) in listOf(
            Triple("success", null, "Channel 7 was not found"),
            Triple("success", response("channelNotFound" to true), "Channel 7 was not found"),
            Triple("success", response("channels" to listOf(rawChannel("Wrong", 9))), "Channel 7 was not found"),
            Triple("error", null, "detail"), Triple("missing", null, "Channel lookup is unavailable"))) {
            window(n = 2, offset = 0, current = 0, total = 2); set("iptvZapPagingActive", false)
            jump(); queue().add(1); reply(kind, value)
            assertEquals(expected, ShadowToast.getTextOfLatestToast()); assertFalse(field("iptvZapRequestInFlight") as Boolean)
            assertTrue("$kind drains queued zap", queue().isEmpty()); assertEquals(1, field("currentIptvIndex"))
        }
    }

    @Test fun jumpAbsentBridgeDoesNotTouchTokenOrFlight() {
        val bridge = com.debrify.app.MainActivity.getAndroidTvPlayerChannel(); val token = field("iptvZapRequestToken")
        try {
            com.debrify.app.MainActivity.setAndroidTvPlayerChannel(null); jump()
            assertEquals("Channel lookup is unavailable", ShadowToast.getTextOfLatestToast())
            assertEquals(token, field("iptvZapRequestToken")); assertFalse(field("iptvZapRequestInFlight") as Boolean)
        } finally { com.debrify.app.MainActivity.setAndroidTvPlayerChannel(bridge) }
    }

    @Test fun jumpEmptySourceMetadataRetainsBothOwnersAndEmptyCategoriesRetainLists() {
        set("iptvSourceId", "Browse id"); set("iptvZapSourceId", "Zap id")
        set("iptvSourceName", "Browse name"); set("iptvZapSourceName", "Zap name")
        val categories = field("iptvCategories"); val zapCategories = field("iptvZapCategories")
        jump(); reply(value = response("sourceId" to "", "sourceName" to "", "selectedCategory" to "", "categories" to emptyList<String>(), "totalChannels" to 1))
        assertEquals("Browse id", field("iptvSourceId")); assertEquals("Zap id", field("iptvZapSourceId"))
        assertEquals("Browse name", field("iptvSourceName")); assertEquals("Zap name", field("iptvZapSourceName"))
        assertNull(field("iptvZapCategory")); assertNull(field("iptvSelectedCategory"))
        assertSame(categories, field("iptvCategories")); assertSame(zapCategories, field("iptvZapCategories"))
    }

    @Test fun foundJumpPrefetchesForwardOrBackwardWhenForwardIsExhausted() {
        for ((total, expectedOffset) in listOf(100 to 42, 42 to 0)) {
            set("iptvZapRequestInFlight", false); clearTransport(); jump()
            reply(value = response("channels" to listOf(rawChannel("First", 3), rawChannel("Target", 7)), "pageOffset" to 40, "totalChannels" to total))
            assertEquals(2, requests("requestIptvBrowse").size)
            assertEquals("zapPage", args("requestIptvBrowse")["action"]); assertEquals(expectedOffset, args("requestIptvBrowse")["offset"])
        }
    }

    @Test fun foundJumpDrainsPendingInputAfterSelectingRequestedNumber() {
        jump(); queue().add(-1)
        reply(value = response("channels" to listOf(rawChannel("First", 3), rawChannel("Target", 7)), "totalChannels" to 2))
        assertTrue(queue().isEmpty()); assertEquals(0, field("currentIptvIndex")); assertEquals("First", channels()[0].name)
    }

    @Test fun pageAbsentAndEmptyMetadataKeepsBothOwnersAndDefaultsCallbackValues() {
        for (metadata in listOf(emptyMap<String, Any?>(), mapOf("sourceId" to "", "sourceName" to "", "contentType" to ""))) {
            set("iptvSourceId", "Browse"); set("iptvZapSourceId", "Zap")
            set("iptvSourceName", "Browse name"); set("iptvZapSourceName", "Zap name")
            set("iptvContentType", "vod"); set("iptvZapContentType", "live")
            var observed: List<Any?>? = null
            page { channels, offset, total, category, cats -> observed = listOf(channels.size, offset, total, category, cats) }
            reply(value = metadata + mapOf("selectedCategory" to "", "categories" to listOf("", 3, "Sports")))
            assertEquals(listOf(0, 0, 0, null, listOf("Sports")), observed)
            assertEquals("Browse", field("iptvSourceId")); assertEquals("Zap", field("iptvZapSourceId"))
            assertEquals("Browse name", field("iptvSourceName")); assertEquals("Zap name", field("iptvZapSourceName"))
            assertEquals("vod", field("iptvContentType")); assertEquals("live", field("iptvZapContentType"))
        }
    }

    @Test fun pageMissingAndWrongTypedKeysDefaultWithoutChangingOwners() {
        for (value in listOf(emptyMap<String, Any?>(), mapOf("channels" to 3, "pageOffset" to "bad", "totalChannels" to "bad",
            "selectedCategory" to 3, "categories" to 3, "sourceId" to 3, "sourceName" to 3, "contentType" to 3))) {
            var observed: List<Any?>? = null
            val owners = listOf("iptvSourceId", "iptvZapSourceId", "iptvSourceName", "iptvZapSourceName", "iptvContentType", "iptvZapContentType").associateWith { field(it) }
            page { ch, offset, total, category, categories -> observed = listOf(ch.size, offset, total, category, categories) }
            reply(value = value)
            assertEquals(listOf(0, 0, 0, null, emptyList<String>()), observed)
            assertEquals(owners, owners.keys.associateWith { field(it) })
        }
    }

    @Test fun pageStartIncrementsRequestTokenAndCapturesNonDefaultUiToken() {
        val token = field("iptvZapRequestToken") as Int
        set("iptvUiContextToken", 123)
        var delivered = false
        page { _, _, _, _, _ -> delivered = true }
        assertEquals(token + 1, field("iptvZapRequestToken"))
        assertEquals(123, field("iptvUiContextToken")); assertTrue(field("iptvZapRequestInFlight") as Boolean)
        reply()
        assertTrue("response matches the UI context captured at dispatch", delivered)
        assertFalse(field("iptvZapRequestInFlight") as Boolean)
    }

    @Test fun drainOffersReentrantGuardAndFifoUntilNewFlightAndAlwaysClearsFlag() {
        window(n = 3, offset = 0, current = 0, total = 3); set("iptvZapPagingActive", false)
        queue().add(1); queue().add(1)
        var observedReentrant = false
        probe.onEvent = {
            if (!observedReentrant) {
                observedReentrant = true
                assertTrue("draining flag set before zap", field("iptvZapDrainingInputs") as Boolean)
                val pending = queue().toList(); call("drainPendingIptvZapInputs", emptyArray())
                assertEquals("nested drain cannot consume", pending, queue().toList())
            }
        }
        call("drainPendingIptvZapInputs", emptyArray())
        // Live playback begins synchronously through channel-start; queued inputs also drain synchronously.
        assertTrue(queue().isEmpty()); assertEquals(2, field("currentIptvIndex"))
        assertTrue("live tune exercises the nested drain attempt", observedReentrant)
        assertFalse(field("iptvZapDrainingInputs") as Boolean)
        probe.onEvent = null
    }
}
