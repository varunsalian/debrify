package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import org.junit.Test

class SubtitleAutoSelectionTest {
    @Test fun sourceReplacementInvalidatesReadinessUntilNewSourceIsReady() {
        val readiness = SubtitleTrackReadiness()
        readiness.onReady()
        assertTrue(readiness.canSelect(playerReady = true))

        readiness.onMediaReplacement()
        // The old player can still report READY immediately before setMediaItem.
        assertFalse(readiness.canSelect(playerReady = true))
        // Pending addon response during replacement must wait, even with no tracks.
        assertEquals(SubtitleAutoSelection.Wait, choose(
            ready = readiness.canSelect(playerReady = false),
        ))
        readiness.onReady()
        assertEquals(SubtitleAutoSelection.Embedded(0), choose(
            listOf(track(matches = true)), ready = readiness.canSelect(playerReady = true),
        ))
    }

    @Test fun mediaReplacementPreservesManualSubtitleChoice() {
        val readiness = SubtitleTrackReadiness()
        readiness.onReady()
        readiness.onMediaReplacement()
        assertEquals(SubtitleAutoSelection.Keep, choose(
            ready = readiness.canSelect(playerReady = false), manual = true,
        ))
        readiness.onReady()
        assertEquals(SubtitleAutoSelection.Keep, choose(
            listOf(track(matches = true)), ready = readiness.canSelect(playerReady = true),
            manual = true,
        ))
    }

    @Test fun bufferingCannotReusePreviouslyReadyTracksForAddonSelection() {
        val readiness = SubtitleTrackReadiness()
        readiness.onReady()
        assertEquals(SubtitleAutoSelection.Wait, choose(
            ready = readiness.canSelect(playerReady = false),
        ))
    }

    @Test fun undeclaredHlsCaptionDoesNotSuppressAddonFallback() {
        val synthetic = isUndeclaredHlsCaption(
            true, MimeTypes.APPLICATION_CEA608, Format.NO_VALUE, null,
        )
        assertTrue(synthetic)
        val placeholder = track().copy(undeclaredHlsCaption = synthetic)
        assertEquals(SubtitleAutoSelection.Addon, choose(listOf(placeholder)))
        assertEquals(SubtitleAutoSelection.Embedded(1), choose(listOf(placeholder, track())))
        assertEquals(SubtitleAutoSelection.Keep, choose(listOf(placeholder), manual = true))
    }

    @Test fun declaredCaptionsAndRealUntaggedSubtitlesRemainEligible() {
        for ((isHls, mime, channel) in listOf(
            Triple(true, MimeTypes.APPLICATION_CEA608, 1),
            Triple(true, MimeTypes.APPLICATION_CEA708, 1),
            Triple(true, MimeTypes.TEXT_VTT, Format.NO_VALUE),
            Triple(false, MimeTypes.APPLICATION_SUBRIP, Format.NO_VALUE),
            Triple(false, MimeTypes.APPLICATION_CEA608, Format.NO_VALUE),
        )) {
            val synthetic = isUndeclaredHlsCaption(isHls, mime, channel, null)
            assertFalse(synthetic)
            assertEquals(SubtitleAutoSelection.Embedded(0), choose(listOf(
                track().copy(undeclaredHlsCaption = synthetic),
            )))
        }
    }

    private fun track(
        matches: Boolean = false,
        selected: Boolean = false,
        supported: Boolean = true,
        default: Boolean = false,
    ) = EmbeddedSubtitleCandidate(supported, selected, matches, default)

    private fun choose(
        tracks: List<EmbeddedSubtitleCandidate> = emptyList(),
        ready: Boolean = true,
        pref: String? = null,
        manual: Boolean = false,
        suppressed: Boolean = false,
        addon: Boolean = false,
    ) = chooseAutomaticSubtitle(ready, pref, manual, suppressed, addon, tracks)

    @Test fun fastAddonWaitsThenEmbeddedWinsWhenTracksArrive() {
        assertEquals(SubtitleAutoSelection.Wait, choose(ready = false))
        assertEquals(SubtitleAutoSelection.Embedded(0), choose(listOf(track(matches = true))))
    }

    @Test fun addonCanBeUsedAfterReadyWithoutEmbeddedTracks() {
        assertEquals(SubtitleAutoSelection.Wait, choose(ready = false))
        assertEquals(SubtitleAutoSelection.Addon, choose())
    }

    @Test fun noPreferenceAllowsUntaggedEmbeddedSubtitle() {
        assertEquals(SubtitleAutoSelection.Embedded(0), choose(listOf(track())))
    }

    @Test fun noPreferenceKeepsAlreadySelectedEmbeddedLanguage() {
        assertEquals(SubtitleAutoSelection.Embedded(1), choose(listOf(
            track(matches = true), track(selected = true),
        )))
    }

    @Test fun noPreferencePrefersEnglishThenDefaultTrack() {
        assertEquals(SubtitleAutoSelection.Embedded(1), choose(listOf(
            track(default = true), track(matches = true),
        )))
        assertEquals(SubtitleAutoSelection.Embedded(1), choose(listOf(
            track(), track(default = true),
        )))
    }

    @Test fun explicitLanguageDoesNotAcceptUnrelatedEmbeddedTracks() {
        assertEquals(SubtitleAutoSelection.Addon, choose(
            listOf(track(selected = true)), pref = "es",
        ))
        assertEquals(SubtitleAutoSelection.Embedded(1), choose(
            listOf(track(selected = true), track(matches = true)), pref = "es",
        ))
    }

    @Test fun unsupportedEmbeddedTracksDoNotBlockAddonFallback() {
        assertEquals(SubtitleAutoSelection.Addon, choose(listOf(
            track(matches = true, supported = false),
        )))
    }

    @Test fun manualOffInjectedAndExistingAddonSelectionsAreRespected() {
        val tracks = listOf(track(matches = true))
        assertEquals(SubtitleAutoSelection.Keep, choose(tracks, pref = "off"))
        assertEquals(SubtitleAutoSelection.Keep, choose(tracks, manual = true))
        assertEquals(SubtitleAutoSelection.Keep, choose(tracks, suppressed = true))
        assertEquals(SubtitleAutoSelection.Keep, choose(tracks, addon = true))
    }

    @Test fun nextEpisodeWaitsForItsOwnTracks() {
        assertEquals(SubtitleAutoSelection.Embedded(0), choose(listOf(track())))
        assertEquals(SubtitleAutoSelection.Wait, choose(listOf(track()), ready = false))
        assertEquals(SubtitleAutoSelection.Addon, choose())
    }
}
