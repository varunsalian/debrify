package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvShuffleProtocolCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun attemptCurrentLive() {
        val a=attemptWith(automatic=false);
         assertEquals(true,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun attemptCurrentFinished() {
        val a=attemptWith(automatic=false); setAttempt(a,"finished",true)
         assertEquals(false,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun attemptCurrentFinishing() {
        val a=attemptWith(automatic=false); finishing(true)
         assertEquals(false,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun attemptCurrentDestroyed() {
        val a=attemptWith(automatic=false); destroyed(true)
         assertEquals(false,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun attemptCurrentGeneration() {
        val a=attemptWith(automatic=false); set("showShuffleGeneration",1)
         assertEquals(false,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun attemptCurrentNavigation() {
        val a=attemptWith(automatic=false); set("mediaPreparationGeneration",1)
         assertEquals(false,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun attemptCurrentAutomaticSleep() {
        val a=attemptWith(automatic=true); set("sleepStopLatched",true)
         assertEquals(false,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun attemptCurrentManualSleep() {
        val a=attemptWith(automatic=false); set("sleepStopLatched",true)
         assertEquals(true,call("shuffleAttemptCurrent",arrayOf(attemptType),a))
    }

    @Test fun restoreUnstarted() {
        var restored=0; val a=attemptWith(started=false,restore={ restored++ }); set("mediaPreparationGeneration",0)
         call("restoreShufflePreparation",arrayOf(attemptType),a); assertEquals(1,restored)
    }

    @Test fun restoreStarted() {
        var restored=0; val a=attemptWith(started=true,restore={ restored++ }); set("mediaPreparationGeneration",0)
         call("restoreShufflePreparation",arrayOf(attemptType),a); assertEquals(0,restored)
    }

    @Test fun restoreSuperseded() {
        var restored=0; val a=attemptWith(started=false,restore={ restored++ }); set("mediaPreparationGeneration",1)
         call("restoreShufflePreparation",arrayOf(attemptType),a); assertEquals(0,restored)
    }

    @Test fun failWithoutPendingIsFalse() {
        assertEquals(false,call("failShufflePlayback",emptyArray()))
    }

    @Test fun failRestoresClearsFinishesThenPostsOnce() {
        val events=mutableListOf<String>(); val a=attemptWith(restore={events.add("restore")},unavailable={events.add("retry")}); set("pendingShufflePlayback",a)
        assertEquals(true,call("failShufflePlayback",emptyArray())); assertEquals(listOf("restore"),events); assertNull(field("pendingShufflePlayback")); assertEquals(true,attemptField(a,"finished")); pump(); assertEquals(listOf("restore","retry"),events)
    }

    @Test fun postedFailureRejectsGeneration() {
        var retries=0; val a=attemptWith(automatic=true,unavailable={retries++}); set("pendingShufflePlayback",a); call("failShufflePlayback",emptyArray()); set("showShuffleGeneration",1); pump(); assertEquals(0,retries)
    }

    @Test fun postedFailureRejectsNavigation() {
        var retries=0; val a=attemptWith(automatic=true,unavailable={retries++}); set("pendingShufflePlayback",a); call("failShufflePlayback",emptyArray()); set("mediaPreparationGeneration",1); pump(); assertEquals(0,retries)
    }

    @Test fun postedFailureRejectsFinishing() {
        var retries=0; val a=attemptWith(automatic=true,unavailable={retries++}); set("pendingShufflePlayback",a); call("failShufflePlayback",emptyArray()); finishing(true); pump(); assertEquals(0,retries)
    }

    @Test fun postedFailureRejectsDestroyed() {
        var retries=0; val a=attemptWith(automatic=true,unavailable={retries++}); set("pendingShufflePlayback",a); call("failShufflePlayback",emptyArray()); destroyed(true); pump(); assertEquals(0,retries)
    }

    @Test fun postedFailureRejectsSleep() {
        var retries=0; val a=attemptWith(automatic=true,unavailable={retries++}); set("pendingShufflePlayback",a); call("failShufflePlayback",emptyArray()); set("sleepStopLatched",true); pump(); assertEquals(0,retries)
    }

    @Test fun clearQueuedMatches() {
        set("queuedShuffleGeneration",3); set("queuedShuffleNavigation",7); call("clearQueuedShuffle",arrayOf(intType),3)
         assertEquals(null,field("queuedShuffleGeneration")); assertEquals(null,field("queuedShuffleNavigation"))
    }

    @Test fun clearQueuedNewerQueue() {
        set("queuedShuffleGeneration",3); set("queuedShuffleNavigation",7); call("clearQueuedShuffle",arrayOf(intType),2)
         assertEquals(3,field("queuedShuffleGeneration")); assertEquals(7,field("queuedShuffleNavigation"))
    }

    @Test fun yieldLive() {
        set("queuedShuffleGeneration",0); set("queuedShuffleNavigation",0);
        assertEquals(true,call("yieldEpisodeFetchToQueuedShuffle",emptyArray()))
    }

    @Test fun yieldGeneration() {
        set("queuedShuffleGeneration",0); set("queuedShuffleNavigation",0); set("queuedShuffleGeneration",1)
        assertEquals(false,call("yieldEpisodeFetchToQueuedShuffle",emptyArray()))
    }

    @Test fun yieldNavigation() {
        set("queuedShuffleGeneration",0); set("queuedShuffleNavigation",0); set("queuedShuffleNavigation",1)
        assertEquals(false,call("yieldEpisodeFetchToQueuedShuffle",emptyArray()))
    }

    @Test fun yieldFinishing() {
        set("queuedShuffleGeneration",0); set("queuedShuffleNavigation",0); finishing(true)
        assertEquals(false,call("yieldEpisodeFetchToQueuedShuffle",emptyArray()))
    }

    @Test fun yieldDestroyed() {
        set("queuedShuffleGeneration",0); set("queuedShuffleNavigation",0); destroyed(true)
        assertEquals(false,call("yieldEpisodeFetchToQueuedShuffle",emptyArray()))
    }

    @Test fun watchdogHasExactFifteenSecondBoundary() {
        var retries=0; val a=attemptWith(unavailable={retries++}); call("watchShufflePlayback",arrayOf(attemptType),a)
        assertSame(a,field("pendingShufflePlayback")); pump(14_999); assertEquals(0,retries); pump(1); assertEquals(1,retries); assertNull(field("pendingShufflePlayback"))
    }

    @Test fun oldWatchdogCannotFailReplacement() {
        val a=attemptWith(); call("watchShufflePlayback",arrayOf(attemptType),a); pump(1)
        val b=attemptWith(); call("watchShufflePlayback",arrayOf(attemptType),b); pump(14_999)
        assertSame(b,field("pendingShufflePlayback")); assertEquals(false,attemptField(b,"finished"))
    }

    @Test fun watchdogPikPakRetryRearmsWithoutUnavailable() {
        payload(p2Item(provider="PikPak")); var retries=0; val a=attemptWith(started=true,unavailable={retries++}); set("isPikPakRetrying",true)
        call("watchShufflePlayback",arrayOf(attemptType),a); pump(15_000); assertSame(a,field("pendingShufflePlayback")); assertEquals(0,retries); assertEquals(2,field("shuffleWatchGeneration"))
        set("isPikPakRetrying",false); pump(15_000); assertEquals(1,retries)
    }

    @Test fun resetRestoresClearsBagVisitedAndQueuedGeneration() {
        var restored=0; val a=attemptWith(restore={restored++}); set("pendingShufflePlayback",a); (field("shuffleBag") as MutableList<Int>).add(3); set("queuedShuffleGeneration",0)
        call("resetShuffle",emptyArray()); assertEquals(1,restored); assertNull(field("pendingShufflePlayback")); assertTrue((field("shuffleBag") as List<*>).isEmpty()); assertEquals(1,field("showShuffleGeneration")); assertNull(field("queuedShuffleGeneration"))
    }
}
