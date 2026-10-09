package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistStateCharacterizationTest : TvPhase13OriginalTest() {
    @Test fun originalBootstrapInstallsSeriesAdaptersAndSeasonSelection() {
        assertEquals(PlaylistMode.SERIES,field("playlistMode"))
        assertSame(field("playlistAdapter"),playlist().adapter)
        assertSame(field("seriesPlaylistAdapter"),playlist().adapter)
        assertNull(field("moviePlaylistAdapter"));assertNull(field("movieGroups"))
        assertEquals(listOf("S1","S2"),seasonTabs().map{it.text.toString()})
        assertEquals(listOf(true,false),seasonTabs().map{it.isSelected})
        assertEquals(View.GONE,overlay().visibility);assertFalse(field("playlistVisible") as Boolean)
        val manager=playlist().layoutManager as androidx.recyclerview.widget.LinearLayoutManager
        assertEquals(androidx.recyclerview.widget.LinearLayoutManager.HORIZONTAL,manager.orientation)
        assertTrue(manager.isItemPrefetchEnabled);assertEquals(4,manager.initialPrefetchItemCount)
        assertNull(playlist().itemAnimator)
        val recycler=org.robolectric.util.ReflectionHelpers.getField<Any>(playlist(),"mRecycler")
        assertEquals(10,org.robolectric.util.ReflectionHelpers.getField<Int>(recycler,"mRequestedCacheMax"))
        assertEquals(android.view.ViewGroup.FOCUS_AFTER_DESCENDANTS,playlist().descendantFocusability)
        overlay().visibility=View.VISIBLE;playlist().descendantFocusability=android.view.ViewGroup.FOCUS_BEFORE_DESCENDANTS
        call("setupPlaylist",emptyArray())
        assertEquals(View.GONE,overlay().visibility);assertEquals(android.view.ViewGroup.FOCUS_AFTER_DESCENDANTS,playlist().descendantFocusability)
    }
    @Test fun seasonTabClickFiltersThenOpenAlignsCurrentSeasonWithoutChangingCurrentIndex() {
        val original=model().items.toList()
        seasonTabs()[1].performClick()
        assertEquals(listOf(false,true),seasonTabs().map{it.isSelected})
        val adapter=playlist().adapter as PlaylistAdapter
        assertEquals(1,adapter.itemCount)
        assertEquals(0,field("currentIndex"))
        open()
        assertEquals(listOf(true,false),seasonTabs().map{it.isSelected})
        assertEquals(2,adapter.itemCount)
        assertEquals(original,model().items)
    }
    @Test fun rebuildClearsOldStateBeforeSingleStreamEarlyReturn() {
        val fullModel=model()
        set("movieGroups",MovieGroups(listOf(CollectionGroup("Stale",listOf(0)))))
        set("payload",model().copy(items=mutableListOf(model().items[0])))
        rebuild()
        assertEquals(PlaylistMode.NONE,field("playlistMode"));assertNull(playlist().adapter)
        assertNull(field("playlistAdapter"));assertNull(field("seriesPlaylistAdapter"));assertNull(field("moviePlaylistAdapter"));assertNull(field("movieGroups"))
        assertTrue(seasonTabs().isEmpty());assertTrue(movieTabs().isEmpty());assertEquals(0,tabs().childCount)
        assertEquals(View.GONE,tabs().visibility)
        set("payload",fullModel)
        collection(listOf(JSONObject().put("fileIndices",JSONArray(listOf(0,1))),JSONObject().put("fileIndices",JSONArray(listOf(2)))))
        assertNotNull(field("moviePlaylistAdapter"));assertEquals(2,movieTabs().size)
        set("payload",fullModel.copy(items=mutableListOf(fullModel.items[0])));rebuild()
        assertNull(field("moviePlaylistAdapter"));assertTrue(movieTabs().isEmpty());assertNull(field("movieGroups"));assertEquals(0,tabs().childCount)
    }
    @Test fun nullPayloadRebuildRetainsExistingAdapterAndTabs() {
        val adapter=playlist().adapter;val tab=seasonTabs()[0]
        set("payload",null);rebuild()
        assertSame(adapter,playlist().adapter);assertSame(tab,seasonTabs()[0]);assertEquals(PlaylistMode.SERIES,field("playlistMode"))
    }
    @Test fun singleGuideEpisodeRequiresResolverAndSeriesContentTogether() {
        val one=model().copy(items=mutableListOf(model().items[0]))
        one.guideEpisodes.add(GuideEpisode(season=1,episode=2,title="Absent",artwork=null,description=null,rating=null,runtime=null,resumePositionMs=null,durationMs=null,trackerProgressPercent=null,watched=false))
        set("payload",one);set("hasPlaylistResolver",true);rebuild()
        assertEquals(PlaylistMode.SERIES,field("playlistMode"));assertEquals(2,playlist().adapter?.itemCount)
        one.contentType="single";rebuild();assertNull(playlist().adapter)
        one.contentType="series";set("hasPlaylistResolver",false);rebuild();assertNull(playlist().adapter)
        set("hasPlaylistResolver",true);one.guideEpisodes.clear();rebuild();assertNull(playlist().adapter)
    }
    @Test fun movieTabsUseUppercaseNamesCountsAndGroupFiltering() {
        collection(listOf(JSONObject().put("name","main").put("fileIndices",JSONArray(listOf(1,0))),JSONObject().put("name","extra").put("fileIndices",JSONArray(listOf(2)))))
        assertEquals(PlaylistMode.COLLECTION,field("playlistMode"));assertNull(field("seriesPlaylistAdapter"))
        assertSame(field("moviePlaylistAdapter"),playlist().adapter)
        assertEquals(listOf("MAIN (2)","EXTRA (1)"),movieTabs().map{it.view.text.toString()})
        assertEquals(listOf(true,false),movieTabs().map{it.view.isSelected})
        assertEquals(2,playlist().adapter?.itemCount)
        movieTabs()[1].view.performClick()
        assertEquals(listOf(false,true),movieTabs().map{it.view.isSelected});assertEquals(1,playlist().adapter?.itemCount)
        set("currentIndex",1);open();assertEquals(listOf(true,false),movieTabs().map{it.view.isSelected});assertEquals(2,playlist().adapter?.itemCount)
    }
    @Test fun movieSingleAndEmptyGroupsHideTabsAndForceFirstGroup() {
        collection(listOf(JSONObject().put("fileIndices",JSONArray(listOf(1,0)))))
        assertEquals(View.GONE,tabs().visibility);assertTrue(movieTabs().isEmpty());assertTrue(seasonTabs().isEmpty());assertEquals(2,playlist().adapter?.itemCount)
        collection(listOf(JSONObject().put("fileIndices",JSONArray(listOf(0,1))),JSONObject().put("fileIndices",JSONArray(listOf(2)))))
        assertEquals(View.VISIBLE,tabs().visibility);assertEquals(2,movieTabs().size)
        collection(listOf(JSONObject().put("fileIndices",JSONArray())))
        assertEquals(View.GONE,tabs().visibility);assertTrue(movieTabs().isEmpty());assertEquals(0,playlist().adapter?.itemCount)
        val single=MovieGroups(listOf(CollectionGroup("Single",listOf(0,1))))
        val adapter=MoviePlaylistAdapter(model().items,single){}
        var refreshes=0
        adapter.registerAdapterDataObserver(object: androidx.recyclerview.widget.RecyclerView.AdapterDataObserver(){override fun onChanged(){refreshes++}})
        call("setupCollectionTabs",arrayOf(MoviePlaylistAdapter::class.java,MovieGroups::class.java),adapter,single)
        assertEquals("single-group setup refreshes even the initially selected group",1,refreshes)
        assertEquals(2,adapter.itemCount)
    }
    @Test fun payloadGroupsPreserveOrderDefaultNameAndDropEmptyGroups() {
        model().collectionGroups=listOf(JSONObject().put("fileIndices",JSONArray(listOf(2,0))),JSONObject().put("name","empty"),JSONObject().put("name","tail").put("fileIndices",JSONArray(listOf(1))))
        assertEquals(listOf(CollectionGroup("Group",listOf(2,0)),CollectionGroup("tail",listOf(1))),group(model().items).groups)
        assertTrue(group(emptyList()).groups.isEmpty())
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").any{it.msg=="Using 2 collection groups from payload"})
    }
    @Test fun fallbackGroupsPinFortyPercentBoundaryYearAndSizeOrdering() {
        set("payload",model().copy(collectionGroups=null))
        val items=listOf(p2Item("Old 1999").copy(sizeBytes=80L),p2Item("New 2002").copy(sizeBytes=100L),p2Item("Edge").copy(sizeBytes=40L),p2Item("Extra 39").copy(sizeBytes=39L),p2Item("Extra 10").copy(sizeBytes=10L))
        assertEquals(listOf(CollectionGroup("Main",listOf(0,1,2)),CollectionGroup("Extras",listOf(4,3))),group(items).groups)
        assertEquals(listOf(CollectionGroup("Main",listOf(1,0,2))),group(listOf(p2Item("Unknown").copy(sizeBytes=null),p2Item("Zero").copy(sizeBytes=0L),p2Item("Negative").copy(sizeBytes=-1L))).groups)
        assertEquals(listOf(CollectionGroup("Main",listOf(1,0))),group(listOf(p2Item("Older 1899").copy(sizeBytes=80L),p2Item("Future 2100").copy(sizeBytes=100L))).groups)
        assertEquals(listOf(CollectionGroup("Main",listOf(1,0))),group(listOf(p2Item("Older 1899").copy(sizeBytes=80L),p2Item("Known 2000").copy(sizeBytes=100L))).groups)
        assertEquals(listOf(CollectionGroup("Main",listOf(1,0))),group(listOf(p2Item("Known 2000").copy(sizeBytes=80L),p2Item("Future 2100").copy(sizeBytes=100L))).groups)
        assertEquals(listOf(CollectionGroup("Main",listOf(1,0))),group(listOf(p2Item("Embedded X1999Y").copy(sizeBytes=80L),p2Item("Known 2000").copy(sizeBytes=100L))).groups)
        assertEquals(listOf(CollectionGroup("Main",listOf(1,0))),group(listOf(p2Item("Same 2001").copy(sizeBytes=80L),p2Item("Same 2001 again").copy(sizeBytes=100L))).groups)
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").any{it.msg=="Computed 2 collection groups (fallback)"})
    }
    @Test fun seriesNavigationUsesSparseFlutterMapsExactly() {
        model().nextEpisodeMap=mapOf(0 to 2);model().prevEpisodeMap=mapOf(2 to 0)
        assertEquals(2,next(0));assertNull(next(1));assertEquals(0,prev(2));assertNull(prev(1))
        val logs=org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").map{it.msg}
        assertTrue(logs.contains("getNextPlayableIndex - series mode, fromIndex: 0, nextIndex: 2"))
        assertTrue(logs.contains("getPrevPlayableIndex - series mode, fromIndex: 2, prevIndex: 0"))
    }
    @Test fun collectionNavigationStaysInsideOrderedGroupAndPinsEnds() {
        org.robolectric.shadows.ShadowLog.clear()
        collection(listOf(JSONObject().put("fileIndices",JSONArray(listOf(2,0))),JSONObject().put("fileIndices",JSONArray(listOf(1)))))
        assertEquals(0,next(2));assertNull(next(0));assertEquals(2,prev(0));assertNull(prev(2));assertNull(next(1));assertNull(prev(1));assertNull(next(7));assertNull(prev(7))
        set("movieGroups",null);assertNull(next(0));assertNull(prev(1))
        val logs=org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").map{it.msg}
        assertFalse(logs.any{it.startsWith("getNextPlayableIndex - series mode") || it.startsWith("getPrevPlayableIndex - series mode")})
    }
    @Test fun sequentialNavigationPinsOriginalBoundsAndNullPayload() {
        org.robolectric.shadows.ShadowLog.clear()
        set("playlistMode",PlaylistMode.NONE)
        assertEquals(1,next(0));assertNull(next(2));assertEquals(0,prev(1));assertNull(prev(0))
        set("payload",null);assertNull(next(0));assertNull(prev(1))
        val logs=org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").map{it.msg}
        assertFalse(logs.any{it.startsWith("getNextPlayableIndex - series mode") || it.startsWith("getPrevPlayableIndex - series mode")})
    }
    @Test fun showGuardAndHidePinVisibilityWithoutClearingPendingWork() {
        set("playlistMode",PlaylistMode.NONE);showPlaylist()
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("PlaylistNav").any{it.msg=="showPlaylist: Starting - playlistMode=NONE"})
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("PlaylistNav").any{it.msg=="showPlaylist: Exiting early - no playlist adapter"})
        assertFalse(field("playlistVisible") as Boolean);assertEquals(View.GONE,overlay().visibility)
        set("playlistMode",PlaylistMode.SERIES);val adapter=field("playlistAdapter");set("playlistAdapter",null);showPlaylist();assertFalse(field("playlistVisible") as Boolean)
        set("playlistAdapter",adapter);showPlaylist();assertTrue(field("playlistVisible") as Boolean);assertEquals(View.VISIBLE,overlay().visibility)
        set("isNavigating",true);set("navigationTargetPosition",8)
        hidePlaylist();assertFalse(field("playlistVisible") as Boolean);assertEquals(View.GONE,overlay().visibility);assertTrue(navigating());assertEquals(8,target())
    }
    @Test fun seasonTabLegacyGeometryAndTextRemainPinned() {
        val t=seasonTabs()[0]
        assertEquals("S1",t.text.toString());assertEquals(13f,t.textSize/activity.resources.displayMetrics.scaledDensity,0.01f)
        assertEquals(listOf(28,14,28,14),listOf(t.paddingLeft,t.paddingTop,t.paddingRight,t.paddingBottom));assertEquals(0xFFFFFFFF.toInt(),t.currentTextColor)
        assertTrue(t.isFocusable);assertTrue(t.isFocusableInTouchMode);assertEquals(4f,t.elevation,0f);assertEquals(0.04f,t.letterSpacing,0f)
        val lp=t.layoutParams as android.widget.LinearLayout.LayoutParams;assertEquals(10,lp.marginEnd);assertEquals(-2,lp.width);assertEquals(-2,lp.height)
    }
}
