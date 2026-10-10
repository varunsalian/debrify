package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvRecoveryCharacterizationTest : TvPhase17OriginalTest() {
    @Test fun recoveryNonIptvDeclinesAnEndedRetune() {
        iptv();set("isIptvMode",false);assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryFinishingDeclinesAnEndedRetune() {
        iptv();activity.finish();assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryNoEntryDeclinesAnEndedRetune() {
        iptv();set("iptvChannels",mutableListOf<IptvChannelEntry>());assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryWrongIndexDeclinesAnEndedRetune() {
        iptv();set("currentIptvIndex",1);assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryVodDeclinesAnEndedRetune() {
        iptv();iptv(channel(live=false));assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoverySleepLatchDeclinesAnEndedRetune() {
        iptv();set("sleepStopLatched",true);assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryEndOfItemSleepDeclinesAnEndedRetune() {
        iptv();set("sleepTimerMode",SleepTimerMode.END_OF_ITEM);assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryCandidateHuntDeclinesAnEndedRetune() {
        iptv();set("iptvStremioChannelKey","hunt");set("iptvStremioWinnerReported",false);assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryPausedDeclinesAnEndedRetune() {
        iptv();probe.playIntent=false;assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun recoveryNullPlayerDeclinesAnEndedRetune() {
        iptv();set("player",null);assertEquals(false,invoke("iptvLiveRecoveryEligible"));assertFalse(recovery().onEnded());advance(0);assertTrue(tuning().isEmpty())
    }
    @Test fun bufferingWithoutIsPlayingStillHonorsPlaybackIntent() {
        iptv();probe.playing=false;probe.playIntent=true;assertEquals(true,invoke("iptvLiveRecoveryEligible"));assertTrue(recovery().onEnded());advance(0);quiet();assertEquals(1,tuning().size)
    }
    @Test fun reportedStremioWinnerHandsRecoveryToTheLiveMachine() {
        iptv();set("iptvStremioChannelKey","winner");set("iptvStremioWinnerReported",true);assertEquals(true,invoke("iptvLiveRecoveryEligible"));recovery().onEnded();advance(0);quiet();assertEquals(1,tuning().size)
    }
    @Test fun reconnectingNarrationUsesExactTextAndRecoveredHidesItAndRearmsFrameHold() {
        tune();quiet();recovery().onEnded();advance(0);quiet();advance(301);recovery().onEnded();val pill=reconnectPill();assertEquals("Reconnecting…",pill.text.toString());assertEquals(View.VISIBLE,pill.visibility);(field("playerView") as androidx.media3.ui.PlayerView).setKeepContentOnPlayerReset(false);listener().onPlaybackStateChanged(androidx.media3.common.Player.STATE_READY);assertEquals(View.GONE,pill.visibility);assertTrue(org.robolectric.util.ReflectionHelpers.getField<Boolean>(field("playerView"),"keepContentOnPlayerReset"))
    }
    @Test fun nonIptvRecoveryCallbackDoesNotRearmFrameHold() {
        tune();quiet();recovery().onEnded();advance(0);quiet();advance(301);recovery().onEnded();set("isIptvMode",false);(field("playerView") as androidx.media3.ui.PlayerView).setKeepContentOnPlayerReset(false);recovery().onReady();assertFalse(org.robolectric.util.ReflectionHelpers.getField<Boolean>(field("playerView"),"keepContentOnPlayerReset"))
    }
    @Test fun surrenderDropsHeldFrameAndLogsExactRecoverySource() {
        tune();quiet();recovery().onFatalError(IptvLiveRecovery.ErrorClass.AUTH);assertFalse(org.robolectric.util.ReflectionHelpers.getField<Boolean>(field("playerView"),"keepContentOnPlayerReset"));assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("source=auth") && it.msg.contains("surrender")})
    }
}
