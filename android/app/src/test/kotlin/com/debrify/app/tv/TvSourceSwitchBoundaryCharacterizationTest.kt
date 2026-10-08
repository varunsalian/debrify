package com.debrify.app.tv

import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSourceSwitchBoundaryCharacterizationTest : TvPhase8OriginalTest() {
    @Test fun nonDirectStreamWithDirectUrlStillUsesSingleResolver() {
        val selected = source(1, "https://phase8.invalid/direct.mp4").copy(streamType = "torrent")
        call("onStremioSourceSelected", arrayOf(StremioSource::class.java), selected)
        assertEquals(1, requests("requestStremioSourceResolve").size)
        assertTrue(requests("requestSourcePlaylistResolve").isEmpty())
        assertTrue("non-direct URL must not be applied", probe.media.isEmpty())
    }
    @Test fun directStreamWithoutUsableUrlUsesSingleResolver() {
        for (url in listOf(null, "")) {
            call("onStremioSourceSelected", arrayOf(StremioSource::class.java), source(1).copy(streamType = "directUrl", directUrl = url))
        }
        assertEquals(2, requests("requestStremioSourceResolve").size)
        assertTrue(probe.media.isEmpty())
    }
    @Test fun playlistResolverTakesPrecedenceOverUsableDirectUrl() {
        set("hasPlaylistResolver", true)
        call("onStremioSourceSelected", arrayOf(StremioSource::class.java), source(1, "https://phase8.invalid/direct.mp4"))
        assertEquals(1, requests("requestSourcePlaylistResolve").size)
        assertTrue(requests("requestStremioSourceResolve").isEmpty()); assertTrue(probe.media.isEmpty())
    }
    private fun failureReason(playlist: Boolean, branch: String, manual: Boolean, expected: String) {
        if (manual) call("beginManualSourceCandidate", arrayOf(intType), 1)
        else {
            set("startupFailoverCursor", StartupFailoverCursor(1, maxAttempts = 1).also { it.beginInitial(2) })
            set("currentStremioSourceIndex", 1)
            set("startupTryNextOnFailure", false)
        }
        ShadowLog.clear()
        if (branch == "exception") messenger.onSend = {
            if (it.call.method == if (playlist) "requestSourcePlaylistResolve" else "requestStremioSourceResolve")
                throw IllegalStateException("resolver transport failure")
        }
        resolve(playlist)
        if (branch != "exception") {
            if (branch == "empty") reply(playlist, emptyMap<String, Any>())
            else { workerReply(branch); idle() }
        }
        if (manual) {
            val rejects = ShadowLog.getLogs().filter { it.msg.contains("event=manual_candidate_reject ") }
            assertEquals("one manual rejection", 1, rejects.size)
            assertTrue("exact manual failure reason: $expected; actual=${rejects.single().msg}",
                rejects.single().msg.contains(" reason=$expected restoredSourceIndex="))
        } else {
            assertEquals("one startup rejection", 1, requests("startupSourceFailed").size)
            assertEquals("exact startup failure reason", expected,
                (requests("startupSourceFailed").single().call.arguments as Map<*, *>)["reason"])
        }
    }
    @Test fun singleEmptyManualReasonIsExact() = failureReason(false, "empty", true, "empty-resolve")
    @Test fun singleEmptyStartupReasonIsExact() = failureReason(false, "empty", false, "empty-resolve")
    @Test fun singleErrorManualReasonIsExact() = failureReason(false, "error", true, "resolve:error")
    @Test fun singleErrorStartupReasonIsExact() = failureReason(false, "error", false, "resolve:error")
    @Test fun singleMissingManualReasonIsExact() = failureReason(false, "missing", true, "resolve-not-implemented")
    @Test fun singleMissingStartupReasonIsExact() = failureReason(false, "missing", false, "resolve-not-implemented")
    @Test fun singleExceptionManualReasonIsExact() = failureReason(false, "exception", true, "resolve-exception")
    @Test fun singleExceptionStartupReasonIsExact() = failureReason(false, "exception", false, "resolve-exception")
    @Test fun playlistEmptyManualReasonIsExact() = failureReason(true, "empty", true, "empty-playlist")
    @Test fun playlistEmptyStartupReasonIsExact() = failureReason(true, "empty", false, "empty-playlist")
    @Test fun playlistErrorManualReasonIsExact() = failureReason(true, "error", true, "playlist:error")
    @Test fun playlistErrorStartupReasonIsExact() = failureReason(true, "error", false, "playlist:error")
    @Test fun playlistMissingManualReasonIsExact() = failureReason(true, "missing", true, "playlist-not-implemented")
    @Test fun playlistMissingStartupReasonIsExact() = failureReason(true, "missing", false, "playlist-not-implemented")
    @Test fun playlistExceptionManualReasonIsExact() = failureReason(true, "exception", true, "playlist-exception")
    @Test fun playlistExceptionStartupReasonIsExact() = failureReason(true, "exception", false, "playlist-exception")
    private fun applyFailureReason(items: List<*>, expected: String, startup: Boolean = false, episodeExact: Boolean = false) {
        if (episodeExact) seriesItem()
        if (startup) {
            set("startupFailoverCursor", StartupFailoverCursor(1, maxAttempts = 1).also { it.beginInitial(2) })
            set("currentStremioSourceIndex", 1); set("startupTryNextOnFailure", false)
        } else call("beginManualSourceCandidate", arrayOf(intType), 1)
        ShadowLog.clear()
        pack(items, exact = episodeExact)
        if (startup) assertEquals(expected, (requests("startupSourceFailed").single().call.arguments as Map<*, *>)["reason"])
        else {
            val reject = ShadowLog.getLogs().single { it.msg.contains("event=manual_candidate_reject ") }
            assertTrue("exact apply failure reason: $expected; actual=${reject.msg}", reject.msg.contains(" reason=$expected restoredSourceIndex="))
        }
        assertTrue("rejected pack never replaces media", probe.media.isEmpty())
    }
    @Test fun parsedEmptyPackManualReasonIsExact() = applyFailureReason(listOf("not an item"), "playlist-empty-after-parse")
    @Test fun invalidPackManualReasonIsExact() = applyFailureReason(listOf(raw() + mapOf("rating" to Double.NaN)), "playlist-items-invalid")
    @Test fun missingEpisodePackManualReasonIsExact() = applyFailureReason(listOf(raw("Wrong episode", 3, 1), raw("Another wrong episode", 3, 2)), "playlist-missing-episode", episodeExact = true)
    @Test fun missingEpisodePackStartupReasonIsExact() = applyFailureReason(listOf(raw("Wrong episode", 3, 1), raw("Another wrong episode", 3, 2)), "playlist-missing-episode", startup = true, episodeExact = true)
    @Test fun directReplacementCarriesMimeHeadersAndAllOtherPayloadFields() {
        val old = model().items.single().copy(mimeType = "video/old", sourceTitle = "Filename", artwork = "art", description = "description", rating = 8.5)
        model().items[0] = old
        val headers = mapOf("X-Phase8" to "payload")
        sources()[1] = source(1, headers = headers)
        val url = "https://phase8.invalid/new.mp4"
        direct(url, mime = "video/mp4", discovered = true)
        assertEquals("replacement payload preserves every field except URL, headers and MIME",
            old.copy(url = url, httpHeaders = headers, mimeType = "video/mp4"), model().items.single())
    }
    @Test fun playlistReplacementPreservesIncomingHeadersAndMetadata() {
        val incoming = raw() + mapOf("mimeType" to "video/mp4", "httpHeaders" to mapOf("X-Phase8" to "pack"),
            "artwork" to "pack-art", "description" to "pack-description", "rating" to 7.5, "sizeBytes" to 1234L)
        val expected = PlaybackItem.fromMap(incoming).copy(title = "Film", resumePositionMs = probe.position)
        pack(listOf(incoming))
        assertEquals("parsed payload fields survive the resume copy", expected, model().items.single())
    }
    @Test fun directApplyRefreshesQualityBadge() {
        val text = field("stremioSourceBadgeText") as TextView
        text.text = "stale direct badge"
        direct()
        assertEquals("Sources", text.text.toString())
        assertEquals(1, field("currentStremioSourceIndex"))
    }
    @Test fun playlistApplyRefreshesQualityBadge() {
        val text = field("stremioSourceBadgeText") as TextView
        text.text = "stale playlist badge"
        pack(listOf(raw()))
        assertEquals("Sources", text.text.toString())
        assertEquals(1, field("currentStremioSourceIndex"))
    }
}
