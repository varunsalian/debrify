package com.debrify.app.tv

/** Immutable owner routes used only by the original-surface reflection fixture. */
internal object TvPlayerControllerOwners {
    val routes = TvPlayerPlaybackOwners.routes + TvPlayerIptvOwners.routes +
        TvPlayerSubtitleOwners.routes + TvPlayerUiOwners.routes
}
