package com.debrify.app.tv

import java.util.Locale

internal fun buildNowPlayingText(channel: StremioTvGuideChannel): String {
    val title = channel.nowPlayingTitle ?: return "Loading..."
    val parts = mutableListOf(title)
    if (!channel.nowPlayingYear.isNullOrEmpty()) parts.add("(${channel.nowPlayingYear})")
    if (channel.nowPlayingRating != null && channel.nowPlayingRating!! > 0) {
        parts.add("★ ${String.format(Locale.US, "%.1f", channel.nowPlayingRating)}")
    }
    return parts.joinToString(" ")
}

internal fun updateStremioTvGuideChannelData(
    channel: StremioTvGuideChannel,
    data: Map<*, *>
) {
    val np = data["nowPlaying"] as? Map<*, *>
    if (np != null) {
        channel.nowPlayingTitle = np["title"] as? String
        channel.nowPlayingPoster = (np["poster"] as? String)?.takeIf { it.isNotEmpty() }
        channel.nowPlayingYear = (np["year"] as? String)?.takeIf { it.isNotEmpty() }
        channel.nowPlayingRating = (np["rating"] as? Number)?.toDouble()
        channel.nowPlayingSlotEndMs = (np["slotEndMs"] as? Number)?.toLong() ?: 0
        channel.nowPlayingProgress = (np["progress"] as? Number)?.toFloat() ?: 0f
        channel.hasGuideData = true
    }

    val next = data["nextUp"] as? Map<*, *>
    if (next != null) {
        channel.nextUpTitle = next["title"] as? String
        channel.nextUpPoster = (next["poster"] as? String)?.takeIf { it.isNotEmpty() }
        channel.nextUpYear = (next["year"] as? String)?.takeIf { it.isNotEmpty() }
        channel.nextUpRating = (next["rating"] as? Number)?.toDouble()
    }
    channel.isLoadingGuideData = false
}
