package com.debrify.app.tv

import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.NestedScrollView
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.common.TrackSelectionOverride
import com.debrify.app.MainActivity
import com.debrify.app.util.OffsetRenderersFactory
import com.debrify.app.util.SubtitleSettings
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Before
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import java.lang.reflect.Proxy

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvSubtitleSelectionCharacterizationTest : TvPhase4OriginalTest() {
    private val messenger = TvPlayerRecordingMessenger()
    private var previous: MethodChannel? = null
    @Before fun connect() { previous = MainActivity.getAndroidTvPlayerChannel(); MainActivity.setAndroidTvPlayerChannel(MethodChannel(messenger, "com.debrify.app/android_tv_player")) }
    @After fun disconnect() = MainActivity.setAndroidTvPlayerChannel(previous)
    private fun ts() = field("trackSelector") as DefaultTrackSelector
    @Suppress("UNCHECKED_CAST") private fun flat() = field("subtitleTracks") as MutableList<Pair<String, TrackSelectionOverride?>>
    @Suppress("UNCHECKED_CAST") private fun external() = field("stremioSubtitles") as MutableList<com.debrify.app.subtitle.StremioSubtitle>
    @Suppress("UNCHECKED_CAST") private fun rows(name: String) = invoke(name) as List<UnifiedMenuController.Row>
    private fun callbacks() = field("subtitlePanelCallbacks") as SubtitlePanelController.Callbacks
    private fun embedded(selected: Boolean = true): TrackSelectionOverride {
        val group = TrackGroup(Format.Builder().setSampleMimeType(MimeTypes.TEXT_VTT).setLanguage("en").setLabel("English CC").build())
        val tracks = Tracks(listOf(Tracks.Group(group, false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(selected))))
        set("player", Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, args ->
            if (method.name == "getCurrentTracks") tracks else method.invoke(probe.player, *(args ?: emptyArray()))
        } as ExoPlayer)
        return TrackSelectionOverride(group, listOf(0))
    }
    private fun factory(): OffsetRenderersFactory = OffsetRenderersFactory(androidx.media3.exoplayer.DefaultRenderersFactory(activity)).also { set("offsetRenderersFactory", it) }
    private fun panel(): Pair<SubtitlePanelController, LinearLayout> {
        val root = LinearLayout(activity).apply { visibility = View.GONE }
        val controller = SubtitlePanelController(activity, root, LinearLayout(activity), LinearLayout(activity),
            NestedScrollView(activity), NestedScrollView(activity), TextView(activity), TextView(activity), View(activity), callbacks())
        set("subtitlePanel", controller); return controller to root
    }
    @Test fun flatListIncludesOffEmbeddedExternalAndLoadingWithSelectedIndexPreserved() {
        setup(); embedded(); external().add(subtitle()); set("isLoadingStremioSubtitles", true)
        invoke("rebuildSubtitleTrackList")
        assertEquals(listOf("Off", "English CC (en)", "⬇ English (Addon)", "⏳ Loading external subtitles..."), callbacks().getTrackLabels())
        assertEquals(1, callbacks().getCurrentTrackIndex())
        set("currentStremioSubtitleIndex", 0); invoke("rebuildSubtitleTrackList"); assertEquals(2, callbacks().getCurrentTrackIndex())
        embedded(selected = false); set("currentStremioSubtitleIndex", -1); invoke("rebuildSubtitleTrackList"); assertEquals(0, callbacks().getCurrentTrackIndex())
    }
    @Test fun selectingEmbeddedAndOffClearsExternalStateOverridesAndOffset() {
        setup(); val override = embedded(); active(); val f = factory(); f.setOffsetUs(500_000); SubtitleSettings.setSyncOffsetMs(activity, 500)
        flat().addAll(listOf("Off" to null, "English CC (en)" to override)); set("currentSubtitleTrackIndex", 1)
        invoke("applySelectedSubtitleTrack")
        assertEquals(false, field("externalSubtitleActive")); assertEquals(-1, field("currentStremioSubtitleIndex"))
        assertEquals(override, ts().parameters.overrides[groupOf(override)]); assertFalse(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        assertEquals(0L, f.currentOffsetUs); assertEquals(0L, SubtitleSettings.getSyncOffsetMs(activity))
        set("currentSubtitleTrackIndex", 0); invoke("applySelectedSubtitleTrack")
        assertTrue(ts().parameters.overrides.isEmpty()); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    private fun groupOf(override: TrackSelectionOverride) = override.mediaTrackGroup
    @Test fun selectingExternalCountsOnlyExternalRowsAndLeavesPlayerSourceUnchanged() {
        setup(); embedded(); external().add(subtitle()); external().add(subtitle("https://phase4.invalid/second.srt", "Spanish"))
        cache()[url] = cues; cache()[external()[1].url] = cues
        flat().addAll(listOf("Off" to null, "⏳ Loading external subtitles..." to null, "English CC (en)" to embedded(), "⬇ English (Addon)" to null, "⬇ Spanish (Addon)" to null))
        set("currentSubtitleTrackIndex", 4); invoke("applySelectedSubtitleTrack")
        assertEquals(1, field("currentStremioSubtitleIndex")); assertEquals(external()[1].url, field("activeExternalSubtitleUrl"))
        assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)); assertTrue(probe.events.isEmpty())
    }
    @Test fun loadingAndInvalidPanelChoicesAreIgnoredButOffChoiceMarksManualSelection() {
        setup(); set("isLoadingStremioSubtitles", true); invoke("rebuildSubtitleTrackList")
        callbacks().selectTrack(1); callbacks().selectTrack(-1); callbacks().selectTrack(99)
        assertEquals(0, callbacks().getCurrentTrackIndex()); assertEquals(false, field("userManuallySelectedSubtitle"))
        callbacks().selectTrack(0); assertEquals(true, field("userManuallySelectedSubtitle")); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun embeddedMenuRowsKeepLabelsSelectedStateAndSelectionBetweenRenders() {
        setup(); embedded(); external().add(subtitle()); invoke("rebuildSubtitleTrackList")
        val rows = rows("umEmbeddedTrackRows"); assertEquals(listOf("Off", "English CC (en)"), rows.map { it.title })
        assertFalse(rows[0].selected); assertTrue(rows[1].selected); rows[0].onOk!!.invoke()
        assertEquals(true, field("userManuallySelectedSubtitle")); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        assertTrue(rows("umEmbeddedTrackRows")[0].selected)
        invoke("umSelectSubtitleRowIndex", 99); assertEquals(0, field("currentSubtitleTrackIndex"))
    }
    @Test fun externalUrlMenuSelectionRebuildsRowsUsesMatchingUrlAndIgnoresMissingUrl() {
        setup(); embedded(); external().add(subtitle()); external().add(subtitle("https://phase4.invalid/second.srt", "Spanish"))
        cache()[external()[1].url] = cues
        invoke("umSelectStremioSubtitleByUrl", external()[1].url)
        assertEquals(3, field("currentSubtitleTrackIndex")); assertEquals(1, field("currentStremioSubtitleIndex"))
        assertEquals(true, field("userManuallySelectedSubtitle")); assertEquals(external()[1].url, field("activeExternalSubtitleUrl"))
        invoke("umSelectStremioSubtitleByUrl", "missing"); assertEquals(3, field("currentSubtitleTrackIndex"))
    }
    @Test fun timingRowsShowNeedsListeningAndOnlyCurrentSubtitleOutcomeThenDispatchManualDefault() {
        setup(); var timing = rows("umTimingRows")
        assertEquals(listOf("Auto-sync from audio", "Adjust timing  ▸"), timing.map { it.title })
        assertEquals("needs an addon subtitle", timing[0].value); assertFalse(timing[0].enabled)
        active(); set("autoSyncRunning", true); timing = rows("umTimingRows"); assertEquals("listening…", timing[0].value); assertFalse(timing[0].enabled)
        set("autoSyncRunning", false); set("autoSyncResultLabel", "✓ remembered"); set("autoSyncResultUrl", "other"); assertNull(rows("umTimingRows")[0].value)
        set("autoSyncResultUrl", url); timing = rows("umTimingRows"); assertEquals("✓ remembered", timing[0].value); assertTrue(timing[0].enabled)
        val response = TvPhase4Response<com.debrify.app.util.AlignResult>(com.debrify.app.util.AlignResult.NoMatch(30)); pending.add(response); TvPhase4AlignerShadow.responses.add(response)
        timing[0].onOk!!.invoke(); entered(response); assertEquals("SYNCING SUBTITLES…", label()); complete(response, job())
    }
    @Test fun timingAdjustActionUsesEmbeddedOverlayAndAppearanceRowsDispatchPersistedSettings() {
        setup(); val timing = rows("umTimingRows"); assertEquals(SubtitleSettings.formatSyncOffset(0), timing[1].value)
        timing[1].onOk!!.invoke(); assertNotNull(field("syncOverlay")); assertNull(field("linePickerOverlay"))
        val appearance = rows("umAppearanceRows")
        assertEquals(listOf("Size", "Style", "Text colour", "Outline colour", "Background", "Position", "Font", "Bold", "Reset all to defaults"), appearance.map { it.title })
        val before = SubtitleSettings.getFontSizeSp(activity); appearance[0].onAdjust!!.invoke(1)
        assertNotEquals(before, SubtitleSettings.getFontSizeSp(activity))
        assertEquals("saveSubtitleAppearance", messenger.requests.last().call.method)
        assertEquals(SubtitleSettings.profileAppearanceSnapshot(activity), messenger.requests.last().call.arguments)
        appearance.last().onOk!!.invoke(); assertEquals(before, SubtitleSettings.getFontSizeSp(activity))
    }
    @Test fun panelShowRefreshHideAndCallbacksKeepVisibilityAndReturnFocusToPlayer() {
        setup(); val (panel, root) = panel(); set("manualSubtitleDisplayLabel", "  Film  ")
        invoke("showSubtitleSettingsPanel"); assertTrue(panel.isVisible); assertEquals(View.VISIBLE, root.visibility); assertEquals(true, field("subtitleSettingsVisible"))
        assertEquals("Subtitles for Film", callbacks().getIdentityLabel()); set("isLoadingStremioSubtitles", true)
        invoke("refreshSubtitlePanelForLoading"); assertEquals(listOf("Off", "⏳ Loading external subtitles..."), callbacks().getTrackLabels())
        invoke("hideSubtitleSettingsPanel"); assertFalse(panel.isVisible); assertEquals(View.GONE, root.visibility); assertEquals(false, field("subtitleSettingsVisible"))
        assertTrue((field("playerView") as View).hasFocus())
        set("subtitlePanel", null); set("subtitleSettingsVisible", true); invoke("hideSubtitleSettingsPanel"); assertEquals(false, field("subtitleSettingsVisible"))
    }
    @Test fun panelSettingsAndSyncCallbacksApplyAppearanceAndOpenEmbeddedSlider() {
        setup(); SubtitleSettings.setSizeIndex(activity, 2); callbacks().onSettingsChanged()
        assertEquals("saveSubtitleAppearance", messenger.requests.single().call.method)
        assertEquals(SubtitleSettings.profileAppearanceSnapshot(activity), messenger.requests.single().call.arguments)
        callbacks().onSyncOverlayRequested(); assertNotNull(field("syncOverlay"))
    }
    @Test fun subtitleIdentityScopesExternalByContentAndEmbeddedBySelectedTrack() {
        setup(); assertNull(invoke("currentSubtitleIdentity")); embedded(); assertEquals("idx:0|emb", invoke("currentSubtitleIdentity"))
        active(); assertEquals("idx:0|ext:$url", invoke("currentSubtitleIdentity"))
        set("payload", PlaybackPayload("Film", null, "movie", mutableListOf(p2Item().copy(resumeId = "content")), 0, null))
        assertEquals("content|ext:$url", invoke("currentSubtitleIdentity")); set("activeExternalSubtitleUrl", null); assertNull(invoke("currentSubtitleIdentity"))
        set("externalSubtitleActive", false); assertEquals("content|emb", invoke("currentSubtitleIdentity"))
    }
    @Test fun embeddedOffsetDebouncesSeekAtOneHundredFiftyMillisecondsAndOffDoesNotPushOffset() {
        setup(); embedded(); probe.position = 1234; val f = factory()
        SubtitleSettings.setSyncOffsetMs(activity, 500); invoke("applySubtitleSettings"); assertEquals(500_000L, f.currentOffsetUs)
        advance(100); SubtitleSettings.setSyncOffsetMs(activity, 750); invoke("applySubtitleSettings"); advance(149)
        assertTrue(probe.events.isEmpty()); advance(1); assertEquals(listOf("seek:1234"), probe.events)
        assertEquals(750_000L, f.currentOffsetUs); embedded(selected = false); invoke("applySubtitleSettings"); assertEquals(0L, f.currentOffsetUs)
    }
    @Test fun syncPickerPrefersRenderingUrlWhenAddonListWasRebuiltAndDismissRestoresFocus() {
        setup(); active(); cache()["https://phase4.invalid/other.srt"] = cues; external().add(subtitle("https://phase4.invalid/other.srt")); set("currentStremioSubtitleIndex", 0)
        invoke("showSyncOverlay")
        val picker = field("linePickerOverlay") as SubtitleLinePickerController
        assertTrue(picker.isVisible); assertEquals(url, TvPlayerOriginalAccess.field(picker, "currentUrl")); assertNull(field("syncOverlay"))
        picker.hide(); assertNull(field("linePickerOverlay")); assertTrue((field("playerView") as View).hasFocus())
    }
    @Test fun syncPickerFallsBackToSelectedAddonAndEmbeddedSliderReusesItsInstance() {
        setup(); external().add(subtitle()); cache()[url] = cues; set("currentStremioSubtitleIndex", 0)
        callbacks().onSyncOverlayRequested(); assertNotNull("selected addon opens line picker", field("linePickerOverlay"))
        val picker = field("linePickerOverlay") as SubtitleLinePickerController
        assertEquals(url, TvPlayerOriginalAccess.field(picker, "currentUrl")); picker.hide()
        set("currentStremioSubtitleIndex", -1); invoke("showSyncOverlay"); val slider = field("syncOverlay") as SubtitleSyncOverlayController
        assertTrue(slider.isVisible); slider.hide(); invoke("showSyncOverlay"); assertSame(slider, field("syncOverlay")); slider.hide()
    }
    @Test fun legacySubtitleDialogKeepsNoTracksToastAndEmbeddedOffChoices() {
        setup(); invoke("showSubtitleTrackDialog")
        assertEquals("No subtitle tracks available", org.robolectric.shadows.ShadowToast.getTextOfLatestToast())
        embedded(); invoke("showSubtitleTrackDialog")
        val dialog = org.robolectric.shadows.ShadowDialog.getLatestDialog() as androidx.appcompat.app.AlertDialog
        assertEquals("Select Subtitle Track", dialog.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        dialog.listView.performItemClick(null, 0, 0)
        assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
        invoke("showSubtitleTrackDialog"); (org.robolectric.shadows.ShadowDialog.getLatestDialog() as androidx.appcompat.app.AlertDialog).listView.performItemClick(null, 1, 1)
        assertFalse(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)); assertEquals(1, ts().parameters.overrides.size)
    }
    @Test fun externalOffsetChangesRenderImmediatelyAndNeverSeek() {
        setup(); active(); probe.position = 2000; val f = factory(); SubtitleSettings.setSyncOffsetMs(activity, 1000)
        invoke("applySubtitleSettings"); assertEquals(listOf("first\nsecond"), text()); assertEquals(1_000_000L, f.currentOffsetUs)
        advance(200); assertTrue(probe.events.isEmpty())
    }
}
