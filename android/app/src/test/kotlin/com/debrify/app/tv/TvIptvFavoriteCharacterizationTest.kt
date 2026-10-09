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
internal class TvIptvFavoriteCharacterizationTest : TvPhase12OriginalTest() {

    @Test fun favoritePinsBothToastTextsAndEveryMetadataField() {
        val e=entry(false).copy(contentType="vod",duration=123,httpHeaders=mapOf("X" to "Y"))
        for(expected in listOf(true,false)){favorite(e)
        assertEquals(expected,e.isFavorite)
        assertEquals(mapOf("url" to e.url,"name" to e.name,"logoUrl" to e.logoUrl,"group" to e.group,"sourceId" to e.sourceId,"channelNumber" to e.channelNumber,"contentType" to "vod","duration" to 123,"httpHeaders" to mapOf("X" to "Y"),"isFavorite" to expected),args("setIptvFavorite"))
        assertEquals(if(expected) "Added to favorites" else "Removed from favorites",ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_SHORT,ShadowToast.getLatestToast().duration)}
    }

    @Test fun favoriteSearchMirrorRequiresUrlNameSourceAndActiveSearch() {
        val e=entry(false)
        val exact=e.copy()
        val otherName=e.copy(name="other")
        val otherSource=e.copy(sourceId="other")
        val otherUrl=e.copy(url="other")
        set("iptvSearchSavedChannels",mutableListOf(exact,otherName,otherSource,otherUrl))
        favorite(e)
        assertFalse(exact.isFavorite)
        set("iptvAllCategorySearchActive",true)
        e.isFavorite=false
        favorite(e)
        assertTrue(exact.isFavorite)
        assertFalse(otherName.isFavorite)
        assertFalse(otherSource.isFavorite)
        assertFalse(otherUrl.isFavorite)
    }

    @Test fun removeRowKeepsPlayingAndUsesObjectIdentity() {
        val current=entry()
        val e=entry(false)
        val equal=e.copy()
        set("iptvBrowseChannels",mutableListOf(current,e,equal))
        set("iptvSearchSavedChannels",mutableListOf(current,e,equal))
        boundAdapter().updateChannels(listOf(current,e,equal))
        remove(current)
        assertEquals(3,browseChannels().size)
        remove(e)
        assertEquals(listOf(current,equal),browseChannels())
        assertSame(equal,browseChannels()[1])
        assertEquals(2,boundAdapter().itemCount)
        @Suppress("UNCHECKED_CAST") val saved=field("iptvSearchSavedChannels") as List<IptvChannelEntry>
        assertEquals(listOf(current,equal),saved)
    }

    @Test fun removeAbsentBrowseStillRemovesSavedWithoutRefreshingAdapter() {
        val e=entry(false)
        set("iptvBrowseChannels",mutableListOf<IptvChannelEntry>())
        set("iptvSearchSavedChannels",mutableListOf(e))
        boundAdapter().updateChannels(listOf(entry()))
        remove(e)
        assertEquals(1,boundAdapter().itemCount)
        assertEquals(emptyList<IptvChannelEntry>(),field("iptvSearchSavedChannels"))
    }

    @Test fun rowRemovalRepaintsCountAndRetainsCurrentTitle() {
        val current=playing()
        fresh(current)
        val e=entry(false)
        set("iptvBrowseChannels",mutableListOf(current,e))
        boundAdapter().updateChannels(listOf(current,e))
        set("iptvGuideUsesZapWindow",false)
        set("iptvZapPagingActive",false)
        (field("iptvGuideCountText") as TextView).text="stale"
        remove(e)
        assertEquals(1,browseChannels().size)
        assertEquals("1 items",(field("iptvGuideCountText") as TextView).text.toString())
        assertEquals(1,boundAdapter().itemCount)
    }
}
