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
internal class TvIptvEditionChromeCharacterizationTest : TvPhase12OriginalTest() {
    override val phase12Style = GuideStyle.EDITION

    @Test fun realBootstrapBuildsBothAdaptersAndPinsStyleRowGeometry() {
        assertEquals(GuideStyle.EDITION,call("getGuideStyle",emptyArray()))
        assertSame(boundAdapter(),guideList().adapter)
        assertNull(guideList().itemAnimator)
        assertTrue(guideList().layoutManager is androidx.recyclerview.widget.LinearLayoutManager)
        assertSame(epgAdapter(),(v("iptvEpgList") as RecyclerView).adapter)
        assertTrue("EPG vertical manager",(v("iptvEpgList") as RecyclerView).layoutManager is androidx.recyclerview.widget.LinearLayoutManager)
        fun property(o: Any,name: String): Any? = o.javaClass.getDeclaredField(name).apply{isAccessible=true}.get(o)
        val radius=density(8).toFloat()
        for(a in listOf(boundAdapter(),epgAdapter())){assertEquals(GuideStyle.EDITION,property(a,"style"))
        assertSame(GuideTokens.of(GuideStyle.EDITION),property(a,"tokens"))
        assertEquals(radius,property(a,"rowRadiusPx"))
        assertEquals(density(2),property(a,"rowStrokePx"))}
        assertTrue(activity.findViewById<View>(R.id.iptv_nav_browse).isSelected)
        for(id in listOf(R.id.iptv_nav_favorites,R.id.iptv_nav_sources,R.id.iptv_source_button))assertEquals(View.VISIBLE,activity.findViewById<View>(id).visibility)
        activity.getSharedPreferences("FlutterSharedPreferences",0).edit().putString("flutter.iptv_player_guide_style","other").commit()
        assertEquals("cached for this activity instance",GuideStyle.EDITION,call("getGuideStyle",emptyArray()))
    }

    @Test fun styledPassPinsEveryOverlayColorAndGeometry() {
        val tokens=GuideTokens.of(phase12Style)!!
        fun tv(id: Int)=activity.findViewById<TextView>(id)
        fun color(id: Int,expected: Int){assertEquals("text color id=$id",expected,tv(id).currentTextColor)}
        fun background(id: Int):android.graphics.drawable.GradientDrawable{val drawable=activity.findViewById<View>(id).background
        assertTrue("styled surface id=$id",drawable is android.graphics.drawable.GradientDrawable)
        return drawable as android.graphics.drawable.GradientDrawable}
        for(id in listOf(R.id.iptv_guide_panel,R.id.iptv_epg_panel,R.id.iptv_guide_now_playing)){val d=background(id)
        assertEquals(density(10).toFloat(),d.cornerRadius,0f)
        assertEquals(tokens.panel,d.color?.defaultColor)
        val state: Any=org.robolectric.util.ReflectionHelpers.getField(d,"mGradientState")
        assertEquals(density(1),org.robolectric.util.ReflectionHelpers.getField<Int>(state,"mStrokeWidth"))
        assertEquals(tokens.hairline2,org.robolectric.util.ReflectionHelpers.getField<android.content.res.ColorStateList?>(state,"mStrokeColors")?.defaultColor)}
        for(id in listOf(R.id.iptv_nav_rail,R.id.iptv_mode_tabs,R.id.iptv_epg_day_tabs))assertEquals(tokens.bg,(activity.findViewById<View>(id).background as android.graphics.drawable.ColorDrawable).color)
        assertEquals(tokens.hairline,(activity.findViewById<View>(R.id.iptv_rail_divider).background as android.graphics.drawable.ColorDrawable).color)
        assertEquals(tokens.fg,(tv(R.id.iptv_nav_logo).background as android.graphics.drawable.ColorDrawable).color)
        color(R.id.iptv_nav_logo,tokens.bg or 0xFF000000.toInt())
        for(id in listOf(R.id.iptv_guide_title,R.id.iptv_epg_channel_name,R.id.iptv_epg_letter,R.id.iptv_guide_now_letter,R.id.iptv_guide_current_name))color(id,tokens.fg)
        for(id in listOf(R.id.iptv_guide_count,R.id.iptv_epg_channel_group,R.id.iptv_footer_play,R.id.iptv_footer_schedule,R.id.iptv_footer_favorite,R.id.iptv_epg_footer_channels,R.id.iptv_epg_footer_replay,R.id.iptv_guide_current_group))color(id,tokens.fgFaint)
        color(R.id.iptv_epg_date,tokens.fgMid)
        color(R.id.iptv_epg_empty,tokens.fgDim)
        color(R.id.iptv_guide_current_epg,tokens.live)
        for(id in listOf(R.id.iptv_guide_kicker,R.id.iptv_epg_kicker))color(id,tokens.fgDim)
        for(id in listOf(R.id.iptv_browse_loading,R.id.iptv_epg_loading))assertEquals(tokens.accent,activity.findViewById<android.widget.ProgressBar>(id).indeterminateTintList?.defaultColor)
        for(id in listOf(R.id.iptv_epg_logo_tile,R.id.iptv_guide_now_logo_tile)){val d=background(id)
        assertEquals(density(24).toFloat(),d.cornerRadius,0f)
        assertEquals(tokens.selectedTint,d.color?.defaultColor)
        val state: Any=org.robolectric.util.ReflectionHelpers.getField(d,"mGradientState")
        assertEquals(density(1),org.robolectric.util.ReflectionHelpers.getField<Int>(state,"mStrokeWidth"))
        assertEquals(tokens.hairline,org.robolectric.util.ReflectionHelpers.getField<android.content.res.ColorStateList?>(state,"mStrokeColors")?.defaultColor)}
        val searchBg=search().background as android.graphics.drawable.StateListDrawable
        for(focused in listOf(false,true)){searchBg.state=if(focused) intArrayOf(android.R.attr.state_focused) else intArrayOf()
        val d=searchBg.current as android.graphics.drawable.GradientDrawable
        assertEquals(density(8).toFloat(),d.cornerRadius,0f)
        assertEquals(tokens.focusTint,d.color?.defaultColor)
        val state: Any=org.robolectric.util.ReflectionHelpers.getField(d,"mGradientState")
        assertEquals(if(focused) 2 else 1,org.robolectric.util.ReflectionHelpers.getField<Int>(state,"mStrokeWidth"))
        assertEquals(if(focused) tokens.accent else tokens.hairline,org.robolectric.util.ReflectionHelpers.getField<android.content.res.ColorStateList?>(state,"mStrokeColors")?.defaultColor)}
        assertEquals(tokens.fg,search().currentTextColor)
        assertEquals(tokens.fgFaint,search().currentHintTextColor)
        assertEquals(tokens.fgFaint,androidx.core.widget.TextViewCompat.getCompoundDrawableTintList(search())?.defaultColor)
        val ids=listOf(R.id.iptv_nav_browse,R.id.iptv_nav_search,R.id.iptv_nav_favorites,R.id.iptv_nav_sources,R.id.iptv_nav_close,R.id.iptv_source_button,R.id.iptv_category_button,R.id.iptv_mode_live,R.id.iptv_epg_day_three_ago,R.id.iptv_epg_day_two_ago,R.id.iptv_epg_day_yesterday,R.id.iptv_epg_day_today,R.id.iptv_epg_day_tomorrow,R.id.iptv_epg_day_later)
        for(id in ids){val b=tv(id)
        assertEquals(tokens.fgDim,b.textColors.defaultColor)
        assertEquals(tokens.bg or 0xFF000000.toInt(),b.textColors.getColorForState(intArrayOf(android.R.attr.state_focused),0))
        assertEquals(tokens.fg,b.textColors.getColorForState(intArrayOf(android.R.attr.state_selected),0))
        assertEquals(b.textColors,androidx.core.widget.TextViewCompat.getCompoundDrawableTintList(b))
        assertTrue(b.background is android.graphics.drawable.StateListDrawable)
        val bg=b.background as android.graphics.drawable.StateListDrawable
        bg.state=intArrayOf()
        assertEquals(density(8).toFloat(),(bg.current as android.graphics.drawable.GradientDrawable).cornerRadius,0f)}
    }

    @Test fun categoryDialogPinsStyleAndInnerTintReceiver() {
        call("showIptvCategoryPicker",emptyArray())
        val d=dialog()
        val input=dialogInput()
        val tokens=GuideTokens.of(phase12Style)
        assertEquals("Search categories",input.hint)
        assertEquals(android.text.InputType.TYPE_CLASS_TEXT,input.inputType)
        assertEquals(EditorInfo.IME_ACTION_DONE,input.imeOptions)
        assertEquals(1,input.maxLines)
        assertNotNull(input.compoundDrawables[0])
        assertEquals(density(10),input.compoundDrawablePadding)
        assertEquals(density(16),input.paddingLeft)
        assertEquals(density(16),input.paddingRight)
        val fieldBg=input.background
        assertTrue("category search has focus selector",fieldBg is android.graphics.drawable.StateListDrawable)
        val selector=fieldBg as android.graphics.drawable.StateListDrawable
        for(focused in listOf(false,true)){selector.state=if(focused) intArrayOf(android.R.attr.state_focused) else intArrayOf()
        val d=selector.current
        assertTrue(d is android.graphics.drawable.GradientDrawable)
        val shape=d as android.graphics.drawable.GradientDrawable
        assertEquals(density(if(tokens==null)12 else 10).toFloat(),shape.cornerRadius,0f)
        assertEquals(tokens?.focusTint ?: if(focused)0x14FFFFFF else 0x0AFFFFFF,shape.color?.defaultColor)}
        assertEquals(tokens?.fg ?: android.graphics.Color.WHITE,input.currentTextColor)
        assertEquals(tokens?.fgFaint ?: 0x80FFFFFF.toInt(),input.currentHintTextColor)
        assertEquals(tokens?.fgFaint ?: 0xB3FFFFFF.toInt(),androidx.core.widget.TextViewCompat.getCompoundDrawableTintList(input)?.defaultColor)
        assertEquals(tokens?.fgDim ?: 0xB3FFFFFF.toInt(),status("2 categories").currentTextColor)
        assertEquals(density(2),status("2 categories").paddingLeft)
        assertEquals(density(12),status("2 categories").paddingTop)
        assertEquals(density(2),status("2 categories").paddingRight)
        assertEquals(density(8),status("2 categories").paddingBottom)
        if(tokens!=null){val rawBg=d.window!!.decorView.background
        assertTrue("styled dialog gets opaque painter",rawBg is android.graphics.drawable.GradientDrawable)
        val bg=rawBg as android.graphics.drawable.GradientDrawable
        assertEquals(density(18).toFloat(),bg.cornerRadius,0f)
        assertEquals(tokens.panelOpaque,bg.color?.defaultColor)
        val state: Any=org.robolectric.util.ReflectionHelpers.getField(bg,"mGradientState")
        assertEquals(density(1),org.robolectric.util.ReflectionHelpers.getField<Int>(state,"mStrokeWidth"))
        assertEquals(tokens.hairline2,org.robolectric.util.ReflectionHelpers.getField<android.content.res.ColorStateList?>(state,"mStrokeColors")?.defaultColor)}
        val list=dialogList()
        val manager=list.layoutManager
        assertTrue("category has its vertical manager",manager is androidx.recyclerview.widget.LinearLayoutManager)
        manager as androidx.recyclerview.widget.LinearLayoutManager
        assertEquals(androidx.recyclerview.widget.LinearLayoutManager.VERTICAL,manager.orientation)
        assertFalse(manager.reverseLayout)
        assertTrue(list.isFocusable)
        assertTrue(input.id!=list.id)
        val a=list.adapter as IptvCategoryAdapter
        val holder=a.onCreateViewHolder(list,0)
        a.onBindViewHolder(holder,0)
        assertEquals(input.id,holder.label.nextFocusUpId)
        assertEquals(density(8).toFloat(),org.robolectric.util.ReflectionHelpers.getField<Float>(a,"rowRadiusPx"),0f)
        assertEquals(tokens,org.robolectric.util.ReflectionHelpers.getField<GuideTokens?>(a,"tokens"))
        assertEquals(13f,status("2 categories").textSize/activity.resources.displayMetrics.scaledDensity,0.01f)
        assertEquals(listOf("All categories","News","Movies"),categoryLabels())
    }

    @Test fun listDialogPinsStyleLayoutAndLoadingStatus() {
        seedLists(listOf(IptvListEntry("custom","Custom",false)))
        lists(entry())
        val d=dialog()
        val list=dialogList()
        val label=status("Loading lists…")
        val tokens=GuideTokens.of(phase12Style)
        val manager=list.layoutManager
        assertTrue("list has its vertical manager",manager is androidx.recyclerview.widget.LinearLayoutManager)
        manager as androidx.recyclerview.widget.LinearLayoutManager
        assertEquals(androidx.recyclerview.widget.LinearLayoutManager.VERTICAL,manager.orientation)
        assertFalse(manager.reverseLayout)
        val a=list.adapter as IptvListPickerAdapter
        assertEquals(tokens,org.robolectric.util.ReflectionHelpers.getField<GuideTokens?>(a,"tokens"))
        assertEquals(density(8).toFloat(),org.robolectric.util.ReflectionHelpers.getField<Float>(a,"rowRadiusPx"),0f)
        assertEquals(tokens?.fgDim ?: 0xB3FFFFFF.toInt(),label.currentTextColor)
        assertEquals(13f,label.textSize/activity.resources.displayMetrics.scaledDensity,0.01f)
        assertEquals(density(2),label.paddingLeft)
        assertEquals(density(4),label.paddingTop)
        assertEquals(density(8),label.paddingBottom)
        assertEquals(density(16),list.paddingBottom)
        assertFalse(list.clipToPadding)
        assertEquals(minOf(density(400),(activity.resources.displayMetrics.heightPixels*0.5f).toInt()),list.layoutParams.height)
        assertEquals("alpha",d.findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
        assertEquals(android.widget.LinearLayout.VERTICAL,(list.parent as android.widget.LinearLayout).orientation)
        assertEquals(density(24),(list.parent as View).paddingLeft)
        assertEquals(density(8),(list.parent as View).paddingTop)
        assertEquals(android.view.ViewGroup.LayoutParams.MATCH_PARENT,list.layoutParams.width)
        assertTrue(list.isFocusable)
        assertEquals("Done",d.getButton(AlertDialog.BUTTON_NEGATIVE).text.toString())
        if(tokens!=null){val rawBg=d.window!!.decorView.background
        assertTrue("styled dialog gets opaque painter",rawBg is android.graphics.drawable.GradientDrawable)
        val bg=rawBg as android.graphics.drawable.GradientDrawable
        assertEquals(density(18).toFloat(),bg.cornerRadius,0f)
        assertEquals(tokens.panelOpaque,bg.color?.defaultColor)
        val state: Any=org.robolectric.util.ReflectionHelpers.getField(bg,"mGradientState")
        assertEquals(density(1),org.robolectric.util.ReflectionHelpers.getField<Int>(state,"mStrokeWidth"))
        assertEquals(tokens.hairline2,org.robolectric.util.ReflectionHelpers.getField<android.content.res.ColorStateList?>(state,"mStrokeColors")?.defaultColor)}
        assertEquals(0,list.adapter!!.itemCount)
    }
}
