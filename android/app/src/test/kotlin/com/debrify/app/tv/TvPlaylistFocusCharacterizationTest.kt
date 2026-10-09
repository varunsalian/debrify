package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistFocusCharacterizationTest : TvPhase13OriginalTest() {
    private fun logs() = ShadowLog.getLogsForTag("PlaylistNav").map{it.msg}
    private fun visible() { set("playlistVisible",true);overlay().visibility=View.VISIBLE }
    private fun unfocused() { playlist().clearFocus();(field("playerView") as View).requestFocus() }
    private fun fakeRow(focus: Boolean=true)=TextView(activity).apply{isFocusable=focus;isFocusableInTouchMode=focus}
    private fun focusListeners(): Int {
        val array=ReflectionHelpers.getField<Any?>(playlist().viewTreeObserver,"mOnGlobalFocusListeners") ?: return 0
        return (array as List<*>).size
    }
    @Test fun focusSearchSkipsHeadersInBothDirectionsAndPinsAllBounds() {
        (playlist().adapter as PlaylistAdapter).filterBySeason(null)
        assertEquals(5,playlist().adapter?.itemCount)
        assertEquals(1,find(0,1));assertEquals(2,find(3,-1));assertEquals(4,find(3,1))
        assertEquals(-1,find(0,-1));assertEquals(-1,find(5,1));assertEquals(-1,find(-1,1))
        collection();assertEquals(0,find(0,-1));assertEquals(2,find(2,1));assertEquals(-1,find(3,1));assertEquals(-1,find(-1,1))
        set("seriesPlaylistAdapter",null);set("moviePlaylistAdapter",null);assertEquals(-1,find(0,1))
    }
    @Test fun rapidNavigationUsesPendingTargetAndStopsAtEachEdge() {
        (playlist().adapter as PlaylistAdapter).filterBySeason(null)
        set("navigationTargetPosition",1);move(1);assertEquals(2,target());assertTrue(navigating())
        val manager=playlist().layoutManager as androidx.recyclerview.widget.LinearLayoutManager
        assertEquals("off-screen move requests the target scroll",2,ReflectionHelpers.getField<Int>(manager,"mPendingScrollPosition"))
        assertEquals(100,ReflectionHelpers.getField<Int>(manager,"mPendingScrollPositionOffset"))
        move(1);assertEquals(4,target());assertTrue(navigating())
        assertEquals(4,ReflectionHelpers.getField<Int>(manager,"mPendingScrollPosition"))
        move(1);assertEquals(-1,target());assertFalse(navigating())
        set("navigationTargetPosition",0);move(-1);assertEquals(-1,target());assertFalse(navigating())
        set("navigationTargetPosition",1);move(-1);assertEquals(-1,target());assertFalse(navigating())
        val messages=logs()
        for(prefix in listOf("movePlaylistFocus: delta=","movePlaylistFocus: currentPosition=","movePlaylistFocus: searchStart=","movePlaylistFocus: Target not visible, using transferFocusToPosition","movePlaylistFocus: Already at end, ignoring","movePlaylistFocus: Already at start, ignoring","movePlaylistFocus: No valid target found or same position"))assertTrue(prefix,messages.any{it.startsWith(prefix)})
    }
    @Test fun missingAdapterAndManagerAndPositionClearMoveState() {
        playlist().adapter=null;set("navigationTargetPosition",8);move(1);assertEquals(-1,target());assertFalse(navigating())
        rebuild();playlist().layoutManager=null;set("navigationTargetPosition",8);move(1);assertEquals(-1,target());assertFalse(navigating())
        call("setupPlaylist",emptyArray());set("navigationTargetPosition",-1);move(1);assertEquals(-1,target());assertFalse(navigating())
        assertTrue(logs().contains("movePlaylistFocus: NO_POSITION, aborting"))
    }
    @Test fun transferWithoutLinearManagerClearsFlagButRetainsOriginalTarget() {
        playlist().layoutManager=null;set("navigationTargetPosition",8);set("isNavigating",true)
        transfer(1);assertFalse(navigating());assertEquals(8,target())
    }
    @Test fun transferGlobalLayoutSelfRemovalAndFiftyMillisecondReset() {
        open();transfer(0);assertTrue(navigating());assertEquals(0,target())
        val manager=playlist().layoutManager as androidx.recyclerview.widget.LinearLayoutManager
        assertEquals(0,ReflectionHelpers.getField<Int>(manager,"mPendingScrollPosition"))
        assertEquals(100,ReflectionHelpers.getField<Int>(manager,"mPendingScrollPositionOffset"))
        playlist().viewTreeObserver.dispatchOnGlobalLayout()
        assertTrue(navigating());advanceUi(49);assertTrue(navigating());assertEquals(0,target())
        advanceUi(1);assertFalse(navigating());assertEquals(-1,target())
        for(prefix in listOf("transferFocusToPosition: target=0","transferFocusToPosition: Focusing target at 0","transferFocusToPosition: Focus result=true for position 0"))assertTrue(prefix,logs().contains(prefix))
        set("navigationTargetPosition",7);set("isNavigating",true)
        playlist().viewTreeObserver.dispatchOnGlobalLayout();advanceUi(50)
        assertTrue("self-removal prevents a second callback",navigating());assertEquals(7,target())
    }
    @Test fun olderTransferResetUnconditionallyClearsNewerNavigation() {
        open();transfer(0);playlist().viewTreeObserver.dispatchOnGlobalLayout();advanceUi(49)
        set("navigationTargetPosition",7);set("isNavigating",true)
        advanceUi(1);assertFalse("original older reset clears newer state",navigating());assertEquals(-1,target())
    }
    @Test fun missingTransferHolderResetsBeforeFocusRecovery() {
        open();transfer(999);playlist().viewTreeObserver.dispatchOnGlobalLayout()
        assertFalse(navigating());assertEquals(-1,target())
        assertTrue(playlist().hasFocus())
        assertTrue(logs().any{it.contains("Holder not found or not focusable, using fallback")})
    }
    @Test fun directVisibleMoveKeepsTargetUntilHundredMillisecondReset() {
        (playlist().adapter as PlaylistOverlayAdapter).setActiveIndex(0)
        open();advanceUi(150);layout();set("navigationTargetPosition",0);move(1)
        for(message in listOf("showPlaylist: activePosition=0, adapter.itemCount=2","showPlaylist: Scrolling to position 0","showPlaylist: ViewHolder found=true for position 0","showPlaylist: Requesting focus on viewHolder at position 0"))assertTrue(message,logs().contains(message))
        assertTrue(logs().any{it.contains("Target visible, focusing directly")});assertTrue(navigating());assertEquals(1,target())
        advanceUi(99);assertTrue(navigating());assertEquals(1,target())
        advanceUi(1);assertFalse(navigating());assertEquals(-1,target())
        val listeners=ReflectionHelpers.getField<List<android.view.ViewTreeObserver.OnGlobalFocusChangeListener>>(playlist().viewTreeObserver,"mOnGlobalFocusListeners")
        playlist().scrollToPosition(0);layout();advanceUi(0);layout()
        val first=playlist().findViewHolderForAdapterPosition(0)!!.itemView
        val second=playlist().findViewHolderForAdapterPosition(1)!!.itemView
        ShadowLog.clear();listeners.forEach{it.onGlobalFocusChanged(first,second)}
        assertTrue(logs().any{it.startsWith("Focus changed: oldPos=0 -> newPos=1, newFocus=")})
        ShadowLog.clear();set("playlistVisible",false);listeners.forEach{it.onGlobalFocusChanged(first,second)}
        assertFalse("hidden overlay suppresses global-focus diagnostics",logs().any{it.startsWith("Focus changed:")})
    }
    @Test fun ensureFocusGuardsVisibilityNavigationAndExistingFocus() {
        ShadowLog.clear();set("playlistVisible",false);call("ensureFocusInPlaylist",emptyArray());assertFalse(logs().any{it.contains("Focus lost, recovering")})
        visible();set("isNavigating",true);call("ensureFocusInPlaylist",emptyArray());assertFalse(logs().any{it.contains("Focus lost, recovering")})
        set("isNavigating",false);open();playlist().requestFocus();ShadowLog.clear();call("ensureFocusInPlaylist",emptyArray());assertFalse(logs().any{it.contains("Focus lost, recovering")})
    }
    @Test fun ensureFocusPrefersVisibleRecentTargetOtherwiseSearchesMiddleOut() {
        open();advanceUi(150);layout();unfocused();set("navigationTargetPosition",1)
        ShadowLog.clear();call("ensureFocusInPlaylist",emptyArray());assertEquals(1,focusedPosition());assertTrue(logs().any{it.contains("Focusing recent target at 1")})
        assertTrue(logs().contains("ensureFocusInPlaylist: Focus lost, recovering..."))
        unfocused();set("navigationTargetPosition",999);ShadowLog.clear();call("ensureFocusInPlaylist",emptyArray())
        assertEquals(0,focusedPosition());assertTrue(logs().any{it.contains("(middle-out)")})
    }
    @Test fun attachRecoveryReplacesAndCancelsOlderIdentityAtExactDeadline() {
        visible();layout();advanceUi(17);unfocused();handler().removeCallbacksAndMessages(null);var old=0;val prior=Runnable{old++};handler().postDelayed(prior,100);set("focusRecoveryRunnable",prior)
        attachListener().onChildViewAttachedToWindow(fakeRow());val replacement=field("focusRecoveryRunnable")
        assertNotSame(prior,replacement);assertTrue(replacement is Runnable)
        ShadowLog.clear();advanceUi(99);assertEquals(0,old);assertFalse(logs().any{it.contains("Recovering focus after delay")})
        advanceUi(1);assertEquals(0,old);assertTrue(logs().any{it.contains("Recovering focus after delay")})
    }
    @Test fun attachRecoveryRejectsNavigatingHiddenAndUnfocusableRows() {
        val prior=Runnable{};set("focusRecoveryRunnable",prior)
        visible();set("isNavigating",true);attachListener().onChildViewAttachedToWindow(fakeRow());assertSame(prior,field("focusRecoveryRunnable"))
        set("isNavigating",false);set("playlistVisible",false);attachListener().onChildViewAttachedToWindow(fakeRow());assertSame(prior,field("focusRecoveryRunnable"))
        visible();attachListener().onChildViewAttachedToWindow(fakeRow(false));assertSame(prior,field("focusRecoveryRunnable"))
        assertTrue(logs().contains("onChildViewAttached: Skipping - navigation in progress"))
    }
    @Test fun queuedRecoveryReadsVisibilityAndNavigationAgainAtDelivery() {
        val listener=attachListener()
        set("playlistView",RecyclerView(activity)) // no framework focus acquisition can mask the delivery guards
        handler().removeCallbacksAndMessages(null);visible();set("isNavigating",false)
        listener.onChildViewAttachedToWindow(fakeRow());val hidden=field("focusRecoveryRunnable") as Runnable
        assertTrue(TvPlaylistUiQueue.pending(handler(),hidden));set("playlistVisible",false)
        ShadowLog.clear();advanceUi(120)
        assertFalse(TvPlaylistUiQueue.pending(handler(),hidden));assertFalse(logs().any{it.contains("Recovering focus after delay")})
        visible();listener.onChildViewAttachedToWindow(fakeRow());val navigating=field("focusRecoveryRunnable") as Runnable
        assertTrue(TvPlaylistUiQueue.pending(handler(),navigating));set("isNavigating",true)
        advanceUi(120);assertFalse(TvPlaylistUiQueue.pending(handler(),navigating));assertFalse(logs().any{it.contains("Recovering focus after delay")})
    }
    @Test fun focusedDetachSchedulesReplacementAndUnfocusedDetachDoesNothing() {
        visible();layout();advanceUi(17);unfocused();handler().removeCallbacksAndMessages(null);val row=fakeRow();assertTrue(row.requestFocus())
        val prior=Runnable{};set("focusRecoveryRunnable",prior);attachListener().onChildViewDetachedFromWindow(row)
        assertNotSame(prior,field("focusRecoveryRunnable"));val replacement=field("focusRecoveryRunnable")
        assertTrue(logs().contains("Focused view being detached, scheduling recovery"))
        attachListener().onChildViewDetachedFromWindow(fakeRow());assertSame(replacement,field("focusRecoveryRunnable"))
        ShadowLog.clear();advanceUi(100);assertTrue(logs().any{it.contains("Recovering focus after delay")})
    }
    @Test fun hideDoesNotCancelAlreadyPostedShowFocus() {
        (playlist().adapter as PlaylistOverlayAdapter).setActiveIndex(0)
        showPlaylist();hidePlaylist();idle();ShadowLog.clear();advanceUi(200)
        assertFalse(field("playlistVisible") as Boolean)
        assertTrue("posted focus lookup still runs while hidden",logs().any{it.contains("ViewHolder found=")})
    }
    @Test fun rebuildRetainsQueuedViewFocusWorkAndAddsGlobalFocusListener() {
        (playlist().adapter as PlaylistOverlayAdapter).setActiveIndex(0)
        showPlaylist();idle();val before=focusListeners();rebuild()
        assertEquals(before+1,focusListeners());rebuild();assertEquals(before+2,focusListeners())
        ShadowLog.clear();advanceUi(200);assertTrue(logs().any{it.contains("ViewHolder found=")})
    }
    @Test fun destroyClearsOwnedRecoveryWhileQueuedViewLookupSurvives() {
        (playlist().adapter as PlaylistOverlayAdapter).setActiveIndex(0)
        showPlaylist();layout();advanceUi(50)
        assertTrue("outer View post has scheduled the delayed lookup",logs().any{it.contains("Scrolling to position 0")})
        assertFalse(logs().any{it.contains("ViewHolder found=")})
        var fired=0;handler().postDelayed({fired++},100)
        destroyNow();ShadowLog.clear();advanceUi(200)
        assertEquals(0,fired);assertNull(field("focusRecoveryRunnable"))
        assertTrue("already queued lookup still runs after destroy",logs().any{it.contains("ViewHolder found=")})
        assertTrue(logs().contains("showPlaylist: Requesting focus on playlistView itself"))
    }
    @Test fun detachGatesAndReplacementCancelTheOldRunnable() {
        visible();layout();advanceUi(17);unfocused()
        val row=fakeRow();assertTrue(row.requestFocus())
        var old=0;val prior=Runnable{old++};handler().postDelayed(prior,100);set("focusRecoveryRunnable",prior)
        set("isNavigating",true);attachListener().onChildViewDetachedFromWindow(row);assertSame(prior,field("focusRecoveryRunnable"))
        set("isNavigating",false);set("playlistVisible",false);attachListener().onChildViewDetachedFromWindow(row);assertSame(prior,field("focusRecoveryRunnable"))
        visible();attachListener().onChildViewDetachedFromWindow(row);assertNotSame(prior,field("focusRecoveryRunnable"))
        advanceUi(100);assertEquals(0,old)
    }
    @Test fun queuedRecoveryDoesNotStealExistingFocusForAttachOrDetach() {
        open();advanceUi(150);layout()
        for(detach in listOf(false,true)) {
            val row=fakeRow();assertTrue(row.requestFocus())
            if(detach)attachListener().onChildViewDetachedFromWindow(row) else attachListener().onChildViewAttachedToWindow(row)
            assertTrue(playlist().requestFocus());assertTrue(playlist().hasFocus())
            val scheduled=field("focusRecoveryRunnable") as Runnable
            assertTrue(TvPlaylistUiQueue.pending(handler(),scheduled))
            ShadowLog.clear();advanceUi(120)
            assertFalse("scheduled recovery actually delivered",TvPlaylistUiQueue.pending(handler(),scheduled))
            assertFalse(logs().any{it.contains("Recovering focus after delay")})
        }
    }
    @Test fun moveReadsFocusedChildBeforeFirstVisibleAndZeroDeltaDoesNotNavigate() {
        open();advanceUi(150);layout();assertTrue(playlist().findViewHolderForAdapterPosition(1)!!.itemView.requestFocus())
        set("navigationTargetPosition",-1);move(-1);assertEquals(0,target())
        set("navigationTargetPosition",1);move(0);assertEquals(-1,target());assertFalse(navigating())
    }
    @Test fun ensureFocusWithEmptyLayoutOrNonLinearManagerLeavesFocusOutside() {
        visible();unfocused();playlist().adapter=null;layout();call("ensureFocusInPlaylist",emptyArray());assertFalse(playlist().hasFocus())
        playlist().layoutManager=null;call("ensureFocusInPlaylist",emptyArray());assertFalse(playlist().hasFocus())
    }
    @Test fun showFallbackFocusIsPostedAndClassicKeyLogsKeepDirectionAndVisibility() {
        (playlist().adapter as PlaylistOverlayAdapter).setActiveIndex(-1)
        ShadowLog.clear();call("setupPlaylistNavigation",emptyArray());showPlaylist();layout();advanceUi(17)
        assertTrue(logs().any{it.contains("No active position, requesting focus on playlistView")})
        assertTrue(playlist().hasFocus())
        set("navigationTargetPosition",0);key(android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
        key(android.view.KeyEvent.KEYCODE_DPAD_LEFT);key(android.view.KeyEvent.KEYCODE_DPAD_UP)
        hidePlaylist();key(android.view.KeyEvent.KEYCODE_DPAD_RIGHT)
        val messages=logs();assertTrue(messages.contains("setupPlaylistNavigation: Setting up navigation"));assertTrue(messages.any{it.startsWith("Focus changed: oldPos=")});assertTrue(messages.contains("DPAD_RIGHT pressed"));assertTrue(messages.contains("DPAD_LEFT pressed"))
        assertTrue(messages.contains("UP/DOWN pressed - allowing navigation to season tabs"));assertTrue(messages.any{it.startsWith("Key event but playlist not visible:")})
        pinPostedShowFocusRequests()
    }

    private fun pinPostedShowFocusRequests() {
        val adapter=field("playlistAdapter") as PlaylistOverlayAdapter
        var childFocus=0;var containerFocus=0
        val child=object: View(activity) {
            override fun requestFocus(direction: Int,rect: android.graphics.Rect?): Boolean { childFocus++;return true }
        }
        val holder=object: RecyclerView.ViewHolder(child){}
        val queue=android.os.Handler(android.os.Looper.getMainLooper())
        val scrolls=mutableListOf<Int>()
        var present=true
        val rows=object: RecyclerView(activity) {
            override fun findViewHolderForAdapterPosition(position: Int): RecyclerView.ViewHolder? = if(present)holder else null
            override fun scrollToPosition(position: Int) { scrolls.add(position) }
            override fun post(action: Runnable): Boolean = queue.post(action)
            override fun postDelayed(action: Runnable,delay: Long): Boolean = queue.postDelayed(action,delay)
            override fun requestFocus(direction: Int,rect: android.graphics.Rect?): Boolean { containerFocus++;return true }
        }
        rows.adapter=playlist().adapter;rows.layoutManager=androidx.recyclerview.widget.LinearLayoutManager(activity)
        set("playlistView",rows)
        adapter.setActiveIndex(0);showPlaylist();advanceUi(0)
        assertEquals(listOf(0),scrolls);assertEquals(0,childFocus)
        advanceUi(99);assertEquals(0,childFocus)
        advanceUi(1);assertEquals(1,childFocus);assertEquals(0,containerFocus)
        present=false;showPlaylist();advanceUi(100)
        assertEquals(1,childFocus);assertEquals(1,containerFocus)
        adapter.setActiveIndex(-1);showPlaylist();advanceUi(0)
        assertEquals("no active row requests container focus through the installed post",2,containerFocus)
    }

}
