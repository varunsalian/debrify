package com.debrify.app.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvModelDefaultsCharacterizationTest {
    @Test fun everyAbsentSourceKeyKeepsItsJsonAndMapDefault() {
        val expected = linkedMapOf<String, Any?>(
            "index" to 3, "name" to "", "infohash" to "", "directUrl" to null,
            "httpHeaders" to emptyMap<String, String>(), "streamType" to "torrent",
            "sizeBytes" to 0L, "seeders" to 0, "source" to null, "addonId" to null,
            "quality" to "HD", "coverageType" to null, "badgeDescription" to null,
            "videoId" to null, "addonPresentation" to null, "addonDisplayName" to null,
            "addonLogo" to null, "hasRealInfoHash" to true, "addonKey" to null,
        )
        for ((path, input) in listOf("JSON" to JSONObject(), "map" to emptyMap<String, Any>())) {
            val source = Original.source(input)
            expected.forEach { (key, value) -> assertEquals("$path.$key", value, Original.get(source, key)) }
        }
    }

    @Test fun everyAbsentPlaybackKeyKeepsItsJsonAndMapDefault() {
        val expected = PlaybackItem(
            id = "", title = "", url = "", httpHeaders = emptyMap(), mimeType = null,
            hdVideoUrl = null, audioUrl = null, index = 0, season = null, episode = null,
            artwork = null, description = null, resumePositionMs = 0, durationMs = 0,
            updatedAt = 0, resumeId = null, sizeBytes = null, rating = null, provider = null,
            traktProgressPercent = null, watched = false, allowLocalProgressDisplay = true, sourceTitle = null,
        )
        assertEquals(expected, PlaybackItem.fromJson(JSONObject()))
        assertEquals(expected, PlaybackItem.fromMap(emptyMap<String, Any>()))
        // Present but empty optional values use their existing optX defaults.
        val empty = mapOf<String, Any?>(
            "season" to "", "episode" to "", "artwork" to "", "description" to "",
            "resumeId" to "", "sizeBytes" to "", "rating" to "", "provider" to "",
            "traktProgressPercent" to "", "hdVideoUrl" to "", "audioUrl" to "",
        )
        for (item in listOf(PlaybackItem.fromMap(empty), PlaybackItem.fromJson(JSONObject(empty)))) {
            assertEquals(0, item.season)
            assertEquals(0, item.episode)
            assertEquals("", item.artwork)
            assertEquals("", item.description)
            assertEquals("", item.resumeId)
            assertEquals(0L, item.sizeBytes)
            assertTrue(item.rating!!.isNaN())
            assertEquals("", item.provider)
            assertTrue(item.traktProgressPercent!!.isNaN())
            assertNull(item.hdVideoUrl)
            assertNull(item.audioUrl)
        }
    }

    @Test fun rewatchBoundariesDistinguishNinetyNinetyFourAndNinetyFive() {
        val item = PlaybackItem.fromJson(JSONObject().put("durationMs", 1000L))
        assertEquals(100, item.copy(durationMs = 1, resumePositionMs = 1).displayProgressPercent())
        assertEquals(0, item.copy(resumePositionMs = 1, traktProgressPercent = 100.0).displayProgressPercent())
        for (local in listOf(0, 1, 5, 6, 89, 90, 94, 95, 96, 100)) {
            for (tracker in listOf(0, 94, 95, 100)) {
                val current = item.copy(resumePositionMs = local * 10L, traktProgressPercent = tracker.toDouble())
                val expected = if (tracker >= 95 && local > 0 && local < 95) local else maxOf(local, tracker)
                assertEquals("local=$local tracker=$tracker", expected, current.displayProgressPercent())
                assertEquals(tracker, current.copy(allowLocalProgressDisplay = false).displayProgressPercent())
                assertEquals(100, current.copy(watched = true).displayProgressPercent())
            }
        }
    }

    @Test fun sourceDisplayTitleAndSizeBoundaryLiteralsRemainObservable() {
        for ((bytes, expected) in listOf(0L to null, -1L to null, 1L to "0 MB",
            1_073_741_823L to "1024 MB", 1_073_741_824L to "1.0 GB")) {
            assertEquals(expected, Original.get(Original.source(mapOf("size_bytes" to bytes)), "formattedSize"))
        }
        val short = "a".repeat(19)
        val boundary = "a".repeat(20)
        assertEquals("Long movie filename 1080p", Original.get(Original.source(mapOf("name" to "$short\nLong movie filename 1080p")), "displayTitle"))
        assertEquals(boundary, Original.get(Original.source(mapOf("name" to "$boundary\nLong movie filename 1080p")), "displayTitle"))
        assertEquals("\nMovie", Original.get(Original.source(mapOf("name" to "\nMovie")), "displayTitle"))
        assertEquals("Movie", Original.get(Original.source(mapOf("name" to "A\nMovie")), "displayTitle"))
    }

    @Test fun payloadConstructorDefaultsKeepCompletionThresholdsAndIndependentGuideLists() {
        val first = Original.defaultPayload()
        val second = Original.defaultPayload()
        assertEquals(80, Original.get(first, "movieCompletionThreshold"))
        assertEquals(80, Original.get(first, "episodeCompletionThreshold"))
        assertEquals(0.0, Original.get(first, "startAtPercent"))
        assertEquals(0.0, Original.get(first, "traktProgressPercent"))
        assertEquals(false, Original.get(first, "localCompletionTracking"))
        assertEquals(emptyMap<Int, Int>(), Original.get(first, "nextEpisodeMap"))
        assertEquals(emptyMap<Int, Int>(), Original.get(first, "prevEpisodeMap"))
        assertEquals(emptyMap<String, String>(), Original.get(first, "httpHeaders"))
        assertNull(Original.get(first, "collectionGroups"))
        assertNull(Original.get(first, "imdbId"))
        assertNotSame(Original.get(first, "guideEpisodes"), Original.get(second, "guideEpisodes"))
        assertNotSame(Original.get(first, "perItemImdbIds"), Original.get(second, "perItemImdbIds"))
    }

    @Test fun lateMetadataPositiveDurationAndNegativeLivePositionBoundsStayExact() {
        assertEquals(1L, mergeLateMetadataDuration(60_000L, 30_000L, 1L, true))
        assertEquals(30_000L, mergeLateMetadataDuration(60_000L, 30_000L, 0L, true))
        assertEquals(0L, mergeLateMetadataResumePosition(-10L, -5L, -1L, true))
        assertEquals(-5L, mergeLateMetadataResumePosition(-10L, -5L, -1L, false))
    }
}
