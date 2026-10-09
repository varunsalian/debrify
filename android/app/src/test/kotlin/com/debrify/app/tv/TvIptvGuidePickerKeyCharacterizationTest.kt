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
internal class TvIptvGuidePickerKeyCharacterizationTest : TvPhase12OriginalTest() {
    private fun trackScroll(list: RecyclerView): MutableList<Int> {
        val calls=mutableListOf<Int>()
        list.layoutManager=object:androidx.recyclerview.widget.LinearLayoutManager(activity) {
            override fun scrollToPosition(position: Int) { calls.add(position);super.scrollToPosition(position) }
        }
        idle();calls.clear();return calls
    }
    private fun keyListener(input: android.widget.EditText): View.OnKeyListener {
        val info: Any?=org.robolectric.util.ReflectionHelpers.getField(input,"mListenerInfo")
        assertNotNull("category input publishes listener storage",info)
        val listener: View.OnKeyListener?=org.robolectric.util.ReflectionHelpers.getField(info!!,"mOnKeyListener")
        assertNotNull("category dialog installs the key listener",listener);return listener!!
    }

    @Test fun categoryDownOnlyFirstPressPostsFocusToFirstActualRow() {
        call("showIptvCategoryPicker",emptyArray())
        val input=dialogInput()
        val list=dialogList()
        val scroll=trackScroll(list)
        val listener=keyListener(input)
        for(event in listOf(KeyEvent(KeyEvent.ACTION_UP,KeyEvent.KEYCODE_DPAD_DOWN),KeyEvent(0,0,KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_DOWN,1),KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_LEFT))){assertFalse(listener.onKey(input,event.keyCode,event))
        assertTrue(input.hasFocus())}
        assertTrue(listener.onKey(input,KeyEvent.KEYCODE_DPAD_DOWN,KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_DOWN)))
        assertEquals("exact first-row scroll is dispatched",listOf(0),scroll)
        idle()
        val first=list.findViewHolderForAdapterPosition(0)
        assertNotNull(first)
        assertTrue("posted first row gets focus",first!!.itemView.hasFocus())
    }

    @Test fun categoryDonePostsFocusWhileGoLeavesSearchFocused() {
        call("showIptvCategoryPicker",emptyArray())
        val input=dialogInput()
        val list=dialogList()
        val scroll=trackScroll(list)
        assertFalse(editor(input,EditorInfo.IME_ACTION_GO))
        assertTrue(input.hasFocus())
        assertTrue(editor(input,EditorInfo.IME_ACTION_DONE))
        assertEquals("exact first-row scroll is dispatched",listOf(0),scroll)
        idle()
        val first=list.findViewHolderForAdapterPosition(0)
        assertNotNull(first)
        assertTrue("DONE posts first-row focus",first!!.itemView.hasFocus())
    }
}
