package com.debrify.app.tv

import android.app.Activity
import android.view.KeyEvent
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import androidx.savedstate.SavedStateRegistryController
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleCueCache
import com.debrify.app.util.SubtitleSettings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SubtitleSyncDismissTest {
    private fun picker(activity: Activity, root: FrameLayout, dismissed: Runnable): SubtitleLinePickerController {
        val url = "https://example.invalid/dismiss-test.srt"
        val field = SubtitleCueCache::class.java.getDeclaredField("cache").apply { isAccessible = true }
        @Suppress("UNCHECKED_CAST")
        val cache = field.get(null) as MutableMap<String, List<SubtitleCue>>
        synchronized(cache) { cache[url] = listOf(SubtitleCue(0, 1000, "Example")) }
        return SubtitleLinePickerController(activity, root, { 100L }, {}, dismissed).also { it.show(url) }
    }

    @Test fun backAndEscapeConsumeWholeGestureWithoutChangingOffset() {
        for (code in listOf(KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE)) {
            for (linePicker in listOf(true, false)) {
                val owner = Robolectric.buildActivity(Activity::class.java).setup()
                val activity = owner.get()
                val root = FrameLayout(activity)
                activity.setContentView(root)
                SubtitleSettings.setSyncOffsetMs(activity, 70100L)
                var dismissed = 0
                val onDismissed = Runnable { dismissed++ }
                val picker = if (linePicker) picker(activity, root, onDismissed) else null
                val slider = if (!linePicker) SubtitleSyncOverlayController(activity, root, Runnable {}, onDismissed).also { it.show() } else null
                fun key(event: KeyEvent) = picker?.dispatchKey(event) ?: slider!!.dispatchKey(event)
                fun visible() = picker?.isVisible ?: slider!!.isVisible
                assertTrue(key(KeyEvent(KeyEvent.ACTION_DOWN, code)))
                assertTrue(key(KeyEvent(0L, 0L, KeyEvent.ACTION_DOWN, code, 1)))
                assertTrue(visible())
                assertEquals(0, dismissed)
                assertTrue(key(KeyEvent(KeyEvent.ACTION_UP, code)))
                assertFalse(visible())
                assertEquals(1, dismissed)
                assertEquals(70100L, SubtitleSettings.getSyncOffsetMs(activity))
                owner.pause().stop().destroy()
            }
        }
    }

    @Test fun systemBackDismissesBothOverlaysInBothPlayersWithoutExiting() {
        for (type in listOf(AndroidTvTorrentPlayerActivity::class.java, TorboxTvPlayerActivity::class.java)) {
            for (linePicker in listOf(true, false)) {
                val activity = Robolectric.buildActivity(type).get() as ComponentActivity
                val state = ComponentActivity::class.java.declaredFields.first {
                    it.type == SavedStateRegistryController::class.java
                }.apply {
                    isAccessible = true
                }.get(activity) as SavedStateRegistryController
                state.performRestore(null)
                val lifecycle = activity.lifecycle as LifecycleRegistry
                lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
                lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_START)
                val root = FrameLayout(activity)
                var dismissed = 0
                val done = Runnable { dismissed++ }
                val overlay: Any = if (linePicker) picker(activity, root, done)
                    else SubtitleSyncOverlayController(activity, root, Runnable {}, done).also { it.show() }
                type.getDeclaredField(if (linePicker) "linePickerOverlay" else "syncOverlay").apply {
                    isAccessible = true
                    set(activity, overlay)
                }
                type.getDeclaredMethod("setupBackPressHandler").apply { isAccessible = true }.invoke(activity)
                activity.onBackPressedDispatcher.onBackPressed()
                assertEquals(1, dismissed)
                assertFalse(activity.isFinishing)
                lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
                lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
            }
        }
    }
}
