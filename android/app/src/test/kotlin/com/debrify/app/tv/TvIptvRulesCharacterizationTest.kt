package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TvIptvRulesCharacterizationTest : TvPhase2OriginalTest() {
    @Test fun segmentedUrlsMatchOnlyKnownPathSuffixesBeforeQueryAndFragment() {
        for (suffix in listOf(".m3u8", ".m3u", ".mpd", ".ism", ".isml", "/manifest")) {
            assertEquals(suffix, true, call("isSegmentedStreamUrl", arrayOf(stringType), "https://host/A${suffix.uppercase()}?token=x#end"))
            assertEquals(suffix, true, call("isSegmentedStreamUrl", arrayOf(stringType), "https://host/a$suffix#end"))
        }
        for (url in listOf("", "https://host/a.ts", "https://host/a.m3u8/extra", "https://host/a?file=.m3u8", "https://host/a#file.mpd")) {
            assertEquals(url, false, call("isSegmentedStreamUrl", arrayOf(stringType), url))
        }
    }

    @Test fun xtreamTwinKeepsHostCredentialsIdAndRejectsTokenOrLoosePaths() {
        assertEquals("https://Host:81/live/user/pass/123.ts", call("xtreamTsTwin", arrayOf(stringType), "https://Host:81/live/user/pass/123.m3u8#end"))
        assertEquals("HTTP://host/live/u/p/id.ts", call("xtreamTsTwin", arrayOf(stringType), "HTTP://host/LIVE/u/p/id.M3U8"))
        for (url in listOf("https://h/live/u/p/id.m3u8?", "https://h/live/u/p/id.m3u8?token=x", "ftp://h/live/u/p/id.m3u8",
            "https://h/live/u/p/id.extra.m3u8", "https://h/vod/u/p/id.m3u8", "https://h/live/u/p/a/id.m3u8",
            "https://h/live//p/id.m3u8", "https://h/live/u//id.m3u8", "https://h/live/u/p/.m3u8", "https://h/live/u/p/id.m3u8/", "")) {
            assertNull(url, call("xtreamTsTwin", arrayOf(stringType), url))
        }
    }

    @Test fun recordingNamesStripUnsafeCharactersCollapseSpacesAndBoundLength() {
        assertEquals("A_B-_123", call("sanitizeRecordingName", arrayOf(stringType), "  A  B-_/é:123!?  "))
        assertEquals("recording", call("sanitizeRecordingName", arrayOf(stringType), "é:/!?"))
        assertEquals("recording", call("sanitizeRecordingName", arrayOf(stringType), ""))
        assertEquals("a".repeat(60), call("sanitizeRecordingName", arrayOf(stringType), "a".repeat(61)))
        assertEquals("a".repeat(59), call("sanitizeRecordingName", arrayOf(stringType), "a".repeat(59)))
    }

    @Test fun recordingTimestampUsesLocalZoneAndUsDigitsToSecondPrecision() {
        val zone = TimeZone.getDefault(); val locale = Locale.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("GMT+05:30")); Locale.setDefault(Locale.forLanguageTag("ar"))
            val before = System.currentTimeMillis()
            val timestamp = call("recordingTimestamp", emptyArray()) as String
            val after = System.currentTimeMillis()
            assertTrue(timestamp.matches(Regex("[0-9]{8}_[0-9]{6}")))
            val parsed = java.text.SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).parse(timestamp)!!.time
            assertTrue("timestamp must describe this invocation in the default zone", parsed in (before - 999)..after)
        } finally { TimeZone.setDefault(zone); Locale.setDefault(locale) }
    }

    @Test fun seriesSentinelRecognizesEitherExactTypeOrCaseSensitiveScheme() {
        for ((entry, expected) in listOf(p2Channel().copy(contentType = "series") to true,
            p2Channel().copy(url = "xtream-series://id") to true, p2Channel().copy(contentType = "Series") to false,
            p2Channel().copy(url = "XTREAM-SERIES://id") to false, p2Channel() to false)) {
            assertEquals(expected, call("isIptvSeriesSentinel", arrayOf(IptvChannelEntry::class.java), entry))
        }
    }

    @Test fun stremioUrlRequiresExactPrefixAtTheBeginning() {
        for ((url, expected) in listOf("stremio-tv://id" to true, "stremio-tv://" to true,
            "STREMIO-TV://id" to false, "xstremio-tv://id" to false, "" to false)) {
            assertEquals(expected, call("isStremioIptvUrl", arrayOf(stringType), url))
        }
    }

    @Test fun qualityUsesFirstCaseInsensitiveRecognizedTokenAndLiveFallback() {
        for ((label, expected) in listOf("a2160P b" to "4K", "4k" to "4K", "1080P then 4K" to "1080p",
            "720P" to "720p", "480p" to "480p", "HDR" to "LIVE", "" to "LIVE")) {
            assertEquals(expected, call("iptvQualityFromLabel", arrayOf(stringType), label))
        }
    }

    @Test fun startOverRequiresLiveArchiveAndCurrentWindowWithinRetention() {
        val now = System.currentTimeMillis()
        val valid = p2Channel(archive = "1", days = 1).apply { epgNowTitle = "Show"; epgNowStartMs = now - 10_000; epgNowStopMs = now + 10_000 }
        fun result(entry: IptvChannelEntry) = call("currentIptvStartOverProgramme", arrayOf(IptvChannelEntry::class.java), entry)
        assertEquals(IptvEpgProgram("Show", null, valid.epgNowStartMs, valid.epgNowStopMs, true), result(valid))
        assertEquals("Cinema", (result(valid.copy(epgNowTitle = null)) as IptvEpgProgram).title)
        assertNotNull(result(valid.copy(tvArchive = null, epgNowHasArchive = true)))
        assertNotNull(result(valid.copy(tvArchiveDuration = 0, epgNowStartMs = now - 2 * 86_400_000L)))
        assertNotNull(result(valid.copy(tvArchiveDuration = null)))
        assertNotNull(result(valid.copy(epgNowStartMs = now - 86_400_000L + 1000)))
        for (invalid in listOf(valid.copy(isLive = false), valid.copy(tvArchive = "0", epgNowHasArchive = true),
            valid.copy(tvArchive = null, epgNowHasArchive = false), valid.copy(tvArchive = "2"),
            valid.copy(epgNowStartMs = 0), valid.copy(epgNowStartMs = now + 1000), valid.copy(epgNowStopMs = now),
            valid.copy(epgNowStartMs = now - 86_400_000L - 1000))) assertNull(result(invalid))
    }

    @Test fun remainingTimeFloorsMinutesAndFormatsHourRemainders() {
        for ((ms, expected) in listOf(-60_000L to "0 min", 0L to "0 min", 59_999L to "0 min", 60_000L to "1 min",
            3_599_999L to "59 min", 3_600_000L to "1 hr", 4_320_000L to "1 hr 12 min", 7_200_000L to "2 hr")) {
            assertEquals(expected, call("formatIptvRemaining", arrayOf(longType), ms))
        }
    }

    @Test fun epgAdoptionCopiesRealDataWithoutOverwritingLoadedOrInFlightOwnership() {
        val from = p2Channel().apply {
            epgNowTitle = "Now"; epgNowStartMs = 10; epgNowStopMs = 20; epgNowHasArchive = true
            epgCatchupMetadataLoaded = true; epgNextTitle = "Next"; epgNextStartMs = 30
        }
        fun adopt(f: IptvChannelEntry, t: IptvChannelEntry) = call("adoptIptvEpg", arrayOf(IptvChannelEntry::class.java, IptvChannelEntry::class.java), f, t)
        val to = p2Channel(); adopt(from, to)
        assertEquals(from.copy(epgLoaded = true), to)
        val loading = p2Channel().apply { epgLoading = true }; adopt(from, loading)
        assertEquals(from.copy(epgLoading = true), loading)
        val loaded = p2Channel().apply { epgLoaded = true; epgNowTitle = "Fresh" }; val snapshot = loaded.copy()
        adopt(from, loaded); assertEquals(snapshot, loaded)
        val empty = p2Channel(); adopt(p2Channel(), empty); assertEquals(p2Channel(), empty)
    }
}
