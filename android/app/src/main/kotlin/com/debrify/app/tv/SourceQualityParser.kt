package com.debrify.app.tv

/** Shared release-name quality parser for native Android TV source badges. */
internal object SourceQualityParser {
    private fun has(name: String, pattern: String): Boolean =
        Regex("(?:^|[^A-Za-z0-9])(?:$pattern)(?=$|[^A-Za-z0-9])", RegexOption.IGNORE_CASE)
            .containsMatchIn(name)

    fun badge(name: String): String? = when {
        has(name, "2160p") -> "4K"
        has(name, "1080p|1080i") -> "1080p"
        has(name, "720p|720i") -> "720p"
        has(name, "480p|576p|360p") -> "480p"
        has(name, "FHD|Full[ .-]?HD") -> "1080p"
        has(name, "4K|UHD") -> "4K"
        else -> null
    }
}
