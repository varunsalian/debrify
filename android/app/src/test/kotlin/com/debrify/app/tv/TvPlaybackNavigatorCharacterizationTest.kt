package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackNavigatorCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun nextPlaylistIndexWinsAndSuppressesSavedResume() {
        payload(p2Item(), p2Item("Next").copy(index = 1, resumePositionMs = 400L, traktProgressPercent = 30.0))
        call("playNext", emptyArray()); assertEquals(1, field("currentIndex")); assertEquals(0L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent")); assertEquals(1, probe.media.size)
    }

    @Test fun continuousShuffleBagWinsOverNextIndex() {
        payload(p2Item(),p2Item("Next").copy(index=1),p2Item("Random").copy(index=2,resumePositionMs=321L,traktProgressPercent=55.0)); set("continuousShuffleEnabled", true)
        (field("shuffleBag") as MutableList<Int>).add(2); call("playNext", emptyArray()); assertEquals(2, field("currentIndex")); assertEquals(1, probe.media.size); assertEquals(0L,field("pendingSeekMs")); assertEquals(0.0,field("pendingItemTraktPercent"))
    }

    @Test fun wholeShowShuffleWinsOverPackShuffle() {
        payload(p2Item("Current",season=1,episode=1),p2Item("Pack",season=1,episode=2).copy(index=1))
        wholeShow(ShuffleEpisode(1,1), ShuffleEpisode(2,4)); set("continuousShuffleEnabled", true)
        call("playNext", emptyArray()); assertEquals(mapOf("season" to 2,"episode" to 4),request("requestEpisodeFetch").call.arguments); assertEquals(0,field("currentIndex")); assertTrue(probe.media.isEmpty())
    }

    @Test fun nextLiveChannelRequestsTvBeforeGuide() {
        payload(p2Item(season=1,episode=1),type="series",imdb="tt12"); set("isStremioTvMode",true)
        (field("stremioTvChannels") as MutableList<StremioTvGuideChannel>).add(p2Guide().apply { isCurrent=true })
        call("playNext",emptyArray()); assertEquals(1,requests("requestStremioTvNext").size); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertFalse(activity.isFinishing)
    }

    @Test fun guideNext() {
        payload(p2Item(season=1,episode=1),type="series",imdb="tt12"); set("hasPlaylistResolver",true)
        model().guideEpisodes.addAll(listOf(guide(1,1),guide(1,2))); call("playNext",emptyArray())
        assertEquals(mapOf("season" to 1,"episode" to 2),request("requestEpisodeFetch").call.arguments); assertTrue(probe.media.isEmpty()); assertFalse(activity.isFinishing)
    }

    @Test fun guidePrevious() {
        payload(p2Item(season=1,episode=2),type="series",imdb="tt12"); set("hasPlaylistResolver",true)
        model().guideEpisodes.addAll(listOf(guide(1,1),guide(1,2))); call("playPrevious",emptyArray())
        assertEquals(mapOf("season" to 1,"episode" to 1),request("requestEpisodeFetch").call.arguments); assertTrue(probe.media.isEmpty()); assertFalse(activity.isFinishing)
    }

    @Test fun adjacentNext() {
        payload(p2Item(season=2,episode=3),type="series",imdb="tt12"); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
        call("playNext",emptyArray()); val args=request("requestEpisodeFetch").call.arguments as Map<*,*>
        assertEquals(2,args["currentSeason"]); assertEquals(3,args["currentEpisode"]); assertEquals(1,args["direction"]); assertEquals("tt12",args["imdbId"]); assertFalse(activity.isFinishing)
    }

    @Test fun adjacentPrevious() {
        payload(p2Item(season=2,episode=3),type="series",imdb="tt12"); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
        call("playPrevious",emptyArray()); val args=request("requestEpisodeFetch").call.arguments as Map<*,*>
        assertEquals(2,args["currentSeason"]); assertEquals(3,args["currentEpisode"]); assertEquals(-1,args["direction"]); assertEquals("tt12",args["imdbId"]); assertFalse(activity.isFinishing)
    }

    @Test fun quickPlayHandsBackThroughActivityFinishOverride() {
        payload(p2Item(season=2,episode=3),type="series",imdb="tt12"); call("playNext",emptyArray())
        assertEquals(1,requests("requestQuickPlayNextEpisode").size); assertTrue(activity.isFinishing)
        assertTrue(field("finishProgressAttempted") as Boolean)
    }

    @Test fun nextEndMovie() {
        call("playNext",emptyArray()); assertEquals("End of playlist",lastToast()); assertFalse(activity.isFinishing); assertTrue(probe.media.isEmpty())
    }

    @Test fun nextEndNoImdb() {
        model().contentType="series"; model().items[0]=item().copy(season=1,episode=1)
        call("playNext",emptyArray()); assertEquals("End of playlist",lastToast()); assertFalse(activity.isFinishing); assertTrue(probe.media.isEmpty())
    }

    @Test fun nextEndNoSeason() {
        model().contentType="series"; model().imdbId="tt12"; model().items[0]=item().copy(season=null,episode=1)
        call("playNext",emptyArray()); assertEquals("End of playlist",lastToast()); assertFalse(activity.isFinishing); assertTrue(probe.media.isEmpty())
    }

    @Test fun nextEndNoEpisode() {
        model().contentType="series"; model().imdbId="tt12"; model().items[0]=item().copy(season=1,episode=null)
        call("playNext",emptyArray()); assertEquals("End of playlist",lastToast()); assertFalse(activity.isFinishing); assertTrue(probe.media.isEmpty())
    }

    @Test fun nextEndMissingItem() {
        set("currentIndex",2)
        call("playNext",emptyArray()); assertEquals("End of playlist",lastToast()); assertFalse(activity.isFinishing); assertTrue(probe.media.isEmpty())
    }

    @Test fun nextEndMissingPayload() {
        set("payload",null)
        call("playNext",emptyArray()); assertEquals("End of playlist",lastToast()); assertFalse(activity.isFinishing); assertTrue(probe.media.isEmpty())
    }

    @Test fun previousLoadedEpisodeStartsFresh() {
        payload(p2Item("Previous").copy(resumePositionMs=400L,traktProgressPercent=40.0),p2Item("Current").copy(index=1)); set("currentIndex",1)
        dockCall("playPrevious"); assertEquals(0,field("currentIndex")); assertEquals(0L,field("pendingSeekMs")); assertEquals(0.0,field("pendingItemTraktPercent")); assertEquals(1,probe.media.size)
    }

    @Test fun previousAtBeginningShowsExactToast() {
        dockCall("playPrevious"); assertEquals("Beginning of playlist",lastToast()); assertTrue(probe.media.isEmpty())
    }

    @Test fun previousMissingPayloadHasNoEffects() {
        set("payload",null); dockCall("playPrevious"); assertNull(lastToast()); assertTrue(probe.media.isEmpty())
    }

    @Test fun catalogMovie() {
        payload(p2Item(season=2,episode=2),p2Item().copy(index=1),type="movie")
         set("currentIndex",1); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.GONE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogLoadedPrevious() {
        payload(p2Item(season=1,episode=2),p2Item().copy(index=1),type="series")
         set("currentIndex",1); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",false); set("hasAdjacentEpisodeResolver",false)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.VISIBLE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogTv() {
        payload(p2Item(season=2,episode=2),p2Item().copy(index=1),type="series")
         set("currentIndex",1); set("isStremioTvMode",true); set("isIptvMode",false); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.GONE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogIptvUntouched() {
        payload(p2Item(season=2,episode=2),p2Item().copy(index=1),type="series")
         set("currentIndex",1); set("isStremioTvMode",false); set("isIptvMode",true); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.INVISIBLE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogFirst() {
        payload(p2Item(season=1,episode=1),p2Item().copy(index=1),type="series")
         set("currentIndex",0); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.GONE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogSeasonBoundary() {
        payload(p2Item(season=2,episode=1),p2Item().copy(index=1),type="series")
         set("currentIndex",0); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.VISIBLE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogEpisodeBoundary() {
        payload(p2Item(season=1,episode=2),p2Item().copy(index=1),type="series")
         set("currentIndex",0); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.VISIBLE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogNoResolver() {
        payload(p2Item(season=2,episode=2),p2Item().copy(index=1),type="series")
         set("currentIndex",0); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",false); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.GONE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogNoAdjacent() {
        payload(p2Item(season=2,episode=2),p2Item().copy(index=1),type="series")
         set("currentIndex",0); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",false)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.GONE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun catalogNullIdentity() {
        payload(p2Item(season=null,episode=null),p2Item().copy(index=1),type="series")
         set("currentIndex",0); set("isStremioTvMode",false); set("isIptvMode",false); set("hasPlaylistResolver",true); set("hasAdjacentEpisodeResolver",true)
         dockCall("updateCatalogEpisodeControls"); assertEquals(View.GONE,(field("iptvPrevButton") as View).visibility)
    }
}
