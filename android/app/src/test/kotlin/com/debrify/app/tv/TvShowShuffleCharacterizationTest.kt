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
internal class TvShowShuffleCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun canShuffleEnabled() {
        wholeShow(ShuffleEpisode(1,1));
        assertEquals(true,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun canShuffleNoResolver() {
        wholeShow(ShuffleEpisode(1,1)); set("hasPlaylistResolver",false)
        assertEquals(false,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun canShuffleIptv() {
        wholeShow(ShuffleEpisode(1,1)); set("isIptvMode",true)
        assertEquals(false,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun canShuffleTv() {
        wholeShow(ShuffleEpisode(1,1)); set("isStremioTvMode",true)
        assertEquals(false,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun canShuffleCaseInsensitive() {
        wholeShow(ShuffleEpisode(1,1)); model().contentType="SeRiEs"
        assertEquals(true,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun canShuffleMovie() {
        wholeShow(ShuffleEpisode(1,1)); model().contentType="movie"
        assertEquals(false,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun canShuffleNoGuide() {
        wholeShow(ShuffleEpisode(1,1)); model().guideEpisodes.clear()
        assertEquals(false,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun canShuffleCustomEmpty() {
        wholeShow(ShuffleEpisode(1,1)); model().guideEpisodes.clear(); set("customShuffleEpisodes",emptyList<ShuffleEpisode>())
        assertEquals(true,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun notWholeShowReturnsFalseWithoutEffects() {
        assertFalse(shuffle()); assertTrue(probe.media.isEmpty()); assertTrue(requests("requestEpisodeFetch").isEmpty())
    }

    @Test fun busyFetchDoesNotDuplicateAutomatic() {
        wholeShow(ShuffleEpisode(1,2)); set("episodeFetchInFlight",true);
        assertTrue(shuffle(automatic=true)); assertEquals(null,field("queuedShuffleGeneration")); assertEquals(null,field("queuedShuffleNavigation")); assertTrue(requests("requestEpisodeFetch").isEmpty())
    }

    @Test fun busyFetchDoesNotDuplicateAlreadyQueued() {
        wholeShow(ShuffleEpisode(1,2)); set("episodeFetchInFlight",true); set("queuedShuffleGeneration",0); set("queuedShuffleNavigation",123)
        assertTrue(shuffle(automatic=false)); assertEquals(0,field("queuedShuffleGeneration")); assertEquals(123,field("queuedShuffleNavigation")); assertTrue(requests("requestEpisodeFetch").isEmpty())
    }

    @Test fun manualBusyFetchQueuesAtExactFiftyMsThenStarts() {
        payload(p2Item(season=1,episode=1),p2Item("Target",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,1),ShuffleEpisode(1,2)); set("episodeFetchInFlight",true)
        assertTrue(shuffle()); assertEquals(0,field("queuedShuffleGeneration")); assertEquals(0,field("queuedShuffleNavigation")); pump(49); assertTrue(probe.media.isEmpty()); set("episodeFetchInFlight",false); pump(1)
        assertEquals(1,probe.media.size); assertEquals(1,field("currentIndex")); assertNull(field("queuedShuffleGeneration")); assertNull(field("queuedShuffleNavigation"))
    }

    @Test fun queuedBusyFetchPollsAgainBeforeStarting() {
        payload(p2Item(season=1,episode=1),p2Item("Target",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); set("episodeFetchInFlight",true); shuffle(); set("hasPlaylistResolver",false); pump(50)
        assertTrue(probe.media.isEmpty()); assertEquals(0,field("queuedShuffleGeneration")); set("hasPlaylistResolver",true); set("episodeFetchInFlight",false); pump(50); assertEquals(1,probe.media.size)
    }

    @Test fun queuedPollCancelsGeneration() {
        payload(p2Item(season=1,episode=1),p2Item("Target",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); set("episodeFetchInFlight",true); shuffle(); set("upNextVisible",true); set("showShuffleGeneration",1); set("episodeFetchInFlight",false); pump(50)
        assertTrue(field("upNextVisible") as Boolean); assertNull(field("queuedShuffleGeneration")); assertNull(field("queuedShuffleNavigation")); assertTrue(probe.media.isEmpty())
    }

    @Test fun queuedPollCancelsNavigation() {
        payload(p2Item(season=1,episode=1),p2Item("Target",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); set("episodeFetchInFlight",true); shuffle(); set("upNextVisible",true); set("mediaPreparationGeneration",1); set("episodeFetchInFlight",false); pump(50)
        assertTrue(field("upNextVisible") as Boolean); assertNull(field("queuedShuffleGeneration")); assertNull(field("queuedShuffleNavigation")); assertTrue(probe.media.isEmpty())
    }

    @Test fun queuedPollCancelsFinishing() {
        payload(p2Item(season=1,episode=1),p2Item("Target",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); set("episodeFetchInFlight",true); shuffle(); set("upNextVisible",true); finishing(true); set("episodeFetchInFlight",false); pump(50)
        assertTrue(field("upNextVisible") as Boolean); assertNull(field("queuedShuffleGeneration")); assertNull(field("queuedShuffleNavigation")); assertTrue(probe.media.isEmpty())
    }

    @Test fun queuedPollCancelsDestroyed() {
        payload(p2Item(season=1,episode=1),p2Item("Target",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); set("episodeFetchInFlight",true); shuffle(); set("upNextVisible",true); destroyed(true); set("episodeFetchInFlight",false); pump(50)
        assertTrue(field("upNextVisible") as Boolean); assertNull(field("queuedShuffleGeneration")); assertNull(field("queuedShuffleNavigation")); assertTrue(probe.media.isEmpty())
    }

    @Test fun threeAttemptCapShowsExactPill() {
        wholeShow(ShuffleEpisode(1,4)); assertTrue(shuffle(setOf(ShuffleEpisode(1,1),ShuffleEpisode(1,2),ShuffleEpisode(1,3))))
        assertEquals("No other playable episode found for shuffle",pill().text.toString()); assertTrue(requests("requestEpisodeFetch").isEmpty())
    }

    @Test fun guideExcludesZeroSeason() {
        wholeShow(ShuffleEpisode(1,1)); model().guideEpisodes.clear(); model().guideEpisodes.add(guide(0,2)); assertTrue(shuffle()); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertEquals("No other playable episode found for shuffle",pill().text.toString())
    }

    @Test fun guideExcludesZeroEpisode() {
        wholeShow(ShuffleEpisode(1,1)); model().guideEpisodes.clear(); model().guideEpisodes.add(guide(2,0)); assertTrue(shuffle()); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertEquals("No other playable episode found for shuffle",pill().text.toString())
    }

    @Test fun guideExcludesDisabled() {
        wholeShow(ShuffleEpisode(1,1)); model().guideEpisodes.clear(); model().guideEpisodes.add(guide(2,2,false)); assertTrue(shuffle()); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertEquals("No other playable episode found for shuffle",pill().text.toString())
    }

    @Test fun customEligibilityOverridesGuideAndExcludesCurrentAttempted() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(3,3)); set("customShuffleEpisodes",listOf(ShuffleEpisode(1,1),ShuffleEpisode(2,2),ShuffleEpisode(4,4)))
        shuffle(setOf(ShuffleEpisode(4,4))); assertEquals(mapOf("season" to 2,"episode" to 2),request("requestEpisodeFetch").call.arguments)
    }

    @Test fun inPackResolvedTargetUsesSuppressedResumeAndAttempt() {
        payload(p2Item(season=1,episode=1),p2Item("Target",season=1,episode=2).copy(index=1,resumePositionMs=600L,traktProgressPercent=55.0)); wholeShow(ShuffleEpisode(1,1),ShuffleEpisode(1,2))
        assertTrue(shuffle()); assertEquals(1,field("currentIndex")); assertEquals(0L,field("pendingSeekMs")); assertEquals(0.0,field("pendingItemTraktPercent")); assertEquals(true,attemptField(field("pendingShufflePlayback")!!,"mediaStarted")); assertTrue(requests("requestEpisodeFetch").isEmpty())
    }

    @Test fun blankTargetResolvesBeforeChangingIndexAndProvider() {
        payload(p2Item("Outgoing",season=1,episode=1),p2Item("Target",url=" ",season=1,episode=2,provider="Old").copy(index=1)); wholeShow(ShuffleEpisode(1,2))
        shuffle(); assertEquals(0,field("currentIndex")); assertTrue(probe.media.isEmpty()); assertEquals(1,(request("requestTorrentStream").call.arguments as Map<*,*>)["index"])
        replyDirect(mapOf("url" to "https://shuffle.invalid/resolved.mp4","provider" to "Fetched")); assertEquals(1,field("currentIndex")); assertEquals("Fetched",item(1).provider); assertEquals(1,probe.media.size)
    }

    @Test fun blankTargetLateReplyRejectedGeneration() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); set("showShuffleGeneration",1); replyDirect(mapOf("url" to "https://shuffle.invalid/late.mp4"))
        assertEquals(0,field("currentIndex")); assertEquals("",item(1).url); assertTrue(probe.media.isEmpty())
    }

    @Test fun blankTargetLateReplyRejectedNavigation() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); set("mediaPreparationGeneration",1); replyDirect(mapOf("url" to "https://shuffle.invalid/late.mp4"))
        assertEquals(0,field("currentIndex")); assertEquals("",item(1).url); assertTrue(probe.media.isEmpty())
    }

    @Test fun blankTargetLateReplyRejectedFinishing() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); finishing(true); replyDirect(mapOf("url" to "https://shuffle.invalid/late.mp4"))
        assertEquals(0,field("currentIndex")); assertEquals("",item(1).url); assertTrue(probe.media.isEmpty())
    }

    @Test fun blankTargetLateReplyRejectedDestroyed() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); destroyed(true); replyDirect(mapOf("url" to "https://shuffle.invalid/late.mp4"))
        assertEquals(0,field("currentIndex")); assertEquals("",item(1).url); assertTrue(probe.media.isEmpty())
    }

    @Test fun blankTargetLateReplyRejectedSleepAutomatic() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=true); set("sleepStopLatched",true); replyDirect(mapOf("url" to "https://shuffle.invalid/late.mp4"))
        assertEquals(0,field("currentIndex")); assertEquals("",item(1).url); assertTrue(probe.media.isEmpty())
    }

    @Test fun blankResolutionFailureFetchesSameIdentityThenRetriesAnother() {
        payload(p2Item(season=1,episode=1),p2Item(url="",season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(); replyDirect(null); pump()
        assertEquals(0,field("currentIndex")); assertEquals(mapOf("season" to 1,"episode" to 2),request("requestEpisodeFetch").call.arguments)
        replyDirect(null,request("requestEpisodeFetch")); pump(); assertEquals("No other playable episode found for shuffle",pill().text.toString())
    }

    @Test fun currentIdentityRequiresBothSeasonOnly() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,1)); model().items[0]=item().copy(season=1,episode=null);
         assertTrue(shuffle()); assertEquals(mapOf("season" to 1,"episode" to 1),request("requestEpisodeFetch").call.arguments)
    }

    @Test fun currentIdentityRequiresBothEpisodeOnly() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,1)); model().items[0]=item().copy(season=null,episode=1);
         assertTrue(shuffle()); assertEquals(mapOf("season" to 1,"episode" to 1),request("requestEpisodeFetch").call.arguments)
    }
}
