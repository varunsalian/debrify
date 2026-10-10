package com.debrify.app.tv

import android.os.SystemClock
import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvClockCharacterizationTest : TvPhase17OriginalTest() {
    @Test fun pausedClockDrivesTheFortySecondPreReadyDeadline() {
        begin();quiet();val start=SystemClock.elapsedRealtime();probe.playIntent=true
        advance(39_999);assertEquals(39_999,SystemClock.elapsedRealtime()-start);assertEquals(twin,trial())
        advance(1);assertNull(trial());assertEquals(original,field("currentIptvStreamUrl"));assertTrue(failed().contains(original))
    }
    @Test fun readyCallbackRearmsTheDeadlineForThirtySeconds() {
        begin();quiet();advance(25_000);listener().onPlaybackStateChanged(Player.STATE_READY);quiet()
        advance(29_999);assertEquals(twin,trial());advance(1);assertNull(trial());assertEquals(original,field("currentIptvStreamUrl"))
    }
    @Test fun repeatedReadyCannotExtendTheAbsoluteNinetySecondBudget() {
        begin();quiet();advance(20_000);listener().onPlaybackStateChanged(Player.STATE_READY);quiet()
        advance(20_000);listener().onPlaybackStateChanged(Player.STATE_READY);quiet()
        advance(20_000);listener().onPlaybackStateChanged(Player.STATE_READY);quiet()
        advance(20_000);listener().onPlaybackStateChanged(Player.STATE_READY);quiet()
        advance(9_999);assertEquals(twin,trial());advance(1);assertNull(trial());assertTrue(failed().contains(original))
    }
    @Test fun realProgressTickerAcceptsOnlyFifteenSecondsOfAdvancingFrames() {
        begin();quiet();probe.counters.renderedOutputBufferCount=10;tick()
        repeat(3) { advance(5_000);probe.position+=5_000;probe.counters.renderedOutputBufferCount++;tick();assertEquals(twin,trial()) }
        advance(5_000);probe.position+=5_000;probe.counters.renderedOutputBufferCount++;tick()
        assertNull(trial());assertEquals(twin,pref()[original]);assertTrue(strict().isEmpty())
    }
    @Test fun recoveryCallbacksKeepTheZeroOneThreeFiveSecondLadder() {
        tune();quiet();val machine=recovery();probe.events.clear()
        assertTrue(machine.onEnded());assertTrue(tuning().isEmpty());advance(0);quiet();assertEquals(1,tuning().size)
        for(delay in listOf(1_000L,3_000L,5_000L)) {
            advance(301);val before=tuning().size;assertTrue(machine.onEnded());advance(delay-1);assertEquals(before,tuning().size)
            advance(1);quiet();assertEquals(before+1,tuning().size)
        }
        assertFalse(field("iptvLiveRetuneInFlight") as Boolean)
    }
}
