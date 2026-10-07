package com.debrify.app.tv

import android.graphics.Color
import android.view.View
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvGuideVisibilityCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun iptvCurrentLiveFavoriteGroupAndEpgUseExactVisibleOrGoneStates() {
        val entries = mutableListOf(Original.channel())
        val adapter = Original.channels(entries)
        val row = holder(adapter)
        for (current in listOf(false, true)) for (live in listOf(false, true)) {
            for (favorite in listOf(false, true)) for (details in listOf(false, true)) {
                entries[0] = Original.channel(index = 4, current = current, live = live, favorite = favorite,
                    number = null, group = if (details) "Group" else null, epg = if (details) "Film" else null)
                row.itemView.scaleX = 1.5f
                row.itemView.scaleY = 1.5f
                adapter.onBindViewHolder(row, 0)
                visible(row, "nowBadge", current)
                visible(row, "liveBadge", live && !current)
                visible(row, "favorite", favorite)
                visible(row, "group", details)
                visible(row, "epg", details)
                visible(row, "logo", false)
                visible(row, "letter", true)
                assertEquals("5", (Original.field(row, "number") as TextView).text.toString())
                assertEquals(if (current) Color.parseColor("#00E5FF") else Color.argb(217, 255, 255, 255),
                    (Original.field(row, "name") as TextView).currentTextColor)
                assertEquals(1f, row.itemView.scaleX, 0f)
                assertEquals(1f, row.itemView.scaleY, 0f)
                assertEquals(if (current) Color.argb(204, 0, 229, 255) else Color.argb(46, 255, 255, 255),
                    (Original.field(row, "number") as TextView).currentTextColor)
            }
        }
    }

    @Test fun epgAiringReplayFutureAndExpiredRowsPinVisibilityAlphaAndProgressScale() {
        val adapter = Original.epg(emptyList())
        val row = adapter.createViewHolder(parent, 0)
        val now = System.currentTimeMillis()
        val programs = listOf(Original.program("now", now - 500, now + 500, description = "Detail"),
            Original.program("future", now + 500, now + 1500),
            Original.program("expired", now - 1500, now - 500),
            Original.program("replay", now - 1500, now - 500, archive = true),
            Original.program("ended", now - 1000, now - 1),
            Original.program("starting", now - 1, now + 999),
            Original.program("zero duration", now - 1000, now - 1000))
        Original.call(adapter, "updatePrograms", programs)
        for (position in programs.indices) {
            try { adapter.onBindViewHolder(row, position) }
            catch (error: ArithmeticException) { fail("EPG bind must handle a zero-duration programme: $error") }
            visible(row, "description", position == 0)
            visible(row, "now", position in listOf(0, 3, 5))
            visible(row, "progress", position in listOf(0, 5))
            assertEquals(if (position in listOf(2, 4, 6)) 0.55f else 1f, row.itemView.alpha, 0f)
            val progress = (Original.field(row, "progress") as android.widget.ProgressBar).progress
            val expected = listOf(500, 0, 1000, 1000, 1000, 1, 1000)[position]
            assertTrue("position=$position progress=$progress", progress in expected..(expected + 30).coerceAtMost(1000))
        }
    }

    @Test fun stremioSwitchCurrentLoadingEmptyAndNextRowsPinEveryVisibilityAndTextAlpha() {
        val entries = mutableListOf(Original.tvChannel())
        val adapter = Original.tvGuide(entries)
        val row = holder(adapter)
        for (current in listOf(false, true)) for (loading in listOf(false, true)) {
            for (switching in listOf(false, true)) for (data in listOf(false, true)) {
                entries[0] = Original.tvChannel(current = current, loading = loading, switching = switching, data = data)
                row.itemView.scaleX = 1.5f
                row.itemView.scaleY = 1.5f
                adapter.onBindViewHolder(row, 0)
                assertEquals(1f, row.itemView.scaleX, 0f)
                assertEquals(1f, row.itemView.scaleY, 0f)
                visible(row, "accentBar", current)
                visible(row, "poster", false)
                visible(row, "posterLetter", true)
                visible(row, "nextTitle", data)
                visible(row, "progressContainer", data)
                visible(row, "nowBadge", !switching && current)
                visible(row, "loading", switching || (!current && loading))
                val title = Original.field(row, "nowTitle") as TextView
                if (switching) assertEquals(Color.argb(204, 0, 229, 255), title.currentTextColor)
                else if (data) assertEquals(if (current) Color.argb(230, 0, 229, 255)
                    else Color.argb(179, 255, 255, 255), title.currentTextColor)
                else if (loading) assertEquals(Color.argb(89, 255, 255, 255), title.currentTextColor)
                assertEquals(if (current) Color.argb(204, 0, 229, 255) else Color.argb(46, 255, 255, 255),
                    (Original.field(row, "number") as TextView).currentTextColor)
                assertEquals(if (current) Color.parseColor("#00E5FF") else Color.argb(217, 255, 255, 255),
                    (Original.field(row, "channelName") as TextView).currentTextColor)
                assertEquals(if (current) Color.parseColor("#00E5FF") else Color.argb(89, 255, 255, 255),
                    (Original.field(row, "typeBadge") as TextView).currentTextColor)
            }
        }
        val empty = Original.tvChannel(name = "", title = "Film")
        Original.set(empty, "nextUpTitle", null)
        Original.set(empty, "nowPlayingYear", "")
        Original.set(empty, "nowPlayingRating", 0.0)
        Original.set(empty, "nowPlayingSlotEndMs", 0L)
        entries[0] = empty
        adapter.onBindViewHolder(row, 0)
        visible(row, "nextTitle", false)
        visible(row, "progressContainer", false)
        assertEquals("?", (Original.field(row, "posterLetter") as TextView).text.toString())
        assertEquals("Film", (Original.field(row, "nowTitle") as TextView).text.toString())
        Original.set(empty, "nowPlayingRating", 0.1)
        adapter.onBindViewHolder(row, 0)
        assertEquals("Film ★ 0.1", (Original.field(row, "nowTitle") as TextView).text.toString())
        focus(row.itemView, true)
        visible(row, "accentBar", true)
        focus(row.itemView, false)
        visible(row, "accentBar", false)
    }

    @Test fun stremioEndTimeUsesTwelveAtMidnightAndNoonAndGoneAtTheStopBoundary() {
        val oldZone = TimeZone.getDefault()
        val oldLocale = Locale.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            Locale.setDefault(Locale.US)
            val channel = Original.tvChannel()
            val adapter = Original.tvGuide(mutableListOf(channel))
            val row = holder(adapter)
            for ((hour, expected) in listOf(0 to "12:05 AM", 12 to "12:05 PM", 13 to "1:05 PM")) {
                val calendar = Calendar.getInstance().apply {
                    add(Calendar.DATE, 1)
                    set(Calendar.HOUR_OF_DAY, hour)
                    set(Calendar.MINUTE, 5)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                Original.set(channel, "nowPlayingSlotEndMs", calendar.timeInMillis)
                adapter.onBindViewHolder(row, 0, mutableListOf<Any>("guide_data"))
                visible(row, "endTime", true)
                assertEquals(expected, (Original.field(row, "endTime") as TextView).text.toString())
            }
            Original.set(channel, "nowPlayingSlotEndMs", System.currentTimeMillis())
            adapter.onBindViewHolder(row, 0, mutableListOf<Any>("guide_data"))
            visible(row, "endTime", false)
            Original.set(channel, "nowPlayingSlotEndMs", 1L)
            adapter.onBindViewHolder(row, 0, mutableListOf<Any>("guide_data"))
            visible(row, "progressContainer", true)
            visible(row, "endTime", false)
        } finally {
            TimeZone.setDefault(oldZone)
            Locale.setDefault(oldLocale)
        }
    }

    private fun visible(row: RecyclerView.ViewHolder, field: String, yes: Boolean) {
        assertEquals(field, if (yes) View.VISIBLE else View.GONE, (Original.field(row, field) as View).visibility)
    }
}
