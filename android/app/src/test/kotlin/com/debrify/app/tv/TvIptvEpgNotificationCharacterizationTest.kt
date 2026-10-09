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
internal class TvIptvEpgNotificationCharacterizationTest : TvPhase12OriginalTest() {
    private class Changes : RecyclerView.AdapterDataObserver() {
        var changed=0
        override fun onItemRangeChanged(start: Int,count: Int,payload: Any?) { changed+=count }
        override fun onChanged() { changed++ }
    }

    @Test fun nowReplyNotifiesRowAndPaintsVisibleZapBanner() {
        val e=playing()
        boundAdapter().updateChannels(listOf(e))
        val observer=Changes()
        boundAdapter().registerAdapterDataObserver(observer)
        val banner=v("iptvZapBanner")
        banner.visibility=View.VISIBLE
        ensure(e)
        epgAnswer(value=epgReply())
        idle()
        assertTrue("row repaint notified",observer.changed>0)
        assertEquals("Now",e.epgNowTitle)
        assertTrue((field("iptvZapBannerNow") as TextView).text.toString().contains("Now"))
    }

    @Test fun favoriteNotifiesBoundRow() {
        val e=entry(false)
        boundAdapter().updateChannels(listOf(e))
        val observer=Changes()
        boundAdapter().registerAdapterDataObserver(observer)
        favorite(e)
        assertTrue(observer.changed>0)
    }
}
