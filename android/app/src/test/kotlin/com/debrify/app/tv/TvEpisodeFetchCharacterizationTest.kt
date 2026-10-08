package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpisodeFetchCharacterizationTest : TvPhase10OriginalTest() {
    @Test fun requestPinsMapIncrementedTokenLockAndInFlightGuard() {
        set("stremioResolutionToken",40); fetch();assertEquals(41,field("stremioResolutionToken"));assertTrue(lock())
        assertEquals(mapOf("season" to 2,"episode" to 5),requestMap("requestEpisodeFetch"));assertEquals("Fetching S02E05…",pill().text.toString())
        fetch(3,1);assertEquals(1,requests("requestEpisodeFetch").size);assertEquals(41,field("stremioResolutionToken"))
        callback(value=result());assertFalse("captured prefix token accepts its own reply",probe.media.isEmpty());assertFalse(lock())
    }
    @Test fun episodeDefaultSuppressResumeIsEvaluatedFromAutoAdvance() {
        seriesItem();set("stremioSources",object : ArrayList<StremioSource>(sources()) {
            // The independent shared flag can be consumed during adoption; the
            // default parameter must already retain its invocation-time value.
            override fun clear() { set("isAutoAdvancing",false);super.clear() }
        });defaultCall("requestEpisodeFetch",arrayOf(intType,intType,boolType,boolType,attemptType,function0,function0),120,2,5,true,false,null,null,null)
        callback(value=result());assertEquals(0L,field("pendingSeekMs"))
    }
    @Test fun adjacentDefaultDirectionAndAutoAdvancePreserveForwardResume() {
        seriesItem();defaultCall("requestAdjacentEpisodeFetch",arrayOf(stringType,intType,intType,boolType,intType),24,null,2,4,false,0)
        assertEquals(1,requestMap("requestEpisodeFetch")["direction"]);callback(value=result());assertEquals(123L,field("pendingSeekMs"))
    }
    @Test fun missingChannelShowsExactMessageWithoutLockOrTokenMutation() {
        noChannel();val token=field("stremioResolutionToken");fetch();assertEquals("Couldn't fetch S02E05",pill().text.toString());assertFalse(lock());assertEquals(token,field("stremioResolutionToken"))
    }
    @Test fun successfulEpisodeAdoptsSourcesAndPassesTargetResumeAndShuffleAttempt() {
        seriesItem(); var firstAdoption=true; val adopted=object : ArrayList<StremioSource>(sources()) { override fun clear() { if(firstAdoption) assertEquals("auto flag set before source adoption",true,field("isAutoAdvancing"));firstAdoption=false;super.clear() } };set("stremioSources",adopted);val a=attempt();fetch(auto=true,suppress=true,attempt=a);callback(value=result("preferredSourceMissing" to true))
        assertFalse(lock());assertEquals(false,field("isAutoAdvancing"));assertEquals("Fetched source",sources().single().name)
        assertEquals(5,model().items.single().episode);assertEquals(0L,field("pendingSeekMs"));assertSame(a,field("pendingShufflePlayback"))
        assertEquals("Your previous source is unavailable for this episode. Using another source.",ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_LONG,ShadowToast.getLatestToast().duration)
    }
    @Test fun successfulEpisodeWithResumeEnabledKeepsFetchedBookmark() {
        seriesItem();fetch();callback(value=result());assertEquals(123L,field("pendingSeekMs"));assertEquals(5,model().items.single().episode)
    }
    @Test fun malformedSuccessInvokesUnavailableInsteadOfReplacingMediaOrShowingPill() {
        var unavailable=0;fetch(unavailable={unavailable++});callback(value=mapOf("items" to emptyList<Any>(),"sourceIndex" to 0))
        assertEquals(1,unavailable);assertFalse(lock());assertEquals("Fetching S02E05…",pill().text.toString());assertTrue(probe.media.isEmpty())
    }
    @Test fun malformedSuccessWithoutCallbackShowsNoPlayableMessage() {
        fetch();callback(value=mapOf("items" to listOf(raw())));assertEquals("No playable source found for S02E05",pill().text.toString());assertFalse(lock())
    }
    private fun staleSuccess(queued: Boolean) {
        fetch();callback(value=result(),queued=queued)
        if(queued) {assertTrue("lock clearing deferred to UI",lock());set("stremioResolutionToken",999);tick(32);assertTrue("stale UI success rejected",probe.media.isEmpty())}
        else assertFalse("inline callback applied before later supersession",probe.media.isEmpty())
        assertFalse(lock())
    }
    @Test fun inlineSuccessAppliesBeforeLaterTokenSupersession() = staleSuccess(false)
    @Test fun queuedSuccessClearsLockThenRejectsTokenChangedBeforeUiRuns() = staleSuccess(true)
    private fun continuation(queued: Boolean) {
        var current=true;var unavailable=0;fetch(unavailable={unavailable++},continueIf={current});callback("error",queued=queued)
        if(queued){assertTrue(lock());current=false;tick(32);assertEquals("continuation read inside UI block",0,unavailable)}else assertEquals(1,unavailable)
        assertFalse(lock())
    }
    @Test fun inlineErrorReadsContinuationBeforeItsChange() = continuation(false)
    @Test fun queuedErrorReadsContinuationAfterItsChangeAndClearsLock() = continuation(true)
    @Test fun falseContinuationSuppressesSuccessAndUnavailable() {
        var unavailable=0;fetch(unavailable={unavailable++},continueIf={false});callback(value=result());assertFalse(lock());assertTrue(probe.media.isEmpty());assertEquals(0,unavailable)
    }
    @Test fun queuedShuffleOwnsNavigationAndEpisodeSuccessYields() {
        fetch();callback(value=result(),queued=true);set("queuedShuffleGeneration",field("showShuffleGeneration"));set("queuedShuffleNavigation",field("mediaPreparationGeneration"));tick(32)
        assertFalse(lock());assertTrue(probe.media.isEmpty())
    }
    @Test fun errorHonorsUnavailableAndItsExactFallbackMessage() {
        var count=0;fetch(unavailable={count++});callback("error");assertEquals(1,count);fetch();callback("error");assertEquals("No playable source found for S02E05",pill().text.toString())
    }
    private fun missing(queued: Boolean) {
        fetch();set("stremioResolutionToken",99);callback("missing",queued=queued)
        if(queued){assertTrue(lock());tick(32)}
        assertFalse(lock());assertEquals("Couldn't fetch S02E05",pill().text.toString())
    }
    @Test fun inlineNotImplementedIgnoresSupersededToken() = missing(false)
    @Test fun queuedNotImplementedIgnoresSupersededTokenAndDefersClear() = missing(true)
    @Test fun adjacentMapPinsOptionalImdbDirectionLabelAndInFlightGuard() {
        adjacent(direction=-1);assertEquals(mapOf("imdbId" to "tt12345","currentSeason" to 2,"currentEpisode" to 4,"direction" to -1),requestMap("requestEpisodeFetch"))
        assertEquals("Finding previous episode…",pill().text.toString());adjacent();assertEquals(1,requests("requestEpisodeFetch").size)
    }
    @Test fun adjacentWithoutImdbOmitsItAndMissingBridgeKeepsNextMessage() {
        adjacent(imdb=null);assertFalse(requestMap("requestEpisodeFetch").containsKey("imdbId"));callback("missing")
        assertEquals("Couldn't fetch next episode",pill().text.toString());noChannel();adjacent(direction=-1);assertEquals("Couldn't fetch next episode",pill().text.toString())
    }
    @Test fun adjacentSuccessRequiresTargetIdentityAndCarriesAutoAdvanceResumeFlag() {
        seriesItem();adjacent(auto=true);callback(value=result());assertEquals(5,model().items.single().episode);assertEquals(0L,field("pendingSeekMs"))
    }
    @Test fun adjacentMissingTargetShowsDirectionSpecificFailure() {
        adjacent(direction=-1);callback(value=result().filterKeys { it!="targetEpisode" });assertEquals("No playable previous episode found",pill().text.toString());assertTrue(probe.media.isEmpty())
    }
    private fun guideItem(ep: Int) = GuideEpisode(season=2,episode=ep,title="Episode",artwork=null,description=null,rating=null,runtime=null,resumePositionMs=null,durationMs=null,trackerProgressPercent=null,watched=false)
    private fun fallback(queued: Boolean) {
        seriesItem();model().guideEpisodes.addAll(listOf(guideItem(4),guideItem(5)));set("hasAdjacentEpisodeResolver",true)
        adjacent(auto=true);callback("error",queued=queued,code="episode_guide_unavailable")
        if(queued) {
            assertEquals(1,requests("requestEpisodeFetch").size);model().items[0]=p2Item(season=9,episode=9);tick(32)
            assertEquals("fallback reads live payload on UI",1,requests("requestEpisodeFetch").size);assertEquals("No playable next episode found",pill().text.toString())
        } else {assertEquals(2,requests("requestEpisodeFetch").size);assertEquals(mapOf("season" to 2,"episode" to 5),requestMap("requestEpisodeFetch"));callback(value=result());assertEquals(0L,field("pendingSeekMs"))}
    }
    @Test fun inlineAdjacentFallbackUsesCurrentGuideAndAllowsResolverFallback() = fallback(false)
    @Test fun queuedAdjacentFallbackReadsChangedPayloadAtUiTime() = fallback(true)
    @Test fun queuedAdjacentFallbackReadsChangedIndexAtUiTime() {
        seriesItem();model().guideEpisodes.addAll(listOf(guideItem(4),guideItem(5)));model().items.add(p2Item(season=9,episode=9))
        adjacent();callback("error",queued=true,code="episode_guide_unavailable");set("currentIndex",1);tick(32)
        assertEquals(1,requests("requestEpisodeFetch").size);assertEquals("No playable next episode found",pill().text.toString())
    }
    @Test fun queuedAdjacentSuccessRejectsSupersededTokenInsideUi() {
        adjacent();callback(value=result(),queued=true);assertTrue(lock());set("stremioResolutionToken",99);tick(32);assertFalse(lock());assertTrue(probe.media.isEmpty())
    }
    @Test fun queuedAdjacentErrorYieldsToExplicitShuffle() {
        adjacent();callback("error",queued=true);set("queuedShuffleGeneration",field("showShuffleGeneration"));set("queuedShuffleNavigation",field("mediaPreparationGeneration"));tick(32)
        assertFalse(lock());assertEquals("Finding next episode…",pill().text.toString())
    }
    @Test fun shuffleWaitRetriesAfter50MillisAndReadsTheLiveFetchLock() {
        seriesItem();model().guideEpisodes.addAll(listOf(guideItem(4),guideItem(5)));set("hasPlaylistResolver",true);set("episodeFetchInFlight",true)
        assertEquals(true,call("playShowShuffle",arrayOf(Set::class.java,boolType),emptySet<ShuffleEpisode>(),false))
        tick(49);assertTrue(requests("requestEpisodeFetch").isEmpty());tick(1);assertTrue(requests("requestEpisodeFetch").isEmpty())
        set("episodeFetchInFlight",false);tick(49);assertTrue(requests("requestEpisodeFetch").isEmpty());tick(1);assertEquals(1,requests("requestEpisodeFetch").size)
    }
}
