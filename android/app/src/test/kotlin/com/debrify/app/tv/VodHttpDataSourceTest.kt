package com.debrify.app.tv

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.IOException
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class VodHttpDataSourceTest {
    private fun factory() = VodHttpDataSource.Factory(
        DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(5000)
            .setReadTimeoutMs(5000)
            .setDefaultRequestProperties(mapOf("User-Agent" to ProtectedStreamHttp.userAgent)),
        ProtectedStreamHttp.dataSourceFactory(ProtectedStreamHttp.client(5000)),
    )

    private fun read(source: DataSource, spec: DataSpec): String = try {
        source.open(spec)
        val buffer = ByteArray(32)
        val result = java.io.ByteArrayOutputStream()
        while (true) {
            val count = source.read(buffer, 0, buffer.size)
            if (count == C.RESULT_END_OF_INPUT) break
            result.write(buffer, 0, count)
        }
        result.toString("UTF-8")
    } finally {
        source.close()
    }

    @Test fun sourceSwitchesReevaluateResolvedHeadersAndPreserveRangeAndQueryToken() {
        MockWebServer().use { origin ->
            MockWebServer().use { cdn ->
                var activeHeaders = emptyMap<String, String>()
                // As in the activity, resolve the active source's headers BEFORE
                // the router sees the request; the same DataSource is reopened.
                val source = ResolvingDataSource.Factory(factory()) { spec ->
                    spec.withAdditionalHeaders(activeHeaders)
                }.createDataSource()
                for (protected in listOf(false, true, false)) {
                    activeHeaders = if (protected) mapOf(
                        "Authorization" to "Bearer private",
                        "Cookie" to "session=private",
                        "X-Plex-Token" to "private",
                        "user-agent" to "CustomPlayer/1.0",
                    ) else emptyMap()
                    origin.enqueue(MockResponse().setResponseCode(302)
                        .setHeader("Location", cdn.url("/video?X-Plex-Token=query-token")))
                    cdn.enqueue(MockResponse().setResponseCode(206)
                        .setHeader("Content-Range", "bytes 4-7/8").setBody("efgh"))
                    assertEquals("efgh", read(source, DataSpec.Builder()
                        .setUri(Uri.parse(origin.url("/video").toString()))
                        .setPosition(4).setLength(4).build()))
                    val initial = origin.takeRequest(5, TimeUnit.SECONDS)!!
                    assertEquals(listOf(if (protected) "CustomPlayer/1.0" else ProtectedStreamHttp.userAgent),
                        initial.headers.values("User-Agent"))
                    assertEquals(if (protected) "Bearer private" else null, initial.getHeader("Authorization"))
                    val redirected = cdn.takeRequest(5, TimeUnit.SECONDS)!!
                    assertEquals("bytes=4-7", redirected.getHeader("Range"))
                    assertEquals("query-token", redirected.requestUrl!!.queryParameter("X-Plex-Token"))
                    for (name in listOf("Authorization", "Cookie", "X-Plex-Token")) {
                        assertNull(redirected.getHeader(name))
                    }
                    assertEquals(if (protected) null else ProtectedStreamHttp.userAgent,
                        redirected.getHeader("User-Agent"))
                }
            }
        }
    }

    @Test fun adaptiveManifestAndSegmentRequestsKeepOriginScopedCredentials() {
        MockWebServer().use { origin ->
            MockWebServer().use { cdn ->
                for ((manifest, segment, mime) in listOf(
                    Triple("master.m3u8", "segment.ts", "application/x-mpegURL"),
                    Triple("manifest.mpd", "segment.m4s", "application/dash+xml"),
                )) {
                    val scoped = ResolvingDataSource.Factory(factory()) { spec ->
                        if (spec.uri.port == origin.port) {
                            spec.withAdditionalHeaders(mapOf("X-Addon-Key" to "private"))
                        } else spec
                    }
                    val mediaSource = DefaultMediaSourceFactory(RuntimeEnvironment.getApplication())
                        .setDataSourceFactory(scoped)
                        .createMediaSource(MediaItem.Builder()
                            .setUri(origin.url("/$manifest").toString()).setMimeType(mime).build())
                    if (manifest.endsWith("m3u8")) assertTrue(mediaSource is HlsMediaSource)
                    else assertTrue(mediaSource is DashMediaSource)
                    // Each manifest / segment / key load is a separate open;
                    // off-origin segment requests must never inherit credentials.
                    val source = scoped.createDataSource()
                    for ((server, path) in listOf(origin to manifest, origin to segment, cdn to segment)) {
                        server.enqueue(MockResponse().setBody("data"))
                        assertEquals("data", read(source, DataSpec.Builder()
                            .setUri(Uri.parse(server.url("/$path").toString())).build()))
                        val request = server.takeRequest(5, TimeUnit.SECONDS)!!
                        assertEquals(if (server === origin) "private" else null,
                            request.getHeader("X-Addon-Key"))
                    }
                }
            }
        }
    }

    @Test fun httpFailureCanCloseAndReopenWithTheOtherTransport() {
        MockWebServer().use { server ->
            val source = factory().createDataSource()
            server.enqueue(MockResponse().setResponseCode(403))
            try {
                read(source, DataSpec.Builder().setUri(Uri.parse(server.url("/protected").toString()))
                    .setHttpRequestHeaders(mapOf("Authorization" to "private")).build())
                fail("Expected HTTP rejection")
            } catch (_: IOException) { }
            server.takeRequest(5, TimeUnit.SECONDS)
            server.enqueue(MockResponse().setBody("recovered"))
            assertEquals("recovered", read(source, DataSpec.Builder()
                .setUri(Uri.parse(server.url("/plain").toString())).build()))
            assertNull(server.takeRequest(5, TimeUnit.SECONDS)!!.getHeader("Authorization"))
        }
    }

    @Test fun transferEventsAndFinalResponseFollowEveryReopen() {
        MockWebServer().use { origin ->
            MockWebServer().use { cdn ->
                var starts = 0
                var ends = 0
                var bytes = 0
                val listener = object : TransferListener {
                    override fun onTransferInitializing(source: DataSource, spec: DataSpec, network: Boolean) {}
                    override fun onTransferStart(source: DataSource, spec: DataSpec, network: Boolean) { starts++ }
                    override fun onBytesTransferred(source: DataSource, spec: DataSpec, network: Boolean, count: Int) { bytes += count }
                    override fun onTransferEnd(source: DataSource, spec: DataSpec, network: Boolean) { ends++ }
                }
                val source = factory().createDataSource()
                source.addTransferListener(listener)
                source.addTransferListener(listener)
                for (headers in listOf(emptyMap(), mapOf("X-Addon-Key" to "private"))) {
                    val target = cdn.url("/final.mp4")
                    origin.enqueue(MockResponse().setResponseCode(302).setHeader("Location", target))
                    cdn.enqueue(MockResponse().setBody("data").setHeader("X-Response-Marker", "yes"))
                    try {
                        source.open(DataSpec.Builder().setUri(Uri.parse(origin.url("/start").toString()))
                            .setHttpRequestHeaders(headers).build())
                        assertEquals(target.toString(), source.uri.toString())
                        assertEquals(listOf("yes"), source.responseHeaders.entries
                            .first { it.key.equals("X-Response-Marker", ignoreCase = true) }.value)
                        val buffer = ByteArray(4)
                        assertEquals(4, source.read(buffer, 0, 4))
                    } finally { source.close() }
                    assertNull(source.uri)
                    assertTrue(source.responseHeaders.isEmpty())
                }
                assertEquals(2, starts)
                assertEquals(2, ends)
                assertEquals(8, bytes)
            }
        }
    }

    @Test fun localFilesBypassBothHttpTransports() {
        val neverHttp = DataSource.Factory { error("Local file reached HTTP routing") }
        val source = DefaultDataSource.Factory(RuntimeEnvironment.getApplication(),
            VodHttpDataSource.Factory(neverHttp, neverHttp)).createDataSource()
        val file = java.io.File.createTempFile("vod-local", ".mp4")
        try {
            file.writeText("local")
            assertEquals("local", read(source, DataSpec.Builder().setUri(Uri.fromFile(file)).build()))
        } finally { file.delete() }
    }
}
