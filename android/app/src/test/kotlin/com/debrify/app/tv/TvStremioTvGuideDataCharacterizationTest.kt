package com.debrify.app.tv

import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStremioTvGuideDataCharacterizationTest : TvPhase7OriginalTest() {
    private fun unloaded(count: Int = 3) { init(*(0 until count).map { json("$it", data = false) }.toTypedArray()); range(0, count - 1) }
    private fun load() = invoke("requestGuideDataForVisibleChannels")
    private fun ids() = (requests("requestStremioTvGuideData").last().call.arguments as Map<*, *>)["channelIds"]

    @Test fun visibleRangePrefetchClipsAndExcludesLoadedOrLoadingWithoutNotifying() {
        unloaded(12); val lm = range(4, 5); channels()[2].hasGuideData = true; channels()[7].isLoadingGuideData = true
        val observer = TvPhase7AdapterObserver(); adapter().registerAdapterDataObserver(observer)
        load()
        assertEquals("prefetch extends three on each side", listOf("1", "3", "4", "5", "6", "8"), ids())
        assertTrue(channels()[1].isLoadingGuideData); assertFalse(channels()[0].isLoadingGuideData)
        assertTrue("loading does not notify or disturb focus", observer.events.isEmpty())
        load(); assertEquals(1, requests("requestStremioTvGuideData").size)
        messenger.success(null); pump(); lm.first = 0; lm.last = 0; load()
        assertEquals(listOf("0", "1", "3"), ids())
        messenger.success(null); pump(); lm.first = 11; lm.last = 11; load()
        assertEquals(listOf("8", "9", "10", "11"), ids())
        messenger.success(null); pump(); lm.first = RecyclerView.NO_POSITION; load()
        assertEquals("NO_POSITION never requests", 3, requests("requestStremioTvGuideData").size)
    }

    @Test fun successMergesAllFieldsWithTargetedPayloadUpdates() {
        unloaded(); val observer = TvPhase7AdapterObserver(); adapter().registerAdapterDataObserver(observer)
        load(); messenger.success(mapOf("0" to mapOf("nowPlaying" to mapOf("title" to "Now", "poster" to "", "year" to "2024",
            "rating" to 8, "slotEndMs" to 999L, "progress" to 0.3), "nextUp" to mapOf("title" to "Next", "poster" to "", "year" to "", "rating" to 7.5))))
        assertFalse("reply is asynchronous", channels()[0].hasGuideData); pump()
        val c = channels()[0]
        assertEquals(listOf("Now", null, "2024", 8.0, 999L, 0.3f, "Next", null, null, 7.5),
            listOf(c.nowPlayingTitle, c.nowPlayingPoster, c.nowPlayingYear, c.nowPlayingRating, c.nowPlayingSlotEndMs,
                c.nowPlayingProgress, c.nextUpTitle, c.nextUpPoster, c.nextUpYear, c.nextUpRating))
        assertTrue(c.hasGuideData); assertFalse(c.isLoadingGuideData)
        assertEquals(listOf("change:0:1:${StremioTvGuideAdapter.PAYLOAD_GUIDE_DATA}"), observer.events)
        assertEquals("Now (2024) ★ 8.0", text("stremioTvGuideCurrentTitle").text.toString())
        c.isLoadingGuideData = true; messenger.success(mapOf("0" to mapOf("nowPlaying" to emptyMap<String, Any>(), "nextUp" to emptyMap<String, Any>()))); pump()
        assertEquals(listOf(null, null, null, null, 0L, 0f, null, null, null, null),
            listOf(c.nowPlayingTitle, c.nowPlayingPoster, c.nowPlayingYear, c.nowPlayingRating, c.nowPlayingSlotEndMs,
                c.nowPlayingProgress, c.nextUpTitle, c.nextUpPoster, c.nextUpYear, c.nextUpRating))
    }

    @Test fun guideReplyStillAppliesAfterSwitchTokenAdvances() {
        unloaded(); load(); set("stremioTvSwitchToken", 900)
        messenger.success(mapOf("0" to mapOf("nowPlaying" to mapOf("title" to "late guide")))); pump()
        assertEquals("guide data has no switch-token guard", "late guide", channels()[0].nowPlayingTitle)
        assertTrue(channels()[0].hasGuideData); assertFalse(channels()[0].isLoadingGuideData)
    }

    @Test fun partialAndMalformedEntriesLeaveUnreturnedChannelsLoading() {
        unloaded(); load(); messenger.success(mapOf("0" to emptyMap<String, Any>(), "1" to "malformed", 3 to emptyMap<String, Any>(), "unknown" to emptyMap<String, Any>())); pump()
        assertTrue("valid empty map counts as loaded", channels()[0].hasGuideData)
        assertFalse(channels()[0].isLoadingGuideData)
        assertEquals(listOf(true, true), channels().drop(1).map { it.isLoadingGuideData })
        assertEquals(listOf(false, false), channels().drop(1).map { it.hasGuideData })
    }

    @Test fun whollyMalformedRepliesClearOnlyRequestedLoading() {
        unloaded(); channels()[2].hasGuideData = true; channels()[2].isLoadingGuideData = true
        load(); messenger.success("not a map"); pump()
        assertEquals("malformed whole reply cleans requested rows", listOf(false, false, true), channels().map { it.isLoadingGuideData })
        assertFalse(channels()[0].hasGuideData)
    }

    @Test fun nullBridgeLeavesGuideRowsLoadingAndSuppressesDuplicates() {
        unloaded(); MainActivity.setAndroidTvPlayerChannel(null); load(); load()
        assertEquals("null bridge retains loading state", listOf(true, true, true), channels().map { it.isLoadingGuideData })
        assertTrue(messenger.requests.isEmpty()); assertTrue(channels().none { it.hasGuideData })
    }

    @Test fun errorNotImplementedAndSendExceptionCleanLoading() {
        unloaded()
        for (kind in listOf("error", "notImplemented", "throw")) {
            messenger.throwOnSend = kind == "throw"; load()
            if (kind == "error") messenger.error()
            if (kind == "notImplemented") messenger.notImplemented()
            pump()
            assertEquals("$kind clears requested rows", listOf(false, false, false), channels().map { it.isLoadingGuideData })
            assertTrue(channels().none { it.hasGuideData })
        }
    }
}

internal class TvPhase7AdapterObserver : RecyclerView.AdapterDataObserver() {
    val events = mutableListOf<String>()
    override fun onChanged() { events.add("all") }
    override fun onItemRangeChanged(positionStart: Int, itemCount: Int, payload: Any?) {
        events.add("change:$positionStart:$itemCount:$payload")
    }
}
