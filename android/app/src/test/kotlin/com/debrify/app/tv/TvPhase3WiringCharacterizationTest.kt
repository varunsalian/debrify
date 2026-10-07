package com.debrify.app.tv

import android.content.Context
import android.view.View
import androidx.appcompat.widget.AppCompatButton
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPhase3WiringCharacterizationTest : TvPhase3OriginalTest() {
    private class ObservingButton(context: Context) : AppCompatButton(context) {
        var visibilityChanged: ((Int) -> Unit)? = null
        override fun setVisibility(value: Int) { visibilityChanged?.invoke(value); super.setVisibility(value) }
    }

    @Test fun originalLifecycleAndCrossFeatureWiring() {
        val root = bindViews(); val model = series()
        model.items[1] = model.items[1].copy(url = "file:///unused-fixture.mp4")
        val button = ObservingButton(activity).apply { visibility = View.VISIBLE }
        root.addView(button); set("skipSegmentButton", button)
        set("loadedSkipSegmentKey", "outgoing"); set("activeSkipSegment", TvSkipSegment(TvSkipSegmentType.OUTRO, 1, 2))
        invoke("showUpNextCard", 1)
        var observed = false
        button.visibilityChanged = { value ->
            if (value == View.GONE) {
                assertEquals("readiness reset before skip reset", false, field("hasEverBeenReady"))
                assertEquals("Up Next hidden before skip reset", false, field("upNextVisible"))
                assertNull(field("loadedSkipSegmentKey")); assertNull(field("activeSkipSegment"))
                observed = true
                // Exercise the existing startPlayback sleep gate after the reset;
                // this fixture never creates a player or opens a media source.
                set("sleepStopLatched", true)
            }
        }
        call("playItem", arrayOf(intType, boolType, boolType,
            TvPlayerOriginalAccess.type("AndroidTvTorrentPlayerActivity\$ShufflePlaybackAttempt")), 1, false, false, null)
        assertTrue("playItem reset reached the bound button", observed)
        assertEquals(1, field("currentIndex")); assertFalse(field("hasEverBeenReady") as Boolean)
        assertNull(field("loadingSkipSegmentKey")); assertSame(TvSkipSegments.EMPTY, field("skipSegments"))
    }
}
