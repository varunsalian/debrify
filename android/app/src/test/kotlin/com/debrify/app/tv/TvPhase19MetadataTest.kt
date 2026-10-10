package com.debrify.app.tv

import android.content.Intent
import androidx.recyclerview.widget.RecyclerView
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before

/** Actual registered receiver, dock, playlist and binary channel; queued work remains queued. */
internal open class TvPhase19MetadataTest : TvPhase16OriginalTest() {
    protected lateinit var model: PlaybackPayload
    protected var seriesChanges = 0
    protected var movieChanges = 0
    protected val first get() = model.items[0]
    @Before fun prepareMetadata() {
        val one = p2Item("Original", season = 1, episode = 1).copy(description = "Description", artwork = "art",
            rating = 7.0, resumePositionMs = 9_000L, durationMs = 90_000L, traktProgressPercent = 25.0)
        val two = one.copy(id = "two", index = 1, title = "Second", season = 2, episode = 3)
        model = PlaybackPayload("Show", null, "series", mutableListOf(one, two), 0, "Show")
        set("payload", model); set("currentIndex", 0)
        val series = PlaylistAdapter(model.items, onItemClick = {})
        val movies = MoviePlaylistAdapter(model.items, MovieGroups(listOf(CollectionGroup("All", listOf(0, 1)))), onItemClick = {})
        series.registerAdapterDataObserver(object : RecyclerView.AdapterDataObserver() { override fun onChanged() { seriesChanges++ } })
        movies.registerAdapterDataObserver(object : RecyclerView.AdapterDataObserver() { override fun onChanged() { movieChanges++ } })
        set("seriesPlaylistAdapter", series); set("moviePlaylistAdapter", movies)
        seriesChanges = 0; movieChanges = 0; tv("titleView").text = "Before"
        messenger.requests.clear()
        org.robolectric.shadows.ShadowLog.clear()
    }
    protected fun metadata(updates: String? = null, imdb: String? = null, guide: String? = null, show: String? = null) =
        call("handleMetadataUpdate", arrayOf(stringType, stringType, stringType, stringType), updates, imdb, guide, show)
    protected fun update(vararg values: Pair<String, Any>) = metadata(JSONArray().put(JSONObject(mapOf("originalIndex" to 0, *values))).toString())
    protected fun receive(vararg extras: Pair<String, String>) {
        val intent = Intent("com.debrify.app.tv.UPDATE_EPISODE_METADATA")
        extras.forEach { intent.putExtra(it.first, it.second) }
        val registered = org.robolectric.Shadows.shadowOf(activity.application).getReceiversForIntent(intent)
        assertTrue("receiver registered for broadcast", registered.contains(field("metadataUpdateReceiver")))
        activity.sendBroadcast(intent); step(0)
    }
    protected fun metadataLog(text: String) = assertTrue("metadata diagnostic: $text",
        org.robolectric.shadows.ShadowLog.getLogsForTag("TVMazeUpdate").any { it.msg == text })
    protected fun metadataLogPrefix(text: String) = assertTrue("metadata diagnostic prefix: $text",
        org.robolectric.shadows.ShadowLog.getLogsForTag("TVMazeUpdate").any { it.msg.startsWith(text) })
    protected fun changes(series: Int, movies: Int) {
        assertEquals("series adapter notifications", series, seriesChanges)
        assertEquals("movie adapter notifications", movies, movieChanges)
    }
}
