package com.debrify.app.tv

import androidx.recyclerview.widget.RecyclerView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvPlaylistScrollCharacterizationTest : TvPhase13OriginalTest() {
    private class Scrolls(context: android.content.Context): RecyclerView(context) {
        val positions=mutableListOf<Int>()
        override fun scrollToPosition(position: Int) { positions.add(position) }
    }
    @Test fun seasonScrollFlagAndDefaultDispatchAreReadForEachSelection() {
        val adapter=playlist().adapter as PlaylistAdapter
        val view=Scrolls(activity);set("playlistView",view)
        call("selectSeasonTab",arrayOf(intType,PlaylistAdapter::class.java,boolType),0,adapter,false)
        assertTrue(view.positions.isEmpty())
        defaultCall("selectSeasonTab",arrayOf(intType,PlaylistAdapter::class.java,boolType),4,1,adapter,false)
        assertEquals(listOf(0),view.positions)
    }
    @Test fun collectionScrollDependsOnFlagOrChangedGroupAndNonemptyItems() {
        collection(listOf(org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(0,1))),org.json.JSONObject().put("fileIndices",org.json.JSONArray(listOf(2)))))
        val adapter=playlist().adapter as MoviePlaylistAdapter
        val view=Scrolls(activity);set("playlistView",view)
        fun select(index: Int,scroll: Boolean=false,force: Boolean=false)=call("selectMovieTab",arrayOf(intType,MoviePlaylistAdapter::class.java,boolType,boolType),index,adapter,scroll,force)
        select(0);assertTrue(view.positions.isEmpty())
        select(1);assertEquals(listOf(0),view.positions)
        select(1);assertEquals(1,view.positions.size)
        select(1,true);assertEquals(2,view.positions.size)
        select(1,false,true);assertEquals(3,view.positions.size)
        select(99,true);assertEquals(3,view.positions.size)
    }
}
