package com.debrify.app.tv

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable

/**
 * The in-player IPTV guide look, mirroring the Dart player's
 * `PlayerGuideStyle` (lib/screens/video_player/widgets/player_guide_style.dart).
 * Read once at activity launch from `flutter.iptv_player_guide_style` in
 * FlutterSharedPreferences — changing the setting applies to the next
 * playback session.
 *
 * CLASSIC takes the untouched legacy code paths everywhere: every restyled
 * builder/painter branches on `guideTokens == null` FIRST, and only the
 * styled branches read [GuideTokens]. Colors and font choices alone can't
 * select between the styled builds, so the style identity always travels
 * with the tokens.
 */
enum class GuideStyle {
    CLASSIC, GLASS, EDITION, CONSOLE;

    companion object {
        fun fromPref(raw: String?): GuideStyle = when (raw) {
            "glass" -> GLASS
            "edition" -> EDITION
            "console" -> CONSOLE
            else -> CLASSIC
        }
    }
}

/**
 * Kotlin mirror of the Dart `PlayerGuideTokens` presets — the SAME hex
 * values, so both players' guides read as one design. Panels carry
 * pre-multiplied over-video translucency exactly like the Dart side.
 *
 * Font values are file names under `flutter_assets/assets/fonts/` (the
 * bundled TTFs); null = default typeface. The activity owns the Typeface
 * cache — see `guideTypeface`.
 */
class GuideTokens(
    val bg: Int,
    val panel: Int,
    val fg: Int,
    val fgMid: Int,
    val fgDim: Int,
    val fgFaint: Int,
    val hairline: Int,
    val hairline2: Int,
    val accent: Int,
    val rec: Int,
    val live: Int,
    val selectedTint: Int,
    val focusTint: Int,
    val headlineFont: String? = null,
    val captionFont: String? = null,
    val nameFont: String? = null,
    val monoFont: String? = null,
) {
    companion object {
        /** Cinema Glass — translucent deep panels, one restrained violet. */
        val GLASS = GuideTokens(
            bg = 0xFF0A0C12.toInt(),
            panel = 0xF20E1118.toInt(),
            fg = 0xFFF2F5FA.toInt(),
            fgMid = 0xCCF2F5FA.toInt(),
            fgDim = 0x8CF2F5FA.toInt(),
            fgFaint = 0x54F2F5FA.toInt(),
            hairline = 0x16FFFFFF,
            hairline2 = 0x2BFFFFFF,
            accent = 0xFF8F7BFF.toInt(),
            rec = 0xFFFF4545.toInt(),
            live = 0xFF34D399.toInt(),
            selectedTint = 0x148F7BFF,
            focusTint = 0x0F8F7BFF,
        )

        /** Midnight Edition — ink, cream ramp, Fraunces serif. */
        val EDITION = GuideTokens(
            bg = 0xF00D0B09.toInt(),
            panel = 0xF2141110.toInt(),
            fg = 0xFFF3EEE3.toInt(),
            fgMid = 0xCCF3EEE3.toInt(),
            fgDim = 0x8CF3EEE3.toInt(),
            fgFaint = 0x59F3EEE3.toInt(),
            hairline = 0x17F3EEE3,
            hairline2 = 0x29F3EEE3,
            accent = 0xFFF3EEE3.toInt(), // paper — edition has no color accent
            rec = 0xFFE5484D.toInt(),
            live = 0xFFB8C79B.toInt(),
            selectedTint = 0x0DF3EEE3,
            focusTint = 0x09F3EEE3,
            headlineFont = "Fraunces72pt-Regular.ttf",
            captionFont = "Fraunces9pt-Italic.ttf",
        )

        /** Master Control — black instrument, amber time machinery, mono. */
        val CONSOLE = GuideTokens(
            bg = 0xF2050505.toInt(),
            panel = 0xF50A0A0A.toInt(),
            fg = 0xFFEDEDED.toInt(),
            fgMid = 0xB3EDEDED.toInt(),
            fgDim = 0x73EDEDED.toInt(),
            fgFaint = 0x47EDEDED.toInt(),
            hairline = 0x14FFFFFF,
            hairline2 = 0x26FFFFFF,
            accent = 0xFFF2A93B.toInt(),
            rec = 0xFFFF4545.toInt(),
            live = 0xFF34D399.toInt(),
            selectedTint = 0x0FF2A93B,
            focusTint = 0x0DF2A93B,
            nameFont = "SpaceGrotesk-Bold.ttf",
            monoFont = "JetBrainsMono-Regular.ttf",
        )

        fun of(style: GuideStyle): GuideTokens? = when (style) {
            GuideStyle.CLASSIC -> null
            GuideStyle.GLASS -> GLASS
            GuideStyle.EDITION -> EDITION
            GuideStyle.CONSOLE -> CONSOLE
        }
    }

    /** Panels are FLATTENED to opaque where a surface must not show video
     *  through (dialogs, popup menus) — same trick as the Dart side. */
    val panelOpaque: Int get() = panel or 0xFF000000.toInt()

    /** A fresh panel drawable — fill, hairline stroke, per-style radius.
     *  Always built new; styled code never mutates a shared XML drawable. */
    fun panelDrawable(radiusPx: Float, strokePx: Int): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = radiusPx
            setColor(panel)
            setStroke(strokePx, hairline2)
        }

    /** Quiet fill used for tiles/fields (logo tiles, search, chips). */
    fun tileDrawable(radiusPx: Float, strokePx: Int, fill: Int = selectedTint): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = radiusPx
            setColor(fill)
            setStroke(strokePx, hairline)
        }

    /**
     * Focusable-control background: focused = inverse chip ([fg] fill, so
     *  the label paints in [bg]); selected = [selectedTint]; idle = subtle
     *  [focusTint]. The same grammar the legacy cream-on-focus selector
     *  uses, re-tinted per style.
     */
    fun buttonBackground(radiusPx: Float): StateListDrawable =
        StateListDrawable().apply {
            addState(
                intArrayOf(android.R.attr.state_focused),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(fg)
                },
            )
            addState(
                intArrayOf(android.R.attr.state_selected),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(selectedTint)
                    setStroke(1, hairline2)
                },
            )
            addState(
                intArrayOf(),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(focusTint)
                    setStroke(1, hairline)
                },
            )
        }

    /** Text/icon color companion to [buttonBackground]: dark-on-fill when
     *  focused, [fg] when selected, [fgDim] idle. */
    fun buttonTextColors(): ColorStateList = ColorStateList(
        arrayOf(
            intArrayOf(android.R.attr.state_focused),
            intArrayOf(android.R.attr.state_selected),
            intArrayOf(),
        ),
        intArrayOf(bg or 0xFF000000.toInt(), fg, fgDim),
    )

    /** Channel/EPG row background: transparent idle, [focusTint] + accent
     *  stroke when focused, quiet [selectedTint] when selected (the airing
     *  programme row). Built fresh per holder. */
    fun rowBackground(radiusPx: Float, strokePx: Int): StateListDrawable =
        StateListDrawable().apply {
            addState(
                intArrayOf(android.R.attr.state_focused),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(focusTint)
                    setStroke(strokePx, accent)
                },
            )
            addState(
                intArrayOf(android.R.attr.state_selected),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(selectedTint)
                },
            )
            addState(
                intArrayOf(),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(Color.TRANSPARENT)
                },
            )
        }

    /** Search-field background: hairline idle, accent stroke on focus. */
    fun searchDrawable(radiusPx: Float): StateListDrawable =
        StateListDrawable().apply {
            addState(
                intArrayOf(android.R.attr.state_focused),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(focusTint)
                    setStroke(2, accent)
                },
            )
            addState(
                intArrayOf(),
                GradientDrawable().apply {
                    cornerRadius = radiusPx
                    setColor(focusTint)
                    setStroke(1, hairline)
                },
            )
        }
}
