package com.debrify.app.tv

/**
 * Release-name format tags for the premium dock skins' quality badges —
 * a native port of the Dart `FormatTagDetector` subset the dock renders:
 * resolution, HDR flavor, audio format (in that display order, one per
 * group, max 3). Resolution delegates to [SourceQualityParser] so the
 * "UHD names the source" trap stays handled in exactly one place
 * (e.g. "UHD BluRay 1080p" is 1080p, not 4K).
 *
 * Each tag carries a SHORT form (chips: "DV", "ATMOS") and a LONG form
 * (Marquee's serif print line: "Dolby Vision", "Atmos").
 */
internal object DockFormatTags {
    data class Tag(val short: String, val long: String)

    /** Dart `_has` boundary rule: no letter/digit before the token, no
     *  LETTER after — digit suffixes pass (DD5.1, HDR10) but "HDRip" never
     *  matches "HDR". */
    private fun has(name: String, pattern: String): Boolean =
        Regex("(?:^|[^A-Za-z0-9])(?:$pattern)(?![A-Za-z])", RegexOption.IGNORE_CASE)
            .containsMatchIn(name)

    fun detect(rawName: String): List<Tag> {
        // Multi-line pack names: only the first line describes the release.
        val name = rawName.lineSequence().firstOrNull()?.trim().orEmpty()
        if (name.isEmpty()) return emptyList()
        val tags = mutableListOf<Tag>()

        SourceQualityParser.badge(name)?.let { badge ->
            tags.add(Tag(badge, badge))
        }

        val hdr = when {
            has(name, "DV|Dolby[ ._-]?Vision|DoVi") -> Tag("DV", "Dolby Vision")
            has(name, "HDR10\\+|HDR10Plus") -> Tag("HDR10+", "HDR10+")
            has(name, "HDR10") -> Tag("HDR10", "HDR10")
            has(name, "HLG") -> Tag("HLG", "HLG")
            has(name, "HDR") -> Tag("HDR", "HDR")
            else -> null
        }
        hdr?.let { tags.add(it) }

        val audio = when {
            has(name, "Atmos") -> Tag("ATMOS", "Atmos")
            has(name, "True[ ._-]?HD") -> Tag("TRUEHD", "TrueHD")
            has(name, "DTS[ ._-]?HD[ ._-]?MA|DTS[ ._-]?HD[ ._-]?Master") ->
                Tag("DTS-HD MA", "DTS-HD MA")
            has(name, "DTS[ ._-]?HD") -> Tag("DTS-HD", "DTS-HD")
            has(name, "DTS") -> Tag("DTS", "DTS")
            has(name, "DD\\+|DDP|E[ ._-]?AC[ ._-]?3|EAC3") -> Tag("DD+", "Dolby Digital Plus")
            has(name, "DD|AC[ ._-]?3|Dolby[ ._-]?Digital") -> Tag("DD", "Dolby Digital")
            has(name, "AAC") -> Tag("AAC", "AAC")
            else -> null
        }
        audio?.let { tags.add(it) }

        return tags
    }
}
