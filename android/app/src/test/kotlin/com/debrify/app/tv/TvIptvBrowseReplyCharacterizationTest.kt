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
internal class TvIptvBrowseReplyCharacterizationTest : TvPhase11OriginalTest() {
    private fun stale(kind: String, condition: String, queued: Boolean) {
        val original=browseChannels().toList()
        browse(); val request=messenger.requests.lastIndex
        if(queued) reply(kind,queued=true,request=request)
        when(condition) {
            "request" -> set("iptvBrowseToken",(field("iptvBrowseToken") as Int)+1)
            "context" -> set("iptvUiContextToken",(field("iptvUiContextToken") as Int)+1)
            "owner" -> set("iptvZapOwnsUiContext",true)
        }
        if(queued) idle() else reply(kind,request=request)
        assertEquals("stale browse leaves current loading owner visible",View.VISIBLE,(field("iptvBrowseLoading") as View).visibility)
        assertEquals(original,browseChannels())
        assertNull(ShadowToast.getTextOfLatestToast())
    }
    private fun accepted(kind: String,queued: Boolean) {
        browse();reply(kind,queued=queued,message=null)
        if(queued) { assertEquals(View.VISIBLE,(field("iptvBrowseLoading") as View).visibility);idle() }
        assertEquals("accepted browse ends loading",View.GONE,(field("iptvBrowseLoading") as View).visibility)
        if(kind=="success") assertEquals("Reply",browseChannels().single().name)
        assertEquals(if(kind=="error")"Unable to load IPTV catalog" else null,ShadowToast.getTextOfLatestToast())
    }
    @Test fun successRequestInlineIgnoresStaleBrowse() {
        stale("success","request",false)
    }
    @Test fun successContextInlineIgnoresStaleBrowse() {
        stale("success","context",false)
    }
    @Test fun successOwnerInlineIgnoresStaleBrowse() {
        stale("success","owner",false)
    }
    @Test fun successInlineAppliesCurrentBrowse() {
        accepted("success",false)
    }
    @Test fun successRequestQueuedIgnoresStaleBrowse() {
        stale("success","request",true)
    }
    @Test fun successContextQueuedIgnoresStaleBrowse() {
        stale("success","context",true)
    }
    @Test fun successOwnerQueuedIgnoresStaleBrowse() {
        stale("success","owner",true)
    }
    @Test fun successQueuedAppliesCurrentBrowse() {
        accepted("success",true)
    }
    @Test fun errorRequestInlineIgnoresStaleBrowse() {
        stale("error","request",false)
    }
    @Test fun errorContextInlineIgnoresStaleBrowse() {
        stale("error","context",false)
    }
    @Test fun errorOwnerInlineIgnoresStaleBrowse() {
        stale("error","owner",false)
    }
    @Test fun errorInlineAppliesCurrentBrowse() {
        accepted("error",false)
    }
    @Test fun errorRequestQueuedIgnoresStaleBrowse() {
        stale("error","request",true)
    }
    @Test fun errorContextQueuedIgnoresStaleBrowse() {
        stale("error","context",true)
    }
    @Test fun errorOwnerQueuedIgnoresStaleBrowse() {
        stale("error","owner",true)
    }
    @Test fun errorQueuedAppliesCurrentBrowse() {
        accepted("error",true)
    }
    @Test fun missingRequestInlineIgnoresStaleBrowse() {
        stale("missing","request",false)
    }
    @Test fun missingContextInlineIgnoresStaleBrowse() {
        stale("missing","context",false)
    }
    @Test fun missingOwnerInlineIgnoresStaleBrowse() {
        stale("missing","owner",false)
    }
    @Test fun missingInlineAppliesCurrentBrowse() {
        accepted("missing",false)
    }
    @Test fun missingRequestQueuedIgnoresStaleBrowse() {
        stale("missing","request",true)
    }
    @Test fun missingContextQueuedIgnoresStaleBrowse() {
        stale("missing","context",true)
    }
    @Test fun missingOwnerQueuedIgnoresStaleBrowse() {
        stale("missing","owner",true)
    }
    @Test fun missingQueuedAppliesCurrentBrowse() {
        accepted("missing",true)
    }
}
