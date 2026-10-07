package com.debrify.app.tv

import com.debrify.app.MainActivity

internal fun requestStreamFromFlutter(item: PlaybackItem, index: Int, callback: (String?, String?) -> Unit) {
    try {
        val args = hashMapOf<String, Any?>(
            "resumeId" to item.resumeId,
            "itemId" to item.id,
            "index" to index
        )
        android.util.Log.d("AndroidTvPlayer", "requestStreamFromFlutter - sending to Flutter: resumeId=${item.resumeId}, itemId=${item.id}, index=$index")

        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "requestTorrentStream",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    android.util.Log.d("AndroidTvPlayer", "requestStreamFromFlutter - Flutter returned: $result")
                    val map = result as? Map<*, *>
                    val url = map?.get("url") as? String
                    val provider = map?.get("provider") as? String
                    android.util.Log.d("AndroidTvPlayer", "requestStreamFromFlutter - extracted URL: $url, provider: $provider")
                    callback(url, provider)
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    android.util.Log.e("AndroidTvPlayer", "requestStreamFromFlutter - error: $errorCode - $errorMessage")
                    callback(null, null)
                }

                override fun notImplemented() {
                    android.util.Log.e("AndroidTvPlayer", "requestStreamFromFlutter - not implemented")
                    callback(null, null)
                }
            }
        )
    } catch (e: Exception) {
        android.util.Log.e("AndroidTvPlayer", "requestStreamFromFlutter - exception: ${e.message}", e)
        callback(null, null)
    }
}

/**
     * Request movie metadata (IMDB ID) from Flutter for the given item.
     * Used for movie collections to fetch per-item IMDB IDs from Cinemeta.
     */
internal fun requestMovieMetadataFromFlutter(item: PlaybackItem, index: Int, callback: (String?) -> Unit) {
    try {
        val args = hashMapOf<String, Any?>(
            "index" to index,
            "filename" to item.title
        )
        android.util.Log.d("MovieMetadata", "requestMovieMetadataFromFlutter - index=$index, filename=${item.title}")

        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "requestMovieMetadata",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    android.util.Log.d("MovieMetadata", "requestMovieMetadataFromFlutter - Flutter returned: $result")
                    val map = result as? Map<*, *>
                    val imdbId = map?.get("imdbId") as? String
                    android.util.Log.d("MovieMetadata", "requestMovieMetadataFromFlutter - extracted imdbId: $imdbId")
                    callback(imdbId)
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    android.util.Log.e("MovieMetadata", "requestMovieMetadataFromFlutter - error: $errorCode - $errorMessage")
                    callback(null)
                }

                override fun notImplemented() {
                    android.util.Log.e("MovieMetadata", "requestMovieMetadataFromFlutter - not implemented")
                    callback(null)
                }
            }
        )
    } catch (e: Exception) {
        android.util.Log.e("MovieMetadata", "requestMovieMetadataFromFlutter - exception: ${e.message}", e)
        callback(null)
    }
}

/**
     * Ask Flutter for a channel's guide data. Always answers asynchronously
     * on the main thread — the failure paths are posted on purpose, because
     * the callback runs notifyItemChanged and a synchronous invocation from
     * onBindViewHolder would fire it while RecyclerView is computing layout
     * (IllegalStateException). MethodChannel results are async already.
     */
internal fun requestIptvEpg(
    entry: IptvChannelEntry,
    includeSchedule: Boolean,
    includeCatchupMetadata: Boolean = entry.isCurrent,
    callback: (Map<*, *>?) -> Unit,
) {
    // Deliver exactly once, and ALWAYS: a MethodChannel whose engine died
    // in the background never invokes its Result (the messenger is gone),
    // which used to leave entry.epgLoading stuck true for the whole
    // session — i.e. "EPG missing everywhere on TV" with playback fine.
    // The watchdog turns that silence into a null answer so rows recover
    // (and retry once the engine is back).
    //
    // 45s, NOT a snappy timeout: the Dart side's legitimate worst case is
    // a queue wait behind its 3-slot fetch gate plus two 10s HTTP tries
    // (data-table + typo fallback) — a shorter deadline would discard
    // real answers from slow panels and report "no guide data" wrongly.
    // The watchdog only exists for the dead-engine hang, where nothing
    // ever arrives; slow-but-alive answers must win.
    val handler = android.os.Handler(android.os.Looper.getMainLooper())
    val delivered = java.util.concurrent.atomic.AtomicBoolean(false)
    fun deliver(result: Map<*, *>?) {
        if (delivered.compareAndSet(false, true)) callback(result)
    }
    handler.postDelayed({ deliver(null) }, 45_000)
    try {
        val args = hashMapOf<String, Any?>(
            "channelUrl" to entry.url,
            "includeSchedule" to includeSchedule,
            "includeCatchupMetadata" to includeCatchupMetadata,
            "archiveDisabled" to (entry.tvArchive == "0"),
            "archiveDurationDays" to entry.tvArchiveDuration,
        )
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            handler.post { deliver(null) }
            return
        }
        channel.invokeMethod(
            "requestIptvEpg",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    deliver(result as? Map<*, *>)
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    android.util.Log.e("AndroidTvPlayer", "requestIptvEpg error: $errorCode - $errorMessage")
                    deliver(null)
                }

                override fun notImplemented() {
                    deliver(null)
                }
            }
        )
    } catch (e: Exception) {
        android.util.Log.e("AndroidTvPlayer", "requestIptvEpg exception: ${e.message}", e)
        handler.post { deliver(null) }
    }
}

/** One playable link for a Stremio channel: stream URL + the addon's label. */
internal data class IptvStremioCandidate(val url: String, val label: String)

/**
     * Ask Flutter to resolve a stremio-tv:// channel key into labeled stream
     * links. On an empty result the callback's second argument carries a
     * user-facing reason ("Couldn't reach <addon>…") when Flutter knows one.
     */
internal fun requestIptvStreamUrls(
    channelUrl: String,
    channelName: String?,
    callback: (List<IptvStremioCandidate>, String?) -> Unit,
) {
    try {
        val args = hashMapOf<String, Any?>(
            "channelUrl" to channelUrl,
            "channelName" to channelName,
        )
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            callback(emptyList(), null)
            return
        }
        channel.invokeMethod(
            "requestIptvStreamUrls",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    val map = result as? Map<*, *>
                    val candidates = (map?.get("candidates") as? List<*>)?.mapNotNull { item ->
                        val m = item as? Map<*, *> ?: return@mapNotNull null
                        val u = (m["url"] as? String)?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                        val label = (m["label"] as? String)?.takeIf { it.isNotBlank() } ?: "Source"
                        IptvStremioCandidate(u, label)
                    } ?: emptyList()
                    val message = (map?.get("message") as? String)?.takeIf { it.isNotBlank() }
                    callback(candidates, message)
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    android.util.Log.e("AndroidTvPlayer", "requestIptvStreamUrls error: $errorCode - $errorMessage")
                    callback(emptyList(), null)
                }

                override fun notImplemented() {
                    callback(emptyList(), null)
                }
            }
        )
    } catch (e: Exception) {
        android.util.Log.e("AndroidTvPlayer", "requestIptvStreamUrls exception: ${e.message}", e)
        callback(emptyList(), null)
    }
}

/** Fire-and-forget outcome report (winner caching / invalidation). */
internal fun reportIptvStreamResult(channelUrl: String, url: String?, success: Boolean) {
    try {
        val args = hashMapOf<String, Any?>(
            "channelUrl" to channelUrl,
            "url" to url,
            "success" to success,
        )
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("reportIptvStreamResult", args)
    } catch (e: Exception) {
        android.util.Log.w("AndroidTvPlayer", "reportIptvStreamResult failed: ${e.message}")
    }
}

internal fun requestQuickPlayNextEpisode(imdbId: String, season: Int, episode: Int) {
    android.util.Log.d("AndroidTvPlayer", "Requesting Quick Play next episode after S${season}E${episode} for $imdbId")
    MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
        "requestQuickPlayNextEpisode",
        hashMapOf<String, Any>(
            "imdbId" to imdbId,
            "season" to season,
            "episode" to episode,
        )
    )
}
