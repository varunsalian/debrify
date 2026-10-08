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
internal class TvIptvJumpReplyCharacterizationTest : TvPhase11OriginalTest() {
    private fun checkReply(kind:String,condition:String,queued:Boolean) {
        set("iptvUiContextToken",0);jump();val request=messenger.requests.lastIndex
        if(queued) reply(kind,response("channelNotFound" to true),true,request,message=null)
        when(condition) {
            "request" -> set("iptvZapRequestToken",(field("iptvZapRequestToken") as Int)+1)
            "context" -> set("iptvUiContextToken",1)
            "owner" -> set("iptvZapOwnsUiContext",false)
        }
        if(queued) idle() else reply(kind,response("channelNotFound" to true),false,request,message=null)
        assertEquals("channel jump checks request token only",condition=="request",field("iptvZapRequestInFlight"))
        val expected=if(condition=="request")null else when(kind) {
            "success" -> "Channel 7 was not found"
            "error" -> "Unable to look up that channel"
            else -> "Channel lookup is unavailable"
        }
        assertEquals(expected,ShadowToast.getTextOfLatestToast())
    }
    @Test fun successRequestInlinePinsRequestOnlyJumpGuard() {
        checkReply("success","request",false)
    }
    @Test fun successContextInlinePinsRequestOnlyJumpGuard() {
        checkReply("success","context",false)
    }
    @Test fun successOwnerInlinePinsRequestOnlyJumpGuard() {
        checkReply("success","owner",false)
    }
    @Test fun successRequestQueuedPinsRequestOnlyJumpGuard() {
        checkReply("success","request",true)
    }
    @Test fun successContextQueuedPinsRequestOnlyJumpGuard() {
        checkReply("success","context",true)
    }
    @Test fun successOwnerQueuedPinsRequestOnlyJumpGuard() {
        checkReply("success","owner",true)
    }
    @Test fun errorRequestInlinePinsRequestOnlyJumpGuard() {
        checkReply("error","request",false)
    }
    @Test fun errorContextInlinePinsRequestOnlyJumpGuard() {
        checkReply("error","context",false)
    }
    @Test fun errorOwnerInlinePinsRequestOnlyJumpGuard() {
        checkReply("error","owner",false)
    }
    @Test fun errorRequestQueuedPinsRequestOnlyJumpGuard() {
        checkReply("error","request",true)
    }
    @Test fun errorContextQueuedPinsRequestOnlyJumpGuard() {
        checkReply("error","context",true)
    }
    @Test fun errorOwnerQueuedPinsRequestOnlyJumpGuard() {
        checkReply("error","owner",true)
    }
    @Test fun missingRequestInlinePinsRequestOnlyJumpGuard() {
        checkReply("missing","request",false)
    }
    @Test fun missingContextInlinePinsRequestOnlyJumpGuard() {
        checkReply("missing","context",false)
    }
    @Test fun missingOwnerInlinePinsRequestOnlyJumpGuard() {
        checkReply("missing","owner",false)
    }
    @Test fun missingRequestQueuedPinsRequestOnlyJumpGuard() {
        checkReply("missing","request",true)
    }
    @Test fun missingContextQueuedPinsRequestOnlyJumpGuard() {
        checkReply("missing","context",true)
    }
    @Test fun missingOwnerQueuedPinsRequestOnlyJumpGuard() {
        checkReply("missing","owner",true)
    }
}
