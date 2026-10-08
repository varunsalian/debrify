package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.recyclerview.widget.RecyclerView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvIptvNavigatorSweepTest : TvPhase11OriginalTest() {
    private fun window(n: Int = 2, offset: Int = 0, current: Int = n - 1, total: Int = n) {
        val entries = MutableList(n) { i -> channel(url = "https://navigate.invalid/$i").copy(name = "Row $i", index = offset + i, isCurrent = i == current, logoUrl = null) }
        set("iptvChannels", entries); set("iptvBrowseChannels", entries.toMutableList()); adapter().updateChannels(entries)
        set("currentIptvIndex", current); set("iptvZapPagingActive", true); set("iptvZapCategoryTotal", total)
        set("iptvZapOwnsUiContext", true); set("iptvZapRequestInFlight", false); set("iptvGuideUsesZapWindow", true)
        set("iptvZapCategory", "News"); set("iptvZapCategories", mutableListOf("News", "Movies", "Sports"))
        set("iptvZapCachedChannels", mutableListOf<IptvChannelEntry>()); queue().clear(); clearTransport()
    }
    private fun adjacent(delta: Int, attempt: Int = 1) = call("prefetchAdjacentIptvCategory", arrayOf(intType, intType), delta, attempt)
    private fun requestAdjacent(delta: Int, attempt: Int = 1) = call("requestAdjacentIptvCategory", arrayOf(intType, intType), delta, attempt)
    private fun cached(delta: Int = 1): MutableList<IptvChannelEntry> {
        val cached = mutableListOf(channel(url = "https://cache.invalid/0").copy(name = "Cache first", logoUrl = null), channel(url = "https://cache.invalid/1").copy(name = "Cache last", logoUrl = null))
        set("iptvZapCachedOriginCategory", "News"); set("iptvZapCachedDirection", delta)
        set("iptvZapCachedChannels", cached); set("iptvZapCachedOffset", 45); set("iptvZapCachedTotal", 47)
        set("iptvZapCachedCategory", "Movies"); set("iptvZapCachedCategories", listOf("Movies", "Sports"))
        return cached
    }

    @Test fun adjacentCategoryPinsNullEmptyAttemptZeroAndUnknownOriginFallback() {
        set("iptvZapCategory", null); assertNull(call("adjacentIptvCategory", arrayOf(intType, intType), 1, 1))
        set("iptvZapCategory", "Unknown"); set("iptvZapCategories", mutableListOf<String>())
        assertNull(call("adjacentIptvCategory", arrayOf(intType, intType), 1, 1))
        set("iptvZapCategories", mutableListOf("News", "Movies", "Sports", "News"))
        assertNull(call("adjacentIptvCategory", arrayOf(intType, intType), 1, 0))
        assertEquals("Movies", call("adjacentIptvCategory", arrayOf(intType, intType), 1, 1))
        assertEquals("Sports", call("adjacentIptvCategory", arrayOf(intType, intType), -1, 1))
        assertEquals("Sports", call("adjacentIptvCategory", arrayOf(intType, intType), 1, 2))
    }

    @Test fun adjacentPrefetchGuardsEachOwnerAndBoundaryOperandAndDropsOppositeCache() {
        for (guard in listOf("inactive", "flight", "uncategorized", "cache", "notAbsoluteEnd", "notNearEnd", "notAbsoluteStart", "notNearStart")) {
            val backward = guard.endsWith("Start")
            window(n = 30, offset = if (backward) 0 else 70, current = if (backward) 0 else 29, total = 100)
            when (guard) {
                "inactive" -> set("iptvZapPagingActive", false)
                "flight" -> set("iptvZapRequestInFlight", true)
                "uncategorized" -> set("iptvZapCategory", null)
                "cache" -> cached()
                "notAbsoluteEnd" -> set("iptvZapCategoryTotal", 101)
                "notNearEnd" -> set("currentIptvIndex", 17)
                "notAbsoluteStart" -> channels()[0].index = 1
                "notNearStart" -> set("currentIptvIndex", 12)
            }
            adjacent(if (backward) -1 else 1)
            assertTrue("$guard suppresses adjacent page", requests("requestIptvBrowse").isEmpty())
        }
        window(); val opposite = cached(-1); set("iptvZapPagingActive", false)
        adjacent(1)
        assertEquals(2, opposite.size); assertTrue((field("iptvZapCachedChannels") as List<*>).isEmpty())
        assertNull(field("iptvZapCachedOriginCategory")); assertEquals(0, field("iptvZapCachedDirection"))
        assertEquals(0, field("iptvZapCachedOffset")); assertEquals(0, field("iptvZapCachedTotal"))
        assertNull(field("iptvZapCachedCategory")); assertTrue((field("iptvZapCachedCategories") as List<*>).isEmpty())
    }

    @Test fun adjacentPrefetchPinsBothInclusiveDistanceBoundariesAndRequestDirection() {
        window(n = 30, offset = 70, current = 18, total = 100)
        adjacent(1); assertEquals("Movies", args("requestIptvBrowse")["category"])
        assertEquals(0, args("requestIptvBrowse")["offset"]); assertEquals(false, args("requestIptvBrowse")["fromEnd"])
        window(n = 30, offset = 0, current = 11, total = 100)
        adjacent(-1); assertEquals("Sports", args("requestIptvBrowse")["category"]); assertEquals(true, args("requestIptvBrowse")["fromEnd"])
    }

    @Test fun adjacentReplyStoresEveryCacheFieldAndRecursesAcrossEmptyCategory() {
        window(); adjacent(1)
        reply(value = response("channels" to emptyList<Any>(), "selectedCategory" to "Movies"))
        assertEquals("Sports", args("requestIptvBrowse")["category"])
        reply(value = response("channels" to listOf(rawChannel("Cached", 8)), "pageOffset" to 40,
            "totalChannels" to 41, "selectedCategory" to "Sports", "categories" to listOf("News", "Sports")))
        assertEquals("News", field("iptvZapCachedOriginCategory")); assertEquals(1, field("iptvZapCachedDirection"))
        val cached = field("iptvZapCachedChannels") as List<*>
        assertEquals(1, cached.size); assertEquals("Cached", (cached.single() as IptvChannelEntry).name)
        assertEquals(40, field("iptvZapCachedOffset")); assertEquals(41, field("iptvZapCachedTotal"))
        assertEquals("Sports", field("iptvZapCachedCategory")); assertEquals(listOf("News", "Sports"), field("iptvZapCachedCategories"))
        assertEquals("News", field("iptvZapCategory")); assertEquals("Row 1", channels()[1].name)
    }

    @Test fun adjacentReplyDrainsBoundaryInputIntoCachedDestination() {
        window(); adjacent(1); queue().add(1)
        reply(value = response("channels" to listOf(rawChannel("Destination", 8)), "totalChannels" to 1,
            "selectedCategory" to "Movies", "categories" to listOf("Movies")))
        assertTrue(queue().isEmpty()); assertEquals("Destination", channels()[field("currentIptvIndex") as Int].name)
        assertEquals("Movies", field("iptvZapCategory"))
    }

    @Test fun consumeCachePinsDetachedWindowOffsetCategoriesAndFirstVsLast() {
        for (delta in listOf(1, -1)) {
            window(); val old = cached(delta)
            assertEquals(true, call("consumeCachedAdjacentIptvCategory", arrayOf(intType), delta))
            assertNotSame("consumer detaches list before clear", old, channels()); assertEquals(2, old.size)
            assertEquals(listOf(45, 46), channels().map { it.index }); assertEquals(47, field("iptvZapCategoryTotal"))
            assertEquals("Movies", field("iptvZapCategory")); assertEquals(listOf("Movies", "Sports"), field("iptvCategories"))
            assertEquals(if (delta > 0) 0 else 1, field("currentIptvIndex"))
            assertEquals(channels()[if (delta > 0) 0 else 1].displayName, (field("titleView") as TextView).text.toString())
            assertTrue((field("iptvZapCachedChannels") as List<*>).isEmpty())
            assertTrue("consume starts subsequent page/adjacent prefetch", requests("requestIptvBrowse").isNotEmpty())
        }
    }

    @Test fun consumeCacheRejectsWrongOriginAndEmptyCacheWithoutChangingPlayback() {
        window(); cached(); set("iptvZapCachedOriginCategory", "Other"); val old = channels()
        assertEquals(false, call("consumeCachedAdjacentIptvCategory", arrayOf(intType), 1)); assertSame(old, channels())
        set("iptvZapCachedOriginCategory", "News"); set("iptvZapCachedChannels", mutableListOf<IptvChannelEntry>())
        assertEquals(false, call("consumeCachedAdjacentIptvCategory", arrayOf(intType), 1)); assertSame(old, channels())
    }

    @Test fun consumeSameCategoryCacheStillClearsItsOwnMetadata() {
        window(); cached(); set("iptvZapCachedCategory", "News")
        assertEquals(true, call("consumeCachedAdjacentIptvCategory", arrayOf(intType), 1))
        assertEquals("News", field("iptvZapCategory"))
        assertTrue((field("iptvZapCachedChannels") as List<*>).isEmpty())
        assertNull(field("iptvZapCachedOriginCategory")); assertEquals(0, field("iptvZapCachedDirection"))
        assertEquals(0, field("iptvZapCachedOffset")); assertEquals(0, field("iptvZapCachedTotal"))
        assertNull(field("iptvZapCachedCategory")); assertTrue((field("iptvZapCachedCategories") as List<*>).isEmpty())
    }

    @Test fun requestAdjacentFlightQueuesAndExhaustedAttemptsClearWithoutRequest() {
        window(); set("iptvZapRequestInFlight", true); requestAdjacent(-1)
        assertEquals(listOf(-1), queue().toList()); assertTrue(messenger.requests.isEmpty())
        set("iptvZapRequestInFlight", false)
        set("iptvZapCategories", mutableListOf("News", "Movies", "News"))
        requestAdjacent(1, 3)
        assertTrue(queue().isEmpty()); assertTrue(messenger.requests.isEmpty())
        requestAdjacent(1, 0); assertTrue(messenger.requests.isEmpty())
    }

    @Test fun requestAdjacentRecursesEmptyThenInstallsAndDrainsForBothDirections() {
        for (delta in listOf(1, -1)) {
            window(); requestAdjacent(delta)
            assertEquals(if (delta > 0) "Movies" else "Sports", args("requestIptvBrowse")["category"])
            reply(value = response("channels" to emptyList<Any>()))
            assertEquals(if (delta > 0) "Sports" else "Movies", args("requestIptvBrowse")["category"])
            queue().add(0)
            reply(value = response("channels" to listOf(rawChannel("First", 8), rawChannel("Last", 9)),
                "selectedCategory" to "Movies", "pageOffset" to 0, "totalChannels" to 2,
                "categories" to listOf("Movies")))
            assertEquals("Movies", field("iptvZapCategory")); assertEquals(listOf(0, 1), channels().map { it.index })
            assertEquals(if (delta > 0) 0 else 1, field("currentIptvIndex")); assertTrue(queue().isEmpty())
            assertEquals(channels()[if (delta > 0) 0 else 1].displayName, (field("titleView") as TextView).text.toString())
        }
    }

    @Test fun requestAdjacentUncategorizedWrapInstallsFirstOrLastAndIgnoresEmptyReply() {
        for (delta in listOf(1, -1)) {
            window(); set("iptvZapCategory", null); set("iptvZapCategories", mutableListOf<String>())
            requestAdjacent(delta)
            assertNull(args("requestIptvBrowse")["category"]); assertEquals(delta < 0, args("requestIptvBrowse")["fromEnd"])
            reply(value = response("channels" to listOf(rawChannel("First", 8), rawChannel("Last", 9)), "totalChannels" to 2,
                "selectedCategory" to "", "categories" to emptyList<String>()))
            assertEquals(listOf("First", "Last"), channels().map { it.name })
            assertEquals(listOf("https://phase11.invalid/8", "https://phase11.invalid/9"), channels().map { it.url })
            assertEquals(if (delta > 0) 0 else 1, field("currentIptvIndex"))
            assertEquals(if (delta > 0) "CH 8  First" else "CH 9  Last", (field("titleView") as TextView).text.toString())
        }
        window(); set("iptvZapCategory", null); val old = channels(); requestAdjacent(1)
        reply(value = response("channels" to emptyList<Any>()))
        assertSame(old, channels())
    }

    @Test fun adjacentReplyStartsNormalPrefetchInBothDirectionsForCategorizedAndAllChannels() {
        for (categorized in listOf(false, true)) for (delta in listOf(1, -1)) {
            window()
            if (!categorized) { set("iptvZapCategory", null); set("iptvZapCategories", mutableListOf<String>()) }
            requestAdjacent(delta)
            reply(value = response("channels" to listOf(rawChannel("First", 8), rawChannel("Last", 9)), "pageOffset" to 40,
                "totalChannels" to 100, "selectedCategory" to if (categorized) "Movies" else "", "categories" to emptyList<String>()))
            assertEquals(2, requests("requestIptvBrowse").size)
            assertEquals(if (delta > 0) 42 else 0, args("requestIptvBrowse")["offset"])
            assertEquals(if (categorized) "Movies" else null, args("requestIptvBrowse")["category"])
        }
    }

    @Test fun adjacentReplyAtCategoryEdgeStartsAdjacentPrefetchWithoutQueuedInputs() {
        for (delta in listOf(1, -1)) {
            window(); requestAdjacent(delta)
            reply(value = response("channels" to listOf(rawChannel("First", 8), rawChannel("Last", 9)), "totalChannels" to 2,
                "selectedCategory" to "Movies", "categories" to listOf("News", "Movies", "Sports")))
            assertEquals(2, requests("requestIptvBrowse").size)
            assertEquals(if (delta > 0) "Sports" else "News", args("requestIptvBrowse")["category"])
            assertEquals(delta < 0, args("requestIptvBrowse")["fromEnd"])
        }
    }

    @Test fun uncategorizedAdjacentReplyDrainsQueuedForwardInputIntoLastReturnedRow() {
        window(); set("iptvZapCategory", null); set("iptvZapCategories", mutableListOf<String>())
        requestAdjacent(1); queue().add(1)
        reply(value = response("channels" to listOf(rawChannel("First", 8), rawChannel("Last", 9)), "totalChannels" to 2,
            "selectedCategory" to "", "categories" to emptyList<String>()))
        assertTrue(queue().isEmpty()); assertEquals(1, field("currentIptvIndex")); assertEquals("Last", channels()[1].name)
    }

    @Test fun activateContextPublishesAllPlaybackOwnersCopiesListsAndInvalidatesAllTokens() {
        window(); set("iptvZapOwnsUiContext", false); set("iptvZapRequestInFlight", true)
        set("iptvSourceId", "Browse id"); set("iptvSourceName", "Browse name"); set("iptvContentType", "vod")
        set("iptvZapSourceId", "Playing id"); set("iptvZapSourceName", "Playing name"); set("iptvZapContentType", "live")
        set("iptvSelectedCategory", "Wrong"); set("iptvCategories", mutableListOf("Wrong"))
        set("iptvBrowseChannels", mutableListOf<IptvChannelEntry>()); adapter().updateChannels(emptyList())
        set("iptvGuideUsesZapWindow", false); search().setText("stale")
        val before = listOf("iptvUiContextToken", "iptvBrowseToken", "iptvZapRequestToken").associateWith { field(it) as Int }
        call("activateIptvZapUiContext", emptyArray())
        before.forEach { (name, value) -> assertEquals(name, value + 1, field(name)) }
        assertFalse(field("iptvZapRequestInFlight") as Boolean); assertTrue(field("iptvZapOwnsUiContext") as Boolean)
        assertEquals("Playing id", field("iptvSourceId")); assertEquals("Playing name", field("iptvSourceName"))
        assertEquals("live", field("iptvContentType")); assertEquals("News", field("iptvSelectedCategory"))
        assertEquals(field("iptvZapCategories"), field("iptvCategories")); assertNotSame(field("iptvZapCategories"), field("iptvCategories"))
        assertEquals("", search().text.toString()); assertEquals(channels(), browseChannels()); assertNotSame(channels(), browseChannels())
        assertTrue(field("iptvGuideUsesZapWindow") as Boolean); assertEquals(channels(), adapter().entriesSnapshot())
        assertEquals("Playing name", (field("iptvSourceButton") as TextView).text.toString())
        val activated = before.keys.associateWith { field(it) }
        set("iptvSourceName", "Already owned sentinel")
        call("activateIptvZapUiContext", emptyArray())
        assertEquals(activated, before.keys.associateWith { field(it) }); assertEquals("Already owned sentinel", field("iptvSourceName"))
    }

    @Test fun switchAdoptsVisibleRowsNormalizesIndicesAndNotifiesOldAndNewRows() {
        window(current = 0); val old = channels()[0]
        val selected = channel(url = "https://selected.invalid", live = false).copy(name = "Selected", index = 71, sourceId = "New", seriesId = "42", logoUrl = null)
        val sibling = selected.copy(name = "Sibling", url = "https://sibling.invalid", index = 90, isCurrent = true)
        adapter().updateChannels(mutableListOf(old, selected, sibling))
        val changes = mutableListOf<Int>()
        adapter().registerAdapterDataObserver(object : RecyclerView.AdapterDataObserver() {
            override fun onItemRangeChanged(start: Int, count: Int) { changes.add(start) }
        })
        set("subtitleSearchStatus", "Stale captions"); set("iptvSeriesAudioKey", "Old key")
        switch(selected)
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").any { it.msg == "switchToIptvChannel: Selected (index=71)" })
        assertEquals(listOf(0, 1, 2), channels().map { it.index }); assertEquals(listOf(false, true, false), channels().map { it.isCurrent })
        assertEquals(1, field("currentIptvIndex")); assertSame(selected, channels()[1])
        assertEquals(listOf(0, 1), changes); assertEquals("New::42", field("iptvSeriesAudioKey"))
        assertEquals("", field("subtitleSearchStatus")); assertEquals("Selected", (field("titleView") as TextView).text.toString())
        assertEquals(selected.displayName, (field("iptvGuideCurrentName") as TextView).text.toString())
        assertEquals("Previous", (field("iptvPrevButton") as TextView).text.toString())
        assertEquals(View.VISIBLE, (field("iptvPrevButton") as View).visibility)
        assertEquals(View.VISIBLE, (field("iptvNextButton") as View).visibility)
        assertEquals(selected.url, args("recordIptvWatch")["url"])
    }

    @Test fun switchAdoptionPinsUrlFallbackFirstFallbackAndAbsentAdapter() {
        val entry = channel().copy(url = "https://chosen.invalid", logoUrl = null)
        val matched = entry.copy(name = "Visible renamed", sourceId = null, seriesId = "series", index = 88)
        adapter().updateChannels(mutableListOf(matched)); switch(entry)
        assertSame(matched, channels()[0]); assertEquals("::series", field("iptvSeriesAudioKey"))
        val unmatched = entry.copy(url = "https://unmatched.invalid", seriesId = null)
        adapter().updateChannels(mutableListOf(unmatched)); switch(entry)
        assertSame(unmatched, channels()[0]); assertNull(field("iptvSeriesAudioKey"))
        set("iptvChannelAdapter", null); val last = entry.copy(url = "https://last.invalid", index = 94)
        switch(last)
        assertSame(last, channels()[0]); assertEquals(0, last.index); assertTrue(last.isCurrent)
    }

    @Test fun switchRetiresSourceWaitAndPillBeforeDeferredVodWatchRegistration() {
        call("showStatusPill", arrayOf(stringType), "Waiting for source")
        call("watchSourceSwitchOutcome", arrayOf(intType), 0)
        assertNotNull(field("sourceSwitchReadyListener")); assertNotNull(field("sourceSwitchTimeoutRunnable"))
        val vod = channel(live = false).copy(logoUrl = null)
        switch(vod, adopt = false)
        assertNull("switch immediately removes pending source listener", field("sourceSwitchReadyListener"))
        assertNull(field("sourceSwitchTimeoutRunnable"))
        assertTrue(requests("recordIptvWatch").isNotEmpty())
        advance(300)
        assertEquals(View.GONE, (field("statusPill") as View).visibility)
    }

    @Test fun liveZapContextPinsEveryOperandAndSingleChannelPaging() {
        window(n = 1, current = 0)
        assertEquals(true, call("isLiveIptvZapContext", emptyArray()))
        set("iptvZapPagingActive", false); assertEquals(false, call("isLiveIptvZapContext", emptyArray()))
        window(); set("isIptvMode", false); assertEquals(false, call("isLiveIptvZapContext", emptyArray()))
        set("isIptvMode", true); set("controlsMenuVisible", true); assertEquals(false, call("isLiveIptvZapContext", emptyArray()))
        set("controlsMenuVisible", false); channels()[1] = channels()[1].copy(isLive = false)
        assertEquals(false, call("isLiveIptvZapContext", emptyArray()))
        set("currentIptvIndex", 99); assertEquals(false, call("isLiveIptvZapContext", emptyArray()))
    }

    @Test fun zapGuardsMissingVodAndSingleUnpagedChannelBeforeAnyTune() {
        window(n = 1, current = 0); set("iptvZapPagingActive", false)
        call("zapIptvChannel", arrayOf(intType), 1)
        assertEquals(0, field("currentIptvIndex")); assertTrue(messenger.requests.isEmpty()); assertTrue(probe.events.isEmpty())
        channels()[0] = channels()[0].copy(isLive = false)
        set("iptvZapOwnsUiContext", false); val token = field("iptvUiContextToken")
        call("zapIptvChannel", arrayOf(intType), 1)
        assertEquals(token, field("iptvUiContextToken")); assertFalse(field("iptvZapOwnsUiContext") as Boolean)
        assertTrue(messenger.requests.isEmpty()); set("currentIptvIndex", 99)
        call("zapIptvChannel", arrayOf(intType), 1); assertEquals(token, field("iptvUiContextToken"))
    }

    @Test fun zapBoundaryQueuesPageInBothDirectionsAndUsesCachedOrUncachedCategory() {
        for (delta in listOf(1, -1)) {
            window(offset = 200, current = if (delta > 0) 1 else 0, total = 1_000)
            call("beginIptvAllCategorySearch", emptyArray())
            call("zapIptvChannel", arrayOf(intType), delta)
            assertFalse(field("iptvAllCategorySearchActive") as Boolean)
            assertTrue((field("iptvSearchSavedChannels") as List<*>).isEmpty())
            assertEquals(listOf(delta), queue().toList())
            assertEquals(if (delta > 0) 202 else 0, args("requestIptvBrowse")["offset"])
            window(current = if (delta > 0) 1 else 0); cached(delta)
            call("zapIptvChannel", arrayOf(intType), delta)
            assertEquals(if (delta > 0) "Cache first" else "Cache last", channels()[field("currentIptvIndex") as Int].name)
            window(current = if (delta > 0) 1 else 0)
            call("zapIptvChannel", arrayOf(intType), delta)
            assertEquals(if (delta > 0) "Movies" else "Sports", args("requestIptvBrowse")["category"])
        }
    }

    @Test fun realInWindowZapStartsPageAtBothTwelveRowEdges() {
        for (delta in listOf(1, -1)) {
            window(n = 30, offset = 200, current = if (delta > 0) 17 else 12, total = 1_000)
            assertTrue(key(if (delta > 0) android.view.KeyEvent.KEYCODE_CHANNEL_UP else android.view.KeyEvent.KEYCODE_CHANNEL_DOWN))
            assertEquals(if (delta > 0) 18 else 11, field("currentIptvIndex"))
            assertEquals("zapPage", args("requestIptvBrowse")["action"])
            assertEquals(if (delta > 0) 230 else 0, args("requestIptvBrowse")["offset"])
        }
    }

    @Test fun zapUsesRequestedBoundaryWhenOnlyOppositeDirectionHasMorePages() {
        for (delta in listOf(1, -1)) {
            window(offset = if (delta > 0) 200 else 0, current = if (delta > 0) 1 else 0, total = if (delta > 0) 202 else 1_000)
            call("zapIptvChannel", arrayOf(intType), delta)
            assertEquals(if (delta > 0) "Movies" else "Sports", args("requestIptvBrowse")["category"])
            assertTrue("exhausted requested direction uses category boundary rather than queuing a page", queue().isEmpty())
        }
    }

    @Test fun checkpointNoopsForMissingLivePlayerAndNonPositiveReads() {
        val entry = channel(live = false).copy(resumePositionMs = 8_000)
        set("iptvChannels", mutableListOf(entry)); set("currentIptvIndex", 99)
        call("checkpointCurrentIptvPosition", emptyArray()); assertEquals(8_000L, entry.resumePositionMs)
        set("currentIptvIndex", 0); entry.isCurrent = true
        for ((duration, position) in listOf(0L to 25_000L, -1L to 25_000L, 100_000L to 0L, 100_000L to -1L)) {
            probe.duration = duration; probe.position = position
            call("checkpointCurrentIptvPosition", emptyArray()); assertEquals(8_000L, entry.resumePositionMs)
        }
        set("player", null); call("checkpointCurrentIptvPosition", emptyArray()); assertEquals(8_000L, entry.resumePositionMs)
        set("player", probe.player); set("iptvChannels", mutableListOf(entry.copy(isLive = true)))
        probe.duration = 100_000L; probe.position = 25_000L
        call("checkpointCurrentIptvPosition", emptyArray()); assertEquals(8_000L, channels()[0].resumePositionMs)
    }

    @Test fun playChannelPinsLiveBannerSubtitleResetPlaybackAndBothIndexBounds() {
        window(current = 0); set("subtitleSearchStatus", "Stale")
        channels()[1] = channels()[1].copy(url = "https://long.invalid/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
        call("playIptvChannel", arrayOf(intType), 1)
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").any { it.msg == "playIptvChannel: Row 1 url=https://long.invalid/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" })
        assertEquals("", field("subtitleSearchStatus")); assertEquals(channels()[1].displayName, (field("titleView") as TextView).text.toString())
        assertTrue(tuning().any { it.contains(channels()[1].url) }); assertSame(channels()[1], field("iptvZapBannerEntry"))
        clearTransport()
        for (index in listOf(-1, 2)) call("playIptvChannel", arrayOf(intType), index)
        assertTrue(probe.events.isEmpty())
    }

    @Test fun episodeModePinsSessionSeriesLiveAndMissingIndexAndBothControls() {
        window(n = 3, current = 1); channels().indices.forEach { channels()[it] = channels()[it].copy(isLive = false) }
        channels()[2] = channels()[2].copy(isLive = true)
        assertEquals("episode mode reads the current row, not its live neighbour", true, call("isIptvEpisodeMode", emptyArray()))
        channels()[1] = channels()[1].copy(isLive = true)
        assertEquals(false, call("isIptvEpisodeMode", emptyArray()))
        assertNull(call("nextIptvEpisode", emptyArray())); assertNull(call("prevIptvEpisode", emptyArray()))
        channels()[1] = channels()[1].copy(isLive = false); channels()[2] = channels()[2].copy(isLive = false)
        assertEquals(true, call("isIptvEpisodeMode", emptyArray()))
        assertSame(channels()[2], call("nextIptvEpisode", emptyArray())); assertSame(channels()[0], call("prevIptvEpisode", emptyArray()))
        call("updateIptvEpisodeControls", emptyArray())
        assertEquals("Previous", (field("iptvPrevButton") as TextView).text.toString()); assertEquals("Next", (field("iptvNextButton") as TextView).text.toString())
        assertEquals(View.VISIBLE, (field("iptvPrevButton") as View).visibility); assertEquals(View.VISIBLE, (field("iptvNextButton") as View).visibility)
        assertEquals(View.GONE, (field("iptvGuideButton") as View).visibility)
        set("iptvSeriesAudioKey", null); assertEquals(false, call("isIptvEpisodeMode", emptyArray()))
        assertNull(call("nextIptvEpisode", emptyArray())); assertNull(call("prevIptvEpisode", emptyArray()))
        call("updateIptvEpisodeControls", emptyArray()); assertEquals(View.GONE, (field("iptvPrevButton") as View).visibility); assertEquals(View.GONE, (field("iptvNextButton") as View).visibility)
        set("iptvSeriesAudioKey", "series"); set("isIptvMode", false); assertEquals(false, call("isIptvEpisodeMode", emptyArray()))
        set("isIptvMode", true); set("currentIptvIndex", 99); assertEquals(false, call("isIptvEpisodeMode", emptyArray()))
    }

    @Test fun liveControlsPinSingleChannelPagingGateAndNonIptvEarlyReturn() {
        for ((n, paging, visibility) in listOf(Triple(1, false, View.GONE), Triple(1, true, View.VISIBLE), Triple(2, false, View.VISIBLE))) {
            window(n, current = 0); set("iptvZapPagingActive", paging)
            (field("iptvPrevButton") as TextView).text = "Before previous"
            (field("iptvNextButton") as TextView).text = "Before next"
            (field("iptvPrevButton") as View).visibility = View.INVISIBLE
            (field("iptvNextButton") as View).visibility = View.INVISIBLE
            call("updateIptvEpisodeControls", emptyArray())
            assertEquals("CH -", (field("iptvPrevButton") as TextView).text.toString()); assertEquals("CH +", (field("iptvNextButton") as TextView).text.toString())
            assertEquals(visibility, (field("iptvPrevButton") as View).visibility); assertEquals(visibility, (field("iptvNextButton") as View).visibility)
            assertEquals(View.VISIBLE, (field("iptvGuideButton") as View).visibility)
        }
        set("isIptvMode", false); (field("iptvPrevButton") as TextView).text = "Preserve"
        call("updateIptvEpisodeControls", emptyArray()); assertEquals("Preserve", (field("iptvPrevButton") as TextView).text.toString())
    }

    @Test fun missingCurrentEntryUsesPreviousNextLabelsAndNoEpisodeActions() {
        set("currentIptvIndex", 99)
        call("updateIptvEpisodeControls", emptyArray())
        assertEquals("Previous", (field("iptvPrevButton") as TextView).text.toString())
        assertEquals("Next", (field("iptvNextButton") as TextView).text.toString())
        assertEquals(View.GONE, (field("iptvPrevButton") as View).visibility)
        assertEquals(View.GONE, (field("iptvNextButton") as View).visibility)
    }

    @Test fun audioLanguageSetsSelectorVariantsAndPersistsAfterGuardedChoices() {
        val selector = field("trackSelector") as DefaultTrackSelector
        selector.parameters = selector.parameters.buildUpon().setPreferredTextLanguage("es").setMaxVideoSize(640, 480).build()
        call("setIptvPreferredAudioLang", arrayOf(stringType), "de")
        assertEquals(listOf("de", "de", "de", "german", "deutsch", "de-de", "de-at", "de-ch"), selector.parameters.preferredAudioLanguages.toList())
        assertEquals(listOf("es"), selector.parameters.preferredTextLanguages.toList())
        assertEquals(640, selector.parameters.maxVideoWidth); assertEquals(480, selector.parameters.maxVideoHeight)
        call("onIptvSeriesAudioPicked", arrayOf(stringType), "fr")
        assertEquals("fr", field("iptvPreferredAudioLang"))
        assertEquals(listOf("fr", "fr", "fr", "french", "français", "francais", "fr-fr", "fr-ca", "fr-be", "fr-ch"), selector.parameters.preferredAudioLanguages.toList())
        assertEquals(mapOf("seriesKey" to "provider::series", "lang" to "fr"), args("saveIptvSeriesAudio"))
        clearTransport(); set("iptvSeriesAudioKey", null)
        call("onIptvSeriesAudioPicked", arrayOf(stringType), "de")
        assertTrue(messenger.requests.isEmpty()); assertEquals("fr", field("iptvPreferredAudioLang"))
        set("trackSelector", null); call("setIptvPreferredAudioLang", arrayOf(stringType), "de")
        set("trackSelector", selector)
    }

    @Test fun audioPickWithoutBridgeStillUpdatesMemoryAndSelector() {
        val bridge = com.debrify.app.MainActivity.getAndroidTvPlayerChannel()
        try {
            com.debrify.app.MainActivity.setAndroidTvPlayerChannel(null)
            call("onIptvSeriesAudioPicked", arrayOf(stringType), "de")
            assertEquals("de", field("iptvPreferredAudioLang"))
            assertEquals(listOf("de", "de", "de", "german", "deutsch", "de-de", "de-at", "de-ch"),
                (field("trackSelector") as DefaultTrackSelector).parameters.preferredAudioLanguages.toList())
        } finally { com.debrify.app.MainActivity.setAndroidTvPlayerChannel(bridge) }
    }
}
