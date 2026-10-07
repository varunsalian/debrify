package com.debrify.app.tv

import android.view.View
import android.widget.ProgressBar
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
internal class TvPlaylistAdapterCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun seasonsGuideUnionAndFilteringKeepNumericEpisodeOrder() {
        val items = listOf(item(0, 2, 10, "Ten"), item(1, 1, 2, "Two"), item(2, 2, 2, "Second"))
        val adapter = Original.playlist(items, listOf(Original.guide(2, 1, "Missing"), Original.guide(1, 2, "Two")))
        assertEquals(listOf(1, 2), Original.get(adapter, "availableSeasons"))
        assertEquals(6, adapter.itemCount)
        assertEquals(listOf(0, 1, 0, 1, 1, 1), (0 until adapter.itemCount).map(adapter::getItemViewType))
        assertEquals("SEASON 1", text(holder(adapter), R.id.season_header_title))
        assertEquals("1 Episode", text(holder(adapter), R.id.season_header_subtitle))
        val header = holder(adapter, 2)
        assertFalse(header.itemView.isFocusable)
        assertFalse(header.itemView.isClickable)
        assertEquals("3 Episodes", text(header, R.id.season_header_subtitle))
        assertEquals(listOf("Missing", "Second", "Ten"), (3..5).map { text(holder(adapter, it), R.id.android_tv_playlist_item_title) })
        Original.call(adapter, "filterBySeason", 2)
        assertEquals(3, adapter.itemCount)
        assertEquals(1, adapter.getItemViewType(0))
        Original.call(adapter, "filterBySeason", 99)
        assertEquals(0, adapter.itemCount)
        Original.call(adapter, "filterBySeason", null)
        assertEquals(6, adapter.itemCount)
    }

    @Test fun missingAndActualRebindResetDimmingAndClickOwnership() {
        var played = -99
        var fetched: Pair<Int, Int>? = null
        val adapter = Original.playlist(listOf(item(0, title = "Actual")),
            listOf(Original.guide(1, 1), Original.guide(1, 2, "Missing", watched = true)),
            fetch = { season, episode -> fetched = season to episode }, click = { played = it })
        val row = holder(adapter, 2)
        assertEquals(0.55f, row.itemView.alpha, 0f)
        assertEquals("Missing", text(row, R.id.android_tv_playlist_item_title))
        assertEquals(View.VISIBLE, view(row, R.id.android_tv_playlist_item_watched).visibility)
        row.itemView.performClick()
        assertEquals(1 to 2, fetched)
        assertEquals(-99, played)
        adapter.onBindViewHolder(row, 1)
        assertEquals(1f, row.itemView.alpha, 0f)
        assertEquals("Actual", text(row, R.id.android_tv_playlist_item_title))
        assertEquals(View.GONE, view(row, R.id.android_tv_playlist_item_watched).visibility)
        row.itemView.performClick()
        assertEquals(0, played)
        adapter.onBindViewHolder(row, 2)
        assertEquals(0.55f, row.itemView.alpha, 0f)
        row.itemView.performClick()
        assertEquals(1 to 2, fetched)
        assertEquals(0, played)
    }

    @Test fun episodeBindKeepsWatchedProgressFallbackAndClassicFocus() {
        val items = mutableListOf(item())
        val adapter = Original.playlist(items)
        val row = holder(adapter, 1)
        assertEquals("S01 E01", text(row, R.id.android_tv_playlist_item_badge))
        assertEquals("Description", text(row, R.id.android_tv_playlist_item_description))
        assertEquals("30 min", text(row, R.id.android_tv_playlist_item_duration))
        assertEquals("8.5", text(row, R.id.android_tv_playlist_item_rating_text))
        assertEquals("40%", text(row, R.id.android_tv_playlist_item_progress_text))
        assertEquals(40, row.itemView.findViewById<ProgressBar>(R.id.android_tv_playlist_item_poster_progress).progress)
        assertEquals(View.GONE, view(row, R.id.android_tv_playlist_item_poster).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.fallback_container).visibility)
        assertEquals(View.GONE, view(row, R.id.android_tv_playlist_item_fallback).visibility)
        val container = view(row, R.id.android_tv_playlist_item_container)
        focus(container, true)
        assertEquals(View.VISIBLE, view(row, R.id.focus_border).visibility)
        focus(container, false)
        assertEquals(View.GONE, view(row, R.id.focus_border).visibility)
        items[0] = items[0].copy(watched = true, description = " null ", rating = null, durationMs = 0)
        adapter.onBindViewHolder(row, 1)
        assertEquals(0.5f, container.alpha, 0f)
        assertEquals(View.VISIBLE, view(row, R.id.android_tv_playlist_item_watched).visibility)
        assertEquals(View.GONE, view(row, R.id.android_tv_playlist_item_description).visibility)
        assertEquals(View.GONE, view(row, R.id.android_tv_playlist_item_rating_badge).visibility)
        assertEquals(View.GONE, view(row, R.id.android_tv_playlist_item_duration).visibility)
        Original.call(adapter, "setActiveIndex", 0)
        adapter.onBindViewHolder(row, 1)
        assertTrue(container.isSelected)
        assertEquals(1f, container.alpha, 0f)
        assertEquals(View.VISIBLE, view(row, R.id.now_playing_indicator).visibility)
        Original.call(adapter, "setActiveIndex", -1)
        adapter.onBindViewHolder(row, 1)
    }

    @Test fun skinBinderAndFocusedItemUseTheCurrentOriginalIndex() {
        var bound: Triple<PlaybackItem, Int, Boolean>? = null
        var focused: Pair<PlaybackItem, Int>? = null
        var clicked = -1
        val items = listOf(item(0, episode = 2), item(1, episode = 1))
        val adapter = Original.playlist(items, skin = { _, value, index, active -> bound = Triple(value, index, active) },
            focus = { value, index -> focused = value to index }, click = { clicked = it })
        Original.call(adapter, "setActiveIndex", 1)
        val row = holder(adapter, 1)
        assertEquals(Triple(items[1], 1, true), bound)
        focus(view(row, R.id.android_tv_playlist_item_container), false)
        assertNull(focused)
        focus(view(row, R.id.android_tv_playlist_item_container), true)
        assertEquals(items[1] to 1, focused)
        row.itemView.performClick()
        assertEquals(1, clicked)
        Original.call(adapter, "setActiveIndex", -1)
        adapter.onBindViewHolder(row, 1)
    }

    @Test fun progressPayloadAnywherePreservesTitleButUnknownAndEmptyFullyBind() {
        val items = mutableListOf(item(title = "Before"))
        val adapter = Original.playlist(items)
        for (payloads in listOf<List<Any>>(emptyList(), listOf("unknown"), listOf("progress_update"),
            listOf("unknown", "progress_update"), listOf("progress_update", "unknown"))) {
            items[0] = item(title = "Before", progress = 40)
            val row = holder(adapter, 1)
            items[0] = item(title = "After", progress = 70)
            adapter.onBindViewHolder(row, 1, payloads.toMutableList())
            assertEquals(if ("progress_update" in payloads) "Before" else "After", text(row, R.id.android_tv_playlist_item_title))
            assertEquals("70%", text(row, R.id.android_tv_playlist_item_progress_text))
        }
        val header = holder(adapter)
        header.itemView.findViewById<android.widget.TextView>(R.id.season_header_title).text = "sentinel"
        adapter.onBindViewHolder(header, 0, mutableListOf<Any>("progress_update"))
        assertEquals("sentinel", text(header, R.id.season_header_title))
        val missingAdapter = Original.playlist(emptyList(), listOf(Original.guide(1, 1, "Missing")))
        val missing = holder(missingAdapter, 1)
        missing.itemView.findViewById<android.widget.TextView>(R.id.android_tv_playlist_item_title).text = "sentinel"
        missingAdapter.onBindViewHolder(missing, 1, mutableListOf<Any>("progress_update"))
        assertEquals("sentinel", text(missing, R.id.android_tv_playlist_item_title))
    }

    @Test fun activeAndProgressNotificationsRespectHiddenAndUnchangedPositions() {
        val adapter = Original.playlist(listOf(item(0), item(1, season = 2)))
        val events = notices(adapter)
        Original.call(adapter, "setActiveIndex", 0)
        assertEquals(listOf(Notice("change", 1, 1)), events)
        events.clear()
        Original.call(adapter, "setActiveIndex", 0)
        Original.call(adapter, "updateCurrentProgress")
        assertEquals(listOf(Notice("change", 1, 1), Notice("change", 1, 1), Notice("change", 1, 1, "progress_update")), events)
        Original.call(adapter, "filterBySeason", 2)
        assertEquals(-1, Original.call(adapter, "getActiveItemPosition"))
        events.clear()
        Original.call(adapter, "updateCurrentProgress")
        assertTrue(events.isEmpty())
        Original.call(adapter, "setActiveIndex", 1)
        assertEquals(0, Original.call(adapter, "getActiveItemPosition"))
        assertEquals(listOf(Notice("change", 0, 1)), events)
    }
}
