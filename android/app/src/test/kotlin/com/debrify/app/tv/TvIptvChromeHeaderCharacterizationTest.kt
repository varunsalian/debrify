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
internal class TvIptvChromeHeaderCharacterizationTest : TvPhase12OriginalTest() {

    @Test fun currentHeaderPinsNameGroupAndNowCard() {
        val e=playing()
        fresh(e)
        t("iptvGuideCurrentName").text="stale"
        t("iptvGuideCurrentGroup").text="stale"
        v("iptvGuideCurrentGroup").visibility=View.GONE
        v("iptvGuideNowPlaying").visibility=View.GONE
        header()
        assertEquals(e.displayName,text("iptvGuideCurrentName"))
        assertEquals("News",text("iptvGuideCurrentGroup"))
        assertEquals(View.VISIBLE,v("iptvGuideCurrentGroup").visibility)
        assertEquals(View.VISIBLE,v("iptvGuideNowPlaying").visibility)
    }

    @Test fun paneVisibleHidesNowCard() {
        val e=playing()
        fresh(e)
        set("iptvEpgVisible",true)
        header()
        assertEquals(View.GONE,v("iptvGuideNowPlaying").visibility)
    }

    @Test fun missingAndEmptyGroupAreGone() {
        for(g in listOf<String?>(null,"")){val e=playing(entry().copy(group=g))
        fresh(e)
        v("iptvGuideCurrentGroup").visibility=View.VISIBLE
        header()
        assertEquals(View.GONE,v("iptvGuideCurrentGroup").visibility)}
    }

    @Test fun invalidIndexHidesCardWithoutClearingLabels() {
        set("currentIptvIndex",99)
        t("iptvGuideCurrentName").text="retained"
        header()
        assertEquals("retained",text("iptvGuideCurrentName"))
        assertEquals(View.GONE,v("iptvGuideNowPlaying").visibility)
    }

    @Test fun playingLetterUppercaseAndEmptyFallback() {
        for(pair in listOf("alpha" to "A","ßeta" to "SS","" to "?")){val e=playing(entry().copy(name=pair.first))
        fresh(e)
        v("iptvGuideNowLogo").visibility=View.VISIBLE
        v("iptvGuideNowLetter").visibility=View.GONE
        header()
        assertEquals(pair.second,text("iptvGuideNowLetter"))
        assertEquals(View.VISIBLE,v("iptvGuideNowLetter").visibility)
        assertEquals(View.GONE,v("iptvGuideNowLogo").visibility)}
    }

    @Test fun headerRequestsFreshCatchupMetadata() {
        val e=playing()
        header()
        assertTrue(e.epgLoading)
        assertEquals(true,args("requestIptvEpg")["includeCatchupMetadata"])
        assertEquals(false,args("requestIptvEpg")["includeSchedule"])
    }

    @Test fun nowAndNextTextPinsSeparators() {
        val e=playing()
        e.epgNowTitle="Morning"
        e.epgNextTitle="Evening"
        nowLine()
        assertEquals("Now: Morning   ›   Next: Evening",text("iptvGuideCurrentEpg"))
        assertEquals(View.VISIBLE,v("iptvGuideCurrentEpg").visibility)
    }

    @Test fun nowWithoutNextHasNoSuffix() {
        val e=playing()
        e.epgNowTitle="Morning"
        e.epgNextTitle=null
        nowLine()
        assertEquals("Now: Morning",text("iptvGuideCurrentEpg"))
    }

    @Test fun missingNowOrCurrentEntryHidesLine() {
        for(index in listOf(0,99)){playing()
        set("currentIptvIndex",index)
        v("iptvGuideCurrentEpg").visibility=View.VISIBLE
        nowLine()
        assertEquals(View.GONE,v("iptvGuideCurrentEpg").visibility)}
    }

    @Test fun playingLogoUsesActivityLifecycleAndPinnedFallback() {
        val e=entry().copy(logoUrl="android.resource://com.debrify.app/${R.drawable.splash_logo}")
        playing(e)
        fresh(e)
        header()
        val image=v("iptvGuideNowLogo") as ImageView
        val attached=com.bumptech.glide.request.target.DrawableImageViewTarget(image).request
        assertNotNull("Glide attaches the request to the selected logo",attached)
        val request=attached!!
        assertEquals(e.logoUrl,org.robolectric.util.ReflectionHelpers.getField<Any?>(request,"model"))
        val options=org.robolectric.util.ReflectionHelpers.getField<com.bumptech.glide.request.BaseRequestOptions<*>>(request,"requestOptions")
        assertTrue("explicit centerInside requires its transformation",options.isTransformationRequired)
        val transform=options.transformations[android.graphics.Bitmap::class.java]
        assertNotNull("bitmap transformation is installed",transform)
        assertEquals(com.bumptech.glide.load.resource.bitmap.CenterInside::class.java,transform!!.javaClass)
        val manager=com.bumptech.glide.Glide.with(activity)
        assertTrue(TvPlayerOriginalAccess.glideTracks(manager,request))
        assertFalse(TvPlayerOriginalAccess.glideTracks(com.bumptech.glide.Glide.with(activity.applicationContext),request))
        assertEquals(View.VISIBLE,image.visibility)
        assertEquals(View.GONE,v("iptvGuideNowLetter").visibility)
        val installed=org.robolectric.util.ReflectionHelpers.getField<List<*>?>(request,"requestListeners")
        assertNotNull("Glide listener registration is present",installed)
        assertEquals("exactly the moved fallback listener is installed",1,installed!!.size)
        val listener=TvPlayerOriginalAccess.artworkListener(image)
        assertFalse(listener.onResourceReady(android.graphics.drawable.ColorDrawable(),"local",null,com.bumptech.glide.load.DataSource.LOCAL,true))
        t("iptvGuideNowLetter").text="stale"
        assertTrue(listener.onLoadFailed(null,"local",com.bumptech.glide.request.target.DrawableImageViewTarget(image),true))
        assertEquals(View.GONE,image.visibility)
        assertEquals(View.VISIBLE,v("iptvGuideNowLetter").visibility)
        assertEquals("A",text("iptvGuideNowLetter"))
        destroyNow()
        idle()
        assertTrue(request.isCleared)
        assertFalse(TvPlayerOriginalAccess.glideTracks(manager,request))
    }

    @Test fun paneLogoUsesActivityLifecycleAndPinnedFallback() {
        val e=entry().copy(logoUrl="android.resource://com.debrify.app/${R.drawable.splash_logo}")
        logo(e)
        val image=v("iptvEpgLogo") as ImageView
        val attached=com.bumptech.glide.request.target.DrawableImageViewTarget(image).request
        assertNotNull("Glide attaches the request to the selected logo",attached)
        val request=attached!!
        assertEquals(e.logoUrl,org.robolectric.util.ReflectionHelpers.getField<Any?>(request,"model"))
        val options=org.robolectric.util.ReflectionHelpers.getField<com.bumptech.glide.request.BaseRequestOptions<*>>(request,"requestOptions")
        assertTrue("explicit centerInside requires its transformation",options.isTransformationRequired)
        val transform=options.transformations[android.graphics.Bitmap::class.java]
        assertNotNull("bitmap transformation is installed",transform)
        assertEquals(com.bumptech.glide.load.resource.bitmap.CenterInside::class.java,transform!!.javaClass)
        val manager=com.bumptech.glide.Glide.with(activity)
        assertTrue(TvPlayerOriginalAccess.glideTracks(manager,request))
        assertFalse(TvPlayerOriginalAccess.glideTracks(com.bumptech.glide.Glide.with(activity.applicationContext),request))
        assertEquals(View.VISIBLE,image.visibility)
        assertEquals(View.GONE,v("iptvEpgLetter").visibility)
        val installed=org.robolectric.util.ReflectionHelpers.getField<List<*>?>(request,"requestListeners")
        assertNotNull("Glide listener registration is present",installed)
        assertEquals("exactly the moved fallback listener is installed",1,installed!!.size)
        val listener=TvPlayerOriginalAccess.artworkListener(image)
        assertFalse(listener.onResourceReady(android.graphics.drawable.ColorDrawable(),"local",null,com.bumptech.glide.load.DataSource.LOCAL,true))
        t("iptvEpgLetter").text="stale"
        assertTrue(listener.onLoadFailed(null,"local",com.bumptech.glide.request.target.DrawableImageViewTarget(image),true))
        assertEquals(View.GONE,image.visibility)
        assertEquals(View.VISIBLE,v("iptvEpgLetter").visibility)
        assertEquals("A",text("iptvEpgLetter"))
        destroyNow()
        idle()
        assertTrue(request.isCleared)
        assertFalse(TvPlayerOriginalAccess.glideTracks(manager,request))
    }

    @Test fun paneLetterUppercaseAndEmptyFallback() {
        for(pair in listOf("alpha" to "A","ßeta" to "SS","" to "?")){v("iptvEpgLogo").visibility=View.VISIBLE
        v("iptvEpgLetter").visibility=View.GONE
        logo(entry().copy(name=pair.first))
        assertEquals(pair.second,text("iptvEpgLetter"))
        assertEquals(View.VISIBLE,v("iptvEpgLetter").visibility)
        assertEquals(View.GONE,v("iptvEpgLogo").visibility)}
    }

    @Test fun timeFormatReadsActivityTwelveAndTwentyFourHourPreference() {
        val ms=java.util.Calendar.getInstance().apply{set(2020,0,1,13,5,0)}.timeInMillis
        for(pref in listOf("12","24")){android.provider.Settings.System.putString(activity.contentResolver,android.provider.Settings.System.TIME_12_24,pref)
        assertEquals(android.text.format.DateFormat.getTimeFormat(activity).format(java.util.Date(ms)),call("formatEpgTime",arrayOf(longType),ms))}
    }

    @Test fun missingNowHeaderViewDoesNotPaintAnotherLabel() {
        val e=playing()
        e.epgNowTitle="News"
        t("iptvGuideCurrentName").text="untouched"
        set("iptvGuideCurrentEpg",null)
        nowLine()
        assertEquals("untouched",text("iptvGuideCurrentName"))
        assertNull(field("iptvGuideCurrentEpg"))
    }
}
