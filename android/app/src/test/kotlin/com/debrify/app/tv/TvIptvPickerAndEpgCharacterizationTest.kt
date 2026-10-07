package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvPickerAndEpgCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun categoryOrderSelectionRemoteClickAndFirstRowFocusTarget() {
        for (style in GuideStyle.entries) {
            var selected: String? = null
            val adapter = Original.categories(style = style, click = { selected = it })
            val events = notices(adapter)
            assertEquals(0, adapter.itemCount)
            Original.call(adapter, "update", listOf("All categories", "Movies"))
            assertEquals(listOf(Notice("all")), events)
            assertEquals(2, adapter.itemCount)
            assertEquals(0, adapter.getItemViewType(0))
            val first = holder(adapter)
            assertEquals("All categories", (first.itemView as TextView).text.toString())
            assertTrue(first.itemView.isSelected)
            assertEquals(123, first.itemView.nextFocusUpId)
            val second = holder(adapter, 1)
            assertFalse(second.itemView.isSelected)
            assertEquals(View.NO_ID, second.itemView.nextFocusUpId)
            second.itemView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER))
            second.itemView.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_CENTER))
            assertEquals("Movies", selected)
            focus(second.itemView, true)
            advance()
            assertEquals(1.015f, second.itemView.scaleX, 0.001f)
            focus(second.itemView, false)
            advance()
            assertEquals(1f, second.itemView.scaleX, 0.001f)
            Original.call(adapter, "update", listOf("Other"))
            assertEquals(1, adapter.itemCount)
            assertEquals("Other", (holder(adapter).itemView as TextView).text.toString())
        }
    }

    @Test fun listReadinessAndMutableMembershipControlCheckedRowsAndNotifications() {
        for (style in GuideStyle.entries) {
            val entry = Original.list("one", "My list")
            val membership = mutableSetOf<String>()
            var toggled: Any? = null
            val adapter = Original.lists(listOf(entry), membership, style) {
                toggled = it
                membership += "one"
            }
            val events = notices(adapter)
            assertEquals(0, adapter.itemCount)
            Original.call(adapter, "setReady", false)
            assertTrue(events.isEmpty())
            Original.call(adapter, "setReady", true)
            assertEquals(listOf(Notice("all")), events)
            Original.call(adapter, "setReady", true)
            assertEquals(1, events.size)
            assertEquals(1, adapter.itemCount)
            val row = holder(adapter)
            assertEquals("My list", (row.itemView as TextView).text.toString())
            assertFalse(row.itemView.isSelected)
            events.clear()
            row.itemView.performClick()
            assertSame(entry, toggled)
            assertEquals(listOf(Notice("change", 0, 1)), events)
            adapter.onBindViewHolder(row, 0)
            assertEquals("✓  My list", (row.itemView as TextView).text.toString())
            assertTrue(row.itemView.isSelected)
            focus(row.itemView, true)
            advance()
            assertEquals(1.015f, row.itemView.scaleX, 0.001f)
            focus(row.itemView, false)
            advance()
            assertEquals(1f, row.itemView.scaleX, 0.001f)
            Original.call(adapter, "setReady", false)
            assertEquals(0, adapter.itemCount)
        }
    }

    @Test fun epgTimeStatesReplayAndFutureRecordingUseTheBoundProgram() {
        val now = System.currentTimeMillis()
        val programs = listOf(
            Original.program("Current", now - 60_000, now + 60_000),
            Original.program("Archive", now - 60_000, now + 60_000, true, "description"),
            Original.program("Past", now - 120_000, now - 60_000, true),
            Original.program("Expired", now - 120_000, now - 60_000),
            Original.program("Future", now + 60_000, now + 120_000),
        )
        val replayed = mutableListOf<Any>()
        val recorded = mutableListOf<Any>()
        val adapter = Original.epg(programs, replayed::add, recorded::add)
        assertEquals(5, adapter.itemCount)
        for (position in programs.indices) {
            val row = holder(adapter, position)
            assertEquals(listOf("Current", "Archive", "Past", "Expired", "Future")[position], text(row, R.id.iptv_epg_program_title))
            assertEquals(listOf("NOW", "START OVER", "REPLAY", "REPLAY", "REPLAY")[position], text(row, R.id.iptv_epg_program_now))
            assertEquals(if (position <= 2) View.VISIBLE else View.GONE, view(row, R.id.iptv_epg_program_now).visibility)
            assertEquals(if (position < 2) View.VISIBLE else View.GONE, view(row, R.id.iptv_epg_program_progress).visibility)
            assertEquals(if (position == 3) 0.55f else 1f, row.itemView.alpha, 0f)
            assertEquals(if (position == 1) View.VISIBLE else View.GONE, view(row, R.id.iptv_epg_program_description).visibility)
            if (position < 2) assertTrue((view(row, R.id.iptv_epg_program_progress) as ProgressBar).progress in 480..520)
            row.itemView.performClick()
        }
        assertEquals(listOf(programs[1], programs[2]), replayed)
        assertEquals(listOf(programs[4]), recorded)
        val events = notices(adapter)
        Original.call(adapter, "updatePrograms", listOf(programs[4]))
        assertEquals(listOf(Notice("all")), events)
        assertEquals(1, adapter.itemCount)
    }

    @Test fun styledEpgRecyclingClearsSelectedWhileClassicKeepsItsExistingState() {
        val now = System.currentTimeMillis()
        val programs = listOf(Original.program("Now", now - 60_000, now + 60_000),
            Original.program("Future", now + 60_000, now + 120_000))
        for (style in GuideStyle.entries) {
            val adapter = Original.epg(programs, style = style)
            val row = holder(adapter)
            assertEquals(style != GuideStyle.CLASSIC, row.itemView.isSelected)
            if (style != GuideStyle.CLASSIC) {
                assertEquals(GuideTokens.of(style)!!.fg, (view(row, R.id.iptv_epg_program_title) as TextView).currentTextColor)
                assertNotNull(row.itemView.background)
            } else {
                row.itemView.isSelected = true
            }
            adapter.onBindViewHolder(row, 1)
            assertEquals(style == GuideStyle.CLASSIC, row.itemView.isSelected)
        }
    }
}
