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
internal class TvIptvGuidePickerCharacterizationTest : TvPhase12OriginalTest() {

    @Test fun sourcePickerFiltersContinueAndUsesInstalledChoice() {
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","Provider",false,false,true),IptvSourceEntry("continue","Continue",false,true,false),IptvSourceEntry("other","Other",false,false,true)))
        call("showIptvSourcePicker",emptyArray())
        val d=dialog()
        assertEquals("Choose source",d.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals(2,d.listView.adapter.count)
        assertEquals("Provider",d.listView.adapter.getItem(0))
        assertEquals("Other",d.listView.adapter.getItem(1))
        d.listView.performItemClick(null,1,1)
        assertEquals("other",field("iptvSourceId"))
        assertEquals("other",args("requestIptvBrowse")["sourceId"])
    }

    @Test fun sourcePickerAllContinueDoesNotShowDialog() {
        val prior=org.robolectric.shadows.ShadowDialog.getLatestDialog()
        set("iptvSources",mutableListOf(IptvSourceEntry("continue","Continue",false,true,false)))
        call("showIptvSourcePicker",emptyArray())
        assertSame(prior,org.robolectric.shadows.ShadowDialog.getLatestDialog())
    }

    @Test fun categoryFilterPinsDistinctSnapshotAllTermsCaseAndWhitespace() {
        set("iptvCategories",listOf("World News","News World","WORLD Movies","World News"))
        call("showIptvCategoryPicker",emptyArray())
        assertEquals(listOf("All categories","World News","News World","WORLD Movies"),categoryLabels())
        status("3 categories")
        val input=dialogInput()
        input.setText("  NeWs   wOrLd  ")
        assertEquals(listOf("All categories","World News","News World"),categoryLabels())
        status("2 categories")
        set("iptvCategories",listOf("New category"))
        input.setText("movies")
        assertEquals(listOf("All categories","WORLD Movies"),categoryLabels())
        status("1 category")
        input.setText("nothing")
        assertEquals(listOf("All categories"),categoryLabels())
        status("No matching categories")
        input.setText("")
        assertEquals(4,categoryLabels().size)
    }

    @Test fun emptyCategoriesPinStatusAndAllRow() {
        set("iptvCategories",emptyList<String>())
        call("showIptvCategoryPicker",emptyArray())
        assertEquals(listOf("All categories"),categoryLabels())
        status("No categories available")
    }

    @Test fun categorySelectionDismissesClearsSearchAndCommitsScope() {
        set("iptvCategories",listOf("News","Movies"))
        show()
        set("iptvSelectedCategory","Saved")
        search().requestFocus()
        assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        search().setText("old")
        call("showIptvCategoryPicker",emptyArray())
        val d=dialog()
        clickCategory(2)
        assertFalse(d.isShowing)
        assertFalse(field("iptvAllCategorySearchActive") as Boolean)
        assertNull(field("iptvSearchSavedCategory"))
        assertEquals("Movies",field("iptvSelectedCategory"))
        assertEquals("Movies",(field("iptvCategoryButton") as TextView).text.toString())
        assertEquals("",search().text.toString())
        assertEquals("",args("requestIptvBrowse")["query"])
        assertEquals("Movies",args("requestIptvBrowse")["category"])
    }

    @Test fun allCategorySelectionIsNullAndNotLiteralLabel() {
        call("showIptvCategoryPicker",emptyArray())
        clickCategory(0)
        assertNull(field("iptvSelectedCategory"))
        assertNull(args("requestIptvBrowse")["category"])
    }

    @Test fun categoryKeyboardAndDialogChromePinsInputLayoutAndDone() {
        call("showIptvCategoryPicker",emptyArray())
        val d=dialog()
        val input=dialogInput()
        val list=dialogList()
        assertEquals("Choose category",d.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertTrue(input.id!=View.NO_ID)
        assertTrue(list.id!=View.NO_ID)
        assertEquals(android.widget.LinearLayout.VERTICAL,(list.parent as android.widget.LinearLayout).orientation)
        assertEquals(density(24),(list.parent as View).paddingLeft)
        assertEquals(density(8),(list.parent as View).paddingTop)
        assertEquals(density(24),(list.parent as View).paddingRight)
        assertEquals(android.view.ViewGroup.LayoutParams.MATCH_PARENT,input.layoutParams.width)
        assertEquals(android.view.ViewGroup.LayoutParams.MATCH_PARENT,list.layoutParams.width)
        assertTrue(list.isFocusable)
        assertNotNull(input.compoundDrawables[0])
        assertEquals("Search categories",input.hint)
        assertEquals(1,input.maxLines)
        assertEquals(EditorInfo.IME_ACTION_DONE,input.imeOptions)
        assertEquals(android.text.InputType.TYPE_CLASS_TEXT,input.inputType)
        assertEquals(density(48),input.layoutParams.height)
        assertEquals(density(16),input.paddingLeft)
        assertEquals(density(16),input.paddingRight)
        assertEquals(density(10),input.compoundDrawablePadding)
        assertTrue("input focus="+input.isFocused+", visible="+input.isShown+", size="+input.width+"x"+input.height+", focusable="+input.isFocusable+", decor="+d.window!!.decorView.findFocus(),input.hasFocus())
        assertEquals(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE,d.window!!.attributes.softInputMode and android.view.WindowManager.LayoutParams.SOFT_INPUT_MASK_STATE)
        assertEquals(minOf(density(400),(activity.resources.displayMetrics.heightPixels*0.5f).toInt()),list.layoutParams.height)
        assertFalse(list.clipToPadding)
        assertEquals(density(16),list.paddingBottom)
        assertEquals("Cancel",d.getButton(AlertDialog.BUTTON_NEGATIVE).text.toString())
        assertTrue(editor(input,EditorInfo.IME_ACTION_DONE))
        assertFalse(editor(input,EditorInfo.IME_ACTION_GO))
    }

    @Test fun listMembershipErrorRetainsUnreadyRowsAndExactStatus() {
        seedLists(listOf(IptvListEntry("favorites","Favorites",true)))
        lists(entry())
        assertEquals(0,dialogList().adapter!!.itemCount)
        status("Loading lists…")
        reply(kind="error",request=requestIndex("getIptvChannelListMembership"))
        idle()
        assertEquals(0,dialogList().adapter!!.itemCount)
        status("Couldn't load your lists")
    }

    @Test fun listMembershipMissingRetainsUnreadyRowsAndExactStatus() {
        seedLists(listOf(IptvListEntry("favorites","Favorites",true)))
        lists(entry())
        assertEquals(0,dialogList().adapter!!.itemCount)
        status("Loading lists…")
        reply(kind="missing",request=requestIndex("getIptvChannelListMembership"))
        idle()
        assertEquals(0,dialogList().adapter!!.itemCount)
        status("Couldn't load your lists")
    }

    @Test fun listMembershipInlineLoadsBeforeToggleAndPinsFullPayload() {
        val e=entry().copy(isCurrent=false,isFavorite=true,contentType="vod",duration=120,httpHeaders=mapOf("X" to "Y"))
        seedLists(listOf(IptvListEntry("favorites","Favorites",true),IptvListEntry("list","My list",false)))
        boundAdapter().updateChannels(listOf(e))
        val changes=watchGuide()
        lists(e)
        assertEquals(e.url,args("getIptvChannelListMembership")["url"])
        assertEquals(0,dialogList().adapter!!.itemCount)
        val readyList=dialogList()
        reply(value=listOf("favorites",3,null),queued=false,request=requestIndex("getIptvChannelListMembership"))
        idle()
        status("Pick the lists this channel belongs to")
        assertEquals(2,dialogList().adapter!!.itemCount)
        val label=clickList(0)
        assertEquals("✓  Favorites",label.text.toString())
        assertFalse(e.isFavorite)
        assertTrue("favorite callback repaints the guide row",changes.changed>0)
        assertEquals("Favorites",listLabel(0).text.toString())
        assertFalse(listLabel(0).isSelected)
        val a=args("setIptvChannelInList")
        assertEquals(mapOf("listId" to "favorites","inList" to false,"url" to e.url,"name" to e.name,"logoUrl" to e.logoUrl,"group" to e.group,"sourceId" to e.sourceId,"channelNumber" to e.channelNumber,"contentType" to e.contentType,"duration" to e.duration,"httpHeaders" to e.httpHeaders),a)
        clickList(1)
        assertEquals("list",args("setIptvChannelInList")["listId"])
        assertEquals(true,args("setIptvChannelInList")["inList"])
        assertTrue(listLabel(1).isSelected)
    }

    @Test fun listMembershipQueuedLoadsBeforeToggleAndPinsFullPayload() {
        val e=entry().copy(isCurrent=false,isFavorite=true,contentType="vod",duration=120,httpHeaders=mapOf("X" to "Y"))
        seedLists(listOf(IptvListEntry("favorites","Favorites",true),IptvListEntry("list","My list",false)))
        boundAdapter().updateChannels(listOf(e))
        val changes=watchGuide()
        lists(e)
        assertEquals(e.url,args("getIptvChannelListMembership")["url"])
        assertEquals(0,dialogList().adapter!!.itemCount)
        val readyList=dialogList()
        reply(value=listOf("favorites",3,null),queued=true,request=requestIndex("getIptvChannelListMembership"))
        assertEquals(0,readyList.adapter!!.itemCount)
        idle()
        status("Pick the lists this channel belongs to")
        assertEquals(2,dialogList().adapter!!.itemCount)
        val label=clickList(0)
        assertEquals("✓  Favorites",label.text.toString())
        assertFalse(e.isFavorite)
        assertTrue("favorite callback repaints the guide row",changes.changed>0)
        assertEquals("Favorites",listLabel(0).text.toString())
        assertFalse(listLabel(0).isSelected)
        val a=args("setIptvChannelInList")
        assertEquals(mapOf("listId" to "favorites","inList" to false,"url" to e.url,"name" to e.name,"logoUrl" to e.logoUrl,"group" to e.group,"sourceId" to e.sourceId,"channelNumber" to e.channelNumber,"contentType" to e.contentType,"duration" to e.duration,"httpHeaders" to e.httpHeaders),a)
        clickList(1)
        assertEquals("list",args("setIptvChannelInList")["listId"])
        assertEquals(true,args("setIptvChannelInList")["inList"])
        assertTrue(listLabel(1).isSelected)
    }

    @Test fun listRemovalFromBrowsedCustomListRemovesOnlyIdentityAndUpdatesGuide() {
        val e=entry(false)
        val equal=e.copy()
        set("iptvBrowseChannels",mutableListOf(e,equal))
        set("iptvSearchSavedChannels",mutableListOf(e,equal))
        boundAdapter().updateChannels(listOf(e,equal))
        set("iptvSources",mutableListOf(IptvSourceEntry("provider","My list",false,false,false,true,"custom")))
        seedLists(listOf(IptvListEntry("custom","Custom",false)))
        lists(e)
        reply(value=listOf("custom"),request=requestIndex("getIptvChannelListMembership"))
        idle()
        clickList(0)
        assertEquals(1,browseChannels().size)
        assertSame(equal,browseChannels().single())
        assertEquals(1,boundAdapter().itemCount)
        assertEquals(false,args("setIptvChannelInList")["inList"])
    }

    @Test fun listPickerAbsentBridgeFallsBackToFavorite() {
        val e=entry(false)
        MainActivity.setAndroidTvPlayerChannel(null)
        lists(e)
        assertTrue(e.isFavorite)
        assertEquals("Added to favorites",ShadowToast.getTextOfLatestToast())
    }
}
