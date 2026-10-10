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
internal class TvPlaybackItemStartCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun resumeManual() {
        payload(p2Item().copy(resumePositionMs = 43_210, traktProgressPercent = 62.0))
        set("isAutoAdvancing", false); set("resumeHoldTargetMs", 999L)
        play(suppressTrakt = false, suppressResume = false)
        assertEquals(43210L, field("pendingSeekMs")); assertEquals(62.0, field("pendingItemTraktPercent"))
        assertFalse(field("isAutoAdvancing") as Boolean); assertEquals(0L, field("resumeHoldTargetMs"))
        assertEquals(1, probe.media.size)
    }

    @Test fun resumeAuto() {
        payload(p2Item().copy(resumePositionMs = 43_210, traktProgressPercent = 62.0))
        set("isAutoAdvancing", true); set("resumeHoldTargetMs", 999L)
        play(suppressTrakt = false, suppressResume = false)
        assertEquals(0L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent"))
        assertFalse(field("isAutoAdvancing") as Boolean); assertEquals(0L, field("resumeHoldTargetMs"))
        assertEquals(1, probe.media.size)
    }

    @Test fun resumeTraktSuppressed() {
        payload(p2Item().copy(resumePositionMs = 43_210, traktProgressPercent = 62.0))
        set("isAutoAdvancing", false); set("resumeHoldTargetMs", 999L)
        play(suppressTrakt = true, suppressResume = false)
        assertEquals(43210L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent"))
        assertFalse(field("isAutoAdvancing") as Boolean); assertEquals(0L, field("resumeHoldTargetMs"))
        assertEquals(1, probe.media.size)
    }

    @Test fun resumeResumeSuppressed() {
        payload(p2Item().copy(resumePositionMs = 43_210, traktProgressPercent = 62.0))
        set("isAutoAdvancing", false); set("resumeHoldTargetMs", 999L)
        play(suppressTrakt = false, suppressResume = true)
        assertEquals(0L, field("pendingSeekMs")); assertEquals(0.0, field("pendingItemTraktPercent"))
        assertFalse(field("isAutoAdvancing") as Boolean); assertEquals(0L, field("resumeHoldTargetMs"))
        assertEquals(1, probe.media.size)
    }

    @Test fun defaultDispatcherUsesRealFalseAndNullArguments() {
        payload(p2Item().copy(resumePositionMs = 321L, traktProgressPercent = 45.0))
        playDefaults()
        assertEquals(321L, field("pendingSeekMs")); assertEquals(45.0, field("pendingItemTraktPercent"))
        assertNull(field("pendingShufflePlayback")); assertEquals(1, probe.media.size)
    }

    @Test fun sleepLatchAutomatic() {
        set("sleepStopLatched", true); set("isAutoAdvancing", true)
        play()
        assertEquals(true, field("sleepStopLatched"))
        assertFalse(field("isAutoAdvancing") as Boolean)
        assertEquals(0, probe.media.size)
        assertEquals(1, field("mediaPreparationGeneration"))
    }

    @Test fun sleepLatchManual() {
        set("sleepStopLatched", true); set("isAutoAdvancing", false)
        play()
        assertEquals(false, field("sleepStopLatched"))
        assertFalse(field("isAutoAdvancing") as Boolean)
        assertEquals(1, probe.media.size)
        assertEquals(1, field("mediaPreparationGeneration"))
    }

    @Test fun outOfRangeNegative() {
        set("pendingSeekMs", 123L); set("hasEverBeenReady", true); play(-1)
        assertTrue(probe.media.isEmpty()); assertEquals(0, field("currentIndex"))
        assertEquals(123L, field("pendingSeekMs")); assertTrue(field("hasEverBeenReady") as Boolean)
        assertEquals(1, field("mediaPreparationGeneration"))
    }

    @Test fun outOfRangeUpperBoundary() {
        set("pendingSeekMs", 123L); set("hasEverBeenReady", true); play(1)
        assertTrue(probe.media.isEmpty()); assertEquals(0, field("currentIndex"))
        assertEquals(123L, field("pendingSeekMs")); assertTrue(field("hasEverBeenReady") as Boolean)
        assertEquals(1, field("mediaPreparationGeneration"))
    }

    @Test fun missingPayloadStillInvalidatesPreparation() {
        set("payload", null); set("pendingShufflePlayback", attemptWith()); play()
        assertNull(field("pendingShufflePlayback")); assertEquals(1, field("mediaPreparationGeneration")); assertTrue(probe.media.isEmpty())
    }

    @Test fun staleAttemptReturnsBeforeAnyNavigationReset() {
        val old = attemptWith(); set("pendingShufflePlayback", old)
        val incoming = attemptWith(generation = 99); play(attempt = incoming)
        assertSame(old, field("pendingShufflePlayback")); assertEquals(0, field("mediaPreparationGeneration")); assertTrue(probe.media.isEmpty())
    }

    @Test fun newItemResetshasEverBeenReady() {
        set("hasEverBeenReady", true); play(); assertEquals(false, field("hasEverBeenReady"))
    }

    @Test fun newItemResetsmaxStableDurationMs() {
        set("maxStableDurationMs", 999L); play(); assertEquals(0L, field("maxStableDurationMs"))
    }

    @Test fun newItemResetslastRealPositionMs() {
        set("lastRealPositionMs", 999L); play(); assertEquals(0L, field("lastRealPositionMs"))
    }

    @Test fun newItemCancelsRetryAndSkipAndUpNextBeforePlayer() {
        set("isPikPakRetrying", true); set("activeSkipSegment", TvSkipSegment(TvSkipSegmentType.INTRO, 1_000, 5_000))
        set("upNextVisible", true); val retry = field("pikPakRetryId") as Int
        probe.onEvent = { if (it.startsWith("media:")) {
            assertFalse(field("isPikPakRetrying") as Boolean); assertNull(field("activeSkipSegment"))
            assertFalse(field("upNextVisible") as Boolean)
        } }
        play(); assertEquals(retry + 1, field("pikPakRetryId")); assertEquals(1, probe.media.size)
    }

    @Test fun selectionAndProtectedHeadersPrecedeMedia() {
        val incoming = p2Item("Incoming", "").copy(index = 1, httpHeaders = mapOf("Authorization" to "fixture"))
        payload(p2Item(), incoming); probe.onEvent = { if (it.startsWith("media:")) {
            assertEquals(1, field("currentIndex")); assertEquals(incoming.httpHeaders, (field("activeVodHeaders") as Pair<*, *>).second)
        } }; messenger.onSend = { r -> if(r.call.method=="requestTorrentStream") {
            assertEquals("headers selected before asynchronous resolution",incoming.httpHeaders,(field("activeVodHeaders") as Pair<*,*>).second)
            replyDirect(mapOf("url" to "https://headers.invalid/b.mp4"),r)
        } }; play(1); assertEquals("Incoming", title())
    }

    @Test fun restoreClosureReturnsOutgoingIndexHeadersAndControls() {
        val outgoing = p2Item("Outgoing", season = 1, episode = 1).copy(httpHeaders = mapOf("X-Old" to "old"))
        payload(outgoing, p2Item("Next", url = "", season = 1, episode = 2).copy(index = 1), type = "series")
        val attempt = attemptWith(); play(1, attempt = attempt)
        assertEquals(1, field("currentIndex")); assertEquals(1, attemptField(attempt, "navigation"))
        call("failShufflePlayback", emptyArray()); assertEquals(0, field("currentIndex"))
        assertEquals(outgoing.httpHeaders, (field("activeVodHeaders") as Pair<*, *>).second)
        assertEquals(View.GONE, (field("iptvPrevButton") as View).visibility)
    }

    @Test fun existingRestoreClosureIsNotOverwritten() {
        var restored = 0; val closure: () -> Unit = { restored++ }
        val attempt = attemptWith(restore = closure); payload(p2Item(url = "")); play(attempt = attempt)
        assertSame(closure, attemptField(attempt, "restorePreparation")); call("failShufflePlayback", emptyArray()); assertEquals(1, restored)
    }

    @Test fun blankUrlUsesResolverInsteadOfMedia() {
        payload(p2Item(url = " 	")); play()
        assertEquals(1, requests("requestTorrentStream").size); assertTrue(probe.media.isEmpty())
        assertEquals(mapOf("resumeId" to "resume", "itemId" to "item", "index" to 0), request("requestTorrentStream").call.arguments)
    }
}
