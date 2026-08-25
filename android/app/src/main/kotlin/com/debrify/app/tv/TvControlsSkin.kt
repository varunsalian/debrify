package com.debrify.app.tv

/**
 * The native player's control skin, selected by the Dart-side Appearance
 * setting `tv_player_controls_style` and read once at activity launch via
 * `ProfilePreferenceProjection` — changing it applies to the next playback
 * session.
 *
 * CLASSIC is today's Cinema Mode controller layout, byte-for-byte: every
 * other skin is a SECOND controller layout swapped in before any view
 * binding, and every behavioral difference lives behind an
 * `if (dockSkinInstalled)` / `when (installedSkin)` branch with the classic
 * body untouched — the same discipline [GuideStyle] documents.
 *
 * The dock family (everything except CLASSIC) shares the OTT skin's seam:
 * one layout per skin reusing every legacy id plus zero-size stubs, one
 * icon family per visual language (`ic_dock_*` solid-rounded, `ic_wire_*`
 * hairline for MARQUEE), behavior driven by [AndroidTvTorrentPlayerActivity]'s
 * per-skin spec:
 *
 *  - OTT       — the Apple TV transport dock (tv_controls.dart) port.
 *  - FROST     — floating translucent panel inset from the screen edges.
 *  - MARQUEE   — editorial serif, bare glyphs, underline focus.
 *  - BROADCAST — labeled pill buttons, flipped show-first identity.
 *  - PULSE     — accent-glow bar and focus rings in the app indigo.
 *  - TICKET    — single opaque band with the progress line on its top edge.
 *
 * Unknown raw values resolve to MARQUEE — the Dart setter coerces on write too,
 * so the two readers can never disagree about the default.
 */
enum class TvControlsSkin {
    CLASSIC, OTT, FROST, MARQUEE, BROADCAST, PULSE, TICKET;

    companion object {
        const val PREF_KEY = "tv_player_controls_style"

        fun fromPref(raw: String?): TvControlsSkin = when (raw) {
            "classic" -> CLASSIC
            "ott" -> OTT
            "frost" -> FROST
            "broadcast" -> BROADCAST
            "pulse" -> PULSE
            "ticket" -> TICKET
            else -> MARQUEE
        }
    }
}
