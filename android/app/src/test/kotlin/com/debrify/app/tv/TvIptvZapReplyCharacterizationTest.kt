package com.debrify.app.tv
import android.os.Handler
import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvZapReplyCharacterizationTest : TvPhase11OriginalTest() {
    private fun stale(kind: String, condition: String, queued: Boolean) {
        var loaded = 0; var failed = 0
        page(failure = { failed++ }) { _,_,_,_,_ -> loaded++ }
        val request = messenger.requests.lastIndex
        queue().add(1); queue().add(-1)
        if (queued) { reply(kind, queued=true, request=request); assertTrue(field("iptvZapRequestInFlight") as Boolean) }
        when(condition) {
            "request" -> set("iptvZapRequestToken", (field("iptvZapRequestToken") as Int)+1)
            "context" -> set("iptvUiContextToken", (field("iptvUiContextToken") as Int)+1)
            "owner" -> set("iptvZapOwnsUiContext",false)
        }
        if (queued) idle() else reply(kind,request=request)
        assertEquals("old request preserves newer flag; matching stale request clears its flag",condition=="request",field("iptvZapRequestInFlight"))
        assertEquals("stale reply cannot invoke onLoaded",0,loaded)
        assertEquals("stale reply cannot invoke onFailure",0,failed)
        assertEquals("stale reply cannot clear pending inputs",listOf(1,-1),queue().toList())
        assertNull("stale reply cannot toast",ShadowToast.getTextOfLatestToast())
    }
    private fun accepted(kind: String, queued: Boolean) {
        var loaded=0; var failed=0
        page(failure={ assertFalse("flag clear before failure callback",field("iptvZapRequestInFlight") as Boolean); failed++ }) { _,_,_,_,_ ->
            assertFalse("flag clear before loaded callback",field("iptvZapRequestInFlight") as Boolean); loaded++
        }
        queue().add(1)
        reply(kind, queued=queued, message=null)
        if (queued) { assertEquals(0,loaded+failed); assertTrue(field("iptvZapRequestInFlight") as Boolean); idle() }
        assertFalse(field("iptvZapRequestInFlight") as Boolean)
        assertEquals(if(kind=="success")1 else 0,loaded)
        assertEquals(if(kind=="success")0 else 1,failed)
        assertEquals(if(kind=="success")listOf(1) else emptyList<Int>(),queue().toList())
        assertEquals(if(kind=="error")"Unable to load more channels" else null,ShadowToast.getTextOfLatestToast())
    }
    @Test fun successRequestInlinePinsAsymmetricCleanup() {
        stale("success","request",false)
    }
    @Test fun successContextInlinePinsAsymmetricCleanup() {
        stale("success","context",false)
    }
    @Test fun successOwnerInlinePinsAsymmetricCleanup() {
        stale("success","owner",false)
    }
    @Test fun successInlineClearsFlagBeforeCallback() {
        accepted("success",false)
    }
    @Test fun successRequestQueuedPinsAsymmetricCleanup() {
        stale("success","request",true)
    }
    @Test fun successContextQueuedPinsAsymmetricCleanup() {
        stale("success","context",true)
    }
    @Test fun successOwnerQueuedPinsAsymmetricCleanup() {
        stale("success","owner",true)
    }
    @Test fun successQueuedClearsFlagBeforeCallback() {
        accepted("success",true)
    }
    @Test fun errorRequestInlinePinsAsymmetricCleanup() {
        stale("error","request",false)
    }
    @Test fun errorContextInlinePinsAsymmetricCleanup() {
        stale("error","context",false)
    }
    @Test fun errorOwnerInlinePinsAsymmetricCleanup() {
        stale("error","owner",false)
    }
    @Test fun errorInlineClearsFlagBeforeCallback() {
        accepted("error",false)
    }
    @Test fun errorRequestQueuedPinsAsymmetricCleanup() {
        stale("error","request",true)
    }
    @Test fun errorContextQueuedPinsAsymmetricCleanup() {
        stale("error","context",true)
    }
    @Test fun errorOwnerQueuedPinsAsymmetricCleanup() {
        stale("error","owner",true)
    }
    @Test fun errorQueuedClearsFlagBeforeCallback() {
        accepted("error",true)
    }
    @Test fun missingRequestInlinePinsAsymmetricCleanup() {
        stale("missing","request",false)
    }
    @Test fun missingContextInlinePinsAsymmetricCleanup() {
        stale("missing","context",false)
    }
    @Test fun missingOwnerInlinePinsAsymmetricCleanup() {
        stale("missing","owner",false)
    }
    @Test fun missingInlineClearsFlagBeforeCallback() {
        accepted("missing",false)
    }
    @Test fun missingRequestQueuedPinsAsymmetricCleanup() {
        stale("missing","request",true)
    }
    @Test fun missingContextQueuedPinsAsymmetricCleanup() {
        stale("missing","context",true)
    }
    @Test fun missingOwnerQueuedPinsAsymmetricCleanup() {
        stale("missing","owner",true)
    }
    @Test fun missingQueuedClearsFlagBeforeCallback() {
        accepted("missing",true)
    }
}
