package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class SubtitleSourcePriorityTest {
    private val embedded = listOf(EmbeddedSubtitleCandidate(true, true, true, false))
    private fun choose(
        order: List<String> = listOf("embedded"),
        addons: List<AddonSubtitleCandidate> = emptyList(),
        candidates: List<EmbeddedSubtitleCandidate> = embedded,
        ready: Boolean = true,
        discovery: Boolean = true,
        manual: Boolean = false,
        language: String? = null,
    ) = chooseAutomaticSubtitle(ready, language, manual, false, false, candidates, order, addons, discovery)

    @Test fun defaultKeepsEmbeddedAheadOfAddons() {
        assertEquals(SubtitleAutoSelection.Embedded(0), choose(addons = listOf(AddonSubtitleCandidate("a", false, listOf(0)))))
    }
    @Test fun customAddonWinsEvenWithSelectedEmbeddedTrack() {
        assertEquals(SubtitleAutoSelection.AddonTrack("b", 2), choose(
            order = listOf("addon:b", "embedded", "addon:a"),
            addons = listOf(AddonSubtitleCandidate("a", false, listOf(0)), AddonSubtitleCandidate("b", false, listOf(2))),
        ))
    }
    @Test fun preferredAddonCannotLoseToAFasterResponse() {
        assertEquals(SubtitleAutoSelection.Wait, choose(
            order = listOf("addon:b", "addon:a", "embedded"),
            addons = listOf(AddonSubtitleCandidate("a", false, listOf(0)), AddonSubtitleCandidate("b", true, emptyList())),
        ))
    }
    @Test fun failedOrUnmatchedPreferredAddonFallsBackToEmbedded() {
        assertEquals(SubtitleAutoSelection.Embedded(0), choose(
            order = listOf("addon:b", "embedded"), addons = listOf(AddonSubtitleCandidate("b", false, emptyList())),
        ))
    }
    @Test fun removedAddonsAreSkippedAndNewAddonsRemainEligible() {
        assertEquals(SubtitleAutoSelection.AddonTrack("new", 0), choose(
            order = listOf("addon:removed", "embedded"), candidates = emptyList(),
            addons = listOf(AddonSubtitleCandidate("new", false, listOf(0))),
        ))
    }
    @Test fun sourceAndAddonDiscoveryMustBeReady() {
        assertEquals(SubtitleAutoSelection.Wait, choose(ready = false))
        assertEquals(SubtitleAutoSelection.Wait, choose(order = listOf("addon:a", "embedded"), discovery = false))
        assertEquals(SubtitleAutoSelection.Embedded(0), choose(discovery = false))
    }
    @Test fun manualAndOffSelectionsAlwaysWin() {
        assertEquals(SubtitleAutoSelection.Keep, choose(order = listOf("addon:a", "embedded"), manual = true))
        assertEquals(SubtitleAutoSelection.Keep, choose(language = "off"))
    }
}
