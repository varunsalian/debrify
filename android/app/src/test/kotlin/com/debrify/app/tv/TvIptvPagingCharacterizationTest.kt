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
internal class TvIptvPagingCharacterizationTest : TvPhase11OriginalTest() {
    private fun window(n:Int=30,offset:Int=200,current:Int=15,total:Int=1000) {
        set("iptvZapPagingActive",true)
        val entries=MutableList(n) { i->channel(url="https://phase11.invalid/$i").copy(index=offset+i,isCurrent=i==current,logoUrl=null) }
        set("iptvChannels",entries);set("iptvBrowseChannels",entries.toMutableList());set("currentIptvIndex",current)
        set("iptvZapCategoryTotal",total);set("iptvGuideUsesZapWindow",true);adapter().updateChannels(entries);clearTransport()
    }
    private fun merge(entries:MutableList<IptvChannelEntry>,offset:Int,category:String?="News") =
        call("mergeIptvZapPage",arrayOf(MutableList::class.java,intType,intType,stringType,listType),entries,offset,1000,category,listOf("News","Movies"))
    @Test fun pagePayloadPinsAnchorOffsetAndLimit() {
        val anchor=channels().first();page(offset=-7,anchor=anchor,fromEnd=true){_,_,_,_,_->}
        assertEquals(mapOf("action" to "zapPage","sourceId" to "provider","contentType" to "live","category" to "News","query" to "","offset" to 0,"limit" to 200,"anchorUrl" to anchor.url,"anchorName" to anchor.name,"fromEnd" to true),args("requestIptvBrowse"))

    }
    @Test fun pageFlightGuardPreventsDuplicateRequest() {
        page {_,_,_,_,_->};val token=field("iptvZapRequestToken")
        page {_,_,_,_,_->};assertEquals(1,requests("requestIptvBrowse").size);assertEquals(token,field("iptvZapRequestToken"))

    }
    @Test fun pageAbsentBridgeFailsInlineWithoutToken() {
        val old=com.debrify.app.MainActivity.getAndroidTvPlayerChannel();val token=field("iptvZapRequestToken");var failed=0
        try { com.debrify.app.MainActivity.setAndroidTvPlayerChannel(null);page(failure={failed++}){_,_,_,_,_->fail("no loaded callback")};assertEquals(1,failed);assertEquals(token,field("iptvZapRequestToken"));assertFalse(field("iptvZapRequestInFlight") as Boolean) }
        finally { com.debrify.app.MainActivity.setAndroidTvPlayerChannel(old) }

    }
    @Test fun pageResponseClampsAndPublishesBothSourceOwners() {
        var observed:List<Any?>?=null
        page { ch,offset,total,category,cats->observed=listOf(ch.single().name,offset,total,category,cats) }
        reply(value=response("sourceId" to "new","sourceName" to "New","contentType" to "vod","pageOffset" to -1,"totalChannels" to -2,"categories" to listOf("",3,"Movies")))
        assertEquals(listOf("Reply",0,0,"News",listOf("Movies")),observed)
        for(name in listOf("iptvSourceId","iptvZapSourceId"))assertEquals("new",field(name))
        for(name in listOf("iptvSourceName","iptvZapSourceName"))assertEquals("New",field(name))
        for(name in listOf("iptvContentType","iptvZapContentType"))assertEquals("vod",field(name))

    }
    @Test fun installPinsAbsoluteIndicesAndIdentity() {
        val playing=channels().first();val entries=mutableListOf(playing.copy(name="renamed",isCurrent=false),playing.copy(isCurrent=false))
        install(entries,40,300)
        assertEquals(listOf(40,41),channels().map{it.index});assertEquals(listOf(false,true),channels().map{it.isCurrent})
        assertEquals(1,field("currentIptvIndex"));assertEquals(300,field("iptvZapCategoryTotal"));assertTrue(field("iptvGuideUsesZapWindow") as Boolean)

    }
    @Test fun mergeReplacesOverlapSortedAndKeepsCurrentIdentity() {
        window(n=3,current=1);val playing=channels()[1];val replacement=playing.copy(isCurrent=false)
        merge(mutableListOf(replacement,channel(url="https://new.invalid").copy(name="New",logoUrl=null)),201)
        assertEquals(listOf(200,201,202),channels().map{it.index});assertSame(replacement,channels()[1]);assertTrue(replacement.isCurrent)
        assertEquals("New",channels()[2].name);assertEquals(1,field("currentIptvIndex"))

    }
    @Test fun mergeRejectsOtherCategory() {
        window();val original=channels().toList();merge(mutableListOf(channel()),0,"Movies");assertEquals(original,channels())

    }
    @Test fun hiddenWindowBoundsAndGuideRetention() {
        window(n=800,offset=0,current=400);val all=channels()
        set("iptvGuideVisible",true);assertSame(all,call("boundedHiddenIptvZapWindow",arrayOf(MutableList::class.java),all))
        set("iptvGuideVisible",false)
        val bounded=call("boundedHiddenIptvZapWindow",arrayOf(MutableList::class.java),all) as List<*>
        assertEquals(600,bounded.size);assertEquals(100,(bounded.first() as IptvChannelEntry).index);assertEquals(699,(bounded.last() as IptvChannelEntry).index)

    }
    @Test fun prefetchForwardPinsTwelveRowBoundary() {
        window(current=17);prefetch(1);assertTrue(requests("requestIptvBrowse").isEmpty())
        set("currentIptvIndex",18);prefetch(1);assertEquals(230,args("requestIptvBrowse")["offset"])

    }
    @Test fun prefetchBackwardPinsTwelveRowBoundary() {
        window(current=12);prefetch(-1);assertTrue(requests("requestIptvBrowse").isEmpty())
        set("currentIptvIndex",11);prefetch(-1);assertEquals(0,args("requestIptvBrowse")["offset"])

    }
    @Test fun forcedPrefetchBypassesDistanceOnly() {
        window(current=0);prefetch(1,true);assertEquals(230,args("requestIptvBrowse")["offset"])
        set("iptvZapRequestInFlight",false);clearTransport();set("iptvZapCategoryTotal",230);prefetch(1,true);assertTrue(requests("requestIptvBrowse").isEmpty())

    }
    @Test fun pendingInputsNormalizeAndBoundAtTwentyFour() {
        for(i in 0..30)call("queuePendingIptvZapInput",arrayOf(intType),if(i==0)0 else -1)
        assertEquals(24,queue().size);assertEquals(1,queue().first);assertTrue(queue().drop(1).all{it==-1})

    }
    @Test fun drainIsFifoAndResetsReentrancyWhenPageStarts() {
        window(n=2,offset=0,current=0);queue().add(1);queue().add(-1)
        call("drainPendingIptvZapInputs",emptyArray())
        assertFalse(field("iptvZapDrainingInputs") as Boolean);assertEquals(1,field("currentIptvIndex"));assertEquals(listOf(-1),queue().toList());assertTrue(field("iptvZapRequestInFlight") as Boolean)

    }
    @Test fun drainReentrantCallLeavesQueueAlone() {
        set("iptvZapDrainingInputs",true);queue().add(1)
        call("drainPendingIptvZapInputs",emptyArray());assertEquals(listOf(1),queue().toList());assertTrue(field("iptvZapDrainingInputs") as Boolean)

    }
    @Test fun disableInvalidatesAndReplacesBorrowedCache() {
        window();queue().add(1);set("iptvZapRequestInFlight",true);val cached=mutableListOf(channel());set("iptvZapCachedChannels",cached)
        val token=field("iptvZapRequestToken") as Int;call("disableIptvZapPaging",emptyArray())
        assertEquals(token+1,field("iptvZapRequestToken"));assertFalse(field("iptvZapPagingActive") as Boolean);assertFalse(field("iptvZapRequestInFlight") as Boolean);assertTrue(queue().isEmpty())
        assertEquals(1,cached.size);assertTrue((field("iptvZapCachedChannels") as List<*>).isEmpty());assertNotSame(cached,field("iptvZapCachedChannels"))

    }
    @Test fun adjacentCategoryWrapsDistinctOrderAndAttemptBounds() {
        set("iptvZapCategory","News");set("iptvZapCategories",mutableListOf("News","Movies","Sports","News"))
        assertEquals("Sports",call("adjacentIptvCategory",arrayOf(intType,intType),-1,1));assertEquals("Movies",call("adjacentIptvCategory",arrayOf(intType,intType),1,1))
        assertEquals("News",call("adjacentIptvCategory",arrayOf(intType,intType),1,3));assertNull(call("adjacentIptvCategory",arrayOf(intType,intType),1,4))

    }
    @Test fun adjacentPrefetchRejectsChangedOriginAtReplyTime() {
        window(n=2,offset=0,current=1,total=2)
        call("prefetchAdjacentIptvCategory",arrayOf(intType,intType),1,1);assertEquals("Movies",args("requestIptvBrowse")["category"])
        set("iptvZapCategory","Sports");reply(value=response("selectedCategory" to "Movies"))
        assertTrue((field("iptvZapCachedChannels") as List<*>).isEmpty())

    }
    @Test fun cachedBoundaryInstallsTotalAndKeepsDetachedSnapshot() {
        window(n=2,offset=0,current=1,total=2);val cached=mutableListOf(channel(url="https://cache.invalid/0").copy(logoUrl=null),channel(url="https://cache.invalid/1").copy(logoUrl=null))
        set("iptvZapCachedOriginCategory","News");set("iptvZapCachedDirection",1);set("iptvZapCachedChannels",cached);set("iptvZapCachedTotal",2);set("iptvZapCachedCategory","Movies")
        assertEquals(true,call("consumeCachedAdjacentIptvCategory",arrayOf(intType),1));assertEquals(2,field("iptvZapCategoryTotal"));assertEquals("Movies",field("iptvZapCategory"));assertEquals(cached[0].url,channels()[field("currentIptvIndex") as Int].url);assertEquals(2,cached.size)

    }
    @Test fun cachedBoundaryRejectsWrongDirection() {
        set("iptvZapCachedOriginCategory","News");set("iptvZapCachedDirection",-1);set("iptvZapCachedChannels",mutableListOf(channel()))
        assertEquals(false,call("consumeCachedAdjacentIptvCategory",arrayOf(intType),1));assertEquals(2,channels().size)

    }
    @Test fun uncategorizedReverseWrapRequestsLastPage() {
        window();set("iptvZapCategory",null);set("iptvZapCategories",mutableListOf<String>())
        call("requestAdjacentIptvCategory",arrayOf(intType,intType),-1,1)
        assertNull(args("requestIptvBrowse")["category"]);assertEquals(true,args("requestIptvBrowse")["fromEnd"])

    }
    @Test fun channelNumberFoundInstallsWindowAndSelectedTarget() {
        jump(7);reply(value=response("channels" to listOf(rawChannel("First",3),rawChannel("Target",7)),"sourceId" to "new","sourceName" to "New","pageOffset" to 40,"totalChannels" to 42))
        assertEquals("Target",channels()[field("currentIptvIndex") as Int].name);assertEquals(1,field("currentIptvIndex"));assertEquals(listOf(40,41),channels().map{it.index})
        assertEquals("new",field("iptvSourceId"));assertEquals("new",field("iptvZapSourceId"));assertTrue(field("iptvZapPagingActive") as Boolean)

    }
}
