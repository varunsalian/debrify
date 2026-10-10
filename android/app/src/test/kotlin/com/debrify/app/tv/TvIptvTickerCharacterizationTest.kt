package com.debrify.app.tv

import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvTickerCharacterizationTest : TvPhase17OriginalTest() {
    @Test fun tuneWatchdogUsesPlaybackIntentEvenWhileIsPlayingIsFalse() {
        tune();quiet();probe.playing=false;tick();advance(19_999);tick();assertEquals(1,tuning().size)
        advance(1);tick();advance(0);quiet();assertEquals(2,tuning().size);assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("tune-watchdog")})
    }
    @Test fun pausedIntentDoesNotTripTheTuneWatchdog() {tune();quiet();probe.playIntent=false;tick();advance(20_000);tick();advance(0);assertEquals(1,tuning().size)}
    @Test fun readyStallRetunesAtTwelveSecondsOfFrozenPosition() {
        tune();quiet();listener().onPlaybackStateChanged(Player.STATE_READY);tick();advance(11_999);tick();assertEquals(1,tuning().size)
        advance(1);tick();advance(0);quiet();assertEquals(2,tuning().size);assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("source=stall")})
    }
    @Test fun renderedFrameStallEscalatesWhileTheAudioClockKeepsAdvancing() {
        tune(iptv(channel("http://h/live.ts")));quiet();listener().onPlaybackStateChanged(Player.STATE_READY);probe.counters.renderedOutputBufferCount=10;tick()
        advance(7_999);probe.position++;tick();assertEquals(1,tuning().size);advance(1);probe.position++;tick();advance(0);quiet();assertEquals(2,tuning().size)
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("video-stall")})
    }
    @Test fun missingVideoTrackDisarmsTheVideoStallDetector() {tune();quiet();listener().onPlaybackStateChanged(Player.STATE_READY);probe.videoFormat=null;tick();advance(8_000);probe.position++;tick();advance(0);assertEquals(1,tuning().size)}
    @Test fun nonIptvProgressDoesNotConstructTheRecoveryLazy() {movie();val deferred=field("iptvLiveRecovery\$delegate") as Lazy<*>;assertFalse(deferred.isInitialized());tick();assertFalse(deferred.isInitialized());assertEquals(1,requests("torrentPlaybackProgress").size)}
    @Test fun endedListenerDispatchesIntoLiveRecoveryInsteadOfAutoAdvance() {tune();quiet();probe.events.clear();listener().onPlaybackStateChanged(Player.STATE_ENDED);advance(0);quiet();assertEquals(1,tuning().size);assertFalse(activity.isFinishing)}
}
