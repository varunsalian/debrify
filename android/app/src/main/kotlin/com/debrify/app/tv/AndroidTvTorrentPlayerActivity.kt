package com.debrify.app.tv

import android.animation.ValueAnimator
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.media.MediaCodecList
import android.os.Bundle
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
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
import androidx.media3.exoplayer.audio.DefaultAudioSink
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
class AndroidTvTorrentPlayerActivity : AppCompatActivity() {

    // Views
    private lateinit var playerView: PlayerView
    private lateinit var titleContainer: View
    private lateinit var titleView: TextView
    // OTT-style title views (compact mode when metadata available)
    private lateinit var titleOttContainer: View
    private lateinit var ottEpisodeBadge: TextView
    private lateinit var ottEpisodeTitle: TextView
    private lateinit var ottRatingContainer: View
    private lateinit var ottRating: TextView
    private lateinit var channelBadge: TextView
    private lateinit var subtitleOverlay: SubtitleView
    private lateinit var playlistOverlay: View
    private lateinit var playlistView: RecyclerView
    private lateinit var seasonTabsContainer: android.widget.LinearLayout
    private lateinit var nextOverlay: View
    private lateinit var nextText: TextView
    private lateinit var nextSubtext: TextView

    // Loading/tuning overlay backdrop art
    private lateinit var nextBackdrop: android.widget.ImageView

    // Up Next card (slide-in near end of episode)
    private lateinit var upNextCard: View
    private lateinit var upNextPoster: android.widget.ImageView
    private lateinit var upNextTitle: TextView
    private lateinit var upNextCountdown: TextView
    private lateinit var skipSegmentButton: AppCompatButton
    private var upNextVisible = false
    private var upNextTargetIndex: Int? = null
    private var upNextDismissedForIndex = -1
    private val upNextHandler = Handler(Looper.getMainLooper())
    private val seasonTabs = mutableListOf<android.widget.TextView>()
    private val movieTabs = mutableListOf<MovieTab>()

    // Seekbar
    private lateinit var seekbarOverlay: View
    private lateinit var seekbarProgress: View
    private lateinit var seekbarHandle: View
    private lateinit var seekbarCurrentTime: TextView
    private lateinit var seekbarTotalTime: TextView
    private lateinit var seekbarSpeedIndicator: TextView
    private var seekbarBackgroundWidth: Int = 0
    private var currentSeekSpeed: Float = 1.0f

    // Controls
    private var controlsOverlay: View? = null
    private var pauseButton: AppCompatButton? = null
    private var iptvPrevButton: AppCompatButton? = null
    private var iptvNextButton: AppCompatButton? = null
    private var iptvGuideButton: AppCompatButton? = null
    private var iptvJumpButton: AppCompatButton? = null
    private var iptvRecordButton: AppCompatButton? = null
    // Tees the live progressive stream to a MediaStore file while playing.
    private val iptvRecordingController by lazy { IptvRecordingController(this) }
    private var iptvUpPressActive = false
    private var iptvUpLongPressHandled = false
    private var originalControlDockOrder: List<View> = emptyList()
    private var audioButton: AppCompatButton? = null
    private var subtitleButton: AppCompatButton? = null
    private var aspectButton: AppCompatButton? = null
    private var speedButton: AppCompatButton? = null
    private var nightModeButton: AppCompatButton? = null

    // Time Display in Controls (Cinema Mode - split displays)
    private var debrifyTimeDisplay: TextView? = null  // Legacy combined display (hidden)
    private var debrifyTimeCurrent: TextView? = null  // Current time (left)
    private var debrifyTimeTotal: TextView? = null    // Total time (right)
    private var debrifyProgressLine: View? = null
    private var cinemaProgressBuffered: View? = null

    // Cinema Mode Interactive Progress Bar
    private var cinemaProgressContainer: View? = null
    private var cinemaProgressBackground: View? = null
    private var cinemaProgressThumb: View? = null
    private var cinemaSpeedIndicator: TextView? = null
    private var cinemaProgressTrackWidth: Int = 0
    private var cinemaSeekMode: Boolean = false  // True when actively seeking via progress bar
    private var cinemaProgressAnimator: ValueAnimator? = null
    private var cinemaLastAnimatedProgress: Float = 0f

    // Player
    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var subtitleListener: Player.Listener? = null

    private val decoderAnalyticsListener = object : AnalyticsListener {
        private var inputFormat: Format? = null

        override fun onVideoInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: DecoderReuseEvaluation?,
        ) {
            inputFormat = format
        }

        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializedTimestampMs: Long,
            initializationDurationMs: Long,
        ) {
            val format = player?.videoFormat ?: inputFormat
            val generation = eventTime.mediaPeriodId?.windowSequenceNumber ?: -1L
            Log.i(
                DECODER_LOG_TAG,
                "generation=$generation phase=stable " +
                    "status=${androidDecoderStatus(decoderName)} " +
                    "platform=android_tv backend=media3 " +
                    "codec=${format?.sampleMimeType ?: "unknown"} " +
                    "decoder=$decoderName output=surface_view " +
                    "resolution=${format?.width ?: 0}x${format?.height ?: 0}",
            )
        }
    }

    private fun androidDecoderStatus(decoderName: String): String {
        val normalized = decoderName.lowercase(Locale.US)
        if (
            normalized.contains(".google.") ||
            normalized.contains(".android.") ||
            normalized.startsWith("c2.android") ||
            normalized.startsWith("c2.google") ||
            normalized.contains("ffmpeg")
        ) {
            return "software"
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            val codecInfo = runCatching {
                MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.firstOrNull {
                    it.name.equals(decoderName, ignoreCase = true)
                }
            }.getOrNull()
            if (codecInfo?.isSoftwareOnly == true) return "software"
            if (codecInfo?.isHardwareAccelerated == true) return "hardware"
        }
        return "unknown"
    }
    private var offsetRenderersFactory: OffsetRenderersFactory? = null

    // Phase 0 of the IPTV resilience plan: per-tune logcat diagnostics.
    // Inert for non-IPTV playback (nothing calls onTuneStart there).
    private val iptvTuneDiagnostics = IptvTuneDiagnostics()

    // ── IPTV live recovery (Phases 1/3/5 of the resilience plan) ──────────
    //
    // The ONE owner of live re-tunes. Sources: STATE_ENDED, unclaimed fatal
    // errors, the tune watchdog, the stall detector, lifecycle rejoin, and
    // the user's play press on a dead stream. See IptvLiveRecovery.kt.

    /** True while a machine-driven re-tune is inside setIptvMediaItem, so
     *  onTuneStarted keeps the recovery episode instead of resetting it. */
    private var iptvLiveRetuneInFlight = false

    /** Wall time we left the foreground; a live channel resumed after more
     *  than [IPTV_LIVE_REJOIN_AFTER_MS] away re-tunes to the live edge
     *  instead of resuming a stale (possibly dead) connection. */
    private var iptvStoppedAtRealtime = 0L

    private val IPTV_LIVE_REJOIN_AFTER_MS = 30_000L

    private var iptvNetworkCallback: ConnectivityManager.NetworkCallback? = null

    /** Bottom-center "Reconnecting…" pill; created on first use, lives in
     *  the decor content view so it floats over every player surface. */
    private var iptvReconnectPill: TextView? = null

    private val iptvLiveRecovery: IptvLiveRecovery by lazy {
        IptvLiveRecovery(
            Handler(Looper.getMainLooper()),
            object : IptvLiveRecovery.Callbacks {
                override fun isEligible(): Boolean = iptvLiveRecoveryEligible()

                override fun performRetune(source: String, attempt: Int) {
                    performIptvLiveRetune(source, attempt)
                }

                override fun onEpisodeVisible(attempt: Int) {
                    showIptvReconnectPill("Reconnecting…")
                }

                override fun onRecovered() {
                    hideIptvReconnectPill()
                    // Re-arm the zap frame-hold a surrender may have cleared.
                    if (isIptvMode) playerView.setKeepContentOnPlayerReset(true)
                }

                override fun onSurrender(source: String) {
                    iptvTuneDiagnostics.onRecovery(source, "surrender")
                    // The held last frame must not keep painting a dead
                    // channel under the failure pill (plan invariant T11).
                    playerView.setKeepContentOnPlayerReset(false)
                    showIptvReconnectPill(
                        if (source == "auth") {
                            "Stream refused (expired or blocked) — press play to retry"
                        } else {
                            "Stream lost — press play to retry"
                        }
                    )
                }
            },
        )
    }

    /** The machine may act only on a LIVE entry with nothing else in charge:
     *  the Stremio candidate ladder owns recovery until its winner plays,
     *  sleep stops outrank reconnects, and a user pause (playWhenReady
     *  false — onStop pauses too) means nobody asked for playback. */
    private fun iptvLiveRecoveryEligible(): Boolean {
        if (!isIptvMode || isFinishing || isDestroyed) return false
        val entry = iptvChannels.getOrNull(currentIptvIndex) ?: return false
        if (!entry.isLive) return false
        if (sleepStopLatched || sleepTimerMode == SleepTimerMode.END_OF_ITEM) return false
        if (iptvStremioChannelKey != null && !iptvStremioWinnerReported) return false
        if (player?.playWhenReady != true) return false
        return true
    }

    /** Re-tune the current live channel with its full identity — the SAME
     *  resolved URL and per-channel headers (already in
     *  currentIptvHttpHeaders; setIptvMediaItem re-stamps both). A fresh
     *  prepare joins the live edge, never a stale position. */
    private fun performIptvLiveRetune(source: String, attempt: Int) {
        val entry = iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive } ?: return
        val url = currentIptvStreamUrl ?: entry.url
        iptvTuneDiagnostics.onRecovery(source, "retune", "attempt=$attempt")
        // Video-stall attempt 1 was a plain re-tune (transient wedges heal
        // on a codec reset). Still frozen: drop the aggressive TS join flags
        // for this channel before going again — mid-GOP joins are exactly
        // what strict MediaTek decoders wedge on (frozen video, running
        // audio; the Google TV Streamer report). setIptvMediaItem below
        // recomputes iptvStrictTsActive from the set. Segmented/HLS streams
        // never see the progressive extractor factory, so a stall there says
        // nothing about the flags — recording one would only poison the
        // two-URLs-means-strict-device session escalation. Same for a tune
        // that was ALREADY strict (a twin — strict from birth — or a
        // session-strict device): its wedge was observed with the aggressive
        // flags off, so it is not evidence about them; without this gate two
        // failed twin trials would flip the whole session strict.
        if (source == "video-stall" && attempt >= 2 &&
            !isCurrentIptvSegmented() && !iptvStrictTsActive &&
            iptvStrictTsUrls.add(url)
        ) {
            iptvTuneDiagnostics.onRecovery(source, "strict-ts")
        }
        // Segmented streams have no strict rung — but an Xtream `.m3u8` has a
        // progressive `.ts` twin that does. Divert the strict-rung re-tune
        // into a reversible twin trial (see the twin-trial fields for the
        // full story). Only ever from an objectively detected video stall;
        // no twin / already failed / twin known HLS-forced falls through to
        // the plain re-tune below, exactly as before.
        if (source == "video-stall" && attempt >= 2 && isCurrentIptvSegmented() &&
            iptvTwinTrialOriginalUrl == null && !iptvTwinFailedUrls.contains(url)
        ) {
            val twin = xtreamTsTwin(url)
            if (twin != null && !iptvHlsForcedUrls.contains(twin)) {
                beginIptvTwinTrial(entry, url, twin)
                return
            }
        }
        // A same-URL reopen would append a fresh TS connection — reset
        // PCR/PTS, no discontinuity marker — into the active tee file, and
        // setIptvMediaItem's finalize only fires on URL CHANGE. Finalize
        // here instead: the recorded portion stays a valid file; the
        // recovered stream simply isn't recorded further (plan invariant,
        // codex round 2 finding 7).
        if (iptvRecordingController.isActive) {
            finalizeIptvRecordingIfActive()
            updateRecordButtonState()
        }
        iptvLiveRetuneInFlight = true
        try {
            setIptvMediaItem(entry, url)
        } finally {
            iptvLiveRetuneInFlight = false
        }
    }

    /** Start the reversible twin trial: tune the `.ts` twin under the
     *  machine's episode (expectRetune keeps ladder state) with a verdict
     *  deadline armed. A sustained advancing-frames streak accepts
     *  ([judgeIptvTwinTrial]); an error on the twin or the deadline →
     *  [failIptvTwinTrial]. */
    private fun beginIptvTwinTrial(entry: IptvChannelEntry, original: String, twin: String) {
        iptvTuneDiagnostics.onRecovery("video-stall", "twin-ts", "trial")
        iptvTwinTrialOriginalUrl = original
        iptvTwinTrialUrl = twin
        iptvTwinTrialLastFrames = -1
        iptvTwinTrialAdvanceSince = 0L
        iptvTwinTrialStartedRealtime = SystemClock.elapsedRealtime()
        scheduleIptvTwinTrialTimeout(IPTV_TWIN_TRIAL_TIMEOUT_MS)
        iptvLiveRetuneInFlight = true
        try {
            setIptvMediaItem(entry, twin)
        } finally {
            iptvLiveRetuneInFlight = false
        }
    }

    /** The trial's verdict, fed the rendered-frame counter by the 5s
     *  progress ticker. First valid sample is a baseline; every later
     *  sample must ADVANCE to keep the acceptance streak alive — a frozen
     *  sample (or a counter reset, i.e. a decoder swap from an interleaved
     *  machine re-tune) re-baselines and the streak starts over. Only a
     *  streak of [IPTV_TWIN_TRIAL_STABLE_MS] accepts; anything short of
     *  that leaves the verdict to the error path or the deadline. */
    private fun judgeIptvTwinTrial(frames: Int) {
        val twin = iptvTwinTrialUrl ?: return
        if (currentIptvStreamUrl != twin || frames < 0) return
        if (frames <= iptvTwinTrialLastFrames || iptvTwinTrialLastFrames < 0) {
            // Baseline, stalled, or reset: no streak to speak of.
            iptvTwinTrialLastFrames = frames
            iptvTwinTrialAdvanceSince = 0L
            return
        }
        iptvTwinTrialLastFrames = frames
        val now = SystemClock.elapsedRealtime()
        if (iptvTwinTrialAdvanceSince == 0L) {
            iptvTwinTrialAdvanceSince = now
            return
        }
        if (now - iptvTwinTrialAdvanceSince >= IPTV_TWIN_TRIAL_STABLE_MS) {
            acceptIptvTwinTrial()
        }
    }

    /** Frames advanced continuously for the stability window: keep the twin
     *  for the session. The original→twin preference applies at zap time,
     *  and the preferred twin keeps strict demux (both via the maps'
     *  readers) — nothing is enrolled in [iptvStrictTsUrls], whose
     *  two-URLs-means-strict-DEVICE escalation must only count wedges
     *  observed under the aggressive flags, which the twin (strict from
     *  birth) never was. */
    private fun acceptIptvTwinTrial() {
        val original = iptvTwinTrialOriginalUrl ?: return
        val twin = iptvTwinTrialUrl ?: return
        if (currentIptvStreamUrl != twin) return
        clearIptvTwinTrial()
        iptvTwinPreferredUrls[original] = twin
        iptvTuneDiagnostics.onRecovery("video-stall", "twin-ts", "accepted")
    }

    /** The twin errored or never rendered: blacklist it for the session and
     *  restore the original HLS stream under the machine's episode. The
     *  machine handles what follows on its own — the restored stream's
     *  frozen video recurs, the twin rung is now closed, and the recurrence
     *  ladder latches: audio plays on, today's end state, never worse. */
    private fun failIptvTwinTrial(reason: String) {
        val original = iptvTwinTrialOriginalUrl ?: return
        val twin = iptvTwinTrialUrl
        clearIptvTwinTrial()
        // A zap/teardown superseded the trial: nothing to restore, and the
        // twin was never judged — don't blacklist it on an interruption.
        if (twin == null || currentIptvStreamUrl != twin) return
        if (isFinishing || isDestroyed) return
        iptvTwinFailedUrls.add(original)
        iptvTuneDiagnostics.onRecovery("video-stall", "twin-ts", "failed:$reason")
        val entry = iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive } ?: return
        iptvLiveRetuneInFlight = true
        try {
            setIptvMediaItem(entry, original)
        } finally {
            iptvLiveRetuneInFlight = false
        }
    }

    /** A verdict timeout is recovery too, so it must respect explicit pause
     *  just like [IptvLiveRecovery]. Park the original instead of calling
     *  setIptvMediaItem (which deliberately starts playback); the next
     *  explicit Play or foreground resume consumes the parked restore. */
    private fun onIptvTwinTrialTimeout() {
        if (player?.playWhenReady != true || sleepStopLatched) {
            parkIptvTwinTrialRestore()
            return
        }
        failIptvTwinTrial("timeout")
    }

    private fun scheduleIptvTwinTrialTimeout(delayMs: Long) {
        iptvTwinTrialTimeout?.let { iptvTwinTrialHandler.removeCallbacks(it) }
        val timeout = Runnable { onIptvTwinTrialTimeout() }
        iptvTwinTrialTimeout = timeout
        iptvTwinTrialHandler.postDelayed(timeout, delayMs.coerceAtLeast(0L))
    }

    /** Each READY on the twin restarts the verdict deadline at the
     *  post-READY bound: the proof (baseline sample + advancing streak) can
     *  only begin once rendering can, so prepare time — including an
     *  interleaved tune-watchdog re-tune's — must not be charged against
     *  the streak. Without this, a twin READY around the 20s watchdog
     *  boundary would be killed by the trial-start deadline one sample
     *  short of acceptance. */
    private fun rearmIptvTwinTrialDeadline() {
        val twin = iptvTwinTrialUrl ?: return
        if (currentIptvStreamUrl != twin) return
        val started = iptvTwinTrialStartedRealtime
        if (started == 0L) return
        val absoluteRemaining =
            started + IPTV_TWIN_TRIAL_MAX_MS - SystemClock.elapsedRealtime()
        scheduleIptvTwinTrialTimeout(
            minOf(IPTV_TWIN_TRIAL_POST_READY_MS, absoluteRemaining)
        )
    }

    /** Suspend an unjudged twin without changing the paused player's media
     *  item. The pair is essential: a same-twin retry must preserve the
     *  rollback, while a tune anywhere else invalidates it. */
    private fun parkIptvTwinTrialRestore(): Boolean {
        val original = iptvTwinTrialOriginalUrl ?: return false
        val twin = iptvTwinTrialUrl ?: return false
        if (currentIptvStreamUrl != twin) return false
        iptvTwinTrialRestoreOriginal = original
        iptvTwinTrialRestoreTwin = twin
        clearIptvTwinTrial()
        return true
    }

    /** Restore a trial parked by pause/onStop. Used by both lifecycle resume
     *  and the explicit Play button because Play need not cause onStart. */
    private fun restoreParkedIptvTwinIfNeeded(): Boolean {
        val original = iptvTwinTrialRestoreOriginal ?: return false
        val twin = iptvTwinTrialRestoreTwin
        clearParkedIptvTwinRestore()
        if (twin == null || currentIptvStreamUrl != twin) return false
        val entry = iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive }
            ?: return false
        setIptvMediaItem(entry, original)
        return true
    }

    private fun clearParkedIptvTwinRestore() {
        iptvTwinTrialRestoreOriginal = null
        iptvTwinTrialRestoreTwin = null
    }

    /** Disarm the trial without a verdict. Safe to call at any time; every
     *  tune to a non-twin URL and both recovery-cancel sites go through
     *  here, so a stale timeout can never restore an old channel's URL —
     *  or restart playback from the background. */
    private fun clearIptvTwinTrial() {
        iptvTwinTrialTimeout?.let { iptvTwinTrialHandler.removeCallbacks(it) }
        iptvTwinTrialTimeout = null
        iptvTwinTrialOriginalUrl = null
        iptvTwinTrialUrl = null
        iptvTwinTrialLastFrames = -1
        iptvTwinTrialAdvanceSince = 0L
        iptvTwinTrialStartedRealtime = 0L
    }

    /** An accepted twin is still speculative provider infrastructure. If it
     *  later becomes deterministically unavailable, revoke the preference
     *  and give the original HLS endpoint one chance before AUTH surrender. */
    private fun restoreAcceptedIptvTwinAfterAuth(error: PlaybackException): Boolean {
        if (classifyIptvError(error) != IptvLiveRecovery.ErrorClass.AUTH) return false
        val twin = currentIptvStreamUrl ?: return false
        val preferred = iptvTwinPreferredUrls.entries.firstOrNull { it.value == twin }
            ?: return false
        val original = preferred.key
        val entry = iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive }
            ?: return false
        iptvTwinPreferredUrls.remove(original)
        iptvTwinFailedUrls.add(original)
        iptvTuneDiagnostics.onRecovery("auth", "twin-ts", "revoked")
        iptvLiveRetuneInFlight = true
        try {
            setIptvMediaItem(entry, original)
        } finally {
            iptvLiveRetuneInFlight = false
        }
        return true
    }

    /** 401/403/404 repeat deterministically; decoder failures repeat unless
     *  the hiccup was transient; everything else gets the full ladder. */
    private fun classifyIptvError(error: PlaybackException): IptvLiveRecovery.ErrorClass {
        val http = generateSequence<Throwable>(error) { it.cause }
            .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
            .firstOrNull()?.responseCode
        if (http == 401 || http == 403 || http == 404) {
            return IptvLiveRecovery.ErrorClass.AUTH
        }
        return when (error.errorCode) {
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED ->
                IptvLiveRecovery.ErrorClass.DECODER
            else -> IptvLiveRecovery.ErrorClass.TRANSIENT
        }
    }

    /** Phase 1, Layer 1: loader-level retry policy for live IPTV. Retries
     *  happen UNDER an intact buffer — the player never leaves READY, so a
     *  drop the origin repairs within the buffered lead is invisible.
     *  Classified per the plan: 401/403/404 are deterministic (no retry —
     *  escalate to the fatal-error path, where the machine surrenders or
     *  re-resolves), 429/503 honor Retry-After, other transport errors get
     *  a short flat delay and a generous (bounded) retry count. Non-live
     *  entries keep media3 defaults untouched. */
    private inner class IptvLiveLoadErrorPolicy : DefaultLoadErrorHandlingPolicy() {
        private fun liveNow(): Boolean =
            iptvChannels.getOrNull(currentIptvIndex)?.isLive == true

        override fun getRetryDelayMsFor(
            loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo,
        ): Long {
            if (!liveNow()) return super.getRetryDelayMsFor(loadErrorInfo)
            val http = generateSequence(loadErrorInfo.exception as Throwable?) { it.cause }
                .filterIsInstance<HttpDataSource.InvalidResponseCodeException>()
                .firstOrNull()
            when (http?.responseCode) {
                401, 403, 404 -> return C.TIME_UNSET // fatal: same answer every time
                429, 503 -> {
                    // Bound the TIME this class can hide a failure, not just
                    // the count: minimumLoadableRetryCount is a floor, and a
                    // 5s-per-retry rate limit would otherwise sit invisible
                    // (no pill — the player never errors) for minutes before
                    // the machine's ladder even starts (codex r2, finding 9).
                    if (loadErrorInfo.errorCount > 4) return C.TIME_UNSET
                    val retryAfterSec = http.headerFields.entries
                        .firstOrNull { it.key.equals("Retry-After", ignoreCase = true) }
                        ?.value?.firstOrNull()?.trim()?.toLongOrNull()
                    return (retryAfterSec?.times(1000))?.coerceIn(1_000L, 15_000L)
                        ?: 5_000L
                }
            }
            return if (loadErrorInfo.exception is HttpDataSource.HttpDataSourceException) {
                // ~15s of 1s in-buffer retries, then escalate to the machine.
                if (loadErrorInfo.errorCount > 15) C.TIME_UNSET else 1_000L
            } else {
                super.getRetryDelayMsFor(loadErrorInfo)
            }
        }

        // A floor, not a cap — the real bound is the TIME_UNSET escalation
        // by errorCount in getRetryDelayMsFor above. Kept above the default
        // so transport errors actually reach the 15×1s schedule.
        override fun getMinimumLoadableRetryCount(dataType: Int): Int =
            if (liveNow()) 20 else super.getMinimumLoadableRetryCount(dataType)
    }

    private fun showIptvReconnectPill(text: String) {
        val pill = iptvReconnectPill ?: TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dpToPx(20), dpToPx(10), dpToPx(20), dpToPx(10))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#CC101418"))
                cornerRadius = dpToPx(22).toFloat()
            }
            val params = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dpToPx(56)
            }
            // addContentView reaches the decor content FrameLayout, which
            // exists whatever the activity's own root layout is.
            addContentView(this, params)
            iptvReconnectPill = this
        }
        pill.text = text
        pill.visibility = View.VISIBLE
    }

    private fun hideIptvReconnectPill() {
        iptvReconnectPill?.visibility = View.GONE
    }

    private fun dpToPx(dp: Int): Int =
        (dp * resources.displayMetrics.density).toInt()

    private val iptvDiagAnalyticsListener = object : AnalyticsListener {
        override fun onRenderedFirstFrame(
            eventTime: AnalyticsListener.EventTime,
            output: Any,
            renderTimeMs: Long,
        ) {
            iptvTuneDiagnostics.onFirstFrame()
        }

        override fun onLoadCompleted(
            eventTime: AnalyticsListener.EventTime,
            loadEventInfo: androidx.media3.exoplayer.source.LoadEventInfo,
            mediaLoadData: androidx.media3.exoplayer.source.MediaLoadData,
        ) {
            iptvTuneDiagnostics.onBytesLoaded(loadEventInfo.bytesLoaded)
        }
    }

    // Subtitle auto-sync: taps the decoded PCM (created with the player, in
    // setupPlayer) so the aligner has audio history the moment it's asked.
    private var speechTap: SpeechFeatureTap? = null
    private var autoSyncRunning = false

    // Seek feedback manager
    private lateinit var seekFeedbackManager: SeekFeedbackManager

    // State
    private var payload: PlaybackPayload? = null
    private var currentIndex = 0
    private var pendingSeekMs: Long = 0
    private var percentSeekApplied = false
    // Per-item Trakt resume (0-100) for the item currently loading, applied on
    // STATE_READY when it has no local resume — lets ANY switched-to episode
    // resume from Trakt, not just the launched one (which uses the payload-level
    // percent + percentSeekApplied latch). Local resume always wins.
    private var pendingItemTraktPercent: Double = 0.0
    // Set right before an auto-advance / skip / shuffle playItem so that path
    // starts the next episode fresh (no Trakt resume), matching the Flutter
    // player's _isAutoAdvancing behavior. Consumed at the top of playItem.
    private var isAutoAdvancing = false
    private var controlsMenuVisible = false
    private var playlistVisible = false
    private var seekbarVisible = false
    private var seekbarPosition: Long = 0
    private var videoDuration: Long = 0
    private var resizeModeIndex = 1  // Fill by default
    private var playbackSpeedIndex = 2  // 1.0x
    private var nightModeIndex = 0  // Off by default
    private var loudnessEnhancer: LoudnessEnhancer? = null

    /** Opt-in (Settings → Player Settings): announce our audio session so system
     *  effect apps (Wavelet, OEM equalizers) can attach. Off by default. */
    private var systemAudioEffectsEnabled = false
    private var skipSegmentsEnabled = true
    private var skipSegmentProviderId = TvSkipSegmentClients.AUTO
    private var playlistMode: PlaylistMode = PlaylistMode.NONE
    private var playlistAdapter: PlaylistOverlayAdapter? = null
    private var seriesPlaylistAdapter: PlaylistAdapter? = null
    private var moviePlaylistAdapter: MoviePlaylistAdapter? = null
    private var movieGroups: MovieGroups? = null
    private var continuousShuffleEnabled = false
    private val shuffleBag = mutableListOf<Int>()
    private var lastBackPressTime: Long = 0

    // IPTV mode state
    private var isIptvMode = false
    private var iptvChannels = mutableListOf<IptvChannelEntry>()
    private var currentIptvIndex = 0

    // Xtream series audio memory: the `<playlistId>::<seriesId>` key the Flutter
    // store uses, and the language resolved from it at launch. A native audio
    // pick updates the TrackSelector's preferred language (so it carries to the
    // next episode) and rounds back to Flutter to persist. Null unless this
    // IPTV session is an Xtream series.
    private var iptvSeriesAudioKey: String? = null
    private var iptvPreferredAudioLang: String? = null

    // Per-channel HTTP headers for the CURRENT channel, injected into every
    // player request by the IPTV resolver installed in setupPlayer. Written
    // on the main thread in setIptvMediaItem, read on ExoPlayer's loader
    // threads — hence @Volatile.
    @Volatile
    private var currentIptvHttpHeaders: Map<String, String> = emptyMap()

    // URLs that failed extractor sniffing and play as HLS instead (bare
    // extension-less URLs — jmp2.uk-style — infer as progressive). Session
    // memory so zapping back starts straight in HLS with no failed attempt.
    private val iptvHlsForcedUrls = HashSet<String>()

    /** Channels whose video wedged twice under the aggressive TS join flags
     *  (see the IPTV media-source factory in setupPlayer): their re-tunes
     *  and later visits demux strictly — IDR-only sync points, spec AU
     *  boundaries — the way the browse screen's stock preview player does.
     *  Session-scoped, like [iptvHlsForcedUrls]. Two distinct URLs earning
     *  a place means the DEVICE is the strict one (MediaTek boxes refusing
     *  mid-GOP joins), so from there every tune goes strict. */
    private val iptvStrictTsUrls = HashSet<String>()

    /** The factory's per-tune switch: written on main before each prepare
     *  (setIptvMediaItem), read on the extractor's loader thread. */
    @Volatile private var iptvStrictTsActive = false

    // ── Xtream HLS→TS twin trial ─────────────────────────────────────────
    // Segmented streams never see the strict-demux remedy (they bypass the
    // progressive extractor factory), so an Xtream `.m3u8` channel whose
    // video wedges has nowhere to escalate — the ladder plain-re-tunes and
    // latches with frozen video under running audio. But Xtream panels serve
    // the SAME channel as one progressive `.ts` stream (xtreamTsTwin), which
    // IS reachable by the demux path the browse preview proves works on
    // strict decoders. So: at the video-stall strict rung on a segmented
    // URL, trial the twin — reversibly. Frames rendering accepts it for the
    // session; an error or a no-frames timeout restores the original HLS URL
    // and blacklists the twin so the channel can't ping-pong. All state is
    // session-scoped, like [iptvHlsForcedUrls].

    /** Original `.m3u8` URL while its `.ts` twin is on trial; null = idle. */
    private var iptvTwinTrialOriginalUrl: String? = null

    /** The twin URL under trial. Its tune runs strict demux from the first
     *  attempt: the stall already proved this device+channel wedges, and the
     *  twin exists precisely to reach the demux mode that works — joining it
     *  mid-GOP under the aggressive flags would recreate the wedge and doom
     *  the trial. Read on main only (setIptvMediaItem computes the volatile
     *  [iptvStrictTsActive] from it before prepare). */
    private var iptvTwinTrialUrl: String? = null

    /** Originals whose twin trial failed this session — never re-trialed. */
    private val iptvTwinFailedUrls = HashSet<String>()

    /** Accepted trials, original → twin: later zaps to the channel start on
     *  the twin directly (still strict — see [iptvStrictTsActive]'s
     *  computation), instead of wedging on HLS and re-earning it. */
    private val iptvTwinPreferredUrls = HashMap<String, String>()

    private var iptvTwinTrialTimeout: Runnable? = null
    private val iptvTwinTrialHandler = Handler(Looper.getMainLooper())

    /** Set by onStop when it abandons an UNJUDGED trial: the original HLS
     *  URL onStart must re-tune to. Bookkeeping alone can't express this —
     *  while backgrounded the player still holds the twin media item, and
     *  lying about the identity would misroute error attribution, recording
     *  eligibility and diagnostics on a quick resume. Consumed (and the
     *  actual media item restored) at the top of onStart. */
    private var iptvTwinTrialRestoreOriginal: String? = null

    /** Twin paired with [iptvTwinTrialRestoreOriginal]. Same-twin recovery
     *  keeps the parked rollback alive; any different tune discards it. */
    private var iptvTwinTrialRestoreTwin: String? = null

    /** Verdict sampling state, fed by the 5s progress ticker
     *  (judgeIptvTwinTrial): last rendered-frame count seen on the twin, and
     *  when its current uninterrupted advancing streak began (0 = none). */
    private var iptvTwinTrialLastFrames = -1
    private var iptvTwinTrialAdvanceSince = 0L
    private var iptvTwinTrialStartedRealtime = 0L

    /** Acceptance = frames advancing on EVERY 5s sample for this long —
     *  the machine's own STABLE_MS idiom. One frame over baseline is not a
     *  verdict: a twin that renders a moment and wedges must fail, not get
     *  remembered as the channel's preferred URL. */
    private val IPTV_TWIN_TRIAL_STABLE_MS = 15_000L

    /** Verdict deadline from trial start — the PRE-READY bound: a twin that
     *  can't even reach READY inside this (the machine's 20s watchdog gets
     *  one same-URL re-tune in between) fails and HLS is restored. Every
     *  READY on the twin re-arms the deadline to the post-READY bound below,
     *  so prepare time is never charged against the proof itself. */
    private val IPTV_TWIN_TRIAL_TIMEOUT_MS = 40_000L

    /** Verdict deadline from (each) READY: a baseline sample (≤5s) + the
     *  15s advancing streak + sampling jitter. Re-armed per READY, so a
     *  mid-trial machine re-tune restarts the proof rather than inheriting
     *  a clock its prepare already spent; the machine's own strict/latch
     *  budgets bound how often that can happen. */
    private val IPTV_TWIN_TRIAL_POST_READY_MS = 30_000L

    /** Hard ceiling across every READY/rebuffer cycle. A pathological twin
     *  cannot renew its post-READY deadline forever. */
    private val IPTV_TWIN_TRIAL_MAX_MS = 90_000L

    private var currentIptvStreamUrl: String? = null
    private var iptvGuideOverlay: View? = null
    private var iptvGuideList: RecyclerView? = null
    private var iptvGuideSearch: android.widget.EditText? = null
    private var iptvGuideTitle: TextView? = null
    private var iptvGuideCountText: TextView? = null
    private var iptvSourceButton: AppCompatButton? = null
    private var iptvCategoryButton: AppCompatButton? = null
    private var iptvBrowseLoading: View? = null
    private var iptvGuideCurrentName: TextView? = null
    private var iptvGuideCurrentGroup: TextView? = null
    private var iptvGuideCurrentEpg: TextView? = null
    private var iptvGuideNowPlaying: View? = null
    private var iptvGuideNowLogo: android.widget.ImageView? = null
    private var iptvGuideNowLetter: TextView? = null
    private var iptvChannelAdapter: IptvChannelAdapter? = null
    private var iptvGuideVisible = false
    private var iptvBrowseChannels = mutableListOf<IptvChannelEntry>()
    private var iptvSources = mutableListOf<IptvSourceEntry>()

    // The user's channel lists, shipped once at launch (never per channel —
    // the channel payload is already capped for size on the Dart side).
    private var iptvLists = mutableListOf<IptvListEntry>()
    private var iptvCategories = mutableListOf<String>()
    private var iptvSourceId: String? = null
    private var iptvSourceName: String = "IPTV"
    private var iptvContentType: String = "live"
    private var iptvSelectedCategory: String? = null
    private var iptvBrowseToken = 0
    private var iptvWatchRegistrationToken = 0
    private val iptvBrowseHandler = Handler(Looper.getMainLooper())
    private val iptvZapPageSize = 200
    private var iptvZapPagingActive = false
    private var iptvZapCategory: String? = null
    private var iptvZapSourceId: String? = null
    private var iptvZapSourceName: String = "IPTV"
    private var iptvZapContentType: String = "live"
    private var iptvZapCategories = mutableListOf<String>()
    private var iptvZapCategoryTotal = 0
    private var iptvZapRequestToken = 0
    private var iptvZapRequestInFlight = false
    private val iptvZapPendingInputs = java.util.ArrayDeque<Int>()
    private var iptvZapDrainingInputs = false
    private var iptvGuideUsesZapWindow = false
    private var iptvUiContextToken = 0
    private var iptvZapOwnsUiContext = false
    // Search always spans the whole source. Keep the visible category context
    // aside while the search field/results are active so Back/Close/Browse can
    // restore it exactly when the user leaves without tuning another channel.
    private var iptvAllCategorySearchActive = false
    private var iptvSearchSavedCategory: String? = null
    private var iptvSearchSavedChannels = mutableListOf<IptvChannelEntry>()
    private var iptvSearchSavedCategories = mutableListOf<String>()
    private var iptvSearchSavedUsesZapWindow = false
    private var iptvSearchSavedZapOwnsUiContext = false
    private val iptvZapMaxHiddenWindow = 600
    private var iptvZapCachedOriginCategory: String? = null
    private var iptvZapCachedDirection = 0
    private var iptvZapCachedChannels = mutableListOf<IptvChannelEntry>()
    private var iptvZapCachedOffset = 0
    private var iptvZapCachedTotal = 0
    private var iptvZapCachedCategory: String? = null
    private var iptvZapCachedCategories = emptyList<String>()

    // Contextual EPG pane shown beside the Lean Rail.
    private var iptvEpgPanel: View? = null
    private var iptvEpgLogo: android.widget.ImageView? = null
    private var iptvEpgLetter: TextView? = null
    private var iptvEpgChannelName: TextView? = null
    private var iptvEpgChannelGroup: TextView? = null
    private var iptvEpgDate: TextView? = null
    private var iptvEpgLoading: View? = null
    private var iptvEpgEmpty: View? = null
    private var iptvEpgList: RecyclerView? = null
    private var iptvEpgAdapter: IptvEpgAdapter? = null
    private var iptvEpgPrograms: List<IptvEpgProgram> = emptyList()
    private var iptvEpgDayOffset = 0
    private var iptvEpgToken = 0
    private var iptvEpgVisible = false
    private var iptvEpgEntry: IptvChannelEntry? = null

    // Stremio-addon IPTV channels: their `url` is a stremio-tv:// key, not a
    // stream — Flutter resolves it into an ordered candidate URL list on
    // demand, and playback walks the candidates serially on error until one
    // plays or the list runs out (then the channel goes quiet, like a dead
    // M3U stream). Token guards stale async resolves after a channel switch.
    private var iptvStremioToken = 0
    private var iptvStremioChannelKey: String? = null
    private var iptvStremioCandidates: List<IptvStremioCandidate> = emptyList()
    private var iptvStremioCandidateIndex = 0
    private var iptvStremioWinnerReported = false
    // Per-candidate stall watchdog: live streams can buffer forever without
    // ever erroring, and the ladder only advances on error — this converts a
    // never-READY candidate into a failure. Cancelled by STATE_READY.
    private var iptvStremioStallRunnable: Runnable? = null

    // Stremio Sources state
    private var stremioSources = mutableListOf<StremioSource>()
    private var currentStremioSourceIndex = 0
    private var stremioSourceBadge: View? = null
    private var stremioSourceBadgeText: TextView? = null
    private var stremioResolutionToken = 0 // Guards against stale async resolution callbacks
    private var hasPlaylistResolver = false // True when source switching rebuilds entire playlist

    // Network & Buffering presets (Settings → Playback), riding the launch
    // payload. "standard" = the stock configuration in setupPlayer runs
    // untouched — the invariant that keeps this feature regression-free.
    private var networkPatience = "standard"
    private var networkBuffer = "standard"
    /** 'auto' | 'hardware' | 'software' — see StorageService.iptvDecoderModes.
     *  Only ever non-auto when the user picked a decoder in Playback settings
     *  (a frozen picture with running audio is a box decoder defect). */
    private var iptvDecoderMode = "auto"
    // Series source tabs (payload-gated): torrent sources split into
    // "Season packs" / "Episodes" columns, each offering "Load more sources"
    // until its dedicated fetch has run (a series play arrives with only one
    // category searched — bound source: neither, pack-first: packs only,
    // episode fallback: episodes only).
    private var seriesSourceTabs = false
    private var seriesPacksFetched = true
    private var seriesEpisodesFetched = true
    // Movie flavor: flat picker, one "Load more sources" on the Torrent tab
    // (a bound movie play launches with just the pinned torrent).
    private var movieMoreSources = false
    private var movieSourcesFetched = true
    private var moreSourcesLoadingMode: String? = null // in-flight "Load more" tab

    // Per-addon fetch: every applicable addon rides the payload so the source
    // browser can show zero-result addons as placeholder groups with a
    // "Fetch results" row. State is keyed by the addon's sourceKey (= its
    // browser group id): "fetching" / "failed" / "fetched".
    data class TvSourceAddon(val id: String, val name: String, val sourceKey: String)
    private var sourceAddons: List<TvSourceAddon> = emptyList()
    private val addonFetchState = mutableMapOf<String, String>()
    private val addonPackProbing = mutableSetOf<String>()

    // Stremio TV Guide state
    private var isStremioTvMode = false
    private var stremioTvChannels = mutableListOf<StremioTvGuideChannel>()
    private var stremioTvGuideOverlay: View? = null
    private var stremioTvGuideList: RecyclerView? = null
    private var stremioTvGuideSearch: android.widget.EditText? = null
    private var stremioTvGuideCountText: TextView? = null
    private var stremioTvGuideNowPlaying: View? = null
    private var stremioTvGuideNowPoster: android.widget.ImageView? = null
    private var stremioTvGuideNowLetter: TextView? = null
    private var stremioTvGuideCurrentName: TextView? = null
    private var stremioTvGuideCurrentTitle: TextView? = null
    private var stremioTvChannelAdapter: StremioTvGuideAdapter? = null
    private var stremioTvGuideVisible = false
    private var stremioTvChannelSwitchInProgress = false
    private var stremioTvNextInProgress = false
    private var stremioTvSwitchToken = 0

    // Subtitle Settings Panel
    private var subtitleSettingsRoot: View? = null
    private var subtitleSettingsVisible = false
    private var subtitlePanel: SubtitlePanelController? = null
    private var syncOverlay: SubtitleSyncOverlayController? = null
    private var linePickerOverlay: SubtitleLinePickerController? = null
    private var unifiedMenu: UnifiedMenuController? = null
    private var sourceBrowser: TvSourceBrowserController? = null
    private val subtitleSeekHandler = Handler(Looper.getMainLooper())
    private val subtitleSeekRunnable = Runnable {
        player?.let { p ->
            val pos = p.currentPosition
            if (pos >= 0) p.seekTo(pos)
        }
    }
    private var subtitleTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()
    private var currentSubtitleTrackIndex = 0

    // Stremio external subtitles
    private var stremioSubtitleService: StremioSubtitleService? = null
    private val stremioSubtitles = mutableListOf<StremioSubtitle>()  // deduped flat view over addonSubtitleResults
    private val addonSubtitleResults = mutableListOf<AddonSubtitleResult>()  // per-addon, ordered/stable
    // Subtitles supplied at launch (e.g. YouTube closed captions). Parsed once
    // from the payload; re-seeded as a provider group on each item instead of
    // an IMDb-keyed addon fetch. Non-empty only for sources that carry their
    // own captions.
    private val injectedSubtitles = mutableListOf<StremioSubtitle>()
    // When launch-supplied captions are the only subtitles (YouTube), don't
    // auto-enable them — matches YouTube's captions-off default and the phone
    // player. The user turns them on from the subtitle menu.
    private var suppressSubtitleAutoSelect = false
    private val addonFetchTokens = mutableMapOf<String, Int>()  // per-addon retry generation
    private val failedSubtitleUrls = mutableSetOf<String>()  // external subs that parsed to zero cues — don't re-auto-select
    private var currentStremioSubtitleIndex: Int = -1  // -1 means no Stremio subtitle selected
    private var isLoadingStremioSubtitles = false  // Loading state for UI indicator
    private var embeddedSubtitleSelected = false  // Track if embedded subtitle was auto-selected
    private var userManuallySelectedSubtitle = false  // Track if user manually selected a subtitle
    private var addonSubtitleFetchToken = 0  // Guard against stale async fetches on content switch
    private var manualSubtitleImdbId: String? = null  // Subtitle-only identity override from Search Subtitle
    private var manualSubtitleType: String? = null
    private var manualSubtitleSeason: Int? = null
    private var manualSubtitleEpisode: Int? = null
    private var manualSubtitleDisplayLabel: String? = null
    private val subtitleScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

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
    private val skipSegmentScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var skipSegmentFetchJob: kotlinx.coroutines.Job? = null
    private var skipSegmentFetchGeneration = 0
    private var loadedSkipSegmentKey: String? = null
    private var loadingSkipSegmentKey: String? = null
    private var skipSegments = TvSkipSegments.EMPTY
    private var activeSkipSegment: TvSkipSegment? = null
    private var skipFocusOfferedKey: String? = null
    private val skipSegmentCache = mutableMapOf<String, TvSkipSegments>()

    // ── Sleep timer ───────────────────────────────────────────────────────────
    // Stops playback after a countdown, or at the end of the current item.
    //
    // The activity adds FLAG_KEEP_SCREEN_ON on create and never clears it, so
    // pausing alone would leave the TV lit all night — the exact thing this
    // feature exists to prevent. Firing therefore drops the flag as well, and
    // any later playback re-arms it (see onIsPlayingChanged).
    private enum class SleepTimerMode { OFF, COUNTDOWN, END_OF_ITEM }
    private var sleepTimerMode = SleepTimerMode.OFF
    private var sleepTimerDeadlineElapsedMs = 0L
    private val sleepTimerHandler = Handler(Looper.getMainLooper())
    private var sleepTimerRunnable: Runnable? = null
    private val sleepTimerMinuteOptions = listOf(15, 30, 45, 60, 90)

    /**
     * Latched from a sleep-timer stop until the user explicitly starts playback
     * again. Pausing alone is not enough to make the stop stick: `onStart()`
     * calls `play()` unconditionally, so the next time this activity restarts
     * it would resume and play through the night; a queued auto-advance would
     * do the same. Every automatic start checks this.
     */
    private var sleepStopLatched = false

    // Side-loaded external subtitle rendering. External (Stremio) subtitles are
    // downloaded + parsed off-thread and fed straight to subtitleOverlay from a
    // position ticker — the player source is never rebuilt, so switching
    // subtitles never interrupts playback (and never touches the fragile
    // resume/seek logic that a re-prepare would).
    private var externalSubtitleCues: List<SubtitleCue> = emptyList()
    private var externalSubtitleActive = false
    private var activeExternalSubtitleUrl: String? = null  // URL of the side-rendered subtitle currently on screen; identifies it for sync-offset scoping
    private var externalSubtitleLoadToken = 0  // Guard against stale downloads (fast switching / content change)
    private val externalSubtitleHandler = Handler(Looper.getMainLooper())
    private var externalSubtitleTicker: Runnable? = null
    private var lastExternalCueText: String? = null
    private var statusPill: TextView? = null
    private val statusPillHideRunnable = Runnable { hideStatusPill() }

    // Auto-sync's toast (bottom-right, quiet): out of the subtitles' way at
    // bottom-center, and deliberately soft-spoken — sync happens by default
    // now, so its feedback must never feel like an alert.
    private var autoSyncPill: LinearLayout? = null
    private var autoSyncPillRing: AutoSyncRingView? = null
    private var autoSyncPillLabel: TextView? = null
    private var autoSyncPillResultShowing = false
    private var autoSyncPillWindowActive = false
    private var autoSyncPillAnnounceShowing = false
    // Dismiss the announce line only if it's still what's on screen — a
    // status shown meanwhile (manual sync-now) must not be clobbered.
    private val autoSyncPillAnnounceDismissRunnable = Runnable {
        if (autoSyncPillAnnounceShowing) {
            autoSyncPillAnnounceShowing = false
            hideAutoSyncPillView()
        }
    }
    private val autoSyncCardHideRunnable = Runnable { hideAutoSyncCard() }

    /** Last auto-sync outcome, shown on the menu row while its subtitle is active. */
    private var autoSyncResultLabel: String? = null
    private var autoSyncResultUrl: String? = null

    // Hands-free auto-sync (Settings → Playback, Android TV only): a ladder of
    // attempts as audio accrues — narrow search needs ~20s, wider ones more —
    // each silent unless it SUCCEEDS. Stops on success, on drift (retrying
    // won't fix a framerate mismatch), when the user dials any manual offset,
    // or when the rungs run out.
    private val autoSyncLadderSec = intArrayOf(20, 45, 90, 180)
    private var autoSyncLadderIdx = 0
    private var autoSyncLadderDone = false
    private var autoSyncLadderTick: Runnable? = null

    // Verify mode: after an offset WE applied (auto, manual button, or a
    // restored memory), periodically re-check the CURRENT region of the film
    // against that offset — piecewise alignment delivered where the user is.
    // The applied value doubles as the tamper flag: the moment the stored
    // offset differs from it, the user has taken over and verification ends.
    private var autoSyncAppliedOffsetMs: Long? = null
    private var autoSyncVerifyTick: Runnable? = null
    private var autoSyncVerifyMisses = 0

    // Focus navigation state - prevents focus recovery from interfering with active navigation
    private var isNavigating = false
    private var navigationTargetPosition = -1
    private val focusRecoveryHandler = Handler(Looper.getMainLooper())
    private var focusRecoveryRunnable: Runnable? = null

    private val resizeModes = arrayOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
        AspectRatioFrameLayout.RESIZE_MODE_FIT
    )

    private val resizeModeLabels = arrayOf("Fit", "Fill", "Zoom", "Cinema Zoom")

    private val playbackSpeeds = arrayOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    private val playbackSpeedLabels = arrayOf("0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x")

    private val nightModeGains = arrayOf(0, 500, 1000, 1500, 2000, 2500, 3000, 5000)  // millibels
    private val nightModeLabels = arrayOf("Off", "Low", "Medium", "High", "Higher", "Extreme", "Max", "Sleeping Baby")

    // Handlers
    private val progressHandler = Handler(Looper.getMainLooper())
    private val controlsHandler = Handler(Looper.getMainLooper())
    private val seekbarHandler = Handler(Looper.getMainLooper())

    // PikPak cold storage retry state
    private var isPikPakRetrying: Boolean = false
    private var pikPakRetryCount: Int = 0
    private var pikPakRetryId: Int = 0
    private val pikPakRetryHandler = Handler(Looper.getMainLooper())

    // Buffering indicator
    private lateinit var bufferingIndicator: View
    private lateinit var pikPakReactivationIndicator: View
    private lateinit var pikPakReactivationText: TextView
    private var hasEverBeenReady = false
    // Guards against falsely marking an item watched on Trakt. maxStableDurationMs
    // is the largest duration ExoPlayer has reported this item; lastRealPositionMs
    // is the most recent genuine playback position. A source re-prepare (channel/
    // source switch) can make ExoPlayer briefly report a short duration or fire a
    // spurious STATE_ENDED — either of which would otherwise inflate progress to
    // ~100% and scrobble the item as fully watched. Both reset per item.
    private var maxStableDurationMs: Long = 0L
    private var lastRealPositionMs: Long = 0L
    // One local-threshold report per content identity. Flutter owns the durable
    // completed state; this only prevents sending a write-trigger on every
    // five-second progress pulse after the threshold has been crossed.
    // A fetched direct episode replaces the one-entry playlist in place, so
    // its index is always 0. Deduplicate completion by episode identity rather
    // than index or only the first direct episode could cross the threshold.
    private val locallyCompletedItemKeys = mutableSetOf<String>()
    private val bufferingHandler = Handler(Looper.getMainLooper())
    private var bufferingDebounceRunnable: Runnable? = null

    private val progressRunnable = object : Runnable {
        override fun run() {
            sendProgress(completed = false)
            maybeShowUpNext()
            player?.let {
                iptvTuneDiagnostics.onProgress(it.currentPosition, it.isPlaying)
                // playWhenReady, not isPlaying: a buffering wedge reports
                // isPlaying=false but still wants playback; a user pause is
                // exactly what must NOT read as a stall.
                if (isIptvMode) {
                    iptvLiveRecovery.onProgress(it.currentPosition, it.playWhenReady)
                    // The renderer's own output counter — the one signal
                    // that survives a wedged video decoder under a healthy
                    // audio clock (finding #13; the Streamer report).
                    val frames = it.videoDecoderCounters?.let { c ->
                        c.ensureUpdated()
                        c.renderedOutputBufferCount
                    } ?: -1
                    iptvLiveRecovery.onVideoFrames(
                        renderedFrames = frames,
                        hasVideoTrack = it.videoFormat != null,
                        wantsPlayback = it.playWhenReady,
                    )
                    // The twin trial's verdict rides the same counter: a
                    // continuous advancing streak accepts, nothing else does
                    // (see judgeIptvTwinTrial).
                    judgeIptvTwinTrial(frames)
                }
            }
            progressHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    private val hideControlsRunnable = Runnable {
        if (!isFocusInControlsOverlay()) {
            hideControlsMenu()
        } else {
            scheduleHideControlsMenu()
        }
    }

    private val seekbarProgressRunnable = object : Runnable {
        override fun run() {
            updateSeekbarProgress()
            seekbarHandler.postDelayed(this, 100) // Update every 100ms for smooth progress
        }
    }

    private val playbackListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            when (playbackState) {
                Player.STATE_READY -> {
                    hasEverBeenReady = true
                    iptvTuneDiagnostics.onReady(player?.currentPosition ?: 0L)
                    if (isIptvMode) {
                        iptvLiveRecovery.onReady()
                        rearmIptvTwinTrialDeadline()
                    }
                    reportIptvStremioWinnerIfNeeded()
                    hideBufferingIndicator()
                    // Furthest-watched resume (same rule as the Dart player): seek
                    // the DEEPER of the local position and the Trakt percent so
                    // playback never jumps backward. startAtPercent (Stremio TV
                    // slot progress) is an explicit start and still takes precedence;
                    // it retries until the duration is known (Media3 can report
                    // TIME_UNSET on the first READY), matching the old cascade.
                    val duration = player?.duration ?: 0
                    val startPct = payload?.startAtPercent ?: 0.0
                    if (startPct > 0 && !startPct.isNaN() && !percentSeekApplied) {
                        if (duration > 0) {
                            val offset = (duration * startPct).toLong()
                            if (offset in 1 until duration) {
                                player?.seekTo(offset)
                                android.util.Log.d("AndroidTvPlayer", "Seeked to ${startPct * 100}% ($offset ms of $duration ms)")
                            }
                            // Latch ONLY once the duration was known — an unknown
                            // duration must retry on the next READY, not burn the
                            // one-shot without seeking.
                            percentSeekApplied = true
                            pendingSeekMs = 0
                            pendingItemTraktPercent = 0.0
                        }
                    } else {
                        // Launched item's payload percent (first load only) — an
                        // eligible value also arms the branch below.
                        val launchTrakt =
                            if (!percentSeekApplied) (payload?.traktProgressPercent ?: 0.0) else 0.0
                        if (pendingSeekMs > 0 || pendingItemTraktPercent > 0 || launchTrakt > 0) {
                            if (duration > 0) {
                                // Anti-yank: only seek while playback is still near
                                // the start. If the duration resolved late (e.g. it
                                // was TIME_UNSET on the first READY) and the user has
                                // already watched real seconds, dropping the resume
                                // beats jumping them mid-viewing.
                                val pos = player?.currentPosition ?: 0L
                                if (pos <= 5000) {
                                    val hi = (duration * 0.9).toLong()
                                    // The launched item's payload percent is an EXPLICIT
                                    // promise (the details-screen Resume advertised this
                                    // position) — honour it outright when seekable,
                                    // matching the pre-rework launched-item behaviour.
                                    val launchMs =
                                        if (launchTrakt > 0 && launchTrakt < 100) (duration * launchTrakt / 100.0).toLong() else 0L
                                    if (launchMs > 2000 && launchMs < hi) {
                                        player?.seekTo(launchMs)
                                        android.util.Log.d("AndroidTvPlayer", "Resume: explicit launch tracker ${launchTrakt.toInt()}% -> $launchMs ms of $duration ms")
                                    } else {
                                        // FURTHEST-WATCHED WINS: the per-episode tracker
                                        // candidate is gated to the resumable window
                                        // (past 2s, before the last 10%); the LOCAL
                                        // candidate keeps the old cascade's semantics —
                                        // ANY explicit position inside the duration is
                                        // honoured (a source switch may capture 93% and
                                        // must come back exactly there).
                                        val rawTraktMs =
                                            if (pendingItemTraktPercent > 0 && pendingItemTraktPercent < 100) (duration * pendingItemTraktPercent / 100.0).toLong() else 0L
                                        val traktMs = if (rawTraktMs > 2000 && rawTraktMs < hi) rawTraktMs else 0L
                                        val localMs =
                                            if (pendingSeekMs > 0 && pendingSeekMs < duration) pendingSeekMs else 0L
                                        val target = maxOf(traktMs, localMs)
                                        if (target > 0) {
                                            player?.seekTo(target)
                                            android.util.Log.d("AndroidTvPlayer", "Resume: furthest trakt=$traktMs local=$localMs -> $target ms of $duration ms")
                                        }
                                    }
                                }
                                percentSeekApplied = true
                                pendingSeekMs = 0
                                pendingItemTraktPercent = 0.0
                            }
                            // Duration unknown on this READY: leave ALL candidates
                            // intact and retry on the next READY (Media3 often
                            // resolves TIME_UNSET one event later) — otherwise a
                            // launched item's local resume dies here and a shallower
                            // payload Trakt percent would win the retry, jumping
                            // backward. The anti-yank guard above bounds the retry.
                        }
                    }
                    // Initialize night mode if needed
                    if (loudnessEnhancer == null && nightModeIndex > 0) {
                        initializeLoudnessEnhancer()
                    }
                    // Announce the audio session to system effect apps. Mirrors
                    // the night-mode handling above: the session id only exists
                    // once the audio renderer is live, and onAudioSessionIdChanged
                    // doesn't re-fire when a seamless transition reuses the
                    // same AudioTrack.
                    syncAudioEffectSession()
                }
                Player.STATE_BUFFERING -> {
                    iptvTuneDiagnostics.onBufferingStart(player?.currentPosition ?: 0L)
                    if (hasEverBeenReady) {
                        showBufferingIndicatorDebounced()
                    }
                }
                Player.STATE_ENDED -> {
                    iptvTuneDiagnostics.onPlaybackEnded(lastRealPositionMs)
                    hideBufferingIndicator()
                    // LIVE: an ended live stream is a dropped connection, not
                    // a finished item — the origin closed on us. NOTHING
                    // below this block (completion progress, episode advance)
                    // may interpret a live EOF as "watched to the end", so
                    // live ALWAYS returns here — even when the recovery
                    // machine declines (backgrounded, paused). Sleep's
                    // end-of-item stop keeps its meaning: the item ended,
                    // stop here — minus the completion side-effects that
                    // make no sense for live. (Codex round 2, finding 4:
                    // gating the return on onEnded()'s answer let an
                    // ineligible live EOF fall into VOD completion.)
                    val endedLiveEntry = if (isIptvMode) {
                        iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive }
                    } else null
                    if (endedLiveEntry != null) {
                        if (sleepTimerMode == SleepTimerMode.END_OF_ITEM) {
                            cancelSleepTimer()
                            sleepStopLatched = true
                            releaseScreenForSleep()
                            Toast.makeText(
                                this@AndroidTvTorrentPlayerActivity,
                                "Sleep timer — stopping here",
                                Toast.LENGTH_LONG
                            ).show()
                        } else {
                            iptvLiveRecovery.onEnded()
                        }
                        return
                    }
                    // Ignore a spurious end: if real playback never got near the full
                    // (stable) duration, the source "ended" early — e.g. a subtitle
                    // reload re-prepared it against an incomplete timeline. Reporting
                    // it as completed would scrobble the item as fully watched on Trakt
                    // and auto-advance, despite little of it being watched.
                    val stableDur = maxStableDurationMs
                    val genuineEnd = stableDur <= 0L ||
                        lastRealPositionMs >= (stableDur * 0.9).toLong()
                    if (!genuineEnd) {
                        android.util.Log.w(
                            "AndroidTvPlayer",
                            "Ignoring spurious STATE_ENDED at ${lastRealPositionMs}ms of stable ${stableDur}ms"
                        )
                        return
                    }
                    sendProgress(completed = true)

                    // "Stop at the end of this episode". Playback has already
                    // finished, so this only has to suppress every advance
                    // below and let the screen go to sleep.
                    if (sleepTimerMode == SleepTimerMode.END_OF_ITEM) {
                        cancelSleepTimer()
                        sleepStopLatched = true
                        releaseScreenForSleep()
                        Toast.makeText(
                            this@AndroidTvTorrentPlayerActivity,
                            "Sleep timer — stopping here",
                            Toast.LENGTH_LONG
                        ).show()
                        return
                    }

                    // IPTV episode list (series/VOD): auto-advance to the next
                    // episode, mirroring the Next button. Checked before the
                    // payload guard below because IPTV mode has no `payload`
                    // model — without this an episode just parks on its final
                    // frame with a next episode available.
                    if (isIptvMode) {
                        nextIptvEpisode()?.let { switchToIptvChannel(it) }
                        return
                    }

                    val model = payload ?: return
                    if (continuousShuffleEnabled) {
                        val shuffleIndex = pickShuffleIndex()
                        if (shuffleIndex != null) {
                            showNextOverlay(model.items[shuffleIndex])
                            progressHandler.postDelayed({
                                hideNextOverlay()
                                isAutoAdvancing = true
                                playItem(shuffleIndex)
                            }, 1500)
                            return
                        }
                    }

                    val nextIndex = getNextPlayableIndex(currentIndex)
                    if (nextIndex != null) {
                        showNextOverlay(model.items[nextIndex])
                        progressHandler.postDelayed({
                            hideNextOverlay()
                            isAutoAdvancing = true
                            playItem(nextIndex)
                        }, 1500)
                    } else {
                        if (isStremioTvMode && stremioTvChannels.any { it.isCurrent }) {
                            requestStremioTvNext(finishOnFailure = true)
                            return
                        }

                        // No next in playlist — fetch the next episode
                        // in-player when possible; else hand back for a
                        // quick-play relaunch.
                        val currentItem = model.items[currentIndex]
                        if (model.contentType == "series" && currentItem.season != null && currentItem.episode != null) {
                            val nextTarget = guideAdjacent(model, currentItem, 1)
                            if (nextTarget != null && hasPlaylistResolver) {
                                requestEpisodeFetch(
                                    nextTarget.season,
                                    nextTarget.episode,
                                    autoAdvance = true,
                                )
                                return
                            }
                            if (model.imdbId != null) {
                                if (hasPlaylistResolver) {
                                    requestAdjacentEpisodeFetch(
                                        model.imdbId!!,
                                        currentItem.season,
                                        currentItem.episode,
                                        autoAdvance = true,
                                    )
                                    return
                                }
                                requestQuickPlayNextEpisode(model.imdbId!!, currentItem.season, currentItem.episode)
                            }
                        }
                        finish()
                    }
                }
            }
            updatePauseButtonLabel()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updatePauseButtonLabel()
            // Re-arm the screen if a sleep-timer stop released it and the user
            // started watching again. Idempotent, so it's harmless otherwise.
            if (isPlaying) {
                holdScreenForPlayback()
            }
            // Startup-channel memory — armed by real playback only, never by a
            // tune, so a dead stream cannot become "the last channel watched".
            if (isPlaying) noteLiveChannelPlaying()
        }

        override fun onPlayerError(error: PlaybackException) {
            iptvTuneDiagnostics.onError(error)
            // Stale-delivery gate for EVERY IPTV recovery path below: a
            // queued onPlayerError whose media item was already superseded
            // (a zap's or the watchdog's prepare() cleared the error) reports
            // playerError == null. Acting on one would attribute channel A's
            // failure to channel B — e.g. force-HLS-poisoning B's URL for the
            // whole session, or restarting A's stream under B's identity.
            val isLiveIptvError = isIptvMode && player?.playerError != null

            // A twin trial owns every error on its `.ts` URL — an HLS-only
            // panel can answer it with anything (404, playlist text the TS
            // sniffer rejects, junk). The verdict is simply "twin failed,
            // restore the original HLS": never surrender the channel over a
            // speculative URL, and never let the unrecognized-format retry
            // below force-HLS the twin for the session. MUST stay above that
            // retry and the generic ladder.
            if (isLiveIptvError && iptvTwinTrialUrl != null &&
                currentIptvStreamUrl == iptvTwinTrialUrl
            ) {
                failIptvTwinTrial("error:${error.errorCodeName}")
                return
            }

            // A twin that proved itself earlier can still disappear later.
            // AUTH-class answers are deterministic, so retrying that twin is
            // pointless; revoke it and restore the original HLS once.
            if (isLiveIptvError && restoreAcceptedIptvTwinAfterAuth(error)) return

            // IPTV: a stream that failed extractor sniffing is almost always
            // an HLS playlist behind an extension-less URL (inferred as
            // progressive). Retry the SAME url once with the type forced —
            // before the Stremio ladder, so a playable-if-forced candidate
            // isn't skipped.
            if (isLiveIptvError && retryIptvAsHlsIfUnrecognized(error)) return

            // IPTV live: falling behind the live window (long pause, hiccup
            // on a short-window stream) is recoverable by rejoining the live
            // edge — without this the channel just dies with an error.
            if (isLiveIptvError &&
                currentIptvStreamUrl != null &&
                error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW
            ) {
                android.util.Log.w("AndroidTvPlayer", "Behind live window — rejoining live edge")
                player?.seekToDefaultPosition()
                player?.prepare()
                player?.play()
                return
            }

            // Stremio-addon IPTV channels: a dead candidate URL is expected —
            // step down the ladder. Everything else keeps the pre-existing
            // behavior (no handler existed; playback simply stops).
            if (isLiveIptvError && tryNextIptvStremioCandidate()) return
            // Generic live recovery — the last resort after every specific
            // handler above declined. Classified: auth-class surrenders
            // immediately, decoder-class gets one retry, the rest climb the
            // 0/1/3/5s ladder. The decoder toast still shows so a codec wall
            // stays explained even while the machine tries its one retry.
            if (isLiveIptvError &&
                iptvLiveRecovery.onFatalError(classifyIptvError(error))
            ) {
                reportDecoderFailure(error)
                return
            }
            android.util.Log.e("AndroidTvPlayer", "Player error: ${error.errorCodeName}")
            reportDecoderFailure(error)
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) {
            // Auto-sync anchoring: every discontinuity (seek, transition) tells
            // the PCM tap where its newest audio run sits on the media timeline.
            speechTap?.notifyDiscontinuity(newPosition.positionMs)
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // A different media item means a different timeline AND usually a
            // different release — audio features captured from the old one
            // would mis-anchor (or mis-match) subtitle timing on the new one.
            speechTap?.reset()
            // The player is reused across every content swap (next episode, IPTV
            // and Stremio channel/source switches, subtitle reloads), so the audio
            // session id stays the same and onAudioSessionIdChanged never fires.
            // But each new media item rebuilds the AudioTrack, detaching the
            // night-mode LoudnessEnhancer — leaving the button reading e.g. "High"
            // with no boost actually applied. Drop the stale instance here so the
            // STATE_READY handler recreates it against the live audio track.
            //
            // Defensive: repeat mode isn't enabled today (looping is manual via
            // STATE_ENDED), so this can't currently fire. But if it ever is, a
            // seamless repeat reuses the same AudioTrack (effect still attached)
            // and won't re-fire STATE_READY — releasing there would kill night
            // mode with nothing to rebuild it.
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT) return
            releaseLoudnessEnhancer()
        }

        override fun onAudioSessionIdChanged(audioSessionId: Int) {
            // Let system effect apps follow the new session (no-op if unchanged).
            syncAudioEffectSession(audioSessionId)
            // Reinitialize night mode effect when audio session changes
            if (nightModeIndex > 0 && audioSessionId != 0) {
                releaseLoudnessEnhancer()
                initializeLoudnessEnhancer()
            }
        }
    }

    // Broadcast receiver for async metadata updates from Flutter
    private var metadataUpdateReceiver: android.content.BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_android_tv_torrent_player)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Engine captures start/stop outside this activity (notification Stop,
        // duration cap) — the registry callback keeps the Record button honest.
        RecordingRegistry.addListener(recordingRegistryListener)

        // Load default player settings from Flutter's SharedPreferences
        loadPlayerDefaults()

        // Parse payload from temp file (avoids Android's ~1MB Intent size limit)
        val payloadPath = intent.getStringExtra("payloadPath")
        val rawPayload = if (payloadPath != null) {
            try {
                val file = java.io.File(payloadPath)
                val content = file.readText()
                file.delete() // Clean up temp file after reading
                android.util.Log.d("AndroidTvPlayer", "Read payload from file: $payloadPath (${content.length} bytes)")
                content
            } catch (e: Exception) {
                android.util.Log.e("AndroidTvPlayer", "Failed to read payload file: $payloadPath", e)
                null
            }
        } else {
            // Fallback to legacy Intent extra for backward compatibility
            intent.getStringExtra(PAYLOAD_KEY)
        }
        if (rawPayload.isNullOrEmpty()) {
            finish()
            return
        }

        // Check for IPTV mode before normal payload parsing
        try {
            val payloadCheck = JSONObject(rawPayload)
            if (payloadCheck.optString("mode") == "iptv") {
                initIptvMode(payloadCheck)
                return
            }
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "IPTV mode check failed", e)
        }

        payload = parsePayload(rawPayload)
        if (payload == null || payload!!.items.isEmpty()) {
            finish()
            return
        }
        currentIndex = payload!!.startIndex.coerceIn(0, payload!!.items.lastIndex)

        // Apply custom font from Flutter settings if provided in payload
        try {
            val payloadJson = JSONObject(rawPayload)
            val customFontPath = payloadJson.optString("customFontPath").takeIf { it.isNotEmpty() }
            val customFontName = payloadJson.optString("customFontName").takeIf { it.isNotEmpty() }
            if (customFontPath != null) {
                android.util.Log.d("AndroidTvPlayer", "Applying custom font from Flutter: $customFontPath")
                SubtitleFontManager.applyCustomFontIfValid(this, customFontPath, customFontName)
            }
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Failed to parse custom font from payload", e)
        }

        bindViews()
        setupPlayer()
        setupSeekbar()
        setupPlaylist()
        setupControls()
        setupStremioSources()

        // Check for Stremio TV guide data in payload
        try {
            val payloadJson = JSONObject(rawPayload)
            val guideJson = payloadJson.optJSONObject("stremioTvGuide")
            if (guideJson != null) {
                initStremioTvGuide(guideJson)
                updateCatalogEpisodeControls()
            }
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Stremio TV guide init failed", e)
        }

        // Launch-supplied subtitles (e.g. YouTube captions). Parsed once here;
        // seeded per-item in fetchStremioSubtitles instead of an addon fetch.
        try {
            val payloadJson = JSONObject(rawPayload)
            val subsArray = payloadJson.optJSONArray("initialSubtitles")
            if (subsArray != null) {
                for (i in 0 until subsArray.length()) {
                    val obj = subsArray.optJSONObject(i) ?: continue
                    val source = obj.optString("source").takeIf { it.isNotEmpty() } ?: "Captions"
                    injectedSubtitles.add(StremioSubtitle.fromJson(obj, source, addonId = "injected"))
                }
                android.util.Log.d("AndroidTvPlayer", "Loaded ${injectedSubtitles.size} launch-supplied subtitles")
            }
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Failed to parse initialSubtitles from payload", e)
        }

        // Initialize seek feedback manager
        seekFeedbackManager = SeekFeedbackManager(findViewById(android.R.id.content))
        setupBackPressHandler()
        setupMetadataReceiver()

        // Initialize Stremio subtitle service
        stremioSubtitleService = StremioSubtitleService(this)

        // Start playback
        playItem(currentIndex)
    }

    private fun setupMetadataReceiver() {
        metadataUpdateReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
                val updatesJson = intent?.getStringExtra("metadataUpdates")
                val imdbId = intent?.getStringExtra("imdbId")
                val guideJson = intent?.getStringExtra("guideEpisodes")
                handleMetadataUpdate(updatesJson, imdbId, guideJson)
            }
        }

        val filter = android.content.IntentFilter("com.debrify.app.tv.UPDATE_EPISODE_METADATA")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(metadataUpdateReceiver, filter, android.content.Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(metadataUpdateReceiver, filter)
        }
        android.util.Log.d("AndroidTvPlayer", "Metadata update receiver registered")

        // Request metadata from Flutter now that receiver is ready
        requestMetadataFromFlutter()
    }

    private fun handleMetadataUpdate(updatesJson: String?, imdbId: String?, guideJson: String? = null) {
        android.util.Log.d("TVMazeUpdate", "handleMetadataUpdate CALLED")
        android.util.Log.d("TVMazeUpdate", "updatesJson length=${updatesJson?.length ?: 0}, imdbId=$imdbId")

        val model = payload
        if (model == null) {
            android.util.Log.e("TVMazeUpdate", "payload is NULL - cannot update")
            return
        }

        // Handle IMDB ID update for Stremio subtitles
        if (!imdbId.isNullOrEmpty() && imdbId.startsWith("tt")) {
            val previousImdbId = model.imdbId
            if (previousImdbId.isNullOrEmpty()) {
                android.util.Log.d("TVMazeUpdate", "Discovered IMDB ID from TVMaze: $imdbId (was: $previousImdbId)")
                // Update payload with discovered IMDB ID
                model.imdbId = imdbId
                // Fetch Stremio subtitles now that we have IMDB ID
                val currentItem = model.items.getOrNull(currentIndex)
                if (currentItem != null) {
                    android.util.Log.d("TVMazeUpdate", "Fetching Stremio subtitles with discovered IMDB ID")
                    fetchStremioSubtitles(currentItem)
                }
            }
        }

        // Full-show episode guide: adopt it and rebuild the series playlist so
        // absent episodes render as fetchable rows (this also enables the
        // playlist overlay for single-stream launches).
        if (!guideJson.isNullOrEmpty()) {
            try {
                val guideArray = JSONArray(guideJson)
                val parsed = mutableListOf<GuideEpisode>()
                for (i in 0 until guideArray.length()) {
                    val g = guideArray.getJSONObject(i)
                    val season = g.optInt("season", -1)
                    val episode = g.optInt("episode", -1)
                    if (season < 0 || episode < 0) continue
                    parsed.add(
                        GuideEpisode(
                            season = season,
                            episode = episode,
                            title = if (g.has("title")) g.optString("title") else null,
                            artwork = if (g.has("artwork")) g.optString("artwork") else null,
                            description = if (g.has("description")) g.optString("description") else null,
                            rating = if (g.has("rating")) g.optDouble("rating") else null,
                            runtime = if (g.has("runtime")) g.optInt("runtime") else null,
                            resumePositionMs = if (g.has("resumePositionMs")) g.optLong("resumePositionMs") else null,
                            durationMs = if (g.has("durationMs")) g.optLong("durationMs") else null,
                            trackerProgressPercent = if (g.has("trackerProgressPercent")) g.optDouble("trackerProgressPercent") else null,
                            watched = g.optBoolean("watched", false),
                        )
                    )
                }
                if (parsed.isNotEmpty()) {
                    model.guideEpisodes.clear()
                    model.guideEpisodes.addAll(parsed)
                    android.util.Log.d("TVMazeUpdate", "Adopted ${parsed.size} guide episodes")
                    runOnUiThread {
                        if (model.contentType.lowercase(Locale.US) == "series") {
                            rebuildPlaylistContent()
                            seriesPlaylistAdapter?.setActiveIndex(currentIndex)
                            updateCatalogEpisodeControls()
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("TVMazeUpdate", "Failed to parse guide episodes: ${e.message}", e)
            }
        }

        // Handle episode metadata updates
        if (updatesJson.isNullOrEmpty()) {
            android.util.Log.d("TVMazeUpdate", "No episode metadata updates to process")
            return
        }

        try {
            val updatesArray = JSONArray(updatesJson)
            android.util.Log.d("TVMazeUpdate", "Parsed ${updatesArray.length()} updates")
            android.util.Log.d("TVMazeUpdate", "model.items.size=${model.items.size}")

            var anyUpdated = false
            var updatedCount = 0
            var skippedCount = 0
            for (i in 0 until updatesArray.length()) {
                val update = updatesArray.getJSONObject(i)
                val requestedIndex = update.optInt("originalIndex", -1)
                val updateSeason = if (update.has("season")) update.optInt("season") else null
                val updateEpisode = if (update.has("episode")) update.optInt("episode") else null
                val originalIndex = if (updateSeason != null && updateEpisode != null) {
                    val requestedItem = model.items.getOrNull(requestedIndex)
                    if (requestedItem?.season == updateSeason && requestedItem.episode == updateEpisode) {
                        requestedIndex
                    } else {
                        model.items.indexOfFirst {
                            it.season == updateSeason && it.episode == updateEpisode
                        }
                    }
                } else {
                    requestedIndex
                }
                if (originalIndex < 0 || originalIndex >= model.items.size) {
                    android.util.Log.w("TVMazeUpdate", "Skipping unmatched update index=$requestedIndex S${updateSeason}E${updateEpisode} (items.size=${model.items.size})")
                    skippedCount++
                    continue
                }

                val item = model.items[originalIndex]
                val newTitle: String? = if (update.has("title")) update.optString("title") else null
                val newDescription: String? = if (update.has("description")) update.optString("description") else null
                val newArtwork: String? = if (update.has("artwork")) update.optString("artwork") else null
                val newRating = if (update.has("rating")) update.optDouble("rating") else null
                val newResumePositionMs = if (update.has("resumePositionMs")) update.optLong("resumePositionMs") else null
                val newDurationMs = if (update.has("durationMs")) update.optLong("durationMs") else null
                val hasWatchedUpdate = update.has("watched")
                val watched = if (hasWatchedUpdate) update.optBoolean("watched", false) else item.watched
                val newTrackerProgress = when {
                    hasWatchedUpdate && watched -> 100.0
                    update.has("trackerProgressPercent") -> update.optDouble("trackerProgressPercent")
                    else -> null
                }
                val isCurrentItem = originalIndex == currentIndex
                val livePositionMs = if (isCurrentItem) {
                    (player?.currentPosition ?: 0L).coerceAtLeast(0L)
                } else {
                    0L
                }
                val liveDurationMs = if (isCurrentItem) {
                    (player?.duration ?: 0L).coerceAtLeast(0L)
                } else {
                    0L
                }

                // Create updated item with new metadata
                val updatedItem = item.copy(
                    title = if (!newTitle.isNullOrEmpty()) newTitle else item.title,
                    description = if (!newDescription.isNullOrEmpty()) newDescription else item.description,
                    artwork = if (!newArtwork.isNullOrEmpty()) newArtwork else item.artwork,
                    rating = newRating ?: item.rating,
                    resumePositionMs = mergeLateMetadataResumePosition(
                        existingPositionMs = item.resumePositionMs,
                        incomingPositionMs = newResumePositionMs,
                        livePositionMs = livePositionMs,
                        isCurrentItem = isCurrentItem,
                    ),
                    durationMs = mergeLateMetadataDuration(
                        existingDurationMs = item.durationMs,
                        incomingDurationMs = newDurationMs,
                        liveDurationMs = liveDurationMs,
                        isCurrentItem = isCurrentItem,
                    ),
                    traktProgressPercent = newTrackerProgress ?: item.traktProgressPercent,
                    watched = watched,
                )
                model.items[originalIndex] = updatedItem
                anyUpdated = true
                updatedCount++
            }

            android.util.Log.d("TVMazeUpdate", "Updated $updatedCount items, skipped $skippedCount")

            if (anyUpdated) {
                android.util.Log.d("TVMazeUpdate", "Refreshing UI adapters...")
                // Refresh playlist adapter if visible
                runOnUiThread {
                    // seriesPlaylistAdapter and moviePlaylistAdapter extend RecyclerView.Adapter
                    val seriesAdapter = seriesPlaylistAdapter
                    val movieAdapter = moviePlaylistAdapter
                    android.util.Log.d("TVMazeUpdate", "seriesAdapter=${seriesAdapter != null}, movieAdapter=${movieAdapter != null}")
                    seriesAdapter?.notifyDataSetChanged()
                    movieAdapter?.notifyDataSetChanged()
                    android.util.Log.d("TVMazeUpdate", "UI refresh done")

                    // Also refresh title bar for currently playing episode
                    val currentItem = model.items.getOrNull(currentIndex)
                    if (currentItem != null) {
                        android.util.Log.d("TVMazeUpdate", "Refreshing title for current episode: ${currentItem.title}")
                        updateTitle(currentItem)
                    }
                }
            } else {
                android.util.Log.w("TVMazeUpdate", "No items updated - anyUpdated=false")
            }
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "Failed to parse metadata updates: ${e.message}", e)
        }
    }

    private fun requestMetadataFromFlutter() {
        android.util.Log.d("TVMazeUpdate", "requestMetadataFromFlutter CALLED")
        val model = payload ?: return

        // Only request metadata for series content
        if (model.contentType != "series") {
            android.util.Log.d("TVMazeUpdate", "Not requesting metadata - contentType=${model.contentType}")
            return
        }

        try {
            val channel = MainActivity.getAndroidTvPlayerChannel()
            if (channel == null) {
                android.util.Log.e("TVMazeUpdate", "Method channel is null, cannot request metadata")
                return
            }

            android.util.Log.d("TVMazeUpdate", "Invoking requestEpisodeMetadata on method channel")
            // Method channel calls MUST be on the main/UI thread
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    channel.invokeMethod("requestEpisodeMetadata", null)
                    android.util.Log.d("TVMazeUpdate", "requestEpisodeMetadata invoked successfully")
                } catch (e: Exception) {
                    android.util.Log.e("TVMazeUpdate", "Failed to invoke requestEpisodeMetadata", e)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "Error requesting metadata from Flutter", e)
        }
    }

    private fun bindViews() {
        playerView = findViewById(R.id.android_tv_player_view)
        titleContainer = findViewById(R.id.android_tv_title_container)
        titleView = findViewById(R.id.android_tv_player_title)
        // OTT-style title views (compact mode)
        titleOttContainer = findViewById(R.id.android_tv_title_ott)
        ottEpisodeBadge = findViewById(R.id.android_tv_ott_episode_badge)
        ottEpisodeTitle = findViewById(R.id.android_tv_ott_episode_title)
        ottRatingContainer = findViewById(R.id.android_tv_ott_rating_container)
        ottRating = findViewById(R.id.android_tv_ott_rating)
        channelBadge = findViewById(R.id.android_tv_channel_badge)
        subtitleOverlay = findViewById(R.id.android_tv_subtitles_custom)
        playlistOverlay = findViewById(R.id.android_tv_playlist_overlay)
        playlistView = findViewById(R.id.android_tv_playlist)
        seasonTabsContainer = findViewById(R.id.season_tabs_container)
        nextOverlay = findViewById(R.id.android_tv_next_overlay)
        nextText = findViewById(R.id.android_tv_next_text)
        nextSubtext = findViewById(R.id.android_tv_next_subtext)
        nextBackdrop = findViewById(R.id.android_tv_next_backdrop)
        upNextCard = findViewById(R.id.android_tv_upnext_card)
        upNextPoster = findViewById(R.id.android_tv_upnext_poster)
        upNextTitle = findViewById(R.id.android_tv_upnext_title)
        upNextCountdown = findViewById(R.id.android_tv_upnext_countdown)
        skipSegmentButton = findViewById(R.id.android_tv_skip_segment_button)
        skipSegmentButton.setOnClickListener { skipActiveSegment() }
        seekbarOverlay = findViewById(R.id.seekbar_overlay)
        seekbarProgress = findViewById(R.id.seekbar_progress)
        seekbarHandle = findViewById(R.id.seekbar_handle)
        seekbarCurrentTime = findViewById(R.id.seekbar_current_time)
        seekbarTotalTime = findViewById(R.id.seekbar_total_time)
        seekbarSpeedIndicator = findViewById(R.id.seekbar_speed_indicator)

        // Subtitle Settings Panel
        subtitleSettingsRoot = findViewById(R.id.subtitle_settings_root)
        subtitlePanel = subtitleSettingsRoot?.let { root ->
            SubtitlePanelController(
                activity = this,
                root = root,
                categoriesContainer = findViewById(R.id.subtitle_categories_container),
                optionsContainer = findViewById(R.id.subtitle_options_container),
                categoriesScroll = findViewById(R.id.subtitle_categories_scroll),
                optionsScroll = findViewById(R.id.subtitle_options_scroll),
                previewText = findViewById(R.id.subtitle_preview_text),
                identityLabel = findViewById(R.id.subtitle_identity_label),
                searchButton = findViewById(R.id.subtitle_search_button),
                callbacks = subtitlePanelCallbacks
            )
        }

        // Unified player menu (Miller columns) — additive, gated by USE_UNIFIED_MENU
        findViewById<View?>(R.id.unified_menu_root)?.let { root ->
            unifiedMenu = UnifiedMenuController(
                activity = this,
                root = root,
                col1 = findViewById(R.id.unified_col1),
                col2 = findViewById(R.id.unified_col2),
                col3 = findViewById(R.id.unified_col3),
                col2Header = findViewById(R.id.unified_col2_header),
                col3Header = findViewById(R.id.unified_col3_header),
                preview = findViewById(R.id.unified_preview),
                callbacks = unifiedMenuCallbacks
            )
        }

        findViewById<View?>(R.id.tv_source_browser_root)?.let { root ->
            sourceBrowser = TvSourceBrowserController(
                activity = this,
                root = root,
                rail = findViewById(R.id.tv_source_browser_rail),
                railScroll = findViewById(R.id.tv_source_browser_rail_scroll),
                header = findViewById(R.id.tv_source_browser_header),
                count = findViewById(R.id.tv_source_browser_count),
                context = findViewById(R.id.tv_source_browser_context),
                loadMore = findViewById(R.id.tv_source_browser_load_more),
                results = findViewById(R.id.tv_source_browser_results),
                resultsScroll = findViewById(R.id.tv_source_browser_scroll),
                callbacks = object : TvSourceBrowserController.Callbacks {
                    override fun entries(): List<TvSourceBrowserEntry> = stremioSources.map { source ->
                        TvSourceBrowserEntry(
                            index = source.index,
                            title = source.displayTitle,
                            source = source.source,
                            quality = source.quality,
                            size = source.formattedSize,
                            seeders = source.seeders,
                            direct = source.isDirectStream,
                            seasonPack = source.isSeasonPack,
                        )
                    }

                    override fun currentIndex(): Int = currentStremioSourceIndex

                    override fun isSeries(): Boolean =
                        payload?.contentType?.lowercase(java.util.Locale.US) == "series"

                    override fun loadMoreMode(): String? = when {
                        seriesSourceTabs && !seriesPacksFetched -> "packs"
                        seriesSourceTabs && !seriesEpisodesFetched -> "episodes"
                        !seriesSourceTabs && movieMoreSources && !movieSourcesFetched -> "movie"
                        else -> null
                    }

                    override fun isLoading(mode: String): Boolean =
                        moreSourcesLoadingMode == mode

                    override fun requestLoadMore(mode: String) {
                        requestMoreTorrentSources(mode)
                    }

                    override fun placeholderGroups(): List<Pair<String, String>> =
                        sourceAddons.map { it.sourceKey to it.name }

                    override fun groupFetchState(groupId: String): String? {
                        if (sourceAddons.none { it.sourceKey == groupId }) return null
                        return addonFetchState[groupId] ?: "idle"
                    }

                    override fun isGroupProbing(groupId: String): Boolean =
                        addonPackProbing.contains(groupId)

                    override fun requestGroupFetch(groupId: String) {
                        requestAddonTorrentSources(groupId)
                    }

                    override fun onSourceSelected(index: Int) {
                        if (index == currentStremioSourceIndex) return
                        val source = stremioSources.firstOrNull { it.index == index } ?: return
                        sourceBrowser?.hide()
                        onStremioSourceSelected(source)
                    }

                    override fun onHidden() {
                        findViewById<View>(R.id.android_tv_player_view)?.requestFocus()
                    }
                },
            )
        }

        bufferingIndicator = findViewById(R.id.android_tv_buffering_indicator)
        pikPakReactivationIndicator = findViewById(R.id.android_tv_pikpak_reactivation_indicator)
        pikPakReactivationText = findViewById(R.id.android_tv_pikpak_reactivation_text)

        // Stremio sources badge (opens the dedicated full-screen browser).
        stremioSourceBadge = findViewById(R.id.stremio_source_badge)
        stremioSourceBadgeText = findViewById(R.id.stremio_source_badge_text)
    }

    private fun buildProtectedMediaOrigins(items: List<PlaybackItem>): Set<String> {
        return items
            .mapNotNull { item ->
                if (item.url.isBlank()) {
                    null
                } else {
                    originKey(Uri.parse(item.url))
                }
            }
            .toSet()
    }

    private fun originKey(uri: Uri): String? {
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        val host = uri.host?.lowercase() ?: return null
        val port = when {
            uri.port != -1 -> uri.port
            scheme == "http" -> 80
            scheme == "https" -> 443
            else -> -1
        }
        return "$scheme://$host:$port"
    }

    /**
     * Video decoder order for IPTV, honouring the user's Playback setting.
     *
     * A frozen picture with running audio on live TV is the box's hardware
     * decoder mishandling the stream (MediaTek/Amlogic boxes are the usual
     * reports, and ExoPlayer issue #10369 is the same signature) — it can't
     * be fixed from the app, only routed around, which is why every IPTV
     * player exposes this switch. 'software' promotes Android's own software
     * codecs; the rejected decoders stay in the list as fallbacks because
     * setEnableDecoderFallback(true) can still reach them. Audio decoding and
     * every non-IPTV playback keep the platform's own order.
     */
    private fun iptvMediaCodecSelector(): MediaCodecSelector {
        return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            val infos = MediaCodecSelector.DEFAULT.getDecoderInfos(
                mimeType,
                requiresSecureDecoder,
                requiresTunnelingDecoder,
            )
            if (!isIptvMode || iptvDecoderMode == "auto" || !MimeTypes.isVideo(mimeType)) {
                infos
            } else {
                val preferSoftware = iptvDecoderMode == "software"
                val preferred = infos.filter { it.softwareOnly == preferSoftware }
                if (preferred.isEmpty()) {
                    infos
                } else {
                    preferred + infos.filterNot { it.softwareOnly == preferSoftware }
                }
            }
        }
    }

    private fun setupPlayer() {
        trackSelector = DefaultTrackSelector(this)

        // Get default language settings
        val defaultAudioLang = SubtitleSettings.getDefaultAudioLanguage(this)
        val defaultSubtitleLang = SubtitleSettings.getDefaultSubtitleLanguage(this)

        // Build track selector parameters with robust language matching
        val paramsBuilder = trackSelector?.buildUponParameters()
            ?.setPreferredAudioMimeType("audio/opus")
            ?.setIgnoredTextSelectionFlags(C.SELECTION_FLAG_DEFAULT)

        // Live IPTV: never adapt between video tracks in a way that forces a
        // codec reconfigure. That switch — not the stream itself — is where
        // strict decoders wedge into "frozen picture, audio still running"
        // (ExoPlayer #10369, an ABR switch on an Amlogic STB with no
        // MediaCodec error at all). Seamless adaptation within one codec
        // configuration is untouched, so multi-variant channels still adapt.
        if (isIptvMode) {
            paramsBuilder?.setAllowVideoNonSeamlessAdaptiveness(false)
        }

        // Apply audio language preference
        if (defaultAudioLang != null) {
            val audioVariants = LanguageMapper.getLanguageVariantsForExoPlayer(defaultAudioLang)
            if (audioVariants.isNotEmpty()) {
                paramsBuilder?.setPreferredAudioLanguages(*audioVariants.toTypedArray())
            } else {
                paramsBuilder?.setPreferredAudioLanguage(defaultAudioLang)
            }
        } else {
            // Default to English if no preference set
            val englishVariants = LanguageMapper.getLanguageVariantsForExoPlayer("en")
            paramsBuilder?.setPreferredAudioLanguages(*englishVariants.toTypedArray())
        }

        // Apply subtitle language preference
        when {
            defaultSubtitleLang == "off" -> {
                // Disable subtitle auto-selection by setting empty preferred language
                paramsBuilder?.setPreferredTextLanguage("")
            }
            defaultSubtitleLang != null -> {
                // Get all language variants (ISO 639-1, ISO 639-2, etc.) for robust matching
                val variants = LanguageMapper.getLanguageVariantsForExoPlayer(defaultSubtitleLang)
                if (variants.isNotEmpty()) {
                    paramsBuilder?.setPreferredTextLanguages(*variants.toTypedArray())
                } else {
                    paramsBuilder?.setPreferredTextLanguage(defaultSubtitleLang)
                }
            }
            else -> {
                // Default to English if no preference set
                val englishVariants = LanguageMapper.getLanguageVariantsForExoPlayer("en")
                paramsBuilder?.setPreferredTextLanguages(*englishVariants.toTypedArray())
            }
        }

        trackSelector?.parameters = paramsBuilder?.build()!!

        // Subtitle auto-sync's PCM tap rides the audio sink as a user
        // AudioProcessor: it sees every decoded sample the player plays, at
        // media rate (user processors sit before the speed processors), for
        // free. Created fresh per player build so a rebuild can't feed an old
        // tap. Passthrough audio bypasses processors entirely — the tap then
        // simply never fills and auto-sync declines instead of guessing.
        val tap = SpeechFeatureTap(
            mainPost = { action -> runOnUiThread(action) },
            positionMs = { player?.currentPosition ?: 0L },
        ).also { speechTap = it }
        val baseRenderersFactory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: android.content.Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): AudioSink {
                return DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(enableFloatOutput)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessorChain(
                        DefaultAudioSink.DefaultAudioProcessorChain(tap.processor)
                    )
                    .build()
            }
        }
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true)
            .setMediaCodecSelector(iptvMediaCodecSelector())
        val renderersFactory = OffsetRenderersFactory(baseRenderersFactory)
            .also { offsetRenderersFactory = it }

        // Create HTTP data source factory with redirect support for HLS/live streams.
        // The browser UA rides in defaultRequestProperties, NOT setUserAgent:
        // media3 applies the userAgent field LAST in makeConnection, silently
        // clobbering any per-request User-Agent — which would break IPTV
        // channels that declare their own UA (injected via the resolver's
        // dataSpec headers, which override defaults in the merge).
        // Connection patience preset: longer connect/read timeouts for slow
        // origins (Plex-backed addons can take >15s to first byte while the
        // upstream server wakes). VOD only — IPTV's resilience ladder depends
        // on failing fast enough to retry, so it keeps the stock 15s.
        val networkTimeoutMs = if (!isIptvMode) when (networkPatience) {
            "extended" -> 30_000
            "patient" -> 60_000
            else -> 15_000
        } else 15_000
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(networkTimeoutMs)
            .setReadTimeoutMs(networkTimeoutMs)
            .setDefaultRequestProperties(
                mapOf(
                    "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                )
            )

        // Wrap with DefaultDataSource.Factory for local file/content URI support
        val upstreamDataSourceFactory = DefaultDataSource.Factory(this, httpDataSourceFactory)
        val playbackHeaders = payload?.httpHeaders.orEmpty()
        val protectedMediaOrigins = buildProtectedMediaOrigins(payload?.items.orEmpty())
        val dataSourceFactory = if (playbackHeaders.isNotEmpty() && protectedMediaOrigins.isNotEmpty()) {
            android.util.Log.d(
                "AndroidTvPlayer",
                "setupPlayer - scoped ${playbackHeaders.size} HTTP header(s) to ${protectedMediaOrigins.size} media origin(s)"
            )
            ResolvingDataSource.Factory(
                upstreamDataSourceFactory,
                object : ResolvingDataSource.Resolver {
                    override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
                        val origin = originKey(dataSpec.uri)
                        return if (origin != null && protectedMediaOrigins.contains(origin)) {
                            dataSpec.withAdditionalHeaders(playbackHeaders)
                        } else {
                            dataSpec
                        }
                    }

                    override fun resolveReportedUri(uri: Uri): Uri = uri
                }
            )
        } else {
            upstreamDataSourceFactory
        }

        // IPTV: inject the CURRENT channel's declared headers into every
        // request (playlist + segments — CDNs enforce them on both). Read per
        // request so channel zaps just update [currentIptvHttpHeaders]; the
        // factory-level Chrome UA still applies when a channel names no UA.
        // (Channel UA keys are canonicalized to "User-Agent" at parse time,
        // so the dataSpec entry deterministically replaces the default.)
        val finalDataSourceFactory = if (isIptvMode) {
            ResolvingDataSource.Factory(
                dataSourceFactory,
                object : ResolvingDataSource.Resolver {
                    override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
                        val headers = currentIptvHttpHeaders
                        return if (headers.isEmpty()) dataSpec
                        else dataSpec.withAdditionalHeaders(headers)
                    }

                    override fun resolveReportedUri(uri: Uri): Uri = uri
                }
            )
        } else {
            dataSourceFactory
        }

        // IPTV: tee the played bytes to a recording file on demand. Inert unless
        // the user starts a recording (see IptvRecordingController); wraps the
        // fully-resolved factory so recorded bytes carry the channel's headers.
        val recordingDataSourceFactory = if (isIptvMode) {
            // A write error (disk full, row revoked) ends the recording on the
            // loader thread; without this the dock would keep saying "Stop".
            iptvRecordingController.onAborted = {
                updateRecordButtonState()
                Toast.makeText(
                    this,
                    "Recording stopped — couldn't keep writing to storage",
                    Toast.LENGTH_LONG,
                ).show()
            }
            RecordingDataSource.Factory(finalDataSourceFactory, iptvRecordingController)
        } else {
            finalDataSourceFactory
        }

        // Create media source factory that uses the data source. IPTV gets
        // two live-stream aids on top:
        //  - TS extractor flags (Phase 3 of the resilience plan, marked
        //    experimental there): ALLOW_NON_IDR_KEYFRAMES lets a mid-GOP
        //    live join render before the next IDR arrives (broadcast streams
        //    can go seconds between them), DETECT_ACCESS_UNITS lets H.264
        //    parse when the container lies about access-unit boundaries.
        //    Both are what dedicated IPTV players run with.
        //  - the classified load-error policy (Phase 1): loader-level retries
        //    UNDER an intact buffer for transient errors, so the common
        //    connection drop heals without the player ever leaving READY.
        val mediaSourceFactory = if (isIptvMode) {
            val aggressiveTs = DefaultExtractorsFactory().setTsExtractorFlags(
                DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or
                    DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
            )
            // The fallback the video-stall detector escalates to (see
            // performIptvLiveRetune): stock demux — IDR-only sync points —
            // for channels whose decoder wedges on mid-GOP joins. This is
            // the pre-0.8.1 behavior, and what the browse screen's preview
            // player runs with everywhere (which is why the same channel
            // plays fine in the two-pane stage on those boxes).
            val strictTs = DefaultExtractorsFactory()
            val iptvExtractors = object : ExtractorsFactory {
                override fun createExtractors(): Array<Extractor> =
                    (if (iptvStrictTsActive) strictTs else aggressiveTs)
                        .createExtractors()

                override fun createExtractors(
                    uri: Uri,
                    responseHeaders: Map<String, List<String>>,
                ): Array<Extractor> =
                    (if (iptvStrictTsActive) strictTs else aggressiveTs)
                        .createExtractors(uri, responseHeaders)
            }
            DefaultMediaSourceFactory(this, iptvExtractors)
                .setDataSourceFactory(recordingDataSourceFactory)
                .setLoadErrorHandlingPolicy(IptvLiveLoadErrorPolicy())
        } else {
            DefaultMediaSourceFactory(this)
                .setDataSourceFactory(recordingDataSourceFactory)
        }

        val playerBuilder = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector!!)
            .setMediaSourceFactory(mediaSourceFactory)
            .setHandleAudioBecomingNoisy(true)
            // Hold CPU + Wi-Fi while playing over the network: TV boxes with
            // aggressive Wi-Fi power-save can starve a live stream without
            // this (downloads and recordings already take their own locks —
            // playback was the only network consumer without one).
            .setWakeMode(C.WAKE_MODE_NETWORK)

        // IPTV buffering: media3 1.8.0's stock DefaultLoadControl already
        // resumes 2s after a rebuffer (the plan's audit assumed the old 5s
        // default — codex review round 2 corrected it against the 1.8.0
        // constants). Stock is the right call: no override.

        // For YouTube (merged video-only + audio) ONLY, start after buffering
        // ~1s instead of ExoPlayer's conservative 2.5s default — otherwise the
        // two separate googlevideo streams take 20-30s to fill the buffer before
        // the first frame. All other content keeps ExoPlayer's defaults so this
        // can't regress torrent/IPTV/debrid playback.
        val isYouTubeMerge = payload?.items?.any {
            !it.hdVideoUrl.isNullOrEmpty() && !it.audioUrl.isNullOrEmpty()
        } == true
        if (isYouTubeMerge) {
            playerBuilder.setLoadControl(
                DefaultLoadControl.Builder()
                    .setBufferDurationsMs(
                        15_000, // minBufferMs (default 50000)
                        50_000, // maxBufferMs (default 50000)
                        1_000,  // bufferForPlaybackMs (default 2500)
                        2_000,  // bufferForPlaybackAfterRebufferMs (default 5000)
                    )
                    .setPrioritizeTimeOverSizeThresholds(true)
                    .build()
            )
        } else if (!isIptvMode && networkBuffer != "standard") {
            // Stream buffer preset: wider read-ahead rides over origin
            // stalls. Start thresholds stay stock (only min/max grow), so
            // start latency is unchanged; the byte target is the real memory
            // guard (mirrors the mpv side's demuxer-max-bytes) — loading
            // stops at whichever target hits first, exactly like stock.
            val hugeBuffer = networkBuffer == "huge"
            // Unlike mpv's native-memory demuxer cache, this target is JAVA
            // heap (DefaultAllocator's byte[] segments) shared with the
            // Flutter engine, image caches, and every profile/guide
            // structure in this process. The original clamp — HALF the
            // large-heap class — was a ceiling, not headroom: on a 256
            // MiB-class TV box a high-bitrate stream drove the allocator to
            // 128 MiB of live byte[] and the loader thread died with
            // OutOfMemoryError, an Error no player plumbing catches →
            // process death straight to the launcher, on exactly the
            // hardware this preset serves (Mecool KM2+ field report,
            // 2026-08-18: one high-bitrate episode "crashes the app", every
            // source). Budget a QUARTER of the heap instead, cap the
            // requests well below the old 256/512 MiB, and when even the
            // quarter is too small to be worth overriding, keep stock —
            // stock's own byte targets are what the device already
            // survives. Long math throughout: largeMemoryClass is an Int MB
            // count, and `mb / 2 * 1024 * 1024` overflows Int from a 4
            // GiB heap class up.
            val activityManager =
                getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            val heapBudgetBytes =
                activityManager.largeMemoryClass.toLong() * 1024L * 1024L / 4L
            val requestedBytes = (if (hugeBuffer) 192L else 96L) * 1024L * 1024L
            val targetBytes = minOf(requestedBytes, heapBudgetBytes)
            if (targetBytes >= 48L * 1024L * 1024L) {
                playerBuilder.setLoadControl(
                    DefaultLoadControl.Builder()
                        .setBufferDurationsMs(
                            if (hugeBuffer) 300_000 else 120_000, // minBufferMs
                            if (hugeBuffer) 300_000 else 120_000, // maxBufferMs
                            DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                            DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
                        )
                        .setTargetBufferBytes(targetBytes.toInt())
                        .build()
                )
            }
        }

        player = playerBuilder.build()

        player?.addListener(playbackListener)
        player?.addAnalyticsListener(decoderAnalyticsListener)
        player?.addAnalyticsListener(iptvDiagAnalyticsListener)
        playerView.player = player

        // Hide internal subtitle view, use custom one
        playerView.subtitleView?.visibility = View.GONE

        // Connect subtitle output to custom view
        subtitleListener = object : Player.Listener {
            override fun onCues(cueGroup: androidx.media3.common.text.CueGroup) {
                // While an external subtitle is side-rendered, the overlay is
                // owned by the ticker — ignore the player's (empty) cue events.
                if (externalSubtitleActive) return
                subtitleOverlay.setCues(cueGroup.cues)
            }
        }
        player?.addListener(subtitleListener!!)

        // Setup subtitle styling from saved preferences
        subtitleOverlay.setApplyEmbeddedStyles(false)
        subtitleOverlay.setApplyEmbeddedFontSizes(false)
        SubtitleSettings.synchronizeProjectedAppearance(this)
        SubtitleFontManager.synchronizeProjectedFont(this)
        // The sync offset is per-subtitle and in-memory: start this session at 0
        // and let SubtitleSettings scope it to whatever subtitle is on screen.
        SubtitleSettings.resetSyncOffset()
        SubtitleSettings.setActiveSubtitleIdentityProvider(this) { currentSubtitleIdentity() }
        applySubtitleSettings()

        playerView.setControllerAutoShow(false)
        applyResizeMode()
        playerView.requestFocus()

        if (isIptvMode) {
            // Phase 3: hold the last frame across a zap's player reset — the
            // zap banner rides over the old channel's picture instead of a
            // black flash. Cleared on surrender (a dead channel must not
            // keep painting under the failure pill) and re-armed on READY.
            playerView.setKeepContentOnPlayerReset(true)

            // Phase 1: connectivity gate for the recovery ladder. While the
            // OS reports no network there is nothing to hammer; the moment a
            // network validates, the parked attempt fires immediately.
            // API 24+ only (registerDefaultNetworkCallback); older boxes
            // just keep the plain timed ladder.
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        runOnUiThread { iptvLiveRecovery.setOffline(false) }
                    }

                    override fun onLost(network: Network) {
                        runOnUiThread { iptvLiveRecovery.setOffline(true) }
                    }
                }
                try {
                    cm.registerDefaultNetworkCallback(callback)
                    iptvNetworkCallback = callback
                    // Cold-start truth: registration alone reports nothing
                    // until the network CHANGES — launched offline, the
                    // ladder must know now, not at the first handover.
                    iptvLiveRecovery.setOffline(cm.activeNetwork == null)
                } catch (e: Exception) {
                    // Some ROMs throw on registration limits; the ladder
                    // works without the gate, just less politely offline.
                    android.util.Log.w("AndroidTvPlayer", "network callback: $e")
                }
            }
        }
    }

    private fun setupSeekbar() {
        seekbarOverlay.visibility = View.GONE
        seekbarOverlay.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
                hideSeekbar()
                return@setOnKeyListener true
            }
            false
        }
    }

    private fun setupPlaylist() {
        // Configure RecyclerView for optimal focus handling
        playlistView.layoutManager = LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false).apply {
            // Pre-fetch items for smoother scrolling
            isItemPrefetchEnabled = true
            initialPrefetchItemCount = 4
        }

        // Disable item animator to prevent focus issues during view animations
        playlistView.itemAnimator = null

        // Keep more views in memory to reduce recycling-related focus issues
        playlistView.setItemViewCacheSize(10)

        // Ensure children can receive focus
        playlistView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS

        // Add focus recovery listener for view recycling (with delay to prevent interference with navigation)
        playlistView.addOnChildAttachStateChangeListener(object : RecyclerView.OnChildAttachStateChangeListener {
            override fun onChildViewAttachedToWindow(view: View) {
                // Don't interfere during active navigation
                if (isNavigating) {
                    android.util.Log.d("PlaylistNav", "onChildViewAttached: Skipping - navigation in progress")
                    return
                }

                // Only consider recovery if playlist is visible and view is focusable
                if (playlistVisible && view.isFocusable) {
                    // Cancel any pending recovery
                    focusRecoveryRunnable?.let { focusRecoveryHandler.removeCallbacks(it) }

                    // Schedule focus check with delay to let transitions complete
                    focusRecoveryRunnable = Runnable {
                        // Double-check focus is actually lost after delay
                        if (playlistVisible && !isNavigating &&
                            !playlistView.hasFocus() &&
                            playlistView.focusedChild == null) {
                            android.util.Log.d("PlaylistNav", "onChildViewAttached: Recovering focus after delay")
                            ensureFocusInPlaylist()
                        }
                    }
                    // 100ms delay to let focus transitions complete
                    focusRecoveryHandler.postDelayed(focusRecoveryRunnable!!, 100)
                }
            }

            override fun onChildViewDetachedFromWindow(view: View) {
                // Only recover if the detached view had focus AND we're not navigating
                if (view.hasFocus() && playlistVisible && !isNavigating) {
                    android.util.Log.d("PlaylistNav", "Focused view being detached, scheduling recovery")

                    // Cancel any pending recovery
                    focusRecoveryRunnable?.let { focusRecoveryHandler.removeCallbacks(it) }

                    // Schedule recovery with delay
                    focusRecoveryRunnable = Runnable {
                        if (playlistVisible && !isNavigating &&
                            !playlistView.hasFocus() &&
                            playlistView.focusedChild == null) {
                            android.util.Log.d("PlaylistNav", "onChildViewDetached: Recovering focus after delay")
                            ensureFocusInPlaylist()
                        }
                    }
                    focusRecoveryHandler.postDelayed(focusRecoveryRunnable!!, 100)
                }
            }
        })

        playlistOverlay.visibility = View.GONE

        rebuildPlaylistContent()
    }

    /** Rebuilds playlist adapters, tabs, and mode from current payload items. Safe to call multiple times. */
    private fun rebuildPlaylistContent() {
        val model = payload ?: return
        val items = model.items
        movieTabs.clear()
        seasonTabs.clear()
        seasonTabsContainer.removeAllViews()
        seriesPlaylistAdapter = null
        moviePlaylistAdapter = null
        playlistAdapter = null
        movieGroups = null
        playlistMode = PlaylistMode.NONE

        if (items.size <= 1) {
            // Single stream: with a full-show guide + a playlist resolver the
            // series overlay still renders (absent rows fetch in-player),
            // matching the Flutter player's synthetic guide.
            val guideCapable = hasPlaylistResolver &&
                model.contentType.lowercase(Locale.US) == "series" &&
                model.guideEpisodes.isNotEmpty()
            if (!guideCapable) {
                playlistView.adapter = null
                seasonTabsContainer.visibility = View.GONE
                return
            }
        }

        when (model.contentType.lowercase(Locale.US)) {
            "series" -> setupSeriesPlaylist(items)
            else -> setupCollectionPlaylist(items)
        }

        setupPlaylistNavigation()
    }

    private fun setupSeriesPlaylist(items: List<PlaybackItem>) {
        // Full-guide mode only when absent rows can actually be fetched.
        val guide = if (hasPlaylistResolver) {
            payload?.guideEpisodes ?: emptyList()
        } else {
            emptyList()
        }
        val adapter = PlaylistAdapter(
            items,
            guide = guide,
            onFetchEpisode = if (guide.isEmpty()) null else { season, episode ->
                hidePlaylist()
                requestEpisodeFetch(season, episode)
            },
        ) { index ->
            hidePlaylist()
            playItem(index)
        }
        playlistView.adapter = adapter
        playlistAdapter = adapter
        seriesPlaylistAdapter = adapter
        moviePlaylistAdapter = null
        playlistMode = PlaylistMode.SERIES
        setupSeasonTabs(adapter)
    }

    private fun setupCollectionPlaylist(items: List<PlaybackItem>) {
        val groups = computeMovieGroups(items)
        val adapter = MoviePlaylistAdapter(items, groups) { index ->
            hidePlaylist()
            playItem(index)
        }
        playlistView.adapter = adapter
        playlistAdapter = adapter
        moviePlaylistAdapter = adapter
        seriesPlaylistAdapter = null
        movieGroups = groups
        playlistMode = PlaylistMode.COLLECTION
        setupCollectionTabs(adapter, groups)
    }

    private fun setupSeasonTabs(adapter: PlaylistAdapter) {
        seasonTabsContainer.removeAllViews()
        seasonTabs.clear()

        val seasons = adapter.availableSeasons
        if (seasons.isEmpty()) {
            seasonTabsContainer.visibility = View.GONE
            return
        }

        seasonTabsContainer.visibility = View.VISIBLE

        // Add season tabs
        for (season in seasons) {
            val tab = createSeasonTab("S$season", season, adapter)
            seasonTabsContainer.addView(tab)
            seasonTabs.add(tab)
        }

        // Default to the season of the currently playing episode
        val currentSeason = payload?.items?.getOrNull(currentIndex)?.season
        val defaultTabIndex = if (currentSeason != null) {
            seasons.indexOf(currentSeason).takeIf { it >= 0 } ?: 0
        } else {
            0
        }

        if (seasonTabs.isNotEmpty()) {
            selectSeasonTab(defaultTabIndex, adapter)
        }
    }

    private fun createSeasonTab(label: String, season: Int?, adapter: PlaylistAdapter): TextView {
        val tab = TextView(this)
        tab.text = label
        tab.textSize = 13f
        tab.setTextColor(0xFFFFFFFF.toInt())
        tab.setPadding(28, 14, 28, 14)
        tab.setBackgroundResource(R.drawable.season_tab_selector)
        tab.isFocusable = true
        tab.isFocusableInTouchMode = true
        tab.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD)
        tab.letterSpacing = 0.04f
        tab.elevation = 4f

        val params = android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.marginEnd = 10
        tab.layoutParams = params

        tab.setOnClickListener {
            val index = seasonTabs.indexOf(tab)
            if (index != -1) {
                selectSeasonTab(index, adapter)
            }
        }

        return tab
    }

    private fun selectSeasonTab(index: Int, adapter: PlaylistAdapter, scrollToTop: Boolean = true) {
        // Update tab selection states
        seasonTabs.forEachIndexed { i, tab ->
            tab.isSelected = (i == index)
        }

        // Filter adapter to the selected season
        val season = adapter.availableSeasons.getOrNull(index)
        adapter.filterBySeason(season)

        // Scroll to top (unless explicitly disabled)
        if (scrollToTop) {
            playlistView.scrollToPosition(0)
        }
    }

    private fun setupCollectionTabs(adapter: MoviePlaylistAdapter, groups: MovieGroups) {
        seasonTabs.clear()
        movieTabs.clear()
        seasonTabsContainer.removeAllViews()

        if (groups.groups.isEmpty()) {
            seasonTabsContainer.visibility = View.GONE
            return
        }

        if (groups.groups.size <= 1) {
            seasonTabsContainer.visibility = View.GONE
            // Ensure adapter still shows first group
            adapter.showGroup(0, force = true)
            return
        }

        seasonTabsContainer.visibility = View.VISIBLE

        groups.groups.forEachIndexed { index, group ->
            val label = "${group.name.uppercase()} (${group.fileIndices.size})"
            val tab = createMovieTab(label, index, group.name, adapter)
            seasonTabsContainer.addView(tab)
            movieTabs.add(MovieTab(tab, index, group.name))
        }

        selectMovieTab(0, adapter, scrollToTop = false, forceAdapterUpdate = true)
    }

    private fun setupPlaylistNavigation() {
        android.util.Log.d("PlaylistNav", "setupPlaylistNavigation: Setting up navigation")

        // Trap LEFT/RIGHT focus inside RecyclerView, but allow UP/DOWN for season tabs
        playlistView.setOnKeyListener { view, keyCode, event ->
            if (!playlistVisible) {
                android.util.Log.d("PlaylistNav", "Key event but playlist not visible: keyCode=$keyCode")
                return@setOnKeyListener false
            }

            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        // Simple delegation - movePlaylistFocus handles all logic including boundaries
                        android.util.Log.d("PlaylistNav", "DPAD_RIGHT pressed")
                        movePlaylistFocus(1)
                        true  // Always consume to prevent focus escape
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        // Simple delegation - movePlaylistFocus handles all logic including boundaries
                        android.util.Log.d("PlaylistNav", "DPAD_LEFT pressed")
                        movePlaylistFocus(-1)
                        true  // Always consume to prevent focus escape
                    }
                    KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> {
                        android.util.Log.d("PlaylistNav", "UP/DOWN pressed - allowing navigation to season tabs")
                        false  // Allow UP/DOWN to navigate to season tabs
                    }
                    else -> false
                }
            } else {
                false
            }
        }

        // Add global focus change listener for debugging
        playlistView.viewTreeObserver.addOnGlobalFocusChangeListener { oldFocus, newFocus ->
            if (playlistVisible) {
                val oldPos = if (oldFocus != null && oldFocus.parent == playlistView) {
                    playlistView.getChildAdapterPosition(oldFocus)
                } else {
                    -1
                }
                val newPos = if (newFocus != null && newFocus.parent == playlistView) {
                    playlistView.getChildAdapterPosition(newFocus)
                } else {
                    -1
                }
                android.util.Log.d("PlaylistNav", "Focus changed: oldPos=$oldPos -> newPos=$newPos, newFocus=$newFocus")
                // Note: Removed focus escape recovery - LEFT/RIGHT trapping prevents unintended escapes,
                // and we want to allow intentional UP/DOWN navigation to season tabs
            }
        }
    }

    /**
     * Find the next focusable position starting from a given position, moving in the specified direction.
     * Skips over non-focusable items like SeasonHeaders (for series playlists).
     * Works for both series and collection/movie playlists.
     *
     * @param startPosition The position to start searching from (inclusive)
     * @param direction 1 for forward, -1 for backward
     * @return The next focusable position, or RecyclerView.NO_POSITION if none found
     */
    private fun findNextFocusablePosition(startPosition: Int, direction: Int): Int {
        // Handle series playlist (has SeasonHeaders to skip)
        val seriesAdapter = seriesPlaylistAdapter
        if (seriesAdapter != null) {
            val itemCount = seriesAdapter.itemCount
            var position = startPosition
            while (position in 0 until itemCount) {
                // Check if this position is an Episode (focusable), not a Header
                if (seriesAdapter.getItemViewType(position) == 1) { // VIEW_TYPE_EPISODE = 1
                    return position
                }
                position += direction
            }
            return RecyclerView.NO_POSITION
        }

        // Handle collection/movie playlist (all items are focusable - no headers)
        val movieAdapter = moviePlaylistAdapter
        if (movieAdapter != null) {
            val itemCount = movieAdapter.itemCount
            // All items in movie playlist are focusable, just check bounds
            if (startPosition in 0 until itemCount) {
                return startPosition
            }
            return RecyclerView.NO_POSITION
        }

        // No playlist adapter available
        return RecyclerView.NO_POSITION
    }

    /**
     * Ensure focus remains within the playlist when it should be visible.
     * Called when focus might be lost due to view recycling or other issues.
     */
    private fun ensureFocusInPlaylist() {
        // Don't interfere during active navigation
        if (!playlistVisible || isNavigating) return

        // Check if any child of playlistView currently has focus
        val hasFocus = playlistView.hasFocus() || playlistView.focusedChild != null
        if (hasFocus) return

        android.util.Log.d("PlaylistNav", "ensureFocusInPlaylist: Focus lost, recovering...")

        val layoutManager = playlistView.layoutManager as? LinearLayoutManager ?: return
        val firstVisible = layoutManager.findFirstVisibleItemPosition()
        val lastVisible = layoutManager.findLastVisibleItemPosition()

        if (firstVisible == RecyclerView.NO_POSITION) return

        // If we have a recent navigation target in visible range, prefer that
        if (navigationTargetPosition in firstVisible..lastVisible) {
            val holder = playlistView.findViewHolderForAdapterPosition(navigationTargetPosition)
            if (holder?.itemView != null && holder.itemView.isFocusable) {
                android.util.Log.d("PlaylistNav", "ensureFocusInPlaylist: Focusing recent target at $navigationTargetPosition")
                holder.itemView.requestFocus()
                return
            }
        }

        // Find the middle item in the visible range (not the first)
        // This prevents always jumping back to the beginning
        val middlePosition = (firstVisible + lastVisible) / 2

        // Search outward from the middle
        for (offset in 0..(lastVisible - firstVisible)) {
            val positions = listOf(middlePosition + offset, middlePosition - offset)
            for (pos in positions) {
                if (pos in firstVisible..lastVisible) {
                    val nextFocusable = findNextFocusablePosition(pos, 1)
                    if (nextFocusable in firstVisible..lastVisible) {
                        val holder = playlistView.findViewHolderForAdapterPosition(nextFocusable)
                        if (holder != null && holder.itemView.isFocusable) {
                            android.util.Log.d("PlaylistNav", "ensureFocusInPlaylist: Recovering focus to position $nextFocusable (middle-out)")
                            holder.itemView.requestFocus()
                            return
                        }
                    }
                }
            }
        }
    }

    /**
     * Transfer focus to a specific position using ViewTreeObserver for reliable timing.
     * This ensures layout is complete before attempting to focus.
     */
    private fun transferFocusToPosition(targetPosition: Int) {
        val layoutManager = playlistView.layoutManager as? LinearLayoutManager ?: run {
            isNavigating = false
            return
        }

        android.util.Log.d("PlaylistNav", "transferFocusToPosition: target=$targetPosition")

        // Keep navigation flag active and track target
        isNavigating = true
        navigationTargetPosition = targetPosition

        // Scroll to position with some offset for visual comfort
        layoutManager.scrollToPositionWithOffset(targetPosition, 100)

        // Use ViewTreeObserver for reliable timing instead of nested posts
        playlistView.viewTreeObserver.addOnGlobalLayoutListener(object : android.view.ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                playlistView.viewTreeObserver.removeOnGlobalLayoutListener(this)

                val holder = playlistView.findViewHolderForAdapterPosition(targetPosition)
                if (holder?.itemView != null && holder.itemView.isFocusable) {
                    android.util.Log.d("PlaylistNav", "transferFocusToPosition: Focusing target at $targetPosition")
                    val focused = holder.itemView.requestFocus()
                    android.util.Log.d("PlaylistNav", "transferFocusToPosition: Focus result=$focused for position $targetPosition")

                    // Clear navigation flag after a short delay to let focus settle
                    playlistView.postDelayed({
                        isNavigating = false
                        navigationTargetPosition = -1
                    }, 50)

                    if (!focused) {
                        // Focus failed, try once more after a short delay
                        playlistView.postDelayed({
                            playlistView.findViewHolderForAdapterPosition(targetPosition)?.itemView?.requestFocus()
                            isNavigating = false
                            navigationTargetPosition = -1
                        }, 50)
                    }
                } else {
                    android.util.Log.d("PlaylistNav", "transferFocusToPosition: Holder not found or not focusable, using fallback")
                    // Clear navigation state before fallback
                    isNavigating = false
                    navigationTargetPosition = -1
                    ensureFocusInPlaylist()
                }
            }
        })
    }

    private fun movePlaylistFocus(delta: Int) {
        android.util.Log.d("PlaylistNav", "movePlaylistFocus: delta=$delta")

        // Set navigation flag to prevent focus recovery from interfering
        isNavigating = true

        val adapter = playlistView.adapter ?: run {
            isNavigating = false
            navigationTargetPosition = -1
            return
        }
        val layoutManager = playlistView.layoutManager as? LinearLayoutManager ?: run {
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Use navigationTargetPosition if we're in the middle of rapid navigation
        // This prevents stutter like 3 → 4 → 4 → 5 when pressing keys quickly
        val currentPosition = if (navigationTargetPosition >= 0) {
            // We have an ongoing navigation, use target as current position
            navigationTargetPosition
        } else {
            // Normal case: get from focused child
            val focusedChild = playlistView.focusedChild
            if (focusedChild != null) {
                playlistView.getChildAdapterPosition(focusedChild)
            } else {
                layoutManager.findFirstVisibleItemPosition()
            }
        }

        android.util.Log.d("PlaylistNav", "movePlaylistFocus: currentPosition=$currentPosition, navTarget=$navigationTargetPosition")
        if (currentPosition == RecyclerView.NO_POSITION) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: NO_POSITION, aborting")
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Boundary checks - stop at start/end
        val itemCount = adapter.itemCount
        if (delta > 0 && currentPosition >= itemCount - 1) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Already at end, ignoring")
            isNavigating = false
            navigationTargetPosition = -1
            return
        } else if (delta < 0 && currentPosition <= 0) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Already at start, ignoring")
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Find the next focusable position (skipping headers)
        val searchStart = currentPosition + delta
        val targetPosition = findNextFocusablePosition(searchStart, delta)

        android.util.Log.d("PlaylistNav", "movePlaylistFocus: searchStart=$searchStart, targetPosition=$targetPosition")

        if (targetPosition == RecyclerView.NO_POSITION || targetPosition == currentPosition) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: No valid target found or same position")
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Track the target position for rapid navigation support
        navigationTargetPosition = targetPosition

        // Check if target is already visible and can be focused directly
        val targetHolder = playlistView.findViewHolderForAdapterPosition(targetPosition)
        if (targetHolder != null && targetHolder.itemView.parent != null && targetHolder.itemView.isFocusable) {
            // Item is visible and focusable, focus it directly
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Target visible, focusing directly")
            val focused = targetHolder.itemView.requestFocus()
            // Clear navigation flag after short delay to let focus settle
            // Keep navigationTargetPosition for rapid key presses, clear later
            playlistView.postDelayed({
                isNavigating = false
                navigationTargetPosition = -1
            }, 100)  // Increased to 100ms for better rapid press handling
            if (!focused) {
                // Direct focus failed, use transfer method
                transferFocusToPosition(targetPosition)
            }
        } else {
            // Item is not visible or not ready, use reliable transfer method
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Target not visible, using transferFocusToPosition")
            transferFocusToPosition(targetPosition)
        }
    }

    private fun createMovieTab(label: String, groupIndex: Int, groupName: String, adapter: MoviePlaylistAdapter): TextView {
        val tab = TextView(this)
        tab.text = label
        tab.textSize = 13f
        tab.setTextColor(0xFFFFFFFF.toInt())
        tab.setPadding(28, 14, 28, 14)
        tab.setBackgroundResource(R.drawable.season_tab_selector)
        tab.isFocusable = true
        tab.isFocusableInTouchMode = true
        tab.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD)
        tab.letterSpacing = 0.04f
        tab.elevation = 4f

        val params = android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.marginEnd = 10
        tab.layoutParams = params

        tab.setOnClickListener {
            selectMovieTab(groupIndex, adapter)
        }

        return tab
    }

    private fun selectMovieTab(
        groupIndex: Int,
        adapter: MoviePlaylistAdapter,
        scrollToTop: Boolean = true,
        forceAdapterUpdate: Boolean = false,
    ) {
        movieTabs.forEach { movieTab ->
            movieTab.view.isSelected = movieTab.groupIndex == groupIndex
        }
        val changed = adapter.showGroup(groupIndex, force = forceAdapterUpdate)
        if ((scrollToTop || changed) && adapter.itemCount > 0) {
            playlistView.scrollToPosition(0)
        }
    }

    private fun setupControls() {
        controlsOverlay = playerView.findViewById(R.id.debrify_controls_root)
        pauseButton = playerView.findViewById(R.id.debrify_pause_button)
        nightModeButton = playerView.findViewById(R.id.debrify_night_mode_button)
        audioButton = playerView.findViewById(R.id.debrify_audio_button)
        subtitleButton = playerView.findViewById(R.id.debrify_subtitle_button)
        aspectButton = playerView.findViewById(R.id.debrify_aspect_button)
        speedButton = playerView.findViewById(R.id.debrify_speed_button)
        val playlistButton: AppCompatButton? = playerView.findViewById(R.id.debrify_playlist_button)
        val nextButton: AppCompatButton? = playerView.findViewById(R.id.debrify_next_button)
        val prevButton: AppCompatButton? = playerView.findViewById(R.id.debrify_prev_button)
        val randomButton: AppCompatButton? = playerView.findViewById(R.id.debrify_random_button)
        iptvNextButton = nextButton
        iptvPrevButton = prevButton
        iptvGuideButton = playlistButton
        iptvJumpButton = playerView.findViewById(R.id.iptv_jump_channel_button)
        iptvRecordButton = playerView.findViewById(R.id.iptv_record_button)
        playerView.findViewById<LinearLayout>(R.id.debrify_controls_buttons)?.let { dock ->
            if (originalControlDockOrder.isEmpty()) {
                originalControlDockOrder =
                    List(dock.childCount) { index -> dock.getChildAt(index) }
            }
        }

        // Time display views (Cinema Mode)
        debrifyTimeDisplay = playerView.findViewById(R.id.debrify_time_display)  // Legacy (hidden)
        debrifyTimeCurrent = playerView.findViewById(R.id.debrify_time_current)  // Current time
        debrifyTimeTotal = playerView.findViewById(R.id.debrify_time_total)      // Total time
        debrifyProgressLine = playerView.findViewById(R.id.debrify_progress_line)
        cinemaProgressBuffered = playerView.findViewById(R.id.cinema_progress_buffered)

        // Cinema Mode Interactive Progress Bar
        cinemaProgressContainer = playerView.findViewById(R.id.cinema_progress_container)
        cinemaProgressBackground = playerView.findViewById(R.id.cinema_progress_background)
        cinemaProgressThumb = playerView.findViewById(R.id.cinema_progress_thumb)
        cinemaSpeedIndicator = playerView.findViewById(R.id.cinema_speed_indicator)
        setupCinemaProgressBar()

        controlsOverlay?.visibility = View.GONE
        controlsOverlay?.alpha = 0f

        // Start updating time display
        startSeekbarProgressUpdates()

        // Apple TV-style focus animation with scale effect
        val applyAppleTvAnimation = { view: View? ->
            view?.onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
                if (hasFocus) {
                    // Scale up with premium smooth animation when focused
                    v.animate()
                        .scaleX(1.12f)
                        .scaleY(1.12f)
                        .translationZ(8f)
                        .setDuration(200)
                        .setInterpolator(android.view.animation.DecelerateInterpolator())
                        .start()
                    // Extend timer when focused
                    if (controlsMenuVisible) {
                        scheduleHideControlsMenu()
                    }
                } else {
                    // Scale back to normal smoothly
                    v.animate()
                        .scaleX(1.0f)
                        .scaleY(1.0f)
                        .translationZ(2f)
                        .setDuration(200)
                        .setInterpolator(android.view.animation.AccelerateInterpolator())
                        .start()
                }
            }
        }

        // Apply Apple TV animations to all control buttons
        applyAppleTvAnimation(pauseButton)
        applyAppleTvAnimation(nightModeButton)
        applyAppleTvAnimation(audioButton)
        applyAppleTvAnimation(subtitleButton)
        applyAppleTvAnimation(aspectButton)
        applyAppleTvAnimation(speedButton)
        applyAppleTvAnimation(playlistButton)
        applyAppleTvAnimation(nextButton)
        applyAppleTvAnimation(prevButton)
        applyAppleTvAnimation(randomButton)
        applyAppleTvAnimation(iptvJumpButton)

        val extendTimerOnFocus = View.OnFocusChangeListener { _, hasFocus ->
            if (hasFocus && controlsMenuVisible) {
                scheduleHideControlsMenu()
            }
        }

        pauseButton?.setOnClickListener {
            togglePlayPause()
            if (player?.isPlaying == true) {
                scheduleHideControlsMenu()
            } else {
                cancelScheduledHideControlsMenu()
            }
        }
        pauseButton?.onFocusChangeListener = extendTimerOnFocus

        nightModeButton?.setOnClickListener {
            if (USE_UNIFIED_MENU && unifiedMenu != null) {
                hideControlsMenu(); unifiedMenu?.show("audio", "night")
            } else {
                showNightModeDialog()
            }
        }
        nightModeButton?.onFocusChangeListener = extendTimerOnFocus
        updateNightModeButtonLabel()

        iptvJumpButton?.setOnClickListener {
            hideControlsMenu()
            showIptvChannelJumpDialog()
        }
        iptvJumpButton?.onFocusChangeListener = extendTimerOnFocus

        audioButton?.setOnClickListener {
            if (USE_UNIFIED_MENU && unifiedMenu != null) {
                hideControlsMenu(); unifiedMenu?.show("audio")
            } else {
                showAudioTrackDialog()
                scheduleHideControlsMenu()
            }
        }
        audioButton?.onFocusChangeListener = extendTimerOnFocus

        subtitleButton?.setOnClickListener {
            hideControlsMenu()
            if (USE_UNIFIED_MENU && unifiedMenu != null) {
                unifiedMenu?.show("subs")
            } else {
                showSubtitleSettingsPanel()
            }
        }
        subtitleButton?.onFocusChangeListener = extendTimerOnFocus

        // Aspect is a 3-value cycle — apply it right from the controls bar
        // (with its toast feedback) instead of routing through the menu.
        aspectButton?.setOnClickListener {
            cycleAspectRatio()
            scheduleHideControlsMenu()
        }
        aspectButton?.onFocusChangeListener = extendTimerOnFocus
        updateAspectButtonLabel()

        speedButton?.setOnClickListener {
            if (USE_UNIFIED_MENU && unifiedMenu != null) {
                hideControlsMenu(); unifiedMenu?.show("playback", "speed")
            } else {
                cyclePlaybackSpeed()
                scheduleHideControlsMenu()
            }
        }
        speedButton?.onFocusChangeListener = extendTimerOnFocus

        playlistButton?.setOnClickListener {
            hideControlsMenu()
            showPlaylist()
        }
        playlistButton?.onFocusChangeListener = extendTimerOnFocus

        nextButton?.setOnClickListener {
            hideControlsMenu()
            // In an IPTV episode list, walk the season; otherwise the playlist.
            val iptvNext = nextIptvEpisode()
            if (iptvNext != null) switchToIptvChannel(iptvNext) else playNext()
        }
        nextButton?.onFocusChangeListener = extendTimerOnFocus

        // Previous episode: IPTV walks its episode list; catalog series use the
        // current playlist first, then fetch across its boundary from the full
        // guide without leaving the native player.
        prevButton?.setOnClickListener {
            hideControlsMenu()
            if (isIptvMode) {
                prevIptvEpisode()?.let { switchToIptvChannel(it) }
            } else {
                playPrevious()
            }
        }
        prevButton?.onFocusChangeListener = extendTimerOnFocus
        updateCatalogEpisodeControls()

        randomButton?.setOnClickListener {
            hideControlsMenu()
            if (USE_UNIFIED_MENU && unifiedMenu != null) {
                unifiedMenu?.show("playback", "shuffle")
            } else {
                showRandomPlaybackDialog()
            }
        }
        randomButton?.onFocusChangeListener = extendTimerOnFocus
    }

    // [suppressTrakt]: a source switch resumes the captured live position and
    // must not let the per-episode tracker percent override it. The parameter
    // retains its legacy name because the payload field does too.
    private fun playItem(
        index: Int,
        suppressTrakt: Boolean = false,
        suppressResume: Boolean = false,
    ) {
        // A sleep stop wins over anything already queued: the auto-advance
        // arms a 1.5s postDelayed before starting the next item, and a
        // countdown expiring inside that window would otherwise be undone by
        // its own handoff. Only automatic starts are gated — an explicit pick
        // clears the latch first (isAutoAdvancing is set by the auto paths).
        if (sleepStopLatched) {
            if (isAutoAdvancing) {
                android.util.Log.d("AndroidTvPlayer", "playItem suppressed by sleep timer")
                isAutoAdvancing = false
                return
            }
            // Picking something by hand means the viewer is awake.
            sleepStopLatched = false
        }
        val model = payload ?: return
        android.util.Log.d("AndroidTvPlayer", "playItem called - index: $index, total items: ${model.items.size}")
        if (index < 0 || index >= model.items.size) {
            android.util.Log.e("AndroidTvPlayer", "playItem - index out of bounds! index: $index, size: ${model.items.size}")
            return
        }

        // Navigating to an item invalidates any in-flight source-switch
        // feedback — without this, the pending watcher would report the NEW
        // item's READY/IDLE as the OLD switch's outcome. (switchToSourcePlaylist
        // registers its watcher AFTER calling playItem, so it's unaffected.)
        dropStaleSourceSwitchFeedback()

        // Reset buffering state for new content
        hasEverBeenReady = false
        maxStableDurationMs = 0L
        lastRealPositionMs = 0L
        hideBufferingIndicator()
        hideUpNextCard()
        resetSkipSegmentState()

        // Cancel any ongoing PikPak retry before starting new item
        cancelPikPakRetry()

        currentIndex = index
        updateCatalogEpisodeControls()
        val item = model.items[index]
        android.util.Log.d("AndroidTvPlayer", "playItem - item found: title=${item.title}, season=${item.season}, episode=${item.episode}, url=${item.url}, resumeId=${item.resumeId}")
        // Keep BOTH the local position and the remote tracker percent (the
        // payload field is the furthest of Trakt + Simkl + MDBList); STATE_READY resumes
        // the FURTHER of the two (never backward). Suppress trackers during
        // auto-advance (binge starts the next episode fresh) and during a source
        // switch on the same content (must honour the captured live position).
        val autoAdvance = isAutoAdvancing
        isAutoAdvancing = false
        pendingSeekMs = if (suppressResume) 0L else item.resumePositionMs
        pendingItemTraktPercent =
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
        setResolvingState(true)

        // Request stream from Flutter with async callback
        requestStreamFromFlutter(item, index) { url, provider ->
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - received url: $url")
            setResolvingState(false)

            if (url.isNullOrEmpty()) {
                android.util.Log.e("AndroidTvPlayer", "resolveAndPlay - URL is null or empty!")
                Toast.makeText(this, "Unable to load stream", Toast.LENGTH_SHORT).show()
                return@requestStreamFromFlutter
            }

            // Update the item with resolved URL and provider
            val updatedItem = item.copy(url = url, provider = provider ?: item.provider)
            payload?.items?.set(index, updatedItem)
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - starting playback with resolved URL, provider: $provider")
            startPlayback(payload!!.items[index])
        }
    }

    private fun startPlayback(item: PlaybackItem) {
        // Last gate before ExoPlayer actually starts. playItem's check happens
        // before URL resolution, and that round trip can outlast the countdown
        // — without rechecking here, a resolve that was already in flight would
        // start the night up again and re-take both screen holds.
        if (sleepStopLatched) {
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

    private fun resetSubtitleState() {
        stopExternalSubtitleRendering()
        stremioSubtitles.clear()
        subtitleTracks.clear()   // rebuilt lazily for the new media's embedded tracks
        addonSubtitleResults.clear()
        addonFetchTokens.clear()
        failedSubtitleUrls.clear()
        subtitleSearchResults = emptyList()
        subtitleSearchStatus = ""
        pendingSeriesResult = null
        currentStremioSubtitleIndex = -1
        isLoadingStremioSubtitles = false
        embeddedSubtitleSelected = false
        userManuallySelectedSubtitle = false
        // Re-established by seedInjectedSubtitles() when the next item has
        // launch-supplied captions; cleared here so a non-injected item never
        // inherits the previous item's auto-select suppression.
        suppressSubtitleAutoSelect = false
        manualSubtitleImdbId = null
        manualSubtitleType = null
        manualSubtitleSeason = null
        manualSubtitleEpisode = null
        manualSubtitleDisplayLabel = null
        addonSubtitleFetchToken++
        // Switching content resets the sync offset (it belonged to the previous
        // item's subtitle). The identity-scoped read already returns 0 for the
        // new content, but the embedded renderer offset is push-based and would
        // otherwise keep the previous item's shift — pushing a stale offset onto
        // the next episode's auto-selected subtitles while the UI reads 0.
        SubtitleSettings.resetSyncOffset()
        offsetRenderersFactory?.setOffsetUs(0L)
    }

    private fun playMediaDirect(item: PlaybackItem) {
        // Clear subtitle state when switching content
        resetSubtitleState()

        val metadata = MediaMetadata.Builder()
            .setTitle(item.title)
            .setArtist(item.seasonEpisodeLabel())
            .setDescription(item.description ?: payload?.subtitle ?: payload?.title)
            .build()

        val mediaItem = MediaItem.Builder()
            .setUri(item.url)
            .setMediaMetadata(metadata)
            .build()

        // High-res YouTube: video and audio are separate streams. Merge a
        // video-only track with its audio track. If anything goes wrong we fall
        // back to [item.url], a muxed stream that already contains audio, so we
        // never end up with silent video.
        val mergedSource = buildMergedSourceOrNull(item, mediaItem)

        player?.apply {
            if (mergedSource != null) {
                setMediaSource(mergedSource)
            } else {
                setMediaItem(mediaItem)
            }
            prepare()
            playWhenReady = true
            play()
        }

        // Detect if ExoPlayer auto-selects an embedded subtitle via TrackSelector preferences
        player?.addListener(object : Player.Listener {
            override fun onTracksChanged(tracks: Tracks) {
                player?.removeListener(this)
                if (isFinishing || isDestroyed) return
                val defaultSubtitleLang = SubtitleSettings.getDefaultSubtitleLanguage(this@AndroidTvTorrentPlayerActivity)
                if (defaultSubtitleLang == "off") return
                // Language-aware: an auto-selected embedded track (e.g. a forced
                // English one in a MULTi rip) only blocks addon auto-select when
                // it actually matches the user's preferred language.
                if (selectedEmbeddedTrackSatisfiesPreference(tracks)) {
                    embeddedSubtitleSelected = true
                }
            }
        })

        updateTitle(item)
        playlistAdapter?.setActiveIndex(currentIndex)
        restartProgressUpdates()

        // Fetch Stremio subtitles for this item
        fetchStremioSubtitles(item)
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
            val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
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
    private fun buildMergedSource(videoUrl: String, audioUrl: String): MergingMediaSource? {
        return try {
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
            val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
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

    /**
     * Fetch external subtitles from Stremio addons for the current item.
     * For series: uses payload.imdbId
     * For movie collections: uses per-item IMDB ID from perItemImdbIds cache or requests from Flutter
     */
    private fun fetchStremioSubtitles(item: PlaybackItem) {
        val model = payload ?: return

        // Launch-supplied captions (e.g. YouTube): use them directly and skip
        // addon discovery entirely — the title-based IMDB lookup would be
        // spurious for arbitrary video titles, and these tracks are already
        // known. Seeded as a single provider group so the subtitle menu shows
        // them; not auto-selected (captions stay off until the user picks one).
        //
        // Exception: once the user has manually identified a title (Search
        // Subtitle), honour that identity and fall through to the real addon
        // fetch below — otherwise a re-fetch (source/quality switch, playlist
        // advance) would silently discard their searched subtitles.
        if (injectedSubtitles.isNotEmpty() && manualSubtitleImdbId.isNullOrEmpty()) {
            seedInjectedSubtitles()
            return
        }

        // The addon match is spurious for YouTube (title-based IMDB lookup on
        // arbitrary video titles), so skip addon subtitle fetching for merged
        // YouTube items. (Side-rendering no longer re-prepares the source, so
        // the old merged-audio-drop hazard is gone — manually searched
        // subtitles now work on YouTube too.)
        if (!item.audioUrl.isNullOrEmpty()) {
            stremioSubtitles.clear()
            currentStremioSubtitleIndex = -1
            clearStremioLoadingState()
            return
        }

        val isSeries = model.contentType.lowercase(Locale.US) == "series"
        val type = if (isSeries) "series" else "movie"

        // Set loading state and refresh panel if visible
        isLoadingStremioSubtitles = true
        if (subtitleSettingsVisible) {
            refreshSubtitlePanelForLoading()
        }

        val manualImdbId = manualSubtitleImdbId
        if (!manualImdbId.isNullOrEmpty()) {
            val manualType = if (manualSubtitleType == "series") "series" else "movie"
            val subtitleItem = if (manualType == "series") {
                item.copy(
                    season = manualSubtitleSeason ?: item.season,
                    episode = manualSubtitleEpisode ?: item.episode
                )
            } else {
                item.copy(season = null, episode = null)
            }
            android.util.Log.d(
                "StremioSubs",
                "Using manual subtitle identity $manualImdbId type=$manualType S${subtitleItem.season}E${subtitleItem.episode}"
            )
            fetchStremioSubtitlesWithImdb(manualImdbId, manualType, subtitleItem)
            return
        }

        // For series, use the shared IMDB ID directly
        if (isSeries) {
            val imdbId = model.imdbId
            if (imdbId.isNullOrEmpty()) {
                stremioSubtitles.clear()
                currentStremioSubtitleIndex = -1
                clearStremioLoadingState()
                return
            }
            fetchStremioSubtitlesWithImdb(imdbId, type, item)
            return
        }

        // For movie collections, use per-item IMDB ID
        val itemIndex = item.index

        // Check if we already have a cached IMDB ID for this item
        if (model.perItemImdbIds.containsKey(itemIndex)) {
            val cachedImdbId = model.perItemImdbIds[itemIndex]
            if (cachedImdbId.isNullOrEmpty()) {
                // Already looked up and found nothing
                android.util.Log.d("StremioSubs", "No cached IMDB ID for item $itemIndex (previously not found)")
                stremioSubtitles.clear()
                currentStremioSubtitleIndex = -1
                clearStremioLoadingState()
                return
            }
            android.util.Log.d("StremioSubs", "Using cached IMDB ID $cachedImdbId for item $itemIndex")
            fetchStremioSubtitlesWithImdb(cachedImdbId, type, item)
            return
        }

        // Check if we have a fallback IMDB ID from payload (e.g., first item lookup)
        val fallbackImdbId = model.imdbId
        if (!fallbackImdbId.isNullOrEmpty() && model.items.size == 1) {
            // Single item, use payload IMDB ID
            android.util.Log.d("StremioSubs", "Single item, using payload IMDB ID: $fallbackImdbId")
            fetchStremioSubtitlesWithImdb(fallbackImdbId, type, item)
            return
        }

        // Request IMDB ID from Flutter for this item
        android.util.Log.d("StremioSubs", "Requesting IMDB ID from Flutter for item $itemIndex")
        val metadataFetchToken = addonSubtitleFetchToken
        requestMovieMetadataFromFlutter(item, itemIndex) { imdbId ->
            if (metadataFetchToken != addonSubtitleFetchToken) {
                android.util.Log.d("StremioSubs", "Content changed during metadata lookup, discarding IMDB result for item $itemIndex")
                return@requestMovieMetadataFromFlutter
            }

            // Cache the result (even if null to prevent repeated requests)
            model.perItemImdbIds[itemIndex] = imdbId
            android.util.Log.d("StremioSubs", "Received IMDB ID from Flutter: $imdbId for item $itemIndex")

            if (imdbId.isNullOrEmpty()) {
                stremioSubtitles.clear()
                currentStremioSubtitleIndex = -1
                clearStremioLoadingState()
                return@requestMovieMetadataFromFlutter
            }

            fetchStremioSubtitlesWithImdb(imdbId, type, item)
        }
    }

    /**
     * Seed the launch-supplied captions ([injectedSubtitles]) as a single
     * OK provider group, so they appear in the subtitle menu without any addon
     * fetch. Not auto-selected: [suppressSubtitleAutoSelect] keeps them off
     * until the user opts in from the menu (matching YouTube's own default).
     */
    private fun seedInjectedSubtitles() {
        suppressSubtitleAutoSelect = true
        val groupName = injectedSubtitles.first().source
        val addon = StremioAddon(
            id = "injected",
            name = groupName,
            manifestUrl = "",
            baseUrl = "",
            resources = listOf("subtitles"),
            types = emptyList(),
            enabled = true
        )
        addonSubtitleResults.clear()
        addonSubtitleResults.add(
            AddonSubtitleResult(
                addon,
                AddonSubtitleStatus.OK,
                injectedSubtitles.filter { isSideRenderableSubtitle(it.url) }
            )
        )
        rebuildFlatStremioSubtitles()
        clearStremioLoadingState()
        refreshSubtitleUiForLoading()
    }

    /**
     * Actually fetch subtitles with a known IMDB ID.
     */
    private fun fetchStremioSubtitlesWithImdb(imdbId: String, type: String, item: PlaybackItem) {
        // Fan out one independent fetch per addon so each keeps its own identity,
        // loading/failed state and can be retried alone. Two guards:
        //  • addonSubtitleFetchToken — invalidates ALL slots on a content switch.
        //  • addonFetchTokens[addonId] — invalidates one addon's in-flight call
        //    when that addon is retried.
        val contentToken = addonSubtitleFetchToken
        val addons = stremioSubtitleService?.getSubtitleAddons() ?: emptyList()
        addonSubtitleResults.clear()
        addons.forEach { addonSubtitleResults.add(AddonSubtitleResult(it, AddonSubtitleStatus.LOADING)) }
        isLoadingStremioSubtitles = addons.isNotEmpty()
        rebuildFlatStremioSubtitles()
        refreshSubtitleUiForLoading()

        addons.forEach { launchAddonSubtitleFetch(it, type, imdbId, item, contentToken) }
    }

    private fun launchAddonSubtitleFetch(
        addon: StremioAddon,
        type: String,
        imdbId: String,
        item: PlaybackItem,
        contentToken: Int
    ) {
        val slotToken = (addonFetchTokens[addon.id] ?: 0) + 1
        addonFetchTokens[addon.id] = slotToken
        setAddonSubtitleSlot(addon.id, AddonSubtitleStatus.LOADING, emptyList(), null)
        isLoadingStremioSubtitles = true   // covers single-addon retry too
        refreshSubtitleUiForLoading()

        subtitleScope.launch {
            val result = try {
                val subs = (stremioSubtitleService?.fetchSubtitlesForAddon(
                    addon = addon,
                    type = type,
                    imdbId = imdbId,
                    season = if (type == "series") item.season else null,
                    episode = if (type == "series") item.episode else null
                ) ?: emptyList()).filter { isSideRenderableSubtitle(it.url) }
                AddonSubtitleResult(addon, AddonSubtitleStatus.OK, subs)
            } catch (e: Exception) {
                android.util.Log.w("StremioSubs", "${addon.name} subtitle fetch failed: ${e.message}")
                AddonSubtitleResult(addon, AddonSubtitleStatus.FAILED, emptyList(), e.message)
            }

            if (contentToken != addonSubtitleFetchToken) return@launch      // content switched
            if (slotToken != addonFetchTokens[addon.id]) return@launch      // superseded by a retry

            setAddonSubtitleSlot(addon.id, result.status, result.subtitles, result.error)
            rebuildFlatStremioSubtitles()
            isLoadingStremioSubtitles =
                addonSubtitleResults.any { it.status == AddonSubtitleStatus.LOADING }
            tryAutoSelectAddonSubtitle()   // no-ops once a subtitle is selected
            // When the LAST addon finishes a manual "Fix movie" search with nothing
            // usable, tell the user (the old merged fetch showed this toast).
            if (!isLoadingStremioSubtitles && stremioSubtitles.isEmpty() && !manualSubtitleImdbId.isNullOrEmpty()) {
                Toast.makeText(this@AndroidTvTorrentPlayerActivity, "No online subtitles found for this title", Toast.LENGTH_SHORT).show()
            }
            refreshSubtitleUiForLoading()
        }
    }

    private fun setAddonSubtitleSlot(
        addonId: String,
        status: AddonSubtitleStatus,
        subs: List<StremioSubtitle>,
        error: String?
    ) {
        val i = addonSubtitleResults.indexOfFirst { it.addon.id == addonId }
        if (i >= 0) {
            addonSubtitleResults[i] =
                addonSubtitleResults[i].copy(status = status, subtitles = subs, error = error)
        }
    }

    /** Rebuild the deduped flat [stremioSubtitles] view, re-pinning the active
     *  selection by URL so a late-arriving addon can't shift the user's pick. */
    private fun rebuildFlatStremioSubtitles() {
        val activeUrl = if (currentStremioSubtitleIndex >= 0)
            stremioSubtitles.getOrNull(currentStremioSubtitleIndex)?.url else null
        val seen = HashSet<String>()
        stremioSubtitles.clear()
        for (r in addonSubtitleResults) {
            for (s in r.subtitles) {
                if (s.url.isNotEmpty() && seen.add(s.url)) stremioSubtitles.add(s)
            }
        }
        currentStremioSubtitleIndex =
            if (activeUrl != null) stremioSubtitles.indexOfFirst { it.url == activeUrl } else -1
    }

    /** Retry a single addon's subtitle fetch (bound to the col3 "retry" row). */
    private fun retryAddonSubtitles(addonId: String) {
        val model = payload ?: return
        val addon = addonSubtitleResults.firstOrNull { it.addon.id == addonId }?.addon ?: return
        val item = model.items.getOrNull(currentIndex) ?: return
        // Mirror fetchStremioSubtitles' id resolution: multi-item movie collections
        // resolve per-item via perItemImdbIds (payload.imdbId is null for them).
        val imdbId = manualSubtitleImdbId ?: model.perItemImdbIds[item.index] ?: model.imdbId ?: return
        val type = if ((manualSubtitleType ?: model.contentType).lowercase(Locale.US) == "series")
            "series" else "movie"
        val subtitleItem = if (type == "series") {
            item.copy(
                season = manualSubtitleSeason ?: item.season,
                episode = manualSubtitleEpisode ?: item.episode
            )
        } else item
        launchAddonSubtitleFetch(addon, type, imdbId, subtitleItem, addonSubtitleFetchToken)
    }

    /** Repaint whichever subtitle surface is showing (unified menu or legacy panel). */
    private fun refreshSubtitleUiForLoading() {
        if (unifiedMenu?.isVisible == true) unifiedMenu?.render()
        if (subtitleSettingsVisible) refreshSubtitlePanelForLoading()
    }

    /**
     * Clear Stremio subtitle loading state and refresh panel if visible.
     */
    private fun clearStremioLoadingState() {
        isLoadingStremioSubtitles = false
        if (subtitleSettingsVisible) {
            refreshSubtitlePanelForLoading()
        }
    }

    private fun playNext() {
        if (continuousShuffleEnabled) {
            val shuffleIndex = pickShuffleIndex()
            if (shuffleIndex != null) {
                isAutoAdvancing = true
                playItem(shuffleIndex)
                return
            }
        }

        val nextIndex = getNextPlayableIndex(currentIndex)
        if (nextIndex != null) {
            isAutoAdvancing = true
            playItem(nextIndex)
        } else {
            if (isStremioTvMode && stremioTvChannels.any { it.isCurrent }) {
                requestStremioTvNext()
                return
            }

            // No next in playlist — fetch the next episode IN-PLAYER when the
            // guide + resolver allow it, else fall back to the quick-play
            // relaunch hand-back.
            val model = payload
            val currentItem = model?.items?.getOrNull(currentIndex)
            if (model != null && currentItem != null &&
                model.contentType == "series" && currentItem.season != null &&
                currentItem.episode != null) {
                val nextTarget = guideAdjacent(model, currentItem, 1)
                if (nextTarget != null && hasPlaylistResolver) {
                    requestEpisodeFetch(nextTarget.season, nextTarget.episode)
                    return
                }
                if (model.imdbId != null) {
                    if (hasPlaylistResolver) {
                        requestAdjacentEpisodeFetch(
                            model.imdbId!!,
                            currentItem.season,
                            currentItem.episode,
                        )
                    } else {
                        requestQuickPlayNextEpisode(model.imdbId!!, currentItem.season, currentItem.episode)
                        finish()
                    }
                } else {
                    Toast.makeText(this, "End of playlist", Toast.LENGTH_SHORT).show()
                }
            } else {
                Toast.makeText(this, "End of playlist", Toast.LENGTH_SHORT).show()
            }
        }
    }

    /** Previous for catalog series, including a single direct-link episode.
     * Existing playlist navigation wins; at its boundary the full guide names
     * the adjacent episode and Flutter resolves it in place. */
    private fun playPrevious() {
        val model = payload ?: return
        val prevIndex = getPrevPlayableIndex(currentIndex)
        if (prevIndex != null) {
            // Match the Dart player's manual Previous semantics: selecting an
            // already-present episode starts it fresh. Guide-fetched Previous
            // remains resumable, as it does in Dart.
            playItem(prevIndex, suppressResume = true)
            return
        }
        val currentItem = model.items.getOrNull(currentIndex)
        if (model.contentType == "series" && hasPlaylistResolver) {
            val previousTarget = guideAdjacent(model, currentItem, -1)
            if (previousTarget != null) {
                requestEpisodeFetch(previousTarget.season, previousTarget.episode)
                return
            }
        }
        Toast.makeText(this, "Beginning of playlist", Toast.LENGTH_SHORT).show()
    }

    /** The IPTV Previous control is shared by catalog playback. Keep it hidden
     * for movies/first episodes, and reveal it when either the current source
     * or the asynchronously delivered full-show guide has a predecessor. */
    private fun updateCatalogEpisodeControls() {
        if (isIptvMode) return
        val model = payload
        val currentItem = model?.items?.getOrNull(currentIndex)
        val hasPrevious = model != null && model.contentType == "series" &&
            !isStremioTvMode &&
            (getPrevPlayableIndex(currentIndex) != null ||
                (hasPlaylistResolver &&
                    guideAdjacent(model, currentItem, -1) != null))
        iptvPrevButton?.visibility = if (hasPrevious) View.VISIBLE else View.GONE
    }

    private fun playRandom() {
        val model = payload ?: return
        if (model.items.isEmpty()) {
            Toast.makeText(this, "No items in playlist", Toast.LENGTH_SHORT).show()
            return
        }

        val randomIndex = pickShuffleIndex() ?: return
        isAutoAdvancing = true
        playItem(randomIndex)
    }

    private fun showRandomPlaybackDialog() {
        val model = payload
        if (model == null || model.items.isEmpty()) {
            Toast.makeText(this, "No items in playlist", Toast.LENGTH_SHORT).show()
            return
        }

        val shuffleLabel = if (continuousShuffleEnabled) {
            "Turn Off Continuous Shuffle"
        } else {
            "Shuffle Continuously"
        }
        val choices = arrayOf("Play Random Once", shuffleLabel)

        AlertDialog.Builder(this)
            .setTitle("Shuffle Playback")
            .setItems(choices) { _, which ->
                when (which) {
                    0 -> {
                        continuousShuffleEnabled = false
                        shuffleBag.clear()
                        playRandom()
                    }
                    1 -> {
                        if (continuousShuffleEnabled) {
                            continuousShuffleEnabled = false
                            shuffleBag.clear()
                            Toast.makeText(this, "Continuous shuffle off", Toast.LENGTH_SHORT).show()
                        } else {
                            continuousShuffleEnabled = true
                            shuffleBag.clear()
                            Toast.makeText(this, "Continuous shuffle on", Toast.LENGTH_SHORT).show()
                            playRandom()
                        }
                    }
                }
            }
            .show()
    }

    private fun getShuffleEligibleIndices(): List<Int> {
        val model = payload ?: return emptyList()
        if (model.items.isEmpty()) return emptyList()

        if (playlistMode == PlaylistMode.SERIES) {
            val episodeIndices = model.items.mapIndexedNotNull { index, item ->
                if (item.season != null && item.episode != null) index else null
            }
            if (episodeIndices.isNotEmpty()) return episodeIndices
        }

        if (playlistMode == PlaylistMode.COLLECTION) {
            val preferredGroup = movieGroups?.groups?.firstOrNull {
                it.name.equals("Main", ignoreCase = true)
            } ?: movieGroups?.groups?.firstOrNull()
            val indices = preferredGroup?.fileIndices
                ?.filter { it in model.items.indices }
                ?: emptyList()
            if (indices.isNotEmpty()) return indices
        }

        return model.items.indices.toList()
    }

    private fun pickShuffleIndex(): Int? {
        val eligible = getShuffleEligibleIndices().distinct()
        if (eligible.isEmpty()) return null
        if (eligible.size == 1) return eligible.first()

        val eligibleSet = eligible.toSet()
        shuffleBag.removeAll { it !in eligibleSet || it == currentIndex }

        if (shuffleBag.isEmpty()) {
            shuffleBag.addAll(eligible.filter { it != currentIndex }.shuffled())
        }

        if (shuffleBag.isEmpty()) return null
        return shuffleBag.removeAt(shuffleBag.lastIndex)
    }

    private fun updateTitle(item: PlaybackItem) {
        // Prefer the episode label / show title when the item title is blank, so
        // a series episode never renders as just the red badge with no text (the
        // "red line" bug). If everything is blank (rare non-series case) the
        // showControlsMenu guard keeps the header hidden rather than showing empty.
        val model = payload
        val fallbackTitle = item.seasonEpisodeLabel().ifEmpty { model?.title.orEmpty() }
        titleView.text = item.title.ifBlank { fallbackTitle }

        // Pre-populate OTT fields for when controls menu is shown
        if (model?.contentType?.lowercase(java.util.Locale.US) == "series") {
            if (item.season != null && item.episode != null) {
                val seasonStr = item.season.toString().padStart(2, '0')
                val episodeStr = item.episode.toString().padStart(2, '0')
                ottEpisodeBadge.text = "S$seasonStr E$episodeStr"
                ottEpisodeBadge.visibility = View.VISIBLE
            } else {
                ottEpisodeBadge.visibility = View.GONE
            }
            // Fall back to "Episode N" so the badge never sits next to a blank line.
            ottEpisodeTitle.text = item.title.ifBlank {
                item.episode?.let { "Episode $it" } ?: fallbackTitle
            }

            val rating = item.rating
            if (rating != null && rating > 0) {
                ottRatingContainer.visibility = View.VISIBLE
                ottRating.text = String.format(java.util.Locale.US, "%.1f", rating)
            } else {
                ottRatingContainer.visibility = View.GONE
            }
        }

        channelBadge.visibility = View.GONE
    }

    private fun setResolvingState(resolving: Boolean) {
        if (resolving) {
            nextText.text = "" // Title is filled in once the stream resolves
            nextSubtext.visibility = View.GONE
            fadeInNextOverlay()
        } else {
            hideNextOverlay()
            setNextOverlayBackdrop(null)
        }
    }

    // Loads dimmed backdrop art behind the loading/tuning overlay, or clears it.
    private fun setNextOverlayBackdrop(artworkUrl: String?) {
        if (!::nextBackdrop.isInitialized) return
        // Glide.with(activity) throws once the activity is destroyed; the
        // loading overlay is torn down from async MethodChannel callbacks that
        // can resolve after onDestroy, so bail out defensively.
        if (isFinishing || isDestroyed) return
        if (!artworkUrl.isNullOrEmpty()) {
            nextBackdrop.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(this).load(artworkUrl).into(nextBackdrop)
        } else {
            com.bumptech.glide.Glide.with(this).clear(nextBackdrop)
            nextBackdrop.setImageDrawable(null)
            nextBackdrop.visibility = View.GONE
        }
    }

    private fun requestStreamFromFlutter(item: PlaybackItem, index: Int, callback: (String?, String?) -> Unit) {
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
    private fun requestMovieMetadataFromFlutter(item: PlaybackItem, index: Int, callback: (String?) -> Unit) {
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

    private fun showSearchSubtitleDialog() {
        val currentItem = getCurrentSubtitleSearchItem()
        if (currentItem == null) {
            Toast.makeText(this, "No current video to search", Toast.LENGTH_SHORT).show()
            return
        }

        val results = mutableListOf<SubtitleCatalogResult>()
        val adapter = createSubtitleCatalogResultAdapter(results)

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), 0)
        }

        val queryInput = EditText(this).apply {
            setSingleLine(true)
            hint = "Movie or show title"
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_SEARCH
            setText(buildSubtitleSearchInitialQuery(currentItem))
            setSelectAllOnFocus(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0x80FFFFFF.toInt())
        }

        val actionRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(12), 0, dp(8))
        }

        val searchButton = AppCompatButton(this).apply {
            text = "Search"
            isFocusable = true
            isAllCaps = true
            setTextColor(Color.WHITE)
            setBackgroundResource(R.drawable.subtitle_search_button_bg)
            stateListAnimator = null
            minimumHeight = dp(44)
        }

        val progressBar = ProgressBar(this).apply {
            isIndeterminate = true
            visibility = View.GONE
        }

        actionRow.addView(
            searchButton,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )
        actionRow.addView(
            progressBar,
            LinearLayout.LayoutParams(dp(48), dp(48)).apply {
                leftMargin = dp(16)
            }
        )

        val statusText = TextView(this).apply {
            text = "Find subtitles by choosing the correct title."
            setPadding(0, 0, 0, dp(8))
            setTextColor(0xB3FFFFFF.toInt())
        }

        val resultList = ListView(this).apply {
            this.adapter = adapter
            isFocusable = true
            isFocusableInTouchMode = true
            selector = ContextCompat.getDrawable(context, R.drawable.subtitle_catalog_row_selector)
            isDrawSelectorOnTop = false
            divider = ColorDrawable(0x14FFFFFF)
            dividerHeight = 1
            // Keep the DPAD-focused row fully on screen: with bottom padding + clipToPadding
            // off, ListView scrolls the selection above the padding instead of half-clipping it.
            clipToPadding = false
            setPadding(0, 0, 0, dp(48))
            emptyView = null
        }

        container.addView(
            queryInput,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            actionRow,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            resultList,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(360)
            )
        )

        lateinit var dialog: AlertDialog

        fun setLoading(loading: Boolean) {
            progressBar.visibility = if (loading) View.VISIBLE else View.GONE
            searchButton.isEnabled = !loading
            queryInput.isEnabled = !loading
            if (loading) {
                statusText.text = "Searching..."
            }
        }

        fun updateResults(newResults: List<SubtitleCatalogResult>) {
            results.clear()
            results.addAll(newResults)
            adapter.notifyDataSetChanged()
            statusText.text = when {
                newResults.isEmpty() -> "No matching movie/show results found."
                newResults.size == 1 -> "1 result"
                else -> "${newResults.size} results"
            }
            if (newResults.isNotEmpty()) {
                resultList.requestFocus()
                resultList.setSelection(0)
            } else {
                searchButton.requestFocus()
            }
        }

        fun performSearch() {
            val query = queryInput.text?.toString()?.trim().orEmpty()
            if (query.isEmpty()) {
                results.clear()
                adapter.notifyDataSetChanged()
                statusText.text = "Enter a title to search."
                queryInput.requestFocus()
                return
            }

            setLoading(true)
            requestSubtitleCatalogSearchFromFlutter(
                query,
                onSuccess = { searchResults ->
                    if (!dialog.isShowing) return@requestSubtitleCatalogSearchFromFlutter
                    setLoading(false)
                    updateResults(searchResults)
                },
                onError = { message ->
                    if (!dialog.isShowing) return@requestSubtitleCatalogSearchFromFlutter
                    setLoading(false)
                    results.clear()
                    adapter.notifyDataSetChanged()
                    statusText.text = message
                    searchButton.requestFocus()
                }
            )
        }

        resultList.setOnItemClickListener { _, _, position, _ ->
            val selected = adapter.getItem(position) ?: return@setOnItemClickListener
            val item = getCurrentSubtitleSearchItem()
            if (item == null) {
                Toast.makeText(this, "No current video to search", Toast.LENGTH_SHORT).show()
                return@setOnItemClickListener
            }

            dialog.dismiss()
            if (selected.type == "series") {
                val resolvedEpisode = resolveSeasonEpisodeForSubtitle(item)
                if (resolvedEpisode != null) {
                    applyManualSubtitleIdentity(
                        selected,
                        resolvedEpisode.season,
                        resolvedEpisode.episode
                    )
                } else {
                    showSeasonEpisodePrompt(selected)
                }
            } else {
                applyManualSubtitleIdentity(selected, null, null)
            }
        }

        searchButton.setOnClickListener { performSearch() }
        queryInput.setOnEditorActionListener { _, actionId, event ->
            val isSearchAction = actionId == EditorInfo.IME_ACTION_SEARCH
            val isEnterKey = event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_UP
            if (isSearchAction || isEnterKey) {
                performSearch()
                true
            } else {
                false
            }
        }

        dialog = AlertDialog.Builder(this, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle("Search Movie/Show Subtitles")
            .setView(container)
            .setNegativeButton("Cancel", null)
            .create()

        dialog.setOnShowListener {
            searchButton.requestFocus()
        }
        dialog.show()
    }

    private fun getCurrentSubtitleSearchItem(): PlaybackItem? {
        payload?.items?.getOrNull(currentIndex)?.let { return it }

        if (isIptvMode && currentIptvIndex in iptvChannels.indices) {
            val entry = iptvChannels[currentIptvIndex]
            return PlaybackItem(
                id = "iptv:${entry.index}",
                title = entry.name,
                url = entry.url,
                hdVideoUrl = null,
                audioUrl = null,
                index = 0,
                season = null,
                episode = null,
                artwork = entry.logoUrl,
                description = entry.group,
                resumePositionMs = 0L,
                durationMs = 0L,
                updatedAt = System.currentTimeMillis(),
                resumeId = null,
                sizeBytes = null,
                rating = null,
                provider = "iptv",
            )
        }

        val mediaItem = player?.currentMediaItem ?: return null
        val mediaTitle = mediaItem.mediaMetadata.title?.toString()?.trim()
        val mediaUrl = mediaItem.localConfiguration?.uri?.toString().orEmpty()
        val fallbackTitle = mediaTitle
            ?.takeIf { it.isNotEmpty() }
            ?: mediaUrl.substringAfterLast('/').substringBefore('?').takeIf { it.isNotEmpty() }
            ?: return null

        return PlaybackItem(
            id = "current:${fallbackTitle.hashCode()}",
            title = fallbackTitle,
            url = mediaUrl,
            hdVideoUrl = null,
            audioUrl = null,
            index = currentIndex,
            season = null,
            episode = null,
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
    }

    private fun requestSubtitleCatalogSearchFromFlutter(
        query: String,
        onSuccess: (List<SubtitleCatalogResult>) -> Unit,
        onError: (String) -> Unit
    ) {
        try {
            val channel = MainActivity.getAndroidTvPlayerChannel()
            if (channel == null) {
                onError("Subtitle search is unavailable.")
                return
            }

            channel.invokeMethod(
                "searchSubtitleCatalogs",
                hashMapOf<String, Any?>("query" to query),
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        val parsedResults = parseSubtitleCatalogResults(result)
                        runOnUiThread { onSuccess(parsedResults) }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        android.util.Log.e("StremioSubs", "Subtitle catalog search failed: $errorCode - $errorMessage")
                        runOnUiThread {
                            onError(errorMessage ?: "Subtitle search failed.")
                        }
                    }

                    override fun notImplemented() {
                        android.util.Log.e("StremioSubs", "Subtitle catalog search is not implemented")
                        runOnUiThread { onError("Subtitle search is unavailable.") }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("StremioSubs", "Subtitle catalog search exception", e)
            onError("Subtitle search failed.")
        }
    }

    private fun parseSubtitleCatalogResults(result: Any?): List<SubtitleCatalogResult> {
        val items = result as? List<*> ?: return emptyList()
        return items.mapNotNull { rawItem ->
            val map = rawItem as? Map<*, *> ?: return@mapNotNull null
            val imdbId = map["imdbId"]?.toString()?.takeIf { it.startsWith("tt") }
                ?: return@mapNotNull null
            val type = map["type"]?.toString()?.lowercase(Locale.US)
                ?.takeIf { it == "movie" || it == "series" }
                ?: return@mapNotNull null
            val name = map["name"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                ?: imdbId
            val year = map["year"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            val source = map["source"]?.toString()?.trim()?.takeIf { it.isNotEmpty() }

            SubtitleCatalogResult(
                imdbId = imdbId,
                type = type,
                name = name,
                year = year,
                source = source
            )
        }
    }

    private fun createSubtitleCatalogResultAdapter(
        results: MutableList<SubtitleCatalogResult>
    ): ArrayAdapter<SubtitleCatalogResult> {
        return object : ArrayAdapter<SubtitleCatalogResult>(this, 0, results) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val row = (convertView as? LinearLayout) ?: LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(20), dp(12), dp(20), dp(12))
                    minimumHeight = dp(72)
                }
                row.removeAllViews()

                val item = getItem(position)
                val title = TextView(context).apply {
                    text = item?.titleLine().orEmpty()
                    textSize = 18f
                    setTextColor(Color.WHITE)
                    typeface = Typeface.DEFAULT_BOLD
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }
                val detail = TextView(context).apply {
                    text = item?.detailLine().orEmpty()
                    textSize = 14f
                    setTextColor(Color.LTGRAY)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }

                row.addView(
                    title,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
                row.addView(
                    detail,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
                return row
            }
        }
    }

    private fun showSeasonEpisodePrompt(result: SubtitleCatalogResult) {
        val currentItem = getCurrentSubtitleSearchItem()

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), 0)
        }

        val title = TextView(this).apply {
            text = result.titleLine()
            textSize = 18f
            setPadding(0, 0, 0, dp(12))
        }

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        val seasonInput = EditText(this).apply {
            hint = "Season"
            inputType = InputType.TYPE_CLASS_NUMBER
            imeOptions = EditorInfo.IME_ACTION_NEXT
            setText((currentItem?.season ?: manualSubtitleSeason ?: 1).toString())
            setSelectAllOnFocus(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0x80FFFFFF.toInt())
        }

        val episodeInput = EditText(this).apply {
            hint = "Episode"
            inputType = InputType.TYPE_CLASS_NUMBER
            imeOptions = EditorInfo.IME_ACTION_DONE
            setText((currentItem?.episode ?: manualSubtitleEpisode ?: 1).toString())
            setSelectAllOnFocus(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0x80FFFFFF.toInt())
        }

        row.addView(
            seasonInput,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = dp(12)
            }
        )
        row.addView(
            episodeInput,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )
        container.addView(
            title,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            row,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        val dialog = AlertDialog.Builder(this, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle("Series Episode")
            .setView(container)
            .setPositiveButton("Search", null)
            .setNegativeButton("Cancel", null)
            .create()

        fun submit() {
            val season = seasonInput.text?.toString()?.toIntOrNull()
            val episode = episodeInput.text?.toString()?.toIntOrNull()
            if (season == null || episode == null || season <= 0 || episode <= 0) {
                Toast.makeText(this, "Enter a valid season and episode", Toast.LENGTH_SHORT).show()
                return
            }

            dialog.dismiss()
            applyManualSubtitleIdentity(result, season, episode)
        }

        episodeInput.setOnEditorActionListener { _, actionId, event ->
            val isDoneAction = actionId == EditorInfo.IME_ACTION_DONE
            val isEnterKey = event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_UP
            if (isDoneAction || isEnterKey) {
                submit()
                true
            } else {
                false
            }
        }

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { submit() }
            seasonInput.requestFocus()
        }
        dialog.show()
    }

    private fun applyManualSubtitleIdentity(
        result: SubtitleCatalogResult,
        season: Int?,
        episode: Int?
    ) {
        val currentItem = getCurrentSubtitleSearchItem()
        if (currentItem == null) {
            Toast.makeText(this, "No current video to search", Toast.LENGTH_SHORT).show()
            return
        }

        val type = if (result.type == "series") "series" else "movie"
        if (type == "series" && (season == null || episode == null || season <= 0 || episode <= 0)) {
            showSeasonEpisodePrompt(result)
            return
        }

        addonSubtitleFetchToken++
        manualSubtitleImdbId = result.imdbId
        manualSubtitleType = type
        manualSubtitleSeason = if (type == "series") season else null
        manualSubtitleEpisode = if (type == "series") episode else null
        manualSubtitleDisplayLabel = buildManualSubtitleDisplayLabel(
            result,
            type,
            manualSubtitleSeason,
            manualSubtitleEpisode
        )

        // Tear down any side-rendered subtitle before switching identity —
        // otherwise its cues keep drawing while the panel shows nothing selected.
        stopExternalSubtitleRendering()

        stremioSubtitles.clear()
        currentStremioSubtitleIndex = -1
        embeddedSubtitleSelected = false
        userManuallySelectedSubtitle = false
        isLoadingStremioSubtitles = true

        trackSelector?.let { selector ->
            selector.parameters = selector.parameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
        }

        if (subtitleSettingsVisible) {
            refreshSubtitlePanelForLoading()
        }

        val subtitleItem = if (type == "series") {
            currentItem.copy(season = season, episode = episode)
        } else {
            currentItem.copy(season = null, episode = null)
        }

        Toast.makeText(this, "Searching subtitles for ${result.name}", Toast.LENGTH_SHORT).show()
        fetchStremioSubtitlesWithImdb(result.imdbId, type, subtitleItem)
    }

    private fun resolveSeasonEpisodeForSubtitle(item: PlaybackItem): SeasonEpisode? {
        val existingSeason = item.season
        val existingEpisode = item.episode
        if (existingSeason != null && existingEpisode != null && existingSeason > 0 && existingEpisode > 0) {
            return SeasonEpisode(existingSeason, existingEpisode)
        }

        return parseSeasonEpisodeFromTitle(item.title)
    }

    private fun parseSeasonEpisodeFromTitle(title: String): SeasonEpisode? {
        val patterns = listOf(
            Regex("""(?i)\bS(\d{1,2})\s*E(\d{1,3})\b"""),
            Regex("""(?i)\b(\d{1,2})x(\d{1,3})\b"""),
            Regex("""(?i)\bSeason\s*(\d{1,2})\s*(?:Episode|Ep|E)\s*(\d{1,3})\b""")
        )

        for (pattern in patterns) {
            val match = pattern.find(title) ?: continue
            val season = match.groupValues.getOrNull(1)?.toIntOrNull()
            val episode = match.groupValues.getOrNull(2)?.toIntOrNull()
            if (season != null && episode != null && season > 0 && episode > 0) {
                return SeasonEpisode(season, episode)
            }
        }

        return null
    }

    private fun buildSubtitleSearchInitialQuery(item: PlaybackItem): String {
        val filename = item.title.substringAfterLast('/').substringBefore('?')
        val withoutExtension = filename.replace(Regex("""\.[A-Za-z0-9]{2,5}$"""), "")
        val cleaned = withoutExtension
            .replace(Regex("""[._]+"""), " ")
            .replace(Regex("""(?i)\bS\d{1,2}\s*E\d{1,3}\b"""), " ")
            .replace(Regex("""(?i)\b\d{1,2}x\d{1,3}\b"""), " ")
            .replace(
                Regex(
                    """(?i)\b(2160p|1080p|720p|480p|4k|uhd|hdr|web[- ]?dl|webrip|bluray|brrip|hdtv|dvdrip|x264|x265|h264|h265|hevc|aac|dts|yify)\b"""
                ),
                " "
            )
            .replace(Regex("""\s+"""), " ")
            .trim()

        return cleaned.ifEmpty { item.title }
    }

    private fun buildManualSubtitleDisplayLabel(
        result: SubtitleCatalogResult,
        type: String,
        season: Int?,
        episode: Int?
    ): String {
        val base = result.titleLine()
        return if (type == "series" && season != null && episode != null) {
            "$base S${season}E$episode"
        } else {
            base
        }
    }

    private fun currentSubtitleIdentityLabel(): String {
        val manualLabel = manualSubtitleDisplayLabel?.trim()
        if (!manualLabel.isNullOrEmpty()) {
            return "Subtitles for $manualLabel"
        }

        val detectedTitle = getCurrentSubtitleSearchItem()
            ?.let { buildSubtitleSearchInitialQuery(it).trim() }
            ?.takeIf { it.isNotEmpty() }

        return if (detectedTitle != null) {
            "Detected: $detectedTitle"
        } else {
            "Detected title unavailable"
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    // PikPak Cold Storage Retry Logic
    // PikPak uses "cold storage" where files that haven't been accessed recently need 10-30 seconds
    // to reactivate. This implements retry logic with exponential backoff.

    private fun playPikPakVideoWithRetry(item: PlaybackItem) {
        android.util.Log.d("AndroidTvPlayer", "PikPak: Starting retry logic for cold storage handling")

        // Clear subtitle state when switching content
        resetSubtitleState()

        // Cancel any previous retry loops
        pikPakRetryId++
        val myRetryId = pikPakRetryId

        // Reset retry state
        pikPakRetryCount = 0
        isPikPakRetrying = false
        hidePikPakRetryOverlay()

        // Null safety check for player
        if (player == null) {
            android.util.Log.e("AndroidTvPlayer", "PikPak: Player is null, cannot attempt playback")
            return
        }

        // Clear previous video's subtitles
        subtitleOverlay.setCues(emptyList())

        // Prepare and play the media ONCE before retry loop
        val metadata = MediaMetadata.Builder()
            .setTitle(item.title)
            .setArtist(item.seasonEpisodeLabel())
            .setDescription(item.description ?: payload?.subtitle ?: payload?.title)
            .build()

        val mediaItem = MediaItem.Builder()
            .setUri(item.url)
            .setMediaMetadata(metadata)
            .build()

        player?.apply {
            setMediaItem(mediaItem)
            prepare()
            play()
        }

        updateTitle(item)
        playlistAdapter?.setActiveIndex(currentIndex)
        restartProgressUpdates()

        // Fetch Stremio subtitles for this item (same as playMediaDirect)
        fetchStremioSubtitles(item)

        // Start retry loop with attempt 0
        attemptPikPakPlaybackLoop(item, 0, myRetryId)
    }

    private fun attemptPikPakPlaybackLoop(item: PlaybackItem, attemptNumber: Int, retryId: Int) {
        // Check if this retry has been cancelled
        if (pikPakRetryId != retryId) {
            android.util.Log.d("AndroidTvPlayer", "PikPak: Retry cancelled (token mismatch)")
            isPikPakRetrying = false
            pikPakRetryCount = 0
            hidePikPakRetryOverlay()
            return
        }

        // Null safety check for player
        if (player == null) {
            android.util.Log.e("AndroidTvPlayer", "PikPak: Player is null, cannot continue playback")
            isPikPakRetrying = false
            pikPakRetryCount = 0
            hidePikPakRetryOverlay()
            return
        }

        android.util.Log.d("AndroidTvPlayer", "PikPak: Playback attempt ${attemptNumber + 1}/${PIKPAK_MAX_RETRIES + 1}")

        // Calculate delay for this attempt (0 for first attempt, exponential backoff for subsequent)
        val delayMs = if (attemptNumber == 0) {
            0L
        } else {
            val calculatedDelay = PIKPAK_BASE_DELAY_MS * (1 shl (attemptNumber - 1))
            calculatedDelay.toLong().coerceAtMost(PIKPAK_MAX_DELAY_MS.toLong())
        }

        // Monitor during BOTH the timeout period AND the delay period
        waitForPikPakMetadata(item, attemptNumber, retryId, additionalMonitoringMs = delayMs) { success ->
            // Check if retry was cancelled during monitoring
            if (pikPakRetryId != retryId) {
                android.util.Log.d("AndroidTvPlayer", "PikPak: Retry cancelled during monitoring")
                return@waitForPikPakMetadata
            }

            if (success) {
                // Video loaded successfully, exit retry loop
                android.util.Log.d("AndroidTvPlayer", "PikPak: Video loaded successfully, exiting retry loop")
                return@waitForPikPakMetadata
            }

            // Check if this was the last attempt
            if (attemptNumber >= PIKPAK_MAX_RETRIES) {
                // All retries exhausted
                android.util.Log.e("AndroidTvPlayer", "PikPak: All retry attempts exhausted. Video failed to load.")

                // Clear state synchronously
                isPikPakRetrying = false
                pikPakRetryCount = 0
                hidePikPakRetryOverlay()

                if (!isFinishing) {
                    runOnUiThread {
                        Toast.makeText(this, "Video failed to load. Skipping to next...", Toast.LENGTH_SHORT).show()

                        // Auto-advance to next video
                        pikPakRetryHandler.postDelayed({
                            playNext()
                        }, 1500)
                    }
                }
                return@waitForPikPakMetadata
            }

            // Video didn't load, need to retry
            // Update retry UI
            pikPakRetryCount = attemptNumber + 1
            isPikPakRetrying = true
            if (!isFinishing) {
                showPikPakRetryOverlay("Reactivating video... (Attempt ${attemptNumber + 2}/${PIKPAK_MAX_RETRIES + 1})")
            }

            android.util.Log.d("AndroidTvPlayer", "PikPak: Video didn't load, monitoring for next attempt")

            // Continue to next attempt
            attemptPikPakPlaybackLoop(item, attemptNumber + 1, retryId)
        }
    }

    private fun waitForPikPakMetadata(
        item: PlaybackItem,
        attemptNumber: Int,
        retryId: Int,
        additionalMonitoringMs: Long = 0,
        onComplete: (Boolean) -> Unit
    ) {
        val startTime = System.currentTimeMillis()
        val totalTimeoutMs = PIKPAK_METADATA_TIMEOUT_MS + additionalMonitoringMs
        val checkHandler = Handler(Looper.getMainLooper())

        val checkRunnable = object : Runnable {
            override fun run() {
                // Check if retry was cancelled
                if (pikPakRetryId != retryId) {
                    android.util.Log.d("AndroidTvPlayer", "PikPak: Metadata check cancelled")
                    checkHandler.removeCallbacks(this)
                    onComplete(false)
                    return
                }

                val elapsed = System.currentTimeMillis() - startTime

                // Check if player state is ready or has duration (with null safety)
                val currentPlayer = player
                if (currentPlayer != null && (currentPlayer.playbackState == Player.STATE_READY || currentPlayer.duration > 0)) {
                    android.util.Log.d("AndroidTvPlayer", "PikPak: Video metadata loaded successfully - file is ready!")

                    // CRITICAL FIX: Clear retry state IMMEDIATELY when video loads
                    // This prevents race conditions and ensures UI updates instantly
                    isPikPakRetrying = false
                    pikPakRetryCount = 0
                    hidePikPakRetryOverlay()

                    // Clean up handler callbacks
                    checkHandler.removeCallbacks(this)

                    // Ensure subtitles are selected after successful load
                    ensureDefaultSubtitleSelected()

                    onComplete(true)
                    return
                }

                // Check timeout (now includes additional monitoring period)
                if (elapsed >= totalTimeoutMs) {
                    android.util.Log.d("AndroidTvPlayer", "PikPak: Timeout waiting for metadata after ${totalTimeoutMs}ms - file likely in cold storage")
                    checkHandler.removeCallbacks(this)
                    onComplete(false)
                    return
                }

                // Continue checking
                checkHandler.postDelayed(this, 500)
            }
        }

        // Start checking
        checkHandler.postDelayed(checkRunnable, 500)
    }


    private fun showPikPakRetryOverlay(message: String) {
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
            pikPakReactivationText.text = message
            pikPakReactivationIndicator.animate().cancel()
            pikPakReactivationIndicator.visibility = View.VISIBLE
            pikPakReactivationIndicator.animate().alpha(1f).setDuration(250).start()
        }
    }

    private fun hidePikPakRetryOverlay() {
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
            pikPakReactivationIndicator.animate().cancel()
            pikPakReactivationIndicator.alpha = 0f
            pikPakReactivationIndicator.visibility = View.GONE
        }
    }

    private fun cancelPikPakRetry() {
        // Increment retry ID to invalidate any ongoing retry operations
        pikPakRetryId++
        isPikPakRetrying = false
        pikPakRetryCount = 0

        // Remove any pending retry callbacks
        pikPakRetryHandler.removeCallbacksAndMessages(null)

        // Hide overlay
        hidePikPakRetryOverlay()
    }

    private fun ensureDefaultSubtitleSelected() {
        player?.let { currentPlayer ->
            currentPlayer.addListener(object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    currentPlayer.removeListener(this)

                    // Skip if user already manually selected a subtitle
                    if (userManuallySelectedSubtitle) return

                    val trackSelector = trackSelector ?: return

                    // Get user's default subtitle language preference
                    val defaultSubtitleLang = SubtitleSettings.getDefaultSubtitleLanguage(this@AndroidTvTorrentPlayerActivity)

                    // If subtitles are explicitly disabled, don't auto-select
                    if (defaultSubtitleLang == "off") {
                        android.util.Log.d("AndroidTvPlayer", "PikPak: Subtitles disabled by user preference")
                        embeddedSubtitleSelected = false
                        return
                    }

                    // If no preference set, default to English
                    val targetLang = defaultSubtitleLang ?: "en"

                    // Search for subtitle track matching the preferred language
                    for (trackGroup in tracks.groups) {
                        if (trackGroup.type == C.TRACK_TYPE_TEXT) {
                            for (i in 0 until trackGroup.length) {
                                val format = trackGroup.getTrackFormat(i)
                                val language = format.language
                                val label = format.label
                                val id = format.id

                                // Check if track matches the preferred language using robust matching
                                if (LanguageMapper.matchesLanguage(targetLang, language) ||
                                    LanguageMapper.matchesLanguage(targetLang, label) ||
                                    LanguageMapper.matchesLanguage(targetLang, id)) {

                                    val override = TrackSelectionOverride(
                                        trackGroup.mediaTrackGroup,
                                        listOf(i)
                                    )
                                    trackSelector.parameters = trackSelector.parameters.buildUpon()
                                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                        .addOverride(override)
                                        .build()
                                    android.util.Log.d("AndroidTvPlayer", "PikPak: Auto-enabled $targetLang subtitles: label=$label lang=$language")
                                    embeddedSubtitleSelected = true
                                    return
                                }
                            }
                        }
                    }

                    // No embedded subtitle found - mark for addon subtitle selection
                    android.util.Log.d("AndroidTvPlayer", "PikPak: No $targetLang embedded subtitle found")
                    embeddedSubtitleSelected = false

                    // Try addon subtitles if already loaded
                    if (stremioSubtitles.isNotEmpty()) {
                        tryAutoSelectAddonSubtitle()
                    }
                }
            })
        }
    }

    /**
     * Whether the embedded text track ExoPlayer selected satisfies the user's
     * default-subtitle-language preference. With no preference set, any
     * selection satisfies (respect the file's own choice). With a preference,
     * only a matching-language track does — a forced/default English track
     * must NOT block addon auto-select of e.g. Spanish.
     */
    private fun selectedEmbeddedTrackSatisfiesPreference(tracks: Tracks): Boolean {
        val pref = SubtitleSettings.getDefaultSubtitleLanguage(this)
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_TEXT) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSelected(i)) continue
                if (pref == null) return true
                val f = group.getTrackFormat(i)
                if (LanguageMapper.matchesLanguage(pref, f.language) ||
                    LanguageMapper.matchesLanguage(pref, f.label) ||
                    LanguageMapper.matchesLanguage(pref, f.id)
                ) return true
            }
        }
        return false
    }

    /**
     * Try to auto-select a Stremio addon subtitle matching user's preferred language.
     * Called after Stremio subtitles are fetched, if no embedded subtitle was selected.
     */
    private fun tryAutoSelectAddonSubtitle() {
        // Skip when the offered subtitles are launch-supplied captions (YouTube):
        // they stay off until the user picks one, so we never force them on.
        if (suppressSubtitleAutoSelect) {
            return
        }

        // Skip if embedded subtitle was already selected
        if (embeddedSubtitleSelected) {
            return
        }

        // Skip if user manually selected a subtitle
        if (userManuallySelectedSubtitle) {
            return
        }

        // Check if ExoPlayer auto-selected an embedded subtitle via TrackSelector
        // preferences (covers non-PikPak content where ensureDefaultSubtitleSelected()
        // isn't called). Language-aware: a selected track only blocks addon
        // auto-select when it actually matches the user's preference.
        val tracksNow = player?.currentTracks
        if (tracksNow != null &&
            currentStremioSubtitleIndex == -1 &&
            selectedEmbeddedTrackSatisfiesPreference(tracksNow)
        ) {
            embeddedSubtitleSelected = true
            return
        }

        // Skip if addon subtitle is already selected
        if (currentStremioSubtitleIndex >= 0) {
            return
        }

        // Get user's default subtitle language preference
        val defaultSubtitleLang = SubtitleSettings.getDefaultSubtitleLanguage(this)

        // If subtitles are explicitly disabled, don't auto-select
        if (defaultSubtitleLang == "off") {
            return
        }

        // If no preference set, default to English
        val targetLang = defaultSubtitleLang ?: "en"

        // Search for addon subtitle matching the preferred language
        for ((index, sub) in stremioSubtitles.withIndex()) {
            if (sub.url in failedSubtitleUrls) continue   // skip subs that parsed to zero cues
            if (LanguageMapper.matchesLanguage(targetLang, sub.lang)) {
                android.util.Log.d("AndroidTvPlayer", "PikPak: Auto-selecting addon subtitle: ${sub.displayName} (${sub.lang})")
                loadStremioSubtitle(sub)
                currentStremioSubtitleIndex = index
                return
            }
        }

        android.util.Log.d("AndroidTvPlayer", "PikPak: No $targetLang addon subtitle found")
    }

    // D-pad navigation
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode

        // Handle subtitle line picker overlay (floats on top of video)
        if (linePickerOverlay?.isVisible == true) {
            return linePickerOverlay?.dispatchKey(event) ?: super.dispatchKeyEvent(event)
        }

        // Handle subtitle sync overlay (floats on top of video)
        if (syncOverlay?.isVisible == true) {
            return syncOverlay?.dispatchKey(event) ?: super.dispatchKeyEvent(event)
        }

        // Handle subtitle settings panel
        if (subtitlePanel?.isVisible == true) {
            return subtitlePanel?.dispatchKey(event) ?: super.dispatchKeyEvent(event)
        }

        if (sourceBrowser?.isVisible == true) {
            return sourceBrowser?.dispatchKey(event) ?: super.dispatchKeyEvent(event)
        }

        // Handle unified player menu (Miller columns). Only navigation keys are
        // consumed; volume/media keys fall through to the system. In edit mode
        // (search field focused) all keys fall through so typing + IME work,
        // except the boundary keys the controller uses to leave the field.
        if (unifiedMenu?.isVisible == true) {
            if (unifiedMenu?.inEditMode == true) {
                if (unifiedMenu?.handleEditModeKey(event) == true) return true
                return super.dispatchKeyEvent(event)
            }
            if (unifiedMenu?.dispatchKey(event) == true) return true
            return super.dispatchKeyEvent(event)
        }

        // IPTV: dedicated channel keys zap regardless of overlay state —
        // live-TV muscle memory on remotes that have them. First press only
        // (repeatCount gate, same as the LEFT/RIGHT zap path): a held key's
        // auto-repeat would otherwise re-prepare ExoPlayer tens of times a
        // second and hammer the panel with one stream open per repeat.
        if (isIptvMode &&
            iptvChannels.getOrNull(currentIptvIndex)?.isLive == true &&
            (iptvChannels.size > 1 || iptvZapPagingActive) &&
            (keyCode == KeyEvent.KEYCODE_CHANNEL_UP ||
                keyCode == KeyEvent.KEYCODE_CHANNEL_DOWN)
        ) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                zapIptvChannel(if (keyCode == KeyEvent.KEYCODE_CHANNEL_UP) 1 else -1)
            }
            return true
        }

        // Handle IPTV guide overlay
        if (iptvGuideVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_BACK -> {
                        if (iptvEpgVisible) {
                            hideIptvEpgPane()
                            iptvGuideList?.requestFocus()
                        } else {
                            hideIptvGuide()
                        }
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        if (isFocusInIptvEpgPanel()) {
                            val entry = iptvEpgEntry
                            hideIptvEpgPane()
                            val position = iptvChannelAdapter?.positionOf(entry) ?: 0
                            iptvGuideList?.findViewHolderForAdapterPosition(position)
                                ?.itemView?.requestFocus()
                            return true
                        }
                        // Only block left when focus is in the channel list
                        // to prevent escaping the guide. Allow left in search
                        // (cursor movement).
                        if (isFocusInIptvChannelList()) {
                            return true
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        // RIGHT on a channel row: its programme schedule —
                        // the same grammar as the IPTV page's guide list.
                        if (isFocusInIptvChannelList() && event.repeatCount == 0) {
                            focusedIptvGuideEntry()?.let { entry ->
                                if (entry.isLive) showIptvSchedulePane(entry)
                            }
                            return true
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        // Long-press up in channel list: jump to search bar
                        if (isFocusInIptvChannelList() && event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                            iptvGuideSearch?.requestFocus()
                            return true
                        }
                    }
                }
            }
            // Let DPAD up/down/right/center work normally within the guide
            return super.dispatchKeyEvent(event)
        }

        // Handle Stremio TV guide overlay
        if (stremioTvGuideVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_BACK -> {
                        hideStremioTvGuide()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        if (isFocusInStremioTvGuideList()) {
                            return true
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        if (isFocusInStremioTvGuideList() && event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                            stremioTvGuideSearch?.requestFocus()
                            return true
                        }
                    }
                }
            }
            return super.dispatchKeyEvent(event)
        }

        // Handle seekbar
        if (seekbarVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekBackward(step, isContinuous = event.repeatCount > 0)
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekForward(step, isContinuous = event.repeatCount > 0)
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                        confirmSeekPosition()
                        return true
                    }
                    KeyEvent.KEYCODE_BACK -> {
                        hideSeekbar()
                        return true
                    }
                }
            }
            return true
        }

        // Handle playlist
        if (playlistVisible) {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
                hidePlaylist()
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        // Handle Up Next card: OK plays next now, BACK dismisses it for this
        // episode, any other key soft-hides it (it may reappear near the end)
        // and proceeds with normal playback handling.
        if (upNextVisible) {
            when (keyCode) {
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                    if (event.action == KeyEvent.ACTION_DOWN) triggerUpNext()
                    return true
                }
                KeyEvent.KEYCODE_BACK -> {
                    if (event.action == KeyEvent.ACTION_DOWN) dismissUpNext()
                    return true
                }
                else -> {
                    if (event.action == KeyEvent.ACTION_DOWN) hideUpNextCard()
                }
            }
        }

        if (controlsMenuVisible && keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
            hideControlsMenu()
            return true
        }

        val focusInControls = isFocusInControlsOverlay()

        // Center button - play/pause (or badge click)
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            // Let the focused manual skip button receive its normal click.
            if (::skipSegmentButton.isInitialized && currentFocus == skipSegmentButton) {
                return super.dispatchKeyEvent(event)
            }
            // If focus is on stremio source badge, let click handler fire
            if (currentFocus == stremioSourceBadge) {
                return super.dispatchKeyEvent(event)
            }
            if (focusInControls) {
                return super.dispatchKeyEvent(event)
            }
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                handlePlayPauseToggleFromCenter()
            }
            return true
        }

        // Down button - show controls menu, or from badge go to progress bar
        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            // If focus is on Stremio badge, DOWN goes back to progress bar (or controls dock if seeking unavailable)
            if (currentFocus == stremioSourceBadge && controlsMenuVisible) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    val duration = player?.duration ?: 0
                    if (duration > 0) {
                        cinemaProgressContainer?.requestFocus()
                    } else {
                        pauseButton?.requestFocus()
                    }
                }
                return true
            }
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                if (!controlsMenuVisible) {
                    showControlsMenu()
                    scheduleHideControlsMenu()
                    return true
                } else if (!focusInControls) {
                    showControlsMenu()
                    scheduleHideControlsMenu()
                    return true
                }
            }
            return super.dispatchKeyEvent(event)
        }

        // Up button - from dock go to progress bar, from progress bar go to badge, otherwise show playlist/guide
        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
            // If focus is on progress bar and Stremio badge is available, UP goes to badge
            if (currentFocus == cinemaProgressContainer && controlsMenuVisible && stremioSources.isNotEmpty()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    stremioSourceBadge?.requestFocus()
                }
                return true
            }
            // If focus is in controls dock, UP goes to progress bar (or badge if seeking unavailable)
            if ((!isIptvMode ||
                    iptvChannels.getOrNull(currentIptvIndex)?.isLive == false) &&
                focusInControls && controlsMenuVisible && !cinemaSeekMode
            ) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    val duration = player?.duration ?: 0
                    if (duration > 0) {
                        cinemaProgressContainer?.requestFocus()
                    } else if (stremioSources.isNotEmpty()) {
                        stremioSourceBadge?.requestFocus()
                    }
                }
                return true
            }
            // Only live IPTV has a channel guide. IPTV VOD follows the normal
            // video-player controls and UP behavior.
            if (isIptvMode &&
                iptvChannels.getOrNull(currentIptvIndex)?.isLive == true
            ) {
                when (event.action) {
                    KeyEvent.ACTION_DOWN -> {
                        if (event.repeatCount == 0) {
                            iptvUpPressActive = true
                            iptvUpLongPressHandled = false
                        } else if (iptvUpPressActive &&
                            !iptvUpLongPressHandled &&
                            event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD
                        ) {
                            iptvUpLongPressHandled = true
                            hideControlsMenu()
                            showIptvChannelJumpDialog()
                        }
                    }
                    KeyEvent.ACTION_UP -> {
                        if (iptvUpPressActive && !iptvUpLongPressHandled) {
                            showIptvGuide()
                        }
                        iptvUpPressActive = false
                        iptvUpLongPressHandled = false
                    }
                }
                return true
            }
            // Stremio TV mode: UP opens the channel guide
            if (isStremioTvMode && stremioTvChannels.isNotEmpty()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    showStremioTvGuide()
                }
                return true
            }
            // Otherwise show playlist (if available)
            if (playlistMode == PlaylistMode.NONE) {
                return super.dispatchKeyEvent(event)
            }
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                showPlaylist()
            }
            return true
        }

        // Left/Right - seek (VOD) or channel zap (live IPTV)
        if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
            if (focusInControls) {
                return super.dispatchKeyEvent(event)
            }
            // Live channels: seeking a live stream is meaningless, so
            // LEFT/RIGHT zap to the previous/next channel instead (the
            // TiviMate grammar; the zap banner teaches it on every switch).
            // On-demand items keep their seek behavior untouched.
            if (isLiveIptvZapContext()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    zapIptvChannel(1)
                }
                return true
            }
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                    // Long-press: Show controls and focus progress bar for seeking
                    showControlsAndFocusProgressBar()
                } else if (event.repeatCount == 0) {
                    seekBy(SEEK_STEP_MS)
                }
            }
            return true
        }

        if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) {
            if (focusInControls) {
                return super.dispatchKeyEvent(event)
            }
            if (isLiveIptvZapContext()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    zapIptvChannel(-1)
                }
                return true
            }
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                    // Long-press: Show controls and focus progress bar for seeking
                    showControlsAndFocusProgressBar()
                } else if (event.repeatCount == 0) {
                    seekBy(-SEEK_STEP_MS)
                }
            }
            return true
        }

        return super.dispatchKeyEvent(event)
    }

    private fun isFocusInControlsOverlay(): Boolean {
        val overlay = controlsOverlay ?: return false
        var current = currentFocus
        while (current != null) {
            if (current == overlay) return true
            val parent = current.parent
            current = if (parent is View) parent else null
        }
        return false
    }

    private fun isFocusInIptvChannelList(): Boolean {
        val list = iptvGuideList ?: return false
        var current = currentFocus
        while (current != null) {
            if (current == list) return true
            val parent = current.parent
            current = if (parent is View) parent else null
        }
        return false
    }

    private fun handlePlayPauseToggleFromCenter() {
        showControlsMenu()
        togglePlayPause()
        if (player?.isPlaying == true) {
            scheduleHideControlsMenu()
        }
    }

    private fun togglePlayPause() {
        player?.let {
            if (it.isPlaying) {
                it.pause()
            } else {
                // An explicit press is the one thing that clears a sleep stop.
                sleepStopLatched = false
                // A verdict timeout or onStop may have parked the original
                // HLS while leaving the paused twin media item installed.
                // Resolve that identity before ordinary play/userRetry logic.
                if (restoreParkedIptvTwinIfNeeded()) return@let
                // LIVE: play on a dead stream must re-tune to the live edge.
                // A bare play() on an ENDED/errored live stream either does
                // nothing (media3 leaves it parked) or replays stale bytes —
                // both read as "the app is broken". The machine treats the
                // press as a fresh user ask: budget reset, immediate attempt.
                val deadLive = isIptvMode &&
                    iptvChannels.getOrNull(currentIptvIndex)?.isLive == true &&
                    (it.playbackState == Player.STATE_ENDED ||
                        it.playerError != null ||
                        iptvLiveRecovery.isSurrendered)
                if (deadLive) {
                    it.playWhenReady = true // eligibility reads this
                    iptvLiveRecovery.userRetry("play-press")
                } else {
                    it.play()
                }
            }
        }
        updatePauseButtonLabel()
    }

    private fun showControlsMenu() {
        val overlay = controlsOverlay ?: return
        cancelScheduledHideControlsMenu()

        // The channel panel and the dock share the bottom strip, so they merge
        // into one surface: the panel rides flush on top of the dock for as
        // long as it is open. Non-live playback has no panel to merge.
        val liveEntry = iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive }
        if (liveEntry != null) {
            showIptvZapBanner(liveEntry, docked = true)
        } else {
            hideIptvZapBanner()
        }

        // Hide subtitles when controls menu is shown
        subtitleOverlay.visibility = View.GONE

        // The title and controls are one presentation state: metadata updates
        // may change the text, but only this method is allowed to reveal it.
        titleContainer.animate().cancel()

        // Switch to OTT mode if we have series metadata, otherwise keep simple mode
        val model = payload
        val currentItem = model?.items?.getOrNull(currentIndex)
        val hasSeriesMetadata = model?.contentType?.lowercase(java.util.Locale.US) == "series" &&
                               currentItem?.season != null && currentItem.episode != null

        if (hasSeriesMetadata) {
            titleView.visibility = View.GONE
            titleOttContainer.visibility = View.VISIBLE
        } else {
            titleView.visibility = View.VISIBLE
            titleOttContainer.visibility = View.GONE
        }

        if (titleView.text?.isNotEmpty() == true || hasSeriesMetadata) {
            titleContainer.visibility = View.VISIBLE
            titleContainer.alpha = 1f
        }

        // Show Stremio source quality badge
        showStremioSourceBadge()

        overlay.animate().cancel()

        if (!controlsMenuVisible) {
            controlsMenuVisible = true
            overlay.visibility = View.VISIBLE
            overlay.alpha = 0f
            overlay.translationY = 30f  // Start slightly below for Apple TV effect
            overlay.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(300)
                .setInterpolator(android.view.animation.DecelerateInterpolator(1.5f))
                .withEndAction {
                    overlay.alpha = 1f
                    overlay.translationY = 0f
                }
                .start()
            pauseButton?.post {
                pauseButton?.requestFocus()
            }
        } else {
            overlay.alpha = 1f
            overlay.translationY = 0f
            overlay.visibility = View.VISIBLE
            pauseButton?.post {
                pauseButton?.requestFocus()
            }
        }
        updatePauseButtonLabel()
    }

    private fun hideControlsMenu() {
        val overlay = controlsOverlay ?: return

        // The merged panel leaves with the dock it was riding on. A floating
        // banner (raised by a zap) is left alone to finish its own timeout.
        if (iptvZapBannerDocked) hideIptvZapBanner()

        overlay.animate().cancel()

        if (!controlsMenuVisible) {
            overlay.visibility = View.GONE
            overlay.alpha = 0f
            overlay.translationY = 0f
            hideTitleImmediately()
            hideStremioSourceBadge()
            cancelScheduledHideControlsMenu()
            return
        }

        cancelScheduledHideControlsMenu()
        controlsMenuVisible = false

        // Hide title and revert to simple mode when controls hide
        titleContainer.animate()
            .alpha(0f)
            .setDuration(250)
            .withEndAction {
                titleContainer.visibility = View.GONE
                // Revert to simple mode for the next controls reveal.
                titleView.visibility = View.VISIBLE
                titleOttContainer.visibility = View.GONE
            }
            .start()

        // Hide Stremio source quality badge
        hideStremioSourceBadge()

        overlay.animate()
            .alpha(0f)
            .translationY(20f)  // Slide down slightly for premium effect
            .setDuration(250)
            .setInterpolator(android.view.animation.AccelerateInterpolator(1.2f))
            .withEndAction {
                if (!controlsMenuVisible) {
                    overlay.visibility = View.GONE
                    overlay.alpha = 0f
                    overlay.translationY = 0f
                    // Show subtitles when controls menu is hidden
                    subtitleOverlay.visibility = View.VISIBLE
                }
            }
            .start()
    }

    private fun hideTitleImmediately() {
        titleContainer.animate().cancel()
        titleContainer.visibility = View.GONE
        titleContainer.alpha = 0f
        // Reset the presentation mode for the next controls reveal.
        titleView.visibility = View.VISIBLE
        titleOttContainer.visibility = View.GONE
    }

    private fun scheduleHideControlsMenu() {
        if (!controlsMenuVisible) return
        controlsHandler.removeCallbacks(hideControlsRunnable)
        if (player?.isPlaying == true) {
            controlsHandler.postDelayed(hideControlsRunnable, CONTROLS_AUTO_HIDE_DELAY_MS)
        }
    }

    private fun cancelScheduledHideControlsMenu() {
        controlsHandler.removeCallbacks(hideControlsRunnable)
    }

    private fun updatePauseButtonLabel() {
        val button = pauseButton ?: return
        val playing = player?.isPlaying == true
        button.text = if (playing) "Pause" else "Play"
        val iconRes = if (playing) R.drawable.ic_pause else R.drawable.ic_play
        button.setCompoundDrawablesRelativeWithIntrinsicBounds(iconRes, 0, 0, 0)
    }

    private fun updateAspectButtonLabel() {
        aspectButton?.text = resizeModeLabels[resizeModeIndex]
    }

    private fun updateNightModeButtonLabel() {
        nightModeButton?.text = nightModeLabels[nightModeIndex]
    }

    // Premium Seekbar Progress Updates
    private fun startSeekbarProgressUpdates() {
        seekbarHandler.removeCallbacks(seekbarProgressRunnable)
        seekbarHandler.post(seekbarProgressRunnable)
    }

    private fun stopSeekbarProgressUpdates() {
        seekbarHandler.removeCallbacks(seekbarProgressRunnable)
    }

    private fun updateSeekbarProgress() {
        // Skip updates when in cinema seek mode (progress bar is being controlled manually)
        if (cinemaSeekMode) return

        val player = player ?: return

        val currentPosition = player.currentPosition
        val duration = player.duration

        if (duration > 0) {
            // Track the largest stable duration and the last genuine position so a
            // later transient short-duration reading or a spurious STATE_ENDED can be
            // recognised and not scrobbled as a full watch (see maxStableDurationMs).
            if (duration > maxStableDurationMs) maxStableDurationMs = duration
            if (currentPosition in 0..duration) lastRealPositionMs = currentPosition
            updateSkipSegmentState(currentPosition, duration)

            // Update Cinema Mode split time displays
            debrifyTimeCurrent?.text = formatTime(currentPosition)
            debrifyTimeTotal?.text = formatTime(duration)

            // Update legacy combined display (for compatibility)
            debrifyTimeDisplay?.text = "${formatTime(currentPosition)} / ${formatTime(duration)}"

            // Update progress line width
            debrifyProgressLine?.let { progressLine ->
                val progressPercentage = (currentPosition.toFloat() / duration.toFloat())
                val parentWidth = (progressLine.parent as? View)?.width ?: 0
                if (parentWidth > 0) {
                    val progressWidth = (parentWidth * progressPercentage).toInt()
                    val layoutParams = progressLine.layoutParams
                    layoutParams.width = progressWidth
                    progressLine.layoutParams = layoutParams
                }
            }

            // Update buffered-ahead width (translucent bar behind the played line).
            // bufferedPosition fills in chunks, so skip the relayout when the
            // computed width hasn't actually changed (avoids a layout pass each tick).
            cinemaProgressBuffered?.let { buffered ->
                val bufferedPercentage = (player.bufferedPosition.toFloat() / duration.toFloat())
                    .coerceIn(0f, 1f)
                val parentWidth = (buffered.parent as? View)?.width ?: 0
                if (parentWidth > 0) {
                    val bufferedWidth = (parentWidth * bufferedPercentage).toInt()
                    val layoutParams = buffered.layoutParams
                    if (layoutParams.width != bufferedWidth) {
                        layoutParams.width = bufferedWidth
                        buffered.layoutParams = layoutParams
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CINEMA MODE - Interactive Progress Bar (replaces old seekbar overlay)
    // ═══════════════════════════════════════════════════════════════════════════

    private fun showControlsAndFocusProgressBar() {
        if (!controlsMenuVisible) {
            showControlsMenu()
        }
        // Delay focus to allow controls to become visible
        controlsHandler.postDelayed({
            cinemaProgressContainer?.requestFocus()
        }, 100)
    }

    private fun setupCinemaProgressBar() {
        cinemaProgressContainer?.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                enterCinemaSeekMode()
            } else {
                exitCinemaSeekMode(confirm = false)
            }
        }

        cinemaProgressContainer?.setOnKeyListener { _, keyCode, event ->
            if (!cinemaSeekMode) return@setOnKeyListener false

            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekbarPosition = (seekbarPosition - step).coerceAtLeast(0)
                        updateCinemaSeekSpeed(step)
                        updateCinemaProgressUI()
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekbarPosition = (seekbarPosition + step).coerceAtMost(videoDuration)
                        updateCinemaSeekSpeed(step)
                        updateCinemaProgressUI()
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                        confirmCinemaSeek()
                        true
                    }
                    KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> {
                        exitCinemaSeekMode(confirm = false)
                        pauseButton?.requestFocus()
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_DOWN -> {
                        exitCinemaSeekMode(confirm = false)
                        pauseButton?.requestFocus()
                        true
                    }
                    else -> false
                }
            } else if (event.action == KeyEvent.ACTION_UP) {
                // Reset speed indicator when key is released
                if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT || keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
                    currentSeekSpeed = 1.0f
                    cinemaSpeedIndicator?.visibility = View.GONE
                }
                false
            } else false
        }
    }

    private fun enterCinemaSeekMode() {
        if (cinemaSeekMode || player == null) return

        seekbarPosition = player?.currentPosition ?: 0
        videoDuration = player?.duration ?: 0

        if (videoDuration <= 0) {
            // Don't trap focus — let DPAD navigation skip to Sources badge
            if (stremioSources.isNotEmpty()) {
                stremioSourceBadge?.requestFocus()
            } else {
                pauseButton?.requestFocus()
            }
            return
        }

        // Pause playback during seeking
        val wasPlaying = player?.isPlaying == true
        if (wasPlaying) {
            player?.pause()
        }

        cinemaSeekMode = true
        currentSeekSpeed = 1.0f

        // Reset animated progress to current position
        cinemaLastAnimatedProgress = if (videoDuration > 0) {
            seekbarPosition.toFloat() / videoDuration.toFloat()
        } else 0f

        // Show thumb with smooth entrance animation
        cinemaProgressThumb?.let { thumb ->
            thumb.visibility = View.VISIBLE
            thumb.alpha = 0f
            thumb.scaleX = 0.6f
            thumb.scaleY = 0.6f
            thumb.animate()
                .alpha(1f)
                .scaleX(1.15f)  // Slight overshoot
                .scaleY(1.15f)
                .setDuration(200)
                .setInterpolator(android.view.animation.OvershootInterpolator(2f))
                .withEndAction {
                    // Settle to normal size
                    thumb.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(100)
                        .start()
                }
                .start()
        }

        // Highlight current time with Netflix red
        debrifyTimeCurrent?.setTextColor(Color.parseColor("#E50914"))

        // Cache track width
        cinemaProgressBackground?.let { bg ->
            cinemaProgressTrackWidth = bg.width
        }

        updateCinemaProgressUI()
    }

    private fun exitCinemaSeekMode(confirm: Boolean) {
        if (!cinemaSeekMode) return

        cinemaSeekMode = false

        // Cancel any running progress animation
        cinemaProgressAnimator?.cancel()

        // Hide thumb with smooth exit animation
        cinemaProgressThumb?.let { thumb ->
            thumb.animate()
                .alpha(0f)
                .scaleX(0.3f)
                .scaleY(0.3f)
                .setDuration(150)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction {
                    thumb.visibility = View.INVISIBLE
                    thumb.scaleX = 1f
                    thumb.scaleY = 1f
                }
                .start()
        }

        // Fade current time color back to white
        debrifyTimeCurrent?.setTextColor(Color.WHITE)

        // Resume playback
        player?.play()
    }

    private fun confirmCinemaSeek() {
        if (!cinemaSeekMode || player == null) return
        player?.seekTo(seekbarPosition)
        exitCinemaSeekMode(confirm = true)
        pauseButton?.requestFocus()
    }

    private fun updateCinemaSeekSpeed(stepMs: Long) {
        currentSeekSpeed = stepMs / 10_000f  // Base is 10s = 1x
        // Speed indicator removed for cleaner UI - speed still affects seeking behavior
    }

    private fun updateCinemaProgressUI() {
        // Update time display
        debrifyTimeCurrent?.text = formatTime(seekbarPosition)
        debrifyTimeTotal?.text = formatTime(videoDuration)

        val targetProgress = if (videoDuration > 0) {
            seekbarPosition.toFloat() / videoDuration.toFloat()
        } else 0f

        val parentWidth = cinemaProgressTrackWidth
        if (parentWidth <= 0) return

        // Cancel any running animation
        cinemaProgressAnimator?.cancel()

        // Animate from current to target position
        cinemaProgressAnimator = ValueAnimator.ofFloat(cinemaLastAnimatedProgress, targetProgress).apply {
            duration = 80  // Quick but smooth
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val animatedProgress = animator.animatedValue as Float

                // Update progress bar width
                debrifyProgressLine?.let { progressLine ->
                    val progressWidth = (parentWidth * animatedProgress).toInt()
                    val layoutParams = progressLine.layoutParams
                    layoutParams.width = progressWidth
                    progressLine.layoutParams = layoutParams
                }

                // Update thumb position with smooth glide
                cinemaProgressThumb?.let { thumb ->
                    val thumbOffset = (parentWidth * animatedProgress) - (thumb.width / 2f)
                    thumb.translationX = thumbOffset.coerceAtLeast(0f)
                }
            }
            start()
        }

        cinemaLastAnimatedProgress = targetProgress
    }

    // Seekbar (Legacy - kept for compatibility)
    private fun showSeekbar() {
        if (seekbarVisible || player == null) return

        seekbarPosition = player?.currentPosition ?: 0
        videoDuration = player?.duration ?: 0

        if (videoDuration <= 0) {
            Toast.makeText(this, "Seeking not available", Toast.LENGTH_SHORT).show()
            return
        }

        val wasPlaying = player?.isPlaying == true
        if (wasPlaying) {
            player?.pause()
        }

        // Reset cached values
        seekbarBackgroundWidth = 0
        currentSeekSpeed = 1.0f
        seekbarSpeedIndicator.visibility = View.GONE

        updateSeekbarUI()

        seekbarVisible = true
        seekbarOverlay.visibility = View.VISIBLE
        seekbarOverlay.alpha = 0f
        seekbarOverlay.animate()
            .alpha(1f)
            .setDuration(200)
            .start()
    }

    private fun hideSeekbar() {
        if (!seekbarVisible) return

        seekbarVisible = false
        seekbarSpeedIndicator.visibility = View.GONE
        seekbarOverlay.animate()
            .alpha(0f)
            .setDuration(150)
            .withEndAction {
                seekbarOverlay.visibility = View.GONE
                player?.play()
            }
            .start()
    }

    private fun confirmSeekPosition() {
        if (!seekbarVisible || player == null) return
        player?.seekTo(seekbarPosition)
        hideSeekbar()
    }

    private fun getAcceleratedSeekStep(repeatCount: Int): Long {
        val baseStep = 10_000L          // 10 seconds
        val acceleration = 2_000L       // 2 seconds per repeat
        val maxStep = 120_000L          // 2 minutes cap

        val calculatedStep = baseStep + (repeatCount * acceleration)
        return calculatedStep.coerceAtMost(maxStep)
    }

    private fun seekBackward(stepMs: Long = 10_000L, isContinuous: Boolean = false) {
        seekbarPosition = (seekbarPosition - stepMs).coerceAtLeast(0)
        updateSeekSpeed(stepMs)
        updateSeekbarUI()

        // NO visual feedback - this is only called when seekbar is visible (long-press mode)
        // Visual feedback should only appear for quick single presses (handled in seekBy method)
    }

    private fun seekForward(stepMs: Long = 10_000L, isContinuous: Boolean = false) {
        seekbarPosition = (seekbarPosition + stepMs).coerceAtMost(videoDuration)
        updateSeekSpeed(stepMs)
        updateSeekbarUI()

        // NO visual feedback - this is only called when seekbar is visible (long-press mode)
        // Visual feedback should only appear for quick single presses (handled in seekBy method)
    }

    private fun updateSeekSpeed(stepMs: Long) {
        currentSeekSpeed = stepMs / 10_000f  // Base is 10s = 1x

        if (currentSeekSpeed > 1.0f) {
            seekbarSpeedIndicator.text = String.format("→ %.1fx", currentSeekSpeed)
            seekbarSpeedIndicator.visibility = View.VISIBLE
        } else {
            seekbarSpeedIndicator.visibility = View.GONE
        }
    }

    private fun updateSeekbarUI() {
        seekbarCurrentTime.text = formatTime(seekbarPosition)
        seekbarTotalTime.text = formatTime(videoDuration)

        val progressPercent = if (videoDuration > 0) {
            seekbarPosition.toFloat() / videoDuration.toFloat()
        } else 0f

        // Cache the background width on first use
        val seekbarBackground = findViewById<View>(R.id.seekbar_background)
        if (seekbarBackgroundWidth == 0 && seekbarBackground != null) {
            seekbarBackground.post {
                seekbarBackgroundWidth = seekbarBackground.width
                updateSeekbarPosition(progressPercent)
            }
        } else {
            updateSeekbarPosition(progressPercent)
        }
    }

    private fun updateSeekbarPosition(progressPercent: Float) {
        if (seekbarBackgroundWidth <= 0) return

        val progressWidth = (seekbarBackgroundWidth * progressPercent).toInt()

        // Update progress bar width
        val progressParams = seekbarProgress.layoutParams
        progressParams.width = progressWidth
        seekbarProgress.layoutParams = progressParams

        // Smoothly animate handle position
        val handleSize = seekbarHandle.width
        val handleX = progressWidth - (handleSize / 2f)
        seekbarHandle.animate()
            .translationX(handleX)
            .setDuration(0)  // Instant for responsiveness
            .start()
    }

    private fun seekBy(offsetMs: Long) {
        val p = player ?: return
        val position = p.currentPosition
        val duration = p.duration
        var target = position + offsetMs
        if (duration != C.TIME_UNSET) {
            target = target.coerceIn(0L, duration)
        } else {
            target = target.coerceAtLeast(0L)
        }
        p.seekTo(target)

        // Show visual feedback for quick seek
        val seekSeconds = kotlin.math.abs(offsetMs / 1000).toString() + "s"
        if (offsetMs > 0) {
            seekFeedbackManager.showSeekForward(seekSeconds)
        } else {
            seekFeedbackManager.showSeekBackward(seekSeconds)
        }
    }

    private fun currentSkipSegmentRequest(durationMs: Long): SkipSegmentRequest? {
        if (!skipSegmentsEnabled ||
            !TvSkipSegmentClients.supports(skipSegmentProviderId) ||
            isIptvMode ||
            durationMs <= 0L ||
            durationMs == C.TIME_UNSET
        ) {
            return null
        }

        val model = payload ?: return null
        if (model.contentType.lowercase(Locale.US) != "series") return null
        val imdbId = model.imdbId?.trim()?.takeIf { IMDB_ID_REGEX.matches(it) } ?: return null
        val item = model.items.getOrNull(currentIndex) ?: return null
        val season = item.season?.takeIf { it >= 0 } ?: return null
        val episode = item.episode?.takeIf { it >= 1 } ?: return null
        val durationSeconds = durationMs / 1_000L
        if (durationSeconds <= 0L) return null

        return SkipSegmentRequest(
            providerId = skipSegmentProviderId,
            imdbId = imdbId,
            season = season,
            episode = episode,
            durationSeconds = durationSeconds,
            key = "$skipSegmentProviderId:$imdbId:$season:$episode:$durationSeconds",
        )
    }

    private fun updateSkipSegmentState(positionMs: Long, durationMs: Long) {
        if (!::skipSegmentButton.isInitialized) return

        // Between playlist items the player still reports the OUTGOING media's
        // position and duration for a moment, while currentIndex already names
        // the incoming episode. Judging the new episode against those makes the
        // button flash on as soon as next-episode is pressed — the old position
        // is usually deep in the outgoing episode, which lands inside a segment
        // — and fetches its segments against a duration that isn't its own,
        // which can select or validate the wrong release. Wait until the new
        // media is prepared; resetSkipSegmentState() has already hidden the button.
        if (!hasEverBeenReady) {
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
        val segment = if (upNextVisible) null else skipSegments.segmentAt(positionMs)
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
            val liveDuration = player?.duration ?: C.TIME_UNSET
            if (currentSkipSegmentRequest(liveDuration)?.key != request.key) return@launch

            if (skipSegmentCache.size >= MAX_SKIP_SEGMENT_CACHE_ENTRIES) {
                skipSegmentCache.keys.firstOrNull()?.let { skipSegmentCache.remove(it) }
            }
            skipSegmentCache[request.key] = result
            skipSegments = result
            loadedSkipSegmentKey = request.key
            loadingSkipSegmentKey = null
            skipSegmentFetchJob = null
            val p = player ?: return@launch
            updateSkipSegmentState(p.currentPosition, p.duration)
        }
    }

    private fun presentSkipSegment(segment: TvSkipSegment?, requestKey: String?) {
        val button = skipSegmentButton
        activeSkipSegment = segment
        if (segment == null || requestKey == null) {
            if (button.visibility != View.GONE) {
                if (currentFocus == button) playerView.requestFocus()
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

        val targetTranslationY = if (controlsMenuVisible) {
            -128f * resources.displayMetrics.density
        } else {
            0f
        }
        if (kotlin.math.abs(button.translationY - targetTranslationY) > 0.5f) {
            button.animate().translationY(targetTranslationY).setDuration(180L).start()
        }

        val focusKey = "$requestKey:${segment.type}:${segment.startMs}"
        val canOfferFocus = !controlsMenuVisible &&
            !playlistVisible &&
            !seekbarVisible &&
            !upNextVisible &&
            subtitlePanel?.isVisible != true &&
            unifiedMenu?.isVisible != true &&
            sourceBrowser?.isVisible != true &&
            syncOverlay?.isVisible != true &&
            linePickerOverlay?.isVisible != true
        if (canOfferFocus && skipFocusOfferedKey != focusKey) {
            skipFocusOfferedKey = focusKey
            button.post { if (button.visibility == View.VISIBLE) button.requestFocus() }
        }
    }

    private fun skipActiveSegment() {
        val p = player ?: return
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

        p.seekTo(target)
        if (::seekFeedbackManager.isInitialized) {
            val seconds = ((target - position) / 1_000L).coerceAtLeast(1L)
            seekFeedbackManager.showSeekForward("${seconds}s")
        }
        presentSkipSegment(null, null)
    }

    // ── Sleep timer ───────────────────────────────────────────────────────────

    /** Whole minutes left, rounded up so a fresh 30-minute timer reads "30". */
    private fun sleepTimerMinutesLeft(): Int {
        if (sleepTimerMode != SleepTimerMode.COUNTDOWN) return 0
        val remaining = sleepTimerDeadlineElapsedMs - android.os.SystemClock.elapsedRealtime()
        return kotlin.math.ceil(remaining / 60_000.0).toInt().coerceAtLeast(0)
    }

    private fun sleepTimerValueLabel(): String = when (sleepTimerMode) {
        SleepTimerMode.OFF -> "Off"
        SleepTimerMode.END_OF_ITEM -> "End of episode"
        SleepTimerMode.COUNTDOWN -> "${sleepTimerMinutesLeft()} min"
    }

    private fun startSleepCountdown(minutes: Int) {
        cancelSleepTimer()
        val durationMs = minutes * 60_000L
        sleepTimerMode = SleepTimerMode.COUNTDOWN
        // elapsedRealtime, not currentTimeMillis: the countdown must survive a
        // clock adjustment and keep counting while the box is dozing.
        sleepTimerDeadlineElapsedMs = android.os.SystemClock.elapsedRealtime() + durationMs
        val runnable = Runnable { fireSleepTimer() }
        sleepTimerRunnable = runnable
        sleepTimerHandler.postDelayed(runnable, durationMs)
        Toast.makeText(this, "Sleep timer set for $minutes minutes", Toast.LENGTH_SHORT).show()
    }

    private fun armSleepAtEndOfItem() {
        cancelSleepTimer()
        sleepTimerMode = SleepTimerMode.END_OF_ITEM
        Toast.makeText(this, "Sleep timer: stopping at the end of this episode", Toast.LENGTH_SHORT).show()
    }

    private fun cancelSleepTimer(announce: Boolean = false) {
        sleepTimerRunnable?.let { sleepTimerHandler.removeCallbacks(it) }
        sleepTimerRunnable = null
        sleepTimerMode = SleepTimerMode.OFF
        sleepTimerDeadlineElapsedMs = 0L
        if (announce) Toast.makeText(this, "Sleep timer off", Toast.LENGTH_SHORT).show()
    }

    /**
     * Stop for the night: persist the position first (losing someone's place
     * overnight is exactly the moment this feature is supposed to be helping),
     * pause, then release the screen so the TV can sleep on its own.
     */
    private fun fireSleepTimer() {
        cancelSleepTimer()
        sleepStopLatched = true
        sendProgress(completed = false)
        player?.pause()
        releaseScreenForSleep()
        Toast.makeText(this, "Sleep timer ended — paused", Toast.LENGTH_LONG).show()
    }

    /**
     * Let the screen go dark. BOTH holds have to go: the activity adds
     * FLAG_KEEP_SCREEN_ON on create, and the layout independently sets
     * `android:keepScreenOn="true"` on the PlayerView — a view holding it
     * re-applies the window flag, so clearing only one keeps the TV lit.
     */
    private fun releaseScreenForSleep() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (::playerView.isInitialized) playerView.keepScreenOn = false
    }

    /** Re-take both holds when playback resumes. Idempotent. */
    private fun holdScreenForPlayback() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (::playerView.isInitialized) playerView.keepScreenOn = true
    }

    private fun resetSkipSegmentState() {
        skipSegmentFetchGeneration++
        skipSegmentFetchJob?.cancel()
        skipSegmentFetchJob = null
        loadingSkipSegmentKey = null
        loadedSkipSegmentKey = null
        skipSegments = TvSkipSegments.EMPTY
        activeSkipSegment = null
        skipFocusOfferedKey = null
        if (::skipSegmentButton.isInitialized) presentSkipSegment(null, null)
    }

    // Playlist
    private fun showPlaylist() {
        android.util.Log.d("PlaylistNav", "showPlaylist: Starting - playlistMode=$playlistMode")

        if (playlistMode == PlaylistMode.NONE || playlistAdapter == null) {
            android.util.Log.d("PlaylistNav", "showPlaylist: Exiting early - no playlist adapter")
            return
        }

        playlistVisible = true
        playlistOverlay.visibility = View.VISIBLE

        when (playlistMode) {
            PlaylistMode.SERIES -> alignSeriesTabsForCurrentEpisode()
            PlaylistMode.COLLECTION -> alignMovieTabsForCurrentItem()
            else -> Unit
        }

        val activePosition = playlistAdapter?.getActiveItemPosition() ?: -1
        android.util.Log.d("PlaylistNav", "showPlaylist: activePosition=$activePosition, adapter.itemCount=${playlistView.adapter?.itemCount}")

        if (activePosition != -1) {
            playlistView.post {
                android.util.Log.d("PlaylistNav", "showPlaylist: Scrolling to position $activePosition")
                playlistView.scrollToPosition(activePosition)
                playlistView.postDelayed({
                    val viewHolder = playlistView.findViewHolderForAdapterPosition(activePosition)
                    android.util.Log.d("PlaylistNav", "showPlaylist: ViewHolder found=${viewHolder != null} for position $activePosition")
                    if (viewHolder != null) {
                        android.util.Log.d("PlaylistNav", "showPlaylist: Requesting focus on viewHolder at position $activePosition")
                        viewHolder.itemView.requestFocus()
                    } else {
                        android.util.Log.d("PlaylistNav", "showPlaylist: Requesting focus on playlistView itself")
                        playlistView.requestFocus()
                    }
                }, 100)
            }
        } else {
            playlistView.post {
                android.util.Log.d("PlaylistNav", "showPlaylist: No active position, requesting focus on playlistView")
                playlistView.requestFocus()
            }
        }
    }

    private fun alignSeriesTabsForCurrentEpisode() {
        val adapter = seriesPlaylistAdapter ?: return
        val currentSeason = payload?.items?.getOrNull(currentIndex)?.season ?: return
        if (currentSeason <= 0 || seasonTabs.isEmpty()) return
        val seasons = adapter.availableSeasons
        val tabIndex = seasons.indexOf(currentSeason)
        if (tabIndex >= 0 && tabIndex < seasonTabs.size) {
            selectSeasonTab(tabIndex, adapter, scrollToTop = false)
        }
    }

    private fun alignMovieTabsForCurrentItem() {
        val adapter = moviePlaylistAdapter ?: return
        val groups = movieGroups ?: return
        val groupIndex = groups.getGroupIndex(currentIndex)
        if (groupIndex >= 0) {
            selectMovieTab(groupIndex, adapter, scrollToTop = false)
        }
    }

    private fun getNextPlayableIndex(fromIndex: Int): Int? {
        val model = payload ?: return null

        // For series content, use pre-computed navigation map from Flutter
        // This mirrors mobile video_player_screen.dart's navigation exactly
        if (playlistMode == PlaylistMode.SERIES && model.nextEpisodeMap.isNotEmpty()) {
            val nextIndex = model.nextEpisodeMap[fromIndex]
            android.util.Log.d("AndroidTvPlayer", "getNextPlayableIndex - series mode, fromIndex: $fromIndex, nextIndex: $nextIndex")
            return nextIndex
        }

        // For collections, continue using movie group logic
        if (playlistMode == PlaylistMode.COLLECTION) {
            val groups = movieGroups ?: return null
            val currentGroup = groups.findGroupContaining(fromIndex) ?: return null
            val source = currentGroup.fileIndices

            if (source.isNullOrEmpty()) {
                return null
            }

            val positionInGroup = source.indexOf(fromIndex)
            if (positionInGroup == -1) {
                return null
            }

            return if (positionInGroup + 1 < source.size) {
                source[positionInGroup + 1]
            } else {
                null
            }
        }

        // Fallback for single/unknown modes: simple sequential navigation
        val next = fromIndex + 1
        return if (next < model.items.size) next else null
    }

    private fun getPrevPlayableIndex(fromIndex: Int): Int? {
        val model = payload ?: return null

        // For series content, use pre-computed navigation map from Flutter
        if (playlistMode == PlaylistMode.SERIES && model.prevEpisodeMap.isNotEmpty()) {
            val prevIndex = model.prevEpisodeMap[fromIndex]
            android.util.Log.d("AndroidTvPlayer", "getPrevPlayableIndex - series mode, fromIndex: $fromIndex, prevIndex: $prevIndex")
            return prevIndex
        }

        // For collections, use movie group logic
        if (playlistMode == PlaylistMode.COLLECTION) {
            val groups = movieGroups ?: return null
            val currentGroup = groups.findGroupContaining(fromIndex) ?: return null
            val source = currentGroup.fileIndices

            if (source.isNullOrEmpty()) {
                return null
            }

            val positionInGroup = source.indexOf(fromIndex)
            if (positionInGroup <= 0) {
                return null
            }

            return source[positionInGroup - 1]
        }

        // Fallback for single/unknown modes: simple sequential navigation
        val prev = fromIndex - 1
        return if (prev >= 0) prev else null
    }

    private fun computeMovieGroups(items: List<PlaybackItem>): MovieGroups {
        if (items.isEmpty()) {
            return MovieGroups(emptyList())
        }

        // Check if payload contains collection groups
        val payloadGroups = payload?.collectionGroups
        if (!payloadGroups.isNullOrEmpty()) {
            // Use groups from Flutter payload
            val groups = payloadGroups.map { group ->
                CollectionGroup(
                    name = group.optString("name", "Group"),
                    fileIndices = mutableListOf<Int>().apply {
                        val indicesArray = group.optJSONArray("fileIndices")
                        if (indicesArray != null) {
                            for (i in 0 until indicesArray.length()) {
                                add(indicesArray.getInt(i))
                            }
                        }
                    }
                )
            }.filter { it.fileIndices.isNotEmpty() } // Only include non-empty groups

            android.util.Log.d("AndroidTvPlayer", "Using ${groups.size} collection groups from payload")
            return MovieGroups(groups)
        }

        // Fallback: compute Main/Extras groups based on file size (40% threshold)
        // This maintains backward compatibility
        var maxSize = -1L
        items.forEach { item ->
            val size = item.sizeBytes ?: -1L
            if (size > maxSize) {
                maxSize = size
            }
        }

        val threshold = if (maxSize > 0) (maxSize * 0.40).toLong() else -1L
        val main = mutableListOf<Int>()
        val extras = mutableListOf<Int>()

        items.forEachIndexed { index, item ->
            val size = item.sizeBytes ?: -1L
            val isSmall = threshold > 0 && size > 0 && size < threshold
            if (isSmall) {
                extras.add(index)
            } else {
                main.add(index)
            }
        }

        if (main.isEmpty()) {
            main.addAll(extras)
            extras.clear()
        }

        val yearRegex = Regex("\\b(19|20)\\d{2}\\b")
        fun yearOf(index: Int): Int? {
            val match = yearRegex.find(items[index].title)
            return match?.value?.toIntOrNull()
        }
        fun sizeOf(index: Int): Long = items[index].sizeBytes ?: -1L

        main.sortWith { a, b ->
            val yearA = yearOf(a)
            val yearB = yearOf(b)
            when {
                yearA != null && yearB != null && yearA != yearB -> yearA - yearB
                else -> sizeOf(b).compareTo(sizeOf(a))
            }
        }

        extras.sortWith { a, b ->
            sizeOf(a).compareTo(sizeOf(b))
        }

        val groups = mutableListOf<CollectionGroup>()
        if (main.isNotEmpty()) {
            groups.add(CollectionGroup("Main", main))
        }
        if (extras.isNotEmpty()) {
            groups.add(CollectionGroup("Extras", extras))
        }

        android.util.Log.d("AndroidTvPlayer", "Computed ${groups.size} collection groups (fallback)")
        return MovieGroups(groups)
    }

    private fun hidePlaylist() {
        playlistVisible = false
        playlistOverlay.visibility = View.GONE
    }

    // Next overlay
    private fun showNextOverlay(nextItem: PlaybackItem) {
        nextText.text = nextItem.title
        nextSubtext.visibility = View.GONE
        fadeInNextOverlay()
    }

    private fun fadeInNextOverlay() {
        nextOverlay.animate().cancel()
        nextOverlay.alpha = 0f
        nextOverlay.visibility = View.VISIBLE
        nextOverlay.animate().alpha(1f).setDuration(220).start()
    }

    private fun hideNextOverlay() {
        if (nextOverlay.visibility != View.VISIBLE) return
        nextOverlay.animate().cancel()
        nextOverlay.animate().alpha(0f).setDuration(160).withEndAction {
            nextOverlay.visibility = View.GONE
            nextOverlay.alpha = 1f
        }.start()
    }

    // ═══════════════════════════════════════════════════════════════
    // UP NEXT CARD
    // ═══════════════════════════════════════════════════════════════

    // True only during plain playback (no overlay/panel/controls on screen).
    private fun isCleanPlaybackState(): Boolean {
        if (controlsMenuVisible || seekbarVisible || playlistVisible) return false
        if (iptvGuideVisible || stremioTvGuideVisible) return false
        if (subtitlePanel?.isVisible == true) return false
        if (linePickerOverlay?.isVisible == true || syncOverlay?.isVisible == true) return false
        if (unifiedMenu?.isVisible == true) return false
        if (sourceBrowser?.isVisible == true) return false
        if (nextOverlay.visibility == View.VISIBLE) return false
        if (pikPakReactivationIndicator.visibility == View.VISIBLE) return false
        return true
    }

    // Called periodically from the progress loop. Shows the Up Next card when
    // the current episode is near its end and a playable next item exists.
    private fun maybeShowUpNext() {
        if (upNextVisible) return
        if (isIptvMode || isStremioTvMode) return
        if (upNextDismissedForIndex == currentIndex) return
        if (!isCleanPlaybackState()) return
        val p = player ?: return
        if (p.playbackState != Player.STATE_READY || !p.isPlaying) return
        val duration = p.duration
        if (duration <= UP_NEXT_MIN_DURATION_MS) return
        val remaining = duration - p.currentPosition
        if (remaining <= 0 || remaining > UP_NEXT_THRESHOLD_MS) return
        // Mirror the STATE_ENDED auto-advance: shuffle picks a random eligible
        // episode, otherwise advance to the linear next.
        val nextIndex = if (continuousShuffleEnabled) {
            pickShuffleIndex()
        } else {
            getNextPlayableIndex(currentIndex)
        } ?: return
        showUpNextCard(nextIndex)
    }

    private val upNextTicker = object : Runnable {
        override fun run() {
            val p = player
            val target = upNextTargetIndex
            val duration = p?.duration ?: 0L
            if (p == null || target == null || duration <= 0) {
                hideUpNextCard()
                return
            }
            // A panel/controls opened — pull the card; the progress loop can
            // re-show it later if still near the end.
            if (!isCleanPlaybackState()) {
                hideUpNextCard()
                return
            }
            val remaining = duration - p.currentPosition
            // User seeked back well before the end — drop the card.
            if (remaining > UP_NEXT_THRESHOLD_MS + 5_000L) {
                hideUpNextCard()
                return
            }
            if (remaining <= UP_NEXT_TICK_MS + 250L) {
                triggerUpNext()
                return
            }
            val secs = ((remaining + 999L) / 1000L).toInt()
            upNextCountdown.text = "Starting in ${secs}s"
            upNextHandler.postDelayed(this, UP_NEXT_TICK_MS)
        }
    }

    private fun showUpNextCard(nextIndex: Int) {
        val model = payload ?: return
        if (nextIndex < 0 || nextIndex >= model.items.size) return
        val item = model.items[nextIndex]
        upNextTargetIndex = nextIndex

        val badge = item.seasonEpisodeLabel()
        upNextTitle.text = if (badge.isNotEmpty()) "$badge · ${item.title}" else item.title

        val art = item.artwork
        if (!art.isNullOrEmpty()) {
            upNextPoster.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(this).load(art).into(upNextPoster)
        } else {
            upNextPoster.visibility = View.GONE
        }

        upNextVisible = true
        upNextCard.visibility = View.VISIBLE
        upNextCard.alpha = 0f
        upNextCard.translationX = 40f
        upNextCard.animate().alpha(1f).translationX(0f).setDuration(220).start()

        upNextHandler.removeCallbacks(upNextTicker)
        upNextHandler.post(upNextTicker)
    }

    private fun triggerUpNext() {
        // playItem() hides the card (and cancels the ticker) as part of its
        // per-item reset, so no explicit hide is needed here.
        val target = upNextTargetIndex ?: return
        playItem(target)
    }

    private fun dismissUpNext() {
        upNextDismissedForIndex = currentIndex
        hideUpNextCard()
    }

    private fun hideUpNextCard() {
        upNextHandler.removeCallbacks(upNextTicker)
        upNextTargetIndex = null
        if (!upNextVisible) {
            upNextCard.visibility = View.GONE
            return
        }
        upNextVisible = false
        upNextCard.animate().alpha(0f).translationX(40f).setDuration(160).withEndAction {
            upNextCard.visibility = View.GONE
            upNextCard.translationX = 0f
        }.start()
    }

    // ═══════════════════════════════════════════════════════════════
    // IPTV MODE
    // ═══════════════════════════════════════════════════════════════

    private fun initIptvMode(json: JSONObject) {
        isIptvMode = true
        android.util.Log.d("AndroidTvPlayer", "initIptvMode: Starting IPTV mode")

        // IPTV mode returns before parsePayload, so the decoder preference is
        // read here too — this is the ONLY path where it has any effect.
        iptvDecoderMode = json.optString("iptvDecoder", "auto")

        iptvSourceId = json.optString("sourceId").takeIf { it.isNotEmpty() }
        iptvSourceName = json.optString("sourceName").takeIf { it.isNotEmpty() } ?: "IPTV"
        iptvContentType = json.optString("contentType").takeIf {
            it in setOf("live", "vod", "series", "episodes")
        } ?: "live"
        iptvSelectedCategory =
            json.optString("selectedCategory").takeIf { it.isNotEmpty() }
        iptvSources = parseIptvSources(json.optJSONArray("sources"))
        iptvLists = parseIptvLists(json.optJSONArray("lists"))
        iptvCategories = parseStringList(json.optJSONArray("categories"))
        // Playback owns this context until the user starts browsing another
        // source/category. CH +/- can then restore the actual playing source
        // instead of whatever catalog happens to be visible in the guide.
        iptvZapSourceId = iptvSourceId
        iptvZapSourceName = iptvSourceName
        iptvZapContentType = iptvContentType
        iptvZapCategory = iptvSelectedCategory
        iptvZapCategories = iptvCategories.toMutableList()
        iptvZapOwnsUiContext = true

        iptvChannels = parseIptvChannels(json.optJSONArray("channels") ?: JSONArray())
        iptvChannels.forEach { channel ->
            if (channel.sourceId == null) channel.sourceId = iptvSourceId
            if (channel.sourceName == null) channel.sourceName = iptvSourceName
        }
        iptvBrowseChannels = iptvChannels.toMutableList()

        currentIptvIndex = json.optInt("startIndex", 0).coerceIn(0, iptvChannels.lastIndex.coerceAtLeast(0))
        if (iptvChannels.isNotEmpty()) {
            iptvChannels[currentIptvIndex].isCurrent = true
        }

        val title = json.optString("title")
        android.util.Log.d("AndroidTvPlayer", "initIptvMode: ${iptvChannels.size} channels, startIndex=$currentIptvIndex, title=$title")

        // Xtream series audio memory (see fields). Applied to the TrackSelector
        // below so it carries across every episode automatically.
        iptvSeriesAudioKey = json.optString("seriesAudioKey").takeIf { it.isNotEmpty() }
        iptvPreferredAudioLang = json.optString("preferredAudioLang").takeIf { it.isNotEmpty() }

        // Bind views and setup player
        bindViews()
        setupPlayer()
        setupSeekbar()
        setupControls()
        setupIptvControls()

        // A remembered per-series audio language overrides setupPlayer's global
        // default. It's a TrackSelector parameter, so it re-applies to every
        // episode on switch without any per-media work.
        iptvPreferredAudioLang?.let { setIptvPreferredAudioLang(it) }

        // Show the Previous-episode control only for a non-live episode list.
        updateIptvEpisodeControls()

        // Initialize seek feedback manager
        seekFeedbackManager = SeekFeedbackManager(findViewById(android.R.id.content))
        setupBackPressHandler()
        setupMetadataReceiver()

        // Initialize Stremio subtitle service
        stremioSubtitleService = StremioSubtitleService(this)

        // Bind IPTV guide overlay views
        iptvGuideOverlay = findViewById(R.id.iptv_guide_overlay)
        iptvGuideList = findViewById(R.id.iptv_guide_list)
        iptvGuideSearch = findViewById(R.id.iptv_guide_search)
        iptvGuideTitle = findViewById(R.id.iptv_guide_title)
        iptvGuideCountText = findViewById(R.id.iptv_guide_count)
        iptvSourceButton = findViewById(R.id.iptv_source_button)
        iptvCategoryButton = findViewById(R.id.iptv_category_button)
        iptvBrowseLoading = findViewById(R.id.iptv_browse_loading)
        iptvGuideCurrentName = findViewById(R.id.iptv_guide_current_name)
        iptvGuideCurrentGroup = findViewById(R.id.iptv_guide_current_group)
        iptvGuideCurrentEpg = findViewById(R.id.iptv_guide_current_epg)
        iptvGuideNowPlaying = findViewById(R.id.iptv_guide_now_playing)
        iptvGuideNowLogo = findViewById(R.id.iptv_guide_now_logo)
        iptvGuideNowLetter = findViewById(R.id.iptv_guide_now_letter)
        iptvEpgPanel = findViewById(R.id.iptv_epg_panel)
        iptvEpgLogo = findViewById(R.id.iptv_epg_logo)
        iptvEpgLetter = findViewById(R.id.iptv_epg_letter)
        iptvEpgChannelName = findViewById(R.id.iptv_epg_channel_name)
        iptvEpgChannelGroup = findViewById(R.id.iptv_epg_channel_group)
        iptvEpgDate = findViewById(R.id.iptv_epg_date)
        iptvEpgLoading = findViewById(R.id.iptv_epg_loading)
        iptvEpgEmpty = findViewById(R.id.iptv_epg_empty)
        iptvEpgList = findViewById(R.id.iptv_epg_list)

        setupIptvOverlay()

        // Override the normal List button only for live television. VOD keeps
        // the standard video controls installed by setupControls().
        val playlistButton: AppCompatButton? = playerView.findViewById(R.id.debrify_playlist_button)
        if (iptvChannels.getOrNull(currentIptvIndex)?.isLive == true) {
            playlistButton?.text = "Guide"
            playlistButton?.setOnClickListener {
                hideControlsMenu()
                toggleIptvGuide()
            }
        }

        // Play initial channel
        if (iptvChannels.isNotEmpty()) {
            val initial = iptvChannels[currentIptvIndex]
            playIptvChannel(currentIptvIndex)
            bootstrapInitialIptvZapPaging(initial)
        }
    }

    private fun parseIptvSources(array: JSONArray?): MutableList<IptvSourceEntry> {
        if (array == null) return mutableListOf()
        return MutableList(array.length()) { index ->
            val source = array.optJSONObject(index) ?: JSONObject()
            IptvSourceEntry(
                id = source.optString("id"),
                name = source.optString("name").ifEmpty { "IPTV" },
                isFavorites = source.optBoolean("isFavorites"),
                isContinue = source.optBoolean("isContinue"),
                isXtream = source.optBoolean("isXtream"),
                isList = source.optBoolean("isList"),
                listId = source.optString("listId").takeIf { it.isNotEmpty() },
                connectionResourceId = source.optString("connectionResourceId")
                    .takeIf { it.isNotEmpty() },
                connectionResourceRevision = if (source.has("connectionResourceRevision"))
                    source.optLong("connectionResourceRevision") else null,
            )
        }.filterTo(mutableListOf()) { it.id.isNotEmpty() && !it.isContinue }
    }

    private fun parseIptvLists(array: JSONArray?): MutableList<IptvListEntry> {
        if (array == null) return mutableListOf()
        return MutableList(array.length()) { index ->
            val entry = array.optJSONObject(index) ?: JSONObject()
            IptvListEntry(
                id = entry.optString("id"),
                name = entry.optString("name").ifEmpty { "List" },
                isBuiltin = entry.optBoolean("isBuiltin"),
            )
        }.filterTo(mutableListOf()) { it.id.isNotEmpty() }
    }

    private fun parseStringList(array: JSONArray?): MutableList<String> {
        if (array == null) return mutableListOf()
        return MutableList(array.length()) { index -> array.optString(index) }
            .filterTo(mutableListOf()) { it.isNotEmpty() }
    }

    private fun parseIptvChannels(array: JSONArray): MutableList<IptvChannelEntry> =
        MutableList(array.length()) { index ->
            val channel = array.optJSONObject(index) ?: JSONObject()
            iptvChannelEntry(
                index = index,
                channelNumber = channel.optInt("channelNumber", 0).takeIf { it > 0 },
                name = channel.optString("name"),
                url = channel.optString("url"),
                logoUrl = channel.optString("logoUrl").takeIf { it.isNotEmpty() },
                group = channel.optString("group").takeIf { it.isNotEmpty() },
                contentType = channel.optString("contentType"),
                duration = channel.optInt("duration", -1),
                sourceId = channel.optString("sourceId").takeIf { it.isNotEmpty() },
                sourceName = channel.optString("sourceName").takeIf { it.isNotEmpty() },
                isFavorite = channel.optBoolean("isFavorite"),
                seriesId = channel.optString("seriesId").takeIf { it.isNotEmpty() },
                seriesName = channel.optString("seriesName").takeIf { it.isNotEmpty() },
                season = channel.optInt("season", -1).takeIf { it >= 0 },
                episode = channel.optInt("episode", -1).takeIf { it >= 0 },
                hasNextEpisode =
                    channel.optBoolean("hasNextEpisode").takeIf {
                        channel.has("hasNextEpisode")
                    },
                resumePositionMs = channel.optLong("resumePositionMs", 0L),
                headers = channel.optJSONObject("httpHeaders")?.let { obj ->
                    buildMap {
                        for (key in obj.keys()) {
                            obj.optString(key).takeIf { it.isNotEmpty() }?.let { value ->
                                put(
                                    if (key.equals("User-Agent", ignoreCase = true)) {
                                        "User-Agent"
                                    } else {
                                        key
                                    },
                                    value,
                                )
                            }
                        }
                    }
                } ?: emptyMap(),
            )
        }

    private fun parseIptvChannels(raw: List<*>): MutableList<IptvChannelEntry> =
        raw.mapIndexedNotNullTo(mutableListOf()) { index, item ->
            val channel = item as? Map<*, *> ?: return@mapIndexedNotNullTo null
            val headers = (channel["httpHeaders"] as? Map<*, *>)?.entries
                ?.mapNotNull { (key, value) ->
                    val name = key as? String ?: return@mapNotNull null
                    val text = value?.toString()?.takeIf { it.isNotEmpty() }
                        ?: return@mapNotNull null
                    (if (name.equals("User-Agent", ignoreCase = true)) {
                        "User-Agent"
                    } else {
                        name
                    }) to text
                }?.toMap() ?: emptyMap()
            iptvChannelEntry(
                index = index,
                channelNumber = (channel["channelNumber"] as? Number)
                    ?.toInt()
                    ?.takeIf { it > 0 },
                name = channel["name"] as? String ?: return@mapIndexedNotNullTo null,
                url = channel["url"] as? String ?: return@mapIndexedNotNullTo null,
                logoUrl = (channel["logoUrl"] as? String)?.takeIf { it.isNotEmpty() },
                group = (channel["group"] as? String)?.takeIf { it.isNotEmpty() },
                contentType = channel["contentType"] as? String ?: "",
                duration = (channel["duration"] as? Number)?.toInt() ?: -1,
                sourceId = (channel["sourceId"] as? String)?.takeIf { it.isNotEmpty() },
                sourceName = (channel["sourceName"] as? String)?.takeIf { it.isNotEmpty() },
                isFavorite = channel["isFavorite"] == true,
                seriesId = (channel["seriesId"] as? String)?.takeIf { it.isNotEmpty() },
                seriesName = (channel["seriesName"] as? String)?.takeIf { it.isNotEmpty() },
                season = (channel["season"] as? Number)?.toInt(),
                episode = (channel["episode"] as? Number)?.toInt(),
                hasNextEpisode = channel["hasNextEpisode"] as? Boolean,
                resumePositionMs =
                    (channel["resumePositionMs"] as? Number)?.toLong() ?: 0L,
                headers = headers,
            )
        }

    private fun iptvChannelEntry(
        index: Int,
        channelNumber: Int?,
        name: String,
        url: String,
        logoUrl: String?,
        group: String?,
        contentType: String,
        duration: Int,
        sourceId: String?,
        sourceName: String?,
        isFavorite: Boolean,
        seriesId: String?,
        seriesName: String?,
        season: Int?,
        episode: Int?,
        hasNextEpisode: Boolean?,
        resumePositionMs: Long,
        headers: Map<String, String>,
    ): IptvChannelEntry {
        val normalizedType = contentType.ifEmpty {
            if (duration == -1) "live" else "vod"
        }
        return IptvChannelEntry(
            index = index,
            channelNumber = channelNumber,
            name = name,
            url = url,
            logoUrl = logoUrl,
            group = group,
            isLive = normalizedType == "live",
            isCurrent = false,
            resumePositionMs = resumePositionMs,
            httpHeaders = headers,
            contentType = normalizedType,
            duration = duration,
            sourceId = sourceId,
            sourceName = sourceName,
            isFavorite = isFavorite,
            seriesId = seriesId,
            seriesName = seriesName,
            season = season,
            episode = episode,
            hasNextEpisode = hasNextEpisode,
        )
    }

    private fun setupIptvControls() {
        playerView.findViewById<View>(R.id.debrify_random_button)?.visibility = View.GONE
        val entry = iptvChannels.getOrNull(currentIptvIndex)
        if (entry?.isLive == false) {
            // IPTV VOD uses the same cinema/Netflix-style dock installed by
            // setupControls(). Do not replace its panel/button backgrounds or
            // handlers with the live-TV presentation.
            iptvGuideButton?.visibility = View.GONE
            iptvPrevButton?.visibility = View.GONE
            iptvNextButton?.visibility = View.GONE
            updateIptvControlPresentation(entry)
            return
        }

        applyLiveIptvControlStyle()

        iptvRecordButton?.setOnClickListener {
            hideControlsMenu()
            toggleIptvRecording()
        }

        iptvPrevButton?.apply {
            text = "CH -"
            setOnClickListener {
                hideControlsMenu()
                zapIptvChannel(-1)
            }
        }
        iptvNextButton?.apply {
            text = "CH +"
            setOnClickListener {
                hideControlsMenu()
                zapIptvChannel(1)
            }
        }
        updateIptvControlPresentation(iptvChannels.getOrNull(currentIptvIndex))
    }

    /** The live dock buttons that restyle for live IPTV — the same set the
     *  original setup loop touched, so classic stays verbatim. */
    private fun liveIptvDockButtons(): List<AppCompatButton> = listOfNotNull(
        audioButton,
        subtitleButton,
        aspectButton,
        pauseButton,
        speedButton,
        nightModeButton,
        iptvPrevButton,
        iptvNextButton,
        iptvJumpButton,
        iptvRecordButton,
        playerView.findViewById<AppCompatButton>(R.id.debrify_playlist_button),
    )

    /** Cinema compound-drawable tints + typefaces captured before the first
     *  styled live swap, so a styled live→VOD transition can put them back —
     *  [restoreCinemaIptvControlStyle] only restores backgrounds/text. */
    private val cinemaIconTints = HashMap<View, android.content.res.ColorStateList?>()
    private val cinemaButtonTypefaces = HashMap<View, Typeface?>()

    /**
     * The live-IPTV dock skin. Extracted from `setupIptvControls` so the
     * VOD→live transition can re-apply it (`restoreCinemaIptvControlStyle`
     * overwrites every drawable on the way to VOD, and the return trip only
     * reordered children). Classic keeps its original swap verbatim AND its
     * original call graph — only styled launches call this from
     * `updateIptvControlPresentation`.
     */
    private fun applyLiveIptvControlStyle() {
        val t = guideTokens
        if (t == null) {
            playerView.findViewById<View>(R.id.debrify_controls_buttons)
                ?.setBackgroundResource(R.drawable.iptv_premium_panel_bg)

            val buttons = liveIptvDockButtons()
            buttons.forEach {
                it.setBackgroundResource(R.drawable.iptv_premium_button_bg)
                it.setTextColor(
                    ContextCompat.getColorStateList(this, R.color.iptv_premium_button_text)
                )
            }
            return
        }

        val radius = when (guideStyle) {
            GuideStyle.GLASS -> dp(22).toFloat()
            GuideStyle.EDITION -> dp(8).toFloat()
            else -> dp(4).toFloat()
        }
        playerView.findViewById<View>(R.id.debrify_controls_buttons)?.background =
            t.panelDrawable(radius, dp(1))
        val buttonRadius = when (guideStyle) {
            GuideStyle.GLASS -> dp(16).toFloat()
            GuideStyle.EDITION -> dp(6).toFloat()
            else -> dp(3).toFloat()
        }
        liveIptvDockButtons().forEach { button ->
            if (!cinemaIconTints.containsKey(button)) {
                // TextViewCompat throughout: the direct getter/setter is
                // API 23 and this app ships to minSdk 21.
                cinemaIconTints[button] =
                    TextViewCompat.getCompoundDrawableTintList(button)
                cinemaButtonTypefaces[button] = button.typeface
            }
            button.background = t.buttonBackground(buttonRadius)
            val colors = t.buttonTextColors()
            button.setTextColor(colors)
            TextViewCompat.setCompoundDrawableTintList(button, colors)
            if (guideStyle == GuideStyle.CONSOLE) {
                button.typeface = guideTypeface(t.monoFont) ?: button.typeface
            }
        }
    }

    /** Styled-only tail after [restoreCinemaIptvControlStyle]: put back the
     *  cinema icon tints AND typefaces the styled live skin replaced.
     *  Classic never runs this (its restore function is untouched and
     *  sufficient). */
    private fun restoreCinemaDockIconTints() {
        if (cinemaIconTints.isEmpty()) return
        liveIptvDockButtons().forEach { button ->
            if (cinemaIconTints.containsKey(button)) {
                TextViewCompat.setCompoundDrawableTintList(
                    button,
                    cinemaIconTints[button],
                )
            }
            if (cinemaButtonTypefaces.containsKey(button)) {
                button.typeface = cinemaButtonTypefaces[button]
            }
        }
    }

    // ── IPTV recording ──────────────────────────────────────────────────────

    /**
     * Engine vs tee. ON (default): Record starts a [LiveRecordingService]
     * capture over its own connection — it survives zaps, Home, and player
     * teardown, and stops only from the button, the notification, or its
     * duration cap. OFF: the original in-player tee ([IptvRecordingController])
     * with its record-what-you-watch, stops-with-the-player semantics.
     * Dart owns the setting; fixed per activity launch (like the player
     * defaults loaded in onCreate).
     */
    private val recordingEngineEnabled: Boolean by lazy {
        com.debrify.app.profiles.ProfilePreferenceProjection.getBoolean(
            this,
            "recording_engine_enabled",
            true,
        )
    }

    /** Repaints the Record button whenever an engine capture starts or ends —
     *  including from the notification's Stop, which the activity never sees. */
    private val recordingRegistryListener: () -> Unit = {
        if (!isDestroyed && !isFinishing) updateRecordButtonState()
    }

    /**
     * True when [url] is a SEGMENTED (adaptive) stream: HLS, DASH,
     * SmoothStreaming. Neither recorder can capture those byte-for-byte — the
     * manifest and the media segments live at different URIs, so a raw capture
     * would be the manifest alone, an XML/text file wearing a .ts name.
     */
    private fun isSegmentedStreamUrl(url: String): Boolean {
        val path = url.substringBefore('?').substringBefore('#').lowercase()
        return path.endsWith(".m3u8") ||
            path.endsWith(".m3u") ||
            path.endsWith(".mpd") ||
            path.endsWith(".ism") ||
            path.endsWith(".isml") ||
            path.endsWith("/manifest")
    }

    private fun isCurrentIptvSegmented(): Boolean {
        val url = currentIptvStreamUrl ?: return true
        return iptvHlsForcedUrls.contains(url) || isSegmentedStreamUrl(url)
    }

    /**
     * Xtream panels serve every live channel in both containers — the `.ts`
     * twin of a `/live/user/pass/id.m3u8` URL is the same channel as one
     * progressive MPEG-TS stream, which IS engine-recordable. Strict path
     * match only, and never for URLs carrying a query string (a twin stripped
     * of its token would just 401); anything else returns null.
     */
    private fun xtreamTsTwin(url: String): String? {
        if (url.contains('?')) return null
        val clean = url.substringBefore('#')
        val m = Regex(
            "^(https?://[^/]+)/live/([^/]+)/([^/]+)/([^/.]+)\\.m3u8$",
            RegexOption.IGNORE_CASE,
        ).find(clean) ?: return null
        val (host, user, pass, id) = m.destructured
        return "$host/live/$user/$pass/$id.ts"
    }

    /** The URL the ENGINE would capture for [url], or null when it can't:
     *  the URL itself when progressive, its Xtream `.ts` twin when that
     *  rescues an `.m3u8` channel, nothing for true segmented streams or
     *  non-HTTP transports (rtmp/rtsp/udp/... — the engine is a plain HTTP
     *  client and would fail every attempt after reporting a start). */
    private fun engineRecordableUrl(url: String): String? {
        if (!url.startsWith("http://", ignoreCase = true) &&
            !url.startsWith("https://", ignoreCase = true)
        ) {
            return null
        }
        if (!iptvHlsForcedUrls.contains(url) && !isSegmentedStreamUrl(url)) return url
        return xtreamTsTwin(url)
    }

    /**
     * Stricter gate for SCHEDULING: only URLs affirmatively known to be
     * progressive TS. At alarm time nobody is watching, so there is no player
     * probe to catch an extensionless HLS URL — which the raw engine would
     * "record" as looping playlist text. Explicit `.ts` and Xtream live URLs
     * (extensionless default IS TS) qualify.
     */
    private fun isSchedulableStreamUrl(url: String): Boolean {
        val recordable = engineRecordableUrl(url) ?: return false
        val path = recordable.substringBefore('?').substringBefore('#').lowercase()
        if (path.endsWith(".ts") || path.endsWith(".mts") || path.endsWith(".m2ts")) return true
        return Regex("^https?://[^/]+/(?:live/)?[^/]+/[^/]+/\\d+(?:\\.ts)?$")
            .matches(path)
    }

    /** The live engine capture for the CURRENT channel, if any — matched on
     *  the playing URL or its recordable twin. */
    private fun engineTaskIdForCurrentChannel(): String? {
        val url = currentIptvStreamUrl ?: return null
        RecordingRegistry.taskIdForUrl(url)?.let { return it }
        return engineRecordableUrl(url)?.let { RecordingRegistry.taskIdForUrl(it) }
    }

    private fun recordingResourceFor(entry: IptvChannelEntry?): IptvSourceEntry? {
        val sourceId = entry?.sourceId ?: iptvSourceId
        return iptvSources.firstOrNull { it.id == sourceId }
    }

    /** Record is offered only when the stream AND the OS can support it.
     *  Pre-Q needs-permission counts as offered: the button is how the user
     *  triggers the storage grant in the first place. */
    private fun canRecordCurrentIptv(): Boolean {
        if (recordingEngineEnabled) {
            if (!LiveRecordingService.isSupported(this) &&
                !LiveRecordingService.needsLegacyPermission(this)
            ) {
                return false
            }
            val url = currentIptvStreamUrl ?: return false
            return engineRecordableUrl(url) != null
        }
        return IptvRecordingController.isSupported && !isCurrentIptvSegmented()
    }

    /** Reflect record availability + active state on the button. */
    private fun updateRecordButtonState() {
        val button = iptvRecordButton ?: return
        val engineActive = recordingEngineEnabled && engineTaskIdForCurrentChannel() != null
        if (engineActive || iptvRecordingController.isActive) {
            button.text = "Stop"
            button.isEnabled = true
            button.isFocusable = true
            button.alpha = 1f
        } else {
            val recordable = canRecordCurrentIptv()
            button.text = "Record"
            button.isEnabled = recordable
            // A disabled button can still trap D-pad focus; drop it from the
            // focus order so segmented channels skip past it cleanly.
            button.isFocusable = recordable
            button.alpha = if (recordable) 1f else 0.4f
        }
    }

    private fun toggleIptvRecording() {
        if (recordingEngineEnabled) {
            toggleEngineRecording()
            return
        }
        if (iptvRecordingController.isActive) {
            val result = iptvRecordingController.stop()
            updateRecordButtonState()
            Toast.makeText(
                this,
                if (result.published) {
                    "Recording saved to Downloads/Debrify/Recordings"
                } else {
                    "Recording stopped, but couldn't be added to Downloads"
                },
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!IptvRecordingController.isSupported) {
            Toast.makeText(this, "Recording needs Android 10 or newer", Toast.LENGTH_SHORT).show()
            return
        }
        if (isCurrentIptvSegmented()) {
            Toast.makeText(this, "Recording isn't supported for this stream", Toast.LENGTH_SHORT).show()
            return
        }
        val url = currentIptvStreamUrl
        if (url.isNullOrEmpty()) return
        val entry = iptvChannels.getOrNull(currentIptvIndex)
        val fileName = "${sanitizeRecordingName(entry?.name ?: "recording")}_${recordingTimestamp()}.ts"
        if (iptvRecordingController.start(url, fileName, "video/mp2t")) {
            updateRecordButtonState()
            Toast.makeText(this, "Recording started", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "Couldn't start recording", Toast.LENGTH_SHORT).show()
        }
    }

    /** Android 13+ notification permission, asked contextually on the first
     *  record/schedule — same asked-once pref the phone activity uses, so
     *  the user is asked at most once app-wide. Non-blocking: recording
     *  proceeds while the dialog is up (it works without the grant; only
     *  the notifications go silent). */
    private fun maybeAskNotificationPermission() {
        if (android.os.Build.VERSION.SDK_INT < 33) return
        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) return
        val prefs = getSharedPreferences("debrify_permissions", MODE_PRIVATE)
        if (prefs.getBoolean("notification_permission_asked", false)) return
        prefs.edit().putBoolean("notification_permission_asked", true).apply()
        androidx.core.app.ActivityCompat.requestPermissions(
            this,
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun toggleEngineRecording() {
        engineTaskIdForCurrentChannel()?.let { taskId ->
            // Finalization is async in the service; its "Saved" notification is
            // the confirmation. The registry listener repaints the button.
            try {
                startService(
                    Intent(this, LiveRecordingService::class.java).apply {
                        action = LiveRecordingService.ACTION_STOP
                        putExtra(LiveRecordingService.EXTRA_TASK_ID, taskId)
                    },
                )
                Toast.makeText(this, "Recording stopped — saving…", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Couldn't stop recording", Toast.LENGTH_SHORT).show()
            }
            return
        }
        if (LiveRecordingService.needsLegacyPermission(this)) {
            // Pre-Q: the grant IS the enable switch. Ask, tell the user to
            // press Record again once allowed; onRequestPermissionsResult
            // repaints the button.
            androidx.core.app.ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                legacyStoragePermissionRequestCode,
            )
            Toast.makeText(
                this,
                "Allow storage access, then press Record again",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!LiveRecordingService.isSupported(this)) {
            Toast.makeText(this, "Recording isn't available on this device", Toast.LENGTH_SHORT).show()
            return
        }
        val url = currentIptvStreamUrl
        if (url.isNullOrEmpty()) return
        val recordUrl = engineRecordableUrl(url)
        if (recordUrl == null) {
            Toast.makeText(this, "Recording isn't supported for this stream", Toast.LENGTH_SHORT).show()
            return
        }
        val recordingLimit = LiveRecordingService.maxConcurrent(this)
        if (RecordingRegistry.live.size >= recordingLimit) {
            Toast.makeText(
                this,
                "Recording limit reached ($recordingLimit at a time) — " +
                    "stop one, or raise the limit in IPTV settings",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        maybeAskNotificationPermission()
        val entry = iptvChannels.getOrNull(currentIptvIndex)
        val resource = recordingResourceFor(entry)
        val owner = com.debrify.app.profiles.ProfilePreferenceProjection
            .activeJobContext(this)
        // Drift-tolerant: the channel's resource revision rode in with the
        // launch payload and a sources edit since then bumped every revision.
        // The live grant/feature checks still refuse real revocation.
        if (!com.debrify.app.profiles.ProfilePreferenceProjection.jobAuthorizationValid(
                this, owner.profileId, owner.authorizationRevision, "recordings",
                resource?.connectionResourceId, resource?.connectionResourceRevision,
                allowRevisionDrift = true,
            )
        ) {
            Toast.makeText(this, "Recording is disabled for this profile", Toast.LENGTH_SHORT).show()
            return
        }
        val fileName = "${sanitizeRecordingName(entry?.name ?: "recording")}_${recordingTimestamp()}.ts"
        try {
            ContextCompat.startForegroundService(
                this,
                LiveRecordingService.buildStartIntent(
                    context = this,
                    taskId = "rec-${System.currentTimeMillis()}",
                    url = recordUrl,
                    fileName = fileName,
                    channelName = entry?.name ?: "Live channel",
                    headers = HashMap(currentIptvHttpHeaders),
                    maxDurationMs = LiveRecordingService.MAX_DURATION_DEFAULT_MS,
                    ownerProfileId = owner.profileId,
                    connectionResourceId = resource?.connectionResourceId,
                    profileAuthorizationRevision = owner.authorizationRevision,
                    resourceAuthorizationRevision = resource?.connectionResourceRevision,
                ),
            )
            Toast.makeText(
                this,
                "Recording in background — keeps going if you zap or leave",
                Toast.LENGTH_LONG,
            ).show()
        } catch (e: Exception) {
            Toast.makeText(this, "Couldn't start recording", Toast.LENGTH_SHORT).show()
        }
    }

    /** Confirm-and-schedule for a FUTURE programme picked in the EPG guide.
     *  Everything stays native: the schedule store and alarms need no Dart. */
    private fun promptScheduleRecording(entry: IptvChannelEntry, program: IptvEpgProgram) {
        if (!recordingEngineEnabled) {
            Toast.makeText(this, "Scheduled recording isn't available", Toast.LENGTH_SHORT).show()
            return
        }
        if (LiveRecordingService.needsLegacyPermission(this)) {
            androidx.core.app.ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                legacyStoragePermissionRequestCode,
            )
            Toast.makeText(
                this,
                "Allow storage access, then pick the programme again",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!LiveRecordingService.isSupported(this)) {
            Toast.makeText(this, "Scheduled recording isn't available", Toast.LENGTH_SHORT).show()
            return
        }
        if (!RecordingAlarmReceiver.exactAlarmsGranted(this)) {
            // An inexact fire couldn't legally start the recording service from
            // the background — refuse rather than schedule something doomed.
            Toast.makeText(
                this,
                "Allow \"Alarms & reminders\" for Debrify in system settings to schedule recordings",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        if (!isSchedulableStreamUrl(entry.url)) {
            Toast.makeText(this, "This channel can't be scheduled", Toast.LENGTH_SHORT).show()
            return
        }
        val recordUrl = engineRecordableUrl(entry.url)
        if (recordUrl == null) {
            Toast.makeText(this, "This channel can't be recorded", Toast.LENGTH_SHORT).show()
            return
        }
        if (RecordingScheduleStore.findDuplicate(this, recordUrl, program.startMs) != null) {
            Toast.makeText(this, "Already scheduled", Toast.LENGTH_SHORT).show()
            return
        }
        val timeFormat = android.text.format.DateFormat.getTimeFormat(this)
        val range = "${timeFormat.format(java.util.Date(program.startMs))} – " +
            timeFormat.format(java.util.Date(program.stopMs))
        // Capacity check folded into the confirm dialog: Android's runtime
        // rule is fire-time skip, so scheduling anyway is honest — but the
        // user must hear about the conflict NOW, while they can still fix it.
        val limit = LiveRecordingService.maxConcurrent(this)
        val peak = RecordingScheduleStore.peakOverlap(this, program.startMs, program.stopMs)
        val conflictNote = if (peak + 1 > limit) {
            val names = RecordingScheduleStore
                .overlappingTitles(this, program.startMs, program.stopMs)
                .take(3)
                .joinToString(" · ")
            "\n\nConflicts with $names — only $limit can record at once, so " +
                "this may be skipped. Raise the limit in IPTV settings, or " +
                "cancel another recording."
        } else {
            ""
        }
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle(if (conflictNote.isEmpty()) "Record programme" else "Recording conflict")
            .setMessage("${program.title}\n${entry.name} · $range$conflictNote")
            .setPositiveButton("Record") { _, _ ->
                maybeAskNotificationPermission()
                val owner = com.debrify.app.profiles.ProfilePreferenceProjection
                    .activeJobContext(this)
                val resource = recordingResourceFor(entry)
                // Drift-tolerant: the payload's resource revision predates any
                // sources edit made since launch — see the projection's note.
                if (!com.debrify.app.profiles.ProfilePreferenceProjection.jobAuthorizationValid(
                        this, owner.profileId, owner.authorizationRevision, "recordings",
                        resource?.connectionResourceId, resource?.connectionResourceRevision,
                        allowRevisionDrift = true,
                    )
                ) {
                    Toast.makeText(this, "Recording is disabled for this profile", Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                val scheduleId = "sched-${System.currentTimeMillis()}"
				try {
				RecordingScheduleStore.put(
					this,
                    RecordingSchedule(
                        id = scheduleId,
                        channelName = entry.name,
                        url = recordUrl,
                        headers = HashMap(entry.httpHeaders),
                        startMs = program.startMs,
                        endMs = program.stopMs,
                        programmeTitle = program.title,
                        createdAt = System.currentTimeMillis(),
                        ownerProfileId = owner.profileId,
                        connectionResourceId = resource?.connectionResourceId,
                        profileAuthorizationRevision = owner.authorizationRevision,
                        resourceAuthorizationRevision = resource?.connectionResourceRevision,
						sealedExecutionPayload = null,
					),
				)
				RecordingAlarmReceiver.registerAll(this)
				Toast.makeText(this, "Recording scheduled", Toast.LENGTH_SHORT).show()
				} catch (_: Exception) {
					Toast.makeText(this, "Could not save the recording schedule", Toast.LENGTH_SHORT).show()
				}
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    /** Finalize any active recording (channel change / exit). Safe when idle.
     *  Silent on success — the user didn't ask for this stop — but a failed
     *  publish is worth saying out loud, since the file is invisible. */
    private fun finalizeIptvRecordingIfActive() {
        if (!iptvRecordingController.isActive) return
        val result = iptvRecordingController.stop()
        updateRecordButtonState()
        if (result.wasRecording && !result.published && !isFinishing) {
            Toast.makeText(
                this,
                "Recording stopped, but couldn't be added to Downloads",
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    private fun sanitizeRecordingName(raw: String): String {
        val cleaned = raw.replace(Regex("[^A-Za-z0-9 _-]"), "")
            .trim()
            .replace(Regex("\\s+"), "_")
        return cleaned.take(60).ifEmpty { "recording" }
    }

    private fun recordingTimestamp(): String =
        java.text.SimpleDateFormat("yyyyMMdd_HHmmss", java.util.Locale.US)
            .format(java.util.Date())

    private fun updateIptvControlPresentation(entry: IptvChannelEntry?) {
        val live = entry?.isLive != false
        val vodVisibility = if (live) View.GONE else View.VISIBLE
        if (live) {
            arrangeLiveIptvControlDock()
            // Styled only: a VOD trip restored every cinema drawable, and
            // reordering alone doesn't bring the live skin back. Classic
            // keeps its original call graph (and its original quirk).
            if (guideTokens != null) applyLiveIptvControlStyle()
        } else {
            restoreCinemaIptvControlStyle()
            if (guideTokens != null) restoreCinemaDockIconTints()
        }
        cinemaProgressContainer?.visibility = vodVisibility
        debrifyTimeCurrent?.visibility = vodVisibility
        debrifyTimeTotal?.visibility = vodVisibility
        speedButton?.visibility = vodVisibility
        nightModeButton?.visibility = View.VISIBLE
        iptvJumpButton?.visibility = if (live) View.VISIBLE else View.GONE
        iptvGuideButton?.visibility = if (live) View.VISIBLE else View.GONE
        // Visibility follows the ACTIVE recorder: the engine records pre-Q
        // once storage is granted (and shows the button so it CAN be
        // granted); the tee remains Q+-only.
        val recorderAvailable = if (recordingEngineEnabled) {
            LiveRecordingService.isSupported(this) ||
                LiveRecordingService.needsLegacyPermission(this)
        } else {
            IptvRecordingController.isSupported
        }
        iptvRecordButton?.visibility =
            if (live && recorderAvailable) View.VISIBLE else View.GONE
        updateRecordButtonState()
        if (!live && iptvGuideVisible) hideIptvGuide()
        if (live) {
            cinemaSeekMode = false
            cinemaProgressThumb?.visibility = View.INVISIBLE
            cinemaSpeedIndicator?.visibility = View.GONE
            if (currentFocus == cinemaProgressContainer) {
                pauseButton?.requestFocus()
            }
        }
    }

    /** Live IPTV uses a balanced dock:
     *  Audio · Subs · Aspect | CH- · Play/Pause · CH+ | Guide · Jump · Record · Night.
     *  Record is present only for progressive streams (disabled for HLS). The
     *  XML order remains the standard cinema/VOD order; only the live
     *  presentation is rearranged, so movies and episodes keep their old UX. */
    private fun arrangeLiveIptvControlDock() {
        val dock =
            playerView.findViewById<LinearLayout>(R.id.debrify_controls_buttons)
                ?: return
        val desired = listOfNotNull(
            audioButton,
            subtitleButton,
            aspectButton,
            playerView.findViewById<View>(R.id.debrify_controls_left_divider),
            iptvPrevButton,
            pauseButton,
            iptvNextButton,
            playerView.findViewById<View>(R.id.debrify_controls_right_divider),
            iptvGuideButton,
            iptvJumpButton,
            iptvRecordButton,
            nightModeButton,
        )
        replaceControlDockOrder(dock, desired)
    }

    private fun restoreOriginalControlDockOrder() {
        val dock =
            playerView.findViewById<LinearLayout>(R.id.debrify_controls_buttons)
                ?: return
        if (originalControlDockOrder.isNotEmpty()) {
            replaceControlDockOrder(dock, originalControlDockOrder)
        }
    }

    private fun replaceControlDockOrder(dock: LinearLayout, leading: List<View>) {
        // Keep hidden/format-specific controls attached after the requested
        // order. GONE children consume no space, but retaining them lets the
        // same dock switch back to VOD without reinflating the controller.
        val order = leading + originalControlDockOrder.filterNot { it in leading }
        val alreadyApplied =
            dock.childCount == order.size &&
                order.indices.all { index -> dock.getChildAt(index) === order[index] }
        if (alreadyApplied) return
        dock.removeAllViews()
        order.forEach { dock.addView(it) }
    }

    private fun restoreCinemaIptvControlStyle() {
        restoreOriginalControlDockOrder()
        playerView.findViewById<View>(R.id.debrify_controls_buttons)
            ?.setBackgroundResource(R.drawable.cinema_dock_bg)
        val standardButtons = listOfNotNull(
            audioButton,
            subtitleButton,
            aspectButton,
            speedButton,
            nightModeButton,
            iptvPrevButton,
            iptvNextButton,
            iptvGuideButton,
            iptvJumpButton,
            iptvRecordButton,
        )
        standardButtons.forEach {
            it.setBackgroundResource(R.drawable.cinema_button_bg)
            it.setTextColor(
                ContextCompat.getColorStateList(this, R.color.cinema_control_button_text)
            )
        }
        pauseButton?.apply {
            setBackgroundResource(R.drawable.cinema_play_button_bg)
            setTextColor(
                ContextCompat.getColorStateList(
                    this@AndroidTvTorrentPlayerActivity,
                    R.color.cinema_play_button_text,
                ),
            )
        }
    }

    private fun setupIptvOverlay() {
        val guideList = iptvGuideList ?: return

        guideList.layoutManager = LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false)
        iptvChannelAdapter = IptvChannelAdapter(
            channels = iptvBrowseChannels.toMutableList(),
            onItemClick = { entry ->
                if (isIptvSeriesSentinel(entry)) {
                    requestIptvBrowse(
                        action = "seriesEpisodes",
                        channelUrl = entry.url,
                        title = entry.name,
                        sourceIdOverride = entry.sourceId,
                    )
                } else if (iptvContentType == "episodes") {
                    commitIptvAllCategorySearch()
                    hideIptvGuide()
                    disableIptvZapPaging()
                    switchToIptvChannel(entry)
                } else {
                    commitIptvAllCategorySearch()
                    hideIptvGuide()
                    beginIptvCategoryZapSession(entry)
                }
            },
            onItemLongClick = { entry ->
                if (isIptvSeriesSentinel(entry)) {
                    Toast.makeText(
                        this,
                        "Open the series to choose an episode",
                        Toast.LENGTH_SHORT,
                    ).show()
                } else if (iptvLists.any { !it.isBuiltin }) {
                    showIptvListPicker(entry)
                } else {
                    toggleIptvFavorite(entry)
                }
            },
            onEpgNeeded = { entry -> ensureIptvChannelEpg(entry) },
            tokens = guideTokens,
            style = guideStyle,
            nameTypeface = guideTokens?.let { guideTypeface(it.nameFont) },
            monoTypeface = guideTokens?.let { guideTypeface(it.monoFont) },
            headlineTypeface = guideTokens?.let { guideTypeface(it.headlineFont) },
            captionTypeface = guideTokens?.let { guideTypeface(it.captionFont) },
            rowRadiusPx = when (guideStyle) {
                GuideStyle.GLASS -> dp(14).toFloat()
                GuideStyle.EDITION -> dp(8).toFloat()
                else -> dp(3).toFloat()
            },
            rowStrokePx = dp(2),
        )
        guideList.adapter = iptvChannelAdapter
        guideList.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (!iptvZapPagingActive ||
                    !iptvGuideUsesZapWindow ||
                    iptvZapRequestInFlight
                ) return
                val layout = recyclerView.layoutManager as? LinearLayoutManager ?: return
                val last = layout.findLastVisibleItemPosition()
                val first = layout.findFirstVisibleItemPosition()
                val count = iptvChannelAdapter?.itemCount ?: return
                when {
                    dy >= 0 && last >= count - 12 -> prefetchIptvZapPage(1, force = true)
                    dy < 0 && first in 0..11 -> prefetchIptvZapPage(-1, force = true)
                }
            }
        })

        iptvEpgList?.layoutManager =
            LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false)
        iptvEpgAdapter = IptvEpgAdapter(
            emptyList(),
            onReplay = { program ->
                iptvEpgEntry?.let { entry -> requestIptvCatchup(entry, program) }
            },
            onRecordFuture = { program ->
                iptvEpgEntry?.let { entry -> promptScheduleRecording(entry, program) }
            },
            tokens = guideTokens,
            style = guideStyle,
            monoTypeface = guideTokens?.let { guideTypeface(it.monoFont) },
            headlineTypeface = guideTokens?.let { guideTypeface(it.headlineFont) },
            rowRadiusPx = when (guideStyle) {
                GuideStyle.GLASS -> dp(14).toFloat()
                GuideStyle.EDITION -> dp(8).toFloat()
                else -> dp(3).toFloat()
            },
            rowStrokePx = dp(2),
        )
        iptvEpgList?.adapter = iptvEpgAdapter

        val premiumButtonIds = intArrayOf(
            R.id.iptv_nav_browse,
            R.id.iptv_nav_search,
            R.id.iptv_nav_favorites,
            R.id.iptv_nav_sources,
            R.id.iptv_nav_close,
            R.id.iptv_source_button,
            R.id.iptv_category_button,
            R.id.iptv_mode_live,
            R.id.iptv_epg_day_today,
            R.id.iptv_epg_day_tomorrow,
            R.id.iptv_epg_day_later,
        )
        premiumButtonIds.forEach { id ->
            findViewById<AppCompatButton>(id)?.setTextColor(
                ContextCompat.getColorStateList(this, R.color.iptv_premium_button_text)
            )
        }
        val sourceControlsVisibility =
            if (iptvSources.isEmpty()) View.GONE else View.VISIBLE
        findViewById<View>(R.id.iptv_nav_favorites)?.visibility =
            sourceControlsVisibility
        findViewById<View>(R.id.iptv_nav_sources)?.visibility =
            sourceControlsVisibility
        iptvSourceButton?.visibility = sourceControlsVisibility
        findViewById<View>(R.id.iptv_nav_browse)?.isSelected = true

        // Submit-only search: typing does NOT filter. (A live filter only ever
        // reached the loaded <=1500 window, so it looked like search was missing
        // channels.) Instead show a hint so the user commits the query with the
        // OK / search key; the real search then runs over the WHOLE source.
        iptvGuideSearch?.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                iptvGuideCountText?.text = if (s.isNullOrBlank()) {
                    iptvGuideItemCountLabel()
                } else {
                    "Press OK to search"
                }
            }
        })
        iptvGuideSearch?.setOnFocusChangeListener { _, focused ->
            if (focused) beginIptvAllCategorySearch()
        }
        // Submit-only catalog search: the paged browse of the current source
        // fires when the user commits the query with the search / enter key —
        // not on every keystroke,
        // which is what froze the player on six-figure catalogs.
        iptvGuideSearch?.setOnEditorActionListener { _, actionId, event ->
            val isSubmit = actionId == EditorInfo.IME_ACTION_SEARCH ||
                actionId == EditorInfo.IME_ACTION_DONE ||
                actionId == EditorInfo.IME_ACTION_GO ||
                (event?.keyCode == KeyEvent.KEYCODE_ENTER &&
                    event.action == KeyEvent.ACTION_UP)
            if (isSubmit) {
                requestIptvBrowse(
                    action = "browse",
                    query = iptvGuideSearch?.text?.toString()?.trim().orEmpty(),
                )
                true
            } else {
                false
            }
        }

        findViewById<View>(R.id.iptv_nav_browse)?.setOnClickListener {
            if (restoreIptvCategoryAfterSearch()) {
                focusCurrentIptvGuideRow()
            } else {
                iptvGuideSearch?.setText("")
                requestIptvBrowse(action = "browse", query = "")
            }
        }
        findViewById<View>(R.id.iptv_nav_search)?.setOnClickListener {
            beginIptvAllCategorySearch()
            iptvGuideSearch?.requestFocus()
        }
        findViewById<View>(R.id.iptv_nav_favorites)?.setOnClickListener {
            val source = iptvSources.firstOrNull { it.isFavorites }
            if (source != null) selectIptvSource(source) else {
                Toast.makeText(this, "No favorites source", Toast.LENGTH_SHORT).show()
            }
        }
        findViewById<View>(R.id.iptv_nav_sources)?.setOnClickListener {
            showIptvSourcePicker()
        }
        findViewById<View>(R.id.iptv_nav_close)?.setOnClickListener {
            hideIptvGuide()
        }
        iptvSourceButton?.setOnClickListener { showIptvSourcePicker() }
        iptvCategoryButton?.setOnClickListener { showIptvCategoryPicker() }
        findViewById<View>(R.id.iptv_mode_live)?.setOnClickListener {
            selectIptvContentType("live")
        }
        findViewById<View>(R.id.iptv_epg_day_today)?.setOnClickListener {
            selectIptvEpgDay(0)
        }
        findViewById<View>(R.id.iptv_epg_day_tomorrow)?.setOnClickListener {
            selectIptvEpgDay(1)
        }
        findViewById<View>(R.id.iptv_epg_day_later)?.setOnClickListener {
            selectIptvEpgDay(2)
        }

        refreshIptvBrowserChrome()
        updateIptvGuideCurrentName()
        // AFTER the premiumButtonIds loop above, so the legacy tinting can
        // never overwrite the styled pass.
        applyGuideStyle()
    }

    /**
     * The styled looks' one-shot re-tint of the guide overlay. Classic
     * returns immediately — the XML keeps every legacy value, and this runs
     * once from [setupIptvOverlay] (no per-frame or per-bind work).
     */
    private fun applyGuideStyle() {
        val t = guideTokens ?: return
        val style = guideStyle
        val panelRadius = when (style) {
            GuideStyle.GLASS -> dp(18).toFloat()
            GuideStyle.EDITION -> dp(10).toFloat()
            else -> dp(4).toFloat()
        }
        val controlRadius = when (style) {
            GuideStyle.GLASS -> dp(12).toFloat()
            GuideStyle.EDITION -> dp(8).toFloat()
            else -> dp(3).toFloat()
        }
        val serif = guideTypeface(t.headlineFont)
        val serifItalic = guideTypeface(t.captionFont)
        val grotesk = guideTypeface(t.nameFont)
        val mono = guideTypeface(t.monoFont)
        val buttonColors = t.buttonTextColors()

        fun styleButton(id: Int) {
            findViewById<AppCompatButton>(id)?.let { button ->
                button.background = t.buttonBackground(controlRadius)
                button.setTextColor(buttonColors)
                TextViewCompat.setCompoundDrawableTintList(button, buttonColors)
                if (style == GuideStyle.CONSOLE) {
                    button.typeface = mono ?: button.typeface
                }
            }
        }

        // Panels + rail.
        findViewById<View>(R.id.iptv_guide_panel)?.background =
            t.panelDrawable(panelRadius, dp(1))
        findViewById<View>(R.id.iptv_epg_panel)?.background =
            t.panelDrawable(panelRadius, dp(1))
        findViewById<View>(R.id.iptv_guide_now_playing)?.background =
            t.panelDrawable(panelRadius, dp(1))
        findViewById<View>(R.id.iptv_nav_rail)?.setBackgroundColor(t.bg)
        findViewById<View>(R.id.iptv_rail_divider)?.setBackgroundColor(t.hairline)
        findViewById<TextView>(R.id.iptv_nav_logo)?.let { d ->
            d.setBackgroundColor(t.fg)
            d.setTextColor(t.bg or 0xFF000000.toInt())
        }
        findViewById<View>(R.id.iptv_mode_tabs)?.setBackgroundColor(t.bg)
        findViewById<View>(R.id.iptv_epg_day_tabs)?.setBackgroundColor(t.bg)

        // Buttons — nav rail, source/category, mode, day tabs.
        intArrayOf(
            R.id.iptv_nav_browse,
            R.id.iptv_nav_search,
            R.id.iptv_nav_favorites,
            R.id.iptv_nav_sources,
            R.id.iptv_nav_close,
            R.id.iptv_source_button,
            R.id.iptv_category_button,
            R.id.iptv_mode_live,
            R.id.iptv_epg_day_today,
            R.id.iptv_epg_day_tomorrow,
            R.id.iptv_epg_day_later,
        ).forEach { styleButton(it) }

        // Kickers: the one place each style stamps its voice.
        val kickerColor = when (style) {
            GuideStyle.EDITION -> t.fgDim
            else -> t.accent
        }
        intArrayOf(R.id.iptv_guide_kicker, R.id.iptv_epg_kicker).forEach { id ->
            findViewById<TextView>(id)?.let { kicker ->
                kicker.setTextColor(kickerColor)
                when (style) {
                    GuideStyle.EDITION -> kicker.typeface =
                        serifItalic?.let { Typeface.create(it, Typeface.ITALIC) }
                            ?: kicker.typeface
                    GuideStyle.CONSOLE -> kicker.typeface = mono ?: kicker.typeface
                    else -> {}
                }
            }
        }

        // Titles + secondary text.
        findViewById<TextView>(R.id.iptv_guide_title)?.let { title ->
            title.setTextColor(t.fg)
            when (style) {
                GuideStyle.EDITION -> title.typeface = serif ?: title.typeface
                GuideStyle.CONSOLE -> title.typeface = grotesk ?: title.typeface
                else -> {}
            }
        }
        findViewById<TextView>(R.id.iptv_epg_channel_name)?.let { name ->
            name.setTextColor(t.fg)
            when (style) {
                GuideStyle.EDITION -> name.typeface = serif ?: name.typeface
                GuideStyle.CONSOLE -> name.typeface = grotesk ?: name.typeface
                else -> {}
            }
        }
        findViewById<TextView>(R.id.iptv_guide_count)?.setTextColor(t.fgFaint)
        findViewById<TextView>(R.id.iptv_epg_channel_group)?.setTextColor(t.fgFaint)
        findViewById<TextView>(R.id.iptv_epg_date)?.setTextColor(t.fgMid)
        findViewById<TextView>(R.id.iptv_epg_empty)?.setTextColor(t.fgDim)
        intArrayOf(
            R.id.iptv_footer_play,
            R.id.iptv_footer_schedule,
            R.id.iptv_footer_favorite,
            R.id.iptv_epg_footer_channels,
            R.id.iptv_epg_footer_replay,
        ).forEach { findViewById<TextView>(it)?.setTextColor(t.fgFaint) }

        // Search field.
        iptvGuideSearch?.let { search ->
            search.background = t.searchDrawable(controlRadius)
            search.setTextColor(t.fg)
            search.setHintTextColor(t.fgFaint)
            TextViewCompat.setCompoundDrawableTintList(
                search,
                android.content.res.ColorStateList.valueOf(t.fgFaint),
            )
            if (style == GuideStyle.CONSOLE) search.typeface = mono ?: search.typeface
        }

        // Spinners + logo tiles + the now-playing card texts.
        val accentTint = android.content.res.ColorStateList.valueOf(t.accent)
        findViewById<ProgressBar>(R.id.iptv_browse_loading)?.indeterminateTintList =
            accentTint
        findViewById<ProgressBar>(R.id.iptv_epg_loading)?.indeterminateTintList =
            accentTint
        val tileRadius = if (style == GuideStyle.EDITION) dp(24).toFloat() else controlRadius
        intArrayOf(R.id.iptv_epg_logo_tile, R.id.iptv_guide_now_logo_tile).forEach { id ->
            findViewById<View>(id)?.background = t.tileDrawable(tileRadius, dp(1))
        }
        intArrayOf(R.id.iptv_epg_letter, R.id.iptv_guide_now_letter).forEach { id ->
            findViewById<TextView>(id)?.setTextColor(t.fg)
        }
        findViewById<TextView>(R.id.iptv_guide_current_epg)?.setTextColor(t.live)
        findViewById<TextView>(R.id.iptv_guide_current_name)?.setTextColor(t.fg)
        findViewById<TextView>(R.id.iptv_guide_current_group)?.setTextColor(t.fgFaint)
    }

    private fun isIptvSeriesSentinel(entry: IptvChannelEntry): Boolean =
        entry.contentType == "series" || entry.url.startsWith("xtream-series://")

    private fun showIptvGuide() {
        if (iptvChannels.getOrNull(currentIptvIndex)?.isLive != true) return
        // The banner is attached last to the content view (topmost) — it must
        // never float over the guide.
        hideIptvZapBanner()
        iptvGuideVisible = true
        iptvGuideOverlay?.animate()?.cancel() // cancel any pending hide animation
        iptvGuideOverlay?.visibility = View.VISIBLE
        iptvGuideOverlay?.alpha = 0f
        iptvGuideOverlay?.animate()?.alpha(1f)?.setDuration(200)?.start()

        hideIptvEpgPane()
        refreshIptvBrowserChrome()
        updateIptvGuideCurrentName()

        // Focus the list and scroll to current channel
        iptvGuideList?.post {
            val currentPos = iptvChannelAdapter?.getCurrentChannelPosition() ?: 0
            iptvGuideList?.scrollToPosition(currentPos)
            iptvGuideList?.postDelayed({
                val holder = iptvGuideList?.findViewHolderForAdapterPosition(currentPos)
                holder?.itemView?.requestFocus()
            }, 150)
        }
    }

    private fun hideIptvGuide() {
        restoreIptvCategoryAfterSearch()
        iptvGuideVisible = false
        // Deferred: hide is often reached from inside a guide row's own click
        // dispatch, and trimming can remove hundreds of rows (including the
        // focused one) from the RecyclerView mid-event. Posting lets the click
        // finish first; after a channel pick the trim then no-ops because the
        // zap session has already replaced the window.
        iptvBrowseHandler.post { trimHiddenIptvZapWindow() }
        hideIptvEpgPane()
        iptvGuideOverlay?.animate()?.cancel() // cancel any pending show animation
        iptvGuideOverlay?.animate()?.alpha(0f)?.setDuration(150)?.withEndAction {
            iptvGuideOverlay?.visibility = View.GONE
        }?.start()
    }

    private fun beginIptvAllCategorySearch() {
        if (iptvContentType != "live" || iptvAllCategorySearchActive) return
        iptvAllCategorySearchActive = true
        iptvSearchSavedCategory = iptvSelectedCategory
        iptvSearchSavedChannels =
            iptvChannelAdapter?.entriesSnapshot()?.toMutableList()
                ?: iptvBrowseChannels.toMutableList()
        iptvSearchSavedCategories = iptvCategories.toMutableList()
        iptvSearchSavedUsesZapWindow = iptvGuideUsesZapWindow
        iptvSearchSavedZapOwnsUiContext = iptvZapOwnsUiContext

        // Search is a temporary browsing context. Invalidate any page that was
        // about to update the category window and send subsequent browse
        // requests without a category filter.
        iptvUiContextToken++
        iptvBrowseToken++
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()
        iptvZapOwnsUiContext = false
        iptvSelectedCategory = null
        iptvBrowseLoading?.visibility = View.GONE
        refreshIptvBrowserChrome()
    }

    /**
     * Restore the category/list that was visible before Search got focus.
     * Returning true lets callers avoid a redundant bridge request and keep
     * the guide responsive.
     */
    private fun restoreIptvCategoryAfterSearch(): Boolean {
        if (!iptvAllCategorySearchActive) return false
        val savedCategory = iptvSearchSavedCategory
        val savedChannels = iptvSearchSavedChannels.toMutableList()
        val savedCategories = iptvSearchSavedCategories.toMutableList()
        val savedUsesZapWindow = iptvSearchSavedUsesZapWindow
        val savedZapOwnsUiContext = iptvSearchSavedZapOwnsUiContext
        clearIptvAllCategorySearchState()

        // A submitted All-categories result may still be returning. Make it
        // stale before putting the original category window back.
        iptvUiContextToken++
        iptvBrowseToken++
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()
        iptvBrowseLoading?.visibility = View.GONE
        iptvSelectedCategory = savedCategory
        iptvCategories = savedCategories
        iptvBrowseChannels = savedChannels
        iptvGuideUsesZapWindow = savedUsesZapWindow
        iptvZapOwnsUiContext = savedZapOwnsUiContext
        iptvGuideSearch?.setText("")
        iptvChannelAdapter?.updateChannels(savedChannels)
        refreshIptvBrowserChrome()
        updateIptvGuideCurrentName()
        if (savedZapOwnsUiContext && !iptvZapPagingActive) {
            iptvChannels.getOrNull(currentIptvIndex)?.let {
                bootstrapInitialIptvZapPaging(it)
            }
        }
        return true
    }

    private fun commitIptvAllCategorySearch() {
        if (!iptvAllCategorySearchActive) return
        clearIptvAllCategorySearchState()
    }

    private fun clearIptvAllCategorySearchState() {
        iptvAllCategorySearchActive = false
        iptvSearchSavedCategory = null
        iptvSearchSavedChannels = mutableListOf()
        iptvSearchSavedCategories = mutableListOf()
        iptvSearchSavedUsesZapWindow = false
        iptvSearchSavedZapOwnsUiContext = false
    }

    private fun focusCurrentIptvGuideRow() {
        iptvGuideList?.post {
            val position = iptvChannelAdapter?.getCurrentChannelPosition() ?: 0
            iptvGuideList?.scrollToPosition(position)
            iptvGuideList?.post {
                iptvGuideList?.findViewHolderForAdapterPosition(position)
                    ?.itemView?.requestFocus()
            }
        }
    }

    private fun toggleIptvGuide() {
        if (iptvGuideVisible) hideIptvGuide() else showIptvGuide()
    }

    private fun refreshIptvBrowserChrome(title: String? = null) {
        iptvSourceButton?.text = iptvSourceName
        iptvCategoryButton?.text = iptvSelectedCategory ?: "All categories"
        iptvGuideTitle?.text = title ?: when (iptvContentType) {
            "vod" -> "Movies"
            "series" -> "Series"
            "episodes" -> "Episodes"
            else -> "Live television"
        }
        iptvGuideCountText?.text = iptvGuideItemCountLabel()

        val modeButtons = listOf(
            "live" to findViewById<AppCompatButton>(R.id.iptv_mode_live),
        )
        modeButtons.forEach { (type, button) ->
            button?.isSelected = iptvContentType == type
        }
        updateIptvCatalogControlVisibility()
    }

    private fun updateIptvCatalogControlVisibility() {
        val liveCatalog = iptvContentType == "live"
        val liveVisibility = if (liveCatalog) View.VISIBLE else View.GONE
        findViewById<View>(R.id.iptv_nav_browse)?.visibility = liveVisibility
        findViewById<View>(R.id.iptv_nav_search)?.visibility = liveVisibility
        findViewById<View>(R.id.iptv_filter_bar)?.visibility = liveVisibility

        val sourceVisibility =
            if (liveCatalog && iptvSources.isNotEmpty()) View.VISIBLE else View.GONE
        findViewById<View>(R.id.iptv_nav_favorites)?.visibility = sourceVisibility
        findViewById<View>(R.id.iptv_nav_sources)?.visibility = sourceVisibility
        iptvSourceButton?.visibility = sourceVisibility
    }

    private fun iptvGuideItemCountLabel(): String {
        val count = if (iptvGuideUsesZapWindow &&
            iptvZapPagingActive &&
            iptvZapCategoryTotal > 0
        ) {
            iptvZapCategoryTotal
        } else {
            iptvBrowseChannels.size
        }
        return "$count items"
    }

    private fun selectIptvContentType(contentType: String) {
        if (iptvContentType == contentType) {
            restoreIptvCategoryAfterSearch()
            return
        }
        commitIptvAllCategorySearch()
        iptvContentType = contentType
        iptvSelectedCategory = null
        iptvGuideSearch?.setText("")
        refreshIptvBrowserChrome()
        requestIptvBrowse(action = "browse", query = "")
    }

    private fun selectIptvSource(source: IptvSourceEntry) {
        commitIptvAllCategorySearch()
        iptvSourceId = source.id
        iptvSourceName = source.name
        iptvSelectedCategory = null
        iptvCategories.clear()
        iptvContentType = when {
            source.isContinue -> "vod"
            source.isFavorites -> "live"
            // A list is a curated mix with no content type of its own. Without
            // this arm a lingering "vod" state would ride through and ask Dart
            // for the wrong slice of the list.
            source.isList -> "live"
            iptvContentType == "episodes" -> if (source.isXtream) "series" else "live"
            !source.isXtream && iptvContentType == "series" -> "live"
            else -> iptvContentType
        }
        iptvGuideSearch?.setText("")
        refreshIptvBrowserChrome()
        requestIptvBrowse(action = "browse")
    }

    private fun showIptvSourcePicker() {
        val liveSources = iptvSources.filterNot { it.isContinue }
        if (liveSources.isEmpty()) return
        val options = liveSources.map { it.name }
        AlertDialog.Builder(this)
            .setTitle("Choose source")
            .setItems(options.toTypedArray()) { _, index ->
                selectIptvSource(liveSources[index])
            }
            .show()
    }

    private fun showIptvCategoryPicker() {
        val allLabel = "All categories"
        val categories = iptvCategories.distinct()
        val categoryListHeight = minOf(
            dp(400),
            (resources.displayMetrics.heightPixels * 0.5f).toInt(),
        )
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), 0)
        }
        val pickerTokens = guideTokens
        val searchInput = EditText(this).apply {
            id = View.generateViewId()
            setSingleLine(true)
            hint = "Search categories"
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_DONE
            if (pickerTokens == null) {
                setTextColor(Color.WHITE)
                setHintTextColor(0x80FFFFFF.toInt())
                setBackgroundResource(R.drawable.iptv_guide_search_bg)
                setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0)
                compoundDrawablePadding = dp(10)
                compoundDrawableTintList =
                    android.content.res.ColorStateList.valueOf(0xB3FFFFFF.toInt())
            } else {
                setTextColor(pickerTokens.fg)
                setHintTextColor(pickerTokens.fgFaint)
                background = pickerTokens.searchDrawable(dp(10).toFloat())
                setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0)
                compoundDrawablePadding = dp(10)
                TextViewCompat.setCompoundDrawableTintList(
                    this,
                    android.content.res.ColorStateList.valueOf(pickerTokens.fgFaint),
                )
            }
            setPadding(dp(16), 0, dp(16), 0)
        }
        val statusText = TextView(this).apply {
            setPadding(dp(2), dp(12), dp(2), dp(8))
            setTextColor(pickerTokens?.fgDim ?: 0xB3FFFFFF.toInt())
            textSize = 13f
        }
        val categoryList = RecyclerView(this).apply {
            id = View.generateViewId()
            layoutManager = LinearLayoutManager(
                this@AndroidTvTorrentPlayerActivity,
                LinearLayoutManager.VERTICAL,
                false,
            )
            isFocusable = true
            clipToPadding = false
            setPadding(0, 0, 0, dp(16))
        }

        container.addView(
            searchInput,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48),
            ),
        )
        container.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(
            categoryList,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                categoryListHeight,
            ),
        )

        lateinit var dialog: AlertDialog
        val adapter = IptvCategoryAdapter(
            selectedCategory = iptvSelectedCategory,
            searchViewId = searchInput.id,
            tokens = pickerTokens,
            rowRadiusPx = dp(8).toFloat(),
        ) { category ->
            dialog.dismiss()
            commitIptvAllCategorySearch()
            iptvSelectedCategory = category.takeUnless { it == allLabel }
            iptvGuideSearch?.setText("")
            refreshIptvBrowserChrome()
            requestIptvBrowse(action = "browse", query = "")
        }
        categoryList.adapter = adapter

        fun applyCategoryFilter(rawQuery: String) {
            val query = rawQuery.trim().lowercase()
            val terms = query.split(Regex("\\s+")).filter { it.isNotEmpty() }
            val matches = if (terms.isEmpty()) {
                categories
            } else {
                categories.filter { category ->
                    val haystack = category.lowercase()
                    terms.all(haystack::contains)
                }
            }
            adapter.update(listOf(allLabel) + matches)
            statusText.text = when {
                categories.isEmpty() -> "No categories available"
                matches.isEmpty() -> "No matching categories"
                matches.size == 1 -> "1 category"
                else -> "${matches.size} categories"
            }
        }

        searchInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(
                text: CharSequence?,
                start: Int,
                count: Int,
                after: Int,
            ) = Unit

            override fun onTextChanged(
                text: CharSequence?,
                start: Int,
                before: Int,
                count: Int,
            ) = Unit

            override fun afterTextChanged(text: android.text.Editable?) {
                applyCategoryFilter(text?.toString().orEmpty())
            }
        })
        searchInput.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN &&
                event.action == KeyEvent.ACTION_DOWN &&
                event.repeatCount == 0
            ) {
                categoryList.scrollToPosition(0)
                categoryList.post {
                    categoryList.findViewHolderForAdapterPosition(0)
                        ?.itemView?.requestFocus()
                }
                true
            } else {
                false
            }
        }
        searchInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                categoryList.scrollToPosition(0)
                categoryList.post {
                    categoryList.findViewHolderForAdapterPosition(0)
                        ?.itemView?.requestFocus()
                }
                true
            } else {
                false
            }
        }

        applyCategoryFilter("")
        dialog = AlertDialog.Builder(this, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle("Choose category")
            .setView(container)
            .setNegativeButton("Cancel", null)
            .create()
        // Styled looks give the dialog their own (flattened-opaque) panel.
        pickerTokens?.let { t ->
            dialog.window?.setBackgroundDrawable(
                GradientDrawable().apply {
                    cornerRadius = dp(18).toFloat()
                    setColor(t.panelOpaque)
                    setStroke(dp(1), t.hairline2)
                },
            )
        }
        dialog.setOnShowListener {
            searchInput.requestFocus()
            dialog.window?.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE,
            )
        }
        dialog.show()
    }

    private class IptvCategoryAdapter(
        private val selectedCategory: String?,
        private val searchViewId: Int,
        private val tokens: GuideTokens? = null,
        private val rowRadiusPx: Float = 0f,
        private val onSelected: (String) -> Unit,
    ) : RecyclerView.Adapter<IptvCategoryAdapter.ViewHolder>() {
        private val categories = mutableListOf<String>()

        class ViewHolder(val label: TextView) : RecyclerView.ViewHolder(label)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val density = parent.resources.displayMetrics.density
            fun px(dp: Int) = (dp * density).toInt()
            val label = TextView(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    px(52),
                ).apply {
                    bottomMargin = px(6)
                }
                isFocusable = true
                isClickable = true
                gravity = Gravity.CENTER_VERTICAL
                setPadding(px(16), 0, px(16), 0)
                if (tokens == null) {
                    setBackgroundResource(R.drawable.iptv_premium_button_bg)
                    setTextColor(
                        ContextCompat.getColorStateList(
                            context,
                            R.color.iptv_premium_button_text,
                        ),
                    )
                } else {
                    background = tokens.buttonBackground(rowRadiusPx)
                    setTextColor(tokens.buttonTextColors())
                }
                textSize = 15f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                stateListAnimator = null
            }

            return ViewHolder(label)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val category = categories[position]
            holder.label.text = category
            holder.label.isSelected =
                category == (selectedCategory ?: "All categories")
            holder.label.nextFocusUpId =
                if (position == 0) searchViewId else View.NO_ID
            holder.label.setOnClickListener { onSelected(category) }
            holder.label.setOnFocusChangeListener { view, focused ->
                view.animate()
                    .scaleX(if (focused) 1.015f else 1f)
                    .scaleY(if (focused) 1.015f else 1f)
                    .setDuration(120)
                    .start()
            }
        }

        override fun getItemCount(): Int = categories.size

        fun update(items: List<String>) {
            categories.clear()
            categories.addAll(items)
            notifyDataSetChanged()
        }
    }


    /// "Add to list" checklist for one channel. Reached by long-click once the
    /// user has created a list of their own; before that the same gesture
    /// toggles the favourite outright, exactly as it always did.
    ///
    /// Membership is fetched per channel rather than shipped with every
    /// channel at launch — the launch payload is already capped for size.
    /// Creating a list stays on the Flutter side; this only picks.
    private fun showIptvListPicker(entry: IptvChannelEntry) {
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            toggleIptvFavorite(entry)
            return
        }
        val listHeight = minOf(
            dp(400),
            (resources.displayMetrics.heightPixels * 0.5f).toInt(),
        )
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(8), dp(24), 0)
        }
        val pickerTokens = guideTokens
        val statusText = TextView(this).apply {
            setPadding(dp(2), dp(4), dp(2), dp(8))
            setTextColor(pickerTokens?.fgDim ?: 0xB3FFFFFF.toInt())
            textSize = 13f
            text = "Loading lists…"
        }
        val listView = RecyclerView(this).apply {
            layoutManager = LinearLayoutManager(
                this@AndroidTvTorrentPlayerActivity,
                LinearLayoutManager.VERTICAL,
                false,
            )
            isFocusable = true
            clipToPadding = false
            setPadding(0, 0, 0, dp(16))
        }
        container.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(
            listView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                listHeight,
            ),
        )

        val membership = mutableSetOf<String>()
        val adapter = IptvListPickerAdapter(
            iptvLists,
            membership,
            tokens = pickerTokens,
            rowRadiusPx = dp(8).toFloat(),
        ) { list ->
            val nowIn = !membership.contains(list.id)
            if (nowIn) membership.add(list.id) else membership.remove(list.id)
            // Favorites drives the star badge in the guide, so keep the row in
            // step when it is the list being toggled.
            if (list.isBuiltin) {
                entry.isFavorite = nowIn
                iptvChannelAdapter?.notifyFavoriteFor(entry)
            }
            // Removing a channel from the list currently being browsed has to
            // take its row out of the guide too — otherwise it stays there,
            // still selectable, claiming a membership it no longer has.
            if (!nowIn) {
                val browsing = iptvSources.firstOrNull { it.id == iptvSourceId }
                val browsingThisList = browsing != null &&
                    (browsing.listId == list.id ||
                        (list.isBuiltin && browsing.isFavorites))
                if (browsingThisList) removeIptvGuideRow(entry)
            }
            channel.invokeMethod(
                "setIptvChannelInList",
                hashMapOf<String, Any?>(
                    "listId" to list.id,
                    "inList" to nowIn,
                    "url" to entry.url,
                    "name" to entry.name,
                    "logoUrl" to entry.logoUrl,
                    "group" to entry.group,
                    "sourceId" to entry.sourceId,
                    "channelNumber" to entry.channelNumber,
                    "contentType" to entry.contentType,
                    "duration" to entry.duration,
                    "httpHeaders" to entry.httpHeaders,
                ),
            )
        }
        listView.adapter = adapter

        val dialog = AlertDialog.Builder(this, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle(entry.name)
            .setView(container)
            .setNegativeButton("Done", null)
            .create()
        pickerTokens?.let { t ->
            dialog.window?.setBackgroundDrawable(
                GradientDrawable().apply {
                    cornerRadius = dp(18).toFloat()
                    setColor(t.panelOpaque)
                    setStroke(dp(1), t.hairline2)
                },
            )
        }
        dialog.show()

        channel.invokeMethod(
            "getIptvChannelListMembership",
            hashMapOf<String, Any?>("url" to entry.url),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val ids = (result as? List<*>)?.mapNotNull { it as? String }.orEmpty()
                    membership.clear()
                    membership.addAll(ids)
                    statusText.text = "Pick the lists this channel belongs to"
                    // Rows only exist from here on: toggling against an
                    // unloaded membership set would read every list as "not
                    // in", so pressing an already-added list would re-add it
                    // instead of removing it.
                    adapter.setReady(true)
                    listView.post {
                        listView.findViewHolderForAdapterPosition(0)
                            ?.itemView?.requestFocus()
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    statusText.text = "Couldn't load your lists"
                }

                override fun notImplemented() {
                    statusText.text = "Couldn't load your lists"
                }
            },
        )
    }

    /// Drop [entry] from the guide after it left the list being browsed.
    ///
    /// A local removal rather than a re-browse: re-requesting the source would
    /// rebuild the whole window and throw away the user's scroll position and
    /// focus, for a change we already know the shape of. The adapter diffs, so
    /// the row animates out and the rest keep their holders.
    private fun removeIptvGuideRow(entry: IptvChannelEntry) {
        // The playing channel is not removable from under the player — it
        // would strand zapping with no current index. Its membership is gone
        // in storage either way; the row simply outlives the session.
        if (entry.isCurrent) return
        val removedFromBrowse = iptvBrowseChannels.removeAll { it === entry }
        iptvSearchSavedChannels.removeAll { it === entry }
        if (!removedFromBrowse) return
        iptvChannelAdapter?.updateChannels(iptvBrowseChannels.toList())
        refreshIptvBrowserChrome()
    }

    private class IptvListPickerAdapter(
        private val lists: List<IptvListEntry>,
        private val membership: Set<String>,
        private val tokens: GuideTokens? = null,
        private val rowRadiusPx: Float = 0f,
        private val onToggle: (IptvListEntry) -> Unit,
    ) : RecyclerView.Adapter<IptvListPickerAdapter.ViewHolder>() {
        // No rows until the channel's real membership has landed — see the
        // success callback in showIptvListPicker.
        private var ready = false

        fun setReady(value: Boolean) {
            if (ready == value) return
            ready = value
            notifyDataSetChanged()
        }

        class ViewHolder(val label: TextView) : RecyclerView.ViewHolder(label)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val density = parent.resources.displayMetrics.density
            fun px(dp: Int) = (dp * density).toInt()
            val label = TextView(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    px(52),
                ).apply {
                    bottomMargin = px(6)
                }
                isFocusable = true
                isClickable = true
                gravity = Gravity.CENTER_VERTICAL
                setPadding(px(16), 0, px(16), 0)
                if (tokens == null) {
                    setBackgroundResource(R.drawable.iptv_premium_button_bg)
                    setTextColor(
                        ContextCompat.getColorStateList(
                            context,
                            R.color.iptv_premium_button_text,
                        ),
                    )
                } else {
                    background = tokens.buttonBackground(rowRadiusPx)
                    setTextColor(tokens.buttonTextColors())
                }
                textSize = 15f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                stateListAnimator = null
            }
            return ViewHolder(label)
        }

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val list = lists[position]
            val checked = membership.contains(list.id)
            holder.label.text = if (checked) "\u2713  ${list.name}" else list.name
            holder.label.isSelected = checked
            holder.label.setOnClickListener {
                onToggle(list)
                notifyItemChanged(position)
            }
            holder.label.setOnFocusChangeListener { view, focused ->
                view.animate()
                    .scaleX(if (focused) 1.015f else 1f)
                    .scaleY(if (focused) 1.015f else 1f)
                    .setDuration(120)
                    .start()
            }
        }

        override fun getItemCount(): Int = if (ready) lists.size else 0
    }


    private fun requestIptvBrowse(
        action: String,
        query: String = iptvGuideSearch?.text?.toString()?.trim().orEmpty(),
        channelUrl: String? = null,
        title: String? = null,
        sourceIdOverride: String? = null,
    ) {
        val channel = MainActivity.getAndroidTvPlayerChannel() ?: return
        val uiContext = ++iptvUiContextToken
        iptvZapOwnsUiContext = false
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()
        val token = ++iptvBrowseToken
        iptvBrowseLoading?.visibility = View.VISIBLE
        val args = hashMapOf<String, Any?>(
            "action" to action,
            "sourceId" to (sourceIdOverride ?: iptvSourceId),
            "contentType" to iptvContentType,
            "category" to iptvSelectedCategory,
            "query" to query,
            "channelUrl" to channelUrl,
            "title" to title,
        )
        channel.invokeMethod(
            "requestIptvBrowse",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    if (token != iptvBrowseToken ||
                        uiContext != iptvUiContextToken ||
                        iptvZapOwnsUiContext
                    ) return
                    iptvBrowseLoading?.visibility = View.GONE
                    val response = result as? Map<*, *> ?: return
                    val keepSearchFocus = iptvGuideSearch?.hasFocus() == true
                    val channels = parseIptvChannels(response["channels"] as? List<*> ?: emptyList<Any>())
                    val playingUrl = iptvChannels.getOrNull(currentIptvIndex)?.url
                    channels.forEach { it.isCurrent = it.url == playingUrl }
                    iptvGuideUsesZapWindow = false
                    iptvBrowseChannels = channels
                    iptvChannelAdapter?.updateChannels(channels)
                    (response["sourceId"] as? String)?.let { iptvSourceId = it }
                    (response["sourceName"] as? String)?.let { iptvSourceName = it }
                    (response["contentType"] as? String)?.let { iptvContentType = it }
                    iptvSelectedCategory =
                        (response["selectedCategory"] as? String)?.takeIf { it.isNotEmpty() }
                            ?: iptvSelectedCategory
                    val categories = (response["categories"] as? List<*>)
                        ?.mapNotNull { it as? String }
                        ?.filter { it.isNotEmpty() }
                        .orEmpty()
                    if (iptvSelectedCategory == null) {
                        iptvCategories = categories.toMutableList()
                    }
                    refreshIptvBrowserChrome(response["title"] as? String ?: title)
                    if (keepSearchFocus) {
                        // RecyclerView updates and the result-focus post below
                        // must not eject the IME after every typed character.
                        iptvGuideSearch?.post {
                            if (iptvGuideVisible) iptvGuideSearch?.requestFocus()
                        }
                    } else if (channels.isNotEmpty()) {
                        iptvGuideList?.scrollToPosition(0)
                        iptvGuideList?.post {
                            iptvGuideList?.findViewHolderForAdapterPosition(0)
                                ?.itemView?.requestFocus()
                        }
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (token != iptvBrowseToken ||
                        uiContext != iptvUiContextToken ||
                        iptvZapOwnsUiContext
                    ) return
                    iptvBrowseLoading?.visibility = View.GONE
                    Toast.makeText(
                        this@AndroidTvTorrentPlayerActivity,
                        message ?: "Unable to load IPTV catalog",
                        Toast.LENGTH_SHORT,
                    ).show()
                }

                override fun notImplemented() {
                    if (token == iptvBrowseToken &&
                        uiContext == iptvUiContextToken &&
                        !iptvZapOwnsUiContext
                    ) {
                        iptvBrowseLoading?.visibility = View.GONE
                    }
                }
            },
        )
    }

    private fun toggleIptvFavorite(entry: IptvChannelEntry) {
        entry.isFavorite = !entry.isFavorite
        if (iptvAllCategorySearchActive) {
            iptvSearchSavedChannels
                .filter {
                    it.url == entry.url &&
                        it.name == entry.name &&
                        it.sourceId == entry.sourceId
                }
                .forEach { it.isFavorite = entry.isFavorite }
        }
        iptvChannelAdapter?.notifyFavoriteFor(entry)
        val args = hashMapOf<String, Any?>(
            "url" to entry.url,
            "name" to entry.name,
            "logoUrl" to entry.logoUrl,
            "group" to entry.group,
            "sourceId" to entry.sourceId,
            "channelNumber" to entry.channelNumber,
            // Without these a movie favourited here would be replayed as a
            // live channel and lose its resume bar — the list view rebuilds
            // rows from stored metadata alone.
            "contentType" to entry.contentType,
            "duration" to entry.duration,
            "httpHeaders" to entry.httpHeaders,
            "isFavorite" to entry.isFavorite,
        )
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("setIptvFavorite", args)
        Toast.makeText(
            this,
            if (entry.isFavorite) "Added to favorites" else "Removed from favorites",
            Toast.LENGTH_SHORT,
        ).show()
    }

    // ── IPTV EPG ─────────────────────────────────────────────────────────
    // Guide data comes from Flutter over the bridge (the Dart EPG service
    // recovers Xtream credentials from the channel URL and owns all caching),
    // so the native side only ever asks and paints.

    /** Fetch now/next for [entry] unless it's already fresh or in flight. */
    private fun ensureIptvChannelEpg(entry: IptvChannelEntry) {
        if (!entry.isLive || entry.epgLoading) return
        val stale = entry.epgLoaded && entry.epgNowStopMs > 0 &&
            entry.epgNowStopMs < System.currentTimeMillis()
        if (entry.epgLoaded && !stale) return
        if (!entry.url.startsWith("http")) return // stremio-tv:// keys etc.

        entry.epgLoading = true
        requestIptvEpg(entry.url, includeSchedule = false) { result ->
            entry.epgLoading = false
            entry.epgLoaded = true
            val now = result?.get("now") as? Map<*, *>
            entry.epgNowTitle =
                (now?.get("title") as? String)?.takeIf { it.isNotBlank() }
            entry.epgNowStartMs = (now?.get("startMs") as? Number)?.toLong() ?: 0L
            entry.epgNowStopMs = (now?.get("stopMs") as? Number)?.toLong() ?: 0L
            val next = result?.get("next") as? Map<*, *>
            entry.epgNextTitle =
                (next?.get("title") as? String)?.takeIf { it.isNotBlank() }
            entry.epgNextStartMs =
                (next?.get("startMs") as? Number)?.toLong() ?: 0L
            if (entry.epgNowTitle == null) {
                // Nothing airing per this answer — a guide still downloading
                // on the Flutter side, a transient fetch failure, or a gap
                // until the next programme. Without a retry deadline the
                // stale rule (`stopMs > 0 && stopMs < now`) never re-arms
                // and the entry stays blank all session. Reuse stopMs as
                // "re-ask at": when the next programme starts, or in 60
                // seconds — short, because the common cause is the guide
                // finishing its download moments after the first ask, and a
                // longer lock reads as "EPG doesn't work on TV". Dart's
                // caches rate-limit the repeat asks.
                val retryAt = System.currentTimeMillis() + 60 * 1000L
                val nextStart = entry.epgNextStartMs
                entry.epgNowStopMs =
                    if (nextStart > 0 && nextStart < retryAt) nextStart else retryAt
            }
            iptvChannelAdapter?.notifyEpgFor(entry)
            if (entry.isCurrent) {
                updateIptvGuideEpgHeader()
                // A visible zap banner for this channel paints the fresh data.
                if (iptvZapBanner?.visibility == View.VISIBLE) {
                    paintIptvZapBannerEpg(entry)
                }
            }
        }
    }

    /** Paint the playing channel's now/next line in the guide header. */
    private fun updateIptvGuideEpgHeader() {
        val epgView = iptvGuideCurrentEpg ?: return
        val entry = iptvChannels.getOrNull(currentIptvIndex)
        val nowTitle = entry?.epgNowTitle
        if (entry == null || nowTitle == null) {
            epgView.visibility = View.GONE
            return
        }
        val text = StringBuilder("Now: $nowTitle")
        entry.epgNextTitle?.let { text.append("   ›   Next: $it") }
        epgView.text = text
        epgView.visibility = View.VISIBLE
    }

    /** The guide-list entry that currently holds DPAD focus, if any. */
    private fun focusedIptvGuideEntry(): IptvChannelEntry? {
        val list = iptvGuideList ?: return null
        val focused = list.focusedChild ?: return null
        val holder = list.getChildViewHolder(focused) ?: return null
        val position = holder.bindingAdapterPosition
        if (position == RecyclerView.NO_POSITION) return null
        return iptvChannelAdapter?.entryAt(position)
    }

    private fun formatEpgTime(ms: Long): String =
        android.text.format.DateFormat.getTimeFormat(this).format(java.util.Date(ms))

    /** RIGHT on a live row opens its schedule beside the Lean Rail. */
    private fun showIptvSchedulePane(entry: IptvChannelEntry) {
        val token = ++iptvEpgToken
        iptvEpgEntry = entry
        iptvEpgVisible = true
        // The floating now-playing card occupies the same right-hand space on
        // compact TV viewports. Keep the schedule column completely exposed.
        iptvGuideNowPlaying?.visibility = View.GONE
        iptvEpgDayOffset = 0
        iptvEpgPrograms = emptyList()
        iptvEpgPanel?.visibility = View.VISIBLE
        iptvEpgLoading?.visibility = View.VISIBLE
        iptvEpgEmpty?.visibility = View.GONE
        iptvEpgList?.visibility = View.GONE
        iptvEpgChannelName?.text = entry.displayName
        iptvEpgChannelGroup?.text =
            listOfNotNull(
                entry.group,
                "Channel ${entry.channelNumber ?: (entry.index + 1)}",
            ).joinToString(" · ")
        paintIptvEpgLogo(entry)
        selectIptvEpgDay(0, requestFocus = false)

        requestIptvEpg(entry.url, includeSchedule = true) { result ->
            if (token != iptvEpgToken || isFinishing || isDestroyed ||
                !iptvGuideVisible || !iptvEpgVisible
            ) {
                return@requestIptvEpg
            }
            iptvEpgPrograms = (result?.get("schedule") as? List<*>)
                ?.mapNotNull { it as? Map<*, *> }
                ?.mapNotNull { item ->
                    val title = (item["title"] as? String)?.takeIf { it.isNotBlank() }
                        ?: return@mapNotNull null
                    val startMs = (item["startMs"] as? Number)?.toLong()
                        ?: return@mapNotNull null
                    val stopMs = (item["stopMs"] as? Number)?.toLong()
                        ?: return@mapNotNull null
                    IptvEpgProgram(
                        title = title,
                        description = (item["description"] as? String)
                            ?.takeIf { it.isNotBlank() },
                        startMs = startMs,
                        stopMs = stopMs,
                        hasArchive = item["hasArchive"] == true,
                    )
                } ?: emptyList()
            iptvEpgLoading?.visibility = View.GONE
            selectIptvEpgDay(0)
        }
    }

    private fun paintIptvEpgLogo(entry: IptvChannelEntry) {
        val firstLetter = entry.name.firstOrNull()?.uppercase() ?: "?"
        if (entry.logoUrl.isNullOrEmpty()) {
            iptvEpgLogo?.visibility = View.GONE
            iptvEpgLetter?.text = firstLetter
            iptvEpgLetter?.visibility = View.VISIBLE
            return
        }
        iptvEpgLetter?.visibility = View.GONE
        iptvEpgLogo?.visibility = View.VISIBLE
        iptvEpgLogo?.let { logo ->
            com.bumptech.glide.Glide.with(this)
                .load(entry.logoUrl)
                .centerInside()
                .listener(
                    object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                        override fun onLoadFailed(
                            e: com.bumptech.glide.load.engine.GlideException?,
                            model: Any?,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                            isFirstResource: Boolean,
                        ): Boolean {
                            logo.visibility = View.GONE
                            iptvEpgLetter?.text = firstLetter
                            iptvEpgLetter?.visibility = View.VISIBLE
                            return true
                        }

                        override fun onResourceReady(
                            resource: android.graphics.drawable.Drawable,
                            model: Any,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                            dataSource: com.bumptech.glide.load.DataSource,
                            isFirstResource: Boolean,
                        ): Boolean = false
                    },
                )
                .into(logo)
        }
    }

    private fun selectIptvEpgDay(dayOffset: Int, requestFocus: Boolean = true) {
        iptvEpgDayOffset = dayOffset
        val calendar = java.util.Calendar.getInstance().apply {
            add(java.util.Calendar.DAY_OF_YEAR, dayOffset)
        }
        val year = calendar.get(java.util.Calendar.YEAR)
        val day = calendar.get(java.util.Calendar.DAY_OF_YEAR)
        val filtered = iptvEpgPrograms.filter { program ->
            java.util.Calendar.getInstance().apply { timeInMillis = program.startMs }.let {
                it.get(java.util.Calendar.YEAR) == year &&
                    it.get(java.util.Calendar.DAY_OF_YEAR) == day
            }
        }
        iptvEpgDate?.text = java.text.SimpleDateFormat(
            "EEEE, d MMMM",
            Locale.getDefault(),
        ).format(calendar.time)
        iptvEpgAdapter?.updatePrograms(filtered)
        iptvEpgList?.visibility = if (filtered.isEmpty()) View.GONE else View.VISIBLE
        iptvEpgEmpty?.visibility =
            if (filtered.isEmpty() && iptvEpgLoading?.visibility != View.VISIBLE) {
                View.VISIBLE
            } else {
                View.GONE
            }
        val dayButtons = listOf(
            0 to findViewById<AppCompatButton>(R.id.iptv_epg_day_today),
            1 to findViewById<AppCompatButton>(R.id.iptv_epg_day_tomorrow),
            2 to findViewById<AppCompatButton>(R.id.iptv_epg_day_later),
        )
        dayButtons.forEach { (offset, button) ->
            button?.isSelected = offset == dayOffset
        }
        if (requestFocus && filtered.isNotEmpty()) {
            val now = System.currentTimeMillis()
            val position = filtered.indexOfFirst { it.startMs <= now && now < it.stopMs }
                .coerceAtLeast(0)
            iptvEpgList?.scrollToPosition(position)
            iptvEpgList?.post {
                iptvEpgList?.findViewHolderForAdapterPosition(position)
                    ?.itemView?.requestFocus()
            }
        }
    }

    private fun hideIptvEpgPane() {
        iptvEpgToken++
        iptvEpgVisible = false
        iptvEpgEntry = null
        iptvEpgPanel?.visibility = View.GONE
        iptvGuideNowPlaying?.visibility =
            if (iptvGuideVisible && currentIptvIndex in iptvChannels.indices) {
                View.VISIBLE
            } else {
                View.GONE
            }
        iptvEpgPrograms = emptyList()
        iptvEpgAdapter?.updatePrograms(emptyList())
    }

    private fun requestIptvCatchup(
        channelEntry: IptvChannelEntry,
        programme: IptvEpgProgram,
    ) {
        if (!programme.hasArchive || programme.stopMs >= System.currentTimeMillis()) return
        val channel = MainActivity.getAndroidTvPlayerChannel() ?: return
        val token = iptvEpgToken
        Toast.makeText(this, "Preparing replay…", Toast.LENGTH_SHORT).show()
        channel.invokeMethod(
            "requestIptvCatchup",
            mapOf(
                "channelUrl" to channelEntry.url,
                "startMs" to programme.startMs,
                "channelName" to channelEntry.name,
                "logoUrl" to channelEntry.logoUrl,
                "playlistId" to channelEntry.sourceId,
                "httpHeaders" to channelEntry.httpHeaders,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    if (token != iptvEpgToken || !iptvGuideVisible) return
                    val response = result as? Map<*, *>
                    val url = response?.get("url") as? String
                    if (url.isNullOrEmpty()) {
                        Toast.makeText(
                            this@AndroidTvTorrentPlayerActivity,
                            "Replay is not available",
                            Toast.LENGTH_SHORT,
                        ).show()
                        return
                    }
                    checkpointCurrentIptvPosition()
                    val replay = IptvChannelEntry(
                        index = 0,
                        channelNumber = null,
                        name = response["title"] as? String ?: programme.title,
                        url = url,
                        logoUrl = channelEntry.logoUrl,
                        group = channelEntry.name,
                        isLive = false,
                        isCurrent = true,
                        resumePositionMs =
                            (response["resumePositionMs"] as? Number)?.toLong() ?: 0L,
                        httpHeaders = channelEntry.httpHeaders,
                        contentType = "vod",
                        sourceId = channelEntry.sourceId,
                        sourceName = channelEntry.sourceName,
                    )
                    iptvChannels.forEach { it.isCurrent = false }
                    iptvChannels = mutableListOf(replay)
                    currentIptvIndex = 0
                    iptvSeriesAudioKey = null
                    // Starting a replay is a real playback switch, just like
                    // selecting a live search result. Do not restore the
                    // category that preceded Search while closing the guide.
                    commitIptvAllCategorySearch()
                    hideIptvGuide()
                    resetSubtitleState()
                    beginIptvPlayback(replay)
                    titleView.text = replay.name
                    updateIptvEpisodeControls()
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (token != iptvEpgToken) return
                    Toast.makeText(
                        this@AndroidTvTorrentPlayerActivity,
                        message ?: "Replay is not available",
                        Toast.LENGTH_SHORT,
                    ).show()
                }

                override fun notImplemented() {
                    if (token == iptvEpgToken) {
                        Toast.makeText(
                            this@AndroidTvTorrentPlayerActivity,
                            "Replay is not available",
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            },
        )
    }

    private fun isFocusInIptvEpgPanel(): Boolean {
        val focused = currentFocus ?: return false
        val panel = iptvEpgPanel ?: return false
        var node: View? = focused
        while (node != null) {
            if (node === panel) return true
            node = node.parent as? View
        }
        return false
    }

    /**
     * Ask Flutter for a channel's guide data. Always answers asynchronously
     * on the main thread — the failure paths are posted on purpose, because
     * the callback runs notifyItemChanged and a synchronous invocation from
     * onBindViewHolder would fire it while RecyclerView is computing layout
     * (IllegalStateException). MethodChannel results are async already.
     */
    private fun requestIptvEpg(
        channelUrl: String,
        includeSchedule: Boolean,
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
                "channelUrl" to channelUrl,
                "includeSchedule" to includeSchedule,
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

    private fun updateIptvGuideCurrentName() {
        if (currentIptvIndex in iptvChannels.indices) {
            val ch = iptvChannels[currentIptvIndex]
            iptvGuideCurrentName?.text = ch.displayName
            iptvGuideNowPlaying?.visibility =
                if (iptvEpgVisible) View.GONE else View.VISIBLE

            // Group
            if (ch.group != null && ch.group.isNotEmpty()) {
                iptvGuideCurrentGroup?.text = ch.group
                iptvGuideCurrentGroup?.visibility = View.VISIBLE
            } else {
                iptvGuideCurrentGroup?.visibility = View.GONE
            }

            // EPG now/next for the playing channel
            updateIptvGuideEpgHeader()
            ensureIptvChannelEpg(ch)

            // Now playing logo
            val firstLetter = if (ch.name.isNotEmpty()) ch.name[0].uppercase() else "?"
            if (!ch.logoUrl.isNullOrEmpty()) {
                iptvGuideNowLetter?.visibility = View.GONE
                iptvGuideNowLogo?.visibility = View.VISIBLE
                com.bumptech.glide.Glide.with(this)
                    .load(ch.logoUrl)
                    .centerInside()
                    .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                        override fun onLoadFailed(
                            e: com.bumptech.glide.load.engine.GlideException?,
                            model: Any?,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                            isFirstResource: Boolean
                        ): Boolean {
                            iptvGuideNowLogo?.visibility = View.GONE
                            iptvGuideNowLetter?.text = firstLetter
                            iptvGuideNowLetter?.visibility = View.VISIBLE
                            return true
                        }
                        override fun onResourceReady(
                            resource: android.graphics.drawable.Drawable,
                            model: Any,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                            dataSource: com.bumptech.glide.load.DataSource,
                            isFirstResource: Boolean
                        ): Boolean = false
                    })
                    .into(iptvGuideNowLogo!!)
            } else {
                iptvGuideNowLogo?.visibility = View.GONE
                iptvGuideNowLetter?.text = firstLetter
                iptvGuideNowLetter?.visibility = View.VISIBLE
            }
        } else {
            iptvGuideNowPlaying?.visibility = View.GONE
        }
    }

    /**
     * A guide search is only a way to discover the destination. Once selected,
     * playback belongs to the channel's category: the search is cleared and a
     * small page centered on the channel becomes the CH +/- and guide context.
     */
    private fun beginIptvCategoryZapSession(entry: IptvChannelEntry) {
        commitIptvAllCategorySearch()
        val category = entry.group?.trim()?.takeIf { it.isNotEmpty() }
        val sourceId = iptvSourceId
        val sourceName = iptvSourceName
        val contentType = iptvContentType
        val fallbackChannels = iptvChannelAdapter?.entriesSnapshot().orEmpty()

        iptvSelectedCategory = category
        iptvGuideSearch?.setText("")
        refreshIptvBrowserChrome()

        iptvUiContextToken++
        iptvZapOwnsUiContext = true
        iptvBrowseToken++
        iptvZapPagingActive = true
        iptvZapCategory = category
        iptvZapSourceId = sourceId
        iptvZapSourceName = sourceName
        iptvZapContentType = contentType
        iptvZapCategories = iptvCategories.toMutableList()
        iptvZapCategoryTotal = 1
        iptvZapPendingInputs.clear()
        iptvGuideUsesZapWindow = false
        // A second rapid selection supersedes a page still returning for the
        // previous result.
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        clearIptvZapBoundaryCache()

        // Do not let the search matches become the temporary zap list while
        // the centered category page crosses the platform channel.
        switchToIptvChannel(entry, adoptVisibleBrowseList = false)
        requestIptvZapPage(
            category = category,
            offset = 0,
            anchor = entry,
            onFailure = {
                restoreIptvZapBootstrapFallback(entry, fallbackChannels)
            },
        ) { channels, pageOffset, total, responseCategory, categories ->
            val containsPlayingChannel = channels.any {
                it.url == entry.url && it.name == entry.name
            }
            if (channels.isEmpty() || !containsPlayingChannel) {
                restoreIptvZapBootstrapFallback(entry, fallbackChannels)
                return@requestIptvZapPage
            }
            installIptvZapWindow(
                channels = channels,
                pageOffset = pageOffset,
                total = total,
                category = responseCategory,
                categories = categories,
                preservePlayingChannel = true,
            )
            drainPendingIptvZapInputs()
            prefetchIptvZapPage(1)
            prefetchAdjacentIptvCategory(1)
        }
    }

    /**
     * The launch payload is capped and has window-relative indices. Resolve a
     * small anchored page immediately so CH +/- works across the full category
     * even before the user opens the guide for the first time.
     */
    private fun bootstrapInitialIptvZapPaging(entry: IptvChannelEntry) {
        if (!entry.isLive || iptvContentType != "live") return
        val category =
            entry.group?.trim()?.takeIf { it.isNotEmpty() } ?: iptvSelectedCategory
        iptvSelectedCategory = category
        iptvZapCategory = category
        refreshIptvBrowserChrome()
        requestIptvZapPage(
            category = category,
            offset = 0,
            anchor = entry,
        ) { channels, pageOffset, total, responseCategory, categories ->
            val playing = iptvChannels.getOrNull(currentIptvIndex)
            if (playing?.url != entry.url || playing.name != entry.name) {
                if (playing?.isLive == true && iptvZapOwnsUiContext) {
                    bootstrapInitialIptvZapPaging(playing)
                }
                return@requestIptvZapPage
            }
            val containsPlayingChannel = channels.any {
                it.url == playing.url && it.name == playing.name
            }
            if (channels.isEmpty() || !containsPlayingChannel) return@requestIptvZapPage
            iptvZapPagingActive = true
            installIptvZapWindow(
                channels = channels,
                pageOffset = pageOffset,
                total = total,
                category = responseCategory,
                categories = categories,
                preservePlayingChannel = true,
            )
            updateIptvEpisodeControls()
            prefetchIptvZapPage(1)
            prefetchAdjacentIptvCategory(1)
        }
    }

    private fun restoreIptvZapBootstrapFallback(
        selected: IptvChannelEntry,
        fallbackChannels: List<IptvChannelEntry>,
    ) {
        val playing = iptvChannels.getOrNull(currentIptvIndex)
        if (playing?.url != selected.url || playing.name != selected.name) return
        disableIptvZapPaging()
        val fallback = fallbackChannels
            .ifEmpty { listOf(selected) }
            .mapIndexed { index, entry ->
                entry.apply {
                    this.index = index
                    isCurrent = url == selected.url && name == selected.name
                }
            }
            .toMutableList()
        if (fallback.none { it.isCurrent }) {
            selected.index = fallback.size
            selected.isCurrent = true
            fallback.add(selected)
        }
        iptvChannels = fallback
        currentIptvIndex = fallback.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        iptvBrowseChannels = fallback.toMutableList()
        iptvGuideUsesZapWindow = false
        iptvChannelAdapter?.updateChannels(fallback)
        refreshIptvBrowserChrome()
    }

    private fun showIptvChannelJumpDialog() {
        val current = iptvChannels.getOrNull(currentIptvIndex)
        if (current?.isLive != true) return
        val activeSource = iptvSources.firstOrNull { it.id == iptvZapSourceId }
        if (activeSource?.isFavorites == true || activeSource?.isList == true) {
            Toast.makeText(
                this,
                "Select a provider before jumping by channel number",
                Toast.LENGTH_SHORT,
            ).show()
            return
        }
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER
            hint = "Channel number"
            setSingleLine(true)
            imeOptions = EditorInfo.IME_ACTION_GO
            setPadding(dp(20), dp(14), dp(20), dp(14))
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle("Jump to channel")
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Jump", null)
            .create()
        dialog.setOnShowListener {
            val submit = {
                val number = input.text?.toString()?.trim()?.toIntOrNull()
                if (number == null || number <= 0) {
                    input.error = "Enter a valid channel number"
                } else {
                    dialog.dismiss()
                    requestIptvChannelJump(number)
                }
            }
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                submit()
            }
            input.setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_GO) {
                    submit()
                    true
                } else {
                    false
                }
            }
            input.requestFocus()
            dialog.window?.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE
            )
        }
        dialog.show()
    }

    private fun requestIptvChannelJump(channelNumber: Int) {
        val bridge = MainActivity.getAndroidTvPlayerChannel()
        if (bridge == null) {
            Toast.makeText(this, "Channel lookup is unavailable", Toast.LENGTH_SHORT).show()
            return
        }
        val token = ++iptvZapRequestToken
        iptvZapRequestInFlight = true
        bridge.invokeMethod(
            "requestIptvBrowse",
            hashMapOf<String, Any?>(
                "action" to "channelNumber",
                "sourceId" to iptvZapSourceId,
                "contentType" to "live",
                "channelNumber" to channelNumber,
                "limit" to iptvZapPageSize,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    if (token != iptvZapRequestToken) return
                    iptvZapRequestInFlight = false
                    val response = result as? Map<*, *>
                    if (response == null || response["channelNotFound"] == true) {
                        Toast.makeText(
                            this@AndroidTvTorrentPlayerActivity,
                            "Channel $channelNumber was not found",
                            Toast.LENGTH_SHORT,
                        ).show()
                        drainPendingIptvZapInputs()
                        return
                    }
                    val channels = parseIptvChannels(
                        response["channels"] as? List<*> ?: emptyList<Any>()
                    )
                    val target = channels.firstOrNull {
                        it.channelNumber == channelNumber
                    }
                    if (target == null) {
                        Toast.makeText(
                            this@AndroidTvTorrentPlayerActivity,
                            "Channel $channelNumber was not found",
                            Toast.LENGTH_SHORT,
                        ).show()
                        drainPendingIptvZapInputs()
                        return
                    }
                    (response["sourceId"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        iptvZapSourceId = it
                        iptvSourceId = it
                    }
                    (response["sourceName"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        iptvZapSourceName = it
                        iptvSourceName = it
                    }
                    val category =
                        (response["selectedCategory"] as? String)?.takeIf { it.isNotEmpty() }
                    val categories = (response["categories"] as? List<*>)
                        ?.mapNotNull { it as? String }
                        ?.filter { it.isNotEmpty() }
                        .orEmpty()
                    iptvZapContentType = "live"
                    iptvContentType = "live"
                    iptvZapOwnsUiContext = true
                    iptvZapPagingActive = true
                    installIptvZapWindow(
                        channels,
                        (response["pageOffset"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0,
                        (response["totalChannels"] as? Number)?.toInt()
                            ?.coerceAtLeast(0) ?: channels.size,
                        category,
                        categories,
                        preservePlayingChannel = false,
                    )
                    val selected = iptvChannels.firstOrNull {
                        it.channelNumber == channelNumber
                    } ?: return
                    switchToIptvChannel(selected, checkpointOutgoing = false)
                    drainPendingIptvZapInputs()
                    prefetchIptvZapPage(1)
                    prefetchIptvZapPage(-1)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (token != iptvZapRequestToken) return
                    iptvZapRequestInFlight = false
                    Toast.makeText(
                        this@AndroidTvTorrentPlayerActivity,
                        message ?: "Unable to look up that channel",
                        Toast.LENGTH_SHORT,
                    ).show()
                    drainPendingIptvZapInputs()
                }

                override fun notImplemented() {
                    if (token != iptvZapRequestToken) return
                    iptvZapRequestInFlight = false
                    Toast.makeText(
                        this@AndroidTvTorrentPlayerActivity,
                        "Channel lookup is unavailable",
                        Toast.LENGTH_SHORT,
                    ).show()
                    drainPendingIptvZapInputs()
                }
            },
        )
    }

    private fun requestIptvZapPage(
        category: String?,
        offset: Int,
        anchor: IptvChannelEntry? = null,
        fromEnd: Boolean = false,
        onFailure: (() -> Unit)? = null,
        onLoaded: (
            channels: MutableList<IptvChannelEntry>,
            pageOffset: Int,
            total: Int,
            category: String?,
            categories: List<String>,
        ) -> Unit,
    ) {
        if (iptvZapRequestInFlight) return
        val bridge = MainActivity.getAndroidTvPlayerChannel()
        if (bridge == null) {
            onFailure?.invoke()
            return
        }
        val uiContext = iptvUiContextToken
        val token = ++iptvZapRequestToken
        iptvZapRequestInFlight = true
        bridge.invokeMethod(
            "requestIptvBrowse",
            hashMapOf<String, Any?>(
                "action" to "zapPage",
                "sourceId" to iptvZapSourceId,
                "contentType" to iptvZapContentType,
                "category" to category,
                "query" to "",
                "offset" to offset.coerceAtLeast(0),
                "limit" to iptvZapPageSize,
                "anchorUrl" to anchor?.url,
                "anchorName" to anchor?.name,
                "fromEnd" to fromEnd,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    // The flag belongs to the latest request (token), not to the
                    // UI context: a context change while this page was in flight
                    // must not strand iptvZapRequestInFlight at true, or every
                    // later zap page is silently dropped for the whole session.
                    if (token == iptvZapRequestToken) iptvZapRequestInFlight = false
                    if (token != iptvZapRequestToken ||
                        uiContext != iptvUiContextToken ||
                        !iptvZapOwnsUiContext
                    ) return
                    val response = result as? Map<*, *>
                    if (response == null) {
                        iptvZapPendingInputs.clear()
                        onFailure?.invoke()
                        return
                    }
                    (response["sourceId"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        iptvZapSourceId = it
                        iptvSourceId = it
                    }
                    (response["sourceName"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        iptvZapSourceName = it
                        iptvSourceName = it
                    }
                    (response["contentType"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        iptvZapContentType = it
                        iptvContentType = it
                    }
                    val channels = parseIptvChannels(
                        response["channels"] as? List<*> ?: emptyList<Any>()
                    )
                    val pageOffset =
                        (response["pageOffset"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0
                    val total =
                        (response["totalChannels"] as? Number)?.toInt()?.coerceAtLeast(0)
                            ?: channels.size
                    val responseCategory =
                        (response["selectedCategory"] as? String)?.takeIf { it.isNotEmpty() }
                    val categories = (response["categories"] as? List<*>)
                        ?.mapNotNull { it as? String }
                        ?.filter { it.isNotEmpty() }
                        .orEmpty()
                    onLoaded(channels, pageOffset, total, responseCategory, categories)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (token == iptvZapRequestToken) iptvZapRequestInFlight = false
                    if (token != iptvZapRequestToken ||
                        uiContext != iptvUiContextToken ||
                        !iptvZapOwnsUiContext
                    ) return
                    iptvZapPendingInputs.clear()
                    onFailure?.invoke()
                    Toast.makeText(
                        this@AndroidTvTorrentPlayerActivity,
                        message ?: "Unable to load more channels",
                        Toast.LENGTH_SHORT,
                    ).show()
                }

                override fun notImplemented() {
                    if (token == iptvZapRequestToken) iptvZapRequestInFlight = false
                    if (token != iptvZapRequestToken ||
                        uiContext != iptvUiContextToken ||
                        !iptvZapOwnsUiContext
                    ) return
                    iptvZapPendingInputs.clear()
                    onFailure?.invoke()
                }
            },
        )
    }

    private fun installIptvZapWindow(
        channels: MutableList<IptvChannelEntry>,
        pageOffset: Int,
        total: Int,
        category: String?,
        categories: List<String>,
        preservePlayingChannel: Boolean,
    ) {
        if (category != iptvZapCategory) clearIptvZapBoundaryCache()
        val playing = iptvChannels.getOrNull(currentIptvIndex)
        if (!preservePlayingChannel) {
            // The old list is about to disappear. Bank its VOD position while
            // currentIptvIndex still identifies the actual outgoing item.
            checkpointCurrentIptvPosition()
        }
        channels.forEachIndexed { index, entry ->
            entry.index = pageOffset + index
            entry.isCurrent = preservePlayingChannel &&
                playing != null &&
                entry.url == playing.url &&
                entry.name == playing.name
        }

        iptvZapCategory = category
        iptvZapCategoryTotal = total
        if (categories.isNotEmpty()) {
            iptvZapCategories = categories.toMutableList()
            iptvCategories = categories.toMutableList()
        }
        iptvSelectedCategory = category
        iptvChannels = channels
        iptvBrowseChannels = channels.toMutableList()
        iptvGuideUsesZapWindow = true
        currentIptvIndex = channels.indexOfFirst { it.isCurrent }.let { index ->
            if (index >= 0) index else 0
        }
        if (preservePlayingChannel &&
            channels.isNotEmpty() &&
            channels.none { it.isCurrent }
        ) {
            channels[currentIptvIndex].isCurrent = true
        }
        iptvChannelAdapter?.updateChannels(channels)
        refreshIptvBrowserChrome()
        updateIptvGuideCurrentName()
        refreshIptvZapBannerPosition()
    }

    private fun mergeIptvZapPage(
        page: MutableList<IptvChannelEntry>,
        pageOffset: Int,
        total: Int,
        category: String?,
        categories: List<String>,
    ) {
        if (!iptvZapPagingActive || category != iptvZapCategory) return
        val playing = iptvChannels.getOrNull(currentIptvIndex)
        page.forEachIndexed { index, entry -> entry.index = pageOffset + index }
        val byPosition = java.util.TreeMap<Int, IptvChannelEntry>()
        iptvChannels.forEach { byPosition[it.index] = it }
        page.forEach { byPosition[it.index] = it }
        val merged = byPosition.values.toMutableList()
        merged.forEach {
            it.isCurrent = playing != null &&
                it.url == playing.url &&
                it.name == playing.name
        }
        iptvZapCategoryTotal = total
        if (categories.isNotEmpty()) {
            iptvZapCategories = categories.toMutableList()
            iptvCategories = categories.toMutableList()
        }
        val window = boundedHiddenIptvZapWindow(merged)
        iptvChannels = window
        iptvBrowseChannels = window.toMutableList()
        iptvGuideUsesZapWindow = true
        currentIptvIndex = window.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        iptvChannelAdapter?.updateChannels(window)
        refreshIptvBrowserChrome()
        refreshIptvZapBannerPosition()
    }

    private fun boundedHiddenIptvZapWindow(
        channels: MutableList<IptvChannelEntry>,
    ): MutableList<IptvChannelEntry> {
        if (iptvGuideVisible || channels.size <= iptvZapMaxHiddenWindow) return channels
        val current = channels.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        val maxStart = channels.size - iptvZapMaxHiddenWindow
        val start = (current - iptvZapMaxHiddenWindow / 2).coerceIn(0, maxStart)
        return channels.subList(start, start + iptvZapMaxHiddenWindow).toMutableList()
    }

    private fun trimHiddenIptvZapWindow() {
        if (!iptvZapPagingActive || iptvChannels.size <= iptvZapMaxHiddenWindow) return
        val trimmed = boundedHiddenIptvZapWindow(iptvChannels)
        if (trimmed.size == iptvChannels.size) return
        iptvChannels = trimmed
        iptvBrowseChannels = trimmed.toMutableList()
        currentIptvIndex = trimmed.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        if (iptvGuideUsesZapWindow) iptvChannelAdapter?.updateChannels(trimmed)
    }

    private fun prefetchIptvZapPage(delta: Int, force: Boolean = false) {
        if (!iptvZapPagingActive || iptvZapRequestInFlight || iptvChannels.isEmpty()) return
        val firstAbsolute = iptvChannels.first().index
        val lastAbsolute = iptvChannels.last().index
        val shouldLoad = if (delta > 0) {
            lastAbsolute + 1 < iptvZapCategoryTotal &&
                (force || currentIptvIndex >= iptvChannels.size - 12)
        } else {
            firstAbsolute > 0 && (force || currentIptvIndex <= 11)
        }
        if (!shouldLoad) return
        val offset = if (delta > 0) {
            lastAbsolute + 1
        } else {
            (firstAbsolute - iptvZapPageSize).coerceAtLeast(0)
        }
        requestIptvZapPage(
            category = iptvZapCategory,
            offset = offset,
        ) { channels, loadedOffset, total, category, categories ->
            mergeIptvZapPage(channels, loadedOffset, total, category, categories)
            drainPendingIptvZapInputs()
        }
    }

    private fun queuePendingIptvZapInput(delta: Int) {
        if (iptvZapPendingInputs.size < 24) {
            iptvZapPendingInputs.addLast(if (delta >= 0) 1 else -1)
        }
    }

    private fun drainPendingIptvZapInputs() {
        if (iptvZapDrainingInputs) return
        iptvZapDrainingInputs = true
        try {
            while (iptvZapPendingInputs.isNotEmpty()) {
                val delta = iptvZapPendingInputs.removeFirst()
                zapIptvChannel(delta)
                if (iptvZapRequestInFlight) break
            }
        } finally {
            iptvZapDrainingInputs = false
        }
    }

    private fun clearIptvZapBoundaryCache() {
        iptvZapCachedOriginCategory = null
        iptvZapCachedDirection = 0
        // Replace rather than clear: a boundary consumer may already hold the
        // previous list while it atomically installs that cached category.
        iptvZapCachedChannels = mutableListOf()
        iptvZapCachedOffset = 0
        iptvZapCachedTotal = 0
        iptvZapCachedCategory = null
        iptvZapCachedCategories = emptyList()
    }

    private fun disableIptvZapPaging() {
        iptvZapPagingActive = false
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()
        clearIptvZapBoundaryCache()
    }

    private fun adjacentIptvCategory(delta: Int, attempt: Int): String? {
        val categories = iptvZapCategories.distinct()
        val currentCategory = iptvZapCategory ?: return null
        if (categories.isEmpty() || attempt !in 1..categories.size) return null
        val currentIndex = categories.indexOf(currentCategory).let {
            if (it >= 0) it else 0
        }
        val target =
            (currentIndex + delta * attempt + categories.size * 2) % categories.size
        return categories[target]
    }

    private fun prefetchAdjacentIptvCategory(delta: Int, attempt: Int = 1) {
        if (iptvZapCachedChannels.isNotEmpty() &&
            iptvZapCachedDirection != delta
        ) {
            clearIptvZapBoundaryCache()
        }
        if (!iptvZapPagingActive ||
            iptvZapRequestInFlight ||
            iptvZapCategory == null ||
            iptvZapCachedChannels.isNotEmpty()
        ) return
        val nearBoundary = if (delta > 0) {
            iptvChannels.lastOrNull()?.index == iptvZapCategoryTotal - 1 &&
                currentIptvIndex >= iptvChannels.size - 12
        } else {
            iptvChannels.firstOrNull()?.index == 0 && currentIptvIndex <= 11
        }
        if (!nearBoundary) return
        val targetCategory = adjacentIptvCategory(delta, attempt) ?: return
        val originCategory = iptvZapCategory
        requestIptvZapPage(
            category = targetCategory,
            offset = 0,
            fromEnd = delta < 0,
        ) { channels, pageOffset, total, category, categories ->
            if (originCategory != iptvZapCategory) return@requestIptvZapPage
            if (channels.isEmpty()) {
                prefetchAdjacentIptvCategory(delta, attempt + 1)
                return@requestIptvZapPage
            }
            iptvZapCachedOriginCategory = originCategory
            iptvZapCachedDirection = delta
            iptvZapCachedChannels = channels
            iptvZapCachedOffset = pageOffset
            iptvZapCachedTotal = total
            iptvZapCachedCategory = category
            iptvZapCachedCategories = categories
            drainPendingIptvZapInputs()
        }
    }

    private fun consumeCachedAdjacentIptvCategory(delta: Int): Boolean {
        if (iptvZapCachedOriginCategory != iptvZapCategory ||
            iptvZapCachedDirection != delta ||
            iptvZapCachedChannels.isEmpty()
        ) return false
        // Detach from the cache before clearing it. Keeping the same mutable
        // instance here made clearIptvZapBoundaryCache() empty [channels] and
        // the following first()/last() crash at category boundaries.
        val channels = iptvZapCachedChannels.toMutableList()
        val offset = iptvZapCachedOffset
        val total = iptvZapCachedTotal
        val category = iptvZapCachedCategory
        val categories = iptvZapCachedCategories
        clearIptvZapBoundaryCache()
        if (channels.isEmpty()) return false
        installIptvZapWindow(
            channels,
            offset,
            total,
            category,
            categories,
            preservePlayingChannel = false,
        )
        val destination =
            if (delta > 0) iptvChannels.firstOrNull() else iptvChannels.lastOrNull()
        if (destination == null) return false
        switchToIptvChannel(destination, checkpointOutgoing = false)
        prefetchIptvZapPage(delta)
        prefetchAdjacentIptvCategory(delta)
        return true
    }

    private fun switchToIptvChannel(
        entry: IptvChannelEntry,
        adoptVisibleBrowseList: Boolean = true,
        checkpointOutgoing: Boolean = true,
    ) {
        android.util.Log.d("AndroidTvPlayer", "switchToIptvChannel: ${entry.name} (index=${entry.index})")
        val previousPlaying = iptvChannels.getOrNull(currentIptvIndex)
        // Bank the outgoing channel's position BEFORE currentIptvIndex moves,
        // or zapping back to a half-watched movie would rewind it to wherever
        // it stood when the player was launched.
        if (checkpointOutgoing) checkpointCurrentIptvPosition()
        // A channel zap orphans any pending source-switch watcher (see playItem)
        dropStaleSourceSwitchFeedback()

        // Browsing can replace the source/category without replacing playback.
        // Adopt the visible result set only when the chosen row is outside the
        // active zap list, then normalize indices for CH +/- navigation.
        var selected = entry
        val adoptsBrowseList = iptvChannels.none { it === entry }
        if (adoptsBrowseList) {
            iptvChannels = if (adoptVisibleBrowseList) {
                iptvChannelAdapter?.entriesSnapshot()
                    ?.mapIndexed { index, item -> item.apply { this.index = index } }
                    ?.toMutableList()
                    ?: mutableListOf(entry.apply { index = 0 })
            } else {
                // Copy: `entry` is still row N of the guide adapter's list, and
                // DiffUtil keys on `index` — rewriting it in place desyncs the
                // adapter from its own rows while the anchored page is in flight.
                mutableListOf(entry.copy(index = 0))
            }
            selected = iptvChannels.firstOrNull { it === entry || it.url == entry.url }
                ?: iptvChannels.first()
            iptvSeriesAudioKey = selected.seriesId?.let { seriesId ->
                "${selected.sourceId.orEmpty()}::$seriesId"
            }
        }

        // Update current flags
        iptvChannels.forEach { it.isCurrent = false }
        selected.isCurrent = true
        currentIptvIndex = iptvChannels.indexOfFirst { it === selected }.coerceAtLeast(0)
        iptvChannelAdapter?.notifyCurrentChanged(previousPlaying, selected)

        // Clear subtitle identity/results when changing channels from the guide.
        resetSubtitleState()

        // Persist on-demand metadata before playback so the progress row can
        // join Continue Watching even when this item was discovered in-player.
        beginIptvPlaybackAfterWatchRegistration(selected)

        // Update title
        titleView.text = selected.displayName

        // Channel-change feedback belongs to live zapping. VOD keeps the
        // standard player presentation.
        if (selected.isLive) showIptvZapBanner(selected) else hideIptvZapBanner()

        updateIptvGuideCurrentName()
        // Index moved — a previous episode may have (dis)appeared.
        updateIptvEpisodeControls()
    }

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

    private fun noteLiveChannelPlaying() {
        if (!isIptvMode) return
        val entry = iptvChannels.getOrNull(currentIptvIndex) ?: return
        if (!entry.isLive) return
        // Already counting down for this channel — a pause/resume must not
        // restart the settle window.
        if (lastLiveChannelArmedUrl == entry.url && lastLiveChannelRunnable != null) return

        lastLiveChannelRunnable?.let { iptvBrowseHandler.removeCallbacks(it) }
        lastLiveChannelArmedUrl = entry.url

        val runnable = Runnable {
            lastLiveChannelRunnable = null
            // Re-read: the user may have zapped on during the settle window,
            // and the channel that settled is the one that counts.
            val current = iptvChannels.getOrNull(currentIptvIndex)
            if (current == null || !current.isLive || current.url != entry.url) return@Runnable
            if (player?.isPlaying != true) return@Runnable
            // sourceId is backfilled from the launch-level id for entries that
            // carried none, so fall back to it here for the same reason.
            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "noteIptvLiveChannel",
                mapOf(
                    "url" to current.url,
                    "name" to current.name,
                    "sourceId" to (current.sourceId ?: iptvSourceId),
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
        iptvBrowseHandler.postDelayed(runnable, lastLiveChannelSettleMs)
    }

    private fun beginIptvPlaybackAfterWatchRegistration(entry: IptvChannelEntry) {
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
            val current = iptvChannels.getOrNull(currentIptvIndex)
            if (current !== entry && current?.url != entry.url) return
            beginIptvPlayback(entry)
        }

        // A detached Flutter engine can leave MethodChannel callbacks silent.
        // Metadata is best-effort in that case; playback must still proceed.
        iptvBrowseHandler.postDelayed({ continuePlayback() }, 2_000)
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

    /** True when LEFT/RIGHT should zap instead of seek: an IPTV session with
     *  a live channel playing, at least one other channel to go to, and the
     *  controls fully hidden — with the dock (or the sources badge) up,
     *  LEFT/RIGHT belong to whatever the user is looking at, and a surprise
     *  channel change under an open menu would read as a glitch. */
    private fun isLiveIptvZapContext(): Boolean =
        isIptvMode && !controlsMenuVisible &&
            (iptvChannels.size > 1 || iptvZapPagingActive) &&
            iptvChannels.getOrNull(currentIptvIndex)?.isLive == true

    private fun activateIptvZapUiContext() {
        if (iptvZapOwnsUiContext) return
        iptvUiContextToken++
        iptvBrowseToken++
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapOwnsUiContext = true
        iptvSourceId = iptvZapSourceId
        iptvSourceName = iptvZapSourceName
        iptvContentType = iptvZapContentType
        iptvSelectedCategory = iptvZapCategory
        iptvCategories = iptvZapCategories.toMutableList()
        iptvGuideSearch?.setText("")
        iptvBrowseChannels = iptvChannels.toMutableList()
        iptvGuideUsesZapWindow = true
        iptvChannelAdapter?.updateChannels(iptvChannels)
        refreshIptvBrowserChrome()
    }

    /** Fullscreen channel zap: previous/next channel in guide order,
     *  paging through the active category and crossing into the adjacent
     *  category at its ends. */
    private fun zapIptvChannel(delta: Int) {
        if (iptvChannels.getOrNull(currentIptvIndex)?.isLive != true) return
        // A physical channel key is a real tune, so the temporary search scope
        // is no longer eligible for restoration.
        commitIptvAllCategorySearch()
        activateIptvZapUiContext()
        if (!iptvZapPagingActive && iptvChannels.size < 2) return
        val from = currentIptvIndex.coerceIn(0, iptvChannels.lastIndex)
        val next = from + delta
        if (!iptvZapPagingActive) {
            val wrapped = (next + iptvChannels.size) % iptvChannels.size
            switchToIptvChannel(iptvChannels[wrapped])
            return
        }
        if (next in iptvChannels.indices) {
            switchToIptvChannel(iptvChannels[next])
            prefetchIptvZapPage(delta)
            prefetchAdjacentIptvCategory(delta)
            return
        }

        val firstAbsolute = iptvChannels.first().index
        val lastAbsolute = iptvChannels.last().index
        val hasAnotherPage = if (delta > 0) {
            lastAbsolute + 1 < iptvZapCategoryTotal
        } else {
            firstAbsolute > 0
        }
        if (hasAnotherPage) {
            queuePendingIptvZapInput(delta)
            prefetchIptvZapPage(delta)
            return
        }
        if (consumeCachedAdjacentIptvCategory(delta)) return
        requestAdjacentIptvCategory(delta)
    }

    private fun requestAdjacentIptvCategory(delta: Int, attempt: Int = 1) {
        if (iptvZapRequestInFlight) {
            queuePendingIptvZapInput(delta)
            return
        }
        val categories = iptvZapCategories.distinct()
        val currentCategory = iptvZapCategory
        if (currentCategory == null || categories.isEmpty()) {
            // An uncategorized/All-channels context has no category boundary;
            // wrap by paging the opposite end of the same result set.
            requestIptvZapPage(
                category = null,
                offset = 0,
                fromEnd = delta < 0,
            ) { channels, pageOffset, total, category, returnedCategories ->
                if (channels.isEmpty()) return@requestIptvZapPage
                installIptvZapWindow(
                    channels,
                    pageOffset,
                    total,
                    category,
                    returnedCategories,
                    preservePlayingChannel = false,
                )
                switchToIptvChannel(
                    if (delta > 0) iptvChannels.first() else iptvChannels.last(),
                    checkpointOutgoing = false,
                )
                prefetchIptvZapPage(delta)
                drainPendingIptvZapInputs()
            }
            return
        }

        if (attempt > categories.size) {
            iptvZapPendingInputs.clear()
            return
        }
        val targetCategory = adjacentIptvCategory(delta, attempt) ?: return
        requestIptvZapPage(
            category = targetCategory,
            offset = 0,
            fromEnd = delta < 0,
        ) { channels, pageOffset, total, category, returnedCategories ->
            if (channels.isEmpty()) {
                requestAdjacentIptvCategory(delta, attempt + 1)
                return@requestIptvZapPage
            }
            installIptvZapWindow(
                channels,
                pageOffset,
                total,
                category,
                returnedCategories,
                preservePlayingChannel = false,
            )
            switchToIptvChannel(
                if (delta > 0) iptvChannels.first() else iptvChannels.last(),
                checkpointOutgoing = false,
            )
            prefetchIptvZapPage(delta)
            prefetchAdjacentIptvCategory(delta)
            drainPendingIptvZapInputs()
        }
    }

    // ── IPTV zap banner ──────────────────────────────────────────────────
    // Channel-change feedback as a broadcast lower third: a scrim instead of
    // a card, so the picture stays whole. Channel identity anchors left, what
    // is on anchors right, a key-hint rail sits above the bottom edge, and the
    // elapsed rule runs the full width of the screen where it reads as part of
    // the broadcast rather than part of a dialog. Built in code and attached to
    // the content view on first use; EPG fields ride the same
    // ensureIptvChannelEpg flow the guide rows use, so a banner appearance also
    // warms the guide's data.

    private var iptvZapBanner: FrameLayout? = null
    private var iptvZapBannerLogo: android.widget.ImageView? = null
    private var iptvZapBannerLetter: TextView? = null
    private var iptvZapBannerNumber: TextView? = null
    private var iptvZapBannerName: TextView? = null
    private var iptvZapBannerMeta: TextView? = null
    private var iptvZapBannerNow: TextView? = null
    private var iptvZapBannerTimes: TextView? = null
    private var iptvZapBannerNext: TextView? = null
    private var iptvZapBannerProgress: ProgressBar? = null
    private var iptvZapBannerHintChannel: View? = null
    private var iptvZapBannerHintJump: View? = null
    private var iptvZapBannerBody: View? = null
    private var iptvZapBannerRail: View? = null

    /** The banner is riding on top of the controls dock as one merged panel,
     *  rather than floating over bare video after a zap. Docked, it has no
     *  auto-hide (it belongs to the dock's lifetime) and drops the key hints,
     *  whose keys move focus around the dock instead of zapping. */
    private var iptvZapBannerDocked = false
    private var iptvDockLayoutListenerAttached = false

    /** The channel the visible banner is describing. A paging window installed
     *  after the banner appeared changes this channel's position and the
     *  category total, so the banner needs a way back to its own entry. */
    private var iptvZapBannerEntry: IptvChannelEntry? = null
    private val iptvZapBannerHideToken = Any()
    private val iptvZapBannerTickToken = Any()

    private val iptvZapAccent = Color.parseColor("#00E5FF")

    // ── In-player guide style (see IptvGuideStyle.kt) ──────────────────────
    // Read once per launch, like recordingEngineEnabled: the Dart side owns
    // the pref; changing it applies to the next playback session. CLASSIC
    // (null tokens) keeps every legacy paint path verbatim.
    private val guideStyle: GuideStyle by lazy {
        GuideStyle.fromPref(
            com.debrify.app.profiles.ProfilePreferenceProjection.getString(
                this,
                "iptv_player_guide_style",
                "classic",
            ),
        )
    }
    private val guideTokens: GuideTokens? by lazy { GuideTokens.of(guideStyle) }

    /** Typefaces for the styled looks, loaded from the Flutter asset bundle.
     *  Failures are memoized too (containsKey, not getOrPut) so a missing
     *  asset is never retried per repaint — it just falls back to default. */
    private val guideTypefaces = HashMap<String, Typeface?>()

    private fun guideTypeface(file: String?): Typeface? {
        if (file == null) return null
        if (guideTypefaces.containsKey(file)) return guideTypefaces[file]
        val loaded = try {
            Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/$file")
        } catch (e: Exception) {
            android.util.Log.w("AndroidTvPlayer", "Guide style font missing: $file")
            null
        }
        guideTypefaces[file] = loaded
        return loaded
    }

    /** One truth for "is THIS channel being recorded right now" — the same
     *  combination the Record button paints from. The styled zap banner's
     *  REC tag reads it on show and on every 1s repaint. */
    private fun isRecordingCurrentIptvChannel(): Boolean =
        (recordingEngineEnabled && engineTaskIdForCurrentChannel() != null) ||
            iptvRecordingController.isActive

    private fun zapText(
        size: Float,
        alpha: Int,
        bold: Boolean = false,
        mono: Boolean = false,
    ) = TextView(this).apply {
        textSize = size
        setTextColor(Color.argb(alpha, 255, 255, 255))
        typeface = when {
            mono && bold -> Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            mono -> Typeface.MONOSPACE
            bold -> Typeface.DEFAULT_BOLD
            else -> Typeface.DEFAULT
        }
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
    }

    /** One rail entry: keycaps followed by what pressing them does. */
    private fun zapHint(caps: List<String>, label: String): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        caps.forEach { cap ->
            row.addView(
                zapText(10f, 190, mono = true).apply {
                    text = cap
                    setPadding(dp(5), 0, dp(5), dp(1))
                    background = GradientDrawable().apply {
                        cornerRadius = dp(3).toFloat()
                        setColor(Color.TRANSPARENT)
                        setStroke(dp(1), Color.argb(66, 255, 255, 255))
                    }
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { rightMargin = dp(4) },
            )
        }
        row.addView(
            zapText(10.5f, 102).apply {
                text = label
                isAllCaps = true
                letterSpacing = 0.1f
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { leftMargin = dp(3) },
        )
        return row
    }

    private fun ensureIptvZapBanner(): FrameLayout {
        iptvZapBanner?.let { return it }
        guideTokens?.let { return buildStyledIptvZapBanner(it) }

        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT

        val banner = FrameLayout(this).apply {
            visibility = View.GONE
            elevation = dp(8).toFloat()
        }

        // The scrim replaces the old card: it darkens what sits under the text
        // without drawing a box the eye has to read around.
        banner.addView(
            View(this).apply {
                background = GradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    intArrayOf(
                        Color.argb(0, 4, 6, 12),
                        Color.argb(184, 4, 6, 12),
                        Color.argb(240, 4, 6, 12),
                    ),
                )
            },
            FrameLayout.LayoutParams(match, match),
        )

        // ── channel identity (left) ──
        val logo = android.widget.ImageView(this).apply {
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            visibility = View.GONE
        }
        val letter = zapText(30f, 255, bold = true).apply { gravity = Gravity.CENTER }
        val tile = FrameLayout(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.argb(38, 255, 255, 255), Color.argb(13, 255, 255, 255)),
            ).apply {
                cornerRadius = dp(10).toFloat()
                setStroke(dp(1), Color.argb(41, 255, 255, 255))
            }
            setPadding(dp(6), dp(6), dp(6), dp(6))
        }
        tile.addView(logo, FrameLayout.LayoutParams(match, match))
        tile.addView(letter, FrameLayout.LayoutParams(match, match))

        val number = zapText(27f, 255, bold = true, mono = true).apply {
            setTextColor(iptvZapAccent)
        }
        val name = zapText(31f, 255, bold = true)
        val nameRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        nameRow.addView(
            number,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(12) },
        )
        nameRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))

        val liveTag = zapText(11.5f, 255, bold = true).apply {
            text = "● LIVE"
            setTextColor(Color.parseColor("#FF6470"))
            letterSpacing = 0.12f
        }
        val meta = zapText(11.5f, 143).apply {
            isAllCaps = true
            letterSpacing = 0.09f
        }
        val metaRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        metaRow.addView(
            liveTag,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(9) },
        )
        metaRow.addView(meta, LinearLayout.LayoutParams(0, wrap, 1f))

        val ident = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        ident.addView(nameRow, LinearLayout.LayoutParams(match, wrap))
        ident.addView(
            metaRow,
            LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(5) },
        )

        // ── what's on (right) ──
        val now = zapText(17f, 255, bold = true).apply {
            gravity = Gravity.END
            maxWidth = dp(380)
        }
        val times = zapText(11.5f, 153, mono = true).apply {
            gravity = Gravity.END
            maxWidth = dp(380)
        }
        val next = zapText(12.5f, 133).apply {
            gravity = Gravity.END
            maxWidth = dp(380)
        }
        val programme = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
        }
        programme.addView(now, LinearLayout.LayoutParams(wrap, wrap))
        programme.addView(
            times,
            LinearLayout.LayoutParams(wrap, wrap).apply { topMargin = dp(4) },
        )
        programme.addView(
            next,
            LinearLayout.LayoutParams(wrap, wrap).apply { topMargin = dp(4) },
        )

        // The identity column carries the weight, so a long channel name
        // ellipsizes before it can squeeze the programme out of the frame.
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        body.addView(tile, LinearLayout.LayoutParams(dp(68), dp(68)))
        body.addView(
            ident,
            LinearLayout.LayoutParams(0, wrap, 1f).apply { leftMargin = dp(20) },
        )
        body.addView(
            programme,
            LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(24) },
        )
        banner.addView(
            body,
            FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                leftMargin = dp(48)
                rightMargin = dp(48)
                bottomMargin = dp(58)
            },
        )

        // ── key hints ──
        // On its own line, so nothing it shares a row with can push it out when
        // a channel name runs long or the programme column empties.
        val hintChannel = zapHint(listOf("◀", "▶"), "Channel")
        val hintGuide = zapHint(listOf("▲"), "Guide")
        val hintJump = zapHint(listOf("HOLD ▲"), "Channel number")
        val rail = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        // Trailing margins rather than leading ones: when a hint is dropped
        // because its key does nothing on this channel, the one after it still
        // starts flush with the banner's 48 dp inset.
        rail.addView(
            hintChannel,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(20) },
        )
        rail.addView(hintGuide, LinearLayout.LayoutParams(wrap, wrap))
        rail.addView(View(this), LinearLayout.LayoutParams(0, dp(1), 1f))
        rail.addView(hintJump, LinearLayout.LayoutParams(wrap, wrap))
        banner.addView(
            rail,
            FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                leftMargin = dp(48)
                rightMargin = dp(48)
                bottomMargin = dp(16)
            },
        )

        // ── elapsed rule, screen edge to screen edge ──
        val bar = ProgressBar(
            this, null, android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 1000
            progressTintList =
                android.content.res.ColorStateList.valueOf(iptvZapAccent)
            progressBackgroundTintList = android.content.res.ColorStateList
                .valueOf(Color.argb(33, 255, 255, 255))
        }
        banner.addView(bar, FrameLayout.LayoutParams(match, dp(4), Gravity.BOTTOM))

        val root = findViewById<ViewGroup>(android.R.id.content)
        root.addView(
            banner,
            android.widget.FrameLayout.LayoutParams(match, dp(250)).apply {
                gravity = Gravity.BOTTOM
            },
        )

        iptvZapBanner = banner
        iptvZapBannerLogo = logo
        iptvZapBannerLetter = letter
        iptvZapBannerNumber = number
        iptvZapBannerName = name
        iptvZapBannerMeta = meta
        iptvZapBannerNow = now
        iptvZapBannerTimes = times
        iptvZapBannerNext = next
        iptvZapBannerProgress = bar
        iptvZapBannerHintChannel = hintChannel
        iptvZapBannerHintJump = hintJump
        iptvZapBannerBody = body
        iptvZapBannerRail = rail
        return banner
    }

    // ── Styled zap banner (GLASS / EDITION / CONSOLE) ──────────────────────
    // Its own builder + painters, per the style contract: the classic tree
    // above never changes, and the styled tree owns every color, typeface,
    // and drawable it paints. The shared BEHAVIORAL fns (show/hide, ticker,
    // position text, hint gating) work on both trees through the same field
    // refs.

    private var iptvZapStyledScrim: View? = null
    private var iptvZapStyledCard: LinearLayout? = null
    private var iptvZapGlassCardWidth = 0
    private var iptvZapStyledRule: View? = null
    private var iptvZapStyledLive: TextView? = null
    private var iptvZapStyledRec: TextView? = null
    private var iptvZapStyledEnd: TextView? = null
    private var iptvZapStyledMeterRow: LinearLayout? = null

    private fun styledZapText(
        t: GuideTokens,
        size: Float,
        color: Int,
        font: String? = null,
        bold: Boolean = false,
        italic: Boolean = false,
    ) = TextView(this).apply {
        textSize = size
        setTextColor(color)
        val base = guideTypeface(font)
        typeface = when {
            base != null && italic -> Typeface.create(base, Typeface.ITALIC)
            base != null && bold -> Typeface.create(base, Typeface.BOLD)
            base != null -> base
            bold && italic -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD_ITALIC)
            bold -> Typeface.DEFAULT_BOLD
            italic -> Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
            else -> Typeface.DEFAULT
        }
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
    }

    /** One styled rail entry: keycaps + label, token colors only. */
    private fun styledZapHint(t: GuideTokens, caps: List<String>, label: String): LinearLayout {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        caps.forEach { cap ->
            row.addView(
                styledZapText(t, 10f, t.fgMid, font = t.monoFont).apply {
                    text = cap
                    setPadding(dp(5), 0, dp(5), dp(1))
                    background = GradientDrawable().apply {
                        cornerRadius = dp(3).toFloat()
                        setColor(Color.TRANSPARENT)
                        setStroke(dp(1), t.hairline2)
                    }
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { rightMargin = dp(4) },
            )
        }
        row.addView(
            styledZapText(t, 10.5f, t.fgFaint).apply {
                text = label
                isAllCaps = true
                letterSpacing = 0.1f
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { leftMargin = dp(3) },
        )
        return row
    }

    private fun buildStyledIptvZapBanner(t: GuideTokens): FrameLayout {
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
        val style = guideStyle

        val banner = FrameLayout(this).apply {
            visibility = View.GONE
            elevation = dp(8).toFloat()
        }

        // Scrim: glass keeps the video visible; edition/console fade to their
        // own ink/black. Hidden entirely while docked (the dock is the panel).
        val scrim = View(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                when (style) {
                    GuideStyle.GLASS -> intArrayOf(0x000A0C12, 0x730A0C12)
                    GuideStyle.EDITION -> intArrayOf(0x000D0B09, t.bg)
                    else -> intArrayOf(0x00050505, t.bg)
                },
            )
        }
        banner.addView(scrim, FrameLayout.LayoutParams(match, match))

        // Shared-role views. The behavioral painters write text into these no
        // matter which styled tree they sit in (or, for the logo pair in
        // edition/console, don't sit in at all).
        val logo = android.widget.ImageView(this).apply {
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            visibility = View.GONE
        }
        val letter = styledZapText(t, 24f, t.fg, bold = true).apply {
            gravity = Gravity.CENTER
        }
        val number: TextView
        val name: TextView
        val now: TextView
        val times: TextView
        val next: TextView
        val meta: TextView
        val liveTag: TextView
        val recTag = styledZapText(t, 10.5f, t.rec, bold = true).apply {
            text = "● REC"
            letterSpacing = 0.12f
            visibility = View.GONE
        }

        when (style) {
            GuideStyle.EDITION -> {
                // Editorial: the PROGRAMME is the headline, the channel is
                // the byline. Kicker caps in the italic serif above it.
                number = styledZapText(t, 11f, t.fgDim, font = t.captionFont, italic = true)
                liveTag = styledZapText(t, 11f, t.live, font = t.captionFont, italic = true).apply {
                    text = "· LIVE"
                }
                meta = styledZapText(t, 11f, t.fgFaint, font = t.captionFont, italic = true).apply {
                    isAllCaps = true
                    letterSpacing = 0.09f
                }
                now = styledZapText(t, 26f, t.fg, font = t.headlineFont)
                name = styledZapText(t, 12.5f, t.fgDim)
                times = styledZapText(t, 12.5f, t.fgDim)
                next = styledZapText(t, 12f, t.fgFaint, font = t.captionFont, italic = true)
            }
            GuideStyle.CONSOLE -> {
                number = styledZapText(t, 18f, t.accent, font = t.monoFont, bold = true)
                name = styledZapText(t, 19f, t.fg, font = t.nameFont, bold = true)
                liveTag = styledZapText(t, 10.5f, t.live, font = t.monoFont, bold = true).apply {
                    text = "● LIVE"
                    letterSpacing = 0.12f
                }
                meta = styledZapText(t, 10.5f, t.fgFaint, font = t.monoFont).apply {
                    isAllCaps = true
                    letterSpacing = 0.09f
                }
                now = styledZapText(t, 15f, t.fg, bold = true)
                times = styledZapText(t, 11f, t.fgDim, font = t.monoFont)
                next = styledZapText(t, 10.5f, t.fgFaint, font = t.monoFont).apply {
                    isAllCaps = true
                }
            }
            else -> { // GLASS
                number = styledZapText(t, 20f, t.fg, bold = true)
                name = styledZapText(t, 22f, t.fg, bold = true)
                liveTag = styledZapText(t, 11f, t.live, bold = true).apply {
                    text = "● LIVE"
                    letterSpacing = 0.12f
                }
                meta = styledZapText(t, 11f, t.fgDim).apply {
                    isAllCaps = true
                    letterSpacing = 0.09f
                }
                now = styledZapText(t, 15f, t.fgMid, bold = true)
                times = styledZapText(t, 11.5f, t.fgDim)
                next = styledZapText(t, 11.5f, t.fgFaint)
            }
        }

        // Elapsed rule. Glass/edition use a plain bar; console pairs it with
        // the programme's end time, instrument style.
        val bar = ProgressBar(
            this, null, android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 1000
            progressTintList = android.content.res.ColorStateList.valueOf(
                if (style == GuideStyle.EDITION) t.fg else t.accent,
            )
            progressBackgroundTintList =
                android.content.res.ColorStateList.valueOf(t.hairline2)
        }
        val endTime = styledZapText(t, 10.5f, t.fgDim, font = t.monoFont).apply {
            visibility = View.GONE
        }

        val hintChannel = styledZapHint(t, listOf("◀", "▶"), "Channel")
        val hintGuide = styledZapHint(t, listOf("▲"), "Guide")
        val hintJump = styledZapHint(t, listOf("HOLD ▲"), "Channel number")
        val rail = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        rail.addView(
            hintChannel,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(20) },
        )
        rail.addView(hintGuide, LinearLayout.LayoutParams(wrap, wrap))
        rail.addView(View(this), LinearLayout.LayoutParams(0, dp(1), 1f))
        rail.addView(hintJump, LinearLayout.LayoutParams(wrap, wrap))

        val body: LinearLayout
        when (style) {
            GuideStyle.GLASS -> {
                // Island card, bottom-left, like a broadcast bug.
                val tile = FrameLayout(this).apply {
                    background = t.tileDrawable(dp(14).toFloat(), dp(1))
                    setPadding(dp(6), dp(6), dp(6), dp(6))
                }
                tile.addView(logo, FrameLayout.LayoutParams(match, match))
                tile.addView(letter, FrameLayout.LayoutParams(match, match))

                val nameRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                nameRow.addView(
                    number,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(10) },
                )
                nameRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))
                nameRow.addView(
                    liveTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(12) },
                )
                nameRow.addView(
                    recTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(10) },
                )

                val ident = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                }
                ident.addView(nameRow, LinearLayout.LayoutParams(match, wrap))
                ident.addView(
                    now,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(6) },
                )
                ident.addView(
                    times,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(3) },
                )
                ident.addView(
                    meta,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(3) },
                )
                ident.addView(
                    next,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(3) },
                )

                val contentRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(20), dp(18), dp(20), dp(14))
                }
                contentRow.addView(tile, LinearLayout.LayoutParams(dp(60), dp(60)))
                contentRow.addView(
                    ident,
                    LinearLayout.LayoutParams(0, wrap, 1f).apply { leftMargin = dp(16) },
                )

                val card = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    background = t.panelDrawable(dp(22).toFloat(), dp(1))
                    clipToOutline = true
                }
                card.addView(contentRow, LinearLayout.LayoutParams(match, wrap))
                card.addView(
                    bar,
                    LinearLayout.LayoutParams(match, dp(3)).apply {
                        leftMargin = dp(20)
                        rightMargin = dp(20)
                        bottomMargin = dp(16)
                    },
                )

                val cardWidth = minOf(
                    dp(620),
                    resources.displayMetrics.widthPixels - dp(56),
                ).coerceAtLeast(dp(220))
                iptvZapGlassCardWidth = cardWidth
                banner.addView(
                    card,
                    FrameLayout.LayoutParams(cardWidth, wrap, Gravity.BOTTOM or Gravity.START)
                        .apply {
                            leftMargin = dp(28)
                            bottomMargin = dp(58)
                        },
                )
                iptvZapStyledCard = card
                body = card
            }
            GuideStyle.EDITION -> {
                val rule = View(this).apply { setBackgroundColor(t.hairline2) }
                val kickerRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                kickerRow.addView(
                    number,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(6) },
                )
                kickerRow.addView(
                    liveTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(6) },
                )
                kickerRow.addView(
                    recTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(6) },
                )
                kickerRow.addView(meta, LinearLayout.LayoutParams(0, wrap, 1f))

                val bylineRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                bylineRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))
                bylineRow.addView(
                    times,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(14) },
                )

                val column = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                }
                column.addView(rule, LinearLayout.LayoutParams(match, dp(1)))
                column.addView(
                    kickerRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(12) },
                )
                column.addView(
                    now,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(7) },
                )
                column.addView(
                    bylineRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(6) },
                )
                column.addView(
                    next,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(4) },
                )

                banner.addView(
                    column,
                    FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                        leftMargin = dp(48)
                        rightMargin = dp(48)
                        bottomMargin = dp(58)
                    },
                )
                banner.addView(bar, FrameLayout.LayoutParams(match, dp(2), Gravity.BOTTOM))
                iptvZapStyledRule = rule
                body = column
            }
            else -> { // CONSOLE
                val nameRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                nameRow.addView(
                    number,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(12) },
                )
                nameRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))
                nameRow.addView(
                    liveTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(12) },
                )
                nameRow.addView(
                    recTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(10) },
                )

                val nowLabel = styledZapText(t, 10f, t.fgFaint, font = t.monoFont, bold = true)
                    .apply {
                        text = "NOW"
                        letterSpacing = 0.2f
                    }
                val nowRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                nowRow.addView(
                    nowLabel,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = dp(10) },
                )
                nowRow.addView(now, LinearLayout.LayoutParams(0, wrap, 1f))
                nowRow.addView(
                    times,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(14) },
                )

                val content = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                }
                content.addView(nameRow, LinearLayout.LayoutParams(match, wrap))
                content.addView(
                    nowRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(7) },
                )
                content.addView(
                    meta,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(4) },
                )
                content.addView(
                    next,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(4) },
                )

                // The amber rule rides the content block as a left rule.
                val ruled = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                }
                val rule = View(this).apply { setBackgroundColor(t.accent) }
                ruled.addView(rule, LinearLayout.LayoutParams(dp(3), match))
                ruled.addView(
                    content,
                    LinearLayout.LayoutParams(0, wrap, 1f).apply { leftMargin = dp(16) },
                )

                val meterRow = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                meterRow.addView(bar, LinearLayout.LayoutParams(0, dp(5), 1f))
                meterRow.addView(
                    endTime,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = dp(10) },
                )

                val column = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                }
                column.addView(ruled, LinearLayout.LayoutParams(match, wrap))
                column.addView(
                    meterRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = dp(12) },
                )

                banner.addView(
                    column,
                    FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                        leftMargin = dp(48)
                        rightMargin = dp(48)
                        bottomMargin = dp(58)
                    },
                )
                iptvZapStyledRule = rule
                iptvZapStyledMeterRow = meterRow
                body = column
            }
        }

        banner.addView(
            rail,
            FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                leftMargin = dp(48)
                rightMargin = dp(48)
                bottomMargin = dp(16)
            },
        )

        val root = findViewById<ViewGroup>(android.R.id.content)
        root.addView(
            banner,
            FrameLayout.LayoutParams(match, dp(250)).apply {
                gravity = Gravity.BOTTOM
            },
        )

        iptvZapBanner = banner
        iptvZapBannerLogo = logo
        iptvZapBannerLetter = letter
        iptvZapBannerNumber = number
        iptvZapBannerName = name
        iptvZapBannerMeta = meta
        iptvZapBannerNow = now
        iptvZapBannerTimes = times
        iptvZapBannerNext = next
        iptvZapBannerProgress = bar
        iptvZapBannerHintChannel = hintChannel
        iptvZapBannerHintJump = hintJump
        iptvZapBannerBody = body
        iptvZapBannerRail = rail
        iptvZapStyledScrim = scrim
        iptvZapStyledLive = liveTag
        iptvZapStyledRec = recTag
        iptvZapStyledEnd = endTime
        return banner
    }

    /**
     * Present [entry]'s channel panel.
     *
     * [docked] defaults to whether the controls dock is open, so every caller
     * lands in the right home without knowing about the modes: a zap with the
     * dock up repaints the dock's panel, and the same zap over bare video
     * floats the banner. Only the guide takes the screen outright.
     */
    private fun showIptvZapBanner(
        entry: IptvChannelEntry,
        docked: Boolean = controlsMenuVisible,
    ) {
        // The banner is the topmost child of the content view and spans the
        // full width, so it would simply cover the guide; a zap from inside
        // the guide updates the guide's own header instead.
        if (iptvGuideVisible) return
        val banner = ensureIptvZapBanner()
        // Already on this surface: repaint in place. Re-running the entrance
        // would flash the panel on every keypress that re-arms the dock.
        val alreadyUp = banner.visibility == View.VISIBLE &&
            iptvZapBannerDocked == docked
        // Is this the same channel the panel is already describing? The dock
        // re-arms itself on every play/pause and DPAD press, and repainting
        // identity each time would re-run the logo's clear-and-fetch — a
        // visible flicker on every keypress. Position still refreshes: a
        // paging window can renumber the channel under a panel that stays up.
        val previous = iptvZapBannerEntry
        val sameChannel = previous != null &&
            previous.url == entry.url && previous.name == entry.name
        iptvZapBannerEntry = entry
        iptvZapBannerDocked = docked
        applyIptvZapBannerMode(docked)
        if (sameChannel) {
            paintIptvZapBannerPosition(entry)
        } else {
            paintIptvZapBannerIdentity(entry)
        }
        paintIptvZapBannerEpg(entry) // whatever is already known paints now
        // The same lazy fetch the guide rows use — a fresh answer repaints
        // the banner via the isCurrent hook in ensureIptvChannelEpg.
        ensureIptvChannelEpg(entry)

        if (!alreadyUp) {
            banner.animate().cancel()
            banner.visibility = View.VISIBLE
            banner.alpha = 0f
            if (docked) {
                // Ride the dock's entrance. It rises from +30 over 300ms, and
                // a panel that stayed put would visibly detach from the thing
                // it is supposed to be part of.
                banner.translationY = 30f
                banner.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(300)
                    .setInterpolator(android.view.animation.DecelerateInterpolator(1.5f))
                    .start()
            } else {
                banner.translationY = 0f
                banner.animate().alpha(1f).setDuration(160).start()
            }
        }
        progressHandler.removeCallbacksAndMessages(iptvZapBannerHideToken)
        // Docked, the panel belongs to the dock's lifetime — hideControlsMenu
        // takes it down. Only the floating banner times itself out.
        if (!docked) {
            progressHandler.postAtTime(
                { hideIptvZapBanner() },
                iptvZapBannerHideToken,
                android.os.SystemClock.uptimeMillis() + 4500,
            )
        }
        // Only when the panel is (re)entering: the tick chain re-posts itself
        // while visible, and re-scheduling on every repeat call would push the
        // next tick out by another second each time, so it would never fire.
        if (!alreadyUp) scheduleIptvZapBannerTick()
    }

    /**
     * Sit the panel flush on top of the controls dock, or back over bare
     * video.
     *
     * The dock's height is only known once it has been laid out, so a first
     * show re-applies on the next layout pass rather than stacking the panel
     * at the wrong offset.
     */
    private fun applyIptvZapBannerMode(docked: Boolean) {
        guideTokens?.let { applyStyledZapBannerMode(docked, it); return }
        val banner = iptvZapBanner ?: return
        val dock = controlsOverlay
        val dockHeight = if (docked) (dock?.height ?: 0) else 0
        (banner.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            if (lp.bottomMargin != dockHeight) {
                lp.bottomMargin = dockHeight
                banner.layoutParams = lp
            }
        }
        // The hints teach zapping; docked, those keys walk the dock's buttons.
        iptvZapBannerRail?.visibility = if (docked) View.GONE else View.VISIBLE
        // With the rail gone there is nothing between the text and the rule
        // to leave room for.
        (iptvZapBannerBody?.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            val margin = if (docked) dp(16) else dp(58)
            if (lp.bottomMargin != margin) {
                lp.bottomMargin = margin
                iptvZapBannerBody?.layoutParams = lp
            }
        }
        // The dock's height is 0 until it has been laid out, and it changes
        // with its own contents (the button row varies per channel). One
        // listener keeps the panel sitting on it whatever it does.
        if (docked && dock != null && !iptvDockLayoutListenerAttached) {
            iptvDockLayoutListenerAttached = true
            dock.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                if (iptvZapBannerDocked) applyIptvZapBannerMode(true)
            }
        }
    }

    /**
     * Repaint the now/next block once a second while the banner is up.
     *
     * The elapsed rule and the "N min left" tail were computed once at paint
     * time, so both sat frozen for the whole time the banner was on screen —
     * a progress bar that visibly does not progress.
     */
    private fun scheduleIptvZapBannerTick() {
        progressHandler.removeCallbacksAndMessages(iptvZapBannerTickToken)
        progressHandler.postAtTime(
            {
                val entry = iptvZapBannerEntry
                if (entry != null && iptvZapBanner?.visibility == View.VISIBLE) {
                    paintIptvZapBannerEpg(entry)
                    scheduleIptvZapBannerTick()
                }
            },
            iptvZapBannerTickToken,
            android.os.SystemClock.uptimeMillis() + 1000,
        )
    }

    private fun hideIptvZapBanner() {
        val banner = iptvZapBanner ?: return
        progressHandler.removeCallbacksAndMessages(iptvZapBannerTickToken)
        iptvZapBannerEntry = null
        iptvZapBannerDocked = false
        banner.animate().cancel()
        banner.animate().alpha(0f).setDuration(180).withEndAction {
            banner.visibility = View.GONE
        }.start()
    }

    /** The styled counterpart of [applyIptvZapBannerMode]: same margin/dock
     *  bookkeeping, plus the styled chrome that changes between homes (scrim
     *  off while docked; the glass card hands its surface to the dock). */
    private fun applyStyledZapBannerMode(docked: Boolean, t: GuideTokens) {
        val banner = iptvZapBanner ?: return
        val dock = controlsOverlay
        val dockHeight = if (docked) (dock?.height ?: 0) else 0
        (banner.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            if (lp.bottomMargin != dockHeight) {
                lp.bottomMargin = dockHeight
                banner.layoutParams = lp
            }
        }
        iptvZapStyledScrim?.visibility = if (docked) View.GONE else View.VISIBLE
        iptvZapBannerRail?.visibility = if (docked) View.GONE else View.VISIBLE
        // Edition's top hairline reads wrong pressed against the dock edge.
        if (guideStyle == GuideStyle.EDITION) {
            iptvZapStyledRule?.visibility = if (docked) View.INVISIBLE else View.VISIBLE
        }
        if (guideStyle == GuideStyle.GLASS) {
            // Docked, the island hands its surface AND its island geometry to
            // the dock: full-width flush band, full-width progress pill.
            val card = iptvZapStyledCard
            card?.background =
                if (docked) null else t.panelDrawable(dp(22).toFloat(), dp(1))
            (card?.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                val width = if (docked) {
                    ViewGroup.LayoutParams.MATCH_PARENT
                } else {
                    iptvZapGlassCardWidth
                }
                val left = if (docked) dp(20) else dp(28)
                val right = if (docked) dp(20) else 0
                if (lp.width != width || lp.leftMargin != left ||
                    lp.rightMargin != right
                ) {
                    lp.width = width
                    lp.leftMargin = left
                    lp.rightMargin = right
                    card.layoutParams = lp
                }
            }
            (iptvZapBannerProgress?.layoutParams as? LinearLayout.LayoutParams)
                ?.let { lp ->
                    val side = if (docked) 0 else dp(20)
                    val bottom = if (docked) dp(4) else dp(16)
                    if (lp.leftMargin != side || lp.bottomMargin != bottom) {
                        lp.leftMargin = side
                        lp.rightMargin = side
                        lp.bottomMargin = bottom
                        iptvZapBannerProgress?.layoutParams = lp
                    }
                }
        }
        (iptvZapBannerBody?.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            val margin = if (docked) dp(16) else dp(58)
            if (lp.bottomMargin != margin) {
                lp.bottomMargin = margin
                iptvZapBannerBody?.layoutParams = lp
            }
        }
        if (docked && dock != null && !iptvDockLayoutListenerAttached) {
            iptvDockLayoutListenerAttached = true
            dock.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                if (iptvZapBannerDocked) applyIptvZapBannerMode(true)
            }
        }
    }

    /** Logo, channel number and name — the parts that only change on a zap. */
    private fun paintIptvZapBannerIdentity(entry: IptvChannelEntry) {
        guideTokens?.let { paintStyledZapBannerIdentity(entry, it); return }
        val letter = iptvZapBannerLetter ?: return
        val logo = iptvZapBannerLogo ?: return

        val firstLetter = entry.name.firstOrNull()?.uppercase() ?: "?"
        // Drop the outgoing channel's image before anything else. Without
        // this, a zap between two channels that both have logos leaves the
        // PREVIOUS logo sitting beside the new channel's name for as long as
        // the new one takes to fetch — the banner showing two channels at
        // once. The guide adapter clears for the same reason on rebind.
        com.bumptech.glide.Glide.with(this).clear(logo)
        logo.setImageDrawable(null)
        if (entry.logoUrl.isNullOrEmpty()) {
            logo.visibility = View.GONE
            letter.text = firstLetter
            letter.visibility = View.VISIBLE
        } else {
            // The letter holds the tile until the image actually lands, so the
            // cleared slot is never just an empty box.
            letter.text = firstLetter
            letter.visibility = View.VISIBLE
            logo.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(this)
                .load(entry.logoUrl)
                .centerInside()
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?,
                        model: Any?,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                        isFirstResource: Boolean
                    ): Boolean {
                        logo.visibility = View.GONE
                        letter.text = firstLetter
                        letter.visibility = View.VISIBLE
                        return true
                    }
                    override fun onResourceReady(
                        resource: android.graphics.drawable.Drawable,
                        model: Any,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                        dataSource: com.bumptech.glide.load.DataSource,
                        isFirstResource: Boolean
                    ): Boolean {
                        // The image is here — retire the placeholder letter
                        // that was holding the tile.
                        letter.visibility = View.GONE
                        return false
                    }
                })
                .into(logo)
        }

        iptvZapBannerNumber?.text =
            (entry.channelNumber ?: (entry.index + 1)).toString()
        // The RAW name: the number already has its own accent slot beside
        // this, and displayName carries a "CH n" prefix of its own — pairing
        // the two printed the number twice ("7  CH 7  Sky Sports"). The guide
        // rows pair the same number view with entry.name for this reason.
        iptvZapBannerName?.text = entry.name
        paintIptvZapBannerPosition(entry)
    }

    /** Category, position within it, and which key hints are honest here. */
    private fun paintIptvZapBannerPosition(entry: IptvChannelEntry) {
        val total = if (iptvZapPagingActive && iptvZapCategoryTotal > 0) {
            iptvZapCategoryTotal
        } else {
            iptvChannels.size
        }
        val locale = java.util.Locale.getDefault()
        val parts = buildList {
            entry.group?.trim()?.takeIf { it.isNotEmpty() }?.let { add(it) }
            if (total > 0) {
                add(
                    String.format(locale, "%,d", entry.index + 1) +
                        " of " + String.format(locale, "%,d", total)
                )
            }
        }
        iptvZapBannerMeta?.text =
            if (parts.isEmpty()) "" else "·  " + parts.joinToString("  ·  ")

        // Only teach a key that actually does something on this channel: with a
        // single channel and no paging there is nothing to zap to, and the jump
        // dialog refuses a favourites source outright.
        val canZap = iptvChannels.size > 1 || iptvZapPagingActive
        iptvZapBannerHintChannel?.visibility =
            if (canZap) View.VISIBLE else View.GONE
        val activeSource = iptvSources.firstOrNull { it.id == iptvZapSourceId }
        iptvZapBannerHintJump?.visibility =
            if (canZap && activeSource?.isFavorites != true) View.VISIBLE else View.GONE
    }

    /** The styled identity paint: same Glide dance for the glass tile, no
     *  logo at all for edition/console (the number IS the identity there),
     *  per-style number formatting. Ends on the shared position painter. */
    private fun paintStyledZapBannerIdentity(entry: IptvChannelEntry, t: GuideTokens) {
        if (guideStyle == GuideStyle.GLASS) {
            val letter = iptvZapBannerLetter
            val logo = iptvZapBannerLogo
            if (letter != null && logo != null) {
                val firstLetter = entry.name.firstOrNull()?.uppercase() ?: "?"
                com.bumptech.glide.Glide.with(this).clear(logo)
                logo.setImageDrawable(null)
                if (entry.logoUrl.isNullOrEmpty()) {
                    logo.visibility = View.GONE
                    letter.text = firstLetter
                    letter.visibility = View.VISIBLE
                } else {
                    letter.text = firstLetter
                    letter.visibility = View.VISIBLE
                    logo.visibility = View.VISIBLE
                    com.bumptech.glide.Glide.with(this)
                        .load(entry.logoUrl)
                        .centerInside()
                        .listener(object :
                            com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                            override fun onLoadFailed(
                                e: com.bumptech.glide.load.engine.GlideException?,
                                model: Any?,
                                target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                                isFirstResource: Boolean,
                            ): Boolean {
                                logo.visibility = View.GONE
                                letter.text = firstLetter
                                letter.visibility = View.VISIBLE
                                return true
                            }

                            override fun onResourceReady(
                                resource: android.graphics.drawable.Drawable,
                                model: Any,
                                target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                                dataSource: com.bumptech.glide.load.DataSource,
                                isFirstResource: Boolean,
                            ): Boolean {
                                letter.visibility = View.GONE
                                return false
                            }
                        })
                        .into(logo)
                }
            }
        }

        val displayNumber = (entry.channelNumber ?: (entry.index + 1)).toString()
        iptvZapBannerNumber?.text = when (guideStyle) {
            GuideStyle.CONSOLE -> displayNumber.padStart(3, '0')
            GuideStyle.EDITION -> "CH $displayNumber"
            else -> displayNumber
        }
        iptvZapBannerName?.text = entry.name
        paintIptvZapBannerPosition(entry)
    }

    /** The styled now/next paint. Owns its colors outright — the classic
     *  painter resets typefaces/colors per call and must never run on a
     *  styled tree. Also the REC tag's only writer (show + 1s tick). */
    private fun paintStyledZapBannerEpg(entry: IptvChannelEntry, t: GuideTokens) {
        val nowView = iptvZapBannerNow ?: return
        val timesView = iptvZapBannerTimes ?: return
        val nextView = iptvZapBannerNext ?: return
        val bar = iptvZapBannerProgress ?: return

        val nowTitle = entry.epgNowTitle
        if (guideStyle == GuideStyle.EDITION) {
            // Editorial hierarchy: the headline slot carries the programme;
            // a guideless channel promotes its name there and the byline
            // names the silence.
            if (nowTitle != null) {
                nowView.text = nowTitle
                iptvZapBannerName?.text = entry.name
                iptvZapBannerName?.setTextColor(t.fgDim)
            } else {
                nowView.text = entry.name
                iptvZapBannerName?.text =
                    if (entry.epgLoading) "Loading guide…" else "No guide data"
                iptvZapBannerName?.setTextColor(t.fgFaint)
            }
        } else {
            if (nowTitle != null) {
                nowView.text = nowTitle
                nowView.setTextColor(
                    if (guideStyle == GuideStyle.CONSOLE) t.fg else t.fgMid,
                )
            } else {
                nowView.text =
                    if (entry.epgLoading) "Loading guide…" else "No guide data"
                nowView.setTextColor(t.fgFaint)
            }
        }

        val start = entry.epgNowStartMs
        val stop = entry.epgNowStopMs
        val runtime = stop - start
        if (nowTitle != null && runtime > 0) {
            val nowMs = System.currentTimeMillis()
            val remaining = stop - nowMs
            val tail =
                if (remaining > 60_000L) "  ·  ${formatIptvRemaining(remaining)} left"
                else ""
            timesView.text =
                "${formatEpgTime(start)} – ${formatEpgTime(stop)}$tail"
            timesView.visibility = View.VISIBLE
            val elapsed = (nowMs - start).coerceIn(0L, runtime)
            bar.progress = ((elapsed.toDouble() / runtime) * 1000).toInt()
            iptvZapStyledEnd?.let {
                it.text = formatEpgTime(stop)
                it.visibility = View.VISIBLE
            }
        } else {
            timesView.visibility = View.GONE
            bar.progress = 0
            iptvZapStyledEnd?.visibility = View.GONE
        }

        val nextTitle = entry.epgNextTitle
        if (nowTitle != null && nextTitle != null) {
            val at =
                if (entry.epgNextStartMs > 0) "${formatEpgTime(entry.epgNextStartMs)}  ·  "
                else ""
            nextView.text = "Next  $at$nextTitle"
            nextView.visibility = View.VISIBLE
        } else {
            nextView.visibility = View.GONE
        }

        iptvZapStyledRec?.visibility =
            if (isRecordingCurrentIptvChannel()) View.VISIBLE else View.GONE
    }

    /** Paint the banner's now/next lines from [entry]'s EPG fields. */
    private fun paintIptvZapBannerEpg(entry: IptvChannelEntry) {
        guideTokens?.let { paintStyledZapBannerEpg(entry, it); return }
        val nowView = iptvZapBannerNow ?: return
        val timesView = iptvZapBannerTimes ?: return
        val nextView = iptvZapBannerNext ?: return
        val bar = iptvZapBannerProgress ?: return

        val nowTitle = entry.epgNowTitle
        if (nowTitle != null) {
            nowView.text = nowTitle
            nowView.setTextColor(Color.WHITE)
            nowView.typeface = Typeface.DEFAULT_BOLD
        } else {
            // A channel with no guide still deserves a whole banner — say which
            // of the two silences this is rather than leaving a gap.
            nowView.text =
                if (entry.epgLoading) "Loading guide…" else "No guide data"
            nowView.setTextColor(Color.argb(107, 255, 255, 255))
            nowView.typeface = Typeface.DEFAULT
        }

        val start = entry.epgNowStartMs
        val stop = entry.epgNowStopMs
        val runtime = stop - start
        if (nowTitle != null && runtime > 0) {
            val nowMs = System.currentTimeMillis()
            val remaining = stop - nowMs
            val tail =
                if (remaining > 60_000L) "  ·  ${formatIptvRemaining(remaining)} left"
                else ""
            timesView.text =
                "${formatEpgTime(start)} – ${formatEpgTime(stop)}$tail"
            timesView.visibility = View.VISIBLE
            val elapsed = (nowMs - start).coerceIn(0L, runtime)
            bar.progress = ((elapsed.toDouble() / runtime) * 1000).toInt()
        } else {
            timesView.visibility = View.GONE
            // The rule stays — an empty track still reads as the edge of the
            // broadcast, where hiding it would make the banner look truncated.
            bar.progress = 0
        }

        val nextTitle = entry.epgNextTitle
        if (nowTitle != null && nextTitle != null) {
            val at =
                if (entry.epgNextStartMs > 0) "${formatEpgTime(entry.epgNextStartMs)}  ·  "
                else ""
            nextView.text = "Next  $at$nextTitle"
            nextView.visibility = View.VISIBLE
        } else {
            nextView.visibility = View.GONE
        }
    }

    /** "36 min" / "1 hr 12 min" — what is left of a programme's runtime. */
    private fun formatIptvRemaining(ms: Long): String {
        val minutes = (ms / 60_000L).coerceAtLeast(0L)
        if (minutes < 60) return "$minutes min"
        val hours = minutes / 60
        val rest = minutes % 60
        return if (rest == 0L) "$hours hr" else "$hours hr $rest min"
    }

    /** A window install or merge renumbers this channel and can change the
     *  category total. Repaint a banner that is still on screen instead of
     *  leaving it showing whatever the launcher's list implied. */
    private fun refreshIptvZapBannerPosition() {
        val banner = iptvZapBanner ?: return
        if (banner.visibility != View.VISIBLE) return
        val shown = iptvZapBannerEntry ?: return
        val playing = iptvChannels.getOrNull(currentIptvIndex)
        val entry = if (
            playing != null && playing.url == shown.url && playing.name == shown.name
        ) playing else shown
        if (entry !== shown) adoptIptvEpg(from = shown, to = entry)
        iptvZapBannerEntry = entry
        paintIptvZapBannerPosition(entry)
        paintIptvZapBannerEpg(entry)
    }

    /**
     * Hand known now/next data to a replacement entry for the same channel.
     *
     * A window install swaps in fresh [IptvChannelEntry] objects, and the new
     * one carries no EPG. Without this, repainting from it flips a banner that
     * is already showing the programme back to "No guide data" until the
     * refetch lands — a visible regression on the very first tune, where the
     * bootstrap window always arrives a moment after the banner. Only real data
     * moves across: adopting a blank answer would suppress [to]'s own fetch.
     */
    private fun adoptIptvEpg(from: IptvChannelEntry, to: IptvChannelEntry) {
        if (from.epgNowTitle == null || to.epgLoaded) return
        to.epgNowTitle = from.epgNowTitle
        to.epgNowStartMs = from.epgNowStartMs
        to.epgNowStopMs = from.epgNowStopMs
        to.epgNextTitle = from.epgNextTitle
        to.epgNextStartMs = from.epgNextStartMs
        // Claim "loaded" only when nothing is already on its way; an in-flight
        // fetch will overwrite these with its own, fresher answer.
        if (!to.epgLoading) to.epgLoaded = true
    }

    /**
     * Store the playing on-demand item's live position on its own entry, so a
     * later zap back to it resumes from there.
     *
     * Mirrors the Flutter-side window: a barely-started or effectively
     * finished item banks 0 and replays from the beginning, rather than
     * stranding the viewer a second from the credits.
     */
    private fun checkpointCurrentIptvPosition() {
        val entry = iptvChannels.getOrNull(currentIptvIndex) ?: return
        if (entry.isLive) return

        val duration = player?.duration ?: 0L
        val position = player?.currentPosition ?: 0L
        if (duration <= 0L || position <= 0L) return

        val fraction = position.toDouble() / duration.toDouble()
        entry.resumePositionMs = if (fraction in 0.02..0.95) position else 0L
    }

    private fun playIptvChannel(index: Int) {
        if (index !in iptvChannels.indices) return
        val entry = iptvChannels[index]

        android.util.Log.d("AndroidTvPlayer", "playIptvChannel: ${entry.name} url=${entry.url.take(60)}")

        // Clear subtitle identity/results when changing channels.
        resetSubtitleState()

        beginIptvPlayback(entry)

        // Update the title content. Visibility stays synchronized with controls.
        titleView.text = entry.displayName

        // First tune on a live channel: the zap banner doubles as the "here's
        // what's on" card and teaches the zap/guide keys — without it, EPG
        // exists only inside a guide overlay nobody knows how to open.
        if (entry.isLive) showIptvZapBanner(entry)
    }

    // ── IPTV episode navigation (series/VOD lists) ──────────────────────────

    /** This IPTV session is an Xtream SERIES episode list. Scoped to series
     *  (the launcher sets seriesAudioKey only then) — NOT every non-live item —
     *  so automatic episode progression never applies to a standalone movie. */
    private fun isIptvEpisodeMode(): Boolean {
        if (!isIptvMode || iptvSeriesAudioKey == null) return false
        val entry = iptvChannels.getOrNull(currentIptvIndex) ?: return false
        return !entry.isLive
    }

    private fun nextIptvEpisode(): IptvChannelEntry? {
        if (!isIptvEpisodeMode()) return null
        return iptvChannels.getOrNull(currentIptvIndex + 1)
    }

    private fun prevIptvEpisode(): IptvChannelEntry? {
        if (!isIptvEpisodeMode()) return null
        return iptvChannels.getOrNull(currentIptvIndex - 1)
    }

    /** IPTV guide and CH controls belong to live television only. VOD keeps
     *  the standard seek controls and episode Previous/Next actions. */
    private fun updateIptvEpisodeControls() {
        val entry = iptvChannels.getOrNull(currentIptvIndex)
        updateIptvControlPresentation(entry)
        if (!isIptvMode) return
        if (entry?.isLive == true) {
            iptvPrevButton?.text = "CH -"
            iptvNextButton?.text = "CH +"
            val visibility =
                if (iptvChannels.size > 1 || iptvZapPagingActive) {
                    View.VISIBLE
                } else {
                    View.GONE
                }
            iptvPrevButton?.visibility = visibility
            iptvNextButton?.visibility = visibility
        } else {
            iptvPrevButton?.text = "Previous"
            iptvNextButton?.text = "Next"
            iptvPrevButton?.visibility =
                if (prevIptvEpisode() != null) View.VISIBLE else View.GONE
            iptvNextButton?.visibility =
                if (nextIptvEpisode() != null) View.VISIBLE else View.GONE
        }
    }

    /** Set the TrackSelector's preferred audio language — a persistent
     *  parameter, so it re-applies to each episode's tracks on switch. */
    private fun setIptvPreferredAudioLang(lang: String) {
        val ts = trackSelector ?: return
        val variants = LanguageMapper.getLanguageVariantsForExoPlayer(lang)
        val p = ts.parameters.buildUpon()
        if (variants.isNotEmpty()) {
            p.setPreferredAudioLanguages(*variants.toTypedArray())
        } else {
            p.setPreferredAudioLanguage(lang)
        }
        ts.parameters = p.build()
    }

    /** A native audio pick in a series: carry it to later episodes (preferred-
     *  language param) and persist it back to Flutter's per-series store. */
    private fun onIptvSeriesAudioPicked(lang: String?) {
        val key = iptvSeriesAudioKey ?: return
        if (lang.isNullOrEmpty() || lang == "und" || lang == "auto") return
        iptvPreferredAudioLang = lang
        setIptvPreferredAudioLang(lang)
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "saveIptvSeriesAudio",
            mapOf("seriesKey" to key, "lang" to lang)
        )
    }

    /** The audio language of a track-selection override, for capturing a pick. */
    private fun languageOfOverride(override: TrackSelectionOverride?): String? {
        if (override == null) return null
        val idx = override.trackIndices.firstOrNull() ?: return null
        return try {
            override.mediaTrackGroup.getFormat(idx).language
        } catch (e: Exception) {
            null
        }
    }

    // ── Stremio-addon IPTV channels (resolve-on-demand + serial ladder) ──────

    private fun isStremioIptvUrl(url: String): Boolean = url.startsWith("stremio-tv://")

    /** One playable link for a Stremio channel: stream URL + the addon's label. */
    private data class IptvStremioCandidate(val url: String, val label: String)

    /** The shared ExoPlayer media-item swap both IPTV entry points use. */
    private fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String) {
        // A genuine channel change while recording: finalize the previous
        // channel's file before the stream identity flips. An HLS-fallback retry
        // re-enters with the SAME url and is handled via abortAndDelete instead.
        if (iptvRecordingController.isActive && streamUrl != currentIptvStreamUrl) {
            finalizeIptvRecordingIfActive()
        }

        val metadata = MediaMetadata.Builder()
            .setTitle(entry.name)
            .setArtist(entry.group ?: "IPTV")
            .build()

        // The channel's own headers ride every request from here on (the
        // resolver installed in setupPlayer reads this per request). Set
        // BEFORE the media item so the first playlist fetch already has them.
        currentIptvHttpHeaders = entry.httpHeaders
        currentIptvStreamUrl = streamUrl
        // Any tune to a URL other than the twin under trial supersedes the
        // trial (a zap, a Stremio candidate, a lifecycle rejoin — every path
        // funnels through here). Without this, the trial's timeout could
        // later fire against a different channel.
        if (iptvTwinTrialUrl != null && streamUrl != iptvTwinTrialUrl) {
            clearIptvTwinTrial()
        }
        // A same-twin recovery must not destroy a parked rollback (sleep can
        // leave that twin errored before the user presses Play). Tuning the
        // original consumes the restore; tuning anywhere else supersedes it.
        if (iptvTwinTrialRestoreOriginal != null &&
            streamUrl != iptvTwinTrialRestoreTwin
        ) {
            clearParkedIptvTwinRestore()
        }
        // Demux mode for this tune: strict for channels that earned it — and
        // for the whole session once two did (that's a strict-decoder device,
        // not two odd channels). Read per media-period load by the extractor
        // factory installed in setupPlayer. A twin — on trial or accepted —
        // is always strict: it exists to reach the demux mode that works
        // (see the twin-trial fields).
        iptvStrictTsActive =
            iptvStrictTsUrls.contains(streamUrl) || iptvStrictTsUrls.size >= 2 ||
            streamUrl == iptvTwinTrialUrl ||
            iptvTwinPreferredUrls.containsValue(streamUrl)
        iptvTuneDiagnostics.onTuneStart(
            entry.name,
            streamUrl,
            entry.isLive,
            forcedHls = iptvHlsForcedUrls.contains(streamUrl),
        )
        // A machine-driven re-tune keeps its recovery episode (attempt count,
        // surrender budget); a real zap/launch resets the machine — and takes
        // any reconnect pill with it (the pill described the OLD channel).
        iptvLiveRecovery.expectRetune = iptvLiveRetuneInFlight
        iptvLiveRecovery.onTuneStarted()
        if (!iptvLiveRetuneInFlight) hideIptvReconnectPill()
        // Every tune re-arms the zap frame-hold: a surrender turned it off,
        // and without this, zapping AWAY from the surrendered channel would
        // black-flash forever after (codex round 2, finding 17).
        playerView.setKeepContentOnPlayerReset(true)

        val mediaItem = MediaItem.Builder()
            .setUri(streamUrl)
            .setMediaMetadata(metadata)
            .apply {
                // Extension-less URLs infer as progressive and fail on HLS
                // playlists; once a URL has proven to be HLS (via the error
                // fallback) start it as HLS directly.
                if (iptvHlsForcedUrls.contains(streamUrl)) {
                    setMimeType(MimeTypes.APPLICATION_M3U8)
                }
            }
            .build()

        // Resume on-demand items where they were left off. Passing the start
        // position to setMediaItem rather than seeking after prepare avoids
        // briefly rendering frame 0. Live channels always take the plain form:
        // a start position on a live stream would drop it off the live edge.
        val startAt = if (entry.isLive) 0L else entry.resumePositionMs
        player?.apply {
            if (startAt > 0L) {
                setMediaItem(mediaItem, startAt)
            } else {
                setMediaItem(mediaItem)
            }
            prepare()
            playWhenReady = true
            play()
        }

        // IPTV mode never goes through playMediaDirect, so nothing else starts
        // the progress ticker here — without this the Flutter side is told
        // nothing about on-demand playback and can't save a resume position.
        restartProgressUpdates()

        // Reflect the new stream's HLS-ness on the record button (progressive →
        // enabled, HLS → disabled).
        updateRecordButtonState()
    }

    /**
     * The extension-less-HLS fallback: when the current IPTV stream failed
     * because no extractor recognized it (bare URLs — `jmp2.uk/stvp-…` —
     * infer as progressive, and progressive extractors can't read an
     * `#EXTM3U` text playlist), remember the URL as HLS and restart it once
     * with the type forced. Returns true when a retry was started. mpv
     * content-sniffs, which is why the same channels play on phone — this
     * closes that gap for ExoPlayer.
     */
    /// A playback error the user can act on: this box has no decoder for the
    /// track we handed it. Until now every non-IPTV error only reached logcat,
    /// so the screen just sat there — which is exactly what an MPEG-2 file
    /// looks like on a box without an MPEG-2 decoder.
    ///
    /// Worth naming specifically because MPEG program streams (.mpg/.vob) are
    /// the common case: their container and audio are covered here, but their
    /// video has no software fallback — ExoPlayer ships none, and the bundled
    /// ffmpeg extension's video renderer is a stub that reports every format
    /// unsupported. Most TV boxes carry an MPEG-2 decoder from their
    /// broadcast heritage; the ones that don't deserve an explanation rather
    /// than a dead screen. The phone/desktop player has no such limit — it
    /// decodes these in software through libmpv.
    private fun reportDecoderFailure(error: PlaybackException) {
        if (isFinishing || isDestroyed) return
        val decoderProblem = when (error.errorCode) {
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED -> true
            else -> false
        }
        if (!decoderProblem) return

        val mime = (error as? ExoPlaybackException)?.rendererFormat?.sampleMimeType
        val message = when (mime) {
            MimeTypes.VIDEO_MPEG2, MimeTypes.VIDEO_MPEG ->
                "This device has no MPEG-2 video decoder, so this file can't play here. It will play on the phone app."
            null -> "This device can't decode this file."
            else -> "This device can't decode ${'$'}mime."
        }
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    private fun retryIptvAsHlsIfUnrecognized(error: PlaybackException): Boolean {
        val url = currentIptvStreamUrl ?: return false
        if (iptvHlsForcedUrls.contains(url)) return false // already tried
        var cause: Throwable? = error
        var unrecognized = false
        while (cause != null) {
            if (cause is UnrecognizedInputFormatException) {
                unrecognized = true
                break
            }
            cause = cause.cause
        }
        if (!unrecognized) return false

        val entry = iptvChannels.getOrNull(currentIptvIndex) ?: return false
        android.util.Log.d(
            "AndroidTvPlayer",
            "Unrecognized format for ${entry.name} — retrying as HLS"
        )
        // The stream is HLS, so any tee-recorded bytes are an unusable
        // playlist/segment mix — discard them and lock the button off.
        if (iptvRecordingController.isActive) {
            iptvRecordingController.abortAndDelete()
            Toast.makeText(
                this,
                "Recording stopped — this channel is HLS",
                Toast.LENGTH_LONG,
            ).show()
        }
        iptvHlsForcedUrls.add(url)
        setIptvMediaItem(entry, url)
        updateRecordButtonState()
        // Stremio candidate: give the forced-HLS attempt a FULL stall window
        // (arming re-cancels the one ticking since candidate start — a slow
        // panel can eat most of that window on the failed sniff alone, and
        // the ladder would advance past a candidate that plays when forced).
        if (iptvStremioChannelKey != null) {
            armIptvStremioStallWatchdog()
        }
        return true
    }

    /**
     * Start playback for an IPTV channel. Plain channels play their URL
     * directly; Stremio-addon channels first resolve their candidate stream
     * URLs through the Flutter bridge (cached on the Dart side), then play
     * candidate 0 — [tryNextIptvStremioCandidate] walks the rest on error.
     */
    private fun beginIptvPlayback(entry: IptvChannelEntry) {
        // The channel change starts HERE, so the outgoing channel's recording
        // ends here too. Waiting for setIptvMediaItem would strand it whenever
        // a Stremio resolve returns nothing: the row would stay pending while
        // the UI already shows the new channel.
        finalizeIptvRecordingIfActive()

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
        currentIptvStreamUrl = null

        if (!isStremioIptvUrl(entry.url)) {
            // A channel whose `.m3u8` wedged and whose `.ts` twin proved
            // itself this session starts on the twin directly.
            setIptvMediaItem(entry, iptvTwinPreferredUrls[entry.url] ?: entry.url)
            return
        }

        // The guide/title/index already committed to this channel — stop the
        // outgoing stream now so a slow (or failed) resolve can't leave the
        // previous channel playing under the new channel's UI state.
        player?.stop()

        requestIptvStreamUrls(entry.url, entry.name) { candidates, message ->
            runOnUiThread {
                if (token != iptvStremioToken || isFinishing) return@runOnUiThread
                if (candidates.isEmpty()) {
                    android.util.Log.w("AndroidTvPlayer", "No playable streams for ${entry.name}")
                    Toast.makeText(
                        this,
                        message ?: "${entry.name} is not playable right now",
                        Toast.LENGTH_LONG,
                    ).show()
                    return@runOnUiThread
                }
                iptvStremioChannelKey = entry.url
                iptvStremioCandidates = candidates
                iptvStremioCandidateIndex = 0
                populateIptvStremioSources()
                setIptvMediaItem(entry, candidates[0].url)
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
        stremioSources.clear()
        iptvStremioCandidates.forEachIndexed { i, c ->
            stremioSources.add(
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
        currentStremioSourceIndex = iptvStremioCandidateIndex
        setupStremioSources()
    }

    private fun iptvQualityFromLabel(label: String): String {
        val m = Regex("(2160p|4k|1080p|720p|480p)", RegexOption.IGNORE_CASE).find(label)
        return when (m?.value?.lowercase()) {
            "2160p", "4k" -> "4K"
            "1080p" -> "1080p"
            "720p" -> "720p"
            "480p" -> "480p"
            else -> "LIVE"
        }
    }

    /** Leaving a Stremio channel (or re-resolving one) — retire its source rows. */
    private fun clearIptvStremioSources() {
        if (!isIptvMode || stremioSources.isEmpty()) return
        stremioSources.clear()
        currentStremioSourceIndex = 0
        stremioSourceBadge?.visibility = View.GONE
    }

    /**
     * Manual pick from the sources panel while a Stremio IPTV channel plays.
     * Keeps the ladder in step (an error after the pick advances from the
     * picked link) and skips the movie path's position seek — meaningless on
     * a live stream.
     */
    private fun switchToIptvStremioSource(url: String, sourceIndex: Int) {
        android.util.Log.d("AndroidTvPlayer", "switchToIptvStremioSource: index=$sourceIndex")
        iptvStremioCandidateIndex = sourceIndex
        iptvStremioWinnerReported = false
        currentStremioSourceIndex = sourceIndex
        updateStremioQualityBadge()
        sourceBrowser?.render()
        val entry = iptvChannels.getOrNull(currentIptvIndex)
        if (entry != null) {
            setIptvMediaItem(entry, url)
        } else {
            player?.setMediaItem(MediaItem.fromUri(url))
            player?.prepare()
            player?.play()
        }
        armIptvStremioStallWatchdog()
        watchSourceSwitchOutcome(sourceIndex)
    }

    /**
     * Advance the serial candidate ladder after a playback error. Returns
     * false when the current playback isn't a Stremio channel (the error
     * isn't ours to handle).
     */
    private fun tryNextIptvStremioCandidate(): Boolean {
        val key = iptvStremioChannelKey ?: return false
        val candidates = iptvStremioCandidates
        if (candidates.isEmpty()) return false
        // The ladder owns error messaging from here (silent advance, toast only
        // when every candidate dies) — a manual pick's watcher must not speak.
        dropStaleSourceSwitchFeedback()
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
            val name = iptvChannels.getOrNull(currentIptvIndex)?.name ?: "Channel"
            // Distinct from the "resolve came back empty" toast: links existed
            // but every one died. Point at the escape hatch we kept alive.
            val attempted = candidates.size
            val message = if (attempted == 1)
                "$name: its only source didn't play — pick it in Sources to retry"
            else
                "$name: tried all $attempted sources, none played — pick one in Sources to retry"
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
            return true
        }
        iptvStremioCandidateIndex = next
        iptvStremioWinnerReported = false
        val entry = iptvChannels.getOrNull(currentIptvIndex) ?: return false
        android.util.Log.d(
            "AndroidTvPlayer",
            "IPTV stremio ladder: trying candidate ${next + 1}/${candidates.size} for ${entry.name}"
        )
        // Keep the sources menu's active row in step with the auto-advance.
        if (stremioSources.isNotEmpty()) {
            currentStremioSourceIndex = next
            sourceBrowser?.render()
        }
        setIptvMediaItem(entry, candidates[next].url)
        armIptvStremioStallWatchdog()
        return true
    }

    /** See [iptvStremioStallRunnable]. Re-armed per candidate. */
    private fun armIptvStremioStallWatchdog() {
        cancelIptvStremioStallWatchdog()
        val token = iptvStremioToken
        val candidateIndex = iptvStremioCandidateIndex
        val runnable = Runnable {
            if (isFinishing || isDestroyed) return@Runnable
            if (token != iptvStremioToken || candidateIndex != iptvStremioCandidateIndex) return@Runnable
            if (iptvStremioWinnerReported || iptvStremioChannelKey == null) return@Runnable
            android.util.Log.w(
                "AndroidTvPlayer",
                "IPTV stremio ladder: candidate ${candidateIndex + 1} never reached READY, advancing"
            )
            tryNextIptvStremioCandidate()
        }
        iptvStremioStallRunnable = runnable
        progressHandler.postDelayed(runnable, 20_000)
    }

    private fun cancelIptvStremioStallWatchdog() {
        iptvStremioStallRunnable?.let { progressHandler.removeCallbacks(it) }
        iptvStremioStallRunnable = null
    }

    /** First READY on a Stremio candidate — cache the winner on the Dart side. */
    private fun reportIptvStremioWinnerIfNeeded() {
        if (iptvStremioWinnerReported) return
        val key = iptvStremioChannelKey ?: return
        val url = iptvStremioCandidates.getOrNull(iptvStremioCandidateIndex)?.url ?: return
        iptvStremioWinnerReported = true
        cancelIptvStremioStallWatchdog()
        reportIptvStreamResult(key, url, true)
    }

    /**
     * Ask Flutter to resolve a stremio-tv:// channel key into labeled stream
     * links. On an empty result the callback's second argument carries a
     * user-facing reason ("Couldn't reach <addon>…") when Flutter knows one.
     */
    private fun requestIptvStreamUrls(
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
    private fun reportIptvStreamResult(channelUrl: String, url: String?, success: Boolean) {
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

    // Track selection
    // ═══════════════════════════════════════════════════════════════════════════
    // UNIFIED MENU · backing (reuses existing apply logic; nothing is duplicated
    // that would drift from the individual dialogs).
    // ═══════════════════════════════════════════════════════════════════════════

    /** Same list [showAudioTrackDialog] builds: "Off" + one entry per audio track. */
    private fun umAudioTracks(): List<Pair<String, TrackSelectionOverride?>> {
        val out = mutableListOf<Pair<String, TrackSelectionOverride?>>()
        out.add("Off" to null)
        val tracks = player?.currentTracks ?: return out
        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_AUDIO) {
                for (i in 0 until group.length) {
                    out.add(
                        buildAudioTrackLabel(group.getTrackFormat(i)) to
                            TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                    )
                }
            }
        }
        return out
    }

    /** Index into [umAudioTracks] of the currently selected track (0 = Off). */
    private fun umAudioSelectedIndex(): Int {
        val tracks = player?.currentTracks ?: return 0
        var pos = 1
        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_AUDIO) {
                for (i in 0 until group.length) {
                    if (group.isTrackSelected(i)) return pos
                    pos++
                }
            }
        }
        return 0
    }

    // Inline subtitle-search state (rendered in the Subtitles → Fix movie column).
    private var subtitleSearchResults: List<SubtitleCatalogResult> = emptyList()
    private var subtitleSearchStatus: String = ""
    private var pendingSeriesResult: SubtitleCatalogResult? = null
    private var pendingSeason: Int = 1
    private var pendingEpisode: Int = 1

    // Menu section order — MUST match UnifiedMenuController.sectionIds.
    private val unifiedSectionIds = listOf("audio", "subs", "sources", "display", "playback")

    private fun mrow(
        title: String, value: String? = null, selected: Boolean = false, accent: Boolean = false,
        enabled: Boolean = true, swatch: Int? = null, adjustable: Boolean = false, tag: String? = null,
        onOk: (() -> Unit)? = null, onAdjust: ((Int) -> Unit)? = null
    ) = UnifiedMenuController.Row(title, value, selected, accent, enabled, swatch, adjustable, tag, onOk, onAdjust)

    private fun umSectionRows(): List<UnifiedMenuController.Row> {
        val subBadge = when {
            isLoadingStremioSubtitles -> "…"
            stremioSubtitles.isNotEmpty() -> "${stremioSubtitles.size}"
            else -> null
        }
        return listOf(
            mrow("Audio"),
            mrow("Subtitles", value = subBadge),
            mrow(
                "Sources",
                value = if (stremioSources.isNotEmpty()) "${stremioSources.size}" else null,
                enabled = stremioSources.isNotEmpty(),
            ),
            mrow("Display"),
            mrow("Playback")
        )
    }

    private val unifiedMenuCallbacks = object : UnifiedMenuController.Callbacks {
        override fun buildModel(sectionIndex: Int, col2Index: Int): UnifiedMenuController.Model {
            val col1 = umSectionRows()
            return when (unifiedSectionIds.getOrNull(sectionIndex)) {
                "audio" -> umAudioModel(col1, col2Index)
                "subs" -> umSubsModel(col1, col2Index)
                "sources" -> umSourcesModel(col1, col2Index)
                "display" -> umDisplayModel(col1, col2Index)
                "playback" -> umPlaybackModel(col1, col2Index)
                else -> UnifiedMenuController.Model(col1, "", emptyList(), "", emptyList())
            }
        }

        override fun onSectionActivated(sectionIndex: Int): Boolean {
            if (unifiedSectionIds.getOrNull(sectionIndex) != "sources") return false
            if (stremioSources.isEmpty()) return true
            unifiedMenu?.hide()
            sourceBrowser?.show()
            return true
        }

        override fun onSearchSubmit(query: String) {
            subtitleSearchStatus = "Searching…"
            subtitleSearchResults = emptyList()
            pendingSeriesResult = null
            unifiedMenu?.render()
            requestSubtitleCatalogSearchFromFlutter(
                query,
                onSuccess = { results ->
                    if (unifiedMenu?.isVisible != true) return@requestSubtitleCatalogSearchFromFlutter
                    subtitleSearchResults = results
                    subtitleSearchStatus =
                        if (results.isEmpty()) "No matches — try a different title" else "${results.size} results"
                    unifiedMenu?.render()
                },
                onError = { msg ->
                    if (unifiedMenu?.isVisible != true) return@requestSubtitleCatalogSearchFromFlutter
                    subtitleSearchStatus = msg
                    unifiedMenu?.render()
                }
            )
        }

        override fun searchInitialQuery(): String {
            val item = getCurrentSubtitleSearchItem() ?: return ""
            return buildSubtitleSearchInitialQuery(item)
        }

        override fun stylePreview(tv: TextView) {
            val ctx = this@AndroidTvTorrentPlayerActivity
            tv.text = "Sample subtitle preview"
            tv.setTextColor(SubtitleSettings.getCurrentColor(ctx).color)
            tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, SubtitleSettings.getFontSizeSp(ctx))
            tv.typeface = SubtitleSettings.getEffectiveTypeface(ctx)
            tv.setBackgroundColor(SubtitleSettings.getCurrentBg(ctx).color)
            if (SubtitleSettings.getStyleIndex(ctx) != 0) {  // 0 = "None" edge
                val edge = SubtitleSettings.getCurrentOutlineColor(ctx).color ?: Color.BLACK
                tv.setShadowLayer(6f, 0f, 0f, edge)
            } else {
                tv.setShadowLayer(0f, 0f, 0f, 0)
            }
        }

        override fun onHidden() { /* clean frame; BACK returns to the video */ }
    }

    // ── Audio ─────────────────────────────────────────────────────────────────
    private fun umAudioModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val col2 = listOf(
            mrow("Audio track", tag = "audio"),
            mrow("Night mode", value = nightModeLabels.getOrNull(nightModeIndex), tag = "night")
        )
        val tag = col2.getOrNull(col2Index)?.tag
        val (title, col3) = if (tag == "night") {
            "Night mode · loudness" to nightModeLabels.mapIndexed { i, l ->
                mrow(l, selected = i == nightModeIndex, onOk = { applyNightMode(i) })
            }
        } else if (umAudioTracks().size <= 1) {   // only the synthetic "Off" entry → no real tracks
            "Audio tracks" to listOf(mrow("No audio tracks available", enabled = false))
        } else {
            val sel = umAudioSelectedIndex()
            "Audio tracks" to umAudioTracks().mapIndexed { i, pair ->
                mrow(pair.first, selected = i == sel, onOk = {
                    val ts = trackSelector
                    if (ts != null) {
                        val override = umAudioTracks().getOrNull(i)?.second
                        val p = ts.parameters.buildUpon()
                        if (override != null) {
                            p.setOverrideForType(override); p.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                        } else p.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                        ts.parameters = p.build()
                        // Series: remember this language for later episodes + sessions.
                        onIptvSeriesAudioPicked(languageOfOverride(override))
                    }
                })
            }
        }
        return UnifiedMenuController.Model(col1, "AUDIO", col2, title, col3)
    }

    // ── Subtitles (embedded + per-addon + appearance + timing + search) ─────────
    private fun umSubsModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val curSub = stremioSubtitles.getOrNull(currentStremioSubtitleIndex)
        val col2 = mutableListOf<UnifiedMenuController.Row>()
        col2.add(mrow("Embedded", tag = "emb", selected = curSub == null))
        for (r in addonSubtitleResults) {
            val badge = when (r.status) {
                AddonSubtitleStatus.LOADING -> "…"
                AddonSubtitleStatus.OK -> "${r.subtitles.size}"
                AddonSubtitleStatus.FAILED -> "⚠"
            }
            col2.add(mrow(
                r.addon.name, value = badge, tag = "addon:${r.addon.id}",
                selected = curSub != null && curSub.addonId == r.addon.id
            ))
        }
        col2.add(mrow("Fix movie", tag = "search", accent = true))
        col2.add(mrow("Appearance", tag = "appearance"))
        col2.add(mrow("Timing", tag = "timing"))

        val tag = col2.getOrNull(col2Index)?.tag
        var mode = UnifiedMenuController.Col3Mode.ROWS
        val (col3Title, col3) = when {
            tag == "emb" -> "Track" to umEmbeddedTrackRows()
            tag == "appearance" -> "Appearance · live" to umAppearanceRows()
            tag == "timing" -> "Timing" to umTimingRows()
            tag == "search" -> {
                if (pendingSeriesResult == null) mode = UnifiedMenuController.Col3Mode.SEARCH
                "Fix movie" to umSearchRows()
            }
            tag != null && tag.startsWith("addon:") -> {
                val id = tag.removePrefix("addon:")
                (addonSubtitleResults.firstOrNull { it.addon.id == id }?.addon?.name ?: "Addon") to
                    umAddonTrackRows(id)
            }
            else -> "" to emptyList()
        }
        // Column header carries the detected/override identity ("Detected: <title>" /
        // "Subtitles for <title>") that the old panel showed as a persistent row.
        return UnifiedMenuController.Model(
            col1, currentSubtitleIdentityLabel(), col2, col3Title, col3, mode,
            previewVisible = tag == "appearance"
        )
    }

    private fun umEmbeddedTrackRows(): List<UnifiedMenuController.Row> {
        // Build the flat track list only when we don't already have one (menu open /
        // after a content switch clears it). Rebuilding on every render would re-derive
        // currentSubtitleTrackIndex from the not-yet-updated player.currentTracks and
        // clobber a just-made selection, painting the wrong row as selected.
        if (subtitleTracks.isEmpty()) rebuildSubtitleTrackList()
        val rows = mutableListOf<UnifiedMenuController.Row>()
        for ((i, pair) in subtitleTracks.withIndex()) {
            val isOff = i == 0
            val isEmbedded = pair.second != null
            if (isOff || isEmbedded) {
                rows.add(mrow(
                    if (isOff) "Off" else pair.first,
                    selected = currentSubtitleTrackIndex == i,
                    onOk = { umSelectSubtitleRowIndex(i) }
                ))
            }
        }
        return rows
    }

    private fun umAddonTrackRows(addonId: String): List<UnifiedMenuController.Row> {
        val r = addonSubtitleResults.firstOrNull { it.addon.id == addonId } ?: return emptyList()
        return when (r.status) {
            AddonSubtitleStatus.LOADING -> listOf(mrow("Loading…", enabled = false))
            AddonSubtitleStatus.FAILED -> {
                val rows = mutableListOf(mrow("Failed — retry this addon", accent = true,
                    onOk = { retryAddonSubtitles(addonId) }))
                r.error?.takeIf { it.isNotBlank() }?.let { rows.add(mrow(it.take(48), enabled = false)) }
                rows
            }
            AddonSubtitleStatus.OK ->
                if (r.subtitles.isEmpty()) listOf(mrow("No subtitles from this addon", enabled = false))
                else r.subtitles.map { sub ->
                    val cur = stremioSubtitles.getOrNull(currentStremioSubtitleIndex)
                    mrow(
                        sub.displayName, value = sub.lang.uppercase(Locale.US),
                        // Require addonId match too: a URL shared by two addons dedupes
                        // to one owner, so only that addon's row highlights.
                        selected = cur?.url == sub.url && cur.addonId == addonId,
                        onOk = { umSelectStremioSubtitleByUrl(sub.url) }
                    )
                }
        }
    }

    private fun umAppearanceRows(): List<UnifiedMenuController.Row> =
        // Shared with the Torbox player so the subtitle-appearance controls
        // can't drift between the two (see UnifiedMenuSections).
        UnifiedMenuSections.appearanceRows(this) { applyAndPersistSubtitleSettings() }

    private fun umTimingRows(): List<UnifiedMenuController.Row> {
        val ctx = this
        val ms = SubtitleSettings.getSyncOffsetMs(ctx)
        // Sync needs the subtitle on screen to judge alignment, which a bottom menu
        // column covers — so this opens the dedicated over-video sync overlay
        // (slider for embedded subs, "tap the line" picker for downloaded subs).
        // Single launcher — the overlay itself owns reset (OK on the slider /
        // hold-OK on the picker), which also clears the picker's remembered line.
        return listOf(
            // Listens to the played audio it has already seen (the PCM tap) and
            // cross-correlates it against the subtitle's cue schedule — answers
            // in under a second, applies only on a confident match. Addon subs
            // only: their cue timelines are in hand, and they're the ones that
            // arrive mistimed; embedded tracks are authored against this video.
            mrow(
                "Auto-sync from audio",
                value = when {
                    !externalSubtitleActive -> "needs an addon subtitle"
                    autoSyncRunning -> "listening…"
                    // Last outcome, only while the subtitle it was computed
                    // against is still the one on screen.
                    autoSyncResultUrl == activeExternalSubtitleUrl -> autoSyncResultLabel
                    else -> null
                },
                accent = true,
                enabled = externalSubtitleActive && !autoSyncRunning,
                onOk = { unifiedMenu?.hide(); runSubtitleAutoSync() },
            ),
            mrow("Adjust timing  ▸", value = SubtitleSettings.formatSyncOffset(ms),
                swatch = SubtitleSettings.getSyncOffsetColor(ms), accent = true, onOk = {
                    unifiedMenu?.hide(); showSyncOverlay()
                })
        )
    }

    /**
     * Run the audio↔subtitle aligner over whatever anchored PCM history the
     * tap holds and apply the offset through the exact pathway the manual
     * slider and line picker use — one offset store, three ways to fill it.
     *
     * Every failure mode gets its own honest message; nothing is ever applied
     * below the aligner's confidence gate. The v1 lesson, kept on purpose: a
     * wrong auto-sync reads as "broken feature", a declined one as a miss.
     */
    private fun runSubtitleAutoSync(auto: Boolean = false) {
        if (autoSyncRunning) return
        val tap = speechTap
        val url = activeExternalSubtitleUrl
        val rawCues = url?.let { SubtitleCueCache.get(it) }
        if (tap == null || rawCues.isNullOrEmpty()) {
            if (!auto) showSyncToast(
                "✕", AutoSyncColors.FAIL,
                "Pick an addon subtitle first",
                autoHideMs = 3_500,
            )
            return
        }
        val segments = tap.snapshot()
        val heardSec = (segments.sumOf { it.durationMs } / 1000.0).toInt()
        val anchoredSec =
            (segments.filter { it.anchorMs != Long.MIN_VALUE }.sumOf { it.durationMs } / 1000.0).toInt()
        android.util.Log.d(
            "AutoSync",
            "run: heard=${heardSec}s anchored=${anchoredSec}s segments=${segments.size} cues=${rawCues.size}"
        )
        if (anchoredSec < 1 && player?.isPlaying == true && !tap.hasRecentAudio(8_000)) {
            // Playing, yet no PCM ever reached the tap: passthrough/tunneled
            // audio, or a format the sink won't route through processors.
            if (auto) return
            showSyncToast(
                "✕", AutoSyncColors.FAIL,
                "Can't analyze this stream's audio",
                autoHideMs = 4_000,
            )
            return
        }
        autoSyncRunning = true
        if (!auto) {
            showSyncToast(
                "●", AutoSyncColors.BUSY,
                "Syncing subtitles…",
                autoHideMs = null,
            )
        } else if (autoSyncPillWindowActive) {
            // Ladder attempt: the heartbeat flips to its checking face
            // (white dot + label) while the aligner runs.
            showSyncToast("●", AutoSyncColors.BUSY, "Checking…", autoHideMs = null)
            autoSyncPillRing?.arcColor = Color.WHITE
        }
        subtitleScope.launch {
            val result = try {
                val cues = rawCues.map { CueSpan(it.startMs, it.endMs, it.text) }
                withContext(Dispatchers.Default) { SubtitleAligner.alignTiered(segments, cues) }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e // activity teardown — let the scope die quietly
            } catch (e: Exception) {
                // Pure math should never throw; if it somehow does, the player
                // must not die for a subtitle convenience feature.
                android.util.Log.e("AutoSync", "aligner failed", e)
                AlignResult.NoMatch(0)
            } finally {
                autoSyncRunning = false
            }
            android.util.Log.d("AutoSync", "result: $result")
            // An intermediate rung that stays silent hands the screen back
            // its quiet; speaking results overwrite this at once.
            if (auto && autoSyncPillWindowActive) {
                hideAutoSyncPillView()
            }
            // The user may have switched subtitles during the analysis — the
            // computed offset belongs to the cue timeline it was computed FROM.
            if (activeExternalSubtitleUrl != url) {
                if (!auto) showSyncToast(
                    "●", AutoSyncColors.BUSY,
                    "Subtitle changed — try again",
                    autoHideMs = 3_000,
                )
                return@launch
            }
            fun remember(label: String) {
                autoSyncResultLabel = label
                autoSyncResultUrl = url
            }
            when (result) {
                is AlignResult.Synced -> {
                    autoSyncLadderDone = true
                    SubtitleSettings.setSyncOffsetMs(this@AndroidTvTorrentPlayerActivity, result.offsetMs)
                    applySubtitleSettings()
                    autoSyncAppliedOffsetMs = result.offsetMs
                    scheduleAutoSyncVerify()
                    val fmt = SubtitleSettings.formatSyncOffset(result.offsetMs)
                    remember("✓ $fmt")
                    // Shown in BOTH modes — an offset changing under the user
                    // must always announce itself, however quietly.
                    // Number-free by design; the offset lives in the menu row
                    // (autoSyncResultLabel) and logcat.
                    showSyncToast(
                        "✓", AutoSyncColors.OK,
                        "Subtitles synced",
                        autoHideMs = 3_000,
                    )
                }
                is AlignResult.Drift -> {
                    autoSyncLadderDone = true // a longer listen can't fix drift
                    remember("drifting")
                    // Worth a word in both modes: drift means THIS subtitle
                    // file can never be fixed by an offset — switching is the
                    // only cure, so say so.
                    showSyncToast(
                        "✕", AutoSyncColors.FAIL,
                        "Subs drift on this file",
                        hint = "Try another subtitle",
                        autoHideMs = 4_500,
                    )
                }
                is AlignResult.NoMatch -> {
                    remember("no match")
                    if (auto) {
                        // Intermediate rungs stay silent; only the LAST rung's
                        // failure earns a (gentle) word, so the user knows the
                        // hand-off is theirs now.
                        if (autoSyncLadderIdx >= autoSyncLadderSec.size) {
                            showSyncToast(
                                "✕", AutoSyncColors.FAIL,
                                "Couldn't sync automatically",
                                hint = "Switch subs, or adjust in Subtitles → Timing",
                                autoHideMs = 5_000,
                            )
                        }
                        return@launch
                    }
                    showSyncToast(
                        "✕", AutoSyncColors.FAIL,
                        "No confident match",
                        hint = "Adjust in Subtitles → Timing",
                        autoHideMs = 4_500,
                    )
                }
                is AlignResult.NotEnoughAudio -> {
                    remember("${result.analyzedSec}s heard")
                    if (auto) {
                        if (autoSyncLadderIdx >= autoSyncLadderSec.size) {
                            showSyncToast(
                                "✕", AutoSyncColors.FAIL,
                                "Couldn't sync automatically",
                                hint = "Switch subs, or adjust in Subtitles → Timing",
                                autoHideMs = 5_000,
                            )
                        }
                        return@launch
                    }
                    showSyncToast(
                        "●", AutoSyncColors.BUSY,
                        "Keep watching a little, then try again",
                        autoHideMs = 3_500,
                    )
                }
            }
        }
    }

    /**
     * Arm the hands-free ladder for a freshly loaded addon subtitle. Each tick
     * asks the tap how much ANCHORED audio exists and fires the next attempt
     * when a rung's worth is on hand — so the first attempt (narrow search)
     * lands ~20s in, without the user touching anything. Skips entirely while
     * a manual offset is dialed in: the user's hand beats the machine's.
     */
    private fun startAutoSyncLadder() {
        cancelAutoSyncLadder()
        if (!isAutoSyncPrefEnabled()) return
        // The one up-front sentence, then the heartbeat. Skipped when a
        // remembered offset just restored — that pill already said everything.
        if (SubtitleSettings.getSyncOffsetMs(this) == 0L) {
            openAutoSyncPillWindow()
        }
        autoSyncLadderIdx = 0
        autoSyncLadderDone = false
        val tick = object : Runnable {
            override fun run() {
                if (autoSyncLadderDone || !externalSubtitleActive) return
                val tap = speechTap
                if (tap != null && !autoSyncRunning &&
                    SubtitleSettings.getSyncOffsetMs(this@AndroidTvTorrentPlayerActivity) == 0L &&
                    autoSyncLadderIdx < autoSyncLadderSec.size &&
                    tap.anchoredDurationMs() >= autoSyncLadderSec[autoSyncLadderIdx] * 1000.0
                ) {
                    autoSyncLadderIdx++
                    android.util.Log.d("AutoSync", "ladder attempt ${autoSyncLadderIdx}/${autoSyncLadderSec.size}")
                    runSubtitleAutoSync(auto = true)
                }
                if (!autoSyncLadderDone && autoSyncLadderIdx < autoSyncLadderSec.size) {
                    externalSubtitleHandler.postDelayed(this, 8_000)
                }
            }
        }
        autoSyncLadderTick = tick
        externalSubtitleHandler.postDelayed(tick, 8_000)
    }

    private fun cancelAutoSyncLadder() {
        autoSyncLadderTick?.let { externalSubtitleHandler.removeCallbacks(it) }
        autoSyncLadderTick = null
        autoSyncLadderDone = true
    }

    private fun scheduleAutoSyncVerify() {
        cancelAutoSyncVerify()
        if (!isAutoSyncPrefEnabled()) return
        val tick = object : Runnable {
            override fun run() {
                maybeRunAutoSyncVerify()
                if (autoSyncVerifyTick === this) {
                    externalSubtitleHandler.postDelayed(this, 120_000)
                }
            }
        }
        autoSyncVerifyTick = tick
        externalSubtitleHandler.postDelayed(tick, 90_000)
    }

    private fun cancelAutoSyncVerify() {
        autoSyncVerifyTick?.let { externalSubtitleHandler.removeCallbacks(it) }
        autoSyncVerifyTick = null
        autoSyncVerifyMisses = 0
    }

    /**
     * Re-check the region the user is CURRENTLY watching against the offset
     * we applied. Cues ride in pre-shifted by that offset, so a still-correct
     * sync correlates at lag 0 and any confident peak IS the residual to add.
     * Two confident-audio misses escalate the residual search from ±10s to
     * the full width over the same recent window — the ad-break/cut case,
     * where timing jumps too far for the narrow check to see.
     */
    private fun maybeRunAutoSyncVerify() {
        val applied = autoSyncAppliedOffsetMs ?: return
        if (!externalSubtitleActive || autoSyncRunning) return
        if (player?.isPlaying != true) return
        if (SubtitleSettings.getSyncOffsetMs(this) != applied) {
            // The user dialed something since — their hand wins, permanently.
            cancelAutoSyncVerify()
            return
        }
        val tap = speechTap ?: return
        val url = activeExternalSubtitleUrl ?: return
        val rawCues = SubtitleCueCache.get(url) ?: return
        val pos = player?.currentPosition ?: return
        val windowStart = pos - 360_000
        val segments = tap.snapshot().filter {
            it.anchorMs != Long.MIN_VALUE &&
                it.anchorMs + it.durationMs >= windowStart &&
                it.anchorMs <= pos + 10_000
        }
        if (segments.sumOf { it.durationMs } < 30_000.0) return
        autoSyncRunning = true
        subtitleScope.launch {
            val escalated = autoSyncVerifyMisses >= 2
            val result = try {
                val centered = rawCues.map {
                    CueSpan(it.startMs + applied, it.endMs + applied, it.text)
                }
                withContext(Dispatchers.Default) {
                    if (escalated) {
                        SubtitleAligner.align(segments, centered)
                    } else {
                        SubtitleAligner.align(
                            segments, centered,
                            searchMs = 10_000.0,
                            minAudioMs = 25_000.0,
                            minCueOverlapFrames = SubtitleAligner.Tuning.NARROW_MIN_CUE_OVERLAP_FRAMES,
                            minCues = SubtitleAligner.Tuning.NARROW_MIN_CUES,
                            minZPeak = SubtitleAligner.Tuning.NARROW_MIN_ZPEAK,
                            minPsr = SubtitleAligner.Tuning.NARROW_MIN_PSR,
                            scales = doubleArrayOf(1.0),
                        )
                    }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                android.util.Log.e("AutoSync", "verify failed", e)
                AlignResult.NoMatch(0)
            } finally {
                autoSyncRunning = false
            }
            if (activeExternalSubtitleUrl != url || autoSyncAppliedOffsetMs != applied) return@launch
            when (result) {
                is AlignResult.Synced -> {
                    autoSyncVerifyMisses = 0
                    if (kotlin.math.abs(result.offsetMs) > 400) {
                        val newOffset = applied + result.offsetMs
                        SubtitleSettings.setSyncOffsetMs(this@AndroidTvTorrentPlayerActivity, newOffset)
                        applySubtitleSettings()
                        autoSyncAppliedOffsetMs = newOffset
                        autoSyncResultLabel = "✓ ${SubtitleSettings.formatSyncOffset(newOffset)}"
                        autoSyncResultUrl = url
                        android.util.Log.d("AutoSync", "verify re-synced $applied -> $newOffset (escalated=$escalated)")
                        showSyncToast(
                            "↻", AutoSyncColors.OK,
                            "Re-synced",
                            autoHideMs = 3_000,
                        )
                    } else {
                        android.util.Log.d("AutoSync", "verify confirmed $applied (residual ${result.offsetMs}ms)")
                    }
                }
                is AlignResult.NoMatch -> {
                    autoSyncVerifyMisses++
                    android.util.Log.d("AutoSync", "verify miss ${autoSyncVerifyMisses}: $result")
                }
                else -> {
                    // NotEnoughAudio / Drift: wait for more playback; a miss
                    // count here would escalate on silence, not on evidence.
                    android.util.Log.d("AutoSync", "verify skipped: $result")
                }
            }
        }
    }

    /**
     * Settings → Playback → "Auto-sync addon subtitles" (Flutter-side pref).
     *
     * OFF by default — experimental opt-in. Must stay in lock-step with the
     * Dart default in StorageService.getSubtitleAutoSyncEnabled, or an
     * untouched toggle would mean different things on the two sides.
     */
    private fun isAutoSyncPrefEnabled(): Boolean =
        com.debrify.app.profiles.ProfilePreferenceProjection.getBoolean(
            this,
            "subtitle_auto_sync_enabled",
            false,
        )

    private fun umSearchRows(): List<UnifiedMenuController.Row> {
        if (pendingSeriesResult != null) {
            return listOf(
                mrow("Season  ◀ ▶", value = "$pendingSeason", adjustable = true,
                    onAdjust = { d -> pendingSeason = (pendingSeason + d).coerceIn(1, 99) }),
                mrow("Episode  ◀ ▶", value = "$pendingEpisode", adjustable = true,
                    onAdjust = { d -> pendingEpisode = (pendingEpisode + d).coerceIn(1, 999) }),
                mrow("Fetch subtitles", accent = true, onOk = {
                    val r = pendingSeriesResult
                    pendingSeriesResult = null
                    if (r != null) applyManualSubtitleIdentity(r, pendingSeason, pendingEpisode)
                    unifiedMenu?.hide()
                })
            )
        }
        val rows = mutableListOf<UnifiedMenuController.Row>()
        if (subtitleSearchStatus.isNotEmpty()) rows.add(mrow(subtitleSearchStatus, enabled = false))
        for (r in subtitleSearchResults) {
            rows.add(mrow(r.titleLine(), value = r.detailLine(), onOk = { umPickSearchResult(r) }))
        }
        return rows
    }

    private fun umPickSearchResult(r: SubtitleCatalogResult) {
        if (r.type == "series") {
            val se = getCurrentSubtitleSearchItem()?.let { resolveSeasonEpisodeForSubtitle(it) }
            if (se != null) {
                applyManualSubtitleIdentity(r, se.season, se.episode)
                unifiedMenu?.hide()
            } else {
                val cur = getCurrentSubtitleSearchItem()
                pendingSeriesResult = r
                pendingSeason = (cur?.season ?: manualSubtitleSeason ?: 1).coerceAtLeast(1)
                pendingEpisode = (cur?.episode ?: manualSubtitleEpisode ?: 1).coerceAtLeast(1)
                unifiedMenu?.render()
            }
        } else {
            applyManualSubtitleIdentity(r, null, null)
            unifiedMenu?.hide()
        }
    }

    /** Select an entry from the flat [subtitleTracks] list (Off / embedded) and apply it. */
    private fun umSelectSubtitleRowIndex(rowIndex: Int) {
        if (rowIndex !in subtitleTracks.indices) return
        currentSubtitleTrackIndex = rowIndex
        userManuallySelectedSubtitle = true
        applySelectedSubtitleTrack()
    }

    /** Select an external Stremio subtitle by URL, reusing the battle-tested apply path. */
    private fun umSelectStremioSubtitleByUrl(url: String) {
        rebuildSubtitleTrackList()
        val k = stremioSubtitles.indexOfFirst { it.url == url }
        if (k < 0) return
        var ext = 0
        var rowIdx = -1
        for ((i, pair) in subtitleTracks.withIndex()) {
            if (isExternalSubtitleOption(pair.first)) {
                if (ext == k) { rowIdx = i; break }
                ext++
            }
        }
        if (rowIdx < 0) return
        currentSubtitleTrackIndex = rowIdx
        userManuallySelectedSubtitle = true
        applySelectedSubtitleTrack()
    }

    // ── Sources ─────────────────────────────────────────────────────────────
    private fun umSourceRows(list: List<StremioSource>, emptyLabel: String): MutableList<UnifiedMenuController.Row> {
        if (list.isEmpty()) return mutableListOf(mrow(emptyLabel, enabled = false))
        return list.map { src ->
            val meta = buildString {
                append(src.quality)
                src.formattedSize?.let { append(" · $it") }
                if (!src.isDirectStream && src.seeders > 0) append(" · ${src.seeders}s")
                src.source?.let { append(" · $it") }
            }
            mrow(
                src.displayTitle, value = meta, selected = src.index == currentStremioSourceIndex,
                onOk = { onStremioSourceSelected(src); unifiedMenu?.hide() }
            )
        }.toMutableList()
    }

    /** Appends the tab's "Load more sources" action (or its in-flight Loading
     *  row) when that tab's dedicated fetch hasn't run yet. */
    private fun umAddLoadMoreRow(
        rows: MutableList<UnifiedMenuController.Row>,
        mode: String,
        fetched: Boolean
    ) {
        when {
            moreSourcesLoadingMode == mode ->
                rows.add(mrow("Loading more sources…", enabled = false))
            !fetched ->
                rows.add(mrow("Load more sources", accent = true,
                    onOk = { requestMoreTorrentSources(mode) }))
        }
    }

    private fun umSourcesModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val direct = stremioSources.filter { it.isDirectStream }
        val torrent = stremioSources.filter { !it.isDirectStream }
        val current = stremioSources.getOrNull(currentStremioSourceIndex)

        if (seriesSourceTabs) {
            // Series play: torrent sources split into pack/episode tabs, each
            // with on-demand "Load more" until its dedicated fetch has run.
            val packs = torrent.filter { it.isSeasonPack }
            val episodes = torrent.filter { !it.isSeasonPack }
            val curTorrent = current != null && !current.isDirectStream
            val col2 = listOf(
                mrow("Season packs", value = "${packs.size}", tag = "packs",
                    selected = curTorrent && current!!.isSeasonPack),
                mrow("Episodes", value = "${episodes.size}", tag = "episodes",
                    selected = curTorrent && !current!!.isSeasonPack),
                mrow("Direct", value = "${direct.size}", tag = "direct",
                    selected = current?.isDirectStream == true)
            )
            val tab = col2.getOrNull(col2Index)?.tag ?: "packs"
            val col3 = when (tab) {
                "packs" -> umSourceRows(packs, "No season pack sources")
                    .also { umAddLoadMoreRow(it, "packs", seriesPacksFetched) }
                "episodes" -> umSourceRows(episodes, "No episode sources")
                    .also { umAddLoadMoreRow(it, "episodes", seriesEpisodesFetched) }
                else -> umSourceRows(direct, "No direct sources")
            }
            return UnifiedMenuController.Model(col1, "SOURCES", col2, "Switch source", col3)
        }

        val col2 = listOf(
            mrow("Direct", value = "${direct.size}", tag = "direct", selected = current?.isDirectStream == true),
            mrow("Torrent", value = "${torrent.size}", tag = "torrent", selected = current?.isDirectStream == false)
        )
        val tab = col2.getOrNull(col2Index)?.tag ?: "direct"
        val list = if (tab == "torrent") torrent else direct
        val col3 = umSourceRows(list, "No ${tab} sources").also {
            // Movie flavor: one "Load more sources" on the Torrent tab.
            if (movieMoreSources && tab == "torrent") {
                umAddLoadMoreRow(it, "movie", movieSourcesFetched)
            }
        }
        return UnifiedMenuController.Model(col1, "SOURCES", col2, "Switch source", col3)
    }

    // ── Display ───────────────────────────────────────────────────────────────
    private fun umDisplayModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val col2 = listOf(
            mrow("Aspect ratio", value = resizeModeLabels.getOrNull(resizeModeIndex), tag = "aspect")
        )
        val col3 = resizeModeLabels.mapIndexed { i, l ->
            mrow(l, selected = i == resizeModeIndex, onOk = {
                resizeModeIndex = i.coerceIn(0, resizeModes.lastIndex)
                applyResizeMode()
                updateAspectButtonLabel()
            })
        }
        return UnifiedMenuController.Model(col1, "DISPLAY", col2, "Aspect ratio", col3)
    }

    // ── Playback ────────────────────────────────────────────────────────────
    private fun umPlaybackModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val col2 = listOf(
            mrow("Playback speed", value = playbackSpeedLabels.getOrNull(playbackSpeedIndex), tag = "speed"),
            mrow("Sleep timer", value = sleepTimerValueLabel(), tag = "sleep"),
            mrow("Shuffle & autoplay", tag = "shuffle")
        )
        val tag = col2.getOrNull(col2Index)?.tag
        val (title, col3) = if (tag == "sleep") {
            "Sleep timer" to buildList {
                add(
                    mrow("Off", selected = sleepTimerMode == SleepTimerMode.OFF, onOk = {
                        cancelSleepTimer(announce = true)
                    })
                )
                sleepTimerMinuteOptions.forEach { minutes ->
                    add(mrow("$minutes minutes", onOk = { startSleepCountdown(minutes) }))
                }
                // A live channel has no end to stop at, so only the countdown
                // applies there — which is the case people actually want it for.
                if (iptvChannels.getOrNull(currentIptvIndex)?.isLive != true) {
                    add(
                        mrow(
                            "End of episode",
                            selected = sleepTimerMode == SleepTimerMode.END_OF_ITEM,
                            onOk = { armSleepAtEndOfItem() }
                        )
                    )
                }
            }
        } else if (tag == "shuffle") {
            "Shuffle & autoplay" to listOf(
                mrow("Play random once", accent = true, onOk = {
                    continuousShuffleEnabled = false; shuffleBag.clear(); playRandom(); unifiedMenu?.hide()
                }),
                mrow("Shuffle continuously", value = if (continuousShuffleEnabled) "On" else "Off",
                    selected = continuousShuffleEnabled, onOk = {
                        val turningOn = !continuousShuffleEnabled
                        continuousShuffleEnabled = turningOn
                        shuffleBag.clear()
                        Toast.makeText(
                            this, if (turningOn) "Continuous shuffle on" else "Continuous shuffle off",
                            Toast.LENGTH_SHORT
                        ).show()
                        if (turningOn) { playRandom(); unifiedMenu?.hide() }   // jump to a random item now
                    })
            )
        } else {
            "Playback speed" to playbackSpeedLabels.mapIndexed { i, l ->
                mrow(l, selected = i == playbackSpeedIndex, onOk = {
                    playbackSpeedIndex = i.coerceIn(0, playbackSpeeds.lastIndex)
                    player?.setPlaybackSpeed(playbackSpeeds[playbackSpeedIndex])
                })
            }
        }
        return UnifiedMenuController.Model(col1, "PLAYBACK", col2, title, col3)
    }

    private fun showAudioTrackDialog() {
        val ts = trackSelector ?: return
        val tracks = player?.currentTracks ?: return

        val audioTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()
        audioTracks.add(Pair("Off", null))

        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_AUDIO) {
                for (i in 0 until group.length) {
                    val format = group.getTrackFormat(i)
                    val label = buildAudioTrackLabel(format)
                    val override = TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                    audioTracks.add(Pair(label, override))
                }
            }
        }

        if (audioTracks.size <= 1) {
            Toast.makeText(this, "No audio tracks available", Toast.LENGTH_SHORT).show()
            return
        }

        val labels = audioTracks.map { it.first }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Select Audio Track")
            .setItems(labels) { _, which ->
                val override = audioTracks[which].second
                val params = ts.parameters.buildUpon()
                if (override != null) {
                    params.setOverrideForType(override)
                    params.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                } else {
                    params.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                }
                ts.parameters = params.build()
                // Series: remember this language for later episodes + sessions.
                onIptvSeriesAudioPicked(languageOfOverride(override))
            }
            .show()
    }

    private fun showSubtitleTrackDialog() {
        val ts = trackSelector ?: return
        val tracks = player?.currentTracks ?: return

        val subtitleTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()
        subtitleTracks.add(Pair("Off", null))

        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_TEXT) {
                for (i in 0 until group.length) {
                    val format = group.getTrackFormat(i)
                    val label = buildSubtitleTrackLabel(format)
                    val override = TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                    subtitleTracks.add(Pair(label, override))
                }
            }
        }

        if (subtitleTracks.size <= 1) {
            Toast.makeText(this, "No subtitle tracks available", Toast.LENGTH_SHORT).show()
            return
        }

        val labels = subtitleTracks.map { it.first }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Select Subtitle Track")
            .setItems(labels) { _, which ->
                val override = subtitleTracks[which].second
                val params = ts.parameters.buildUpon()
                if (override != null) {
                    params.setOverrideForType(override)
                    params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                } else {
                    params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                }
                ts.parameters = params.build()
            }
            .show()
    }

    private fun buildAudioTrackLabel(format: Format): String {
        val lang = format.language ?: "und"
        val label = format.label
        val channels = if (format.channelCount != Format.NO_VALUE) "${format.channelCount}ch" else ""
        val bitrate = if (format.bitrate != Format.NO_VALUE) "${format.bitrate / 1000}kbps" else ""

        val parts = mutableListOf<String>()
        if (!label.isNullOrEmpty()) parts.add(label)
        else parts.add(lang.uppercase(Locale.getDefault()))
        if (channels.isNotEmpty()) parts.add(channels)
        if (bitrate.isNotEmpty()) parts.add(bitrate)

        return parts.joinToString(" · ")
    }

    private fun buildSubtitleTrackLabel(format: Format): String {
        val lang = format.language ?: "und"
        val label = format.label

        return if (!label.isNullOrEmpty()) {
            "$label ($lang)"
        } else {
            lang.uppercase(Locale.getDefault())
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUBTITLE SETTINGS PANEL
    // ═══════════════════════════════════════════════════════════════════════════

    private fun rebuildSubtitleTrackList() {
        subtitleTracks.clear()
        subtitleTracks.add(Pair("Off", null))
        currentSubtitleTrackIndex = 0

        val tracks = player?.currentTracks
        if (tracks != null) {
            for (group in tracks.groups) {
                if (group.type == C.TRACK_TYPE_TEXT) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)
                        val label = buildSubtitleTrackLabel(format)
                        val override = TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                        subtitleTracks.add(Pair(label, override))

                        // Check if this track is currently selected
                        if (group.isTrackSelected(i)) {
                            currentSubtitleTrackIndex = subtitleTracks.size - 1
                        }
                    }
                }
            }
        }

        // Add Stremio external subtitles to the track list
        // These are marked with "⬇" prefix to indicate they're external/downloadable
        for ((index, sub) in stremioSubtitles.withIndex()) {
            val label = "$EXTERNAL_SUBTITLE_PREFIX ${sub.displayName} (${sub.source})"
            // Use null override to indicate this is an external subtitle
            subtitleTracks.add(Pair(label, null))

            // Check if this Stremio subtitle is currently selected
            if (currentStremioSubtitleIndex == index) {
                currentSubtitleTrackIndex = subtitleTracks.lastIndex
            }
        }

        // Add loading indicator if still fetching Stremio subtitles
        if (isLoadingStremioSubtitles) {
            subtitleTracks.add(Pair(SUBTITLE_LOADING_LABEL, null))
        }

        // Check if no subtitle is currently selected (means "Off")
        val hasSelectedSubtitle = tracks?.groups?.any { group ->
            group.type == C.TRACK_TYPE_TEXT && (0 until group.length).any { group.isTrackSelected(it) }
        } ?: false
        if (!hasSelectedSubtitle && currentStremioSubtitleIndex < 0) {
            currentSubtitleTrackIndex = 0
        }
    }

    private val subtitlePanelCallbacks = object : SubtitlePanelController.Callbacks {
        override fun getTrackLabels(): List<String> = subtitleTracks.map { it.first }
        override fun getCurrentTrackIndex(): Int = currentSubtitleTrackIndex
        override fun selectTrack(index: Int) {
            val label = subtitleTracks.getOrNull(index)?.first ?: return
            if (isLoadingSubtitleOption(label)) return
            if (isSearchSubtitleOption(label)) {
                showSearchSubtitleDialog()
                return
            }
            currentSubtitleTrackIndex = index
            userManuallySelectedSubtitle = true
            applySelectedSubtitleTrack()
        }
        override fun onSearchSubtitle() { showSearchSubtitleDialog() }
        override fun getIdentityLabel(): String = currentSubtitleIdentityLabel()
        override fun onSettingsChanged() { applyAndPersistSubtitleSettings() }
        override fun onSyncOverlayRequested() { showSyncOverlay() }
        override fun onHidden() {
            subtitleSettingsVisible = false
            if (::playerView.isInitialized) playerView.requestFocus()
        }
    }

    private fun showSubtitleSettingsPanel() {
        rebuildSubtitleTrackList()
        subtitlePanel?.show()
        subtitleSettingsVisible = true
    }

    private fun hideSubtitleSettingsPanel() {
        subtitlePanel?.hide() ?: run { subtitleSettingsVisible = false }
    }

    private fun showSyncOverlay() {
        val root = findViewById<ViewGroup>(android.R.id.content)?.getChildAt(0) as? ViewGroup ?: return

        // Use line picker for external (Stremio) subtitles. Prefer the actually-
        // rendering URL: a per-addon retry can transiently drop the current sub's
        // URL from the flat list (currentStremioSubtitleIndex → -1) while it's still
        // on screen, and we must not fall through to the embedded slider for it.
        val externalUrl = activeExternalSubtitleUrl?.takeIf { externalSubtitleActive }
            ?: stremioSubtitles.getOrNull(currentStremioSubtitleIndex)?.url
        if (externalUrl != null) {
            if (linePickerOverlay == null) {
                linePickerOverlay = SubtitleLinePickerController(
                    activity = this,
                    rootContainer = root,
                    getCurrentPositionMs = { player?.currentPosition ?: 0L },
                    onOffsetApplied = { applySubtitleSettings() },
                    onDismissed = Runnable {
                        linePickerOverlay = null
                        if (::playerView.isInitialized) playerView.requestFocus()
                    }
                )
            }
            linePickerOverlay?.show(externalUrl)
            return
        }

        // Fall back to slider for embedded subtitles
        if (syncOverlay == null) {
            syncOverlay = SubtitleSyncOverlayController(
                activity = this,
                rootContainer = root,
                onSettingsChanged = Runnable { applySubtitleSettings() },
                onDismissed = Runnable { if (::playerView.isInitialized) playerView.requestFocus() }
            )
        }
        syncOverlay?.show()
    }

    /**
     * Refresh subtitle panel to update loading state / loaded subtitles.
     * Re-collects tracks and updates UI without changing visibility or focus.
     */
    private fun refreshSubtitlePanelForLoading() {
        rebuildSubtitleTrackList()
        subtitlePanel?.refresh()
    }

    private fun isSearchSubtitleOption(label: String): Boolean {
        return label == SEARCH_SUBTITLE_LABEL
    }

    private fun isLoadingSubtitleOption(label: String): Boolean {
        return label.startsWith("⏳")
    }

    private fun isExternalSubtitleOption(label: String): Boolean {
        return label.startsWith(EXTERNAL_SUBTITLE_PREFIX)
    }

    private fun applySelectedSubtitleTrack() {
        val ts = trackSelector ?: return
        val selectedTrack = subtitleTracks.getOrNull(currentSubtitleTrackIndex)
        val label = selectedTrack?.first ?: ""
        val override = selectedTrack?.second

        // Check if this is a Stremio external subtitle (marked with ⬇ prefix)
        if (isSearchSubtitleOption(label)) {
            showSearchSubtitleDialog()
            return
        }

        if (isExternalSubtitleOption(label)) {
            // Calculate the Stremio subtitle index without assuming where utility rows live.
            val stremioIndex = subtitleTracks
                .take(currentSubtitleTrackIndex)
                .count { isExternalSubtitleOption(it.first) }

            if (stremioIndex >= 0 && stremioIndex < stremioSubtitles.size) {
                // Disable embedded subtitles first
                val params = ts.parameters.buildUpon()
                    .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                ts.parameters = params.build()

                // Load Stremio subtitle
                loadStremioSubtitle(stremioSubtitles[stremioIndex])
                currentStremioSubtitleIndex = stremioIndex
            }
            return
        }

        // Clear Stremio subtitle selection and stop any side-rendered subtitle
        currentStremioSubtitleIndex = -1
        stopExternalSubtitleRendering()

        // Handle embedded subtitle selection
        val params = ts.parameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
        if (override != null) {
            params.setOverrideForType(override)
            params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
        } else {
            params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        }
        ts.parameters = params.build()
        // Selecting a different embedded subtitle (or Off) resets the sync offset:
        // it was calibrated for the previous subtitle. Do it explicitly rather
        // than via an identity-scoped read — player.currentTracks hasn't updated
        // to the new selection yet, so a read here would be stale, and embedded
        // subs carry the offset at the (push-based) renderer level. This also
        // prevents a same-language embedded track from inheriting a sibling
        // track's offset through the folded "emb" identity.
        SubtitleSettings.resetSyncOffset()
        offsetRenderersFactory?.setOffsetUs(0L)
    }

    /**
     * True if this subtitle URL is a format the on-device parser can render.
     * TTML/DFXP were handled by ExoPlayer's decoder in the old re-prepare path
     * but our SubtitleCueParser can't parse them (they'd yield zero cues and
     * fail the load), so they're filtered out of the offered list entirely.
     */
    private fun isSideRenderableSubtitle(url: String): Boolean {
        val path = url.substringBefore("?").lowercase()
        return !path.endsWith(".ttml") && !path.endsWith(".dfxp")
    }

    /**
     * Load an external Stremio subtitle by side-rendering it: the file is
     * downloaded + parsed off-thread and cues are fed to subtitleOverlay from
     * a position ticker. The player source is never rebuilt, so playback is
     * never interrupted — no re-prepare, no rebuffer, no resume/seek juggling.
     */
    private fun loadStremioSubtitle(subtitle: StremioSubtitle) {
        val loadToken = ++externalSubtitleLoadToken
        // Capture the currently-*rendering* external selection so a failed load
        // can fall back to it instead of tearing down a working subtitle. At
        // this point currentStremioSubtitleIndex still holds the previous value
        // (callers overwrite it only after this returns), but only trust it when
        // a subtitle is actually active — otherwise the previous pick was still
        // downloading (and will be discarded by the token check), so there's
        // nothing real to fall back to.
        val previousStremioIndex = if (externalSubtitleActive) currentStremioSubtitleIndex else -1
        showStatusPill("Loading ${subtitle.displayName}…")

        val cached = SubtitleCueCache.get(subtitle.url)
        if (cached != null) {
            onExternalSubtitleLoaded(subtitle, cached, previousStremioIndex)
            return
        }

        subtitleScope.launch {
            val parsed = withContext(Dispatchers.IO) { SubtitleCueCache.fetch(subtitle.url) }
            // Stale if the user picked another subtitle or content changed meanwhile
            if (loadToken != externalSubtitleLoadToken) return@launch
            onExternalSubtitleLoaded(subtitle, parsed, previousStremioIndex)
        }
    }

    private fun onExternalSubtitleLoaded(
        subtitle: StremioSubtitle,
        cues: List<SubtitleCue>,
        previousStremioIndex: Int
    ) {
        if (cues.isEmpty()) {
            android.util.Log.w("StremioSubs", "Failed to load/parse external subtitle: ${subtitle.url}")
            failedSubtitleUrls.add(subtitle.url)   // don't auto-select this broken sub again
            showStatusPillTransient("Couldn't load ${subtitle.displayName}")
            // Keep whatever was rendering before — do NOT stopExternalSubtitleRendering()
            // here (it would wipe a working subtitle and cancel the error pill).
            // Just restore the selection state to the previously-good subtitle.
            currentStremioSubtitleIndex = previousStremioIndex
            if (previousStremioIndex < 0) {
                // Nothing external was active before; the selecting caller already
                // disabled embedded text tracks in anticipation. Re-enable so
                // ExoPlayer can restore an embedded subtitle.
                trackSelector?.let { ts ->
                    ts.parameters = ts.parameters.buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                        .build()
                }
            }
            if (subtitleSettingsVisible) refreshSubtitlePanelForLoading()
            return
        }

        // Disable embedded text tracks so they don't double-render under the
        // side-loaded cues (covers the auto-select path, which doesn't go
        // through applySelectedSubtitleTrack).
        trackSelector?.let { ts ->
            ts.parameters = ts.parameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
        }

        externalSubtitleCues = cues
        externalSubtitleActive = true
        activeExternalSubtitleUrl = subtitle.url
        lastExternalCueText = null
        // Clear immediately: disabling the embedded track fires onCues(empty),
        // but that's now suppressed, and the first ticker render early-returns
        // when no cue is active — without this a stale embedded line would
        // freeze on screen until the next external cue.
        if (::subtitleOverlay.isInitialized) subtitleOverlay.setCues(emptyList())
        startExternalSubtitleTicker()
        // Remembered sync for this exact content+subtitle (keyed by the same
        // identity that scopes the live offset): restore BEFORE the ladder
        // arms — a non-zero recall parks the ladder via its own offset==0
        // gate. Announced: an offset appearing out of nowhere must say why.
        val recalledIdentity = currentSubtitleIdentity()
        val recalled = recalledIdentity?.let { SubtitleSettings.recallSyncOffset(this, it) }
        if (recalled != null) {
            SubtitleSettings.setSyncOffsetMs(this, recalled)
            // Same initialized-guard the overlay clear above uses: the side
            // ticker reads the offset at lookup time anyway, so on a very
            // early load the apply can be safely skipped rather than touch a
            // lateinit view.
            if (::subtitleOverlay.isInitialized) applySubtitleSettings()
            autoSyncResultLabel = "↻ ${SubtitleSettings.formatSyncOffset(recalled)}"
            autoSyncResultUrl = subtitle.url
            autoSyncAppliedOffsetMs = recalled
            scheduleAutoSyncVerify()
            showSyncToast(
                "↻", AutoSyncColors.OK,
                "Sync restored",
                autoHideMs = 3_000,
            )
        }
        startAutoSyncLadder()
        showStatusPillTransient("✓ ${subtitle.displayName}")
        android.util.Log.d("StremioSubs", "Side-rendering ${cues.size} cues from ${subtitle.displayName}")
    }

    /** Stop side-rendering and give the overlay back to the player's onCues. */
    private fun stopExternalSubtitleRendering() {
        cancelAutoSyncLadder()
        cancelAutoSyncVerify()
        autoSyncAppliedOffsetMs = null
        externalSubtitleLoadToken++
        externalSubtitleTicker?.let { externalSubtitleHandler.removeCallbacks(it) }
        externalSubtitleTicker = null
        if (externalSubtitleActive || externalSubtitleCues.isNotEmpty()) {
            externalSubtitleActive = false
            activeExternalSubtitleUrl = null
            externalSubtitleCues = emptyList()
            lastExternalCueText = null
            if (::subtitleOverlay.isInitialized) subtitleOverlay.setCues(emptyList())
            // Re-enable the embedded text track type that onExternalSubtitleLoaded
            // disabled — otherwise embedded-subtitle auto-selection stays dead for
            // every subsequent item. Callers that want text off (Off selection)
            // re-apply their own params right after this returns.
            trackSelector?.let { ts ->
                ts.parameters = ts.parameters.buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                    .build()
            }
        }
        hideStatusPill()
    }

    private fun startExternalSubtitleTicker() {
        externalSubtitleTicker?.let { externalSubtitleHandler.removeCallbacks(it) }
        val ticker = object : Runnable {
            override fun run() {
                if (!externalSubtitleActive) return
                renderExternalSubtitleCue()
                externalSubtitleHandler.postDelayed(this, EXTERNAL_SUBTITLE_TICK_MS)
            }
        }
        externalSubtitleTicker = ticker
        ticker.run()
    }

    private fun renderExternalSubtitleCue() {
        val cues = externalSubtitleCues
        if (cues.isEmpty()) return
        // Same convention as the sync line picker: a positive offset means the
        // subtitle text lags the audio, so we look up cues at (position - offset).
        val effectiveMs = (player?.currentPosition ?: return) - SubtitleSettings.getSyncOffsetMs(this)

        // Binary search for the last cue starting at or before effectiveMs,
        // then collect all still-active overlapping cues. Cues are sorted only
        // by start time, so a long-running cue (e.g. an anime sign/song event)
        // can begin many entries before the current dialogue line — scan the
        // whole prefix (cheap: a few thousand comparisons a few times a second).
        var lo = 0
        var hi = cues.size - 1
        var last = -1
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            if (cues[mid].startMs <= effectiveMs) { last = mid; lo = mid + 1 } else hi = mid - 1
        }

        var text: String? = null
        if (last >= 0) {
            val active = StringBuilder()
            for (i in 0..last) {
                val cue = cues[i]
                if (cue.startMs <= effectiveMs && effectiveMs < cue.endMs) {
                    if (active.isNotEmpty()) active.append('\n')
                    active.append(cue.text)
                }
            }
            if (active.isNotEmpty()) text = active.toString()
        }

        if (text == lastExternalCueText) return
        lastExternalCueText = text
        subtitleOverlay.setCues(
            if (text == null) emptyList()
            else listOf(Cue.Builder().setText(text).build())
        )
    }

    // ── Status pill ──────────────────────────────────────────────────────────
    // Small bottom-center chip for transient progress feedback that must not
    // touch playback: external subtitle downloads and source switches.

    private fun ensureStatusPill(): TextView {
        statusPill?.let { return it }
        val pill = TextView(this).apply {
            textSize = 13f
            setTextColor(Color.WHITE)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            background = GradientDrawable().apply {
                setColor(0xD9101014.toInt())
                cornerRadius = dp(18).toFloat()
                setStroke(dp(1), 0x33FFFFFF)
            }
            setPadding(dp(16), dp(8), dp(16), dp(8))
            elevation = dp(240).toFloat()
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).also { it.bottomMargin = dp(48) }
        }
        findViewById<ViewGroup>(android.R.id.content).addView(pill)
        statusPill = pill
        return pill
    }

    private fun showStatusPill(message: String) {
        externalSubtitleHandler.removeCallbacks(statusPillHideRunnable)
        val pill = ensureStatusPill()
        pill.text = message
        if (pill.visibility != View.VISIBLE) {
            pill.alpha = 0f
            pill.visibility = View.VISIBLE
        }
        pill.animate().cancel()
        pill.animate().alpha(1f).setDuration(180).start()
    }

    /** Show a short confirmation/error message, then fade the pill away. */
    private fun showStatusPillTransient(message: String) {
        showStatusPill(message)
        externalSubtitleHandler.postDelayed(statusPillHideRunnable, 1400)
    }

    private fun hideStatusPill() {
        externalSubtitleHandler.removeCallbacks(statusPillHideRunnable)
        val pill = statusPill ?: return
        if (pill.visibility != View.VISIBLE) return
        pill.animate().cancel()
        pill.animate().alpha(0f).setDuration(220).withEndAction {
            pill.visibility = View.GONE
        }.start()
    }

    // ── Auto-sync countdown pill ─────────────────────────────────────────────
    // The quiet bottom-right status pill (design/mockups/
    // subtitle_auto_sync_hint_mockup/countdown_devices.html, same component as
    // the Dart player's AutoSyncPill): a draining 90-second ring + tracked
    // uppercase label + tabular seconds while listening; colored glyph + label
    // for results. Display-only, never focusable, anchored inside the overscan
    // safe area. Numbers never appear in result states — offsets and hints
    // live in logcat (adb logcat -s AutoSync).

    private object AutoSyncColors {
        const val OK = 0xFF82E0AD.toInt() // pill green — synced / restored
        const val FAIL = 0xFFE8C07B.toInt() // pill amber — declined, never alarming
        const val BUSY = 0xFF7BDCFF.toInt() // pill cyan — listening / checking
    }

    /** The pill's leading glyph: a heartbeat — pulsing halo around a dot. */
    private inner class AutoSyncRingView(context: android.content.Context) : View(context) {
        var arcColor = AutoSyncColors.BUSY
            set(value) { field = value; invalidate() }
        private var pulse = 0f
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1_800
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                pulse = it.animatedValue as Float
                invalidate()
            }
        }

        /**
         * Explicit, not attach-driven: the view lives on the content view for
         * the whole activity, so an always-on animator would invalidate every
         * frame forever after the first show — even while the pill is GONE.
         */
        fun setPulsing(on: Boolean) {
            if (on) {
                if (!pulseAnimator.isStarted) pulseAnimator.start()
            } else if (pulseAnimator.isStarted) {
                pulseAnimator.cancel()
                pulse = 0f
                invalidate()
            }
        }

        override fun onDetachedFromWindow() {
            pulseAnimator.cancel()
            super.onDetachedFromWindow()
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val cx = w / 2f
            val cy = height / 2f
            val r = w / 2f
            if (pulse > 0f) {
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = w * 0.14f
                paint.color = arcColor
                paint.alpha = (82 * (1f - pulse)).toInt()
                canvas.drawCircle(cx, cy, r * (0.35f + 0.65f * pulse), paint)
                paint.alpha = 255
            }
            paint.style = Paint.Style.FILL
            paint.color = arcColor
            canvas.drawCircle(cx, cy, r * 0.32f, paint)
        }
    }

    private fun ensureAutoSyncPill(): LinearLayout {
        autoSyncPill?.let { return it }
        val ring = AutoSyncRingView(this)
        val label = TextView(this).apply {
            textSize = 11f
            setTextColor(0xEBFFFFFF.toInt())
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            letterSpacing = 0.08f
            isSingleLine = true
        }
        val pill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(0xA80C0E12.toInt())
                cornerRadius = dp(18).toFloat()
                setStroke(dp(1), 0x21FFFFFF)
            }
            minimumHeight = dp(36)
            setPadding(dp(12), 0, dp(14), 0)
            elevation = dp(240).toFloat()
            visibility = View.GONE
            isFocusable = false
            addView(ring, LinearLayout.LayoutParams(dp(17), dp(17)))
            addView(
                label,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).also { it.marginStart = dp(8) },
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.END
            ).also {
                it.bottomMargin = dp(42)
                it.rightMargin = dp(48)
            }
        }
        findViewById<ViewGroup>(android.R.id.content).addView(pill)
        autoSyncPill = pill
        autoSyncPillRing = ring
        autoSyncPillLabel = label
        return pill
    }

    /**
     * Open the auto-sync window: one plain sentence for ~5 seconds, then the
     * screen stays quiet until a real event — a checking pass or a verdict —
     * has something to say. No countdown, no persistent indicator.
     */
    private fun openAutoSyncPillWindow() {
        stopAutoSyncPillWindow()
        autoSyncPillWindowActive = true
        showSyncToast(
            "●", AutoSyncColors.BUSY,
            "Trying to auto-sync subtitles — this may take a minute, keep watching",
            autoHideMs = null,
            uppercase = false,
        )
        autoSyncPillAnnounceShowing = true
        externalSubtitleHandler.postDelayed(autoSyncPillAnnounceDismissRunnable, 5_000)
    }

    private fun stopAutoSyncPillWindow() {
        externalSubtitleHandler.removeCallbacks(autoSyncPillAnnounceDismissRunnable)
        autoSyncPillAnnounceShowing = false
        autoSyncPillWindowActive = false
    }

    /**
     * Auto-sync status, rendered on the pill. The [glyph] keys the face:
     * "●" = active (pulsing dot + one line), anything else = result (colored
     * glyph + label; the window closes). [hint] is no longer drawn — the pill
     * stays one quiet line — so it goes to logcat instead. [autoHideMs] null
     * keeps the pill up until replaced. [uppercase] false keeps a sentence
     * (the announce line) in its natural case.
     */
    private fun showSyncToast(
        glyph: String,
        accent: Int,
        title: String,
        hint: String? = null,
        autoHideMs: Long?,
        uppercase: Boolean = true,
    ) {
        externalSubtitleHandler.removeCallbacks(autoSyncCardHideRunnable)
        if (hint != null) Log.d("AutoSync", "pill: $title — $hint")
        autoSyncPillAnnounceShowing = false
        val pill = ensureAutoSyncPill()
        val active = glyph == "●"
        autoSyncPillResultShowing = !active
        if (!active) stopAutoSyncPillWindow()
        autoSyncPillRing?.visibility = if (active) View.VISIBLE else View.GONE
        autoSyncPillRing?.setPulsing(active)
        autoSyncPillRing?.arcColor = accent
        pill.setPadding(dp(12), 0, dp(14), 0)
        autoSyncPillLabel?.let { labelView ->
            labelView.visibility = View.VISIBLE
            val text = if (uppercase) title.uppercase() else title
            if (active) {
                labelView.setTextColor(0xEBFFFFFF.toInt())
                labelView.letterSpacing = if (uppercase) 0.08f else 0.01f
                labelView.text = text
            } else {
                labelView.setTextColor(accent)
                labelView.letterSpacing = 0.08f
                labelView.text = "$glyph  $text"
            }
        }
        (pill.background as? GradientDrawable)?.setStroke(
            dp(1),
            if (active) 0x21FFFFFF else (accent and 0x00FFFFFF) or 0x4D000000,
        )
        revealAutoSyncPill()
        if (autoHideMs != null) {
            externalSubtitleHandler.postDelayed(autoSyncCardHideRunnable, autoHideMs)
        }
    }

    private fun revealAutoSyncPill() {
        val pill = autoSyncPill ?: return
        pill.animate().cancel()
        if (pill.visibility != View.VISIBLE) {
            pill.alpha = 0f
            pill.translationY = dp(8).toFloat()
            pill.visibility = View.VISIBLE
        }
        pill.animate().alpha(1f).translationY(0f).setDuration(220).start()
    }

    /** View-only fade; window state is untouched (idle-hide relies on this). */
    private fun hideAutoSyncPillView() {
        autoSyncPillRing?.setPulsing(false)
        val pill = autoSyncPill ?: return
        if (pill.visibility != View.VISIBLE) return
        pill.animate().cancel()
        pill.animate().alpha(0f).translationY(dp(6).toFloat()).setDuration(240).withEndAction {
            pill.visibility = View.GONE
        }.start()
    }

    private fun hideAutoSyncCard() {
        externalSubtitleHandler.removeCallbacks(autoSyncCardHideRunnable)
        stopAutoSyncPillWindow()
        hideAutoSyncPillView()
    }

    /**
     * A stable key for "the subtitle currently on screen", used to scope the
     * sync offset (see SubtitleSettings). It changes whenever the subtitle
     * changes OR the content/episode changes, so the offset — which is only
     * valid for the exact subtitle it was dialed in against — resets by
     * construction. Returns null when no subtitle is showing.
     *
     * The content key is folded in so the same embedded language (or a reused
     * subtitle URL) across two different episodes never shares an offset.
     */
    private fun currentSubtitleIdentity(): String? {
        val contentKey = payload?.items?.getOrNull(currentIndex)?.resumeId ?: "idx:$currentIndex"
        if (externalSubtitleActive) {
            val url = activeExternalSubtitleUrl ?: return null
            return "$contentKey|ext:$url"
        }
        // Fold all embedded text tracks into a single "emb" identity: switching
        // between embedded tracks of the SAME episode keeping the offset is an
        // acceptable edge; the offset only needs to reset across episodes (the
        // content key handles that) and across the external⇄embedded boundary.
        val embeddedSelected = player?.currentTracks?.groups?.any { group ->
            group.type == C.TRACK_TYPE_TEXT && (0 until group.length).any { group.isTrackSelected(it) }
        } ?: false
        return if (embeddedSelected) "$contentKey|emb" else null
    }

    private fun applySubtitleSettings() {
        subtitleOverlay.setFixedTextSize(
            TypedValue.COMPLEX_UNIT_SP,
            SubtitleSettings.getFontSizeSp(this)
        )
        subtitleOverlay.setStyle(SubtitleSettings.buildCaptionStyle(this))
        subtitleOverlay.setBottomPaddingFraction(SubtitleSettings.getElevationPaddingFraction(this))
        // Only carry an offset onto the renderer when a subtitle is actually on
        // screen. Dialing the slider with subtitles off stores an offset under a
        // null owner (so the slider stays live), but it must NOT be pushed to the
        // renderer — otherwise a later auto-selected subtitle, which doesn't pass
        // through the selection reset, would render shifted while the read is 0.
        val hasSubtitle = currentSubtitleIdentity() != null
        val newOffsetUs = if (hasSubtitle) SubtitleSettings.getSyncOffsetMs(this) * 1000L else 0L
        val oldOffsetUs = offsetRenderersFactory?.currentOffsetUs ?: 0L
        offsetRenderersFactory?.setOffsetUs(newOffsetUs)
        if (externalSubtitleActive) {
            // Side-rendered subtitles pick the offset up at lookup time — just
            // force an immediate re-render, no seek needed.
            lastExternalCueText = null
            renderExternalSubtitleCue()
        } else if (newOffsetUs != oldOffsetUs) {
            // Debounce: rapid offset changes (line picker tap, arrow key hold)
            // would otherwise pile up seeks and confuse the text renderer.
            subtitleSeekHandler.removeCallbacks(subtitleSeekRunnable)
            subtitleSeekHandler.postDelayed(subtitleSeekRunnable, 150)
        }
    }

    private fun applyAndPersistSubtitleSettings() {
        applySubtitleSettings()
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "saveSubtitleAppearance",
            SubtitleSettings.profileAppearanceSnapshot(this),
        )
    }

    // Aspect ratio
    private fun cycleAspectRatio() {
        resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size
        applyResizeMode()
        updateAspectButtonLabel()
        Toast.makeText(this, "Aspect: ${resizeModeLabels[resizeModeIndex]}", Toast.LENGTH_SHORT).show()
    }

    private fun applyResizeMode() {
        playerView.resizeMode = resizeModes[resizeModeIndex]
        val content = playerView.findViewById<View>(androidx.media3.ui.R.id.exo_content_frame)
            ?: playerView.videoSurfaceView
        val scale = if (resizeModeIndex == 3) 4f / 3f else 1f
        content?.scaleX = scale
        content?.scaleY = scale
    }

    // Playback speed
    private fun cyclePlaybackSpeed() {
        playbackSpeedIndex = (playbackSpeedIndex + 1) % playbackSpeeds.size
        val speed = playbackSpeeds[playbackSpeedIndex]
        player?.setPlaybackSpeed(speed)
        Toast.makeText(this, "Speed: ${playbackSpeedLabels[playbackSpeedIndex]}", Toast.LENGTH_SHORT).show()
    }

    /**
     * Announce ExoPlayer's current audio session to system audio-effect apps
     * (Wavelet, OEM equalizers) so they can attach, the same way they do for
     * other video apps. Idempotent — AudioEffectSession ignores a re-announce
     * of the session already open and closes the previous one otherwise.
     */
    private fun syncAudioEffectSession(sessionId: Int? = null) {
        if (!systemAudioEffectsEnabled) return
        // Prefer the id the callback handed us over re-reading the player,
        // which may not have published the new one yet.
        val audioSessionId = sessionId ?: player?.audioSessionId ?: return
        if (audioSessionId == 0) return  // Renderer not live yet
        com.debrify.app.audio.AudioEffectSession.open(this, audioSessionId)
    }

    // Night mode (dynamic range compression)
    private fun initializeLoudnessEnhancer() {
        try {
            val audioSessionId = player?.audioSessionId ?: return
            if (audioSessionId == 0) return  // Invalid session

            releaseLoudnessEnhancer()  // Clean up any existing instance

            loudnessEnhancer = LoudnessEnhancer(audioSessionId)
            loudnessEnhancer?.enabled = nightModeIndex > 0
            if (nightModeIndex > 0) {
                loudnessEnhancer?.setTargetGain(nightModeGains[nightModeIndex])
            }
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Failed to initialize LoudnessEnhancer", e)
            loudnessEnhancer = null
        }
    }

    private fun releaseLoudnessEnhancer() {
        try {
            loudnessEnhancer?.release()
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Error releasing LoudnessEnhancer", e)
        }
        loudnessEnhancer = null
    }

    /**
     * Load default player settings from Flutter's SharedPreferences.
     * Keys are prefixed with "flutter." as per flutter shared_preferences package.
     */
    private fun loadPlayerDefaults() {
        try {
            // Load aspect index for TV (separate from mobile)
            // TV only: 0=Fit, 1=Fill, 2=Zoom, 3=Cinema Zoom (default: 0=Fit)
            resizeModeIndex = com.debrify.app.profiles.ProfilePreferenceProjection
                .getLong(this, "player_default_aspect_index_tv", 0L).toInt()
                .coerceIn(0, resizeModes.lastIndex)

            // Load night mode index (default: 0 = Off)
            nightModeIndex = com.debrify.app.profiles.ProfilePreferenceProjection
                .getLong(this, "player_night_mode_index", 0L).toInt()
                .coerceIn(0, nightModeGains.lastIndex)

            // Announce our audio session to system effect apps (default: off)
            systemAudioEffectsEnabled = com.debrify.app.profiles.ProfilePreferenceProjection
                .getBoolean(this, "player_system_audio_effects", false)

            // Manual community intro/outro buttons. These are the same keys the
            // Flutter Playback settings page writes; enabled never means auto-seek.
            skipSegmentsEnabled = com.debrify.app.profiles.ProfilePreferenceProjection
                .getBoolean(this, "skip_segments_enabled", true)
            val storedSkipSegmentProvider = com.debrify.app.profiles.ProfilePreferenceProjection.getString(
                this,
                "skip_segment_provider",
                TvSkipSegmentClients.AUTO,
            ) ?: TvSkipSegmentClients.AUTO
            skipSegmentProviderId = if (TvSkipSegmentClients.supports(storedSkipSegmentProvider)) {
                storedSkipSegmentProvider
            } else {
                TvSkipSegmentClients.AUTO
            }

            android.util.Log.d("AndroidTvPlayer", "Loaded defaults - aspect=$resizeModeIndex, nightMode=$nightModeIndex, audioEffects=$systemAudioEffectsEnabled, skipSegments=$skipSegmentsEnabled, skipProvider=$skipSegmentProviderId")
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Error loading player defaults", e)
            // Keep default values
        }
    }

    private fun showNightModeDialog() {
        AlertDialog.Builder(this)
            .setTitle("Night Mode")
            .setSingleChoiceItems(nightModeLabels, nightModeIndex) { dialog, which ->
                applyNightMode(which)
                dialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun applyNightMode(index: Int) {
        nightModeIndex = index

        if (nightModeIndex == 0) {
            // Turn off
            loudnessEnhancer?.enabled = false
        } else {
            // Turn on or adjust
            if (loudnessEnhancer == null) {
                initializeLoudnessEnhancer()
            }
            // Check if initialization succeeded before using
            loudnessEnhancer?.let {
                it.enabled = true
                it.setTargetGain(nightModeGains[nightModeIndex])
            }
        }

        updateNightModeButtonLabel()
        Toast.makeText(this, "Night Mode: ${nightModeLabels[nightModeIndex]}", Toast.LENGTH_SHORT).show()
    }

    // Progress reporting
    private fun restartProgressUpdates() {
        progressHandler.removeCallbacks(progressRunnable)
        progressHandler.postDelayed(progressRunnable, PROGRESS_INTERVAL_MS)
    }

    private fun sendProgress(completed: Boolean) {
        // IPTV mode builds no payload (initIptvMode returns before it is
        // parsed), so it reports against the current channel instead.
        if (isIptvMode) {
            sendIptvProgress(completed)
            return
        }
        val model = payload ?: return
        val item = model.items[currentIndex]
        // Use the largest stable duration seen — ExoPlayer can briefly report a
        // short duration right after a source re-prepare, which would otherwise
        // inflate progress% and scrobble a false watch on Trakt.
        val duration = maxOf(player?.duration ?: 0L, maxStableDurationMs)
        val position = if (completed) duration else player?.currentPosition ?: 0
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
            "index:$currentIndex"
        }
        val localCompleted =
            model.localCompletionTracking &&
            duration > 0L &&
            position > 0L &&
            position.toDouble() * 100.0 / duration.toDouble() >= completionThreshold &&
            locallyCompletedItemKeys.add(completionKey)

        // Update the item's progress in the payload for live UI updates
        val updatedItem = item.copy(
            resumePositionMs = position,
            durationMs = duration
        )
        model.items[currentIndex] = updatedItem

        // Notify playlist adapter to update progress display (if playlist is visible)
        if (playlistVisible) {
            playlistAdapter?.updateCurrentProgress()
        }

        val map = hashMapOf<String, Any?>(
            "contentType" to model.contentType,
            "itemIndex" to currentIndex,
            "resumeId" to item.resumeId,
            "positionMs" to position.toInt().coerceAtLeast(0),
            "durationMs" to duration.toInt().coerceAtLeast(0),
            "season" to item.season,
            "episode" to item.episode,
            "speed" to playbackSpeeds[playbackSpeedIndex].toDouble(),
            "aspect" to resizeModeLabels[resizeModeIndex].lowercase(),
            "completed" to completed,
            "localCompleted" to localCompleted,
            "url" to item.url,
            "isPlaying" to (player?.isPlaying ?: false),
            "isBuffering" to (player?.playbackState == Player.STATE_BUFFERING)
        )

        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("torrentPlaybackProgress", map)
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
        val entry = iptvChannels.getOrNull(currentIptvIndex) ?: return
        if (entry.isLive) return

        val duration = player?.duration ?: 0L
        if (duration <= 0L) return
        val position = if (completed) duration else player?.currentPosition ?: 0L
        if (position <= 0L) return

        val map = hashMapOf<String, Any?>(
            "mode" to "iptv",
            "itemIndex" to currentIptvIndex,
            "url" to entry.url,
            "title" to entry.name,
            "positionMs" to position.toInt().coerceAtLeast(0),
            "durationMs" to duration.toInt().coerceAtLeast(0),
            "speed" to playbackSpeeds[playbackSpeedIndex].toDouble(),
            "aspect" to resizeModeLabels[resizeModeIndex].lowercase(),
            "completed" to completed,
            "isPlaying" to (player?.isPlaying ?: false),
        )

        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("torrentPlaybackProgress", map)
    }

    private fun sendFinished() {
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("torrentPlaybackFinished", null)
    }

    /** The guide episode adjacent to the current item (specials excluded). */
    private fun guideAdjacent(model: PlaybackPayload, currentItem: PlaybackItem?, direction: Int): SeasonEpisode? {
        val s = currentItem?.season ?: return null
        val e = currentItem.episode ?: return null
        val eps = model.guideEpisodes
            .filter { it.season > 0 }
            .sortedWith(compareBy({ it.season }, { it.episode }))
        if (eps.isEmpty()) return null
        val idx = eps.indexOfFirst { it.season == s && it.episode == e }
        if (idx < 0) return null
        val t = idx + direction
        if (t < 0 || t >= eps.size) return null
        return SeasonEpisode(eps[t].season, eps[t].episode)
    }

    private var episodeFetchInFlight = false

    /** In-player quick play of an episode that isn't in the playlist: asks
     * Flutter to find + resolve a source (existing packs → episode fetch →
     * pack fetch) and swaps playlists in place — no activity relaunch. */
    private fun requestEpisodeFetch(
        season: Int,
        episode: Int,
        autoAdvance: Boolean = false,
    ) {
        if (episodeFetchInFlight) return
        val label = String.format(java.util.Locale.US, "S%02dE%02d", season, episode)
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            showStatusPillTransient("Couldn't fetch $label")
            return
        }
        episodeFetchInFlight = true
        val token = ++stremioResolutionToken
        showStatusPillTransient("Fetching $label…")
        channel.invokeMethod(
            "requestEpisodeFetch",
            hashMapOf<String, Any>("season" to season, "episode" to episode),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != stremioResolutionToken) return@runOnUiThread
                        val map = result as? Map<*, *>
                        val items = map?.get("items") as? List<*>
                        val fetchedSourceIndex = (map?.get("sourceIndex") as? Number)?.toInt()
                        if (map == null || items.isNullOrEmpty() || fetchedSourceIndex == null) {
                            showStatusPillTransient("No playable source found for $label")
                            return@runOnUiThread
                        }
                        adoptSourceList(map)
                        switchToSourcePlaylist(
                            fetchedSourceIndex,
                            items,
                            targetSeason = season,
                            targetEpisode = episode,
                            suppressTargetResume = autoAdvance,
                        )
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != stremioResolutionToken) return@runOnUiThread
                        showStatusPillTransient("No playable source found for $label")
                    }
                }

                override fun notImplemented() {
                    runOnUiThread {
                        episodeFetchInFlight = false
                        showStatusPillTransient("Couldn't fetch $label")
                    }
                }
            }
        )
    }

    /** Guide-not-ready Next for a catalog series. Flutter resolves the next
     * identity and runs the normal in-player episode source ladder. */
    private fun requestAdjacentEpisodeFetch(
        imdbId: String,
        currentSeason: Int,
        currentEpisode: Int,
        autoAdvance: Boolean = false,
    ) {
        if (episodeFetchInFlight) return
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            showStatusPillTransient("Couldn't fetch next episode")
            return
        }
        episodeFetchInFlight = true
        val token = ++stremioResolutionToken
        showStatusPillTransient("Finding next episode…")
        channel.invokeMethod(
            "requestEpisodeFetch",
            hashMapOf<String, Any>(
                "imdbId" to imdbId,
                "currentSeason" to currentSeason,
                "currentEpisode" to currentEpisode,
                "direction" to 1,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != stremioResolutionToken) return@runOnUiThread
                        val map = result as? Map<*, *>
                        val items = map?.get("items") as? List<*>
                        val fetchedSourceIndex = (map?.get("sourceIndex") as? Number)?.toInt()
                        if (map == null || items.isNullOrEmpty() || fetchedSourceIndex == null) {
                            showStatusPillTransient("No playable next episode found")
                            return@runOnUiThread
                        }
                        val targetSeason = (map["targetSeason"] as? Number)?.toInt()
                        val targetEpisode = (map["targetEpisode"] as? Number)?.toInt()
                        if (targetSeason == null || targetEpisode == null) {
                            showStatusPillTransient("No playable next episode found")
                            return@runOnUiThread
                        }
                        adoptSourceList(map)
                        switchToSourcePlaylist(
                            fetchedSourceIndex,
                            items,
                            targetSeason = targetSeason,
                            targetEpisode = targetEpisode,
                            suppressTargetResume = autoAdvance,
                        )
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != stremioResolutionToken) return@runOnUiThread
                        showStatusPillTransient("No playable next episode found")
                    }
                }

                override fun notImplemented() {
                    runOnUiThread {
                        episodeFetchInFlight = false
                        showStatusPillTransient("Couldn't fetch next episode")
                    }
                }
            }
        )
    }

    private fun requestQuickPlayNextEpisode(imdbId: String, season: Int, episode: Int) {
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

    // Utilities
    private fun formatTime(ms: Long): String {
        if (ms <= 0) return "00:00"
        val totalSeconds = ms / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        val hours = minutes / 60
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes % 60, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Stremio Source Switcher
    // ═══════════════════════════════════════════════════════════════════════

    private fun setupStremioSources() {
        if (stremioSources.isEmpty()) return

        android.util.Log.d("AndroidTvPlayer", "setupStremioSources: ${stremioSources.size} sources, current=$currentStremioSourceIndex")

        // Setup quality badge
        updateStremioQualityBadge()
        sourceBrowser?.render()

        // Sources use their own full-screen browser; the unified menu remains
        // the home for player settings such as audio and subtitles.
        stremioSourceBadge?.setOnClickListener {
            hideControlsMenu()
            unifiedMenu?.hide()
            sourceBrowser?.show()
        }
    }

    private fun updateStremioQualityBadge() {
        if (stremioSources.isEmpty()) return
        stremioSourceBadgeText?.text = "Sources"
    }

    private var sourceSwitchReadyListener: Player.Listener? = null
    private var sourceSwitchTimeoutRunnable: Runnable? = null

    /**
     * Feedback for an in-flight source switch: the status pill stays up until
     * the player reaches READY (success tick) or IDLE (error message) —
     * mirroring the old sources panel, which stayed open with a row spinner
     * until the same two states, with the same 10s give-up.
     */
    private fun watchSourceSwitchOutcome(sourceIndex: Int) {
        // Clean up any previous listener/timeout
        cancelSourceSwitchWait()

        val name = stremioSources.getOrNull(sourceIndex)?.displayTitle ?: "source"

        // Timeout fallback — stop reporting after 10s regardless
        val timeout = Runnable {
            cancelSourceSwitchWait()
            hideStatusPill()
        }
        sourceSwitchTimeoutRunnable = timeout
        progressHandler.postDelayed(timeout, 10_000)

        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    cancelSourceSwitchWait()
                    showStatusPillTransient("✓ $name")
                } else if (state == Player.STATE_IDLE) {
                    cancelSourceSwitchWait()
                    if (isIptvMode && iptvStremioChannelKey != null) {
                        // The IPTV candidate ladder handles this failure itself
                        // (silent auto-advance; its own toast when all die) —
                        // an error pill here would contradict it.
                        hideStatusPill()
                    } else {
                        // Playback error — tell the user instead of going silent
                        showStatusPillTransient("Couldn't play $name — pick another source")
                    }
                }
            }
        }
        sourceSwitchReadyListener = listener
        player?.addListener(listener)
    }

    private fun cancelSourceSwitchWait() {
        sourceSwitchReadyListener?.let { player?.removeListener(it) }
        sourceSwitchReadyListener = null
        sourceSwitchTimeoutRunnable?.let { progressHandler.removeCallbacks(it) }
        sourceSwitchTimeoutRunnable = null
    }

    /**
     * Navigation away from an in-flight source switch (next episode, playlist
     * pick, channel zap, ladder advance): drop the pending outcome watcher AND
     * its "Switching to…" pill, so a later item's READY/IDLE can't be reported
     * as the abandoned switch's result. No-op when nothing is pending.
     */
    private fun dropStaleSourceSwitchFeedback() {
        if (sourceSwitchReadyListener == null) return
        cancelSourceSwitchWait()
        hideStatusPill()
    }

    private var guidePanelReadyListener: Player.Listener? = null
    private var guidePanelTimeoutRunnable: Runnable? = null

    private fun hideGuideWhenReady() {
        if (!stremioTvGuideVisible) return

        // Clean up any previous listener/timeout
        cancelGuideWait()

        // Timeout fallback — hide after 10s regardless
        val timeout = Runnable {
            cancelGuideWait()
            if (stremioTvGuideVisible) hideStremioTvGuide()
        }
        guidePanelTimeoutRunnable = timeout
        progressHandler.postDelayed(timeout, 10_000)

        // Listen for STATE_READY to hide the guide
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY) {
                    cancelGuideWait()
                    if (stremioTvGuideVisible) hideStremioTvGuide()
                } else if (state == Player.STATE_IDLE) {
                    // Playback error — keep guide open
                    cancelGuideWait()
                    stremioTvChannels.forEach { it.isSwitchingChannel = false }
                    stremioTvChannelAdapter?.notifyDataSetChanged()
                }
            }
        }
        guidePanelReadyListener = listener
        player?.addListener(listener)
    }

    private fun cancelGuideWait() {
        guidePanelReadyListener?.let { player?.removeListener(it) }
        guidePanelReadyListener = null
        guidePanelTimeoutRunnable?.let { progressHandler.removeCallbacks(it) }
        guidePanelTimeoutRunnable = null
    }

    private fun onStremioSourceSelected(source: StremioSource) {
        android.util.Log.d("AndroidTvPlayer", "Stremio source selected: index=${source.index}, type=${source.streamType}, name=${source.displayTitle}, hasPlaylistResolver=$hasPlaylistResolver")

        // Cancel any pending source switch wait from previous selection
        cancelSourceSwitchWait()

        // Cancel any ongoing PikPak retry from previous source
        cancelPikPakRetry()

        // Increment token to invalidate any in-flight resolution
        stremioResolutionToken++

        // Immediate feedback (replaces the old panel's row spinner); stays up
        // through resolution, then watchSourceSwitchOutcome takes over.
        showStatusPill("Switching to ${source.displayTitle}…")

        if (hasPlaylistResolver) {
            // Torrent search mode — resolve to full playlist via Flutter
            resolveSourceToPlaylistViaFlutter(source, stremioResolutionToken)
        } else if (source.isDirectStream && !source.directUrl.isNullOrEmpty()) {
            // Direct URL — use immediately
            switchToStremioSource(source.directUrl, source.index)
        } else {
            // Torrent — resolve single URL via Flutter bridge
            resolveStremioSourceViaFlutter(source, stremioResolutionToken)
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
                        if (token != stremioResolutionToken) {
                            android.util.Log.d("AndroidTvPlayer", "resolveStremioSource - stale token $token (current: $stremioResolutionToken), discarding")
                            return
                        }
                        android.util.Log.d("AndroidTvPlayer", "resolveStremioSource - Flutter returned: $result")
                        val map = result as? Map<*, *>
                        val url = map?.get("url") as? String
                        if (!url.isNullOrEmpty()) {
                            runOnUiThread { switchToStremioSource(url, source.index) }
                        } else {
                            android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - null URL returned")
                            runOnUiThread {
                                showStatusPillTransient("Couldn't switch — failed to resolve source")
                            }
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (token != stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - error: $errorCode - $errorMessage")
                        runOnUiThread {
                            showStatusPillTransient("Couldn't switch — source resolution failed")
                        }
                    }

                    override fun notImplemented() {
                        if (token != stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - not implemented")
                        runOnUiThread {
                            showStatusPillTransient("Couldn't switch source")
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "resolveStremioSource - exception: ${e.message}", e)
            showStatusPillTransient("Couldn't switch source")
        }
    }

    private fun resolveSourceToPlaylistViaFlutter(source: StremioSource, token: Int) {
        try {
            val args = hashMapOf<String, Any?>("sourceIndex" to source.index)
            android.util.Log.d("AndroidTvPlayer", "resolveSourceToPlaylist - sending to Flutter: index=${source.index}, token=$token")

            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "requestSourcePlaylistResolve",
                args,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (token != stremioResolutionToken) {
                            android.util.Log.d("AndroidTvPlayer", "resolveSourceToPlaylist - stale token $token (current: $stremioResolutionToken), discarding")
                            return
                        }
                        android.util.Log.d("AndroidTvPlayer", "resolveSourceToPlaylist - Flutter returned: ${result != null}")
                        val map = result as? Map<*, *>
                        val itemsList = map?.get("items") as? List<*>
                        if (itemsList != null && itemsList.isNotEmpty()) {
                            runOnUiThread { switchToSourcePlaylist(source.index, itemsList) }
                        } else {
                            android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - null or empty items returned")
                            runOnUiThread {
                                showStatusPillTransient("Source unavailable — not cached or not a video")
                            }
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (token != stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - error: $errorCode - $errorMessage")
                        runOnUiThread {
                            showStatusPillTransient("Couldn't switch — failed to resolve source")
                        }
                    }

                    override fun notImplemented() {
                        if (token != stremioResolutionToken) return
                        android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - not implemented")
                        runOnUiThread {
                            showStatusPillTransient("Couldn't switch source")
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "resolveSourceToPlaylist - exception: ${e.message}", e)
            showStatusPillTransient("Couldn't switch source")
        }
    }

    /**
     * "Load more sources" for a series source tab: asks Flutter to run the
     * not-yet-fetched category's search ('packs' | 'episodes'). The response
     * carries the FULL updated source list (append-only, so every existing
     * index — including [currentStremioSourceIndex] — stays valid) plus the
     * updated per-tab fetch flags. While in flight the tab shows a disabled
     * Loading row; a failure keeps the button up for a retry.
     */
    private fun requestMoreTorrentSources(mode: String) {
        if (moreSourcesLoadingMode != null) return
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            showStatusPillTransient("Couldn't load more sources")
            return
        }
        moreSourcesLoadingMode = mode
        unifiedMenu?.render()
        sourceBrowser?.render()
        // Current playlist position: a season-pack playlist auto-advances
        // episodes without relaunching, so the fetch must target what's
        // playing NOW, not the launch episode.
        val curItem = payload?.items?.getOrNull(currentIndex)
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
                    runOnUiThread { applyMoreTorrentSources(mode, result as? Map<*, *>) }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    android.util.Log.e("AndroidTvPlayer", "requestMoreTorrentSources - error: $errorCode - $errorMessage")
                    runOnUiThread { failMoreTorrentSources() }
                }

                override fun notImplemented() {
                    android.util.Log.e("AndroidTvPlayer", "requestMoreTorrentSources - not implemented")
                    runOnUiThread { failMoreTorrentSources() }
                }
            }
        )
    }

    private fun applyMoreTorrentSources(mode: String, map: Map<*, *>?) {
        moreSourcesLoadingMode = null
        if (map == null) {
            failMoreTorrentSources(alreadyCleared = true)
            return
        }
        val newSources = map["stremioSources"] as? List<*>
        if (newSources != null && newSources.isNotEmpty()) {
            val before = stremioSources.size
            stremioSources.clear()
            for ((idx, src) in newSources.withIndex()) {
                val srcMap = src as? Map<*, *> ?: continue
                stremioSources.add(StremioSource.fromMap(srcMap, idx))
            }
            // Append-only contract: the current source keeps its index; clamp
            // is belt-and-braces only.
            currentStremioSourceIndex = currentStremioSourceIndex
                .coerceIn(0, stremioSources.lastIndex.coerceAtLeast(0))
            android.util.Log.d(
                "AndroidTvPlayer",
                "applyMoreTorrentSources - mode=$mode, sources $before → ${stremioSources.size}"
            )
        }
        (map["packsFetched"] as? Boolean)?.let { seriesPacksFetched = it }
        (map["episodesFetched"] as? Boolean)?.let { seriesEpisodesFetched = it }
        (map["movieFetched"] as? Boolean)?.let { movieSourcesFetched = it }
        updateStremioQualityBadge()
        unifiedMenu?.render()
        sourceBrowser?.render()
    }

    /** Per-addon fetch from the source browser: episode results first — the
     * response merges them into the list AND says whether they carried
     * torrent magnets (probePacks). Only then does the lazy season-pack probe
     * run as a SECOND call, so direct links render the moment they arrive. */
    private fun requestAddonTorrentSources(groupId: String) {
        // Every addon sharing this group's name — same-named addons collapse
        // into one group (results only carry the name), so the fetch asks all.
        val addonIds = sourceAddons.filter { it.sourceKey == groupId }.map { it.id }
        if (addonIds.isEmpty()) return
        if (addonFetchState[groupId] == "fetching") return
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            sourceBrowser?.showError("Couldn't fetch — try again")
            return
        }
        addonFetchState[groupId] = "fetching"
        sourceBrowser?.render()
        val curItem = payload?.items?.getOrNull(currentIndex)
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
                    runOnUiThread {
                        applyAddonEpisodeSources(groupId, result as? Map<*, *>, curItem?.season)
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    runOnUiThread { failAddonFetch(groupId) }
                }

                override fun notImplemented() {
                    runOnUiThread { failAddonFetch(groupId) }
                }
            }
        )
    }

    private fun applyAddonEpisodeSources(groupId: String, map: Map<*, *>?, season: Int?) {
        if (map == null) {
            failAddonFetch(groupId)
            return
        }
        addonFetchState[groupId] = "fetched"
        adoptSourceList(map)
        // Only the ids whose own episode results carried a magnet get the
        // pack probe — the response names them; empty = nothing to probe.
        val packIds = (map["packAddonIds"] as? List<*>)?.filterIsInstance<String>().orEmpty()
        if (packIds.isEmpty()) {
            sourceBrowser?.render()
            return
        }
        addonPackProbing.add(groupId)
        sourceBrowser?.render()
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            addonPackProbing.remove(groupId)
            sourceBrowser?.render()
            return
        }
        channel.invokeMethod(
            "requestAddonTorrentSources",
            hashMapOf<String, Any?>("addonIds" to packIds, "mode" to "packs", "season" to season),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    runOnUiThread {
                        addonPackProbing.remove(groupId)
                        adoptSourceList(result as? Map<*, *>)
                        sourceBrowser?.render()
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    runOnUiThread {
                        addonPackProbing.remove(groupId)
                        sourceBrowser?.render()
                    }
                }

                override fun notImplemented() {
                    runOnUiThread {
                        addonPackProbing.remove(groupId)
                        sourceBrowser?.render()
                    }
                }
            }
        )
    }

    private fun failAddonFetch(groupId: String) {
        addonFetchState[groupId] = "failed"
        sourceBrowser?.render()
    }

    /** Adopt a full replacement source list from a per-addon fetch response —
     * the same append-only swap [applyMoreTorrentSources] performs. */
    private fun adoptSourceList(map: Map<*, *>?) {
        val newSources = (map?.get("stremioSources") as? List<*>) ?: return
        if (newSources.isEmpty()) return
        stremioSources.clear()
        for ((idx, src) in newSources.withIndex()) {
            val srcMap = src as? Map<*, *> ?: continue
            stremioSources.add(StremioSource.fromMap(srcMap, idx))
        }
        currentStremioSourceIndex = currentStremioSourceIndex
            .coerceIn(0, stremioSources.lastIndex.coerceAtLeast(0))
        updateStremioQualityBadge()
        unifiedMenu?.render()
    }

    private fun failMoreTorrentSources(alreadyCleared: Boolean = false) {
        if (!alreadyCleared) moreSourcesLoadingMode = null
        if (sourceBrowser?.isVisible == true) {
            sourceBrowser?.showError("Couldn't load more sources — try again")
        } else {
            showStatusPillTransient("Couldn't load more sources")
        }
        unifiedMenu?.render()
        sourceBrowser?.render()
    }

    private fun switchToSourcePlaylist(
        sourceIndex: Int,
        rawItems: List<*>,
        targetSeason: Int? = null,
        targetEpisode: Int? = null,
        suppressTargetResume: Boolean = false,
    ) {
        android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist: sourceIndex=$sourceIndex, rawItems=${rawItems.size}, target=S${targetSeason}E${targetEpisode}")

        val model = payload ?: return

        // Capture playback position + current item identity so the new source
        // resumes the same content instead of restarting from the beginning.
        // An explicit episode-guide target is different content: land there
        // instead, and never carry the current position onto it.
        val resumePositionMs = (player?.currentPosition ?: 0L).coerceAtLeast(0L)
        val currentItem = model.items.getOrNull(currentIndex)
        val explicitTarget = targetSeason != null && targetEpisode != null
        val resumeSeason = targetSeason ?: currentItem?.season
        val resumeEpisode = targetEpisode ?: currentItem?.episode
        val sameContent = !explicitTarget ||
            (targetSeason == currentItem?.season && targetEpisode == currentItem?.episode)

        // Parse metadata entry (first item with __meta__ flag)
        var contentType = model.contentType
        val itemMaps = mutableListOf<Map<*, *>>()
        for (raw in rawItems) {
            val map = raw as? Map<*, *> ?: continue
            if (map["__meta__"] == true) {
                contentType = (map["contentType"] as? String) ?: contentType
                continue
            }
            itemMaps.add(map)
        }

        if (itemMaps.isEmpty()) {
            android.util.Log.e("AndroidTvPlayer", "switchToSourcePlaylist - no valid items after parsing")
            showStatusPillTransient("Source unavailable")
            return
        }

        // Parse items into PlaybackItem list
        val newItems = mutableListOf<PlaybackItem>()
        for (map in itemMaps) {
            try {
                // Convert Map<*, *> to JSONObject safely
                val obj = JSONObject()
                for ((key, value) in map) {
                    if (key is String) {
                        obj.put(key, value ?: JSONObject.NULL)
                    }
                }
                newItems.add(PlaybackItem.fromJson(obj))
            } catch (e: Exception) {
                android.util.Log.w("AndroidTvPlayer", "switchToSourcePlaylist - failed to parse item: ${e.message}")
            }
        }

        if (newItems.isEmpty()) {
            android.util.Log.e("AndroidTvPlayer", "switchToSourcePlaylist - no items parsed successfully")
            showStatusPillTransient("Source unavailable")
            return
        }

        // A singleton direct stream has no pack filenames from which Flutter
        // can infer an episode. Preserve the catalog identity across a manual
        // source switch as well as an adjacent-episode fetch.
        if (contentType == "series" && newItems.size == 1 &&
            (newItems[0].season == null || newItems[0].episode == null) &&
            resumeSeason != null && resumeEpisode != null) {
            newItems[0] = newItems[0].copy(
                season = resumeSeason,
                episode = resumeEpisode,
            )
        }

        android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist - parsed ${newItems.size} items, contentType=$contentType")

        // Find which item in the new source's playlist matches what the user was
        // watching, so we resume the same content rather than restarting at file 0.
        //  - Single item: unambiguous — it's the content (movie, or one episode).
        //  - Series (multi-file): match by season+episode.
        //  - Collection (multi-file movie torrent): match by title; if names
        //    differ across sources, keep the same list position but don't carry
        //    the timestamp onto what could be a different movie.
        var targetIndex = 0
        var matchedSameContent = false
        if (newItems.size == 1) {
            targetIndex = 0
            matchedSameContent = sameContent
        } else if (resumeSeason != null && resumeEpisode != null) {
            val matched = newItems.indexOfFirst {
                it.season == resumeSeason && it.episode == resumeEpisode
            }
            if (matched >= 0) {
                targetIndex = matched
                matchedSameContent = sameContent
            } else {
                // The exact episode isn't in this source. Do NOT fall back to
                // file 0 — in torrent order that's often an extras/bonus clip
                // (a season pack may list "Extras/" or a featurette first).
                // Land on the first REAL episode (skip season 0 / specials),
                // and tell the user we couldn't find what they were watching.
                val firstReal = newItems.indexOfFirst {
                    val s = it.season
                    s != null && s != 0 && it.episode != null
                }
                targetIndex = if (firstReal >= 0) firstReal else 0
                Toast.makeText(
                    this,
                    "S${resumeSeason}E${resumeEpisode} not in this source — playing from the start",
                    Toast.LENGTH_LONG
                ).show()
            }
        } else if (currentItem != null) {
            val byTitle = newItems.indexOfFirst {
                it.title.isNotEmpty() && it.title == currentItem.title
            }
            if (byTitle >= 0) {
                targetIndex = byTitle
                matchedSameContent = true
            } else {
                targetIndex = currentIndex.coerceIn(0, newItems.lastIndex)
            }
        }
        if (matchedSameContent && resumePositionMs > 0 && targetIndex in newItems.indices) {
            newItems[targetIndex] = newItems[targetIndex].copy(resumePositionMs = resumePositionMs)
            android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist - resuming item $targetIndex at $resumePositionMs ms")
        } else {
            android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist - playing item $targetIndex from start (matchedSameContent=$matchedSameContent)")
        }

        // Update source state
        currentStremioSourceIndex = sourceIndex
        updateStremioQualityBadge()
        sourceBrowser?.render()

        // Cancel any ongoing PikPak retry
        cancelPikPakRetry()

        // Replace payload items and content type
        model.items.clear()
        model.items.addAll(newItems)
        shuffleBag.clear()

        // Rebuild navigation maps for new items
        rebuildNavigationMaps(model, contentType)

        // Point currentIndex at the item we're about to play BEFORE rebuilding
        // the UI: setupSeasonTabs / buildList default the season tab and the
        // active highlight off currentIndex. If it still held the OLD source's
        // index (into a differently-ordered list), the now-playing episode could
        // land outside the selected tab and be neither shown nor highlighted.
        // playItem() re-affirms currentIndex = targetIndex momentarily later.
        currentIndex = targetIndex

        // Rebuild playlist UI (without re-adding RecyclerView listeners)
        rebuildPlaylistContent()

        // Update the title content for the next controls reveal.
        val currentSource = stremioSources.getOrNull(sourceIndex)
        if (currentSource != null) {
            titleView.text = currentSource.displayTitle
        }

        // Resume the previously-playing item; the captured position is carried
        // on the item above as resumePositionMs. Suppress tracker/startAt percent
        // seeks so they can't override our explicit resume position — but ONLY
        // when the new source landed on the SAME content: a fallback episode
        // (exact episode missing from the new source) has no captured position
        // and must keep its own per-episode tracker resume, matching the Dart
        // player's landedOnSameContent behaviour.
        percentSeekApplied = true
        playItem(
            targetIndex,
            suppressTrakt = matchedSameContent,
            suppressResume = suppressTargetResume,
        )

        // Report the switch outcome once playback settles
        watchSourceSwitchOutcome(sourceIndex)
    }

    private fun rebuildNavigationMaps(model: PlaybackPayload, contentType: String) {
        model.contentType = contentType

        val nextMap = mutableMapOf<Int, Int>()
        val prevMap = mutableMapOf<Int, Int>()

        // Determine the CHRONOLOGICAL order to chain next/prev through. Torrent
        // file order is NOT necessarily episode order (a pack may list S01E05
        // before S01E02), and the playlist adapter itself displays episodes
        // sorted by season then episode. If we linked next/prev in raw file
        // order, "next episode" / autoplay-next would jump to whatever file
        // happens to sit next in the torrent — the wrong episode. So for series
        // content, chain in (season, episode) order to match what the user sees.
        // Collections (no season/episode) keep raw list order.
        val isSeries = contentType == "series" &&
            model.items.any { it.season != null && it.episode != null }
        val order: List<Int> = if (isSeries) {
            model.items.indices.sortedWith(
                compareBy(
                    { model.items[it].season ?: Int.MAX_VALUE },
                    { model.items[it].episode ?: Int.MAX_VALUE },
                    { it }, // stable tie-break on raw index
                )
            )
        } else {
            model.items.indices.toList()
        }

        for (pos in 0 until order.lastIndex) {
            nextMap[order[pos]] = order[pos + 1]
        }
        for (pos in 1..order.lastIndex) {
            prevMap[order[pos]] = order[pos - 1]
        }

        model.nextEpisodeMap = nextMap
        model.prevEpisodeMap = prevMap
        model.collectionGroups = null
        model.perItemImdbIds.clear()

        android.util.Log.d("AndroidTvPlayer", "rebuildNavigationMaps - contentType=$contentType, isSeries=$isSeries, nextMap=${nextMap.size}, prevMap=${prevMap.size}")
    }

    private fun switchToStremioSource(url: String, sourceIndex: Int) {
        // Live Stremio IPTV channel: the movie path below seeks to the
        // previous position and runs PikPak/YouTube bookkeeping — all wrong
        // for a live stream. Route to the dedicated live switch.
        if (isIptvMode && iptvStremioChannelKey != null) {
            switchToIptvStremioSource(url, sourceIndex)
            return
        }
        android.util.Log.d("AndroidTvPlayer", "switchToStremioSource: index=$sourceIndex, url=${url.take(60)}...")

        // Capture current position for resume
        val currentPos = player?.currentPosition ?: 0L

        // Update state
        currentStremioSourceIndex = sourceIndex
        updateStremioQualityBadge()
        sourceBrowser?.render()

        // Cancel any ongoing PikPak retry before switching
        cancelPikPakRetry()

        // Switch ExoPlayer source, preserving position. For high-res YouTube the
        // current item carries a separate audio track that ALL qualities share,
        // so merge the newly picked (video-only) url with that audio — otherwise
        // switching to a video-only quality would go silent. Non-YouTube sources
        // (no separate audio) use the single url as-is.
        val currentAudioUrl = payload?.items?.getOrNull(currentIndex)?.audioUrl
        val mergedSource = if (!currentAudioUrl.isNullOrEmpty()) {
            buildMergedSource(url, currentAudioUrl)
        } else {
            null
        }
        if (mergedSource != null) {
            player?.setMediaSource(mergedSource)
        } else {
            player?.setMediaItem(MediaItem.fromUri(url))
        }
        player?.prepare()
        if (currentPos > 0) {
            player?.seekTo(currentPos)
        }
        player?.play()

        // Report the switch outcome once playback settles
        watchSourceSwitchOutcome(sourceIndex)

        // Update the title content for the next controls reveal.
        val currentSource = stremioSources.getOrNull(sourceIndex)
        if (currentSource != null) {
            titleView.text = currentSource.displayTitle
        }

        // For PikPak URLs, start cold storage retry monitoring
        if (url.contains("mypikpak.com")) {
            android.util.Log.d("AndroidTvPlayer", "switchToStremioSource: PikPak URL detected, starting retry logic")
            pikPakRetryId++
            val myRetryId = pikPakRetryId
            pikPakRetryCount = 0
            isPikPakRetrying = false
            hidePikPakRetryOverlay()
            // Build a temporary PlaybackItem for the retry loop
            val tempItem = PlaybackItem(
                id = "stremio_source_$sourceIndex",
                title = currentSource?.displayTitle ?: "",
                url = url,
                index = sourceIndex,
                season = null,
                episode = null,
                artwork = null,
                description = null,
                resumePositionMs = currentPos,
                durationMs = 0L,
                updatedAt = 0L,
                resumeId = null,
                sizeBytes = currentSource?.sizeBytes,
                rating = null,
                provider = PROVIDER_PIKPAK,
            )
            attemptPikPakPlaybackLoop(tempItem, 0, myRetryId)
        }
    }

    private fun showStremioSourceBadge() {
        if (stremioSources.isEmpty()) return
        stremioSourceBadge?.animate()?.cancel()
        stremioSourceBadge?.visibility = View.VISIBLE
        stremioSourceBadge?.alpha = 0f
        stremioSourceBadge?.translationX = 30f
        stremioSourceBadge?.animate()
            ?.alpha(1f)
            ?.translationX(0f)
            ?.setDuration(250)
            ?.setInterpolator(DecelerateInterpolator(1.5f))
            ?.start()
    }

    private fun hideStremioSourceBadge() {
        stremioSourceBadge?.animate()?.cancel()
        stremioSourceBadge?.animate()
            ?.alpha(0f)
            ?.translationX(20f)
            ?.setDuration(200)
            ?.setInterpolator(android.view.animation.AccelerateInterpolator(1.2f))
            ?.withEndAction {
                stremioSourceBadge?.visibility = View.GONE
                stremioSourceBadge?.translationX = 0f
            }
            ?.start()
    }

    private fun parsePayload(raw: String): PlaybackPayload? {
        return try {
            val obj = JSONObject(raw)
            val itemsJson = obj.optJSONArray("items") ?: JSONArray()
            val items = mutableListOf<PlaybackItem>()
            for (i in 0 until itemsJson.length()) {
                val itemObj = itemsJson.getJSONObject(i)
                items.add(PlaybackItem.fromJson(itemObj))
            }

            // Use startIndex directly from Flutter - items are already in correct order
            // DO NOT re-sort items here - Flutter's SeriesPlaylist.allEpisodes order is authoritative
            val startIndex = obj.optInt("startIndex", 0).coerceIn(0, items.lastIndex.coerceAtLeast(0))

            // Parse navigation maps from Flutter (pre-computed based on SeriesPlaylist order)
            val nextEpisodeMap = mutableMapOf<Int, Int>()
            val prevEpisodeMap = mutableMapOf<Int, Int>()

            obj.optJSONObject("nextEpisodeMap")?.let { mapObj ->
                mapObj.keys().forEach { key ->
                    nextEpisodeMap[key.toInt()] = mapObj.getInt(key)
                }
            }

            obj.optJSONObject("prevEpisodeMap")?.let { mapObj ->
                mapObj.keys().forEach { key ->
                    prevEpisodeMap[key.toInt()] = mapObj.getInt(key)
                }
            }

            // Parse collection groups if present
            val collectionGroupsJson = obj.optJSONArray("collectionGroups")
            val collectionGroups = if (collectionGroupsJson != null) {
                mutableListOf<JSONObject>().apply {
                    for (i in 0 until collectionGroupsJson.length()) {
                        add(collectionGroupsJson.getJSONObject(i))
                    }
                }
            } else null

            // Parse IMDB ID for external subtitles
            val imdbId = obj.optString("imdbId").takeIf { it.isNotEmpty() }

            val httpHeaders = mutableMapOf<String, String>()
            obj.optJSONObject("httpHeaders")?.let { headersObj ->
                headersObj.keys().forEach { key ->
                    val value = headersObj.optString(key)
                    if (key.isNotBlank() && value.isNotEmpty()) {
                        httpHeaders[key] = value
                    }
                }
            }

            // Parse startAtPercent for seeking to a specific position (e.g., Stremio TV slot progress)
            val startAtPercent = obj.optDouble("startAtPercent", 0.0).let {
                if (it.isNaN() || it.isInfinite()) 0.0 else it
            }

            // Parse Trakt progress for resume (0-100, takes priority over local resume)
            val traktProgressPercent = obj.optDouble("traktProgressPercent", 0.0).let {
                if (it.isNaN() || it.isInfinite()) 0.0 else it
            }
            val localCompletionTracking = obj.optBoolean("localCompletionTracking", false)
            val movieCompletionThreshold =
                obj.optInt("movieCompletionThreshold", 80).coerceIn(50, 95)
            val episodeCompletionThreshold =
                obj.optInt("episodeCompletionThreshold", 80).coerceIn(50, 95)

            // Parse Stremio sources for source switching
            val stremioSourcesJson = obj.optJSONArray("stremioSources")
            if (stremioSourcesJson != null && stremioSourcesJson.length() > 0) {
                stremioSources.clear()
                for (i in 0 until stremioSourcesJson.length()) {
                    stremioSources.add(StremioSource.fromJson(stremioSourcesJson.getJSONObject(i), i))
                }
                currentStremioSourceIndex = obj.optInt("stremioCurrentSourceIndex", 0)
                    .coerceIn(0, stremioSources.lastIndex.coerceAtLeast(0))
                android.util.Log.d("AndroidTvPlayer", "parsePayload - stremioSources: ${stremioSources.size}, currentIndex: $currentStremioSourceIndex")
            }

            // Parse playlist resolver flag
            hasPlaylistResolver = obj.optBoolean("hasPlaylistResolver", false)

            // Network & Buffering presets. Parsed unconditionally (defaults
            // "standard") so a relaunch/next-episode payload can never
            // inherit stale tuning.
            networkPatience = obj.optString("networkPatience", "standard")
            networkBuffer = obj.optString("networkBuffer", "standard")
            iptvDecoderMode = obj.optString("iptvDecoder", "auto")

            // Series source tabs: pack/episode split + per-tab "Load more"
            // availability. Parsed unconditionally (defaults off) so a
            // relaunch/next-episode payload can never inherit stale state.
            seriesSourceTabs = obj.optBoolean("seriesSourceTabs", false)
            seriesPacksFetched = obj.optBoolean("seriesPacksFetched", true)
            seriesEpisodesFetched = obj.optBoolean("seriesEpisodesFetched", true)
            movieMoreSources = obj.optBoolean("movieMoreSources", false)
            movieSourcesFetched = obj.optBoolean("movieSourcesFetched", true)
            moreSourcesLoadingMode = null
            // Per-addon placeholder groups. Parsed unconditionally so a
            // relaunch/next-episode payload can never inherit stale addons.
            sourceAddons = obj.optJSONArray("sourceAddons")?.let { arr ->
                buildList {
                    for (i in 0 until arr.length()) {
                        val a = arr.optJSONObject(i) ?: continue
                        val id = a.optString("id")
                        val key = a.optString("sourceKey")
                        if (id.isNotEmpty() && key.isNotEmpty()) {
                            add(TvSourceAddon(id, a.optString("name", id), key))
                        }
                    }
                }
            } ?: emptyList()
            addonFetchState.clear()
            addonPackProbing.clear()
            locallyCompletedItemKeys.clear()

            android.util.Log.d("AndroidTvPlayer", "parsePayload - startIndex: $startIndex, items: ${items.size}, nextMap: ${nextEpisodeMap.size}, prevMap: ${prevEpisodeMap.size}, collectionGroups: ${collectionGroups?.size ?: 0}, imdbId: $imdbId, startAtPercent: $startAtPercent")

            PlaybackPayload(
                title = obj.optString("title"),
                subtitle = obj.optString("subtitle"),
                contentType = obj.optString("contentType", "single"),
                items = items,
                startIndex = startIndex,
                seriesTitle = obj.optString("seriesTitle"),
                nextEpisodeMap = nextEpisodeMap,
                prevEpisodeMap = prevEpisodeMap,
                collectionGroups = collectionGroups,
                imdbId = imdbId,
                httpHeaders = httpHeaders,
                startAtPercent = startAtPercent,
                traktProgressPercent = traktProgressPercent,
                localCompletionTracking = localCompletionTracking,
                movieCompletionThreshold = movieCompletionThreshold,
                episodeCompletionThreshold = episodeCompletionThreshold,
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "parsePayload failed", e)
            null
        }
    }

    override fun onStart() {
        super.onStart()
        // Never undo a sleep-timer stop — this runs every time the activity
        // comes back, including after the screen has slept.
        if (!sleepStopLatched) {
            // LIVE, back after a real absence: the paused stream is minutes
            // behind the edge (or the origin dropped it while we were away).
            // Re-tune to the live edge instead of resuming stale bytes —
            // same "always resumes playing" contract this method has always
            // had, just at the right point in the broadcast. Short trips
            // keep the cheap in-buffer resume (that's legitimate timeshift).
            val awayMs = SystemClock.elapsedRealtime() - iptvStoppedAtRealtime
            val liveEntry = if (isIptvMode) {
                iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive }
            } else null
            // A trial onStop abandoned mid-verdict: re-tune the original HLS
            // stream instead of resuming (or live-edge-rejoining) the
            // unjudged twin. A full tune, so player, identity, machine and
            // diagnostics all agree again; it re-tunes to the live edge, so
            // it subsumes the >30s rejoin too.
            if (liveEntry != null && restoreParkedIptvTwinIfNeeded()) {
                // Restored and started by setIptvMediaItem.
            } else if (liveEntry != null &&
                iptvStoppedAtRealtime > 0L &&
                awayMs > IPTV_LIVE_REJOIN_AFTER_MS
            ) {
                player?.playWhenReady = true // eligibility reads this
                iptvLiveRecovery.userRetry("lifecycle-rejoin")
            } else {
                player?.play()
            }
        }
        // Resume the side-rendered subtitle ticker paused in onStop.
        if (externalSubtitleActive) startExternalSubtitleTicker()
    }

    override fun onStop() {
        super.onStop()
        // Publish the recording HERE, not just in onDestroy: Home / app-switch
        // runs onStop and Android may kill the process afterwards without ever
        // calling onDestroy, which would strand the row IS_PENDING (invisible,
        // still eating storage) with no persisted state to recover it from.
        // Nothing is lost by stopping now — the pause below ends the byte flow
        // the recording tees anyway.
        finalizeIptvRecordingIfActive()
        // A recovery in flight must not fight the pause below (its re-tunes
        // set playWhenReady=true); onStart's rejoin re-arms recovery anyway.
        // The twin trial goes with it — its timeout re-tunes too, and firing
        // one while backgrounded would restart playback under the pause. An
        // UNJUDGED twin must not survive as the channel's identity either:
        // park its original for onStart to restore FOR REAL (media item, not
        // just the bookkeeping field — the two disagreeing would misroute
        // error attribution, recording eligibility and diagnostics on a
        // quick resume).
        if (!parkIptvTwinTrialRestore()) clearIptvTwinTrial()
        iptvLiveRecovery.cancel()
        hideIptvReconnectPill()
        iptvStoppedAtRealtime = SystemClock.elapsedRealtime()
        player?.pause()
        // Stop waking the main thread 4x/second while the activity isn't visible;
        // state is preserved and onStart restarts the ticker.
        externalSubtitleTicker?.let { externalSubtitleHandler.removeCallbacks(it) }
    }

    private fun setupBackPressHandler() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // If IPTV guide is visible, hide it first
                if (iptvGuideVisible) {
                    hideIptvGuide()
                    return
                }

                // If playlist is visible, hide it first
                if (playlistOverlay.visibility == View.VISIBLE) {
                    hidePlaylist()
                    return
                }

                // Double-back to exit confirmation
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastBackPressTime < BACK_PRESS_INTERVAL_MS) {
                    // Second back press within time window - exit
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                } else {
                    // First back press - show message
                    lastBackPressTime = currentTime
                    Toast.makeText(
                        this@AndroidTvTorrentPlayerActivity,
                        "Press back again to exit",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
        })
    }

    private val legacyStoragePermissionRequestCode = 7402
    private val notificationPermissionRequestCode = 7403

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == legacyStoragePermissionRequestCode) {
            // Granted or not, the button's enabled/label state may change.
            updateRecordButtonState()
        }
    }

    override fun onResume() {
        super.onResume()
        ActivityTracker.currentActivity = this
        // A recording finished while storage was misbehaving stays written but
        // invisible; coming back to the player is a good moment to retry.
        if (iptvRecordingController.hasUnpublishedRecording &&
            iptvRecordingController.retryPendingPublish()
        ) {
            Toast.makeText(
                this,
                "Earlier recording added to Downloads/Debrify/Recordings",
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    override fun onPause() {
        super.onPause()
        if (ActivityTracker.currentActivity == this) {
            ActivityTracker.currentActivity = null
        }
        // Cancel any ongoing PikPak retry operations
        cancelPikPakRetry()
    }

    private fun showBufferingIndicatorDebounced() {
        bufferingDebounceRunnable?.let { bufferingHandler.removeCallbacks(it) }
        val runnable = Runnable {
            val state = player?.playbackState ?: return@Runnable
            if (state == Player.STATE_BUFFERING && hasEverBeenReady && nextOverlay.visibility != View.VISIBLE && pikPakReactivationIndicator.visibility != View.VISIBLE) {
                bufferingIndicator.visibility = View.VISIBLE
                bufferingIndicator.animate().alpha(1f).setDuration(250).start()
            }
        }
        bufferingDebounceRunnable = runnable
        bufferingHandler.postDelayed(runnable, 800)
    }

    private fun hideBufferingIndicator() {
        bufferingDebounceRunnable?.let { bufferingHandler.removeCallbacks(it) }
        bufferingDebounceRunnable = null
        if (bufferingIndicator.visibility == View.VISIBLE) {
            bufferingIndicator.animate().alpha(0f).setDuration(200).withEndAction {
                bufferingIndicator.visibility = View.GONE
            }.start()
        }
    }

    override fun onDestroy() {
        iptvTuneDiagnostics.onSessionEnd()
        clearIptvTwinTrial()
        iptvLiveRecovery.cancel()
        iptvNetworkCallback?.let {
            try {
                (getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager)
                    .unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
            iptvNetworkCallback = null
        }
        RecordingRegistry.removeListener(recordingRegistryListener)
        // The sleep timer belongs to this playback session — a pending one must
        // not outlive the player and fire against a dead surface.
        cancelSleepTimer()
        // Finalize any in-progress TEE recording so its MediaStore row isn't
        // left pending (invisible) when the player is torn down. Engine
        // captures deliberately ignore player teardown.
        finalizeIptvRecordingIfActive()

        // Clean up seek feedback manager
        if (::seekFeedbackManager.isInitialized) {
            seekFeedbackManager.destroy()
        }

        iptvBrowseHandler.removeCallbacksAndMessages(null)
        iptvEpgToken++
        iptvUiContextToken++
        iptvBrowseToken++
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()

        // Cancel PikPak retry operations
        cancelPikPakRetry()
        pikPakRetryHandler.removeCallbacksAndMessages(null)

        // Clean up indicators
        pikPakReactivationIndicator.animate().cancel()
        pikPakReactivationIndicator.visibility = View.GONE
        bufferingIndicator.animate().cancel()
        bufferingHandler.removeCallbacksAndMessages(null)

        // Clean up Up Next card
        upNextHandler.removeCallbacksAndMessages(null)

        // Unregister broadcast receiver
        metadataUpdateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                android.util.Log.w("AndroidTvPlayer", "Failed to unregister metadata receiver", e)
            }
        }
        metadataUpdateReceiver = null

        // Cancel Stremio subtitle coroutine scope
        subtitleScope.cancel()
        stremioSubtitles.clear()
        stremioSubtitleService = null

        // Cancel optional skip-provider work; late network responses must not retain
        // or update a destroyed TV player.
        skipSegmentFetchGeneration++
        skipSegmentFetchJob?.cancel()
        skipSegmentFetchJob = null
        skipSegmentScope.cancel()
        skipSegmentCache.clear()

        // Clear all handlers
        progressHandler.removeCallbacksAndMessages(null)
        controlsHandler.removeCallbacksAndMessages(null)
        seekbarHandler.removeCallbacksAndMessages(null)

        // Release night mode audio effect
        releaseLoudnessEnhancer()

        // Tell system effect apps to detach — an unmatched OPEN leaves them
        // processing dead audio and degrades other apps' equalizers.
        com.debrify.app.audio.AudioEffectSession.closeCurrent(this)

        // Clear player and listeners
        player?.let {
            sendProgress(completed = false)
            it.removeListener(playbackListener)
            subtitleListener?.let { listener -> it.removeListener(listener) }
            it.release()
        }
        player = null
        subtitleListener = null
        trackSelector = null
        offsetRenderersFactory = null
        speechTap = null
        syncOverlay = null
        linePickerOverlay?.hide()
        linePickerOverlay = null
        subtitleSeekHandler.removeCallbacks(subtitleSeekRunnable)
        externalSubtitleHandler.removeCallbacksAndMessages(null)
        // Drop the identity provider so the SubtitleSettings singleton doesn't
        // retain this Activity via the captured lambda (no-op if a newer player
        // already registered its own).
        SubtitleSettings.clearActiveSubtitleIdentityProvider(this)

        // Clear adapters to release lambda references
        playlistView.adapter = null
        playlistAdapter = null
        seriesPlaylistAdapter = null
        moviePlaylistAdapter = null

        // Clean up Stremio sources
        focusRecoveryHandler.removeCallbacksAndMessages(null)
        focusRecoveryRunnable = null
        cancelSourceSwitchWait()
        stremioSources.clear()

        // Clear tab references
        seasonTabs.clear()
        movieTabs.clear()

        // Clear view listeners
        seekbarOverlay.setOnKeyListener(null)

        sendFinished()
        super.onDestroy()
    }


    // ═══════════════════════════════════════════════════════════════
    // STREMIO TV CHANNEL GUIDE
    // ═══════════════════════════════════════════════════════════════

    private fun initStremioTvGuide(guideJson: JSONObject) {
        isStremioTvMode = true
        android.util.Log.d("AndroidTvPlayer", "initStremioTvGuide: Initializing Stremio TV guide")

        val channelsArray = guideJson.optJSONArray("channels") ?: return
        val currentChannelId = guideJson.optString("currentChannelId")

        for (i in 0 until channelsArray.length()) {
            val ch = channelsArray.getJSONObject(i)
            val id = ch.optString("id")

            // Parse inline now playing data (if channel had items at launch time)
            val npJson = ch.optJSONObject("nowPlaying")
            val nextJson = ch.optJSONObject("nextUp")

            stremioTvChannels.add(
                StremioTvGuideChannel(
                    id = id,
                    name = ch.optString("name"),
                    number = ch.optInt("number", i + 1),
                    type = ch.optString("type", "movie"),
                    isFavorite = ch.optBoolean("isFavorite", false),
                    isCurrent = id == currentChannelId,
                    nowPlayingTitle = npJson?.optString("title"),
                    nowPlayingPoster = npJson?.optString("poster")?.takeIf { it.isNotEmpty() },
                    nowPlayingYear = npJson?.optString("year")?.takeIf { it.isNotEmpty() },
                    nowPlayingRating = npJson?.optDouble("rating")?.takeIf { !it.isNaN() },
                    nowPlayingSlotEndMs = npJson?.optLong("slotEndMs", 0) ?: 0,
                    nowPlayingProgress = npJson?.optDouble("progress", 0.0)?.toFloat() ?: 0f,
                    nextUpTitle = nextJson?.optString("title"),
                    nextUpPoster = nextJson?.optString("poster")?.takeIf { it.isNotEmpty() },
                    nextUpYear = nextJson?.optString("year")?.takeIf { it.isNotEmpty() },
                    nextUpRating = nextJson?.optDouble("rating")?.takeIf { !it.isNaN() },
                    hasGuideData = npJson != null,
                    isLoadingGuideData = false,
                )
            )
        }

        android.util.Log.d("AndroidTvPlayer", "initStremioTvGuide: ${stremioTvChannels.size} channels, current=$currentChannelId")
        setupStremioTvGuide()
    }

    private fun setupStremioTvGuide() {
        stremioTvGuideOverlay = findViewById(R.id.stremio_tv_guide_overlay)
        stremioTvGuideList = findViewById(R.id.stremio_tv_guide_list)
        stremioTvGuideSearch = findViewById(R.id.stremio_tv_guide_search)
        stremioTvGuideCountText = findViewById(R.id.stremio_tv_guide_count)
        stremioTvGuideNowPlaying = findViewById(R.id.stremio_tv_guide_now_playing)
        stremioTvGuideNowPoster = findViewById(R.id.stremio_tv_guide_now_poster)
        stremioTvGuideNowLetter = findViewById(R.id.stremio_tv_guide_now_letter)
        stremioTvGuideCurrentName = findViewById(R.id.stremio_tv_guide_current_name)
        stremioTvGuideCurrentTitle = findViewById(R.id.stremio_tv_guide_current_title)

        val guideList = stremioTvGuideList ?: return

        guideList.layoutManager = LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false)
        stremioTvChannelAdapter = StremioTvGuideAdapter(
            channels = stremioTvChannels.toMutableList(),
            onItemClick = { channel ->
                if (!channel.isCurrent && !stremioTvChannelSwitchInProgress) {
                    switchToStremioTvChannel(channel)
                }
            }
        )
        guideList.adapter = stremioTvChannelAdapter

        // Search
        stremioTvGuideSearch?.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                filterStremioTvChannels()
            }
        })

        stremioTvGuideCountText?.text = "${stremioTvChannels.size} channels"

        // Lazy-load guide data when scrolling stops
        guideList.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    requestGuideDataForVisibleChannels()
                }
            }
        })

        // Repurpose playlist button as "Guide" if in Stremio TV mode
        val playlistButton: AppCompatButton? = playerView.findViewById(R.id.debrify_playlist_button)
        if (playlistMode == PlaylistMode.NONE) {
            playlistButton?.text = "Guide"
            playlistButton?.setOnClickListener {
                hideControlsMenu()
                toggleStremioTvGuide()
            }
        }
    }

    private fun showStremioTvGuide() {
        stremioTvGuideVisible = true
        stremioTvGuideOverlay?.animate()?.cancel()
        stremioTvGuideOverlay?.visibility = View.VISIBLE
        stremioTvGuideOverlay?.alpha = 0f
        stremioTvGuideOverlay?.animate()?.alpha(1f)?.setDuration(200)?.start()

        // Reset search
        stremioTvGuideSearch?.setText("")
        filterStremioTvChannels()

        updateStremioTvGuideHeader()

        // Focus the list and scroll to current channel, then lazy-load visible guide data
        stremioTvGuideList?.post {
            val currentPos = stremioTvChannelAdapter?.getCurrentChannelPosition() ?: 0
            stremioTvGuideList?.scrollToPosition(currentPos)
            stremioTvGuideList?.postDelayed({
                val holder = stremioTvGuideList?.findViewHolderForAdapterPosition(currentPos)
                holder?.itemView?.requestFocus()
                requestGuideDataForVisibleChannels()
            }, 150)
        }
    }

    private fun hideStremioTvGuide() {
        stremioTvGuideVisible = false
        cancelGuideWait()
        stremioTvGuideOverlay?.animate()?.cancel()
        stremioTvGuideOverlay?.animate()?.alpha(0f)?.setDuration(150)?.withEndAction {
            stremioTvGuideOverlay?.visibility = View.GONE
        }?.start()
        stremioTvGuideSearch?.setText("")
    }

    private fun toggleStremioTvGuide() {
        if (stremioTvGuideVisible) hideStremioTvGuide() else showStremioTvGuide()
    }

    private fun filterStremioTvChannels() {
        val query = stremioTvGuideSearch?.text?.toString()?.lowercase() ?: ""
        val filtered = stremioTvChannels.filter { ch ->
            query.isEmpty() ||
                ch.name.lowercase().contains(query) ||
                ch.type.lowercase().contains(query) ||
                (ch.nowPlayingTitle?.lowercase()?.contains(query) == true)
        }
        stremioTvChannelAdapter?.updateChannels(filtered)
        stremioTvGuideCountText?.text = "${filtered.size} of ${stremioTvChannels.size} channels"
        // Load guide data for newly-visible channels after filter change
        stremioTvGuideList?.post { requestGuideDataForVisibleChannels() }
    }

    private fun updateStremioTvGuideHeader() {
        val current = stremioTvChannels.firstOrNull { it.isCurrent } ?: return
        stremioTvGuideNowPlaying?.visibility = View.VISIBLE
        stremioTvGuideCurrentName?.text = current.name
        stremioTvGuideCurrentTitle?.text = buildNowPlayingText(current)

        val firstLetter = if (current.name.isNotEmpty()) current.name[0].uppercase() else "?"
        val poster = current.nowPlayingPoster
        if (!poster.isNullOrEmpty()) {
            stremioTvGuideNowLetter?.visibility = View.GONE
            stremioTvGuideNowPoster?.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(this)
                .load(poster)
                .centerCrop()
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?,
                        model: Any?,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                        isFirstResource: Boolean
                    ): Boolean {
                        stremioTvGuideNowPoster?.visibility = View.GONE
                        stremioTvGuideNowLetter?.text = firstLetter
                        stremioTvGuideNowLetter?.visibility = View.VISIBLE
                        return true
                    }
                    override fun onResourceReady(
                        resource: android.graphics.drawable.Drawable,
                        model: Any,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                        dataSource: com.bumptech.glide.load.DataSource,
                        isFirstResource: Boolean
                    ): Boolean = false
                })
                .into(stremioTvGuideNowPoster!!)
        } else {
            stremioTvGuideNowPoster?.visibility = View.GONE
            stremioTvGuideNowLetter?.text = firstLetter
            stremioTvGuideNowLetter?.visibility = View.VISIBLE
        }
    }

    private fun buildNowPlayingText(channel: StremioTvGuideChannel): String {
        val title = channel.nowPlayingTitle ?: return "Loading..."
        val parts = mutableListOf(title)
        if (!channel.nowPlayingYear.isNullOrEmpty()) parts.add("(${channel.nowPlayingYear})")
        if (channel.nowPlayingRating != null && channel.nowPlayingRating!! > 0) {
            parts.add("★ ${String.format(Locale.US, "%.1f", channel.nowPlayingRating)}")
        }
        return parts.joinToString(" ")
    }

    private fun isFocusInStremioTvGuideList(): Boolean {
        val list = stremioTvGuideList ?: return false
        var current = currentFocus
        while (current != null) {
            if (current == list) return true
            val parent = current.parent
            current = if (parent is View) parent else null
        }
        return false
    }

    private fun requestGuideDataForVisibleChannels() {
        val layoutManager = stremioTvGuideList?.layoutManager as? LinearLayoutManager ?: return
        val adapter = stremioTvChannelAdapter ?: return
        val first = layoutManager.findFirstVisibleItemPosition()
        val last = layoutManager.findLastVisibleItemPosition()
        if (first == RecyclerView.NO_POSITION || last == RecyclerView.NO_POSITION) return

        // Expand range by ±3 for prefetch
        val prefetchFirst = (first - 3).coerceAtLeast(0)
        val prefetchLast = (last + 3).coerceAtMost(adapter.itemCount - 1)

        val visibleChannels = (prefetchFirst..prefetchLast).mapNotNull { pos ->
            adapter.getChannelAt(pos)
        }

        val idsToLoad = visibleChannels
            .filter { !it.hasGuideData && !it.isLoadingGuideData }
            .map { it.id }

        if (idsToLoad.isEmpty()) return

        android.util.Log.d("AndroidTvPlayer", "requestGuideDataForVisibleChannels: requesting ${idsToLoad.size} channels (visible $first-$last, prefetch $prefetchFirst-$prefetchLast)")

        // Mark as loading (no notify — avoids focus loss, loading state is cosmetic)
        for (id in idsToLoad) {
            visibleChannels.firstOrNull { it.id == id }?.isLoadingGuideData = true
        }

        try {
            val args = hashMapOf<String, Any?>("channelIds" to idsToLoad)
            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "requestStremioTvGuideData",
                args,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        val data = result as? Map<*, *>
                        runOnUiThread {
                            if (data != null) {
                                for ((key, value) in data) {
                                    val id = key as? String ?: continue
                                    val chData = value as? Map<*, *> ?: continue
                                    val ch = stremioTvChannels.firstOrNull { it.id == id } ?: continue

                                    val np = chData["nowPlaying"] as? Map<*, *>
                                    val next = chData["nextUp"] as? Map<*, *>

                                    if (np != null) {
                                        ch.nowPlayingTitle = np["title"] as? String
                                        ch.nowPlayingPoster = (np["poster"] as? String)?.takeIf { it.isNotEmpty() }
                                        ch.nowPlayingYear = (np["year"] as? String)?.takeIf { it.isNotEmpty() }
                                        ch.nowPlayingRating = (np["rating"] as? Number)?.toDouble()
                                        ch.nowPlayingSlotEndMs = (np["slotEndMs"] as? Number)?.toLong() ?: 0
                                        ch.nowPlayingProgress = (np["progress"] as? Number)?.toFloat() ?: 0f
                                    }
                                    if (next != null) {
                                        ch.nextUpTitle = next["title"] as? String
                                        ch.nextUpPoster = (next["poster"] as? String)?.takeIf { it.isNotEmpty() }
                                        ch.nextUpYear = (next["year"] as? String)?.takeIf { it.isNotEmpty() }
                                        ch.nextUpRating = (next["rating"] as? Number)?.toDouble()
                                    }
                                    ch.hasGuideData = true
                                    ch.isLoadingGuideData = false

                                    // Targeted partial update — preserves DPAD focus & scale
                                    val pos = adapter.getPositionById(id)
                                    if (pos >= 0) adapter.notifyItemChanged(pos, StremioTvGuideAdapter.PAYLOAD_GUIDE_DATA)
                                }
                            } else {
                                for (id in idsToLoad) {
                                    stremioTvChannels.firstOrNull { it.id == id }?.isLoadingGuideData = false
                                }
                            }
                            updateStremioTvGuideHeader()
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        android.util.Log.e("AndroidTvPlayer", "requestGuideDataForVisibleChannels error: $errorCode - $errorMessage")
                        runOnUiThread {
                            for (id in idsToLoad) {
                                stremioTvChannels.firstOrNull { it.id == id }?.isLoadingGuideData = false
                            }
                        }
                    }

                    override fun notImplemented() {
                        runOnUiThread {
                            for (id in idsToLoad) {
                                stremioTvChannels.firstOrNull { it.id == id }?.isLoadingGuideData = false
                            }
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "requestGuideDataForVisibleChannels exception", e)
            runOnUiThread {
                for (id in idsToLoad) {
                    stremioTvChannels.firstOrNull { it.id == id }?.isLoadingGuideData = false
                }
            }
        }
    }

    private fun updateStremioTvGuideChannelData(
        channel: StremioTvGuideChannel,
        data: Map<*, *>
    ) {
        val np = data["nowPlaying"] as? Map<*, *>
        if (np != null) {
            channel.nowPlayingTitle = np["title"] as? String
            channel.nowPlayingPoster = (np["poster"] as? String)?.takeIf { it.isNotEmpty() }
            channel.nowPlayingYear = (np["year"] as? String)?.takeIf { it.isNotEmpty() }
            channel.nowPlayingRating = (np["rating"] as? Number)?.toDouble()
            channel.nowPlayingSlotEndMs = (np["slotEndMs"] as? Number)?.toLong() ?: 0
            channel.nowPlayingProgress = (np["progress"] as? Number)?.toFloat() ?: 0f
            channel.hasGuideData = true
        }

        val next = data["nextUp"] as? Map<*, *>
        if (next != null) {
            channel.nextUpTitle = next["title"] as? String
            channel.nextUpPoster = (next["poster"] as? String)?.takeIf { it.isNotEmpty() }
            channel.nextUpYear = (next["year"] as? String)?.takeIf { it.isNotEmpty() }
            channel.nextUpRating = (next["rating"] as? Number)?.toDouble()
        }
        channel.isLoadingGuideData = false
    }

    private fun updateStremioSourcesFromPlaybackMap(map: Map<*, *>) {
        val newSources = map["stremioSources"] as? List<*>
        val newSourceIndex = (map["stremioCurrentSourceIndex"] as? Number)?.toInt() ?: 0
        if (newSources != null) {
            stremioSources.clear()
            for ((idx, src) in newSources.withIndex()) {
                val srcMap = src as? Map<*, *> ?: continue
                stremioSources.add(StremioSource.fromMap(srcMap, idx))
            }
            currentStremioSourceIndex = newSourceIndex.coerceIn(
                0,
                stremioSources.lastIndex.coerceAtLeast(0)
            )
            setupStremioSources()
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

        payload?.let { model ->
            val previousItem = model.items.getOrNull(currentIndex)
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
            currentIndex = 0
        }
    }

    private fun playStremioTvPlaybackMap(
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
        updateStremioTvGuideHeader()
        updateStremioQualityBadge()
        if (stremioSources.isNotEmpty()) {
            stremioSourceBadge?.visibility = View.VISIBLE
        } else {
            stremioSourceBadge?.visibility = View.GONE
        }

        resetSubtitleState()
        clearStremioLoadingState()
        cancelPikPakRetry()

        // Route the channel's slot-progress seek through the shared resume
        // machinery instead of an isolated inline listener. The main
        // playbackListener applies the seek on STATE_READY. (Subtitle loads are
        // side-rendered and never seek, so they can't clobber it.)
        payload?.startAtPercent = startAtPercent
        percentSeekApplied = false
        pendingSeekMs = 0
        // Clear any leftover per-episode tracker percent from a torrent item whose
        // READY never fired (rapid switch mid-buffer) — the resume branch now
        // arms on it, and a live channel must never seek to a stale tracker offset.
        pendingItemTraktPercent = 0.0
        hasEverBeenReady = false

        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .build()
        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(metadata)
            .build()

        player?.apply {
            setMediaItem(mediaItem)
            prepare()
            playWhenReady = true
            play()
        }

        val playbackItem = payload?.items?.getOrNull(currentIndex) ?: PlaybackItem(
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

        updateTitle(playbackItem)
        fetchStremioSubtitles(playbackItem)

        channel.isSwitchingChannel = false
        stremioTvChannelAdapter?.notifyDataSetChanged()
        if (hideGuideOnReady) {
            hideGuideWhenReady()
        }
    }

    private fun requestStremioTvNext(finishOnFailure: Boolean = false) {
        if (stremioTvNextInProgress || stremioTvChannelSwitchInProgress) return

        val channel = stremioTvChannels.firstOrNull { it.isCurrent }
        if (channel == null) {
            Toast.makeText(this, "Channel unavailable", Toast.LENGTH_SHORT).show()
            if (finishOnFailure) finish()
            return
        }

        val methodChannel = MainActivity.getAndroidTvPlayerChannel()
        if (methodChannel == null) {
            Toast.makeText(this, "Playback bridge unavailable", Toast.LENGTH_SHORT).show()
            if (finishOnFailure) finish()
            return
        }

        stremioTvNextInProgress = true
        stremioTvSwitchToken++
        val token = stremioTvSwitchToken

        nextText.text = channel.nextUpTitle ?: channel.name
        nextSubtext.visibility = View.GONE
        fadeInNextOverlay()

        try {
            val args = hashMapOf<String, Any?>("channelId" to channel.id)
            methodChannel.invokeMethod(
                "requestStremioTvNext",
                args,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (token != stremioTvSwitchToken) return
                        runOnUiThread {
                            stremioTvNextInProgress = false
                            val map = result as? Map<*, *>
                            val url = map?.get("url") as? String
                            if (url.isNullOrEmpty()) {
                                hideNextOverlay()
                                Toast.makeText(this@AndroidTvTorrentPlayerActivity, "Next item unavailable", Toast.LENGTH_SHORT).show()
                                if (finishOnFailure) finish()
                                return@runOnUiThread
                            }

                            val title = map["title"] as? String ?: channel.name
                            nextText.text = title
                            nextSubtext.visibility = View.GONE

                            playStremioTvPlaybackMap(
                                channel = channel,
                                map = map,
                                url = url,
                                title = title,
                                hideGuideOnReady = false
                            )
                            progressHandler.postDelayed({ hideNextOverlay() }, 1500)
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (token != stremioTvSwitchToken) return
                        runOnUiThread {
                            stremioTvNextInProgress = false
                            hideNextOverlay()
                            Toast.makeText(
                                this@AndroidTvTorrentPlayerActivity,
                                errorMessage ?: "Failed to load next item",
                                Toast.LENGTH_SHORT
                            ).show()
                            if (finishOnFailure) finish()
                        }
                    }

                    override fun notImplemented() {
                        if (token != stremioTvSwitchToken) return
                        runOnUiThread {
                            stremioTvNextInProgress = false
                            hideNextOverlay()
                            if (finishOnFailure) finish()
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "requestStremioTvNext exception", e)
            stremioTvNextInProgress = false
            hideNextOverlay()
            if (finishOnFailure) finish()
        }
    }

    private fun switchToStremioTvChannel(channel: StremioTvGuideChannel) {
        if (stremioTvChannelSwitchInProgress || stremioTvNextInProgress) return
        stremioTvChannelSwitchInProgress = true
        stremioTvSwitchToken++
        val token = stremioTvSwitchToken

        android.util.Log.d("AndroidTvPlayer", "switchToStremioTvChannel: ${channel.name} (id=${channel.id})")

        // Mark channel as switching (inline loading in guide)
        val previousCurrent = stremioTvChannels.firstOrNull { it.isCurrent }
        stremioTvChannels.forEach { it.isCurrent = false; it.isSwitchingChannel = false }
        channel.isCurrent = true
        channel.isSwitchingChannel = true
        stremioTvChannelAdapter?.notifyDataSetChanged()

        try {
            val args = hashMapOf<String, Any?>("channelId" to channel.id)
            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "requestStremioTvChannelSwitch",
                args,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (token != stremioTvSwitchToken) {
                            android.util.Log.d("AndroidTvPlayer", "stale channel switch token $token (current: $stremioTvSwitchToken)")
                            return
                        }
                        runOnUiThread {
                            stremioTvChannelSwitchInProgress = false
                            val map = result as? Map<*, *>
                            val url = map?.get("url") as? String
                            if (url.isNullOrEmpty()) {
                                android.util.Log.e("AndroidTvPlayer", "channel switch returned null URL")
                                Toast.makeText(this@AndroidTvTorrentPlayerActivity, "Channel switch failed", Toast.LENGTH_SHORT).show()
                                // Revert current marker
                                channel.isSwitchingChannel = false
                                channel.isCurrent = false
                                previousCurrent?.isCurrent = true
                                stremioTvChannelAdapter?.notifyDataSetChanged()
                                return@runOnUiThread
                            }

                            val title = map["title"] as? String ?: channel.name
                            playStremioTvPlaybackMap(
                                channel = channel,
                                map = map,
                                url = url,
                                title = title,
                                hideGuideOnReady = true
                            )
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (token != stremioTvSwitchToken) return
                        android.util.Log.e("AndroidTvPlayer", "channel switch error: $errorCode - $errorMessage")
                        runOnUiThread {
                            stremioTvChannelSwitchInProgress = false
                            Toast.makeText(this@AndroidTvTorrentPlayerActivity, "Channel switch failed: $errorMessage", Toast.LENGTH_SHORT).show()
                            channel.isSwitchingChannel = false
                            channel.isCurrent = false
                            previousCurrent?.isCurrent = true
                            stremioTvChannelAdapter?.notifyDataSetChanged()
                        }
                    }

                    override fun notImplemented() {
                        if (token != stremioTvSwitchToken) return
                        runOnUiThread {
                            stremioTvChannelSwitchInProgress = false
                            channel.isSwitchingChannel = false
                            channel.isCurrent = false
                            previousCurrent?.isCurrent = true
                            stremioTvChannelAdapter?.notifyDataSetChanged()
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "switchToStremioTvChannel exception", e)
            stremioTvChannelSwitchInProgress = false
            channel.isSwitchingChannel = false
            channel.isCurrent = false
            previousCurrent?.isCurrent = true
            stremioTvChannelAdapter?.notifyDataSetChanged()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // COMPANION OBJECT
    // ═══════════════════════════════════════════════════════════════

    companion object {
        const val PAYLOAD_KEY = "payload"
        private const val DECODER_LOG_TAG = "DEBRIFY_PLAYER_DECODER"
        /**
         * When true, the dock buttons (Audio, Subs, Fill, Speed, Night, Shuffle) open the
         * unified Miller-columns menu instead of the individual dialogs/panels. Additive —
         * flip to false to restore the exact prior behaviour.
         */
        private const val USE_UNIFIED_MENU = true
        private const val PROGRESS_INTERVAL_MS = 5_000L
        private const val UP_NEXT_THRESHOLD_MS = 25_000L   // show card when this much remains
        private const val UP_NEXT_MIN_DURATION_MS = 5 * 60_000L  // skip for short clips
        private const val UP_NEXT_TICK_MS = 500L
        private const val CONTROLS_AUTO_HIDE_DELAY_MS = 4000L
        private const val SEEK_STEP_MS = 10_000L
        private const val SEEK_LONG_PRESS_THRESHOLD = 3
        private const val BACK_PRESS_INTERVAL_MS = 2000L  // 2 seconds
        private const val SEARCH_SUBTITLE_LABEL = "Search Movie/Show Subtitles"
        private const val SUBTITLE_LOADING_LABEL = "⏳ Loading external subtitles..."
        private const val EXTERNAL_SUBTITLE_TICK_MS = 250L
        private const val EXTERNAL_SUBTITLE_PREFIX = "⬇"
        private const val MAX_SKIP_SEGMENT_CACHE_ENTRIES = 64
        private val IMDB_ID_REGEX = Regex("^tt\\d+$")

        // PikPak cold storage retry constants
        private const val PROVIDER_PIKPAK = "pikpak"
        private const val PIKPAK_MAX_RETRIES = 5
        private const val PIKPAK_METADATA_TIMEOUT_MS = 10000  // 10 seconds to wait for metadata
        private const val PIKPAK_BASE_DELAY_MS = 2000  // 2 seconds base delay
        private const val PIKPAK_MAX_DELAY_MS = 18000  // 18 seconds max delay
    }
}

private enum class PlaylistMode { NONE, SERIES, COLLECTION }

private data class CollectionGroup(
    val name: String,
    val fileIndices: List<Int>,
)

private data class MovieGroups(
    val groups: List<CollectionGroup>,
) {
    // Helper to get group by index
    fun getGroup(index: Int): CollectionGroup? = groups.getOrNull(index)

    // Helper to find which group contains a file index
    fun findGroupContaining(fileIndex: Int): CollectionGroup? {
        return groups.firstOrNull { it.fileIndices.contains(fileIndex) }
    }

    // Helper to get group index for a file
    fun getGroupIndex(fileIndex: Int): Int {
        return groups.indexOfFirst { it.fileIndices.contains(fileIndex) }
    }
}

private data class MovieTab(
    val view: TextView,
    val groupIndex: Int, // Index into MovieGroups.groups list
    val groupName: String,
)

private interface PlaylistOverlayAdapter {
    fun setActiveIndex(index: Int)
    fun updateCurrentProgress()
    fun getActiveItemPosition(): Int
}

// ═══════════════════════════════════════════════════════════════════════
// Stremio Source Switcher — Data model and adapter
// ═══════════════════════════════════════════════════════════════════════

private data class StremioSource(
    val index: Int,
    val name: String,
    val infohash: String,
    val directUrl: String?,
    val streamType: String,  // "torrent", "directUrl"
    val sizeBytes: Long,
    val seeders: Int,
    val source: String?,
    val quality: String,     // parsed: "4K", "1080p", "720p", "480p", "HD"
    // Coverage stamped by the Dart search engines: 'completeSeries',
    // 'multiSeasonPack', 'seasonPack', 'singleEpisode', or null (unknown).
    val coverageType: String? = null,
) {
    val isDirectStream: Boolean get() = streamType == "directUrl"

    /** Season/series-pack coverage — drives the series source-tab split. */
    val isSeasonPack: Boolean get() = coverageType == "seasonPack" ||
        coverageType == "multiSeasonPack" || coverageType == "completeSeries"

    val displayTitle: String get() {
        val newlineIdx = name.indexOf('\n')
        if (newlineIdx <= 0) return name
        val firstLine = name.substring(0, newlineIdx).trim()
        val rest = name.substring(newlineIdx + 1).trim()
        // If first line is just the addon/source name, use the rest instead
        return if (rest.isNotEmpty() && (firstLine.equals(source, ignoreCase = true) ||
                firstLine.length < 20 && rest.length > firstLine.length)) rest.split('\n').first().trim()
            else firstLine
    }

    val formattedSize: String? get() {
        if (sizeBytes <= 0) return null
        val gb = sizeBytes / (1024.0 * 1024.0 * 1024.0)
        val mb = sizeBytes / (1024.0 * 1024.0)
        return if (gb >= 1.0) String.format("%.1f GB", gb) else String.format("%.0f MB", mb)
    }

    companion object {
        fun fromJson(obj: JSONObject, index: Int): StremioSource {
            val name = obj.optString("name", "")
            return StremioSource(
                index = index,
                name = name,
                infohash = obj.optString("infohash", ""),
                directUrl = obj.optString("direct_url").takeIf { it.isNotEmpty() },
                streamType = obj.optString("stream_type", "torrent"),
                sizeBytes = obj.optLong("size_bytes", 0),
                seeders = obj.optInt("seeders", 0),
                source = obj.optString("source").takeIf { it.isNotEmpty() },
                quality = parseQuality(name),
                coverageType = obj.optString("coverage_type").takeIf { it.isNotEmpty() },
            )
        }

        fun fromMap(map: Map<*, *>, index: Int): StremioSource {
            val name = (map["name"] as? String) ?: ""
            return StremioSource(
                index = index,
                name = name,
                infohash = (map["infohash"] as? String) ?: "",
                directUrl = (map["direct_url"] as? String)?.takeIf { it.isNotEmpty() },
                streamType = (map["stream_type"] as? String) ?: "torrent",
                sizeBytes = (map["size_bytes"] as? Number)?.toLong() ?: 0,
                seeders = (map["seeders"] as? Number)?.toInt() ?: 0,
                source = (map["source"] as? String)?.takeIf { it.isNotEmpty() },
                quality = parseQuality(name),
                coverageType = (map["coverage_type"] as? String)?.takeIf { it.isNotEmpty() },
            )
        }

        fun parseQuality(name: String): String {
            return SourceQualityParser.badge(name) ?: "HD"
        }
    }
}

private data class PlaybackPayload(
    val title: String,
    val subtitle: String?,
    var contentType: String,
    val items: MutableList<PlaybackItem>,
    val startIndex: Int,
    val seriesTitle: String?,
    var nextEpisodeMap: Map<Int, Int> = emptyMap(),
    var prevEpisodeMap: Map<Int, Int> = emptyMap(),
    var collectionGroups: List<JSONObject>? = null, // Collection groups from Flutter
    var imdbId: String? = null, // IMDB ID for fetching external subtitles from Stremio addons (var to allow async discovery from TVMaze)
    val httpHeaders: Map<String, String> = emptyMap(), // Optional per-session headers for protected direct streams
    val perItemImdbIds: MutableMap<Int, String?> = mutableMapOf(), // Per-item IMDB IDs for movie collections (caches Cinemeta lookups)
    var startAtPercent: Double = 0.0, // Start video at this fraction (0.0 to 1.0) of duration — var so Stremio TV channel switches can update it
    val traktProgressPercent: Double = 0.0, // Trakt watch progress (0-100) for resume — takes priority over local resume
    val localCompletionTracking: Boolean = false,
    val movieCompletionThreshold: Int = 80,
    val episodeCompletionThreshold: Int = 80,
    // Full-show episode guide (TVMaze), delivered post-launch via the
    // metadata broadcast: every episode of the show, present in the
    // playlist or not. Empty until (unless) the fetch lands.
    val guideEpisodes: MutableList<GuideEpisode> = mutableListOf(),
)

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
private data class GuideEpisode(
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

private data class PlaybackItem(
    val id: String,
    val title: String,
    val url: String,
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
        val local = if (durationMs > 0 && resumePositionMs > 0) {
            ((resumePositionMs.toDouble() / durationMs.toDouble()) * 100).toInt()
        } else {
            0
        }
        val trakt = traktProgressPercent?.toInt() ?: 0
        // resumePositionMs > 0 (not local >= 1): a just-started rewatch of a long
        // episode truncates to local == 0% but is still an active rewatch —
        // matching the Dart series-browser's `local > 0` bound.
        if (trakt >= 95 && resumePositionMs > 0 && local < 95) return local
        return maxOf(local, trakt)
    }

    companion object {
        fun fromJson(obj: JSONObject): PlaybackItem {
            return PlaybackItem(
                id = obj.optString("id"),
                title = obj.optString("title"),
                url = obj.optString("url"),
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
            )
        }
    }
}

private data class SubtitleCatalogResult(
    val imdbId: String,
    val type: String,
    val name: String,
    val year: String?,
    val source: String?,
) {
    fun titleLine(): String {
        return if (!year.isNullOrEmpty()) "$name ($year)" else name
    }

    fun detailLine(): String {
        val parts = mutableListOf(if (type == "series") "Series" else "Movie")
        if (!source.isNullOrEmpty()) parts.add(source)
        parts.add(imdbId)
        return parts.joinToString(" · ")
    }
}

private data class SeasonEpisode(
    val season: Int,
    val episode: Int,
)

// Sealed class for playlist items (header or episode)
private sealed class PlaylistListItem {
    data class SeasonHeader(val season: Int, val episodeCount: Int) : PlaylistListItem()
    data class Episode(val itemIndex: Int) : PlaylistListItem()
    // Full-guide mode: an episode of the show that is NOT in the playlist —
    // rendered dimmed; clicking it fetches the episode in-player.
    data class MissingEpisode(val guideIndex: Int) : PlaylistListItem()
}

private class PlaylistAdapter(
    private val items: List<PlaybackItem>,
    private val guide: List<GuideEpisode> = emptyList(),
    private val onFetchEpisode: ((Int, Int) -> Unit)? = null,
    private val onItemClick: (Int) -> Unit,
) : RecyclerView.Adapter<RecyclerView.ViewHolder>(), PlaylistOverlayAdapter {
    private var activeItemIndex = -1
    private val listItems = mutableListOf<PlaylistListItem>()
    private var selectedSeason: Int? = null

    val availableSeasons: List<Int> by lazy {
        (items.mapNotNull { it.season } + guide.map { it.season }).distinct().sorted()
    }

    init {
        // Show all seasons initially
        buildList(null)
    }

    fun filterBySeason(season: Int?) {
        selectedSeason = season
        buildList(season)
        notifyDataSetChanged()
    }

    private fun buildList(filterSeason: Int?) {
        listItems.clear()

        // Group episodes by season; in full-guide mode the seasons and rows
        // are the union of the playlist and the show's TVMaze episode list.
        val grouped = items.groupBy { it.season ?: 0 }
        val guideGrouped = guide.groupBy { it.season }
        val sortedSeasons = (grouped.keys + guideGrouped.keys).distinct().sorted()

        for (season in sortedSeasons) {
            // Skip seasons that don't match filter
            if (filterSeason != null && season != filterSeason) {
                continue
            }

            val episodesInSeason = grouped[season] ?: emptyList()
            val guideInSeason = (guideGrouped[season] ?: emptyList()).sortedBy { it.episode }

            // Guide order first: playlist row when present, fetchable
            // placeholder when not. Playlist files the guide doesn't know
            // about keep showing after them, in episode order.
            val rows = mutableListOf<PlaylistListItem>()
            val usedIndices = mutableSetOf<Int>()
            for (g in guideInSeason) {
                val matchIdx = items.indexOfFirst {
                    (it.season ?: 0) == season && it.episode == g.episode
                }
                if (matchIdx >= 0) {
                    rows.add(PlaylistListItem.Episode(matchIdx))
                    usedIndices.add(matchIdx)
                } else {
                    rows.add(PlaylistListItem.MissingEpisode(guide.indexOf(g)))
                }
            }
            // Sort episodes by episode number (integer comparison to avoid "1", "10", "11", "2" string sorting)
            val sortedEpisodes = episodesInSeason.sortedBy { it.episode ?: 0 }
            for (episode in sortedEpisodes) {
                val originalIndex = items.indexOf(episode)
                if (originalIndex in usedIndices) continue
                rows.add(PlaylistListItem.Episode(originalIndex))
            }

            if (rows.isEmpty()) continue

            // Don't show season header when filtering (tabs show the season)
            // Only show header when showing all seasons
            if (filterSeason == null && season > 0) {
                listItems.add(PlaylistListItem.SeasonHeader(season, rows.size))
            }
            listItems.addAll(rows)
        }
    }

    override fun getItemViewType(position: Int): Int {
        return when (listItems[position]) {
            is PlaylistListItem.SeasonHeader -> VIEW_TYPE_HEADER
            is PlaylistListItem.Episode -> VIEW_TYPE_EPISODE
            is PlaylistListItem.MissingEpisode -> VIEW_TYPE_EPISODE
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = android.view.LayoutInflater.from(parent.context)
        return when (viewType) {
            VIEW_TYPE_HEADER -> {
                val view = inflater.inflate(R.layout.item_android_tv_season_header, parent, false)
                SeasonHeaderViewHolder(view)
            }
            VIEW_TYPE_EPISODE -> {
                val view = inflater.inflate(R.layout.item_android_tv_playlist_entry_horizontal, parent, false)
                EpisodeViewHolder(view, onItemClick)
            }
            else -> throw IllegalArgumentException("Unknown view type: $viewType")
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val listItem = listItems[position]) {
            is PlaylistListItem.SeasonHeader -> {
                (holder as SeasonHeaderViewHolder).bind(listItem.season, listItem.episodeCount)
            }
            is PlaylistListItem.Episode -> {
                val itemIndex = listItem.itemIndex
                val item = items[itemIndex]  // Fetch current item from items list
                val isActive = itemIndex == activeItemIndex
                (holder as EpisodeViewHolder).bind(item, itemIndex, isActive)
            }
            is PlaylistListItem.MissingEpisode -> {
                val g = guide[listItem.guideIndex]
                val synthetic = PlaybackItem(
                    id = "guide_${g.season}_${g.episode}",
                    title = g.title ?: "Episode ${g.episode}",
                    url = "",
                    index = -1,
                    season = g.season,
                    episode = g.episode,
                    artwork = g.artwork,
                    description = g.description,
                    resumePositionMs = g.resumePositionMs ?: 0,
                    durationMs = g.durationMs?.takeIf { it > 0 }
                        ?: (g.runtime ?: 0) * 60_000L,
                    updatedAt = 0,
                    resumeId = null,
                    sizeBytes = null,
                    rating = g.rating,
                    provider = null,
                    traktProgressPercent = g.trackerProgressPercent,
                    watched = g.watched,
                )
                (holder as EpisodeViewHolder).bindMissing(synthetic) {
                    onFetchEpisode?.invoke(g.season, g.episode)
                }
            }
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isEmpty() || PAYLOAD_PROGRESS_UPDATE !in payloads) {
            super.onBindViewHolder(holder, position, payloads)
            return
        }

        // Handle progress-only update
        when (val listItem = listItems[position]) {
            is PlaylistListItem.Episode -> {
                val itemIndex = listItem.itemIndex
                val item = items[itemIndex]
                val isActive = itemIndex == activeItemIndex
                (holder as EpisodeViewHolder).updateProgress(item, isActive)
            }
            else -> {
                // Not an episode, do nothing
            }
        }
    }

    override fun getItemCount(): Int = listItems.size

    override fun setActiveIndex(index: Int) {
        val previousActivePosition = findPositionForItemIndex(activeItemIndex)
        activeItemIndex = index
        val newActivePosition = findPositionForItemIndex(activeItemIndex)

        if (previousActivePosition != -1) {
            notifyItemChanged(previousActivePosition)
        }
        if (newActivePosition != -1) {
            notifyItemChanged(newActivePosition)
        }
    }

    override fun updateCurrentProgress() {
        // Notify the current playing item to update its progress display with payload
        val position = findPositionForItemIndex(activeItemIndex)
        if (position != -1) {
            notifyItemChanged(position, PAYLOAD_PROGRESS_UPDATE)
        }
    }

    private fun findPositionForItemIndex(itemIndex: Int): Int {
        return listItems.indexOfFirst {
            it is PlaylistListItem.Episode && it.itemIndex == itemIndex
        }
    }

    override fun getActiveItemPosition(): Int {
        return findPositionForItemIndex(activeItemIndex)
    }

    // Season Header ViewHolder - explicitly non-focusable to prevent focus getting stuck
    class SeasonHeaderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val titleView: TextView = itemView.findViewById(R.id.season_header_title)
        private val subtitleView: TextView = itemView.findViewById(R.id.season_header_subtitle)

        init {
            // Headers are visual separators, not interactive items
            // Must be explicitly non-focusable to prevent D-pad navigation from landing here
            itemView.isFocusable = false
            itemView.isFocusableInTouchMode = false
            itemView.isClickable = false
        }

        fun bind(season: Int, episodeCount: Int) {
            titleView.text = "SEASON $season"
            subtitleView.text = "$episodeCount Episode${if (episodeCount != 1) "s" else ""}"
        }
    }

    // Cinema Cards v2 - Episode ViewHolder
    class EpisodeViewHolder(
        itemView: View,
        private val onItemClick: (Int) -> Unit
    ) : RecyclerView.ViewHolder(itemView) {
        // Container & focus elements
        private val container: View = itemView.findViewById(R.id.android_tv_playlist_item_container)
        private val focusBorder: View? = itemView.findViewById(R.id.focus_border)
        private val cardContent: View? = itemView.findViewById(R.id.card_content)

        // Artwork elements
        private val posterImageView: android.widget.ImageView = itemView.findViewById(R.id.android_tv_playlist_item_poster)
        private val shimmerOverlay: View? = itemView.findViewById(R.id.shimmer_overlay)
        private val fallbackContainer: View? = itemView.findViewById(R.id.fallback_container)
        private val fallbackBg: View? = itemView.findViewById(R.id.fallback_bg)
        private val fallbackTextView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_fallback)
        private val watchedOverlay: View = itemView.findViewById(R.id.android_tv_playlist_item_watched_overlay)
        private val watchedIcon: TextView = itemView.findViewById(R.id.android_tv_playlist_item_watched_icon)
        private val posterProgress: android.widget.ProgressBar = itemView.findViewById(R.id.android_tv_playlist_item_poster_progress)
        private val nowPlayingRing: View? = itemView.findViewById(R.id.now_playing_ring)

        // Info elements
        private val badgeView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_badge)
        private val ratingBadge: View = itemView.findViewById(R.id.android_tv_playlist_item_rating_badge)
        private val ratingText: TextView = itemView.findViewById(R.id.android_tv_playlist_item_rating_text)
        private val nowPlayingIndicator: View? = itemView.findViewById(R.id.now_playing_indicator)
        private val nowPlayingDot: View? = itemView.findViewById(R.id.now_playing_dot)
        private val titleView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_title)
        private val descriptionView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_description)
        private val durationView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_duration)
        private val metaSeparator: View? = itemView.findViewById(R.id.meta_separator)
        private val progressText: TextView = itemView.findViewById(R.id.android_tv_playlist_item_progress_text)
        private val watchedView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_watched)

        // Animators
        private var pulseAnimator: android.animation.ObjectAnimator? = null

        fun bind(item: PlaybackItem, itemIndex: Int, isActive: Boolean) {
            // Recycled views may come back from a dimmed missing-episode row.
            itemView.alpha = 1.0f

            // Episode badge with cleaner format
            val seasonNum = item.season
            val episodeNum = item.episode
            val badge = when {
                seasonNum != null && episodeNum != null -> "S${seasonNum.toString().padStart(2, '0')} E${episodeNum.toString().padStart(2, '0')}"
                episodeNum != null -> "E${episodeNum.toString().padStart(2, '0')}"
                else -> "E${(itemIndex + 1).toString().padStart(2, '0')}"
            }
            badgeView.text = badge

            // Title
            titleView.text = item.title

            // Description - filter out "null" string bug
            val cleanDescription = item.description
                ?.trim()
                ?.takeUnless { it.equals("null", ignoreCase = true) || it.isBlank() }
            if (cleanDescription != null) {
                descriptionView.text = cleanDescription
                descriptionView.visibility = View.VISIBLE
            } else {
                descriptionView.visibility = View.GONE
            }

            // IMDB Rating
            if (item.rating != null && item.rating > 0) {
                ratingText.text = String.format("%.1f", item.rating)
                ratingBadge.visibility = View.VISIBLE
            } else {
                ratingBadge.visibility = View.GONE
            }

            // Duration
            val hasDuration = item.durationMs > 0
            if (hasDuration) {
                val mins = (item.durationMs / 60000).toInt()
                durationView.text = "${mins} min"
                durationView.visibility = View.VISIBLE
            } else {
                durationView.visibility = View.GONE
            }

            // Progress calculation
            val progressPercent = item.displayProgressPercent()

            val isWatched = progressPercent >= 95
            val hasProgress = progressPercent > 5 && progressPercent < 95

            // Watched state - subtle dimming
            container.alpha = if (isWatched && !isActive) 0.5f else 1.0f
            watchedOverlay.visibility = View.GONE
            watchedIcon.visibility = View.GONE
            watchedView.visibility = if (isWatched && !isActive) View.VISIBLE else View.GONE

            // Now Playing state - simple, no fading animations
            if (isActive) {
                nowPlayingIndicator?.visibility = View.VISIBLE
                nowPlayingRing?.visibility = View.VISIBLE
                startDotPulse()
            } else {
                nowPlayingIndicator?.visibility = View.GONE
                nowPlayingRing?.visibility = View.GONE
                stopDotPulse()
            }

            // Progress display
            if (hasProgress && !isWatched) {
                progressText.text = "${progressPercent}%"
                progressText.visibility = View.VISIBLE
                metaSeparator?.visibility = if (hasDuration) View.VISIBLE else View.GONE
                posterProgress.max = 100
                posterProgress.progress = progressPercent
                posterProgress.visibility = View.VISIBLE
            } else if (isWatched) {
                // Show 100% for watched
                progressText.visibility = View.GONE
                metaSeparator?.visibility = View.GONE
                posterProgress.max = 100
                posterProgress.progress = 100
                posterProgress.visibility = View.VISIBLE
            } else {
                progressText.visibility = View.GONE
                metaSeparator?.visibility = View.GONE
                posterProgress.visibility = View.GONE
            }

            // Load artwork
            loadPosterImage(item)

            // Selection state
            container.isSelected = isActive

            // Reset scale state
            cardContent?.scaleX = 1.0f
            cardContent?.scaleY = 1.0f
            cardContent?.elevation = 8f
            focusBorder?.visibility = View.GONE

            // Click handler - set on itemView for better touch handling
            itemView.setOnClickListener { onItemClick(itemIndex) }

            // Focus handling with scale + glow (no interference with navigation)
            container.onFocusChangeListener = View.OnFocusChangeListener { _, hasFocus ->
                if (hasFocus) {
                    // Focus animation - scale up, show border, raise elevation
                    cardContent?.animate()
                        ?.scaleX(1.08f)
                        ?.scaleY(1.08f)
                        ?.setDuration(150)
                        ?.setInterpolator(android.view.animation.DecelerateInterpolator())
                        ?.start()
                    cardContent?.elevation = 16f
                    focusBorder?.visibility = View.VISIBLE
                } else {
                    cardContent?.animate()
                        ?.scaleX(1.0f)
                        ?.scaleY(1.0f)
                        ?.setDuration(100)
                        ?.setInterpolator(android.view.animation.DecelerateInterpolator())
                        ?.start()
                    cardContent?.elevation = 8f
                    focusBorder?.visibility = View.GONE
                }
            }
        }

        /** Absent guide episode: dimmed, and the click fetches instead of playing. */
        fun bindMissing(item: PlaybackItem, onFetch: () -> Unit) {
            bind(item, itemIndex = -1, isActive = false)
            itemView.alpha = 0.55f
            itemView.setOnClickListener { onFetch() }
        }

        fun updateProgress(item: PlaybackItem, isActive: Boolean) {
            val progressPercent = item.displayProgressPercent()

            val isWatched = progressPercent >= 95
            val hasProgress = progressPercent > 5 && progressPercent < 95
            val hasDuration = item.durationMs > 0

            container.alpha = if (isWatched && !isActive) 0.5f else 1.0f
            watchedView.visibility = if (isWatched && !isActive) View.VISIBLE else View.GONE

            if (isActive) {
                nowPlayingIndicator?.visibility = View.VISIBLE
                nowPlayingRing?.visibility = View.VISIBLE
                startDotPulse()
            } else {
                nowPlayingIndicator?.visibility = View.GONE
                nowPlayingRing?.visibility = View.GONE
                stopDotPulse()
            }

            if (hasProgress && !isWatched) {
                progressText.text = "${progressPercent}%"
                progressText.visibility = View.VISIBLE
                metaSeparator?.visibility = if (hasDuration) View.VISIBLE else View.GONE
                posterProgress.max = 100
                posterProgress.progress = progressPercent
                posterProgress.visibility = View.VISIBLE
            } else if (isWatched) {
                progressText.visibility = View.GONE
                metaSeparator?.visibility = View.GONE
                posterProgress.max = 100
                posterProgress.progress = 100
                posterProgress.visibility = View.VISIBLE
            } else {
                progressText.visibility = View.GONE
                metaSeparator?.visibility = View.GONE
                posterProgress.visibility = View.GONE
            }
        }

        private fun startDotPulse() {
            if (pulseAnimator?.isRunning == true) return
            nowPlayingDot?.let { dot ->
                pulseAnimator = android.animation.ObjectAnimator.ofFloat(dot, "alpha", 1f, 0.3f, 1f).apply {
                    duration = 1000
                    repeatCount = android.animation.ObjectAnimator.INFINITE
                    start()
                }
            }
        }

        private fun stopDotPulse() {
            pulseAnimator?.cancel()
            pulseAnimator = null
            nowPlayingDot?.alpha = 1f
        }

        private fun loadPosterImage(item: PlaybackItem) {
            val artwork = item.artwork?.takeUnless { it.equals("null", ignoreCase = true) || it.isBlank() }

            if (artwork != null) {
                // Prepare for image loading - show shimmer, hide fallback
                fallbackContainer?.visibility = View.GONE
                shimmerOverlay?.visibility = View.VISIBLE
                // Keep poster visible but clear it - Glide will load into it
                posterImageView.visibility = View.VISIBLE
                posterImageView.setImageDrawable(null)

                com.bumptech.glide.Glide.with(itemView.context)
                    .load(artwork)
                    .centerCrop()
                    .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                        override fun onLoadFailed(
                            e: com.bumptech.glide.load.engine.GlideException?,
                            model: Any?,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                            isFirstResource: Boolean
                        ): Boolean {
                            shimmerOverlay?.visibility = View.GONE
                            posterImageView.visibility = View.GONE
                            showFallback(item)
                            return false
                        }

                        override fun onResourceReady(
                            resource: android.graphics.drawable.Drawable,
                            model: Any,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                            dataSource: com.bumptech.glide.load.DataSource,
                            isFirstResource: Boolean
                        ): Boolean {
                            shimmerOverlay?.visibility = View.GONE
                            posterImageView.visibility = View.VISIBLE
                            fallbackContainer?.visibility = View.GONE
                            return false
                        }
                    })
                    .into(posterImageView)
            } else {
                posterImageView.visibility = View.GONE
                shimmerOverlay?.visibility = View.GONE
                showFallback(item)
            }
        }

        private fun showFallback(item: PlaybackItem) {
            posterImageView.visibility = View.GONE
            shimmerOverlay?.visibility = View.GONE
            fallbackContainer?.visibility = View.VISIBLE

            // Don't show episode number - just clean dark background
            fallbackTextView.text = ""
            fallbackTextView.visibility = View.GONE

            // Dark cinematic background
            fallbackBg?.setBackgroundColor(0xFF0D0D0D.toInt())
        }

        private fun getSeasonGradient(season: Int): Int {
            // Cinematic colors - more visible
            val colors = intArrayOf(
                0xFF312E81.toInt(), // Indigo
                0xFF581C87.toInt(), // Purple
                0xFF831843.toInt(), // Rose
                0xFF78350F.toInt(), // Amber
                0xFF064E3B.toInt(), // Emerald
                0xFF155E75.toInt(), // Cyan
            )
            val safeSeason = season.coerceAtLeast(1)
            return colors[(safeSeason - 1) % colors.size]
        }
    }

    companion object {
        private const val VIEW_TYPE_HEADER = 0
        private const val VIEW_TYPE_EPISODE = 1
        private const val PAYLOAD_PROGRESS_UPDATE = "progress_update"
    }
}

private class MoviePlaylistAdapter(
    private val items: List<PlaybackItem>,
    private val groups: MovieGroups,
    private val onItemClick: (Int) -> Unit,
) : RecyclerView.Adapter<MoviePlaylistAdapter.MovieViewHolder>(), PlaylistOverlayAdapter {

    private var activeItemIndex = -1
    private var currentGroupIndex: Int = 0
    private val visibleIndices = mutableListOf<Int>()

    init {
        showGroup(0, force = true)
    }

    fun showGroup(groupIndex: Int, force: Boolean = false): Boolean {
        if (!force && currentGroupIndex == groupIndex) {
            return false
        }
        currentGroupIndex = groupIndex
        rebuildVisibleItems()
        notifyDataSetChanged()
        return true
    }

    private fun rebuildVisibleItems() {
        visibleIndices.clear()
        val currentGroup = groups.getGroup(currentGroupIndex)
        if (currentGroup != null) {
            visibleIndices.addAll(currentGroup.fileIndices)
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): MovieViewHolder {
        val inflater = android.view.LayoutInflater.from(parent.context)
        val view = inflater.inflate(R.layout.item_android_tv_playlist_entry_horizontal, parent, false)
        return MovieViewHolder(view, onItemClick)
    }

    override fun onBindViewHolder(holder: MovieViewHolder, position: Int) {
        val itemIndex = visibleIndices.getOrNull(position) ?: return
        val item = items[itemIndex]
        val isActive = itemIndex == activeItemIndex
        val groupName = groups.getGroup(currentGroupIndex)?.name ?: ""
        holder.bind(item, itemIndex, isActive, groupName)
    }

    override fun onBindViewHolder(holder: MovieViewHolder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isEmpty() || PAYLOAD_PROGRESS_UPDATE !in payloads) {
            super.onBindViewHolder(holder, position, payloads)
            return
        }

        // Handle progress-only update
        val itemIndex = visibleIndices.getOrNull(position) ?: return
        val item = items[itemIndex]
        val isActive = itemIndex == activeItemIndex
        holder.updateProgress(item, isActive)
    }

    override fun getItemCount(): Int = visibleIndices.size

    override fun setActiveIndex(index: Int) {
        val previousPosition = findPositionForItemIndex(activeItemIndex)
        activeItemIndex = index
        val newPosition = findPositionForItemIndex(activeItemIndex)

        if (previousPosition != -1) {
            notifyItemChanged(previousPosition)
        }
        if (newPosition != -1) {
            notifyItemChanged(newPosition)
        }
    }

    override fun updateCurrentProgress() {
        val position = findPositionForItemIndex(activeItemIndex)
        if (position != -1) {
            notifyItemChanged(position, PAYLOAD_PROGRESS_UPDATE)
        }
    }

    companion object {
        private const val PAYLOAD_PROGRESS_UPDATE = "progress_update"
    }

    override fun getActiveItemPosition(): Int {
        return findPositionForItemIndex(activeItemIndex)
    }

    private fun findPositionForItemIndex(itemIndex: Int): Int {
        return visibleIndices.indexOf(itemIndex)
    }

    class MovieViewHolder(
        itemView: View,
        private val onItemClick: (Int) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {

        private val container: View = itemView.findViewById(R.id.android_tv_playlist_item_container)
        private val selectionOverlay: View? = itemView.findViewById(R.id.selection_overlay)
        private val posterImageView: android.widget.ImageView = itemView.findViewById(R.id.android_tv_playlist_item_poster)
        private val fallbackTextView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_fallback)
        private val watchedOverlay: View = itemView.findViewById(R.id.android_tv_playlist_item_watched_overlay)
        private val watchedIcon: TextView = itemView.findViewById(R.id.android_tv_playlist_item_watched_icon)
        private val posterProgress: android.widget.ProgressBar = itemView.findViewById(R.id.android_tv_playlist_item_poster_progress)
        private val badgeView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_badge)
        private val playingView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_playing)
        private val watchedView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_watched)
        private val titleView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_title)
        private val descriptionView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_description)
        private val progressContainer: View = itemView.findViewById(R.id.android_tv_playlist_item_progress_container)
        private val progressText: TextView = itemView.findViewById(R.id.android_tv_playlist_item_progress_text)

        fun bind(item: PlaybackItem, itemIndex: Int, isActive: Boolean, groupName: String) {
            badgeView.text = groupName.uppercase()
            titleView.text = item.title

            val cleanedDescription = item.description
                ?.trim()
                ?.takeUnless { it.equals("null", ignoreCase = true) }

            val descriptionText = cleanedDescription ?: formatSize(item.sizeBytes)

            if (!descriptionText.isNullOrBlank()) {
                descriptionView.text = descriptionText
                descriptionView.visibility = View.VISIBLE
            } else {
                descriptionView.visibility = View.GONE
            }

            val progressPercent = item.displayProgressPercent()

            val isWatched = progressPercent >= 95
            container.alpha = if (isWatched && !isActive) 0.4f else 1.0f

            watchedOverlay.visibility = View.GONE
            watchedIcon.visibility = View.GONE
            watchedView.visibility = if (isWatched && !isActive) View.VISIBLE else View.GONE
            playingView.visibility = if (isActive) View.VISIBLE else View.GONE

            if (progressPercent in 6..94 && !isWatched) {
                progressText.text = "$progressPercent% watched"
                progressContainer.visibility = View.VISIBLE
                posterProgress.max = 100
                posterProgress.progress = progressPercent
                posterProgress.visibility = View.VISIBLE
            } else {
                progressContainer.visibility = View.GONE
                posterProgress.visibility = View.GONE
            }

            loadPosterImage(item, itemIndex, groupName)

            container.isSelected = isActive
            container.isFocusable = true
            container.setOnClickListener {
                onItemClick(itemIndex)
            }

            // Focus handling with smooth animations
            container.onFocusChangeListener = View.OnFocusChangeListener { view, hasFocus ->
                android.util.Log.d("PlaylistNav", "MovieViewHolder focus changed - itemIndex=$itemIndex, hasFocus=$hasFocus, position=${bindingAdapterPosition}")
                if (hasFocus) {
                    // Scale up and show glow
                    view.animate()
                        .scaleX(1.08f)
                        .scaleY(1.08f)
                        .setDuration(200)
                        .start()
                    selectionOverlay?.visibility = View.VISIBLE
                } else {
                    // Scale back down and hide glow
                    view.animate()
                        .scaleX(1.0f)
                        .scaleY(1.0f)
                        .setDuration(150)
                        .start()
                    selectionOverlay?.visibility = View.GONE
                }
            }
        }

        fun updateProgress(item: PlaybackItem, isActive: Boolean) {
            // Only update progress-related views, not the entire item
            val progressPercent = item.displayProgressPercent()

            val isWatched = progressPercent >= 95

            // Update alpha for watched state
            container.alpha = if (isWatched && !isActive) 0.4f else 1.0f

            // Update status indicators
            watchedView.visibility = if (isWatched && !isActive) View.VISIBLE else View.GONE
            playingView.visibility = if (isActive) View.VISIBLE else View.GONE

            // Update progress indicator
            if (progressPercent in 6..94 && !isWatched) {
                progressText.text = "$progressPercent% watched"
                progressContainer.visibility = View.VISIBLE
                posterProgress.max = 100
                posterProgress.progress = progressPercent
                posterProgress.visibility = View.VISIBLE
            } else {
                progressContainer.visibility = View.GONE
                posterProgress.visibility = View.GONE
            }
        }

        private fun loadPosterImage(item: PlaybackItem, itemIndex: Int, groupName: String) {
            val artwork = item.artwork
            if (!artwork.isNullOrBlank()) {
                com.bumptech.glide.Glide.with(itemView.context)
                    .load(artwork)
                    .centerCrop()
                    .placeholder(android.R.color.transparent)
                    .error(android.R.color.transparent)
                    .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                        override fun onLoadFailed(
                            e: com.bumptech.glide.load.engine.GlideException?,
                            model: Any?,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                            isFirstResource: Boolean
                        ): Boolean {
                            showFallback(itemIndex, groupName)
                            return false
                        }

                        override fun onResourceReady(
                            resource: android.graphics.drawable.Drawable,
                            model: Any,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                            dataSource: com.bumptech.glide.load.DataSource,
                            isFirstResource: Boolean
                        ): Boolean {
                            posterImageView.visibility = View.VISIBLE
                            fallbackTextView.visibility = View.GONE
                            return false
                        }
                    })
                    .into(posterImageView)
            } else {
                showFallback(itemIndex, groupName)
            }
        }

        private fun showFallback(itemIndex: Int, groupName: String) {
            posterImageView.visibility = View.GONE
            fallbackTextView.visibility = View.VISIBLE
            val positionNumber = if (bindingAdapterPosition != RecyclerView.NO_POSITION) {
                bindingAdapterPosition + 1
            } else {
                itemIndex + 1
            }
            fallbackTextView.text = positionNumber.coerceAtLeast(1).toString()
            fallbackTextView.setBackgroundColor(getGroupColor(groupName))
        }

        private fun getGroupColor(groupName: String): Int {
            // Use different colors for different groups
            return when (groupName.uppercase()) {
                "MAIN" -> 0xFF6366F1.toInt() // Indigo
                "EXTRAS" -> 0xFFF59E0B.toInt() // Amber
                "BEHIND THE SCENES" -> 0xFF10B981.toInt() // Emerald
                "DELETED SCENES" -> 0xFFEF4444.toInt() // Red
                "FEATURETTES" -> 0xFF8B5CF6.toInt() // Violet
                else -> 0xFF6B7280.toInt() // Gray (default)
            }
        }

        companion object {
            private fun formatSize(sizeBytes: Long?): String? {
                if (sizeBytes == null || sizeBytes <= 0) return null
                val units = arrayOf("B", "KB", "MB", "GB", "TB")
                var size = sizeBytes.toDouble()
                var unit = 0
                while (size >= 1024 && unit < units.lastIndex) {
                    size /= 1024.0
                    unit++
                }
                return if (unit == 0) {
                    "${size.toInt()} ${units[unit]}"
                } else {
                    String.format(Locale.US, "%.1f %s", size, units[unit])
                }
            }
        }
    }
}

// IPTV Channel Data + Adapter
// ═══════════════════════════════════════════════════════════════

private data class IptvChannelEntry(
    var index: Int,
    val channelNumber: Int?,
    val name: String,
    val url: String,
    val logoUrl: String?,
    val group: String?,
    val isLive: Boolean,
    var isCurrent: Boolean,
    // Where playback of this on-demand item should start. Seeded from the
    // Flutter payload and kept current in-session, so zapping away from a
    // half-watched movie and back returns to the right spot rather than to
    // the position it held at launch. Always 0 for live channels.
    var resumePositionMs: Long = 0L,
    // Headers the playlist declared for this channel (#EXTVLCOPT/#EXTHTTP/
    // pipe-suffix). Sent with every request while the channel plays — a
    // UA/Referer-guarded channel is unplayable without them.
    val httpHeaders: Map<String, String> = emptyMap(),
    // EPG (Xtream panels), fetched lazily over the bridge as rows bind.
    // Instances are shared between the master list and the adapter's filtered
    // copy, so a fetch landing updates both. epgLoaded means "asked once" —
    // a stale answer (now-programme ended) re-arms the fetch on next bind.
    var epgNowTitle: String? = null,
    var epgNowStartMs: Long = 0L,
    var epgNowStopMs: Long = 0L,
    var epgNextTitle: String? = null,
    var epgNextStartMs: Long = 0L,
    var epgLoaded: Boolean = false,
    var epgLoading: Boolean = false,
    val contentType: String = if (isLive) "live" else "vod",
    // The playlist's declared runtime (-1 for live). Retained because a
    // channel saved into a list is rebuilt from stored metadata alone, and
    // without the runtime its progress/resume UI has nothing to divide by.
    val duration: Int = -1,
    var sourceId: String? = null,
    var sourceName: String? = null,
    var isFavorite: Boolean = false,
    val seriesId: String? = null,
    val seriesName: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val hasNextEpisode: Boolean? = null,
) {
    val displayName: String
        get() = if (isLive && channelNumber != null) {
            "CH $channelNumber  $name"
        } else {
            name
        }
}

@androidx.annotation.OptIn(UnstableApi::class)
private class IptvChannelAdapter(
    private var channels: MutableList<IptvChannelEntry>,
    private val onItemClick: (IptvChannelEntry) -> Unit,
    private val onItemLongClick: ((IptvChannelEntry) -> Unit)? = null,
    // Fired from bind for live rows without (fresh) EPG — the activity
    // fetches over the bridge and answers with notifyEpgFor. Bind-driven, so
    // only rows that actually come on screen ever cost a request.
    private val onEpgNeeded: ((IptvChannelEntry) -> Unit)? = null,
    // Styled-look inputs (see IptvGuideStyle.kt); null tokens = classic, and
    // every styled branch below is skipped outright. Invariant styling is
    // applied ONCE per holder in onCreateViewHolder — bind only writes
    // entry-dependent colors/text/visibility.
    private val tokens: GuideTokens? = null,
    private val style: GuideStyle = GuideStyle.CLASSIC,
    private val nameTypeface: Typeface? = null,
    private val monoTypeface: Typeface? = null,
    private val headlineTypeface: Typeface? = null,
    private val captionTypeface: Typeface? = null,
    private val rowRadiusPx: Float = 0f,
    private val rowStrokePx: Int = 0,
) : RecyclerView.Adapter<IptvChannelAdapter.ViewHolder>() {

    companion object {
        private val ACCENT = Color.parseColor("#00E5FF")
        private val ACCENT_DIM = Color.parseColor("#CC00E5FF")
        const val PAYLOAD_EPG = "epg"
    }

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val number: TextView = view.findViewById(R.id.iptv_channel_number)
        val logoTile: FrameLayout = view.findViewById(R.id.iptv_channel_logo_tile)
        val logo: android.widget.ImageView = view.findViewById(R.id.iptv_channel_logo)
        val letter: TextView = view.findViewById(R.id.iptv_channel_letter)
        val name: TextView = view.findViewById(R.id.iptv_channel_name)
        val group: TextView = view.findViewById(R.id.iptv_channel_group)
        val epg: TextView = view.findViewById(R.id.iptv_channel_epg)
        val favorite: TextView = view.findViewById(R.id.iptv_channel_favorite)
        val liveBadge: View = view.findViewById(R.id.iptv_channel_live_badge)
        val liveDot: View = view.findViewById(R.id.iptv_channel_live_dot)
        val liveLabel: TextView = view.findViewById(R.id.iptv_channel_live_label)
        val nowBadge: TextView = view.findViewById(R.id.iptv_channel_now_badge)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_iptv_channel, parent, false)
        val holder = ViewHolder(view)
        val t = tokens ?: return holder
        // Invariant styled chrome — never re-done on bind/scroll.
        view.background = t.rowBackground(rowRadiusPx, rowStrokePx)
        holder.logoTile.background = if (style == GuideStyle.EDITION) {
            t.tileDrawable(view.resources.displayMetrics.density * 21f, 1)
        } else {
            t.tileDrawable(rowRadiusPx, 1)
        }
        holder.letter.setBackgroundColor(Color.TRANSPARENT)
        holder.letter.setTextColor(t.fg)
        holder.group.setTextColor(t.fgFaint)
        holder.epg.setTextColor(t.fgDim)
        holder.favorite.setTextColor(
            if (style == GuideStyle.EDITION) t.fg else t.accent,
        )
        holder.liveBadge.setBackgroundColor(Color.TRANSPARENT)
        holder.liveDot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(t.live)
        }
        holder.liveLabel.setTextColor(t.live)
        if (style == GuideStyle.EDITION) {
            // Edition's NOW is small-caps cream text, no pill.
            holder.nowBadge.background = null
            holder.nowBadge.setTextColor(t.fg)
        } else {
            holder.nowBadge.background = GradientDrawable().apply {
                cornerRadius = if (style == GuideStyle.CONSOLE) {
                    view.resources.displayMetrics.density * 2f
                } else {
                    view.resources.displayMetrics.density * 5f
                }
                setColor(t.accent)
            }
            holder.nowBadge.setTextColor(t.bg or 0xFF000000.toInt())
        }
        when (style) {
            GuideStyle.CONSOLE -> {
                holder.number.typeface = monoTypeface ?: holder.number.typeface
                holder.name.typeface = nameTypeface ?: holder.name.typeface
                holder.epg.typeface = monoTypeface ?: holder.epg.typeface
                holder.liveLabel.typeface = monoTypeface ?: holder.liveLabel.typeface
            }
            GuideStyle.EDITION -> {
                holder.name.typeface = headlineTypeface ?: holder.name.typeface
                holder.epg.typeface = captionTypeface?.let {
                    Typeface.create(it, Typeface.ITALIC)
                } ?: holder.epg.typeface
            }
            else -> {}
        }
        return holder
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isNotEmpty() && payloads[0] == PAYLOAD_EPG) {
            // Partial bind — refresh the EPG line only, preserving focus/scale.
            bindEpgLine(holder, channels[position])
            return
        }
        super.onBindViewHolder(holder, position, payloads)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val entry = channels[position]

        // Cancel any in-flight scale animation from recycled view
        holder.itemView.animate().cancel()
        holder.itemView.scaleX = 1.0f
        holder.itemView.scaleY = 1.0f

        // Channel number
        val t = tokens
        val displayNumber = (entry.channelNumber ?: (entry.index + 1)).toString()
        holder.number.text =
            if (t != null && style == GuideStyle.CONSOLE) {
                displayNumber.padStart(3, '0')
            } else {
                displayNumber
            }
        holder.number.setTextColor(
            if (t == null) {
                if (entry.isCurrent) Color.argb(204, 0, 229, 255) // accent 80%
                else Color.argb(46, 255, 255, 255) // 18%
            } else {
                if (entry.isCurrent) {
                    if (style == GuideStyle.EDITION) t.fg else t.accent
                } else {
                    t.fgFaint
                }
            }
        )

        // Name
        holder.name.text = entry.name
        holder.name.setTextColor(
            if (t == null) {
                if (entry.isCurrent) ACCENT else Color.argb(217, 255, 255, 255)
            } else {
                if (entry.isCurrent) {
                    if (style == GuideStyle.EDITION) t.fg else t.accent
                } else {
                    t.fgMid
                }
            }
        )

        // Group
        if (entry.group != null) {
            holder.group.text = entry.group
            holder.group.visibility = View.VISIBLE
        } else {
            holder.group.visibility = View.GONE
        }

        // EPG line — bind what we have; ask for what we don't. "Stale" means
        // the programme we knew about has ended, so the next bind re-asks.
        bindEpgLine(holder, entry)
        if (entry.isLive && !entry.epgLoading) {
            val stale = entry.epgLoaded && entry.epgNowStopMs > 0 &&
                entry.epgNowStopMs < System.currentTimeMillis()
            if (!entry.epgLoaded || stale) onEpgNeeded?.invoke(entry)
        }

        // Badges — show NOW for current, LIVE for non-current live
        if (entry.isCurrent) {
            holder.nowBadge.visibility = View.VISIBLE
            holder.liveBadge.visibility = View.GONE
        } else {
            holder.nowBadge.visibility = View.GONE
            holder.liveBadge.visibility = if (entry.isLive) View.VISIBLE else View.GONE
        }
        holder.favorite.visibility = if (entry.isFavorite) View.VISIBLE else View.GONE

        // Logo — clear previous Glide load to prevent stale images on recycled views
        com.bumptech.glide.Glide.with(holder.itemView.context).clear(holder.logo)
        val firstLetter = if (entry.name.isNotEmpty()) entry.name[0].uppercase() else "?"
        if (!entry.logoUrl.isNullOrEmpty()) {
            holder.logo.visibility = View.VISIBLE
            holder.letter.visibility = View.GONE
            com.bumptech.glide.Glide.with(holder.itemView.context)
                .load(entry.logoUrl)
                .centerInside()
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?,
                        model: Any?,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                        isFirstResource: Boolean
                    ): Boolean {
                        holder.logo.visibility = View.GONE
                        holder.letter.text = firstLetter
                        holder.letter.visibility = View.VISIBLE
                        return true
                    }
                    override fun onResourceReady(
                        resource: android.graphics.drawable.Drawable,
                        model: Any,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                        dataSource: com.bumptech.glide.load.DataSource,
                        isFirstResource: Boolean
                    ): Boolean = false
                })
                .into(holder.logo)
        } else {
            holder.logo.visibility = View.GONE
            holder.letter.text = firstLetter
            holder.letter.visibility = View.VISIBLE
        }

        // Focus animation
        holder.itemView.onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
            if (hasFocus) {
                v.animate().scaleX(1.02f).scaleY(1.02f).setDuration(150)
                    .setInterpolator(DecelerateInterpolator()).start()
            } else {
                v.animate().scaleX(1.0f).scaleY(1.0f).setDuration(150)
                    .setInterpolator(DecelerateInterpolator()).start()
            }
        }

        holder.itemView.setOnClickListener {
            onItemClick(entry)
        }
        holder.itemView.setOnLongClickListener {
            onItemLongClick?.invoke(entry)
            onItemLongClick != null
        }
    }

    override fun getItemCount(): Int = channels.size

    private fun bindEpgLine(holder: ViewHolder, entry: IptvChannelEntry) {
        val title = entry.epgNowTitle
        if (title != null) {
            holder.epg.text = "Now: $title"
            holder.epg.visibility = View.VISIBLE
        } else {
            holder.epg.visibility = View.GONE
        }
    }

    /** A bridge EPG fetch landed for [entry] — repaint its row if visible. */
    fun notifyEpgFor(entry: IptvChannelEntry) {
        val position = channels.indexOfFirst { it === entry }
        if (position >= 0) notifyItemChanged(position, PAYLOAD_EPG)
    }

    fun entryAt(position: Int): IptvChannelEntry? = channels.getOrNull(position)
    fun positionOf(entry: IptvChannelEntry?): Int =
        channels.indexOfFirst { it === entry }.coerceAtLeast(0)
    fun entriesSnapshot(): List<IptvChannelEntry> = channels.toList()

    fun notifyFavoriteFor(entry: IptvChannelEntry) {
        val position = channels.indexOfFirst { it === entry }
        if (position >= 0) notifyItemChanged(position)
    }

    fun notifyCurrentChanged(
        previous: IptvChannelEntry?,
        current: IptvChannelEntry,
    ) {
        val previousPosition = channels.indexOfFirst { it === previous }
        val currentPosition = channels.indexOfFirst { it === current }
        if (previousPosition >= 0) notifyItemChanged(previousPosition)
        if (currentPosition >= 0 && currentPosition != previousPosition) {
            notifyItemChanged(currentPosition)
        }
    }

    fun updateChannels(filtered: List<IptvChannelEntry>) {
        val old = channels.toList()
        val updated = filtered.toList()
        val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
            override fun getOldListSize(): Int = old.size
            override fun getNewListSize(): Int = updated.size

            override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
                val before = old[oldItemPosition]
                val after = updated[newItemPosition]
                return before.index == after.index &&
                    before.url == after.url &&
                    before.name == after.name &&
                    before.sourceId == after.sourceId
            }

            override fun areContentsTheSame(
                oldItemPosition: Int,
                newItemPosition: Int,
            ): Boolean {
                val before = old[oldItemPosition]
                val after = updated[newItemPosition]
                return before === after ||
                    (before.isCurrent == after.isCurrent &&
                        before.isFavorite == after.isFavorite &&
                        before.logoUrl == after.logoUrl &&
                        before.group == after.group &&
                        before.epgNowTitle == after.epgNowTitle &&
                        before.epgNextTitle == after.epgNextTitle)
            }
        }, true)
        channels.clear()
        channels.addAll(updated)
        diff.dispatchUpdatesTo(this)
    }

    fun getCurrentChannelPosition(): Int {
        return channels.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
    }
}

private data class IptvSourceEntry(
    val id: String,
    val name: String,
    val isFavorites: Boolean,
    val isContinue: Boolean,
    val isXtream: Boolean,
    // A user-created channel list. Favorites keeps its own flag (the SAVED
    // nav button resolves the source by it) and is NOT flagged as a list.
    val isList: Boolean = false,
    val listId: String? = null,
    val connectionResourceId: String? = null,
    val connectionResourceRevision: Long? = null,
)

/// One of the user's channel lists, for the "add to list" picker.
private data class IptvListEntry(
    val id: String,
    val name: String,
    val isBuiltin: Boolean,
)

private data class IptvEpgProgram(
    val title: String,
    val description: String?,
    val startMs: Long,
    val stopMs: Long,
    val hasArchive: Boolean,
)

private class IptvEpgAdapter(
    private var programs: List<IptvEpgProgram>,
    private val onReplay: (IptvEpgProgram) -> Unit,
    private val onRecordFuture: (IptvEpgProgram) -> Unit,
    // Styled-look inputs; null tokens = classic. Invariant styling happens
    // once per holder in onCreateViewHolder.
    private val tokens: GuideTokens? = null,
    private val style: GuideStyle = GuideStyle.CLASSIC,
    private val monoTypeface: Typeface? = null,
    private val headlineTypeface: Typeface? = null,
    private val rowRadiusPx: Float = 0f,
    private val rowStrokePx: Int = 0,
) : RecyclerView.Adapter<IptvEpgAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val time: TextView = view.findViewById(R.id.iptv_epg_program_time)
        val title: TextView = view.findViewById(R.id.iptv_epg_program_title)
        val description: TextView = view.findViewById(R.id.iptv_epg_program_description)
        val progress: ProgressBar = view.findViewById(R.id.iptv_epg_program_progress)
        val now: TextView = view.findViewById(R.id.iptv_epg_program_now)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_iptv_epg_program, parent, false)
        val holder = ViewHolder(view)
        val t = tokens ?: return holder
        view.background = t.rowBackground(rowRadiusPx, rowStrokePx)
        holder.time.setTextColor(t.fgDim)
        holder.title.setTextColor(t.fg)
        holder.description.setTextColor(t.fgFaint)
        holder.progress.progressTintList =
            android.content.res.ColorStateList.valueOf(t.accent)
        holder.progress.progressBackgroundTintList =
            android.content.res.ColorStateList.valueOf(t.hairline2)
        // NOW/REPLAY chip: an outlined token tag (the text flips per bind,
        // the chrome doesn't).
        holder.now.background = GradientDrawable().apply {
            cornerRadius = if (style == GuideStyle.CONSOLE) {
                view.resources.displayMetrics.density * 2f
            } else {
                view.resources.displayMetrics.density * 4f
            }
            setColor(Color.TRANSPARENT)
            setStroke(1, t.accent)
        }
        holder.now.setTextColor(t.accent)
        when (style) {
            GuideStyle.CONSOLE -> {
                holder.time.typeface = monoTypeface ?: holder.time.typeface
                holder.now.typeface = monoTypeface ?: holder.now.typeface
            }
            GuideStyle.EDITION -> {
                holder.title.typeface = headlineTypeface ?: holder.title.typeface
            }
            else -> {}
        }
        return holder
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val program = programs[position]
        val nowMs = System.currentTimeMillis()
        val airing = program.startMs <= nowMs && nowMs < program.stopMs
        val elapsed = nowMs - program.startMs
        val duration = (program.stopMs - program.startMs).coerceAtLeast(1L)
        val replayable = program.hasArchive && program.stopMs < nowMs

        holder.time.text = android.text.format.DateFormat
            .getTimeFormat(holder.itemView.context)
            .format(java.util.Date(program.startMs))
        holder.title.text = program.title
        holder.description.text = program.description
        holder.description.visibility =
            if (program.description.isNullOrBlank()) View.GONE else View.VISIBLE
        holder.now.text = if (airing) "NOW" else "REPLAY"
        holder.now.visibility = if (airing || replayable) View.VISIBLE else View.GONE
        // Styled only: the airing row wears the quiet selected tint (and a
        // recycled holder explicitly clears it). Classic never sets it.
        if (tokens != null) holder.itemView.isSelected = airing
        holder.progress.visibility = if (airing) View.VISIBLE else View.GONE
        holder.progress.progress =
            ((elapsed.coerceIn(0L, duration) * 1000L) / duration).toInt()
        holder.itemView.alpha =
            if (program.stopMs < nowMs && !replayable) 0.55f else 1f
        holder.itemView.setOnClickListener {
            when {
                replayable -> onReplay(program)
                // Future programme: OK offers to schedule a recording. The
                // activity gates (engine on, channel recordable) and confirms.
                program.startMs > System.currentTimeMillis() -> onRecordFuture(program)
            }
        }
    }

    override fun getItemCount(): Int = programs.size

    fun updatePrograms(items: List<IptvEpgProgram>) {
        programs = items
        notifyDataSetChanged()
    }
}

// ═══════════════════════════════════════════════════════════════
// Stremio TV Guide Data + Adapter
// ═══════════════════════════════════════════════════════════════

private data class StremioTvGuideChannel(
    val id: String,
    val name: String,
    val number: Int,
    val type: String,
    val isFavorite: Boolean,
    var isCurrent: Boolean,
    var nowPlayingTitle: String?,
    var nowPlayingPoster: String?,
    var nowPlayingYear: String?,
    var nowPlayingRating: Double?,
    var nowPlayingSlotEndMs: Long,
    var nowPlayingProgress: Float,
    var nextUpTitle: String?,
    var nextUpPoster: String?,
    var nextUpYear: String?,
    var nextUpRating: Double?,
    var hasGuideData: Boolean,
    var isLoadingGuideData: Boolean,
    var isSwitchingChannel: Boolean = false,
)

@androidx.annotation.OptIn(UnstableApi::class)
private class StremioTvGuideAdapter(
    private var channels: MutableList<StremioTvGuideChannel>,
    private val onItemClick: (StremioTvGuideChannel) -> Unit,
) : RecyclerView.Adapter<StremioTvGuideAdapter.ViewHolder>() {

    companion object {
        private val ACCENT = Color.parseColor("#00E5FF")
        const val PAYLOAD_GUIDE_DATA = "guide_data"
        const val PAYLOAD_SWITCH_STATE = "switch_state"
    }

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val accentBar: View = view.findViewById(R.id.stremio_tv_guide_accent_bar)
        val number: TextView = view.findViewById(R.id.stremio_tv_guide_channel_number)
        val poster: android.widget.ImageView = view.findViewById(R.id.stremio_tv_guide_poster)
        val posterLetter: TextView = view.findViewById(R.id.stremio_tv_guide_poster_letter)
        val channelName: TextView = view.findViewById(R.id.stremio_tv_guide_channel_name)
        val typeBadge: TextView = view.findViewById(R.id.stremio_tv_guide_type_badge)
        val nowTitle: TextView = view.findViewById(R.id.stremio_tv_guide_now_title)
        val nextTitle: TextView = view.findViewById(R.id.stremio_tv_guide_next_title)
        val progressContainer: View = view.findViewById(R.id.stremio_tv_guide_progress_container)
        val progressFill: View = view.findViewById(R.id.stremio_tv_guide_progress_fill)
        val endTime: TextView = view.findViewById(R.id.stremio_tv_guide_end_time)
        val nowBadge: TextView = view.findViewById(R.id.stremio_tv_guide_now_badge)
        val loading: View = view.findViewById(R.id.stremio_tv_guide_loading)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_stremio_tv_guide_channel, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isNotEmpty()) {
            val payload = payloads[0]
            if (payload == PAYLOAD_GUIDE_DATA || payload == PAYLOAD_SWITCH_STATE) {
                // Partial bind — only update guide-data fields, preserve focus & scale
                val channel = channels[position]
                bindGuideData(holder, channel)
                return
            }
        }
        super.onBindViewHolder(holder, position, payloads)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val channel = channels[position]

        // Cancel recycled view animation
        holder.itemView.animate().cancel()
        holder.itemView.scaleX = 1.0f
        holder.itemView.scaleY = 1.0f

        // Left accent bar — visible for current channel
        if (channel.isCurrent) {
            val gradient = android.graphics.drawable.GradientDrawable(
                android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#00E5FF"), Color.parseColor("#00BCD4"))
            )
            gradient.cornerRadius = 2f
            holder.accentBar.background = gradient
            holder.accentBar.visibility = View.VISIBLE
        } else {
            holder.accentBar.visibility = View.GONE
        }

        // Channel number
        holder.number.text = channel.number.toString()
        holder.number.setTextColor(
            if (channel.isCurrent) Color.argb(204, 0, 229, 255) else Color.argb(46, 255, 255, 255)
        )

        // Channel name
        holder.channelName.text = channel.name
        holder.channelName.setTextColor(
            if (channel.isCurrent) ACCENT else Color.argb(217, 255, 255, 255)
        )

        // Type badge
        holder.typeBadge.text = channel.type.uppercase()
        holder.typeBadge.setTextColor(
            if (channel.isCurrent) ACCENT else Color.argb(89, 255, 255, 255)
        )

        // Guide data fields (poster, now playing, next up, progress, badges)
        bindGuideData(holder, channel)

        // Focus animation with accent bar toggle
        holder.itemView.onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
            if (hasFocus) {
                v.animate().scaleX(1.02f).scaleY(1.02f).setDuration(150)
                    .setInterpolator(DecelerateInterpolator()).start()
                // Show accent bar on focus
                if (!channel.isCurrent) {
                    val gradient = android.graphics.drawable.GradientDrawable(
                        android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM,
                        intArrayOf(Color.parseColor("#00E5FF"), Color.parseColor("#00BCD4"))
                    )
                    gradient.cornerRadius = 2f
                    holder.accentBar.background = gradient
                    holder.accentBar.visibility = View.VISIBLE
                }
            } else {
                v.animate().scaleX(1.0f).scaleY(1.0f).setDuration(150)
                    .setInterpolator(DecelerateInterpolator()).start()
                // Hide accent bar when not current
                if (!channel.isCurrent) {
                    holder.accentBar.visibility = View.GONE
                }
            }
        }

        holder.itemView.setOnClickListener {
            onItemClick(channel)
        }
    }

    private fun bindGuideData(holder: ViewHolder, channel: StremioTvGuideChannel) {
        val goldStar = Color.parseColor("#FFD700")

        // Poster
        com.bumptech.glide.Glide.with(holder.itemView.context).clear(holder.poster)
        val firstLetter = if (channel.name.isNotEmpty()) channel.name[0].uppercase() else "?"
        val posterUrl = channel.nowPlayingPoster
        if (!posterUrl.isNullOrEmpty()) {
            holder.poster.visibility = View.VISIBLE
            holder.posterLetter.visibility = View.GONE
            com.bumptech.glide.Glide.with(holder.itemView.context)
                .load(posterUrl)
                .centerCrop()
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?,
                        model: Any?,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                        isFirstResource: Boolean
                    ): Boolean {
                        holder.poster.visibility = View.GONE
                        holder.posterLetter.text = firstLetter
                        holder.posterLetter.visibility = View.VISIBLE
                        return true
                    }
                    override fun onResourceReady(
                        resource: android.graphics.drawable.Drawable,
                        model: Any,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                        dataSource: com.bumptech.glide.load.DataSource,
                        isFirstResource: Boolean
                    ): Boolean = false
                })
                .into(holder.poster)
        } else {
            holder.poster.visibility = View.GONE
            holder.posterLetter.text = firstLetter
            holder.posterLetter.visibility = View.VISIBLE
        }

        // Now playing text with gold star
        if (channel.isSwitchingChannel) {
            holder.nowTitle.text = "Tuning..."
            holder.nowTitle.setTextColor(Color.argb(204, 0, 229, 255))
        } else if (channel.hasGuideData && channel.nowPlayingTitle != null) {
            val textParts = mutableListOf<String>()
            textParts.add(channel.nowPlayingTitle!!)
            if (!channel.nowPlayingYear.isNullOrEmpty()) textParts.add("(${channel.nowPlayingYear})")

            val hasRating = channel.nowPlayingRating != null && channel.nowPlayingRating!! > 0
            if (hasRating) {
                val baseText = textParts.joinToString(" ")
                val starText = " ★ ${String.format(java.util.Locale.US, "%.1f", channel.nowPlayingRating)}"
                val spannable = android.text.SpannableString(baseText + starText)
                spannable.setSpan(
                    android.text.style.ForegroundColorSpan(goldStar),
                    baseText.length,
                    baseText.length + starText.length,
                    android.text.Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                holder.nowTitle.text = spannable
            } else {
                holder.nowTitle.text = textParts.joinToString(" ")
            }
            holder.nowTitle.setTextColor(
                if (channel.isCurrent) Color.argb(230, 0, 229, 255) else Color.argb(179, 255, 255, 255)
            )
        } else if (channel.isLoadingGuideData) {
            holder.nowTitle.text = "Loading..."
            holder.nowTitle.setTextColor(Color.argb(89, 255, 255, 255))
        } else {
            holder.nowTitle.text = ""
        }

        // Next up
        if (channel.hasGuideData && channel.nextUpTitle != null) {
            val nextParts = mutableListOf("Next: ${channel.nextUpTitle}")
            if (!channel.nextUpYear.isNullOrEmpty()) nextParts.add("(${channel.nextUpYear})")
            holder.nextTitle.text = nextParts.joinToString(" ")
            holder.nextTitle.visibility = View.VISIBLE
        } else {
            holder.nextTitle.visibility = View.GONE
        }

        // Progress bar
        if (channel.hasGuideData && channel.nowPlayingSlotEndMs > 0) {
            holder.progressContainer.visibility = View.VISIBLE
            val progress = channel.nowPlayingProgress.coerceIn(0f, 1f)
            val channelId = channel.id
            holder.progressFill.post {
                // Guard against recycled/rebound holder
                val pos = holder.bindingAdapterPosition
                if (pos == RecyclerView.NO_POSITION) return@post
                val currentChannel = channels.getOrNull(pos) ?: return@post
                if (currentChannel.id != channelId) return@post
                val parent = holder.progressFill.parent as? View ?: return@post
                val width = (parent.width * progress).toInt()
                val lp = holder.progressFill.layoutParams
                lp.width = width
                holder.progressFill.layoutParams = lp
            }
            // Format end time
            val endMs = channel.nowPlayingSlotEndMs
            if (endMs > System.currentTimeMillis()) {
                val cal = java.util.Calendar.getInstance()
                cal.timeInMillis = endMs
                val h = cal.get(java.util.Calendar.HOUR)
                val m = cal.get(java.util.Calendar.MINUTE)
                val ampm = if (cal.get(java.util.Calendar.AM_PM) == 0) "AM" else "PM"
                val h12 = if (h == 0) 12 else h
                holder.endTime.text = "${h12}:${String.format("%02d", m)} $ampm"
                holder.endTime.visibility = View.VISIBLE
            } else {
                holder.endTime.visibility = View.GONE
            }
        } else {
            holder.progressContainer.visibility = View.GONE
        }

        // Badges
        if (channel.isSwitchingChannel) {
            holder.nowBadge.visibility = View.GONE
            holder.loading.visibility = View.VISIBLE
        } else if (channel.isCurrent) {
            holder.nowBadge.visibility = View.VISIBLE
            holder.loading.visibility = View.GONE
        } else if (channel.isLoadingGuideData) {
            holder.nowBadge.visibility = View.GONE
            holder.loading.visibility = View.VISIBLE
        } else {
            holder.nowBadge.visibility = View.GONE
            holder.loading.visibility = View.GONE
        }
    }

    override fun getItemCount(): Int = channels.size

    fun updateChannels(filtered: List<StremioTvGuideChannel>) {
        channels.clear()
        channels.addAll(filtered)
        notifyDataSetChanged()
    }

    fun getCurrentChannelPosition(): Int {
        return channels.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
    }

    fun getChannelAt(position: Int): StremioTvGuideChannel? {
        return channels.getOrNull(position)
    }

    fun getPositionById(id: String): Int {
        return channels.indexOfFirst { it.id == id }
    }
}
