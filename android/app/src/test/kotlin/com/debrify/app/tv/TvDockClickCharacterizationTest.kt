package com.debrify.app.tv

import android.os.Handler
import android.view.View
import androidx.appcompat.app.AlertDialog
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

/** Invoke the listeners installed by the real original setup, including fallback paths. */
@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvDockClickCharacterizationTest : TvPhase15OriginalTest() {
    private fun visible() { set("controlsMenuVisible", true); (field("controlsOverlay") as View).visibility = View.VISIBLE }
    private fun pending() = TvPlaylistUiQueue.pending(field("controlsHandler") as Handler, field("hideControlsRunnable") as Runnable)
    private fun hidden() { assertFalse(field("controlsMenuVisible") as Boolean) }
    private fun dialog(): AlertDialog { val value = ShadowDialog.getLatestDialog(); assertNotNull("installed callback shows dialog", value); return (value as AlertDialog).also { assertTrue(it.isShowing) } }
    private fun click(name: String) { assertTrue("installed click listener $name", (if (name == "debrifyRandom") view(R.id.debrify_random_button)!! else button(name)).performClick()) }
    @Test fun pauseClickPausesAndCancelsTheDockTimer() {
        visible(); call("scheduleHideControlsMenu", emptyArray()); assertTrue(pending())
        probe.playing = true; click("pauseButton")
        assertFalse(probe.playing); assertEquals(listOf("pause"), probe.events); assertFalse(pending())
    }
    @Test fun resumeClickPlaysAndSchedulesTheDockTimer() {
        visible(); probe.playing = false; click("pauseButton")
        assertTrue(probe.playing); assertEquals(listOf("play"), probe.events); assertTrue(pending())
    }
    @Test fun nightClickHidesDockAndTargetsNightRowsInTheAudioMenu() {
        visible(); click("nightModeButton"); hidden(); assertTrue(menu().isVisible)
        assertEquals("AUDIO", menuModel().col2Title)
        assertEquals("night", menuModel().col2[(TvPlayerOriginalAccess.field(menu(), "sel") as IntArray)[1]].tag)
    }
    @Test fun audioClickHidesDockAndShowsTheAudioMenu() {
        visible(); click("audioButton"); hidden(); assertTrue(menu().isVisible)
        assertEquals("AUDIO", menuModel().col2Title)
    }
    @Test fun subtitleClickHidesDockAndShowsTheSubtitleMenu() {
        visible(); click("subtitleButton"); hidden(); assertTrue(menu().isVisible)
        assertEquals("Detected: Film", menuModel().col2Title)
    }
    @Test fun speedClickHidesDockAndTargetsSpeedRows() {
        visible(); click("speedButton"); hidden(); assertTrue(menu().isVisible)
        assertEquals("PLAYBACK", menuModel().col2Title)
        assertEquals("speed", menuModel().col2[(TvPlayerOriginalAccess.field(menu(), "sel") as IntArray)[1]].tag)
    }
    @Test fun randomClickHidesDockAndTargetsShuffleRows() {
        visible(); click("debrifyRandom"); hidden(); assertTrue(menu().isVisible)
        assertEquals("PLAYBACK", menuModel().col2Title)
        assertEquals("shuffle", menuModel().col2[(TvPlayerOriginalAccess.field(menu(), "sel") as IntArray)[1]].tag)
    }
    @Test fun aspectClickCyclesAndKeepsAnAutoHideTimer() {
        visible(); set("resizeModeIndex", 0); click("aspectButton")
        assertEquals(1, field("resizeModeIndex")); assertEquals("Aspect: Fill", toast()); assertTrue(pending())
    }
    @Test fun nightFallbackShowsAllEightChoicesAndAppliesItsCapturedSelection() {
        set("unifiedMenu", null); visible(); click("nightModeButton")
        assertEquals("Night Mode", dialog().findViewById<android.widget.TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals(8, dialog().listView.adapter.count)
        assertEquals("Cancel", dialog().getButton(AlertDialog.BUTTON_NEGATIVE).text.toString())
        assertEquals(0, dialog().listView.checkedItemPosition)
        dialog().listView.performItemClick(null, 2, 0)
        assertEquals(2, field("nightModeIndex")); assertEquals("Night Mode: Medium", toast()); assertFalse((ShadowDialog.getLatestDialog() as AlertDialog).isShowing)
    }
    @Test fun audioFallbackShowsNoTrackToastAndExtendsTimer() {
        set("unifiedMenu", null); visible(); click("audioButton")
        assertEquals("No audio tracks available", toast()); assertTrue(pending())
    }
    @Test fun speedFallbackCyclesAndExtendsTimerWithoutHidingDock() {
        set("unifiedMenu", null); visible(); click("speedButton")
        assertEquals(1.25f, speed, 0f); assertTrue(pending()); assertTrue(field("controlsMenuVisible") as Boolean)
    }
    @Test fun randomFallbackShowsTheShuffleDialog() {
        set("unifiedMenu", null); visible(); click("debrifyRandom"); hidden()
        assertEquals("Shuffle Playback", dialog().findViewById<android.widget.TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals(listOf("Play Random Once", "Shuffle Continuously"), (0 until dialog().listView.adapter.count).map { dialog().listView.adapter.getItem(it).toString() })
    }
    private fun clickRaw(id: Int) { assertTrue(view(id)!!.performClick()) }
    @Test fun playlistClickHidesDockAndShowsTheInstalledPlaylist() {
        movie("series").items.add(p2Item(season = 2, episode = 5)); call("rebuildPlaylistContent", emptyArray()); visible(); clickRaw(R.id.debrify_playlist_button); hidden()
        assertTrue(field("playlistVisible") as Boolean)
    }
    @Test fun nextAndPreviousClicksTakeTheCatalogFallbackAtPlaylistBoundaries() {
        visible(); clickRaw(R.id.debrify_next_button); hidden(); assertEquals("End of playlist", toast())
        visible(); clickRaw(R.id.debrify_prev_button); hidden(); assertEquals("Beginning of playlist", toast())
    }
    // The random control is a setup-local, so keep access through its actual bound id.
    private fun clickRandom() = clickRaw(R.id.debrify_random_button)
}
