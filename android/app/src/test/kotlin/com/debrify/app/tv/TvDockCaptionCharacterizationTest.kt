package com.debrify.app.tv

import android.graphics.LinearGradient
import android.graphics.drawable.PaintDrawable
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@org.robolectric.annotation.Config(shadows = [TvPhase15AnimatorShadow::class])
internal class TvDockCaptionCharacterizationTest : TvPhase15OriginalTest() {
    override val skin = TvControlsSkin.OTT
    private fun caption() = field("ottCaptionLabel") as TextView
    private fun update(view: View) = call("updateOttCaption", arrayOf(View::class.java), view)
    private fun clear(view: View) = call("clearOttCaption", arrayOf(View::class.java), view)
    private fun visibility(value: Int) {
        val listener = TvPlayerOriginalAccess.field(pv(), "controllerVisibilityListener") as? androidx.media3.ui.PlayerView.ControllerVisibilityListener
        assertNotNull("setupControls registers the actual Media3 visibility callback", listener)
        listener!!.onVisibilityChanged(value)
    }
    private fun refresh(view: View?) = call("refreshOttCaptionFor", arrayOf(View::class.java), view)
    @Test fun captionPrefersNonemptyButtonTextAndRecordsItsOwner() {
        val owner = TextView(activity).apply { text = "Text wins"; contentDescription = "Description" }
        update(owner)
        assertEquals("Text wins", caption().text.toString()); assertSame(owner, field("ottCaptionOwner"))
        assertEquals(120L, caption().animate().duration)
    }
    @Test fun emptyButtonTextFallsBackToContentDescription() {
        val owner = TextView(activity).apply { text = ""; contentDescription = "Fallback caption" }
        update(owner); assertEquals("Fallback caption", caption().text.toString()); assertSame(owner, field("ottCaptionOwner"))
    }
    @Test fun nonTextViewUsesItsContentDescription() {
        val owner = View(activity).apply { contentDescription = "Icon caption" }
        update(owner); assertEquals("Icon caption", caption().text.toString()); assertSame(owner, field("ottCaptionOwner"))
    }
    @Test fun missingLabelOrMissingTextDoesNotReplaceThePreviousOwner() {
        val first = View(activity).apply { contentDescription = "First" }; update(first)
        update(View(activity)); assertSame(first, field("ottCaptionOwner")); assertEquals("First", caption().text.toString())
        val label = caption(); set("ottCaptionLabel", null)
        update(View(activity).apply { contentDescription = "Second" })
        assertSame(first, field("ottCaptionOwner")); assertEquals("First", label.text.toString())
    }
    @Test fun clearingAnOutgoingNonOwnerCannotEraseTheIncomingCaption() {
        val first = View(activity).apply { contentDescription = "First" }
        val second = View(activity).apply { contentDescription = "Second" }
        update(first); update(second); clear(first)
        assertSame(second, field("ottCaptionOwner")); assertEquals("Second", caption().text.toString())
        clear(second); assertNull(field("ottCaptionOwner")); assertEquals(120L, caption().animate().duration)
    }
    @Test fun clearingTheOwnerStillClearsOwnershipWhenTheLabelIsAbsent() {
        val owner = View(activity).apply { contentDescription = "Caption" }; update(owner)
        set("ottCaptionLabel", null); clear(owner); assertNull(field("ottCaptionOwner"))
    }
    @Test fun refreshRejectsNullUnfocusedOrNotInstalledViewsIndependently() {
        val first = View(activity).apply { contentDescription = "First" }; update(first)
        refresh(null); assertSame(first, field("ottCaptionOwner"))
        val second = TextView(activity).apply { text = "Second" }
        refresh(second); assertSame(first, field("ottCaptionOwner")); assertEquals("First", caption().text.toString())
        pv().showController(); (field("controlsOverlay") as View).visibility = View.VISIBLE; layout()
        assertTrue(button("speedButton").requestFocus()); update(first); set("ottSkinInstalled", false)
        refresh(button("speedButton")); assertSame(first, field("ottCaptionOwner"))
    }
    @Test fun refreshAcceptsTheActuallyFocusedViewAndReadsItsLatestText() {
        pv().showController(); (field("controlsOverlay") as View).visibility = View.VISIBLE; layout()
        assertTrue(button("speedButton").requestFocus()); button("speedButton").text = "Latest speed"
        refresh(button("speedButton")); assertEquals("Latest speed", caption().text.toString())
        assertSame(button("speedButton"), field("ottCaptionOwner"))
    }
    @Test fun trackHeightUsesFocusedAndIdleDpAndRetainsTheSameLayoutParams() {
        val track = field("ottProgressTrackContainer") as View
        val params = track.layoutParams
        call("setOttTrackHeight", arrayOf(boolType), true)
        assertSame(params, track.layoutParams); assertEquals((6f * activity.resources.displayMetrics.density).toInt(), params.height)
        call("setOttTrackHeight", arrayOf(boolType), false)
        assertSame(params, track.layoutParams); assertEquals((3f * activity.resources.displayMetrics.density).toInt(), params.height)
    }
    @Test fun changedTrackHeightRequestsLayoutButAnUnchangedHeightDoesNot() {
        val track = object : View(activity) {
            var assignments = 0
            override fun setLayoutParams(params: android.view.ViewGroup.LayoutParams?) {
                assignments++; super.setLayoutParams(params)
            }
        }
        track.layoutParams = android.view.ViewGroup.LayoutParams(100, (3f * activity.resources.displayMetrics.density).toInt())
        track.assignments = 0; set("ottProgressTrackContainer", track)
        call("setOttTrackHeight", arrayOf(boolType), false); assertEquals(0, track.assignments)
        call("setOttTrackHeight", arrayOf(boolType), true); assertEquals(1, track.assignments)
        assertEquals((6f * activity.resources.displayMetrics.density).toInt(), track.layoutParams.height)
    }
    @Test fun trackHeightDoesNothingWhenItsViewIsAbsent() {
        val track = field("ottProgressTrackContainer") as View; val before = track.layoutParams.height
        set("ottProgressTrackContainer", null)
        try { call("setOttTrackHeight", arrayOf(boolType), true) }
        catch (failure: Exception) { fail("Missing track must return without throwing: $failure") }
        assertEquals(before, track.layoutParams.height); assertNull(field("ottProgressTrackContainer"))
    }
    @Test fun ottScrimKeepsAllFourExactColorsStopsAndGeometry() {
        val scrim = view(R.id.ott_content)!!.background
        assertTrue(scrim is PaintDrawable)
        scrim.setBounds(0, 0, 800, 500)
        val shader = (scrim as PaintDrawable).paint.shader
        assertTrue(shader is LinearGradient)
        val gradient = shader as LinearGradient
        assertArrayEquals(intArrayOf(0x00000000, 0x66000000, 0xD9000000.toInt(), 0xF2000000.toInt()), TvPlayerOriginalAccess.field(gradient, "mColors") as IntArray)
        assertArrayEquals(floatArrayOf(0f, 0.28f, 0.62f, 1f), TvPlayerOriginalAccess.field(gradient, "mPositions") as FloatArray, 0f)
        assertEquals(0f, TvPlayerOriginalAccess.field(gradient, "mX0")); assertEquals(0f, TvPlayerOriginalAccess.field(gradient, "mY0"))
        assertEquals(0f, TvPlayerOriginalAccess.field(gradient, "mX1")); assertEquals(500f, TvPlayerOriginalAccess.field(gradient, "mY1"))
    }
    @Test fun media3HideCallbackClearsVisibleControlsAndSnapsSubtitleLiftImmediately() {
        pv().showController(); set("controlsMenuVisible", true); layout()
        (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).layout(0, 0, 1440, 900)
        val lift = field("subtitleControlsLift") as SubtitleControlsLiftController
        lift.liftAbove(150, animate = false)
        assertTrue((field("subtitleOverlay") as androidx.media3.ui.SubtitleView).translationY < 0f)
        visibility(View.GONE)
        assertEquals(false, field("controlsMenuVisible")); assertEquals(0f, (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).translationY, 0f)
        assertEquals(0, TvPlayerOriginalAccess.field(lift, "controlsClearanceHeightPx"))
    }
    @Test fun media3HideWhileControlsAreAlreadyHiddenDoesNotResetAnotherLift() {
        pv().showController(); set("controlsMenuVisible", false); layout()
        (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).layout(0, 0, 1440, 900)
        val lift = field("subtitleControlsLift") as SubtitleControlsLiftController
        lift.liftAbove(150, animate = false); val before = (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).translationY
        assertTrue(before < 0); visibility(View.GONE)
        assertEquals(before, (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).translationY, 0f)
        assertEquals(150, TvPlayerOriginalAccess.field(lift, "controlsClearanceHeightPx"))
    }
    @Test fun media3VisibleCallbackDoesNotHideControlsOrRestoreTheirLift() {
        pv().hideController(); set("controlsMenuVisible", true); layout()
        (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).layout(0, 0, 1440, 900)
        val lift = field("subtitleControlsLift") as SubtitleControlsLiftController
        lift.liftAbove(150, animate = false); val before = (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).translationY
        assertTrue(before < 0); visibility(View.VISIBLE)
        assertEquals(true, field("controlsMenuVisible")); assertEquals(before, (field("subtitleOverlay") as androidx.media3.ui.SubtitleView).translationY, 0f)
    }
    @Test fun trackHeightReturnsWithoutRequestingLayoutWhenItsSpecIsAbsent() {
        val track = field("ottProgressTrackContainer") as View; val before = track.layoutParams.height
        TvPlayerOriginalAccess.set(activity, "dockSkinSpec\$delegate", lazyOf<Any?>(null))
        try { call("setOttTrackHeight", arrayOf(boolType), true) }
        catch (failure: Exception) { fail("Missing spec must return without throwing: $failure") }
        assertEquals(before, track.layoutParams.height)
    }
    private fun animateCaption() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(16))
        pv().showController(); (field("controlsOverlay") as View).visibility = View.VISIBLE; layout()
    }
    @Test fun updatingCaptionCancelsOtherMotionAlreadyRunningOnTheLabel() {
        animateCaption(); val label = caption(); var ended = false
        label.animate().translationY(80f).setDuration(800).withEndAction { ended = true }.start()
        advance(32); val before = label.translationY
        TvPhase15AnimatorShadow.cancelled.clear()
        update(button("audioButton")); assertEquals(listOf(label.animate()), TvPhase15AnimatorShadow.cancelled)
        advance(900)
        assertEquals(before, label.translationY, 0.001f); assertTrue("pending end action is carried into the new alpha animator", ended)
    }
    @Test fun clearingCaptionCancelsOtherMotionAlreadyRunningOnTheLabel() {
        animateCaption(); val owner = button("audioButton"); update(owner); advance(250)
        val label = caption(); var ended = false
        label.animate().translationY(80f).setDuration(800).withEndAction { ended = true }.start()
        advance(32); val before = label.translationY
        TvPhase15AnimatorShadow.cancelled.clear()
        clear(owner); assertEquals(listOf(label.animate()), TvPhase15AnimatorShadow.cancelled)
        assertEquals(120L, label.animate().duration)
        advance(900)
        assertEquals(0f, label.alpha, 0.001f)
        assertEquals(before, label.translationY, 0.001f); assertTrue("pending end action is carried into the new alpha animator", ended)
    }
}
