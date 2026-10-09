package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

/** View callback observation preserves otherwise overwritten intermediate publications. */
@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvTicketPublicationCharacterizationTest : TvPhase16OriginalTest() {
    override val skin = TvControlsSkin.TICKET
    private class PublicationView(context: android.content.Context) : TextView(context) {
        val visibilityWrites = mutableListOf<Int>()
        override fun setVisibility(value: Int) { super.setVisibility(value); visibilityWrites.add(value) }
    }
    private fun observe(): PublicationView {
        val old = v("ottIdentityOverline"); val parent = old.parent as android.view.ViewGroup
        val result = PublicationView(activity); result.layoutParams = old.layoutParams; result.id = old.id
        parent.removeView(old); parent.addView(result); set("ottIdentityOverline", result); return result
    }
    private fun item(show: String?): PlaybackItem {
        val item = p2Item("Episode", season = 2, episode = 7).copy(sourceTitle = "Film.2160p.DV")
        set("payload", PlaybackPayload("release", null, "series", mutableListOf(item), 0, null)); set("ottShowName", show); return item
    }
    @Test fun presentShowPublishesVisibleBeforeExtrasPublishesVisibleAgain() {
        val view = observe(); runOriginal("updateTitle", item("Show"))
        assertEquals(listOf(View.VISIBLE, View.VISIBLE), view.visibilityWrites)
        assertEquals("Show · 4K · Dolby Vision", view.text.toString())
    }
    @Test fun absentShowPublishesGoneBeforeQualityMakesTheOverlineVisible() {
        val view = observe(); runOriginal("updateTitle", item(" "))
        assertEquals(listOf(View.GONE, View.VISIBLE), view.visibilityWrites)
        assertEquals("4K · Dolby Vision", view.text.toString())
    }
    @Test fun movieIdentityHidesSeriesOverlineBeforeQualityRevealsIt() {
        val view = observe(); val item = item(null); (field("payload") as PlaybackPayload).contentType = "movie"
        runOriginal("updateTitle", item)
        assertEquals(listOf(View.GONE, View.VISIBLE), view.visibilityWrites)
        assertEquals("4K · Dolby Vision", view.text.toString())
    }
}
