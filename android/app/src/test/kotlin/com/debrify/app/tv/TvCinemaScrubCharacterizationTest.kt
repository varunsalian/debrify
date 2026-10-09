package com.debrify.app.tv

import android.animation.ValueAnimator
import android.graphics.Color
import android.view.KeyEvent
import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvCinemaScrubCharacterizationTest(override val skin: TvControlsSkin) : TvPhase16OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}") fun skins(): List<Array<Any>> =
            TvControlsSkin.entries.map { arrayOf<Any>(it) }
    }
    @Test fun entryPreservesBufferingPlaybackIntentCachesStateAndRunsBothThumbAnimations() {
        probe.playing = false; playIntent = true; set("currentSeekSpeed", 7f); v("cinemaProgressBackground").layout(0, 0, 1000, 6)
        enterScrub()
        assertTrue(field("cinemaSeekMode") as Boolean); assertTrue(field("cinemaSeekWasPlaying") as Boolean)
        assertEquals(listOf("pause"), probe.events); assertEquals(25_000L, field("seekbarPosition")); assertEquals(100_000L, field("videoDuration"))
        assertEquals(1000, field("cinemaProgressTrackWidth")); assertEquals(0.25f, field("cinemaLastAnimatedProgress"))
        assertEquals(1f, field("currentSeekSpeed")); assertNotNull("entry publishes the initial progress animation", field("cinemaProgressAnimator")); assertEquals(0.25f, (field("cinemaProgressAnimator") as ValueAnimator).animatedValue)
        val thumb = v("cinemaProgressThumb")
        assertEquals(View.VISIBLE, thumb.visibility); assertEquals(0f, thumb.alpha, 0f)
        assertEquals(0.6f, thumb.scaleX, 0f); assertEquals(0.6f, thumb.scaleY, 0f); assertEquals(200L, thumb.animate().duration)
        step(201); assertEquals(1.15f, thumb.scaleX, 0.01f); assertEquals(1.15f, thumb.scaleY, 0.01f)
        assertEquals(100L, thumb.animate().duration); step(101); assertEquals(1f, thumb.scaleX, 0.01f); assertEquals(1f, thumb.alpha, 0.01f)
        if (skin == TvControlsSkin.CLASSIC) assertEquals(Color.parseColor("#E50914"), tv("debrifyTimeCurrent").currentTextColor)
        else assertEquals((when (skin) { TvControlsSkin.MARQUEE -> 4; TvControlsSkin.BROADCAST -> 7; TvControlsSkin.PULSE -> 8; else -> 6 } * activity.resources.displayMetrics.density).toInt(), v("ottProgressTrackContainer").layoutParams.height)
    }
    @Test fun originallyPausedScrubDoesNotPauseOrResumeAndDuplicateEntryDoesNotReadPlayer() {
        probe.playing = false; playIntent = false; enterScrub(); assertTrue(probe.events.isEmpty())
        reads.clear(); enterScrub(); assertTrue(reads.isEmpty()); assertFalse(field("cinemaSeekWasPlaying") as Boolean)
        exitScrub(); assertTrue(probe.events.isEmpty()); assertFalse(field("cinemaSeekMode") as Boolean)
    }
    @Test fun cancelNeverSeeksResumesPriorIntentCancelsBarAndRestoresThumbPaletteAndChip() {
        enterScrub(); step(301); drawScrub(70_000L)
        assertNotNull(field("cinemaProgressAnimator")); val animator = field("cinemaProgressAnimator") as ValueAnimator; probe.events.clear()
        exitScrub(); assertFalse(animator.isRunning); assertFalse(field("cinemaSeekMode") as Boolean)
        assertFalse(field("cinemaSeekWasPlaying") as Boolean); assertEquals(listOf("play"), probe.events)
        assertEquals(150L, v("cinemaProgressThumb").animate().duration); step(151)
        assertEquals(View.INVISIBLE, v("cinemaProgressThumb").visibility); assertEquals(1f, v("cinemaProgressThumb").scaleX, 0f)
        assertEquals(1f, v("cinemaProgressThumb").scaleY, 0f)
        if (skin == TvControlsSkin.CLASSIC) assertEquals(Color.WHITE, tv("debrifyTimeCurrent").currentTextColor)
        else { assertEquals(View.GONE, v("ottScrubPreviewChip").visibility); assertEquals((when (skin) { TvControlsSkin.MARQUEE -> 2; TvControlsSkin.BROADCAST, TvControlsSkin.PULSE -> 5; TvControlsSkin.TICKET -> 4; else -> 3 } * activity.resources.displayMetrics.density).toInt(), v("ottProgressTrackContainer").layoutParams.height) }
        probe.events.clear(); exitScrub(true); assertTrue(probe.events.isEmpty())
    }
    @Test fun commitReleasesTheResumeHoldSeeksThenResumesAndExits() {
        enterScrub(); set("seekbarPosition", 60_000L); set("resumeHoldTargetMs", 80_000L); probe.events.clear()
        val offers = pauseOffers(); runOriginal("confirmCinemaSeek")
        assertEquals(listOf("pause"), offers)
        assertEquals(0L, field("resumeHoldTargetMs")); assertEquals(listOf("seek:60000", "play"), probe.events)
        assertFalse(field("cinemaSeekMode") as Boolean)
        probe.events.clear(); runOriginal("confirmCinemaSeek"); assertTrue(probe.events.isEmpty())
    }
    @Test fun barAnimationCancelsItsPredecessorAndUsesExactPlayedWidthThumbClampAndTime() {
        v("cinemaProgressThumb").layout(0, 0, 20, 20)
        val parent = android.widget.FrameLayout(activity)
        val played = TvLayoutPublicationView(activity); parent.addView(played, android.widget.FrameLayout.LayoutParams(0, 10))
        set("debrifyProgressLine", played); played.layoutWrites = 0
        drawScrub(50_000); assertTrue(played.layoutWrites > 0); assertNotNull(field("cinemaProgressAnimator")); val first = field("cinemaProgressAnimator") as ValueAnimator
        step(40); assertEquals(437f, v("debrifyProgressLine").layoutParams.width.toFloat(), 4f); assertTrue(played.layoutWrites > 1)
        set("seekbarPosition", 75_000L); runOriginal("updateCinemaProgressUI")
        assertFalse(first.isRunning); assertEquals(80L, (field("cinemaProgressAnimator") as ValueAnimator).duration)
        step(80); assertEquals(750, v("debrifyProgressLine").layoutParams.width); assertEquals(740f, v("cinemaProgressThumb").translationX, 0.01f)
        assertEquals("01:15", tv("debrifyTimeCurrent").text.toString())
        assertEquals(if (skin == TvControlsSkin.CLASSIC) "01:40" else "-00:25", tv("debrifyTimeTotal").text.toString())
        set("seekbarPosition", 0L); runOriginal("updateCinemaProgressUI"); step(80); assertEquals(0f, v("cinemaProgressThumb").translationX, 0f)
    }
    @Test fun unavailableDurationAndNullPlayerDoNotEnterScrub() {
        showDock(); step(301); probe.events.clear()
        val offers = mutableListOf<String>()
        val pause = object : androidx.appcompat.widget.AppCompatButton(activity) {
            override fun requestFocus(direction: Int, rect: android.graphics.Rect?): Boolean {
                offers.add("pause"); return super.requestFocus(direction, rect)
            }
        }
        val badge = object : android.widget.TextView(activity) {
            override fun requestFocus(direction: Int, rect: android.graphics.Rect?): Boolean {
                offers.add("source"); return super.requestFocus(direction, rect)
            }
        }
        (v("controlsOverlay") as android.view.ViewGroup).addView(pause)
        (v("controlsOverlay") as android.view.ViewGroup).addView(badge)
        set("pauseButton", pause); set("stremioSourceBadge", badge)
        probe.duration = 0; enterScrub(); assertFalse(field("cinemaSeekMode") as Boolean); assertTrue(probe.events.isEmpty())
        assertEquals(listOf("pause"), offers); offers.clear()
        @Suppress("UNCHECKED_CAST") val sources = field("stremioSources") as MutableList<StremioSource>
        sources.add(StremioSource(0, "Source", "hash", null, streamType = "torrent", sizeBytes = 1, seeders = 0, source = null, quality = "1080p"))
        v("stremioSourceBadge").visibility = View.VISIBLE
        probe.duration = -1; enterScrub(); assertFalse(field("cinemaSeekMode") as Boolean)
        assertEquals(listOf(if (skin == TvControlsSkin.CLASSIC) "source" else "pause"), offers)
        set("player", null); reads.clear(); enterScrub(); assertTrue(reads.isEmpty()); assertFalse(field("cinemaSeekMode") as Boolean)
        assertEquals(25_000L, field("seekbarPosition")); assertEquals(-1L, field("videoDuration"))
    }
    @Test fun barWithoutTrackWidthUpdatesTextButDoesNotReplaceItsAnimator() {
        drawScrub(); val previous = field("cinemaProgressAnimator"); set("cinemaProgressTrackWidth", 0)
        set("seekbarPosition", 80_000L); runOriginal("updateCinemaProgressUI")
        assertSame(previous, field("cinemaProgressAnimator")); assertEquals("01:20", tv("debrifyTimeCurrent").text.toString())
    }
    @Test fun installedFocusAndKeyListenersEnterStepClampReleaseCommitAndCancel() {
        showDock(); step(301); val bar = v("cinemaProgressContainer"); runOriginal("setupCinemaProgressBar")
        focus(bar, true); assertTrue(field("cinemaSeekMode") as Boolean)
        val offers = pauseOffers(); val listener = keyListener(bar)
        fun key(code: Int, action: Int = KeyEvent.ACTION_DOWN, repeat: Int = 0) = listener.onKey(bar, code, KeyEvent(0, 0, action, code, repeat))
        assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT)); assertEquals(35_000L, field("seekbarPosition")); assertEquals("00:35", tv("debrifyTimeCurrent").text.toString())
        assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT)); assertEquals(25_000L, field("seekbarPosition")); assertEquals("00:25", tv("debrifyTimeCurrent").text.toString())
        assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT, repeat = 20)); assertEquals(0L, field("seekbarPosition")); assertEquals(5f, field("currentSeekSpeed"))
        assertEquals("00:00", tv("debrifyTimeCurrent").text.toString()); assertFalse(key(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP))
        assertEquals(1f, field("currentSeekSpeed")); set("seekbarPosition", 25_000L)
        assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 20)); assertEquals(5f, field("currentSeekSpeed")); assertEquals("01:15", tv("debrifyTimeCurrent").text.toString())
        assertFalse(key(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.ACTION_UP)); assertEquals(1f, field("currentSeekSpeed"))
        assertEquals(View.GONE, v("cinemaSpeedIndicator").visibility)
        set("seekbarPosition", 99_999L); assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT)); assertEquals(100_000L, field("seekbarPosition"))
        set("seekbarPosition", 1L); assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT)); assertEquals(0L, field("seekbarPosition"))
        assertFalse(key(KeyEvent.KEYCODE_A)); assertFalse(key(KeyEvent.KEYCODE_A, KeyEvent.ACTION_MULTIPLE))
        probe.events.clear(); assertTrue(key(KeyEvent.KEYCODE_BACK)); assertFalse(field("cinemaSeekMode") as Boolean); assertTrue(seekEvents().isEmpty()); assertEquals(listOf("pause"), offers); offers.clear()
        assertFalse(key(KeyEvent.KEYCODE_DPAD_RIGHT)); focus(bar, true); probe.events.clear()
        assertTrue(key(KeyEvent.KEYCODE_ENTER)); assertEquals(listOf("seek:25000"), seekEvents()); assertEquals(listOf("pause"), offers); offers.clear()
        focus(bar, true); assertTrue(key(KeyEvent.KEYCODE_DPAD_DOWN)); assertFalse(field("cinemaSeekMode") as Boolean); assertEquals(listOf("pause"), offers); offers.clear()
        focus(bar, true); assertTrue(key(KeyEvent.KEYCODE_ESCAPE)); assertFalse(field("cinemaSeekMode") as Boolean); assertEquals(listOf("pause"), offers)
        focus(bar, true); focus(bar, false); assertFalse(field("cinemaSeekMode") as Boolean)
    }
    @Test fun previewChipPinsPositiveNegativeZeroAndNullPlayerOrigins() {
        if (skin == TvControlsSkin.CLASSIC) {
            drawScrub(0, 0); step(80); assertEquals("00:00", tv("debrifyTimeTotal").text.toString()); assertEquals(0f, field("cinemaLastAnimatedProgress")); return
        }
        v("ottScrubPreviewChip").visibility = View.GONE; drawScrub(25_000)
        assertEquals(View.GONE, v("ottScrubPreviewChip").visibility)
        set("seekbarPosition", 15_000L); runOriginal("updateCinemaProgressUI")
        assertEquals("00:15   ·   −00:10", tv("ottScrubPreviewText").text.toString()); assertEquals(View.VISIBLE, v("ottScrubPreviewChip").visibility)
        set("seekbarPosition", 35_000L); runOriginal("updateCinemaProgressUI"); assertEquals("00:35   ·   +00:10", tv("ottScrubPreviewText").text.toString())
        set("seekbarPosition", 25_000L); runOriginal("updateCinemaProgressUI"); assertEquals("00:25   ·   +00:00", tv("ottScrubPreviewText").text.toString())
        set("player", null); set("seekbarPosition", 120_000L); runOriginal("updateCinemaProgressUI")
        assertEquals("02:00   ·   +00:00", tv("ottScrubPreviewText").text.toString()); assertEquals("-00:00", tv("debrifyTimeTotal").text.toString())
    }
}
