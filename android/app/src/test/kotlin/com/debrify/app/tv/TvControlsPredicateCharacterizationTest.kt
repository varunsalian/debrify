package com.debrify.app.tv

import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsPredicateCharacterizationTest : TvPhase16OriginalTest() {
    @Test fun whitespaceSimpleTitleCountsAsNonemptyForTheClassicReveal() {
        tv("titleView").text = " "; v("titleContainer").alpha = 0.4f
        showDock()
        assertEquals(View.VISIBLE, v("titleContainer").visibility)
        assertEquals(1f, v("titleContainer").alpha, 0f)
        assertEquals(View.VISIBLE, v("titleView").visibility); assertEquals(View.GONE, v("titleOttContainer").visibility)
    }
    private fun badgeWithGate(visibility: Int) {
        @Suppress("UNCHECKED_CAST") val sources = field("stremioSources") as MutableList<StremioSource>
        sources.add(StremioSource(0, "Source", "hash", null, streamType = "torrent", sizeBytes = 1,
            seeders = 0, source = null, quality = "1080p"))
        v("startupGateView").visibility = visibility; v("stremioSourceBadge").visibility = View.GONE
        showDock()
        assertEquals("a non-visible initialized gate permits the badge", View.VISIBLE, v("stremioSourceBadge").visibility)
    }
    @Test fun initializedGoneStartupGateDoesNotSuppressTheSourceBadge() = badgeWithGate(View.GONE)
    @Test fun initializedInvisibleStartupGateDoesNotSuppressTheSourceBadge() = badgeWithGate(View.INVISIBLE)
}
