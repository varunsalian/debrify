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
internal class TvIptvClassicChromeCharacterizationTest : TvPhase12OriginalTest() {
    override val phase12Style = GuideStyle.CLASSIC

    @Test fun realBootstrapBuildsBothAdaptersAndPinsStyleRowGeometry() {
        assertEquals(GuideStyle.CLASSIC,call("getGuideStyle",emptyArray()))
        assertSame(boundAdapter(),guideList().adapter)
        assertNull(guideList().itemAnimator)
        assertTrue(guideList().layoutManager is androidx.recyclerview.widget.LinearLayoutManager)
        assertSame(epgAdapter(),(v("iptvEpgList") as RecyclerView).adapter)
        assertTrue("EPG vertical manager",(v("iptvEpgList") as RecyclerView).layoutManager is androidx.recyclerview.widget.LinearLayoutManager)
        fun property(o: Any,name: String): Any? = o.javaClass.getDeclaredField(name).apply{isAccessible=true}.get(o)
        val radius=density(3).toFloat()
        for(a in listOf(boundAdapter(),epgAdapter())){assertEquals(GuideStyle.CLASSIC,property(a,"style"))
        assertSame(GuideTokens.of(GuideStyle.CLASSIC),property(a,"tokens"))
        assertEquals(radius,property(a,"rowRadiusPx"))
        assertEquals(density(2),property(a,"rowStrokePx"))}
        assertTrue(activity.findViewById<View>(R.id.iptv_nav_browse).isSelected)
        for(id in listOf(R.id.iptv_nav_favorites,R.id.iptv_nav_sources,R.id.iptv_source_button))assertEquals(View.VISIBLE,activity.findViewById<View>(id).visibility)
        activity.getSharedPreferences("FlutterSharedPreferences",0).edit().putString("flutter.iptv_player_guide_style","other").commit()
        assertEquals("cached for this activity instance",GuideStyle.CLASSIC,call("getGuideStyle",emptyArray()))
    }

    @Test fun classicStylePreservesXmlAndBootstrapSelection() {
        val panel=activity.findViewById<View>(R.id.iptv_guide_panel)
        val original=panel.background
        call("applyGuideStyle",emptyArray())
        assertSame("classic keeps original XML",original,panel.background)
        assertNull(call("getGuideTokens",emptyArray()))
        assertTrue(activity.findViewById<View>(R.id.iptv_nav_browse).isSelected)
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

    @Test fun legacyButtonPassRestoresEveryPremiumSelector() {
        val ids=listOf(R.id.iptv_nav_browse,R.id.iptv_nav_search,R.id.iptv_nav_favorites,R.id.iptv_nav_sources,R.id.iptv_nav_close,R.id.iptv_source_button,R.id.iptv_category_button,R.id.iptv_mode_live,R.id.iptv_epg_day_three_ago,R.id.iptv_epg_day_two_ago,R.id.iptv_epg_day_yesterday,R.id.iptv_epg_day_today,R.id.iptv_epg_day_tomorrow,R.id.iptv_epg_day_later)
        for(id in ids)activity.findViewById<TextView>(id).setTextColor(android.graphics.Color.MAGENTA)
        call("setupIptvOverlay",emptyArray())
        val expected=androidx.core.content.ContextCompat.getColorStateList(activity,R.color.iptv_premium_button_text)!!
        for(id in ids){val actual=activity.findViewById<TextView>(id).textColors
        for(state in listOf(intArrayOf(),intArrayOf(android.R.attr.state_focused),intArrayOf(android.R.attr.state_selected)))assertEquals(expected.getColorForState(state,0),actual.getColorForState(state,0))}
    }
}
