package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test

class TvSourceBadgeResultTest {
    @Test fun configuredSourceWithoutMatchesStillReplacesQuality() {
        val reply = TvSourceBadgeResult.parse(mapOf("configured" to true, "badges" to emptyList<Any>()))!!
        assertTrue(reply.configured)
        assertEquals(emptyList<Any>(), reply.badges)
    }
    @Test fun deferredMatchingKeepsConfigurationButRemainsRetryable() {
        val reply = TvSourceBadgeResult.parse(mapOf("configured" to true, "badges" to null))!!
        assertTrue(reply.configured)
        assertNull(reply.badges)
    }
    @Test fun disabledConfigurationAndInvalidRepliesStayDistinct() {
        assertFalse(TvSourceBadgeResult.parse(mapOf("configured" to false, "badges" to emptyList<Any>()))!!.configured)
        assertNull(TvSourceBadgeResult.parse(null))
        assertNull(TvSourceBadgeResult.parse(mapOf("badges" to emptyList<Any>())))
        assertNull(TvSourceBadgeResult.parse(mapOf("configured" to true, "badges" to listOf("invalid"))))
    }
}
