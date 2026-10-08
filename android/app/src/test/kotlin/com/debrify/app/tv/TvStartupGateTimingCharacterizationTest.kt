package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.exoplayer.ExoPlaybackException
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStartupGateTimingCharacterizationTest : TvPhase9OriginalTest() {
    @Test fun bufferingWatchdogRechecksAtThreeSecondsAndFailsAt45SecondCap() {
        buffered = 1; begin(); val timeout = field("startupFailoverTimeout")
        advance(12_000); assertFalse(activity.isFinishing); assertSame(timeout, field("startupFailoverTimeout"))
        repeat(10) { advance(3_000) }; advance(2_999); assertFalse("buffering source still has grace at 44999", activity.isFinishing)
        advance(1); assertTrue("45 second cap rejects despite data", activity.isFinishing)
        assertEquals("timeout", requestMap("startupSourceFailed")["reason"])
    }

    @Test fun pikpakWatchdogExtendsUntilExactly120SecondsEvenWithoutBufferData() {
        model().items[0] = model().items[0].copy(provider = "pikpak"); begin()
        advance(12_000); repeat(35) { advance(3_000) }; advance(2_999); assertFalse(activity.isFinishing)
        advance(1); assertTrue("PikPak cap is 120000 ms " + debugState(), activity.isFinishing)
    }

    @Test fun manualWatchdogDoesNotGrantOutgoingPlayerGraceUntilMediaWasReplaced() {
        buffered = 1; manual(); advance(11_999); assertNotNull(field("manualSourceSwitchSnapshot"))
        advance(1); assertNull("outgoing buffered data cannot extend candidate", field("manualSourceSwitchSnapshot"))
        assertFalse(activity.isFinishing); assertEquals("This source is unavailable — choose another source", pill().text.toString())
    }

    @Test fun manualReplacedBufferingCandidateGetsSame45SecondBound() {
        buffered = 1; manual(); set("manualSourceMediaReplaced", true)
        advance(12_000); repeat(10) { advance(3_000) }; advance(2_999); assertNotNull(field("manualSourceSwitchSnapshot"))
        advance(1); assertNull(field("manualSourceSwitchSnapshot")); assertEquals(true, field("manualSourceRestoreInProgress"))
    }

    private fun cold() {
        model().items[0] = model().items[0].copy(provider = "pikpak")
        probe.error = ExoPlaybackException.createForSource(IOException("cold"), PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)
    }
    private fun reprepare(retry: Int? = null) = call("schedulePikPakGateReprepare", arrayOf(boxedIntType), retry)
    @Test fun reprepareWaitsFourSecondsIsSinglePendingAndClearsItsIdentityBeforePlayerCalls() {
        cold(); begin(); reprepare(); val callback = field("pikPakGateReprepare")
        reprepare(); assertSame(callback, field("pikPakGateReprepare"))
        probe.onEvent = { if (it == "prepare") assertNull("clear before invoking player", field("pikPakGateReprepare")) }
        advance(3_999); assertFalse(probe.events.contains("prepare")); advance(1)
        assertEquals(listOf("prepare", "play"), probe.events.filter { it in listOf("prepare", "play") })
        assertNull(field("pikPakGateReprepare"))
    }

    @Test fun reprepareReadsReplacementPlayerRetryAndMediaGenerationAtFireTime() {
        cold(); begin()
        for (guard in listOf("player", "pikPakRetryId", "mediaPreparationGeneration")) {
            set("player", gatePlayer); reprepare()
            when (guard) {
                "player" -> set("player", probe.player)
                else -> set(guard, (field(guard) as Int) + 1)
            }
            advance(5_000)
            assertFalse("live $guard invalidates captured request", probe.events.contains("prepare"))
            assertNull(field("pikPakGateReprepare"))
        }
    }

    @Test fun reprepareRequiresGateOrMatchingLiveChannelRetryAndStillPikpakError() {
        cold(); reprepare(); advance(5_000); assertFalse(probe.events.contains("prepare"))
        reprepare(field("pikPakRetryId") as Int); advance(5_000); assertFalse("matching id requires channel mode", probe.events.contains("prepare"))
        set("isStremioTvMode", true)
        reprepare((field("pikPakRetryId") as Int) + 1); advance(5_000); assertFalse(probe.events.contains("prepare"))
        reprepare(field("pikPakRetryId") as Int); advance(5_000); assertTrue(probe.events.contains("prepare"))
        probe.events.clear(); probe.error = null; reprepare(field("pikPakRetryId") as Int)
        advance(5_000); assertFalse("error recovered before callback", probe.events.contains("prepare"))
        cold(); reprepare(field("pikPakRetryId") as Int); model().items[0] = model().items[0].copy(provider = "realdebrid")
        advance(5_000); assertFalse("replacement item is not PikPak", probe.events.contains("prepare"))
    }

    @Test fun reprepareDropsFinishingActivityAtFireTime() {
        cold(); begin(); reprepare(); activity.finish(); advance(5_000)
        assertFalse("finishing host cannot be re-prepared", probe.events.contains("prepare"))
    }

    @Test fun supersededStartupResolveIsDiscardedBeforePayloadOrPlayerChanges() {
        begin(2); lazyResolve(); set("startupFailoverGeneration", (field("startupFailoverGeneration") as Int) + 1)
        val item = model().items[0]; lazyReply(mapOf("url" to "https://gate.invalid/stale.mp4"))
        assertSame(item, model().items[0]); assertFalse(probe.events.contains("prepare"))
        assertTrue(debugState(), org.robolectric.shadows.ShadowLog.getLogs().any { it.msg.contains("reason=stale_generation") })
    }

    @Test fun supersededManualResolveIsDiscardedBeforePayloadOrPlayerChanges() {
        manual(); lazyResolve(); set("stremioResolutionToken", (field("stremioResolutionToken") as Int) + 1)
        val item = model().items[0]; lazyReply(mapOf("url" to "https://gate.invalid/stale-manual.mp4"))
        assertSame(item, model().items[0]); assertFalse(probe.events.contains("prepare"))
        assertTrue(debugState(), org.robolectric.shadows.ShadowLog.getLogs().any { it.msg.contains("reason=stale_manual_token") })
    }

    @Test fun emptyInitialResolveRejectsThroughStartupGateAndPreservesExactReason() {
        begin(); lazyResolve(); lazyReply(emptyMap<String, Any?>())
        assertTrue(debugState(), activity.isFinishing); assertEquals("initial-resolve", requestMap("startupSourceFailed")["reason"])
    }

    @Test fun destroySnapshotsBeforeGateClearCancelsCallbacksInOrderAndSendsFlagsAfterClear() {
        val names = listOf("startupFailoverTimeout", "startupCommitCheck", "manualSourceSwitchTimeout", "manualSourceCommitCheck", "pikPakGateReprepare")
        val fired = mutableListOf<String>()
        val callbacks = names.associateWith { Runnable { fired.add(it); fail("late:$it") } }
        val oldHandler = handler; oldHandler.removeCallbacksAndMessages(null)
        val trace = Handler(Looper.getMainLooper())
        assertEquals("fifteen teardown statements retain their compiled sequence", listOf(
            "remove", "startupFailoverTimeout", "remove", "startupCommitCheck", "remove", "manualSourceSwitchTimeout",
            "remove", "manualSourceCommitCheck", "remove", "pikPakGateReprepare", "manualSourceSwitchSnapshot",
            "manualSourceSwitchIndex", "manualSourceRestoreInProgress", "startupFailoverGeneration", "startupFailoverCursor"),
            TvPhase9BytecodeAccess.teardown(activity.javaClass))
        lifecycle.pause().stop()
        set("progressHandler", trace); set("startupFailoverGeneration", 7)
        cursor(committed = true); manual(); set("manualSourceRestoreInProgress", true)
        // Snapshot remains gated before cleanup: clearing it early would emit progress.
        for ((name, r) in callbacks) { set(name, r); trace.postDelayed(r, 100) }
        trace.postDelayed({ fired.add("untracked-recovery-fallback") }, 100)
        trace.post { fired.add("untracked-missing-source") }
        set("startupSourcesExhausted", true); set("startupRecoveryConsumed", true)
        messenger.onSend = { if (it.call.method == "torrentPlaybackFinished") {
            names.forEach { assertNull(field(it)) }; assertNull(field("startupFailoverCursor"))
            assertEquals(false, field("manualSourceRestoreInProgress"))
        } }
        // Remove manual's obsolete timeout; it is not one of the five owned identities above.
        messenger.requests.clear()
        lifecycle.destroy(); set("progressHandler", oldHandler)
        names.forEach { assertNull(field(it)) }
        assertNull(field("manualSourceSwitchSnapshot")); assertNull(field("manualSourceSwitchIndex"))
        assertEquals(false, field("manualSourceRestoreInProgress"))
        assertEquals(8, field("startupFailoverGeneration")); assertNull(field("startupFailoverCursor"))
        advance(200); assertTrue("wholesale clear retires untracked posts", fired.isEmpty())
        assertTrue("snapshot before gate clears remains suppressed", requests("torrentPlaybackProgress").isEmpty())
        assertEquals(mapOf("sourcePersistenceSessionId" to field("sourcePersistenceSessionId"),
            "startupSourcesExhausted" to true, "startupRecoveryConsumed" to true), requestMap("torrentPlaybackFinished"))
    }

    @Test fun destroyWholesalelyRemovesActualUntrackedRecoveryFallback() {
        sources().clear(); sources().add(source(0, "https://gate.invalid/saved"))
        set("movieMoreSources", true); set("startupRecoveryAvailable", true); begin(3); fail("saved")
        assertEquals(true, field("startupRecoveryFetching"))
        assertTrue("actual 30 s fallback is queued on borrowed handler", handler.hasMessages(0))
        lifecycle.pause().stop().destroy()
        assertFalse("whole-handler clear removes recovery fallback", handler.hasMessages(0))
        advance(30_000); assertEquals(true, field("startupRecoveryFetching"))
    }

    @Test fun missingSourcePostIsDeferredPastDispatchGuardAndRemovedByDestroy() {
        val flaky = object : ArrayList<StremioSource>() {
            override fun get(index: Int): StremioSource {
                val source = super.get(index)
                if (index == 1 && Thread.currentThread().stackTrace.any { TvPlayerOriginalAccess.isStartupArm(it) }) {
                    removeAt(index)
                }
                return source
            }
        }
        flaky.addAll(sources()); set("stremioSources", flaky)
        begin(2); fail("first")
        assertEquals(1, selected()); assertEquals(false, field("startupFailoverDispatching"))
        assertEquals("unreachable missing-row post is queued, not recursively swallowed", 1, immediateCallbacks())
        assertFalse(activity.isFinishing)
        lifecycle.pause().stop().destroy()
        assertFalse("whole-handler clear removes untracked missing-source post", handler.hasMessages(0))
        advance(1); assertEquals(listOf("first"), requests("startupSourceFailed").map { (it.call.arguments as Map<*, *>)["reason"] })
    }

    @Test fun destroyInvalidatesInFlightInitialResolveBeforeLateCallback() {
        begin(); lazyResolve(); val generation = field("startupFailoverGeneration") as Int
        val item = model().items[0]; lifecycle.pause().stop().destroy()
        assertEquals(generation + 1, field("startupFailoverGeneration"))
        lazyReply(mapOf("url" to "https://gate.invalid/after-destroy"))
        assertSame(item, model().items[0]); assertFalse(probe.events.contains("prepare"))
    }
}
