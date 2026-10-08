package com.debrify.app.tv

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.view.View
import androidx.recyclerview.widget.LinearLayoutManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvGuidePostSweepTest : TvPhase11OriginalTest() {
    private fun cancellation(showing: Boolean) {
        val overlay = field("iptvGuideOverlay") as View
        overlay.visibility = View.VISIBLE
        overlay.animate().cancel()
        var cancelled = false
        overlay.animate().translationY(37f).setDuration(1_000).setListener(object : AnimatorListenerAdapter() {
            override fun onAnimationCancel(animation: Animator) { cancelled = true }
        }).start()
        val running = overlay.animate().javaClass.getDeclaredField("mAnimatorMap").apply { isAccessible = true }.get(overlay.animate()) as Map<*, *>
        assertEquals(1, running.size)
        val animation = running.keys.single() as ValueAnimator
        animation.currentPlayTime = 30
        assertTrue(animation.isStarted)
        if (showing) show() else hide()
        assertTrue("guide ${if (showing) "show" else "hide"} cancels unrelated running translation", cancelled)
        assertFalse(animation.isStarted)
        advance(1_200)
        assertTrue(overlay.translationY < 37f)
        assertEquals(if (showing) View.VISIBLE else View.GONE, overlay.visibility)
        overlay.animate().setListener(null)
    }
    @Test fun showCancelsAllRunningOverlayProperties() = cancellation(true)
    @Test fun hideCancelsAllRunningOverlayProperties() = cancellation(false)

    private fun scrolling(showing: Boolean) {
        val current = channels()[1]
        channels().forEach { it.isCurrent = it === current }; adapter().updateChannels(channels()); set("currentIptvIndex", 1)
        val positions = mutableListOf<Int>()
        guideList().layoutManager = object : LinearLayoutManager(activity) {
            override fun scrollToPosition(position: Int) { positions.add(position); super.scrollToPosition(position) }
        }
        if (showing) show() else {
            show(); advance(250); positions.clear(); search().requestFocus()
            call("focusCurrentIptvGuideRow", emptyArray())
        }
        assertTrue("scroll is posted", positions.isEmpty())
        idle(); assertEquals("posted scroll uses adapter current position", listOf(1), positions)
        advance(250)
        val holder = guideList().findViewHolderForAdapterPosition(1)
        assertNotNull(holder); assertTrue(holder!!.itemView.hasFocus())
    }
    @Test fun showPostsScrollToCurrentAdapterRow() = scrolling(true)
    @Test fun focusPostsScrollToCurrentAdapterRow() = scrolling(false)

    @Test fun browseRowsScrollImmediatelyAndPostFirstRowFocusWhileEmptyRowsDoNeither() {
        show(); advance(250)
        val positions = mutableListOf<Int>()
        guideList().layoutManager = object : LinearLayoutManager(activity) {
            override fun scrollToPosition(position: Int) { positions.add(position); super.scrollToPosition(position) }
        }
        val source = field("iptvSourceButton") as View
        assertTrue(source.requestFocus()); browse()
        reply(value = response())
        assertEquals("nonempty reply scrolls to first result", listOf(0), positions)
        assertTrue("row focus is posted after adapter updates", source.hasFocus())
        idle()
        val holder = guideList().findViewHolderForAdapterPosition(0)
        assertNotNull(holder); assertTrue("result post focuses first bound row", holder!!.itemView.hasFocus())
        source.requestFocus(); positions.clear(); browse(); reply(value = response("channels" to emptyList<Any>()))
        idle(); assertTrue("empty reply does not scroll", positions.isEmpty()); assertTrue(source.hasFocus())
    }

    @Test fun showSchedulesCurrentRowFocusAtExactlyOneHundredFiftyMilliseconds() {
        val original = guideList()
        val delays = mutableListOf<Long>()
        val list = object : androidx.recyclerview.widget.RecyclerView(activity) {
            override fun postDelayed(action: Runnable, delayMillis: Long): Boolean {
                delays.add(delayMillis)
                return super.postDelayed(action, delayMillis)
            }
        }
        list.id = original.id
        list.layoutManager = LinearLayoutManager(activity)
        list.adapter = adapter()
        val parent = original.parent as android.view.ViewGroup
        val index = parent.indexOfChild(original)
        parent.removeView(original); parent.addView(list, index, original.layoutParams)
        set("iptvGuideList", list)
        show(); idle()
        assertEquals("guide focus delay at the RecyclerView boundary", listOf(150L), delays.filter { it > 0 })
        advance(200)
        val holder = list.findViewHolderForAdapterPosition(0)
        assertNotNull(holder); assertTrue(holder!!.itemView.hasFocus())
    }
}
