package com.debrify.app.tv

import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import java.util.Locale

/** The audio language of a track-selection override, for capturing a pick. */
@OptIn(UnstableApi::class)
internal fun languageOfOverride(override: TrackSelectionOverride?): String? {
    if (override == null) return null
    val idx = override.trackIndices.firstOrNull() ?: return null
    return try {
        override.mediaTrackGroup.getFormat(idx).language
    } catch (e: Exception) {
        null
    }
}

@OptIn(UnstableApi::class)
internal fun buildAudioTrackLabel(format: Format): String {
    val lang = format.language ?: "und"
    val label = format.label
    val channels = if (format.channelCount != Format.NO_VALUE) "${format.channelCount}ch" else ""
    val bitrate = if (format.bitrate != Format.NO_VALUE) "${format.bitrate / 1000}kbps" else ""

    val parts = mutableListOf<String>()
    if (!label.isNullOrEmpty()) parts.add(label)
    else parts.add(lang.uppercase(Locale.getDefault()))
    if (channels.isNotEmpty()) parts.add(channels)
    if (bitrate.isNotEmpty()) parts.add(bitrate)

    return parts.joinToString(" · ")
}

internal fun buildSubtitleTrackLabel(format: Format): String {
    val lang = format.language ?: "und"
    val label = format.label

    return if (!label.isNullOrEmpty()) {
        "$label ($lang)"
    } else {
        lang.uppercase(Locale.getDefault())
    }
}

internal fun isSearchSubtitleOption(label: String): Boolean {
    return label == SEARCH_SUBTITLE_LABEL
}

internal fun isLoadingSubtitleOption(label: String): Boolean {
    return label.startsWith("⏳")
}

internal fun isExternalSubtitleOption(label: String): Boolean {
    return label.startsWith(EXTERNAL_SUBTITLE_PREFIX)
}

/**
     * True if this subtitle URL is a format the on-device parser can render.
     * TTML/DFXP were handled by ExoPlayer's decoder in the old re-prepare path
     * but our SubtitleCueParser can't parse them (they'd yield zero cues and
     * fail the load), so they're filtered out of the offered list entirely.
     */
internal fun isSideRenderableSubtitle(url: String): Boolean {
    val path = url.substringBefore("?").lowercase()
    return !path.endsWith(".ttml") && !path.endsWith(".dfxp")
}
    private const val SEARCH_SUBTITLE_LABEL = "Search Movie/Show Subtitles"
    internal const val EXTERNAL_SUBTITLE_PREFIX = "⬇"
