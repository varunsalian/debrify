package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlayerModelCharacterizationTest {
    @Test fun sourceJsonAndMapKeepFieldsQualityAndFailureIdentity() {
        val values = mapOf<String, Any>(
            "name" to "Addon\nMovie.2160p.mkv", "infohash" to "a".repeat(40),
            "direct_url" to "https://example.test/file", "http_headers" to mapOf("user-agent" to "Agent"),
            "stream_type" to "directUrl", "size_bytes" to 1_073_741_824L, "seeders" to 8,
            "source" to "Addon", "stremio_addon_id" to "id", "stremio_addon_key" to "key",
            "coverage_type" to "seasonPack", "stremio_video_id" to "tt123:1:2", "has_real_infohash" to false,
            "addon_display_name" to "Display", "addon_logo" to "logo",
        )
        for (source in listOf(Original.source(JSONObject(values)), Original.source(values))) {
            assertEquals(3, Original.get(source, "index"))
            assertEquals("4K", Original.get(source, "quality"))
            assertEquals("Movie.2160p.mkv", Original.get(source, "displayTitle"))
            assertEquals("1.0 GB", Original.get(source, "formattedSize"))
            assertEquals(mapOf("User-Agent" to "Agent"), Original.get(source, "httpHeaders"))
            assertEquals("https://example.test/file", Original.get(source, "directUrl"))
            assertEquals(8, Original.get(source, "seeders"))
            assertEquals("id", Original.get(source, "addonId"))
            assertEquals("Display", Original.get(source, "addonDisplayName"))
            assertEquals("logo", Original.get(source, "addonLogo"))
            assertEquals(true, Original.get(source, "isDirectStream"))
            assertEquals(true, Original.get(source, "isSeasonPack"))
            assertEquals(listOf("key", "tt123:1:2", null, "addon\nmovie.2160p.mkv", 1_073_741_824L,
                "https://example.test/file", "directUrl"), Original.call(source, "failureKey", ""))
        }
        val real = Original.source(values + ("has_real_infohash" to true))
        assertEquals(listOf("key", "tt123:1:2", "a".repeat(40), "addon\nmovie.2160p.mkv", 1_073_741_824L, null, null),
            Original.call(real, "failureKey", "DECODING_FAILED"))
    }

    @Test fun sourceAbsentKeysAndDisplayFallbacksRemainDistinct() {
        for (source in listOf(Original.source(JSONObject()), Original.source(emptyMap<String, Any>()))) {
            assertEquals("", Original.get(source, "name"))
            assertEquals("HD", Original.get(source, "quality"))
            assertEquals("torrent", Original.get(source, "streamType"))
            assertEquals(0L, Original.get(source, "sizeBytes"))
            assertEquals(true, Original.get(source, "hasRealInfoHash"))
            assertEquals(false, Original.get(source, "isDirectStream"))
            assertEquals(false, Original.get(source, "isSeasonPack"))
            assertNull(Original.get(source, "directUrl"))
            assertNull(Original.get(source, "formattedSize"))
            assertNull(Original.get(source, "addonKey"))
        }
        assertEquals("Title", Original.get(Original.source(mapOf("name" to "Title\nshort")), "displayTitle"))
        assertEquals("Movie 1080p", Original.get(Original.source(mapOf("name" to "Movie 1080p")), "displayTitle"))
        assertEquals("1080p", Original.get(Original.source(mapOf("name" to "Movie 1080p")), "quality"))
        assertEquals("1 MB", Original.get(Original.source(mapOf("size_bytes" to 1_048_576)), "formattedSize"))
        for (coverage in listOf("seasonPack", "multiSeasonPack", "completeSeries", "singleEpisode")) {
            assertEquals(coverage != "singleEpisode", Original.get(Original.source(mapOf("coverage_type" to coverage)), "isSeasonPack"))
        }
        // Existing JSON path normalizes an empty id; the map path preserves it.
        assertNull(Original.get(Original.source(JSONObject().put("stremio_video_id", "")), "videoId"))
        assertEquals("", Original.get(Original.source(mapOf("stremio_video_id" to "")), "videoId"))
    }

    @Test fun payloadParsingKeepsOrderNavigationHeadersAndClampedThresholds() {
        val activity = Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java).get()
        val payload = Original.call(activity, "parsePayload", """{
            "title":"Show","subtitle":"Sub","contentType":"series","seriesTitle":"Series","imdbId":"tt123",
            "startIndex":99,"items":[{"title":"Ten","episode":10},{"title":"Two","episode":2,"httpHeaders":{}}],
            "httpHeaders":{"Authorization":"launch"},"nextEpisodeMap":{"0":1},"prevEpisodeMap":{"1":0},
            "collectionGroups":[{"name":"MAIN"}],"startAtPercent":0.4,"traktProgressPercent":30.5,
            "localCompletionTracking":true,"movieCompletionThreshold":10,"episodeCompletionThreshold":200
        }""")!!
        assertEquals("Show", Original.get(payload, "title"))
        assertEquals("Sub", Original.get(payload, "subtitle"))
        assertEquals("series", Original.get(payload, "contentType"))
        assertEquals("Series", Original.get(payload, "seriesTitle"))
        assertEquals("tt123", Original.get(payload, "imdbId"))
        assertEquals(1, Original.get(payload, "startIndex"))
        val items = Original.get(payload, "items") as List<*>
        assertEquals(listOf("Ten", "Two"), items.map { (it as PlaybackItem).title })
        assertEquals(mapOf("Authorization" to "launch"), (items[0] as PlaybackItem).httpHeaders)
        assertTrue((items[1] as PlaybackItem).httpHeaders.isEmpty())
        assertEquals(mapOf(0 to 1), Original.get(payload, "nextEpisodeMap"))
        assertEquals(mapOf(1 to 0), Original.get(payload, "prevEpisodeMap"))
        assertEquals(1, (Original.get(payload, "collectionGroups") as List<*>).size)
        assertEquals(0.4, Original.get(payload, "startAtPercent"))
        assertEquals(30.5, Original.get(payload, "traktProgressPercent"))
        assertEquals(true, Original.get(payload, "localCompletionTracking"))
        assertEquals(50, Original.get(payload, "movieCompletionThreshold"))
        assertEquals(100, Original.get(payload, "episodeCompletionThreshold"))
        val defaults = Original.call(activity, "parsePayload", "{}")!!
        assertEquals(0, Original.get(defaults, "startIndex"))
        assertEquals("single", Original.get(defaults, "contentType"))
        assertNull(Original.get(defaults, "collectionGroups"))
        assertEquals(80, Original.get(defaults, "movieCompletionThreshold"))
        assertTrue((Original.get(defaults, "guideEpisodes") as List<*>).isEmpty())
        assertNull(Original.call(activity, "parsePayload", "invalid json"))
    }

    @Test fun groupLookupAndSubtitleCatalogFormattingKeepOriginalOrder() {
        val groups = Original.groups("MAIN" to listOf(2, 0), "EXTRAS" to listOf(1, 2))
        val first = Original.call(groups, "getGroup", 0)!!
        assertEquals("MAIN", Original.get(first, "name"))
        assertEquals(listOf(2, 0), Original.get(first, "fileIndices"))
        assertSame(first, Original.call(groups, "findGroupContaining", 2))
        assertEquals(1, Original.call(groups, "getGroupIndex", 1))
        assertEquals(-1, Original.call(groups, "getGroupIndex", 99))
        assertNull(Original.call(groups, "getGroup", 99))
        val catalog = Original.construct("SubtitleCatalogResult", "tt123", "series", "Show", "2024", "Addon")
        assertEquals("Show (2024)", Original.call(catalog, "titleLine"))
        assertEquals("Series · Addon · tt123", Original.call(catalog, "detailLine"))
        val plain = Original.construct("SubtitleCatalogResult", "tt456", "movie", "Film", null, "")
        assertEquals("Film", Original.call(plain, "titleLine"))
        assertEquals("Movie · tt456", Original.call(plain, "detailLine"))
    }
}
