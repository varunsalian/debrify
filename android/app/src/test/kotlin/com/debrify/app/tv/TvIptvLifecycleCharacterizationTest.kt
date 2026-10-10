package com.debrify.app.tv

import android.content.Context
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.Shadows.shadowOf

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@org.robolectric.annotation.Config(sdk=[32],shadows=[TvIptvHandlerRemovalShadow::class])
internal class TvIptvLifecycleCharacterizationTest : TvPhase17OriginalTest() {
    private fun foreground() {bootstrap();lifecycle.start().resume();quiet();probe.events.clear()}
    private fun stop() {lifecycle.pause().stop();quiet()}
    private fun pill()=reconnectPill()
    @Test fun stopParksTrialCancelsRecoveryThenHidesPillAndOnlyThenPauses() {
        foreground();begin();quiet();invoke("showIptvReconnectPill","old");recovery().setOffline(false);recovery().onEnded()
        val token=field("iptvCatchupToken") as Int
        val machine=recovery();val handler=TvPlayerOriginalAccess.field(machine,"handler") as Handler
        val pending=TvPlayerOriginalAccess.field(machine,"pending") as Runnable
        val cancellations=mutableListOf<List<Any?>>()
        TvIptvHandlerRemovalShadow.observe={owner,action -> if(owner===handler && action===pending) {
            cancellations.add(listOf(trial(),field("iptvTwinTrialRestoreOriginal"),pill().visibility,
                field("iptvStoppedAtRealtime"),probe.playIntent,field("iptvCatchupToken")))
        }}
        probe.onEvent={if(it=="pause") {assertEquals(token+1,field("iptvCatchupToken"));assertNull(trial());assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("iptvTwinTrialRestoreTwin"));assertNull(TvPlayerOriginalAccess.field(recovery(),"pending"));assertFalse(TvPlayerOriginalAccess.field(recovery(),"episodeActive") as Boolean);assertEquals(View.GONE,pill().visibility);assertEquals(SystemClock.elapsedRealtime(),field("iptvStoppedAtRealtime"))}}
        stop();TvIptvHandlerRemovalShadow.observe=null
        assertEquals(listOf(listOf(null,original,View.VISIBLE,0L,true,token+1)),cancellations)
        assertFalse(probe.playIntent);advance(40_000);assertEquals(twin,field("currentIptvStreamUrl"));assertTrue(failed().isEmpty())
    }
    @Test fun stopClearsASupersededUnparkableTrialWithoutCreatingARollbackPair() {
        foreground();begin();quiet();val old=timeout();val handler=field("iptvTwinTrialHandler") as Handler
        set("currentIptvStreamUrl","http://h/replacement.ts");stop()
        assertNull(trial());assertNull(field("iptvTwinTrialOriginalUrl"));assertNull(field("iptvTwinTrialTimeout"))
        assertFalse(TvPlaylistUiQueue.pending(handler,old));assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"))
        assertTrue(failed().isEmpty());assertEquals("http://h/replacement.ts",field("currentIptvStreamUrl"))
    }
    @Test fun resumeConsumesParkedRestoreBeforeLongAbsenceOrOrdinaryPlay() {
        foreground();begin();quiet();stop();advance(31_000);probe.events.clear();lifecycle.start();quiet()
        assertEquals(original,field("currentIptvStreamUrl"));assertNull(field("iptvTwinTrialRestoreOriginal"));assertEquals(1,tuning().size);assertEquals(1,probe.events.count {it=="play"})
    }
    @Test fun exactThirtySecondAbsenceKeepsTheBufferButLongerRejoinsThroughRecovery() {
        foreground();recovery().setOffline(false);stop();advance(30_000);probe.events.clear();lifecycle.start();advance(0);quiet();assertTrue(tuning().isEmpty());assertEquals(listOf("play"),probe.events)
        lifecycle.resume();stop();advance(30_001);probe.events.clear();lifecycle.start();advance(0);quiet();assertEquals(1,tuning().size);assertEquals("intent:true",probe.events.first())
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("lifecycle-rejoin")})
    }
    @Test fun sleepLatchPreventsAllResumePlaybackIncludingParkedRestore() {
        foreground();begin();quiet();stop();set("sleepStopLatched",true);advance(31_000);probe.events.clear();lifecycle.start();advance(0);quiet()
        assertTrue(probe.events.isEmpty());assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("currentIptvStreamUrl"))
    }
    @Test fun activeStartOverDoesNotRejoinLiveAfterLongAbsence() {
        foreground();stop();set("iptvStartOverActive",true);advance(31_000);probe.events.clear();lifecycle.start();advance(0);quiet();assertEquals(listOf("play"),probe.events);assertTrue(tuning().isEmpty())
    }
    @Test fun destroyClearsTrialBeforeRecoveryCancellationAndNetworkUnregister() {
        foreground();begin();quiet();val machine=recovery();machine.setOffline(false);machine.onEnded();val cancellations=mutableListOf<String>()
        val cb=field("iptvNetworkCallback") as ConnectivityManager.NetworkCallback
        val cm=activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val handler=TvPlayerOriginalAccess.field(machine,"handler") as Handler
        val pending=TvPlayerOriginalAccess.field(machine,"pending") as Runnable
        TvIptvHandlerRemovalShadow.observe={owner,action -> if(owner===handler && action===pending) {
            cancellations.add("${trial()}|${shadowOf(cm).networkCallbacks.contains(cb)}")
        }}
        lifecycle.destroy();booted=false;TvIptvHandlerRemovalShadow.observe=null;assertEquals(listOf("null|true"),cancellations);assertFalse(shadowOf(cm).networkCallbacks.contains(cb));assertNull(TvPlayerOriginalAccess.field(machine,"pending"));assertNull(field("iptvTwinTrialTimeout"))
    }
    @Test fun destroyRetainsPillParkedPairAndUnrelatedTrialHandlerMessages() {
        foreground();set("iptvTwinTrialRestoreOriginal",original);set("iptvTwinTrialRestoreTwin",twin);invoke("showIptvReconnectPill","old");val p=pill();var foreign=false
        (field("iptvTwinTrialHandler") as Handler).postDelayed({foreign=true},100);lifecycle.destroy();booted=false
        assertSame(p,field("iptvReconnectPill"));assertNotNull(p.parent);assertEquals(View.VISIBLE,p.visibility);assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("iptvTwinTrialRestoreTwin"));advance(100);assertTrue(foreign)
    }
    @Test fun destroyedTrialFailureDoesNotBlacklistOrRestore() {
        foreground();lifecycle.destroy();booted=false;set("iptvTwinTrialOriginalUrl",original);set("iptvTwinTrialUrl",twin);set("currentIptvStreamUrl",twin);probe.events.clear()
        invoke("failIptvTwinTrial","error");assertNull(trial());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty());assertFalse(invoke("iptvLiveRecoveryEligible") as Boolean)
    }
    @Test fun vodStopPreservesTheOriginalFirstAccessLazyConstructionToCancel() {
        // No lifecycle bootstrap is needed to observe the original override and lazy delegate.
        bootstrapVod();val deferred=field("iptvLiveRecovery\$delegate") as Lazy<*>;assertFalse(deferred.isInitialized());invoke("onStop");assertTrue(deferred.isInitialized());assertNull(TvPlayerOriginalAccess.field(deferred.value!!,"pending"))
    }
    @Test fun vodDestroyAlsoConstructsRecoveryOnlyToCancelIt() {
        bootstrapVod();val deferred=field("iptvLiveRecovery\$delegate") as Lazy<*>;assertFalse(deferred.isInitialized());lifecycle.destroy();booted=false;assertTrue(deferred.isInitialized());assertFalse(TvPlayerOriginalAccess.field(deferred.value!!,"episodeActive") as Boolean)
    }
}
