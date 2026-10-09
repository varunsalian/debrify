package com.debrify.app.tv

import android.view.View
import android.view.KeyEvent
import android.widget.TextView
import android.widget.ImageView
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.GridLayoutManager
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test

/** Inherited contracts run against seven independently bootstrapped activity instances. */
internal abstract class TvPlaylistSkinContracts : TvPhase13OriginalTest() {
    private fun installed() { assertEquals(skin != TvControlsSkin.CLASSIC,field("guideSkinInstalled")) }
    private fun density(n: Int) = (n*activity.resources.displayMetrics.density).toInt()
    private fun row(): View {
        val adapter=playlist().adapter as PlaylistAdapter
        adapter.setActiveIndex(0)
        val position=adapter.getActiveItemPosition()
        assertTrue("present current item is still in its selected season",position >= 0)
        adapter.setActiveIndex(-1)
        val holder=adapter.onCreateViewHolder(playlist(),adapter.getItemViewType(position))
        adapter.onBindViewHolder(holder,position)
        return holder.itemView
    }
    private fun current(): PlaybackItem = model().items[0].copy(title="alpha film",season=2,episode=4,
        durationMs=7_200_000L,description="  Description  ",rating=8.5,artwork=null)
    private fun detail(item: PlaybackItem=current()) = call("updateGuideDetail",arrayOf(PlaybackItem::class.java),item)

    @Test fun overlayLayoutManagerAndAllNullableSkinBindingsMatchRealXml() {
        installed()
        if(skin!=TvControlsSkin.CLASSIC)assertEquals("guide installation replaces the legacy overlay children",1,(overlay() as android.view.ViewGroup).childCount)
        val overlayRes=when(skin){TvControlsSkin.CLASSIC->null;TvControlsSkin.OTT->R.layout.view_tv_guide_ott;TvControlsSkin.FROST->R.layout.view_tv_guide_frost;TvControlsSkin.MARQUEE->R.layout.view_tv_guide_marquee;TvControlsSkin.BROADCAST->R.layout.view_tv_guide_broadcast;TvControlsSkin.PULSE->R.layout.view_tv_guide_pulse;TvControlsSkin.TICKET->R.layout.view_tv_guide_ticket}
        val itemRes=when(skin){TvControlsSkin.CLASSIC->R.layout.item_android_tv_playlist_entry_horizontal;TvControlsSkin.OTT->R.layout.item_tv_guide_ott;TvControlsSkin.FROST->R.layout.item_tv_guide_frost;TvControlsSkin.MARQUEE->R.layout.item_tv_guide_marquee;TvControlsSkin.BROADCAST->R.layout.item_tv_guide_broadcast;TvControlsSkin.PULSE->R.layout.item_tv_guide_pulse;TvControlsSkin.TICKET->R.layout.item_tv_guide_ticket}
        assertEquals(overlayRes,call("getGuideOverlayLayoutRes",emptyArray()))
        assertEquals(itemRes,call("getGuideItemLayoutRes",emptyArray()))
        set("guideSkinInstalled",false);assertEquals(R.layout.item_android_tv_playlist_entry_horizontal,call("getGuideItemLayoutRes",emptyArray()));set("guideSkinInstalled",skin!=TvControlsSkin.CLASSIC)
        val manager=playlist().layoutManager
        val vertical=skin in listOf(TvControlsSkin.MARQUEE,TvControlsSkin.FROST,TvControlsSkin.BROADCAST)
        assertTrue(manager is LinearLayoutManager)
        assertEquals(if(vertical || skin==TvControlsSkin.PULSE) LinearLayoutManager.VERTICAL else LinearLayoutManager.HORIZONTAL,(manager as LinearLayoutManager).orientation)
        assertFalse(manager.reverseLayout)
        if(skin==TvControlsSkin.PULSE){assertTrue(manager is GridLayoutManager);assertEquals(5,(manager as GridLayoutManager).spanCount)
            assertEquals(1,manager.spanSizeLookup.getSpanSize(0))
            (playlist().adapter as PlaylistAdapter).filterBySeason(null)
            assertEquals(5,manager.spanSizeLookup.getSpanSize(0))
            collection();assertEquals(1,(playlist().layoutManager as GridLayoutManager).spanSizeLookup.getSpanSize(0))
            set("playlistMode",PlaylistMode.SERIES);playlist().adapter=null
            assertEquals(1,(playlist().layoutManager as GridLayoutManager).spanSizeLookup.getSpanSize(0))}
        val bindings=mapOf("gdShowTitle" to R.id.gd_show_title,"gdCaption" to R.id.gd_caption,
            "gdDetailNum" to R.id.gd_detail_num,"gdDetailTitle" to R.id.gd_detail_title,"gdDetailMeta" to R.id.gd_detail_meta,
            "gdDetailDesc" to R.id.gd_detail_desc,"gdDetailArt" to R.id.gd_detail_art,"gdMonArt" to R.id.gd_mon_art,
            "gdMonLabel" to R.id.gd_mon_label,"gdPop" to R.id.gd_pop,"gdPopArt" to R.id.gd_pop_art,
            "gdPopTitle" to R.id.gd_pop_title,"gdPopDesc" to R.id.gd_pop_desc)
        for((name,id) in bindings)assertSame("skin binding $name",if(skin==TvControlsSkin.CLASSIC)null else activity.findViewById<View?>(id),field(name))
        val original=playlist();call("installGuideOverlaySkin",emptyArray());assertSame(original,activity.findViewById(R.id.android_tv_playlist))
        activity.getSharedPreferences("FlutterSharedPreferences",0).edit().putString("flutter."+TvControlsSkin.PREF_KEY,"classic").commit()
        assertEquals(skin,call("getControlsSkin",emptyArray()))
    }
    @Test fun seasonAndMovieTabsRetainEverySkinFontGeometryAndFocusValue() {
        installed()
        val expectedSize=when(skin){TvControlsSkin.CLASSIC,TvControlsSkin.OTT->13f;TvControlsSkin.MARQUEE,TvControlsSkin.PULSE->11.5f;TvControlsSkin.FROST->11f;TvControlsSkin.BROADCAST->10.5f;TvControlsSkin.TICKET->9f}
        val expectedPadding=when(skin){TvControlsSkin.FROST->listOf(11,4,11,4);TvControlsSkin.BROADCAST->listOf(8,3,8,3);TvControlsSkin.PULSE->listOf(10,5,10,5);TvControlsSkin.TICKET->listOf(6,1,6,1);else->null}
        fun check(tab: TextView){assertEquals(expectedSize,tab.textSize/activity.resources.displayMetrics.scaledDensity,0.01f)
            assertTrue(tab.isFocusable);assertTrue(tab.isFocusableInTouchMode);assertEquals(4f,tab.elevation,0f)
            assertEquals(if(skin==TvControlsSkin.MARQUEE)0.14f else 0.04f,tab.letterSpacing,0f)
            assertEquals(expectedPadding?.map{density(it)} ?: listOf(28,14,28,14),listOf(tab.paddingLeft,tab.paddingTop,tab.paddingRight,tab.paddingBottom))
            val lp=tab.layoutParams as android.widget.LinearLayout.LayoutParams
            assertEquals(if(skin==TvControlsSkin.PULSE)0 else 10,lp.marginEnd)
            assertEquals(if(skin==TvControlsSkin.PULSE)density(6) else 0,lp.bottomMargin)
            assertEquals(if(skin==TvControlsSkin.PULSE)-1 else -2,lp.width);assertEquals(-2,lp.height)
            if(skin in listOf(TvControlsSkin.OTT,TvControlsSkin.MARQUEE))assertNull(tab.background) else assertNotNull(tab.background)
            if(skin==TvControlsSkin.PULSE)assertEquals(android.view.Gravity.CENTER,tab.gravity)
            val face=when(skin){TvControlsSkin.MARQUEE->android.graphics.Typeface.create("serif",android.graphics.Typeface.BOLD);TvControlsSkin.BROADCAST->android.graphics.Typeface.create(android.graphics.Typeface.MONOSPACE,android.graphics.Typeface.BOLD);TvControlsSkin.TICKET->android.graphics.Typeface.MONOSPACE;else->android.graphics.Typeface.create("sans-serif-medium",android.graphics.Typeface.BOLD)}
            assertEquals(face,tab.typeface)
            val colorRes=when(skin){TvControlsSkin.OTT->R.color.gd_tab_text_light;TvControlsSkin.MARQUEE->R.color.gd_tab_text_marquee;TvControlsSkin.FROST,TvControlsSkin.BROADCAST->R.color.gd_tab_text_bcast;TvControlsSkin.PULSE->R.color.gd_tab_text_pulse;TvControlsSkin.TICKET->R.color.gd_tab_text_ticket;else->null}
            for(state in listOf(intArrayOf(),intArrayOf(android.R.attr.state_focused),intArrayOf(android.R.attr.state_selected)))assertEquals(colorRes?.let{androidx.core.content.ContextCompat.getColorStateList(activity,it)!!.getColorForState(state,-1)} ?: 0xFFFFFFFF.toInt(),tab.textColors.getColorForState(state,-1))
            val bg=when(skin){TvControlsSkin.CLASSIC->R.drawable.season_tab_selector;TvControlsSkin.FROST->R.drawable.gd_tab_frost;TvControlsSkin.BROADCAST->R.drawable.gd_tab_bcast;TvControlsSkin.PULSE->R.drawable.gd_tab_pulse;TvControlsSkin.TICKET->R.drawable.gd_tab_ticket;else->null}
            if(bg!=null)assertEquals(bg,org.robolectric.Shadows.shadowOf(tab.background).createdFromResId)
        }
        check(seasonTabs()[0])
        val restyled=TextView(activity).apply{textSize=7f}
        call("applyGuideTabStyle",arrayOf(TextView::class.java),restyled)
        assertEquals(if(skin==TvControlsSkin.CLASSIC)7f else expectedSize,restyled.textSize/activity.resources.displayMetrics.scaledDensity,0.01f)
        collection(listOf(org.json.JSONObject().put("name","one").put("fileIndices",org.json.JSONArray(listOf(0,1))),org.json.JSONObject().put("name","two").put("fileIndices",org.json.JSONArray(listOf(2)))))
        check(movieTabs()[0].view)
    }
    @Test fun detailFormattingDescriptionFallbackAndPopoverArePinned() {
        installed();detail()
        when(skin){
            TvControlsSkin.OTT->assertEquals("Description",text("gdCaption"))
            TvControlsSkin.MARQUEE->{assertEquals("04",text("gdDetailNum"));assertEquals("alpha film",text("gdDetailTitle"));assertEquals("SEASON 2 · EPISODE 4   ·   ★ 8.5   ·   120 MIN",text("gdDetailMeta"));assertEquals("Description",text("gdDetailDesc"))}
            TvControlsSkin.BROADCAST->assertEquals("PVW · S02E04",text("gdMonLabel"))
            TvControlsSkin.PULSE->assertEquals("E4 · alpha film — Description",text("gdDetailDesc"))
            TvControlsSkin.TICKET->{assertEquals(View.VISIBLE,(field("gdPop") as View).visibility);assertEquals("S02E04 · ALPHA FILM",text("gdPopTitle"));assertEquals("Description",text("gdPopDesc"))}
            else->assertNull(text("gdDetailTitle"))}
        detail(current().copy(season=null,episode=null,description=" nUlL ",rating=0.0,durationMs=0))
        when(skin){TvControlsSkin.OTT->assertEquals("",text("gdCaption"));TvControlsSkin.MARQUEE->{assertEquals("",text("gdDetailNum"));assertEquals("",text("gdDetailMeta"));assertEquals("",text("gdDetailDesc"))};TvControlsSkin.BROADCAST->assertEquals("PVW · ALPHA FILM",text("gdMonLabel"));TvControlsSkin.PULSE->assertEquals("alpha film",text("gdDetailDesc"));TvControlsSkin.TICKET->{assertEquals("ALPHA FILM",text("gdPopTitle"));assertEquals("",text("gdPopDesc"))};else->Unit}
        detail(current().copy(description=null))
        if(skin==TvControlsSkin.TICKET)assertEquals("120m · ★ 8.5",text("gdPopDesc"))
        val artworkTarget=when(skin){TvControlsSkin.MARQUEE->"gdDetailArt";TvControlsSkin.BROADCAST->"gdMonArt";TvControlsSkin.TICKET->"gdPopArt";else->null}
        if(artworkTarget!=null) {
            val image=field(artworkTarget) as ImageView
            detail(current().copy(artwork="file:///phase13-detail.jpg"))
            val request=com.bumptech.glide.request.target.DrawableImageViewTarget(image).request
            assertNotNull("detail updates the bound $artworkTarget",request)
            assertEquals("file:///phase13-detail.jpg",org.robolectric.util.ReflectionHelpers.getField<Any>(request,"model"))
            assertTrue(TvPlayerOriginalAccess.glideTracks(com.bumptech.glide.Glide.with(activity),request!!))
            detail(current().copy(artwork=null));assertNull(com.bumptech.glide.request.target.DrawableImageViewTarget(image).request)
        }
    }
    @Test fun seriesAndMovieAdapterFunctionReferencesReachTheSameGuideBinder() {
        installed();model().items[0]=current().copy(watched=true)
        rebuild();(playlist().adapter as PlaylistOverlayAdapter).setActiveIndex(-1)
        fun check(view: View){
            val title=view.findViewById<TextView?>(R.id.android_tv_playlist_item_title)
            when(skin){TvControlsSkin.MARQUEE,TvControlsSkin.TICKET->assertTrue(title!!.paintFlags and android.graphics.Paint.STRIKE_THRU_TEXT_FLAG !=0)
                TvControlsSkin.BROADCAST->{assertEquals("204",view.findViewById<TextView>(R.id.gd_item_num).text.toString());assertEquals("CLEARED",view.findViewById<TextView>(R.id.gd_item_status).text.toString())}
                TvControlsSkin.PULSE->{assertEquals(100,view.findViewById<android.widget.ProgressBar>(R.id.gd_ring).progress);assertEquals("4",view.findViewById<TextView>(R.id.gd_ring_num).text.toString())}
                else->assertEquals("alpha film",title?.text?.toString())}}
        // Current season changed to two; the real season selection chooses that row.
        val seriesRow=row();check(seriesRow)
        fun focusDetail(view: View) {
            val container=view.findViewById<View>(R.id.android_tv_playlist_item_container)
            container.onFocusChangeListener.onFocusChange(container,true)
            when(skin){TvControlsSkin.OTT->assertEquals("Description",text("gdCaption"));TvControlsSkin.MARQUEE->assertEquals("alpha film",text("gdDetailTitle"));TvControlsSkin.BROADCAST->assertEquals("PVW · S02E04",text("gdMonLabel"));TvControlsSkin.PULSE->assertEquals("E4 · alpha film — Description",text("gdDetailDesc"));TvControlsSkin.TICKET->assertEquals("S02E04 · ALPHA FILM",text("gdPopTitle"));else->assertNull(text("gdDetailTitle"))}
        }
        focusDetail(seriesRow)
        collection();(playlist().adapter as PlaylistOverlayAdapter).setActiveIndex(-1)
        val a=playlist().adapter as MoviePlaylistAdapter;val h=a.onCreateViewHolder(playlist(),0);a.onBindViewHolder(h,0);check(h.itemView);focusDetail(h.itemView)
    }
    @Test fun showChromePinsCountsUppercaseAndHidePopover() {
        installed();set("ottShowName","Mixed case");model().items[0]=current().copy(watched=true)
        showPlaylist()
        assertEquals(View.VISIBLE,overlay().visibility);assertEquals(1f,overlay().alpha,0f);assertNull(overlay().animation);assertTrue(field("playlistVisible") as Boolean)
        if(skin!=TvControlsSkin.CLASSIC)assertEquals(if(skin==TvControlsSkin.BROADCAST||skin==TvControlsSkin.TICKET)"MIXED CASE" else "Mixed case",text("gdShowTitle"))
        when(skin){TvControlsSkin.FROST,TvControlsSkin.PULSE->assertEquals("3 episodes · 1 watched",text("gdCaption"));TvControlsSkin.BROADCAST->assertEquals("3 LISTED · OK ROLLS THE FOCUSED ITEM",text("gdCaption"));TvControlsSkin.OTT->assertEquals("Description",text("gdCaption"));else->Unit}
        hidePlaylist();assertFalse(field("playlistVisible") as Boolean);assertEquals(View.GONE,overlay().visibility)
        if(skin==TvControlsSkin.TICKET)assertEquals(View.GONE,(field("gdPop") as View).visibility)
    }
    @Test fun installedKeyAxesConsumeAndEscapeAtTheOriginalEdges() {
        installed();set("playlistVisible",true)
        set("navigationTargetPosition",0)
        val vertical=skin in listOf(TvControlsSkin.MARQUEE,TvControlsSkin.FROST,TvControlsSkin.BROADCAST)
        assertEquals(skin==TvControlsSkin.PULSE,key(KeyEvent.KEYCODE_DPAD_UP))
        assertFalse(key(KeyEvent.KEYCODE_DPAD_LEFT,KeyEvent.ACTION_UP))
        if(vertical){assertFalse(key(KeyEvent.KEYCODE_DPAD_UP));assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT));assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT));assertEquals(0,target())
            assertTrue(key(KeyEvent.KEYCODE_DPAD_DOWN));assertEquals(1,target())}
        else if(skin==TvControlsSkin.PULSE){assertFalse(key(KeyEvent.KEYCODE_DPAD_LEFT));assertTrue(key(KeyEvent.KEYCODE_DPAD_UP));assertEquals(0,target())
            assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT));assertEquals(1,target())}
        else {assertFalse(key(KeyEvent.KEYCODE_DPAD_DOWN));assertTrue(key(KeyEvent.KEYCODE_DPAD_RIGHT));assertEquals(1,target());assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT));assertEquals(0,target())}
        if(vertical){set("navigationTargetPosition",1);assertTrue(key(KeyEvent.KEYCODE_DPAD_UP));assertEquals(0,target())}
        if(skin==TvControlsSkin.PULSE){
            set("navigationTargetPosition",1);assertTrue(key(KeyEvent.KEYCODE_DPAD_LEFT));assertEquals(0,target())
            set("navigationTargetPosition",5);assertTrue(key(KeyEvent.KEYCODE_DPAD_UP));assertEquals(0,target())
            set("navigationTargetPosition",0);assertTrue(key(KeyEvent.KEYCODE_DPAD_DOWN));assertEquals(-1,target())
        }
        set("playlistVisible",false);assertFalse(key(KeyEvent.KEYCODE_DPAD_RIGHT))
        assertFalse(key(KeyEvent.KEYCODE_ENTER))
    }
    @Test fun binderThresholdsActiveStateAndNumberFallbacksUseTheRealSkinViews() {
        installed()
        val res=call("getGuideItemLayoutRes",emptyArray()) as Int
        fun bind(percent: Int,index: Int,active: Boolean,episode: Int?): View {
            val v=android.view.LayoutInflater.from(activity).inflate(res,playlist(),false)
            val item=current().copy(episode=episode,watched=false,traktProgressPercent=percent.toDouble(),resumePositionMs=0,allowLocalProgressDisplay=true)
            call("guideSkinBind",arrayOf(View::class.java,PlaybackItem::class.java,intType,boolType),v,item,index,active)
            return v
        }
        for(percent in listOf(0,94,95,100))for(active in listOf(false,true)) {
            val v=bind(percent,2,active,null)
            when(skin) {
                TvControlsSkin.MARQUEE,TvControlsSkin.TICKET -> {
                    val title=v.findViewById<TextView>(R.id.android_tv_playlist_item_title)
                    assertEquals(percent>=95 && !active,title.paintFlags and android.graphics.Paint.STRIKE_THRU_TEXT_FLAG !=0)
                    if(skin==TvControlsSkin.MARQUEE)assertEquals("3",v.findViewById<TextView>(R.id.gd_item_num).text.toString())
                }
                TvControlsSkin.PULSE -> { assertEquals(if(percent>=95)100 else percent,v.findViewById<android.widget.ProgressBar>(R.id.gd_ring).progress);assertEquals("3",v.findViewById<TextView>(R.id.gd_ring_num).text.toString()) }
                TvControlsSkin.BROADCAST -> assertEquals(if(active)"● ON AIR" else if(percent>=95)"CLEARED" else if(percent==94)"94% IN" else "READY",v.findViewById<TextView>(R.id.gd_item_status).text.toString())
                else -> assertNotNull(v.findViewById<TextView>(R.id.android_tv_playlist_item_title))
            }
        }
        val absent=bind(0,-1,false,null)
        if(skin==TvControlsSkin.MARQUEE)assertEquals("·",absent.findViewById<TextView>(R.id.gd_item_num).text.toString())
        if(skin==TvControlsSkin.PULSE)assertEquals("?",absent.findViewById<TextView>(R.id.gd_ring_num).text.toString())
    }
    @Test fun detailPartialEpisodeMinuteRatingAndBlankDescriptionBoundaries() {
        installed()
        for(ms in listOf(59_999L,60_000L)) {
            detail(current().copy(season=null,episode=4,description=" ",durationMs=ms,rating=-1.0))
            when(skin) {
                TvControlsSkin.MARQUEE->{assertEquals("04",text("gdDetailNum"));assertEquals(if(ms==60_000L)"1 MIN" else "",text("gdDetailMeta"));assertEquals("",text("gdDetailDesc"))}
                TvControlsSkin.TICKET->{assertEquals("ALPHA FILM",text("gdPopTitle"));assertEquals(if(ms==60_000L)"1m" else "",text("gdPopDesc"))}
                TvControlsSkin.BROADCAST->assertEquals("PVW · ALPHA FILM",text("gdMonLabel"))
                TvControlsSkin.PULSE->assertEquals("E4 · alpha film",text("gdDetailDesc"))
                TvControlsSkin.OTT->assertEquals("",text("gdCaption"))
                else->assertNull(text("gdDetailMeta"))
            }
        }
        detail(current().copy(season=2,episode=null,description="",rating=null,durationMs=0))
        if(skin==TvControlsSkin.MARQUEE){assertEquals("",text("gdDetailNum"));assertEquals("",text("gdDetailMeta"))}
        if(skin==TvControlsSkin.TICKET){assertEquals("ALPHA FILM",text("gdPopTitle"));assertEquals("",text("gdPopDesc"))}
        call("bindGuideSkinViews",emptyArray())
        set("payload",model().copy(items=mutableListOf(model().items[0])));set("ottShowName",null)
        call("seedGuideSkinChrome",emptyArray())
        if(skin!=TvControlsSkin.CLASSIC)assertEquals(if(skin in listOf(TvControlsSkin.TICKET,TvControlsSkin.BROADCAST))"EPISODE ONE" else "Episode one",text("gdShowTitle"))
    }

}
