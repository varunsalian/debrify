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
internal class TvStremioTvGuidePlaybackCharacterizationTest : TvPhase7OriginalTest() {
    private fun finished() = field("finishProgressAttempted") as Boolean
    private fun overlay() = view("nextOverlay")
    private fun toast() = ShadowToast.getTextOfLatestToast()
    private fun clearFinish() { set("finishProgressAttempted", false); ShadowToast.reset() }
    private fun assertStarted(title: String, id: String) {
        assertEquals(listOf("media:https://phase7.invalid/play.mp4:$title", "prepare", "playWhenReady:true", "play"), probe.events.take(4))
        val model = field("payload") as PlaybackPayload
        assertEquals(1, model.items.size); assertEquals("stremio_tv:$id", model.items[0].id)
        assertEquals(title, model.items[0].title); assertEquals("https://phase7.invalid/play.mp4", model.items[0].url)
        assertEquals(0.25, model.startAtPercent, 0.0); assertEquals(0, field("currentIndex"))
        assertEquals(title, text("titleView").text.toString()); assertEquals("New programme", channels().first { it.id == id }.nowPlayingTitle)
    }

    @Test fun nextAndSwitchRejectBothInProgressFlags() {
        standard()
        for (flag in listOf("stremioTvNextInProgress", "stremioTvChannelSwitchInProgress")) {
            set(flag, true); next(); switch()
            assertTrue("$flag prevents requests", messenger.requests.isEmpty())
            assertEquals(0, field("stremioTvSwitchToken")); assertTrue(channels()[0].isCurrent)
            set(flag, false)
        }
    }

    @Test fun missingCurrentNextDefaultDoesNotFinishButExplicitTrueUsesOverride() {
        standard(); channels().forEach { it.isCurrent = false }; clearFinish()
        nextDefault(); assertEquals("Channel unavailable", toast()); assertFalse("default is false", finished())
        next(true); assertTrue("finish dispatches activity override", finished())
        assertTrue(messenger.requests.isEmpty()); assertEquals(0, field("stremioTvSwitchToken"))
    }

    @Test fun nullBridgeNextUsesOptionalFinishAndBridgeToast() {
        standard(); MainActivity.setAndroidTvPlayerChannel(null); clearFinish()
        nextDefault(); assertEquals("Playback bridge unavailable", toast()); assertFalse(finished())
        next(true); assertTrue("null bridge explicit finish", finished())
        assertEquals(false, field("stremioTvNextInProgress")); assertEquals(0, field("stremioTvSwitchToken"))
    }

    @Test fun nextSuccessUsesRealTrioWithoutGuideWaitAndHidesOverlayAt1500ms() {
        standard(); val model = payload(); set("stremioTvGuideVisible", true)
        channels()[0].nextUpTitle = "Queued"; next()
        assertEquals(mapOf("channelId" to "0"), requests("requestStremioTvNext").single().call.arguments)
        assertEquals("Queued", text("nextText").text.toString()); assertEquals(View.GONE, view("nextSubtext").visibility)
        assertEquals(View.VISIBLE, overlay().visibility); assertEquals(true, field("stremioTvNextInProgress"))
        assertEquals(1, field("stremioTvSwitchToken")); assertTrue(probe.events.isEmpty())
        val observer = TvPhase7AdapterObserver(); adapter().registerAdapterDataObserver(observer)
        var replyAt = 0L
        probe.onEvent = { if (it == "play") replyAt = android.os.SystemClock.uptimeMillis(); if (it.startsWith("media:")) assertEquals("payload replaced before media start", "stremio_tv:0", model.items[0].id) }
        messenger.success(playback()); assertTrue(probe.events.isEmpty()); pump()
        assertStarted("New programme", "0"); assertEquals(listOf("all"), observer.events)
        assertEquals(false, field("stremioTvNextInProgress")); assertTrue(visible())
        assertNull("Next must not register a guide wait", field("guidePanelReadyListener")); assertNull(field("guidePanelTimeoutRunnable"))
        assertEquals("New programme", text("nextText").text.toString())
        tickUntil(replyAt + 1499); assertEquals("overlay remains before delay", 220L, overlay().animate().duration)
        tick(1); assertEquals("overlay hide starts at 1500ms", 160L, overlay().animate().duration)
    }

    @Test fun nextTitleFallbackAndInvalidUrlCleanupPreserveFinishChoice() {
        standard(); payload(); next(); messenger.success(playback().filterKeys { it != "title" }); pump()
        assertStarted("Channel 0", "0"); assertEquals("Channel 0", text("nextText").text.toString())
        for (bad in listOf(null, emptyMap<String, Any>(), mapOf("url" to ""), mapOf("url" to 9))) {
            clearFinish(); probe.events.clear(); next(true); messenger.success(bad); pump()
            assertEquals("Next item unavailable", toast()); assertTrue("bad URL finishes when requested", finished())
            assertEquals(false, field("stremioTvNextInProgress")); assertTrue(probe.events.isEmpty())
            assertEquals(160L, overlay().animate().duration)
        }
    }

    @Test fun nextErrorAndNotImplementedPreserveMessagesAndFinishChoice() {
        standard()
        for (message in listOf("provider failure", null)) {
            clearFinish(); next(); error(message); pump()
            assertEquals(message ?: "Failed to load next item", toast()); assertFalse(finished())
            assertEquals(false, field("stremioTvNextInProgress")); assertEquals(160L, overlay().animate().duration)
        }
        clearFinish(); next(true); messenger.error(); pump(); assertTrue(finished())
        clearFinish(); next(); messenger.notImplemented(); pump(); assertFalse(finished()); assertNull(toast())
        clearFinish(); next(true); messenger.notImplemented(); pump(); assertTrue(finished()); assertNull(toast())
    }

    @Test fun nextSendExceptionCleansFlagOverlayAndOptionallyFinishes() {
        standard(); messenger.throwOnSend = true; clearFinish()
        next(); assertEquals(false, field("stremioTvNextInProgress")); assertFalse(finished()); assertNull(toast())
        assertEquals(160L, overlay().animate().duration)
        next(true); assertTrue("send exception explicit finish", finished()); assertTrue(messenger.requests.isEmpty())
    }

    @Test fun nextStaleSuccessErrorAndNotImplementedLeavePendingStateUntouched() {
        standard(); payload()
        for (kind in listOf("success", "error", "notImplemented")) {
            set("stremioTvNextInProgress", false); next(true); val token = field("stremioTvSwitchToken") as Int
            set("stremioTvSwitchToken", token + 1); clearFinish()
            when (kind) { "success" -> messenger.success(playback()); "error" -> messenger.error(); else -> messenger.notImplemented() }
            pump()
            assertEquals("stale $kind leaves request flag", true, field("stremioTvNextInProgress"))
            assertFalse(finished()); assertNull(toast()); assertTrue(probe.events.isEmpty())
            assertEquals("Channel 0", text("nextText").text.toString()); assertEquals(220L, overlay().animate().duration)
        }
    }

    @Test fun switchSuccessUsesRealTrioAndWaitsForReadyAfterAdapterUpdate() {
        standard(); payload(); set("stremioTvGuideVisible", true)
        val observer = TvPhase7AdapterObserver(); adapter().registerAdapterDataObserver(observer)
        switch()
        assertEquals(mapOf("channelId" to "1"), requests("requestStremioTvChannelSwitch").single().call.arguments)
        assertEquals(true, field("stremioTvChannelSwitchInProgress")); assertEquals(1, field("stremioTvSwitchToken"))
        assertFalse(channels()[0].isCurrent); assertTrue(channels()[1].isCurrent); assertTrue(channels()[1].isSwitchingChannel)
        assertEquals(listOf("all"), observer.events)
        probe.onEvent = { if (it == "listen:add") {
            assertFalse("switch mark clears before listener", channels()[1].isSwitchingChannel)
            assertEquals("adapter updates before listener", listOf("all", "all"), observer.events)
        } }
        messenger.success(playback()); assertTrue(channels()[1].isSwitchingChannel); pump()
        assertStarted("New programme", "1"); assertEquals(false, field("stremioTvChannelSwitchInProgress"))
        assertEquals("listen:add", probe.events.last()); assertEquals(1, probe.listeners.size)
        assertNotNull(field("guidePanelTimeoutRunnable")); assertTrue(visible())
        probe.emit(Player.STATE_READY); assertFalse("READY hides successful switch guide", visible())
        assertTrue(probe.listeners.isEmpty()); assertNull(field("guidePanelTimeoutRunnable"))
    }

    @Test fun switchFailuresRollbackCurrentAndSwitchingMarksWithOriginalToasts() {
        standard(); val observer = TvPhase7AdapterObserver(); adapter().registerAdapterDataObserver(observer)
        for (kind in listOf("empty", "error", "notImplemented")) {
            ShadowToast.reset(); observer.events.clear(); switch()
            when (kind) { "empty" -> messenger.success(mapOf("url" to "")); "error" -> messenger.error(); else -> messenger.notImplemented() }
            pump()
            assertEquals("$kind restores previous current", listOf(true, false), channels().map { it.isCurrent })
            assertTrue(channels().none { it.isSwitchingChannel }); assertEquals(false, field("stremioTvChannelSwitchInProgress"))
            assertEquals(listOf("all", "all"), observer.events); assertTrue(probe.events.isEmpty())
            assertEquals(when (kind) { "empty" -> "Channel switch failed"; "error" -> "Channel switch failed: message"; else -> null }, toast())
        }
    }

    @Test fun nullBridgeSwitchRetainsNewMarksAndInProgressFlag() {
        standard(); MainActivity.setAndroidTvPlayerChannel(null); switch()
        assertEquals("null bridge retains in-progress switch", true, field("stremioTvChannelSwitchInProgress"))
        assertEquals(listOf(false, true), channels().map { it.isCurrent }); assertTrue(channels()[1].isSwitchingChannel)
        assertEquals(1, field("stremioTvSwitchToken")); assertTrue(messenger.requests.isEmpty())
    }

    @Test fun switchSendExceptionRollsBackWithoutToast() {
        standard(); ShadowToast.reset(); messenger.throwOnSend = true; switch()
        assertEquals("send exception restores previous current", listOf(true, false), channels().map { it.isCurrent })
        assertEquals(false, field("stremioTvChannelSwitchInProgress")); assertTrue(channels().none { it.isSwitchingChannel })
        assertNull(toast()); assertTrue(messenger.requests.isEmpty())
    }

    @Test fun switchStaleSuccessErrorAndNotImplementedLeaveNewMarksUntouched() {
        standard(); payload()
        for (kind in listOf("success", "error", "notImplemented")) {
            set("stremioTvChannelSwitchInProgress", false); channels()[0].isCurrent = true; channels()[1].isCurrent = false
            switch(); set("stremioTvSwitchToken", (field("stremioTvSwitchToken") as Int) + 1); ShadowToast.reset()
            when (kind) { "success" -> messenger.success(playback()); "error" -> messenger.error(); else -> messenger.notImplemented() }
            pump()
            assertEquals("stale $kind keeps switch pending", true, field("stremioTvChannelSwitchInProgress"))
            assertEquals(listOf(false, true), channels().map { it.isCurrent }); assertTrue(channels()[1].isSwitchingChannel)
            assertNull(toast()); assertTrue(probe.events.isEmpty())
        }
    }
}
