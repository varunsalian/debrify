package com.debrify.app.tv

import android.graphics.drawable.ColorDrawable
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.bumptech.glide.request.target.DrawableImageViewTarget
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistGlideCharacterizationTest : TvPhase13OriginalTest() {
    private fun art(target: ImageView?,value: String?) = call("loadGuideArt",arrayOf(ImageView::class.java,stringType),target,value)
    @Test fun guideArtworkRequestKeepsActivityLifecycleAndCenterCrop() {
        val image=ImageView(activity);art(image,"file:///phase13-missing.jpg")
        val request=DrawableImageViewTarget(image).request
        assertNotNull("Glide attaches the original artwork request",request)
        assertEquals("file:///phase13-missing.jpg",ReflectionHelpers.getField<Any>(request,"model"))
        val options=ReflectionHelpers.getField<com.bumptech.glide.request.BaseRequestOptions<*>>(request,"requestOptions")
        val transform=options.transformations[android.graphics.Bitmap::class.java]
        assertNotNull(transform);assertEquals(com.bumptech.glide.load.resource.bitmap.CenterCrop::class.java,transform!!.javaClass)
        assertTrue(TvPlayerOriginalAccess.glideTracks(Glide.with(activity),request!!))
        assertFalse(TvPlayerOriginalAccess.glideTracks(Glide.with(activity.applicationContext),request))
        art(image,null);assertNull(DrawableImageViewTarget(image).request);assertNull(image.drawable)
    }
    @Test fun nullBlankAndNullWordArtworkClearRequestAndDrawableWithoutTrimmingRealArt() {
        val image=ImageView(activity)
        for(value in listOf(null,""," ","null","NuLl")){image.setImageDrawable(ColorDrawable(7));art(image,value);assertNull("clear for $value",image.drawable);assertNull(DrawableImageViewTarget(image).request)}
        art(image," null ");assertNotNull("original nonblank value keeps whitespace",DrawableImageViewTarget(image).request)
        assertEquals(" null ",ReflectionHelpers.getField<Any>(DrawableImageViewTarget(image).request,"model"))
        art(image,null);art(null,"file:///phase13-missing.jpg")
    }
}
