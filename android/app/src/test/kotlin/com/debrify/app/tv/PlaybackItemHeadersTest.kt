package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackItemHeadersTest {
    @Test fun allLaunchFieldsMapWithoutLosingOptionalValues() {
        val values = linkedMapOf<String, Any?>(
            "id" to "id", "title" to "Release", "url" to "https://example.test/file", "index" to 4,
            "season" to 2, "episode" to 10, "artwork" to "poster", "description" to "description",
            "resumePositionMs" to 123L, "durationMs" to 456L, "updatedAt" to 789L, "resumeId" to "resume",
            "sizeBytes" to 1000L, "rating" to 8.5, "provider" to "torbox", "traktProgressPercent" to 21.0,
            "watched" to true, "allowLocalProgressDisplay" to false, "sourceTitle" to "Original release",
            "hdVideoUrl" to "video", "audioUrl" to "audio", "httpHeaders" to mapOf("Referer" to "ref"),
        )
        val item = PlaybackItem.fromMap(values)
        assertEquals(PlaybackItem.fromJson(JSONObject(values)), item)
        assertEquals("id", item.id)
        assertEquals("Release", item.title)
        assertEquals("https://example.test/file", item.url)
        assertEquals(4, item.index)
        assertEquals("S02E10", item.seasonEpisodeLabel())
        assertEquals("poster", item.artwork)
        assertEquals("description", item.description)
        assertEquals(123L, item.resumePositionMs)
        assertEquals(456L, item.durationMs)
        assertEquals(789L, item.updatedAt)
        assertEquals("resume", item.resumeId)
        assertEquals(1000L, item.sizeBytes)
        assertEquals(8.5, item.rating)
        assertEquals("torbox", item.provider)
        assertEquals(21.0, item.traktProgressPercent)
        assertTrue(item.watched)
        assertEquals(false, item.allowLocalProgressDisplay)
        assertEquals("Original release", item.sourceTitle)
        assertEquals("video", item.hdVideoUrl)
        assertEquals("audio", item.audioUrl)
        assertEquals(mapOf("Referer" to "ref"), item.httpHeaders)
    }

    @Test fun absentAndEmptyLaunchKeysKeepOriginalDefaults() {
        val empty = PlaybackItem.fromMap(emptyMap<String, Any>())
        assertEquals("", empty.seasonEpisodeLabel())
        assertEquals("", empty.id)
        assertEquals(0, empty.index)
        assertEquals(0L, empty.durationMs)
        assertNull(empty.season)
        assertNull(empty.episode)
        assertNull(empty.artwork)
        assertNull(empty.rating)
        assertNull(empty.sourceTitle)
        assertNull(empty.hdVideoUrl)
        assertNull(empty.audioUrl)
        assertTrue(empty.allowLocalProgressDisplay)
        val titled = PlaybackItem.fromMap(mapOf("title" to "fallback", "hdVideoUrl" to "", "audioUrl" to ""))
        assertEquals("fallback", titled.sourceTitle)
        assertNull(titled.hdVideoUrl)
        assertNull(titled.audioUrl)
        assertEquals("", titled.copy(season = 2).seasonEpisodeLabel())
    }

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
