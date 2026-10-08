package com.debrify.app.tv

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvSourceSwitchMimeCharacterizationTest : TvPhase8OriginalTest() {
    private class ProbeServer : AutoCloseable {
        val server = ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress()).apply { soTimeout = 5000 }
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        var headers = ""; var failure: Throwable? = null
        val url = "http://127.0.0.1:${server.localPort}/protected"
        val thread = Thread {
            try { server.accept().use { socket ->
                socket.soTimeout = 5000
                val reader = socket.getInputStream().bufferedReader(); val lines = mutableListOf<String>()
                while (true) { val line = reader.readLine() ?: break; if (line.isEmpty()) break; lines.add(line) }
                headers = lines.joinToString("\n"); entered.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                socket.getOutputStream().write("HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray())
            } } catch (t: Throwable) { failure = t; entered.countDown() }
        }.apply { start() }
        override fun close() { release.countDown(); thread.join(5500); server.close(); assertFalse("bounded HEAD server exits", thread.isAlive); failure?.let { throw AssertionError("HEAD fixture failed", it) } }
    }
    private fun awaitCondition(check: () -> Boolean) {
        val end = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!check() && System.nanoTime() < end) { idle(); Thread.sleep(5) }
        idle(); assertTrue("async continuation reached main looper", check())
    }
    @Test fun protectedMimeProbeUsesHeadersThenRecursesOnceToApplyDiscoveredMime() {
        ProbeServer().use { server ->
            sources()[1] = source(1, headers = mapOf("X-Phase8" to "fixture"))
            direct(server.url); idle(); assertTrue(server.entered.await(5, TimeUnit.SECONDS)); assertTrue(probe.media.isEmpty())
            assertTrue(server.headers.startsWith("HEAD /protected")); assertTrue(server.headers.contains("X-Phase8: fixture"))
            server.release.countDown(); awaitCondition { probe.media.isNotEmpty() }
            assertEquals(1, probe.media.size); assertEquals("application/x-mpegURL", probe.media.single().localConfiguration!!.mimeType)
            assertEquals(server.url, model().items[0].url)
            assertEquals("discovered MIME persists in the payload", "application/x-mpegURL", model().items[0].mimeType)
        }
    }
    @Test fun tokenSupersessionDuringProtectedMimeProbeDiscardsLateApply() {
        ProbeServer().use { server ->
            sources()[1] = source(1, headers = mapOf("X-Phase8" to "fixture")); direct(server.url); idle()
            assertTrue(server.entered.await(5, TimeUnit.SECONDS)); set("stremioResolutionToken", (field("stremioResolutionToken") as Int) + 1)
            server.release.countDown(); server.thread.join(5000)
            // Drain the owning scope through a tail coroutine, after the IO probe
            // has returned and posted its continuation, without a timing guess.
            val scope = field("mediaPreparationScope") as kotlinx.coroutines.CoroutineScope
            awaitCondition { scope.coroutineContext[kotlinx.coroutines.Job]!!.children.none() }
            assertTrue(probe.media.isEmpty()); assertEquals(0, field("currentStremioSourceIndex"))
        }
    }
}
