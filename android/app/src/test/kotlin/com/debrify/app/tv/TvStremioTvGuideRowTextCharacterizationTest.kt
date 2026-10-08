package com.debrify.app.tv

import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.request.target.DrawableImageViewTarget
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStremioTvGuideRowTextCharacterizationTest : TvPhase7OriginalTest() {
    @Test fun rowRatingUsesUsDecimalAndOnePlaceWithYearAndNextFormatting() {
        init(json("0", "cinema"))
        channels()[0] = channels()[0].copy(number = 7, nowPlayingTitle = "Film", nowPlayingYear = "2024",
            nowPlayingRating = 8.46, nextUpTitle = "Next Film", nextUpYear = "2025")
        invoke("filterStremioTvChannels")
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.GERMANY)
            val row = adapter().onCreateViewHolder(list(), 0)
            adapter().onBindViewHolder(row, 0)
            fun text(id: Int) = row.itemView.findViewById<TextView>(id).text.toString()
            assertEquals("7", text(R.id.stremio_tv_guide_channel_number))
            assertEquals("row rating keeps US decimal and rounds to one place", "Film (2024) ★ 8.5", text(R.id.stremio_tv_guide_now_title))
            assertEquals("Next: Next Film (2025)", text(R.id.stremio_tv_guide_next_title))
        } finally { Locale.setDefault(previous) }
    }

    @Test fun rowRebindWithoutPosterClearsPreviousGlideRequest() {
        init(json("0", "cinema"))
        channels()[0].nowPlayingPoster = "android.resource://com.debrify.app/${R.drawable.splash_logo}"
        val row = adapter().onCreateViewHolder(list(), 0)
        adapter().onBindViewHolder(row, 0)
        val image = row.itemView.findViewById<ImageView>(R.id.stremio_tv_guide_poster)
        val request = DrawableImageViewTarget(image).request!!
        channels()[0].nowPlayingPoster = null
        adapter().onBindViewHolder(row, 0)
        assertTrue("rebinding without artwork clears the previous request", request.isCleared)
        assertNull("recycled image no longer owns a request", DrawableImageViewTarget(image).request)
        assertEquals("C", row.itemView.findViewById<TextView>(R.id.stremio_tv_guide_poster_letter).text.toString())
    }
}
