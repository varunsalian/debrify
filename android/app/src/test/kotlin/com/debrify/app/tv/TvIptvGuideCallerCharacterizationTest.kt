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
internal class TvIptvGuideCallerCharacterizationTest : TvPhase11OriginalTest() {
    private fun editor(input: EditText, action: Int, event: KeyEvent? = null): Boolean {
        val e: Any = ReflectionHelpers.getField(input,"mEditor")
        val content: Any = ReflectionHelpers.getField(e,"mInputContentType")
        val listener: TextView.OnEditorActionListener = ReflectionHelpers.getField(content,"onEditorActionListener")
        return listener.onEditorAction(input,action,event)
    }
    private fun dialogInput(): Pair<AlertDialog,EditText> {
        call("showIptvChannelJumpDialog",emptyArray())
        idle()
        val dialog=ShadowDialog.getLatestDialog() as AlertDialog
        fun input(v: View): EditText? {
            if(v is EditText)return v
            if(v is android.view.ViewGroup)for(i in 0 until v.childCount)input(v.getChildAt(i))?.let { return it }
            return null
        }
        return dialog to input(dialog.window!!.decorView)!!
    }
    private fun scroll(dy: Int,first: Int,last: Int) {
        guideList().layoutManager=object:LinearLayoutManager(activity) {
            override fun findFirstVisibleItemPosition()=first
            override fun findLastVisibleItemPosition()=last
        }
        val listeners: List<RecyclerView.OnScrollListener> = ReflectionHelpers.getField(guideList(),"mScrollListeners")
        assertEquals("actual bootstrap-installed listener",1,listeners.size)
        listeners.single().onScrolled(guideList(),0,dy)
    }
    @Test fun installedSeriesRowRequestsEpisodes() {
        val entry=channel().copy(name="Series",url="xtream-series://42",contentType="series")
        clickRow(entry)
        val a=args("requestIptvBrowse")
        assertEquals("seriesEpisodes",a["action"]);assertEquals(entry.url,a["channelUrl"])
        assertEquals(entry.name,a["title"]);assertEquals(entry.sourceId,a["sourceId"])

    }
    @Test fun installedEpisodeRowDisablesPagingAndSwitches() {
        set("iptvContentType","episodes");set("iptvZapPagingActive",true)
        val entry=channel(live=false);clickRow(entry)
        assertFalse("episode selection leaves live paging",field("iptvZapPagingActive") as Boolean)
        assertFalse(field("iptvGuideVisible") as Boolean);assertEquals(entry.url,channels().single().url)
        assertTrue("watch registration is called",requests("recordIptvWatch").isNotEmpty())

    }
    @Test fun installedLiveRowStartsAnchoredCategorySession() {
        val entry=channel().copy(index=41,group="  Movies  ");clickRow(entry)
        assertTrue("installed click starts category paging",field("iptvZapPagingActive") as Boolean)
        assertEquals("Movies",field("iptvZapCategory"));assertTrue(field("iptvZapOwnsUiContext") as Boolean)
        assertEquals(41,entry.index);assertNotSame(entry,channels().single())
        val a=args("requestIptvBrowse");assertEquals("zapPage",a["action"]);assertEquals(entry.url,a["anchorUrl"])

    }
    @Test fun typingIsSubmitOnlyAndShowsHint() {
        search().setText("  alpha  ")
        assertTrue("typing performs no bridge requests",messenger.requests.isEmpty())
        assertEquals("Press OK to search",(field("iptvGuideCountText") as TextView).text.toString())
        search().setText("");assertEquals(call("iptvGuideItemCountLabel",emptyArray()),(field("iptvGuideCountText") as TextView).text.toString())

    }
    @Test fun installedEditorSEARCHSubmitsTrimmedQuery() {
        search().setText("  alpha  ")
        assertTrue(editor(search(),EditorInfo.IME_ACTION_SEARCH))
        assertEquals("alpha",args("requestIptvBrowse")["query"])

    }
    @Test fun installedEditorDONESubmitsTrimmedQuery() {
        search().setText("  alpha  ")
        assertTrue(editor(search(),EditorInfo.IME_ACTION_DONE))
        assertEquals("alpha",args("requestIptvBrowse")["query"])

    }
    @Test fun installedEditorGOSubmitsTrimmedQuery() {
        search().setText("  alpha  ")
        assertTrue(editor(search(),EditorInfo.IME_ACTION_GO))
        assertEquals("alpha",args("requestIptvBrowse")["query"])

    }
    @Test fun installedEnterSubmitsOnlyOnRelease() {
        search().setText(" beta ")
        assertFalse(editor(search(),EditorInfo.IME_ACTION_NONE,KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_ENTER)))
        assertTrue(messenger.requests.isEmpty())
        assertTrue(editor(search(),EditorInfo.IME_ACTION_NONE,KeyEvent(KeyEvent.ACTION_UP,KeyEvent.KEYCODE_ENTER)))
        assertEquals("beta",args("requestIptvBrowse")["query"])

    }
    @Test fun installedSearchFocusAndBrowseRestoreSavedCategory() {
        show();set("iptvZapPagingActive",true)
        activity.findViewById<View>(R.id.iptv_nav_search).performClick()
        assertTrue(search().hasFocus());assertTrue(field("iptvAllCategorySearchActive") as Boolean)
        assertNull(field("iptvSelectedCategory"));search().setText("x");clearTransport()
        activity.findViewById<View>(R.id.iptv_nav_browse).performClick()
        assertFalse(field("iptvAllCategorySearchActive") as Boolean);assertEquals("News",field("iptvSelectedCategory"))
        assertEquals("",search().text.toString());assertTrue("restore avoids redundant browse",requests("requestIptvBrowse").isEmpty())

    }
    @Test fun browseDefaultReadsQueryAtEachInvocation() {
        search().setText(" one ");browseDefault();assertEquals("one",args("requestIptvBrowse")["query"])
        search().setText(" two ");browseDefault();assertEquals("two",args("requestIptvBrowse")["query"])

    }
    @Test fun guideOpenClosePinsVisibilityAndDurations() {
        show();val overlay=field("iptvGuideOverlay") as View
        assertTrue(field("iptvGuideVisible") as Boolean);assertEquals(View.VISIBLE,overlay.visibility)
        assertEquals(200L,overlay.animate().duration)
        hide();assertFalse(field("iptvGuideVisible") as Boolean);assertEquals(150L,overlay.animate().duration)
        advance(200);assertEquals(View.GONE,overlay.visibility)

    }
    @Test fun hidePostsTrimOnBorrowedHandler() {
        val entries=MutableList(800) { i -> channel(url="https://phase11.invalid/$i").copy(index=i,isCurrent=i==400,logoUrl=null) }
        set("iptvZapPagingActive",true);set("iptvChannels",entries);set("currentIptvIndex",400);set("iptvGuideVisible",true)
        hide();assertEquals("trim deferred until click completes",800,channels().size)
        idle();assertEquals(600,channels().size);assertEquals(100,channels().first().index);assertEquals(699,channels().last().index)

    }
    @Test fun installedScrollUsesForwardAndBackwardThresholds() {
        val entries=MutableList(30){ i->channel(url="https://phase11.invalid/$i").copy(index=200+i,isCurrent=i==15,logoUrl=null) }
        set("iptvZapPagingActive",true);install(entries,200,1000);set("currentIptvIndex",15);clearTransport()
        scroll(1,12,17);assertTrue(requests("requestIptvBrowse").isEmpty())
        scroll(1,12,18);assertEquals(230,args("requestIptvBrowse")["offset"])
        set("iptvZapRequestInFlight",false);clearTransport()
        scroll(-1,12,29);assertTrue(requests("requestIptvBrowse").isEmpty())
        scroll(-1,11,29);assertEquals(0,args("requestIptvBrowse")["offset"])

    }
    @Test fun installedScrollSuppressesNonWindowPrefetch() {
        set("iptvZapPagingActive",true);set("iptvGuideUsesZapWindow",false);set("iptvZapCategoryTotal",1000)
        channels().forEachIndexed { i,ch->ch.index=200+i };clearTransport()
        scroll(1,0,1);assertTrue("browse list cannot prefetch playing window",requests("requestIptvBrowse").isEmpty())
        set("iptvGuideUsesZapWindow",true);set("iptvZapPagingActive",false);scroll(1,0,1);assertTrue("inactive paging cannot load",requests("requestIptvBrowse").isEmpty())
        set("iptvZapPagingActive",true);set("iptvZapRequestInFlight",true);scroll(1,0,1);assertTrue("in-flight paging cannot load",requests("requestIptvBrowse").isEmpty())

    }
    @Test fun numericDialogPositiveValidatesAndSubmits() {
        val (dialog,input)=dialogInput();assertEquals("Channel number",input.hint)
        for(value in listOf("0","-1","bad")) { input.setText(value);dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick();assertEquals("Enter a valid channel number",input.error?.toString());assertTrue(dialog.isShowing);assertTrue(requests("requestIptvBrowse").isEmpty()) }
        input.setText(" 7 ");dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        assertFalse(dialog.isShowing);assertEquals(7,args("requestIptvBrowse")["channelNumber"])

    }
    @Test fun numericDialogInstalledGoSubmits() {
        val (dialog,input)=dialogInput();input.setText("8")
        assertFalse(editor(input,EditorInfo.IME_ACTION_DONE));assertTrue(dialog.isShowing)
        assertTrue(editor(input,EditorInfo.IME_ACTION_GO));assertFalse(dialog.isShowing)
        assertEquals(8,args("requestIptvBrowse")["channelNumber"])

    }
}
