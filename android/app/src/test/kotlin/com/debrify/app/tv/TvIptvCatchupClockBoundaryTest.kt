package com.debrify.app.tv

import android.os.SystemClock
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowSystem
import org.robolectric.shadows.ShadowSystemClock
import org.robolectric.shadows.ShadowToast
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], instrumentedPackages = [
    "com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
    "com.debrify.app.tv.TvIptvStartOverController",
    "com.debrify.app.tv.IptvEntryRulesKt",
])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvCatchupClockBoundaryTest : TvPhase5OriginalTest() {
    private val now = 1_000_000L

    @Before fun controlWallClock() {
        assertTrue(SystemClock.setCurrentTimeMillis(now))
        assertEquals("instrumented System.currentTimeMillis uses paused clock", now, ShadowSystem.currentTimeMillis())
    }

    private fun programmeAt(start: Long, stop: Long) =
        IptvEpgProgram("Boundary programme", null, start, stop, true)

    @Test fun futureStartOneMillisecondAheadDoesNotRequestOrMutateLoadingAndToken() {
        val entry = iptv()
        val token = field("iptvCatchupToken")
        catchup(entry, programmeAt(now + 1, now + 60_000), true)
        assertEquals("future programme is rejected", 0, requests("requestIptvCatchup").size)
        assertEquals(token, field("iptvCatchupToken"))
        assertEquals(false, field("iptvStartOverLoading"))
    }

    @Test fun exactStartIsRequestedAsAiringWithLoadingAndOriginalStartPayload() {
        val entry = iptv()
        catchup(entry, programmeAt(now, now + 60_000), true)
        assertEquals("programme starting exactly now is requested", 1, requests("requestIptvCatchup").size)
        val map = requests("requestIptvCatchup").single().call.arguments as Map<*, *>
        assertEquals(now, map["startMs"])
        assertEquals(true, map["startOver"])
        assertEquals(true, field("iptvStartOverLoading"))
        assertEquals("Preparing start over…", ShadowToast.getTextOfLatestToast())
    }

    @Test fun startOneMillisecondAgoIsStillRequestedAsAiring() {
        val entry = iptv()
        catchup(entry, programmeAt(now - 1, now + 60_000), true)
        assertEquals("past start remains eligible", 1, requests("requestIptvCatchup").size)
        assertEquals(now - 1, (requests("requestIptvCatchup").single().call.arguments as Map<*, *>)["startMs"])
        assertEquals(true, field("iptvStartOverLoading"))
    }

    private fun requestAndReplyAtStop(stop: Long, airing: Boolean, advanceBeforeReply: Boolean = false) {
        val entry = iptv()
        catchup(entry, programmeAt(now - 60_000, stop), true)
        assertEquals(1, requests("requestIptvCatchup").size)
        assertEquals("stop boundary selects start-over versus replay", airing,
            (requests("requestIptvCatchup").single().call.arguments as Map<*, *>)["startOver"])
        assertEquals(airing, field("iptvStartOverLoading"))
        assertEquals(if (airing) "Preparing start over…" else "Preparing replay…", ShadowToast.getTextOfLatestToast())
        if (advanceBeforeReply) ShadowSystemClock.advanceBy(Duration.ofMillis(2))
        messenger.success(mapOf("url" to "https://phase5.invalid/boundary.mp4"))
        idle()
        assertEquals("airing is captured at request time", airing, field("iptvStartOverActive"))
        assertEquals(false, field("iptvStartOverLoading"))
        @Suppress("UNCHECKED_CAST") val selected = (field("iptvChannels") as List<IptvChannelEntry>).single()
        assertEquals(airing, selected.isLive)
        assertEquals(listOf("media:https://phase5.invalid/boundary.mp4"), tuning())
    }

    @Test fun exactStopIsPastReplayWithoutStartOverLoadingOrLiveFlags() {
        requestAndReplyAtStop(now, false)
    }

    @Test fun stopOneMillisecondAheadIsAiringEvenWhenReplyArrivesAfterStop() {
        requestAndReplyAtStop(now + 1, true, advanceBeforeReply = true)
    }

    @Test fun stopOneMillisecondAgoIsPastReplay() {
        requestAndReplyAtStop(now - 1, false)
    }
}
