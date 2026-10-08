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
internal class TvIptvChannelStartController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val currentIptvIndex: Int
        var currentIptvStreamUrl: String?
        var currentStremioSourceIndex: Int
        fun dropStaleSourceSwitchFeedback(): Unit
        val iptvBrowseHandler: Handler
        val iptvChannels: MutableList<IptvChannelEntry>
        val iptvRecordingActionsController: TvIptvRecordingActionsController
        val iptvSourceId: String?
        val iptvTwinPreferredUrls: MutableMap<String, String>
        val isIptvMode: Boolean
        val player: ExoPlayer?
        val progressHandler: Handler
        fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String): Unit
        fun setupStremioSources(): Unit
        val sourceBrowser: TvSourceBrowserController?
        val stremioSourceBadge: View?
        val stremioSources: MutableList<StremioSource>
        val subtitleTrackReadiness: SubtitleTrackReadiness
        fun updateStremioQualityBadge(): Unit
        fun watchSourceSwitchOutcome(sourceIndex: Int): Unit
    }
    private var iptvWatchRegistrationToken = 0

    // Stremio-addon IPTV channels: their `url` is a stremio-tv:// key, not a
    // stream — Flutter resolves it into an ordered candidate URL list on
    // demand, and playback walks the candidates serially on error until one
    // plays or the list runs out (then the channel goes quiet, like a dead
    // M3U stream). Token guards stale async resolves after a channel switch.
    private var iptvStremioToken = 0
    var iptvStremioChannelKey: String? = null
    private var iptvStremioCandidates: List<IptvStremioCandidate> = emptyList()
    private var iptvStremioCandidateIndex = 0
    var iptvStremioWinnerReported = false
    // Per-candidate stall watchdog: live streams can buffer forever without
    // ever erroring, and the ladder only advances on error — this converts a
    // never-READY candidate into a failure. Cancelled by STATE_READY.
    private var iptvStremioStallRunnable: Runnable? = null

    // ========================================================================
    // Startup-channel memory
    //
    // Remembers the last LIVE channel that actually reached a playing state, so
    // "start on my last channel" re-tunes what was being watched rather than
    // what was launched — zapping is how live IPTV is used.
    //
    // Fire-and-forget, and deliberately NOT on the tune path: the live branch
    // of beginIptvPlaybackAfterWatchRegistration short-circuits precisely so
    // zapping stays instant, and nothing here may reintroduce a round trip in
    // front of playback.
    // ========================================================================

    /// A channel counts once it has been playing for this long. Zapping through
    /// twenty channels supersedes one pending post rather than writing twenty
    /// times, and the write lands while the app is alive — an abrupt force-stop
    /// runs no lifecycle callback, so flush-on-stop alone would lose it.
    private val lastLiveChannelSettleMs = 1_000L

    private var lastLiveChannelArmedUrl: String? = null
    private var lastLiveChannelRunnable: Runnable? = null

    fun noteLiveChannelPlaying() {
        if (!host.isIptvMode) return
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return
        if (!entry.isLive) return
        // Already counting down for this channel — a pause/resume must not
        // restart the settle window.
        if (lastLiveChannelArmedUrl == entry.url && lastLiveChannelRunnable != null) return

        lastLiveChannelRunnable?.let { host.iptvBrowseHandler.removeCallbacks(it) }
        lastLiveChannelArmedUrl = entry.url

        val runnable = Runnable {
            lastLiveChannelRunnable = null
            // Re-read: the user may have zapped on during the settle window,
            // and the channel that settled is the one that counts.
            val current = host.iptvChannels.getOrNull(host.currentIptvIndex)
            if (current == null || !current.isLive || current.url != entry.url) return@Runnable
            if (host.player?.isPlaying != true) return@Runnable
            // sourceId is backfilled from the launch-level id for entries that
            // carried none, so fall back to it here for the same reason.
            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "noteIptvLiveChannel",
                mapOf(
                    "url" to current.url,
                    "name" to current.name,
                    "sourceId" to (current.sourceId ?: host.iptvSourceId),
                    "channelNumber" to current.channelNumber,
                    "group" to current.group,
                    "logoUrl" to current.logoUrl,
                    "httpHeaders" to current.httpHeaders,
                ),
            )
        }
        lastLiveChannelRunnable = runnable
        // Posted to iptvBrowseHandler so onDestroy's removeCallbacksAndMessages
        // already retires it.
        host.iptvBrowseHandler.postDelayed(runnable, lastLiveChannelSettleMs)
    }

    fun beginIptvPlaybackAfterWatchRegistration(entry: IptvChannelEntry) {
        val token = ++iptvWatchRegistrationToken
        if (entry.isLive) {
            beginIptvPlayback(entry)
            return
        }

        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            beginIptvPlayback(entry)
            return
        }

        val delivered = java.util.concurrent.atomic.AtomicBoolean(false)
        fun continuePlayback() {
            if (!delivered.compareAndSet(false, true)) return
            if (token != iptvWatchRegistrationToken) return
            val current = host.iptvChannels.getOrNull(host.currentIptvIndex)
            if (current !== entry && current?.url != entry.url) return
            beginIptvPlayback(entry)
        }

        // A detached Flutter engine can leave MethodChannel callbacks silent.
        // Metadata is best-effort in that case; playback must still proceed.
        host.iptvBrowseHandler.postDelayed({ continuePlayback() }, 2_000)
        channel.invokeMethod(
            "recordIptvWatch",
            mapOf(
                "url" to entry.url,
                "name" to entry.name,
                "logoUrl" to entry.logoUrl,
                "group" to entry.group,
                "sourceId" to entry.sourceId,
                "httpHeaders" to entry.httpHeaders,
                "seriesId" to entry.seriesId,
                "seriesName" to (entry.seriesName ?: entry.group),
                "season" to entry.season,
                "episode" to entry.episode,
                "hasNextEpisode" to entry.hasNextEpisode,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) = continuePlayback()
                override fun error(code: String, message: String?, details: Any?) =
                    continuePlayback()
                override fun notImplemented() = continuePlayback()
            },
        )
    }

    /**
     * Start playback for an IPTV channel. Plain channels play their URL
     * directly; Stremio-addon channels first resolve their candidate stream
     * URLs through the Flutter bridge (cached on the Dart side), then play
     * candidate 0 — [tryNextIptvStremioCandidate] walks the rest on error.
     */
    fun beginIptvPlayback(entry: IptvChannelEntry) {
        // The channel change starts HERE, so the outgoing channel's recording
        // ends here too. Waiting for setIptvMediaItem would strand it whenever
        // a Stremio resolve returns nothing: the row would stay pending while
        // the UI already shows the new channel.
        host.iptvRecordingActionsController.finalizeIptvRecordingIfActive()

        iptvStremioToken++
        val token = iptvStremioToken
        iptvStremioChannelKey = null
        iptvStremioCandidates = emptyList()
        iptvStremioCandidateIndex = 0
        iptvStremioWinnerReported = false
        cancelIptvStremioStallWatchdog()
        clearIptvStremioSources()

        // The outgoing stream's URL must not be attributable from here on: a
        // Stremio zap stops the player and resolves async — stop() does NOT
        // clear playerError, so a stale error delivering mid-resolve would
        // otherwise pass the liveness gate and restart the OLD stream under
        // the new channel's identity. setIptvMediaItem re-sets this.
        host.currentIptvStreamUrl = null

        if (!isStremioIptvUrl(entry.url)) {
            // A channel whose `.m3u8` wedged and whose `.ts` twin proved
            // itself this session starts on the twin directly.
            host.setIptvMediaItem(entry, host.iptvTwinPreferredUrls[entry.url] ?: entry.url)
            return
        }

        // The guide/title/index already committed to this channel — stop the
        // outgoing stream now so a slow (or failed) resolve can't leave the
        // previous channel playing under the new channel's UI state.
        host.player?.stop()

        requestIptvStreamUrls(entry.url, entry.name) { candidates, message ->
            activity.runOnUiThread {
                if (token != iptvStremioToken || activity.isFinishing) return@runOnUiThread
                if (candidates.isEmpty()) {
                    android.util.Log.w("AndroidTvPlayer", "No playable streams for ${entry.name}")
                    Toast.makeText(
                        activity,
                        message ?: "${entry.name} is not playable right now",
                        Toast.LENGTH_LONG,
                    ).show()
                    return@runOnUiThread
                }
                iptvStremioChannelKey = entry.url
                iptvStremioCandidates = candidates
                iptvStremioCandidateIndex = 0
                populateIptvStremioSources()
                host.setIptvMediaItem(entry, candidates[0].url)
                armIptvStremioStallWatchdog()
            }
        }
    }

    /**
     * Mirror the channel's candidate links into the existing Stremio sources
     * panel (as direct streams, 1:1 with [iptvStremioCandidates] so the two
     * index spaces stay interchangeable) — giving live channels the same
     * manual source picker movie playback has.
     */
    private fun populateIptvStremioSources() {
        host.stremioSources.clear()
        iptvStremioCandidates.forEachIndexed { i, c ->
            host.stremioSources.add(
                StremioSource(
                    index = i,
                    name = c.label,
                    infohash = "",
                    directUrl = c.url,
                    streamType = "directUrl",
                    sizeBytes = 0L,
                    seeders = 0,
                    source = null,
                    quality = iptvQualityFromLabel(c.label),
                )
            )
        }
        host.currentStremioSourceIndex = iptvStremioCandidateIndex
        host.setupStremioSources()
    }

    /** Leaving a Stremio channel (or re-resolving one) — retire its source rows. */
    private fun clearIptvStremioSources() {
        if (!host.isIptvMode || host.stremioSources.isEmpty()) return
        host.stremioSources.clear()
        host.currentStremioSourceIndex = 0
        host.stremioSourceBadge?.visibility = View.GONE
    }

    /**
     * Manual pick from the sources panel while a Stremio IPTV channel plays.
     * Keeps the ladder in step (an error after the pick advances from the
     * picked link) and skips the movie path's position seek — meaningless on
     * a live stream.
     */
    fun switchToIptvStremioSource(url: String, sourceIndex: Int) {
        android.util.Log.d("AndroidTvPlayer", "switchToIptvStremioSource: index=$sourceIndex")
        iptvStremioCandidateIndex = sourceIndex
        iptvStremioWinnerReported = false
        host.currentStremioSourceIndex = sourceIndex
        host.updateStremioQualityBadge()
        host.sourceBrowser?.render()
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)
        if (entry != null) {
            host.setIptvMediaItem(entry, url)
        } else {
            host.subtitleTrackReadiness.onMediaReplacement()
            host.player?.setMediaItem(MediaItem.fromUri(url))
            host.player?.prepare()
            host.player?.play()
        }
        armIptvStremioStallWatchdog()
        host.watchSourceSwitchOutcome(sourceIndex)
    }

    /**
     * Advance the serial candidate ladder after a playback error. Returns
     * false when the current playback isn't a Stremio channel (the error
     * isn't ours to handle).
     */
    fun tryNextIptvStremioCandidate(): Boolean {
        val key = iptvStremioChannelKey ?: return false
        val candidates = iptvStremioCandidates
        if (candidates.isEmpty()) return false
        // The ladder owns error messaging from here (silent advance, toast only
        // when every candidate dies) — a manual pick's watcher must not speak.
        host.dropStaleSourceSwitchFeedback()
        val next = iptvStremioCandidateIndex + 1
        if (next >= candidates.size) {
            // Every candidate died: have Flutter forget the stale list so a
            // later attempt re-resolves fresh links, then go quiet. KEEP the
            // key and candidate rows though — the sources panel stays usable
            // as a manual escape hatch (a pick routes back through the live
            // switch; nulling the key here would send it down the movie
            // pipeline, which seeks to a stale live position).
            cancelIptvStremioStallWatchdog()
            reportIptvStreamResult(key, null, false)
            iptvStremioWinnerReported = false
            val name = host.iptvChannels.getOrNull(host.currentIptvIndex)?.name ?: "Channel"
            // Distinct from the "resolve came back empty" toast: links existed
            // but every one died. Point at the escape hatch we kept alive.
            val attempted = candidates.size
            val message = if (attempted == 1)
                "$name: its only source didn't play — pick it in Sources to retry"
            else
                "$name: tried all $attempted sources, none played — pick one in Sources to retry"
            Toast.makeText(activity, message, Toast.LENGTH_LONG).show()
            return true
        }
        iptvStremioCandidateIndex = next
        iptvStremioWinnerReported = false
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return false
        android.util.Log.d(
            "AndroidTvPlayer",
            "IPTV stremio ladder: trying candidate ${next + 1}/${candidates.size} for ${entry.name}"
        )
        // Keep the sources menu's active row in step with the auto-advance.
        if (host.stremioSources.isNotEmpty()) {
            host.currentStremioSourceIndex = next
            host.sourceBrowser?.render()
        }
        host.setIptvMediaItem(entry, candidates[next].url)
        armIptvStremioStallWatchdog()
        return true
    }

    /** See [iptvStremioStallRunnable]. Re-armed per candidate. */
    fun armIptvStremioStallWatchdog() {
        cancelIptvStremioStallWatchdog()
        val token = iptvStremioToken
        val candidateIndex = iptvStremioCandidateIndex
        val runnable = Runnable {
            if (activity.isFinishing || activity.isDestroyed) return@Runnable
            if (token != iptvStremioToken || candidateIndex != iptvStremioCandidateIndex) return@Runnable
            if (iptvStremioWinnerReported || iptvStremioChannelKey == null) return@Runnable
            android.util.Log.w(
                "AndroidTvPlayer",
                "IPTV stremio ladder: candidate ${candidateIndex + 1} never reached READY, advancing"
            )
            tryNextIptvStremioCandidate()
        }
        iptvStremioStallRunnable = runnable
        host.progressHandler.postDelayed(runnable, 20_000)
    }

    private fun cancelIptvStremioStallWatchdog() {
        iptvStremioStallRunnable?.let { host.progressHandler.removeCallbacks(it) }
        iptvStremioStallRunnable = null
    }

    /** First READY on a Stremio candidate — cache the winner on the Dart side. */
    fun reportIptvStremioWinnerIfNeeded() {
        if (iptvStremioWinnerReported) return
        val key = iptvStremioChannelKey ?: return
        val url = iptvStremioCandidates.getOrNull(iptvStremioCandidateIndex)?.url ?: return
        iptvStremioWinnerReported = true
        cancelIptvStremioStallWatchdog()
        reportIptvStreamResult(key, url, true)
    }
}
