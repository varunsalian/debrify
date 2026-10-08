package com.debrify.app.tv

import com.debrify.app.MainActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSourceSwitchResolverCharacterizationTest : TvPhase8OriginalTest() {
    private fun workerAccepted(playlist: Boolean, kind: String) {
        resolve(playlist)
        val value = if (playlist) mapOf("items" to listOf(raw())) else mapOf("url" to "https://phase8.invalid/worker.mp4")
        workerReply(kind, value)
        assertTrue("UI action remains queued", probe.media.isEmpty())
        set("stremioResolutionToken", 8); idle()
        if (kind == "success") assertEquals("accepted reply survives later token", 1, probe.media.size)
        else {
            assertNotNull("accepted failure UI action still runs", field("statusPill"))
            assertEquals(if (kind == "missing") "Couldn't switch source" else if (playlist) "Couldn't switch — failed to resolve source" else "Couldn't switch — source resolution failed", pill().text.toString())
        }
    }
    @Test fun singleSuccessAcceptedOnWorkerRunsAfterTokenSupersession() = workerAccepted(false, "success")
    @Test fun playlistSuccessAcceptedOnWorkerRunsAfterTokenSupersession() = workerAccepted(true, "success")
    @Test fun singleErrorAcceptedOnWorkerRunsAfterTokenSupersession() = workerAccepted(false, "error")
    @Test fun playlistErrorAcceptedOnWorkerRunsAfterTokenSupersession() = workerAccepted(true, "error")
    @Test fun singleMissingAcceptedOnWorkerRunsAfterTokenSupersession() = workerAccepted(false, "missing")
    @Test fun playlistMissingAcceptedOnWorkerRunsAfterTokenSupersession() = workerAccepted(true, "missing")
    @Test fun playlistAcceptedReplyReadsCursorInsideUiBlock() {
        seriesItem(); resolve(true); workerReply("success", mapOf("items" to listOf(raw("Other", 3, 1), raw("Another", 3, 2))))
        cursor(false); set("stremioResolutionToken", 8); idle()
        assertTrue(probe.media.isEmpty()); assertEquals(2, model().items.single().season)
        assertEquals("Source does not contain this episode", pill().text.toString())
    }
    @Test fun staleSingleRepliesAreDiscardedForEveryResultBranch() {
        for (kind in listOf("success", "error", "missing")) {
            resolve(false); set("stremioResolutionToken", 8); workerReply(kind, mapOf("url" to "https://phase8.invalid/stale.mp4")); idle()
            assertTrue(probe.media.isEmpty()); assertNull(field("statusPill"))
        }
    }
    @Test fun stalePlaylistRepliesAreDiscardedForEveryResultBranch() {
        for (kind in listOf("success", "error", "missing")) {
            resolve(true); set("stremioResolutionToken", 8); workerReply(kind, mapOf("items" to listOf(raw()))); idle()
            assertTrue(probe.media.isEmpty()); assertNull(field("statusPill"))
        }
    }
    @Test fun emptyAndMalformedSingleResultsPinFailureMessage() {
        for (result in listOf(null, "malformed", emptyMap<String, Any>(), mapOf("url" to ""))) {
            resolve(false); reply(false, result); assertEquals("Couldn't switch — failed to resolve source", pill().text.toString())
        }
        assertTrue(probe.media.isEmpty())
    }
    @Test fun emptyAndMalformedPlaylistResultsPinFailureMessage() {
        for (result in listOf(null, "malformed", emptyMap<String, Any>(), mapOf("items" to emptyList<Any>()))) {
            resolve(true); reply(true, result); assertEquals("Source unavailable — not cached or not a video", pill().text.toString())
        }
        assertTrue(probe.media.isEmpty())
    }
    @Test fun absentBridgeIsSilentAndSendExceptionsUseCatchFailureForBothResolvers() {
        MainActivity.setAndroidTvPlayerChannel(null); resolve(false); resolve(true)
        assertTrue(messenger.requests.isEmpty()); assertNull(field("statusPill"))
        MainActivity.setAndroidTvPlayerChannel(io.flutter.plugin.common.MethodChannel(messenger, "com.debrify.app/android_tv_player"))
        messenger.throwOnSend = true
        resolve(false); assertEquals("Couldn't switch source", pill().text.toString())
        resolve(true); assertEquals("Couldn't switch source", pill().text.toString()); assertTrue(probe.media.isEmpty())
    }
}
