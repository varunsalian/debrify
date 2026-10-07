package com.debrify.app.tv

internal fun isIptvSeriesSentinel(entry: IptvChannelEntry): Boolean =
    entry.contentType == "series" || entry.url.startsWith("xtream-series://")

internal fun currentIptvStartOverProgramme(entry: IptvChannelEntry): IptvEpgProgram? {
    val now = System.currentTimeMillis()
    if (!entry.isLive ||
        entry.tvArchive == "0" ||
        (!entry.epgNowHasArchive && entry.tvArchive != "1") ||
        entry.epgNowStartMs <= 0L ||
        now !in entry.epgNowStartMs until entry.epgNowStopMs
    ) return null
    val archiveDays = entry.tvArchiveDuration ?: 0
    if (archiveDays > 0 &&
        entry.epgNowStartMs < now - archiveDays.toLong() * 86_400_000L
    ) return null
    return IptvEpgProgram(
        title = entry.epgNowTitle ?: entry.name,
        description = null,
        startMs = entry.epgNowStartMs,
        stopMs = entry.epgNowStopMs,
        hasArchive = true,
    )
}

/** "36 min" / "1 hr 12 min" — what is left of a programme's runtime. */
internal fun formatIptvRemaining(ms: Long): String {
    val minutes = (ms / 60_000L).coerceAtLeast(0L)
    if (minutes < 60) return "$minutes min"
    val hours = minutes / 60
    val rest = minutes % 60
    return if (rest == 0L) "$hours hr" else "$hours hr $rest min"
}

/**
     * Hand known now/next data to a replacement entry for the same channel.
     *
     * A window install swaps in fresh [IptvChannelEntry] objects, and the new
     * one carries no EPG. Without this, repainting from it flips a banner that
     * is already showing the programme back to "No guide data" until the
     * refetch lands — a visible regression on the very first tune, where the
     * bootstrap window always arrives a moment after the banner. Only real data
     * moves across: adopting a blank answer would suppress [to]'s own fetch.
     */
internal fun adoptIptvEpg(from: IptvChannelEntry, to: IptvChannelEntry) {
    if (from.epgNowTitle == null || to.epgLoaded) return
    to.epgNowTitle = from.epgNowTitle
    to.epgNowStartMs = from.epgNowStartMs
    to.epgNowStopMs = from.epgNowStopMs
    to.epgNowHasArchive = from.epgNowHasArchive
    to.epgCatchupMetadataLoaded = from.epgCatchupMetadataLoaded
    to.epgNextTitle = from.epgNextTitle
    to.epgNextStartMs = from.epgNextStartMs
    // Claim "loaded" only when nothing is already on its way; an in-flight
    // fetch will overwrite these with its own, fresher answer.
    if (!to.epgLoading) to.epgLoaded = true
}

// ── Stremio-addon IPTV channels (resolve-on-demand + serial ladder) ──────

internal fun isStremioIptvUrl(url: String): Boolean = url.startsWith("stremio-tv://")

internal fun iptvQualityFromLabel(label: String): String {
    val m = Regex("(2160p|4k|1080p|720p|480p)", RegexOption.IGNORE_CASE).find(label)
    return when (m?.value?.lowercase()) {
        "2160p", "4k" -> "4K"
        "1080p" -> "1080p"
        "720p" -> "720p"
        "480p" -> "480p"
        else -> "LIVE"
    }
}
