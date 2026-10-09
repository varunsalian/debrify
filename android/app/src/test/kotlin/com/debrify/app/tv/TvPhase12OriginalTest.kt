package com.debrify.app.tv

import android.view.View
import android.view.ViewGroup
import android.view.KeyEvent
import android.widget.TextView
import android.widget.EditText
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import org.junit.Assert.*
import org.robolectric.shadows.ShadowDialog
import org.robolectric.util.ReflectionHelpers

/** Original activity bootstrap, installed callbacks, and paired binary replies. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase12OriginalTest : TvPhase11OriginalTest() {
    protected open val phase12Style = GuideStyle.CLASSIC
    override fun bootstrapJson(): org.json.JSONObject {
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter.iptv_player_guide_style", phase12Style.name.lowercase()).commit()
        return super.bootstrapJson()
    }
    protected var replyUptime = 0L
    protected var replyWallClock = 0L
    protected fun epgAnswer(value: Any?, queued: Boolean = false) {
        val request=requestIndex("requestIptvEpg")
        val deliver=Runnable { replyUptime=android.os.SystemClock.uptimeMillis();replyWallClock=org.robolectric.shadows.ShadowSystem.currentTimeMillis();reply(value=value,queued=false,request=request) }
        if(queued)assertTrue(main.post(deliver)) else deliver.run()
    }
    protected fun untilUptime(time: Long) { val remaining=time-android.os.SystemClock.uptimeMillis();assertTrue("fixture has not crossed the requested boundary",remaining>=0);advance(remaining) }
    protected fun seedLists(entries: List<IptvListEntry>) { TvPlayerOriginalAccess.set(field("iptvGuideController")!!,"iptvLists",entries.toMutableList()) }
    protected fun v(name: String) = field(name) as View
    protected fun t(name: String) = field(name) as TextView
    protected fun text(name: String) = t(name).text.toString()
    protected fun entry(current: Boolean = true) = channel().copy(name="alpha", logoUrl=null,
        sourceId="provider", group="News", isCurrent=current, epgLoaded=false,
        epgLoading=false, epgCatchupMetadataLoaded=false)
    protected fun playing(e: IptvChannelEntry = entry()): IptvChannelEntry {
        set("iptvChannels",mutableListOf(e)); set("currentIptvIndex",0); return e
    }
    protected fun ensure(e: IptvChannelEntry) = call("ensureIptvChannelEpg",arrayOf(IptvChannelEntry::class.java),e)
    protected fun pane(e: IptvChannelEntry) = call("showIptvSchedulePane",arrayOf(IptvChannelEntry::class.java),e)
    protected fun hidePane() = call("hideIptvEpgPane",emptyArray())
    protected fun day(offset: Int, focus: Boolean = true) = call("selectIptvEpgDay",arrayOf(intType,boolType),offset,focus)
    protected fun logo(e: IptvChannelEntry) = call("paintIptvEpgLogo",arrayOf(IptvChannelEntry::class.java),e)
    protected fun header() = call("updateIptvGuideCurrentName",emptyArray())
    protected fun nowLine() = call("updateIptvGuideEpgHeader",emptyArray())
    protected fun favorite(e: IptvChannelEntry) = call("toggleIptvFavorite",arrayOf(IptvChannelEntry::class.java),e)
    protected fun remove(e: IptvChannelEntry) = call("removeIptvGuideRow",arrayOf(IptvChannelEntry::class.java),e)
    protected fun lists(e: IptvChannelEntry) = call("showIptvListPicker",arrayOf(IptvChannelEntry::class.java),e)
    protected fun boundAdapter(): IptvChannelAdapter { val a=field("iptvChannelAdapter");assertNotNull("bootstrap installs the channel adapter",a);return a as IptvChannelAdapter }
    protected fun epgAdapter(): IptvEpgAdapter { val a=field("iptvEpgAdapter");assertNotNull("bootstrap installs the schedule adapter",a);return a as IptvEpgAdapter }
    @Suppress("UNCHECKED_CAST") protected fun programs() = field("iptvEpgPrograms") as List<IptvEpgProgram>
    protected fun dialog(): AlertDialog { org.robolectric.shadows.ShadowChoreographer.setPaused(false);idle();val latest=ShadowDialog.getLatestDialog();assertNotNull("installed callback shows the dialog",latest);return (latest as AlertDialog).also { assertTrue(it.isShowing) } }
    protected inline fun <reified T: View> descendants(root: View): List<T> {
        val found=mutableListOf<T>()
        val pending=java.util.ArrayDeque<View>(); pending.add(root)
        while(pending.isNotEmpty()) { val view=pending.removeFirst(); if(view is T)found.add(view)
            if(view is ViewGroup)for(i in 0 until view.childCount)pending.add(view.getChildAt(i)) }
        return found
    }
    protected fun dialogInput(): EditText { val views=descendants<EditText>(dialog().window!!.decorView);assertEquals("dialog publishes exactly one input",1,views.size);return views.single() }
    protected fun dialogList(): RecyclerView { val views=descendants<RecyclerView>(dialog().window!!.decorView);assertEquals("dialog publishes exactly one list",1,views.size);val list=views.single();assertNotNull("dialog installs its row adapter",list.adapter);return list }
    protected fun editor(input: EditText, action: Int, event: KeyEvent? = null): Boolean {
        val e: Any=ReflectionHelpers.getField(input,"mEditor")
        val c: Any=ReflectionHelpers.getField(e,"mInputContentType")
        val listener: TextView.OnEditorActionListener?=ReflectionHelpers.getField(c,"onEditorActionListener")
        assertNotNull("bootstrap installs the editor callback",listener)
        return listener!!.onEditorAction(input,action,event)
    }
    protected fun clickCategory(position: Int) {
        val list=dialogList(); val a=list.adapter as IptvCategoryAdapter
        val h=a.onCreateViewHolder(list,0); a.onBindViewHolder(h,position); h.itemView.performClick()
    }
    protected fun clickList(position: Int): TextView {
        val list=dialogList(); val a=list.adapter as IptvListPickerAdapter
        val h=a.onCreateViewHolder(list,0); a.onBindViewHolder(h,position); h.itemView.performClick(); return h.label
    }
    protected class GuideChanges : RecyclerView.AdapterDataObserver() {
        var changed=0
        override fun onItemRangeChanged(start: Int,count: Int,payload: Any?) { changed+=count }
        override fun onChanged() { changed++ }
    }
    protected fun watchGuide() = GuideChanges().also { boundAdapter().registerAdapterDataObserver(it) }
    protected fun listLabel(position: Int): TextView {
        val list=dialogList();val a=list.adapter as IptvListPickerAdapter
        val h=a.onCreateViewHolder(list,0);a.onBindViewHolder(h,position);return h.label
    }
    protected fun categoryLabels(): List<String> {
        val list=dialogList(); val a=list.adapter as IptvCategoryAdapter
        return (0 until a.itemCount).map { val h=a.onCreateViewHolder(list,0);a.onBindViewHolder(h,it);h.label.text.toString() }
    }
    protected fun status(value: String): TextView { val found=descendants<TextView>(dialog().window!!.decorView).firstOrNull { it.text.toString()==value };assertNotNull("dialog displays exact text: $value",found);return found!! }
    protected fun epgReply(title: String?="Now", archive: Boolean=true, start: Long=1L,
                           stop: Long=System.currentTimeMillis()+3_600_000L, next: String?="Next",
                           nextStart: Long=stop) = mapOf("now" to mapOf("title" to title,"startMs" to start,"stopMs" to stop,"hasArchive" to archive),
        "next" to mapOf("title" to next,"startMs" to nextStart))
    protected fun schedule(programs: List<Any?>) = mapOf("schedule" to programs)
    protected fun rawProgram(title: String="Programme", start: Long=System.currentTimeMillis()-1000,
                             stop: Long=System.currentTimeMillis()+1000, archive: Boolean=true) =
        mapOf("title" to title,"description" to "Description","startMs" to start,"stopMs" to stop,"hasArchive" to archive)
    protected fun fresh(e: IptvChannelEntry) { e.epgLoaded=true;e.epgCatchupMetadataLoaded=true;e.epgNowStopMs=Long.MAX_VALUE }
    protected fun density(value: Int) = (value*activity.resources.displayMetrics.density).toInt()
}
