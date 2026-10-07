package com.debrify.app.tv

import android.graphics.Color
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
internal class TvIptvAdapterCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun channelClassicRowsKeepBadgesFallbackClickLongClickAndFocus() {
        val first = Original.channel(current = true, favorite = true, epg = "Film", loaded = true)
        var clicked: Any? = null
        var longClicked: Any? = null
        val adapter = Original.channels(mutableListOf(first), click = { clicked = it }, longClick = { longClicked = it })
        assertEquals(1, adapter.itemCount)
        assertEquals(0, adapter.getItemViewType(0))
        val row = holder(adapter)
        assertEquals("7", text(row, R.id.iptv_channel_number))
        assertEquals("Cinema", text(row, R.id.iptv_channel_name))
        assertEquals("Movies", text(row, R.id.iptv_channel_group))
        assertEquals("Now: Film", text(row, R.id.iptv_channel_epg))
        assertEquals("C", text(row, R.id.iptv_channel_letter))
        assertEquals(View.GONE, view(row, R.id.iptv_channel_logo).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.iptv_channel_letter).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.iptv_channel_now_badge).visibility)
        assertEquals(View.GONE, view(row, R.id.iptv_channel_live_badge).visibility)
        assertEquals(View.VISIBLE, view(row, R.id.iptv_channel_favorite).visibility)
        row.itemView.performClick()
        assertSame(first, clicked)
        assertTrue(row.itemView.performLongClick())
        assertSame(first, longClicked)
        focus(row.itemView, true)
        advance()
        assertEquals(1.02f, row.itemView.scaleX, 0.001f)
        focus(row.itemView, false)
        advance()
        assertEquals(1f, row.itemView.scaleX, 0.001f)
        val noLongClick = Original.channels(mutableListOf(Original.channel(index = 1, name = "", live = false, group = null)))
        val other = holder(noLongClick)
        parent.addView(other.itemView)
        assertFalse(other.itemView.performLongClick())
        assertEquals("?", text(other, R.id.iptv_channel_letter))
        assertEquals(View.GONE, view(other, R.id.iptv_channel_group).visibility)
        assertEquals(View.GONE, view(other, R.id.iptv_channel_live_badge).visibility)
    }

    @Test fun channelStylesKeepConsoleNumbersAndEditionColors() {
        for (style in listOf(GuideStyle.GLASS, GuideStyle.EDITION, GuideStyle.CONSOLE)) {
            val adapter = Original.channels(mutableListOf(Original.channel(current = true)), style = style)
            val row = holder(adapter)
            val tokens = GuideTokens.of(style)!!
            assertEquals(if (style == GuideStyle.CONSOLE) "007" else "7", text(row, R.id.iptv_channel_number))
            val name = view(row, R.id.iptv_channel_name) as android.widget.TextView
            assertEquals(if (style == GuideStyle.EDITION) tokens.fg else tokens.accent, name.currentTextColor)
            assertEquals(tokens.fgDim, (view(row, R.id.iptv_channel_epg) as android.widget.TextView).currentTextColor)
            assertNotNull(row.itemView.background)
            assertEquals(GuideStyle.EDITION != style, view(row, R.id.iptv_channel_now_badge).background != null)
        }
    }

    @Test fun epgPayloadOnlyInFirstSlotPreservesFocusScaleAndName() {
        val entry = Original.channel(epg = "Before", loaded = true)
        val adapter = Original.channels(mutableListOf(entry))
        for (payloads in listOf<List<Any>>(emptyList(), listOf("unknown"), listOf("epg"), listOf("epg", "unknown"), listOf("unknown", "epg"))) {
            Original.set(entry, "name", "Before")
            Original.set(entry, "epgNowTitle", "Before")
            val row = holder(adapter)
            row.itemView.scaleX = 1.2f
            row.itemView.requestFocus()
            Original.set(entry, "name", "After")
            Original.set(entry, "epgNowTitle", "After")
            adapter.onBindViewHolder(row, 0, payloads.toMutableList())
            val partial = payloads.firstOrNull() == "epg"
            assertEquals(if (partial) "Before" else "After", text(row, R.id.iptv_channel_name))
            assertEquals("Now: After", text(row, R.id.iptv_channel_epg))
            assertEquals(if (partial) 1.2f else 1f, row.itemView.scaleX, 0f)
            assertTrue(row.itemView.hasFocus())
        }
    }

    @Test fun staleEpgRequestsOnlyEligibleLiveRowsAndSnapshotsStayIndependent() {
        val now = System.currentTimeMillis()
        val cases = listOf(
            Original.channel(loaded = false),
            Original.channel(loaded = true, stop = now - 1000),
            Original.channel(loaded = true, stop = now + 60_000),
            Original.channel(loaded = true, stop = 0),
            Original.channel(loaded = false, loading = true),
            Original.channel(live = false),
        )
        val asked = mutableListOf<Any>()
        val adapter = Original.channels(cases.toMutableList(), epg = { asked += it })
        cases.indices.forEach { holder(adapter, it) }
        assertEquals(listOf(cases[0], cases[1]), asked)
        val snapshot = Original.call(adapter, "entriesSnapshot") as List<*>
        assertSame(cases[0], snapshot[0])
        Original.call(adapter, "updateChannels", listOf(cases[1]))
        assertEquals(6, snapshot.size)
        assertEquals(1, adapter.itemCount)
        assertSame(cases[1], Original.call(adapter, "entryAt", 0))
        assertNull(Original.call(adapter, "entryAt", 99))
        assertEquals(0, Original.call(adapter, "positionOf", null))
        assertEquals(0, Original.call(adapter, "getCurrentChannelPosition"))
    }

    @Test fun identityNotificationsRejectEqualCopiesAndAvoidDuplicateCurrentUpdates() {
        val first = Original.channel()
        val second = Original.channel(index = 1, current = true)
        val equalCopy = Original.channel()
        assertEquals(first, equalCopy)
        val adapter = Original.channels(mutableListOf(first, second))
        val events = notices(adapter)
        Original.call(adapter, "notifyEpgFor", equalCopy)
        Original.call(adapter, "notifyFavoriteFor", equalCopy)
        assertTrue(events.isEmpty())
        Original.call(adapter, "notifyEpgFor", second)
        Original.call(adapter, "notifyFavoriteFor", first)
        Original.call(adapter, "notifyCurrentChanged", first, second)
        assertEquals(listOf(Notice("change", 1, 1, "epg"), Notice("change", 0, 1), Notice("change", 0, 1), Notice("change", 1, 1)), events)
        events.clear()
        Original.call(adapter, "notifyCurrentChanged", second, second)
        assertEquals(listOf(Notice("change", 1, 1)), events)
        assertEquals(1, Original.call(adapter, "positionOf", second))
        assertEquals(1, Original.call(adapter, "getCurrentChannelPosition"))
    }

    @Test fun diffUpdatesDistinguishContentsIdentityMovesAndAliasedInput() {
        val first = Original.channel()
        val second = Original.channel(index = 1)
        val underlying = mutableListOf(first, second)
        val adapter = Original.channels(underlying)
        val events = notices(adapter)
        Original.call(adapter, "updateChannels", underlying)
        assertTrue(events.isEmpty())
        assertEquals(2, adapter.itemCount)
        val favorite = Original.channel(favorite = true)
        Original.call(adapter, "updateChannels", listOf(favorite, second))
        assertEquals(listOf(Notice("change", 0, 1)), events)
        events.clear()
        Original.call(adapter, "updateChannels", listOf(second, favorite))
        assertEquals(1, events.count { it.kind == "move" })
        events.clear()
        val differentSource = Original.channel(source = "different", favorite = true)
        Original.call(adapter, "updateChannels", listOf(second, differentSource))
        assertTrue(events.any { it.kind == "remove" })
        assertTrue(events.any { it.kind == "insert" })
        assertFalse(events.any { it.kind == "change" })
        assertSame(differentSource, Original.call(adapter, "entryAt", 1))
    }
}
