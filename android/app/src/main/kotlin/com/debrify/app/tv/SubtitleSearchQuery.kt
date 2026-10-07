package com.debrify.app.tv

import java.util.Locale

internal fun parseSubtitleCatalogResults(result: Any?): List<SubtitleCatalogResult> {
    val items = result as? List<*> ?: return emptyList()
    return items.mapNotNull { rawItem ->
        val map = rawItem as? Map<*, *> ?: return@mapNotNull null
        val imdbId = map["imdbId"]?.toString()?.takeIf { it.startsWith("tt") }
            ?: return@mapNotNull null
        val type = map["type"]?.toString()?.lowercase(Locale.US)
            ?.takeIf { it == "movie" || it == "series" }
            ?: return@mapNotNull null
        val name = map["name"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            ?: imdbId
        val year = map["year"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        val source = map["source"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }

        SubtitleCatalogResult(
            imdbId = imdbId,
            type = type,
            name = name,
            year = year,
            source = source
        )
    }
}

internal fun resolveSeasonEpisodeForSubtitle(item: PlaybackItem): SeasonEpisode? {
    val existingSeason = item.season
    val existingEpisode = item.episode
    if (existingSeason != null && existingEpisode != null && existingSeason > 0 && existingEpisode > 0) {
        return SeasonEpisode(existingSeason, existingEpisode)
    }

    return parseSeasonEpisodeFromTitle(item.title)
}

internal fun parseSeasonEpisodeFromTitle(title: String): SeasonEpisode? {
    val patterns = listOf(
        Regex("""(?i)\bS(\d{1,2})\s*E(\d{1,3})\b"""),
        Regex("""(?i)\b(\d{1,2})x(\d{1,3})\b"""),
        Regex("""(?i)\bSeason\s*(\d{1,2})\s*(?:Episode|Ep|E)\s*(\d{1,3})\b""")
    )

    for (pattern in patterns) {
        val match = pattern.find(title) ?: continue
        val season = match.groupValues.getOrNull(1)?.toIntOrNull()
        val episode = match.groupValues.getOrNull(2)?.toIntOrNull()
        if (season != null && episode != null && season > 0 && episode > 0) {
            return SeasonEpisode(season, episode)
        }
    }

    return null
}

internal fun buildSubtitleSearchInitialQuery(item: PlaybackItem): String {
    val filename = item.title.substringAfterLast('/').substringBefore('?')
    val withoutExtension = filename.replace(Regex("""\.[A-Za-z0-9]{2,5}$"""), "")
    val cleaned = withoutExtension
        .replace(Regex("""[._]+"""), " ")
        .replace(Regex("""(?i)\bS\d{1,2}\s*E\d{1,3}\b"""), " ")
        .replace(Regex("""(?i)\b\d{1,2}x\d{1,3}\b"""), " ")
        .replace(
            Regex(
                """(?i)\b(2160p|1080p|720p|480p|4k|uhd|hdr|web[- ]?dl|webrip|bluray|brrip|hdtv|dvdrip|x264|x265|h264|h265|hevc|aac|dts|yify)\b"""
            ),
            " "
        )
        .replace(Regex("""\s+"""), " ")
        .trim()

    return cleaned.ifEmpty { item.title }
}

internal fun buildManualSubtitleDisplayLabel(
    result: SubtitleCatalogResult,
    type: String,
    season: Int?,
    episode: Int?
): String {
    val base = result.titleLine()
    return if (type == "series" && season != null && episode != null) {
        "$base S${season}E$episode"
    } else {
        base
    }
}
