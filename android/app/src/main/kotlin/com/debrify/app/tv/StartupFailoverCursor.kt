package com.debrify.app.tv

internal fun isCurrentStartupGeneration(captured: Int?, current: Int): Boolean =
    captured == null || captured == current

internal fun isAioStreamsSource(
    addonId: String?,
    sourceName: String?,
    displayName: String?,
    url: String?,
): Boolean = listOfNotNull(addonId, sourceName, displayName, url)
    .joinToString(" ")
    .contains("aiostreams", ignoreCase = true)

internal fun isAioStreamsErrorSlate(
    addonId: String?,
    sourceName: String?,
    displayName: String?,
    url: String?,
    durationMs: Long,
): Boolean = durationMs in 1 until 3 * 60_000L && isAioStreamsSource(
    addonId = addonId,
    sourceName = sourceName,
    displayName = displayName,
    url = url,
)

internal fun containsExactEpisode(
    episodes: Iterable<Pair<Int?, Int?>>,
    season: Int,
    episode: Int,
): Boolean = episodes.any { (candidateSeason, candidateEpisode) ->
    candidateSeason == season && candidateEpisode == episode
}

/**
 * A multi-file pack can silently substitute the wrong episode, so it must
 * prove it contains the requested one. A singleton has nothing else to play —
 * the episode-scoped search already vouched for it, and its lone filename
 * often carries no parseable SxxEyy to check against.
 */
internal fun startupPlaylistSatisfiesEpisode(
    episodes: List<Pair<Int?, Int?>>,
    season: Int,
    episode: Int,
): Boolean = episodes.size <= 1 || containsExactEpisode(episodes, season, episode)

/**
 * Ordered, startup-only candidate cursor.
 *
 * It never wraps or retries an attempted source. [commit] permanently closes
 * the cursor so a later player error is treated as an ordinary playback error,
 * not as a startup failure.
 */
internal class StartupFailoverCursor(
    private val startIndex: Int,
    maxAttempts: Int,
) {
    private val attemptLimit = maxAttempts.coerceAtLeast(1)
    private val attempted = linkedSetOf<Int>()

    var committed: Boolean = false
        private set

    val attempts: Int
        get() = attempted.size

    fun beginInitial(sourceCount: Int): Int? {
        if (committed || sourceCount <= 0) return null
        return begin(startIndex.coerceIn(0, sourceCount - 1))
    }

    fun nextIndex(sourceCount: Int, eligible: (Int) -> Boolean): Int? {
        if (committed || attempted.size >= attemptLimit || sourceCount <= 0) return null
        val after = attempted.lastOrNull() ?: (startIndex - 1)
        for (index in (after + 1) until sourceCount) {
            if (index !in attempted && eligible(index)) return begin(index)
        }
        return null
    }

    fun commit() {
        if (attempted.isNotEmpty()) committed = true
    }

    private fun begin(index: Int): Int? {
        if (attempted.size >= attemptLimit || !attempted.add(index)) return null
        return index
    }
}
