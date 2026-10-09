package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import androidx.media3.common.C
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

/** Actual Activity.dispatchKeyEvent, not leaf-method substitutes. */
@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsKeyCharacterizationTest : TvPhase16OriginalTest() {
    override val skin = TvControlsSkin.OTT
    private fun current(view: View?) = org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(view)
    private fun outside() { current(pv()); set("cinemaSeekMode", false) }
    private fun shown() { showDock(); step(301); outside() }
    private fun source() {
        @Suppress("UNCHECKED_CAST") val sources = field("stremioSources") as MutableList<StremioSource>
        sources.add(StremioSource(0, "Source", "hash", null, streamType = "torrent", sizeBytes = 1, seeders = 0, source = null, quality = "1080p"))
        v("stremioSourceBadge").visibility = View.VISIBLE
    }
    @Test fun firstCenterDownTogglesButRepeatedDownAndUpAreConsumedWithoutAnotherToggle() {
        outside(); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_CENTER)); assertEquals(listOf("pause"), probe.events)
        assertTrue(field("controlsMenuVisible") as Boolean); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_CENTER, repeat = 1))
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.ACTION_UP)); assertEquals(listOf("pause"), probe.events)
    }
    @Test fun enterHasTheSameFirstDownContractAsCenter() {
        outside(); assertTrue(dispatch(KeyEvent.KEYCODE_ENTER)); assertEquals(listOf("pause"), probe.events)
        assertTrue(dispatch(KeyEvent.KEYCODE_ENTER, repeat = 2)); assertTrue(dispatch(KeyEvent.KEYCODE_ENTER, KeyEvent.ACTION_UP)); assertEquals(listOf("pause"), probe.events)
    }
    @Test fun backDownHidesVisibleControlsAndBackUpDoesNotHideThem() {
        shown(); dispatch(KeyEvent.KEYCODE_BACK, KeyEvent.ACTION_UP); assertTrue(field("controlsMenuVisible") as Boolean)
        assertTrue(dispatch(KeyEvent.KEYCODE_BACK)); assertFalse(field("controlsMenuVisible") as Boolean)
    }
    @Test fun downRevealsHiddenControlsAndOutsideFocusRevealsThemAgain() {
        outside(); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_DOWN)); assertTrue(field("controlsMenuVisible") as Boolean); assertTrue(autoHidePending())
        step(301); outside(); v("controlsOverlay").alpha = 0.3f
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_DOWN)); assertEquals(1f, v("controlsOverlay").alpha, 0f)
    }
    @Test fun downRepeatAndUpDoNotRevealHiddenControls() {
        outside(); dispatch(KeyEvent.KEYCODE_DPAD_DOWN, repeat = 1); dispatch(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_UP)
        assertFalse(field("controlsMenuVisible") as Boolean); assertTrue(probe.events.isEmpty())
    }
    @Test fun sourceBadgeDownMovesToScrubForKnownDurationButNotRepeatedOrReleasedKeys() {
        shown(); source(); current(v("stremioSourceBadge")); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_DOWN))
        assertTrue(v("cinemaProgressContainer").hasFocus()); assertTrue(field("cinemaSeekMode") as Boolean)
        exitScrub(); current(v("stremioSourceBadge")); probe.events.clear()
        val offers = mutableListOf<Int>()
        set("cinemaProgressContainer", object : View(activity) {
            override fun requestFocus(direction: Int, rect: android.graphics.Rect?): Boolean {
                offers.add(direction); return true
            }
        })
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_DOWN, repeat = 1)); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.ACTION_UP)); assertTrue(probe.events.isEmpty()); assertTrue("repeat/release does not offer progress focus", offers.isEmpty())
    }
    @Test fun sourceBadgeDownWithUnknownDurationFallsBackToPause() {
        shown(); source(); probe.duration = 0; current(v("stremioSourceBadge"))
        val offers = pauseOffers()
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_DOWN)); assertEquals(listOf("pause"), offers); assertTrue(v("pauseButton").hasFocus()); assertFalse(field("cinemaSeekMode") as Boolean)
    }
    @Test fun progressUpWithSourcesReturnsToTheBadgeWithoutTogglingPlayback() {
        shown(); source(); current(v("cinemaProgressContainer")); probe.events.clear()
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_UP)); assertTrue(v("stremioSourceBadge").hasFocus()); assertTrue(seekEvents().isEmpty())
    }
    @Test fun dockUpWithKnownDurationEntersScrubAndUnknownDurationWithSourcesUsesBadge() {
        shown(); current(v("pauseButton")); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_UP)); assertTrue(field("cinemaSeekMode") as Boolean)
        exitScrub(); source(); probe.duration = 0; current(v("pauseButton"))
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_UP)); assertTrue(v("stremioSourceBadge").hasFocus())
    }
    @Test fun controlsFocusedCenterAndHorizontalKeysDoNotUseTheGlobalToggleOrQuickSeek() {
        shown(); current(v("aspectButton")); probe.events.clear()
        dispatch(KeyEvent.KEYCODE_DPAD_CENTER); dispatch(KeyEvent.KEYCODE_DPAD_RIGHT); dispatch(KeyEvent.KEYCODE_DPAD_LEFT)
        assertTrue(probe.events.isEmpty()); assertTrue(field("controlsMenuVisible") as Boolean)
    }
    @Test fun rightQuickSeekClampsAndLongPressSchedulesProgressFocusAtOneHundredMs() {
        outside(); set("resumeHoldTargetMs", 80_000L); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_RIGHT)); assertEquals(listOf("seek:35000"), probe.events); assertEquals(0L, field("resumeHoldTargetMs"))
        probe.events.clear(); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 1)); assertTrue(probe.events.isEmpty())
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_RIGHT, repeat = 3)); assertTrue(field("controlsMenuVisible") as Boolean)
        step(99); assertFalse(field("cinemaSeekMode") as Boolean); step(1); assertTrue(field("cinemaSeekMode") as Boolean)
    }
    @Test fun leftQuickSeekUsesNegativeTenSecondsAndLongPressShowsTheDock() {
        outside(); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_LEFT)); assertEquals(listOf("seek:15000"), probe.events)
        probe.events.clear(); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.ACTION_UP)); assertTrue(probe.events.isEmpty())
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_LEFT, repeat = 3)); assertTrue(field("controlsMenuVisible") as Boolean); step(100); assertTrue(field("cinemaSeekMode") as Boolean)
    }
    @Test fun legacyRouterStepsAcceleratesConfirmsAndConsumesAllUpEvents() {
        runOriginal("showSeekbar"); step(201); probe.events.clear()
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_RIGHT)); assertEquals(35_000L, field("seekbarPosition"))
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_LEFT, repeat = 2)); assertEquals(21_000L, field("seekbarPosition"))
        assertTrue(dispatch(KeyEvent.KEYCODE_A, KeyEvent.ACTION_UP)); assertTrue(field("seekbarVisible") as Boolean)
        assertTrue(dispatch(KeyEvent.KEYCODE_ENTER)); assertEquals(listOf("seek:21000"), probe.events); assertFalse(field("seekbarVisible") as Boolean)
    }
    @Test fun legacyRouterBackCancelsWithoutASeek() {
        runOriginal("showSeekbar"); step(201); probe.events.clear()
        assertTrue(dispatch(KeyEvent.KEYCODE_BACK)); assertFalse(field("seekbarVisible") as Boolean); assertTrue(seekEvents().isEmpty())
    }
    @Test fun quickSeekKnownAndUnsetDurationClampAndPublishExactDirectionalFeedback() {
        set("resumeHoldTargetMs", 80_000L); runOriginal("seekBy", 100_000L)
        assertEquals(listOf("seek:100000"), seekEvents()); assertEquals(0L, field("resumeHoldTargetMs"))
        assertEquals("+100s", activity.findViewById<android.widget.TextView>(R.id.seek_feedback_right_text).text.toString())
        runOriginal("seekBy", -200_000L); assertEquals("seek:0", seekEvents().last()); assertEquals("-200s", activity.findViewById<android.widget.TextView>(R.id.seek_feedback_left_text).text.toString())
        probe.duration = C.TIME_UNSET; probe.position = 25_000L; runOriginal("seekBy", 200_000L); assertEquals("seek:225000", seekEvents().last())
        runOriginal("seekBy", -300_000L); assertEquals("seek:0", seekEvents().last())
        probe.events.clear(); set("player", null); val absent = runCatching { runOriginal("seekBy", 10_000L) }; assertTrue(absent.isSuccess); assertTrue(probe.events.isEmpty())
    }
    @Test fun badgeAndSkipFocusPassCenterThroughWithoutOpeningOrTogglingControls() {
        source(); current(v("stremioSourceBadge")); dispatch(KeyEvent.KEYCODE_DPAD_CENTER)
        assertFalse(field("controlsMenuVisible") as Boolean); assertTrue(probe.events.isEmpty())
        v("skipSegmentButton").visibility = View.VISIBLE; current(v("skipSegmentButton")); dispatch(KeyEvent.KEYCODE_ENTER)
        assertFalse(field("controlsMenuVisible") as Boolean); assertTrue(probe.events.isEmpty())
    }
    @Test fun activityDelegatesFocusedScrubRightCenterAndDownToTheInstalledListener() {
        pv().setControllerAnimationEnabled(false); shown(); val bar = v("cinemaProgressContainer"); assertTrue(bar.requestFocus()); current(bar)
        assertTrue(field("cinemaSeekMode") as Boolean)
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_RIGHT)); assertEquals(35_000L, field("seekbarPosition"))
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_CENTER)); assertEquals(listOf("seek:35000"), seekEvents()); assertFalse(field("cinemaSeekMode") as Boolean)
        assertTrue(bar.requestFocus()); current(bar); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_DOWN)); assertFalse(field("cinemaSeekMode") as Boolean)
    }
    @Test fun dockUpRepeatsAndReleasesDoNotStealFocusAndCinemaGateDoesNotEnterAgain() {
        shown(); current(v("pauseButton")); probe.events.clear()
        assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_UP, repeat = 1)); assertTrue(dispatch(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.ACTION_UP))
        assertTrue(probe.events.isEmpty()); assertFalse(field("cinemaSeekMode") as Boolean)
        val offers = mutableListOf<Int>()
        val watched = object : View(activity) {
            override fun requestFocus(direction: Int, rect: android.graphics.Rect?): Boolean {
                offers.add(direction); return true
            }
        }
        set("cinemaProgressContainer", watched)
        set("cinemaSeekMode", true); set("seekbarPosition", 7L); dispatch(KeyEvent.KEYCODE_DPAD_UP)
        assertTrue("active cinema gate does not request progress focus", offers.isEmpty())
        assertEquals(7L, field("seekbarPosition"))
    }

}
