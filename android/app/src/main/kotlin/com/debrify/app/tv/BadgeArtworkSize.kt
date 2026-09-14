package com.debrify.app.tv

import kotlin.math.roundToInt

/** Fit the logo to the chip height without making short badges full-width. */
internal fun badgeArtworkWidth(width: Int, height: Int, contentHeight: Int, maxWidth: Int): Int {
    val minimum = contentHeight.coerceAtMost(maxWidth).coerceAtLeast(0)
    if (width <= 0 || height <= 0) return minimum
    return (width.toDouble() / height * contentHeight).roundToInt().coerceIn(minimum, maxWidth.coerceAtLeast(minimum))
}
