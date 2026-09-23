package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test

class ForcedSubtitlePolicyTest {
    private fun pick(
        candidates: List<EmbeddedSubtitleCandidate> = emptyList(),
        manual: Boolean = false, ready: Boolean = true, preference: String? = "en",
    ) = chooseAutomaticSubtitle(
        tracksReady = ready, preference = preference, manualSelection = manual,
        suppressed = false, addonSelected = false, candidates = candidates,
        forcedOnly = true, audioAllowsSubtitles = false,
        sourcePriority = listOf("addon:a", "embedded"), addonDiscoveryReady = false,
        addons = listOf(AddonSubtitleCandidate("a", true, listOf(0))),
    )

    @Test fun selectsForcedInPreferredLanguageEvenWithMatchingAudioAndPendingAddons() {
        val full = EmbeddedSubtitleCandidate(true, true, true, true)
        val foreign = EmbeddedSubtitleCandidate(true, false, false, false, forcedTrack = true)
        val forced = EmbeddedSubtitleCandidate(true, false, true, false, forcedTrack = true)
        assertEquals(SubtitleAutoSelection.Embedded(2), pick(listOf(full, foreign, forced)))
    }
    @Test fun noForcedMatchStaysOffWithoutFallingBackToFullOrAddonSubtitles() {
        assertEquals(SubtitleAutoSelection.Off, pick())
        assertEquals(SubtitleAutoSelection.Off, pick(listOf(
            EmbeddedSubtitleCandidate(true, true, true, true),
            EmbeddedSubtitleCandidate(false, false, true, false, forcedTrack = true),
            EmbeddedSubtitleCandidate(true, false, false, false, forcedTrack = true),
        )))
    }
    @Test fun manualChoicesAndOffPreferenceArePreservedAndTrackReadinessIsRequired() {
        assertEquals(SubtitleAutoSelection.Keep, pick(manual = true))
        assertEquals(SubtitleAutoSelection.Keep, pick(preference = "off"))
        assertEquals(SubtitleAutoSelection.Wait, pick(ready = false))
    }
}
