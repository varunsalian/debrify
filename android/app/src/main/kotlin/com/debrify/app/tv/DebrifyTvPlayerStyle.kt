package com.debrify.app.tv

/**
 * Playback-screen style for the native Debrify TV player
 * ([TorboxTvPlayerActivity]).
 *
 * Mirrors the Flutter pref `debrify_tv_player_style` (see
 * `StorageService.getDebrifyTvPlayerStyle`); read once per player launch via
 * `ProfilePreferenceProjection.getString`. Unknown or unset coerces to
 * [CINEMA] on both sides so the two readers can never disagree about the
 * default.
 *
 * Contract (same discipline as [TvControlsSkin]):
 * - CLASSIC keeps the legacy controller layout + top marquee bar
 *   byte-for-byte; every premium behavior branches on this enum.
 * - Premium styles swap the media3 controller child
 *   (`view_debrify_tv_<style>_controls.xml`) BEFORE any controller-id
 *   findViewById, reusing every legacy id so bindings work unchanged, and
 *   render identity in the dock (the top broadcast bar never shows).
 */
enum class DebrifyTvPlayerStyle {
    CLASSIC,
    NETWORK,
    CINEMA,
    GUIDE,
    SPOTLIGHT,
    PRESTIGE;

    companion object {
        @JvmStatic
        fun fromPref(value: String?): DebrifyTvPlayerStyle = when (value) {
            "classic" -> CLASSIC
            "network" -> NETWORK
            "guide" -> GUIDE
            "spotlight" -> SPOTLIGHT
            "prestige" -> PRESTIGE
            else -> CINEMA
        }
    }
}
