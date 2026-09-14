package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TvSourceBadgeTextTest {
    @Test fun missingPartsDoNotIntroduceNewlines() {
        assertNull(sourceBadgeDescription(null, ""))
        assertNull(sourceBadgeDescription("", ""))
        assertEquals("HDR", sourceBadgeDescription("", "HDR"))
        assertEquals("HDR", sourceBadgeDescription("HDR", ""))
        assertEquals("Provider\nHDR", sourceBadgeDescription("Provider", "HDR"))
    }
    @Test fun nonemptyWhitespaceIsPreservedLikeDart() {
        assertEquals(" \n HDR ", sourceBadgeDescription(" ", " HDR "))
    }
}
