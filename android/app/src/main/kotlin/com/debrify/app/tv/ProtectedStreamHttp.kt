package com.debrify.app.tv

import androidx.media3.datasource.DataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import org.json.JSONObject
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.util.concurrent.TimeUnit

/** Runs for EVERY network hop, including redirects made inside the datasource. */
internal class PlaybackOriginInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val original = chain.call().request().url
        val target = request.url
        if (sameOrigin(original, target)) return chain.proceed(request)
        val builder = request.newBuilder()
        // Addons can use arbitrary credential names. Retain only transport
        // headers needed for range playback, never Authorization/Cookie/etc.
        for (name in request.headers.names()) {
            if (name.lowercase() !in transportHeaders) builder.removeHeader(name)
        }
        return chain.proceed(builder.build())
    }

    companion object {
        private val transportHeaders = setOf("host", "range", "accept", "accept-encoding", "connection", "content-length")
        fun sameOrigin(a: HttpUrl, b: HttpUrl) =
            a.scheme == b.scheme && a.host == b.host && a.port == b.port
    }
}

internal object ProtectedStreamHttp {
    const val userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /** JSON launch payloads and method-channel replacements use different
     * nested representations. Canonicalize UA before Media3 merges defaults. */
    fun headers(raw: Any?): Map<String, String> {
        val entries = when (raw) {
            is JSONObject -> raw.keys().asSequence().map { it to raw.opt(it) }.toList()
            is Map<*, *> -> raw.entries.map { it.key to it.value }
            else -> emptyList()
        }
        return buildMap {
            for ((key, value) in entries) {
                if (key is String && value is String) {
                    put(if (key.equals("User-Agent", ignoreCase = true)) "User-Agent" else key, value)
                }
            }
        }
    }

    fun dataSourceFactory(client: OkHttpClient): DataSource.Factory = ResolvingDataSource.Factory(
        OkHttpDataSource.Factory(client)
            .setDefaultRequestProperties(mapOf("User-Agent" to userAgent)),
    ) { dataSpec ->
        // Normalize even callers that bypass the item parser. With one key,
        // per-request UA replaces the default regardless of original casing.
        dataSpec.buildUpon().setHttpRequestHeaders(headers(dataSpec.httpRequestHeaders)).build()
    }
    fun client(timeoutMs: Int): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
        .readTimeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .addNetworkInterceptor(PlaybackOriginInterceptor())
        .build()

    fun needsDiscovery(url: String, headers: Map<String, String>): Boolean {
        if (headers.isEmpty()) return false
        val path = runCatching { java.net.URI(url).path.lowercase() }.getOrNull() ?: return false
        return !listOf(".m3u8", ".mpd", ".mp4", ".mkv", ".webm", ".avi", ".ts", ".m4v", ".mov").any(path::endsWith)
    }

    /** Header-only discovery keeps the original playback URL and its origin.
     * The MIME hint lets Media3 choose HLS/DASH before opening that URL. */
    fun discoverMimeType(client: OkHttpClient, url: String, headers: Map<String, String>): String? = runCatching {
        val probeClient = client.newBuilder().callTimeout(5, TimeUnit.SECONDS).build()
        val request = Request.Builder().url(url).head().header("User-Agent", userAgent).apply {
            headers.forEach { (name, value) -> header(name, value) }
        }.build()
        probeClient.newCall(request).execute().use { response ->
            val mime = adaptiveMime(response)
            if (mime != null) return@use mime
            if (response.code != 405 && response.code != 501) return@use null
            // Some origins refuse HEAD. Read response headers only and close
            // immediately; a Range request must never download the full video.
            probeClient.newCall(request.newBuilder().get().header("Range", "bytes=0-1023").build())
                .execute().use(::adaptiveMime)
        }
    }.getOrNull()

    private fun adaptiveMime(response: Response): String? {
        val type = response.header("Content-Type").orEmpty().substringBefore(';').trim().lowercase()
        val path = response.request.url.encodedPath.lowercase()
        return when {
            type == "application/vnd.apple.mpegurl" || type == "application/x-mpegurl" ||
                type == "audio/mpegurl" || type == "audio/x-mpegurl" || path.endsWith(".m3u8") -> "application/x-mpegURL"
            type == "application/dash+xml" || path.endsWith(".mpd") -> "application/dash+xml"
            else -> null
        }
    }
}
