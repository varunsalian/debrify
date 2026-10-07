package com.debrify.app.tv

import org.json.JSONArray
import org.json.JSONObject

internal fun parseIptvSources(array: JSONArray?): MutableList<IptvSourceEntry> {
    if (array == null) return mutableListOf()
    return MutableList(array.length()) { index ->
        val source = array.optJSONObject(index) ?: JSONObject()
        IptvSourceEntry(
            id = source.optString("id"),
            name = source.optString("name").ifEmpty { "IPTV" },
            isFavorites = source.optBoolean("isFavorites"),
            isContinue = source.optBoolean("isContinue"),
            isXtream = source.optBoolean("isXtream"),
            isList = source.optBoolean("isList"),
            listId = source.optString("listId").takeIf { it.isNotEmpty() },
            connectionResourceId = source.optString("connectionResourceId")
                .takeIf { it.isNotEmpty() },
            connectionResourceRevision = if (source.has("connectionResourceRevision"))
                source.optLong("connectionResourceRevision") else null,
        )
    }.filterTo(mutableListOf()) { it.id.isNotEmpty() && !it.isContinue }
}

internal fun parseIptvLists(array: JSONArray?): MutableList<IptvListEntry> {
    if (array == null) return mutableListOf()
    return MutableList(array.length()) { index ->
        val entry = array.optJSONObject(index) ?: JSONObject()
        IptvListEntry(
            id = entry.optString("id"),
            name = entry.optString("name").ifEmpty { "List" },
            isBuiltin = entry.optBoolean("isBuiltin"),
        )
    }.filterTo(mutableListOf()) { it.id.isNotEmpty() }
}

internal fun parseStringList(array: JSONArray?): MutableList<String> {
    if (array == null) return mutableListOf()
    return MutableList(array.length()) { index -> array.optString(index) }
        .filterTo(mutableListOf()) { it.isNotEmpty() }
}

internal fun parseIptvChannels(array: JSONArray): MutableList<IptvChannelEntry> =
    MutableList(array.length()) { index ->
        val channel = array.optJSONObject(index) ?: JSONObject()
        iptvChannelEntry(
            index = index,
            channelNumber = channel.optInt("channelNumber", 0).takeIf { it > 0 },
            name = channel.optString("name"),
            url = channel.optString("url"),
            logoUrl = channel.optString("logoUrl").takeIf { it.isNotEmpty() },
            group = channel.optString("group").takeIf { it.isNotEmpty() },
            contentType = channel.optString("contentType"),
            duration = channel.optInt("duration", -1),
            sourceId = channel.optString("sourceId").takeIf { it.isNotEmpty() },
            sourceName = channel.optString("sourceName").takeIf { it.isNotEmpty() },
            isFavorite = channel.optBoolean("isFavorite"),
            seriesId = channel.optString("seriesId").takeIf { it.isNotEmpty() },
            seriesName = channel.optString("seriesName").takeIf { it.isNotEmpty() },
            season = channel.optInt("season", -1).takeIf { it >= 0 },
            episode = channel.optInt("episode", -1).takeIf { it >= 0 },
            hasNextEpisode =
                channel.optBoolean("hasNextEpisode").takeIf {
                    channel.has("hasNextEpisode")
                },
            tvArchive = channel.optString("tvArchive")
                .takeIf { it.isNotEmpty() },
            tvArchiveDuration = channel.optInt("tvArchiveDuration", 0)
                .takeIf { it > 0 },
            resumePositionMs = channel.optLong("resumePositionMs", 0L),
            headers = channel.optJSONObject("httpHeaders")?.let { obj ->
                buildMap {
                    for (key in obj.keys()) {
                        obj.optString(key).takeIf { it.isNotEmpty() }?.let { value ->
                            put(
                                if (key.equals("User-Agent", ignoreCase = true)) {
                                    "User-Agent"
                                } else {
                                    key
                                },
                                value,
                            )
                        }
                    }
                }
            } ?: emptyMap(),
        )
    }

internal fun parseIptvChannels(raw: List<*>): MutableList<IptvChannelEntry> =
    raw.mapIndexedNotNullTo(mutableListOf()) { index, item ->
        val channel = item as? Map<*, *> ?: return@mapIndexedNotNullTo null
        val headers = (channel["httpHeaders"] as? Map<*, *>)?.entries
            ?.mapNotNull { (key, value) ->
                val name = key as? String ?: return@mapNotNull null
                val text = value?.toString()?.takeIf { it.isNotEmpty() }
                    ?: return@mapNotNull null
                (if (name.equals("User-Agent", ignoreCase = true)) {
                    "User-Agent"
                } else {
                    name
                }) to text
            }?.toMap() ?: emptyMap()
        iptvChannelEntry(
            index = index,
            channelNumber = (channel["channelNumber"] as? Number)
                ?.toInt()
                ?.takeIf { it > 0 },
            name = channel["name"] as? String ?: return@mapIndexedNotNullTo null,
            url = channel["url"] as? String ?: return@mapIndexedNotNullTo null,
            logoUrl = (channel["logoUrl"] as? String)?.takeIf { it.isNotEmpty() },
            group = (channel["group"] as? String)?.takeIf { it.isNotEmpty() },
            contentType = channel["contentType"] as? String ?: "",
            duration = (channel["duration"] as? Number)?.toInt() ?: -1,
            sourceId = (channel["sourceId"] as? String)?.takeIf { it.isNotEmpty() },
            sourceName = (channel["sourceName"] as? String)?.takeIf { it.isNotEmpty() },
            isFavorite = channel["isFavorite"] == true,
            seriesId = (channel["seriesId"] as? String)?.takeIf { it.isNotEmpty() },
            seriesName = (channel["seriesName"] as? String)?.takeIf { it.isNotEmpty() },
            season = (channel["season"] as? Number)?.toInt(),
            episode = (channel["episode"] as? Number)?.toInt(),
            hasNextEpisode = channel["hasNextEpisode"] as? Boolean,
            tvArchive = (channel["tvArchive"] as? String)
                ?.takeIf { it.isNotEmpty() },
            tvArchiveDuration = (channel["tvArchiveDuration"] as? Number)
                ?.toInt(),
            resumePositionMs =
                (channel["resumePositionMs"] as? Number)?.toLong() ?: 0L,
            headers = headers,
        )
    }

internal fun iptvChannelEntry(
    index: Int,
    channelNumber: Int?,
    name: String,
    url: String,
    logoUrl: String?,
    group: String?,
    contentType: String,
    duration: Int,
    sourceId: String?,
    sourceName: String?,
    isFavorite: Boolean,
    seriesId: String?,
    seriesName: String?,
    season: Int?,
    episode: Int?,
    hasNextEpisode: Boolean?,
    tvArchive: String?,
    tvArchiveDuration: Int?,
    resumePositionMs: Long,
    headers: Map<String, String>,
): IptvChannelEntry {
    val normalizedType = contentType.ifEmpty {
        if (duration == -1) "live" else "vod"
    }
    return IptvChannelEntry(
        index = index,
        channelNumber = channelNumber,
        name = name,
        url = url,
        logoUrl = logoUrl,
        group = group,
        isLive = normalizedType == "live",
        isCurrent = false,
        resumePositionMs = resumePositionMs,
        httpHeaders = headers,
        contentType = normalizedType,
        duration = duration,
        sourceId = sourceId,
        sourceName = sourceName,
        isFavorite = isFavorite,
        seriesId = seriesId,
        seriesName = seriesName,
        season = season,
        episode = episode,
        hasNextEpisode = hasNextEpisode,
        tvArchive = tvArchive,
        tvArchiveDuration = tvArchiveDuration,
    )
}
