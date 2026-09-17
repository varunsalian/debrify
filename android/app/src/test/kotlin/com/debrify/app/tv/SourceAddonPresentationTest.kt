package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SourceAddonPresentationTest {
    @Test fun preservesMultilineFormatterText() {
        assertEquals("4K\n★ ★ ★" to "Narcos\nHEVC · EN\nProvider",
            sourceAddonPresentation("4K\n★ ★ ★", "original", "Narcos\nHEVC · EN\nProvider"))
    }
    @Test fun legacyTitleFallbackMatchesDart() {
        assertEquals("4K" to "Original title", sourceAddonPresentation("4K", "Original title", null))
        assertEquals("Original title" to "Details", sourceAddonPresentation(null, "Original title", "Details"))
    }
    @Test fun descriptionOnlyIsNotDuplicated() {
        assertEquals("Details" to null, sourceAddonPresentation(" ", null, "Details"))
        assertEquals("Same" to null, sourceAddonPresentation("Same", null, "Same"))
    }
    @Test fun absentAddonTextKeepsFilenameMode() {
        assertNull(sourceAddonPresentation(null, " ", ""))
    }
}
