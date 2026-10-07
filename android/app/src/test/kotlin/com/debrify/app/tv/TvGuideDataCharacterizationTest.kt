package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class TvGuideDataCharacterizationTest : TvPhase2OriginalTest() {
    @Test fun nowPlayingTextKeepsLoadingYearAndPositiveRatingWithUsDecimal() {
        fun text(ch: StremioTvGuideChannel) = call("buildNowPlayingText", arrayOf(StremioTvGuideChannel::class.java), ch)
        assertEquals("Loading...", text(p2Guide()))
        assertEquals("Film", text(p2Guide().copy(nowPlayingTitle = "Film", nowPlayingYear = "", nowPlayingRating = 0.0)))
        assertEquals("Film", text(p2Guide().copy(nowPlayingTitle = "Film", nowPlayingRating = -1.0)))
        val locale = Locale.getDefault()
        try {
            Locale.setDefault(Locale.GERMANY)
            assertEquals("Film (2024) ★ 8.5", text(p2Guide().copy(nowPlayingTitle = "Film", nowPlayingYear = "2024", nowPlayingRating = 8.5)))
            assertEquals("", text(p2Guide().copy(nowPlayingTitle = "")))
        } finally { Locale.setDefault(locale) }
    }

    @Test fun guideDataUpdatesOnlyPresentSectionsAndClearsLoadingOnEveryAnswer() {
        fun update(ch: StremioTvGuideChannel, data: Map<*, *>) = call("updateStremioTvGuideChannelData", arrayOf(StremioTvGuideChannel::class.java, mapType), ch, data)
        val ch = p2Guide()
        update(ch, mapOf("nowPlaying" to mapOf("title" to "Now", "poster" to "p", "year" to "2024", "rating" to 8,
            "slotEndMs" to 90.5, "progress" to 0.25), "nextUp" to mapOf("title" to "Next", "poster" to "q", "year" to "2025", "rating" to 7.5)))
        assertEquals(p2Guide().copy(nowPlayingTitle = "Now", nowPlayingPoster = "p", nowPlayingYear = "2024",
            nowPlayingRating = 8.0, nowPlayingSlotEndMs = 90L, nowPlayingProgress = 0.25f,
            nextUpTitle = "Next", nextUpPoster = "q", nextUpYear = "2025", nextUpRating = 7.5, hasGuideData = true, isLoadingGuideData = false), ch)
        val previous = ch.copy(); ch.isLoadingGuideData = true
        update(ch, mapOf("nowPlaying" to 7, "nextUp" to "bad")); assertEquals(previous, ch)
        update(ch, mapOf("nextUp" to mapOf("title" to 5, "poster" to "", "year" to "", "rating" to "7")))
        assertEquals(previous.copy(nextUpTitle = null, nextUpPoster = null, nextUpYear = null, nextUpRating = null), ch)
        update(ch, mapOf("nowPlaying" to mapOf("title" to 4, "poster" to "", "year" to "", "rating" to "8", "slotEndMs" to "9", "progress" to "0.5")))
        assertEquals(p2Guide().copy(hasGuideData = true, isLoadingGuideData = false), ch)
        val empty = p2Guide(); update(empty, emptyMap<String, Any>())
        assertEquals(p2Guide().copy(isLoadingGuideData = false), empty)
    }
}
