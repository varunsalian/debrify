package com.debrify.app.tv
import android.view.View
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.widget.TextView
import android.widget.ImageView
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import com.debrify.app.MainActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28], instrumentedPackages=["com.debrify.app.tv.AndroidTvTorrentPlayerActivity","com.debrify.app.tv.TvIptvGuideChromeController"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvOverlayCallbackCharacterizationTest : TvPhase12OriginalTest() {
    private class PostProbe(context: android.content.Context) : RecyclerView(context) {
        val pending=mutableListOf<Runnable>()
        override fun post(action: Runnable): Boolean { pending.add(action);return true }
    }

    @Test fun installedSeriesLongClickPinsToastAndDoesNotBrowse() {
        val e=entry().copy(name="Show",url="xtream-series://42",contentType="series")
        boundAdapter().updateChannels(listOf(e))
        val h=boundAdapter().onCreateViewHolder(guideList(),0)
        boundAdapter().onBindViewHolder(h,0)
        clearTransport()
        assertTrue(h.itemView.performLongClick())
        assertEquals("Open the series to choose an episode",ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_SHORT,ShadowToast.getLatestToast().duration)
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun installedOrdinaryLongClickTogglesFavoriteWithoutCustomLists() {
        val e=entry(false)
        seedLists(listOf(IptvListEntry("favorites","Favorites",true)))
        boundAdapter().updateChannels(listOf(e))
        val h=boundAdapter().onCreateViewHolder(guideList(),0)
        boundAdapter().onBindViewHolder(h,0)
        clearTransport()
        h.itemView.performLongClick()
        assertTrue(e.isFavorite)
        assertEquals(true,args("setIptvFavorite")["isFavorite"])
    }

    @Test fun installedCustomListLongClickStartsMembershipFetch() {
        val e=entry(false)
        seedLists(listOf(IptvListEntry("list","List",false)))
        boundAdapter().updateChannels(listOf(e))
        val h=boundAdapter().onCreateViewHolder(guideList(),0)
        boundAdapter().onBindViewHolder(h,0)
        clearTransport()
        h.itemView.performLongClick()
        assertEquals(1,requests("getIptvChannelListMembership").size)
        assertEquals(e.url,args("getIptvChannelListMembership")["url"])
        assertFalse(e.isFavorite)
        assertEquals(0,dialogList().adapter!!.itemCount)
    }

    @Test fun installedEpgReplayUsesPaneEntryAndProgram() {
        val e=entry()
        set("iptvEpgEntry",e)
        val p=programme()
        epgAdapter().updatePrograms(listOf(p))
        val list=v("iptvEpgList") as RecyclerView
        val h=epgAdapter().onCreateViewHolder(list,0)
        epgAdapter().onBindViewHolder(h,0)
        clearTransport()
        h.itemView.performClick()
        assertEquals(p.startMs,args("requestIptvCatchup")["startMs"])
        assertEquals(e.url,args("requestIptvCatchup")["channelUrl"])
    }

    @Test fun installedFutureEpgInvokesRecordingAction() {
        set("iptvEpgEntry",entry())
        val now=System.currentTimeMillis()
        epgAdapter().updatePrograms(listOf(IptvEpgProgram("Future",null,now+100_000,now+200_000,false)))
        val list=v("iptvEpgList") as RecyclerView
        val h=epgAdapter().onCreateViewHolder(list,0)
        epgAdapter().onBindViewHolder(h,0)
        clearTransport()
        h.itemView.performClick()
        assertEquals("Allow storage access, then pick the programme again",ShadowToast.getTextOfLatestToast())
    }

    @Test fun installedEpgCallbacksIgnoreAbsentPaneEntry() {
        set("iptvEpgEntry",null)
        epgAdapter().updatePrograms(listOf(programme()))
        val list=v("iptvEpgList") as RecyclerView
        val h=epgAdapter().onCreateViewHolder(list,0)
        epgAdapter().onBindViewHolder(h,0)
        clearTransport()
        h.itemView.performClick()
        assertTrue(requests("requestIptvCatchup").isEmpty())
        assertNull(ShadowToast.getTextOfLatestToast())
    }

    @Test fun installedLiveSelectionCommitsSearchBeforeHidingAndTuning() {
        show()
        set("iptvSelectedCategory","Saved")
        search().requestFocus()
        assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        val token=field("iptvUiContextToken") as Int
        val e=entry(false).copy(isLive=true,group="News")
        boundAdapter().updateChannels(listOf(e))
        val h=boundAdapter().onCreateViewHolder(guideList(),0)
        boundAdapter().onBindViewHolder(h,0)
        clearTransport()
        assertTrue(h.itemView.performClick())
        assertFalse(field("iptvGuideVisible") as Boolean)
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        assertNull(field("iptvSearchSavedCategory"))
        assertEquals(token+1,field("iptvUiContextToken"))
        assertEquals("News",field("iptvSelectedCategory"))
        assertEquals(1,requests("requestIptvBrowse").size)
        assertEquals(e.url,args("requestIptvBrowse")["anchorUrl"])
    }

    @Test fun installedEpisodeSelectionCommitsSearchBeforeHidingAndTuning() {
        show()
        set("iptvSelectedCategory","Saved")
        search().requestFocus()
        assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        val token=field("iptvUiContextToken") as Int
        set("iptvContentType","episodes")
        val e=entry(false).copy(isLive=false,group="News")
        boundAdapter().updateChannels(listOf(e))
        val h=boundAdapter().onCreateViewHolder(guideList(),0)
        boundAdapter().onBindViewHolder(h,0)
        clearTransport()
        assertTrue(h.itemView.performClick())
        assertFalse(field("iptvGuideVisible") as Boolean)
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        assertNull(field("iptvSearchSavedCategory"))
        assertNull(field("iptvSelectedCategory"))
        assertEquals(token,field("iptvUiContextToken"))
        assertFalse(field("iptvZapPagingActive") as Boolean)
        assertEquals(1,channels().size)
        assertEquals(e.url,channels().single().url)
    }

    @Test fun boundOrdinaryRowRequestsEpgThroughInstalledCallback() {
        val e=entry(false).copy(url="http://provider/live/new/epg.m3u8")
        boundAdapter().updateChannels(listOf(e))
        clearTransport()
        e.epgLoaded=false
        e.epgLoading=false
        val h=boundAdapter().onCreateViewHolder(guideList(),0)
        boundAdapter().onBindViewHolder(h,0)
        assertTrue(e.epgLoading)
        assertEquals(1,requests("requestIptvEpg").size)
        assertEquals(e.url,args("requestIptvEpg")["channelUrl"])
        assertEquals(false,args("requestIptvEpg")["includeCatchupMetadata"])
    }

    @Test fun installedScrollListenerKeepsPagingAndThresholdGuards() {
        guideList().layoutManager=object:androidx.recyclerview.widget.LinearLayoutManager(activity){override fun findFirstVisibleItemPosition()=12
        override fun findLastVisibleItemPosition()=18}
        @Suppress("UNCHECKED_CAST") val listeners:List<RecyclerView.OnScrollListener>?=org.robolectric.util.ReflectionHelpers.getField(guideList(),"mScrollListeners")
        assertNotNull("real bootstrap installs scrolling callback",listeners)
        assertEquals(1,listeners!!.size)
        set("iptvZapPagingActive",true)
        set("iptvGuideUsesZapWindow",true)
        set("iptvZapRequestInFlight",false)
        set("iptvZapCategoryTotal",1000)
        set("iptvZapSourceId","provider")
        set("iptvZapContentType","live")
        set("iptvChannels",MutableList(30){entry(false).copy(index=200+it,url="http://provider/live/$it",isCurrent=it==0)})
        boundAdapter().updateChannels(channels())
        clearTransport()
        listeners.single().onScrolled(guideList(),0,1)
        assertEquals(1,requests("requestIptvBrowse").size)
        assertEquals(230,args("requestIptvBrowse")["offset"])
    }

    @Test fun installedSearchEditorMatrixSubmitsOnlyCommitKeys() {
        val cases=listOf(Triple(EditorInfo.IME_ACTION_SEARCH,null,true),Triple(EditorInfo.IME_ACTION_DONE,null,true),Triple(EditorInfo.IME_ACTION_GO,null,true),Triple(EditorInfo.IME_NULL,KeyEvent(KeyEvent.ACTION_UP,KeyEvent.KEYCODE_ENTER),true),Triple(EditorInfo.IME_NULL,KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_ENTER),false),Triple(EditorInfo.IME_NULL,KeyEvent(KeyEvent.ACTION_UP,KeyEvent.KEYCODE_DPAD_CENTER),false),Triple(EditorInfo.IME_NULL,null,false))
        search().setText("  channel  ")
        for((action,event,accepted) in cases){clearTransport()
        assertEquals(accepted,editor(search(),action,event))
        assertEquals(if(accepted) 1 else 0,requests("requestIptvBrowse").size)
        if(accepted)assertEquals("channel",args("requestIptvBrowse")["query"])}
    }

    @Test fun browseButtonWithoutSearchClearsTextAndRequestsEmptyQuery() {
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        search().setText("old text")
        clearTransport()
        activity.findViewById<View>(R.id.iptv_nav_browse).performClick()
        assertEquals("",search().text.toString())
        assertEquals(1,requests("requestIptvBrowse").size)
        assertEquals("",args("requestIptvBrowse")["query"])
    }

    @Test fun browseButtonRestoresSearchAndPostsCurrentRowFocusWithoutBrowse() {
        show()
        set("iptvSelectedCategory","Saved")
        set("iptvZapOwnsUiContext",false)
        search().requestFocus()
        assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        val list=PostProbe(activity)
        set("iptvGuideList",list)
        clearTransport()
        activity.findViewById<View>(R.id.iptv_nav_browse).performClick()
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        assertEquals("Saved",field("iptvSelectedCategory"))
        assertTrue(requests("requestIptvBrowse").isEmpty())
        assertEquals("current row focus is posted",1,list.pending.size)
    }

    @Test fun searchButtonAlreadyFocusedRestartsCommittedSearchScope() {
        show()
        search().requestFocus()
        assertTrue(search().hasFocus())
        call("commitIptvAllCategorySearch",emptyArray())
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        set("iptvSelectedCategory","Saved")
        val token=field("iptvUiContextToken") as Int
        activity.findViewById<View>(R.id.iptv_nav_search).performClick()
        assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        assertEquals("Saved",field("iptvSearchSavedCategory"))
        assertEquals(token+1,field("iptvUiContextToken"))
        assertTrue(search().hasFocus())
    }

    @Test fun favoritesButtonSelectsAvailableFavoritesSource() {
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Provider",false,false,true),IptvSourceEntry("favorites-id","Favorites",true,false,false)))
        clearTransport()
        activity.findViewById<View>(R.id.iptv_nav_favorites).performClick()
        assertEquals("favorites-id",field("iptvSourceId"))
        assertEquals("Favorites",field("iptvSourceName"))
        assertEquals(1,requests("requestIptvBrowse").size)
        assertEquals("favorites-id",args("requestIptvBrowse")["sourceId"])
        assertNull(ShadowToast.getTextOfLatestToast())
    }

    @Test fun installedNavButtonRoutesToActualPicker() {
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Provider",false,false,true)))
        val prior=org.robolectric.shadows.ShadowDialog.getLatestDialog()
        assertTrue(activity.findViewById<View>(R.id.iptv_nav_sources).performClick())
        assertNotSame("button creates a new dialog",prior,org.robolectric.shadows.ShadowDialog.getLatestDialog())
        val d=dialog()
        assertEquals("Choose source",d.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals(1,d.listView.adapter.count)
        assertEquals("Provider",d.listView.adapter.getItem(0))
    }

    @Test fun installedSourceButtonRoutesToActualPicker() {
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Provider",false,false,true)))
        val prior=org.robolectric.shadows.ShadowDialog.getLatestDialog()
        assertTrue(activity.findViewById<View>(R.id.iptv_source_button).performClick())
        assertNotSame("button creates a new dialog",prior,org.robolectric.shadows.ShadowDialog.getLatestDialog())
        val d=dialog()
        assertEquals("Choose source",d.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals(1,d.listView.adapter.count)
        assertEquals("Provider",d.listView.adapter.getItem(0))
    }

    @Test fun installedCategoryButtonRoutesToActualPicker() {
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Provider",false,false,true)))
        val prior=org.robolectric.shadows.ShadowDialog.getLatestDialog()
        assertTrue(activity.findViewById<View>(R.id.iptv_category_button).performClick())
        assertNotSame("button creates a new dialog",prior,org.robolectric.shadows.ShadowDialog.getLatestDialog())
        val d=dialog()
        assertEquals("Choose category",d.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals(listOf("All categories","News","Movies"),categoryLabels())
    }

    @Test fun setupRepaintsCurrentNameGroupAndNowLine() {
        val e=playing()
        fresh(e)
        e.epgNowTitle="Updated"
        e.epgNextTitle="Future"
        t("iptvGuideCurrentName").text="stale"
        t("iptvGuideCurrentGroup").text="stale"
        t("iptvGuideCurrentEpg").text="stale"
        v("iptvGuideNowPlaying").visibility=View.GONE
        call("setupIptvOverlay",emptyArray())
        assertEquals(e.displayName,text("iptvGuideCurrentName"))
        assertEquals("News",text("iptvGuideCurrentGroup"))
        assertEquals("Now: Updated   ›   Next: Future",text("iptvGuideCurrentEpg"))
        assertEquals(View.VISIBLE,v("iptvGuideNowPlaying").visibility)
    }

    @Test fun episodeSelectionHidesAndDisablesPagingBeforeOutgoingCheckpoint() {
        show()
        search().requestFocus()
        assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        set("iptvContentType","episodes")
        playing(entry().copy(isLive=false))
        set("iptvZapPagingActive",true)
        val atReads=mutableListOf<Pair<Boolean,Boolean>>()
        val wrapped=java.lang.reflect.Proxy.newProxyInstance(androidx.media3.exoplayer.ExoPlayer::class.java.classLoader,arrayOf(androidx.media3.exoplayer.ExoPlayer::class.java)){_,method,args -> if(method.name=="getDuration")atReads.add((field("iptvGuideVisible") as Boolean) to (field("iptvZapPagingActive") as Boolean))
        method.invoke(probe.player,*(args?:emptyArray()))} as androidx.media3.exoplayer.ExoPlayer
        set("player",wrapped)
        val e=entry(false).copy(isLive=false)
        clickRow(e)
        assertTrue("outgoing VOD checkpoint reads its duration",atReads.isNotEmpty())
        assertEquals("adapter hide and paging reset precede navigator checkpoint",false to false,atReads.first())
    }
}
