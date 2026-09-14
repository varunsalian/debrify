package com.debrify.app.diagnostics

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class DiagnosticWorkQueueTest {
    @Test fun saturationDropsWorkWithoutRunningOnCallerAndRecovers() {
        val queue = DiagnosticWorkQueue(2)
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(2)
        try {
            assertTrue(queue.submit { started.countDown(); release.await(5, TimeUnit.SECONDS) })
            assertTrue(started.await(5, TimeUnit.SECONDS))
            repeat(2) { assertTrue(queue.submit { finished.countDown() }) }
            var ranRejected = false
            assertFalse(queue.submit { ranRejected = true })
            assertFalse(ranRejected)
            assertEquals(1L, queue.dropped.get())
            release.countDown()
            assertTrue(finished.await(5, TimeUnit.SECONDS))
            val barrier = CountDownLatch(1)
            assertTrue(queue.submit { barrier.countDown() })
            assertTrue(barrier.await(5, TimeUnit.SECONDS))
        } finally {
            release.countDown()
            queue.shutdown()
        }
    }
}
