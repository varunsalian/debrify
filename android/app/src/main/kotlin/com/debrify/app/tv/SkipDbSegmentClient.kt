package com.debrify.app.tv

import org.json.JSONArray
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
    val intros: List<TvSkipSegment> = emptyList(),
    val outros: List<TvSkipSegment> = emptyList(),
) {
    fun segmentAt(positionMs: Long): TvSkipSegment? =
        intros.firstOrNull { it.contains(positionMs) }
            ?: outros.firstOrNull { it.contains(positionMs) }

    companion object {
        val EMPTY = TvSkipSegments()
    }
}

/** Provider dispatcher for manual skip markers in the native TV player. */
internal object TvSkipSegmentClients {
    const val SKIP_DB = "skipdb"
    const val INTRO_DB = "introdb"
    const val THE_INTRO_DB = "theintrodb"

    fun supports(providerId: String): Boolean = when (providerId) {
        SKIP_DB, INTRO_DB, THE_INTRO_DB -> true
        else -> false
    }

    /** Blocking network call. Invoke from an IO dispatcher. */
    fun fetch(
        providerId: String,
        imdbId: String,
        season: Int,
        episode: Int,
        durationSeconds: Long,
    ): TvSkipSegments = when (providerId) {
        INTRO_DB -> IntroDbSegmentClient.fetch(imdbId, season, episode, durationSeconds)
        THE_INTRO_DB -> TheIntroDbSegmentClient.fetch(imdbId, season, episode, durationSeconds)
        SKIP_DB -> SkipDbSegmentClient.fetch(imdbId, season, episode, durationSeconds)
        else -> TvSkipSegments.EMPTY
    }
}

internal object SkipDbSegmentClient {
    private const val ENDPOINT = "https://api.skipdb.tv/api/segments"

    fun fetch(
        imdbId: String,
        season: Int,
        episode: Int,
        durationSeconds: Long,
    ): TvSkipSegments {
        val body = SkipSegmentHttpClient.get(
            endpoint = ENDPOINT,
            query = listOf(
                "imdb_id" to imdbId,
                "season" to season.toString(),
                "episode" to episode.toString(),
                "duration" to durationSeconds.toString(),
            ),
        ) ?: return TvSkipSegments.EMPTY
        return parse(body, durationSeconds * 1_000L)
    }

    internal fun parse(body: String, durationMs: Long): TvSkipSegments {
        val segments = JSONObject(body).optJSONObject("segments") ?: return TvSkipSegments.EMPTY
        val intro = parseBoundedSegment(
            value = segments.optJSONObject("intro"),
            type = TvSkipSegmentType.INTRO,
            durationMs = durationMs,
            rejectOutOfRange = true,
        )
        val outro = parseBoundedSegment(
            value = segments.optJSONObject("outro"),
            type = TvSkipSegmentType.OUTRO,
            durationMs = durationMs,
            rejectOutOfRange = true,
        )
        return normalizedSegments(listOfNotNull(intro), listOfNotNull(outro))
    }
}

internal object IntroDbSegmentClient {
    private const val ENDPOINT = "https://api.introdb.app/segments"

    fun fetch(
        imdbId: String,
        season: Int,
        episode: Int,
        durationSeconds: Long,
    ): TvSkipSegments {
        val body = SkipSegmentHttpClient.get(
            endpoint = ENDPOINT,
            query = listOf(
                "imdb_id" to imdbId,
                "season" to season.toString(),
                "episode" to episode.toString(),
            ),
        ) ?: return TvSkipSegments.EMPTY
        return parse(body, durationSeconds * 1_000L)
    }

    internal fun parse(body: String, durationMs: Long): TvSkipSegments {
        val response = JSONObject(body)
        val intro = parseBoundedSegment(
            value = response.optJSONObject("intro"),
            type = TvSkipSegmentType.INTRO,
            durationMs = durationMs,
        )
        val outro = parseBoundedSegment(
            value = response.optJSONObject("outro"),
            type = TvSkipSegmentType.OUTRO,
            durationMs = durationMs,
        )
        return normalizedSegments(listOfNotNull(intro), listOfNotNull(outro))
    }
}

internal object TheIntroDbSegmentClient {
    private const val ENDPOINT = "https://api.theintrodb.org/v3/media"

    fun fetch(
        imdbId: String,
        season: Int,
        episode: Int,
        durationSeconds: Long,
    ): TvSkipSegments {
        val durationMs = durationSeconds * 1_000L
        val body = SkipSegmentHttpClient.get(
            endpoint = ENDPOINT,
            query = listOf(
                "imdb_id" to imdbId,
                "season" to season.toString(),
                "episode" to episode.toString(),
                "duration_ms" to durationMs.toString(),
            ),
        ) ?: return TvSkipSegments.EMPTY
        return parse(body, durationMs)
    }

    internal fun parse(body: String, durationMs: Long): TvSkipSegments {
        val response = JSONObject(body)
        val intros = parseSegmentArray(
            values = response.optJSONArray("intro"),
            type = TvSkipSegmentType.INTRO,
            durationMs = durationMs,
            nullStartAtBeginning = true,
        )
        val outros = parseSegmentArray(
            values = response.optJSONArray("credits"),
            type = TvSkipSegmentType.OUTRO,
            durationMs = durationMs,
            nullEndAtMediaEnd = true,
        )
        return normalizedSegments(intros, outros)
    }
}

private object SkipSegmentHttpClient {
    private const val TIMEOUT_MS = 6_000

    fun get(endpoint: String, query: List<Pair<String, String>>): String? {
        val encodedQuery = query.joinToString("&") { (key, value) ->
            "${encode(key)}=${encode(value)}"
        }
        val connection = URL("$endpoint?$encodedQuery").openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "GET"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Accept", "application/json")
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                null
            } else {
                connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
}

private fun parseSegmentArray(
    values: JSONArray?,
    type: TvSkipSegmentType,
    durationMs: Long,
    nullStartAtBeginning: Boolean = false,
    nullEndAtMediaEnd: Boolean = false,
): List<TvSkipSegment> {
    values ?: return emptyList()
    val result = mutableListOf<TvSkipSegment>()
    for (index in 0 until values.length()) {
        val segment = parseBoundedSegment(
            value = values.optJSONObject(index),
            type = type,
            durationMs = durationMs,
            nullStartAtBeginning = nullStartAtBeginning,
            nullEndAtMediaEnd = nullEndAtMediaEnd,
        )
        if (segment != null) result += segment
    }
    return result
}

private fun parseBoundedSegment(
    value: JSONObject?,
    type: TvSkipSegmentType,
    durationMs: Long,
    nullStartAtBeginning: Boolean = false,
    nullEndAtMediaEnd: Boolean = false,
    rejectOutOfRange: Boolean = false,
): TvSkipSegment? {
    value ?: return null
    if (durationMs <= 0L) return null
    if (rejectOutOfRange && value.optString("match") == "out-of-range") return null
    if (!value.has("start_ms") || !value.has("end_ms")) return null

    val startMs = when {
        value.has("start_ms") && !value.isNull("start_ms") -> value.optLong("start_ms", -1L)
        nullStartAtBeginning -> 0L
        else -> return null
    }
    val endMs = when {
        value.has("end_ms") && !value.isNull("end_ms") -> value.optLong("end_ms", -1L)
        nullEndAtMediaEnd -> durationMs
        else -> return null
    }
    if (startMs < 0L || endMs <= startMs || startMs >= durationMs || endMs > durationMs) {
        return null
    }
    return TvSkipSegment(type = type, startMs = startMs, endMs = endMs)
}

private fun normalizedSegments(
    intros: List<TvSkipSegment>,
    outros: List<TvSkipSegment>,
): TvSkipSegments {
    fun normalize(values: List<TvSkipSegment>): List<TvSkipSegment> = values
        .distinctBy { Triple(it.type, it.startMs, it.endMs) }
        .sortedWith(compareBy<TvSkipSegment> { it.startMs }.thenBy { it.endMs })

    return TvSkipSegments(intros = normalize(intros), outros = normalize(outros))
}
