package com.debrify.app.tv

import android.animation.ValueAnimator
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.PaintDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RectShape
import android.view.LayoutInflater
import android.media.MediaCodecList
import android.os.Bundle
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import androidx.core.content.ContextCompat
import androidx.core.widget.TextViewCompat
import com.debrify.app.recording.LiveRecordingService
import com.debrify.app.recording.RecordingAlarmReceiver
import com.debrify.app.recording.RecordingRegistry
import com.debrify.app.recording.RecordingSchedule
import com.debrify.app.recording.RecordingScheduleStore
import com.debrify.app.diagnostics.DiagnosticFileLog
import com.debrify.app.audio.NativeAudioRouting
import com.debrify.app.audio.NativeAudioRenderersFactory
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.annotation.OptIn
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.exoplayer.hls.HlsManifest
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.text.Cue
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import android.net.ConnectivityManager
import android.net.Network
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import com.debrify.app.ActivityTracker
import com.debrify.app.MainActivity
import com.debrify.app.R
import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import com.debrify.app.subtitle.StremioAddon
import com.debrify.app.subtitle.StremioSubtitle
import com.debrify.app.subtitle.StremioSubtitleService
import com.debrify.app.util.AlignResult
import com.debrify.app.util.CueSpan
import com.debrify.app.util.LanguageMapper
import com.debrify.app.util.OffsetRenderersFactory
import com.debrify.app.util.SubtitleAligner
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleCueCache
import com.debrify.app.util.SubtitleFontManager
import com.debrify.app.util.SubtitleSettings
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import kotlin.concurrent.thread

@OptIn(UnstableApi::class)
internal class TvProgressReporter(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val currentIndex: Int
        val currentIptvIndex: Int
        val currentStremioSourceIndex: Int
        val finalProgressSnapshot: Boolean
        fun heldResumePositionMs(actualMs: Long): Long?
        val iptvChannels: MutableList<IptvChannelEntry>
        val isIptvMode: Boolean
        val isStremioTvMode: Boolean
        val manualSourceRestoreInProgress: Boolean
        val manualSourceSwitchSnapshot: ManualSourceSwitchSnapshot?
        val maxStableDurationMs: Long
        val payload: PlaybackPayload?
        val playbackSpeedIndex: Int
        val playbackSpeeds: Array<Float>
        val player: ExoPlayer?
        val playlistAdapter: PlaylistOverlayAdapter?
        val playlistVisible: Boolean
        fun recordPlaybackLifecycle(event: String, details: String = ""): Unit
        val recoveryDataGeneration: Int
        val recoveryImdbId: String?
        val recoveryProfileId: String?
        val recoverySeriesTitle: String?
        val recoveryStartedAtMs: Long
        val recoveryTitle: String?
        val resizeModeIndex: Int
        val resizeModeLabels: Array<String>
        val sourcePersistenceSessionId: Int
        val startupFailoverCursor: StartupFailoverCursor?
        val startupSourcesExhausted: Boolean
    }
    private var recoverySequence = 0L
    // One local-threshold report per content identity. Flutter owns the durable
    // completed state; this only prevents sending a write-trigger on every
    // five-second progress pulse after the threshold has been crossed.
    // A fetched direct episode replaces the one-entry playlist in place, so
    // its index is always 0. Deduplicate completion by episode identity rather
    // than index or only the first direct episode could cross the threshold.
    val locallyCompletedItemKeys = mutableSetOf<String>()
    val recoveryCompletedItemKeys = mutableSetOf<String>()

    var progressSentCount = 0
    var progressAckCount = 0
    private var lastProgressLogAt = 0L
    private var lastProgressAckAt = 0L
    private var lastProgressBridgeAvailable: Boolean? = null

    /** Observe delivery, including a missing/detached Flutter engine. No media
     * identity or URL is logged. A callback confirms the Dart handler finished. */
    private fun deliverProgress(map: HashMap<String, Any?>) {
        map["sourcePersistenceSessionId"] = host.sourcePersistenceSessionId
        val recoverySequenceForMap = ++recoverySequence
        stageRecoveryCheckpoint(
            map,
            recoverySequenceForMap,
            synchronous = host.finalProgressSnapshot,
        )
        val channel = MainActivity.getAndroidTvPlayerChannel()
        val now = SystemClock.elapsedRealtime()
        val forceLog = host.finalProgressSnapshot || map["completed"] == true
        val logSample = forceLog || lastProgressLogAt == 0L ||
            now - lastProgressLogAt >= 60_000L ||
            lastProgressBridgeAvailable != (channel != null)
        if (logSample) {
            lastProgressLogAt = now
            host.recordPlaybackLifecycle(
                "progress_checkpoint",
                "bridgeAvailable=${channel != null} positionMs=${map["positionMs"]} " +
                    "durationMs=${map["durationMs"]} completed=${map["completed"]} " +
                    "lastAckAgeMs=${if (lastProgressAckAt == 0L) -1 else now - lastProgressAckAt}",
            )
        }
        lastProgressBridgeAvailable = channel != null
        if (channel == null) return
        progressSentCount++
        try {
            channel.invokeMethod("torrentPlaybackProgress", map, object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true) {
                        progressAckCount++
                        lastProgressAckAt = SystemClock.elapsedRealtime()
                        acknowledgeRecoveryCheckpoint(recoverySequenceForMap)
                    }
                    if (logSample) host.recordPlaybackLifecycle("progress_ack", "accepted=${result == true}")
                }
                override fun error(code: String, message: String?, details: Any?) {
                    if (logSample) host.recordPlaybackLifecycle("progress_ack_error")
                }
                override fun notImplemented() {
                    if (logSample) host.recordPlaybackLifecycle("progress_handler_missing")
                }
            })
        } catch (error: RuntimeException) {
            if (logSample) DiagnosticFileLog.recordError(
                source = "android_tv_player", event = "progress_delivery_failed", throwable = error,
            )
        }
    }

    private fun stageRecoveryCheckpoint(
        progress: Map<String, Any?>,
        sequence: Long,
        synchronous: Boolean,
    ) {
        // IPTV VOD has a separate Dart store; never disguise it as a movie.
        if (host.isIptvMode || progress["mode"] == "iptv") return
        val ownerProfileId = host.recoveryProfileId ?: return
        if (host.recoveryDataGeneration <= 0 || host.sourcePersistenceSessionId <= 0) return
        val positionMs = (progress["positionMs"] as? Number)?.toLong() ?: 0L
        val durationMs = (progress["durationMs"] as? Number)?.toLong() ?: 0L
        if (positionMs <= 0L || durationMs <= 0L) return

        val snapshot = JSONObject()
            .put("version", 1)
            .put("sessionId", host.sourcePersistenceSessionId)
            .put("sequence", sequence)
            .put("profileId", ownerProfileId)
            .put("dataGeneration", host.recoveryDataGeneration)
            .put("startedAtMs", host.recoveryStartedAtMs)
            .put("updatedAtMs", System.currentTimeMillis())
            .put("contentType", progress["contentType"] ?: "single")
            .put("title", host.recoveryTitle)
            .put("seriesTitle", host.recoverySeriesTitle)
            .put("imdbId", host.recoveryImdbId)
            .put("resumeId", progress["resumeId"])
            .put("url", progress["url"])
            .put("itemIndex", progress["itemIndex"] ?: 0)
            .put("season", progress["season"])
            .put("episode", progress["episode"])
            .put("positionMs", positionMs)
            .put("durationMs", durationMs)
            .put("speed", progress["speed"] ?: 1.0)
            .put("aspect", progress["aspect"] ?: "contain")
            .put("completed", progress["completed"] == true)
            .put("completionReached", progress["completionReached"] == true)
            .put("localCompleted", progress["localCompleted"] == true)
            .put("localCompletionEligible", progress["localCompletionEligible"] == true)
            // localCompleted is edge-triggered and eligibility can become
            // false after a seek. This per-item cumulative bit preserves the
            // completion decision across every later checkpoint.
            .put("localCompletionReached", progress["localCompletionReached"] == true)
            .put("localCompletionTracking", progress["localCompletionTracking"] == true)
            .put("completionThreshold", progress["completionThreshold"] ?: 80)
            .toString()

        if (synchronous || progress["completed"] == true || progress["localCompleted"] == true) {
            TvPlaybackRecoveryStore.stage(activity.filesDir, snapshot)
            return
        }
        TvPlaybackRecoveryStore.stageAsync(activity.filesDir, snapshot)
    }

    private fun acknowledgeRecoveryCheckpoint(sequence: Long) {
        TvPlaybackRecoveryStore.acknowledgeAsync(activity.filesDir, host.sourcePersistenceSessionId, sequence)
    }

    fun sendProgress(completed: Boolean) {
        // IPTV mode builds no payload (initIptvMode returns before it is
        // parsed), so it reports against the current channel instead.
        if (host.isIptvMode) {
            sendIptvProgress(completed)
            return
        }
        // Failure closes the startup cursor before activity teardown reports
        // its final checkpoint. A rejected channel must stay untracked.
        if (host.isStremioTvMode && host.startupSourcesExhausted) return
        // READY and isPlaying may arrive before the video renderer produces a
        // frame. Do not persist/scrobble a candidate the startup gate has not
        // committed.
        if (host.startupFailoverCursor?.committed == false ||
            host.manualSourceSwitchSnapshot != null ||
            host.manualSourceRestoreInProgress
        ) return
        val model = host.payload ?: return
        val item = model.items.getOrNull(host.currentIndex) ?: return
        // Use the largest stable duration seen — ExoPlayer can briefly report a
        // short duration right after a source re-prepare, which would otherwise
        // inflate progress% and scrobble a false watch on Trakt.
        val duration = maxOf(host.player?.duration ?: 0L, host.maxStableDurationMs)
        val rawPosition = if (completed) duration else host.player?.currentPosition ?: 0
        // Resume hold: while the chosen resume target has not landed (dropped
        // by the anti-yank, or clamped away by the stream), report the TARGET
        // instead of the live position — otherwise this ping would overwrite
        // the very bookmark the resume promised, in the local store and on
        // every connected tracker alike. Completion below stays on the RAW
        // position: a held target must never fabricate a watched mark.
        val position = if (completed) rawPosition
            else host.heldResumePositionMs(rawPosition) ?: rawPosition
        val completionThreshold = if (model.contentType == "series") {
            model.episodeCompletionThreshold
        } else {
            model.movieCompletionThreshold
        }
        val completionKey = if (
            model.contentType == "series" && item.season != null && item.episode != null
        ) {
            "series:${item.season}:${item.episode}"
        } else {
            "index:${host.currentIndex}"
        }
        val localCompletionEligible =
            model.localCompletionTracking &&
            duration > 0L &&
            rawPosition > 0L &&
            rawPosition.toDouble() * 100.0 / duration.toDouble() >= completionThreshold
        val localCompleted = localCompletionEligible && locallyCompletedItemKeys.add(completionKey)
        val localCompletionReached = locallyCompletedItemKeys.contains(completionKey)
        if (completed) recoveryCompletedItemKeys.add(completionKey)
        val completionReached = recoveryCompletedItemKeys.contains(completionKey)

        // Update the item's progress in the payload for live UI updates
        val updatedItem = item.copy(
            resumePositionMs = position,
            durationMs = duration
        )
        model.items[host.currentIndex] = updatedItem

        // Notify playlist adapter to update progress display (if playlist is visible)
        if (host.playlistVisible) {
            host.playlistAdapter?.updateCurrentProgress()
        }

        val map = hashMapOf<String, Any?>(
            "contentType" to model.contentType,
            "itemIndex" to host.currentIndex,
            "resumeId" to item.resumeId,
            "sourceIndex" to host.currentStremioSourceIndex,
            "positionMs" to position.toInt().coerceAtLeast(0),
            "durationMs" to duration.toInt().coerceAtLeast(0),
            "season" to item.season,
            "episode" to item.episode,
            "speed" to host.playbackSpeeds[host.playbackSpeedIndex].toDouble(),
            "aspect" to host.resizeModeLabels[host.resizeModeIndex].lowercase(),
            "completed" to completed,
            "completionReached" to completionReached,
            "localCompleted" to localCompleted,
            "localCompletionEligible" to localCompletionEligible,
            "localCompletionReached" to localCompletionReached,
            "localCompletionTracking" to model.localCompletionTracking,
            "completionThreshold" to completionThreshold,
            "url" to item.url,
            "isPlaying" to (host.player?.isPlaying ?: false),
            "isBuffering" to (host.player?.playbackState == Player.STATE_BUFFERING)
        )

        deliverProgress(map)
    }

    /**
     * Report position for the IPTV channel currently playing, so Flutter can
     * save a resume point for on-demand items (movies) and draw progress on
     * their rows.
     *
     * Live channels are skipped: ExoPlayer reports TIME_UNSET for them, and a
     * position into a live stream means nothing. That check doubles as the
     * live/VOD filter — the Flutter side stores whatever it receives.
     */
    private fun sendIptvProgress(completed: Boolean) {
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return
        if (entry.isLive) return

        val duration = host.player?.duration ?: 0L
        if (duration <= 0L) return
        val position = if (completed) duration else host.player?.currentPosition ?: 0L
        if (position <= 0L) return

        val map = hashMapOf<String, Any?>(
            "mode" to "iptv",
            "itemIndex" to host.currentIptvIndex,
            "url" to entry.url,
            "title" to entry.name,
            "positionMs" to position.toInt().coerceAtLeast(0),
            "durationMs" to duration.toInt().coerceAtLeast(0),
            "speed" to host.playbackSpeeds[host.playbackSpeedIndex].toDouble(),
            "aspect" to host.resizeModeLabels[host.resizeModeIndex].lowercase(),
            "completed" to completed,
            "isPlaying" to (host.player?.isPlaying ?: false),
        )

        deliverProgress(map)
    }

    fun sendPlaybackMaintenanceState() {
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "torrentPlaybackMaintenanceState",
            mapOf(
                "sourcePersistenceSessionId" to host.sourcePersistenceSessionId,
                "ready" to (host.player?.isPlaying == true && host.player?.playbackState == Player.STATE_READY),
            ),
        )
    }

    fun sendPlaybackActivityState(active: Boolean) {
        try {
            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "torrentPlaybackActivityState",
                mapOf("sourcePersistenceSessionId" to host.sourcePersistenceSessionId, "active" to active),
            )
            if (active) sendPlaybackMaintenanceState()
        } catch (error: RuntimeException) {
            DiagnosticFileLog.recordError(
                source = "android_tv_player", event = "activity_state_delivery_failed", throwable = error,
            )
        }
    }
}
