package com.debrify.app.tv

import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.NestedScrollView
import androidx.media3.common.C
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.util.SubtitleSettings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPhase4BoundaryCharacterizationTest : TvPhase4OriginalTest() {
    @Test fun rememberedOffsetEitherSignSuppressesAnnounceAndAttemptsButZeroOpensWindow() {
        setup(); active(); pref(true)
        org.robolectric.shadows.ShadowChoreographer.setPaused(true)
        for (offset in listOf(-1200L, -1L, 1L, 1200L)) {
            SubtitleSettings.setSyncOffsetMs(activity, offset)
            invoke("startAutoSyncLadder")
            assertEquals("remembered=$offset", false, field("autoSyncPillWindowActive"))
            assertNull("remembered=$offset", field("autoSyncPill"))
            advance(8000); assertEquals(0, field("autoSyncLadderIdx")); assertTrue(jobs().isEmpty())
        }
        SubtitleSettings.resetSyncOffset(); invoke("startAutoSyncLadder")
        assertEquals(true, field("autoSyncPillWindowActive"))
        assertEquals("Trying to auto-sync subtitles — this may take a minute, keep watching", label())
    }

    @Test fun failedFetchCannotFallBackToAnIndexWhoseSubtitleWasNeverActive() {
        setup(); set("currentStremioSubtitleIndex", 4)
        val ts = field("trackSelector") as DefaultTrackSelector
        ts.parameters = ts.parameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
        val (response, job) = beginFetch(parsed = emptyList())
        set("currentStremioSubtitleIndex", 5); complete(response, job)
        assertEquals(-1, field("currentStremioSubtitleIndex"))
        assertFalse(ts.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        assertEquals(false, field("externalSubtitleActive")); assertNull(field("activeExternalSubtitleUrl"))
    }

    @Test fun uncachedLoadingAndSuccessfulStatusKeepSubtitleDisplayNameAndExactGlyphs() {
        setup(); val (response, job) = beginFetch()
        assertEquals("Loading English…", (field("statusPill") as TextView).text.toString())
        assertEquals(View.VISIBLE, (field("statusPill") as View).visibility)
        complete(response, job)
        assertEquals("✓ English", (field("statusPill") as TextView).text.toString())
    }

    private fun panel(): Pair<SubtitlePanelController, LinearLayout> {
        val callbacks = field("subtitlePanelCallbacks") as SubtitlePanelController.Callbacks
        val root = LinearLayout(activity).apply { visibility = View.GONE }
        val options = LinearLayout(activity)
        val controller = SubtitlePanelController(activity, root, LinearLayout(activity), options,
            NestedScrollView(activity), NestedScrollView(activity), TextView(activity), TextView(activity), View(activity), callbacks)
        set("subtitlePanel", controller); return controller to options
    }
    private fun texts(view: View): List<String> = when (view) {
        is TextView -> listOf(view.text.toString())
        is android.view.ViewGroup -> (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
        else -> emptyList()
    }
    @Suppress("UNCHECKED_CAST") private fun tracks() = field("subtitleTracks") as List<Pair<String, *>>

    @Test fun failedFetchRefreshesVisiblePanelLabelsAndRestoredSelection() {
        setup(); set("isLoadingStremioSubtitles", true)
        val (panel, options) = panel(); invoke("showSubtitleSettingsPanel")
        assertTrue(texts(options).contains("⏳ Loading external subtitles..."))
        val (response, job) = beginFetch(parsed = emptyList())
        set("isLoadingStremioSubtitles", false); set("currentSubtitleTrackIndex", 7)
        complete(response, job)
        assertTrue(panel.isVisible); assertEquals(listOf("Off"), tracks().map { it.first })
        assertEquals(0, field("currentSubtitleTrackIndex"))
        assertTrue(texts(options).contains("Off")); assertFalse(texts(options).contains("⏳ Loading external subtitles..."))
        assertEquals("Couldn't load English", (field("statusPill") as TextView).text.toString())
    }

    @Test fun failedFetchDoesNotRefreshHiddenPanelOrReplaceItsTrackSnapshot() {
        setup(); set("isLoadingStremioSubtitles", true)
        val (panel, _) = panel(); invoke("showSubtitleSettingsPanel"); invoke("hideSubtitleSettingsPanel")
        val before = tracks().map { it.first }
        val (response, job) = beginFetch(parsed = emptyList()); set("isLoadingStremioSubtitles", false)
        complete(response, job)
        assertFalse(panel.isVisible); assertEquals(before, tracks().map { it.first })
    }

    @Test fun legacyTrackDialogKeepsShortToastDurationAndOffLabel() {
        setup(); invoke("showSubtitleTrackDialog")
        assertEquals("No subtitle tracks available", org.robolectric.shadows.ShadowToast.getTextOfLatestToast())
        val toast = org.robolectric.shadows.ShadowToast.getLatestToast()
        assertEquals(android.widget.Toast.LENGTH_SHORT, toast.duration)
        val group = androidx.media3.common.TrackGroup(androidx.media3.common.Format.Builder()
            .setSampleMimeType(androidx.media3.common.MimeTypes.TEXT_VTT).setLanguage("en").build())
        val tracks = androidx.media3.common.Tracks(listOf(androidx.media3.common.Tracks.Group(group, false,
            intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(false))))
        set("player", java.lang.reflect.Proxy.newProxyInstance(androidx.media3.exoplayer.ExoPlayer::class.java.classLoader,
            arrayOf(androidx.media3.exoplayer.ExoPlayer::class.java)) { _, method, args ->
            if (method.name == "getCurrentTracks") tracks else method.invoke(probe.player, *(args ?: emptyArray()))
        })
        invoke("showSubtitleTrackDialog")
        val dialog = org.robolectric.shadows.ShadowDialog.getLatestDialog() as androidx.appcompat.app.AlertDialog
        assertEquals("Select Subtitle Track", dialog.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals("Off", dialog.listView.adapter.getItem(0))
    }
}
