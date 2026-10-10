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
internal class TvPlaybackMimeCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun mimeReturnedIoRejectsNavigation() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        val a=attemptWith();
        TvPhase18ProbeServer().use { server ->
            var ready=0; discover(server.url,emptyMap()) { ready++ }; barrier.step()
            assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); server.release.countDown(); val continuation=barrier.next()
            assertEquals(1,field("mediaPreparationGeneration"));  set("mediaPreparationGeneration",99); continuation.run(); assertEquals(0,ready)
        }
    }

    @Test fun mimeReturnedIoRejectsSourceToken() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        val a=attemptWith();
        TvPhase18ProbeServer().use { server ->
            var ready=0; discover(server.url,emptyMap()) { ready++ }; barrier.step()
            assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); server.release.countDown(); val continuation=barrier.next()
            assertEquals(1,field("mediaPreparationGeneration"));  set("stremioResolutionToken",99); continuation.run(); assertEquals(0,ready)
        }
    }

    @Test fun mimeReturnedIoRejectsShuffleFinished() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        val a=attemptWith(); set("pendingShufflePlayback",a)
        TvPhase18ProbeServer().use { server ->
            var ready=0; discover(server.url,emptyMap()) { ready++ }; barrier.step()
            assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); server.release.countDown(); val continuation=barrier.next()
            assertEquals(1,field("mediaPreparationGeneration")); assertEquals(1,attemptField(a,"navigation")); setAttempt(a,"finished",true); continuation.run(); assertEquals(0,ready)
        }
    }

    @Test fun mimeReturnedIoRejectsFinishing() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        val a=attemptWith();
        TvPhase18ProbeServer().use { server ->
            var ready=0; discover(server.url,emptyMap()) { ready++ }; barrier.step()
            assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); server.release.countDown(); val continuation=barrier.next()
            assertEquals(1,field("mediaPreparationGeneration"));  finishing(true); continuation.run(); assertEquals(0,ready)
        }
    }

    @Test fun mimeReturnedIoRejectsDestroyed() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        val a=attemptWith();
        TvPhase18ProbeServer().use { server ->
            var ready=0; discover(server.url,emptyMap()) { ready++ }; barrier.step()
            assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); server.release.countDown(); val continuation=barrier.next()
            assertEquals(1,field("mediaPreparationGeneration"));  destroyed(true); continuation.run(); assertEquals(0,ready)
        }
    }

    @Test fun mimeReturnedIoRejectsSleep() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        val a=attemptWith();
        TvPhase18ProbeServer().use { server ->
            var ready=0; discover(server.url,emptyMap()) { ready++ }; barrier.step()
            assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); server.release.countDown(); val continuation=barrier.next()
            assertEquals(1,field("mediaPreparationGeneration"));  set("sleepStopLatched",true); continuation.run(); assertEquals(0,ready)
        }
    }

    @Test fun mimeReadsCurrentClientAtIoEvaluation() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        TvPhase18ProbeServer().use { server ->
            var ready:String?=null; discover(server.url,emptyMap()) { ready=it }
            set("protectedStreamClient",okhttp3.OkHttpClient.Builder().addInterceptor { chain -> chain.proceed(chain.request().newBuilder().header("X-Evaluation","IO").build()) }.build())
            barrier.step(); assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); assertTrue(server.headers.contains("X-Evaluation: IO")); server.release.countDown(); barrier.step(); assertEquals("application/x-mpegURL",ready)
        }
    }

    @Test fun mimeReentryRejectsMissingPayload() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        TvPhase18ProbeServer().use { server ->
            payload(p2Item(url=server.url).copy(httpHeaders=mapOf("X-Protected" to "fixture"))); start(); barrier.step(); assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
            server.release.countDown(); val continuation=barrier.next(); set("payload",null); continuation.run(); assertTrue(probe.media.isEmpty())
        }
    }

    @Test fun mimeReentryRejectsMissingSlot() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        TvPhase18ProbeServer().use { server ->
            payload(p2Item(url=server.url).copy(httpHeaders=mapOf("X-Protected" to "fixture"))); start(); barrier.step(); assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
            server.release.countDown(); val continuation=barrier.next(); model().items.clear(); continuation.run(); assertTrue(probe.media.isEmpty())
        }
    }

    @Test fun mimeReentryRejectsChangedUrl() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        TvPhase18ProbeServer().use { server ->
            payload(p2Item(url=server.url).copy(httpHeaders=mapOf("X-Protected" to "fixture"))); start(); barrier.step(); assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
            server.release.countDown(); val continuation=barrier.next(); model().items[0]=item().copy(url="https://different.invalid/b.mp4"); continuation.run(); assertTrue(probe.media.isEmpty())
        }
    }

    @Test fun mimeReentryPersistsDiscoveredTypeWithoutSecondProbe() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        TvPhase18ProbeServer().use { server ->
            payload(p2Item(url=server.url).copy(httpHeaders=mapOf("X-Protected" to "fixture"))); start(); assertTrue(probe.media.isEmpty()); barrier.step(); assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
            server.release.countDown(); barrier.step(); assertEquals("application/x-mpegURL",item().mimeType); assertEquals("application/x-mpegURL",probe.media.single().localConfiguration!!.mimeType); assertEquals(1,field("mediaPreparationGeneration"))
        }
    }

    @Test fun discoveryBypassIptv() {
        payload(p2Item(url="https://protected.invalid/no-extension").copy(httpHeaders=mapOf("X-P" to "p"),mimeType=null)); set("isIptvMode",true)
        start(discovered=false); assertEquals(1,probe.media.size); assertEquals(0,field("mediaPreparationGeneration"))
    }

    @Test fun discoveryBypassAlreadyDiscovered() {
        payload(p2Item(url="https://protected.invalid/no-extension").copy(httpHeaders=mapOf("X-P" to "p"),mimeType=null));
        start(discovered=true); assertEquals(1,probe.media.size); assertEquals(0,field("mediaPreparationGeneration"))
    }

    @Test fun discoveryBypassExplicitMime() {
        payload(p2Item(url="https://protected.invalid/no-extension").copy(httpHeaders=mapOf("X-P" to "p"),mimeType="video/mp4"));
        start(discovered=false); assertEquals(1,probe.media.size); assertEquals(0,field("mediaPreparationGeneration"))
    }

    @Test fun discoveryBypassNoHeaders() {
        payload(p2Item(url="https://protected.invalid/no-extension").copy(httpHeaders=emptyMap(),mimeType=null));
        start(discovered=false); assertEquals(1,probe.media.size); assertEquals(0,field("mediaPreparationGeneration"))
    }

    @Test fun startSleepGateFollowsProtectedHeaderWrite() {
        val value=p2Item(url="https://headers.invalid/a.mp4").copy(httpHeaders=mapOf("X-Night" to "night")); payload(value); set("sleepStopLatched",true); start()
        assertEquals(value.httpHeaders,(field("activeVodHeaders") as Pair<*,*>).second); assertTrue(probe.media.isEmpty())
    }

    @Test fun staleStartRestoresPreparationAndClearsPending() {
        var restored=0; val a=attemptWith(generation=1,restore={restored++}); set("pendingShufflePlayback",a); start()
        assertEquals(1,restored); assertNull(field("pendingShufflePlayback")); assertTrue(probe.media.isEmpty())
    }
}
