package com.debrify.app.tv

import android.widget.TextView
import androidx.media3.common.C
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleSourcesRefreshCharacterizationTest : TvPhase14OriginalTest() {
    private fun panelHeading() = (TvPlayerOriginalAccess.field(field("subtitlePanel")!!, "identityLabel") as TextView).text.toString()
    @Suppress("UNCHECKED_CAST") private fun labels() = (field("subtitleTracks") as List<Pair<String, androidx.media3.common.TrackSelectionOverride?>>).map { it.first }
    @Test fun clearLoadingPublishesDiscoveryRunsAutoSelectionAndRefreshesVisiblePanel() {
        call("showSubtitleSettingsPanel", emptyArray()); set("manualSubtitleDisplayLabel", "Fresh identity")
        set("userManuallySelectedSubtitle", false); flag("subtitle_forced_only", true)
        (field("subtitleTrackReadiness") as SubtitleTrackReadiness).onReady()
        set("externalSubtitleActive", true); set("currentStremioSubtitleIndex", 0); set("isLoadingStremioSubtitles", true); set("subtitleAddonDiscoveryReady", false)
        clearLoading()
        assertFalse(loading()); assertTrue(discovery()); assertEquals(false, field("externalSubtitleActive")); assertEquals(-1, field("currentStremioSubtitleIndex"))
        assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)); assertEquals(listOf("Off"), labels()); assertEquals("Subtitles for Fresh identity", panelHeading())
    }
    @Test fun clearLoadingLeavesHiddenPanelTrackSnapshotUntouched() {
        call("hideSubtitleSettingsPanel", emptyArray())
        @Suppress("UNCHECKED_CAST") val tracks = field("subtitleTracks") as MutableList<Pair<String, androidx.media3.common.TrackSelectionOverride?>>
        tracks.clear(); set("isLoadingStremioSubtitles", true); set("subtitleAddonDiscoveryReady", false)
        clearLoading(); assertFalse(loading()); assertTrue(discovery()); assertTrue(tracks.isEmpty())
    }
    @Test fun metadataLookupStartRepaintsVisiblePanelIntoLoadingState() {
        call("showSubtitleSettingsPanel", emptyArray()); model().imdbId = null
        fetch(); assertTrue(loading()); assertEquals(listOf("Off", "⏳ Loading external subtitles..."), labels())
    }
    @Test fun fanoutAndSlotCompletionRepaintBothVisibleSurfaces() {
        menu().show("subs", "search"); call("showSubtitleSettingsPanel", emptyArray()); installAddons(addon())
        val response = response(); known(); entered(response)
        assertTrue(labels().contains("⏳ Loading external subtitles..."))
        assertTrue((TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model).col2.any { it.title == "Addon a" && it.value == "…" })
        complete(response, jobs().single())
        assertFalse(labels().contains("⏳ Loading external subtitles...")); assertTrue(labels().any { it.startsWith("⬇") })
        assertTrue((TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model).col2.any { it.title == "Addon a" && it.value == "1" })
    }
    @Test fun emptyDiscoveryClearsStaleAddonRowsAndRepaintsWithoutLaunchingAnyWorker() {
        slots().add(com.debrify.app.subtitle.AddonSubtitleResult(addon(), com.debrify.app.subtitle.AddonSubtitleStatus.OK, listOf(subtitle())))
        flat().add(subtitle()); set("currentStremioSubtitleIndex", 0)
        menu().show("subs", "addon:a"); call("showSubtitleSettingsPanel", emptyArray())
        set("stremioSubtitleService", null); known()
        assertTrue(slots().isEmpty()); assertTrue(flat().isEmpty()); assertEquals(listOf("Off"), labels())
        val model = TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model
        assertEquals(listOf("Embedded", "Fix movie", "Appearance", "Timing"), model.col2.map { it.title })
        assertTrue(jobs().isEmpty()); assertFalse(loading())
    }
    @Test fun retryImmediatelyRepaintsFailedSlotIntoLoadingOnBothSurfaces() {
        val old = subtitle(); slots().add(com.debrify.app.subtitle.AddonSubtitleResult(addon(), com.debrify.app.subtitle.AddonSubtitleStatus.FAILED, listOf(old), "old failure"))
        flat().add(old); menu().show("subs", "addon:a"); call("showSubtitleSettingsPanel", emptyArray())
        val response = response(); invoke("retryAddonSubtitles", "a"); entered(response)
        assertTrue(labels().contains("⏳ Loading external subtitles..."))
        val model = TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model
        assertEquals("…", model.col2.single { it.title == "Addon a" }.value)
        assertEquals(listOf("Wrong subtitles? Fix the title", "Off", "Embedded", "Addon a", "Loading…"), model.col3.map { it.title }); complete(response, jobs().single())
    }
}
