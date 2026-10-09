package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.media3.common.Player
import androidx.media3.ui.AspectRatioFrameLayout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackDisplayCharacterizationTest : TvPhase15OriginalTest() {
    private val aspectLabels = listOf("Fit", "Fill", "Zoom", "Cinema Zoom")
    private val modes = listOf(AspectRatioFrameLayout.RESIZE_MODE_FIT, AspectRatioFrameLayout.RESIZE_MODE_FILL, AspectRatioFrameLayout.RESIZE_MODE_ZOOM, AspectRatioFrameLayout.RESIZE_MODE_FIT)
    private val speeds = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)
    private val speedLabels = listOf("0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x")
    private fun content() = view(androidx.media3.ui.R.id.exo_content_frame)!!
    private fun focusSpeed() {
        pv().showController(); (field("controlsOverlay") as View).visibility = View.VISIBLE
        layout(); assertTrue("speed is actually focused", button("speedButton").requestFocus())
        set("ottSkinInstalled", true)
        set("ottCaptionLabel", TextView(activity))
    }
    @Test fun everyAspectModeUsesTheCorrectResizeModeAndBothScaleAxes() {
        aspectLabels.indices.forEach { index ->
            aspect(index)
            assertEquals(modes[index], pv().resizeMode)
            val scale = if (index == 3) 4f / 3f else 1f
            assertEquals(scale, content().scaleX, 0f); assertEquals(scale, content().scaleY, 0f)
            assertEquals(aspectLabels[index], button("aspectButton").text.toString())
        }
        aspect(3); aspect(0); assertEquals(1f, content().scaleX, 0f); assertEquals(1f, content().scaleY, 0f)
    }
    @Test fun aspectScalingFallsBackToTheRetainedVideoSurfaceIfTheFrameIsAbsent() {
        val frame = content(); (frame.parent as android.view.ViewGroup).removeView(frame)
        val surface = pv().videoSurfaceView
        assertNotNull("original PlayerView supplies fallback surface", surface)
        aspect(3); assertEquals(4f / 3f, surface!!.scaleX, 0f); assertEquals(4f / 3f, surface.scaleY, 0f)
        aspect(2); assertEquals(1f, surface.scaleX, 0f); assertEquals(1f, surface.scaleY, 0f)
    }
    @Test fun aspectCyclingWrapsAndPinsEveryVisibleLabelAndToast() {
        aspectLabels.indices.forEach { index ->
            set("resizeModeIndex", index); call("cycleAspectRatio", emptyArray())
            val next = (index + 1) % 4
            assertEquals(next, field("resizeModeIndex")); assertEquals(modes[next], pv().resizeMode)
            assertEquals(aspectLabels[next], button("aspectButton").text.toString())
            assertEquals("Aspect: ${aspectLabels[next]}", toast())
        }
    }
    @Test fun aspectLabelRefreshReadsCurrentFocusedCaptionOwner() {
        pv().showController(); (field("controlsOverlay") as View).visibility = View.VISIBLE; layout()
        assertTrue(button("aspectButton").requestFocus()); set("ottSkinInstalled", true); set("ottCaptionLabel", TextView(activity))
        aspect(3)
        assertEquals("Cinema Zoom", (field("ottCaptionLabel") as TextView).text.toString())
        assertSame(button("aspectButton"), field("ottCaptionOwner"))
    }
    @Test fun playbackSpeedClampsBothBoundariesAndReadsAllSixLiteralSpeeds() {
        for ((input, expected) in listOf(-1 to 0, 0 to 0, 1 to 1, 2 to 2, 3 to 3, 4 to 4, 5 to 5, 99 to 5)) {
            probe.events.clear(); playback(input)
            assertEquals(expected, field("playbackSpeedIndex")); assertEquals(speeds[expected], speed, 0f)
            assertEquals(listOf("speed:${speeds[expected]}"), probe.events)
            assertEquals(speeds[expected] != 1f, routing().requiresPcm)
        }
    }
    @Test fun speedCyclingWrapsAndPinsEveryToast() {
        speedLabels.indices.forEach { index ->
            set("playbackSpeedIndex", index); call("cyclePlaybackSpeed", emptyArray())
            val next = (index + 1) % 6
            assertEquals(next, field("playbackSpeedIndex")); assertEquals(speeds[next], speed, 0f)
            assertEquals("Speed: ${speedLabels[next]}", toast())
        }
    }
    @Test fun speedRouteChangeReleasesEffectAndRepreparesInStopSpeedPrepareOrder() {
        initialize(); assertEquals(1, TvPhase15Effects.effects.size); val first = TvPhase15Effects.effects.single()
        mediaCount = 1; probe.state = Player.STATE_READY; playback(3)
        assertTrue(first.released); assertNull(effect()); assertTrue(routing().requiresPcm)
        assertEquals(listOf("stop", "speed:1.25", "prepare"), probe.events)
    }
    @Test fun speedChangeOnAnAlreadyPcmRouteRetainsEffectAndDoesNotRestart() {
        routing().update(true, false); set("nightModeIndex", 1); initialize()
        val first = effect(); mediaCount = 1; playback(3)
        assertSame(first, effect()); assertFalse(TvPhase15Effects.effects.single().released)
        assertEquals(listOf("speed:1.25"), probe.events)
    }
    @Test fun systemEffectsKeepThePcmRouteWhenSpeedReturnsToNormal() {
        routing().update(false, true, 1.25f); set("systemAudioEffectsEnabled", true); mediaCount = 1
        playback(2)
        assertTrue(routing().requiresPcm); assertEquals(listOf("speed:1.0"), probe.events)
    }
    @Test fun nightModeKeepsThePcmRouteWhenSpeedReturnsToNormal() {
        routing().update(true, false, 1.25f); set("nightModeIndex", 1); mediaCount = 1
        playback(2)
        assertTrue(routing().requiresPcm); assertEquals(listOf("speed:1.0"), probe.events)
    }
    @Test fun endedRouteChangeDefersSpeedAndReprepareUntilReady() {
        mediaCount = 1; probe.state = Player.STATE_ENDED; playback(3)
        assertTrue(routing().requiresPcm); assertTrue(probe.events.isEmpty()); assertEquals(1f, speed, 0f)
        probe.state = Player.STATE_READY; (field("playbackListener") as Player.Listener).onPlaybackStateChanged(Player.STATE_READY)
        assertEquals(listOf("stop", "speed:1.25", "prepare"), probe.events.take(3)); assertEquals(1.25f, speed, 0f)
    }
    @Test fun classicSpeedLeavesButtonTextAndCaptionUntouched() {
        val before = button("speedButton").text.toString(); playback(3)
        assertEquals(before, button("speedButton").text.toString()); assertNull(field("ottCaptionOwner"))
    }
    @Test fun ottSpeedUpdatesButtonAndItsActuallyFocusedCaption() {
        focusSpeed(); playback(4)
        assertEquals("1.5x", button("speedButton").text.toString())
        assertEquals("1.5x", (field("ottCaptionLabel") as TextView).text.toString())
        assertSame(button("speedButton"), field("ottCaptionOwner"))
    }
    @Test fun displayMenuPinsHeadersAllRowsSelectionAndInstalledActions() {
        set("resizeModeIndex", 1); val value = model("umDisplayModel")
        assertEquals("Rail", value.col1.single().title); assertEquals("DISPLAY", value.col2Title)
        assertEquals("Aspect ratio", value.col3Title); assertEquals("Aspect ratio", value.col2.single().title)
        assertEquals("Fill", value.col2.single().value); assertEquals("aspect", value.col2.single().tag)
        assertEquals(aspectLabels, value.col3.map { it.title }); assertEquals(listOf(false, true, false, false), value.col3.map { it.selected })
        value.col3[3].onOk!!.invoke()
        assertEquals(3, field("resizeModeIndex")); assertEquals(4f / 3f, content().scaleX, 0f)
        assertEquals("Cinema Zoom", button("aspectButton").text.toString())
    }
    @Test fun displayMenuUnknownIndexHasNoSelectedOrCurrentValueUntilAnAction() {
        set("resizeModeIndex", 99); val value = model("umDisplayModel", 99)
        assertNull(value.col2.single().value); assertFalse(value.col3.any { it.selected })
        value.col3[0].onOk!!.invoke(); assertEquals(0, field("resizeModeIndex")); assertEquals(1f, content().scaleX, 0f)
    }
    @Test fun retainedPlaybackMenuSpeedRowsDispatchToTheOriginalDisplayLogic() {
        val value = model("umPlaybackModel")
        assertEquals("Playback speed", value.col3Title); assertEquals(speedLabels, value.col3.map { it.title })
        assertEquals(listOf(false, false, true, false, false, false), value.col3.map { it.selected })
        value.col3[4].onOk!!.invoke(); assertEquals(4, field("playbackSpeedIndex")); assertEquals(1.5f, speed, 0f)
    }
}
