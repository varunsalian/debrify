package com.debrify.app.tv

/** Source filenames identify the media, not the episode's display name. */
internal fun resolveSwitchedEpisodeTitle(
    episode: Int,
    incomingTitle: String,
    sourceTitle: String?,
    guideTitle: String?,
    previousEpisodeTitle: String?,
): String {
    val fallback = "Episode $episode"
    return guideTitle?.takeIf { it.isNotBlank() }
        ?: incomingTitle.takeIf {
            it.isNotBlank() && it != fallback && sourceTitle != null && it != sourceTitle
        }
        ?: previousEpisodeTitle?.takeIf { it.isNotBlank() }
        ?: fallback
}
