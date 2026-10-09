package com.debrify.app.tv

import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.LooperMode

/** Every case bootstraps its own Activity with the persisted skin selection. */
@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsSkinRuntimeCharacterizationTest(override val skin: TvControlsSkin) : TvPhase16OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}") fun skins(): List<Array<Any>> =
            TvControlsSkin.entries.map { arrayOf<Any>(it) }
    }
    @Test fun showRevealsTheDockAndCompletesItsOriginalThreeHundredMsAnimation() {
        tv("titleView").text = "Runtime film"
        v("controlsOverlay").alpha = 0.8f; v("controlsOverlay").translationY = 99f
        (field("subtitleControlsLift") as SubtitleControlsLiftController).liftAbove(999, false)
        val expectedLift = v("controlsOverlay").height
        showDock()
        assertEquals(expectedLift, TvPlayerOriginalAccess.field(field("subtitleControlsLift")!!, "controlsClearanceHeightPx"))
        assertTrue(field("controlsMenuVisible") as Boolean); assertEquals(View.VISIBLE, v("controlsOverlay").visibility)
        assertEquals(0f, v("controlsOverlay").alpha, 0f); assertEquals(30f, v("controlsOverlay").translationY, 0f)
        assertEquals(300L, v("controlsOverlay").animate().duration)
        step(150); assertEquals(0.875f, v("controlsOverlay").alpha, 0.015f)
        assertEquals(3.75f, v("controlsOverlay").translationY, 0.4f)
        step(151); assertEquals(1f, v("controlsOverlay").alpha, 0.001f); assertEquals(0f, v("controlsOverlay").translationY, 0.001f)
        assertTrue(if (skin == TvControlsSkin.CLASSIC) pv().hasFocus() else v("pauseButton").hasFocus())
        assertEquals("Pause", tv("pauseButton").text.toString())
        assertEquals(if (skin == TvControlsSkin.CLASSIC) View.VISIBLE else View.GONE, v("titleContainer").visibility)
        if (skin != TvControlsSkin.CLASSIC) assertEquals("Runtime film", tv("ottIdentityTitle").text.toString())
        else { assertEquals(View.VISIBLE, v("titleView").visibility); assertEquals(View.GONE, v("titleOttContainer").visibility) }
    }
    @Test fun alreadyVisibleShowRestoresAnInterruptedAnimationAndCancelsAutoHide() {
        set("controlsMenuVisible", true); v("controlsOverlay").visibility = View.INVISIBLE
        v("controlsOverlay").alpha = 0.4f; v("controlsOverlay").translationY = 33f
        runOriginal("scheduleHideControlsMenu"); assertTrue(autoHidePending())
        showDock(); assertFalse("synchronous cancel", autoHidePending()); step(17)
        assertEquals(View.VISIBLE, v("controlsOverlay").visibility); assertEquals(1f, v("controlsOverlay").alpha, 0f)
        assertEquals(0f, v("controlsOverlay").translationY, 0f); assertTrue(if (skin == TvControlsSkin.CLASSIC) pv().hasFocus() else v("pauseButton").hasFocus())
        assertEquals(skin != TvControlsSkin.CLASSIC, autoHidePending())
    }
    @Test fun hideClearsStateThenFinishesTheOriginalTwoHundredFiftyMsFade() {
        showDock(); step(301); runOriginal("scheduleHideControlsMenu"); hideDock()
        assertFalse(field("controlsMenuVisible") as Boolean); assertFalse(autoHidePending())
        assertEquals(250L, v("controlsOverlay").animate().duration); assertEquals(250L, v("titleContainer").animate().duration)
        step(251)
        assertEquals(View.GONE, v("controlsOverlay").visibility); assertEquals(0f, v("controlsOverlay").alpha, 0f)
        assertEquals(0f, v("controlsOverlay").translationY, 0f); assertEquals(View.GONE, v("titleContainer").visibility)
        assertEquals(View.VISIBLE, v("titleView").visibility); assertEquals(View.GONE, v("titleOttContainer").visibility)
    }
    @Test fun hiddenHideNormalizesVisibilityTranslationTitleAndPendingWork() {
        v("controlsOverlay").visibility = View.VISIBLE; v("controlsOverlay").alpha = 0.4f; v("controlsOverlay").translationY = 18f
        v("titleContainer").visibility = View.VISIBLE; v("titleContainer").alpha = 1f
        v("titleView").visibility = View.GONE; v("titleOttContainer").visibility = View.VISIBLE
        (field("controlsHandler") as android.os.Handler).postDelayed(field("hideControlsRunnable") as Runnable, 100)
        v("stremioSourceBadge").visibility = View.VISIBLE; v("stremioSourceBadge").alpha = 1f
        hideDock(); step(201); assertEquals(View.GONE, v("stremioSourceBadge").visibility)
        assertEquals(View.GONE, v("controlsOverlay").visibility); assertEquals(0f, v("controlsOverlay").alpha, 0f)
        assertEquals(0f, v("controlsOverlay").translationY, 0f); assertEquals(View.GONE, v("titleContainer").visibility)
        assertEquals(0f, v("titleContainer").alpha, 0f); assertEquals(View.VISIBLE, v("titleView").visibility)
        assertEquals(View.GONE, v("titleOttContainer").visibility); assertFalse(autoHidePending())
    }
    @Test fun aLateHideEndActionCannotHideAReshownDock() {
        showDock(); step(301); hideDock(); step(100); showDock(); step(400)
        assertTrue(field("controlsMenuVisible") as Boolean); assertEquals(View.VISIBLE, v("controlsOverlay").visibility)
        assertEquals(1f, v("controlsOverlay").alpha, 0.001f); assertEquals(0f, v("controlsOverlay").translationY, 0.001f)
    }
    @Test fun showBothBranchesHideAndTitleResetCancelAlreadyRunningAnimations() {
        // Settle bootstrap focus work; keep the moved animations real while the
        // Media3 parent is immediately visible for this cancellation observation.
        pv().setControllerAnimationEnabled(false); showDock(); step(301); hideDock(); step(251)
        probe.playing = true; playIntent = true; set("cinemaSeekMode", false)
        beginRotation("titleContainer"); beginRotation("controlsOverlay")
        val titleRotation = v("titleContainer").rotation; val freshRotation = v("controlsOverlay").rotation
        showDock(); step(301); frozenRotation("titleContainer", titleRotation); frozenRotation("controlsOverlay", freshRotation)
        val visibleRotation = beginRotation("controlsOverlay")
        showDock(); step(301); frozenRotation("controlsOverlay", visibleRotation)
        val hideRotation = beginRotation("controlsOverlay")
        hideDock(); step(251); frozenRotation("controlsOverlay", hideRotation)
        val resetRotation = beginRotation("titleContainer")
        hideDock(); step(101); frozenRotation("titleContainer", resetRotation)
    }
    @Test fun centerActionPausesThenPlaysAndSchedulesOnlyWhenPlaying() {
        runOriginal("handlePlayPauseToggleFromCenter")
        assertEquals(listOf("pause"), probe.events); assertEquals("Play", tv("pauseButton").text.toString())
        assertFalse(autoHidePending()); assertTrue(field("controlsMenuVisible") as Boolean)
        runOriginal("handlePlayPauseToggleFromCenter")
        assertEquals(listOf("pause", "play"), probe.events); assertEquals("Pause", tv("pauseButton").text.toString())
        assertTrue(autoHidePending())
    }
    @Test fun explicitPlayClearsSleepStopAndPausedNullPlayerLabelsRemainPlay() {
        probe.playing = false; playIntent = false; set("sleepStopLatched", true)
        runOriginal("togglePlayPause"); assertFalse(field("sleepStopLatched") as Boolean); assertEquals(listOf("play"), probe.events)
        probe.playing = false; runOriginal("updatePauseButtonLabel"); assertEquals("Play", tv("pauseButton").text.toString())
        set("player", null); tv("pauseButton").text = "sentinel"; runOriginal("updatePauseButtonLabel")
        assertEquals("Play", tv("pauseButton").text.toString())
    }
    @Test fun absentDockOrPauseButtonDoesNotMutateOtherViews() {
        val dock = v("controlsOverlay"); val pause = v("pauseButton")
        set("controlsOverlay", null); val absentDock = runCatching { showDock(); hideDock() }; assertTrue(absentDock.isSuccess); assertFalse(field("controlsMenuVisible") as Boolean)
        set("controlsOverlay", dock); (pause as android.widget.TextView).text = "sentinel"; set("pauseButton", null); val absentPause = runCatching { runOriginal("updatePauseButtonLabel") }; assertTrue(absentPause.isSuccess)
        assertEquals("sentinel", pause.text.toString())
        set("pauseButton", pause)
    }
    @Test fun pauseLabelUsesTheSkinIconAndRefreshesTheOwnedCaptionAfterPlaybackChanges() {
        showDock(); step(301); focus(v("pauseButton"), true); step(120)
        probe.playing = false; runOriginal("updatePauseButtonLabel"); assertEquals("Play", tv("pauseButton").text.toString())
        if (skin != TvControlsSkin.CLASSIC) {
            val drawable = tv("pauseButton").compoundDrawables[0]; assertNotNull(drawable)
            assertEquals(if (skin == TvControlsSkin.MARQUEE) com.debrify.app.R.drawable.ic_wire_play else com.debrify.app.R.drawable.ic_dock_play,
                org.robolectric.Shadows.shadowOf(drawable).createdFromResId)
            field("ottCaptionLabel")?.let { assertEquals("Play", (it as android.widget.TextView).text.toString()) }
        }
        probe.playing = true; runOriginal("updatePauseButtonLabel"); assertEquals("Pause", tv("pauseButton").text.toString())
        if (skin != TvControlsSkin.CLASSIC) {
            assertEquals(if (skin == TvControlsSkin.MARQUEE) com.debrify.app.R.drawable.ic_wire_pause else com.debrify.app.R.drawable.ic_dock_pause,
                org.robolectric.Shadows.shadowOf(tv("pauseButton").compoundDrawables[0]).createdFromResId)
            field("ottCaptionLabel")?.let { assertEquals("Pause", (it as android.widget.TextView).text.toString()) }
        }
    }

}
