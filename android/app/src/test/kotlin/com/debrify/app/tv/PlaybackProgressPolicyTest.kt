package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackProgressPolicyTest {
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
