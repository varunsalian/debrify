package com.debrify.app.tv

import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistTabCharacterizationTest : TvPhase13OriginalTest() {
    @Test fun seasonSelectionDefaultDispatcherAndExplicitNoScrollKeepPayloadUntouched() {
        val adapter=playlist().adapter as PlaylistAdapter
        defaultCall("selectSeasonTab",arrayOf(intType,PlaylistAdapter::class.java,boolType),4,1,adapter,false)
        assertEquals(listOf(false,true),seasonTabs().map{it.isSelected});assertEquals(1,adapter.itemCount)
        call("selectSeasonTab",arrayOf(intType,PlaylistAdapter::class.java,boolType),0,adapter,false)
        assertEquals(listOf(true,false),seasonTabs().map{it.isSelected});assertEquals(2,adapter.itemCount);assertEquals(0,field("currentIndex"))
    }
    @Test fun createSeasonTabCallbackUsesItsLiveIndexAndIgnoresRemovedTab() {
        val a=playlist().adapter as PlaylistAdapter
        val tab=call("createSeasonTab",arrayOf(stringType,Int::class.javaObjectType,PlaylistAdapter::class.java),"Custom",2,a) as android.widget.TextView
        assertEquals("Custom",tab.text.toString());seasonTabs().add(tab)
        tab.performClick();assertTrue(tab.isSelected);assertEquals(5,a.itemCount)
        seasonTabs().remove(tab);val before=a.itemCount;tab.performClick();assertEquals(before,a.itemCount)
    }
    @Test fun emptySeasonListClearsTabsAndHidesRail() {
        val items=model().items.map{it.copy(season=null)}
        val a=PlaylistAdapter(items){ }
        call("setupSeasonTabs",arrayOf(PlaylistAdapter::class.java),a)
        assertTrue(seasonTabs().isEmpty());assertEquals(0,tabs().childCount);assertEquals(View.GONE,tabs().visibility)
        call("setupSeasonTabs",arrayOf(PlaylistAdapter::class.java),field("seriesPlaylistAdapter") as PlaylistAdapter)
        assertEquals(View.VISIBLE,tabs().visibility);assertEquals(2,tabs().childCount);assertEquals(2,seasonTabs().size)
    }
    @Test fun seriesSetupAssignsOnlySeriesAdaptersAndRetainsStandaloneGroupState() {
        collection();val old=field("movieGroups")
        call("setupSeriesPlaylist",arrayOf(listType),model().items)
        assertEquals(PlaylistMode.SERIES,field("playlistMode"));assertSame(field("seriesPlaylistAdapter"),playlist().adapter);assertNull(field("moviePlaylistAdapter"));assertSame(old,field("movieGroups"))
        val copy=PlaylistAdapter(model().items.toList()){}
        set("currentIndex",2);call("setupSeasonTabs",arrayOf(PlaylistAdapter::class.java),copy)
        assertEquals(listOf(false,true),seasonTabs().map{it.isSelected})
        set("currentIndex",99);call("setupSeasonTabs",arrayOf(PlaylistAdapter::class.java),copy)
        assertEquals(listOf(true,false),seasonTabs().map{it.isSelected})
        set("currentIndex",0);model().items[0]=model().items[0].copy(season=99)
        call("setupSeasonTabs",arrayOf(PlaylistAdapter::class.java),copy);assertEquals(listOf(true,false),seasonTabs().map{it.isSelected})
        set("payload",null);call("setupSeasonTabs",arrayOf(PlaylistAdapter::class.java),copy)
        assertEquals(listOf(true,false),seasonTabs().map{it.isSelected})
    }
    @Test fun collectionSetupAndEmptyTabsClearPriorSeasonRail() {
        model().collectionGroups=listOf(org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(0,1))),org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(2))))
        call("setupCollectionPlaylist",arrayOf(listType),model().items)
        assertEquals(PlaylistMode.COLLECTION,field("playlistMode"));assertSame(field("moviePlaylistAdapter"),playlist().adapter);assertNull(field("seriesPlaylistAdapter"));assertNotNull(field("movieGroups"));assertTrue(seasonTabs().isEmpty())
        assertEquals(2,movieTabs().size);assertEquals(2,tabs().childCount)
        movieTabs().forEachIndexed{i,tab->assertSame(tab.view,tabs().getChildAt(i));assertSame(tabs(),tab.view.parent)}
        val groups=MovieGroups(emptyList());val a=MoviePlaylistAdapter(model().items,groups){}
        call("setupCollectionTabs",arrayOf(MoviePlaylistAdapter::class.java,MovieGroups::class.java),a,groups)
        assertTrue(movieTabs().isEmpty());assertEquals(View.GONE,tabs().visibility);assertEquals(0,tabs().childCount)
    }
    @Test fun movieTabCallbackAndDefaultDispatcherPinGroupAndForceFlag() {
        collection(listOf(org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(0,1))),org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(2)))))
        val a=playlist().adapter as MoviePlaylistAdapter
        val tab=call("createMovieTab",arrayOf(stringType,intType,stringType,MoviePlaylistAdapter::class.java),"Custom",1,"Group",a) as android.widget.TextView
        assertEquals("Custom",tab.text.toString())
        tab.performClick();assertEquals(1,a.itemCount);assertTrue(movieTabs()[1].view.isSelected)
        defaultCall("selectMovieTab",arrayOf(intType,MoviePlaylistAdapter::class.java,boolType,boolType),12,0,a,false,true)
        assertEquals(2,a.itemCount);assertTrue(movieTabs()[0].view.isSelected)
    }
    @Test fun seriesAlignmentRejectsInvalidSeasonIndexAndMissingAdapter() {
        val a=playlist().adapter as PlaylistAdapter
        seasonTabs()[1].performClick();model().items[0]=model().items[0].copy(season=0)
        call("alignSeriesTabsForCurrentEpisode",emptyArray());assertTrue(seasonTabs()[1].isSelected);assertEquals(1,a.itemCount)
        model().items[0]=model().items[0].copy(season=99);call("alignSeriesTabsForCurrentEpisode",emptyArray());assertTrue(seasonTabs()[1].isSelected)
        model().items[0]=model().items[0].copy(season=null);call("alignSeriesTabsForCurrentEpisode",emptyArray());assertTrue(seasonTabs()[1].isSelected)
        set("currentIndex",99);call("alignSeriesTabsForCurrentEpisode",emptyArray());assertTrue(seasonTabs()[1].isSelected)
        set("seriesPlaylistAdapter",null);call("alignSeriesTabsForCurrentEpisode",emptyArray());assertTrue(seasonTabs()[1].isSelected)
        seasonTabs().clear();call("alignSeriesTabsForCurrentEpisode",emptyArray());assertTrue(seasonTabs().isEmpty())
    }
    @Test fun movieAlignmentRejectsMissingGroupsAdapterAndUngroupedIndex() {
        collection(listOf(org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(0,1))),org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(2)))))
        movieTabs()[1].view.performClick();set("currentIndex",99);call("alignMovieTabsForCurrentItem",emptyArray());assertTrue(movieTabs()[1].view.isSelected)
        set("movieGroups",null);call("alignMovieTabsForCurrentItem",emptyArray());assertTrue(movieTabs()[1].view.isSelected)
        set("moviePlaylistAdapter",null);call("alignMovieTabsForCurrentItem",emptyArray());assertTrue(movieTabs()[1].view.isSelected)
    }
    @Test fun classicGuideGetterAndGuardedMethodsPreserveOriginalViewsAndStyle() {
        assertNull(call("getGuideOverlayLayoutRes",emptyArray()))
        assertEquals(com.debrify.app.R.layout.item_android_tv_playlist_entry_horizontal,call("getGuideItemLayoutRes",emptyArray()))
        val original=playlist();val manager=original.layoutManager;val tab=seasonTabs()[0];val background=tab.background
        assertNotNull("classic tab keeps its legacy background",background)
        call("bindGuideSkinViews",emptyArray());call("applyGuideLayoutManager",emptyArray());call("applyGuideKeyOverride",emptyArray())
        call("applyGuideTabStyle",arrayOf(android.widget.TextView::class.java),tab)
        assertSame(manager,original.layoutManager);assertSame(background,tab.background);assertNull(field("gdShowTitle"));assertSame(original,playlist())
        call("setupPlaylistNavigation",emptyArray());set("playlistVisible",true)
        assertFalse(key(android.view.KeyEvent.KEYCODE_DPAD_UP));assertTrue(key(android.view.KeyEvent.KEYCODE_DPAD_RIGHT))
    }
}
