package com.debrify.app.tv

/**
 * The native player's control skin, selected by the Dart-side Appearance
 * setting `tv_player_controls_style` and read once at activity launch via
 * `ProfilePreferenceProjection` — changing it applies to the next playback
 * session.
 *
 * CLASSIC is today's Cinema Mode controller layout, byte-for-byte: the OTT
 * skin exists as a SECOND controller layout (`view_debrify_tv_ott_controls`)
 * swapped in before any view binding, and every behavioral difference lives
 * behind an `if (skin == OTT)` branch with the classic body untouched — the
 * same discipline [GuideStyle] documents.
 *
 * OTT mirrors the Flutter player's Apple TV transport dock
 * (lib/screens/video_player/widgets/tv_controls.dart): circular buttons with
 * a shared focus caption, identity row in the dock, 3→6dp progress bar and a
 * cinema-scrub preview chip.
 *
 * Unknown raw values resolve to OTT — the Dart setter coerces on write too,
 * so the two readers can never disagree about the default.
 */
enum class TvControlsSkin {
    CLASSIC, OTT;

    companion object {
        const val PREF_KEY = "tv_player_controls_style"

        fun fromPref(raw: String?): TvControlsSkin = when (raw) {
            "classic" -> CLASSIC
            else -> OTT
        }
    }
}
