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
internal class TvIptvEpgPaneCharacterizationTest : TvPhase12OriginalTest() {
    private class PaintProbe(context: android.content.Context) : View(context) {
        var observe: (() -> Unit)? = null
        val values=mutableListOf<Int>()
        override fun setVisibility(value: Int) { observe?.invoke();values.add(value);super.setVisibility(value) }
    }
    private class ListPaintProbe(context: android.content.Context) : RecyclerView(context) {
        var values: MutableList<Int>? = null
        override fun setVisibility(value: Int) { values?.add(value);super.setVisibility(value) }
    }

    @Test fun openingPanePublishesAllOwnersAndLoadingViewsBeforeReply() {
        val e=entry()
        show()
        set("iptvEpgToken",41)
        set("iptvEpgDayOffset",2)
        set("iptvEpgPrograms",listOf(programme()))
        pane(e)
        assertEquals(42,field("iptvEpgToken"))
        assertSame(e,field("iptvEpgEntry"))
        assertEquals(true,field("iptvEpgVisible"))
        assertEquals(0,field("iptvEpgDayOffset"))
        assertTrue(programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgPanel").visibility)
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
        assertEquals(View.GONE,v("iptvEpgEmpty").visibility)
        assertEquals(View.GONE,v("iptvEpgList").visibility)
        assertEquals(View.GONE,v("iptvGuideNowPlaying").visibility)
        assertEquals(e.displayName,text("iptvEpgChannelName"))
        assertEquals("News · Channel 7",text("iptvEpgChannelGroup"))
        assertEquals(true,args("requestIptvEpg")["includeSchedule"])
        assertEquals(true,args("requestIptvEpg")["includeCatchupMetadata"])
    }

    @Test fun groupAndNumberFallbackAreExact() {
        show()
        pane(entry().copy(group=null,channelNumber=null,index=8))
        assertEquals("Channel 9",text("iptvEpgChannelGroup"))
    }

    @Test fun scheduleInlineFiltersInvalidRowsAndPreservesProgrammeFields() {
        show()
        pane(entry())
        val valid=rawProgram()
        epgAnswer(value=schedule(listOf(null,"not a row",mapOf("title" to ""),mapOf("title" to "missing"),valid,rawProgram("No archive").plus("hasArchive" to "true"),rawProgram("Blank description").plus("description" to " "))),queued=false)
        idle()
        assertEquals(3,programs().size)
        assertEquals(valid["startMs"],programs()[0].startMs)
        assertEquals(valid["stopMs"],programs()[0].stopMs)
        assertEquals("Programme",programs()[0].title)
        assertEquals("Description",programs()[0].description)
        assertTrue(programs()[0].hasArchive)
        assertFalse(programs()[1].hasArchive)
        assertNull(programs()[2].description)
        assertEquals(View.GONE,v("iptvEpgLoading").visibility)
        assertEquals(View.VISIBLE,v("iptvEpgList").visibility)
        assertEquals(View.GONE,v("iptvEpgEmpty").visibility)
        assertEquals(3,epgAdapter().itemCount)
    }

    @Test fun nullScheduleInlineShowsEmptyAfterLoading() {
        show()
        pane(entry())
        epgAnswer(value=null,queued=false)
        idle()
        assertTrue(programs().isEmpty())
        assertEquals(View.GONE,v("iptvEpgLoading").visibility)
        assertEquals(View.GONE,v("iptvEpgList").visibility)
        assertEquals(View.VISIBLE,v("iptvEpgEmpty").visibility)
    }

    @Test fun scheduleInlineStaleTokenReplyIsRejected() {
        show()
        pane(entry())
        set("iptvEpgToken",(field("iptvEpgToken") as Int)+1)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=false)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleInlineHiddenGuideReplyIsRejected() {
        show()
        pane(entry())
        set("iptvGuideVisible",false)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=false)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleInlineHiddenPaneReplyIsRejected() {
        show()
        pane(entry())
        set("iptvEpgVisible",false)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=false)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleInlineFinishingReplyIsRejected() {
        show()
        pane(entry())
        activity.finish()
        epgAnswer(value=schedule(listOf(rawProgram())),queued=false)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleInlineDestroyedReplyIsRejected() {
        show()
        pane(entry())
        val captured=field("iptvEpgToken") as Int
        destroyNow()
        assertEquals(captured+1,field("iptvEpgToken"))
        set("iptvEpgToken",captured)
        assertTrue(activity.isDestroyed)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=false)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleQueuedFiltersInvalidRowsAndPreservesProgrammeFields() {
        show()
        pane(entry())
        val valid=rawProgram()
        epgAnswer(value=schedule(listOf(null,"not a row",mapOf("title" to ""),mapOf("title" to "missing"),valid,rawProgram("No archive").plus("hasArchive" to "true"),rawProgram("Blank description").plus("description" to " "))),queued=true)
        idle()
        assertEquals(3,programs().size)
        assertEquals(valid["startMs"],programs()[0].startMs)
        assertEquals(valid["stopMs"],programs()[0].stopMs)
        assertEquals("Programme",programs()[0].title)
        assertEquals("Description",programs()[0].description)
        assertTrue(programs()[0].hasArchive)
        assertFalse(programs()[1].hasArchive)
        assertNull(programs()[2].description)
        assertEquals(View.GONE,v("iptvEpgLoading").visibility)
        assertEquals(View.VISIBLE,v("iptvEpgList").visibility)
        assertEquals(View.GONE,v("iptvEpgEmpty").visibility)
        assertEquals(3,epgAdapter().itemCount)
    }

    @Test fun nullScheduleQueuedShowsEmptyAfterLoading() {
        show()
        pane(entry())
        epgAnswer(value=null,queued=true)
        idle()
        assertTrue(programs().isEmpty())
        assertEquals(View.GONE,v("iptvEpgLoading").visibility)
        assertEquals(View.GONE,v("iptvEpgList").visibility)
        assertEquals(View.VISIBLE,v("iptvEpgEmpty").visibility)
    }

    @Test fun scheduleQueuedStaleTokenReplyIsRejected() {
        show()
        pane(entry())
        set("iptvEpgToken",(field("iptvEpgToken") as Int)+1)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=true)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleQueuedHiddenGuideReplyIsRejected() {
        show()
        pane(entry())
        set("iptvGuideVisible",false)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=true)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleQueuedHiddenPaneReplyIsRejected() {
        show()
        pane(entry())
        set("iptvEpgVisible",false)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=true)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleQueuedFinishingReplyIsRejected() {
        show()
        pane(entry())
        activity.finish()
        epgAnswer(value=schedule(listOf(rawProgram())),queued=true)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun scheduleQueuedDestroyedReplyIsRejected() {
        show()
        pane(entry())
        val captured=field("iptvEpgToken") as Int
        destroyNow()
        assertEquals(captured+1,field("iptvEpgToken"))
        set("iptvEpgToken",captured)
        assertTrue(activity.isDestroyed)
        epgAnswer(value=schedule(listOf(rawProgram())),queued=true)
        idle()
        assertTrue("rejected reply does not publish programmes",programs().isEmpty())
        assertEquals(View.VISIBLE,v("iptvEpgLoading").visibility)
    }

    @Test fun hidePaneRetiresTokenEntryProgrammesAndRestoresCurrentCard() {
        show()
        val e=entry()
        pane(e)
        set("iptvEpgPrograms",listOf(programme()))
        epgAdapter().updatePrograms(programs())
        val token=field("iptvEpgToken") as Int
        hidePane()
        assertEquals(token+1,field("iptvEpgToken"))
        assertEquals(false,field("iptvEpgVisible"))
        assertNull(field("iptvEpgEntry"))
        assertEquals(View.GONE,v("iptvEpgPanel").visibility)
        assertEquals(View.VISIBLE,v("iptvGuideNowPlaying").visibility)
        assertTrue(programs().isEmpty())
        assertEquals(0,epgAdapter().itemCount)
    }

    @Test fun hidePaneDoesNotRestoreCardForHiddenGuideOrInvalidIndex() {
        for(pair in listOf(false to 0,true to 99)){set("iptvGuideVisible",pair.first)
        set("currentIptvIndex",pair.second)
        hidePane()
        assertEquals(View.GONE,v("iptvGuideNowPlaying").visibility)}
    }

    @Test fun focusWalkRecognizesPanelAncestorsOnly() {
        val panel=v("iptvEpgPanel")
        for(view in listOf(panel,v("iptvEpgChannelName"),search())){org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(view)
        assertEquals(view!==search(),call("isFocusInIptvEpgPanel",emptyArray()))}
        org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(null)
        assertEquals(false,call("isFocusInIptvEpgPanel",emptyArray()))
    }

    @Test fun dayButtonsPinAllSixOffsetsAndSelectedState() {
        val ids=listOf(-3 to R.id.iptv_epg_day_three_ago,-2 to R.id.iptv_epg_day_two_ago,-1 to R.id.iptv_epg_day_yesterday,0 to R.id.iptv_epg_day_today,1 to R.id.iptv_epg_day_tomorrow,2 to R.id.iptv_epg_day_later)
        for((offset,id) in ids){activity.findViewById<View>(id).performClick()
        assertEquals(offset,field("iptvEpgDayOffset"))
        for((other,buttonId) in ids)assertEquals(offset==other,activity.findViewById<View>(buttonId).isSelected)
        val date=java.util.Calendar.getInstance().apply{add(java.util.Calendar.DAY_OF_YEAR,offset)}
        assertEquals(java.text.SimpleDateFormat("EEEE, d MMMM",java.util.Locale.getDefault()).format(date.time),text("iptvEpgDate"))}
    }

    @Test fun dayFilteringPinsYearAndDayAndEmptyLoadingVisibility() {
        val today=java.util.Calendar.getInstance()
        val otherYear=today.clone() as java.util.Calendar
        otherYear.add(java.util.Calendar.YEAR,-1)
        val tomorrow=today.clone() as java.util.Calendar
        tomorrow.add(java.util.Calendar.DAY_OF_YEAR,1)
        set("iptvEpgPrograms",listOf(IptvEpgProgram("Today",null,today.timeInMillis,today.timeInMillis+1000,true),IptvEpgProgram("Tomorrow",null,tomorrow.timeInMillis,tomorrow.timeInMillis+1000,true),IptvEpgProgram("Other year",null,otherYear.timeInMillis,otherYear.timeInMillis+1000,true)))
        day(0,false)
        assertEquals(1,epgAdapter().itemCount)
        assertEquals(View.VISIBLE,v("iptvEpgList").visibility)
        day(2,false)
        assertEquals(0,epgAdapter().itemCount)
        assertEquals(View.GONE,v("iptvEpgList").visibility)
        v("iptvEpgLoading").visibility=View.VISIBLE
        day(2,false)
        assertEquals(View.GONE,v("iptvEpgEmpty").visibility)
        v("iptvEpgLoading").visibility=View.GONE
        day(2,false)
        assertEquals(View.VISIBLE,v("iptvEpgEmpty").visibility)
    }

    @Test fun paneResetsDayAndProgrammesBeforeFirstPanelPaint() {
        show()
        set("iptvEpgDayOffset",2)
        set("iptvEpgPrograms",listOf(programme()))
        val panel=PaintProbe(activity)
        var atPaint:Pair<Int,Int>?=null
        panel.observe={atPaint=(field("iptvEpgDayOffset") as Int) to programs().size}
        set("iptvEpgPanel",panel)
        pane(entry())
        assertEquals("initial reset occurs before painter call",0 to 0,atPaint)
        assertEquals(listOf(View.VISIBLE),panel.values)
        assertEquals(0,field("iptvEpgDayOffset"))
    }

    @Test fun paneInitialVisibilityWritesAreNotMaskedByDaySelection() {
        show()
        val empty=PaintProbe(activity)
        val loading=PaintProbe(activity)
        set("iptvEpgEmpty",empty)
        set("iptvEpgLoading",loading)
        pane(entry())
        assertEquals("empty hidden before select-day hides it again",listOf(View.GONE,View.GONE),empty.values)
        assertEquals(listOf(View.VISIBLE),loading.values)
    }

    @Test fun paneStartPinsOneExactScheduleRequest() {
        show()
        val e=entry(false)
        pane(e)
        assertEquals(1,requests("requestIptvEpg").size)
        assertEquals(e.url,args("requestIptvEpg")["channelUrl"])
        assertEquals(true,args("requestIptvEpg")["includeSchedule"])
        assertEquals(false,args("requestIptvEpg")["includeCatchupMetadata"])
    }

    @Test fun scheduleReplyPostsFocusToAiringProgrammeAfterLayout() {
        val now=java.util.Calendar.getInstance().timeInMillis
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(now))
        show()
        advance(200)
        pane(entry())
        search().requestFocus()
        assertTrue(search().hasFocus())
        val list=v("iptvEpgList") as RecyclerView
        val positions=mutableListOf<Int>()
        list.layoutManager=object:androidx.recyclerview.widget.LinearLayoutManager(activity){override fun scrollToPosition(position: Int){positions.add(position)
        super.scrollToPosition(position)}}
        epgAnswer(value=schedule(listOf(rawProgram("Ended",now-2000,now-1000),rawProgram("Airing",now-1000,now+60_000))))
        list.measure(View.MeasureSpec.makeMeasureSpec(600,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(400,View.MeasureSpec.EXACTLY))
        list.layout(0,0,600,400)
        assertEquals(listOf(1),positions)
        val airing=list.findViewHolderForAdapterPosition(1)
        assertNotNull(airing)
        assertFalse("focus remains deferred until view post",airing!!.itemView.hasFocus())
        idle()
        val attached=list.findViewHolderForAdapterPosition(1)
        assertNotNull(attached)
        assertTrue("default day dispatch focuses the attached airing row",attached!!.itemView.hasFocus())
    }

    @Test fun paneHidesListBeforeDaySelectionRepeatsTheWrite() {
        show()
        val list=ListPaintProbe(activity)
        list.values=mutableListOf()
        set("iptvEpgList",list)
        pane(entry())
        assertEquals(listOf(View.GONE,View.GONE),list.values)
    }

    @Test fun panePaintsItsLogoThroughTheInstalledOwnerCall() {
        show()
        v("iptvEpgLogo").visibility=View.VISIBLE
        v("iptvEpgLetter").visibility=View.GONE
        t("iptvEpgLetter").text="stale"
        pane(entry())
        assertEquals(View.GONE,v("iptvEpgLogo").visibility)
        assertEquals(View.VISIBLE,v("iptvEpgLetter").visibility)
        assertEquals("A",text("iptvEpgLetter"))
    }

    @Test fun paneSelectsTodayAndPaintsDateWithoutPostingFocus() {
        show()
        t("iptvEpgDate").text="stale"
        activity.findViewById<View>(R.id.iptv_epg_day_today).isSelected=false
        activity.findViewById<View>(R.id.iptv_epg_day_later).isSelected=true
        pane(entry())
        assertEquals(java.text.SimpleDateFormat("EEEE, d MMMM",java.util.Locale.getDefault()).format(java.util.Calendar.getInstance().time),text("iptvEpgDate"))
        assertTrue(activity.findViewById<View>(R.id.iptv_epg_day_today).isSelected)
        assertFalse(activity.findViewById<View>(R.id.iptv_epg_day_later).isSelected)
    }
}
