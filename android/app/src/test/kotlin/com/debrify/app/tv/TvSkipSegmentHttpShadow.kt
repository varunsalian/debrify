package com.debrify.app.tv

import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** No production HTTP runs: missing responses fail closed and are observable. */
@Implements(className = "com.debrify.app.tv.SkipSegmentHttpClient", isInAndroidSdk = false)
class TvSkipSegmentHttpShadow {
    data class Response(val body: String? = """{"segments":{"intro":{"start_ms":1000,"end_ms":20000}}}""") {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val returned = CountDownLatch(1)
        @Volatile var endpoint: String? = null
        @Volatile var query: List<Pair<String, String>> = emptyList()
        @Volatile var thread: Thread? = null
    }

    @Implementation
    fun get(endpoint: String, query: List<Pair<String, String>>): String? {
        val response = responses.poll() ?: error("unplanned skip HTTP request: $endpoint")
        response.endpoint = endpoint; response.query = query; response.thread = Thread.currentThread()
        response.entered.countDown()
        check(response.release.await(10, TimeUnit.SECONDS)) { "test did not release skip response" }
        response.returned.countDown()
        return response.body
    }

    companion object { val responses = LinkedBlockingQueue<Response>() }
}
