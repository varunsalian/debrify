package com.debrify.app.tv

import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPlaybackStartPrerequisiteTest : TvPhase18OriginalTest() {
    @Test fun realResolveObservesInlineBinaryReply() = binaryReply("inline")
    @Test fun realResolveObservesQueuedBinaryReply() = binaryReply("queued")
    @Test fun realResolvePinsOffLooperWorkerReplyQuirk() = binaryReply("worker")
    private fun binaryReply(timing: String) {
            val outgoing = p2Item("Waiting", url = "", provider = "Original")
            payload(outgoing); clearObservations()
            val value = mapOf("url" to "https://phase18.invalid/$timing.mp4", "provider" to "Resolved")
            messenger.onSend = if (timing == "inline") ({ request ->
                if (request.call.method == "requestTorrentStream") replyDirect(value, request)
            }) else null
            call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, outgoing)
            if (timing != "inline") assertTrue("asynchronous transport has not started media", probe.media.isEmpty())
            if (timing == "queued") { android.os.Handler(android.os.Looper.getMainLooper()).post { replyDirect(value) }; pump(1) }
            if (timing == "worker") {
                workerReply("success", value)
                assertEquals("worker callback reaches resolving UI before payload replacement", "", item().url)
                assertTrue("original off-looper animation exception is swallowed by MethodChannel", org.robolectric.shadows.ShadowLog.getLogs().any {
                    it.tag.startsWith("MethodChannel") && it.throwable?.message == "Animators may only be run on Looper threads"
                })
                assertTrue(probe.media.isEmpty())
                return
            }
            assertEquals("original callback accepts $timing reply; gen=${field("mediaPreparationGeneration")} allLogs=${org.robolectric.shadows.ShadowLog.getLogs().map { it.tag + ":" + it.msg + ":" + it.throwable?.stackTraceToString() }}", "https://phase18.invalid/$timing.mp4", item().url)
            assertEquals("provider survives $timing binary decoding", "Resolved", item().provider)
            assertEquals("one original media start for $timing", 1, probe.media.size)
            assertEquals(item().url, probe.media.single().localConfiguration!!.uri.toString())
            assertEquals("accepted reply schedules resolving fade-out", 160L, (field("nextOverlay") as android.view.View).animate().duration)
        messenger.onSend = null
    }

    @Test fun originalMimeCoroutineCanPauseAfterIoBeforeItsMainGuard() {
        val barrier = TvPhase18MainBarrier()
        pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel()
        set("mediaPreparationScope", barrier.scope())
        TvPhase18ProbeServer().use { server ->
            val values = mutableListOf<String?>()
            val generation = field("mediaPreparationGeneration") as Int
            discover(server.url, mapOf("X-Phase18" to "fixture")) { values.add(it) }
            assertTrue("launch remains queued until Main is stepped", values.isEmpty())
            barrier.step()
            assertTrue("real bounded IO HEAD entered", server.entered.await(5, TimeUnit.SECONDS))
            assertTrue(server.headers.startsWith("HEAD /protected"))
            assertTrue(server.headers.contains("X-Phase18: fixture"))
            server.release.countDown()
            val continuation = barrier.next()
            assertTrue("IO returned but original guard/ready are still queued", values.isEmpty())
            assertEquals(generation + 1, field("mediaPreparationGeneration"))
            continuation.run()
            assertEquals(listOf("application/x-mpegURL"), values)
            assertTrue(pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.children.none())
        }
    }

    @Test fun originalPlayerProbeDistinguishesMergedPlainMimeAndPlayIntent() {
        val merged = p2Item().copy(hdVideoUrl = "https://phase18.invalid/video.mp4", audioUrl = "https://phase18.invalid/audio.mp4")
        payload(merged)
        directItem()
        assertEquals(listOf("merged", "prepare", "playWhenReady:true", "play"), probe.events)
        assertTrue(probe.media.isEmpty())
        clearObservations()
        val plain = p2Item("Plain", season = 2, episode = 4).copy(mimeType = "video/mp4", description = "Description")
        payload(plain); readiness().onReady(); directItem()
        assertEquals(listOf("media:https://example.test/a", "prepare", "playWhenReady:true", "play"), probe.events)
        assertEquals("video/mp4", probe.media.single().localConfiguration!!.mimeType)
        assertEquals("Plain", probe.media.single().mediaMetadata.title.toString())
        assertEquals("S02E04", probe.media.single().mediaMetadata.artist.toString())
        assertEquals("Description", probe.media.single().mediaMetadata.description.toString())
        assertFalse(readiness().canSelect(true))
    }

    @Test fun originalRandomDialogRunsItsRealChoiceCallback() {
        payload(p2Item("First"), p2Item("Second").copy(index = 1))
        set("continuousShuffleEnabled", true)
        dockCall("showRandomPlaybackDialog")
        val dialog = ShadowDialog.getLatestDialog() as AlertDialog
        assertEquals("Play Random Once", dialog.listView.adapter.getItem(0))
        assertEquals("Turn Off Continuous Shuffle", dialog.listView.adapter.getItem(1))
        val before = field("showShuffleGeneration") as Int
        dialog.listView.performItemClick(null, 0, 0)
        assertFalse(field("continuousShuffleEnabled") as Boolean)
        assertEquals(before + 1, field("showShuffleGeneration"))
        assertEquals(1, field("currentIndex"))
        assertEquals(1, probe.media.size)
    }
    @Test fun unseededShuffleIsObservableThroughSeededBagAndCycleInvariants() {
        payload(p2Item("0"), p2Item("1").copy(index = 1), p2Item("2").copy(index = 2), p2Item("3").copy(index = 3))
        val bag = field("shuffleBag") as MutableList<Int>
        bag.addAll(listOf(-1, 0, 1, 2))
        val first = call("pickShuffleIndex", emptyArray()) as Int
        assertEquals("explicit bag seed gives an observable pop", 2, first)
        assertEquals(listOf(1), bag)
        assertEquals(1, call("pickShuffleIndex", emptyArray()))
        val cycle = (1..3).map { call("pickShuffleIndex", emptyArray()) as Int }
        assertEquals("fresh unseeded cycle exhausts all noncurrent identities", setOf(1, 2, 3), cycle.toSet())
        assertTrue("no repeat until seeded/fresh bag exhaustion", bag.isEmpty())
    }
}
