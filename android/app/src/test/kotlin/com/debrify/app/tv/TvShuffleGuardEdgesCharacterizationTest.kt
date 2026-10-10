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
internal class TvShuffleGuardEdgesCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun sameAttemptNewWatchGenerationSuppressesOldTimeout() {
        var retries=0; val a=attemptWith(unavailable={retries++}); call("watchShufflePlayback",arrayOf(attemptType),a); pump(1); call("watchShufflePlayback",arrayOf(attemptType),a); pump(14_999); assertSame(a,field("pendingShufflePlayback")); assertEquals(0,retries); pump(1); assertEquals(1,retries)
    }

    @Test fun pikpakWatchRejectsNotStarted() {
        payload(p2Item(provider="PikPak")); set("isPikPakRetrying",true); var retries=0; val a=attemptWith(started=false,unavailable={retries++}); call("watchShufflePlayback",arrayOf(attemptType),a); ; pump(15_000); assertNull(field("pendingShufflePlayback")); assertEquals(1,field("shuffleWatchGeneration")); assertEquals(1,retries)
    }

    @Test fun pikpakWatchRejectsNotPikPak() {
        payload(p2Item(provider="Other")); set("isPikPakRetrying",true); var retries=0; val a=attemptWith(started=true,unavailable={retries++}); call("watchShufflePlayback",arrayOf(attemptType),a); ; pump(15_000); assertNull(field("pendingShufflePlayback")); assertEquals(1,field("shuffleWatchGeneration")); assertEquals(1,retries)
    }

    @Test fun pikpakWatchRejectsNotRetrying() {
        payload(p2Item(provider="PikPak")); set("isPikPakRetrying",false); var retries=0; val a=attemptWith(started=true,unavailable={retries++}); call("watchShufflePlayback",arrayOf(attemptType),a); ; pump(15_000); assertNull(field("pendingShufflePlayback")); assertEquals(1,field("shuffleWatchGeneration")); assertEquals(1,retries)
    }

    @Test fun pikpakWatchRejectsNotCurrent() {
        payload(p2Item(provider="PikPak")); set("isPikPakRetrying",true); var retries=0; val a=attemptWith(started=true,unavailable={retries++}); call("watchShufflePlayback",arrayOf(attemptType),a); set("showShuffleGeneration",1); pump(15_000); assertNull(field("pendingShufflePlayback")); assertEquals(1,field("shuffleWatchGeneration")); assertEquals(0,retries)
    }

    @Test fun inPackIdentityMustMatchDifferentSeason() {
        payload(p2Item("Outgoing",season=1,episode=1)); wholeShow(ShuffleEpisode(2,1)); shuffle(); assertTrue(probe.media.isEmpty()); assertEquals(0,field("currentIndex")); assertEquals(mapOf("season" to 2,"episode" to 1),request("requestEpisodeFetch").call.arguments)
    }

    @Test fun inPackIdentityMustMatchDifferentEpisode() {
        payload(p2Item("Outgoing",season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); shuffle(); assertTrue(probe.media.isEmpty()); assertEquals(0,field("currentIndex")); assertEquals(mapOf("season" to 1,"episode" to 2),request("requestEpisodeFetch").call.arguments)
    }

    @Test fun fetchAttemptAlreadyUnownedFinishing() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); finishing(true); assertTrue(shuffle(automatic=false)); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertTrue(probe.media.isEmpty())
    }

    @Test fun fetchAttemptAlreadyUnownedDestroyed() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); destroyed(true); assertTrue(shuffle(automatic=false)); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertTrue(probe.media.isEmpty())
    }

    @Test fun fetchAttemptAlreadyUnownedAutomaticSleep() {
        payload(p2Item(season=1,episode=1)); wholeShow(ShuffleEpisode(1,2)); set("sleepStopLatched",true); assertTrue(shuffle(automatic=true)); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertTrue(probe.media.isEmpty())
    }

    @Test fun catalogGuidePreviousVisibleWithoutAdjacentResolver() {
        payload(p2Item(season=2,episode=2),type="series"); set("hasPlaylistResolver",true); model().guideEpisodes.addAll(listOf(guide(2,1),guide(2,2))); dockCall("updateCatalogEpisodeControls"); assertEquals(View.VISIBLE,(field("iptvPrevButton") as View).visibility)
    }

    @Test fun wholeShowRandomWinsOverPackRandom() {
        payload(p2Item(season=1,episode=1),p2Item(season=1,episode=2).copy(index=1)); wholeShow(ShuffleEpisode(2,4)); call("playRandom",emptyArray()); assertTrue(probe.media.isEmpty()); assertEquals(mapOf("season" to 2,"episode" to 4),request("requestEpisodeFetch").call.arguments)
    }

    @Test fun missingPayloadCannotShuffleWholeShow() {
        set("payload",null); assertEquals(false,call("canShuffleWholeShow",emptyArray()))
    }

    @Test fun trioUpdatesRealGuideHeaderAndNotifiesAdapter() {
        call("initStremioTvGuide",arrayOf(org.json.JSONObject::class.java),org.json.JSONObject().put("currentChannelId","id").put("channels",org.json.JSONArray().put(org.json.JSONObject().put("id","id").put("name","Cinema").put("nowPlaying",org.json.JSONObject().put("title","Old")))))
        val c=(field("stremioTvChannels") as List<StremioTvGuideChannel>).single(); val adapter=field("stremioTvChannelAdapter") as androidx.recyclerview.widget.RecyclerView.Adapter<*>
        var refreshed=0; adapter.registerAdapterDataObserver(object: androidx.recyclerview.widget.RecyclerView.AdapterDataObserver() { override fun onChanged() { refreshed++ } })
        call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,mapOf("nowPlaying" to mapOf("title" to "New programme")),"https://tv.invalid/new.mp4","Next",false)
        assertEquals(1,refreshed); assertEquals("New programme",(field("stremioTvGuideCurrentTitle") as TextView).text.toString())
    }

    @Test fun replacePayloadResetsNonzeroCurrentIndex() {
        payload(p2Item(),p2Item("Outgoing").copy(index=1)); set("currentIndex",1); call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),p2Guide(),emptyMap<String,Any>(),"Next","https://tv.invalid/new.mp4"); assertEquals(0,field("currentIndex")); assertEquals("Next",item().title)
    }

    @Test fun trioClearsBorrowedLoadingStateBeforePlayerInstall() {
        set("subtitleAddonDiscoveryReady",false); set("isLoadingStremioSubtitles",true); probe.onEvent={ if(it.startsWith("media:")) { assertTrue(field("subtitleAddonDiscoveryReady") as Boolean); assertFalse(field("isLoadingStremioSubtitles") as Boolean) } }; call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),p2Guide(),emptyMap<String,Any>(),"https://tv.invalid/new.mp4","Next",false); assertEquals(1,probe.media.size)
    }
}
