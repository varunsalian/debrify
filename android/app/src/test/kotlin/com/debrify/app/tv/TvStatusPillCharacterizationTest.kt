package com.debrify.app.tv

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStatusPillCharacterizationTest : TvPhase10OriginalTest() {
    @Test fun lazyTreeHasOriginalTypographyDrawablePaddingAndParentAndIsReused() {
        assertNull(field("statusPill")); invoke("ensureStatusPill")
        val p = pill(); val dp = activity.resources.displayMetrics.density
        assertEquals(13f, p.textSize / activity.resources.displayMetrics.scaledDensity, .001f)
        assertEquals(Color.WHITE, p.currentTextColor); assertEquals(View.GONE, p.visibility)
        assertEquals(android.graphics.Typeface.create("sans-serif-medium", 0), p.typeface)
        val bg = p.background as GradientDrawable
        assertEquals(0xD9101014.toInt(), bg.color!!.defaultColor)
        assertEquals(18 * dp, bg.cornerRadius, .001f)
        val state=org.robolectric.util.ReflectionHelpers.getField<Any>(bg,"mGradientState")
        assertEquals((dp).toInt(),org.robolectric.util.ReflectionHelpers.getField<Int>(state,"mStrokeWidth"))
        assertEquals(0x33FFFFFF,org.robolectric.util.ReflectionHelpers.getField<android.content.res.ColorStateList>(state,"mStrokeColors").defaultColor)
        assertEquals(listOf(16, 8, 16, 8).map { (it * dp).toInt() }, listOf(p.paddingLeft,p.paddingTop,p.paddingRight,p.paddingBottom))
        assertEquals(240 * dp, p.elevation, .001f)
        val lp = p.layoutParams as FrameLayout.LayoutParams
        assertEquals(-2,lp.width); assertEquals(-2,lp.height); assertEquals(Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL, lp.gravity)
        assertEquals((48 * dp).toInt(),lp.bottomMargin); assertSame(activity.findViewById<View>(android.R.id.content),p.parent)
        showPill("first"); showPill("second"); assertSame(p, pill()); assertEquals("second",p.text.toString())
    }
    @Test fun showStartsAtZeroAndFadesInFor180Milliseconds() {
        showPill(); val p=pill(); assertEquals(View.VISIBLE,p.visibility); assertEquals(0f,p.alpha,0f)
        assertEquals(180L,p.animate().duration); tick(250); assertEquals(1f,p.alpha,.001f)
    }
    @Test fun transientSchedulesExactly1400AndHideFadesFor220Milliseconds() {
        val start=SystemClock.uptimeMillis(); showPill("temporary",true)
        val hide=field("statusPillHideRunnable") as Runnable
        val message=queuedCallbacks(pillHandler()).single { it.callback === hide }
        assertEquals(start+1400,message.`when`)
        tick(1399); assertEquals(View.VISIBLE,pill().visibility); assertEquals(180L,pill().animate().duration)
        tick(1); assertEquals(220L,pill().animate().duration); tick(300); assertEquals(View.GONE,pill().visibility)
    }
    @Test fun reshowCancelsBorrowedHideAndKeepsTheSinglePillVisible() {
        showPill("old",true); tick(1000); showPill("new"); tick(1000)
        assertEquals("new",pill().text.toString()); assertEquals(View.VISIBLE,pill().visibility)
        assertTrue(queuedCallbacks(pillHandler()).none { it.callback === field("statusPillHideRunnable") })
    }
    @Test fun hideIsAbsentAndInvisibleNoOpAndUsesGoneAtEnd() {
        hidePill(); assertNull(field("statusPill")); invoke("ensureStatusPill"); val p=pill()
        p.visibility=View.INVISIBLE; p.alpha=.4f; hidePill(); tick(300)
        assertEquals(View.INVISIBLE,p.visibility); assertEquals(.4f,p.alpha,0f)
        showPill(); tick(250); hidePill(); tick(300); assertEquals(View.GONE,p.visibility)
    }
    @Test fun destructionClearsPendingHideOnTheBorrowedHandler() {
        showPill("pending",true); val h=pillHandler(); assertFalse(queuedCallbacks(h).isEmpty())
        lifecycle.pause().stop().destroy(); assertTrue(queuedCallbacks(h).isEmpty())
    }
    @Test fun subtitleSwitcherGateAndFetchUseTheSamePill() {
        showPill("switcher"); val p=pill()
        val subtitle=TvPlayerOriginalAccess.field(field("subtitleController")!!,"host")!!
        TvPlayerOriginalAccess.callTyped(subtitle,"showStatusPill",arrayOf(stringType),"subtitle")
        assertSame(p,pill()); assertEquals("subtitle",p.text.toString())
        begin(); assertSame(p,pill()); noChannel(); fetch(); assertSame(p,pill()); assertEquals("Couldn't fetch S02E05",p.text.toString())
    }
}
