package com.debrify.app.tv

import android.view.View
import android.widget.FrameLayout
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
internal class TvIptvStartOverCharacterizationTest : TvPhase5OriginalTest() {
    @Test fun defaultButtonArgumentReadsCurrentEntryAtEachInvocationAndPinsEveryLabel() {
        val entry = iptv(); val p = programme()
        entry.epgNowTitle = p.title; entry.epgNowStartMs = p.startMs; entry.epgNowStopMs = p.stopMs; entry.epgNowHasArchive = true
        fun update() = defaultCall("updateIptvStartOverButton", arrayOf(IptvChannelEntry::class.java), 1, null)
        update(); assertEquals(View.VISIBLE, button().visibility); assertTrue(button().isEnabled)
        assertEquals("Start Over", button().text.toString()); assertEquals("Start programme from beginning", button().contentDescription)
        assertEquals(View.GONE, seekButton().visibility)
        set("iptvChannels", mutableListOf(entry, channel().copy(tvArchive = "0"))); set("currentIptvIndex", 1)
        update(); assertEquals(View.GONE, button().visibility)
        set("iptvStartOverActive", true); update(); assertEquals("Go Live", button().text.toString())
        assertEquals("Return to live channel", button().contentDescription); assertEquals(View.VISIBLE, seekButton().visibility)
        assertEquals("Seek", seekButton().text.toString()); assertEquals("Show start over timeline", seekButton().contentDescription)
        set("iptvStartOverLoading", true); update(); assertFalse(button().isEnabled); assertFalse(seekButton().isEnabled)
        assertEquals("Preparing…", button().text.toString()); assertEquals("Preparing start over", button().contentDescription)
        set("iptvStartOverTimelineVisible", true); invoke("updateIptvStartOverSeekButton")
        assertEquals("Hide Timeline", seekButton().text.toString()); assertEquals("Hide start over timeline", seekButton().contentDescription)
    }

    @Test fun catchupPayloadAndArchiveFutureMissingBridgeGuardsAreExact() {
        val entry = iptv(); val p = programme(); set("iptvGuideVisible", true)
        catchup(entry, p.copy(hasArchive = false)); catchup(entry, p.copy(startMs = System.currentTimeMillis() + 1))
        assertTrue(requests("requestIptvCatchup").isEmpty())
        catchup(entry, p)
        assertEquals(mapOf("channelUrl" to entry.url, "startMs" to p.startMs, "channelName" to "Cinema", "logoUrl" to entry.logoUrl,
            "playlistId" to "playlist", "httpHeaders" to entry.httpHeaders, "archiveDisabled" to false, "archiveEnabled" to true,
            "archiveDurationDays" to 3, "startOver" to true), requests("requestIptvCatchup").single().call.arguments)
        assertEquals(true, field("iptvStartOverLoading")); assertEquals("Preparing start over…", ShadowToast.getTextOfLatestToast())
        com.debrify.app.MainActivity.setAndroidTvPlayerChannel(null); val token = field("iptvCatchupToken")
        catchup(entry, p); assertEquals(token, field("iptvCatchupToken"))
    }

    @Test fun controlsReplyIgnoresGuideVisibilityAndEpgGenerationAndTunesArchiveWithRetainedFlags() {
        val entry = iptv(); set("iptvGuideVisible", false); val p = programme(); catchup(entry, p, true)
        set("iptvEpgToken", (field("iptvEpgToken") as Int) + 1)
        messenger.success(mapOf("url" to "https://phase5.invalid/archive.ts")); idle()
        assertEquals(false, field("iptvStartOverLoading")); assertEquals(true, field("iptvStartOverActive"))
        assertEquals(false, field("iptvStartOverTimelineVisible")); assertEquals(listOf("media:https://phase5.invalid/archive.ts"), tuning())
        assertEquals(entry.displayName, (field("titleView") as android.widget.TextView).text.toString())
        assertEquals("Go Live", button().text.toString()); assertEquals(View.VISIBLE, seekButton().visibility)
    }

    @Test fun guideReplyRequiresVisibleGuideAndSameScheduleAndClearsOnlyCurrentLoading() {
        val entry = iptv(); set("iptvGuideVisible", true); catchup(entry, programme()); set("iptvGuideVisible", false)
        messenger.success(mapOf("url" to "https://phase5.invalid/stale.ts")); idle()
        assertTrue(tuning().isEmpty()); assertEquals(false, field("iptvStartOverLoading"))
        set("iptvGuideVisible", true); catchup(entry, programme()); set("iptvEpgToken", (field("iptvEpgToken") as Int) + 1)
        messenger.success(mapOf("url" to "https://phase5.invalid/stale.ts")); idle()
        assertTrue(tuning().isEmpty()); assertEquals(false, field("iptvStartOverLoading"))
    }

    @Test fun catchupTokenSupersessionPreventsOldSuccessFromTuningOrClearingNewLoading() {
        val entry = iptv(); catchup(entry, programme(), true); val old = requestIndex("requestIptvCatchup")
        catchup(entry, programme(), true); val current = requestIndex("requestIptvCatchup")
        messenger.success(mapOf("url" to "https://phase5.invalid/old.ts"), old); idle()
        assertTrue(tuning().isEmpty()); assertEquals(true, field("iptvStartOverLoading"))
        messenger.success(mapOf("url" to "https://phase5.invalid/current.ts"), current); idle()
        assertEquals(listOf("media:https://phase5.invalid/current.ts"), tuning()); assertEquals(false, field("iptvStartOverLoading"))
    }

    @Test fun unavailableErrorAndMissingRepliesKeepFlagsAndPinMessages() {
        val entry = iptv()
        for (kind in 0..2) {
            catchup(entry, programme(), true)
            when (kind) { 0 -> messenger.success(emptyMap<String, Any>()); 1 -> messenger.error(); else -> messenger.notImplemented() }
            idle(); assertEquals(false, field("iptvStartOverLoading")); assertEquals(false, field("iptvStartOverActive"))
            assertEquals(if (kind == 1) "message" else "Replay is not available", ShadowToast.getTextOfLatestToast())
            assertTrue(tuning().isEmpty())
        }
    }

    @Test fun pastProgrammeBecomesVodReplayPreservingHeadersAndResumeWithDefaultGuideDispatch() {
        val entry = iptv(); val p = programme(airing = false); set("iptvGuideVisible", true)
        defaultCall("requestIptvCatchup", arrayOf(IptvChannelEntry::class.java, IptvEpgProgram::class.java, boolType), 4, entry, p, false)
        assertEquals(false, field("iptvStartOverLoading")); assertEquals("Preparing replay…", ShadowToast.getTextOfLatestToast())
        messenger.success(mapOf("url" to "https://phase5.invalid/replay.mp4", "title" to "Replay title", "resumePositionMs" to 7654L)); idle()
        @Suppress("UNCHECKED_CAST") val replay = (field("iptvChannels") as List<IptvChannelEntry>).single()
        assertFalse(replay.isLive); assertTrue(replay.isCurrent); assertEquals(0, replay.index); assertEquals("vod", replay.contentType)
        assertEquals("Replay title", replay.name); assertEquals(entry.name, replay.group); assertEquals(entry.httpHeaders, replay.httpHeaders)
        assertEquals(entry.logoUrl, replay.logoUrl); assertEquals(entry.sourceId, replay.sourceId); assertEquals(entry.sourceName, replay.sourceName)
        assertEquals(7654L, replay.resumePositionMs); assertEquals("media:https://phase5.invalid/replay.mp4:7654", tuning().last())
        assertEquals(0, field("currentIptvIndex")); assertNull(field("iptvSeriesAudioKey")); assertEquals(false, field("iptvGuideVisible"))
        assertEquals("Replay title", (field("titleView") as android.widget.TextView).text.toString())
    }

    @Test fun pastReplayDefaultsToProgrammeTitleAndZeroResume() {
        val entry = iptv(); val p = programme(airing = false); set("iptvGuideVisible", true); catchup(entry, p)
        messenger.success(mapOf("url" to "https://phase5.invalid/replay.mp4")); idle()
        @Suppress("UNCHECKED_CAST") val replay = (field("iptvChannels") as List<IptvChannelEntry>).single()
        assertEquals(p.title, replay.name); assertEquals(0L, replay.resumePositionMs)
        assertEquals(listOf("media:https://phase5.invalid/replay.mp4"), tuning())
    }

    @Test fun timelineRequiresActivePositiveDurationThenTogglesVisibilityAndFocus() {
        iptv(); invoke("showIptvStartOverTimeline"); assertEquals(false, field("iptvStartOverTimelineVisible"))
        set("iptvStartOverActive", true); probe.duration = 0; invoke("showIptvStartOverTimeline")
        assertEquals("Timeline is still loading", ShadowToast.getTextOfLatestToast()); assertEquals(false, field("iptvStartOverTimelineVisible"))
        probe.duration = 100_000; set("controlsMenuVisible", true)
        val progress = FrameLayout(activity).apply { isFocusable = true }; (seekButton().parent as android.view.ViewGroup).addView(progress)
        set("cinemaProgressContainer", progress); invoke("showIptvStartOverTimeline")
        assertEquals(true, field("iptvStartOverTimelineVisible")); assertEquals(View.VISIBLE, progress.visibility)
        advance(99); assertFalse(progress.hasFocus()); advance(1); assertTrue(progress.hasFocus())
        invoke("showIptvStartOverTimeline"); assertEquals(false, field("iptvStartOverTimelineVisible"))
        assertEquals(View.GONE, progress.visibility); assertTrue(seekButton().hasFocus())
    }

    @Test fun goLiveToggleSupersedesCatchupAndResetsFlagsBeforeChannelStart() {
        val entry = iptv(); set("iptvStartOverLoading", true); invoke("toggleIptvStartOver"); assertTrue(tuning().isEmpty())
        set("iptvStartOverLoading", false); set("iptvStartOverActive", true); set("iptvStartOverTimelineVisible", true)
        val before = field("iptvCatchupToken") as Int
        probe.onEvent = { if (it.startsWith("media:")) {
            assertEquals(before + 1, field("iptvCatchupToken")); assertEquals(false, field("iptvStartOverActive")); assertEquals(false, field("iptvStartOverTimelineVisible"))
        } }
        invoke("toggleIptvStartOver"); assertEquals(listOf("media:${entry.url}"), tuning())
        assertEquals("Start Over", button().text.toString())
    }

    @Test fun archivePlayerErrorCancelsCatchupBeforeReturningLiveAndLateReplyCannotRestartArchive() {
        val entry = iptv(); catchup(entry, programme(), true); val pending = requestIndex("requestIptvCatchup")
        set("iptvStartOverActive", true); set("iptvStartOverTimelineVisible", true)
        val token = field("iptvCatchupToken") as Int
        probe.error = androidx.media3.exoplayer.ExoPlaybackException.createForSource(java.io.IOException("archive failed"),
            androidx.media3.common.PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED)
        (field("playbackListener") as androidx.media3.common.Player.Listener).onPlayerError(probe.error!!)
        assertEquals("player error invalidates pending archive", token + 1, field("iptvCatchupToken"))
        assertEquals(false, field("iptvStartOverLoading")); assertEquals(false, field("iptvStartOverActive"))
        assertEquals(false, field("iptvStartOverTimelineVisible")); assertEquals(listOf("media:${entry.url}"), tuning())
        messenger.success(mapOf("url" to "https://phase5.invalid/late-archive.ts"), pending); idle()
        assertEquals(listOf("media:${entry.url}"), tuning())
    }

    @Test fun cancelStopAndDestroyInvalidatePendingCallbacksBeforePauseOrRelease() {
        createLifecycle(); val entry = iptv(); catchup(entry, programme(), true); val explicit = requestIndex("requestIptvCatchup")
        val token = field("iptvCatchupToken") as Int; invoke("cancelPendingIptvCatchupRequest")
        assertEquals(token + 1, field("iptvCatchupToken")); assertEquals(false, field("iptvStartOverLoading"))
        messenger.success(mapOf("url" to "https://phase5.invalid/explicit.ts"), explicit); idle(); assertTrue(tuning().isEmpty())
        catchup(entry, programme(), true); val stopped = requestIndex("requestIptvCatchup"); lifecycle.pause().stop()
        messenger.success(mapOf("url" to "https://phase5.invalid/stopped.ts"), stopped); idle(); assertTrue(tuning().isEmpty())
        catchup(entry, programme(), true); val destroyed = requestIndex("requestIptvCatchup"); lifecycle.destroy()
        messenger.success(mapOf("url" to "https://phase5.invalid/destroyed.ts"), destroyed); idle(); assertTrue(tuning().isEmpty())
        assertEquals(listOf("pause", "release"), probe.events); assertEquals(false, field("iptvStartOverLoading"))
    }
}
