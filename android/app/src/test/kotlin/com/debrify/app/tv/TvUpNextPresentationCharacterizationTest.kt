package com.debrify.app.tv

import android.view.View
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
internal class TvUpNextPresentationCharacterizationTest : TvPhase3OriginalTest() {
    @Test fun showAndHidePinBothAlphaTranslationTargetsDurationsAndEndReset() {
        bindViews(); series(); set("player", PlayerProbe(position = 575_000).player); invoke("showUpNextCard", 1)
        val card = field("upNextCard") as View
        assertEquals(0f, card.alpha, 0f); assertEquals(40f, card.translationX, 0f)
        assertEquals(220L, card.animate().duration)
        advance(300); assertEquals(1f, card.alpha, 0.001f); assertEquals(0f, card.translationX, 0.001f)
        invoke("hideUpNextCard"); assertEquals(160L, card.animate().duration)
        val bundles = TvPlayerOriginalAccess.field(card.animate(), "mAnimatorMap") as Map<*, *>
        val values = bundles.values.flatMap { TvPlayerOriginalAccess.field(it!!, "mNameValuesHolder") as List<*> }
        fun target(property: Int): Float {
            val holder = values.single { TvPlayerOriginalAccess.field(it!!, "mNameConstant") == property }!!
            return TvPlayerOriginalAccess.field(holder, "mFromValue") as Float + (TvPlayerOriginalAccess.field(holder, "mDeltaValue") as Float)
        }
        assertEquals(0f, target(0x0800), 0f); assertEquals(40f, target(0x0001), 0f)
        advance(200); assertEquals(0f, card.alpha, 0.001f)
        assertEquals(View.GONE, card.visibility); assertEquals(0f, card.translationX, 0f)
    }
    @Test fun unbadgedTitleAndCountdownUseExactVisibleStrings() {
        bindViews(); val model = series(); model.items[1] = model.items[1].copy(season = null, episode = null)
        set("player", PlayerProbe(position = 575_001).player); invoke("showUpNextCard", 1); idle()
        assertEquals("Second", (field("upNextTitle") as TextView).text.toString())
        assertEquals("Starting in 25s", (field("upNextCountdown") as TextView).text.toString())
    }
}
