package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Callbacks are installed by real bootstrap, rather than injected by the tests. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistCallerCharacterizationTest : TvPhase13OriginalTest() {
    @Test fun controlsButtonOpensPlaylistAndActivityBackClosesIt() {
        val button=activity.findViewById<View>(R.id.debrify_playlist_button)
        assertNotNull(button);button.performClick()
        assertTrue(field("playlistVisible") as Boolean);assertEquals(View.VISIBLE,overlay().visibility)
        assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_BACK)))
        assertFalse(field("playlistVisible") as Boolean);assertEquals(View.GONE,overlay().visibility)
    }
    @Test fun realSeriesRowClickHidesOverlayAndPlaysItsPayloadIndex() {
        showPlaylist();val a=playlist().adapter as PlaylistAdapter
        val h=a.onCreateViewHolder(playlist(),1);a.onBindViewHolder(h,1);h.itemView.performClick()
        assertFalse(field("playlistVisible") as Boolean);assertEquals(1,field("currentIndex"))
        assertTrue(probe.events.any{it.startsWith("media:https://phase13.invalid/two")})
    }
    @Test fun realMovieRowClickHidesOverlayAndPreservesGroupPayloadIndex() {
        collection();showPlaylist();val a=playlist().adapter as MoviePlaylistAdapter
        val h=a.onCreateViewHolder(playlist(),0);a.onBindViewHolder(h,1)
        h.itemView.findViewById<View>(R.id.android_tv_playlist_item_container).performClick()
        assertFalse(field("playlistVisible") as Boolean);assertEquals(1,field("currentIndex"))
        assertTrue(probe.events.any{it.startsWith("media:https://phase13.invalid/two")})
    }
    @Test fun realAbsentGuideRowClickHidesOverlayAndRequestsItsExactEpisode() {
        set("hasPlaylistResolver",true)
        model().guideEpisodes.add(GuideEpisode(season=1,episode=8,title="Absent",artwork=null,description=null,rating=null,runtime=null,resumePositionMs=null,durationMs=null,trackerProgressPercent=null,watched=false))
        rebuild();showPlaylist();val a=playlist().adapter as PlaylistAdapter
        val h=a.onCreateViewHolder(playlist(),1);a.onBindViewHolder(h,0);h.itemView.performClick()
        assertFalse(field("playlistVisible") as Boolean)
        val request=requests("requestEpisodeFetch").lastOrNull();assertNotNull(request)
        val args=request!!.call.arguments as Map<*,*>
        assertEquals(1,args["season"]);assertEquals(8,args["episode"])
    }
}
