package com.debrify.app.tv

import android.os.SystemClock
import android.view.View
import android.widget.TextView
import androidx.media3.common.Player
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowSystem
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], instrumentedPackages = ["com.debrify.app.tv.AndroidTvTorrentPlayerActivity", "com.debrify.app.tv.TvPikPakRetryController"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPikPakRetryCharacterizationTest : TvPhase10OriginalTest() {
    @Before fun virtualClock() { duration=0; model().items[0]=model().items[0].copy(url="https://p10.mypikpak.com/video",provider="pikpak"); probe.state=Player.STATE_BUFFERING; SystemClock.setCurrentTimeMillis(1_000_000); assertEquals(1_000_000L,ShadowSystem.currentTimeMillis()) }
    private fun retrying() = field("isPikPakRetrying") as Boolean
    private fun count() = field("pikPakRetryCount") as Int
    private fun overlay() = view("pikPakReactivationIndicator")
    private fun status() = field("startupGateStatus") as TextView
    @Test fun virtualClockPinsAllSixTimeoutsAnd109500AdvanceBoundary() {
        model().items.add(p2Item("Next")); val started=SystemClock.uptimeMillis(); loop()
        val deadlines=listOf(10_000L,22_000L,36_000L,54_000L,80_000L,108_000L)
        for ((i,d) in deadlines.withIndex()) {
            tick(started+d-SystemClock.uptimeMillis()-1)
            assertEquals("attempt ${i+1} before timeout",i,count())
            tick(1)
            assertEquals("attempt ${i+1} at timeout",if(i<5)i+1 else 0,count())
            assertEquals("retry state at timeout",i<5,retrying())
        }
        assertEquals("Video failed to load. Skipping to next...",ShadowToast.getTextOfLatestToast())
        tick(1499); assertEquals(0,field("currentIndex")); tick(1); assertEquals(1,field("currentIndex"))
    }
    @Test fun metadataPollIs500AndReadyShortCircuitsZeroDuration() {
        val replies=mutableListOf<Boolean>(); monitor(callback={replies.add(it)}); probe.state=Player.STATE_READY
        tick(499); assertTrue(replies.isEmpty()); tick(1); assertEquals(listOf(true),replies)
    }
    @Test fun positiveDurationSucceedsAndClearsStateAndReprepareBeforeCallback() {
        set("isPikPakRetrying",true);set("pikPakRetryCount",4);duration=1
        call("schedulePikPakGateReprepare",arrayOf(boxedIntType),field("pikPakRetryId"))
        monitor { assertEquals(false,field("isPikPakRetrying"));assertEquals(0,count());assertNull(field("pikPakGateReprepare")); assertEquals(View.GONE,overlay().visibility) }
        tick(500); assertEquals(1,durationReads)
    }
    @Test fun monitoringAdditionalWindowTimesOutAtExactly10500() {
        val replies=mutableListOf<Boolean>();monitor(extra=500,callback={replies.add(it)})
        tick(10_499);assertTrue(replies.isEmpty());tick(1);assertEquals(listOf(false),replies)
    }
    @Test fun staleIdAtLoopEntryClearsAndNeverStartsPolling() {
        set("pikPakRetryCount",4);set("isPikPakRetrying",true);loop(retry=-1)
        assertEquals(0,count());assertFalse(retrying());tick(500);assertEquals(0,durationReads)
    }
    @Test fun staleIdAtPollCallsFalseWithoutReadingPlayer() {
        val replies=mutableListOf<Boolean>();monitor(callback={replies.add(it)});set("pikPakRetryId",7)
        tick(500);assertEquals(listOf(false),replies);assertEquals(0,durationReads)
    }
    @Test fun cancelledMonitoringCallbackCannotStartTheNextAttempt() {
        loop();invoke("cancelPikPakRetry");tick(11_000)
        assertFalse(retrying());assertEquals(0,count());assertEquals(0,durationReads)
        assertNull(ShadowToast.getTextOfLatestToast())
    }
    @Test fun playerReplacementIsReadAtPollTime() {
        val replies=mutableListOf<Boolean>();monitor(callback={replies.add(it)});set("player",PlayerProbe(duration=1).player)
        tick(500);assertEquals(listOf(true),replies)
    }
    @Test fun coldTvErrorSchedulesReprepareWithTheLiveId() {
        set("isStremioTvMode",true);probe.error=androidx.media3.exoplayer.ExoPlaybackException.createForSource(java.io.IOException("cold"),2004)
        set("pikPakRetryId",9);monitor { };tick(500)
        assertNotNull(field("pikPakGateReprepare"));tick(4000);assertTrue(probe.events.contains("prepare"))
    }
    @Test fun uncommittedBoundGateReceivesOverlayTextAnd250Fade() {
        cursor();loop();tick(10_000)
        assertEquals("Reactivating video... (Attempt 2/6)",status().text.toString())
        assertEquals(status().text,(field("pikPakReactivationText") as TextView).text)
        assertEquals(View.VISIBLE,overlay().visibility);assertEquals(250L,overlay().animate().duration)
    }
    @Test fun committedGateTextIsNotOverwrittenByRetryOverlay() {
        cursor(committed=true);status().text="committed";loop();tick(10_000)
        assertEquals("committed",status().text.toString());assertEquals(View.VISIBLE,overlay().visibility)
    }
    @Test fun successSelectsSubtitlesBeforeDeliveringTheTrueCallback() {
        var reads=0;val underlying=gatePlayer
        val replacement=java.lang.reflect.Proxy.newProxyInstance(androidx.media3.exoplayer.ExoPlayer::class.java.classLoader,arrayOf(androidx.media3.exoplayer.ExoPlayer::class.java)) { _, method, args ->
            if(method.name=="getCurrentTracks")reads++
            method.invoke(underlying,*(args?:emptyArray()))
        } as androidx.media3.exoplayer.ExoPlayer
        set("player",replacement);probe.state=Player.STATE_READY;monitor { assertTrue(it);assertEquals("subtitle selection precedes completion",1,reads) };tick(500)
    }
    @Test fun nullPlayerClearsRetryWithoutStartingMonitoring() {
        set("player",null);set("isPikPakRetrying",true);set("pikPakRetryCount",3);loop();assertFalse(retrying());assertEquals(0,count());tick(500);assertEquals(0,durationReads)
    }
    @Test fun unboundGateStatusStillShowsTheReactivationOverlay() {
        cursor();set("startupGateStatus",null);loop();tick(10_000)
        assertEquals(View.VISIBLE,overlay().visibility);assertEquals("Reactivating video... (Attempt 2/6)",(field("pikPakReactivationText") as TextView).text.toString())
    }
    @Test fun finishingAndDestroyedSuppressShowAndHideUiMutations() {
        for(destroy in listOf(false,true)) {
            overlay().visibility=View.VISIBLE;overlay().alpha=.5f
            if(destroy)destroyed(true)else finishing(true)
            gateHost("hidePikPakRetryOverlay",emptyArray());assertEquals(View.VISIBLE,overlay().visibility);assertEquals(.5f,overlay().alpha,0f)
            if(destroy)destroyed(false)else finishing(false)
        }
    }
    @Test fun shuffleExhaustionOwnsTheFailureBeforeManualGateAndAutoAdvance() {
        var rejected=0
        val a=attemptType.declaredConstructors.first { it.parameterCount==7 }.apply {isAccessible=true}.newInstance(field("mediaPreparationGeneration"),field("showShuffleGeneration"),false,{rejected++},false,null,false)
        set("pendingShufflePlayback",a);loop(5);tick(28_000);assertEquals(1,rejected);assertNull(field("pendingShufflePlayback"));assertNull(ShadowToast.getTextOfLatestToast())
    }
    @Test fun hideWithAnUnboundIndicatorIsSafe() {
        val bound=field("pikPakReactivationIndicator")
        try {
            set("pikPakReactivationIndicator",null)
            assertNull("unbound indicator hide is safe",runCatching { gateHost("hidePikPakRetryOverlay",emptyArray()) }.exceptionOrNull())
            assertNull(field("pikPakReactivationIndicator"))
        } finally { set("pikPakReactivationIndicator",bound) }
    }
    @Test fun exhaustionManualFailureRestoresInsteadOfAdvancing() {
        seriesItem();model().items[0]=model().items[0].copy(provider="pikpak");set("startupGateView",View(activity));manual();set("manualSourceMediaReplaced",true);loop(5);tick(28_000)
        assertNull(field("manualSourceSwitchSnapshot"));assertEquals(0,field("currentIndex"))
        assertEquals("This source is unavailable — choose another source",pill().text.toString());assertTrue(org.robolectric.shadows.ShadowLog.getLogs().any { it.msg.contains("reason=pikpak-exhausted") })
    }
    @Test fun exhaustionUncommittedStartupFailsItsCursorBeforeToast() {
        begin();loop(5);tick(28_000)
        assertEquals(true,field("startupSourcesExhausted"));assertTrue(activity.isFinishing)
        assertEquals("No playable source could be started",ShadowToast.getTextOfLatestToast())
    }
    @Test fun exhaustionFinishingSuppressesToastAndDelayedAdvance() {
        finishing(true);loop(5);tick(30_000);assertNull(ShadowToast.getTextOfLatestToast());assertEquals(0,field("currentIndex"))
    }
    @Test fun exhaustionDestroyedStillToastsBecauseOnlyFinishingIsChecked() {
        destroyed(true);loop(5);tick(28_000)
        assertEquals("Video failed to load. Skipping to next...",ShadowToast.getTextOfLatestToast());destroyed(false)
    }
    @Test fun onPauseInvalidatesRetryAndCancelsOwnedDelayedAdvance() {
        loop(5);tick(28_000);val id=field("pikPakRetryId") as Int
        lifecycle.pause();assertEquals(id+1,field("pikPakRetryId"));tick(2000);assertEquals(0,field("currentIndex"))
    }
    @Test fun playItemCancelsRetryBeforeStartingReplacementMedia() {
        set("isPikPakRetrying",true);set("pikPakRetryCount",3);val id=field("pikPakRetryId") as Int
        model().items[0]=model().items[0].copy(url="https://p10.invalid/direct.mp4",provider=null)
        probe.onEvent={ if(it.startsWith("media:")) { assertEquals(id+1,field("pikPakRetryId"));assertFalse(retrying());assertEquals(0,count()) } }
        call("playItem",arrayOf(intType,boolType,boolType,attemptType),0,false,false,null)
        assertTrue(probe.media.isNotEmpty());assertEquals(id+1,field("pikPakRetryId"))
    }
    @Test fun stremioTvMediaStartCancelsRetryWithoutPassingPlayItem() {
        set("isPikPakRetrying",true);val id=field("pikPakRetryId") as Int
        call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),p2Guide(),emptyMap<String,Any>(),"https://p10.invalid/tv.mp4","Programme",false)
        assertEquals(id+1,field("pikPakRetryId"));assertFalse(retrying());assertTrue(probe.media.isNotEmpty())
    }
    @Test fun destroyExplicitlyHidesIndicatorEvenThoughInlineHideIsGuarded() {
        overlay().visibility=View.VISIBLE;overlay().alpha=.8f;lifecycle.destroy()
        assertEquals(View.GONE,overlay().visibility);assertEquals("inline guarded hide preserves alpha; explicit cleanup only hides",.8f,overlay().alpha,0f)
    }
}
