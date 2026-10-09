package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlaybackException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsLiveCharacterizationTest : TvPhase16OriginalTest() {
    private fun retry(kind: String) {
        iptv(); probe.playing = false; playIntent = false; set("sleepStopLatched", true)
        val recovery = runOriginal("getIptvLiveRecovery") as IptvLiveRecovery
        val events = mutableListOf<String>()
        TvPlayerOriginalAccess.set(recovery, "callbacks", object : IptvLiveRecovery.Callbacks {
            override fun isEligible(): Boolean { events.add("eligible:$playIntent"); return playIntent }
            override fun performRetune(source: String, attempt: Int) { events.add("$source:$attempt") }
            override fun onEpisodeVisible(attempt: Int) { events.add("visible:$attempt") }
            override fun onRecovered() { events.add("recovered") }
            override fun onSurrender(source: String) { events.add("surrender:$source") }
        })
        when (kind) {
            "ended" -> probe.state = Player.STATE_ENDED
            "error" -> probe.error = ExoPlaybackException.createForSource(java.io.IOException("failure"), 2000)
            "surrendered" -> TvPlayerOriginalAccess.set(recovery, "isSurrendered", true)
        }
        runOriginal("togglePlayPause")
        assertFalse(field("sleepStopLatched") as Boolean); assertEquals(listOf("intent:true"), probe.events)
        assertEquals("Play", tv("pauseButton").text.toString()); step(0)
        assertEquals(listOf("eligible:true", "play-press:1"), events); assertFalse(recovery.isSurrendered)
    }
    @Test fun endedLiveSetsIntentBeforeTheRetryEligibilityRead() = retry("ended")
    @Test fun erroredLiveSetsIntentBeforeTheRetryEligibilityRead() = retry("error")
    @Test fun surrenderedLiveSetsIntentBeforeTheRetryEligibilityRead() = retry("surrendered")
    @Test fun nonLiveEndedItemPlaysNormallyInsteadOfRetuning() {
        iptv(channel(live = false)); probe.state = Player.STATE_ENDED; probe.playing = false; playIntent = false
        runOriginal("togglePlayPause"); assertEquals(listOf("play"), probe.events); assertEquals("Pause", tv("pauseButton").text.toString())
    }
    @Test fun parkedTwinIsRestoredBeforeOrdinaryPlayAndLabelStillRefreshes() {
        val original = "https://phase16.invalid/live.m3u8"; val twin = "https://phase16.invalid/live.ts"
        iptv(channel(original)); probe.playing = false; playIntent = false
        set("currentIptvStreamUrl", twin); set("iptvTwinTrialRestoreOriginal", original); set("iptvTwinTrialRestoreTwin", twin)
        runOriginal("togglePlayPause")
        assertNull(field("iptvTwinTrialRestoreOriginal")); assertNull(field("iptvTwinTrialRestoreTwin"))
        assertEquals(original, field("currentIptvStreamUrl")); assertEquals("Pause", tv("pauseButton").text.toString())
        assertEquals(1, probe.events.count { it == "play" })
    }
    @Test fun showMergesLiveBannerAndHideClearsOnlyTheDockedBanner() {
        iptv(); showDock(); assertTrue(field("iptvZapBannerDocked") as Boolean)
        assertEquals(View.VISIBLE, v("iptvZapBanner").visibility); hideDock(); step(301)
        assertEquals(View.GONE, v("iptvZapBanner").visibility)
        set("iptvZapBannerDocked", false); v("iptvZapBanner").visibility = View.VISIBLE; hideDock()
        assertEquals(View.VISIBLE, v("iptvZapBanner").visibility)
        iptv(channel(live = false)); showDock(); step(301); assertEquals(View.GONE, v("iptvZapBanner").visibility)
    }
    @Test fun liveUpExcludesScrubAndLongPressHidesControlsBeforeOpeningJumpDialog() {
        iptv(); showDock(); step(301); org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(v("pauseButton"))
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_UP)); assertFalse(field("cinemaSeekMode") as Boolean)
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_UP, repeat = 3)); assertFalse(field("controlsMenuVisible") as Boolean)
        assertNotNull(org.robolectric.shadows.ShadowDialog.getLatestDialog())
    }
    @Test fun endedLiveConstructsItsLazyRecoveryAfterSettingPlaybackIntent() {
        iptv(); probe.playing = false; playIntent = false; probe.state = Player.STATE_ENDED
        val events = mutableListOf<String>()
        val recovery = IptvLiveRecovery(android.os.Handler(android.os.Looper.getMainLooper()), object : IptvLiveRecovery.Callbacks {
            override fun isEligible(): Boolean { events.add("eligible:$playIntent"); return playIntent }
            override fun performRetune(source: String, attempt: Int) { events.add("$source:$attempt") }
            override fun onEpisodeVisible(attempt: Int) = Unit
            override fun onRecovered() = Unit
            override fun onSurrender(source: String) = Unit
        })
        val deferred = lazy { events.add("constructed:$playIntent"); recovery }
        set("iptvLiveRecovery\$delegate", deferred); assertFalse(deferred.isInitialized())
        runOriginal("togglePlayPause"); assertTrue(deferred.isInitialized()); assertEquals(listOf("constructed:true"), events)
        step(0); assertEquals(listOf("constructed:true", "eligible:true", "play-press:1"), events)
    }

}
