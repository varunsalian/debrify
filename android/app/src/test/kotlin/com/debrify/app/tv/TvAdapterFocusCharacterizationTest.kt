package com.debrify.app.tv

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.view.View
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvAdapterFocusCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun seasonHeaderZeroOneAndManyUseTheOriginalPluralRule() {
        val adapter = Original.playlist(listOf(item()))
        val row = holder(adapter)
        for ((count, expected) in listOf(0 to "0 Episodes", 1 to "1 Episode", 2 to "2 Episodes")) {
            Original.call(row, "bind", 3, count)
            assertEquals("SEASON 3", text(row, R.id.season_header_title))
            assertEquals(expected, text(row, R.id.season_header_subtitle))
        }
        val unseasoned = Original.playlist(listOf(item(season = 0), item(index = 1).copy(season = null)))
        assertEquals(2, unseasoned.itemCount)
        assertEquals(listOf(1, 1), (0 until unseasoned.itemCount).map(unseasoned::getItemViewType))
    }

    @Test fun classicEpisodeFocusUsesBothScaleAxesElevationAndDurations() {
        val adapter = Original.playlist(listOf(item()))
        val row = holder(adapter, 1)
        val container = view(row, R.id.android_tv_playlist_item_container)
        val card = view(row, R.id.card_content)
        assertEquals(1f, card.scaleX, 0f)
        assertEquals(1f, card.scaleY, 0f)
        assertEquals(8f, card.elevation, 0f)
        focus(container, true)
        assertEquals(View.VISIBLE, view(row, R.id.focus_border).visibility)
        assertEquals(150L, card.animate().duration)
        assertEquals(16f, card.elevation, 0f)
        advance()
        assertEquals(1.08f, card.scaleX, 0.001f)
        assertEquals(1.08f, card.scaleY, 0.001f)
        focus(container, false)
        assertEquals(View.GONE, view(row, R.id.focus_border).visibility)
        assertEquals(100L, card.animate().duration)
        assertEquals(8f, card.elevation, 0f)
        advance()
        assertEquals(1f, card.scaleX, 0.001f)
        assertEquals(1f, card.scaleY, 0.001f)
        adapter.onBindViewHolder(row, 1)
        assertEquals(8f, card.elevation, 0f)
    }

    @Test fun movieFocusUsesBothScaleAxesAndBothDurations() {
        val adapter = Original.movies(listOf(item()), Original.groups("MAIN" to listOf(0)))
        val row = holder(adapter)
        val container = view(row, R.id.android_tv_playlist_item_container)
        focus(container, true)
        assertEquals(View.VISIBLE, view(row, R.id.selection_overlay).visibility)
        assertEquals(200L, container.animate().duration)
        advance(250)
        assertEquals(1.08f, container.scaleX, 0.001f)
        assertEquals(1.08f, container.scaleY, 0.001f)
        focus(container, false)
        assertEquals(150L, container.animate().duration)
        advance()
        assertEquals(1f, container.scaleX, 0.001f)
        assertEquals(1f, container.scaleY, 0.001f)
        assertEquals(View.GONE, view(row, R.id.selection_overlay).visibility)
    }

    @Test fun guideAndPickerFocusTargetsDurationsAndRowDimensionsStayExact() {
        val category = Original.categories()
        Original.call(category, "update", listOf("All categories"))
        val list = Original.lists(listOf(Original.list("one", "List")), emptySet())
        Original.call(list, "setReady", true)
        for ((adapter, target, duration) in listOf(
            Triple(Original.channels(mutableListOf(Original.channel())), 1.02f, 150L),
            Triple(Original.tvGuide(mutableListOf(Original.tvChannel())), 1.02f, 150L),
            Triple(category, 1.015f, 120L), Triple(list, 1.015f, 120L),
        )) {
            val row = holder(adapter)
            focus(row.itemView, true)
            assertEquals(duration, row.itemView.animate().duration)
            advance()
            assertEquals(target, row.itemView.scaleX, 0.001f)
            assertEquals(target, row.itemView.scaleY, 0.001f)
            focus(row.itemView, false)
            assertEquals(duration, row.itemView.animate().duration)
            advance()
            assertEquals(1f, row.itemView.scaleX, 0.001f)
            assertEquals(1f, row.itemView.scaleY, 0.001f)
            if (row.itemView is TextView) {
                val label = row.itemView as TextView
                val density = label.resources.displayMetrics.density
                assertEquals((52 * density).toInt(), label.layoutParams.height)
                assertEquals((6 * density).toInt(), (label.layoutParams as RecyclerView.LayoutParams).bottomMargin)
                assertEquals((16 * density).toInt(), label.paddingLeft)
                assertEquals((16 * density).toInt(), label.paddingRight)
                assertEquals(android.util.TypedValue.applyDimension(android.util.TypedValue.COMPLEX_UNIT_SP,
                    15f, label.resources.displayMetrics), label.textSize, 0f)
                assertEquals(1, label.maxLines)
            }
        }
    }

    @Test fun playingDotKeepsItsPulseValuesDurationRepeatAndStopReset() {
        val adapter = Original.playlist(listOf(item()))
        Original.call(adapter, "setActiveIndex", 0)
        val row = holder(adapter, 1)
        val animator = Original.field(row, "pulseAnimator") as ObjectAnimator
        try {
            assertEquals(1000L, animator.duration)
            assertEquals(ValueAnimator.INFINITE, shadowOf(animator).actualRepeatCount)
            animator.currentPlayTime = 0
            assertEquals(1f, view(row, R.id.now_playing_dot).alpha, 0f)
            animator.currentPlayTime = 500
            assertEquals(0.3f, view(row, R.id.now_playing_dot).alpha, 0.001f)
            animator.currentPlayTime = 1000
            assertEquals(1f, view(row, R.id.now_playing_dot).alpha, 0f)
            Original.call(adapter, "setActiveIndex", -1)
            adapter.onBindViewHolder(row, 1)
            assertFalse(animator.isStarted)
            assertNull(Original.field(row, "pulseAnimator"))
            assertEquals(1f, view(row, R.id.now_playing_dot).alpha, 0f)
        } finally {
            animator.cancel()
        }
    }
}
