package com.debrify.app.tv

import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpisodeMetadataReceiverTest : TvPhase19MetadataTest() {
    @Test fun registeredBroadcastReadsItsOwnIntentAndNotLaunchExtras() {
        activity.intent.putExtra("metadataUpdates", "[{\"originalIndex\":0,\"title\":\"Launch\"}]")
        receive("metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"Broadcast\"}]")
        assertEquals(org.robolectric.shadows.ShadowLog.getLogsForTag("TVMazeUpdate").joinToString { it.msg }, "Broadcast", first.title)
    }

    @Test fun stagedUpdatesIsReadOnlyAndWinsOverInline() {
        val file = File(activity.cacheDir, "episode_metadata_p19.json").apply { writeText("[{\"originalIndex\":0,\"title\":\"Staged\"}]") }
        try {
            receive("metadataUpdatesPath" to file.path, "metadataUpdates" to "[]")
            assertEquals("Staged", first.title)
            assertTrue("handoff receivers share the staged file", file.exists())
            assertEquals("[{\"originalIndex\":0,\"title\":\"Staged\"}]", file.readText())
            receive("metadataUpdatesPath" to file.path)
            assertTrue(file.exists())
        } finally { file.delete() }
    }

    @Test fun stagedGuideIsReadOnlyAndWinsOverInline() {
        val file = File(activity.cacheDir, "episode_guide_p19.json").apply { writeText("[{\"season\":4,\"episode\":5,\"title\":\"Staged\"}]") }
        try {
            receive("guideEpisodesPath" to file.path, "guideEpisodes" to "[]")
            assertEquals("one staged guide episode", 1, model.guideEpisodes.size)
            assertEquals(4, model.guideEpisodes.single().season)
            assertTrue("handoff receivers share the staged file", file.exists())
            assertEquals("[{\"season\":4,\"episode\":5,\"title\":\"Staged\"}]", file.readText())
            receive("guideEpisodesPath" to file.path)
            assertTrue(file.exists())
        } finally { file.delete() }
    }

    @Test fun stagedOutsideFallsBackToInline() {
        val file = File(activity.filesDir, "episode_metadata_p19.json")
        file.writeText("[{\"originalIndex\":0,\"title\":\"Rejected\"}]")
        try { receive("metadataUpdatesPath" to file.path, "metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"Inline\"}]"); assertEquals("Inline", first.title); metadataLog("Rejected staged metadataUpdatesPath outside cacheDir") } finally { file.delete() }
    }

    @Test fun stagedPrefixFallsBackToInline() {
        val file = File(activity.cacheDir, "other_p19.json")
        file.writeText("[{\"originalIndex\":0,\"title\":\"Rejected\"}]")
        try { receive("metadataUpdatesPath" to file.path, "metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"Inline\"}]"); assertEquals("Inline", first.title); metadataLog("Rejected staged metadataUpdatesPath outside cacheDir") } finally { file.delete() }
    }

    @Test fun stagedNestedFallsBackToInline() {
        val file = File(File(activity.cacheDir, "p19-folder").apply { mkdirs() }, "episode_metadata_p19.json")
        file.writeText("[{\"originalIndex\":0,\"title\":\"Rejected\"}]")
        try { receive("metadataUpdatesPath" to file.path, "metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"Inline\"}]"); assertEquals("Inline", first.title); metadataLog("Rejected staged metadataUpdatesPath outside cacheDir") } finally { file.delete() }
    }

    @Test fun stagedMissingFallsBackToInline() {
        val file = File(activity.cacheDir, "episode_metadata_missing.json")
        try { receive("metadataUpdatesPath" to file.path, "metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"Inline\"}]"); assertEquals("Inline", first.title); metadataLogPrefix("Failed to read staged metadataUpdatesPath:") } finally { file.delete() }
    }

    @Test fun stagedUnreadableDirectoryFallsBackToInline() {
        val file = File(activity.cacheDir, "episode_metadata_directory").apply { mkdirs() }
        try { receive("metadataUpdatesPath" to file.path, "metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"Inline\"}]"); assertEquals("Inline", first.title); metadataLogPrefix("Failed to read staged metadataUpdatesPath:") } finally { file.delete() }
    }

    @Test fun canonicalSymlinkOutsideCacheIsRejected() {
        val target = File(activity.filesDir, "episode_metadata_symlink.json").apply { writeText("[{\"originalIndex\":0,\"title\":\"Outside\"}]") }
        val link = File(activity.cacheDir, "episode_metadata_link.json")
        java.nio.file.Files.createSymbolicLink(link.toPath(), target.toPath())
        try { receive("metadataUpdatesPath" to link.path, "metadataUpdates" to "[{\"originalIndex\":0,\"title\":\"Inline\"}]"); assertEquals("Inline", first.title) } finally { link.delete(); target.delete() }
    }

    @Test fun nullIntentAndAbsentPathCannotChangePayload() {
        val fallback = File(activity.cacheDir, "episode_metadata_fallback.json").apply {
            writeText("[{\"originalIndex\":0,\"title\":\"Implicit scan\"}]")
        }
        try {
            (field("metadataUpdateReceiver") as android.content.BroadcastReceiver).onReceive(null, null)
            assertEquals("Original", first.title); changes(0, 0)
            assertNull(call("readStagedExtra", arrayOf(Intent::class.java, stringType, stringType), null, "metadataUpdatesPath", "episode_metadata_"))
            assertNull(call("readStagedExtra", arrayOf(Intent::class.java, stringType, stringType), Intent(), "metadataUpdatesPath", "episode_metadata_"))
        } finally { fallback.delete() }
    }

    @Test fun showNameWritesEvenWithoutPayloadAndBlankDoesNotEraseIt() {
        set("ottSkinInstalled", false); set("payload", null)
        metadata(show = "  Canonical  "); assertEquals("Canonical", field("ottShowName")); metadataLog("payload is NULL - cannot update")
        metadata(show = "  "); assertEquals("Canonical", field("ottShowName")); changes(0, 0)
    }

    @Test fun classicShowNameDoesNotPublishOttDock() {
        set("ottSkinInstalled", false); val title = android.widget.TextView(activity); set("ottIdentityTitle", title); title.text = "Before"
        metadata(show = "Canonical"); assertEquals("Canonical", field("ottShowName")); assertEquals("Before", tv("ottIdentityTitle").text.toString())
    }

    @Test fun guideZeroCoordinatesAndAbsentKeyDefaultsAreAdopted() {
        model.guideEpisodes.add(GuideEpisode(season = 9, episode = 9, title = null, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false))
        metadata(guide = "[{\"season\":0,\"episode\":0}]")
        assertEquals("one adopted guide episode", 1, model.guideEpisodes.size)
        val g = model.guideEpisodes.single(); assertEquals(0, g.season); assertEquals(0, g.episode)
        assertNull(g.title); assertNull(g.artwork); assertNull(g.description); assertNull(g.rating); assertNull(g.runtime)
        assertNull(g.resumePositionMs); assertNull(g.durationMs); assertNull(g.trackerProgressPercent); assertFalse(g.watched); assertTrue(g.shuffleEligible)
    }

    @Test fun guideEveryPresentMetadataFieldIsCopied() {
        metadata(guide = "[{\"season\":3,\"episode\":4,\"title\":\"Title\",\"artwork\":\"Art\",\"description\":\"Desc\",\"rating\":0,\"runtime\":40,\"resumePositionMs\":123,\"durationMs\":456,\"trackerProgressPercent\":25,\"watched\":true,\"shuffleEligible\":false}]")
        assertEquals("one adopted guide episode", 1, model.guideEpisodes.size)
        val g = model.guideEpisodes.single(); assertEquals(3, g.season); assertEquals(4, g.episode)
        assertEquals("Title", g.title); assertEquals("Art", g.artwork); assertEquals("Desc", g.description); assertNotNull("guide rating is present", g.rating); assertEquals(0.0, g.rating!!, 0.0); assertEquals(40, g.runtime)
        assertEquals(123L, g.resumePositionMs); assertEquals(456L, g.durationMs); assertNotNull("guide tracker progress is present", g.trackerProgressPercent); assertEquals(25.0, g.trackerProgressPercent!!, 0.0); assertTrue(g.watched); assertFalse(g.shuffleEligible)
    }

    @Test fun guideMissingSeasonPreservesExistingGuide() {
        val old = GuideEpisode(season = 9, episode = 9, title = null, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false); model.guideEpisodes.add(old)
        metadata(guide = "[{\"episode\":1}]")
        assertEquals(listOf(old), model.guideEpisodes)
    }

    @Test fun guideMissingEpisodePreservesExistingGuide() {
        val old = GuideEpisode(season = 9, episode = 9, title = null, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false); model.guideEpisodes.add(old)
        metadata(guide = "[{\"season\":1}]")
        assertEquals(listOf(old), model.guideEpisodes)
    }

    @Test fun guideNegativeSeasonPreservesExistingGuide() {
        val old = GuideEpisode(season = 9, episode = 9, title = null, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false); model.guideEpisodes.add(old)
        metadata(guide = "[{\"season\":-1,\"episode\":1}]")
        assertEquals(listOf(old), model.guideEpisodes)
    }

    @Test fun guideNegativeEpisodePreservesExistingGuide() {
        val old = GuideEpisode(season = 9, episode = 9, title = null, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false); model.guideEpisodes.add(old)
        metadata(guide = "[{\"season\":1,\"episode\":-1}]")
        assertEquals(listOf(old), model.guideEpisodes)
    }

    @Test fun guideEmptyPreservesExistingGuide() {
        val old = GuideEpisode(season = 9, episode = 9, title = null, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false); model.guideEpisodes.add(old)
        metadata(guide = "[]")
        assertEquals(listOf(old), model.guideEpisodes)
    }

    @Test fun guideMalformedPreservesExistingGuide() {
        val old = GuideEpisode(season = 9, episode = 9, title = null, artwork = null, description = null, rating = null, runtime = null, resumePositionMs = null, durationMs = null, trackerProgressPercent = null, watched = false); model.guideEpisodes.add(old)
        metadata(guide = "bad")
        assertEquals(listOf(old), model.guideEpisodes)
    }

    @Test fun seriesGuideRebuildsMissingRowsActivatesCurrentAndRefreshesTitle() {
        set("hasPlaylistResolver", true); metadata(guide = "[{\"season\":1,\"episode\":1},{\"season\":1,\"episode\":2}]")
        assertEquals(2, model.guideEpisodes.size); val adapter = field("seriesPlaylistAdapter") as PlaylistAdapter
        assertTrue("missing guide row built", (TvPlayerOriginalAccess.field(adapter, "listItems") as List<*>).any { it is PlaylistListItem.MissingEpisode })
        assertTrue("active row selected", adapter.getActiveItemPosition() >= 0)
        assertEquals("Original", tv("titleView").text.toString())
    }

    @Test fun mixedCaseSeriesGuideStillRebuildsButMovieDoesNot() {
        model.contentType = "SeRiEs"; metadata(guide = "[{\"season\":1,\"episode\":2}]")
        assertEquals("Original", tv("titleView").text.toString())
        val adapter = field("seriesPlaylistAdapter"); model.contentType = "movie"; tv("titleView").text = "Before"
        metadata(guide = "[{\"season\":8,\"episode\":9}]")
        assertEquals("new movie guide replaces previous guide", 1, model.guideEpisodes.size)
        assertEquals(8, model.guideEpisodes.single().season); assertSame(adapter, field("seriesPlaylistAdapter")); assertEquals("Before", tv("titleView").text.toString())
    }

    @Test fun imdbDiscoveryGuard() {
        model.imdbId = null; set("currentIndex", 99)
        metadata(imdb = "tt1900")
        assertFalse("no current item means no discovery-driven subtitle fetch", org.robolectric.shadows.ShadowLog.getLogsForTag("TVMazeUpdate").any { it.msg == "Fetching Stremio subtitles with discovered IMDB ID" })
        assertEquals("tt1900", model.imdbId)
    }

    @Test fun imdbEmptyGuard() {
        model.imdbId = ""; set("currentIndex", 99)
        metadata(imdb = "tt1900")
        assertFalse("no current item means no discovery-driven subtitle fetch", org.robolectric.shadows.ShadowLog.getLogsForTag("TVMazeUpdate").any { it.msg == "Fetching Stremio subtitles with discovered IMDB ID" })
        assertEquals("tt1900", model.imdbId)
    }

    @Test fun imdbExistingGuard() {
        model.imdbId = "ttOld"; set("currentIndex", 99)
        metadata(imdb = "tt1900")
        assertEquals("ttOld", model.imdbId)
    }

    @Test fun imdbWrongPrefixGuard() {
        model.imdbId = null; set("currentIndex", 99)
        metadata(imdb = "id1900")
        assertEquals(null, model.imdbId)
    }

    @Test fun imdbWrongCaseGuard() {
        model.imdbId = null; set("currentIndex", 99)
        metadata(imdb = "TT1900")
        assertEquals(null, model.imdbId)
    }

    @Test fun imdbEmptyIncomingGuard() {
        model.imdbId = null; set("currentIndex", 99)
        metadata(imdb = "")
        assertEquals(null, model.imdbId)
    }

    @Test fun imdbDiscoveryCallsCurrentItemSubtitleFetch() {
        set("isLoadingStremioSubtitles", false); set("injectedSubtitles", mutableListOf(com.debrify.app.subtitle.StremioSubtitle("p19", "https://p19.invalid/sub.srt", "en", "P19", "P19")))
        metadata(imdb = "tt1900")
        assertEquals("tt1900", model.imdbId); assertEquals(1, (field("stremioSubtitles") as List<*>).size)
        metadataLog("Discovered IMDB ID from TVMaze: tt1900 (was: null)")
        metadataLog("Fetching Stremio subtitles with discovered IMDB ID")
    }
}
