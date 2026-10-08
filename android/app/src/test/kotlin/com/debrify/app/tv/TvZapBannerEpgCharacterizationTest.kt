package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.view.View
import org.junit.After
import org.junit.Before
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], instrumentedPackages = ["com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
    "com.debrify.app.tv.TvIptvZapBannerController", "com.debrify.app.tv.TvIptvZapBannerStyledRenderer"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvZapBannerEpgCharacterizationTest : TvPhase6OriginalTest() {
    private val previousZone = TimeZone.getDefault()
    @Before fun clockFormat() {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        android.provider.Settings.System.putString(activity.contentResolver, android.provider.Settings.System.TIME_12_24, "24")
    }
    @After fun restoreZone() { TimeZone.setDefault(previousZone) }

    private fun loaded(style: String) {
        setup(style); build(); val e = entry(); paint(e)
        assertEquals("Programme", text("iptvZapBannerNow").text.toString())
        assertEquals("00:14 – 00:24  ·  8 min left", text("iptvZapBannerTimes").text.toString())
        assertEquals(View.VISIBLE, view("iptvZapBannerTimes").visibility)
        assertEquals("Next  00:24  ·  Next programme", text("iptvZapBannerNext").text.toString())
        assertEquals(View.VISIBLE, view("iptvZapBannerNext").visibility); assertEquals(200, progress().progress)
        if (style != "classic") {
            assertEquals("00:24", text("iptvZapStyledEnd").text.toString()); assertEquals(View.VISIBLE, view("iptvZapStyledEnd").visibility)
        }
    }
    @Test fun classicPaintPinsNowNextTimesProgressAndBoldWhiteRestoration() {
        loaded("classic"); assertEquals(Color.WHITE, text("iptvZapBannerNow").currentTextColor)
        assertEquals(Typeface.BOLD, text("iptvZapBannerNow").typeface.style)
        val e = entry().also { it.epgNowTitle = null }; paint(e)
        assertEquals("No guide data", text("iptvZapBannerNow").text.toString())
        assertEquals(Color.argb(107, 255, 255, 255), text("iptvZapBannerNow").currentTextColor)
        assertEquals(Typeface.NORMAL, text("iptvZapBannerNow").typeface.style)
        e.epgLoading = true; paint(e); assertEquals("Loading guide…", text("iptvZapBannerNow").text.toString())
        assertEquals(View.GONE, view("iptvZapBannerTimes").visibility); assertEquals(View.GONE, view("iptvZapBannerNext").visibility)
        assertEquals(0, progress().progress)
    }
    @Test fun glassPaintChangesViewsWithItsOwnColorsAndMissingDataStates() {
        loaded("glass"); assertEquals(GuideTokens.GLASS.fgMid, text("iptvZapBannerNow").currentTextColor)
        val e = entry().also { it.epgNowTitle = null; it.epgLoading = true }; paint(e)
        assertEquals("Loading guide…", text("iptvZapBannerNow").text.toString())
        assertEquals(GuideTokens.GLASS.fgFaint, text("iptvZapBannerNow").currentTextColor)
        assertEquals(View.GONE, view("iptvZapStyledEnd").visibility); assertEquals(0, progress().progress)
        e.epgLoading = false; paint(e); assertEquals("No guide data", text("iptvZapBannerNow").text.toString())
    }
    @Test fun editionPaintPromotesChannelAndNamesMissingGuideInBylineThenRestores() {
        loaded("edition"); assertEquals("Cinema", text("iptvZapBannerName").text.toString())
        val e = entry().also { it.epgNowTitle = null; it.epgLoading = true }; paint(e)
        assertEquals("Cinema", text("iptvZapBannerNow").text.toString())
        assertEquals("Loading guide…", text("iptvZapBannerName").text.toString())
        assertEquals(GuideTokens.EDITION.fgFaint, text("iptvZapBannerName").currentTextColor)
        e.epgLoading = false; paint(e); assertEquals("No guide data", text("iptvZapBannerName").text.toString())
        e.epgNowTitle = "Programme"; paint(e)
        assertEquals("Cinema", text("iptvZapBannerName").text.toString())
        assertEquals(GuideTokens.EDITION.fgDim, text("iptvZapBannerName").currentTextColor)
    }
    @Test fun consolePaintUsesForegroundAndEndTimeAndHidesInvalidRuntime() {
        loaded("console"); assertEquals(GuideTokens.CONSOLE.fg, text("iptvZapBannerNow").currentTextColor)
        val e = entry().also { it.epgNowStopMs = it.epgNowStartMs }; paint(e)
        assertEquals(View.GONE, view("iptvZapBannerTimes").visibility)
        assertEquals(View.GONE, view("iptvZapStyledEnd").visibility); assertEquals(0, progress().progress)
    }
    @Test fun remainingTailRequiresStrictlyMoreThanOneMinuteAndProgressClamps() {
        setup(); build(); val e = entry()
        for ((remaining, tail) in listOf(60_000L to false, 60_001L to true)) {
            e.epgNowStartMs = now - 60_000; e.epgNowStopMs = now + remaining; paint(e)
            assertEquals("remaining=$remaining", tail, text("iptvZapBannerTimes").text.contains("1 min left"))
        }
        e.epgNowStartMs = now + 1000; e.epgNowStopMs = now + 2000; paint(e); assertEquals(0, progress().progress)
        e.epgNowStartMs = now - 2000; e.epgNowStopMs = now - 1000; paint(e); assertEquals(1000, progress().progress)
    }
    @Test fun styledRemainingTailHasTheSameStrictMinuteBoundary() {
        setup("console"); build(); val e = entry()
        e.epgNowStopMs = now + 60_000; paint(e); assertFalse(text("iptvZapBannerTimes").text.contains("left"))
        e.epgNowStopMs = now + 60_001; paint(e); assertTrue(text("iptvZapBannerTimes").text.contains("1 min left"))
    }
    @Test fun nextNeedsBothTitlesAndOptionalPositiveStartTime() {
        setup(); build(); val e = entry().also { it.epgNextStartMs = 0 }; paint(e)
        assertEquals("Next  Next programme", text("iptvZapBannerNext").text.toString())
        e.epgNextTitle = null; paint(e); assertEquals(View.GONE, view("iptvZapBannerNext").visibility)
        e.epgNextTitle = "Next programme"; e.epgNowTitle = null; paint(e)
        assertEquals(View.GONE, view("iptvZapBannerNext").visibility)
    }
    @Test fun styledNextNeedsBothTitlesAndOptionalPositiveStartTime() {
        setup("glass"); build(); val e = entry().also { it.epgNextStartMs = 0 }; paint(e)
        assertEquals("Next  Next programme", text("iptvZapBannerNext").text.toString())
        e.epgNextTitle = null; paint(e); assertEquals(View.GONE, view("iptvZapBannerNext").visibility)
        e.epgNextTitle = "Next programme"; e.epgNowTitle = null; paint(e)
        assertEquals(View.GONE, view("iptvZapBannerNext").visibility)
    }
}
