package com.debrify.app.tv

import android.app.Activity
import android.view.KeyEvent
import android.view.View
import android.widget.TextView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class UnifiedMenuControllerTest {
    @Test fun duplicateUntaggedTracksRemainReachableByRemote() {
        for ((section, group) in listOf("audio" to "audio", "subs" to "emb")) {
            val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
            val root = activity.layoutInflater.inflate(R.layout.view_unified_menu, null)
            activity.setContentView(root)
            var chosen = -1
            val controller = UnifiedMenuController(activity, root,
                root.findViewById(R.id.unified_col1), root.findViewById(R.id.unified_col2),
                root.findViewById(R.id.unified_col3), root.findViewById(R.id.unified_col2_header),
                root.findViewById(R.id.unified_col3_header), root.findViewById(R.id.unified_preview),
                object : UnifiedMenuController.Callbacks {
                    override fun buildModel(sectionIndex: Int, col2Index: Int) = UnifiedMenuController.Model(
                        listOf(UnifiedMenuController.Row(section)), "",
                        listOf(UnifiedMenuController.Row(group, tag = group)), "",
                        (0..2).map { index -> UnifiedMenuController.Row("ENG", selected = index == 0,
                            onOk = { chosen = index }) })
                    override fun onSearchSubmit(query: String) {}
                    override fun searchInitialQuery() = ""
                    override fun stylePreview(tv: TextView) {}
                    override fun onHidden() {}
                }, listOf(section))
            fun key(code: Int) { controller.dispatchKey(KeyEvent(KeyEvent.ACTION_DOWN, code)) }
            controller.show(section)
            for (index in 0..2) {
                if (index > 0) key(KeyEvent.KEYCODE_DPAD_DOWN)
                controller.render() // Async refresh must also retain the duplicate occurrence.
                key(KeyEvent.KEYCODE_DPAD_CENTER)
                assertEquals("$section track $index", index, chosen)
            }
            key(KeyEvent.KEYCODE_DPAD_UP)
            key(KeyEvent.KEYCODE_DPAD_CENTER)
            assertEquals(1, chosen)
        }
    }
    @Test fun providerCompletionPreservesFocusedTrackIdentity() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val root = activity.layoutInflater.inflate(R.layout.view_unified_menu, null)
        activity.setContentView(root)
        var loaded = false
        var chosen = ""
        val controller = UnifiedMenuController(activity, root,
            root.findViewById(R.id.unified_col1), root.findViewById(R.id.unified_col2),
            root.findViewById(R.id.unified_col3), root.findViewById(R.id.unified_col2_header),
            root.findViewById(R.id.unified_col3_header), root.findViewById(R.id.unified_preview),
            object : UnifiedMenuController.Callbacks {
                override fun buildModel(sectionIndex: Int, col2Index: Int): UnifiedMenuController.Model {
                    val rows = when (col2Index) {
                        0 -> listOf(UnifiedMenuController.Row("Off"))
                        1 -> if (!loaded) listOf(UnifiedMenuController.Row("Loading", enabled = false))
                            else (0..8).map { UnifiedMenuController.Row("English", tag = "early:$it") }
                        else -> listOf("one", "two").map { id ->
                            UnifiedMenuController.Row("English", tag = id, onOk = { chosen = id })
                        }
                    }
                    return UnifiedMenuController.Model(listOf(UnifiedMenuController.Row("Subtitles")), "",
                        listOf(UnifiedMenuController.Row("Embedded", tag = "emb"),
                            UnifiedMenuController.Row("Early", tag = "addon:early"),
                            UnifiedMenuController.Row("Later", tag = "addon:later")), "", rows)
                }
                override fun onSearchSubmit(query: String) {}
                override fun searchInitialQuery() = ""
                override fun stylePreview(tv: TextView) {}
                override fun onHidden() {}
            }, listOf("subs"))
        fun key(code: Int) { controller.dispatchKey(KeyEvent(KeyEvent.ACTION_DOWN, code)) }
        controller.show("subs", "addon:later")
        key(KeyEvent.KEYCODE_DPAD_DOWN)
        loaded = true
        controller.render()
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("two", chosen)
        loaded = false // Also preserve focus when the preceding group shrinks.
        controller.render()
        chosen = ""
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("two", chosen)
    }
    @Test fun nightShortcutTargetsNightOptionsInsteadOfSelectedAudioTrack() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val root = activity.layoutInflater.inflate(R.layout.view_unified_menu, null)
        activity.setContentView(root)
        var chosen = ""
        var nightSelected = true
        val controller = UnifiedMenuController(activity, root,
            root.findViewById(R.id.unified_col1), root.findViewById(R.id.unified_col2),
            root.findViewById(R.id.unified_col3), root.findViewById(R.id.unified_col2_header),
            root.findViewById(R.id.unified_col3_header), root.findViewById(R.id.unified_preview),
            object : UnifiedMenuController.Callbacks {
                override fun buildModel(sectionIndex: Int, col2Index: Int) = UnifiedMenuController.Model(
                    listOf(UnifiedMenuController.Row("Audio")), "Audio",
                    listOf(UnifiedMenuController.Row("Audio track", tag = "audio"),
                        UnifiedMenuController.Row("Night mode", tag = "night")), "Options",
                    if (col2Index == 0) listOf(UnifiedMenuController.Row("English", selected = true,
                        onOk = { chosen = "audio" })) else listOf(
                        UnifiedMenuController.Row("Off", selected = nightSelected, onOk = { chosen = "off" }),
                        UnifiedMenuController.Row("On", onOk = { chosen = "on" })))
                override fun onSearchSubmit(query: String) {}
                override fun searchInitialQuery() = ""
                override fun stylePreview(tv: TextView) {}
                override fun onHidden() {}
            }, listOf("audio"))
        fun key(code: Int) { controller.dispatchKey(KeyEvent(KeyEvent.ACTION_DOWN, code)) }
        controller.show("audio", "night")
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("off", chosen)
        key(KeyEvent.KEYCODE_DPAD_DOWN)
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("on", chosen)
        nightSelected = false
        controller.show("audio", "night")
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("off", chosen)
        controller.show("audio", "audio")
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("audio", chosen)
    }
    @Test fun subtitleProvidersAndTracksBelongInValuesNotRail() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val root = activity.layoutInflater.inflate(R.layout.view_unified_menu, null)
        activity.setContentView(root)
        var chosen = ""
        val controls = listOf("emb", "addon:one", "search", "appearance", "timing")
        val controller = UnifiedMenuController(activity, root,
            root.findViewById(R.id.unified_col1), root.findViewById(R.id.unified_col2),
            root.findViewById(R.id.unified_col3), root.findViewById(R.id.unified_col2_header),
            root.findViewById(R.id.unified_col3_header), root.findViewById(R.id.unified_preview),
            object : UnifiedMenuController.Callbacks {
                override fun buildModel(sectionIndex: Int, col2Index: Int) = UnifiedMenuController.Model(
                    listOf(UnifiedMenuController.Row("Subtitles")), "Detected title",
                    controls.map { UnifiedMenuController.Row(it, tag = it) }, "Track",
                    listOf(UnifiedMenuController.Row("Track $col2Index", onOk = { chosen = controls[col2Index] })),
                    if (col2Index == 2) UnifiedMenuController.Col3Mode.SEARCH else UnifiedMenuController.Col3Mode.ROWS)
                override fun onSearchSubmit(query: String) {}
                override fun searchInitialQuery() = ""
                override fun stylePreview(tv: TextView) {}
                override fun onHidden() {}
            }, listOf("subs"))
        fun texts(view: View): List<String> = when (view) {
            is TextView -> listOf(view.text.toString())
            is android.view.ViewGroup -> (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
            else -> emptyList()
        }
        controller.show("subs")
        val rail = root.findViewById<android.widget.LinearLayout>(R.id.unified_col2)
        val pane = root.findViewById<android.widget.LinearLayout>(R.id.unified_col3)
        assertEquals(listOf("Subtitles", "Subtitle style", "Sync"), texts(rail))
        assertTrue(texts(pane).containsAll(listOf("Track 0", "Track 1", "ADDON:ONE")))
        pane.getChildAt(4).performClick()
        assertEquals("addon:one", chosen)
        pane.getChildAt(0).performClick()
        assertTrue(controller.inEditMode)
        controller.handleEditModeKey(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
        controller.dispatchKey(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK))
        assertFalse(controller.inEditMode)
        assertTrue(texts(pane).contains("Track 1"))
        controller.show("subs", "appearance")
        assertTrue(texts(pane).contains("Track 3"))
        controller.show("subs", "timing")
        assertTrue(texts(pane).contains("Track 4"))
    }
    @Test fun tappedSearchResultExitsEditingAndShortcutRevealsRail() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val root = activity.layoutInflater.inflate(R.layout.view_unified_menu, null)
        activity.setContentView(root)
        var search = true
        var activated = false
        val controller = UnifiedMenuController(activity, root,
            root.findViewById(R.id.unified_col1), root.findViewById(R.id.unified_col2),
            root.findViewById(R.id.unified_col3), root.findViewById(R.id.unified_col2_header),
            root.findViewById(R.id.unified_col3_header), root.findViewById(R.id.unified_preview),
            object : UnifiedMenuController.Callbacks {
                override fun buildModel(sectionIndex: Int, col2Index: Int) = UnifiedMenuController.Model(
                    listOf(UnifiedMenuController.Row("Subtitles")), "Subtitles",
                    (0..25).map { UnifiedMenuController.Row("Control $it", tag = "control$it") },
                    "Results", listOf(UnifiedMenuController.Row("Series", onOk = {
                        if (search) search = false else activated = true
                    })), if (search) UnifiedMenuController.Col3Mode.SEARCH else UnifiedMenuController.Col3Mode.ROWS)
                override fun onSearchSubmit(query: String) {}
                override fun searchInitialQuery() = "Example"
                override fun stylePreview(tv: TextView) {}
                override fun onHidden() {}
            }, listOf("subs"))
        controller.show("subs", "control25")
        root.measure(View.MeasureSpec.makeMeasureSpec(960, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(540, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, 960, 540)
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        val rail = root.findViewById<android.widget.LinearLayout>(R.id.unified_col2)
        val scroll = rail.parent as android.widget.ScrollView
        // SmoothScroll stores the destination in its Scroller until the next frames.
        val field = android.widget.ScrollView::class.java.getDeclaredField("mScroller").apply { isAccessible = true }
        val scroller = field.get(scroll) as android.widget.OverScroller
        assertTrue(scroll.scrollY > 0 || scroller.finalY > 0)
        assertTrue(controller.inEditMode)
        val values = root.findViewById<android.widget.LinearLayout>(R.id.unified_col3)
        values.getChildAt(1).performClick()
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        assertFalse(controller.inEditMode)
        controller.dispatchKey(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_CENTER))
        assertTrue(activated)
    }

    @Test fun twoPaneRailRetainsEverySubControlAndItsActions() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val root = activity.layoutInflater.inflate(R.layout.view_unified_menu, null)
        activity.setContentView(root)
        var chosen = ""
        var adjusted = 0
        val controller = UnifiedMenuController(activity, root,
            root.findViewById(R.id.unified_col1), root.findViewById(R.id.unified_col2),
            root.findViewById(R.id.unified_col3), root.findViewById(R.id.unified_col2_header),
            root.findViewById(R.id.unified_col3_header), root.findViewById(R.id.unified_preview),
            object : UnifiedMenuController.Callbacks {
                override fun buildModel(sectionIndex: Int, col2Index: Int) = UnifiedMenuController.Model(
                    listOf(UnifiedMenuController.Row("Audio"), UnifiedMenuController.Row("Subtitles")),
                    "Detected title", listOf(UnifiedMenuController.Row("First"), UnifiedMenuController.Row("Second")),
                    "Options", listOf(
                        UnifiedMenuController.Row("Apply", onOk = { chosen = "$sectionIndex:$col2Index" }),
                        UnifiedMenuController.Row("Adjust", adjustable = true, onAdjust = { adjusted += it })
                    ))
                override fun onSearchSubmit(query: String) {}
                override fun searchInitialQuery() = ""
                override fun stylePreview(tv: TextView) {}
                override fun onHidden() {}
            }, listOf("audio", "subs"))
        fun key(code: Int) { controller.dispatchKey(KeyEvent(KeyEvent.ACTION_DOWN, code)) }
        controller.show("audio")
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("0:0", chosen)
        key(KeyEvent.KEYCODE_BACK) // Values -> rail, not dismissed.
        assertTrue(controller.isVisible)
        key(KeyEvent.KEYCODE_DPAD_DOWN)
        key(KeyEvent.KEYCODE_DPAD_DOWN) // Cross section boundary.
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        key(KeyEvent.KEYCODE_DPAD_CENTER)
        assertEquals("1:0", chosen)
        key(KeyEvent.KEYCODE_DPAD_DOWN)
        key(KeyEvent.KEYCODE_DPAD_RIGHT)
        assertEquals(1, adjusted)
        key(KeyEvent.KEYCODE_BACK)
        key(KeyEvent.KEYCODE_BACK)
        assertFalse(controller.isVisible)
    }
}
