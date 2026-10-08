package com.debrify.app.tv

import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvZapBannerTimingCharacterizationTest : TvPhase6OriginalTest() {
    @Test fun floatingEntranceAndAutoHideHaveExactDurationsAndBoundary() {
        setup(); val e = entry(); channels(e); show(e)
        assertEquals(View.VISIBLE, banner().visibility); assertEquals(0f, banner().alpha, 0f)
        assertEquals(0f, banner().translationY, 0f); assertEquals(160L, banner().animate().duration)
        advance(200); assertEquals(1f, banner().alpha, 0.001f)
        advance(4299); assertNotNull(field("iptvZapBannerEntry")); assertTrue(hidePending())
        advance(1); assertNull("auto-hide fires at exactly 4500ms", field("iptvZapBannerEntry"))
        assertEquals(180L, banner().animate().duration); advance(220)
        assertEquals(View.GONE, banner().visibility); assertEquals(0f, banner().alpha, 0.001f)
    }

    @Test fun dockedEntranceRisesThirtyAndNeverAutoHides() {
        setup(); val e = entry(); channels(e); show(e, true)
        assertEquals(30f, banner().translationY, 0f); assertEquals(300L, banner().animate().duration)
        val easing = banner().animate().interpolator as DecelerateInterpolator
        assertEquals(DecelerateInterpolator(1.5f).getInterpolation(0.25f), easing.getInterpolation(0.25f), 0f)
        assertFalse(hidePending()); advance(400); assertEquals(0f, banner().translationY, 0.001f)
        advance(5000); assertEquals(View.VISIBLE, banner().visibility); assertSame(e, field("iptvZapBannerEntry"))
    }

    @Test fun defaultDockedArgumentReadsControlsAtEveryInvocation() {
        setup(); val e = entry(); channels(e); set("controlsMenuVisible", true); showDefault(e)
        assertEquals(true, field("iptvZapBannerDocked")); assertFalse(hidePending())
        set("controlsMenuVisible", false); showDefault(e)
        assertEquals(false, field("iptvZapBannerDocked")); assertTrue(hidePending())
    }

    @Test fun guideVisibilitySuppressesConstructionAndCallbacks() {
        setup(); set("iptvGuideVisible", true); show(entry())
        assertNull(field("iptvZapBanner")); assertFalse(tickPending()); assertFalse(hidePending())
    }

    @Test fun repeatedShowKeepsEntranceAndTickDeadlineButRearmsHide() {
        setup(); org.robolectric.shadows.ShadowChoreographer.setPaused(true); val e = entry(); channels(e); show(e); advance(800)
        banner().animate().duration = 777L; e.epgNowTitle = "tick title"; show(e)
        assertEquals(777L, banner().animate().duration)
        e.epgNowTitle = "at first deadline"; advance(199)
        assertEquals("tick title", text("iptvZapBannerNow").text.toString()); advance(1)
        assertEquals("at first deadline", text("iptvZapBannerNow").text.toString())
        advance(3500); assertNotNull("old hide deadline was cancelled", field("iptvZapBannerEntry"))
        advance(799); assertNotNull(field("iptvZapBannerEntry")); advance(1)
        assertNull(field("iptvZapBannerEntry"))
    }

    @Test fun visibleTicksRepaintAndRepostUntilExplicitHide() {
        setup("console"); val e = entry(); channels(e); show(e, true)
        e.epgNowTitle = "new title"; advance(999)
        assertEquals("Programme", text("iptvZapBannerNow").text.toString()); advance(1)
        assertEquals("new title", text("iptvZapBannerNow").text.toString()); assertTrue(tickPending())
        e.epgNowTitle = "second tick"; advance(1000)
        assertEquals("second tick", text("iptvZapBannerNow").text.toString())
        invoke("hideIptvZapBanner"); assertFalse(tickPending()); assertNull(field("iptvZapBannerEntry"))
        assertEquals(false, field("iptvZapBannerDocked")); assertEquals(180L, banner().animate().duration)
        advance(220); assertEquals(View.GONE, banner().visibility)
    }

    @Test fun invisibleBannerStopsTickChainWithoutRepainting() {
        setup(); val e = entry(); channels(e); show(e, true)
        banner().visibility = View.INVISIBLE; e.epgNowTitle = "must not paint"; advance(1000)
        assertEquals("Programme", text("iptvZapBannerNow").text.toString()); assertFalse(tickPending())
    }

    @Test fun explicitHideLeavesHideCallbackPostedAndCancelsOnlyItsTickToken() {
        setup(); val e = entry(); channels(e); show(e)
        val handler = field("progressHandler") as android.os.Handler
        var borrowed = false; handler.postDelayed({ borrowed = true }, 2000)
        invoke("hideIptvZapBanner")
        assertFalse(tickPending()); assertTrue("as-is pending hide callback remains", hidePending())
        advance(220); banner().animate().duration = 777L; advance(4280)
        assertTrue("borrowed work survives token cancellation", borrowed)
        assertEquals("pending callback fires again", 180L, banner().animate().duration)
    }

    @Test fun classicDockModeAndLayoutListenerTrackNewDockHeightOnlyOnce() {
        setup(); val e = entry(); channels(e); show(e, true)
        assertEquals(100, frame(banner()).bottomMargin); assertEquals(View.GONE, view("iptvZapBannerRail").visibility)
        assertEquals(dp(16), frame(view("iptvZapBannerBody")).bottomMargin)
        set("controlsMenuVisible", true); dock.layoutParams.height = 140; dock.layout(0, 0, 1000, 140); advance(250)
        assertEquals(140, frame(banner()).bottomMargin)
        assertEquals(-(140 + banner().height + dp(24)).toFloat(), subtitles.translationY, 0.001f)
        assertEquals(true, field("iptvDockLayoutListenerAttached")); show(e, true)
        val listeners = TvPlayerOriginalAccess.field(android.view.View::class.java.getDeclaredField("mListenerInfo").apply { isAccessible = true }.get(dock)!!, "mOnLayoutChangeListeners") as List<*>
        assertEquals("dock listener attaches once", 1, listeners.size)
        val bannerInfo = android.view.View::class.java.getDeclaredField("mListenerInfo").apply { isAccessible = true }.get(banner())!!
        val bannerListeners = TvPlayerOriginalAccess.field(bannerInfo, "mOnLayoutChangeListeners") as List<*>
        assertEquals("banner listener attaches once", 1, bannerListeners.size)
        val larger = banner().height + 50
        banner().layoutParams.height = larger
        banner().layout(0, 0, banner().width, larger); advance(250)
        assertEquals("banner-only layout refreshes subtitle clearance", -(140 + larger + dp(24)).toFloat(), subtitles.translationY, 0.001f)
        show(e, false); assertEquals(0, frame(banner()).bottomMargin)
        assertEquals(View.VISIBLE, view("iptvZapBannerRail").visibility); assertEquals(dp(58), frame(view("iptvZapBannerBody")).bottomMargin)
        invoke("hideIptvZapBanner"); assertEquals("original listener remains after hide", 1, listeners.size)
        assertEquals("banner listener also remains after hide", 1, bannerListeners.size)
    }

    @Test fun glassDockModeHandsSurfaceAndGeometryToDockThenRestoresIsland() {
        setup("glass"); val e = entry(); channels(e); show(e, true)
        val card = view("iptvZapStyledCard"); assertNull(card.background)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, frame(card).width)
        assertEquals(dp(20), frame(card).leftMargin); assertEquals(dp(20), frame(card).rightMargin)
        val meter = progress().layoutParams as android.widget.LinearLayout.LayoutParams
        assertEquals(0, meter.leftMargin); assertEquals(0, meter.rightMargin); assertEquals(dp(4), meter.bottomMargin)
        assertEquals(View.GONE, view("iptvZapStyledScrim").visibility)
        dock.layoutParams.height = 160; dock.layout(0, 0, 1000, 160); advance(250)
        assertEquals("styled dock listener dispatches through classic mode entry", 160, frame(banner()).bottomMargin)
        show(e, false); assertNotNull(card.background); assertEquals(dp(620), frame(card).width)
        assertEquals(dp(28), frame(card).leftMargin); assertEquals(0, frame(card).rightMargin)
        assertEquals(dp(20), meter.leftMargin); assertEquals(dp(16), meter.bottomMargin)
        assertEquals(View.VISIBLE, view("iptvZapStyledScrim").visibility)
    }

    @Test fun editionDockModeUsesInvisibleRuleAndGoneScrimThenRestores() {
        setup("edition"); val e = entry(); channels(e); show(e, true)
        assertEquals(View.INVISIBLE, view("iptvZapStyledRule").visibility)
        assertEquals(View.GONE, view("iptvZapStyledScrim").visibility)
        assertEquals(View.GONE, view("iptvZapBannerRail").visibility)
        show(e, false); assertEquals(View.VISIBLE, view("iptvZapStyledRule").visibility)
        assertEquals(View.VISIBLE, view("iptvZapStyledScrim").visibility)
    }

    @Test fun consoleDockModeKeepsAmberRuleWhileHidingScrimAndRail() {
        setup("console"); val e = entry(); channels(e); show(e, true)
        assertEquals(View.VISIBLE, view("iptvZapStyledRule").visibility)
        assertEquals(View.GONE, view("iptvZapStyledScrim").visibility); assertEquals(View.GONE, view("iptvZapBannerRail").visibility)
        assertEquals(100, frame(banner()).bottomMargin)
        assertEquals(dp(16), frame(view("iptvZapBannerBody")).bottomMargin)
    }
}
