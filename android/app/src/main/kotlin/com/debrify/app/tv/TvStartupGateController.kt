package com.debrify.app.tv

import android.os.Handler
import android.os.SystemClock
import android.view.View
import com.debrify.app.diagnostics.DiagnosticFileLog
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.debrify.app.MainActivity
import com.debrify.app.R
import java.util.Locale
        private const val STARTUP_FAILOVER_TIMEOUT_MS = 12_000L
        // Watchdog recheck cadence once the base timeout has elapsed but the
        // candidate is still legitimately working (see startupWatchdogShouldExtend).
        private const val STARTUP_WATCHDOG_RECHECK_MS = 3_000L
        // Hard cap for a buffering-but-alive non-PikPak candidate.
        private const val STARTUP_SLOW_SOURCE_MAX_WAIT_MS = 45_000L
        // Hard cap while the PikPak cold-storage retry engine owns recovery
        // (its own worst case is ~10s metadata wait + 2/4/8/16/18s backoff).
        private const val STARTUP_PIKPAK_MAX_WAIT_MS = 120_000L
        private const val PIKPAK_GATE_REPREPARE_DELAY_MS = 4_000L

@OptIn(UnstableApi::class)
internal class TvStartupGateController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val controlsMenuVisible: Boolean
        var currentIndex: Int
        var currentStremioSourceIndex: Int
        fun failMoreTorrentSources(): Unit
        val hasPlaylistResolver: Boolean
        fun heldResumePositionMs(actualMs: Long): Long?
        fun hideStatusPill(): Unit
        val isIptvMode: Boolean
        val isStremioTvMode: Boolean
        val mediaPreparationGeneration: Int
        val moreSourcesLoadingMode: String?
        val movieMoreSources: Boolean
        val payload: PlaybackPayload?
        val pikPakRetryId: Int
        fun playItem(index: Int, suppressTrakt: Boolean): Unit
        val player: ExoPlayer?
        val progressHandler: Handler
        fun rebuildPlaylistContent(): Unit
        fun reportValidatedSourceCommit(sourceIndex: Int): Unit
        fun requestMoreTorrentSources(mode: String): Unit
        fun restartProgressUpdates(): Unit
        val seriesSourceTabs: Boolean
        fun setResolvingState(resolving: Boolean): Unit
        fun showStatusPillTransient(message: String): Unit
        val sourceBrowser: TvSourceBrowserController?
        val sourcePersistenceSessionId: Int
        val sourceSwitchController: TvSourceSwitchController
        val startupGateStatus: TextView
        val startupGateView: View
        var stremioResolutionToken: Int
        val stremioSources: MutableList<StremioSource>
        val titleView: TextView
    }
    // VOD is not exposed as successfully started until ExoPlayer renders a
    // frame. HTTP errors, resolver failures and silent startup stalls advance
    // this cursor through the already-ranked source list.
    internal var startupFailoverCursor: StartupFailoverCursor? = null
    internal var startupFailoverGeneration = 0
    internal var startupFailoverTimeout: Runnable? = null
    internal var startupCommitCheck: Runnable? = null
    private var startupFirstFrameAtElapsedMs = 0L
    private var startupCandidateStartedElapsedMs = 0L
    internal var startupFailoverDispatching = false
    internal var startupTryNextOnFailure = false
    internal var startupMaxAttempts = 1
    internal var startupResolverProvider: String? = null
    internal var startupRecoveryAvailable = false
    internal var startupHasRemainingSavedSources = false
    internal var startupRecoveryFetching = false
    internal var startupRecoveryConsumed = false
    internal var startupRecoveryProducedCandidates = false
    internal var startupRecoveryNextMode: String? = null
    internal var startupRecoveryCandidateIndices: List<Int>? = null
    private val startupFailedReleases = mutableSetOf<List<Any?>>()
    internal var startupSourcesExhausted = false
    private var startupPikPakTorrentAcquisitionAttempted = false
    // An explicit in-player source pick is a one-candidate transaction. It
    // shares the startup decoder/slate checks, but never advances to another
    // row and never exposes candidate progress to Flutter scrobbling.
    internal var manualSourceSwitchSnapshot: ManualSourceSwitchSnapshot? = null
    internal var manualSourceSwitchIndex: Int? = null
    internal var manualSourceSwitchTimeout: Runnable? = null
    internal var manualSourceCommitCheck: Runnable? = null
    private var manualSourceFirstFrameAtElapsedMs = 0L
    private var manualSourceCandidateStartedElapsedMs = 0L
    internal var pikPakGateReprepare: Runnable? = null
    internal var manualSourceMediaReplaced = false
    internal var manualSourceCandidateUrl: String? = null
    internal var manualSourceRestoreInProgress = false

    // ═══════════════════════════════════════════════════════════════════════
    // Stremio Source Switcher
    // ═══════════════════════════════════════════════════════════════════════

    fun beginStartupFailoverIfEligible() {
        startupSourcesExhausted = false
        startupRecoveryConsumed = false
        startupRecoveryProducedCandidates = false
        startupRecoveryNextMode = null
        startupRecoveryCandidateIndices = null
        startupFailedReleases.clear()
        val model = host.payload
        if (model == null) {
            startupLog("event=bypass reason=missing_payload")
            return
        }
        val source = host.stremioSources.getOrNull(host.currentStremioSourceIndex)
        val validateChannelSlate = host.isStremioTvMode && isAioStreamsSource(
            addonId = source?.addonId,
            sourceName = source?.source,
            displayName = source?.name,
            url = source?.directUrl,
        )
        // AIOStreams may return a decodable error clip. Retain its validation
        // and progress suppression, but armStartupCandidate leaves channel
        // opens without the VOD deadline. Manual picks keep their own gate.
        if (host.isIptvMode || (host.isStremioTvMode && !validateChannelSlate) ||
            host.stremioSources.isEmpty() || model.items.isEmpty()
        ) {
            val reason = when {
                host.isIptvMode -> "iptv"
                host.isStremioTvMode -> "stremio_tv"
                host.stremioSources.isEmpty() -> "no_sources"
                else -> "no_items"
            }
            startupLog("event=bypass reason=$reason")
            return
        }

        val cursor = StartupFailoverCursor(
            startIndex = host.currentStremioSourceIndex,
            maxAttempts = if (startupTryNextOnFailure) startupMaxAttempts else 1,
        )
        val first = cursor.beginInitial(host.stremioSources.size) ?: return
        startupFailoverCursor = cursor
        startupPikPakTorrentAcquisitionAttempted =
            startupResolverProvider.equals("pikpak", ignoreCase = true) &&
                host.stremioSources.getOrNull(host.currentStremioSourceIndex)?.streamType == "torrent"
        // Visibility is decided per candidate in armStartupCandidate: a
        // debrid-direct first open keeps the player surface (pre-ladder
        // look); the gate appears only when failover starts retrying.
        host.sourceSwitchController.hideStremioSourceBadgeImmediately()
        val item = model.items.getOrNull(host.currentIndex)
        startupLog(
            "event=begin sourceCount=${host.stremioSources.size} selectedIndex=${host.currentStremioSourceIndex} " +
                "tryNext=$startupTryNextOnFailure maxAttempts=${if (startupTryNextOnFailure) startupMaxAttempts else 1} " +
                "playlistResolver=${host.hasPlaylistResolver} targetSeason=${item?.season ?: "-"} " +
                "targetEpisode=${item?.episode ?: "-"}",
        )
        armStartupCandidate(first)
    }

    fun beginManualSourceCandidate(sourceIndex: Int) {
        val model = host.payload ?: return
        manualSourceRestoreInProgress = false
        if (manualSourceSwitchSnapshot != null) {
            failManualSourceCandidate("superseded", showFailure = false)
        }
        // An unlanded resume outranks the live position: a failed candidate
        // must roll back to the BOOKMARK, not to the ~0 the dropped/clamped
        // resume left playback at. (The hold window restarts on rollback via
        // playItem → READY re-arm from this snapshot's resumePositionMs.)
        val livePosition = (host.player?.currentPosition ?: 0L).coerceAtLeast(0L)
        val position = host.heldResumePositionMs(livePosition) ?: livePosition
        val savedItems = model.items.mapIndexed { index, item ->
            if (index == host.currentIndex) item.copy(resumePositionMs = position) else item
        }
        manualSourceSwitchSnapshot = ManualSourceSwitchSnapshot(
            sourceIndex = host.currentStremioSourceIndex,
            itemIndex = host.currentIndex,
            contentType = model.contentType,
            items = savedItems,
            nextEpisodeMap = model.nextEpisodeMap,
            prevEpisodeMap = model.prevEpisodeMap,
            collectionGroups = model.collectionGroups,
            perItemImdbIds = model.perItemImdbIds.toMap(),
            title = host.titleView.text?.toString(),
        )
        manualSourceSwitchIndex = sourceIndex
        manualSourceMediaReplaced = false
        manualSourceCandidateUrl = null
        manualSourceFirstFrameAtElapsedMs = 0L
        manualSourceCandidateStartedElapsedMs = SystemClock.elapsedRealtime()
        manualSourceSwitchTimeout?.let { host.progressHandler.removeCallbacks(it) }
        val timeout = object : Runnable {
            override fun run() {
                if (manualSourceSwitchSnapshot == null ||
                    manualSourceSwitchIndex != sourceIndex
                ) {
                    return
                }
                // Only once the candidate's media is actually loaded — before
                // that, player state (and the current item) still belong to
                // the outgoing source and must not earn the candidate grace.
                if (manualSourceMediaReplaced &&
                    startupWatchdogShouldExtend(manualSourceCandidateStartedElapsedMs)
                ) {
                    startupLog(
                        "event=manual_watchdog_extend sourceIndex=$sourceIndex " +
                            "pikpak=${currentPlaybackItemIsPikPak()}",
                    )
                    host.progressHandler.postDelayed(this, STARTUP_WATCHDOG_RECHECK_MS)
                    return
                }
                failManualSourceCandidate("timeout")
            }
        }
        manualSourceSwitchTimeout = timeout
        host.progressHandler.postDelayed(timeout, STARTUP_FAILOVER_TIMEOUT_MS)
        startupLog(
            "event=manual_candidate_open ${startupSourceFields(sourceIndex)} " +
                "timeoutMs=$STARTUP_FAILOVER_TIMEOUT_MS",
        )
    }

    fun commitManualSourceCandidate() {
        val snapshot = manualSourceSwitchSnapshot ?: return
        val sourceIndex = manualSourceSwitchIndex ?: return
        if (!manualSourceMediaReplaced) return
        val source = host.stremioSources.getOrNull(sourceIndex)
        val duration = host.player?.duration ?: C.TIME_UNSET
        val isAioStreams = isAioStreamsSource(
            addonId = source?.addonId,
            sourceName = source?.source,
            displayName = source?.name,
            url = source?.directUrl,
        )
        if (isAioStreams && duration <= 0L &&
            (manualSourceFirstFrameAtElapsedMs == 0L ||
                SystemClock.elapsedRealtime() - manualSourceFirstFrameAtElapsedMs < 1_000L)
        ) {
            if (manualSourceFirstFrameAtElapsedMs == 0L) {
                manualSourceFirstFrameAtElapsedMs = SystemClock.elapsedRealtime()
            }
            if (manualSourceCommitCheck == null) {
                val check = Runnable {
                    manualSourceCommitCheck = null
                    commitManualSourceCandidate()
                }
                manualSourceCommitCheck = check
                host.progressHandler.postDelayed(check, 200L)
            }
            return
        }
        if (isAioStreamsErrorSlate(
                addonId = source?.addonId,
                sourceName = source?.source,
                displayName = source?.name,
                url = source?.directUrl,
                durationMs = duration,
            )
        ) {
            failManualSourceCandidate("aiostreams-error-slate:$duration")
            return
        }

        manualSourceSwitchTimeout?.let { host.progressHandler.removeCallbacks(it) }
        manualSourceSwitchTimeout = null
        manualSourceCommitCheck?.let { host.progressHandler.removeCallbacks(it) }
        manualSourceCommitCheck = null
        pikPakGateReprepare?.let { host.progressHandler.removeCallbacks(it) }
        pikPakGateReprepare = null
        manualSourceCandidateUrl?.let { url ->
            host.payload?.items?.getOrNull(host.currentIndex)?.let { item ->
                host.payload?.items?.set(host.currentIndex, item.copy(url = url))
            }
        }
        manualSourceSwitchSnapshot = null
        manualSourceSwitchIndex = null
        manualSourceMediaReplaced = false
        manualSourceCandidateUrl = null
        host.restartProgressUpdates()
        host.reportValidatedSourceCommit(sourceIndex)
        sourceSelectionLog("player_switch_committed", sourceIndex, snapshot.sourceIndex)
        host.showStatusPillTransient("✓ ${source?.displayTitle ?: "Source"}")
        startupLog(
            "event=manual_candidate_commit ${startupSourceFields(sourceIndex)} " +
                "durationMs=$duration previousSourceIndex=${snapshot.sourceIndex}",
        )
    }

    internal fun failManualSourceCandidate(
        reason: String,
        showFailure: Boolean = true,
    ): Boolean {
        val snapshot = manualSourceSwitchSnapshot ?: return false
        val failedIndex = manualSourceSwitchIndex
        manualSourceSwitchTimeout?.let { host.progressHandler.removeCallbacks(it) }
        manualSourceSwitchTimeout = null
        manualSourceCommitCheck?.let { host.progressHandler.removeCallbacks(it) }
        manualSourceCommitCheck = null
        pikPakGateReprepare?.let { host.progressHandler.removeCallbacks(it) }
        pikPakGateReprepare = null
        host.stremioResolutionToken++
        host.sourceSwitchController.cancelSourceSwitchWait()
        host.setResolvingState(false)

        val model = host.payload
        if (model != null) {
            model.items.clear()
            model.items.addAll(snapshot.items)
            model.contentType = snapshot.contentType
            model.nextEpisodeMap = snapshot.nextEpisodeMap
            model.prevEpisodeMap = snapshot.prevEpisodeMap
            model.collectionGroups = snapshot.collectionGroups
            model.perItemImdbIds.clear()
            model.perItemImdbIds.putAll(snapshot.perItemImdbIds)
        }
        host.currentStremioSourceIndex = snapshot.sourceIndex
        host.currentIndex = snapshot.itemIndex.coerceIn(
            0,
            (model?.items?.lastIndex ?: 0).coerceAtLeast(0),
        )
        snapshot.title?.let { host.titleView.text = it }
        host.sourceSwitchController.updateStremioQualityBadge()
        host.sourceBrowser?.render()

        val replaced = manualSourceMediaReplaced
        manualSourceSwitchSnapshot = null
        manualSourceSwitchIndex = null
        manualSourceMediaReplaced = false
        manualSourceCandidateUrl = null
        if (replaced && model != null && model.items.isNotEmpty()) {
            // Keep tracker/local progress muted until the known source has
            // rendered again. Player callbacks queued by the rejected media
            // can otherwise arrive after the transaction snapshot is cleared.
            manualSourceRestoreInProgress = true
            host.player?.stop()
            host.rebuildPlaylistContent()
            host.playItem(host.currentIndex, suppressTrakt = true)
        }
        if (showFailure) {
            host.showStatusPillTransient("This source is unavailable — choose another source")
        } else {
            host.hideStatusPill()
        }
        startupLog(
            "event=manual_candidate_reject ${startupSourceFields(failedIndex ?: -1)} " +
                "reason=$reason restoredSourceIndex=${snapshot.sourceIndex}",
            warning = true,
        )
        sourceSelectionLog("player_switch_rejected", failedIndex ?: -1, snapshot.sourceIndex, reason)
        return true
    }

    internal fun armStartupCandidate(sourceIndex: Int) {
        startupFailoverTimeout?.let { host.progressHandler.removeCallbacks(it) }
        startupCommitCheck?.let { host.progressHandler.removeCallbacks(it) }
        startupCommitCheck = null
        startupFirstFrameAtElapsedMs = 0L
        startupCandidateStartedElapsedMs = SystemClock.elapsedRealtime()
        startupFailoverGeneration++
        val generation = startupFailoverGeneration
        val timeout = object : Runnable {
            override fun run() {
                if (generation != startupFailoverGeneration ||
                    startupFailoverCursor?.committed != false
                ) {
                    return
                }
                if (startupWatchdogShouldExtend(startupCandidateStartedElapsedMs)) {
                    startupLog(
                        "event=watchdog_extend generation=$generation " +
                            "elapsedMs=${startupCandidateElapsedMs()} " +
                            "pikpak=${currentPlaybackItemIsPikPak()}",
                    )
                    host.progressHandler.postDelayed(this, STARTUP_WATCHDOG_RECHECK_MS)
                    return
                }
                failStartupCandidate("timeout")
            }
        }
        startupFailoverTimeout = if (host.isStremioTvMode) null else timeout
        if (!host.isStremioTvMode) {
            host.progressHandler.postDelayed(timeout, STARTUP_FAILOVER_TIMEOUT_MS)
        }
        val attempt = startupFailoverCursor?.attempts ?: 1
        // Mirrors the Dart gate copy: a debrid-direct first open is loading
        // the user's own source, not "checking" candidates. Failover retries
        // keep the counter.
        val debridFirstOpen = attempt <= 1 &&
            host.stremioSources.getOrNull(sourceIndex)?.streamType == "torrent" &&
            !currentPlaybackItemIsPikPak()
        host.startupGateView.visibility =
            if (debridFirstOpen) View.GONE else View.VISIBLE
        val heading = activity.findViewById<TextView>(R.id.startup_title)
        heading.text = host.titleView.text
        heading.animate().cancel()
        heading.alpha = 0f
        heading.translationY = 12f
        heading.animate().alpha(1f).translationY(0f).setDuration(600L).start()
        if (!debridFirstOpen && !host.startupGateView.hasFocus()) {
            activity.findViewById<View>(R.id.startup_back).requestFocus()
        }
        activity.findViewById<TextView>(R.id.startup_explanation).text = if (attempt <= 1)
            "Connecting and waiting for the first frames."
        else "The previous source couldn’t start. Trying an alternative."
        host.startupGateStatus.text = if (debridFirstOpen) {
            "Loading stream…"
        } else if (attempt <= 1) {
            "Opening your stream"
        } else {
            "Connecting to another source"
        }
        startupLog(
            "event=candidate_open attempt=$attempt " +
                "generation=$generation ${startupSourceFields(sourceIndex)} " +
                "timeoutMs=${if (host.isStremioTvMode) "none" else STARTUP_FAILOVER_TIMEOUT_MS}",
        )
    }

    fun commitStartupCandidate() {
        val cursor = startupFailoverCursor ?: return
        if (cursor.committed) return
        val source = host.stremioSources.getOrNull(host.currentStremioSourceIndex)
        val isAioStreams = isAioStreamsSource(
            addonId = source?.addonId,
            sourceName = source?.source,
            displayName = source?.name,
            url = source?.directUrl,
        )
        val duration = host.player?.duration ?: C.TIME_UNSET
        if (isAioStreams && duration <= 0L &&
            (startupFirstFrameAtElapsedMs == 0L ||
                SystemClock.elapsedRealtime() - startupFirstFrameAtElapsedMs < 1_000L)
        ) {
            // Some progressive sources publish their timeline just after the
            // first frame. Give duration its existing one-second grace; this
            // does not impose a network startup deadline on channel playback.
            if (startupFirstFrameAtElapsedMs == 0L) {
                startupFirstFrameAtElapsedMs = SystemClock.elapsedRealtime()
                startupLog(
                    "event=duration_grace ${startupSourceFields(host.currentStremioSourceIndex)} " +
                        "reason=aiostreams_duration_unknown",
                )
            }
            if (startupCommitCheck == null) {
                val check = Runnable {
                    startupCommitCheck = null
                    commitStartupCandidate()
                }
                startupCommitCheck = check
                host.progressHandler.postDelayed(check, 200L)
            }
            return
        }
        if (isAioStreamsErrorSlate(
                addonId = source?.addonId,
                sourceName = source?.source,
                displayName = source?.name,
                url = source?.directUrl,
                durationMs = duration,
            )
        ) {
            // AIOStreams/ElfHosted returns a short, perfectly decodable video
            // for errors such as Wrong IP. A first-frame-only gate would accept
            // that interstitial, so reject its implausible VOD duration while
            // it is still hidden by startupGateView.
            failStartupCandidate("aiostreams-error-slate:$duration")
            return
        }
        cursor.commit()
        startupFailoverTimeout?.let { host.progressHandler.removeCallbacks(it) }
        startupFailoverTimeout = null
        startupCommitCheck?.let { host.progressHandler.removeCallbacks(it) }
        startupCommitCheck = null
        pikPakGateReprepare?.let { host.progressHandler.removeCallbacks(it) }
        pikPakGateReprepare = null
        startupFailoverGeneration++
        host.startupGateView.visibility = View.GONE
        if (host.controlsMenuVisible) host.sourceSwitchController.showStremioSourceBadge()
        host.hideStatusPill()
        host.restartProgressUpdates()
        host.reportValidatedSourceCommit(host.currentStremioSourceIndex)
        startupLog(
            "event=commit attempts=${cursor.attempts} ${startupSourceFields(host.currentStremioSourceIndex)} " +
                "elapsedMs=${startupCandidateElapsedMs()} durationMs=$duration",
        )
    }

    internal fun failStartupCandidate(reason: String) {
        val cursor = startupFailoverCursor ?: return
        if (cursor.committed || startupFailoverDispatching) return
        startupFailoverDispatching = true
        try {
            if (reason != "recovery-results") {
                host.stremioSources.getOrNull(host.currentStremioSourceIndex)?.let {
                    startupFailedReleases.add(it.failureKey(reason))
                }
                MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("startupSourceFailed", mapOf(
                    "sourcePersistenceSessionId" to host.sourcePersistenceSessionId,
                    "sourceIndex" to host.currentStremioSourceIndex, "reason" to reason,
                ))
            }
            startupFailoverTimeout?.let { host.progressHandler.removeCallbacks(it) }
            startupFailoverTimeout = null
            startupCommitCheck?.let { host.progressHandler.removeCallbacks(it) }
            startupCommitCheck = null
            pikPakGateReprepare?.let { host.progressHandler.removeCallbacks(it) }
            pikPakGateReprepare = null
            startupFailoverGeneration++
            host.stremioResolutionToken++ // invalidate any resolver callback for the failed row
            host.sourceSwitchController.cancelSourceSwitchWait()
            host.setResolvingState(false)
            host.player?.stop()

            val nextIndex = cursor.nextIndex(host.stremioSources.size, startupRecoveryCandidateIndices) { index ->
                val candidate = host.stremioSources.getOrNull(index)
                candidate?.streamType != "externalUrl" &&
                    candidate?.let {
                        it.failureKey("player:ERROR_CODE_DECODING_FAILED") !in startupFailedReleases &&
                            it.failureKey() !in startupFailedReleases
                    } == true &&
                    !(startupResolverProvider.equals("pikpak", ignoreCase = true) &&
                        startupPikPakTorrentAcquisitionAttempted &&
                        candidate?.streamType == "torrent")
            }
            if (nextIndex == null) {
                startupRecoveryConsumed = startupRecoveryIsConsumed(
                    startupHasRemainingSavedSources, startupRecoveryProducedCandidates,
                    cursor.attempts, if (startupTryNextOnFailure) startupMaxAttempts else 1)
                val initialRecovery = startupRecoveryAvailable && host.stremioSources.size == 1 &&
                    host.stremioSources.first().isDirectStream && (host.seriesSourceTabs || host.movieMoreSources)
                if (!startupHasRemainingSavedSources && startupTryNextOnFailure &&
                    cursor.attempts < startupMaxAttempts &&
                    (initialRecovery || startupRecoveryNextMode != null)) {
                    // Keep the opaque gate and this activity alive while Dart
                    // expands the episode/movie results. The cursor's attempt
                    // budget and attempted indices survive the fetch.
                    startupRecoveryAvailable = false
                    startupRecoveryFetching = true
                    val recoveryMode = startupRecoveryNextMode ?: "startup:begin"
                    startupRecoveryNextMode = null
                    startupLog("event=recovery_fetch attempts=${cursor.attempts}")
                    host.requestMoreTorrentSources(recoveryMode)
                    host.progressHandler.postDelayed({
                        if (startupRecoveryFetching && host.moreSourcesLoadingMode == recoveryMode && !activity.isFinishing && !activity.isDestroyed) {
                            host.failMoreTorrentSources()
                        }
                    }, 30_000L)
                    return
                }
                startupSourcesExhausted = true
                startupLog(
                    "event=exhausted attempts=${cursor.attempts} " +
                        "${startupSourceFields(host.currentStremioSourceIndex)} reason=$reason",
                    warning = true,
                )
                startupFailoverCursor = null
                host.hideStatusPill()
                Toast.makeText(
                    activity,
                    if (startupRecoveryAvailable) {
                        "Saved source failed. Looking for another source…"
                    } else {
                        "No playable source could be started"
                    },
                    Toast.LENGTH_LONG,
                ).show()
                activity.finish()
                return
            }
            if (startupResolverProvider.equals("pikpak", ignoreCase = true) &&
                host.stremioSources.getOrNull(nextIndex)?.streamType == "torrent"
            ) {
                // Count before resolution: PikPak may enqueue cold storage even
                // when Flutter ultimately cannot return a playable URL.
                startupPikPakTorrentAcquisitionAttempted = true
            }

            startupLog(
                "event=candidate_result ok=false attempt=${cursor.attempts} " +
                    "${startupSourceFields(host.currentStremioSourceIndex)} reason=$reason " +
                    "elapsedMs=${startupCandidateElapsedMs()} nextIndex=$nextIndex",
                warning = true,
            )
            host.currentStremioSourceIndex = nextIndex
            host.sourceSwitchController.updateStremioQualityBadge()
            host.sourceBrowser?.render()
            armStartupCandidate(nextIndex)
            val next = host.stremioSources.getOrNull(nextIndex)
            if (next != null) {
                host.sourceSwitchController.onStremioSourceSelected(next)
            } else {
                // Unreachable today (nextIndex is always < size), but never
                // recurse under the dispatch guard — it would swallow the call
                // and stall behind the gate until the watchdog. Re-enter on
                // the next loop tick instead.
                host.progressHandler.post { failStartupCandidate("missing-source") }
            }
        } finally {
            startupFailoverDispatching = false
        }
    }

    internal fun failStartupResolution(sourceIndex: Int, reason: String): Boolean {
        val cursor = startupFailoverCursor
        if (cursor?.committed != false || sourceIndex != host.currentStremioSourceIndex) {
            startupLog(
                "event=failure_ignored ${startupSourceFields(sourceIndex)} reason=$reason " +
                    "currentIndex=${host.currentStremioSourceIndex} committed=${cursor?.committed}",
            )
            return false
        }
        failStartupCandidate(reason)
        return true
    }

    private fun startupCandidateElapsedMs(): Long =
        if (startupCandidateStartedElapsedMs <= 0L) 0L
        else (SystemClock.elapsedRealtime() - startupCandidateStartedElapsedMs).coerceAtLeast(0L)

    internal fun currentPlaybackItemIsPikPak(): Boolean =
        isPikPakPlaybackItem(host.payload?.items?.getOrNull(host.currentIndex))

    internal fun cancelPikPakGateReprepare() {
        pikPakGateReprepare?.let { host.progressHandler.removeCallbacks(it) }
        pikPakGateReprepare = null
    }

    // After a player error ExoPlayer sits in IDLE and the PikPak retry
    // engine (which only monitors readiness) can never see metadata arrive.
    // A spaced re-prepare re-issues the HTTP request — which is also what
    // re-triggers PikPak's cold-storage warmup server-side. Guarded at fire
    // time so a completed gate/retry or a replacement media item drops it.
    fun schedulePikPakGateReprepare(retryId: Int? = null) {
        if (pikPakGateReprepare != null) return
        val retryPlayer = host.player
        val retryToken = host.pikPakRetryId
        val mediaGeneration = host.mediaPreparationGeneration
        val reprepare = Runnable {
            pikPakGateReprepare = null
            val gateActive = startupFailoverCursor?.committed == false ||
                manualSourceSwitchSnapshot != null
            val channelRetryActive = host.isStremioTvMode && retryId == host.pikPakRetryId
            if (activity.isFinishing || activity.isDestroyed || host.player !== retryPlayer ||
                retryToken != host.pikPakRetryId || mediaGeneration != host.mediaPreparationGeneration ||
                (!gateActive && !channelRetryActive) || !currentPlaybackItemIsPikPak()
            ) return@Runnable
            if (host.player?.playerError == null) return@Runnable
            startupLog("event=pikpak_reprepare")
            host.player?.prepare()
            host.player?.play()
        }
        pikPakGateReprepare = reprepare
        host.progressHandler.postDelayed(reprepare, PIKPAK_GATE_REPREPARE_DELAY_MS)
    }

    // Whether a startup/manual validation watchdog should hold its fire
    // instead of failing the candidate:
    //  - PikPak cold storage routinely needs 10-30s (sometimes more) before
    //    the file warms up; the dedicated retry engine owns recovery and
    //    reports its own exhaustion back to the gate. Killing it at the base
    //    timeout regresses playback that recovered on its own — and the
    //    acquisition guard would then skip every other torrent row.
    //  - A non-PikPak source whose buffer keeps growing is slow, not dead
    //    (large 4K remux, cold CDN); give it a bounded grace.
    private fun startupWatchdogShouldExtend(startedElapsedMs: Long): Boolean {
        val elapsed =
            if (startedElapsedMs <= 0L) 0L
            else SystemClock.elapsedRealtime() - startedElapsedMs
        if (currentPlaybackItemIsPikPak()) {
            return elapsed < STARTUP_PIKPAK_MAX_WAIT_MS
        }
        val activePlayer = host.player ?: return false
        val loadingWithData = activePlayer.playerError == null &&
            activePlayer.playbackState == Player.STATE_BUFFERING &&
            activePlayer.totalBufferedDuration > 0L
        return loadingWithData && elapsed < STARTUP_SLOW_SOURCE_MAX_WAIT_MS
    }

    internal fun startupSourceFields(index: Int): String {
        val source = host.stremioSources.getOrNull(index)
        val sourceType = source?.streamType
            ?.lowercase(Locale.US)
            ?.replace(Regex("[^a-z0-9_.-]"), "_")
            ?.take(32)
            ?.ifBlank { "-" }
            ?: "-"
        return "sourceIndex=$index type=$sourceType " +
            "addonPresent=${!source?.addonId.isNullOrBlank()} " +
            "sourcePresent=${!source?.source.isNullOrBlank()} " +
            "mediaServer=${source?.source?.startsWith("mediaserver:") == true}"
    }

    internal fun mediaServerPlaybackLog(event: String, errorCode: Int? = null, httpStatus: Int? = null) {
        val source = host.stremioSources.firstOrNull { it.index == host.currentStremioSourceIndex }
        if (source?.source?.startsWith("mediaserver:") != true) return
        DiagnosticFileLog.record(
            source = "media_server", event = event,
            message = "player=exo index=${host.currentStremioSourceIndex} errorCode=$errorCode httpStatus=$httpStatus",
        )
    }

    internal fun sourceSelectionLog(event: String, index: Int, previous: Int? = null, reason: String? = null) {
        val item = host.payload?.items?.getOrNull(host.currentIndex)
        val source = host.stremioSources.firstOrNull { it.index == index }
        val message = "SourceSelect: event=$event player=exo index=$index previous=$previous " +
            "season=${item?.season} episode=${item?.episode} transport=${source?.streamType} reason=$reason " +
            "mediaServer=${source?.source?.startsWith("mediaserver:") == true}"
        DiagnosticFileLog.record(source = "source_selection", event = event, message = message)
        android.util.Log.i("SourceSelect", message)
    }
}
