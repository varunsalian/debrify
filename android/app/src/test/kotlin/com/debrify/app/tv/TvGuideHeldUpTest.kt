package com.debrify.app.tv

import android.app.Activity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** A guide header (the source picker) above a channel list, as in the player. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class TvGuideHeldUpTest {
    private lateinit var activity: Activity
    private lateinit var header: View
    private lateinit var list: RecyclerView

    @Before fun setUp() {
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        header = TextView(activity).apply {
            text = "Source"
            isFocusable = true
        }
        list = RecyclerView(activity).apply {
            layoutManager = LinearLayoutManager(activity)
            itemAnimator = null
            adapter = Rows(100)
        }
        activity.setContentView(
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(header, ViewGroup.LayoutParams(400, 60))
                addView(list, ViewGroup.LayoutParams(400, 600))
            },
        )
        layout()
    }

    private fun layout() {
        val root = activity.window.decorView
        root.measure(
            View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(700, View.MeasureSpec.EXACTLY),
        )
        root.layout(0, 0, 400, 700)
        shadowOf(activity.mainLooper).idle()
    }

    private fun up(repeat: Int) =
        KeyEvent(0L, 0L, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_UP, repeat)

    private fun focusRow(position: Int) {
        list.scrollToPosition(position)
        layout()
        list.findViewHolderForAdapterPosition(position)!!.itemView.requestFocus()
    }

    private fun focusedPosition(): Int =
        list.getChildAdapterPosition(list.findContainingItemView(list.findFocus()!!)!!)

    @Test fun heldUpOnTheFirstRowStaysInTheList() {
        focusRow(0)
        assertTrue(TvGuideHeldUp.holdsInList(list, up(repeat = 1)))
        assertTrue(TvGuideHeldUp.holdsInList(list, up(repeat = 40)))
    }

    @Test fun aFreshPressOnTheFirstRowStillLeavesForTheHeader() {
        focusRow(0)
        assertFalse(TvGuideHeldUp.holdsInList(list, up(repeat = 0)))
        assertSame(header, list.findFocus()!!.focusSearch(View.FOCUS_UP))
    }

    @Test fun heldUpMidListIsLeftToTheListWhichMovesOneRow() {
        focusRow(57)
        for (expected in 56 downTo 50) {
            assertFalse(TvGuideHeldUp.holdsInList(list, up(repeat = 5)))
            list.findFocus()!!.focusSearch(View.FOCUS_UP)!!.requestFocus()
            layout()
            assertEquals(expected, focusedPosition())
        }
    }

    @Test fun otherKeysAndAnUnfocusedListAreIgnored() {
        assertFalse(TvGuideHeldUp.holdsInList(list, up(repeat = 3)))
        assertFalse(TvGuideHeldUp.holdsInList(null, up(repeat = 3)))
        focusRow(0)
        val down = KeyEvent(0L, 0L, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_DOWN, 3)
        assertFalse(TvGuideHeldUp.holdsInList(list, down))
    }

    private class Rows(private val count: Int) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            object : RecyclerView.ViewHolder(
                TextView(parent.context).apply {
                    isFocusable = true
                    layoutParams = RecyclerView.LayoutParams(400, 60)
                },
            ) {}

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            (holder.itemView as TextView).text = "Channel ${position + 1}"
        }

        override fun getItemCount() = count
    }
}
