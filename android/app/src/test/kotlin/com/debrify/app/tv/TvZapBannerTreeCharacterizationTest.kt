package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvZapBannerTreeCharacterizationTest : TvPhase6OriginalTest() {
    private fun commonTree(style: String): android.widget.FrameLayout {
        setup(style); val tree = build()
        assertSame(activity.findViewById<ViewGroup>(android.R.id.content), tree.parent)
        assertEquals(View.GONE, tree.visibility); assertEquals(dp(8).toFloat(), tree.elevation, 0f)
        assertEquals(dp(250), frame(tree).height); assertEquals(Gravity.BOTTOM, frame(tree).gravity)
        assertEquals(1000, progress().max)
        val rail = view("iptvZapBannerRail") as LinearLayout
        assertEquals(4, rail.childCount); assertSame(view("iptvZapBannerHintChannel"), rail.getChildAt(0))
        assertSame(view("iptvZapBannerHintJump"), rail.getChildAt(3))
        assertEquals(listOf("◀", "▶", "Channel", "▲", "Guide", "HOLD ▲", "Channel number"),
            all(rail).filterIsInstance<TextView>().map { it.text.toString() })
        val cap = all(rail).filterIsInstance<TextView>().first()
        assertEquals(10f, cap.textSize / activity.resources.displayMetrics.scaledDensity, 0.001f)
        assertEquals(dp(3).toFloat(), (cap.background as GradientDrawable).cornerRadius, 0f)
        assertEquals(0.1f, (view("iptvZapBannerHintJump") as LinearLayout).getChildAt(1).let { (it as TextView).letterSpacing }, 0f)
        val live = all(tree).filterIsInstance<TextView>().single { it.text.contains("LIVE") }
        assertEquals(View.VISIBLE, live.visibility)
        assertEquals(if (style == "classic") Color.parseColor("#FF6470") else GuideTokens.of(GuideStyle.fromPref(style))!!.live,
            live.currentTextColor)
        if (style != "classic") {
            assertEquals("● REC", text("iptvZapStyledRec").text.toString())
            assertEquals(GuideTokens.of(GuideStyle.fromPref(style))!!.rec, text("iptvZapStyledRec").currentTextColor)
        }
        assertSame(tree, build())
        // Replace the launch snapshot as well as the live preference. This pins
        // both retained lazies and the existing-tree-before-token lookup contract.
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter.iptv_player_guide_style", if (style == "classic") "glass" else "classic").commit()
        set("playerPreferences", com.debrify.app.profiles.NativePlayerPreferences.fromIntent(activity, activity.intent))
        assertSame("session tree stays cached", tree, build())
        assertEquals(GuideStyle.fromPref(style), TvPlayerOriginalAccess.get(activity, "guideStyle"))
        return tree
    }

    @Test fun classicTreePinsHierarchyTypographyScrimAndCachedSessionStyle() {
        val tree = commonTree("classic")
        assertEquals(4, tree.childCount); assertSame(view("iptvZapBannerBody"), tree.getChildAt(1))
        assertSame(view("iptvZapBannerRail"), tree.getChildAt(2)); assertSame(progress(), tree.getChildAt(3))
        assertArrayEquals(intArrayOf(Color.argb(0, 4, 6, 12), Color.argb(184, 4, 6, 12), Color.argb(240, 4, 6, 12)),
            (tree.getChildAt(0).background as GradientDrawable).colors)
        assertEquals(31f, text("iptvZapBannerName").textSize / activity.resources.displayMetrics.scaledDensity, 0.001f)
        assertEquals(Typeface.BOLD, text("iptvZapBannerName").typeface.style)
        assertEquals(Color.parseColor("#00E5FF"), text("iptvZapBannerNumber").currentTextColor)
        assertEquals(Color.parseColor("#00E5FF"), progress().progressTintList!!.defaultColor)
        assertEquals(dp(4), progress().layoutParams.height)
        assertEquals("● LIVE", all(tree).filterIsInstance<TextView>().single { it.text.contains("LIVE") }.text.toString())
        assertFalse(all(tree).filterIsInstance<TextView>().any { it.text.contains("REC") })
    }

    @Test fun glassTreePinsIslandSurfaceLogoHierarchyAndCachedSessionStyle() {
        val tree = commonTree("glass"); val card = view("iptvZapStyledCard") as LinearLayout
        assertEquals(3, tree.childCount); assertSame(card, tree.getChildAt(1))
        assertSame(view("iptvZapBannerRail"), tree.getChildAt(2))
        assertEquals(2, card.childCount); assertSame(progress(), card.getChildAt(1))
        assertEquals(dp(620), frame(card).width); assertEquals(dp(28), frame(card).leftMargin)
        val surface = card.background as GradientDrawable
        assertEquals(dp(22).toFloat(), surface.cornerRadius, 0f); assertEquals(GuideTokens.GLASS.panel, surface.color!!.defaultColor)
        assertTrue(card.clipToOutline); assertNotNull(view("iptvZapBannerLogo").parent)
        assertEquals(22f, text("iptvZapBannerName").textSize / activity.resources.displayMetrics.scaledDensity, 0.001f)
        assertEquals(GuideTokens.GLASS.fgMid, text("iptvZapBannerNow").currentTextColor)
        assertEquals(dp(3), progress().layoutParams.height)
        assertEquals("● REC", text("iptvZapStyledRec").text.toString()); assertEquals(View.GONE, view("iptvZapStyledRec").visibility)
    }

    @Test fun editionTreePinsHeadlineBylineRuleAndCachedSessionStyle() {
        val tree = commonTree("edition"); val column = view("iptvZapBannerBody") as LinearLayout
        assertEquals(4, tree.childCount); assertSame(column, tree.getChildAt(1))
        assertSame(progress(), tree.getChildAt(2)); assertSame(view("iptvZapBannerRail"), tree.getChildAt(3))
        assertEquals(5, column.childCount); assertSame(view("iptvZapStyledRule"), column.getChildAt(0))
        assertSame(text("iptvZapBannerNow"), column.getChildAt(2))
        assertEquals(26f, text("iptvZapBannerNow").textSize / activity.resources.displayMetrics.scaledDensity, 0.001f)
        assertEquals(12.5f, text("iptvZapBannerName").textSize / activity.resources.displayMetrics.scaledDensity, 0.001f)
        assertEquals(Typeface.ITALIC, org.robolectric.Shadows.shadowOf(text("iptvZapBannerNumber").typeface).fontDescription.style)
        assertEquals("· LIVE", text("iptvZapStyledLive").text.toString())
        assertEquals(dp(2), progress().layoutParams.height); assertEquals(GuideTokens.EDITION.fg, progress().progressTintList!!.defaultColor)
        assertNull(view("iptvZapBannerLogo").parent)
    }

    @Test fun consoleTreePinsInstrumentMeterRuleAndCachedSessionStyle() {
        val tree = commonTree("console"); val column = view("iptvZapBannerBody") as LinearLayout
        assertEquals(3, tree.childCount); assertEquals(2, column.childCount)
        assertSame(view("iptvZapStyledMeterRow"), column.getChildAt(1))
        val meter = view("iptvZapStyledMeterRow") as LinearLayout
        assertEquals(2, meter.childCount); assertSame(progress(), meter.getChildAt(0)); assertSame(view("iptvZapStyledEnd"), meter.getChildAt(1))
        assertEquals(dp(5), progress().layoutParams.height); assertEquals(GuideTokens.CONSOLE.accent, progress().progressTintList!!.defaultColor)
        assertEquals(19f, text("iptvZapBannerName").textSize / activity.resources.displayMetrics.scaledDensity, 0.001f)
        assertEquals(0.2f, all(tree).filterIsInstance<TextView>().single { it.text == "NOW" }.letterSpacing, 0f)
        assertEquals(View.GONE, view("iptvZapStyledEnd").visibility); assertNull(view("iptvZapBannerLogo").parent)
    }

    @Test fun glassWidthClampsAtSmallAvailableWidthAndLargeScreenCap() {
        setup("glass", 100); build(); assertEquals(dp(220), frame(view("iptvZapStyledCard")).width)
    }

    @Test fun glassWidthUsesScreenMinusFiftySixBeforeCap() {
        setup("glass", dp(500)); build(); assertEquals(dp(500) - dp(56), frame(view("iptvZapStyledCard")).width)
    }

    @Test fun existingTreeReturnedBeforeAnyTokenAccess() {
        setup(); val preexisting = android.widget.FrameLayout(activity); set("iptvZapBanner", preexisting)
        assertSame(preexisting, build())
        val lazy = TvPlayerOriginalAccess.field(activity, "guideTokens\$delegate") as Lazy<*>
        assertFalse("returning an existing tree does not initialize tokens", lazy.isInitialized())
    }
}
