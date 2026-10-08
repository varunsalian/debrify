package com.debrify.app.tv

import android.view.View
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvZapBannerPagingCharacterizationTest : TvPhase6OriginalTest() {
    private fun pagingTransitions(style: String) {
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.US)
            setup(style)
            val e = entry(group = null)
            channels(e)
            show(e, true)
            set("iptvZapCategoryTotal", 2000)
            position(e)
            assertEquals("inactive paging ignores stale category total", "·  1 of 2", text("iptvZapBannerMeta").text.toString())

            set("iptvZapPagingActive", true)
            position(e)
            assertEquals("·  1 of 2,000", text("iptvZapBannerMeta").text.toString())
            for (total in listOf(0, -1)) {
                set("iptvZapCategoryTotal", total)
                position(e)
                assertEquals("nonpositive paged total falls back to loaded window", "·  1 of 2", text("iptvZapBannerMeta").text.toString())
            }

            channels(e, 1)
            set("iptvZapCategoryTotal", 2000)
            set("iptvZapPagingActive", false)
            position(e)
            assertEquals("·  1 of 1", text("iptvZapBannerMeta").text.toString())
            assertEquals(View.GONE, view("iptvZapBannerHintChannel").visibility)
            assertEquals(View.GONE, view("iptvZapBannerHintJump").visibility)
            set("iptvZapPagingActive", true)
            position(e)
            assertEquals("paging alone enables channel hint", View.VISIBLE, view("iptvZapBannerHintChannel").visibility)
            assertEquals(View.VISIBLE, view("iptvZapBannerHintJump").visibility)
            set("iptvSources", listOf(IptvSourceEntry("fav", "Saved", true, false, false)))
            set("iptvZapSourceId", "fav")
            position(e)
            assertEquals(View.VISIBLE, view("iptvZapBannerHintChannel").visibility)
            assertEquals(View.GONE, view("iptvZapBannerHintJump").visibility)

            set("iptvSources", emptyList<IptvSourceEntry>())
            set("iptvZapPagingActive", false)
            channels(e)
            position(e)
            assertEquals(View.VISIBLE, view("iptvZapBannerHintChannel").visibility)
            assertEquals(View.VISIBLE, view("iptvZapBannerHintJump").visibility)
            channels(e, 0)
            position(e)
            assertEquals("empty inactive window ignores stale total", "", text("iptvZapBannerMeta").text.toString())
            assertEquals(View.GONE, view("iptvZapBannerHintChannel").visibility)
            assertEquals(View.GONE, view("iptvZapBannerHintJump").visibility)
            set("iptvZapPagingActive", true)
            position(e)
            assertEquals("·  1 of 2,000", text("iptvZapBannerMeta").text.toString())
            set("iptvZapCategoryTotal", 0)
            position(e)
            assertEquals("", text("iptvZapBannerMeta").text.toString())
        } finally {
            Locale.setDefault(previous)
        }
    }

    @Test fun classicPagingTransitionsRejectStaleTotalsAndGateHints() = pagingTransitions("classic")
    @Test fun glassPagingTransitionsRejectStaleTotalsAndGateHints() = pagingTransitions("glass")
    @Test fun editionPagingTransitionsRejectStaleTotalsAndGateHints() = pagingTransitions("edition")
    @Test fun consolePagingTransitionsRejectStaleTotalsAndGateHints() = pagingTransitions("console")
}
