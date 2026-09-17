package com.debrify.app.tv

import android.app.Activity
import android.graphics.Color
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class TvSourceBrowserFocusTest {
    @Test fun episodeScopeExcludesOldLinksButKeepsPacksAndUnknownScope() {
        assertFalse(sourceVisibleForEpisode("directUrl", "tt123:1:1", 1, 3))
        assertFalse(sourceVisibleForEpisode("externalUrl", "tt123:1:1", 1, 3))
        assertFalse(sourceVisibleForEpisode("directUrl", "tt123:1:1", 2, 1))
        assertTrue(sourceVisibleForEpisode("directUrl", "tt123:1:3", 1, 3))
        assertTrue(sourceVisibleForEpisode("torrent", "tt123:1:1", 1, 3))
        assertTrue(sourceVisibleForEpisode("directUrl", null, 1, 3))
        assertTrue(sourceVisibleForEpisode("directUrl", "tt123:1:1", null, null))
    }

    @Test fun dpadAndRailFocusKeepRowsAndImportedArtworkAttached() {
        val lifecycle = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = lifecycle.get()
        val root = LinearLayout(activity)
        val rail = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val results = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val railScroll = ScrollView(activity).apply { addView(rail) }
        val resultsScroll = ScrollView(activity).apply { addView(results) }
        root.addView(railScroll, LinearLayout.LayoutParams(200, 600))
        root.addView(resultsScroll, LinearLayout.LayoutParams(800, 600))
        activity.setContentView(root)
        val entries = (0..11).map {
            TvSourceBrowserEntry(it, "Movie $it", "addon", "4K", "12 GB", 5, false, false)
        }
        val badges = listOf(mapOf<String, Any>(
            "label" to "4K", "imageUrl" to "android.resource://android/drawable/ic_media_play",
            "fillColor" to Color.DKGRAY, "textColor" to Color.WHITE,
        ))
        var played = -1
        var current = 0
        val controller = TvSourceBrowserController(
            activity, root, rail, railScroll, TextView(activity), TextView(activity),
            TextView(activity), TextView(activity), results, resultsScroll,
            object : TvSourceBrowserController.Callbacks {
                override fun entries() = entries
                override fun currentIndex() = current
                override fun isSeries() = false
                override fun loadMoreMode(): String? = null
                override fun isLoading(mode: String) = false
                override fun requestLoadMore(mode: String) {}
                override fun onSourceSelected(index: Int) { played = index }
                override fun onHidden() {}
                override fun requestBadges(entry: TvSourceBrowserEntry, complete: (TvSourceBadgeResult?) -> Unit) {
                    complete(TvSourceBadgeResult(true, badges))
                }
            },
        )
        fun layout() {
            root.measure(View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY))
            root.layout(0, 0, 1000, 600)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(300))
        }
        fun key(code: Int) { assertTrue(controller.dispatchKey(KeyEvent(KeyEvent.ACTION_DOWN, code))) }
        try {
            controller.show()
            repeat(4) { layout() }
            val rows = (0..1).map { results.getChildAt(it) as LinearLayout }
            // Explicitly seed the strips too: this test is about View lifetime,
            // independent of visibility-based matcher admission and Glide timing.
            val strips = rows.map { it.getChildAt(2) as TvStreamBadgeStrip }
            strips.forEach { it.show(badges) }
            layout()
            val images = strips.map { it.getChildAt(0) as ImageView }
            val builtIns = rows.map { it.getChildAt(1) as TvStreamBadgeStrip }
            val chips = builtIns.map { strip -> (0 until strip.childCount).map { strip.getChildAt(it) } }
            var detachments = 0
            images.forEach { image -> image.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                override fun onViewAttachedToWindow(v: View) {}
                override fun onViewDetachedFromWindow(v: View) { detachments++ }
            }) }
            key(KeyEvent.KEYCODE_DPAD_DOWN)
            assertEquals(Color.BLACK, (rows[1].getChildAt(0) as TextView).currentTextColor)
            assertEquals(0xE6FFFFFF.toInt(), (rows[0].getChildAt(0) as TextView).currentTextColor)
            repeat(8) {
                key(KeyEvent.KEYCODE_DPAD_UP)
                key(KeyEvent.KEYCODE_DPAD_DOWN)
            }
            key(KeyEvent.KEYCODE_DPAD_LEFT)
            key(KeyEvent.KEYCODE_DPAD_RIGHT)
            layout()
            rows.indices.forEach { i ->
                assertSame(rows[i], results.getChildAt(i))
                assertSame(strips[i], rows[i].getChildAt(2))
                assertSame(images[i], strips[i].getChildAt(0))
                chips[i].indices.forEach { j -> assertSame(chips[i][j], builtIns[i].getChildAt(j)) }
            }
            assertEquals(0, detachments)
            assertTrue(rows[0].isSelected)
            assertFalse(rows[1].isSelected)
            val playing = rows[0].getChildAt(0) as TextView
            assertNotNull(playing.compoundDrawablesRelative[2])
            assertEquals("Movie 0, Playing", playing.contentDescription)
            assertNull((rows[1].getChildAt(0) as TextView).compoundDrawablesRelative[2])
            key(KeyEvent.KEYCODE_DPAD_CENTER)
            assertEquals(1, played)
            // Picking a candidate alone does not change the playing marker.
            controller.render()
            assertTrue(results.getChildAt(0).isSelected)
            assertFalse(results.getChildAt(1).isSelected)
            // Reopening lands on the player's committed source, even below
            // the initial viewport, and a later committed switch moves it.
            controller.hide()
            current = 10
            controller.show()
            repeat(4) { layout() }
            val currentRow = results.getChildAt(10) as LinearLayout
            assertTrue(currentRow.isSelected)
            assertEquals(Color.BLACK, (currentRow.getChildAt(0) as TextView).currentTextColor)
            assertTrue(resultsScroll.scrollY > 0)
            assertTrue(currentRow.top < resultsScroll.scrollY + resultsScroll.height)
            assertTrue(currentRow.bottom > resultsScroll.scrollY)
            current = 11
            controller.render()
            assertFalse(results.getChildAt(10).isSelected)
            assertTrue(results.getChildAt(11).isSelected)
        } finally {
            controller.destroy()
            lifecycle.pause().stop().destroy()
        }
    }
}
