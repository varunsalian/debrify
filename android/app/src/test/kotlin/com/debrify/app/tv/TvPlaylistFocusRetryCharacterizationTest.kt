package com.debrify.app.tv

import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.LinearLayoutManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** A focus-rejecting child makes the original retry branch deterministic. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistFocusRetryCharacterizationTest : TvPhase13OriginalTest() {
    private class RejectFocus(context: android.content.Context): View(context) {
        var attempts=0
        var onAttempt: ((Int)->Unit)?=null
        override fun requestFocus(direction: Int,previouslyFocusedRect: Rect?): Boolean { attempts++;onAttempt?.invoke(attempts);return false }
    }
    private class Rows(context: android.content.Context,val holder: RecyclerView.ViewHolder): RecyclerView(context) {
        private val queue=Handler(Looper.getMainLooper())
        var present=true
        override fun findViewHolderForAdapterPosition(position: Int): RecyclerView.ViewHolder? = if(present)holder else null
        override fun post(action: Runnable): Boolean = queue.post(action)
        override fun postDelayed(action: Runnable,delayMillis: Long): Boolean = queue.postDelayed(action,delayMillis)
    }
    private fun rows(): Pair<Rows,RejectFocus> {
        val row=RejectFocus(activity).apply{isFocusable=true;isFocusableInTouchMode=true}
        FrameLayout(activity).addView(row)
        val holder=object: RecyclerView.ViewHolder(row){}
        return Rows(activity,holder).apply{adapter=playlist().adapter;layoutManager=LinearLayoutManager(activity);set("playlistView",this)} to row
    }
    @Test fun rejectedTransferFocusRetriesOnceAtFiftyMillisecondsAndClearsState() {
        val (view,row)=rows()
        row.onAttempt={attempt->if(attempt==2){
            assertFalse("the first reset runs before retrying focus",navigating());assertEquals(-1,target())
            set("isNavigating",true);set("navigationTargetPosition",7)
        }}
        transfer(1);assertEquals(0,row.attempts)
        view.viewTreeObserver.dispatchOnGlobalLayout();assertEquals(1,row.attempts);assertTrue(navigating());assertEquals(1,target())
        advanceUi(49);assertEquals(1,row.attempts);assertTrue(navigating())
        advanceUi(1);assertEquals(2,row.attempts);assertFalse(navigating());assertEquals(-1,target())
    }
    @Test fun directFocusFailureUsesTransferAndItsRetryWithoutCancellingOlderReset() {
        val (view,row)=rows();set("navigationTargetPosition",0);move(1)
        assertEquals(1,row.attempts);assertTrue(navigating());assertEquals(1,target())
        view.viewTreeObserver.dispatchOnGlobalLayout();assertEquals(2,row.attempts)
        advanceUi(50);assertEquals(3,row.attempts);assertFalse(navigating())
        set("navigationTargetPosition",7);set("isNavigating",true)
        advanceUi(50);assertFalse("older direct reset remains unconditional",navigating());assertEquals(-1,target())
    }
    @Test fun retryRereadsHolderAndStillClearsStateWhenTheChildDisappears() {
        val (view,row)=rows();transfer(1);view.viewTreeObserver.dispatchOnGlobalLayout();assertEquals(1,row.attempts)
        view.present=false;advanceUi(50);assertEquals(1,row.attempts);assertFalse(navigating());assertEquals(-1,target())
    }
}
