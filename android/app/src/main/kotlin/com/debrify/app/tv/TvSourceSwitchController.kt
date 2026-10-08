package com.debrify.app.tv

import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.ui.PlayerView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import android.net.Uri
import com.debrify.app.MainActivity
import com.debrify.app.R
import org.json.JSONObject
import com.debrify.app.tv.AndroidTvTorrentPlayerActivity.ShufflePlaybackAttempt

@OptIn(UnstableApi::class)
internal class TvSourceSwitchController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        var activeVodHeaders: Pair<Set<String>, Map<String, String>>
        fun armStartupCandidate(sourceIndex: Int): Unit
        fun attemptPikPakPlaybackLoop(item: PlaybackItem, attemptNumber: Int, retryId: Int): Unit
        fun beginManualSourceCandidate(sourceIndex: Int): Unit
        fun buildMergedSource(videoUrl: String, audioUrl: String): MergingMediaSource?
        fun cancelPikPakRetry(): Unit
        var currentIndex: Int
        var currentStremioSourceIndex: Int
        fun discoverProtectedMime(url: String, headers: Map<String, String>, ready: (String?) -> Unit): Unit
        fun failManualSourceCandidate(reason: String): Boolean
        fun failStartupResolution(sourceIndex: Int, reason: String): Boolean
        val hasPlaylistResolver: Boolean
        fun heldResumePositionMs(actualMs: Long): Long?
        fun hideControlsMenu(): Unit
        fun hidePikPakRetryOverlay(): Unit
        fun hideStatusPill(): Unit
        val iptvChannelStartController: TvIptvChannelStartController
        val isIptvMode: Boolean
        var isPikPakRetrying: Boolean
        var manualSourceCandidateUrl: String?
        var manualSourceMediaReplaced: Boolean
        val manualSourceSwitchSnapshot: ManualSourceSwitchSnapshot?
        var mediaPreparationGeneration: Int
        val ottSkinInstalled: Boolean
        val ottSourcesButton: AppCompatButton?
        val payload: PlaybackPayload?
        var percentSeekApplied: Boolean
        var pikPakRetryCount: Int
        var pikPakRetryId: Int
        fun playItem(index: Int, suppressTrakt: Boolean, suppressResume: Boolean, shuffleAttempt: ShufflePlaybackAttempt?): Unit
        val player: ExoPlayer?
        val progressHandler: Handler
        fun rebuildPlaylistContent(): Unit
        fun requestMetadataFromFlutter(): Unit
        var resumeHoldArmedAtMs: Long
        fun showStatusPill(text: String): Unit
        fun showStatusPillTransient(text: String): Unit
        val shuffleBag: MutableList<Int>
        val sourceBrowser: TvSourceBrowserController?
        var startupFailoverCursor: StartupFailoverCursor?
        val startupFailoverDispatching: Boolean
        val startupRecoveryCandidateIndices: List<Int>?
        fun startupSourceFields(index: Int): String
        var stremioResolutionToken: Int
        val stremioSourceBadge: View?
        val stremioSourceBadgeText: TextView?
        val stremioSources: MutableList<StremioSource>
        val subtitleTrackReadiness: SubtitleTrackReadiness
        val titleView: TextView
        val unifiedMenu: UnifiedMenuController?
        fun updateCatalogEpisodeControls(): Unit
    }
    internal val applier = TvSourceSwitchApplier(activity, host, this)

    fun setupStremioSources() {
        if (host.stremioSources.isEmpty()) return

        android.util.Log.d("AndroidTvPlayer", "setupStremioSources: ${host.stremioSources.size} sources, current=${host.currentStremioSourceIndex}")

        // Setup quality badge
        updateStremioQualityBadge()
        host.sourceBrowser?.render()

        // Sources use their own full-screen browser; the unified menu remains
        // the home for player settings such as audio and subtitles.
        host.stremioSourceBadge?.setOnClickListener {
            host.hideControlsMenu()
            host.unifiedMenu?.hide()
            host.sourceBrowser?.show()
        }
    }

    fun updateStremioQualityBadge() {
        if (host.stremioSources.isEmpty()) return
        host.stremioSourceBadgeText?.text = "Sources"
    }

    private var sourceSwitchReadyListener: Player.Listener? = null
    private var sourceSwitchTimeoutRunnable: Runnable? = null

    /**
     * Feedback for an in-flight source switch: the status pill stays up until
     * the player reaches READY (success tick) or IDLE (error message) —
     * mirroring the old sources panel, which stayed open with a row spinner
     * until the same two states, with the same 10s give-up.
     */
    fun watchSourceSwitchOutcome(sourceIndex: Int) {
        // Clean up any previous listener/timeout
        cancelSourceSwitchWait()

        val name = host.stremioSources.getOrNull(sourceIndex)?.displayTitle ?: "source"

        // Timeout fallback — stop reporting after 10s regardless
        val timeout = Runnable {
            cancelSourceSwitchWait()
            host.hideStatusPill()
        }
        sourceSwitchTimeoutRunnable = timeout
        host.progressHandler.postDelayed(timeout, 10_000)

        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    cancelSourceSwitchWait()
                    host.showStatusPillTransient("✓ $name")
                } else if (state == Player.STATE_IDLE) {
                    cancelSourceSwitchWait()
                    if (host.isIptvMode && host.iptvChannelStartController.iptvStremioChannelKey != null) {
                        // The IPTV candidate ladder handles this failure itself
                        // (silent auto-advance; its own toast when all die) —
                        // an error pill here would contradict it.
                        host.hideStatusPill()
                    } else {
                        // Playback error — tell the user instead of going silent
                        host.showStatusPillTransient("Couldn't play $name — pick another source")
                    }
                }
            }
        }
        sourceSwitchReadyListener = listener
        host.player?.addListener(listener)
    }

    fun cancelSourceSwitchWait() {
        sourceSwitchReadyListener?.let { host.player?.removeListener(it) }
        sourceSwitchReadyListener = null
        sourceSwitchTimeoutRunnable?.let { host.progressHandler.removeCallbacks(it) }
        sourceSwitchTimeoutRunnable = null
    }

    /**
     * Navigation away from an in-flight source switch (next episode, playlist
     * pick, channel zap, ladder advance): drop the pending outcome watcher AND
     * its "Switching to…" pill, so a later item's READY/IDLE can't be reported
     * as the abandoned switch's result. No-op when nothing is pending.
     */
    fun dropStaleSourceSwitchFeedback() {
        if (sourceSwitchReadyListener == null) return
        cancelSourceSwitchWait()
        host.hideStatusPill()
    }

    fun onStremioSourceSelected(source: StremioSource) {
        android.util.Log.d("AndroidTvPlayer", "Stremio source selected: index=${source.index}, type=${source.streamType}, name=${source.displayTitle}, hasPlaylistResolver=${host.hasPlaylistResolver}")

        // A manual pick made before the first frame remains protected, but it
        // becomes the new head of the ordered ladder. Internal failover calls
        // arrive with startupFailoverDispatching set and retain their cursor.
        if (host.startupFailoverCursor?.committed == false && !host.startupFailoverDispatching) {
            val cursor = StartupFailoverCursor(
                startIndex = source.index,
                // This callback came from a source row the user explicitly
                // chose. Even before the initial gate has committed, failure
                // belongs to that row and must not silently select another.
                maxAttempts = 1,
            )
            cursor.beginInitial(host.stremioSources.size)
            host.startupFailoverCursor = cursor
            host.currentStremioSourceIndex = source.index
            host.armStartupCandidate(source.index)
        } else if (host.startupFailoverCursor?.committed != false) {
            host.beginManualSourceCandidate(source.index)
        }

        // Cancel any pending source switch wait from previous selection
        cancelSourceSwitchWait()

        // Cancel any ongoing PikPak retry from previous source
        host.cancelPikPakRetry()

        // Increment token to invalidate any in-flight resolution
        host.stremioResolutionToken++

        // Immediate feedback (replaces the old panel's row spinner); stays up
        // through resolution, then watchSourceSwitchOutcome takes over.
        host.showStatusPill("Switching to ${source.displayTitle}…")

        if (host.hasPlaylistResolver) {
            startupLog(
                "event=resolve route=playlist token=${host.stremioResolutionToken} " +
                    host.startupSourceFields(source.index),
            )
            // Torrent search mode — resolve to full playlist via Flutter
            resolveSourceToPlaylistViaFlutter(source, host.stremioResolutionToken)
        } else if (source.isDirectStream && !source.directUrl.isNullOrEmpty()) {
            startupLog(
                "event=resolve route=direct_url token=${host.stremioResolutionToken} " +
                    host.startupSourceFields(source.index),
            )
            // Direct URL — use immediately
            applier.switchToStremioSource(source.directUrl, source.index)
        } else {
            startupLog(
                "event=resolve route=single_url token=${host.stremioResolutionToken} " +
                    host.startupSourceFields(source.index),
            )
            // Torrent — resolve single URL via Flutter bridge
            resolveStremioSourceViaFlutter(source, host.stremioResolutionToken)
        }
    }

    private fun resolveStremioSourceViaFlutter(source: StremioSource, token: Int) {
        try {
            val args = hashMapOf<String, Any?>("sourceIndex" to source.index)
            android.util.Log.d("AndroidTvPlayer", "resolveStremioSource - sending to Flutter: index=${source.index}, token=$token")

            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "requestStremioSourceResolve",
                args,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (token != host.stremioResolutionToken) {
                            startupLog(
                                "event=resolve_result ok=false reason=stale_token route=single_url " +
                                    "token=$token currentToken=${host.stremioResolutionToken} " +
                                    host.startupSourceFields(source.index),
                            )
                            android.util.Log.d("AndroidTvPlayer", "resolveStremioSource - stale token $token (current: ${host.stremioResolutionToken}), discarding")
                            return
                        }
                        android.util.Log.d("AndroidTvPlayer", "resolveStremioSource - Flutter returned: $result")
                        val map = result as? Map<*, *>
                        val url = map?.get("url") as? String
                        if (!url.isNullOrEmpty()) {
                            startupLog(
                                "event=resolve_result ok=true route=single_url " +
                                    host.startupSourceFields(source.index),
                            )
                            activity.runOnUiThread { applier.switchToStremioSource(url, source.index) }
                        } else {
                            startupLog(
                                "event=resolve_result ok=false reason=empty_resolution route=single_url " +
                                    host.startupSourceFields(source.index),
                                warning = true,
                            )
                            android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - null URL returned")
                            activity.runOnUiThread {
                                if (!host.failManualSourceCandidate("empty-resolve") &&
                                    !host.failStartupResolution(source.index, "empty-resolve")
                                ) {
                                    host.showStatusPillTransient("Couldn't switch — failed to resolve source")
                                }
                            }
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (token != host.stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - error: $errorCode - $errorMessage")
                        activity.runOnUiThread {
                            if (!host.failManualSourceCandidate("resolve:$errorCode") &&
                                !host.failStartupResolution(source.index, "resolve:$errorCode")
                            ) {
                                host.showStatusPillTransient("Couldn't switch — source resolution failed")
                            }
                        }
                    }

                    override fun notImplemented() {
                        if (token != host.stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - not implemented")
                        activity.runOnUiThread {
                            if (!host.failManualSourceCandidate("resolve-not-implemented") &&
                                !host.failStartupResolution(source.index, "resolve-not-implemented")
                            ) {
                                host.showStatusPillTransient("Couldn't switch source")
                            }
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - exception: ${e.message}", e)
            if (!host.failManualSourceCandidate("resolve-exception") &&
                !host.failStartupResolution(source.index, "resolve-exception")
            ) {
                host.showStatusPillTransient("Couldn't switch source")
            }
        }
    }

    private fun resolveSourceToPlaylistViaFlutter(source: StremioSource, token: Int) {
        try {
            val args = hashMapOf<String, Any?>(
                "sourceIndex" to source.index,
                "automaticRecovery" to (host.startupFailoverDispatching && host.startupRecoveryCandidateIndices != null),
            )
            android.util.Log.d("AndroidTvPlayer", "resolveSourceToPlaylist - sending to Flutter: index=${source.index}, token=$token")

            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "requestSourcePlaylistResolve",
                args,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (token != host.stremioResolutionToken) {
                            startupLog(
                                "event=resolve_result ok=false reason=stale_token route=playlist " +
                                    "token=$token currentToken=${host.stremioResolutionToken} " +
                                    host.startupSourceFields(source.index),
                            )
                            android.util.Log.d("AndroidTvPlayer", "resolveSourceToPlaylist - stale token $token (current: ${host.stremioResolutionToken}), discarding")
                            return
                        }
                        android.util.Log.d("AndroidTvPlayer", "resolveSourceToPlaylist - Flutter returned: ${result != null}")
                        val map = result as? Map<*, *>
                        val itemsList = map?.get("items") as? List<*>
                        if (itemsList != null && itemsList.isNotEmpty()) {
                            startupLog(
                                "event=resolve_result ok=true route=playlist itemCount=${itemsList.size} " +
                                    host.startupSourceFields(source.index),
                            )
                            activity.runOnUiThread {
                                applier.switchToSourcePlaylist(
                                    source.index,
                                    itemsList,
                                    requireExactStartupEpisode =
                                        host.startupFailoverCursor?.committed == false,
                                )
                            }
                        } else {
                            startupLog(
                                "event=resolve_result ok=false reason=empty_playlist route=playlist " +
                                    host.startupSourceFields(source.index),
                                warning = true,
                            )
                            android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - null or empty items returned")
                            activity.runOnUiThread {
                                if (!host.failManualSourceCandidate("empty-playlist") &&
                                    !host.failStartupResolution(source.index, "empty-playlist")
                                ) {
                                    host.showStatusPillTransient("Source unavailable — not cached or not a video")
                                }
                            }
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (token != host.stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - error: $errorCode - $errorMessage")
                        activity.runOnUiThread {
                            if (!host.failManualSourceCandidate("playlist:$errorCode") &&
                                !host.failStartupResolution(source.index, "playlist:$errorCode")
                            ) {
                                host.showStatusPillTransient("Couldn't switch — failed to resolve source")
                            }
                        }
                    }

                    override fun notImplemented() {
                        if (token != host.stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - not implemented")
                        activity.runOnUiThread {
                            if (!host.failManualSourceCandidate("playlist-not-implemented") &&
                                !host.failStartupResolution(source.index, "playlist-not-implemented")
                            ) {
                                host.showStatusPillTransient("Couldn't switch source")
                            }
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - exception: ${e.message}", e)
            if (!host.failManualSourceCandidate("playlist-exception") &&
                !host.failStartupResolution(source.index, "playlist-exception")
            ) {
                host.showStatusPillTransient("Couldn't switch source")
            }
        }
    }

    fun showStremioSourceBadge() {
        if (host.ottSkinInstalled) {
            // The dock button is the sources affordance under OTT; the
            // top-right badge stays hidden. Availability can change per item
            // (Stremio-TV zaps replace the source list), so sync every show.
            host.ottSourcesButton?.visibility =
                if (host.stremioSources.isEmpty()) View.GONE else View.VISIBLE
            return
        }
        if (host.stremioSources.isEmpty()) return
        host.stremioSourceBadge?.animate()?.cancel()
        host.stremioSourceBadge?.visibility = View.VISIBLE
        host.stremioSourceBadge?.alpha = 0f
        host.stremioSourceBadge?.translationX = 30f
        host.stremioSourceBadge?.animate()
            ?.alpha(1f)
            ?.translationX(0f)
            ?.setDuration(250)
            ?.setInterpolator(DecelerateInterpolator(1.5f))
            ?.start()
    }

    fun hideStremioSourceBadge() {
        host.stremioSourceBadge?.animate()?.cancel()
        host.stremioSourceBadge?.animate()
            ?.alpha(0f)
            ?.translationX(20f)
            ?.setDuration(200)
            ?.setInterpolator(android.view.animation.AccelerateInterpolator(1.2f))
            ?.withEndAction {
                host.stremioSourceBadge?.visibility = View.GONE
                host.stremioSourceBadge?.translationX = 0f
            }
            ?.start()
    }

    /** Startup validation owns the same corner as this badge. Unlike the
     *  ordinary controls fade, gate activation must clear it synchronously so
     *  no frame can cover the only source-checking feedback. */
    fun hideStremioSourceBadgeImmediately() {
        host.stremioSourceBadge?.animate()?.cancel()
        host.stremioSourceBadge?.visibility = View.GONE
        host.stremioSourceBadge?.alpha = 0f
        host.stremioSourceBadge?.translationX = 0f
    }
}
