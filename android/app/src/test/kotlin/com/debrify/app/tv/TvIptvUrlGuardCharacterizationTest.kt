package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TvIptvUrlGuardCharacterizationTest : TvPhase2OriginalTest() {
    @Test fun twinRejectsQuestionMarksAnywhereBeforeRemovingTheFragment() {
        for (url in listOf(
            "http://h/live/u/p/1.m3u8#x?y",
            "http://h/live/u/p/1.m3u8#?",
            "http://h/live/u?x/p/1.m3u8",
            "http://h/live/u/p?x/1.m3u8",
            "http://h?x/live/u/p/1.m3u8",
            "http://h/live/u/p/1?x.m3u8",
            "http://h/live/u/p/1.m3u8?x#y",
        )) assertNull(url, call("xtreamTsTwin", arrayOf(stringType), url))
    }

    @Test fun twinPreservesAmpersandsAndEscapesAndUsesOnlyTheFirstFragment() {
        for (path in listOf("h/live/u&x/p/1", "h/live/u/p&x/1", "h/live/u/p/1&x",
            "h&x/live/u/p/1", "h/live/u%3Fx/p%23x/1%26x")) {
            assertEquals(path, "http://$path.ts", call("xtreamTsTwin", arrayOf(stringType), "http://$path.m3u8"))
        }
        assertEquals("http://h/live/u/p/1.ts", call("xtreamTsTwin", arrayOf(stringType), "http://h/live/u/p/1.m3u8#first#last"))
        for (url in listOf("http://h/live/u#x/p/1.m3u8", "http://h/live/u/p#x/1.m3u8",
            "http://h/live/u/p/1#x.m3u8", "http://h/live/u/p/1.ts#x.m3u8")) {
            assertNull(url, call("xtreamTsTwin", arrayOf(stringType), url))
        }
    }

    @Test fun segmentedPathsStopAtTheFirstQuestionMarkEvenWithLaterSuffixes() {
        for ((url, expected) in listOf(
            "http://h/a.M3U8?first.ts?last" to true,
            "http://h/a.ts?first.mpd?last" to false,
            "http://h/a.mpd?first.ts#later.m3u8" to true,
            "http://h/a.ts?first.mpd#later.m3u8" to false,
            "http://h/a%3F.m3u8?last" to true,
            "http://h/a.m3u8%3Ftoken" to false,
        )) assertEquals(url, expected, call("isSegmentedStreamUrl", arrayOf(stringType), url))
    }

    @Test fun segmentedPathsStopAtTheFirstFragmentEvenWhenItContainsAQuestion() {
        for ((url, expected) in listOf(
            "http://h/a.M3U8#first.ts#last" to true,
            "http://h/a.ts#first.m3u8#last" to false,
            "http://h/a.M3U8#first.ts?last.mpd" to true,
            "http://h/a.ts#first.m3u8?last.mpd" to false,
            "http://h/a%23.mpd#last" to true,
            "http://h/a.mpd%23tail" to false,
        )) assertEquals(url, expected, call("isSegmentedStreamUrl", arrayOf(stringType), url))
    }
}
