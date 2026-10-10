package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackRandomDialogCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun dialogRandomOnce() {
        payload(p2Item().copy(resumePositionMs=99L),p2Item("Target").copy(index=1,resumePositionMs=99L)); set("continuousShuffleEnabled",true); (field("shuffleBag") as MutableList<Int>).add(9)
        dockCall("showRandomPlaybackDialog"); val dialog=ShadowDialog.getLatestDialog() as AlertDialog
        assertEquals("Shuffle Playback",(dialog.findViewById<TextView>(androidx.appcompat.R.id.alertTitle))!!.text.toString())
        assertEquals("Play Random Once",dialog.listView.adapter.getItem(0)); assertEquals("Turn Off Continuous Shuffle",dialog.listView.adapter.getItem(1))
        dialog.listView.performItemClick(null,0,0L); assertEquals(false,field("continuousShuffleEnabled")); assertEquals(1,field("showShuffleGeneration")); assertEquals(1,probe.media.size)
        assertEquals(0L,field("pendingSeekMs"))
    }

    @Test fun dialogTurnOff() {
        payload(p2Item().copy(resumePositionMs=99L),p2Item("Target").copy(index=1,resumePositionMs=99L)); set("continuousShuffleEnabled",true); (field("shuffleBag") as MutableList<Int>).add(9)
        dockCall("showRandomPlaybackDialog"); val dialog=ShadowDialog.getLatestDialog() as AlertDialog
        assertEquals("Shuffle Playback",(dialog.findViewById<TextView>(androidx.appcompat.R.id.alertTitle))!!.text.toString())
        assertEquals("Play Random Once",dialog.listView.adapter.getItem(0)); assertEquals("Turn Off Continuous Shuffle",dialog.listView.adapter.getItem(1))
        dialog.listView.performItemClick(null,1,1L); assertEquals(false,field("continuousShuffleEnabled")); assertEquals(1,field("showShuffleGeneration")); assertEquals(0,probe.media.size)
        assertEquals("Continuous shuffle off",lastToast())
    }

    @Test fun dialogTurnOn() {
        payload(p2Item().copy(resumePositionMs=99L),p2Item("Target").copy(index=1,resumePositionMs=99L)); set("continuousShuffleEnabled",false); (field("shuffleBag") as MutableList<Int>).add(9)
        dockCall("showRandomPlaybackDialog"); val dialog=ShadowDialog.getLatestDialog() as AlertDialog
        assertEquals("Shuffle Playback",(dialog.findViewById<TextView>(androidx.appcompat.R.id.alertTitle))!!.text.toString())
        assertEquals("Play Random Once",dialog.listView.adapter.getItem(0)); assertEquals("Shuffle Continuously",dialog.listView.adapter.getItem(1))
        dialog.listView.performItemClick(null,1,1L); assertEquals(true,field("continuousShuffleEnabled")); assertEquals(1,field("showShuffleGeneration")); assertEquals(1,probe.media.size)
        assertEquals(0L,field("pendingSeekMs"))
    }

    @Test fun dialogReadsToggleAtClickTime() {
        dockCall("showRandomPlaybackDialog"); val dialog=ShadowDialog.getLatestDialog() as AlertDialog; set("continuousShuffleEnabled",true)
        dialog.listView.performItemClick(null,1,1); assertFalse(field("continuousShuffleEnabled") as Boolean); assertEquals("Continuous shuffle off",lastToast()); assertTrue(probe.media.isEmpty())
    }

    @Test fun dialogUnavailableNull() {
        set("payload",null); dockCall("showRandomPlaybackDialog"); assertEquals("No items in playlist",lastToast()); assertTrue(probe.media.isEmpty())
    }

    @Test fun dialogUnavailableEmpty() {
        model().items.clear(); dockCall("showRandomPlaybackDialog"); assertEquals("No items in playlist",lastToast()); assertTrue(probe.media.isEmpty())
    }

    @Test fun randomManualClearsAutoAndSuppressesResume() {
        payload(p2Item(),p2Item("Target").copy(index=1,resumePositionMs=99L)); set("isAutoAdvancing",true); call("playRandom",emptyArray()); assertEquals(1,field("currentIndex")); assertEquals(0L,field("pendingSeekMs")); assertFalse(field("isAutoAdvancing") as Boolean)
    }

    @Test fun randomEmptyShowsExactToast() {
        model().items.clear(); call("playRandom",emptyArray()); assertEquals("No items in playlist",lastToast()); assertTrue(probe.media.isEmpty())
    }
}
