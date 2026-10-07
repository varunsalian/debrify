package com.debrify.app.tv

/** "Seven" for 7 — MARQUEE's spelled-out season/episode line. Numbers a
     *  playbill wouldn't spell (50+) fall back to digits. */
internal fun spellNumber(n: Int?): String {
    if (n == null) return ""
    val ones = arrayOf(
        "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
        "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen",
        "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen",
    )
    return when {
        n < 0 || n >= 50 -> n.toString()
        n < 20 -> ones[n]
        else -> {
            val tens = if (n < 30) "Twenty" else if (n < 40) "Thirty" else "Forty"
            if (n % 10 == 0) tens else "$tens-${ones[n % 10]}"
        }
    }
}

internal fun getAcceleratedSeekStep(repeatCount: Int): Long {
    val baseStep = 10_000L          // 10 seconds
    val acceleration = 2_000L       // 2 seconds per repeat
    val maxStep = 120_000L          // 2 minutes cap

    val calculatedStep = baseStep + (repeatCount * acceleration)
    return calculatedStep.coerceAtMost(maxStep)
}

// Utilities
internal fun formatTime(ms: Long): String {
    if (ms <= 0) return "00:00"
    val totalSeconds = ms / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    val hours = minutes / 60
    return if (hours > 0) {
        String.format("%d:%02d:%02d", hours, minutes % 60, seconds)
    } else {
        String.format("%02d:%02d", minutes, seconds)
    }
}
