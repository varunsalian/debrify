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
internal class TvIptvChromeWiringCharacterizationTest : TvPhase12OriginalTest() {
    private class VisibilityProbe(context: android.content.Context) : androidx.appcompat.widget.AppCompatButton(context) {
        var changes: MutableList<Int>? = null
        override fun setVisibility(value: Int) { changes?.add(value);super.setVisibility(value) }
    }

    @Test fun focusedGuideEntryTracksRealAttachedAdapterPosition() {
        show()
        val list=guideList()
        val e=entry(false)
        fresh(e)
        boundAdapter().updateChannels(listOf(e))
        list.measure(View.MeasureSpec.makeMeasureSpec(600,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(500,View.MeasureSpec.EXACTLY))
        list.layout(0,0,600,500)
        val holder=list.findViewHolderForAdapterPosition(0)
        assertNotNull(holder)
        assertTrue(holder!!.itemView.requestFocus())
        assertSame(e,call("focusedIptvGuideEntry",emptyArray()))
        search().requestFocus()
        assertNull(call("focusedIptvGuideEntry",emptyArray()))
    }

    @Test fun bootstrapBindsEveryMovedChromeViewToItsXmlId() {
        val expected=mapOf("iptvGuideCurrentName" to R.id.iptv_guide_current_name,"iptvGuideCurrentGroup" to R.id.iptv_guide_current_group,"iptvGuideCurrentEpg" to R.id.iptv_guide_current_epg,"iptvGuideNowPlaying" to R.id.iptv_guide_now_playing,"iptvGuideNowLogo" to R.id.iptv_guide_now_logo,"iptvGuideNowLetter" to R.id.iptv_guide_now_letter,"iptvEpgPanel" to R.id.iptv_epg_panel,"iptvEpgLogo" to R.id.iptv_epg_logo,"iptvEpgLetter" to R.id.iptv_epg_letter,"iptvEpgChannelName" to R.id.iptv_epg_channel_name,"iptvEpgChannelGroup" to R.id.iptv_epg_channel_group,"iptvEpgDate" to R.id.iptv_epg_date,"iptvEpgLoading" to R.id.iptv_epg_loading,"iptvEpgEmpty" to R.id.iptv_epg_empty,"iptvEpgList" to R.id.iptv_epg_list)
        for((name,id) in expected)assertSame(name,activity.findViewById<View>(id),field(name))
        assertSame(epgAdapter(),(v("iptvEpgList") as RecyclerView).adapter)
    }

    @Test fun backFromPaneHidesScheduleBeforeGuide() {
        show()
        pane(entry())
        org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(v("iptvEpgChannelName"))
        assertTrue(key(KeyEvent.KEYCODE_BACK))
        assertEquals(false,field("iptvEpgVisible"))
        assertEquals(true,field("iptvGuideVisible"))
        assertEquals(View.GONE,v("iptvEpgPanel").visibility)
    }

    @Test fun sourceControlsAreGoneWhenBootstrapSourcesEmpty() {
        val probes=mutableListOf<VisibilityProbe>()
        for(id in listOf(R.id.iptv_nav_favorites,R.id.iptv_nav_sources,R.id.iptv_source_button)){val old=activity.findViewById<View>(id)
        val parent=old.parent as android.view.ViewGroup
        val index=parent.indexOfChild(old)
        val spy=VisibilityProbe(activity)
        spy.id=id
        spy.layoutParams=old.layoutParams
        parent.removeView(old)
        parent.addView(spy,index)
        if(id==R.id.iptv_source_button)set("iptvSourceButton",spy)
        spy.changes=mutableListOf()
        probes.add(spy)}
        set("iptvSources",mutableListOf<IptvSourceEntry>())
        call("setupIptvOverlay",emptyArray())
        for(spy in probes){assertEquals(View.GONE,spy.visibility)
        assertEquals("both setup and core chrome set GONE",listOf(View.GONE,View.GONE),spy.changes)}
    }

    @Test fun favoritesButtonWithoutFavoriteSourcePinsToast() {
        activity.findViewById<View>(R.id.iptv_nav_favorites).performClick()
        assertEquals("No favorites source",ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_SHORT,ShadowToast.getLatestToast().duration)
        assertTrue(requests("requestIptvBrowse").isEmpty())
    }

    @Test fun modeLiveAndCloseButtonsUseInstalledCallbacks() {
        set("iptvContentType","vod")
        activity.findViewById<View>(R.id.iptv_mode_live).performClick()
        assertEquals("live",field("iptvContentType"))
        assertEquals("live",args("requestIptvBrowse")["contentType"])
        show()
        activity.findViewById<View>(R.id.iptv_nav_close).performClick()
        assertEquals(false,field("iptvGuideVisible"))
    }

    @Test fun destroyInvalidatesEpgBeforePlayerRelease() {
        set("iptvEpgToken",41)
        var atRelease: Int?=null
        probe.onEvent={event->if(event=="release"){atRelease=field("iptvEpgToken") as Int}}
        destroyNow()
        assertEquals("EPG generation retired before release",42,atRelease)
        assertEquals(42,field("iptvEpgToken"))
    }

    @Test fun missingGuideListHasNoFocusedEntry() {
        set("iptvGuideList",null)
        assertNull(call("focusedIptvGuideEntry",emptyArray()))
    }
}
