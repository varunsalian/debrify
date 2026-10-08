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
internal class TvSourceFetchCharacterizationTest : TvPhase10OriginalTest() {
    @Suppress("UNCHECKED_CAST") private fun states()=field("addonFetchState") as MutableMap<String,String>
    @Suppress("UNCHECKED_CAST") private fun probing()=field("addonPackProbing") as MutableSet<String>
    private fun addons() {set("sourceAddons",listOf(AndroidTvTorrentPlayerActivity.TvSourceAddon("one","One","group"),AndroidTvTorrentPlayerActivity.TvSourceAddon("two","Two","group"),AndroidTvTorrentPlayerActivity.TvSourceAddon("other","Other","different")))}
    @Test fun moreRequestUsesCurrentPlaylistEpisodeLocksAndRendersLoading() {
        seriesItem();model().items.add(p2Item(season=8,episode=3));set("currentIndex",1);more("episodes")
        assertEquals(mapOf("mode" to "episodes","season" to 8,"episode" to 3),requestMap("requestMoreTorrentSources"));assertEquals("episodes",loading())
        more("packs");assertEquals(1,requests("requestMoreTorrentSources").size)
    }
    @Test fun missingMoreBridgeShowsPillAndVisibleBrowserShowsDifferentError() {
        noChannel();more();assertEquals("Couldn't load more sources",pill().text.toString());assertNull(loading())
        browser().show();more();assertEquals("Couldn't load more sources — try again",browserError())
    }
    @Test fun successfulMoreReplacesAppendOnlySourcesClampsIndexSetsFlagsAndBadge() {
        (field("stremioSourceBadgeText") as android.widget.TextView).text="stale";set("currentStremioSourceIndex",7);more();callback(value=result("packsFetched" to true,"episodesFetched" to true,"movieFetched" to true))
        assertNull(loading());assertEquals("Fetched source",sources().single().name);assertEquals(0,selected())
        assertEquals(true,field("seriesPacksFetched"));assertEquals(true,field("seriesEpisodesFetched"));assertEquals(true,field("movieSourcesFetched"))
        assertEquals("Sources",(field("stremioSourceBadgeText") as android.widget.TextView).text.toString())
    }
    @Test fun emptySourceListKeepsExistingSourceAndIndexWhileClearingLock() {
        set("currentStremioSourceIndex",1);val old=sources().toList();more();callback(value=mapOf("stremioSources" to emptyList<Any>()))
        assertEquals(old,sources());assertEquals(1,selected());assertNull(loading())
    }
    @Test fun invalidSourceEntriesAreSkippedAndTheirOriginalIndicesAreKept() {
        more();callback(value=mapOf("stremioSources" to listOf("invalid",mapOf("name" to "Second"))))
        assertEquals(1,sources().size);assertEquals(1,sources().single().index);assertEquals("Second",sources().single().name)
    }
    private fun finishingReply(queued: Boolean) {
        more();callback(value=result(),queued=queued)
        if(queued){assertEquals("packs",loading());finishing(true);tick(32);assertEquals("packs",loading());assertEquals(2,sources().size);finishing(false)}
        else {assertNull(loading());assertEquals(1,sources().size)}
    }
    @Test fun inlineMoreSuccessAppliesBeforeFinishingChanges()=finishingReply(false)
    @Test fun queuedMoreSuccessDefersFinishingGuardAndLeavesLoadingLocked()=finishingReply(true)
    @Test fun destroyedMoreSuccessLeavesLoadingAndSourcesUntouched() {
        more();destroyed(true);callback(value=result());assertEquals("packs",loading());assertEquals(2,sources().size);destroyed(false)
    }
    @Test fun nullMoreReplyClearsLoadingAndShowsError() {
        more();callback();assertNull(loading());assertEquals("Couldn't load more sources",pill().text.toString())
    }
    @Test fun moreErrorAndNotImplementedClearLoadingAndShowExactMessage() {
        for(kind in listOf("error","missing")){more();callback(kind);assertNull(loading());assertEquals("Couldn't load more sources",pill().text.toString())}
    }
    @Test fun queuedMoreFailureDefersLockClearAndRecoveryUntilUi() {
        more();callback("error",queued=true);assertEquals("packs",loading());tick(32);assertNull(loading());assertEquals("Couldn't load more sources",pill().text.toString())
    }
    @Test fun recoveryResultPreservesCandidateCountIndicesAndNextMode() {
        sources().clear();sources().add(source(0));begin();set("startupRecoveryFetching",true);TvPlayerOriginalAccess.set(field("startupGateController")!!,"startupRecoveryProducedCandidates",true)
        more();callback(value=mapOf("recoveryCandidateCount" to 0,"recoveryCandidateIndices" to listOf(1,"bad",2),"recoveryNextMode" to "episodes"))
        assertEquals(true,TvPlayerOriginalAccess.field(field("startupGateController")!!,"startupRecoveryProducedCandidates"));assertEquals(listOf(1,2),field("startupRecoveryCandidateIndices"));assertEquals("episodes",TvPlayerOriginalAccess.field(field("startupGateController")!!,"startupRecoveryNextMode"));assertEquals(false,field("startupRecoveryFetching"))
    }
    @Test fun addonFiltersConfiguredSourceKeyAndFetchesEpisodesFirstOnlyOnce() {
        addons();seriesItem();addon();assertEquals("configured sourceKey emits one episode request",1,requests("requestAddonTorrentSources").size);assertEquals(mapOf("addonIds" to listOf("one","two"),"mode" to "episodes","season" to 2,"episode" to 4),requestMap("requestAddonTorrentSources"))
        assertEquals("fetching",states()["group"]);addon();addon("absent");assertEquals(1,requests("requestAddonTorrentSources").size)
    }
    @Test fun addonNullChannelShowsBrowserErrorWithoutEnteringFetching() {
        addons();noChannel();addon();assertNull(states()["group"]);assertEquals("Couldn't fetch — try again",browserError())
    }
    @Test fun addonSuccessMarksFetchedAdoptsAndEmptyProbeDoesNotRequestPacks() {
        addons();addon();callback(value=result("packAddonIds" to emptyList<String>()))
        assertEquals("fetched",states()["group"]);assertEquals("Fetched source",sources().single().name);assertTrue(probing().isEmpty());assertEquals(1,requests("requestAddonTorrentSources").size)
    }
    @Test fun addonPackProbeUsesOnlyStringIdsAndCapturedSeason() {
        addons();seriesItem();addon();model().items[0]=p2Item(season=9,episode=9)
        callback(value=result("packAddonIds" to listOf("one",7,"two")))
        assertEquals(mapOf("addonIds" to listOf("one","two"),"mode" to "packs","season" to 2),requestMap("requestAddonTorrentSources"));assertTrue(probing().contains("group"))
        callback(value=result("stremioSources" to listOf(mapOf("name" to "Pack"))))
        assertTrue(probing().isEmpty());assertEquals("Pack",sources().single().name)
    }
    @Test fun addonProbeErrorAndNotImplementedRetireProbingAndKeepFetchedState() {
        addons()
        for(kind in listOf("error","missing")){states().clear();addon();callback(value=result("packAddonIds" to listOf("one")));assertTrue(probing().contains("group"));callback(kind);assertTrue(probing().isEmpty());assertEquals("fetched",states()["group"])}
    }
    @Test fun addonProbeNullChannelRetiresProbingWithoutPackRequest() {
        addons();addon();noChannel();callback(value=result("packAddonIds" to listOf("one")))
        assertEquals("fetched",states()["group"]);assertTrue(probing().isEmpty());assertEquals(1,requests("requestAddonTorrentSources").size)
    }
    @Test fun addonNullErrorAndNotImplementedRepliesAllMarkFailed() {
        addons()
        for(kind in listOf("success","error","missing")){states().clear();addon();callback(kind);assertEquals("failed",states()["group"])}
    }
    @Test fun queuedAddonReplyStillAdoptsAfterDestroyedBecauseItHasNoGuard() {
        addons();addon();callback(value=result(),queued=true);assertEquals("fetching",states()["group"]);destroyed(true);tick(32)
        assertEquals("fetched",states()["group"]);assertEquals("Fetched source",sources().single().name);destroyed(false)
    }
}
