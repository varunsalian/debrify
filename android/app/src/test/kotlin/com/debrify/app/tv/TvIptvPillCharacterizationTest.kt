package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvPillCharacterizationTest : TvPhase17OriginalTest() {
    private fun pill()=reconnectPill()
    @Test fun pillIsCreatedOnceInDecorAndReusedAcrossHideAndReveal() {
        val decor=activity.findViewById<ViewGroup>(android.R.id.content);val count=decor.childCount
        invoke("showIptvReconnectPill","first");val first=pill();assertSame(activity,first.context);assertSame(decor,first.parent);assertEquals(count+1,decor.childCount)
        invoke("hideIptvReconnectPill");assertEquals(View.GONE,first.visibility);invoke("showIptvReconnectPill","second")
        assertSame(first,pill());assertEquals("second",first.text.toString());assertEquals(View.VISIBLE,first.visibility);assertEquals(count+1,decor.childCount)
    }
    @Test fun pillAppearancePinsWhiteBoldSixteenSpAndTranslucentBackground() {
        invoke("showIptvReconnectPill","text");val p=pill();assertEquals(Color.WHITE,p.currentTextColor);assertEquals(16f*activity.resources.displayMetrics.scaledDensity,p.textSize,0.01f)
        assertEquals(Typeface.DEFAULT_BOLD,p.typeface);assertNotNull("pill has a background",p.background)
        val bg=p.background as GradientDrawable;assertEquals(GradientDrawable.RECTANGLE,bg.shape);assertNotNull("pill background has its translucent fill",bg.color);assertEquals(Color.parseColor("#CC101418"),bg.color!!.defaultColor)
    }
    @Test fun pillSpacingAndGravityUseTheCurrentDensityWithIntegerTruncation() {
        activity.resources.displayMetrics.density=1.25f;invoke("showIptvReconnectPill","text");val p=pill()
        assertEquals(25,p.paddingLeft);assertEquals(12,p.paddingTop);assertEquals(25,p.paddingRight);assertEquals(12,p.paddingBottom)
        assertNotNull("pill is attached with layout parameters",p.layoutParams)
        val lp=p.layoutParams as FrameLayout.LayoutParams;assertEquals(70,lp.bottomMargin);assertEquals(Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,lp.gravity)
        assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT,lp.width);assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT,lp.height);assertEquals(27f,(p.background as GradientDrawable).cornerRadius)
    }
    @Test fun hideBeforeCreationIsAHarmlessNoOp() { invoke("hideIptvReconnectPill");assertNull(field("iptvReconnectPill")) }
    @Test fun dpConversionTruncatesRatherThanRoundsAndRetainsNegativeInput() {
        activity.resources.displayMetrics.density=1.25f;assertEquals(1,invoke("dpToPx",1));assertEquals(-1,invoke("dpToPx",-1));assertEquals(0,invoke("dpToPx",0))
    }
    @Test fun densityIsReadWhenPillIsCreatedButExistingPillIsNotRestyled() {
        activity.resources.displayMetrics.density=1f;invoke("showIptvReconnectPill","one");activity.resources.displayMetrics.density=2f
        invoke("showIptvReconnectPill","two");assertEquals(20,pill().paddingLeft);assertEquals("two",pill().text.toString())
    }
}
