package com.debrify.app.tv
import android.view.View
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.LinearLayoutManager
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog
import org.robolectric.shadows.ShadowToast
import org.robolectric.util.ReflectionHelpers
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvNavigationCharacterizationTest : TvPhase11OriginalTest() {
    @Test fun countUsesTotalOnlyForOwnedPagedWindow() {
        set("iptvZapCategoryTotal",99);set("iptvGuideUsesZapWindow",true);set("iptvZapPagingActive",true)
        assertEquals("99 items",call("iptvGuideItemCountLabel",emptyArray()))
        set("iptvZapPagingActive",false);assertEquals("2 items",call("iptvGuideItemCountLabel",emptyArray()))
        set("iptvZapPagingActive",true);set("iptvGuideUsesZapWindow",false);assertEquals("2 items",call("iptvGuideItemCountLabel",emptyArray()))
        set("iptvGuideUsesZapWindow",true);set("iptvZapCategoryTotal",0);assertEquals("2 items",call("iptvGuideItemCountLabel",emptyArray()))

    }
    @Test fun vodCatalogHidesAllLiveControlsWithGone() {
        set("iptvContentType","vod");call("refreshIptvBrowserChrome",arrayOf(stringType),null)
        assertEquals("Movies",(field("iptvGuideTitle") as TextView).text.toString())
        for(id in listOf(R.id.iptv_nav_browse,R.id.iptv_nav_search,R.id.iptv_filter_bar,R.id.iptv_nav_favorites,R.id.iptv_nav_sources,R.id.iptv_source_button))assertEquals(View.GONE,activity.findViewById<View>(id).visibility)

    }
    @Test fun selectSourceResetsEpisodeModeAndBrowseScope() {
        set("iptvContentType","episodes");search().setText("stale")
        call("selectIptvSource",arrayOf(IptvSourceEntry::class.java),IptvSourceEntry("other","Other",false,false,false))
        assertEquals("live",field("iptvContentType"));assertEquals("other",args("requestIptvBrowse")["sourceId"]);assertEquals("",args("requestIptvBrowse")["query"]);assertNull(field("iptvSelectedCategory"))
        call("selectIptvSource",arrayOf(IptvSourceEntry::class.java),IptvSourceEntry("continue","Continue",false,true,false));assertEquals("vod",field("iptvContentType"))

    }
    @Test fun browseCurrentIdentityUsesUrlDespiteRenamedMetadata() {
        val current=channels().first();browse();reply(value=response("channels" to listOf(rawChannel("Renamed",1))))
        assertEquals(current.url,browseChannels().single().url);assertTrue(browseChannels().single().isCurrent)

    }
    @Test fun checkpointPinsInclusiveResumeBoundaries() {
        val entry=channel(live=false);iptv(entry);probe.duration=100_000L
        for((position,expected) in listOf(1_999L to 0L,2_000L to 2_000L,95_000L to 95_000L,95_001L to 0L)) { probe.position=position;call("checkpointCurrentIptvPosition",emptyArray());assertEquals(expected,entry.resumePositionMs) }

    }
    @Test fun switchCheckpointsOutgoingBeforeSelectionAndRetiresStartOver() {
        val old=channel(live=false).copy(logoUrl=null);val next=channel(url="https://next.invalid",live=false).copy(name="Next",logoUrl=null)
        set("iptvChannels",mutableListOf(old,next));set("currentIptvIndex",0);probe.position=25_000
        set("iptvStartOverActive",true);set("iptvStartOverLoading",true);set("iptvStartOverTimelineVisible",true)
        val token=field("iptvCatchupToken") as Int
        switch(next)
        assertEquals(25_000L,old.resumePositionMs);assertEquals(1,field("currentIptvIndex"));assertEquals(token+1,field("iptvCatchupToken"))
        for(name in listOf("iptvStartOverActive","iptvStartOverLoading","iptvStartOverTimelineVisible"))assertEquals(false,field(name))
        assertEquals("Next",(field("titleView") as TextView).text.toString())
        assertEquals(next.url,args("recordIptvWatch")["url"]);assertEquals(next.seriesId,args("recordIptvWatch")["seriesId"])

    }
    @Test fun liveSwitchSupersedesPendingStartupChannelMemory() {
        val controller=field("iptvChannelStartController") as TvIptvChannelStartController
        val first=channels()[0];val second=channels()[1]
        controller.noteLiveChannelPlaying();advance(999);switch(second);controller.noteLiveChannelPlaying();clearTransport()
        advance(1);assertTrue(requests("noteIptvLiveChannel").isEmpty());advance(999)
        assertEquals(second.url,args("noteIptvLiveChannel")["url"]);assertEquals(second.name,args("noteIptvLiveChannel")["name"])

    }
    @Test fun episodeNavigationAndButtonsRespectBoundsAndLiveGate() {
        val entries=mutableListOf(channel(live=false).copy(logoUrl=null),channel(url="https://next.invalid",live=false).copy(logoUrl=null));set("iptvChannels",entries);set("currentIptvIndex",0)
        assertEquals(true,call("isIptvEpisodeMode",emptyArray()));assertSame(entries[1],call("nextIptvEpisode",emptyArray()));assertNull(call("prevIptvEpisode",emptyArray()))
        call("updateIptvEpisodeControls",emptyArray());val prev=field("iptvPrevButton") as TextView;val next=field("iptvNextButton") as TextView
        assertEquals("Previous",prev.text.toString());assertEquals(View.GONE,prev.visibility);assertEquals("Next",next.text.toString());assertEquals(View.VISIBLE,next.visibility)
        set("currentIptvIndex",1);assertNull(call("nextIptvEpisode",emptyArray()));assertSame(entries[0],call("prevIptvEpisode",emptyArray()))
        entries[1]=entries[1].copy(isLive=true);assertEquals(false,call("isIptvEpisodeMode",emptyArray()));call("updateIptvEpisodeControls",emptyArray());assertEquals("CH +",next.text.toString())

    }
    @Test fun seriesAudioPickPersistsOnlyConcreteLanguage() {
        for(lang in listOf(null,"","und","auto"))call("onIptvSeriesAudioPicked",arrayOf(stringType),lang)
        assertTrue(requests("saveIptvSeriesAudio").isEmpty());call("onIptvSeriesAudioPicked",arrayOf(stringType),"de")
        assertEquals("de",field("iptvPreferredAudioLang"));assertEquals(mapOf("seriesKey" to "provider::series","lang" to "de"),args("saveIptvSeriesAudio"))

    }
    @Test fun installedEpgBindingPostsArchiveRetryAtSixtySeconds() {
        val entry=channels().first();entry.epgLoading=false;entry.epgLoaded=false;entry.epgCatchupMetadataLoaded=false
        clearTransport();adapter().updateChannels(mutableListOf(entry));val holder=adapter().onCreateViewHolder(guideList(),0);adapter().onBindViewHolder(holder,0)
        assertTrue("installed row binding calls EPG",requests("requestIptvEpg").isNotEmpty())
        val request=messenger.requests.indexOfLast{it.call.method=="requestIptvEpg" && (it.call.arguments as Map<*,*>)["channelUrl"]==entry.url}
        val deadline=android.os.SystemClock.uptimeMillis()+60_000L
        reply(value=mapOf("now" to mapOf("title" to "Now","stopMs" to System.currentTimeMillis()+120_000L,"hasArchive" to false)),request=request)
        assertTrue("EPG targets current entry",entry.isCurrent);assertTrue("metadata callback delivered",entry.epgCatchupMetadataLoaded);clearTransport();advance(deadline-android.os.SystemClock.uptimeMillis()-1);assertTrue("before deadline: ${requests("requestIptvEpg").map{it.call.arguments}}",requests("requestIptvEpg").isEmpty())
        advance(1);assertFalse(entry.epgCatchupMetadataLoaded);assertEquals(1,requests("requestIptvEpg").size)

    }
    @Test fun destroyInvalidatesGuideWorkAndClearsBorrowedPosts() {
        var delivered=0;page {_,_,_,_,_->delivered++};val request=messenger.requests.lastIndex
        queue().add(1);val before=listOf("iptvUiContextToken","iptvBrowseToken","iptvZapRequestToken").associateWith{field(it) as Int}
        var borrowed=false;(field("iptvBrowseHandler") as android.os.Handler).postDelayed({borrowed=true},1_000)
        var releasedAfterCleanup=false
        probe.onEvent={ if(it=="release") { releasedAfterCleanup=before.all{(name,value)->field(name)==value+1} && field("iptvZapRequestInFlight")==false && queue().isEmpty() } }
        destroyNow()
        assertTrue("guide cleanup precedes player release",releasedAfterCleanup)
        before.forEach{(name,value)->assertEquals(name,value+1,field(name))};assertFalse(field("iptvZapRequestInFlight") as Boolean);assertTrue(queue().isEmpty())
        reply(request=request);advance(1_000);assertEquals(0,delivered);assertFalse(borrowed)

    }
}
