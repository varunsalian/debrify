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
internal class TvIptvContextCharacterizationTest : TvPhase11OriginalTest() {
    @Test fun searchInvalidatesAllOwnersBeforeBrowse() {
        queue().add(1);set("iptvZapRequestInFlight",true)
        val before=listOf("iptvUiContextToken","iptvBrowseToken","iptvZapRequestToken").associateWith{field(it) as Int}
        call("beginIptvAllCategorySearch",emptyArray())
        before.forEach{(n,v)->assertEquals(n,v+1,field(n))};assertFalse(field("iptvZapRequestInFlight") as Boolean);assertTrue(queue().isEmpty());assertFalse(field("iptvZapOwnsUiContext") as Boolean)
        assertNull(field("iptvSelectedCategory"));assertEquals("News",field("iptvSearchSavedCategory"));assertEquals(2,(field("iptvSearchSavedChannels") as List<*>).size)
        browse("alpha");assertNull(args("requestIptvBrowse")["category"])

    }
    @Test fun physicalZapRestoresPlaybackSourceFromBrowsingScope() {
        call("beginIptvAllCategorySearch",emptyArray());set("iptvSourceId","other");set("iptvSourceName","Other");search().setText("stale")
        set("iptvZapPagingActive",false);key(KeyEvent.KEYCODE_CHANNEL_UP)
        assertEquals("provider",field("iptvSourceId"));assertEquals("Provider",field("iptvSourceName"));assertEquals("News",field("iptvSelectedCategory"));assertEquals("",search().text.toString())
        assertTrue(field("iptvZapOwnsUiContext") as Boolean);assertFalse(field("iptvAllCategorySearchActive") as Boolean)

    }
    @Test fun bootstrapAnchoredPageInstallsPlayingIdentity() {
        val playing=channels().first();call("bootstrapInitialIptvZapPaging",arrayOf(IptvChannelEntry::class.java),playing)
        assertEquals(playing.url,args("requestIptvBrowse")["anchorUrl"])
        reply(value=response("channels" to listOf(rawChannel(),rawChannel("Beta",2)),"pageOffset" to 20,"totalChannels" to 22))
        assertTrue(field("iptvZapPagingActive") as Boolean);assertEquals(20,channels().first().index);assertEquals(0,field("currentIptvIndex"));assertEquals(22,field("iptvZapCategoryTotal"))

    }
    @Test fun bootstrapMissingPlayingChannelLeavesWindowUntouched() {
        val playing=channels().first();val old=channels().toList()
        call("bootstrapInitialIptvZapPaging",arrayOf(IptvChannelEntry::class.java),playing)
        reply(value=response("channels" to listOf(rawChannel("Unrelated",9))))
        assertFalse(field("iptvZapPagingActive") as Boolean);assertEquals(old,channels())

    }
    @Test fun liveSelectionFailureRestoresNormalizedBrowseFallback() {
        val chosen=channel(url="https://choice.invalid").copy(index=42,logoUrl=null);val other=channel(url="https://other.invalid").copy(index=88,logoUrl=null)
        adapter().updateChannels(mutableListOf(other,chosen))
        call("beginIptvCategoryZapSession",arrayOf(IptvChannelEntry::class.java),chosen)
        val request=messenger.requests.indexOfLast{it.call.method=="requestIptvBrowse"};reply("error",request=request)
        assertFalse(field("iptvZapPagingActive") as Boolean);assertEquals(listOf(0,1),channels().map{it.index});assertEquals(1,field("currentIptvIndex"));assertTrue(channels()[1].isCurrent);assertFalse(field("iptvGuideUsesZapWindow") as Boolean)

    }
    @Test fun vodPlayEntryUsesChannelStartAndTitle() {
        val vod=channel(live=false).copy(name="VOD",logoUrl=null);set("iptvChannels",mutableListOf(vod));set("currentIptvIndex",0)
        call("playIptvChannel",arrayOf(intType),0)
        assertEquals("VOD",(field("titleView") as TextView).text.toString());assertTrue("channel start sets media",tuning().any{it.contains(vod.url)})
        clearTransport();call("playIptvChannel",arrayOf(intType),-1);assertTrue(tuning().isEmpty())

    }
}
