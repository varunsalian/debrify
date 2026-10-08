package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvReplyAndSwitchSweepTest : TvPhase11OriginalTest() {
    @Test fun nullPageClearsPendingInputsBeforeFailureInlineAndQueued() {
        for (queued in listOf(false, true)) {
            set("iptvZapOwnsUiContext", true)
            queue().add(1)
            var failed = 0
            page(failure = {
                assertTrue("null page clears inputs before invoking failure", queue().isEmpty())
                assertFalse("failure sees request retired", field("iptvZapRequestInFlight") as Boolean)
                failed++
            }) { _, _, _, _, _ -> fail("null page must not load") }
            reply(value = null, queued = queued)
            if (queued) { assertEquals(0, failed); idle() }
            assertEquals(1, failed)
            assertTrue(queue().isEmpty())
        }
    }

    @Test fun foundJumpPublishesBothSourceNamesInlineAndQueued() {
        for (queued in listOf(false, true)) {
            set("iptvSourceName", "Browse old")
            set("iptvZapSourceName", "Zap old")
            jump()
            reply(value = response("sourceName" to "Reply provider", "totalChannels" to 1), queued = queued)
            if (queued) idle()
            assertEquals("jump updates browser source name", "Reply provider", field("iptvSourceName"))
            assertEquals("jump updates playback source name", "Reply provider", field("iptvZapSourceName"))
            assertEquals("Reply provider", (field("iptvSourceButton") as TextView).text.toString())
            set("iptvZapRequestInFlight", false)
        }
    }

    @Test fun absentJumpTotalFallsBackToReturnedChannelCount() {
        jump()
        reply(value = mapOf("channels" to listOf(rawChannel("First", 3), rawChannel("Target", 7)),
            "pageOffset" to 0, "selectedCategory" to "News"))
        assertEquals("absent jump total uses page size", 2, field("iptvZapCategoryTotal"))
        assertEquals(2, channels().size)
        assertEquals(1, field("currentIptvIndex"))
        assertEquals("2 items", call("iptvGuideItemCountLabel", emptyArray()))
    }

    @Test fun absentPageTotalFallsBackToReturnedChannelCount() {
        var total: Int? = null
        page { entries, offset, count, _, _ ->
            assertEquals(2, entries.size)
            assertEquals(0, offset)
            total = count
        }
        reply(value = mapOf("channels" to listOf(rawChannel("First", 3), rawChannel("Target", 7))))
        assertEquals("absent zap-page total uses page size", 2, total)
    }

    @Test fun browseInvalidatesZapTokenAndRetiresPendingInputsBeforeDispatch() {
        var loaded = 0
        page { _, _, _, _, _ -> loaded++ }
        val oldRequest = messenger.requests.lastIndex
        val oldToken = field("iptvZapRequestToken") as Int
        val oldUiToken = field("iptvUiContextToken") as Int
        val oldBrowseToken = field("iptvBrowseToken") as Int
        queue().add(-1)
        (field("iptvBrowseLoading") as View).visibility = View.GONE
        browse()
        assertEquals("browse invalidates resolver generation", oldToken + 1, field("iptvZapRequestToken"))
        assertEquals(oldUiToken + 1, field("iptvUiContextToken"))
        assertEquals(oldBrowseToken + 1, field("iptvBrowseToken"))
        assertEquals(View.VISIBLE, (field("iptvBrowseLoading") as View).visibility)
        assertFalse(field("iptvZapRequestInFlight") as Boolean)
        assertFalse(field("iptvZapOwnsUiContext") as Boolean)
        assertTrue(queue().isEmpty())
        set("iptvZapRequestInFlight", true)
        reply(request = oldRequest)
        assertTrue("old reply cannot clear newer in-flight work", field("iptvZapRequestInFlight") as Boolean)
        assertEquals(0, loaded)
    }

    @Test fun selectedBrowseRetainsCategoriesButAllCategoryBrowseReplacesThem() {
        val original = listOf("News", "Movies")
        set("iptvCategories", original.toMutableList())
        browse()
        reply(value = response("categories" to listOf("Unexpected", "", 3)))
        assertEquals("selected category retains available siblings", original, field("iptvCategories"))
        set("iptvSelectedCategory", null)
        browse()
        reply(value = response("selectedCategory" to "", "categories" to listOf("", 3, "Sports")))
        assertEquals(listOf("Sports"), field("iptvCategories"))
        assertNull(field("iptvSelectedCategory"))
    }

    @Test fun queuedSearchRefocusHonoursGuideVisibilityAtExecutionTime() {
        show(); idle()
        assertTrue(search().requestFocus())
        browse()
        reply(value = response("channels" to emptyList<Any>()))
        val other = activity.findViewById<View>(com.debrify.app.R.id.iptv_source_button)
        assertTrue(other.requestFocus())
        set("iptvGuideVisible", false)
        idle()
        assertFalse("closed guide does not steal focus back into search", search().hasFocus())
        assertTrue(other.hasFocus())
        set("iptvGuideVisible", true)
        search().requestFocus(); browse(); reply(value = response("channels" to emptyList<Any>()))
        other.requestFocus(); idle()
        assertTrue("visible guide preserves the submitted search focus", search().hasFocus())
    }

    @Test fun switchWithoutCheckpointPreservesOutgoingResume() {
        val old = channel(live = false).copy(logoUrl = null, resumePositionMs = 8_000)
        val next = channel(url = "https://next.invalid", live = false).copy(logoUrl = null, resumePositionMs = 9_000)
        set("iptvChannels", mutableListOf(old, next)); set("currentIptvIndex", 0)
        probe.position = 25_000; probe.duration = 100_000
        switch(next, checkpoint = false)
        assertEquals("false checkpoint preserves the outgoing resume", 8_000L, old.resumePositionMs)
        assertEquals(9_000L, next.resumePositionMs)
        assertEquals(1, field("currentIptvIndex"))
    }

    @Test fun liveSwitchShowsBannerAndVodSwitchHidesIt() {
        val live = channel().copy(logoUrl = null)
        val vod = channel(url = "https://vod.invalid", live = false).copy(logoUrl = null)
        set("iptvChannels", mutableListOf(live, vod)); set("currentIptvIndex", 0)
        switch(live)
        assertSame(live, field("iptvZapBannerEntry"))
        assertEquals(View.VISIBLE, (field("iptvZapBanner") as View).visibility)
        switch(vod)
        assertNull("VOD clears the live-banner entry", field("iptvZapBannerEntry"))
        advance(200)
        assertEquals("VOD hides live banner", View.GONE, (field("iptvZapBanner") as View).visibility)
    }

    @Test fun channelKeysZapSingleLoadedChannelWhenPagingActive() {
        set("iptvChannels", mutableListOf(channels().first()))
        set("currentIptvIndex", 0); set("iptvZapPagingActive", true); set("iptvZapCategoryTotal", 20)
        assertTrue(key(KeyEvent.KEYCODE_CHANNEL_UP))
        assertEquals("single-page channel still queues forward zap", listOf(1), queue().toList())
        assertEquals("zapPage", args("requestIptvBrowse")["action"])
        assertEquals(1, args("requestIptvBrowse")["offset"])
    }

    @Test fun inWindowZapPrefetchesAdjacentCategoryAtEnd() {
        set("iptvZapPagingActive", true); set("iptvZapCategoryTotal", 2)
        set("iptvZapCategory", "News"); set("iptvZapCategories", mutableListOf("News", "Movies"))
        set("currentIptvIndex", 0)
        key(KeyEvent.KEYCODE_CHANNEL_UP)
        assertEquals(1, field("currentIptvIndex"))
        assertEquals("in-window zap prepares the next category", "Movies", args("requestIptvBrowse")["category"])
        assertEquals(false, args("requestIptvBrowse")["fromEnd"])
    }
}
