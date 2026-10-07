package com.debrify.app.tv

import android.content.Context
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

    // Manual community skip actions for the native TV player. Requests are
    // keyed by provider + episode + exact stream duration so source changes
    // cannot reuse timestamps from a differently cut release.
    private data class SkipSegmentRequest(
        val providerId: String,
        val imdbId: String,
        val season: Int,
        val episode: Int,
        val durationSeconds: Long,
        val key: String,
    )
        private const val MAX_SKIP_SEGMENT_CACHE_ENTRIES = 64
        private val IMDB_ID_REGEX = Regex("^tt\\d+$")

@OptIn(UnstableApi::class)
internal class TvSkipSegmentController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val skipSegmentButtonBound: Boolean
        val skipSegmentButton: AppCompatButton
        val skipSegmentsEnabled: Boolean
        val skipSegmentProviderId: String
        val isIptvMode: Boolean
        val payload: PlaybackPayload?
        val currentIndex: Int
        val hasEverBeenReady: Boolean
        val player: ExoPlayer?
        val playerView: PlayerView
        val controlsMenuVisible: Boolean
        val playlistVisible: Boolean
        val seekbarVisible: Boolean
        val upNextVisible: Boolean
        val subtitlePanel: SubtitlePanelController?
        val unifiedMenu: UnifiedMenuController?
        val sourceBrowser: TvSourceBrowserController?
        val syncOverlay: SubtitleSyncOverlayController?
        val linePickerOverlay: SubtitleLinePickerController?
        val seekFeedbackManagerBound: Boolean
        val seekFeedbackManager: SeekFeedbackManager
        fun releaseResumeHold()
    }
    val skipSegmentScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    var skipSegmentFetchJob: kotlinx.coroutines.Job? = null
    var skipSegmentFetchGeneration = 0
    private var loadedSkipSegmentKey: String? = null
    private var loadingSkipSegmentKey: String? = null
    private var skipSegments = TvSkipSegments.EMPTY
    private var activeSkipSegment: TvSkipSegment? = null
    private var skipFocusOfferedKey: String? = null
    val skipSegmentCache = mutableMapOf<String, TvSkipSegments>()

    private fun currentSkipSegmentRequest(durationMs: Long): SkipSegmentRequest? {
        if (!host.skipSegmentsEnabled ||
            !TvSkipSegmentClients.supports(host.skipSegmentProviderId) ||
            host.isIptvMode ||
            durationMs <= 0L ||
            durationMs == C.TIME_UNSET
        ) {
            return null
        }

        val model = host.payload ?: return null
        if (model.contentType.lowercase(Locale.US) != "series") return null
        val imdbId = model.imdbId?.trim()?.takeIf { IMDB_ID_REGEX.matches(it) } ?: return null
        val item = model.items.getOrNull(host.currentIndex) ?: return null
        val season = item.season?.takeIf { it >= 0 } ?: return null
        val episode = item.episode?.takeIf { it >= 1 } ?: return null
        val durationSeconds = durationMs / 1_000L
        if (durationSeconds <= 0L) return null

        return SkipSegmentRequest(
            providerId = host.skipSegmentProviderId,
            imdbId = imdbId,
            season = season,
            episode = episode,
            durationSeconds = durationSeconds,
            key = "${host.skipSegmentProviderId}:$imdbId:$season:$episode:$durationSeconds",
        )
    }

    fun updateSkipSegmentState(positionMs: Long, durationMs: Long) {
        if (!host.skipSegmentButtonBound) return

        // Between playlist items the player still reports the OUTGOING media's
        // position and duration for a moment, while currentIndex already names
        // the incoming episode. Judging the new episode against those makes the
        // button flash on as soon as next-episode is pressed — the old position
        // is usually deep in the outgoing episode, which lands inside a segment
        // — and fetches its segments against a duration that isn't its own,
        // which can select or validate the wrong release. Wait until the new
        // media is prepared; resetSkipSegmentState() has already hidden the button.
        if (!host.hasEverBeenReady) {
            presentSkipSegment(null, null)
            return
        }

        val request = currentSkipSegmentRequest(durationMs)
        if (request == null) {
            presentSkipSegment(null, null)
            return
        }

        if (loadedSkipSegmentKey != request.key) {
            ensureSkipSegments(request)
            presentSkipSegment(null, request.key)
            return
        }

        // The Up Next card owns the same end-of-episode action space. If it is
        // present, prefer its richer next-episode action; dismissing it reveals
        // Skip credits again if the outro is still active.
        val segment = if (host.upNextVisible) null else skipSegments.segmentAt(positionMs)
        presentSkipSegment(segment, request.key)
    }

    private fun ensureSkipSegments(request: SkipSegmentRequest) {
        if (loadedSkipSegmentKey == request.key || loadingSkipSegmentKey == request.key) return

        skipSegmentCache[request.key]?.let { cached ->
            skipSegments = cached
            loadedSkipSegmentKey = request.key
            return
        }

        if (loadingSkipSegmentKey != null && loadingSkipSegmentKey != request.key) {
            skipSegmentFetchGeneration++
            skipSegmentFetchJob?.cancel()
            skipSegmentFetchJob = null
            loadingSkipSegmentKey = null
        }

        val generation = ++skipSegmentFetchGeneration
        loadingSkipSegmentKey = request.key
        skipSegmentFetchJob = skipSegmentScope.launch {
            val result = try {
                withContext(Dispatchers.IO) {
                    TvSkipSegmentClients.fetch(
                        providerId = request.providerId,
                        imdbId = request.imdbId,
                        season = request.season,
                        episode = request.episode,
                        durationSeconds = request.durationSeconds,
                    )
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                // Skip data is optional and must never interrupt playback.
                android.util.Log.w(
                    "SkipSegments",
                    "${request.providerId} request failed",
                    error,
                )
                TvSkipSegments.EMPTY
            }

            if (generation != skipSegmentFetchGeneration) return@launch
            val liveDuration = host.player?.duration ?: C.TIME_UNSET
            if (currentSkipSegmentRequest(liveDuration)?.key != request.key) return@launch

            if (skipSegmentCache.size >= MAX_SKIP_SEGMENT_CACHE_ENTRIES) {
                skipSegmentCache.keys.firstOrNull()?.let { skipSegmentCache.remove(it) }
            }
            skipSegmentCache[request.key] = result
            skipSegments = result
            loadedSkipSegmentKey = request.key
            loadingSkipSegmentKey = null
            skipSegmentFetchJob = null
            val p = host.player ?: return@launch
            updateSkipSegmentState(p.currentPosition, p.duration)
        }
    }

    private fun presentSkipSegment(segment: TvSkipSegment?, requestKey: String?) {
        val button = host.skipSegmentButton
        activeSkipSegment = segment
        if (segment == null || requestKey == null) {
            if (button.visibility != View.GONE) {
                if (activity.currentFocus == button) host.playerView.requestFocus()
                button.animate().cancel()
                button.visibility = View.GONE
                button.alpha = 0f
                button.translationY = 0f
            }
            return
        }

        button.text = when (segment.type) {
            TvSkipSegmentType.INTRO -> "Skip intro »"
            TvSkipSegmentType.OUTRO -> "Skip credits »"
        }
        if (button.visibility != View.VISIBLE) {
            button.animate().cancel()
            button.alpha = 0f
            button.visibility = View.VISIBLE
            button.animate().alpha(1f).setDuration(160L).start()
        }

        val targetTranslationY = if (host.controlsMenuVisible) {
            -128f * activity.resources.displayMetrics.density
        } else {
            0f
        }
        if (kotlin.math.abs(button.translationY - targetTranslationY) > 0.5f) {
            button.animate().translationY(targetTranslationY).setDuration(180L).start()
        }

        val focusKey = "$requestKey:${segment.type}:${segment.startMs}"
        val canOfferFocus = !host.controlsMenuVisible &&
            !host.playlistVisible &&
            !host.seekbarVisible &&
            !host.upNextVisible &&
            host.subtitlePanel?.isVisible != true &&
            host.unifiedMenu?.isVisible != true &&
            host.sourceBrowser?.isVisible != true &&
            host.syncOverlay?.isVisible != true &&
            host.linePickerOverlay?.isVisible != true
        if (canOfferFocus && skipFocusOfferedKey != focusKey) {
            skipFocusOfferedKey = focusKey
            button.post { if (button.visibility == View.VISIBLE) button.requestFocus() }
        }
    }

    fun skipActiveSegment() {
        val p = host.player ?: return
        val segment = activeSkipSegment ?: return
        val position = p.currentPosition
        if (!segment.contains(position)) {
            updateSkipSegmentState(position, p.duration)
            return
        }
        val target = if (p.duration > 0L && p.duration != C.TIME_UNSET) {
            segment.endMs.coerceAtMost(p.duration)
        } else {
            segment.endMs
        }
        if (target <= position) return

        // Only caller is the on-screen skip button — a viewer choice, so it
        // outranks any pending resume hold even though the jump is forward.
        host.releaseResumeHold()
        p.seekTo(target)
        if (host.seekFeedbackManagerBound) {
            val seconds = ((target - position) / 1_000L).coerceAtLeast(1L)
            host.seekFeedbackManager.showSeekForward("${seconds}s")
        }
        presentSkipSegment(null, null)
    }

    fun resetSkipSegmentState() {
        skipSegmentFetchGeneration++
        skipSegmentFetchJob?.cancel()
        skipSegmentFetchJob = null
        loadingSkipSegmentKey = null
        loadedSkipSegmentKey = null
        skipSegments = TvSkipSegments.EMPTY
        activeSkipSegment = null
        skipFocusOfferedKey = null
        if (host.skipSegmentButtonBound) presentSkipSegment(null, null)
    }
}
