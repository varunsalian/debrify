package com.debrify.app.tv

import android.os.Handler
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.debrify.app.MainActivity
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity.ShufflePlaybackAttempt
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity.TvSourceAddon

internal class TvSourceFetchController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val addonFetchState: MutableMap<String, String>
        val addonPackProbing: MutableSet<String>
        val currentIndex: Int
        var currentStremioSourceIndex: Int
        fun guideAdjacent(model: PlaybackPayload, currentItem: PlaybackItem?, direction: Int, allowResolverFallback: Boolean): SeasonEpisode?
        var isAutoAdvancing: Boolean
        var moreSourcesLoadingMode: String?
        var movieSourcesFetched: Boolean
        val payload: PlaybackPayload?
        val progressHandler: Handler
        var seriesEpisodesFetched: Boolean
        var seriesPacksFetched: Boolean
        fun showStatusPillTransient(message: String): Unit
        val sourceAddons: List<TvSourceAddon>
        val sourceBrowser: TvSourceBrowserController?
        val sourceSwitchController: TvSourceSwitchController
        val startupGateController: TvStartupGateController
        var stremioResolutionToken: Int
        val stremioSources: MutableList<StremioSource>
        val unifiedMenu: UnifiedMenuController?
        fun watchShufflePlayback(attempt: ShufflePlaybackAttempt): Unit
        fun yieldEpisodeFetchToQueuedShuffle(): Boolean
    }

    internal var episodeFetchInFlight = false

    /** In-player quick play of an episode that isn't in the playlist: asks
     * Flutter to find + resolve a source (existing packs → episode fetch →
     * pack fetch) and swaps playlists in place — no activity relaunch. */
    internal fun requestEpisodeFetch(
        season: Int,
        episode: Int,
        autoAdvance: Boolean = false,
        suppressResume: Boolean = autoAdvance,
        shuffleAttempt: ShufflePlaybackAttempt? = null,
        onUnavailable: (() -> Unit)? = null,
        shouldContinue: (() -> Boolean)? = null,
    ) {
        if (episodeFetchInFlight) return
        val label = String.format(java.util.Locale.US, "S%02dE%02d", season, episode)
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            host.showStatusPillTransient("Couldn't fetch $label")
            return
        }
        episodeFetchInFlight = true
        val token = ++host.stremioResolutionToken
        host.showStatusPillTransient("Fetching $label…")
        channel.invokeMethod(
            "requestEpisodeFetch",
            hashMapOf<String, Any>("season" to season, "episode" to episode),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    activity.runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != host.stremioResolutionToken || shouldContinue?.invoke() == false) return@runOnUiThread
                        if (host.yieldEpisodeFetchToQueuedShuffle()) return@runOnUiThread
                        val map = result as? Map<*, *>
                        val items = map?.get("items") as? List<*>
                        val fetchedSourceIndex = (map?.get("sourceIndex") as? Number)?.toInt()
                        if (map == null || items.isNullOrEmpty() || fetchedSourceIndex == null) {
                            if (onUnavailable != null) onUnavailable()
                            else host.showStatusPillTransient("No playable source found for $label")
                            return@runOnUiThread
                        }
                        host.isAutoAdvancing = autoAdvance
                        adoptSourceList(map)
                        if (shuffleAttempt != null) host.watchShufflePlayback(shuffleAttempt)
                        host.sourceSwitchController.applier.switchToSourcePlaylist(
                            fetchedSourceIndex,
                            items,
                            targetSeason = season,
                            targetEpisode = episode,
                            suppressTargetResume = suppressResume,
                            shuffleAttempt = shuffleAttempt,
                        )
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    activity.runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != host.stremioResolutionToken || shouldContinue?.invoke() == false) return@runOnUiThread
                        if (onUnavailable != null) onUnavailable()
                        else host.showStatusPillTransient("No playable source found for $label")
                    }
                }

                override fun notImplemented() {
                    activity.runOnUiThread {
                        episodeFetchInFlight = false
                        host.showStatusPillTransient("Couldn't fetch $label")
                    }
                }
            }
        )
    }

    /** Guide-not-ready Next for a catalog series. Flutter resolves the next
     * identity and runs the normal in-player episode source ladder. */
    internal fun requestAdjacentEpisodeFetch(
        imdbId: String?,
        currentSeason: Int,
        currentEpisode: Int,
        autoAdvance: Boolean = false,
        direction: Int = 1,
    ) {
        if (episodeFetchInFlight) return
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            host.showStatusPillTransient("Couldn't fetch next episode")
            return
        }
        episodeFetchInFlight = true
        val token = ++host.stremioResolutionToken
        val directionLabel = if (direction < 0) "previous" else "next"
        host.showStatusPillTransient("Finding $directionLabel episode…")
        channel.invokeMethod(
            "requestEpisodeFetch",
            hashMapOf<String, Any>(
                "currentSeason" to currentSeason,
                "currentEpisode" to currentEpisode,
                "direction" to direction,
            ).apply {
                if (imdbId != null) put("imdbId", imdbId)
            },
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    activity.runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != host.stremioResolutionToken) return@runOnUiThread
                        if (host.yieldEpisodeFetchToQueuedShuffle()) return@runOnUiThread
                        val map = result as? Map<*, *>
                        val items = map?.get("items") as? List<*>
                        val fetchedSourceIndex = (map?.get("sourceIndex") as? Number)?.toInt()
                        if (map == null || items.isNullOrEmpty() || fetchedSourceIndex == null) {
                            host.showStatusPillTransient("No playable $directionLabel episode found")
                            return@runOnUiThread
                        }
                        val targetSeason = (map["targetSeason"] as? Number)?.toInt()
                        val targetEpisode = (map["targetEpisode"] as? Number)?.toInt()
                        if (targetSeason == null || targetEpisode == null) {
                            host.showStatusPillTransient("No playable $directionLabel episode found")
                            return@runOnUiThread
                        }
                        adoptSourceList(map)
                        host.sourceSwitchController.applier.switchToSourcePlaylist(
                            fetchedSourceIndex,
                            items,
                            targetSeason = targetSeason,
                            targetEpisode = targetEpisode,
                            suppressTargetResume = autoAdvance,
                        )
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    activity.runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != host.stremioResolutionToken) return@runOnUiThread
                        if (host.yieldEpisodeFetchToQueuedShuffle()) return@runOnUiThread
                        if (errorCode == "episode_guide_unavailable") {
                            val model = host.payload
                            val current = model?.items?.getOrNull(host.currentIndex)
                            if (model != null && current?.season == currentSeason && current.episode == currentEpisode) {
                                val target = host.guideAdjacent(model, current, direction, allowResolverFallback = true)
                                if (target != null) {
                                    requestEpisodeFetch(target.season, target.episode, autoAdvance = autoAdvance)
                                    return@runOnUiThread
                                }
                            }
                        }
                        host.showStatusPillTransient("No playable $directionLabel episode found")
                    }
                }

                override fun notImplemented() {
                    activity.runOnUiThread {
                        episodeFetchInFlight = false
                        host.showStatusPillTransient("Couldn't fetch next episode")
                    }
                }
            }
        )
    }

    /**
     * "Load more sources" for a series source tab: asks Flutter to run the
     * not-yet-fetched category's search ('packs' | 'episodes'). The response
     * carries the FULL updated source list (append-only, so every existing
     * index — including [currentStremioSourceIndex] — stays valid) plus the
     * updated per-tab fetch flags. While in flight the tab shows a disabled
     * Loading row; a failure keeps the button up for a retry.
     */
    internal fun requestMoreTorrentSources(mode: String) {
        if (host.moreSourcesLoadingMode != null) return
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            failMoreTorrentSources()
            return
        }
        host.moreSourcesLoadingMode = mode
        host.unifiedMenu?.render()
        host.sourceBrowser?.render()
        // Current playlist position: a season-pack playlist auto-advances
        // episodes without relaunching, so the fetch must target what's
        // playing NOW, not the launch episode.
        val curItem = host.payload?.items?.getOrNull(host.currentIndex)
        android.util.Log.d(
            "AndroidTvPlayer",
            "requestMoreTorrentSources - mode=$mode, s=${curItem?.season}, e=${curItem?.episode}"
        )
        channel.invokeMethod(
            "requestMoreTorrentSources",
            hashMapOf<String, Any?>(
                "mode" to mode,
                "season" to curItem?.season,
                "episode" to curItem?.episode,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    activity.runOnUiThread { applyMoreTorrentSources(mode, result as? Map<*, *>) }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    android.util.Log.e("AndroidTvPlayer", "requestMoreTorrentSources - error: $errorCode - $errorMessage")
                    activity.runOnUiThread { failMoreTorrentSources() }
                }

                override fun notImplemented() {
                    android.util.Log.e("AndroidTvPlayer", "requestMoreTorrentSources - not implemented")
                    activity.runOnUiThread { failMoreTorrentSources() }
                }
            }
        )
    }

    private fun applyMoreTorrentSources(mode: String, map: Map<*, *>?) {
        if (activity.isFinishing || activity.isDestroyed) return
        host.moreSourcesLoadingMode = null
        if (map == null) {
            failMoreTorrentSources(alreadyCleared = true)
            return
        }
        val newSources = map["stremioSources"] as? List<*>
        if (newSources != null && newSources.isNotEmpty()) {
            val before = host.stremioSources.size
            host.stremioSources.clear()
            for ((idx, src) in newSources.withIndex()) {
                val srcMap = src as? Map<*, *> ?: continue
                host.stremioSources.add(StremioSource.fromMap(srcMap, idx))
            }
            // Append-only contract: the current source keeps its index; clamp
            // is belt-and-braces only.
            host.currentStremioSourceIndex = host.currentStremioSourceIndex
                .coerceIn(0, host.stremioSources.lastIndex.coerceAtLeast(0))
            android.util.Log.d(
                "AndroidTvPlayer",
                "applyMoreTorrentSources - mode=$mode, sources $before → ${host.stremioSources.size}"
            )
        }
        (map["packsFetched"] as? Boolean)?.let { host.seriesPacksFetched = it }
        (map["episodesFetched"] as? Boolean)?.let { host.seriesEpisodesFetched = it }
        (map["movieFetched"] as? Boolean)?.let { host.movieSourcesFetched = it }
        host.sourceSwitchController.updateStremioQualityBadge()
        host.unifiedMenu?.render()
        host.sourceBrowser?.render()
        if (host.startupGateController.startupRecoveryFetching) {
            host.startupGateController.startupRecoveryFetching = false
            // A completed search with candidates owns recovery, even when all
            // were duplicates/ineligible or fewer than the attempt budget.
            // Do not restart Dart recovery with a fresh acquisition allowance.
            host.startupGateController.startupRecoveryProducedCandidates = host.startupGateController.startupRecoveryProducedCandidates ||
                (map["recoveryCandidateCount"] as? Number)?.toInt()?.let { it > 0 } == true
            host.startupGateController.startupRecoveryCandidateIndices = (map["recoveryCandidateIndices"] as? List<*>)
                ?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
            host.startupGateController.startupRecoveryNextMode = map["recoveryNextMode"] as? String
            host.startupGateController.failStartupCandidate("recovery-results")
        }
    }

    /** Per-addon fetch from the source browser: episode results first — the
     * response merges them into the list AND says whether they carried
     * torrent magnets (probePacks). Only then does the lazy season-pack probe
     * run as a SECOND call, so direct links render the moment they arrive. */
    internal fun requestAddonTorrentSources(groupId: String) {
        // Configuration-specific group ids keep separately configured copies
        // of the same manifest independently fetchable.
        val addonIds = host.sourceAddons.filter { it.sourceKey == groupId }.map { it.id }
        if (addonIds.isEmpty()) return
        if (host.addonFetchState[groupId] == "fetching") return
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            host.sourceBrowser?.showError("Couldn't fetch — try again")
            return
        }
        host.addonFetchState[groupId] = "fetching"
        host.sourceBrowser?.render()
        val curItem = host.payload?.items?.getOrNull(host.currentIndex)
        channel.invokeMethod(
            "requestAddonTorrentSources",
            hashMapOf<String, Any?>(
                "addonIds" to addonIds,
                "mode" to "episodes",
                "season" to curItem?.season,
                "episode" to curItem?.episode,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    activity.runOnUiThread {
                        applyAddonEpisodeSources(groupId, result as? Map<*, *>, curItem?.season)
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    activity.runOnUiThread { failAddonFetch(groupId) }
                }

                override fun notImplemented() {
                    activity.runOnUiThread { failAddonFetch(groupId) }
                }
            }
        )
    }

    private fun applyAddonEpisodeSources(groupId: String, map: Map<*, *>?, season: Int?) {
        if (map == null) {
            failAddonFetch(groupId)
            return
        }
        host.addonFetchState[groupId] = "fetched"
        adoptSourceList(map)
        // Only the ids whose own episode results carried a magnet get the
        // pack probe — the response names them; empty = nothing to probe.
        val packIds = (map["packAddonIds"] as? List<*>)?.filterIsInstance<String>().orEmpty()
        if (packIds.isEmpty()) {
            host.sourceBrowser?.render()
            return
        }
        host.addonPackProbing.add(groupId)
        host.sourceBrowser?.render()
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            host.addonPackProbing.remove(groupId)
            host.sourceBrowser?.render()
            return
        }
        channel.invokeMethod(
            "requestAddonTorrentSources",
            hashMapOf<String, Any?>("addonIds" to packIds, "mode" to "packs", "season" to season),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    activity.runOnUiThread {
                        host.addonPackProbing.remove(groupId)
                        adoptSourceList(result as? Map<*, *>)
                        host.sourceBrowser?.render()
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    activity.runOnUiThread {
                        host.addonPackProbing.remove(groupId)
                        host.sourceBrowser?.render()
                    }
                }

                override fun notImplemented() {
                    activity.runOnUiThread {
                        host.addonPackProbing.remove(groupId)
                        host.sourceBrowser?.render()
                    }
                }
            }
        )
    }

    private fun failAddonFetch(groupId: String) {
        host.addonFetchState[groupId] = "failed"
        host.sourceBrowser?.render()
    }

    /** Adopt a full replacement source list from a per-addon fetch response —
     * the same append-only swap [applyMoreTorrentSources] performs. */
    private fun adoptSourceList(map: Map<*, *>?) {
        if (map?.get("preferredSourceMissing") == true) {
            android.widget.Toast.makeText(activity,
                "Your previous source is unavailable for this episode. Using another source.",
                android.widget.Toast.LENGTH_LONG).show()
        }
        val newSources = (map?.get("stremioSources") as? List<*>) ?: return
        if (newSources.isEmpty()) return
        host.stremioSources.clear()
        for ((idx, src) in newSources.withIndex()) {
            val srcMap = src as? Map<*, *> ?: continue
            host.stremioSources.add(StremioSource.fromMap(srcMap, idx))
        }
        host.currentStremioSourceIndex = host.currentStremioSourceIndex
            .coerceIn(0, host.stremioSources.lastIndex.coerceAtLeast(0))
        host.sourceSwitchController.updateStremioQualityBadge()
        host.unifiedMenu?.render()
    }

    internal fun failMoreTorrentSources(alreadyCleared: Boolean = false) {
        if (!alreadyCleared) host.moreSourcesLoadingMode = null
        if (host.sourceBrowser?.isVisible == true) {
            host.sourceBrowser?.showError("Couldn't load more sources — try again")
        } else {
            host.showStatusPillTransient("Couldn't load more sources")
        }
        host.unifiedMenu?.render()
        host.sourceBrowser?.render()
        if (host.startupGateController.startupRecoveryFetching) {
            host.startupGateController.startupRecoveryFetching = false
            host.progressHandler.post { if (!activity.isFinishing && !activity.isDestroyed) host.startupGateController.failStartupCandidate("recovery-results") }
        }
    }
}
