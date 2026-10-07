package com.debrify.app.tv

import android.view.View
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
internal class TvMovieAdapterCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun groupOrderAndForceRefreshKeepHiddenActiveItems() {
        val adapter = Original.movies(listOf(item(0, title = "Zero"), item(1, title = "One"), item(2, title = "Two")),
            Original.groups("MAIN" to listOf(2, 0), "EXTRAS" to listOf(1)))
        assertEquals(2, adapter.itemCount)
        assertEquals(0, adapter.getItemViewType(0))
        assertEquals(listOf("Two", "Zero"), (0..1).map { text(holder(adapter, it), R.id.android_tv_playlist_item_title) })
        val events = notices(adapter)
        assertEquals(false, Original.call(adapter, "showGroup", 0, false))
        assertTrue(events.isEmpty())
        assertEquals(true, Original.call(adapter, "showGroup", 0, true))
        assertEquals(listOf(Notice("all")), events)
        assertEquals(true, Original.call(adapter, "showGroup", 1, false))
        assertEquals(1, adapter.itemCount)
        assertEquals("One", text(holder(adapter), R.id.android_tv_playlist_item_title))
        Original.call(adapter, "showGroup", 99, false)
        assertEquals(0, adapter.itemCount)
    }

    @Test fun movieBindKeepsFallbackStatusClickAndClassicFocus() {
        var clicked = -1
        val items = mutableListOf(item(title = "Film").copy(description = "null", sizeBytes = 1_073_741_824))
        val adapter = Original.movies(items, Original.groups("MAIN" to listOf(0)), click = { clicked = it })
        val row = holder(adapter)
        val container = view(row, R.id.android_tv_playlist_item_container)
        assertEquals("MAIN", text(row, R.id.android_tv_playlist_item_badge))
        assertEquals("1.0 GB", text(row, R.id.android_tv_playlist_item_description))
        assertEquals("40% watched", text(row, R.id.android_tv_playlist_item_progress_text))
        assertEquals("1", text(row, R.id.android_tv_playlist_item_fallback))
        assertEquals(View.GONE, view(row, R.id.android_tv_playlist_item_poster).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.android_tv_playlist_item_fallback).visibility)
        container.performClick()
        assertEquals(0, clicked)
        focus(container, true)
        assertEquals(View.VISIBLE, view(row, R.id.selection_overlay).visibility)
        focus(container, false)
        assertEquals(View.GONE, view(row, R.id.selection_overlay).visibility)
        items[0] = items[0].copy(watched = true)
        adapter.onBindViewHolder(row, 0)
        assertEquals(0.4f, container.alpha, 0f)
        assertEquals(View.VISIBLE, view(row, R.id.android_tv_playlist_item_watched).visibility)
        Original.call(adapter, "setActiveIndex", 0)
        adapter.onBindViewHolder(row, 0)
        assertTrue(container.isSelected)
        assertEquals(1f, container.alpha, 0f)
        assertEquals(View.VISIBLE, view(row, R.id.android_tv_playlist_item_playing).visibility)
    }

    @Test fun moviePayloadMatrixAndSkinFocusKeepFullBindSeparate() {
        val items = mutableListOf(item(title = "Before"))
        var bound: Triple<PlaybackItem, Int, Boolean>? = null
        var focused: Pair<PlaybackItem, Int>? = null
        val adapter = Original.movies(items, Original.groups("MAIN" to listOf(0)),
            skin = { _, value, index, active -> bound = Triple(value, index, active) },
            focus = { value, index -> focused = value to index })
        for (payloads in listOf<List<Any>>(emptyList(), listOf("unknown"), listOf("progress_update"),
            listOf("unknown", "progress_update"), listOf("progress_update", "unknown"))) {
            items[0] = item(title = "Before", progress = 40)
            val row = holder(adapter)
            items[0] = item(title = "After", progress = 70)
            adapter.onBindViewHolder(row, 0, payloads.toMutableList())
            assertEquals(if ("progress_update" in payloads) "Before" else "After", text(row, R.id.android_tv_playlist_item_title))
            assertEquals("70% watched", text(row, R.id.android_tv_playlist_item_progress_text))
            assertEquals(Triple(items[0], 0, false), bound)
            focus(view(row, R.id.android_tv_playlist_item_container), true)
            assertEquals(items[0].takeIf { "progress_update" !in payloads } ?: item(title = "Before", progress = 40), focused?.first)
            assertEquals(0, focused?.second)
        }
    }

    @Test fun movieActiveNotificationsKeepDuplicateAndHiddenSemantics() {
        val adapter = Original.movies(listOf(item(0), item(1)), Original.groups("MAIN" to listOf(0), "EXTRAS" to listOf(1)))
        val events = notices(adapter)
        Original.call(adapter, "setActiveIndex", 0)
        assertEquals(listOf(Notice("change", 0, 1)), events)
        events.clear()
        Original.call(adapter, "setActiveIndex", 0)
        Original.call(adapter, "updateCurrentProgress")
        assertEquals(listOf(Notice("change", 0, 1), Notice("change", 0, 1), Notice("change", 0, 1, "progress_update")), events)
        Original.call(adapter, "showGroup", 1, false)
        events.clear()
        assertEquals(-1, Original.call(adapter, "getActiveItemPosition"))
        Original.call(adapter, "updateCurrentProgress")
        assertTrue(events.isEmpty())
        Original.call(adapter, "setActiveIndex", 1)
        assertEquals(0, Original.call(adapter, "getActiveItemPosition"))
        assertEquals(listOf(Notice("change", 0, 1)), events)
    }
}
