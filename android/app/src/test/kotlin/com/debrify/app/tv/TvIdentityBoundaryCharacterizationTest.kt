package com.debrify.app.tv

import android.view.View
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.LooperMode

@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIdentityBoundaryCharacterizationTest(override val skin: TvControlsSkin) : TvPhase16OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}") fun skins(): List<Array<Any>> =
            TvControlsSkin.entries.map { arrayOf<Any>(it) }
    }
    @Test fun titleUpdateHidesAPreviouslyVisibleOrInvisibleChannelBadge() {
        val item = p2Item("Movie")
        set("payload", PlaybackPayload("Movie", null, "movie", mutableListOf(item), 0, null))
        for (visibility in listOf(View.VISIBLE, View.INVISIBLE)) {
            v("channelBadge").visibility = visibility
            runOriginal("updateTitle", item)
            assertEquals("title update hides channel badge", View.GONE, v("channelBadge").visibility)
            assertEquals("Movie", tv("titleView").text.toString())
        }
    }
    @Test fun uninstalledDockUsesLegacyPlayAndPauseIconsEvenWithASelectedStyledSpec() {
        // A selected styled skin can remain uninstalled under the live-IPTV gate.
        assertEquals(skin != TvControlsSkin.CLASSIC, runOriginal("getDockSkinSpec") != null)
        set("ottSkinInstalled", false)
        probe.playing = false; runOriginal("updatePauseButtonLabel")
        assertEquals("Play", tv("pauseButton").text.toString())
        assertEquals(R.drawable.ic_play, Shadows.shadowOf(tv("pauseButton").compoundDrawables[0]).createdFromResId)
        probe.playing = true; runOriginal("updatePauseButtonLabel")
        assertEquals("Pause", tv("pauseButton").text.toString())
        assertEquals(R.drawable.ic_pause, Shadows.shadowOf(tv("pauseButton").compoundDrawables[0]).createdFromResId)
    }
}
