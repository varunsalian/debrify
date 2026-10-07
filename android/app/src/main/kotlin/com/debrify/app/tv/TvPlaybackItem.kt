package com.debrify.app.tv

import org.json.JSONObject

/**
 * Merge a late cache/network snapshot into a playlist row. Non-current rows
 * honour explicit zeroes so a successful refresh can clear stale progress.
 * The currently playing row never moves behind the live player clock.
 */
internal fun mergeLateMetadataResumePosition(
    existingPositionMs: Long,
    incomingPositionMs: Long?,
    livePositionMs: Long,
    isCurrentItem: Boolean,
): Long {
    val snapshotPositionMs = incomingPositionMs ?: existingPositionMs
    return if (isCurrentItem) {
        maxOf(snapshotPositionMs, livePositionMs.coerceAtLeast(0L))
    } else {
        snapshotPositionMs
    }
}

/** Keep the live media duration authoritative while its item is playing. */
internal fun mergeLateMetadataDuration(
    existingDurationMs: Long,
    incomingDurationMs: Long?,
    liveDurationMs: Long,
    isCurrentItem: Boolean,
): Long {
    return if (isCurrentItem && liveDurationMs > 0L) {
        liveDurationMs
    } else {
        incomingDurationMs ?: existingDurationMs
    }
}

/** One episode of the show's full TVMaze list, for the episode guide. */
internal data class GuideEpisode(
    val shuffleEligible: Boolean = true,
    val season: Int,
    val episode: Int,
    val title: String?,
    val artwork: String?,
    val description: String?,
    val rating: Double?,
    val runtime: Int?,
    val resumePositionMs: Long?,
    val durationMs: Long?,
    val trackerProgressPercent: Double?,
    val watched: Boolean,
)

internal data class PlaybackItem(
    val id: String,
    val title: String,
    val url: String,
    val httpHeaders: Map<String, String> = emptyMap(),
    val mimeType: String? = null,
    // Optional adaptive pair for high-res YouTube: video-only track + separate
    // audio track, merged at playback. When absent, [url] (a muxed stream that
    // already has audio) is played as-is.
    val hdVideoUrl: String? = null,
    val audioUrl: String? = null,
    val index: Int,
    val season: Int?,
    val episode: Int?,
    val artwork: String?,
    val description: String?,
    val resumePositionMs: Long,
    val durationMs: Long,
    val updatedAt: Long,
    val resumeId: String?,
    val sizeBytes: Long?,
    val rating: Double?,
    val provider: String?,
    // Cross-device progress for this episode (0-100), or null. The legacy JSON
    // key is named traktProgressPercent, but Flutter sends the furthest of Trakt,
    // Simkl, and MDBList. Display-only fallback for the playlist bar and a resume source
    // when there's no local position.
    val traktProgressPercent: Double? = null,
    // Explicit local completion. Unlike tracker 100%, this must not yield to
    // an old partial position as an assumed active rewatch.
    val watched: Boolean = false,
    // Display policy is separate from live positions needed for source switching.
    val allowLocalProgressDisplay: Boolean = true,
    // The title as it arrived in the launch payload — on torrent launches the
    // release filename. Metadata pushes overwrite [title] with the fetched
    // episode name, so quality parsing (updateOttExtras) reads THIS, which
    // item.copy preserves across those updates.
    val sourceTitle: String? = null,
) {
    fun seasonEpisodeLabel(): String {
        return if (season != null && episode != null) {
            val seasonStr = season.toString().padStart(2, '0')
            val episodeStr = episode.toString().padStart(2, '0')
            "S${seasonStr}E${episodeStr}"
        } else {
            ""
        }
    }

    /** Playlist-bar progress percent: the FURTHER of the local resume ratio and
     *  the cross-device tracker percent, so the bar never shows less than what's
     *  actually been watched (local advances live; trackers are a launch snapshot).
     *  Exception: an active REWATCH — a tracker says finished (>=95) but there's a
     *  real in-progress local position — shows the live local percent, or the
     *  card would dim into the watched state while you're 20% into a rewatch. */
    fun displayProgressPercent(): Int {
        if (watched) return 100
        val local = if (allowLocalProgressDisplay && durationMs > 0 && resumePositionMs > 0) {
            ((resumePositionMs.toDouble() / durationMs.toDouble()) * 100).toInt()
        } else {
            0
        }
        val trakt = traktProgressPercent?.toInt() ?: 0
        // resumePositionMs > 0 (not local >= 1): a just-started rewatch of a long
        // episode truncates to local == 0% but is still an active rewatch —
        // matching the Dart series-browser's `local > 0` bound.
        if (allowLocalProgressDisplay && trakt >= 95 && resumePositionMs > 0 && local < 95) return local
        return maxOf(local, trakt)
    }

    companion object {
        fun fromJson(obj: JSONObject): PlaybackItem {
            return PlaybackItem(
                id = obj.optString("id"),
                title = obj.optString("title"),
                url = obj.optString("url"),
                httpHeaders = ProtectedStreamHttp.headers(obj.opt("httpHeaders")),
                hdVideoUrl = if (obj.has("hdVideoUrl")) obj.optString("hdVideoUrl").takeIf { it.isNotEmpty() } else null,
                audioUrl = if (obj.has("audioUrl")) obj.optString("audioUrl").takeIf { it.isNotEmpty() } else null,
                index = obj.optInt("index", 0),
                season = obj.optInt("season").takeIf { obj.has("season") },
                episode = obj.optInt("episode").takeIf { obj.has("episode") },
                artwork = if (obj.has("artwork")) obj.optString("artwork") else null,
                description = if (obj.has("description")) obj.optString("description") else null,
                resumePositionMs = obj.optLong("resumePositionMs", 0),
                durationMs = obj.optLong("durationMs", 0),
                updatedAt = obj.optLong("updatedAt", 0),
                resumeId = if (obj.has("resumeId")) obj.optString("resumeId") else null,
                sizeBytes = if (obj.has("sizeBytes")) obj.optLong("sizeBytes") else null,
                rating = if (obj.has("rating")) obj.optDouble("rating") else null,
                provider = if (obj.has("provider")) obj.optString("provider") else null,
                traktProgressPercent = if (obj.has("traktProgressPercent")) obj.optDouble("traktProgressPercent") else null,
                watched = obj.optBoolean("watched", false),
                allowLocalProgressDisplay = obj.optBoolean("allowLocalProgressDisplay", true),
                sourceTitle = obj.nullableString("sourceTitle")
                    ?: obj.optString("title").takeIf { it.isNotEmpty() },
            )
        }

        fun fromMap(map: Map<*, *>): PlaybackItem {
            val obj = JSONObject()
            for ((key, value) in map) {
                if (key is String) obj.put(key, value ?: JSONObject.NULL)
            }
            return fromJson(obj)
        }
    }
}

internal data class SeasonEpisode(
    val season: Int,
    val episode: Int,
)
