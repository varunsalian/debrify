package com.debrify.app.tv

internal fun rebuildNavigationMaps(model: PlaybackPayload, contentType: String) {
    model.contentType = contentType

    val nextMap = mutableMapOf<Int, Int>()
    val prevMap = mutableMapOf<Int, Int>()

    // Determine the CHRONOLOGICAL order to chain next/prev through. Torrent
    // file order is NOT necessarily episode order (a pack may list S01E05
    // before S01E02), and the playlist adapter itself displays episodes
    // sorted by season then episode. If we linked next/prev in raw file
    // order, "next episode" / autoplay-next would jump to whatever file
    // happens to sit next in the torrent — the wrong episode. So for series
    // content, chain in (season, episode) order to match what the user sees.
    // Collections (no season/episode) keep raw list order.
    val isSeries = contentType == "series" &&
        model.items.any { it.season != null && it.episode != null }
    val order: List<Int> = if (isSeries) {
        model.items.indices.sortedWith(
            compareBy(
                { model.items[it].season ?: Int.MAX_VALUE },
                { model.items[it].episode ?: Int.MAX_VALUE },
                { it }, // stable tie-break on raw index
            )
        )
    } else {
        model.items.indices.toList()
    }

    for (pos in 0 until order.lastIndex) {
        nextMap[order[pos]] = order[pos + 1]
    }
    for (pos in 1..order.lastIndex) {
        prevMap[order[pos]] = order[pos - 1]
    }

    model.nextEpisodeMap = nextMap
    model.prevEpisodeMap = prevMap
    model.collectionGroups = null
    model.perItemImdbIds.clear()

    android.util.Log.d("AndroidTvPlayer", "rebuildNavigationMaps - contentType=$contentType, isSeries=$isSeries, nextMap=${nextMap.size}, prevMap=${prevMap.size}")
}
