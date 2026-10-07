package com.debrify.app.tv

import android.graphics.drawable.ColorDrawable
import android.view.View
import android.widget.ProgressBar
import androidx.recyclerview.widget.RecyclerView
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
internal class TvPlaylistThresholdCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun missingToActualBindResetsRootAndContainerAlphaIndependently() {
        // The holder's public view contract uses descendant IDs. A wrapper
        // separates row dimming from the watched-card alpha instead of hiding
        // one reset behind another write to the same classic root view.
        val card = android.view.LayoutInflater.from(activity).inflate(
            R.layout.item_android_tv_playlist_entry_horizontal, parent, false)
        val root = android.widget.FrameLayout(activity).apply { addView(card) }
        val row = Original.episodeHolder(root)
        Original.call(row, "bindMissing", item(), {})
        assertEquals(0.55f, root.alpha, 0f)
        Original.call(row, "bind", item(progress = 95), 0, false)
        assertEquals(1f, root.alpha, 0f)
        assertEquals(0.5f, view(row, R.id.android_tv_playlist_item_container).alpha, 0f)
        Original.call(row, "bindMissing", item(), {})
        assertEquals(0.55f, root.alpha, 0f)
        Original.call(row, "bind", item(progress = 0), 0, false)
        assertEquals(1f, root.alpha, 0f)
        assertEquals(1f, view(row, R.id.android_tv_playlist_item_container).alpha, 0f)
    }

    @Test fun episodeFullAndPartialBindsPinProgressThresholdsAlphaAndExactVisibility() {
        val items = mutableListOf(item())
        val adapter = Original.playlist(items)
        val row = holder(adapter, 1)
        for (partial in listOf(false, true)) for (active in listOf(false, true)) {
            Original.call(adapter, "setActiveIndex", if (active) 0 else -1)
            for (percent in listOf(0, 1, 5, 6, 94, 95, 100)) for (duration in listOf(0L, 1L, 60_000L)) {
                items[0] = item(progress = 0).copy(durationMs = duration, traktProgressPercent = percent.toDouble())
                if (partial) adapter.onBindViewHolder(row, 1, mutableListOf<Any>("progress_update"))
                else adapter.onBindViewHolder(row, 1)
                val watched = percent >= 95
                val progressing = percent in 6..94
                val message = "partial=$partial active=$active percent=$percent duration=$duration"
                assertEquals(message, if (watched && !active) 0.5f else 1f,
                    view(row, R.id.android_tv_playlist_item_container).alpha, 0f)
                visible(row, R.id.android_tv_playlist_item_watched, watched && !active)
                visible(row, R.id.now_playing_indicator, active)
                visible(row, R.id.now_playing_ring, active)
                visible(row, R.id.android_tv_playlist_item_progress_text, progressing)
                visible(row, R.id.meta_separator, progressing && duration > 0)
                visible(row, R.id.android_tv_playlist_item_poster_progress, progressing || watched)
                if (progressing || watched) {
                    val bar = view(row, R.id.android_tv_playlist_item_poster_progress) as ProgressBar
                    assertEquals(100, bar.max)
                    assertEquals(if (watched) 100 else percent, bar.progress)
                }
                if (!partial) {
                    visible(row, R.id.android_tv_playlist_item_duration, duration > 0)
                    visible(row, R.id.android_tv_playlist_item_watched_overlay, false)
                    visible(row, R.id.android_tv_playlist_item_watched_icon, false)
                    visible(row, R.id.focus_border, false)
                }
            }
        }
        Original.call(adapter, "setActiveIndex", -1)
        adapter.onBindViewHolder(row, 1)
    }

    @Test fun movieFullAndPartialBindsPinProgressThresholdsAlphaAndExactVisibility() {
        val items = mutableListOf(item())
        val adapter = Original.movies(items, Original.groups("MAIN" to listOf(0)))
        val row = holder(adapter)
        for (partial in listOf(false, true)) for (active in listOf(false, true)) {
            Original.call(adapter, "setActiveIndex", if (active) 0 else -1)
            for (percent in listOf(0, 1, 5, 6, 94, 95, 100)) {
                items[0] = item(progress = percent)
                if (partial) adapter.onBindViewHolder(row, 0, mutableListOf<Any>("progress_update"))
                else adapter.onBindViewHolder(row, 0)
                val watched = percent >= 95
                val progressing = percent in 6..94
                assertEquals("partial=$partial active=$active percent=$percent",
                    if (watched && !active) 0.4f else 1f,
                    view(row, R.id.android_tv_playlist_item_container).alpha, 0f)
                visible(row, R.id.android_tv_playlist_item_watched, watched && !active)
                visible(row, R.id.android_tv_playlist_item_playing, active)
                visible(row, R.id.android_tv_playlist_item_progress_container, progressing)
                visible(row, R.id.android_tv_playlist_item_poster_progress, progressing)
                if (progressing) {
                    assertEquals("$percent% watched", text(row, R.id.android_tv_playlist_item_progress_text))
                    val bar = view(row, R.id.android_tv_playlist_item_poster_progress) as ProgressBar
                    assertEquals(100, bar.max)
                    assertEquals(percent, bar.progress)
                }
                if (!partial) {
                    visible(row, R.id.android_tv_playlist_item_watched_overlay, false)
                    visible(row, R.id.android_tv_playlist_item_watched_icon, false)
                }
            }
        }
    }

    @Test fun episodeMetadataZeroBoundariesBadgePaddingAndFallbackStatesStayExact() {
        val items = mutableListOf(item())
        val adapter = Original.playlist(items)
        val row = holder(adapter, 1)
        for (description in listOf(null, "", "  ", " NuLl ", " Description ")) {
            for (rating in listOf(null, -1.0, 0.0, 0.1)) {
                items[0] = item().copy(description = description, rating = rating, durationMs = 59_999L)
                adapter.onBindViewHolder(row, 1)
                visible(row, R.id.android_tv_playlist_item_description, description == " Description ")
                visible(row, R.id.android_tv_playlist_item_rating_badge, rating != null && rating > 0)
                assertEquals("0 min", text(row, R.id.android_tv_playlist_item_duration))
                visible(row, R.id.android_tv_playlist_item_poster, false)
                visible(row, R.id.shimmer_overlay, false)
                visible(row, R.id.fallback_container, true)
                visible(row, R.id.android_tv_playlist_item_fallback, false)
                assertEquals(0xFF0D0D0D.toInt(), (view(row, R.id.fallback_bg).background as ColorDrawable).color)
            }
        }
        for ((current, expected) in listOf(item() to "S01 E01",
            item().copy(season = null, episode = 2) to "E02",
            item().copy(season = null, episode = null) to "E01")) {
            items[0] = current
            adapter.onBindViewHolder(row, 1)
            assertEquals(expected, text(row, R.id.android_tv_playlist_item_badge))
        }
    }

    @Test fun movieSizeBoundariesGroupColorsAndAttachedFallbackNumberStayExact() {
        val items = mutableListOf(item().copy(description = null))
        val adapter = Original.movies(items, Original.groups("MAIN" to listOf(0)))
        val row = holder(adapter)
        for ((bytes, expected) in listOf(null to null, -1L to null, 0L to null, 1L to "1 B",
            1023L to "1023 B", 1024L to "1.0 KB", 1_048_576L to "1.0 MB",
            1_073_741_824L to "1.0 GB", 1_099_511_627_776L to "1.0 TB")) {
            items[0] = items[0].copy(sizeBytes = bytes)
            adapter.onBindViewHolder(row, 0)
            visible(row, R.id.android_tv_playlist_item_description, expected != null)
            if (expected != null) assertEquals(expected, text(row, R.id.android_tv_playlist_item_description))
        }
        for ((group, color) in listOf("MAIN" to 0xFF6366F1, "EXTRAS" to 0xFFF59E0B,
            "BEHIND THE SCENES" to 0xFF10B981, "DELETED SCENES" to 0xFFEF4444,
            "FEATURETTES" to 0xFF8B5CF6, "Other" to 0xFF6B7280)) {
            val grouped = Original.movies(items, Original.groups(group to listOf(0)))
            val bound = holder(grouped)
            assertEquals(color.toInt(), (view(bound, R.id.android_tv_playlist_item_fallback).background as ColorDrawable).color)
            visible(bound, R.id.android_tv_playlist_item_poster, false)
            visible(bound, R.id.android_tv_playlist_item_fallback, true)
        }
        val reordered = Original.movies(listOf(item(), item(index = 1)), Original.groups("MAIN" to listOf(1, 0)))
        val recycler = attach(reordered)
        val attached = recycler.findViewHolderForAdapterPosition(0)!!
        reordered.onBindViewHolder(attached, 0)
        assertEquals("1", text(attached, R.id.android_tv_playlist_item_fallback))
    }

    private fun visible(row: RecyclerView.ViewHolder, id: Int, yes: Boolean) {
        assertEquals("view=$id", if (yes) View.VISIBLE else View.GONE, view(row, id).visibility)
    }
}
