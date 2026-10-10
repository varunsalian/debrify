package com.debrify.app.tv

import android.content.Context
import android.net.ConnectivityManager
import android.net.Uri
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsExtractor
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.lang.reflect.Modifier
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Mandatory real-pipeline prerequisite, pinned to installed Media3 1.8.0 internals. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvIptvLoaderCharacterizationTest : TvPhase5OriginalTest() {
    private var created = false
    private fun read(owner: Any, name: String): Any =
        owner.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(owner)!!
    private fun bootstrapFactory(): DefaultMediaSourceFactory {
        set("currentIptvHttpHeaders",mapOf("X-P17" to "first")); set("iptvStrictTsActive",false)
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        shadowOf(cm).setActiveNetworkInfo(null)
        activity.intent.putExtra("payload", JSONObject().put("mode","iptv")
            .put("sourceId","p17").put("sourceName","Provider")
            .put("channels",JSONArray().put(JSONObject().put("name","Probe")
                .put("url","https://phase17.invalid/bootstrap.ts").put("isLive",true)
                .put("httpHeaders",JSONObject().put("X-P17","first"))))
            .put("startIndex",0).toString())
        lifecycle.create().visible(); created = true
        assertTrue("original IPTV bootstrap reached setupPlayer",field("isIptvMode") as Boolean)
        val real = field("player") as ExoPlayer
        assertEquals("real Media3 implementation", "androidx.media3.exoplayer.ExoPlayerImpl", real.javaClass.name)
        val factory = read(real,"mediaSourceFactory") as DefaultMediaSourceFactory
        (field("playerView") as androidx.media3.ui.PlayerView).player = null
        real.release(); set("player",probe.player)
        return factory
    }
    private fun flags(factory: ExtractorsFactory, uri: Uri, noArgs: Boolean): Int {
        val extractors = if (noArgs) factory.createExtractors() else factory.createExtractors(uri,emptyMap())
        val ts = extractors.filterIsInstance<TsExtractor>().single()
        val readers = read(ts,"payloadReaderFactory")
        assertEquals(DefaultTsPayloadReaderFactory::class.java,readers.javaClass)
        return read(readers,"flags") as Int
    }
    @Test fun bootstrapFactoriesReadCurrentHeadersAndStrictModeOnEveryWorkerInvocation() {
        val installed = bootstrapFactory()
        val sources = read(installed,"dataSourceFactory") as DataSource.Factory
        val extractors = read(read(installed,"delegateFactoryLoader"),"extractorsFactory") as ExtractorsFactory
        val worker = Executors.newSingleThreadExecutor { task -> Thread(task,"p17-loader-probe") }
        MockWebServer().use { server ->
            server.start()
            val url = Uri.parse(server.url("/stream.ts").toString())
            fun load(): List<Int> = worker.submit(Callable {
                assertNotEquals("loader observation stays off main",android.os.Looper.getMainLooper().thread,Thread.currentThread())
                val source = sources.createDataSource()
                try {
                    source.open(DataSpec(url)); source.read(ByteArray(8),0,8)
                    listOf(flags(extractors,url,false),flags(extractors,url,true))
                } finally { source.close() }
            }).get(5,TimeUnit.SECONDS)
            try {
                server.enqueue(MockResponse().setBody("probe"))
                set("currentIptvHttpHeaders",mapOf("X-P17" to "first"));set("iptvStrictTsActive",false)
                val aggressive = DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
                assertEquals("both installed extractor overloads use aggressive mode",listOf(aggressive,aggressive),load())
                assertEquals("first resolver invocation sees the main-thread header","first",server.takeRequest(5,TimeUnit.SECONDS)!!.getHeader("X-P17"))
                server.enqueue(MockResponse().setBody("probe"))
                set("currentIptvHttpHeaders",mapOf("X-P17" to "second"));set("iptvStrictTsActive",true)
                assertEquals("both installed extractor overloads re-read strict mode",listOf(0,0),load())
                assertEquals("second resolver invocation re-reads the changed header","second",server.takeRequest(5,TimeUnit.SECONDS)!!.getHeader("X-P17"))
            } finally { worker.shutdownNow(); assertTrue(worker.awaitTermination(5,TimeUnit.SECONDS)) }
        }
    }
    @Test fun bothLoaderThreadFieldsRemainVolatileActivityStorage() {
        for (name in listOf("currentIptvHttpHeaders","iptvStrictTsActive")) {
            val actual = activity.javaClass.getDeclaredField(name)
            assertTrue("$name retains JVM volatility",Modifier.isVolatile(actual.modifiers))
        }
    }
    @After fun destroyLoaderFixture() { if (created) lifecycle.destroy() }
}
