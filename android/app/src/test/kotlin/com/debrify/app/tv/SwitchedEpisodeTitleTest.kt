package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class SwitchedEpisodeTitleTest {
    private val filename = "The Gentlemen 2024 S02E02 1080p WEB H264-CAKES"

    @Test fun nextSingleFileUsesGuideNameInsteadOfReleaseName() {
        assertEquals("The Next Chapter", resolveSwitchedEpisodeTitle(
            2, filename, filename, "The Next Chapter", null,
        ))
    }

    @Test fun missingMetadataUsesEpisodeNumber() {
        assertEquals("Episode 2", resolveSwitchedEpisodeTitle(
            2, filename, filename, null, null,
        ))
    }

    @Test fun sameEpisodeSourceSwitchPreservesFetchedTitle() {
        assertEquals("Proper Business", resolveSwitchedEpisodeTitle(
            2, filename, filename, null, "Proper Business",
        ))
    }

    @Test fun enrichedPackKeepsIncomingEpisodeTitle() {
        assertEquals("Proper Business", resolveSwitchedEpisodeTitle(
            2, "Proper Business", filename, null, null,
        ))
    }

    @Test fun blankMetadataAndLegacyPayloadFallBackCleanly() {
        assertEquals("Episode 2", resolveSwitchedEpisodeTitle(
            2, filename, null, " ", "",
        ))
    }

    @Test fun newlyFetchedTitleReplacesPreviousPlaceholder() {
        assertEquals("Proper Business", resolveSwitchedEpisodeTitle(
            2, "Proper Business", filename, null, "Episode 2",
        ))
    }

    @Test fun incomingPlaceholderDoesNotReplacePreviousFetchedTitle() {
        assertEquals("Proper Business", resolveSwitchedEpisodeTitle(
            2, "Episode 2", filename, null, "Proper Business",
        ))
    }
}
