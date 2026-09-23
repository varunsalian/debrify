package com.debrify.app.tv

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.Tracks
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class SubtitleAudioPolicyTest {
    private fun allows(audio: String?, preferred: String? = "en", enabled: Boolean = true) =
        audioAllowsAutomaticSubtitles(enabled, preferred, audio)

    private fun choose(audio: String?, manual: Boolean = false, addon: Boolean = false,
                       ready: Boolean = true, preference: String? = "en") = chooseAutomaticSubtitle(
        tracksReady = ready, preference = preference, manualSelection = manual,
        suppressed = false, addonSelected = addon,
        candidates = listOf(EmbeddedSubtitleCandidate(true, false, true, false)),
        audioAllowsSubtitles = allows(audio),
    )

    @Test fun onlyThePlayingAudioDeterminesThePolicy() {
        val group = Tracks.Group(
            TrackGroup(
                Format.Builder().setSampleMimeType("audio/aac").setLanguage("en").build(),
                Format.Builder().setSampleMimeType("audio/aac").setLanguage("jpn").build(),
            ), false, intArrayOf(C.FORMAT_HANDLED, C.FORMAT_HANDLED), booleanArrayOf(false, true),
        )
        assertEquals("ja", selectedAudioLanguage(Tracks(listOf(group))))
        assertTrue(allows(selectedAudioLanguage(Tracks(listOf(group)))))
        assertNull(selectedAudioLanguage(Tracks.EMPTY))
    }

    @Test fun defaultOffPreservesExistingSelection() {
        assertTrue(allows(null, null, false))
        assertTrue(allows("en", enabled = false))
    }

    @Test fun knownLanguagesNormalizeBeforeComparison() {
        for (tag in listOf("en", "eng", "English", "EN_us", "en-GB")) assertFalse(allows(tag))
        for (tag in listOf("jpn", "Japanese", "ja-JP", "hin", "fra")) assertTrue(allows(tag))
        assertFalse(allows("fra", "fr"))
        assertFalse(allows("pt-BR", "pt"))
    }

    @Test fun unknownAudioAndUnsetPreferenceStayOff() {
        for (tag in listOf(null, "", "und", "mul", "zxx", "unknown", "Track 1")) assertFalse(allows(tag))
        assertFalse(allows("ja", null))
    }

    @Test fun audioChangesDisableEmbeddedAndExternalSelections() {
        assertEquals(SubtitleAutoSelection.Embedded(0), choose("ja"))
        assertEquals(SubtitleAutoSelection.Off, choose("en"))
        assertEquals(SubtitleAutoSelection.Off, choose("en", addon = true))
        assertEquals(SubtitleAutoSelection.Off, choose(null, addon = true))
        assertEquals(SubtitleAutoSelection.Embedded(0), choose("ja"))
    }

    @Test fun manualChoicesAndGlobalOffWin() {
        assertEquals(SubtitleAutoSelection.Keep, choose("en", manual = true))
        assertEquals(SubtitleAutoSelection.Keep, choose("ja", manual = true))
        assertEquals(SubtitleAutoSelection.Keep, choose("ja", preference = "off"))
    }

    @Test fun nextEpisodeWaitsForItsOwnTracks() {
        assertEquals(SubtitleAutoSelection.Wait, choose("en", ready = false))
        assertEquals(SubtitleAutoSelection.Embedded(0), choose("ja", ready = true))
    }
}
