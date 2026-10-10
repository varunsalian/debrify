package com.debrify.app.tv

import org.junit.Assert.*
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Header-only local origin; every wait/socket is bounded and closed. */
internal class TvPhase18ProbeServer : AutoCloseable {
    private val server = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).apply { soTimeout = 5000 }
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    @Volatile var headers = ""
    @Volatile private var failure: Throwable? = null
    val url = "http://127.0.0.1:${server.localPort}/protected"
    private val thread = Thread {
        try {
            server.accept().use { socket ->
                socket.soTimeout = 5000
                val lines = mutableListOf<String>()
                val input = socket.getInputStream().bufferedReader()
                while (true) {
                    val line = input.readLine() ?: break
                    if (line.isEmpty()) break
                    lines.add(line)
                }
                headers = lines.joinToString("\n")
                entered.countDown()
                check(release.await(5, TimeUnit.SECONDS)) { "bounded origin release" }
                socket.getOutputStream().write(("HTTP/1.1 200 OK\r\n" +
                    "Content-Type: application/vnd.apple.mpegurl\r\nContent-Length: 0\r\n" +
                    "Connection: close\r\n\r\n").toByteArray())
            }
        } catch (error: Throwable) { failure = error; entered.countDown() }
    }.apply { name = "phase18-mime-origin"; start() }
    override fun close() {
        release.countDown(); thread.join(5500); server.close()
        assertFalse("bounded HEAD origin exits", thread.isAlive)
        failure?.let { throw AssertionError("HEAD fixture failed", it) }
    }
}
