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
internal class TvIptvEpgDayFocusCharacterizationTest : TvPhase12OriginalTest() {
    private class ListProbe(context: android.content.Context) : RecyclerView(context) {
        val positions=mutableListOf<Int>()
        val pending=mutableListOf<Runnable>()
        override fun scrollToPosition(position: Int) { positions.add(position) }
        override fun post(action: Runnable): Boolean { pending.add(action); return true }
    }

    @Test fun dayFocusPinsInclusiveStartExclusiveStopAndPost() {
        val now=java.util.Calendar.getInstance().timeInMillis
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(now))
        val list=ListProbe(activity)
        set("iptvEpgList",list)
        val ended=IptvEpgProgram("Ended",null,now-2000,now,true)
        val airing=IptvEpgProgram("Airing",null,now,now+1000,true)
        set("iptvEpgPrograms",listOf(ended,airing))
        day(0)
        assertEquals(listOf(1),list.positions)
        assertEquals(1,list.pending.size)
        hidePane()
        assertEquals("view posts remain uncancelled as originally",1,list.pending.size)
    }

    @Test fun dayFocusFalseAndEmptyAvoidScrollAndPost() {
        val list=ListProbe(activity)
        set("iptvEpgList",list)
        set("iptvEpgPrograms",listOf(programme()))
        day(0,false)
        assertTrue(list.positions.isEmpty())
        assertTrue(list.pending.isEmpty())
        day(3)
        assertTrue(list.positions.isEmpty())
        assertTrue(list.pending.isEmpty())
    }

    @Test fun dayFocusNoAiringCoercesToFirstRow() {
        val now=java.util.Calendar.getInstance().timeInMillis
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(now))
        val list=ListProbe(activity)
        set("iptvEpgList",list)
        set("iptvEpgPrograms",listOf(IptvEpgProgram("Future",null,now+1000,now+2000,false)))
        day(0)
        assertEquals(listOf(0),list.positions)
        assertEquals(1,list.pending.size)
    }
}
