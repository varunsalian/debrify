package com.debrify.app.tv

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.DataSpec
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvMediaPipelineLoaderTest : TvPhase19PipelineTest() {
    @Test fun vodUnmatchedAndAbsentOriginsReturnTheSameSpec() {
        val installed = resolver(sources(buildPipeline()))
        set("activeVodHeaders", setOf("https://p19.test:443") to mapOf("Authorization" to "test"))
        for (url in listOf("https://other.test/a", "http://p19.test/a", "https://p19.test:444/a", "file:///a", "/a")) {
            val spec = DataSpec(Uri.parse(url))
            assertSame("non-protected request: $url", spec, worker { installed.resolveDataSpec(spec) })
        }
    }
    @Test fun vodDefaultPortsAndHeaderPrecedenceAreCanonical() {
        val installed = resolver(sources(buildPipeline()))
        set("activeVodHeaders", setOf("https://p19.test:443", "http://p19.test:80") to mapOf("X-P19" to "new"))
        for (url in listOf("https://p19.test/a", "https://p19.test:443/b", "http://p19.test/a", "http://p19.test:80/b")) {
            val spec = DataSpec.Builder().setUri(url).setHttpRequestHeaders(mapOf("X-P19" to "old", "Keep" to "yes")).build()
            val resolved = worker { installed.resolveDataSpec(spec) }
            assertEquals("protected origin: $url", "new", resolved.httpRequestHeaders["X-P19"])
            assertEquals("unrelated request header retained", "yes", resolved.httpRequestHeaders["Keep"])
        }
    }
    @Test fun vodAndIptvReportedUriAreIdentity() {
        val uri = Uri.parse("https://p19.test/live")
        val vod = resolver(sources(buildPipeline()))
        assertSame(uri, worker { vod.resolveReportedUri(uri) })
        val iptv = resolver(upstream(sources(buildPipeline(true))))
        assertSame(uri, worker { iptv.resolveReportedUri(uri) })
    }
    @Test fun iptvEmptyHeadersReturnIdentityAndChannelUaWins() {
        val installed = resolver(upstream(sources(buildPipeline(true))))
        val spec = DataSpec.Builder().setUri("http://p19.test/live").setHttpRequestHeaders(mapOf("User-Agent" to "old", "Keep" to "yes")).build()
        set("currentIptvHttpHeaders", emptyMap<String, String>())
        assertSame("empty map retains the exact DataSpec", spec, worker { installed.resolveDataSpec(spec) })
        set("currentIptvHttpHeaders", mapOf("User-Agent" to "Channel UA"))
        val result = worker { installed.resolveDataSpec(spec) }
        assertEquals("Channel UA", result.httpRequestHeaders["User-Agent"]); assertEquals("yes", result.httpRequestHeaders["Keep"])
    }
    @Test fun protectedFactoryUsesTheClientPublishedBySetup() {
        set("networkPatience", "patient")
        val factory = sources(buildPipeline())
        val vod = required(upstream(factory), "baseDataSourceFactory")
        val protected = required(vod, "protectedFactory") as androidx.media3.datasource.DataSource.Factory
        val okHttp = upstream(protected)
        val client = required(okHttp, "callFactory") as okhttp3.OkHttpClient
        assertSame("same client handed to protected transport", field("protectedStreamClient"), client)
        assertEquals(60_000, client.connectTimeoutMillis); assertEquals(60_000, client.readTimeoutMillis)
        val previous = client
        set("networkPatience", "standard"); buildPipeline()
        assertNotSame("rebuild publishes the new patience client", previous, field("protectedStreamClient"))
    }
    @Test fun installedLivePolicyReadsCurrentEntryAndIndexEachTime() {
        val installed = required(buildPipeline(true), "loadErrorHandlingPolicy") as LoadErrorHandlingPolicy
        set("iptvChannels", mutableListOf(channel(live = true), channel(live = false))); set("currentIptvIndex", 0)
        assertEquals(20, worker { installed.getMinimumLoadableRetryCount(C.DATA_TYPE_MEDIA) })
        set("currentIptvIndex", 1)
        assertEquals(3, worker { installed.getMinimumLoadableRetryCount(C.DATA_TYPE_MEDIA) })
        set("currentIptvIndex", 99)
        assertEquals("out of bounds is nonlive", 3, worker { installed.getMinimumLoadableRetryCount(C.DATA_TYPE_MEDIA) })
    }
    @Test fun speechTapReadsLivePlayerAndPostsBackToMain() {
        buildPipeline()
        val tap = field("speechTap")!!
        @Suppress("UNCHECKED_CAST") val position = required(tap, "positionMs") as () -> Long
        @Suppress("UNCHECKED_CAST") val post = required(tap, "mainPost") as ((() -> Unit) -> Unit)
        set("player", probe.player); probe.position = 12345
        assertEquals(12345L, position()); probe.position = 999; assertEquals(999L, position())
        var ran = false
        worker { post { assertEquals(android.os.Looper.getMainLooper().thread, Thread.currentThread()); ran = true } }
        assertFalse("worker only queues the callback", ran); idle(); assertTrue(ran)
        set("player", null); assertEquals(0L, position())
        set("player", built)
    }
    @Test fun recordingFirstAccessAndAbortCallbackAreIptvOnly() {
        val lazy = TvPlayerOriginalAccess.field(activity, "iptvRecordingController\$delegate") as Lazy<*>
        assertFalse(lazy.isInitialized()); buildPipeline(); assertFalse("VOD does not create the tee controller", lazy.isInitialized())
        buildPipeline(true); assertTrue(lazy.isInitialized())
        val recording = lazy.value as IptvRecordingController
        assertNotNull(recording.onAborted)
        set("isIptvMode", true); set("iptvChannels", mutableListOf(channel())); set("currentIptvIndex", 0)
        val button = androidx.appcompat.widget.AppCompatButton(activity)
        set("iptvRecordButton", button)
        button.text = "stale"
        recording.onAborted!!.invoke()
        assertEquals("Record", button.text.toString())
        assertEquals("Recording stopped — couldn't keep writing to storage", org.robolectric.shadows.ShadowToast.getTextOfLatestToast())
        assertEquals(android.widget.Toast.LENGTH_LONG, org.robolectric.shadows.ShadowToast.getLatestToast().duration)
    }
    @Test fun installedPlayerHoldsBothNetworkLocksAndNoisyAudioHandling() {
        buildPipeline(); built.playWhenReady = true
        assertEquals(true, required(required(built, "wakeLockManager"), "enabled"))
        assertEquals(true, required(required(built, "wifiLockManager"), "enabled"))
        assertEquals(true, required(required(built, "audioBecomingNoisyManager"), "isEnabled"))
    }
}
