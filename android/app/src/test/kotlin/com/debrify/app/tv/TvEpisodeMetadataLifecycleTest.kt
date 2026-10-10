package com.debrify.app.tv

import android.content.BroadcastReceiver
import android.content.Intent
import android.os.Handler
import kotlinx.coroutines.Job
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase19ReceiverShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpisodeMetadataLifecycleTest : TvPhase19MetadataTest() {
    @org.junit.Before fun resetReceiverObserver() { TvPhase19ReceiverShadow.resetFixture() }
    private fun destroyWithWitness(throws: Boolean) {
        val receiver = field("metadataUpdateReceiver") as BroadcastReceiver
        val events = mutableListOf<String>()
        val upNext = field("upNextHandler") as Handler
        val pending = Runnable { fail("Up Next callback must be removed") }; upNext.postDelayed(pending, 10_000)
        TvPhase19ReceiverShadow.failUnregister = throws
        TvPhase19ReceiverShadow.unregister = {
            if (it === receiver) {
                events.add("unregister")
                assertFalse("Up Next cancelled before receiver", TvPlaylistUiQueue.pending(upNext, pending))
                assertSame("receiver still held at unregister", receiver, field("metadataUpdateReceiver"))
                assertTrue("subtitle scope alive at unregister", (field("subtitleScope") as kotlinx.coroutines.CoroutineScope).coroutineContext[Job]!!.isActive)
            }
        }
        (field("subtitleScope") as kotlinx.coroutines.CoroutineScope).coroutineContext[Job]!!.invokeOnCompletion {
            events.add("subtitle cancel"); assertNull("receiver cleared before subtitle cancel", field("metadataUpdateReceiver"))
        }
        destroyNow()
        assertEquals(listOf("unregister", "subtitle cancel"), events)
        assertNull(field("metadataUpdateReceiver"))
        val receivers = org.robolectric.Shadows.shadowOf(activity.application).getReceiversForIntent(Intent("com.debrify.app.tv.UPDATE_EPISODE_METADATA"))
        assertFalse("platform receiver removed", receivers.contains(receiver))
    }
    @Test fun destroyUnregistersAndNullsReceiverBetweenUpNextAndSubtitleCancellation() = destroyWithWitness(false)
    @Test fun throwingUnregisterStillNullsAndCancelsSubtitleScope() = destroyWithWitness(true)
    @Test fun postedRequestIntentionallySurvivesDestroy() {
        call("requestMetadataFromFlutter", emptyArray()); assertTrue(requests("requestEpisodeMetadata").isEmpty())
        destroyNow(); step(0); assertEquals("uncancelled Handler post preserved", 1, requests("requestEpisodeMetadata").size)
    }
    @Test fun destroyedReceiverCannotConsumeLaterBroadcast() {
        destroyNow(); activity.sendBroadcast(Intent("com.debrify.app.tv.UPDATE_EPISODE_METADATA").putExtra("metadataUpdates", "[{\"originalIndex\":0,\"title\":\"Late\"}]")); idle()
        assertEquals("Original", first.title)
    }
}
