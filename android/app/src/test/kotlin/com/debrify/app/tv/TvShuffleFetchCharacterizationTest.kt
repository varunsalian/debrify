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
internal class TvShuffleFetchCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun episodeFetchRejectsShowGeneration() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); assertEquals(1,requests("requestEpisodeFetch").size)
        set("showShuffleGeneration",1); replyDirect(mapOf("sourceIndex" to 0,"items" to listOf(mapOf("title" to "Target","url" to "https://shuffle.invalid/new.mp4","season" to 1,"episode" to 2))),request("requestEpisodeFetch")); pump()
        assertEquals(0,field("currentIndex")); assertEquals("https://example.test/a",item().url); assertTrue(probe.media.isEmpty()); assertFalse(field("episodeFetchInFlight") as Boolean)
    }

    @Test fun episodeFetchRejectsNavigation() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); assertEquals(1,requests("requestEpisodeFetch").size)
        set("mediaPreparationGeneration",1); replyDirect(mapOf("sourceIndex" to 0,"items" to listOf(mapOf("title" to "Target","url" to "https://shuffle.invalid/new.mp4","season" to 1,"episode" to 2))),request("requestEpisodeFetch")); pump()
        assertEquals(0,field("currentIndex")); assertEquals("https://example.test/a",item().url); assertTrue(probe.media.isEmpty()); assertFalse(field("episodeFetchInFlight") as Boolean)
    }

    @Test fun episodeFetchRejectsFinishing() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); assertEquals(1,requests("requestEpisodeFetch").size)
        finishing(true); replyDirect(mapOf("sourceIndex" to 0,"items" to listOf(mapOf("title" to "Target","url" to "https://shuffle.invalid/new.mp4","season" to 1,"episode" to 2))),request("requestEpisodeFetch")); pump()
        assertEquals(0,field("currentIndex")); assertEquals("https://example.test/a",item().url); assertTrue(probe.media.isEmpty()); assertFalse(field("episodeFetchInFlight") as Boolean)
    }

    @Test fun episodeFetchRejectsDestroyed() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=false); assertEquals(1,requests("requestEpisodeFetch").size)
        destroyed(true); replyDirect(mapOf("sourceIndex" to 0,"items" to listOf(mapOf("title" to "Target","url" to "https://shuffle.invalid/new.mp4","season" to 1,"episode" to 2))),request("requestEpisodeFetch")); pump()
        assertEquals(0,field("currentIndex")); assertEquals("https://example.test/a",item().url); assertTrue(probe.media.isEmpty()); assertFalse(field("episodeFetchInFlight") as Boolean)
    }

    @Test fun episodeFetchRejectsAutomaticSleep() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(automatic=true); assertEquals(1,requests("requestEpisodeFetch").size)
        set("sleepStopLatched",true); replyDirect(mapOf("sourceIndex" to 0,"items" to listOf(mapOf("title" to "Target","url" to "https://shuffle.invalid/new.mp4","season" to 1,"episode" to 2))),request("requestEpisodeFetch")); pump()
        assertEquals(0,field("currentIndex")); assertEquals("https://example.test/a",item().url); assertTrue(probe.media.isEmpty()); assertFalse(field("episodeFetchInFlight") as Boolean)
    }

    @Test fun unavailableFetchRetriesAnotherIdentityWithoutRepeatingAttempt() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2),ShuffleEpisode(1,3)); shuffle(); val first=request("requestEpisodeFetch").call.arguments
        replyDirect(null,request("requestEpisodeFetch")); pump(); assertEquals(2,requests("requestEpisodeFetch").size); assertNotEquals(first,request("requestEpisodeFetch").call.arguments)
        replyDirect(null,request("requestEpisodeFetch")); pump(); assertEquals(2,requests("requestEpisodeFetch").size); assertEquals("No other playable episode found for shuffle",pill().text.toString())
    }

    @Test fun successfulFetchCarriesAutoSuppressionAndAttempt() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(2,4)); shuffle(automatic=true)
        replyDirect(mapOf("sourceIndex" to 0,"items" to listOf(mapOf("title" to "Fetched","url" to "https://shuffle.invalid/fetched.mp4","season" to 2,"episode" to 4,"resumePositionMs" to 500L,"traktProgressPercent" to 60.0))),request("requestEpisodeFetch")); pump()
        assertEquals(2,item().season); assertEquals(4,item().episode); assertEquals(0L,field("pendingSeekMs")); assertEquals(0.0,field("pendingItemTraktPercent")); assertEquals(1,probe.media.size); assertEquals(true,field("pendingShufflePlayback")?.let { attemptField(it,"mediaStarted") })
    }

    @Test fun queuedShuffleMakesOlderFetchYieldBeforeItsMediaStart() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,1),ShuffleEpisode(1,3)); call("playNext",emptyArray()); set("customShuffleEpisodes",listOf(ShuffleEpisode(1,2)))
        val old=request("requestEpisodeFetch"); shuffle(); replyDirect(mapOf("sourceIndex" to 0,"items" to listOf(mapOf("title" to "Older","url" to "https://old.invalid/older.mp4","season" to 1,"episode" to 3))),old); pump()
        assertTrue(probe.media.isEmpty()); pump(50); assertEquals(mapOf("season" to 1,"episode" to 2),request("requestEpisodeFetch").call.arguments); assertEquals("https://example.test/a",item().url)
    }

    @Test fun resetClearsShowVisitedSoPreviouslyVisitedCanBePicked() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,1),ShuffleEpisode(1,2),ShuffleEpisode(1,3))
        val sh=field("showShuffle") as ShowShuffle; sh.pick(listOf(ShuffleEpisode(1,2)),null)
        assertFalse((TvPlayerOriginalAccess.field(sh,"visited") as Set<*>).isEmpty()); call("resetShuffle",emptyArray())
        assertTrue("explicit reset starts a fresh visited cycle",(TvPlayerOriginalAccess.field(sh,"visited") as Set<*>).isEmpty())
        set("customShuffleEpisodes",listOf(ShuffleEpisode(1,2))); shuffle(); assertEquals(mapOf("season" to 1,"episode" to 2),request("requestEpisodeFetch").call.arguments)
    }
}
