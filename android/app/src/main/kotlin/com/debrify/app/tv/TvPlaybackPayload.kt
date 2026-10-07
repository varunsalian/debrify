package com.debrify.app.tv

import org.json.JSONObject

internal enum class PlaylistMode { NONE, SERIES, COLLECTION }

internal data class ManualSourceSwitchSnapshot(
    val sourceIndex: Int,
    val itemIndex: Int,
    val contentType: String,
    val items: List<PlaybackItem>,
    val nextEpisodeMap: Map<Int, Int>,
    val prevEpisodeMap: Map<Int, Int>,
    val collectionGroups: List<JSONObject>?,
    val perItemImdbIds: Map<Int, String?>,
    val title: String?,
)

internal data class CollectionGroup(
    val name: String,
    val fileIndices: List<Int>,
)

internal data class MovieGroups(
    val groups: List<CollectionGroup>,
) {
    // Helper to get group by index
    fun getGroup(index: Int): CollectionGroup? = groups.getOrNull(index)

    // Helper to find which group contains a file index
    fun findGroupContaining(fileIndex: Int): CollectionGroup? {
        return groups.firstOrNull { it.fileIndices.contains(fileIndex) }
    }

    // Helper to get group index for a file
    fun getGroupIndex(fileIndex: Int): Int {
        return groups.indexOfFirst { it.fileIndices.contains(fileIndex) }
    }
}

internal data class PlaybackPayload(
    val title: String,
    val subtitle: String?,
    var contentType: String,
    val items: MutableList<PlaybackItem>,
    val startIndex: Int,
    val seriesTitle: String?,
    var nextEpisodeMap: Map<Int, Int> = emptyMap(),
    var prevEpisodeMap: Map<Int, Int> = emptyMap(),
    var collectionGroups: List<JSONObject>? = null, // Collection groups from Flutter
    var imdbId: String? = null, // IMDB ID for fetching external subtitles from Stremio addons (var to allow async discovery from TVMaze)
    val httpHeaders: Map<String, String> = emptyMap(), // Optional per-session headers for protected direct streams
    val perItemImdbIds: MutableMap<Int, String?> = mutableMapOf(), // Per-item IMDB IDs for movie collections (caches Cinemeta lookups)
    var startAtPercent: Double = 0.0, // Start video at this fraction (0.0 to 1.0) of duration — var so Stremio TV channel switches can update it
    val traktProgressPercent: Double = 0.0, // Trakt watch progress (0-100) for resume — takes priority over local resume
    val localCompletionTracking: Boolean = false,
    val movieCompletionThreshold: Int = 80,
    val episodeCompletionThreshold: Int = 80,
    // Full-show episode guide (TVMaze), delivered post-launch via the
    // metadata broadcast: every episode of the show, present in the
    // playlist or not. Empty until (unless) the fetch lands.
    val guideEpisodes: MutableList<GuideEpisode> = mutableListOf(),
)

internal data class SubtitleCatalogResult(
    val imdbId: String,
    val type: String,
    val name: String,
    val year: String?,
    val source: String?,
) {
    fun titleLine(): String {
        return if (!year.isNullOrEmpty()) "$name ($year)" else name
    }

    fun detailLine(): String {
        val parts = mutableListOf(if (type == "series") "Series" else "Movie")
        if (!source.isNullOrEmpty()) parts.add(source)
        parts.add(imdbId)
        return parts.joinToString(" · ")
    }
}
