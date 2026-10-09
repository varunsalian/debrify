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
internal class TvIptvGuidePickerReplyCharacterizationTest : TvPhase12OriginalTest() {

    @Test fun membershipInlineAfterDestroyIsStillUnguarded() {
        seedLists(listOf(IptvListEntry("favorites","Favorites",true)))
        lists(entry())
        val list=dialogList()
        val d=dialog()
        destroyNow()
        reply(value=listOf("favorites"),queued=false,request=requestIndex("getIptvChannelListMembership"))
        idle()
        assertEquals(1,list.adapter!!.itemCount)
        assertTrue(descendants<TextView>(d.window!!.decorView).any{it.text.toString()=="Pick the lists this channel belongs to"})
    }

    @Test fun membershipQueuedAfterDestroyIsStillUnguarded() {
        seedLists(listOf(IptvListEntry("favorites","Favorites",true)))
        lists(entry())
        val list=dialogList()
        val d=dialog()
        destroyNow()
        reply(value=listOf("favorites"),queued=true,request=requestIndex("getIptvChannelListMembership"))
        idle()
        assertEquals(1,list.adapter!!.itemCount)
        assertTrue(descendants<TextView>(d.window!!.decorView).any{it.text.toString()=="Pick the lists this channel belongs to"})
    }

    @Test fun membershipNullStillEnablesRowsWithEmptyMembership() {
        seedLists(listOf(IptvListEntry("favorites","Favorites",true)))
        lists(entry(false))
        reply(value=null,request=requestIndex("getIptvChannelListMembership"))
        idle()
        assertEquals(1,dialogList().adapter!!.itemCount)
        clickList(0)
        assertEquals(true,args("setIptvChannelInList")["inList"])
    }

    @Test fun listRemovalFavoritesAndPlayingRetentionAreDistinct() {
        val e=entry(false).copy(isFavorite=true)
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Favorites",true,false,false)))
        seedLists(listOf(IptvListEntry("favorites","Favorites",true)))
        set("iptvBrowseChannels",mutableListOf(e))
        boundAdapter().updateChannels(listOf(e))
        lists(e)
        reply(value=listOf("favorites"),request=requestIndex("getIptvChannelListMembership"))
        idle()
        clickList(0)
        assertFalse(e.isFavorite)
        assertTrue(browseChannels().isEmpty())
        assertEquals(0,boundAdapter().itemCount)
    }

    @Test fun membershipDropsNumberAndNullEvenForMatchingStringListIds() {
        seedLists(listOf(IptvListEntry("favorites","Favorites",true),IptvListEntry("3","Number",false),IptvListEntry("null","Null",false)))
        lists(entry(false))
        reply(value=listOf("favorites",3,null),request=requestIndex("getIptvChannelListMembership"))
        idle()
        assertEquals(3,dialogList().adapter!!.itemCount)
        assertTrue(listLabel(0).isSelected)
        assertFalse("numeric wire ID is not a string list ID",listLabel(1).isSelected)
        assertFalse("null wire ID is dropped",listLabel(2).isSelected)
    }

    @Test fun membershipReplyPostsFocusAfterRowsCanBeLaidOut() {
        seedLists(listOf(IptvListEntry("favorites","Favorites",true),IptvListEntry("custom","Custom",false)))
        lists(entry(false))
        val d=dialog()
        val list=dialogList()
        val done=d.getButton(AlertDialog.BUTTON_NEGATIVE)
        assertTrue(done.requestFocus())
        assertTrue(done.hasFocus())
        reply(value=listOf("favorites"),request=requestIndex("getIptvChannelListMembership"))
        list.measure(View.MeasureSpec.makeMeasureSpec(600,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(400,View.MeasureSpec.EXACTLY))
        list.layout(0,0,600,400)
        val first=list.findViewHolderForAdapterPosition(0)
        assertNotNull(first)
        assertFalse("focus is deferred",first!!.itemView.hasFocus())
        idle()
        assertTrue("posted first-row focus replaces Done focus",first.itemView.hasFocus())
    }
}
