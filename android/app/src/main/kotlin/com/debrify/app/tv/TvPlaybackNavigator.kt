package com.debrify.app.tv

import android.os.Handler
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.SubtitleView
import kotlinx.coroutines.cancel
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity.ShufflePlaybackAttempt

internal class TvPlaybackNavigator(
    private val activity: AppCompatActivity,
    private val host: TvPlaybackStartController.Host,
    private val playbackStart: TvPlaybackStartController,
) {
    internal val shuffleBag = mutableListOf<Int>()
    private val showShuffle = ShowShuffle()
    private var showShuffleGeneration = 0

    fun playNext() {
        if (host.continuousShuffleEnabled) {
            if (playShowShuffle()) return
            val shuffleIndex = pickShuffleIndex()
            if (shuffleIndex != null) {
                host.isAutoAdvancing = true
                playbackStart.playItem(shuffleIndex)
                return
            }
        }

        val nextIndex = host.playlistController.getNextPlayableIndex(host.currentIndex)
        if (nextIndex != null) {
            host.isAutoAdvancing = true
            playbackStart.playItem(nextIndex)
        } else {
            if (host.isStremioTvMode && host.stremioTvGuideController.stremioTvChannels.any { it.isCurrent }) {
                host.stremioTvGuideController.requestStremioTvNext()
                return
            }

            // No next in playlist — fetch the next episode IN-PLAYER when the
            // guide + resolver allow it, else fall back to the quick-play
            // relaunch hand-back.
            val model = host.payload
            val currentItem = model?.items?.getOrNull(host.currentIndex)
            if (model != null && currentItem != null &&
                model.contentType == "series" && currentItem.season != null &&
                currentItem.episode != null) {
                val nextTarget = host.guideAdjacent(model, currentItem, 1)
                if (nextTarget != null && host.hasPlaylistResolver) {
                    host.sourceFetchController.requestEpisodeFetch(nextTarget.season, nextTarget.episode)
                    return
                }
                if (host.hasPlaylistResolver) {
                    host.sourceFetchController.requestAdjacentEpisodeFetch(
                        model.imdbId,
                        currentItem.season,
                        currentItem.episode,
                    )
                } else if (model.imdbId != null) {
                    requestQuickPlayNextEpisode(model.imdbId!!, currentItem.season, currentItem.episode)
                    activity.finish()
                } else {
                    Toast.makeText(activity, "End of playlist", Toast.LENGTH_SHORT).show()
                }
            } else {
                Toast.makeText(activity, "End of playlist", Toast.LENGTH_SHORT).show()
            }
        }
    }

    /** Previous for catalog series, including a single direct-link episode.
     * Existing playlist navigation wins; at its boundary the full guide names
     * the adjacent episode and Flutter resolves it in place. */
    fun playPrevious() {
        val model = host.payload ?: return
        val prevIndex = host.playlistController.getPrevPlayableIndex(host.currentIndex)
        if (prevIndex != null) {
            // Match the Dart player's manual Previous semantics: selecting an
            // already-present episode starts it fresh. Guide-fetched Previous
            // remains resumable, as it does in Dart.
            playbackStart.playItem(prevIndex, suppressResume = true)
            return
        }
        val currentItem = model.items.getOrNull(host.currentIndex)
        if (model.contentType == "series" && host.hasPlaylistResolver) {
            val previousTarget = host.guideAdjacent(model, currentItem, -1)
            if (previousTarget != null) {
                host.sourceFetchController.requestEpisodeFetch(previousTarget.season, previousTarget.episode)
                return
            }
            if (host.hasAdjacentEpisodeResolver &&
                currentItem?.season != null && currentItem.episode != null) {
                host.sourceFetchController.requestAdjacentEpisodeFetch(
                    model.imdbId,
                    currentItem.season,
                    currentItem.episode,
                    direction = -1,
                )
                return
            }
        }
        Toast.makeText(activity, "Beginning of playlist", Toast.LENGTH_SHORT).show()
    }

    /** The IPTV Previous control is shared by catalog playback. Keep it hidden
     * for movies/first episodes, and reveal it when either the current source
     * or the asynchronously delivered full-show guide has a predecessor. */
    internal fun updateCatalogEpisodeControls() {
        if (host.isIptvMode) return
        val model = host.payload
        val currentItem = model?.items?.getOrNull(host.currentIndex)
        val hasPrevious = model != null && model.contentType == "series" &&
            !host.isStremioTvMode &&
            (host.playlistController.getPrevPlayableIndex(host.currentIndex) != null ||
                (host.hasPlaylistResolver &&
                    (host.guideAdjacent(model, currentItem, -1) != null ||
                        (host.hasAdjacentEpisodeResolver &&
                            ((currentItem?.season ?: 0) > 1 ||
                                (currentItem?.episode ?: 0) > 1)))))
        host.controlsDockController.iptvPrevButton?.visibility = if (hasPrevious) View.VISIBLE else View.GONE
    }

    fun playRandom() {
        if (playShowShuffle()) return
        val model = host.payload ?: return
        if (model.items.isEmpty()) {
            Toast.makeText(activity, "No items in playlist", Toast.LENGTH_SHORT).show()
            return
        }

        val randomIndex = pickShuffleIndex() ?: return
        host.isAutoAdvancing = false
        playbackStart.playItem(randomIndex, suppressResume = true)
    }

    internal fun showRandomPlaybackDialog() {
        val model = host.payload
        if (model == null || model.items.isEmpty()) {
            Toast.makeText(activity, "No items in playlist", Toast.LENGTH_SHORT).show()
            return
        }

        val shuffleLabel = if (host.continuousShuffleEnabled) {
            "Turn Off Continuous Shuffle"
        } else {
            "Shuffle Continuously"
        }
        val choices = arrayOf("Play Random Once", shuffleLabel)

        AlertDialog.Builder(activity)
            .setTitle("Shuffle Playback")
            .setItems(choices) { _, which ->
                when (which) {
                    0 -> {
                        host.continuousShuffleEnabled = false
                        resetShuffle()
                        playRandom()
                    }
                    1 -> {
                        if (host.continuousShuffleEnabled) {
                            host.continuousShuffleEnabled = false
                            resetShuffle()
                            Toast.makeText(activity, "Continuous shuffle off", Toast.LENGTH_SHORT).show()
                        } else {
                            host.continuousShuffleEnabled = true
                            resetShuffle()
                            Toast.makeText(activity, "Continuous shuffle on", Toast.LENGTH_SHORT).show()
                            playRandom()
                        }
                    }
                }
            }
            .show()
    }

    fun resetShuffle() {
        playbackStart.pendingShufflePlayback?.let { restoreShufflePreparation(it) }
        playbackStart.pendingShufflePlayback = null
        shuffleBag.clear()
        showShuffle.clear()
        showShuffleGeneration++
        queuedShuffleGeneration = null
    }
    private var queuedShuffleGeneration: Int? = null
    private var queuedShuffleNavigation: Int? = null

    fun shuffleAttemptCurrent(attempt: ShufflePlaybackAttempt): Boolean =
        !attempt.finished && shuffleAttemptOwned(attempt)

    private fun shuffleAttemptOwned(attempt: ShufflePlaybackAttempt): Boolean =
        !activity.isFinishing && !activity.isDestroyed && attempt.generation == showShuffleGeneration &&
            attempt.navigation == playbackStart.mediaPreparationGeneration &&
            (!attempt.autoAdvance || !host.sleepStopLatched)

    fun restoreShufflePreparation(attempt: ShufflePlaybackAttempt) {
        if (!attempt.mediaStarted && attempt.navigation == playbackStart.mediaPreparationGeneration) {
            attempt.restorePreparation?.invoke()
        }
    }

    fun failShufflePlayback(): Boolean {
        val attempt = playbackStart.pendingShufflePlayback ?: return false
        playbackStart.pendingShufflePlayback = null
        restoreShufflePreparation(attempt)
        val current = shuffleAttemptCurrent(attempt)
        attempt.finished = true
        if (current) {
            host.progressHandler.post { if (shuffleAttemptOwned(attempt)) attempt.onUnavailable() }
        }
        return true
    }

    private var shuffleWatchGeneration = 0

    fun watchShufflePlayback(attempt: ShufflePlaybackAttempt) {
        val watchGeneration = ++shuffleWatchGeneration
        playbackStart.pendingShufflePlayback = attempt
        host.progressHandler.postDelayed({
            if (playbackStart.pendingShufflePlayback === attempt && watchGeneration == shuffleWatchGeneration) {
                if (attempt.mediaStarted && host.startupGateController.currentPlaybackItemIsPikPak() && host.pikPakRetryController.isPikPakRetrying &&
                    shuffleAttemptCurrent(attempt)) watchShufflePlayback(attempt)
                else failShufflePlayback()
            }
        }, 15000)
    }

    private fun clearQueuedShuffle(generation: Int) {
        if (queuedShuffleGeneration == generation) {
            queuedShuffleGeneration = null
            queuedShuffleNavigation = null
        }
    }

    // The explicit shuffle supersedes the older fetch. Do not let that fetch's
    // playItem advance navigation and accidentally cancel the queued command.
    fun yieldEpisodeFetchToQueuedShuffle(): Boolean =
        queuedShuffleGeneration == showShuffleGeneration &&
            queuedShuffleNavigation == playbackStart.mediaPreparationGeneration &&
            !activity.isFinishing && !activity.isDestroyed

    fun canShuffleWholeShow(): Boolean {
        val model = host.payload ?: return false
        return host.hasPlaylistResolver && !host.isIptvMode && !host.isStremioTvMode &&
            model.contentType.equals("series", ignoreCase = true) &&
            (host.customShuffleEpisodes != null || model.guideEpisodes.isNotEmpty())
    }

    /** Resolve outside the pack only when catalog playback supplies a resolver. */
    fun playShowShuffle(
        attempted: Set<ShuffleEpisode> = emptySet(),
        autoAdvance: Boolean = false,
    ): Boolean {
        if (!canShuffleWholeShow()) return false
        if (host.sourceFetchController.episodeFetchInFlight) {
            if (autoAdvance || queuedShuffleGeneration == showShuffleGeneration) return true
            val generation = showShuffleGeneration
            queuedShuffleGeneration = generation
            val navigation = playbackStart.mediaPreparationGeneration
            queuedShuffleNavigation = navigation
            fun retryWhenIdle() {
                if (generation != showShuffleGeneration || navigation != playbackStart.mediaPreparationGeneration ||
                    activity.isFinishing || activity.isDestroyed) {
                    clearQueuedShuffle(generation)
                    return
                }
                if (host.sourceFetchController.episodeFetchInFlight) host.progressHandler.postDelayed({ retryWhenIdle() }, 50)
                else {
                    clearQueuedShuffle(generation)
                    playShowShuffle(attempted, autoAdvance)
                }
            }
            host.progressHandler.postDelayed({ retryWhenIdle() }, 50)
            return true
        }
        val model = host.payload ?: return false
        val current = model.items.getOrNull(host.currentIndex)?.let { item ->
            val season = item.season
            val episode = item.episode
            if (season != null && episode != null) ShuffleEpisode(season, episode) else null
        }
        val eligible = host.customShuffleEpisodes ?: model.guideEpisodes.filter {
            it.season > 0 && it.episode > 0 && it.shuffleEligible
        }.map { ShuffleEpisode(it.season, it.episode) }
        val target = if (attempted.size < 3) showShuffle.pick(eligible, current, attempted) else null
        if (target == null) {
            host.statusPillController.showStatusPillTransient("No other playable episode found for shuffle")
            return true
        }
        host.upNextController.hideUpNextCard()
        val generation = showShuffleGeneration
        fun fetchTarget() {
            val fetchAttempt = ShufflePlaybackAttempt(playbackStart.mediaPreparationGeneration, generation, autoAdvance,
                onUnavailable = { playShowShuffle(attempted + target, autoAdvance) })
            if (!shuffleAttemptCurrent(fetchAttempt)) return
            host.sourceFetchController.requestEpisodeFetch(target.season, target.episode, autoAdvance = autoAdvance,
                suppressResume = true,
                shuffleAttempt = fetchAttempt,
                shouldContinue = { shuffleAttemptCurrent(fetchAttempt) },
                onUnavailable = { if (shuffleAttemptCurrent(fetchAttempt)) fetchAttempt.onUnavailable() })
        }
        val index = model.items.indexOfFirst {
            it.season == target.season && it.episode == target.episode
        }
        if (index < 0) {
            fetchTarget()
            return true
        }
        val attempt = ShufflePlaybackAttempt(playbackStart.mediaPreparationGeneration, generation, autoAdvance,
            onUnavailable = { fetchTarget() })
        fun openPrepared(item: PlaybackItem) {
            if (!shuffleAttemptCurrent(attempt)) return
            model.items[index] = item
            host.isAutoAdvancing = autoAdvance
            playbackStart.playItem(index, suppressResume = true, shuffleAttempt = attempt)
        }
        val item = model.items[index]
        if (item.url.isBlank()) {
            // Resolve before changing currentIndex, so cancellation/failure
            // leaves the outgoing stream associated with its own episode.
            watchShufflePlayback(attempt)
            requestStreamFromFlutter(item, index) { url, provider ->
                if (!shuffleAttemptCurrent(attempt)) return@requestStreamFromFlutter
                if (url.isNullOrEmpty()) failShufflePlayback()
                else openPrepared(item.copy(url = url, provider = provider ?: item.provider))
            }
        } else openPrepared(item)
        return true
    }

    private fun getShuffleEligibleIndices(): List<Int> {
        val model = host.payload ?: return emptyList()
        if (model.items.isEmpty()) return emptyList()

        if (host.playlistController.playlistMode == PlaylistMode.SERIES) {
            val episodeIndices = model.items.mapIndexedNotNull { index, item ->
                if (item.season != null && item.episode != null) index else null
            }
            if (episodeIndices.isNotEmpty()) return episodeIndices
        }

        if (host.playlistController.playlistMode == PlaylistMode.COLLECTION) {
            val preferredGroup = host.playlistController.movieGroups?.groups?.firstOrNull {
                it.name.equals("Main", ignoreCase = true)
            } ?: host.playlistController.movieGroups?.groups?.firstOrNull()
            val indices = preferredGroup?.fileIndices
                ?.filter { it in model.items.indices }
                ?: emptyList()
            if (indices.isNotEmpty()) return indices
        }

        return model.items.indices.toList()
    }

    fun pickShuffleIndex(): Int? {
        val eligible = getShuffleEligibleIndices().distinct()
        if (eligible.isEmpty()) return null
        if (eligible.size == 1) return eligible.first()

        val eligibleSet = eligible.toSet()
        shuffleBag.removeAll { it !in eligibleSet || it == host.currentIndex }

        if (shuffleBag.isEmpty()) {
            shuffleBag.addAll(eligible.filter { it != host.currentIndex }.shuffled())
        }

        if (shuffleBag.isEmpty()) return null
        return shuffleBag.removeAt(shuffleBag.lastIndex)
    }
}
