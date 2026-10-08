package com.debrify.app.tv

import android.graphics.drawable.ColorDrawable
import android.view.View
import android.widget.EditText
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.request.target.DrawableImageViewTarget
import com.debrify.app.R
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowChoreographer

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStremioTvGuideUiCharacterizationTest : TvPhase7OriginalTest() {
    @Test fun inlineJsonAndAbsentKeysPreserveGuideDefaultsAndCurrentChannel() {
        val full = json("a", "Cinema").put("number", 42).put("type", "series").put("isFavorite", true)
            .put("nowPlaying", JSONObject().put("title", "Now").put("poster", "poster").put("year", "2020")
                .put("rating", 8.5).put("slotEndMs", 123L).put("progress", 0.4))
            .put("nextUp", JSONObject().put("title", "Next").put("poster", "next").put("year", "2021").put("rating", 7.0))
        init(full, JSONObject().put("id", "b"), json("c", data = false).put("nowPlaying", JSONObject()).put("nextUp", JSONObject()), current = "a")
        assertEquals(true, field("isStremioTvMode"))
        val a = channels()[0]
        assertEquals(listOf("Cinema", 42, "series", true, true, "Now", "poster", "2020", 8.5, 123L, 0.4f,
            "Next", "next", "2021", 7.0, true, false), values(a))
        assertEquals(listOf("", 2, "movie", false, false, null, null, null, null, 0L, 0f,
            null, null, null, null, false, false), values(channels()[1]))
        assertEquals(listOf("Channel c", 3, "movie", false, false, "", null, null, null, 0L, 0f,
            "", null, null, null, true, false), values(channels()[2]))
        assertEquals("3 channels", text("stremioTvGuideCountText").text.toString())
        assertEquals(0, adapter().getCurrentChannelPosition())
    }

    private fun values(c: StremioTvGuideChannel) = listOf(c.name, c.number, c.type, c.isFavorite, c.isCurrent,
        c.nowPlayingTitle, c.nowPlayingPoster, c.nowPlayingYear, c.nowPlayingRating, c.nowPlayingSlotEndMs,
        c.nowPlayingProgress, c.nextUpTitle, c.nextUpPoster, c.nextUpYear, c.nextUpRating, c.hasGuideData, c.isLoadingGuideData)

    @Test fun missingChannelsStillSetsModeBeforeReturning() {
        call("initStremioTvGuide", arrayOf(JSONObject::class.java), JSONObject())
        assertEquals("mode is set even without a channels array", true, field("isStremioTvMode"))
        assertTrue(channels().isEmpty()); assertNull(field("stremioTvChannelAdapter"))
    }

    @Test fun nonePlaylistButtonOpensGuideAndHidesControls() {
        standard(); set("controlsMenuVisible", true)
        assertEquals("Guide", playlistButton.text.toString())
        playlistButton.performClick()
        assertTrue("Guide button opens guide", visible())
        assertEquals(false, field("controlsMenuVisible"))
        playlistButton.performClick(); assertFalse(visible())
    }

    @Test fun seriesAndCollectionKeepTheirPlaylistButtonAction() {
        for (mode in listOf(PlaylistMode.SERIES, PlaylistMode.COLLECTION)) {
            set("playlistMode", mode); var clicks = 0
            playlistButton.text = "Playlist"; playlistButton.setOnClickListener { clicks++ }
            init(json(mode.name)); playlistButton.performClick()
            assertEquals("playlist label retained for $mode", "Playlist", playlistButton.text.toString())
            assertEquals(1, clicks); assertFalse(visible())
        }
    }

    @Test fun showScrollsThenOffersCurrentRowFocusAt150msAndHideResetsSearch() {
        init(json("0"), json("1"), current = "1")
        val lm = range(0, 1)
        invoke("showStremioTvGuide"); layout(); pump(); layout()
        assertTrue(visible()); assertEquals(View.VISIBLE, guide().visibility)
        assertEquals(200L, guide().animate().duration); assertEquals(listOf(1), lm.scrolls)
        val holder = list().findViewHolderForAdapterPosition(1)!!
        val search = view("stremioTvGuideSearch") as EditText
        search.requestFocus(); tickUntil(lm.scrolledAt + 149)
        assertTrue("focus remains outside list before deadline", search.hasFocus())
        tick(1)
        assertTrue("current row receives focus at 150ms", list().findViewHolderForAdapterPosition(1)!!.itemView.hasFocus())
        org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(list().findViewHolderForAdapterPosition(1)!!.itemView)
        assertEquals(true, invoke("isFocusInStremioTvGuideList"))
        org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(search)
        assertEquals(false, invoke("isFocusInStremioTvGuideList"))
        search.setText("missing"); invoke("hideStremioTvGuide")
        assertFalse(visible()); assertEquals("", search.text.toString()); assertEquals(150L, guide().animate().duration)
        ShadowChoreographer.setPaused(false); tick(250)
        assertEquals("hide completion uses GONE", View.GONE, guide().visibility)
        ShadowChoreographer.setPaused(true)
        invoke("toggleStremioTvGuide"); assertTrue(visible())
        invoke("toggleStremioTvGuide"); assertFalse(visible())
    }

    @Test fun searchMatchesNameTypeAndProgrammeCaseInsensitively() {
        init(json("0", "Cinema"), json("1", "News").put("type", "SERIES"), json("2", "Drama").put("nowPlaying", JSONObject().put("title", "MOON")))
        val search = view("stremioTvGuideSearch") as EditText
        for ((query, id) in listOf("CIN" to "0", "series" to "1", "moon" to "2")) {
            search.setText(query)
            assertEquals("search $query returns one row", 1, adapter().itemCount)
            assertEquals("search $query", id, adapter().getChannelAt(0)!!.id)
            assertEquals(1, adapter().itemCount); assertEquals("1 of 3 channels", text("stremioTvGuideCountText").text.toString())
        }
        search.setText("absent"); assertEquals(0, adapter().itemCount)
        invoke("showStremioTvGuide"); assertEquals("", search.text.toString()); assertEquals(3, adapter().itemCount)
    }

    @Test fun headerLetterFallbackAndMissingCurrentPreserveBoundHeader() {
        standard(); invoke("updateStremioTvGuideHeader")
        assertEquals("Channel 0", text("stremioTvGuideCurrentName").text.toString())
        assertEquals("Film 0", text("stremioTvGuideCurrentTitle").text.toString())
        assertEquals(View.VISIBLE, view("stremioTvGuideNowPlaying").visibility)
        assertEquals(View.GONE, view("stremioTvGuideNowPoster").visibility)
        assertEquals(View.VISIBLE, view("stremioTvGuideNowLetter").visibility)
        assertEquals("C", text("stremioTvGuideNowLetter").text.toString())
        channels()[0] = channels()[0].copy(name = "")
        invoke("updateStremioTvGuideHeader"); assertEquals("?", text("stremioTvGuideNowLetter").text.toString())
        channels().forEach { it.isCurrent = false }
        text("stremioTvGuideCurrentName").text = "retained"
        invoke("updateStremioTvGuideHeader"); assertEquals("retained", text("stremioTvGuideCurrentName").text.toString())
    }

    @Test fun posterUsesActivityGlideLifecycleAndListenerFallback() {
        standard(); channels()[0].nowPlayingPoster = "android.resource://com.debrify.app/${R.drawable.splash_logo}"
        invoke("updateStremioTvGuideHeader")
        val poster = view("stremioTvGuideNowPoster") as ImageView
        val request = DrawableImageViewTarget(poster).request!!
        val manager = Glide.with(activity)
        assertTrue("header request belongs to activity", TvPlayerOriginalAccess.glideTracks(manager, request))
        assertFalse(TvPlayerOriginalAccess.glideTracks(Glide.with(activity.applicationContext), request))
        assertEquals(View.GONE, view("stremioTvGuideNowLetter").visibility)
        assertEquals(View.VISIBLE, poster.visibility)
        val listener = TvPlayerOriginalAccess.artworkListener(poster)
        assertFalse(listener.onResourceReady(ColorDrawable(), "local", null, DataSource.LOCAL, true))
        assertTrue(listener.onLoadFailed(null, "local", DrawableImageViewTarget(poster), true))
        assertEquals(View.GONE, poster.visibility); assertEquals(View.VISIBLE, view("stremioTvGuideNowLetter").visibility)
        assertEquals("C", text("stremioTvGuideNowLetter").text.toString())
        lifecycle.pause().stop().destroy(); pump()
        assertTrue("destroy clears activity-owned header request", request.isCleared)
        assertFalse(TvPlayerOriginalAccess.glideTracks(manager, request))
    }
}
