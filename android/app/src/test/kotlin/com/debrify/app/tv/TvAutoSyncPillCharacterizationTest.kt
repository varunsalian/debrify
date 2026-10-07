package com.debrify.app.tv

import android.animation.ValueAnimator
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvAutoSyncPillCharacterizationTest : TvPhase4OriginalTest() {
    private fun show(glyph: String, color: Int, title: String, delay: Long? = null, uppercase: Boolean = true) =
        call("showSyncToast", arrayOf(stringType, intType, stringType, stringType, Long::class.javaObjectType, boolType),
            glyph, color, title, "diagnostic hint", delay, uppercase)
    private fun pill() = field("autoSyncPill") as LinearLayout
    private fun ring() = field("autoSyncPillRing") as AutoSyncRingView
    private fun animator() = TvPlayerOriginalAccess.field(ring(), "pulseAnimator") as ValueAnimator

    @Test fun busyOkAndFailFacesKeepColorsLabelsPulseAndGoneSemantics() {
        setup(); show("●", AutoSyncColors.BUSY, "checking")
        assertEquals("CHECKING", label()); assertEquals(View.VISIBLE, ring().visibility)
        assertTrue(animator().isStarted); assertEquals(AutoSyncColors.BUSY, ring().arcColor)
        assertEquals(0xEBFFFFFF.toInt(), (field("autoSyncPillLabel") as TextView).currentTextColor)
        for ((glyph, color) in listOf("✓" to AutoSyncColors.OK, "✕" to AutoSyncColors.FAIL)) {
            show(glyph, color, "result"); assertEquals("$glyph  RESULT", label())
            assertEquals(View.GONE, ring().visibility); assertFalse(animator().isStarted)
            assertEquals(color, ring().arcColor); assertEquals(color, (field("autoSyncPillLabel") as TextView).currentTextColor)
            assertEquals(false, field("autoSyncPillWindowActive"))
        }
    }
    @Test fun announceIsNaturalCaseForFiveSecondsThenQuietAndDoesNotClobberManualRun() {
        setup(); invoke("openAutoSyncPillWindow")
        assertEquals("Trying to auto-sync subtitles — this may take a minute, keep watching", label())
        assertEquals(0.01f, (field("autoSyncPillLabel") as TextView).letterSpacing, 0f)
        advance(4999); assertEquals(true, field("autoSyncPillAnnounceShowing"))
        advance(1); assertEquals(false, field("autoSyncPillAnnounceShowing")); advance(300)
        assertEquals(View.GONE, pill().visibility); assertEquals(true, field("autoSyncPillWindowActive"))
        invoke("openAutoSyncPillWindow"); advance(1000); show("●", AutoSyncColors.BUSY, "Syncing subtitles…")
        advance(4300); assertEquals(View.VISIBLE, pill().visibility); assertEquals("SYNCING SUBTITLES…", label())
    }
    @Test fun revealAndHideKeepAlphaTranslationDurationsAndWindowOwnership() {
        setup(); show("●", AutoSyncColors.BUSY, "work")
        val density = activity.resources.displayMetrics.density
        assertEquals(0f, pill().alpha, 0f); assertEquals((8 * density).toInt().toFloat(), pill().translationY, 0f)
        assertEquals(220L, pill().animate().duration); advance(300)
        assertEquals(1f, pill().alpha, 0.001f); assertEquals(0f, pill().translationY, 0.001f)
        set("autoSyncPillWindowActive", true); invoke("hideAutoSyncPillView")
        assertEquals(240L, pill().animate().duration); advance(300)
        assertEquals(View.GONE, pill().visibility); assertEquals(0f, pill().alpha, 0.001f)
        assertEquals((6 * density).toInt().toFloat(), pill().translationY, 0.001f)
        assertEquals(true, field("autoSyncPillWindowActive")); assertFalse(animator().isStarted)
    }
    @Test fun resultHideDeadlineIsReplacedAndNoDeadlineKeepsBusyVisible() {
        setup(); show("✓", AutoSyncColors.OK, "first", 1000); advance(500)
        show("✕", AutoSyncColors.FAIL, "second", 2000); advance(1499)
        assertEquals(View.VISIBLE, pill().visibility); assertEquals("✕  SECOND", label())
        advance(501); assertEquals(240L, pill().animate().duration); advance(300)
        assertEquals(View.GONE, pill().visibility)
        show("●", AutoSyncColors.BUSY, "work", null); assertTrue(animator().isStarted)
        assertEquals(ValueAnimator.INFINITE, (org.robolectric.Shadows.shadowOf(animator()) as org.robolectric.shadows.ShadowValueAnimator).actualRepeatCount)
        advance(10_000); assertEquals(View.VISIBLE, pill().visibility); assertEquals("WORK", label())
    }
    @Test fun toastDefaultDispatcherKeepsNullHintAndUppercaseTrue() {
        setup()
        defaultCall("showSyncToast", arrayOf(stringType, intType, stringType, stringType, Long::class.javaObjectType, boolType),
            8 or 32, "✓", AutoSyncColors.OK, "default result", "unused", null, false)
        assertEquals("✓  DEFAULT RESULT", label()); assertEquals(View.GONE, ring().visibility)
        assertFalse(org.robolectric.shadows.ShadowLog.getLogsForTag("AutoSync").any { it.msg.contains("unused") })
        assertEquals(0.08f, (field("autoSyncPillLabel") as TextView).letterSpacing, 0f)
    }
}
