package com.debrify.app.tv

import android.os.Handler
import android.view.View
import androidx.appcompat.widget.AppCompatButton
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsTimerCharacterizationTest : TvPhase16OriginalTest() {
    private fun autoHideDeadline(): Long? {
        val handler = field("controlsHandler") as Handler
        val action = field("hideControlsRunnable") as Runnable
        var message = org.robolectric.util.ReflectionHelpers.getField<android.os.Message?>(android.os.Looper.getMainLooper().queue, "mMessages")
        while (message != null) {
            if (message.target === handler && message.callback === action) return message.`when`
            message = org.robolectric.util.ReflectionHelpers.getField(message, "next")
        }
        return null
    }
    @Test fun playingAutoHideWaitsExactlyFourSecondsAndRemovesAnOlderDeadline() {
        set("controlsMenuVisible", true); v("controlsOverlay").visibility = View.VISIBLE
        runOriginal("scheduleHideControlsMenu"); step(2000); runOriginal("scheduleHideControlsMenu")
        step(3999); assertTrue(field("controlsMenuVisible") as Boolean); assertTrue(autoHidePending())
        step(1); assertFalse(field("controlsMenuVisible") as Boolean); assertFalse(autoHidePending())
    }
    @Test fun pausedVisibleDockCancelsTheDeadlineWithoutSchedulingAnother() {
        set("controlsMenuVisible", true); runOriginal("scheduleHideControlsMenu"); assertTrue(autoHidePending())
        probe.playing = false; runOriginal("scheduleHideControlsMenu")
        assertFalse(autoHidePending()); step(4001); assertTrue(field("controlsMenuVisible") as Boolean)
    }
    @Test fun hiddenScheduleReturnsWithoutRemovingAnExistingCallback() {
        val h = field("controlsHandler") as Handler; h.postDelayed(field("hideControlsRunnable") as Runnable, 1000)
        val deadline = android.os.SystemClock.uptimeMillis() + 1000
        runOriginal("scheduleHideControlsMenu"); assertTrue(autoHidePending()); assertEquals(deadline, autoHideDeadline())
        runOriginal("cancelScheduledHideControlsMenu"); assertFalse(autoHidePending())
    }
    @Test fun focusedChildKeepsTheDockAliveAndRearmsTheFourSecondDeadline() {
        set("controlsMenuVisible", true); v("controlsOverlay").visibility = View.VISIBLE
        val child = AppCompatButton(activity).apply { isFocusableInTouchMode = true }
        (v("controlsOverlay") as android.view.ViewGroup).addView(child); assertTrue(child.requestFocus())
        org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(child)
        assertEquals(true, runOriginal("isFocusInControlsOverlay"))
        (field("hideControlsRunnable") as Runnable).run()
        assertTrue(field("controlsMenuVisible") as Boolean); assertTrue(autoHidePending())
        org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(null)
        assertEquals(false, runOriginal("isFocusInControlsOverlay")); step(4000)
        assertFalse(field("controlsMenuVisible") as Boolean)
    }
    @Test fun outsideAndAbsentDockAreNotControlsFocus() {
        org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(v("titleView"))
        assertEquals(false, runOriginal("isFocusInControlsOverlay"))
        set("controlsOverlay", null); assertEquals(false, runOriginal("isFocusInControlsOverlay"))
    }
    @Test fun tickerRunsImmediatelyThenEveryHundredMsAndStopRemovesItsCallback() {
        set("maxStableDurationMs", 0L); set("lastRealPositionMs", -1L)
        runOriginal("startSeekbarProgressUpdates"); assertTrue(tickerPending()); step(0)
        assertEquals(100_000L, field("maxStableDurationMs")); assertEquals(25_000L, field("lastRealPositionMs"))
        probe.position = 30_000; step(99); assertEquals(25_000L, field("lastRealPositionMs"))
        step(1); assertEquals(30_000L, field("lastRealPositionMs")); assertTrue(tickerPending())
        runOriginal("stopSeekbarProgressUpdates"); assertFalse(tickerPending())
    }
    @Test fun startingTickerTwiceStillProducesOneHundredMsCallback() {
        runOriginal("startSeekbarProgressUpdates"); runOriginal("startSeekbarProgressUpdates")
        step(0); reads.clear(); step(100)
        assertEquals(1, reads.count { it == "position" }); assertTrue(tickerPending())
    }
    @Test fun tickerSkipsCinemaNullPlayerAndNonpositiveDurationsWithoutWritingGuards() {
        set("lastRealPositionMs", 123L); set("maxStableDurationMs", 200_000L)
        set("cinemaSeekMode", true); runOriginal("updateSeekbarProgress"); assertTrue(reads.isEmpty())
        set("cinemaSeekMode", false); set("player", null); val absent = runCatching { runOriginal("updateSeekbarProgress") }; assertTrue(absent.isSuccess); assertTrue(reads.isEmpty())
        originalPlayer(); probe.duration = 0; runOriginal("updateSeekbarProgress")
        assertEquals(123L, field("lastRealPositionMs")); assertEquals(200_000L, field("maxStableDurationMs"))
        assertFalse(reads.contains("buffered"))
    }
    @Test fun tickerDoesNotShrinkStableDurationOrAcceptAnOutOfRangeRealPosition() {
        set("maxStableDurationMs", 200_000L); set("lastRealPositionMs", 123L)
        for (position in listOf(-1L, 100_001L)) { probe.position = position; runOriginal("updateSeekbarProgress") }
        assertEquals(200_000L, field("maxStableDurationMs")); assertEquals(123L, field("lastRealPositionMs"))
        probe.position = 0; runOriginal("updateSeekbarProgress"); assertEquals(0L, field("lastRealPositionMs"))
        probe.position = 100_000; runOriginal("updateSeekbarProgress"); assertEquals(100_000L, field("lastRealPositionMs"))
    }
    @Test fun tickerPaintsCurrentTotalCombinedPlayedAndClampedBufferedProgress() {
        val line = v("debrifyProgressLine"); val parent = line.parent as View; parent.layout(0, 0, 1000, 10)
        val bufferedView = v("cinemaProgressBuffered"); (bufferedView.parent as View).layout(0, 0, 1000, 10)
        runOriginal("updateSeekbarProgress")
        assertEquals("00:25", tv("debrifyTimeCurrent").text.toString()); assertEquals("01:40", tv("debrifyTimeTotal").text.toString())
        assertEquals("00:25 / 01:40", tv("debrifyTimeDisplay").text.toString()); assertEquals(250, line.layoutParams.width)
        assertEquals(700, bufferedView.layoutParams.width)
        buffered = -1; runOriginal("updateSeekbarProgress"); assertEquals(0, bufferedView.layoutParams.width)
        buffered = 100_001; runOriginal("updateSeekbarProgress"); assertEquals(1000, bufferedView.layoutParams.width)
        parent.layout(0, 0, 0, 10); line.layoutParams.width = 321
        runOriginal("updateSeekbarProgress"); assertEquals(321, line.layoutParams.width)
    }
    @Test fun unchangedBufferedWidthAvoidsAnotherLayoutWriteButChangedWidthPublishesOnce() {
        val parent = android.widget.FrameLayout(activity); parent.layout(0, 0, 1000, 10)
        val buffer = TvLayoutPublicationView(activity); parent.addView(buffer, android.widget.FrameLayout.LayoutParams(0, 10))
        set("cinemaProgressBuffered", buffer); buffer.layoutWrites = 0
        val played = TvLayoutPublicationView(activity); parent.addView(played, android.widget.FrameLayout.LayoutParams(0, 10))
        set("debrifyProgressLine", played); played.layoutWrites = 0
        runOriginal("updateSeekbarProgress"); assertEquals(700, buffer.layoutParams.width); assertEquals(1, buffer.layoutWrites); assertEquals(250, played.layoutParams.width); assertEquals(1, played.layoutWrites)
        runOriginal("updateSeekbarProgress"); assertEquals(1, buffer.layoutWrites); assertEquals(2, played.layoutWrites)
        buffered = 80_000L; runOriginal("updateSeekbarProgress"); assertEquals(800, buffer.layoutParams.width); assertEquals(2, buffer.layoutWrites); assertEquals(3, played.layoutWrites)
    }

    @Test fun tickerRoutesTheOutgoingUnreadyMediaThroughSkipStateCleanup() {
        set("hasEverBeenReady", false); v("skipSegmentButton").visibility = View.VISIBLE
        runOriginal("updateSeekbarProgress"); assertEquals(View.GONE, v("skipSegmentButton").visibility)
    }

}
