package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackItemHeadersTest {
    @Test fun methodChannelReplacementPreservesNativeMapHeaders() {
        val map = linkedMapOf<String, Any?>(
            "url" to "https://cdn.test/episode2", "season" to 1, "episode" to 2,
            "httpHeaders" to linkedMapOf("Authorization" to "episode-2",
                "Cookie" to "session=2", "uSeR-aGeNt" to "AddonPlayer/1.0"),
        )
        val item = PlaybackItem.fromMap(map)
        assertEquals("episode-2", item.httpHeaders["Authorization"])
        assertEquals("session=2", item.httpHeaders["Cookie"])
        assertEquals("AddonPlayer/1.0", item.httpHeaders["User-Agent"])
        assertEquals(2, item.episode)
        assertEquals(PlaybackItem.fromJson(JSONObject(map)).httpHeaders, item.httpHeaders)
        assertTrue(PlaybackItem.fromMap(map + ("httpHeaders" to emptyMap<String, String>())).httpHeaders.isEmpty())
        assertTrue(PlaybackItem.fromMap(map - "httpHeaders").httpHeaders.isEmpty())
    }

    @Test fun replacementWithoutHeadersDoesNotInheritLaunchCredentials() {
        val original = PlaybackItem.fromJson(JSONObject()
            .put("url", "https://original.test/video")
            .put("httpHeaders", JSONObject().put("Authorization", "Bearer original")))
        val replacement = PlaybackItem.fromJson(JSONObject().put("url", "https://other.test/video"))
        assertEquals("Bearer original", original.httpHeaders["Authorization"])
        assertTrue(replacement.httpHeaders.isEmpty())
    }

    @Test fun eachEpisodeRetainsItsHeadersAcrossMetadataAndUrlUpdates() {
        val first = PlaybackItem.fromJson(JSONObject()
            .put("httpHeaders", JSONObject().put("Authorization", "episode-1")))
        val second = PlaybackItem.fromJson(JSONObject()
            .put("httpHeaders", JSONObject().put("Authorization", "episode-2")))
        assertEquals("episode-1", first.httpHeaders["Authorization"])
        assertEquals("episode-2", second.copy(title = "New title", url = "https://cdn.test/resolved").httpHeaders["Authorization"])
        assertTrue(PlaybackItem.fromJson(JSONObject().put("httpHeaders", JSONObject())).httpHeaders.isEmpty())
    }
}
