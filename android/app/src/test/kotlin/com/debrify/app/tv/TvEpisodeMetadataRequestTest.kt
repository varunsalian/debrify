package com.debrify.app.tv

import android.content.Context
import com.debrify.app.MainActivity
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], shadows = [TvPhase19ReceiverShadow::class, TvPhase19ChannelLookupShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpisodeMetadataRequestTest : TvPhase5OriginalTest() {
    @org.junit.Before fun resetReceiverObserver() { TvPhase19ReceiverShadow.resetFixture(); TvPhase19ChannelLookupShadow.fail = false; org.robolectric.shadows.ShadowLog.clear() }
    @org.junit.After fun restoreChannelLookup() { TvPhase19ChannelLookupShadow.fail = false }
    private fun logged(text: String, tag: String = "TVMazeUpdate") = assertTrue("diagnostic: $text",
        org.robolectric.shadows.ShadowLog.getLogsForTag(tag).any { it.msg == text })
    private fun setupReceiver() = call("setupMetadataReceiver", emptyArray())
    private fun request() = call("requestMetadataFromFlutter", emptyArray())
    private fun registered(flags: Int) {
        val registration = TvPhase19ReceiverShadow.registrations.last()
        assertSame(field("metadataUpdateReceiver"), registration.receiver)
        assertEquals(listOf("com.debrify.app.tv.UPDATE_EPISODE_METADATA"), List(registration.filter.countActions()) { registration.filter.getAction(it) })
        assertEquals("platform registration flags", flags, registration.flags)
    }
    @Test fun pre33RegistersThenPostsSeriesRequestWithNullArguments() {
        movie("series"); setupReceiver(); registered(0)
        logged("Metadata update receiver registered", "AndroidTvPlayer")
        logged("requestMetadataFromFlutter CALLED"); logged("Invoking requestEpisodeMetadata on method channel")
        assertTrue("request remains posted", requests("requestEpisodeMetadata").isEmpty())
        messenger.onSend = { assertNotNull("receiver assigned before Flutter request", field("metadataUpdateReceiver")) }
        idle(); val request = requests("requestEpisodeMetadata").single(); assertNull(request.call.arguments)
        logged("requestEpisodeMetadata invoked successfully")
        activity.unregisterReceiver(field("metadataUpdateReceiver") as android.content.BroadcastReceiver)
        set("metadataUpdateReceiver", null)
    }
    @Test @Config(sdk = [33]) fun tiramisuReceiverIsNotExported() {
        movie("series"); setupReceiver(); registered(Context.RECEIVER_NOT_EXPORTED); idle()
        assertEquals(1, requests("requestEpisodeMetadata").size)
        activity.unregisterReceiver(field("metadataUpdateReceiver") as android.content.BroadcastReceiver); set("metadataUpdateReceiver", null)
    }
    @Test fun movieRegistersWithoutRequestingMetadata() {
        movie("movie"); setupReceiver(); registered(0); idle(); assertTrue(messenger.requests.isEmpty())
        activity.unregisterReceiver(field("metadataUpdateReceiver") as android.content.BroadcastReceiver); set("metadataUpdateReceiver", null)
    }
    @Test fun nullPayloadNullChannelAndMixedCaseSeriesDoNotRequest() {
        set("payload", null); request(); idle(); assertTrue(messenger.requests.isEmpty())
        movie("SeRiEs"); request(); idle(); assertTrue(messenger.requests.isEmpty()); logged("Not requesting metadata - contentType=SeRiEs")
        movie("series"); MainActivity.setAndroidTvPlayerChannel(null); request(); idle(); assertTrue(messenger.requests.isEmpty()); logged("Method channel is null, cannot request metadata")
    }
    @Test fun workerRequestUsesCapturedChannelAndRunsOnMainLater() {
        movie("series"); val failures = java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val worker = Thread { try { request() } catch (error: Throwable) { failures.set(error) } }
        worker.start(); worker.join(5000); assertFalse(worker.isAlive); assertNull(failures.get()); assertTrue(messenger.requests.isEmpty())
        val replacement = TvPlayerRecordingMessenger(); MainActivity.setAndroidTvPlayerChannel(MethodChannel(replacement, "p19-replacement"))
        messenger.onSend = { assertEquals(android.os.Looper.getMainLooper().thread, Thread.currentThread()) }
        idle(); assertEquals(1, requests("requestEpisodeMetadata").size); assertTrue(replacement.requests.isEmpty())
    }
    @Test fun invokeExceptionIsCaughtInsidePostedRequest() {
        movie("series"); messenger.throwOnSend = true; request(); idle()
        assertTrue(messenger.requests.isEmpty())
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("TVMazeUpdate").any { it.msg == "Failed to invoke requestEpisodeMetadata" })
    }
    @Test fun channelLookupExceptionIsCaughtBeforePosting() {
        movie("series"); TvPhase19ChannelLookupShadow.fail = true
        request(); idle(); assertTrue(messenger.requests.isEmpty())
        logged("Error requesting metadata from Flutter")
    }
    @Test fun sourceSwitcherComputedHostDispatchesTheRealMetadataRequest() {
        movie("series")
        val host = TvPlayerOriginalAccess.field(field("sourceSwitchController")!!, "host") as TvSourceSwitchController.Host
        host.requestMetadataFromFlutter(); assertTrue(messenger.requests.isEmpty()); idle()
        assertEquals(1, requests("requestEpisodeMetadata").size)
    }
}

/** Observe failure at the borrowed channel boundary, leaving the receiver body real. */
@org.robolectric.annotation.Implements(className = "com.debrify.app.MainActivity\$Companion", isInAndroidSdk = false)
internal class TvPhase19ChannelLookupShadow {
    @org.robolectric.annotation.RealObject private lateinit var target: MainActivity.Companion
    @org.robolectric.annotation.Implementation fun getAndroidTvPlayerChannel(): MethodChannel? {
        if (fail) throw IllegalStateException("p19 channel lookup failure")
        return org.robolectric.shadow.api.Shadow.directlyOn<MethodChannel?>(target,
            "com.debrify.app.MainActivity\$Companion", "getAndroidTvPlayerChannel")
    }
    companion object { var fail = false }
}
