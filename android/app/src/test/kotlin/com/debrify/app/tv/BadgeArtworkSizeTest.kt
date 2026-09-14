package com.debrify.app.tv

import org.junit.Assert.assertEquals
import org.junit.Test

class BadgeArtworkSizeTest {
    @Test fun shortAndWideLogosGetDifferentWidths() {
        assertEquals(20, badgeArtworkWidth(32, 32, 20, 168))
        assertEquals(100, badgeArtworkWidth(500, 100, 20, 168))
    }
    @Test fun oversizedAndInvalidArtStayWithinTheRow() {
        assertEquals(168, badgeArtworkWidth(Int.MAX_VALUE, 1, 20, 168))
        assertEquals(20, badgeArtworkWidth(0, 0, 20, 168))
        assertEquals(8, badgeArtworkWidth(1, 100, 20, 8))
        assertEquals(0, badgeArtworkWidth(200, 40, 20, 0))
    }
}
