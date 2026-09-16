package com.debrify.app.tv

import kotlin.random.Random

internal data class ShuffleEpisode(val season: Int, val episode: Int)

/** Episode identities survive replacement of the current torrent's file list. */
internal class ShowShuffle(private val random: Random = Random.Default) {
    private val visited = mutableSetOf<ShuffleEpisode>()

    fun clear() = visited.clear()

    fun pick(
        episodes: List<ShuffleEpisode>,
        current: ShuffleEpisode?,
        excluded: Set<ShuffleEpisode> = emptySet(),
    ): ShuffleEpisode? {
        val eligible = episodes.toSet() - excluded - setOfNotNull(current)
        if (eligible.isEmpty()) return null
        current?.let { visited.add(it) }
        var remaining = eligible - visited
        if (remaining.isEmpty()) {
            visited.clear()
            current?.let { visited.add(it) }
            remaining = eligible
        }
        return remaining.toList().random(random).also { visited.add(it) }
    }
}
