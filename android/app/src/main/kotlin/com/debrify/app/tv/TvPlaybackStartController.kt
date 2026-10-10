package com.debrify.app.tv

import android.os.Handler
import android.util.Log
import android.view.View
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.ui.SubtitleView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity.ShufflePlaybackAttempt

@OptIn(UnstableApi::class)
internal class TvPlaybackStartController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        var activeVodHeaders: Pair<Set<String>, Map<String, String>>
        var continuousShuffleEnabled: Boolean
        val controlsDockController: TvControlsDockController
        val controlsOverlayController: TvControlsOverlayController
        var currentIndex: Int
        var currentStremioSourceIndex: Int
        val customShuffleEpisodes: List<ShuffleEpisode>?
        fun guideAdjacent(model: PlaybackPayload, currentItem: PlaybackItem?, direction: Int): SeasonEpisode?
        val hasAdjacentEpisodeResolver: Boolean
        var hasEverBeenReady: Boolean
        val hasPlaylistResolver: Boolean
        fun hideBufferingIndicator(): Unit
        var isAutoAdvancing: Boolean
        val isIptvMode: Boolean
        val isStremioTvMode: Boolean
        var lastRealPositionMs: Long
        var maxStableDurationMs: Long
        val ottSkinInstalled: Boolean
        val payload: PlaybackPayload?
        var pendingItemTraktPercent: Double
        var pendingSeekMs: Long
        var percentSeekApplied: Boolean
        val pikPakRetryController: TvPikPakRetryController
        val player: ExoPlayer?
        val playlistController: TvPlaylistOverlayController
        val progressHandler: Handler
        val protectedStreamClient: okhttp3.OkHttpClient
        fun releaseResumeHold(): Unit
        fun restartProgressUpdates(): Unit
        val skipSegmentController: TvSkipSegmentController
        var sleepStopLatched: Boolean
        val sourceFetchController: TvSourceFetchController
        val sourceSwitchController: TvSourceSwitchController
        val startupGateController: TvStartupGateController
        val statusPillController: TvStatusPillController
        val stremioResolutionToken: Int
        val stremioSourceBadge: View?
        val stremioSources: MutableList<StremioSource>
        val stremioTvGuideController: TvStremioTvGuideController
        val subtitleOverlay: SubtitleView
        val subtitleSourcesController: TvSubtitleSourcesController
        val subtitleTrackReadiness: SubtitleTrackReadiness
        val upNextController: TvUpNextController
    }
    internal val mediaPreparationScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    internal var mediaPreparationGeneration = 0

    // [suppressTrakt]: a source switch resumes the captured live position and
    // must not let the per-episode tracker percent override it. The parameter
    // retains its legacy name because the payload field does too.
    fun playItem(
        index: Int,
        suppressTrakt: Boolean = false,
        suppressResume: Boolean = false,
        shuffleAttempt: ShufflePlaybackAttempt? = null,
    ) {
        if (shuffleAttempt != null && !navigator.shuffleAttemptCurrent(shuffleAttempt)) return
        val outgoingIndex = host.currentIndex
        if (shuffleAttempt != null && shuffleAttempt.restorePreparation == null) {
            shuffleAttempt.restorePreparation = {
                host.currentIndex = outgoingIndex
                host.payload?.items?.getOrNull(outgoingIndex)?.let {
                    host.activeVodHeaders = buildProtectedMediaOrigins(listOf(it)) to it.httpHeaders
                }
                navigator.updateCatalogEpisodeControls()
            }
        }
        pendingShufflePlayback = null
        mediaPreparationGeneration++
        if (shuffleAttempt != null) {
            shuffleAttempt.navigation = mediaPreparationGeneration
            navigator.watchShufflePlayback(shuffleAttempt)
        }
        // A sleep stop wins over anything already queued: the auto-advance
        // arms a 1.5s postDelayed before starting the next item, and a
        // countdown expiring inside that window would otherwise be undone by
        // its own handoff. Only automatic starts are gated — an explicit pick
        // clears the latch first (isAutoAdvancing is set by the auto paths).
        if (host.sleepStopLatched) {
            if (host.isAutoAdvancing) {
                android.util.Log.d("AndroidTvPlayer", "playItem suppressed by sleep timer")
                host.isAutoAdvancing = false
                return
            }
            // Picking something by hand means the viewer is awake.
            host.sleepStopLatched = false
        }
        val model = host.payload ?: return
        android.util.Log.d("AndroidTvPlayer", "playItem called - index: $index, total items: ${model.items.size}")
        if (index < 0 || index >= model.items.size) {
            android.util.Log.e("AndroidTvPlayer", "playItem - index out of bounds! index: $index, size: ${model.items.size}")
            return
        }

        // Navigating to an item invalidates any in-flight source-switch
        // feedback — without this, the pending watcher would report the NEW
        // item's READY/IDLE as the OLD switch's outcome. (switchToSourcePlaylist
        // registers its watcher AFTER calling playItem, so it's unaffected.)
        host.sourceSwitchController.dropStaleSourceSwitchFeedback()

        // Reset buffering state for new content
        host.hasEverBeenReady = false
        host.maxStableDurationMs = 0L
        host.lastRealPositionMs = 0L
        host.hideBufferingIndicator()
        host.upNextController.hideUpNextCard()
        host.skipSegmentController.resetSkipSegmentState()

        // Cancel any ongoing PikPak retry before starting new item
        host.pikPakRetryController.cancelPikPakRetry()

        host.currentIndex = index
        navigator.updateCatalogEpisodeControls()
        val item = model.items[index]
        host.activeVodHeaders = buildProtectedMediaOrigins(listOf(item)) to item.httpHeaders
        android.util.Log.d("AndroidTvPlayer", "playItem - item found: title=${item.title}, season=${item.season}, episode=${item.episode}, url=${item.url}, resumeId=${item.resumeId}")
        // Keep BOTH the local position and the remote tracker percent (the
        // payload field is the furthest of Trakt + Simkl + MDBList); STATE_READY resumes
        // the FURTHER of the two (never backward). Suppress every saved position
        // during auto-advance (binge starts the next episode fresh), and suppress
        // trackers during a source switch on the same content (which must honour
        // the captured live position).
        val autoAdvance = host.isAutoAdvancing
        host.isAutoAdvancing = false
        // A new item starts: any hold belongs to the outgoing one. (A
        // suppressed resume then simply never re-arms — pendingSeekMs stays 0.)
        host.releaseResumeHold()
        host.pendingSeekMs =
            if (autoAdvance || suppressResume) 0L else item.resumePositionMs
        host.pendingItemTraktPercent =
            if (autoAdvance || suppressTrakt || suppressResume) 0.0 else (item.traktProgressPercent ?: 0.0)

        // Check if URL needs to be resolved (lazy loading)
        if (item.url.isBlank()) {
            android.util.Log.d("AndroidTvPlayer", "playItem - URL is blank, resolving...")
            resolveAndPlay(index, item)
            return
        }

        android.util.Log.d("AndroidTvPlayer", "playItem - URL available, starting playback")
        startPlayback(item)
    }

    private fun resolveAndPlay(index: Int, item: PlaybackItem) {
        android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - index: $index, resumeId: ${item.resumeId}, id: ${item.id}")
        val navigation = mediaPreparationGeneration
        val shuffleAttempt = pendingShufflePlayback
        host.controlsOverlayController.setResolvingState(true)
        val startupGeneration = if (host.startupGateController.startupFailoverCursor?.committed == false) {
            host.startupGateController.startupFailoverGeneration
        } else {
            null
        }
        val manualSourceIndex = host.startupGateController.manualSourceSwitchIndex
        val manualResolutionToken = if (manualSourceIndex != null) {
            host.stremioResolutionToken
        } else {
            null
        }
        if (startupGeneration != null) {
            startupLog(
                "event=resolve route=initial_lazy generation=$startupGeneration " +
                    host.startupGateController.startupSourceFields(host.currentStremioSourceIndex),
            )
        }

        // Request stream from Flutter with async callback
        requestStreamFromFlutter(item, index) { url, provider ->
            if (navigation != mediaPreparationGeneration ||
                (shuffleAttempt != null && !navigator.shuffleAttemptCurrent(shuffleAttempt))) return@requestStreamFromFlutter
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - received url: $url")
            if (manualSourceIndex != null &&
                (host.startupGateController.manualSourceSwitchSnapshot == null ||
                    host.startupGateController.manualSourceSwitchIndex != manualSourceIndex ||
                    host.stremioResolutionToken != manualResolutionToken)
            ) {
                startupLog(
                    "event=resolve_result ok=false reason=stale_manual_token " +
                        "captured=$manualResolutionToken current=${host.stremioResolutionToken} " +
                        host.startupGateController.startupSourceFields(manualSourceIndex),
                )
                return@requestStreamFromFlutter
            }
            if (!isCurrentStartupGeneration(
                    captured = startupGeneration,
                    current = host.startupGateController.startupFailoverGeneration,
                )
            ) {
                startupLog(
                    "event=resolve_result ok=false reason=stale_generation " +
                        "captured=$startupGeneration current=${host.startupGateController.startupFailoverGeneration} " +
                        host.startupGateController.startupSourceFields(host.currentStremioSourceIndex),
                )
                android.util.Log.d(
                    "AndroidTvPlayer",
                    "resolveAndPlay - stale startup generation $startupGeneration " +
                        "(current: ${host.startupGateController.startupFailoverGeneration}), discarding",
                )
                return@requestStreamFromFlutter
            }
            host.controlsOverlayController.setResolvingState(false)

            if (url.isNullOrEmpty()) {
                startupLog(
                    "event=resolve_result ok=false reason=empty_initial_resolution " +
                        host.startupGateController.startupSourceFields(host.currentStremioSourceIndex),
                    warning = true,
                )
                android.util.Log.e("AndroidTvPlayer", "resolveAndPlay - URL is null or empty!")
                if (navigator.failShufflePlayback()) return@requestStreamFromFlutter
                if (!host.startupGateController.failManualSourceCandidate("initial-resolve") &&
                    !host.startupGateController.failStartupResolution(host.currentStremioSourceIndex, "initial-resolve")
                ) {
                    Toast.makeText(activity, "Unable to load stream", Toast.LENGTH_SHORT).show()
                }
                return@requestStreamFromFlutter
            }

            // Update the item with resolved URL and provider
            val updatedItem = item.copy(url = url, provider = provider ?: item.provider)
            host.payload?.items?.set(index, updatedItem)
            if (manualSourceIndex != null) host.startupGateController.manualSourceCandidateUrl = url
            startupLog(
                "event=resolve_result ok=true route=initial_lazy " +
                    host.startupGateController.startupSourceFields(host.currentStremioSourceIndex),
            )
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - starting playback with resolved URL, provider: $provider")
            startPlayback(host.payload!!.items[index])
        }
    }

    internal fun discoverProtectedMime(url: String, headers: Map<String, String>, ready: (String?) -> Unit) {
        val shuffleAttempt = pendingShufflePlayback
        val generation = ++mediaPreparationGeneration
        shuffleAttempt?.navigation = generation
        val sourceToken = host.stremioResolutionToken
        mediaPreparationScope.launch {
            val mimeType = withContext(Dispatchers.IO) {
                ProtectedStreamHttp.discoverMimeType(host.protectedStreamClient, url, headers)
            }
            if (generation == mediaPreparationGeneration && sourceToken == host.stremioResolutionToken &&
                (shuffleAttempt == null || navigator.shuffleAttemptCurrent(shuffleAttempt)) &&
                !activity.isFinishing && !activity.isDestroyed && !host.sleepStopLatched) {
                ready(mimeType)
            }
        }
    }

    private fun startPlayback(item: PlaybackItem, mimeDiscovered: Boolean = false) {
        pendingShufflePlayback?.let {
            if (!navigator.shuffleAttemptCurrent(it)) {
                navigator.restoreShufflePreparation(it)
                pendingShufflePlayback = null
                return
            }
        }
        if (!host.isIptvMode && !mimeDiscovered && item.mimeType == null &&
            ProtectedStreamHttp.needsDiscovery(item.url, item.httpHeaders)) {
            discoverProtectedMime(item.url, item.httpHeaders) { mimeType ->
                val current = host.payload?.items?.getOrNull(host.currentIndex)
                if (current == null || current.url != item.url) return@discoverProtectedMime
                val prepared = current.copy(mimeType = mimeType)
                host.payload?.items?.set(host.currentIndex, prepared)
                startPlayback(prepared, mimeDiscovered = true)
            }
            return
        }
        host.activeVodHeaders = buildProtectedMediaOrigins(listOf(item)) to item.httpHeaders
        // Last gate before ExoPlayer actually starts. playItem's check happens
        // before URL resolution, and that round trip can outlast the countdown
        // — without rechecking here, a resolve that was already in flight would
        // start the night up again and re-take both screen holds.
        if (host.sleepStopLatched) {
            android.util.Log.d("AndroidTvPlayer", "startPlayback suppressed by sleep timer")
            return
        }

        // Check if this is a PikPak provider - use retry logic for cold storage handling
        val isPikPak = PROVIDER_PIKPAK.equals(item.provider, ignoreCase = true) ||
            item.url.contains("mypikpak.com")
        android.util.Log.d("AndroidTvPlayer", "startPlayback - provider: ${item.provider}, isPikPak: $isPikPak, url contains mypikpak: ${item.url.contains("mypikpak.com")}")

        if (isPikPak) {
            android.util.Log.d("AndroidTvPlayer", "startPlayback - using PikPak retry logic")
            playPikPakVideoWithRetry(item)
        } else {
            android.util.Log.d("AndroidTvPlayer", "startPlayback - using direct playback")
            playMediaDirect(item)
        }
    }

    private fun playMediaDirect(item: PlaybackItem) {
        // Clear subtitle state when switching content
        host.subtitleSourcesController.resetSubtitleState()

        val metadata = MediaMetadata.Builder()
            .setTitle(item.title)
            .setArtist(item.seasonEpisodeLabel())
            .setDescription(item.description ?: host.payload?.subtitle ?: host.payload?.title)
            .build()

        val mediaItem = MediaItem.Builder()
            .setUri(item.url)
            .setMimeType(item.mimeType)
            .setMediaMetadata(metadata)
            .build()

        // High-res YouTube: video and audio are separate streams. Merge a
        // video-only track with its audio track. If anything goes wrong we fall
        // back to [item.url], a muxed stream that already contains audio, so we
        // never end up with silent video.
        val mergedSource = buildMergedSourceOrNull(item, mediaItem)

        host.player?.apply {
            pendingShufflePlayback?.mediaStarted = true
            if (mergedSource != null) {
                host.subtitleTrackReadiness.onMediaReplacement()
                setMediaSource(mergedSource)
            } else {
                host.subtitleTrackReadiness.onMediaReplacement()
                setMediaItem(mediaItem)
            }
            prepare()
            playWhenReady = true
            play()
        }

        host.controlsOverlayController.identity.updateTitle(item)
        host.playlistController.playlistAdapter?.setActiveIndex(host.currentIndex)
        host.restartProgressUpdates()

        // Fetch Stremio subtitles for this item
        host.subtitleSourcesController.fetchStremioSubtitles(item)
    }

    // Build a MergingMediaSource (video-only + audio) for high-res YouTube,
    // or null when the item has no separate audio track / on any error.
    private fun buildMergedSourceOrNull(
        item: PlaybackItem,
        baseMediaItem: MediaItem,
    ): MergingMediaSource? {
        val hdVideoUrl = item.hdVideoUrl
        val audioUrl = item.audioUrl
        if (hdVideoUrl.isNullOrEmpty() || audioUrl.isNullOrEmpty()) return null
        return try {
            // Use an HTTP data source that follows cross-protocol redirects
            // (googlevideo may redirect) — matching the app's main playback path.
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
            val dataSourceFactory = DefaultDataSource.Factory(activity, httpFactory)
            val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(
                    baseMediaItem.buildUpon().setUri(hdVideoUrl).build()
                )
            val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(MediaItem.fromUri(audioUrl))
            // adjustPeriodTimeOffsets + clipDurations tolerate the tiny
            // duration mismatch between YouTube's video/audio tracks.
            MergingMediaSource(true, true, videoSource, audioSource)
        } catch (e: Exception) {
            android.util.Log.w("AndroidTvPlayer", "merge build failed, using muxed fallback", e)
            null
        }
    }

    // Merge an arbitrary video-only URL with a separate audio URL — used on a
    // YouTube quality switch, where only the video changes and the audio stays
    // the same. Null on error so the caller falls back to the single URL.
    internal fun buildMergedSource(videoUrl: String, audioUrl: String): MergingMediaSource? {
        return try {
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
            val dataSourceFactory = DefaultDataSource.Factory(activity, httpFactory)
            val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(MediaItem.fromUri(videoUrl))
            val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                .createMediaSource(MediaItem.fromUri(audioUrl))
            MergingMediaSource(true, true, videoSource, audioSource)
        } catch (e: Exception) {
            android.util.Log.w("AndroidTvPlayer", "switch merge build failed, using single url", e)
            null
        }
    }
    internal var pendingShufflePlayback: ShufflePlaybackAttempt? = null
    internal val navigator = TvPlaybackNavigator(activity, host, this)

    // PikPak Cold Storage Retry Logic
    // PikPak uses "cold storage" where files that haven't been accessed recently need 10-30 seconds
    // to reactivate. This implements retry logic with exponential backoff.

    private fun playPikPakVideoWithRetry(item: PlaybackItem) {
        android.util.Log.d("AndroidTvPlayer", "PikPak: Starting retry logic for cold storage handling")

        // Clear subtitle state when switching content
        host.subtitleSourcesController.resetSubtitleState()

        // Cancel any previous retry loops
        host.pikPakRetryController.pikPakRetryId++
        val myRetryId = host.pikPakRetryController.pikPakRetryId

        // Reset retry state
        host.pikPakRetryController.pikPakRetryCount = 0
        host.pikPakRetryController.isPikPakRetrying = false
        host.pikPakRetryController.hidePikPakRetryOverlay()

        // Null safety check for player
        if (host.player == null) {
            android.util.Log.e("AndroidTvPlayer", "PikPak: Player is null, cannot attempt playback")
            return
        }

        // Clear previous video's subtitles
        host.subtitleOverlay.setCues(emptyList())

        // Prepare and play the media ONCE before retry loop
        val metadata = MediaMetadata.Builder()
            .setTitle(item.title)
            .setArtist(item.seasonEpisodeLabel())
            .setDescription(item.description ?: host.payload?.subtitle ?: host.payload?.title)
            .build()

        val mediaItem = MediaItem.Builder()
            .setUri(item.url)
            .setMediaMetadata(metadata)
            .build()

        host.player?.apply {
            pendingShufflePlayback?.mediaStarted = true
            host.subtitleTrackReadiness.onMediaReplacement()
            setMediaItem(mediaItem)
            prepare()
            play()
        }

        host.controlsOverlayController.identity.updateTitle(item)
        host.playlistController.playlistAdapter?.setActiveIndex(host.currentIndex)
        host.restartProgressUpdates()

        // Fetch Stremio subtitles for this item (same as playMediaDirect)
        host.subtitleSourcesController.fetchStremioSubtitles(item)

        // Start retry loop with attempt 0
        host.pikPakRetryController.attemptPikPakPlaybackLoop(item, 0, myRetryId)
    }

    private fun updateStremioSourcesFromPlaybackMap(map: Map<*, *>) {
        val newSources = map["stremioSources"] as? List<*>
        val newSourceIndex = (map["stremioCurrentSourceIndex"] as? Number)?.toInt() ?: 0
        if (newSources != null) {
            host.stremioSources.clear()
            for ((idx, src) in newSources.withIndex()) {
                val srcMap = src as? Map<*, *> ?: continue
                host.stremioSources.add(StremioSource.fromMap(srcMap, idx))
            }
            host.currentStremioSourceIndex = newSourceIndex.coerceIn(
                0,
                host.stremioSources.lastIndex.coerceAtLeast(0)
            )
            host.sourceSwitchController.setupStremioSources()
        }
    }

    private fun replacePayloadWithStremioTvItem(
        channel: StremioTvGuideChannel,
        map: Map<*, *>,
        title: String,
        url: String
    ) {
        val contentImdbId = map["contentImdbId"] as? String
        val contentType = map["contentType"] as? String
        val contentSeason = (map["contentSeason"] as? Number)?.toInt()
        val contentEpisode = (map["contentEpisode"] as? Number)?.toInt()

        // This is the one same-activity path that can change SHOW, and the
        // zap closures never re-run the TVMaze pipeline — a kept name would
        // caption the new show's episodes with the old show for the rest of
        // the session. Episode-only is honest until a fresh push arrives.
        host.controlsOverlayController.identity.ottShowName = null

        host.payload?.let { model ->
            val previousItem = model.items.getOrNull(host.currentIndex)
            val switchedItem = PlaybackItem(
                id = "stremio_tv:${channel.id}",
                title = title,
                url = url,
                index = 0,
                season = contentSeason,
                episode = contentEpisode,
                artwork = channel.nowPlayingPoster ?: previousItem?.artwork,
                description = previousItem?.description,
                resumePositionMs = 0L,
                durationMs = 0L,
                updatedAt = System.currentTimeMillis(),
                resumeId = null,
                sizeBytes = null,
                rating = channel.nowPlayingRating ?: previousItem?.rating,
                provider = previousItem?.provider,
                // Keep the release name parseable for the quality chips even
                // if a later metadata copy() overwrites title.
                sourceTitle = title,
            )
            model.items.clear()
            model.items.add(switchedItem)
            model.contentType = contentType ?: ""
            model.imdbId = contentImdbId
            model.nextEpisodeMap = emptyMap()
            model.prevEpisodeMap = emptyMap()
            model.collectionGroups = null
            model.perItemImdbIds.clear()
            model.perItemImdbIds[0] = contentImdbId
            host.currentIndex = 0
        }
    }

    fun playStremioTvPlaybackMap(
        channel: StremioTvGuideChannel,
        map: Map<*, *>,
        url: String,
        title: String,
        hideGuideOnReady: Boolean
    ) {
        val startAtPercent = (map["startAtPercent"] as? Number)?.toDouble() ?: 0.0

        updateStremioTvGuideChannelData(channel, map)
        replacePayloadWithStremioTvItem(channel, map, title, url)
        updateStremioSourcesFromPlaybackMap(map)
        host.stremioTvGuideController.updateStremioTvGuideHeader()
        host.sourceSwitchController.updateStremioQualityBadge()
        if (host.ottSkinInstalled) {
            host.controlsDockController.ottSourcesButton?.visibility =
                if (host.stremioSources.isEmpty()) View.GONE else View.VISIBLE
        } else if (host.stremioSources.isNotEmpty()) {
            host.stremioSourceBadge?.visibility = View.VISIBLE
        } else {
            host.stremioSourceBadge?.visibility = View.GONE
        }

        host.subtitleSourcesController.resetSubtitleState()
        host.subtitleSourcesController.clearStremioLoadingState()
        host.pikPakRetryController.cancelPikPakRetry()

        // Route the channel's slot-progress seek through the shared resume
        // machinery instead of an isolated inline listener. The main
        // playbackListener applies the seek on STATE_READY. (Subtitle loads are
        // side-rendered and never seek, so they can't clobber it.)
        host.payload?.startAtPercent = startAtPercent
        host.percentSeekApplied = false
        host.pendingSeekMs = 0
        // Clear any leftover per-episode tracker percent from a torrent item whose
        // READY never fired (rapid switch mid-buffer) — the resume branch now
        // arms on it, and a live channel must never seek to a stale tracker offset.
        host.pendingItemTraktPercent = 0.0
        // This path replaces the payload WITHOUT passing playItem, so the
        // item-change release there never runs. A slot with no resume signal
        // would otherwise inherit the previous item's hold and file its stale
        // position against the new content. (A slot WITH a signal re-arms at
        // READY — armResumeHold supersedes unconditionally.)
        host.releaseResumeHold()
        host.hasEverBeenReady = false

        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .build()
        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(metadata)
            .build()

        host.player?.apply {
            host.subtitleTrackReadiness.onMediaReplacement()
            setMediaItem(mediaItem)
            prepare()
            playWhenReady = true
            play()
        }

        val playbackItem = host.payload?.items?.getOrNull(host.currentIndex) ?: PlaybackItem(
            id = "stremio_tv:${channel.id}",
            title = title,
            url = url,
            index = 0,
            season = (map["contentSeason"] as? Number)?.toInt(),
            episode = (map["contentEpisode"] as? Number)?.toInt(),
            artwork = null,
            description = null,
            resumePositionMs = 0L,
            durationMs = 0L,
            updatedAt = System.currentTimeMillis(),
            resumeId = null,
            sizeBytes = null,
            rating = null,
            provider = null,
        )

        host.controlsOverlayController.identity.updateTitle(playbackItem)
        host.subtitleSourcesController.fetchStremioSubtitles(playbackItem)

        channel.isSwitchingChannel = false
        host.stremioTvGuideController.stremioTvChannelAdapter?.notifyDataSetChanged()
        if (hideGuideOnReady) {
            host.stremioTvGuideController.hideGuideWhenReady()
        }
    }
}
