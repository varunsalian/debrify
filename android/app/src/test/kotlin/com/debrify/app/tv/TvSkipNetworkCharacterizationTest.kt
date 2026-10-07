package com.debrify.app.tv

import kotlinx.coroutines.Job
import org.junit.Assert.*
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvSkipSegmentHttpShadow::class],
    instrumentedPackages = ["com.debrify.app.tv.SkipSegmentHttpClient"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSkipNetworkCharacterizationTest : TvPhase3OriginalTest() {
    private val pending = mutableListOf<TvSkipSegmentHttpShadow.Response>()
    @After fun releasePendingResponses() {
        pending.forEach { it.release.countDown() }
        TvSkipSegmentHttpShadow.responses.clear()
    }
    private fun request(duration: Long): Any = invoke("currentSkipSegmentRequest", duration)!!
    private fun begin(request: Any): TvSkipSegmentHttpShadow.Response {
        val response = TvSkipSegmentHttpShadow.Response()
        pending.add(response)
        TvSkipSegmentHttpShadow.responses.add(response)
        invoke("ensureSkipSegments", request)
        idle()
        assertTrue("IO request entered deterministic shadow", response.entered.await(5, TimeUnit.SECONDS))
        assertNotEquals(Thread.currentThread(), response.thread)
        return response
    }
    private fun complete(response: TvSkipSegmentHttpShadow.Response, job: Job) {
        response.release.countDown()
        assertTrue("IO response returned", response.returned.await(5, TimeUnit.SECONDS))
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (!job.isCompleted && System.nanoTime() < deadline) { idle(); Thread.yield() }
        assertTrue("production Main continuation completed", job.isCompleted)
        idle()
    }

    @Test fun deterministicHttpFixtureKeepsRealIoMainDispatchAndRequestArgumentsAcrossTwentyFetches() {
        bindViews()
        repeat(20) { index ->
            series(episode = index + 1, duration = 120_000L + index * 1000L)
            val request = request(120_000L + index * 1000L)
            val response = begin(request)
            val job = field("skipSegmentFetchJob") as Job
            assertNull("not published before latch release", field("loadedSkipSegmentKey"))
            assertEquals(listOf("imdb_id" to "tt12345", "season" to "0",
                "episode" to (index + 1).toString(), "duration" to (120 + index).toString()), response.query)
            complete(response, job)
            assertEquals("skipdb:tt12345:0:${index + 1}:${120 + index}", field("loadedSkipSegmentKey"))
            assertEquals(1, (field("skipSegments") as TvSkipSegments).intros.size)
            invoke("resetSkipSegmentState")
        }
        assertTrue(TvSkipSegmentHttpShadow.responses.isEmpty())
    }

    @Test fun boundedCacheEvictsOldestOnlyAtSixtyFourAndPublishesTheCurrentResponse() {
        bindViews(); series(duration = 120_000L)
        @Suppress("UNCHECKED_CAST") val cache = field("skipSegmentCache") as LinkedHashMap<String, TvSkipSegments>
        repeat(64) { cache["old-$it"] = TvSkipSegments.EMPTY }
        val req = request(120_000L); val response = begin(req); val job = field("skipSegmentFetchJob") as Job
        complete(response, job)
        assertEquals(64, cache.size); assertFalse(cache.containsKey("old-0")); assertTrue(cache.containsKey("old-1"))
        assertTrue(cache.containsKey("skipdb:tt12345:0:1:120"))
    }

    @Test fun providerChangeWhileIoIsBlockedRejectsTheOldResult() {
        bindViews(); series(duration = 120_000L)
        val response = begin(request(120_000L)); val job = field("skipSegmentFetchJob") as Job
        set("skipSegmentProviderId", TvSkipSegmentClients.INTRO_DB)
        complete(response, job)
        assertNull("old provider cannot publish", field("loadedSkipSegmentKey"))
        assertTrue((field("skipSegmentCache") as Map<*, *>).isEmpty())
    }

    @Test fun replacementPlayerDurationWhileIoIsBlockedRejectsTheOldResult() {
        bindViews(); series(duration = 120_000L)
        val response = begin(request(120_000L)); val job = field("skipSegmentFetchJob") as Job
        set("player", PlayerProbe(duration = 121_000L).player)
        complete(response, job)
        assertNull("old duration cannot publish", field("loadedSkipSegmentKey"))
        assertTrue((field("skipSegmentCache") as Map<*, *>).isEmpty())
    }

    @Test fun supersededGenerationCannotPublishEvenWhenRequestIdentityStillMatches() {
        bindViews(); series(duration = 120_000L)
        val response = begin(request(120_000L)); val job = field("skipSegmentFetchJob") as Job
        set("skipSegmentFetchGeneration", (field("skipSegmentFetchGeneration") as Int) + 1)
        complete(response, job)
        assertNull("superseded generation cannot publish", field("loadedSkipSegmentKey"))
    }

    @Test fun sameLoadingRequestIsDeduplicatedAndCacheHitPublishesWithoutHttp() {
        bindViews(); series(duration = 120_000L)
        val req = request(120_000L); val response = begin(req); val job = field("skipSegmentFetchJob") as Job
        invoke("ensureSkipSegments", req); assertSame(job, field("skipSegmentFetchJob"))
        complete(response, job)
        val result = field("skipSegments")
        invoke("resetSkipSegmentState"); invoke("ensureSkipSegments", req)
        assertSame(result, field("skipSegments")); assertNull(field("skipSegmentFetchJob"))
        assertEquals("skipdb:tt12345:0:1:120", field("loadedSkipSegmentKey"))
    }

    @Test fun resetCancelsBlockedFetchClearsUiIdentityAndPreventsLatePublication() {
        bindViews(); series(duration = 120_000L)
        val response = begin(request(120_000L)); val job = field("skipSegmentFetchJob") as Job
        val generation = field("skipSegmentFetchGeneration") as Int
        invoke("resetSkipSegmentState")
        assertTrue(job.isCancelled); assertEquals(generation + 1, field("skipSegmentFetchGeneration"))
        assertNull(field("skipSegmentFetchJob")); assertNull(field("loadingSkipSegmentKey"))
        assertNull(field("loadedSkipSegmentKey")); assertNull(field("activeSkipSegment")); assertNull(field("skipFocusOfferedKey"))
        complete(response, job); assertSame(TvSkipSegments.EMPTY, field("skipSegments"))
    }
}
