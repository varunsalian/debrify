package com.debrify.app.tv

import android.view.View
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
internal class TvStremioGuideCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun guideRowsKeepCurrentFallbackNowNextClickAndFocus() {
        val channel = Original.tvChannel(current = true)
        var clicked: Any? = null
        val adapter = Original.tvGuide(mutableListOf(channel)) { clicked = it }
        assertEquals(1, adapter.itemCount)
        assertEquals(0, adapter.getItemViewType(0))
        val row = holder(adapter)
        assertEquals("7", text(row, R.id.stremio_tv_guide_channel_number))
        assertEquals("Cinema", text(row, R.id.stremio_tv_guide_channel_name))
        assertEquals("MOVIE", text(row, R.id.stremio_tv_guide_type_badge))
        assertEquals("Film (2024) ★ 8.5", text(row, R.id.stremio_tv_guide_now_title))
        assertEquals("Next: Next Film (2025)", text(row, R.id.stremio_tv_guide_next_title))
        assertEquals("C", text(row, R.id.stremio_tv_guide_poster_letter))
        assertEquals(View.GONE, view(row, R.id.stremio_tv_guide_poster).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.stremio_tv_guide_poster_letter).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.stremio_tv_guide_now_badge).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.stremio_tv_guide_accent_bar).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.stremio_tv_guide_end_time).visibility)
        row.itemView.performClick()
        assertSame(channel, clicked)
        parent.addView(row.itemView)
        assertFalse(row.itemView.performLongClick())
        Original.set(channel, "isCurrent", false)
        adapter.onBindViewHolder(row, 0)
        assertEquals(View.GONE, view(row, R.id.stremio_tv_guide_now_badge).visibility)
        focus(row.itemView, true)
        assertEquals(View.VISIBLE, view(row, R.id.stremio_tv_guide_accent_bar).visibility)
        advance()
        assertEquals(1.02f, row.itemView.scaleX, 0.001f)
        focus(row.itemView, false)
        assertEquals(View.GONE, view(row, R.id.stremio_tv_guide_accent_bar).visibility)
    }

    @Test fun switchingLoadingAndEmptyDataClearTheRecycledGuideRow() {
        val channel = Original.tvChannel(current = true)
        val adapter = Original.tvGuide(mutableListOf(channel))
        val row = holder(adapter)
        Original.set(channel, "isSwitchingChannel", true)
        adapter.onBindViewHolder(row, 0)
        assertEquals("Tuning...", text(row, R.id.stremio_tv_guide_now_title))
        assertEquals(View.VISIBLE, view(row, R.id.stremio_tv_guide_loading).visibility)
        assertEquals(View.GONE, view(row, R.id.stremio_tv_guide_now_badge).visibility)
        Original.set(channel, "isSwitchingChannel", false)
        Original.set(channel, "isCurrent", false)
        Original.set(channel, "hasGuideData", false)
        Original.set(channel, "isLoadingGuideData", true)
        adapter.onBindViewHolder(row, 0)
        assertEquals("Loading...", text(row, R.id.stremio_tv_guide_now_title))
        assertEquals(View.GONE, view(row, R.id.stremio_tv_guide_next_title).visibility)
        assertEquals(View.GONE, view(row, R.id.stremio_tv_guide_progress_container).visibility)
        Original.set(channel, "isLoadingGuideData", false)
        adapter.onBindViewHolder(row, 0)
        assertEquals("", text(row, R.id.stremio_tv_guide_now_title))
        assertEquals(View.GONE, view(row, R.id.stremio_tv_guide_loading).visibility)
    }

    @Test fun guidePayloadFirstSlotMatrixPreservesStaticFieldsAndScale() {
        val channel = Original.tvChannel(name = "Before")
        val adapter = Original.tvGuide(mutableListOf(channel))
        for (payloads in listOf<List<Any>>(emptyList(), listOf("unknown"), listOf("guide_data"), listOf("switch_state"),
            listOf("guide_data", "unknown"), listOf("unknown", "guide_data"),
            listOf("switch_state", "guide_data"), listOf("unknown", "switch_state"))) {
            Original.set(channel, "name", "Before")
            val row = holder(adapter)
            row.itemView.scaleX = 1.2f
            row.itemView.requestFocus()
            Original.set(channel, "name", "After")
            Original.set(channel, "nowPlayingTitle", "Updated")
            adapter.onBindViewHolder(row, 0, payloads.toMutableList())
            val partial = payloads.firstOrNull() in listOf("guide_data", "switch_state")
            assertEquals(if (partial) "Before" else "After", text(row, R.id.stremio_tv_guide_channel_name))
            assertEquals("Updated (2024) ★ 8.5", text(row, R.id.stremio_tv_guide_now_title))
            assertEquals(if (partial) 1.2f else 1f, row.itemView.scaleX, 0f)
            assertTrue(row.itemView.hasFocus())
        }
    }

    @Test fun attachedMeasuredHolderAppliesClampedPostedProgressWidth() {
        val channel = Original.tvChannel(progress = 0.25f)
        val adapter = Original.tvGuide(mutableListOf(channel))
        val recycler = attach(adapter)
        val row = recycler.findViewHolderForAdapterPosition(0)!!
        assertEquals(0, row.bindingAdapterPosition)
        val fill = view(row, R.id.stremio_tv_guide_progress_fill)
        val track = fill.parent as View
        assertTrue(track.width > 0)
        advance(1)
        assertEquals((track.width * 0.25f).toInt(), fill.layoutParams.width)
        Original.set(channel, "nowPlayingProgress", 2f)
        adapter.onBindViewHolder(row, 0, mutableListOf<Any>("guide_data"))
        advance(1)
        assertEquals(track.width, fill.layoutParams.width)
        Original.set(channel, "nowPlayingProgress", -1f)
        adapter.onBindViewHolder(row, 0, mutableListOf<Any>("guide_data"))
        advance(1)
        assertEquals(0, fill.layoutParams.width)
    }

    @Test fun postedProgressRejectsAReboundChannelAtTheSameAttachedPosition() {
        val original = Original.tvChannel(progress = 0.25f)
        val channels = mutableListOf(original)
        val adapter = Original.tvGuide(channels)
        val recycler = attach(adapter)
        val row = recycler.findViewHolderForAdapterPosition(0)!!
        assertEquals(0, row.bindingAdapterPosition)
        val fill = view(row, R.id.stremio_tv_guide_progress_fill)
        assertTrue((fill.parent as View).width > 0)
        fill.layoutParams = fill.layoutParams.apply { width = 17 }
        // Initial bind's runnable is pending. Rebound row has no progress post
        // of its own, so a missing identity guard visibly overwrites this width.
        channels[0] = Original.tvChannel(id = "two", data = false)
        adapter.onBindViewHolder(row, 0)
        assertEquals(0, row.bindingAdapterPosition)
        advance(1)
        assertEquals(17, fill.layoutParams.width)
    }

    @Test fun postedProgressRejectsNoPositionAfterAnAttachedHolderIsRemoved() {
        val adapter = Original.tvGuide(mutableListOf(Original.tvChannel()))
        val recycler = attach(adapter)
        val row = recycler.findViewHolderForAdapterPosition(0)!!
        assertEquals(0, row.bindingAdapterPosition)
        val fill = view(row, R.id.stremio_tv_guide_progress_fill)
        fill.layoutParams = fill.layoutParams.apply { width = 19 }
        recycler.adapter = null
        assertEquals(androidx.recyclerview.widget.RecyclerView.NO_POSITION, row.bindingAdapterPosition)
        advance(1)
        assertEquals(19, fill.layoutParams.width)
    }

    @Test fun guideUpdatesKeepIdLookupsCurrentFallbackAndNotifications() {
        val first = Original.tvChannel(id = "one")
        val second = Original.tvChannel(id = "two", current = true)
        val adapter = Original.tvGuide(mutableListOf(first, second))
        assertEquals(1, Original.call(adapter, "getCurrentChannelPosition"))
        assertSame(second, Original.call(adapter, "getChannelAt", 1))
        assertNull(Original.call(adapter, "getChannelAt", 99))
        assertEquals(1, Original.call(adapter, "getPositionById", "two"))
        assertEquals(-1, Original.call(adapter, "getPositionById", "missing"))
        val events = notices(adapter)
        Original.call(adapter, "updateChannels", listOf(first))
        assertEquals(listOf(Notice("all")), events)
        assertEquals(1, adapter.itemCount)
        assertEquals(0, Original.call(adapter, "getCurrentChannelPosition"))
    }
}
