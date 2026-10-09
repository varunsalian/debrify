package com.debrify.app.tv

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleCueCache
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleAutoSelectCharacterizationTest : TvPhase14OriginalTest() {
    @Before fun enableAutomaticChoice() {
        set("userManuallySelectedSubtitle", false); set("suppressSubtitleAutoSelect", false)
        set("currentStremioSubtitleIndex", -1); set("subtitleAddonDiscoveryReady", true)
        (field("subtitleTrackReadiness") as SubtitleTrackReadiness).onReady()
        pref("player_default_subtitle_language", "en"); flag("subtitle_auto_sync_enabled", false)
    }
    private fun format(language: String? = "en", label: String? = null, id: String? = null,
        flags: Int = 0, mime: String = MimeTypes.TEXT_VTT, channel: Int = Format.NO_VALUE) =
        Format.Builder().setSampleMimeType(mime).setLanguage(language).setLabel(label).setId(id)
            .setSelectionFlags(flags).setAccessibilityChannel(channel).build()
    private fun group(vararg formats: Format, selected: Int = -1, supported: Int = C.FORMAT_HANDLED) =
        Tracks.Group(TrackGroup(*formats), false, IntArray(formats.size) { supported }, BooleanArray(formats.size) { it == selected })
    private fun embedded(vararg formats: Format, selected: Int = -1, supported: Int = C.FORMAT_HANDLED): Tracks.Group =
        group(*formats, selected = selected, supported = supported).also { tracks = Tracks(listOf(it)) }
    private fun overrideIndex(group: Tracks.Group): List<Int>? = ts().parameters.overrides[group.mediaTrackGroup]?.trackIndices
    @Suppress("UNCHECKED_CAST") private fun cache() = TvPlayerOriginalAccess.field(SubtitleCueCache, "cache") as MutableMap<String, List<SubtitleCue>>
    private fun addonTracks(vararg subtitles: com.debrify.app.subtitle.StremioSubtitle, id: String = "a", status: AddonSubtitleStatus = AddonSubtitleStatus.OK) {
        slots().add(AddonSubtitleResult(addon(id), status, subtitles.toList()))
        flat().addAll(subtitles)
        subtitles.forEach { cache()[it.url] = listOf(SubtitleCue(0, 1_000, "cached")) }
    }
    private fun chosen(url: String) {
        assertEquals(url, field("activeExternalSubtitleUrl")); assertEquals(true, field("externalSubtitleActive"))
        assertEquals(flat().indexOfFirst { it.url == url }, field("currentStremioSubtitleIndex"))
    }
    @Test fun missingPlayerLeavesExistingSelectorParameters() {
        val group = embedded(format()); val before = ts().parameters; set("player", null); autoSelect()
        assertSame(before, ts().parameters); assertNull(overrideIndex(group))
    }
    @Test fun mediaReadinessPreventsEarlySelectionUntilReadyCallback() {
        val group = embedded(format()); (field("subtitleTrackReadiness") as SubtitleTrackReadiness).onMediaReplacement()
        autoSelect(); assertNull(overrideIndex(group))
        (field("subtitleTrackReadiness") as SubtitleTrackReadiness).onReady(); autoSelect(); assertEquals(listOf(0), overrideIndex(group))
    }
    @Test fun bufferingPlayerPreventsSelectionDespiteTrackReadiness() {
        val group = embedded(format()); probe.state = androidx.media3.common.Player.STATE_BUFFERING; autoSelect(); assertNull(overrideIndex(group))
        probe.state = androidx.media3.common.Player.STATE_READY; autoSelect(); assertEquals(listOf(0), overrideIndex(group))
    }
    @Test fun manualSelectionKeepsOverridesAndExternalSelection() {
        val group = embedded(format()); set("userManuallySelectedSubtitle", true); autoSelect(); assertNull(overrideIndex(group))
    }
    @Test fun injectedSuppressionKeepsAutomaticSelectionOff() {
        val group = embedded(format()); set("suppressSubtitleAutoSelect", true); autoSelect(); assertNull(overrideIndex(group))
    }
    @Test fun explicitOffPreferenceKeepsExistingChoiceAsInOriginalPolicy() {
        val group = embedded(format()); pref("player_default_subtitle_language", "off")
        set("externalSubtitleActive", true); set("currentStremioSubtitleIndex", 3); autoSelect()
        assertNull(overrideIndex(group)); assertEquals(3, field("currentStremioSubtitleIndex")); assertEquals(true, field("externalSubtitleActive"))
    }
    @Test fun alreadySelectedAddonKeepsEmbeddedOverridesUnchanged() {
        val group = embedded(format()); set("currentStremioSubtitleIndex", 0); autoSelect(); assertNull(overrideIndex(group))
    }
    @Test fun audioGroupsAreExcludedFromEmbeddedPositionIndices() {
        val audio = group(format("fr", mime = MimeTypes.AUDIO_AAC), selected = 0)
        val text = group(format("es"), format("en")); tracks = Tracks(listOf(audio, text)); autoSelect()
        assertEquals(listOf(1), overrideIndex(text)); assertNull(overrideIndex(audio))
    }
    @Test fun manualIdentityExcludesEmbeddedTracksAndUsesAddonResults() {
        val group = embedded(format()); set("manualSubtitleImdbId", "tt-manual"); addonTracks(subtitle())
        autoSelect(); assertNull(overrideIndex(group)); chosen(subtitle().url)
    }
    @Test fun supportedMatchingEmbeddedTrackClearsTextDisableAndAddsOverride() {
        val group = embedded(format("fr"), format("eng")); ts().parameters = ts().parameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
        autoSelect(); assertEquals(listOf(1), overrideIndex(group)); assertFalse(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun selectedMatchingEmbeddedTrackDoesNotReplaceSelectorParameters() {
        val group = embedded(format(), selected = 0); val before = ts().parameters; autoSelect()
        assertSame(before, ts().parameters); assertNull(overrideIndex(group))
    }
    @Test fun embeddedLanguageCanMatchLabelOrIdUnlessForcedOnly() {
        var group = embedded(format("fr", label = "eng")); autoSelect(); assertEquals(listOf(0), overrideIndex(group))
        group = embedded(format("fr", id = "eng")); autoSelect(); assertEquals(listOf(0), overrideIndex(group))
    }
    @Test fun unsupportedEmbeddedTrackFallsBackToAddon() {
        val group = embedded(format(), supported = C.FORMAT_UNSUPPORTED_TYPE); addonTracks(subtitle()); autoSelect()
        assertNull(overrideIndex(group)); chosen(subtitle().url)
    }
    @Test fun nullLanguagePreferenceAllowsSelectedForeignEmbeddedTrack() {
        pref("player_default_subtitle_language", null); val group = embedded(format("fr"), format("en"), selected = 0)
        val before = ts().parameters; autoSelect(); assertSame(before, ts().parameters); assertNull(overrideIndex(group))
    }
    @Test fun nullLanguagePreferenceUsesDefaultFlagBeforeUnmatchedFirstTrack() {
        pref("player_default_subtitle_language", null)
        val group = embedded(format("fr"), format("es", flags = C.SELECTION_FLAG_DEFAULT)); autoSelect()
        assertEquals(listOf(1), overrideIndex(group))
    }
    @Test fun nullLanguagePreferenceStillPrefersMatchingEnglishToDefaultForeignTrack() {
        pref("player_default_subtitle_language", null)
        val group = embedded(format("fr", flags = C.SELECTION_FLAG_DEFAULT), format("eng")); autoSelect()
        assertEquals(listOf(1), overrideIndex(group))
    }
    @Test fun foreignAudioGateClearsExternalAndDisablesTextForMatchingAudio() {
        flag("subtitle_only_foreign_audio", true); pref("player_default_audio_language", "en")
        tracks = Tracks(listOf(group(format("eng", mime = MimeTypes.AUDIO_AAC), selected = 0), group(format())))
        set("externalSubtitleActive", true); set("currentStremioSubtitleIndex", 2); autoSelect()
        assertEquals(false, field("externalSubtitleActive")); assertEquals(-1, field("currentStremioSubtitleIndex"))
        assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)); assertTrue(ts().parameters.overrides.isEmpty())
    }
    @Test fun unknownPreferredOrSelectedAudioDoesNotCountAsForeign() {
        flag("subtitle_only_foreign_audio", true); pref("player_default_audio_language", null)
        val group = embedded(format()); autoSelect(); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)); assertNull(overrideIndex(group))
        pref("player_default_audio_language", "en"); autoSelect(); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun genuinelyForeignSelectedAudioAllowsEmbeddedSubtitles() {
        flag("subtitle_only_foreign_audio", true); pref("player_default_audio_language", "en")
        val text = group(format()); tracks = Tracks(listOf(group(format("fr", mime = MimeTypes.AUDIO_AAC), selected = 0), text))
        autoSelect(); assertEquals(listOf(0), overrideIndex(text))
    }
    @Test fun forcedOnlyUsesLanguageAndForcedFlagWithoutLabelOrIdFallback() {
        flag("subtitle_forced_only", true)
        val group = embedded(format("fr", label = "eng", id = "eng", flags = C.SELECTION_FLAG_FORCED),
            format("en"), format("eng", flags = C.SELECTION_FLAG_FORCED)); autoSelect()
        assertEquals(listOf(2), overrideIndex(group))
    }
    @Test fun forcedOnlyWithoutEligibleTrackTurnsTextOffEvenIfAddonSelected() {
        flag("subtitle_forced_only", true); embedded(format()); set("externalSubtitleActive", false); set("currentStremioSubtitleIndex", 1)
        autoSelect(); assertEquals(false, field("externalSubtitleActive")); assertEquals(-1, field("currentStremioSubtitleIndex")); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }
    @Test fun offDecisionDoesNotReplaceAlreadyDisabledSelectorParameters() {
        flag("subtitle_forced_only", true); val group = embedded(format())
        ts().parameters = ts().parameters.buildUpon()
            .setOverrideForType(androidx.media3.common.TrackSelectionOverride(group.mediaTrackGroup, listOf(0)))
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
        val before = ts().parameters; autoSelect(); assertSame(before, ts().parameters)
    }
    @Test fun absentSelectorDoesNotPreventOffDecisionFromStoppingExternalRendering() {
        flag("subtitle_forced_only", true); embedded(format()); set("externalSubtitleActive", true); set("trackSelector", null)
        autoSelect(); assertEquals(false, field("externalSubtitleActive")); assertEquals(-1, field("currentStremioSubtitleIndex"))
    }
    @Test fun savedAddonPriorityWinsOverMatchingEmbeddedTracks() {
        pref("subtitle_source_priority_v1", "[\"addon:a\",\"embedded\"]")
        val group = embedded(format()); addonTracks(subtitle()); autoSelect(); chosen(subtitle().url); assertNull(overrideIndex(group))
    }
    @Test fun preferredAddonDiscoveryAndLoadingBlockEmbeddedFallback() {
        pref("subtitle_source_priority_v1", "[\"addon:a\",\"embedded\"]"); val group = embedded(format())
        set("subtitleAddonDiscoveryReady", false); autoSelect(); assertNull(overrideIndex(group))
        set("subtitleAddonDiscoveryReady", true); addonTracks(id = "a", status = AddonSubtitleStatus.LOADING); autoSelect(); assertNull(overrideIndex(group))
    }
    @Test fun failedUrlsAreExcludedFromAddonSelection() {
        val bad = subtitle(); val good = subtitle("https://phase14.invalid/good.srt")
        addonTracks(bad, good)
        @Suppress("UNCHECKED_CAST") val failures = field("failedSubtitleUrls") as MutableSet<String>
        failures.add(bad.url); autoSelect(); chosen(good.url)
    }
    @Test fun explicitLanguageDoesNotFallBackToOtherAddonLanguages() {
        addonTracks(subtitle(lang = "spa", label = "Spanish")); autoSelect()
        assertEquals(-1, field("currentStremioSubtitleIndex")); assertEquals(false, field("externalSubtitleActive"))
    }
    @Test fun nullLanguagePreferenceAppendsEligibleUnmatchedAddonTracksAfterMatches() {
        pref("player_default_subtitle_language", null)
        addonTracks(subtitle("https://phase14.invalid/es.srt", lang = "spa"), subtitle("https://phase14.invalid/en.srt", lang = "eng"))
        autoSelect(); chosen("https://phase14.invalid/en.srt")
        set("currentStremioSubtitleIndex", -1); set("externalSubtitleActive", false); slots()[0] = slots()[0].copy(subtitles = listOf(slots()[0].subtitles[0]))
        autoSelect(); chosen("https://phase14.invalid/es.srt")
    }
    @Test fun brazilianPortugueseAddonCanMatchItsLabel() {
        pref("player_default_subtitle_language", "pT-Br"); addonTracks(subtitle(lang = "por", label = "pt-BR")); autoSelect(); chosen(subtitle().url)
    }
    @Test fun addonSelectionUsesPriorityIdentityAndRepinsFlatUrlIndex() {
        val selected = subtitle("https://phase14.invalid/selected.srt", "b")
        flat().add(subtitle("https://phase14.invalid/other.srt")); addonTracks(selected, id = "b")
        pref("subtitle_source_priority_v1", "[\"addon:b\"]"); autoSelect(); chosen(selected.url); assertEquals(1, field("currentStremioSubtitleIndex"))
    }
    @Test fun undeclaredHlsCaptionIsExcludedButDeclaredCaptionCanBeSelected() {
        val parser = androidx.media3.exoplayer.hls.playlist.HlsPlaylistParser()
        val media = parser.parse(android.net.Uri.parse("https://phase14.invalid/hls.m3u8"),
            java.io.ByteArrayInputStream("#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n#EXTINF:10,\nsegment.ts\n#EXT-X-ENDLIST\n".toByteArray())) as androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist
        val multi = androidx.media3.exoplayer.hls.playlist.HlsMultivariantPlaylist.createSingleVariantMultivariantPlaylist("https://phase14.invalid/hls.m3u8")
        currentManifest = androidx.media3.exoplayer.hls.HlsManifest::class.java.getDeclaredConstructor(multi.javaClass, media.javaClass)
            .apply { isAccessible = true }.newInstance(multi, media)
        pref("player_default_subtitle_language", null)
        val group = embedded(format(null, mime = MimeTypes.APPLICATION_CEA608), format(null, mime = MimeTypes.APPLICATION_CEA608, channel = 1))
        autoSelect(); assertEquals(listOf(1), overrideIndex(group))
    }
    @Test fun noEligibleEmbeddedOrAddonLeavesCurrentStateUnchanged() {
        val group = embedded(format("fr")); val before = ts().parameters; autoSelect()
        assertSame(before, ts().parameters); assertNull(overrideIndex(group)); assertEquals(-1, field("currentStremioSubtitleIndex"))
    }
    @Test fun knownImdbCompletionOfDiscoverySelectsReadyEmbeddedWithoutAnotherCallback() {
        pref("subtitle_source_priority_v1", "[\"addon:a\",\"embedded\"]")
        set("subtitleAddonDiscoveryReady", false); val group = embedded(format())
        known(); assertTrue(discovery()); assertFalse(loading()); assertEquals(listOf(0), overrideIndex(group))
    }
    @Test fun completedAddonWorkerAutomaticallySelectsItsPublishedTrack() {
        pref("subtitle_source_priority_v1", "[\"addon:a\",\"embedded\"]")
        installAddons(addon()); cache()[subtitle().url] = listOf(SubtitleCue(0, 1000, "cached"))
        val response = response(); known(); entered(response)
        val job = jobs().single(); assertEquals(-1, field("currentStremioSubtitleIndex"))
        complete(response, job); chosen(subtitle().url)
    }
}
