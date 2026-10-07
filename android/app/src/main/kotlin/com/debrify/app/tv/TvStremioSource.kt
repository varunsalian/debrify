package com.debrify.app.tv

import org.json.JSONObject

// ═══════════════════════════════════════════════════════════════════════
// Stremio Source Switcher — Data model and adapter
// ═══════════════════════════════════════════════════════════════════════

internal data class StremioSource(
    val index: Int,
    val name: String,
    val infohash: String,
    val directUrl: String?,
    val httpHeaders: Map<String, String> = emptyMap(),
    val streamType: String,  // "torrent", "directUrl"
    val sizeBytes: Long,
    val seeders: Int,
    val source: String?,
    val addonId: String? = null,
    val quality: String,     // parsed: "4K", "1080p", "720p", "480p", "HD"
    // Coverage stamped by the Dart search engines: 'completeSeries',
    // 'multiSeasonPack', 'seasonPack', 'singleEpisode', or null (unknown).
    val coverageType: String? = null,
    val badgeDescription: String? = null,
    val videoId: String? = null,
    val addonPresentation: Pair<String, String?>? = null,
    val addonDisplayName: String? = null,
    val addonLogo: String? = null,
    val hasRealInfoHash: Boolean = true,
    val addonKey: String? = null,
) {
    fun failureKey(reason: String = "") = startupFailureKey(addonKey ?: addonId ?: source, name, sizeBytes, streamType, reason,
        videoId, if (hasRealInfoHash) infohash else null, directUrl)
    val isDirectStream: Boolean get() = streamType == "directUrl"

    /** Season/series-pack coverage — drives the series source-tab split. */
    val isSeasonPack: Boolean get() = coverageType == "seasonPack" ||
        coverageType == "multiSeasonPack" || coverageType == "completeSeries"

    val displayTitle: String get() {
        val newlineIdx = name.indexOf('\n')
        if (newlineIdx <= 0) return name
        val firstLine = name.substring(0, newlineIdx).trim()
        val rest = name.substring(newlineIdx + 1).trim()
        // If first line is just the addon/source name, use the rest instead
        return if (rest.isNotEmpty() && (firstLine.equals(source, ignoreCase = true) ||
                firstLine.length < 20 && rest.length > firstLine.length)) rest.split('\n').first().trim()
            else firstLine
    }

    val formattedSize: String? get() {
        if (sizeBytes <= 0) return null
        val gb = sizeBytes / (1024.0 * 1024.0 * 1024.0)
        val mb = sizeBytes / (1024.0 * 1024.0)
        return if (gb >= 1.0) String.format("%.1f GB", gb) else String.format("%.0f MB", mb)
    }

    companion object {
        fun fromJson(obj: JSONObject, index: Int): StremioSource {
            val name = obj.optString("name", "")
            return StremioSource(
                index = index,
                name = name,
                infohash = obj.optString("infohash", ""),
                hasRealInfoHash = obj.optBoolean("has_real_infohash", true),
                addonKey = obj.optString("stremio_addon_key").takeIf { it.isNotEmpty() },
                directUrl = obj.optString("direct_url").takeIf { it.isNotEmpty() },
                httpHeaders = ProtectedStreamHttp.headers(obj.opt("http_headers")),
                streamType = obj.optString("stream_type", "torrent"),
                sizeBytes = obj.optLong("size_bytes", 0),
                seeders = obj.optInt("seeders", 0),
                source = obj.optString("source").takeIf { it.isNotEmpty() },
                addonId = obj.optString("stremio_addon_id").takeIf { it.isNotEmpty() },
                quality = parseQuality(name),
                coverageType = obj.optString("coverage_type").takeIf { it.isNotEmpty() },
                badgeDescription = sourceBadgeDescription(obj.optString("stream_label"), obj.optString("stream_description")),
                videoId = obj.optString("stremio_video_id").takeIf { it.isNotEmpty() },
                addonPresentation = sourceAddonPresentation(obj.nullableString("stream_label"), obj.nullableString("stream_original_title"), obj.nullableString("stream_description")),
                addonDisplayName = obj.nullableString("addon_display_name"),
                addonLogo = obj.nullableString("addon_logo"),
            )
        }

        fun fromMap(map: Map<*, *>, index: Int): StremioSource {
            val name = (map["name"] as? String) ?: ""
            return StremioSource(
                index = index,
                name = name,
                infohash = (map["infohash"] as? String) ?: "",
                hasRealInfoHash = (map["has_real_infohash"] as? Boolean) ?: true,
                addonKey = (map["stremio_addon_key"] as? String)?.takeIf { it.isNotEmpty() },
                directUrl = (map["direct_url"] as? String)?.takeIf { it.isNotEmpty() },
                httpHeaders = ProtectedStreamHttp.headers(map["http_headers"]),
                streamType = (map["stream_type"] as? String) ?: "torrent",
                sizeBytes = (map["size_bytes"] as? Number)?.toLong() ?: 0,
                seeders = (map["seeders"] as? Number)?.toInt() ?: 0,
                source = (map["source"] as? String)?.takeIf { it.isNotEmpty() },
                addonId = (map["stremio_addon_id"] as? String)?.takeIf { it.isNotEmpty() },
                quality = parseQuality(name),
                coverageType = (map["coverage_type"] as? String)?.takeIf { it.isNotEmpty() },
                badgeDescription = sourceBadgeDescription(map["stream_label"] as? String, map["stream_description"] as? String),
                videoId = map["stremio_video_id"] as? String,
                addonPresentation = sourceAddonPresentation(map["stream_label"] as? String, map["stream_original_title"] as? String, map["stream_description"] as? String),
                addonDisplayName = map["addon_display_name"] as? String,
                addonLogo = map["addon_logo"] as? String,
            )
        }

        fun parseQuality(name: String): String {
            return SourceQualityParser.badge(name) ?: "HD"
        }
    }
}
