package com.debrify.app.tv

import android.view.View
import androidx.media3.common.Player
import com.debrify.app.MainActivity
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
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvIptvChannelStartCharacterizationTest : TvPhase5OriginalTest() {
    @Test fun watchRegistrationPinsPayloadAndReplyBeforeFallbackStartsExactlyOnce() {
        val entry = iptv(channel(live = false)); invoke("beginIptvPlaybackAfterWatchRegistration", entry)
        assertEquals(mapOf("url" to entry.url, "name" to "Cinema", "logoUrl" to entry.logoUrl, "group" to "Movies",
            "sourceId" to "playlist", "httpHeaders" to entry.httpHeaders, "seriesId" to "series", "seriesName" to "Show",
            "season" to 2, "episode" to 4, "hasNextEpisode" to true), messenger.requests.single().call.arguments)
        assertTrue(tuning().isEmpty()); advance(1999); assertTrue(tuning().isEmpty())
        messenger.success(null, 0); idle(); assertEquals(listOf("media:${entry.url}:12345"), tuning())
        advance(1); assertEquals(1, tuning().size)
    }

    @Test fun fallbackAtTwoSecondsAndErrorMissingOrLateRepliesStillStartOnlyOnce() {
        val entry = iptv(channel(live = false)); invoke("beginIptvPlaybackAfterWatchRegistration", entry)
        advance(1999); assertTrue(tuning().isEmpty()); advance(1); assertEquals(1, tuning().size)
        messenger.success(null, 0); idle(); assertEquals(1, tuning().size)
        invoke("beginIptvPlaybackAfterWatchRegistration", entry); val error = requestIndex("recordIptvWatch")
        messenger.error(error); idle(); assertEquals(2, tuning().size); advance(2000); assertEquals(2, tuning().size)
        invoke("beginIptvPlaybackAfterWatchRegistration", entry); val missing = requestIndex("recordIptvWatch")
        messenger.notImplemented(missing); idle(); assertEquals(3, tuning().size); advance(2000); assertEquals(3, tuning().size)
    }

    @Test fun watchTokenAndChangedChannelRejectSupersededRepliesAndFallbacks() {
        val first = iptv(channel(live = false)); invoke("beginIptvPlaybackAfterWatchRegistration", first); val old = requestIndex("recordIptvWatch")
        val second = iptv(channel("https://phase5.invalid/second.mp4", live = false)); invoke("beginIptvPlaybackAfterWatchRegistration", second)
        messenger.success(null, old); idle(); assertTrue(tuning().isEmpty())
        messenger.success(null); idle(); assertEquals(listOf("media:${second.url}:12345"), tuning()); advance(2000); assertEquals(1, tuning().size)
        invoke("beginIptvPlaybackAfterWatchRegistration", second); val sameOld = requestIndex("recordIptvWatch")
        invoke("beginIptvPlaybackAfterWatchRegistration", second); val sameNew = requestIndex("recordIptvWatch")
        messenger.success(null, sameOld); idle(); assertEquals("same-channel old token is still stale", 1, tuning().size)
        messenger.success(null, sameNew); idle(); advance(2000); assertEquals(2, tuning().size)
        invoke("beginIptvPlaybackAfterWatchRegistration", second); val changed = requestIndex("recordIptvWatch")
        iptv(first); messenger.success(null, changed); idle(); advance(2000); assertEquals(2, tuning().size)
    }

    @Test fun liveAndMissingBridgeBypassWatchRoundtripAndHonorPreferredTwin() {
        val entry = iptv(); @Suppress("UNCHECKED_CAST") val twins = field("iptvTwinPreferredUrls") as MutableMap<String, String>
        twins[entry.url] = "https://phase5.invalid/twin.ts"
        invoke("beginIptvPlaybackAfterWatchRegistration", entry)
        assertTrue(requests("recordIptvWatch").isEmpty()); assertEquals(listOf("media:https://phase5.invalid/twin.ts"), tuning())
        MainActivity.setAndroidTvPlayerChannel(null); val vod = iptv(channel("https://phase5.invalid/vod.mp4", live = false)); invoke("beginIptvPlaybackAfterWatchRegistration", vod)
        assertEquals("media:${vod.url}:12345", tuning().last())
    }

    @Test fun liveMemoryWaitsOneSecondDedupesPauseResumeAndPinsFallbackSourcePayload() {
        val entry = iptv(channel().copy(sourceId = null)); set("iptvSourceId", "launch-owner")
        invoke("noteLiveChannelPlaying"); val first = field("lastLiveChannelRunnable")
        advance(500); probe.playing = false; invoke("noteLiveChannelPlaying"); assertSame(first, field("lastLiveChannelRunnable"))
        probe.playing = true; advance(499); assertTrue(requests("noteIptvLiveChannel").isEmpty()); advance(1)
        assertEquals("settle callback at exact deadline", 1, requests("noteIptvLiveChannel").size)
        assertEquals(mapOf("url" to entry.url, "name" to "Cinema", "sourceId" to "launch-owner", "channelNumber" to 7,
            "group" to "Movies", "logoUrl" to entry.logoUrl, "httpHeaders" to entry.httpHeaders), requests("noteIptvLiveChannel").single().call.arguments)
        assertNull(field("lastLiveChannelRunnable"))
    }

    @Test fun liveMemoryZapsSupersedeAndReReadPlaybackAndChannelEligibility() {
        val first = iptv(); invoke("noteLiveChannelPlaying"); advance(500)
        val second = iptv(channel("https://phase5.invalid/second.ts")); invoke("noteLiveChannelPlaying")
        advance(500); assertTrue(requests("noteIptvLiveChannel").isEmpty()); advance(500)
        assertEquals(second.url, (requests("noteIptvLiveChannel").single().call.arguments as Map<*, *>)["url"])
        invoke("noteLiveChannelPlaying"); probe.playing = false; advance(1000); assertEquals(1, requests("noteIptvLiveChannel").size)
        iptv(first); invoke("noteLiveChannelPlaying"); iptv(channel(live = false)); advance(1000)
        assertEquals(1, requests("noteIptvLiveChannel").size); invoke("noteLiveChannelPlaying"); assertNull(field("lastLiveChannelRunnable"))
        set("isIptvMode", false); iptv(first); set("isIptvMode", false); invoke("noteLiveChannelPlaying"); assertNull(field("lastLiveChannelRunnable"))
    }

    @Test fun beginClearsOldLadderAndUrlBeforeStopAndAsynchronousResolution() {
        val entry = iptv(channel("stremio-tv://phase5/one")); set("currentIptvStreamUrl", "old")
        set("iptvStremioChannelKey", "old-key"); set("iptvStremioCandidates", listOf(IptvStremioCandidate("old-url", "Old")))
        set("iptvStremioCandidateIndex", 3); set("iptvStremioWinnerReported", true)
        @Suppress("UNCHECKED_CAST") val sources = field("stremioSources") as MutableList<StremioSource>
        sources.add(StremioSource.fromJson(org.json.JSONObject().put("name", "Old"), 0))
        set("stremioSourceBadge", View(activity).apply { visibility = View.VISIBLE })
        invoke("armIptvStremioStallWatchdog")
        val oldToken = field("iptvStremioToken") as Int
        probe.onEvent = { if (it == "stop") {
            assertNull(field("currentIptvStreamUrl")); assertNull(field("iptvStremioChannelKey"))
            assertEquals(emptyList<IptvStremioCandidate>(), field("iptvStremioCandidates")); assertEquals(0, field("iptvStremioCandidateIndex"))
            assertEquals(false, field("iptvStremioWinnerReported")); assertNull(field("iptvStremioStallRunnable"))
            assertTrue(sources.isEmpty()); assertEquals(View.GONE, (field("stremioSourceBadge") as View).visibility)
            assertEquals(oldToken + 1, field("iptvStremioToken"))
        } }
        messenger.onSend = { if (it.call.method == "requestIptvStreamUrls") assertEquals(listOf("stop"), probe.events) }
        invoke("beginIptvPlayback", entry)
        assertEquals(mapOf("channelUrl" to entry.url, "channelName" to entry.name), requests("requestIptvStreamUrls").single().call.arguments)
        assertTrue(tuning().isEmpty())
    }

    @Test fun resolveSupersessionAndFinishingGuardRejectLateCandidates() {
        val first = iptv(channel("stremio-tv://phase5/first")); invoke("beginIptvPlayback", first); val old = requestIndex("requestIptvStreamUrls")
        val second = iptv(channel("stremio-tv://phase5/second")); invoke("beginIptvPlayback", second)
        messenger.success(mapOf("candidates" to listOf(mapOf("url" to "https://phase5.invalid/old.ts", "label" to "old"))), old); idle()
        assertTrue(tuning().isEmpty()); assertNull(field("iptvStremioChannelKey"))
        activity.finish(); resolve("https://phase5.invalid/new.ts"); assertTrue(tuning().isEmpty())
    }

    @Test fun emptyResolveKeepsStoppedStateAndUsesProviderMessageOrChannelFallback() {
        val entry = iptv(channel("stremio-tv://phase5/empty")); invoke("beginIptvPlayback", entry)
        messenger.success(mapOf("candidates" to emptyList<Any>(), "message" to "Addon unavailable")); idle()
        assertTrue(tuning().isEmpty()); assertNull(field("iptvStremioChannelKey")); assertEquals("Addon unavailable", ShadowToast.getTextOfLatestToast())
        invoke("beginIptvPlayback", entry); messenger.success(emptyMap<String, Any>()); idle()
        assertEquals("Cinema is not playable right now", ShadowToast.getTextOfLatestToast())
    }

    @Test fun candidateOrderMirrorsSourceRowsAdvancesSilentlyAndPreservesEscapeHatchAfterExhaustion() {
        val entry = iptv(channel("stremio-tv://phase5/ladder")); invoke("beginIptvPlayback", entry)
        resolve("https://phase5.invalid/a.ts", "https://phase5.invalid/b.ts")
        @Suppress("UNCHECKED_CAST") val sources = field("stremioSources") as List<StremioSource>
        assertEquals(listOf("https://phase5.invalid/a.ts", "https://phase5.invalid/b.ts"), sources.map { it.directUrl })
        assertEquals(listOf(0, 1), sources.map { it.index }); assertEquals(listOf("1 1080p", "2 1080p"), sources.map { it.name })
        assertEquals(listOf("media:https://phase5.invalid/a.ts"), tuning())
        assertEquals(true, invoke("tryNextIptvStremioCandidate")); assertEquals(1, field("iptvStremioCandidateIndex")); assertEquals(1, field("currentStremioSourceIndex"))
        assertEquals("media:https://phase5.invalid/b.ts", tuning().last()); assertTrue(requests("reportIptvStreamResult").isEmpty())
        assertEquals(true, invoke("tryNextIptvStremioCandidate"))
        assertEquals(mapOf("channelUrl" to entry.url, "url" to null, "success" to false), requests("reportIptvStreamResult").single().call.arguments)
        assertEquals("Cinema: tried all 2 sources, none played — pick one in Sources to retry", ShadowToast.getTextOfLatestToast())
        assertEquals(entry.url, field("iptvStremioChannelKey")); assertEquals(2, sources.size); assertNull(field("iptvStremioStallRunnable"))
    }

    @Test fun singleSourceExhaustionHasSingularToastAndMissingKeyNeverClaimsError() {
        assertEquals(false, invoke("tryNextIptvStremioCandidate"))
        val entry = iptv(channel("stremio-tv://phase5/single")); invoke("beginIptvPlayback", entry); resolve("https://phase5.invalid/a.ts")
        assertEquals(true, invoke("tryNextIptvStremioCandidate"))
        assertEquals("Cinema: its only source didn't play — pick it in Sources to retry", ShadowToast.getTextOfLatestToast())
        set("iptvStremioCandidates", emptyList<IptvStremioCandidate>()); assertEquals(false, invoke("tryNextIptvStremioCandidate"))
    }

    @Test fun stallDeadlineIsTwentySecondsAndTokenIndexWinnerAndLivenessAreReRead() {
        val entry = iptv(channel("stremio-tv://phase5/stall")); invoke("beginIptvPlayback", entry)
        resolve("https://phase5.invalid/a.ts", "https://phase5.invalid/b.ts")
        val old = field("iptvStremioStallRunnable") as Runnable
        advance(19_999); assertEquals(0, field("iptvStremioCandidateIndex")); advance(1); assertEquals(1, field("iptvStremioCandidateIndex"))
        old.run(); assertEquals(1, field("iptvStremioCandidateIndex")); assertTrue(requests("reportIptvStreamResult").isEmpty())
        val current = field("iptvStremioStallRunnable") as Runnable
        set("iptvStremioToken", (field("iptvStremioToken") as Int) + 1); current.run(); assertTrue(requests("reportIptvStreamResult").isEmpty())
        invoke("armIptvStremioStallWatchdog"); set("iptvStremioWinnerReported", true)
        (field("iptvStremioStallRunnable") as Runnable).run(); assertTrue(requests("reportIptvStreamResult").isEmpty())
        set("iptvStremioWinnerReported", false); activity.finish(); advance(20_000); assertTrue(requests("reportIptvStreamResult").isEmpty())
    }

    @Test fun winnerReportsExactlyOnceAndManualSourceSwitchRearmsLadderAndOutcomeWatcher() {
        val entry = iptv(channel("stremio-tv://phase5/winner")); invoke("beginIptvPlayback", entry)
        resolve("https://phase5.invalid/a.ts", "https://phase5.invalid/b.ts")
        invoke("reportIptvStremioWinnerIfNeeded"); invoke("reportIptvStremioWinnerIfNeeded")
        assertEquals("winner reports once", 1, requests("reportIptvStreamResult").size)
        assertEquals(mapOf("channelUrl" to entry.url, "url" to "https://phase5.invalid/a.ts", "success" to true), requests("reportIptvStreamResult").single().call.arguments)
        assertNull(field("iptvStremioStallRunnable")); advance(20_000); assertEquals(1, requests("reportIptvStreamResult").size)
        call("switchToIptvStremioSource", arrayOf(stringType, intType), "https://phase5.invalid/b.ts", 1)
        assertEquals(false, field("iptvStremioWinnerReported")); assertEquals(1, field("iptvStremioCandidateIndex"))
        assertEquals(1, field("currentStremioSourceIndex")); assertNotNull(field("iptvStremioStallRunnable")); assertNotNull(field("sourceSwitchReadyListener"))
        invoke("reportIptvStremioWinnerIfNeeded"); assertEquals("https://phase5.invalid/b.ts", (requests("reportIptvStreamResult").last().call.arguments as Map<*, *>)["url"])
        invoke("clearIptvStremioSources"); assertEquals(emptyList<StremioSource>(), field("stremioSources")); assertEquals(0, field("currentStremioSourceIndex"))
    }
}
