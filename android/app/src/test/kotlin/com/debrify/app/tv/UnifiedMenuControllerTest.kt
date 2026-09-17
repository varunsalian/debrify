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
