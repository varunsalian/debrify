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
internal class TvPlaybackStartLifecycleCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun destroyCancelsScopeBeforeGenerationBeforeBrowserAndPlayer() {
        val job=pendingScope().coroutineContext[kotlinx.coroutines.Job]!!; val before=field("mediaPreparationGeneration") as Int
        var generationAtCancel=-1; job.invokeOnCompletion { generationAtCancel=field("mediaPreparationGeneration") as Int }
        var observed=false; probe.onEvent={ if(it=="release") { observed=true; assertTrue(job.isCancelled); assertEquals(before+1,field("mediaPreparationGeneration")); assertNull(field("sourceBrowser")) } }
        lifecycle.pause().stop().destroy(); assertTrue(observed); assertEquals(before,generationAtCancel); assertEquals(before+1,field("mediaPreparationGeneration")); assertTrue(job.isCancelled)
    }

    @Test fun destroyRemovesShufflePostsAndPolls() {
        var unavailable=0; val a=attemptWith(unavailable={unavailable++}); call("watchShufflePlayback",arrayOf(attemptType),a)
        wholeShow(ShuffleEpisode(1,3)); set("episodeFetchInFlight",true); shuffle(); assertEquals(0,field("queuedShuffleGeneration"))
        lifecycle.pause().stop().destroy(); pump(15_050); assertEquals(0,unavailable); assertTrue(requests("requestEpisodeFetch").isEmpty()); assertEquals(false,attemptField(a,"finished"))
    }

    @Test fun destroyInvalidatesAlreadyReturnedMimeContinuation() {
        val barrier=TvPhase18MainBarrier(); pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.cancel(); set("mediaPreparationScope",barrier.scope())
        TvPhase18ProbeServer().use { server -> var ready=0; discover(server.url,emptyMap()) { ready++ }; barrier.step(); assertTrue(server.entered.await(5,java.util.concurrent.TimeUnit.SECONDS)); server.release.countDown(); val continuation=barrier.next()
        lifecycle.pause().stop().destroy(); continuation.run(); assertEquals(0,ready); assertEquals(2,field("mediaPreparationGeneration")); assertTrue(pendingScope().coroutineContext[kotlinx.coroutines.Job]!!.isCancelled)
        }
    }
}
