package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackResolveCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun lateReplyRejectsNavigation() {
        payload(p2Item(url = "")); val attempt = attemptWith()
        call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        set("mediaPreparationGeneration", 1); replyDirect(mapOf("url" to "https://resolved.invalid/new.mp4"))
        assertEquals("", item().url); assertTrue(probe.media.isEmpty())
        assertEquals(220L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun lateReplyRejectsShuffleFinished() {
        payload(p2Item(url = "")); val attempt = attemptWith(); set("pendingShufflePlayback", attempt)
        call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        setAttempt(attempt, "finished", true); replyDirect(mapOf("url" to "https://resolved.invalid/new.mp4"))
        assertEquals("", item().url); assertTrue(probe.media.isEmpty())
        assertEquals(220L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun lateReplyRejectsManualSnapshot() {
        payload(p2Item(url = "")); val attempt = attemptWith()
        set("manualSourceSwitchIndex", 1); set("manualSourceSwitchSnapshot", ManualSourceSwitchSnapshot(0,0,"single",model().items.toList(),emptyMap(),emptyMap(),null,emptyMap(),null))
         call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
         set("manualSourceSwitchSnapshot", null); replyDirect(mapOf("url" to "https://resolved.invalid/new.mp4"))
         assertEquals("", item().url); assertTrue(probe.media.isEmpty())
         assertEquals(220L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun lateReplyRejectsManualIndex() {
        payload(p2Item(url = "")); val attempt = attemptWith()
        set("manualSourceSwitchIndex", 1); set("manualSourceSwitchSnapshot", ManualSourceSwitchSnapshot(0,0,"single",model().items.toList(),emptyMap(),emptyMap(),null,emptyMap(),null))
         call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
         set("manualSourceSwitchIndex", 0); replyDirect(mapOf("url" to "https://resolved.invalid/new.mp4"))
         assertEquals("", item().url); assertTrue(probe.media.isEmpty())
         assertEquals(220L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun lateReplyRejectsManualToken() {
        payload(p2Item(url = "")); val attempt = attemptWith()
        set("manualSourceSwitchIndex", 1); set("manualSourceSwitchSnapshot", ManualSourceSwitchSnapshot(0,0,"single",model().items.toList(),emptyMap(),emptyMap(),null,emptyMap(),null))
         call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
         set("stremioResolutionToken", 1); replyDirect(mapOf("url" to "https://resolved.invalid/new.mp4"))
         assertEquals("", item().url); assertTrue(probe.media.isEmpty())
         assertEquals(220L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun lateReplyRejectsStartupGeneration() {
        payload(p2Item(url = "")); val attempt = attemptWith()
        val cursor = StartupFailoverCursor(0, 2); cursor.beginInitial(2); set("startupFailoverCursor", cursor)
         call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
         set("startupFailoverGeneration", 1); replyDirect(mapOf("url" to "https://resolved.invalid/new.mp4"))
         assertEquals("", item().url); assertTrue(probe.media.isEmpty())
         assertEquals(220L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun providerMissing() {
        payload(p2Item(url = "", provider = "Original")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        replyDirect(mapOf("url" to "https://resolve.invalid/a.mp4")); assertEquals("Original", item().provider); assertEquals("https://resolve.invalid/a.mp4", item().url)
        assertEquals(1, probe.media.size)
    }

    @Test fun providerExplicit() {
        payload(p2Item(url = "", provider = "Original")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        replyDirect(mapOf("url" to "https://resolve.invalid/a.mp4", "provider" to "Fetched")); assertEquals("Fetched", item().provider); assertEquals("https://resolve.invalid/a.mp4", item().url)
        assertEquals(1, probe.media.size)
    }

    @Test fun providerEmpty() {
        payload(p2Item(url = "", provider = "Original")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        replyDirect(mapOf("url" to "https://resolve.invalid/a.mp4", "provider" to "")); assertEquals("", item().provider); assertEquals("https://resolve.invalid/a.mp4", item().url)
        assertEquals(1, probe.media.size)
    }

    @Test fun failedResolutionNull() {
        payload(p2Item(url = "")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        replyDirect(null); assertEquals("Unable to load stream", lastToast()); assertTrue(probe.media.isEmpty())
        assertEquals(160L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun failedResolutionEmpty() {
        payload(p2Item(url = "")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        replyDirect(mapOf("url" to "")); assertEquals("Unable to load stream", lastToast()); assertTrue(probe.media.isEmpty())
        assertEquals(160L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun failedResolutionWrongType() {
        payload(p2Item(url = "")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        replyDirect(mapOf("url" to 9)); assertEquals("Unable to load stream", lastToast()); assertTrue(probe.media.isEmpty())
        assertEquals(160L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun failedResolutionMalformed() {
        payload(p2Item(url = "")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item())
        replyDirect("not a map"); assertEquals("Unable to load stream", lastToast()); assertTrue(probe.media.isEmpty())
        assertEquals(160L, (field("nextOverlay") as View).animate().duration)
    }

    @Test fun nullResolutionUsesShuffleFailureBeforeToast() {
        var unavailable = 0; val attempt = attemptWith(unavailable = { unavailable++ }); set("pendingShufflePlayback", attempt)
        payload(p2Item(url = "")); call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, item()); replyDirect(null)
        assertNull(lastToast()); assertNull(field("pendingShufflePlayback")); pump(); assertEquals(1, unavailable)
    }

    @Test fun manualSuccessWritesCandidateUrlAndSelectedPayloadSlot() {
        payload(p2Item("Old"), p2Item("New", url = "").copy(index = 1)); set("currentIndex", 1)
        set("manualSourceSwitchIndex", 1); set("manualSourceSwitchSnapshot", ManualSourceSwitchSnapshot(0,0,"single",model().items.toList(),emptyMap(),emptyMap(),null,emptyMap(),null))
        call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 1, item(1)); replyDirect(mapOf("url" to "https://resolve.invalid/selected.mp4"))
        assertEquals("https://resolve.invalid/selected.mp4", field("manualSourceCandidateUrl")); assertEquals("https://example.test/a", item(0).url)
        assertEquals("https://resolve.invalid/selected.mp4", item(1).url)
    }
}
