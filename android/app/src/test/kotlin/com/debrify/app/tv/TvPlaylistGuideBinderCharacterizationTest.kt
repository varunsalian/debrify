package com.debrify.app.tv

import android.view.View
import android.view.LayoutInflater
import android.widget.TextView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistGuideBinderCharacterizationTest : TvPhase13OriginalTest() {
    override val skin=TvControlsSkin.BROADCAST
    private fun bind(item: PlaybackItem,index: Int=0,active: Boolean=false): View {
        val view=LayoutInflater.from(activity).inflate(R.layout.item_tv_guide_broadcast,playlist(),false)
        call("guideSkinBind",arrayOf(View::class.java,PlaybackItem::class.java,intType,boolType),view,item,index,active)
        return view
    }
    private fun label(view: View,id: Int) = view.findViewById<TextView>(id).text.toString()
    @Test fun broadcastStatusPriorityAndEveryProgressBoundary() {
        val original=model().items[0].copy(allowLocalProgressDisplay=true,resumePositionMs=0,watched=false,traktProgressPercent=null)
        val cases=listOf(0 to "READY",5 to "READY",6 to "6% IN",94 to "94% IN",95 to "CLEARED",100 to "CLEARED")
        for((percent,status) in cases){val view=bind(original.copy(traktProgressPercent=percent.toDouble()))
            assertEquals(status,label(view,R.id.gd_item_status))
            val colors=view.findViewById<TextView>(R.id.gd_item_status).textColors
            assertEquals(0xDE000000.toInt(),colors.getColorForState(intArrayOf(android.R.attr.state_focused),0))
            assertEquals(if(percent>=95)0x66FFFFFF else 0x8CFFFFFF.toInt(),colors.defaultColor)}
        assertEquals("FETCH",label(bind(original.copy(url=""),-1),R.id.gd_item_status))
        assertEquals("READY",label(bind(original,-1),R.id.gd_item_status))
        assertEquals("● ON AIR",label(bind(original.copy(url="",watched=true),-1,true),R.id.gd_item_status))
        assertEquals(0xFFEF4444.toInt(),bind(original,0,true).findViewById<TextView>(R.id.gd_item_status).textColors.defaultColor)
        assertEquals(0xFFF5C518.toInt(),bind(original.copy(url=""),-1).findViewById<TextView>(R.id.gd_item_status).textColors.defaultColor)
    }
    @Test fun broadcastNumberTransformsPinSeasonEpisodeIndexAndAbsentFallbacks() {
        val item=model().items[0]
        assertEquals("204",label(bind(item.copy(season=2,episode=4)),R.id.gd_item_num))
        assertEquals("004",label(bind(item.copy(season=null,episode=4)),R.id.gd_item_num))
        assertEquals("003",label(bind(item.copy(season=null,episode=null),2),R.id.gd_item_num))
        assertEquals("———",label(bind(item.copy(season=null,episode=null),-1),R.id.gd_item_num))
    }
    @Test fun bindFocusedCallbacksFromBothAdaptersUpdateRealDetailSurface() {
        for(i in model().items.indices)model().items[i]=model().items[i].copy(season=null,episode=null)
        model().items[0]=model().items[0].copy(title="Focused")
        rebuild()
        val a=playlist().adapter as PlaylistAdapter;val h=a.onCreateViewHolder(playlist(),1);a.onBindViewHolder(h,0)
        val container=h.itemView.findViewById<View>(R.id.android_tv_playlist_item_container)
        container.onFocusChangeListener.onFocusChange(container,true)
        assertEquals("PVW · FOCUSED",text("gdMonLabel"))
        model().items[0]=model().items[0].copy(title="Movie focus")
        collection();val movie=playlist().adapter as MoviePlaylistAdapter;val m=movie.onCreateViewHolder(playlist(),0);movie.onBindViewHolder(m,0)
        val c=m.itemView.findViewById<View>(R.id.android_tv_playlist_item_container)
        c.onFocusChangeListener.onFocusChange(c,true)
        assertEquals("PVW · MOVIE FOCUS",text("gdMonLabel"))
        c.onFocusChangeListener.onFocusChange(c,false)
        assertEquals("PVW · MOVIE FOCUS",text("gdMonLabel"))
    }
    @Test fun seedTitleFallbacksAndCountsUseLivePayloadAndCurrentIndex() {
        set("ottShowName"," ");call("seedGuideSkinChrome",emptyArray())
        assertEquals("EPISODE ONE",text("gdShowTitle"));assertEquals("3 LISTED · OK ROLLS THE FOCUSED ITEM",text("gdCaption"))
        set("currentIndex",2);call("seedGuideSkinChrome",emptyArray());assertEquals("EPISODE THREE",text("gdShowTitle"))
        set("payload",null);call("seedGuideSkinChrome",emptyArray());assertEquals("",text("gdShowTitle"))
    }
    @Test fun disabledSkinGuardsPreserveSentinelBindingsManagerListenerAndStyle() {
        set("guideSkinInstalled",false)
        val title=TextView(activity).apply{text="sentinel title"};val caption=TextView(activity).apply{text="sentinel caption"}
        val monitor=TextView(activity).apply{text="sentinel monitor"}
        set("gdShowTitle",title);set("gdCaption",caption);set("gdMonLabel",monitor)
        val manager=playlist().layoutManager
        val info=org.robolectric.util.ReflectionHelpers.getField<Any>(playlist(),"mListenerInfo")
        val listener=org.robolectric.util.ReflectionHelpers.getField<View.OnKeyListener>(info,"mOnKeyListener")
        val tab=TextView(activity).apply{textSize=7f;setPadding(1,2,3,4)}
        call("bindGuideSkinViews",emptyArray());assertSame(title,field("gdShowTitle"));assertSame(caption,field("gdCaption"));assertSame(monitor,field("gdMonLabel"))
        call("applyGuideLayoutManager",emptyArray());assertSame(manager,playlist().layoutManager)
        call("applyGuideKeyOverride",emptyArray());assertSame(listener,org.robolectric.util.ReflectionHelpers.getField<View.OnKeyListener>(info,"mOnKeyListener"))
        call("applyGuideTabStyle",arrayOf(TextView::class.java),tab);assertEquals(7f,tab.textSize/activity.resources.displayMetrics.scaledDensity,0.01f);assertEquals(listOf(1,2,3,4),listOf(tab.paddingLeft,tab.paddingTop,tab.paddingRight,tab.paddingBottom))
        call("seedGuideSkinChrome",emptyArray());assertEquals("sentinel title",title.text.toString());assertEquals("sentinel caption",caption.text.toString())
        call("updateGuideDetail",arrayOf(PlaybackItem::class.java),model().items[0]);assertEquals("sentinel monitor",monitor.text.toString())
    }
    @Test fun missingOverlayDoesNotMarkTheSkinInstalledOrConstructAReplacement() {
        set("guideSkinInstalled",false);activity.setContentView(android.widget.FrameLayout(activity))
        call("installGuideOverlaySkin",emptyArray());assertFalse(field("guideSkinInstalled") as Boolean)
        assertNull(activity.findViewById<View>(R.id.android_tv_playlist_overlay))
    }
    @Test fun broadcastDetailArtworkUsesItsBoundMonitorAndActivityGlideOwner() {
        val image=field("gdMonArt") as android.widget.ImageView
        val item=model().items[0].copy(artwork="file:///phase13-monitor.jpg")
        call("updateGuideDetail",arrayOf(PlaybackItem::class.java),item)
        val request=com.bumptech.glide.request.target.DrawableImageViewTarget(image).request
        assertNotNull(request);assertEquals("file:///phase13-monitor.jpg",org.robolectric.util.ReflectionHelpers.getField<Any>(request,"model"))
        assertTrue(TvPlayerOriginalAccess.glideTracks(com.bumptech.glide.Glide.with(activity),request!!))
        call("updateGuideDetail",arrayOf(PlaybackItem::class.java),item.copy(artwork=null));assertNull(com.bumptech.glide.request.target.DrawableImageViewTarget(image).request)
    }

}
