package com.debrify.app.tv

import android.net.Uri
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsExtractor
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Mandatory prerequisites on the original, before widening characterization. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvMediaPipelinePrerequisiteTest : TvPhase19PipelineTest() {
    @Test fun builtVodConfigurationCanBeReadBackFromRealMedia3() {
        heap(1024); set("networkBuffer", "huge")
        val factory = buildPipeline()
        val control = loadControl()
        assertEquals("huge preset min buffer", 300_000_000L, required(control, "minBufferUs"))
        assertEquals("huge preset max buffer", 300_000_000L, required(control, "maxBufferUs"))
        assertEquals("huge preset memory cap", 192 * 1024 * 1024, required(control, "targetBufferBytesOverwrite"))
        assertEquals("startup threshold remains stock", DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L,
            required(control, "bufferForPlaybackUs"))
        val selector = field("trackSelector") as DefaultTrackSelector
        assertSame("installed selector is the activity selector", selector, required(built, "trackSelector"))
        assertTrue("selector invalidates on renderer capability changes", selector.parameters.allowInvalidateSelectionsOnRendererCapabilitiesChange)
        val offset = field("offsetRenderersFactory")!!
        val native = required(offset, "delegate")
        assertEquals("installed native renderer extension preference", DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER,
            required(native, "extensionRendererMode"))
        assertEquals("installed renderer fallback", true, required(native, "enableDecoderFallback"))
        assertNotSame("custom codec selector is installed", androidx.media3.exoplayer.mediacodec.MediaCodecSelector.DEFAULT, required(native, "mediaCodecSelector"))
        val vod = sources(factory)
        assertEquals(ResolvingDataSource.Factory::class.java, vod.javaClass)
        val standard = upstream(vod)
        assertEquals(DefaultDataSource.Factory::class.java, standard.javaClass)
        val transport = required(standard, "baseDataSourceFactory")
        assertEquals(VodHttpDataSource.Factory::class.java, transport.javaClass)
        val http = required(transport, "standardFactory")
        assertEquals(DefaultHttpDataSource.Factory::class.java, http.javaClass)
        assertEquals("installed connect timeout", 15_000, required(http, "connectTimeoutMs"))
        assertEquals("installed read timeout", 15_000, required(http, "readTimeoutMs"))
        assertEquals("installed cross-protocol redirects", true, required(http, "allowCrossProtocolRedirects"))
        assertNotNull("protected transport is installed", required(transport, "protectedFactory"))
    }

    @Test fun realHeapGetterControlsStockAndExactFortyEightMiBBoundary() {
        set("networkBuffer", "large")
        heap(128); buildPipeline()
        assertEquals("32 MiB budget keeps stock", DefaultLoadControl.DEFAULT_MIN_BUFFER_MS * 1000L, required(loadControl(), "minBufferUs"))
        assertEquals("stock target sentinel", -1, required(loadControl(), "targetBufferBytesOverwrite"))
        heap(192); buildPipeline()
        assertEquals("exact boundary enables larger buffer", 120_000_000L, required(loadControl(), "minBufferUs"))
        assertEquals("quarter of real heap at boundary", 48 * 1024 * 1024, required(loadControl(), "targetBufferBytesOverwrite"))
    }

    @Test fun builtIptvChainAndPolicyAreObservableOnTheOriginal() {
        heap(1024); set("networkBuffer", "huge")
        val factory = buildPipeline(true)
        assertEquals("IPTV always keeps stock LoadControl", DefaultLoadControl.DEFAULT_MIN_BUFFER_MS * 1000L, required(loadControl(), "minBufferUs"))
        val recording = sources(factory)
        assertEquals(RecordingDataSource.Factory::class.java, recording.javaClass)
        val iptv = upstream(recording)
        assertEquals(ResolvingDataSource.Factory::class.java, iptv.javaClass)
        val vod = upstream(iptv)
        assertEquals(ResolvingDataSource.Factory::class.java, vod.javaClass)
        val data = upstream(vod)
        assertEquals(DefaultDataSource.Factory::class.java, data.javaClass)
        assertEquals(DefaultHttpDataSource.Factory::class.java, required(data, "baseDataSourceFactory").javaClass)
        assertEquals(IptvLiveLoadErrorPolicy::class.java, required(factory, "loadErrorHandlingPolicy").javaClass)
        assertNotNull("codec selector is installed", required(required(field("offsetRenderersFactory")!!, "delegate"), "mediaCodecSelector"))
    }

    @Test fun vodResolverReadsChangedVolatilePairOnEachWorkerInvocation() {
        val factory = buildPipeline()
        val resolver = resolver(sources(factory))
        val spec = DataSpec(Uri.parse("https://p19.test/movie"))
        set("activeVodHeaders", setOf("https://p19.test:443") to mapOf("X-P19" to "first"))
        assertEquals("first worker sees current VOD headers", "first", worker { resolver.resolveDataSpec(spec).httpRequestHeaders["X-P19"] })
        set("activeVodHeaders", setOf("https://p19.test:443") to mapOf("X-P19" to "second"))
        assertEquals("second worker re-reads changed VOD headers", "second", worker { resolver.resolveDataSpec(spec).httpRequestHeaders["X-P19"] })
    }

    @Test fun iptvResolverReadsChangedVolatileMapOnEachWorkerInvocation() {
        val factory = buildPipeline(true)
        val resolver = resolver(upstream(sources(factory)))
        val spec = DataSpec(Uri.parse("http://p19.test/live.ts"))
        set("currentIptvHttpHeaders", mapOf("X-P19" to "first"))
        assertEquals("first worker sees current IPTV headers", "first", worker { resolver.resolveDataSpec(spec).httpRequestHeaders["X-P19"] })
        set("currentIptvHttpHeaders", mapOf("X-P19" to "second"))
        assertEquals("second worker re-reads changed IPTV headers", "second", worker { resolver.resolveDataSpec(spec).httpRequestHeaders["X-P19"] })
    }

    @Test fun bothExtractorOverloadsReadChangedVolatileFlagOnWorkerInvocations() {
        val factory = buildPipeline(true)
        val extractors = required(required(factory, "delegateFactoryLoader"), "extractorsFactory") as ExtractorsFactory
        fun flags(uri: Boolean): Int = worker {
            val all = if (uri) extractors.createExtractors(Uri.parse("http://p19.test/live.ts"), emptyMap()) else extractors.createExtractors()
            val ts = all.filterIsInstance<TsExtractor>().single()
            required(required(ts, "payloadReaderFactory"), "flags") as Int
        }
        val aggressive = DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
        set("iptvStrictTsActive", false)
        assertEquals("no-arg worker uses aggressive TS", aggressive, flags(false))
        assertEquals("URI worker uses aggressive TS", aggressive, flags(true))
        set("iptvStrictTsActive", true)
        assertEquals("no-arg worker re-reads strict TS", 0, flags(false))
        assertEquals("URI worker re-reads strict TS", 0, flags(true))
    }
}
