package com.debrify.app.tv

import androidx.media3.common.MediaItem
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import android.net.Uri
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ProtectedStreamHttpTest {
    private fun playbackFactory(client: okhttp3.OkHttpClient) = VodHttpDataSource.Factory(
        DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(mapOf("User-Agent" to ProtectedStreamHttp.userAgent)),
        ProtectedStreamHttp.dataSourceFactory(client),
    )

    @Test fun playbackSendsExactlyOneUserAgentMatchingDiscovery() {
        MockWebServer().use { server ->
            val client = ProtectedStreamHttp.client(5000)
            val factory = playbackFactory(client)
            for (key in listOf("User-Agent", "user-agent", "uSeR-aGeNt", null)) {
                val headers = if (key == null) emptyMap() else mapOf(key to "RequiredAgent/1.0")
                val expected = if (key == null) ProtectedStreamHttp.userAgent else "RequiredAgent/1.0"
                val url = server.url("/protected").toString()
                server.enqueue(MockResponse().setHeader("Content-Type", "application/vnd.apple.mpegurl"))
                ProtectedStreamHttp.discoverMimeType(client, url, headers)
                assertEquals(listOf(expected), server.takeRequest().headers.values("User-Agent"))
                server.enqueue(MockResponse().setBody("data"))
                val source = factory.createDataSource()
                try {
                    source.open(DataSpec.Builder().setUri(Uri.parse(url)).setHttpRequestHeaders(headers).build())
                } finally { source.close() }
                assertEquals(listOf(expected), server.takeRequest().headers.values("User-Agent"))
            }
        }
    }

    private val secrets = mapOf("Authorization" to "Bearer secret", "Cookie" to "session=secret", "X-Addon-Key" to "custom-secret")

    @Test fun datasourceChecksEveryRedirectHopAndPreservesRange() {
        MockWebServer().use { origin ->
            MockWebServer().use { destination ->
                origin.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/same"))
                origin.enqueue(MockResponse().setResponseCode(307).setHeader("Location", destination.url("/video")))
                destination.enqueue(MockResponse().setResponseCode(206).setBody("data").setHeader("Content-Range", "bytes 10-13/100"))
                val source = playbackFactory(ProtectedStreamHttp.client(5000)).createDataSource()
                try {
                    source.open(DataSpec.Builder().setUri(Uri.parse(origin.url("/start").toString()))
                        .setPosition(10).setLength(4).setHttpRequestHeaders(secrets).build())
                    val bytes = ByteArray(4)
                    assertEquals(4, source.read(bytes, 0, 4))
                    assertEquals("data", String(bytes))
                } finally { source.close() }
                repeat(2) {
                    val request = origin.takeRequest()
                    secrets.forEach { (name, value) -> assertEquals(value, request.getHeader(name)) }
                }
                val redirected = destination.takeRequest()
                secrets.keys.forEach { assertNull(redirected.getHeader(it)) }
                assertEquals("bytes=10-13", redirected.getHeader("Range"))
            }
        }
    }

    @Test fun httpsDowngradeNeverSendsSecretsInPlaintext() {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverTls = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientTls = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        MockWebServer().use { secure ->
            MockWebServer().use { plain ->
                secure.useHttps(serverTls.sslSocketFactory(), false)
                secure.enqueue(MockResponse().setResponseCode(302).setHeader("Location", plain.url("/index.m3u8")))
                plain.enqueue(MockResponse().setHeader("Content-Type", "application/vnd.apple.mpegurl"))
                val client = ProtectedStreamHttp.client(5000).newBuilder()
                    .sslSocketFactory(clientTls.sslSocketFactory(), clientTls.trustManager).build()
                assertEquals("application/x-mpegURL", ProtectedStreamHttp.discoverMimeType(client, secure.url("/protected").toString(), secrets))
                val initial = secure.takeRequest()
                secrets.forEach { (name, value) -> assertEquals(value, initial.getHeader(name)) }
                val redirected = plain.takeRequest()
                secrets.keys.forEach { assertNull(redirected.getHeader(it)) }
            }
        }
    }

    @Test fun extensionlessProtectedRedirectSelectsHlsBeforePlayback() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/master.m3u8"))
            server.enqueue(MockResponse().setHeader("Content-Type", "application/octet-stream"))
            val originalUrl = server.url("/protected").toString()
            val type = ProtectedStreamHttp.discoverMimeType(ProtectedStreamHttp.client(5000), originalUrl, secrets)
            assertEquals("application/x-mpegURL", type)
            val item = MediaItem.Builder().setUri(originalUrl).setMimeType(type).build()
            assertTrue(DefaultMediaSourceFactory(RuntimeEnvironment.getApplication()).createMediaSource(item) is HlsMediaSource)
            repeat(2) { assertEquals("Bearer secret", server.takeRequest().getHeader("Authorization")) }
        }
    }

    @Test fun headRefusalUsesBoundedGetAndRecognizesDashContentType() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(405))
            server.enqueue(MockResponse().setHeader("Content-Type", "application/dash+xml; charset=utf-8"))
            assertEquals("application/dash+xml", ProtectedStreamHttp.discoverMimeType(
                ProtectedStreamHttp.client(5000), server.url("/protected").toString(), secrets))
            assertEquals("HEAD", server.takeRequest().method)
            val fallback = server.takeRequest()
            assertEquals("GET", fallback.method)
            assertEquals("bytes=0-1023", fallback.getHeader("Range"))
        }
    }
}
