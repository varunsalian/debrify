package com.debrify.app.tv

import android.os.Handler
import android.os.SystemClock
import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvTrialCharacterizationTest : TvPhase17OriginalTest() {
    private fun seed() {
        iptv(channel(original));set("currentIptvStreamUrl",twin);set("iptvTwinTrialOriginalUrl",original);set("iptvTwinTrialUrl",twin)
        set("iptvTwinTrialLastFrames",10);set("iptvTwinTrialAdvanceSince",100L);set("iptvTwinTrialStartedRealtime",100L)
    }
    private fun parked() { iptv(channel(original));set("currentIptvStreamUrl",twin);set("iptvTwinTrialRestoreOriginal",original);set("iptvTwinTrialRestoreTwin",twin) }
    private fun cleared() {
        assertNull(trial());assertNull(field("iptvTwinTrialOriginalUrl"));assertNull(field("iptvTwinTrialTimeout"))
        assertEquals(-1,field("iptvTwinTrialLastFrames"));assertEquals(0L,field("iptvTwinTrialAdvanceSince"));assertEquals(0L,field("iptvTwinTrialStartedRealtime"))
    }
    @Test fun beginArmsExactStoredRunnableAndResetsAllCountersBeforeTheMediaSwap() {
        set("iptvTwinTrialLastFrames",999);set("iptvTwinTrialAdvanceSince",999L);val now=SystemClock.elapsedRealtime()
        probe.onEvent={if(it.startsWith("media:")){assertEquals(original,field("iptvTwinTrialOriginalUrl"));assertEquals(twin,trial());assertEquals(-1,field("iptvTwinTrialLastFrames"));assertEquals(0L,field("iptvTwinTrialAdvanceSince"));assertEquals(now,field("iptvTwinTrialStartedRealtime"));assertTrue(field("iptvLiveRetuneInFlight") as Boolean)}}
        begin();assertFalse(field("iptvLiveRetuneInFlight") as Boolean);assertTrue(TvPlaylistUiQueue.pending(field("iptvTwinTrialHandler") as Handler,timeout()))
    }
    @Test fun beginRestoresTheRetuneFlagEvenWhenThePlayerThrows() {
        probe.onEvent={if(it=="prepare")throw IllegalStateException("fixture")};try { begin();fail("fixture must throw") } catch(e: IllegalStateException) { assertEquals("fixture",e.message) };assertFalse(field("iptvLiveRetuneInFlight") as Boolean)
    }
    @Test fun judgeAbsentTrialLeavesTheStreakUntouched() {
        seed();set("iptvTwinTrialUrl",null);invoke("judgeIptvTwinTrial",11);assertEquals(10,field("iptvTwinTrialLastFrames"));assertEquals(100L,field("iptvTwinTrialAdvanceSince"));assertTrue(pref().isEmpty())
    }
    @Test fun judgeDifferentCurrentUrlLeavesTheStreakUntouched() {
        seed();set("currentIptvStreamUrl",original);invoke("judgeIptvTwinTrial",11);assertEquals(10,field("iptvTwinTrialLastFrames"));assertEquals(100L,field("iptvTwinTrialAdvanceSince"));assertTrue(pref().isEmpty())
    }
    @Test fun judgeNegativeFramesLeavesTheStreakUntouched() {
        seed();invoke("judgeIptvTwinTrial",-1);assertEquals(10,field("iptvTwinTrialLastFrames"));assertEquals(100L,field("iptvTwinTrialAdvanceSince"));assertTrue(pref().isEmpty())
    }
    @Test fun judgeFirstCounterRebaselinesAndClearsTheStreak() {
        seed();set("iptvTwinTrialLastFrames",-1);invoke("judgeIptvTwinTrial",5);assertEquals(5,field("iptvTwinTrialLastFrames"));assertEquals(0L,field("iptvTwinTrialAdvanceSince"));assertEquals(twin,trial())
    }
    @Test fun judgeFrozenCounterRebaselinesAndClearsTheStreak() {
        seed();set("iptvTwinTrialLastFrames",10);invoke("judgeIptvTwinTrial",10);assertEquals(10,field("iptvTwinTrialLastFrames"));assertEquals(0L,field("iptvTwinTrialAdvanceSince"));assertEquals(twin,trial())
    }
    @Test fun judgeResetCounterRebaselinesAndClearsTheStreak() {
        seed();set("iptvTwinTrialLastFrames",10);invoke("judgeIptvTwinTrial",9);assertEquals(9,field("iptvTwinTrialLastFrames"));assertEquals(0L,field("iptvTwinTrialAdvanceSince"));assertEquals(twin,trial())
    }
    @Test fun firstAdvancingCounterStartsTheStreakWithoutAccepting() {
        seed();set("iptvTwinTrialAdvanceSince",0L);invoke("judgeIptvTwinTrial",11);assertEquals(11,field("iptvTwinTrialLastFrames"));assertEquals(SystemClock.elapsedRealtime(),field("iptvTwinTrialAdvanceSince"));assertTrue(pref().isEmpty())
    }
    @Test fun judgeOneMillisecondShort() {
        seed();set("iptvTwinTrialAdvanceSince",SystemClock.elapsedRealtime()-1);advance(14998L);invoke("judgeIptvTwinTrial",11);assertEquals(twin,trial());assertTrue(pref().isEmpty())
    }
    @Test fun judgeExactStabilityBoundary() {
        seed();set("iptvTwinTrialAdvanceSince",SystemClock.elapsedRealtime()-1);advance(14999L);invoke("judgeIptvTwinTrial",11);cleared();assertEquals(twin,pref()[original]);assertTrue(strict().isEmpty())
    }
    @Test fun judgePastStabilityBoundary() {
        seed();set("iptvTwinTrialAdvanceSince",SystemClock.elapsedRealtime()-1);advance(15000L);invoke("judgeIptvTwinTrial",11);cleared();assertEquals(twin,pref()[original]);assertTrue(strict().isEmpty())
    }
    @Test fun acceptAbsentOriginalDoesNotEnrollPreference() {
        seed();set("iptvTwinTrialOriginalUrl",null);invoke("acceptIptvTwinTrial");assertTrue(pref().isEmpty());assertEquals(10,field("iptvTwinTrialLastFrames"))
    }
    @Test fun acceptAbsentTwinDoesNotEnrollPreference() {
        seed();set("iptvTwinTrialUrl",null);invoke("acceptIptvTwinTrial");assertTrue(pref().isEmpty());assertEquals(10,field("iptvTwinTrialLastFrames"))
    }
    @Test fun acceptSupersededDoesNotEnrollPreference() {
        seed();set("currentIptvStreamUrl",original);invoke("acceptIptvTwinTrial");assertTrue(pref().isEmpty());assertEquals(10,field("iptvTwinTrialLastFrames"))
    }
    @Test fun acceptedTrialCancelsItsDeadlineAndRecordsTheVerdict() {
        begin();quiet();invoke("acceptIptvTwinTrial");cleared();assertEquals(twin,pref()[original]);advance(40_000);assertEquals(twin,field("currentIptvStreamUrl"));assertTrue(failed().isEmpty());assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("accepted")})
    }
    @Test fun failureRestoresUnderTheExistingRecoveryEpisodeAndThenDropsTheFlag() {
        begin();quiet();recovery().onEnded();advance(0);quiet();probe.events.clear();probe.onEvent={if(it.startsWith("media:")){assertTrue(field("iptvLiveRetuneInFlight") as Boolean);assertTrue(failed().contains(original));assertNull(trial())}};invoke("failIptvTwinTrial","named");cleared();assertEquals(original,field("currentIptvStreamUrl"));assertFalse(field("iptvLiveRetuneInFlight") as Boolean);assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("failed:named")})
    }
    @Test fun failureRestoresFlagWhenPlayerPrepareThrows() {
        seed();probe.onEvent={if(it=="prepare")throw IllegalStateException("fixture")};try { invoke("failIptvTwinTrial","error");fail("expected fixture throw") } catch(e: IllegalStateException) {assertEquals("fixture",e.message)};assertFalse(field("iptvLiveRetuneInFlight") as Boolean)
    }
    @Test fun failureAbsentOriginalDoesNotBlacklistOrRestore() {
        seed();set("iptvTwinTrialOriginalUrl",null);invoke("failIptvTwinTrial","error");assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty());assertEquals(10,field("iptvTwinTrialLastFrames"))
    }
    @Test fun failureAbsentTwinDoesNotBlacklistOrRestore() {
        seed();set("iptvTwinTrialUrl",null);invoke("failIptvTwinTrial","error");assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty());cleared()
    }
    @Test fun failureSupersededDoesNotBlacklistOrRestore() {
        seed();set("currentIptvStreamUrl",original);invoke("failIptvTwinTrial","error");assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty());cleared()
    }
    @Test fun failureFinishingDoesNotBlacklistOrRestore() {
        seed();activity.finish();invoke("failIptvTwinTrial","error");assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty());cleared()
    }
    @Test fun failureNoEntryStillBlacklistsBeforeDecliningRestore() {
        seed();set("iptvChannels",mutableListOf<IptvChannelEntry>());invoke("failIptvTwinTrial","error");cleared();assertTrue(failed().contains(original));assertTrue(tuning().isEmpty())
    }
    @Test fun failureVodEntryStillBlacklistsBeforeDecliningRestore() {
        seed();iptv(channel(original,live=false));invoke("failIptvTwinTrial","error");cleared();assertTrue(failed().contains(original));assertTrue(tuning().isEmpty())
    }
    @Test fun timeoutPausedParksInsteadOfRestartingPlayback() {
        seed();probe.playIntent=false;invoke("onIptvTwinTrialTimeout");cleared();assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("iptvTwinTrialRestoreTwin"));assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun timeoutSleepParksInsteadOfRestartingPlayback() {
        seed();set("sleepStopLatched",true);invoke("onIptvTwinTrialTimeout");cleared();assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("iptvTwinTrialRestoreTwin"));assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun timeoutMissingPlayerParksInsteadOfRestartingPlayback() {
        seed();set("player",null);invoke("onIptvTwinTrialTimeout");cleared();assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("iptvTwinTrialRestoreTwin"));assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun timeoutWithWantedPlaybackFailsAndRestores() {
        seed();invoke("onIptvTwinTrialTimeout");cleared();assertEquals(original,field("currentIptvStreamUrl"));assertTrue(failed().contains(original))
    }
    @Test fun reschedulingRemovesThePreviousRunnableBeforePostingTheNewOne() {
        seed();invoke("scheduleIptvTwinTrialTimeout",10_000L);val old=timeout();invoke("scheduleIptvTwinTrialTimeout",20_000L);val h=field("iptvTwinTrialHandler") as Handler;assertFalse(TvPlaylistUiQueue.pending(h,old));assertTrue(TvPlaylistUiQueue.pending(h,timeout()));advance(10_000);assertEquals(twin,trial());advance(10_000);assertNull(trial())
    }
    @Test fun negativeDeadlineClampsToImmediateDelivery() {
        seed();invoke("scheduleIptvTwinTrialTimeout",-1L);assertEquals(twin,trial());advance(0);assertNull(trial());assertEquals(original,field("currentIptvStreamUrl"))
    }
    @Test fun readyDeadlineAbsentTwinKeepsTheOldRunnable() {
        seed();invoke("scheduleIptvTwinTrialTimeout",40_000L);val old=field("iptvTwinTrialTimeout");set("iptvTwinTrialUrl",null);invoke("rearmIptvTwinTrialDeadline");assertSame(old,field("iptvTwinTrialTimeout"))
    }
    @Test fun readyDeadlineOtherUrlKeepsTheOldRunnable() {
        seed();invoke("scheduleIptvTwinTrialTimeout",40_000L);val old=field("iptvTwinTrialTimeout");set("currentIptvStreamUrl",original);invoke("rearmIptvTwinTrialDeadline");assertSame(old,field("iptvTwinTrialTimeout"))
    }
    @Test fun readyDeadlineZeroStartKeepsTheOldRunnable() {
        seed();invoke("scheduleIptvTwinTrialTimeout",40_000L);val old=field("iptvTwinTrialTimeout");set("iptvTwinTrialStartedRealtime",0L);invoke("rearmIptvTwinTrialDeadline");assertSame(old,field("iptvTwinTrialTimeout"))
    }
    @Test fun readyAfterAbsoluteBudgetSchedulesImmediateFailure() {
        seed();set("iptvTwinTrialStartedRealtime",SystemClock.elapsedRealtime());advance(90_001);invoke("rearmIptvTwinTrialDeadline");advance(0);cleared();assertTrue(failed().contains(original))
    }
    @Test fun parkAbsentOriginalLeavesExistingRollbackAndCountersUntouched() {
        seed();set("iptvTwinTrialRestoreOriginal","old");set("iptvTwinTrialOriginalUrl",null);assertEquals(false,invoke("parkIptvTwinTrialRestore"));assertEquals("old",field("iptvTwinTrialRestoreOriginal"));assertEquals(10,field("iptvTwinTrialLastFrames"))
    }
    @Test fun parkAbsentTwinLeavesExistingRollbackAndCountersUntouched() {
        seed();set("iptvTwinTrialRestoreOriginal","old");set("iptvTwinTrialUrl",null);assertEquals(false,invoke("parkIptvTwinTrialRestore"));assertEquals("old",field("iptvTwinTrialRestoreOriginal"));assertEquals(10,field("iptvTwinTrialLastFrames"))
    }
    @Test fun parkSupersededLeavesExistingRollbackAndCountersUntouched() {
        seed();set("iptvTwinTrialRestoreOriginal","old");set("currentIptvStreamUrl",original);assertEquals(false,invoke("parkIptvTwinTrialRestore"));assertEquals("old",field("iptvTwinTrialRestoreOriginal"));assertEquals(10,field("iptvTwinTrialLastFrames"))
    }
    @Test fun parkPreservesBothUrlsAndDisarmsTheExactVerdictDeadline() {
        begin();quiet();val old=timeout();assertEquals(true,invoke("parkIptvTwinTrialRestore"));cleared();assertFalse(TvPlaylistUiQueue.pending(field("iptvTwinTrialHandler") as Handler,old));assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("iptvTwinTrialRestoreTwin"));assertEquals(twin,field("currentIptvStreamUrl"))
    }
    @Test fun restoreAbsentOriginalDoesNotTune() {
        parked();set("iptvTwinTrialRestoreOriginal",null);assertEquals(false,invoke("restoreParkedIptvTwinIfNeeded"));assertTrue(tuning().isEmpty());assertEquals(twin,field("iptvTwinTrialRestoreTwin"))
    }
    @Test fun restoreAbsentTwinDoesNotTune() {
        parked();set("iptvTwinTrialRestoreTwin",null);assertEquals(false,invoke("restoreParkedIptvTwinIfNeeded"));assertTrue(tuning().isEmpty());assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"))
    }
    @Test fun restoreSupersededDoesNotTune() {
        parked();set("currentIptvStreamUrl",original);assertEquals(false,invoke("restoreParkedIptvTwinIfNeeded"));assertTrue(tuning().isEmpty());assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"))
    }
    @Test fun restoreMissingEntryDoesNotTune() {
        parked();set("iptvChannels",mutableListOf<IptvChannelEntry>());assertEquals(false,invoke("restoreParkedIptvTwinIfNeeded"));assertTrue(tuning().isEmpty());assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"))
    }
    @Test fun restoreVodEntryDoesNotTune() {
        parked();iptv(channel(original,live=false));assertEquals(false,invoke("restoreParkedIptvTwinIfNeeded"));assertTrue(tuning().isEmpty());assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"))
    }
    @Test fun parkedRestoreIsConsumedBeforeMediaAndIsAGenuineTune() {
        parked();recovery().onEnded();advance(0);quiet();invoke("showIptvReconnectPill","old");probe.onEvent={if(it.startsWith("media:")){assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"));assertFalse(field("iptvLiveRetuneInFlight") as Boolean)}};assertEquals(true,invoke("restoreParkedIptvTwinIfNeeded"));assertEquals(original,field("currentIptvStreamUrl"));assertFalse(TvPlayerOriginalAccess.field(recovery(),"episodeActive") as Boolean)
    }
    @Test fun clearParkedRestoreClearsBothHalves() {
        parked();invoke("clearParkedIptvTwinRestore");assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"))
    }
    @Test fun clearTrialCancelsOnlyItsOwnRunnableAndResetsEveryVerdictField() {
        seed();invoke("scheduleIptvTwinTrialTimeout",10L);val old=timeout();var foreign=false;(field("iptvTwinTrialHandler") as Handler).postDelayed({foreign=true},10);invoke("clearIptvTwinTrial");cleared();assertFalse(TvPlaylistUiQueue.pending(field("iptvTwinTrialHandler") as Handler,old));advance(10);assertTrue(foreign);assertTrue(tuning().isEmpty())
    }
    @Test fun failedTrialWithOutOfWindowIndexBlacklistsWithoutRestoringTheFirstEntry() {
        seed();set("currentIptvIndex",1);invoke("failIptvTwinTrial","error");cleared();assertTrue(failed().contains(original));assertTrue(tuning().isEmpty())
    }
    @Test fun parkedRestoreWithOutOfWindowIndexConsumesWithoutTuningTheFirstEntry() {
        parked();set("currentIptvIndex",1);assertEquals(false,invoke("restoreParkedIptvTwinIfNeeded"));assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"));assertTrue(tuning().isEmpty())
    }
    @Test fun pausedTimeoutWithIncompletePairLeavesTheUnjudgedOriginalUntouched() {
        seed();set("iptvTwinTrialUrl",null);probe.playIntent=false;invoke("onIptvTwinTrialTimeout");assertEquals(original,field("iptvTwinTrialOriginalUrl"));assertEquals(10,field("iptvTwinTrialLastFrames"));assertTrue(tuning().isEmpty())
    }
}
