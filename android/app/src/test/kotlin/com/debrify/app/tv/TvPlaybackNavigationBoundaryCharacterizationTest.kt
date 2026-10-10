package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackNavigationBoundaryCharacterizationTest : TvPhase18OriginalTest() {
    private fun nextGuideWithoutResolver(imdb: String?) {
        payload(p2Item(season = 1, episode = 1), type = "series", imdb = imdb)
        model().guideEpisodes.addAll(listOf(guide(1, 1), guide(1, 2)))
        set("hasPlaylistResolver", false)
        val target = call("guideAdjacent", arrayOf(PlaybackPayload::class.java,
            PlaybackItem::class.java, intType, boolType), model(), item(), 1, false)
        assertEquals("the guide target exists independently of resolver availability",
            SeasonEpisode(1, 2), target)
        call("playNext", emptyArray())
        assertTrue("without a resolver, guide adjacency cannot request an in-player fetch",
            requests("requestEpisodeFetch").isEmpty())
        assertTrue(probe.media.isEmpty())
    }

    @Test fun guideNextWithoutResolverHandsBackToQuickPlayAndFinish() {
        nextGuideWithoutResolver("tt18")
        assertEquals(1, requests("requestQuickPlayNextEpisode").size)
        assertTrue(activity.isFinishing)
        assertTrue(field("finishProgressAttempted") as Boolean)
    }

    @Test fun guideNextWithoutResolverOrImdbShowsEndToast() {
        nextGuideWithoutResolver(null)
        assertTrue(requests("requestQuickPlayNextEpisode").isEmpty())
        assertEquals("End of playlist", lastToast())
        assertFalse(activity.isFinishing)
    }

    @Test fun explicitRandomClearsStaleAutoAdvanceAndSleepLatchBeforePlaying() {
        payload(p2Item(), p2Item("Picked").copy(index = 1, resumePositionMs = 500L))
        (field("shuffleBag") as MutableList<Int>).add(1)
        set("isAutoAdvancing", true)
        set("sleepStopLatched", true)
        call("playRandom", emptyArray())
        assertFalse("an explicit random pick clears the sleep stop latch",
            field("sleepStopLatched") as Boolean)
        assertFalse(field("isAutoAdvancing") as Boolean)
        assertEquals(1, field("currentIndex"))
        assertEquals(0L, field("pendingSeekMs"))
        assertEquals(1, probe.media.size)
        assertEquals("Picked", probe.media.single().mediaMetadata.title.toString())
    }

    @Test fun twoPriorFailuresStillAllowTheThirdShuffleAttempt() {
        payload(p2Item(season = 1, episode = 1),
            p2Item("Third attempt", season = 1, episode = 4).copy(index = 1))
        wholeShow(ShuffleEpisode(1, 4))
        val failed = setOf(ShuffleEpisode(1, 2), ShuffleEpisode(1, 3))
        assertTrue(shuffle(failed))
        assertEquals("two prior failures must still select the third target", 1,
            field("currentIndex"))
        assertEquals(1, probe.media.size)
        assertEquals("Third attempt", probe.media.single().mediaMetadata.title.toString())
        assertNotNull(field("pendingShufflePlayback"))
        assertTrue(requests("requestEpisodeFetch").isEmpty())
    }
}
