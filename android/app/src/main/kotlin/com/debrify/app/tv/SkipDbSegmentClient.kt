package com.debrify.app.tv

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

internal enum class TvSkipSegmentType { INTRO, OUTRO }

internal data class TvSkipSegment(
    val type: TvSkipSegmentType,
    val startMs: Long,
    val endMs: Long,
) {
    fun contains(positionMs: Long): Boolean = positionMs in startMs until endMs
}

internal data class TvSkipSegments(
    val intro: TvSkipSegment? = null,
    val outro: TvSkipSegment? = null,
) {
    fun segmentAt(positionMs: Long): TvSkipSegment? = when {
        intro?.contains(positionMs) == true -> intro
        outro?.contains(positionMs) == true -> outro
        else -> null
    }

    companion object {
        val EMPTY = TvSkipSegments()
    }
}

/** Blocking SkipDB HTTP client. Call [fetch] from an IO dispatcher. */
internal object SkipDbSegmentClient {
    private const val ENDPOINT = "https://api.skipdb.tv/api/segments"
    private const val TIMEOUT_MS = 6_000

    fun fetch(
        imdbId: String,
        season: Int,
        episode: Int,
        durationSeconds: Long,
    ): TvSkipSegments {
        val query = listOf(
            "imdb_id" to imdbId,
            "season" to season.toString(),
            "episode" to episode.toString(),
            "duration" to durationSeconds.toString(),
        ).joinToString("&") { (key, value) ->
            "${encode(key)}=${encode(value)}"
        }
        val connection = URL("$ENDPOINT?$query").openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                TvSkipSegments.EMPTY
            } else {
                val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                parse(body)
            }
        } finally {
            connection.disconnect()
        }
    }

    internal fun parse(body: String): TvSkipSegments {
        val segments = JSONObject(body).optJSONObject("segments") ?: return TvSkipSegments.EMPTY
        return TvSkipSegments(
            intro = parseSegment(segments.optJSONObject("intro"), TvSkipSegmentType.INTRO),
            outro = parseSegment(segments.optJSONObject("outro"), TvSkipSegmentType.OUTRO),
        )
    }

    private fun parseSegment(value: JSONObject?, type: TvSkipSegmentType): TvSkipSegment? {
        value ?: return null
        // SkipDB uses this status when a release's duration differs too much
        // from its reference timestamps. Never offer a potentially unsafe jump.
        if (value.optString("match") == "out-of-range") return null

        val startMs = value.optLong("start_ms", -1L)
        val endMs = value.optLong("end_ms", -1L)
        if (startMs < 0L || endMs <= startMs) return null
        return TvSkipSegment(type = type, startMs = startMs, endMs = endMs)
    }

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
}
