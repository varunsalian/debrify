package com.debrify.app.tv

import com.debrify.app.subtitle.AddonSubtitleStatus
import com.debrify.app.subtitle.StremioSubtitle
import kotlinx.coroutines.Job
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleSourcesLifecycleCharacterizationTest : TvPhase14OriginalTest() {
    @Test fun destroyCancelsBorrowedScopeThenClearsFlatListThenNullsService() {
        val scope = scope(); val service = field("stremioSubtitleService")
        val observations = mutableListOf<Pair<Boolean, Boolean>>()
        val observed = object : ArrayList<StremioSubtitle>() {
            override fun clear() {
                observations.add(scope.coroutineContext[Job]!!.isCancelled to (field("stremioSubtitleService") === service))
                super.clear()
            }
        }
        observed.add(subtitle()); set("stremioSubtitles", observed); val token = token(); destroyNow()
        assertEquals(listOf(true to true), observations); assertTrue(observed.isEmpty())
        assertNull(field("stremioSubtitleService")); assertTrue(scope.coroutineContext[Job]!!.isCancelled)
        assertEquals("Original destroy does not invalidate metadata generation", token, token())
    }
    @Test fun lateMetadataAfterDestroyStillWritesCapturedCacheButFinishesWithNoAddons() {
        model().imdbId = null; val captured = model(); fetch(); val token = token(); destroyNow()
        assertNull(field("stremioSubtitleService")); assertEquals(token, token()); assertTrue(loading())
        endpoint.success("requestMovieMetadata", mapOf("imdbId" to "tt-late"))
        assertEquals("tt-late", captured.perItemImdbIds[0]); assertTrue(slots().isEmpty()); assertTrue(flat().isEmpty())
        assertTrue(discovery()); assertFalse("Correct pinned late-metadata outcome is loading false", loading())
        assertTrue(scope().coroutineContext[Job]!!.children.none())
    }
    @Test fun cancelledRunningFetchPublishesFailedSlotAndCanToastAfterDestroy() {
        installAddons(addon()); set("manualSubtitleImdbId", "tt-manual"); val response = response(); known(); entered(response)
        val job = jobs().single(); ShadowToast.reset(); destroyNow(); complete(response, job)
        assertEquals(AddonSubtitleStatus.FAILED, slots().single().status); assertTrue(flat().isEmpty()); assertFalse(loading())
        assertEquals("No online subtitles found for this title", ShadowToast.getTextOfLatestToast())
        assertTrue(job.isCancelled); assertNull(field("stremioSubtitleService"))
    }
    @Test fun olderCatalogReplyCanOverwriteNewerUnifiedSearchResultsAsInOriginal() {
        menu().show("subs", "search"); menuCallbacks().onSearchSubmit("older"); menuCallbacks().onSearchSubmit("newer")
        endpoint.success("searchSubtitleCatalogs", catalog(result(name = "New", imdb = "tt-new")), occurrence = 1)
        assertEquals(listOf(result(name = "New", imdb = "tt-new")), field("subtitleSearchResults"))
        endpoint.success("searchSubtitleCatalogs", catalog(result(name = "Old", imdb = "tt-old")), occurrence = 0)
        assertEquals("1 results", field("subtitleSearchStatus")); assertEquals(listOf(result(name = "Old", imdb = "tt-old")), field("subtitleSearchResults"))
    }
    @Test fun hiddenUnifiedMenuIgnoresLateSuccessAndError() {
        menu().show("subs", "search"); menuCallbacks().onSearchSubmit("query"); menu().hide()
        endpoint.success("searchSubtitleCatalogs", catalog(result())); assertEquals("Searching…", field("subtitleSearchStatus")); assertEquals(emptyList<SubtitleCatalogResult>(), field("subtitleSearchResults"))
        endpoint.error("searchSubtitleCatalogs", "Server declined"); assertEquals("Searching…", field("subtitleSearchStatus"))
    }
    @Test fun directPlaybackCallerResetsManualIdentityAndFetchesForReplacement() {
        set("manualSubtitleImdbId", "tt-old"); set("subtitleSearchStatus", "old search"); set("subtitleAddonDiscoveryReady", false)
        call("playMediaDirect", arrayOf(PlaybackItem::class.java), item())
        assertNull(field("manualSubtitleImdbId")); assertEquals("", field("subtitleSearchStatus")); assertTrue(discovery()); assertFalse(loading())
        assertTrue(probe.events.any { it.startsWith("media:") })
    }
    @Test fun pikPakPlaybackCallerResetsManualIdentityAndFetchesForReplacement() {
        set("manualSubtitleImdbId", "tt-old"); set("subtitleSearchStatus", "old search")
        call("playPikPakVideoWithRetry", arrayOf(PlaybackItem::class.java), item())
        assertNull(field("manualSubtitleImdbId")); assertEquals("", field("subtitleSearchStatus")); assertTrue(discovery()); assertFalse(loading())
        assertTrue(probe.events.any { it.startsWith("media:") })
    }
}
