package com.debrify.app.tv

import android.graphics.drawable.ColorDrawable
import android.view.View
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.DrawableImageViewTarget
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvNextOverlayCharacterizationTest : TvPhase16OriginalTest() {
    @Test fun resolvingClearsOldTitleAndSubtextThenFadesInForTwoHundredTwentyMs() {
        tv("nextText").text = "old"; v("nextSubtext").visibility = View.INVISIBLE
        runOriginal("setResolvingState", true)
        assertEquals("", tv("nextText").text.toString()); assertEquals(View.GONE, v("nextSubtext").visibility)
        assertEquals(View.VISIBLE, v("nextOverlay").visibility); assertEquals(0f, v("nextOverlay").alpha, 0f)
        assertEquals(220L, v("nextOverlay").animate().duration); step(110)
        assertTrue(v("nextOverlay").alpha in 0.01f..0.99f); step(111); assertEquals(1f, v("nextOverlay").alpha, 0.001f)
    }
    @Test fun nextItemSetsTheExactTitleHidesTheSubtextAndCancelsThePriorFade() {
        runOriginal("fadeInNextOverlay"); step(50); v("nextSubtext").visibility = View.VISIBLE
        val rotation = beginRotation("nextOverlay")
        runOriginal("showNextOverlay", p2Item("Episode Seven"))
        assertEquals("Episode Seven", tv("nextText").text.toString()); assertEquals(View.GONE, v("nextSubtext").visibility)
        assertEquals(0f, v("nextOverlay").alpha, 0f); step(221); assertEquals(1f, v("nextOverlay").alpha, 0.001f); frozenRotation("nextOverlay", rotation)
    }
    @Test fun hideWaitsOneHundredSixtyMsThenRestoresAlphaForTheNextReveal() {
        runOriginal("fadeInNextOverlay"); step(221); val rotation = beginRotation("nextOverlay"); runOriginal("hideNextOverlay")
        assertEquals(160L, v("nextOverlay").animate().duration); step(159); assertEquals(View.VISIBLE, v("nextOverlay").visibility)
        step(2); frozenRotation("nextOverlay", rotation); assertEquals(View.GONE, v("nextOverlay").visibility); assertEquals(1f, v("nextOverlay").alpha, 0f)
        v("nextOverlay").alpha = 0.6f; runOriginal("hideNextOverlay"); step(200); assertEquals(0.6f, v("nextOverlay").alpha, 0f)
    }
    @Test fun resolvingFalseClearsTheExistingBackdropAndHidesBothViews() {
        val image = v("nextBackdrop") as ImageView; image.setImageDrawable(ColorDrawable(0xff123456.toInt())); image.visibility = View.VISIBLE
        runOriginal("fadeInNextOverlay"); step(221); runOriginal("setResolvingState", false); step(161)
        assertNull(image.drawable); assertEquals(View.GONE, image.visibility); assertEquals(View.GONE, v("nextOverlay").visibility)
    }
    @Test fun artworkRequestBelongsToTheActivityAndEmptyStringClearsItsRequest() {
        val image = v("nextBackdrop") as ImageView
        call("setNextOverlayBackdrop", arrayOf(String::class.java), "https://phase16.invalid/backdrop")
        val request = DrawableImageViewTarget(image).request; assertNotNull(request)
        assertEquals("https://phase16.invalid/backdrop", org.robolectric.util.ReflectionHelpers.getField<Any>(request, "model"))
        assertTrue(TvPlayerOriginalAccess.glideTracks(Glide.with(activity), request!!))
        assertFalse(TvPlayerOriginalAccess.glideTracks(Glide.with(activity.applicationContext), request))
        assertEquals(View.VISIBLE, image.visibility)
        call("setNextOverlayBackdrop", arrayOf(String::class.java), "")
        assertNull(DrawableImageViewTarget(image).request); assertNull(image.drawable); assertEquals(View.GONE, image.visibility)
    }
    @Test fun finishingActivityLeavesArtworkAndVisibilityUntouched() {
        val image = v("nextBackdrop") as ImageView; val original = ColorDrawable(); image.setImageDrawable(original); image.visibility = View.INVISIBLE
        activity.finish(); call("setNextOverlayBackdrop", arrayOf(String::class.java), null)
        assertSame(original, image.drawable); assertEquals(View.INVISIBLE, image.visibility)
    }
    @Test fun destroyedActivityLeavesArtworkAndVisibilityUntouchedWithoutCreatingARequest() {
        val image = v("nextBackdrop") as ImageView; val original = ColorDrawable(); image.setImageDrawable(original); image.visibility = View.INVISIBLE
        destroyNow(); assertTrue(activity.isDestroyed)
        val result = runCatching { call("setNextOverlayBackdrop", arrayOf(String::class.java), "https://phase16.invalid/late") }
        assertTrue(result.isSuccess)
        assertSame(original, image.drawable); assertEquals(View.INVISIBLE, image.visibility); assertNull(DrawableImageViewTarget(image).request)
    }
}
