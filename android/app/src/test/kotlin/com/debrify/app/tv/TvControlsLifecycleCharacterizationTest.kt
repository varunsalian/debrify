package com.debrify.app.tv

import android.animation.ValueAnimator
import android.os.Handler
import android.view.View
import android.widget.ImageView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsLifecycleCharacterizationTest : TvPhase16OriginalTest() {
    @Test fun pauseAndStopLeaveTheTickerRunningAndUpdatingProgressGuards() {
        runOriginal("startSeekbarProgressUpdates"); step(0)
        lifecycle.pause(); lifecycle.stop(); probe.position = 40_000L; step(100)
        assertTrue(tickerPending()); assertEquals(40_000L, field("lastRealPositionMs"))
    }
    @Test fun destroyClearsBothOwnedHandlersAtTheirOriginalPositions() {
        assertEquals(listOf("progressHandler", "controlsHandler", "seekbarHandler", "releaseEffect"), TvControlsLifecycleBytecode.destroyOrder())
        set("controlsMenuVisible", true); runOriginal("scheduleHideControlsMenu"); runOriginal("startSeekbarProgressUpdates")
        val effects = mutableListOf<String>()
        (field("controlsHandler") as Handler).postDelayed({ effects.add("controls") }, 500)
        (field("seekbarHandler") as Handler).postDelayed({ effects.add("seek") }, 500)
        assertTrue(autoHidePending()); assertTrue(tickerPending()); destroyNow()
        assertFalse(autoHidePending()); assertFalse(tickerPending()); step(600); assertTrue(effects.isEmpty())
    }
    @Test fun destroyDoesNotCancelAnInFlightScrubAnimator() {
        drawScrub(); val animator = field("cinemaProgressAnimator") as ValueAnimator
        step(20); assertTrue(animator.isRunning); destroyNow(); assertTrue(animator.isRunning)
        step(60); assertFalse(animator.isRunning); assertEquals(500, v("debrifyProgressLine").layoutParams.width)
    }
    @Test fun uninitializedBackdropReturnsBeforeGlideAndDoesNotTouchTheOldView() {
        val image = v("nextBackdrop") as ImageView; image.visibility = View.INVISIBLE
        set("nextBackdrop", null)
        val result = runCatching { call("setNextOverlayBackdrop", arrayOf(String::class.java), "https://phase16.invalid/ignored") }
        assertTrue(result.isSuccess); assertEquals(View.INVISIBLE, image.visibility)
        set("nextBackdrop", image)
    }
    @Test fun startupGateVisibilitySuppressesSourceBadgeAndUninitializedGateAllowsIt() {
        @Suppress("UNCHECKED_CAST") val sources = field("stremioSources") as MutableList<StremioSource>
        sources.add(StremioSource(0, "Source", "hash", null, streamType = "torrent", sizeBytes = 1, seeders = 0, source = null, quality = "1080p"))
        val gate = v("startupGateView"); gate.visibility = View.VISIBLE; v("stremioSourceBadge").visibility = View.VISIBLE
        showDock(); assertEquals(View.GONE, v("stremioSourceBadge").visibility)
        set("startupGateView", null); showDock(); assertEquals(View.VISIBLE, v("stremioSourceBadge").visibility)
        set("startupGateView", gate); hideDock(); step(251); assertEquals(View.GONE, v("stremioSourceBadge").visibility)
    }
    @Test fun emptyClassicTitleStaysHiddenAndSeriesMetadataUsesTheOttHeader() {
        tv("titleView").text = ""; showDock(); assertEquals(View.GONE, v("titleContainer").visibility)
        hideDock(); step(251)
        val item = p2Item("", season = 2, episode = 7)
        set("payload", PlaybackPayload("Show", null, "series", mutableListOf(item), 0, "Show")); set("currentIndex", 0)
        showDock(); assertEquals(View.VISIBLE, v("titleContainer").visibility); assertEquals(1f, v("titleContainer").alpha, 0f)
        assertEquals(View.GONE, v("titleView").visibility); assertEquals(View.VISIBLE, v("titleOttContainer").visibility)
        runOriginal("hideTitleImmediately"); assertEquals(View.GONE, v("titleContainer").visibility); assertEquals(0f, v("titleContainer").alpha, 0f)
        assertEquals(View.VISIBLE, v("titleView").visibility); assertEquals(View.GONE, v("titleOttContainer").visibility)
    }
    @Test fun showExplicitlyReopensMedia3ParentControllerAndPostedFocusSurvivesHide() {
        pv().setControllerAnimationEnabled(false); pv().controllerAutoShow = false; pv().hideController(); assertFalse(pv().isControllerFullyVisible)
        class FocusProbe : androidx.appcompat.widget.AppCompatButton(activity) {
            val offers = mutableListOf<Boolean>()
            override fun requestFocus(direction: Int, rect: android.graphics.Rect?): Boolean {
                offers.add(field("controlsMenuVisible") as Boolean); return super.requestFocus(direction, rect)
            }
        }
        val pause = FocusProbe(); (v("controlsOverlay") as android.view.ViewGroup).addView(pause); set("pauseButton", pause)
        showDock(); assertTrue(pv().isControllerFullyVisible); hideDock(); step(17)
        assertEquals(listOf(false), pause.offers)
    }

}
