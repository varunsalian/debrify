package com.debrify.app.tv

/**
     * True when [url] is a SEGMENTED (adaptive) stream: HLS, DASH,
     * SmoothStreaming. Neither recorder can capture those byte-for-byte — the
     * manifest and the media segments live at different URIs, so a raw capture
     * would be the manifest alone, an XML/text file wearing a .ts name.
     */
internal fun isSegmentedStreamUrl(url: String): Boolean {
    val path = url.substringBefore('?').substringBefore('#').lowercase()
    return path.endsWith(".m3u8") ||
        path.endsWith(".m3u") ||
        path.endsWith(".mpd") ||
        path.endsWith(".ism") ||
        path.endsWith(".isml") ||
        path.endsWith("/manifest")
}

/**
     * Xtream panels serve every live channel in both containers — the `.ts`
     * twin of a `/live/user/pass/id.m3u8` URL is the same channel as one
     * progressive MPEG-TS stream, which IS engine-recordable. Strict path
     * match only, and never for URLs carrying a query string (a twin stripped
     * of its token would just 401); anything else returns null.
     */
internal fun xtreamTsTwin(url: String): String? {
    if (url.contains('?')) return null
    val clean = url.substringBefore('#')
    val m = Regex(
        "^(https?://[^/]+)/live/([^/]+)/([^/]+)/([^/.]+)\\.m3u8$",
        RegexOption.IGNORE_CASE,
    ).find(clean) ?: return null
    val (host, user, pass, id) = m.destructured
    return "$host/live/$user/$pass/$id.ts"
}

internal fun sanitizeRecordingName(raw: String): String {
    val cleaned = raw.replace(Regex("[^A-Za-z0-9 _-]"), "")
        .trim()
        .replace(Regex("\\s+"), "_")
    return cleaned.take(60).ifEmpty { "recording" }
}

internal fun recordingTimestamp(): String =
    java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US)
        .format(java.util.Date())
