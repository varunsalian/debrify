package com.debrify.app.diagnostics

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Never runs disk work on the caller or grows without bound under log storms. */
internal class DiagnosticWorkQueue(capacity: Int = 256) {
    private val executor = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(capacity),
        { runnable -> Thread(runnable, "debrify-diagnostics").apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )
    val dropped = AtomicLong()

    fun submit(action: () -> Unit): Boolean = try {
        executor.execute(action)
        true
    } catch (_: RejectedExecutionException) {
        dropped.incrementAndGet()
        false
    }

    fun shutdown() = executor.shutdown()
}
