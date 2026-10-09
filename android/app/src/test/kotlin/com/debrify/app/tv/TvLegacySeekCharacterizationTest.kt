package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

/** The original dead legacy entry is exercised by reflection, with its real installed key listener. */
@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvLegacySeekCharacterizationTest : TvPhase16OriginalTest() {
    @Test fun legacyShowCachesPlayerStateResetsSpeedPausesAndFadesForTwoHundredMs() {
        set("seekbarBackgroundWidth", 99); set("currentSeekSpeed", 5f); v("seekbarSpeedIndicator").visibility = View.VISIBLE
        runOriginal("showSeekbar")
        assertEquals(25_000L, field("seekbarPosition")); assertEquals(100_000L, field("videoDuration"))
        assertEquals("00:25", tv("seekbarCurrentTime").text.toString()); assertEquals("01:40", tv("seekbarTotalTime").text.toString())
        assertEquals(0, field("seekbarBackgroundWidth")); assertEquals(1f, field("currentSeekSpeed"))
        assertEquals(listOf("pause"), probe.events); assertEquals(View.GONE, v("seekbarSpeedIndicator").visibility)
        assertTrue(field("seekbarVisible") as Boolean); assertEquals(View.VISIBLE, v("seekbarOverlay").visibility)
        assertEquals(0f, v("seekbarOverlay").alpha, 0f); assertEquals(200L, v("seekbarOverlay").animate().duration)
        step(201); assertEquals(1f, v("seekbarOverlay").alpha, 0.001f)
    }
    @Test fun legacyShowRejectsNonpositiveDurationWithExactShortToast() {
        probe.duration = 0; runOriginal("showSeekbar")
        assertEquals("Seeking not available", toast()); assertEquals(android.widget.Toast.LENGTH_SHORT, org.robolectric.shadows.ShadowToast.getLatestToast().duration)
        assertFalse(field("seekbarVisible") as Boolean); assertTrue(probe.events.isEmpty())
    }
    @Test fun legacyShowReturnsForNullPlayerOrAlreadyVisibleAndPausedShowDoesNotPause() {
        val toasts = org.robolectric.shadows.ShadowToast.shownToastCount()
        set("player", null); runOriginal("showSeekbar"); assertFalse(field("seekbarVisible") as Boolean)
        assertEquals(toasts, org.robolectric.shadows.ShadowToast.shownToastCount())
        originalPlayer(); probe.playing = false; runOriginal("showSeekbar"); assertTrue(probe.events.isEmpty())
        set("seekbarPosition", 7L); runOriginal("showSeekbar"); assertEquals(7L, field("seekbarPosition"))
    }
    @Test fun hideResumesEvenOriginallyPausedPlaybackAfterExactlyOneHundredFiftyMs() {
        probe.playing = false; runOriginal("showSeekbar"); step(201); v("seekbarSpeedIndicator").visibility = View.VISIBLE; runOriginal("hideSeekbar")
        assertEquals(View.GONE, v("seekbarSpeedIndicator").visibility)
        assertFalse(field("seekbarVisible") as Boolean); assertEquals(150L, v("seekbarOverlay").animate().duration)
        step(149); assertTrue(probe.events.isEmpty()); step(2)
        assertEquals(listOf("play"), probe.events); assertEquals(View.GONE, v("seekbarOverlay").visibility)
        probe.events.clear(); runOriginal("hideSeekbar"); step(200); assertTrue(probe.events.isEmpty())
    }
    @Test fun legacyConfirmReleasesResumeHoldThenSeeksAndHides() {
        runOriginal("showSeekbar"); step(201); set("seekbarPosition", 65_000L); set("resumeHoldTargetMs", 65_000L)
        probe.events.clear(); runOriginal("confirmSeekPosition")
        assertEquals(0L, field("resumeHoldTargetMs")); assertEquals(listOf("seek:65000"), probe.events)
        assertFalse(field("seekbarVisible") as Boolean); step(151); assertEquals(listOf("seek:65000", "play"), probe.events)
    }
    @Test fun backwardForwardClampAndPublishTheExactSpeedAndTime() {
        set("videoDuration", 100_000L); set("seekbarPosition", 5_000L); set("currentSeekSpeed", 7f); v("seekbarSpeedIndicator").visibility = View.VISIBLE
        tv("seekbarCurrentTime").text = "stale"; tv("seekbarTotalTime").text = "stale"
        runOriginal("seekBackward", 10_000L, false); assertEquals(0L, field("seekbarPosition")); assertEquals(1f, field("currentSeekSpeed")); assertEquals(View.GONE, v("seekbarSpeedIndicator").visibility); assertEquals("00:00", tv("seekbarCurrentTime").text.toString()); assertEquals("01:40", tv("seekbarTotalTime").text.toString())
        set("seekbarPosition", 99_000L); runOriginal("seekForward", 20_000L, true)
        assertEquals(100_000L, field("seekbarPosition")); assertEquals(2f, field("currentSeekSpeed"))
        assertEquals("→ 2.0x", tv("seekbarSpeedIndicator").text.toString()); assertEquals(View.VISIBLE, v("seekbarSpeedIndicator").visibility)
        assertEquals("01:40", tv("seekbarCurrentTime").text.toString()); assertEquals("01:40", tv("seekbarTotalTime").text.toString())
        runOriginal("updateSeekSpeed", 10_000L); assertEquals(View.GONE, v("seekbarSpeedIndicator").visibility)
    }
    @Test fun legacyDefaultArgumentsUseTenSecondsAndTheContinuousFlagDoesNotChangeTheStep() {
        set("seekbarPosition", 50_000L); set("videoDuration", 100_000L)
        TvPlayerOriginalAccess.callDefault(activity, "seekBackward", arrayOf(longType, boolType), 3, 0L, false)
        assertEquals(40_000L, field("seekbarPosition"))
        TvPlayerOriginalAccess.callDefault(activity, "seekForward", arrayOf(longType, boolType), 3, 0L, false)
        assertEquals(50_000L, field("seekbarPosition"))
    }
    @Test fun legacyPostedWidthUsesTheCapturedFractionAndInstantHandlePosition() {
        val background = activity.findViewById<View>(R.id.seekbar_background); background.layout(0, 0, 1000, 10)
        val played = TvLayoutPublicationView(activity).apply { layoutParams = android.widget.FrameLayout.LayoutParams(0, 10) }
        set("seekbarProgress", played); played.layoutWrites = 0
        v("seekbarHandle").layout(0, 0, 20, 20)
        set("seekbarBackgroundWidth", 0); set("seekbarPosition", 25_000L); set("videoDuration", 100_000L)
        runOriginal("updateSeekbarUI"); set("seekbarPosition", 75_000L); step(17)
        assertEquals(1000, field("seekbarBackgroundWidth")); assertEquals(250, v("seekbarProgress").layoutParams.width); assertEquals(1, played.layoutWrites)
        assertEquals(240f, v("seekbarHandle").translationX, 0.01f); assertEquals(0L, v("seekbarHandle").animate().duration)
        set("seekbarBackgroundWidth", 0); v("seekbarProgress").layoutParams.width = 321
        call("updateSeekbarPosition", arrayOf(floatType), 0.8f); assertEquals(321, v("seekbarProgress").layoutParams.width)
        set("seekbarBackgroundWidth", 1000); set("videoDuration", 0L); runOriginal("updateSeekbarUI"); step(1)
        assertEquals(0, v("seekbarProgress").layoutParams.width)
    }
    @Test fun setupInstallsBackDownOnlyAndNormalizesTheOverlayToGone() {
        v("seekbarOverlay").visibility = View.INVISIBLE; runOriginal("setupSeekbar")
        assertEquals(View.GONE, v("seekbarOverlay").visibility)
        val listener = keyListener(v("seekbarOverlay"))
        set("seekbarVisible", true); assertFalse(listener.onKey(v("seekbarOverlay"), KeyEvent.KEYCODE_BACK, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)))
        assertTrue(field("seekbarVisible") as Boolean)
        assertTrue(listener.onKey(v("seekbarOverlay"), KeyEvent.KEYCODE_BACK, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
        assertFalse(field("seekbarVisible") as Boolean)
    }
}
