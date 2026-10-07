package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackProgressPolicyTest {
    @Test fun watchedAndRewatchEdgesKeepTheOriginalDisplayPolicy() {
        val item = PlaybackItem.fromJson(JSONObject().put("durationMs", 1000L).put("resumePositionMs", 200L))
        assertEquals(20, item.displayProgressPercent())
        assertEquals(40, item.copy(traktProgressPercent = 40.9).displayProgressPercent())
        assertEquals(20, item.copy(traktProgressPercent = 95.0).displayProgressPercent())
        assertEquals(0, item.copy(resumePositionMs = 1L, durationMs = 100_000L, traktProgressPercent = 100.0).displayProgressPercent())
        assertEquals(100, item.copy(resumePositionMs = 0L, traktProgressPercent = 100.0).displayProgressPercent())
        assertEquals(100, item.copy(watched = true).displayProgressPercent())
        assertEquals(0, item.copy(durationMs = 0L).displayProgressPercent())
        // Characterization: this function deliberately has no percent clamp.
        assertEquals(150, item.copy(resumePositionMs = 1500L).displayProgressPercent())
    }

    @Test fun excludedLocalProgressDoesNotOverrideTracker() {
        val item = PlaybackItem.fromJson(JSONObject()
            .put("resumePositionMs", 400L).put("durationMs", 1000L)
            .put("traktProgressPercent", 20.0)
            .put("allowLocalProgressDisplay", false))
        assertEquals(20, item.displayProgressPercent())
        assertEquals(100, item.copy(traktProgressPercent = 100.0).displayProgressPercent())
        assertEquals(0, item.copy(traktProgressPercent = null).displayProgressPercent())
        assertEquals(400L, item.resumePositionMs)
        assertEquals(40, item.copy(allowLocalProgressDisplay = true).displayProgressPercent())
    }
}
