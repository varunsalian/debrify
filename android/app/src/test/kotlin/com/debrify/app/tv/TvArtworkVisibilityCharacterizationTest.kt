package com.debrify.app.tv

import android.graphics.drawable.ColorDrawable
import android.view.View
import android.widget.ImageView
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.request.target.DrawableImageViewTarget
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvArtworkVisibilityCharacterizationTest : TvPlayerAdapterHarness() {
    @Test fun episodeArtworkLoadingFailureAndSuccessPinEveryVisibilityAssignment() {
        val adapter = Original.playlist(listOf(item().copy(artwork = "test://unresolved")))
        val row = holder(adapter, 1)
        val image = view(row, R.id.android_tv_playlist_item_poster) as ImageView
        try {
            val listener = Original.artworkListener(image)
            visible(row, R.id.fallback_container, false)
            visible(row, R.id.shimmer_overlay, true)
            visible(row, R.id.android_tv_playlist_item_poster, true)
            assertNull(image.drawable)
            assertFalse(listener.onLoadFailed(null, "test://unresolved", DrawableImageViewTarget(image), true))
            visible(row, R.id.shimmer_overlay, false)
            visible(row, R.id.android_tv_playlist_item_poster, false)
            visible(row, R.id.fallback_container, true)
            visible(row, R.id.android_tv_playlist_item_fallback, false)
            assertFalse(listener.onResourceReady(ColorDrawable(), "test://unresolved", DrawableImageViewTarget(image), DataSource.LOCAL, true))
            visible(row, R.id.shimmer_overlay, false)
            visible(row, R.id.android_tv_playlist_item_poster, true)
            visible(row, R.id.fallback_container, false)
        } finally { Glide.with(image.context).clear(image) }
    }

    @Test fun movieArtworkFailureAndSuccessUseGoneForTheReplacedView() {
        val adapter = Original.movies(listOf(item().copy(artwork = "test://unresolved")), Original.groups("MAIN" to listOf(0)))
        val row = holder(adapter)
        val image = view(row, R.id.android_tv_playlist_item_poster) as ImageView
        try {
            val listener = Original.artworkListener(image)
            assertFalse(listener.onLoadFailed(null, "test://unresolved", DrawableImageViewTarget(image), true))
            visible(row, R.id.android_tv_playlist_item_poster, false)
            visible(row, R.id.android_tv_playlist_item_fallback, true)
            assertFalse(listener.onResourceReady(ColorDrawable(), "test://unresolved", DrawableImageViewTarget(image), DataSource.LOCAL, true))
            visible(row, R.id.android_tv_playlist_item_poster, true)
            visible(row, R.id.android_tv_playlist_item_fallback, false)
        } finally { Glide.with(image.context).clear(image) }
    }

    @Test fun channelLogoStartFailureAndSuccessKeepTheOriginalListenerConsumption() {
        val entry = Original.channel()
        Original.set(entry, "logoUrl", "test://unresolved")
        checkLogo(Original.channels(mutableListOf(entry)), "logo", "letter")
    }

    @Test fun stremioPosterStartFailureAndSuccessKeepTheOriginalListenerConsumption() {
        val channel = Original.tvChannel()
        Original.set(channel, "nowPlayingPoster", "test://unresolved")
        checkLogo(Original.tvGuide(mutableListOf(channel)), "poster", "posterLetter")
    }

    private fun checkLogo(adapter: RecyclerView.Adapter<RecyclerView.ViewHolder>, imageField: String, letterField: String) {
        val row = holder(adapter)
        val image = Original.field(row, imageField) as ImageView
        val letter = Original.field(row, letterField) as View
        try {
            val listener = Original.artworkListener(image)
            assertEquals(View.VISIBLE, image.visibility)
            assertEquals(View.GONE, letter.visibility)
            assertFalse(listener.onResourceReady(ColorDrawable(), "test://unresolved", DrawableImageViewTarget(image), DataSource.LOCAL, true))
            assertEquals(View.VISIBLE, image.visibility)
            assertEquals(View.GONE, letter.visibility)
            assertTrue(listener.onLoadFailed(null, "test://unresolved", DrawableImageViewTarget(image), true))
            assertEquals(View.GONE, image.visibility)
            assertEquals(View.VISIBLE, letter.visibility)
        } finally { Glide.with(image.context).clear(image) }
    }

    private fun visible(row: RecyclerView.ViewHolder, id: Int, yes: Boolean) {
        assertEquals("view=$id", if (yes) View.VISIBLE else View.GONE, view(row, id).visibility)
    }
}
