package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpisodeMetadataSweepTest : TvPhase19MetadataTest() {
    private fun messages() = org.robolectric.shadows.ShadowLog.getLogsForTag("TVMazeUpdate").map { it.msg }
    private fun logged(text: String) = assertTrue("diagnostic: $text", messages().contains(text))
    @Test fun receiverBroadcastDispatchesAllInlineExtrasTogether() {
        set("ottSkinInstalled", false)
        receive("metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"New\"}]", "imdbId" to "tt1900",
            "guideEpisodes" to "[{\"season\":3,\"episode\":4}]", "showName" to "  Show  ")
        assertEquals("New", first.title); assertEquals("tt1900", model.imdbId)
        assertEquals("one broadcast guide episode", 1, model.guideEpisodes.size)
        assertEquals(3, model.guideEpisodes.single().season); assertEquals("Show", field("ottShowName"))
    }
    @Test fun workerGuideAdoptsImmediatelyThenRebuildsAndPublishesOnMain() {
        set("hasPlaylistResolver", true); val before = field("seriesPlaylistAdapter")
        val error = java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val thread = Thread { try { metadata(guide = "[{\"season\":1,\"episode\":2}]") } catch (e: Throwable) { error.set(e) } }
        thread.start(); thread.join(5000); assertFalse(thread.isAlive); assertNull(error.get())
        logged("Adopted 1 guide episodes")
        assertEquals("worker guide is immediately adopted", 1, model.guideEpisodes.size)
        assertEquals(2, model.guideEpisodes.single().episode); assertSame(before, field("seriesPlaylistAdapter"))
        assertEquals("Before", tv("titleView").text.toString()); step(0)
        assertNotSame(before, field("seriesPlaylistAdapter")); assertEquals("Original", tv("titleView").text.toString())
    }
    @Test fun guideRefreshesCatalogButtonsAndSelectsNonzeroCurrentIndex() {
        set("currentIndex", 1); set("hasPlaylistResolver", true)
        activity.findViewById<android.view.View>(com.debrify.app.R.id.debrify_prev_button).visibility = android.view.View.GONE
        metadata(guide = "[{\"season\":2,\"episode\":3},{\"season\":2,\"episode\":4}]")
        val adapter = field("seriesPlaylistAdapter") as PlaylistAdapter
        val active = adapter.getActiveItemPosition()
        assertTrue(active >= 0)
        val row = (TvPlayerOriginalAccess.field(adapter, "listItems") as List<*>)[active] as PlaylistListItem.Episode
        assertEquals(1, row.itemIndex); assertEquals(android.view.View.VISIBLE, activity.findViewById<android.view.View>(com.debrify.app.R.id.debrify_prev_button).visibility)
        assertEquals("Second", tv("titleView").text.toString())
    }
    @Test fun updateDiagnosticsCountValidAndSkippedRowsAndPublishBothAdapterStates() {
        val json = "[{\"originalIndex\":-1},{\"originalIndex\":0,\"title\":\"New\"}]"
        metadata(json)
        logged("updatesJson length=${json.length}, imdbId=null")
        logged("Skipping unmatched update index=-1 SnullEnull (items.size=2)")
        logged("handleMetadataUpdate CALLED")
        logged("model.items.size=2"); logged("Parsed 2 updates"); logged("Updated 1 items, skipped 1")
        logged("Refreshing UI adapters..."); logged("seriesAdapter=true, movieAdapter=true"); logged("UI refresh done")
        logged("Refreshing title for current episode: New")
        assertEquals("New", first.title); changes(1, 1)
    }
    @Test fun absentAndMalformedUpdatesAndGuideHaveDistinctDiagnostics() {
        metadata(); logged("updatesJson length=0, imdbId=null"); logged("No episode metadata updates to process")
        metadata("[]"); logged("No items updated - anyUpdated=false")
        metadata("bad", guide = "bad")
        assertTrue(messages().any { it.startsWith("Failed to parse guide episodes:") })
        assertTrue(messages().any { it.startsWith("Failed to parse metadata updates:") })
        changes(0, 0)
    }
}
