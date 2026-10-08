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
class AndroidTvTorrentPlayerActivity : AppCompatActivity() {

    // Views
    private lateinit var playerView: PlayerView
    private lateinit var startupGateView: View
    private lateinit var startupGateStatus: TextView
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
    private lateinit var subtitleControlsLift: SubtitleControlsLiftController
    private lateinit var playlistOverlay: View
    private lateinit var playlistView: RecyclerView
    private lateinit var seasonTabsContainer: android.widget.LinearLayout
    private lateinit var nextOverlay: View
    private lateinit var nextText: TextView
    private lateinit var nextSubtext: TextView

    // Loading/tuning overlay backdrop art
    private lateinit var nextBackdrop: android.widget.ImageView
    private val upNextController = TvUpNextController(
        this,
        object : TvUpNextController.Host {
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override val continuousShuffleEnabled: Boolean get() = this@AndroidTvTorrentPlayerActivity.continuousShuffleEnabled
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val isStremioTvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isStremioTvMode
            override var isAutoAdvancing: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.isAutoAdvancing
                set(value) { this@AndroidTvTorrentPlayerActivity.isAutoAdvancing = value }
            override fun isCleanPlaybackState(): Boolean = this@AndroidTvTorrentPlayerActivity.isCleanPlaybackState()
            override fun canShuffleWholeShow(): Boolean = this@AndroidTvTorrentPlayerActivity.canShuffleWholeShow()
            override fun pickShuffleIndex(): Int? = this@AndroidTvTorrentPlayerActivity.pickShuffleIndex()
            override fun getNextPlayableIndex(i: Int): Int? = this@AndroidTvTorrentPlayerActivity.getNextPlayableIndex(i)
            override fun playItem(index: Int) = this@AndroidTvTorrentPlayerActivity.playItem(index)
        },
    )
    private lateinit var skipSegmentButton: AppCompatButton
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
    private var iptvStartOverButton: AppCompatButton? = null
    private var iptvStartOverSeekButton: AppCompatButton? = null
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

    // OTT skin views (null while CLASSIC is installed). ottSkinInstalled is
    // the single truth every OTT branch tests — it can only become true after
    // the controller-layout swap succeeded, so a failed inflate degrades to
    // the classic skin instead of a half-styled one.
    private var ottSkinInstalled = false
    private var ottCaptionLabel: TextView? = null
    private var ottCaptionOwner: View? = null
    private var ottIdentityTitle: TextView? = null
    private var ottIdentitySubtitle: TextView? = null

    // Optional per-skin identity views (null where a layout doesn't have them):
    // MARQUEE/TICKET show-name overline, TICKET gold S·E badge + its rule.
    private var ottIdentityOverline: TextView? = null
    private var ottIdentityBadge: TextView? = null
    private var ottIdentityDivider: View? = null

    // Release-quality chips + rating (updateOttExtras): chips row on
    // FROST/BROADCAST/PULSE, serif print line on MARQUEE, gold stub on
    // TICKET. All optional per layout.
    private val ottQualityChips = arrayOfNulls<TextView>(3)
    private var ottRatingChip: TextView? = null
    private var ottMetaLine: TextView? = null
    private var dockTagsCacheKey: String? = null
    private var dockTagsCache: List<DockFormatTags.Tag> = emptyList()
    private var ottScrubPreviewChip: View? = null
    private var ottScrubPreviewText: TextView? = null
    private var ottProgressTrackContainer: View? = null

    /** In-dock Sources button; replaces the top-right stremio_source_badge
     *  under the OTT skin (the badge stays permanently hidden there). */
    private var ottSourcesButton: AppCompatButton? = null

    /** TVMaze's official show title, pushed with the metadata updates. */
    @Volatile
    private var ottShowName: String? = null
    private var cinemaProgressTrackWidth: Int = 0
    private var cinemaSeekMode: Boolean = false  // True when actively seeking via progress bar
    private var cinemaSeekWasPlaying: Boolean = false
    private var cinemaProgressAnimator: ValueAnimator? = null
    private var cinemaLastAnimatedProgress: Float = 0f

    // Player
    private var player: ExoPlayer? = null
    private val nativeAudioRouting = NativeAudioRouting()
    private var trackSelector: DefaultTrackSelector? = null
    private var subtitleListener: Player.Listener? = null
    private var displayMatchMode = TvContentDisplayMatchMode.SYSTEM
    private var displayModeController: TvDisplayModeController? = null

    private val decoderAnalyticsListener = object : AnalyticsListener {
        private var inputFormat: Format? = null

        override fun onAudioTrackInitialized(
            eventTime: AnalyticsListener.EventTime,
            audioTrackConfig: AudioSink.AudioTrackConfig,
        ) {
            // Format/route changes can replace AudioTrack without changing its
            // session ID or media item. Reattach effects to the actual output.
            if (nightModeIndex > 0) initializeLoudnessEnhancer()
            syncAudioEffectSession()
        }

        override fun onVideoInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: DecoderReuseEvaluation?,
        ) {
            inputFormat = format
            displayModeController?.onVideoFormat(format)
        }

        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializedTimestampMs: Long,
            initializationDurationMs: Long,
        ) {
            val format = player?.videoFormat ?: inputFormat
            val generation = eventTime.mediaPeriodId?.windowSequenceNumber ?: -1L
            val message =
                "generation=$generation phase=stable " +
                    "status=${androidDecoderStatus(decoderName)} " +
                    "platform=android_tv backend=media3 " +
                    "codec=${format?.sampleMimeType ?: "unknown"} " +
                    "decoder=$decoderName output=surface_view " +
                    "resolution=${format?.width ?: 0}x${format?.height ?: 0}"
            DiagnosticFileLog.record(
                source = "android_tv_player",
                event = "decoder_initialized",
                message = message,
            )
            Log.i(
                DECODER_LOG_TAG,
                message,
            )
        }
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
        if (sleepStopLatched || sleepTimerController.sleepTimerMode == SleepTimerMode.END_OF_ITEM) return false
        if (iptvChannelStartController.iptvStremioChannelKey != null && !iptvChannelStartController.iptvStremioWinnerReported) return false
        if (player?.playWhenReady != true) return false
        return true
    }

    /** Re-tune the current live channel with its full identity — the SAME
     *  resolved URL and per-channel headers (already in
     *  currentIptvHttpHeaders; setIptvMediaItem re-stamps both). A fresh
     *  prepare joins the live edge, never a stale position. */
    private fun performIptvLiveRetune(source: String, attempt: Int) {
        val entry = iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive } ?: return
        // A start-over URL is a finite archive segment. Recovery from its EOF
        // must join the channel's real live URL, not reopen the old segment.
        val url = if (iptvStartOverActive) entry.url else currentIptvStreamUrl ?: entry.url
        if (iptvStartOverActive || iptvStartOverLoading) {
            iptvStartOverActive = false
            iptvStartOverLoading = false
            iptvStartOverTimelineVisible = false
            iptvStartOverController.iptvCatchupToken++
            updateIptvControlPresentation(entry)
        }
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
            !iptvRecordingActionsController.isCurrentIptvSegmented() && !iptvStrictTsActive &&
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
        if (source == "video-stall" && attempt >= 2 && iptvRecordingActionsController.isCurrentIptvSegmented() &&
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
            iptvRecordingActionsController.finalizeIptvRecordingIfActive()
            iptvRecordingActionsController.updateRecordButtonState()
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
            startupGateController.mediaServerPlaybackLog("first_frame")
            iptvTuneDiagnostics.onFirstFrame()
            if (startupGateController.manualSourceRestoreInProgress) {
                startupGateController.manualSourceRestoreInProgress = false
                restartProgressUpdates()
            }
            startupGateController.commitManualSourceCandidate()
            startupGateController.commitStartupCandidate()
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
    private val autoSyncController: TvAutoSyncController = TvAutoSyncController(
        this,
        object : TvAutoSyncController.Host {
            override val activeExternalSubtitleUrl: String? get() = this@AndroidTvTorrentPlayerActivity.subtitleController.activeExternalSubtitleUrl
            override fun applySubtitleSettings(): Unit = this@AndroidTvTorrentPlayerActivity.subtitleController.applySubtitleSettings()
            override fun dp(value: Int): Int = this@AndroidTvTorrentPlayerActivity.dp(value)
            override val externalSubtitleActive: Boolean get() = this@AndroidTvTorrentPlayerActivity.subtitleController.externalSubtitleActive
            override val externalSubtitleHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.externalSubtitleHandler
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val speechTap: SpeechFeatureTap? get() = this@AndroidTvTorrentPlayerActivity.speechTap
            override val subtitleScope: CoroutineScope get() = this@AndroidTvTorrentPlayerActivity.subtitleScope
        },
    )

    // Seek feedback manager
    private lateinit var seekFeedbackManager: SeekFeedbackManager

    // State
    private var payload: PlaybackPayload? = null
    private var currentIndex = 0
    @Volatile private var activeVodHeaders: Pair<Set<String>, Map<String, String>> = emptySet<String>() to emptyMap()
    private var protectedStreamClient = ProtectedStreamHttp.client(15_000)
    private val mediaPreparationScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var mediaPreparationGeneration = 0
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
    private val showShuffle = ShowShuffle()
    private var showShuffleGeneration = 0
    private var lastBackPressTime: Long = 0

    // IPTV mode state
    private var isIptvMode = false
    private var iptvChannels = mutableListOf<IptvChannelEntry>()
    private var currentIptvIndex = 0
    private var iptvStartOverActive = false
    private var iptvStartOverLoading = false
    private var iptvStartOverTimelineVisible = false
    private val iptvStartOverController: TvIptvStartOverController = TvIptvStartOverController(
        this,
        object : TvIptvStartOverController.Host {
            override fun beginIptvPlayback(entry: IptvChannelEntry): Unit = this@AndroidTvTorrentPlayerActivity.iptvChannelStartController.beginIptvPlayback(entry)
            override fun checkpointCurrentIptvPosition(): Unit = this@AndroidTvTorrentPlayerActivity.checkpointCurrentIptvPosition()
            override fun commitIptvAllCategorySearch(): Unit = this@AndroidTvTorrentPlayerActivity.commitIptvAllCategorySearch()
            override var currentIptvIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIptvIndex = value }
            override fun hideIptvGuide(): Unit = this@AndroidTvTorrentPlayerActivity.hideIptvGuide()
            override var iptvChannels: MutableList<IptvChannelEntry>
                get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvChannels = value }
            override val iptvEpgToken: Int get() = this@AndroidTvTorrentPlayerActivity.iptvEpgToken
            override val iptvGuideVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvGuideVisible
            override var iptvSeriesAudioKey: String?
                get() = this@AndroidTvTorrentPlayerActivity.iptvSeriesAudioKey
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvSeriesAudioKey = value }
            override var iptvStartOverActive: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverActive
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverActive = value }
            override val iptvStartOverButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverButton
            override var iptvStartOverLoading: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading = value }
            override val iptvStartOverSeekButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverSeekButton
            override var iptvStartOverTimelineVisible: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible = value }
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override fun resetSubtitleState(): Unit = this@AndroidTvTorrentPlayerActivity.resetSubtitleState()
            override fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String): Unit = this@AndroidTvTorrentPlayerActivity.setIptvMediaItem(entry, streamUrl)
            override fun showControlsAndFocusProgressBar(): Unit = this@AndroidTvTorrentPlayerActivity.showControlsAndFocusProgressBar()
            override fun switchToIptvChannel(entry: IptvChannelEntry, adoptVisibleBrowseList: Boolean, checkpointOutgoing: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.switchToIptvChannel(entry, adoptVisibleBrowseList, checkpointOutgoing)
            override val titleView: TextView get() = this@AndroidTvTorrentPlayerActivity.titleView
            override fun updateIptvControlPresentation(entry: IptvChannelEntry?): Unit = this@AndroidTvTorrentPlayerActivity.updateIptvControlPresentation(entry)
            override fun updateIptvEpisodeControls(): Unit = this@AndroidTvTorrentPlayerActivity.updateIptvEpisodeControls()
        },
    )

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

    /** The Google TV Streamer must use the same stock TS join policy as the
     *  working browse preview from its first fullscreen tune. Other devices
     *  retain the faster aggressive join and the existing adaptive fallback. */
    private val iptvStartsWithStrictTs by lazy {
        IptvDeviceQuirks.startsIptvWithStrictTs(
            manufacturer = android.os.Build.MANUFACTURER,
            model = android.os.Build.MODEL,
            device = android.os.Build.DEVICE,
        )
    }

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
    private val iptvChannelStartController: TvIptvChannelStartController = TvIptvChannelStartController(
        this,
        object : TvIptvChannelStartController.Host {
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override var currentIptvStreamUrl: String?
                get() = this@AndroidTvTorrentPlayerActivity.currentIptvStreamUrl
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIptvStreamUrl = value }
            override var currentStremioSourceIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex = value }
            override fun dropStaleSourceSwitchFeedback(): Unit = this@AndroidTvTorrentPlayerActivity.sourceSwitchController.dropStaleSourceSwitchFeedback()
            override val iptvBrowseHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.iptvBrowseHandler
            override val iptvChannels: MutableList<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvRecordingActionsController: TvIptvRecordingActionsController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingActionsController
            override val iptvSourceId: String? get() = this@AndroidTvTorrentPlayerActivity.iptvSourceId
            override val iptvTwinPreferredUrls: MutableMap<String, String> get() = this@AndroidTvTorrentPlayerActivity.iptvTwinPreferredUrls
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String): Unit = this@AndroidTvTorrentPlayerActivity.setIptvMediaItem(entry, streamUrl)
            override fun setupStremioSources(): Unit = this@AndroidTvTorrentPlayerActivity.sourceSwitchController.setupStremioSources()
            override val sourceBrowser: TvSourceBrowserController? get() = this@AndroidTvTorrentPlayerActivity.sourceBrowser
            override val stremioSourceBadge: View? get() = this@AndroidTvTorrentPlayerActivity.stremioSourceBadge
            override val stremioSources: MutableList<StremioSource> get() = this@AndroidTvTorrentPlayerActivity.stremioSources
            override val subtitleTrackReadiness: SubtitleTrackReadiness get() = this@AndroidTvTorrentPlayerActivity.subtitleTrackReadiness
            override fun updateStremioQualityBadge(): Unit = this@AndroidTvTorrentPlayerActivity.sourceSwitchController.updateStremioQualityBadge()
            override fun watchSourceSwitchOutcome(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.sourceSwitchController.watchSourceSwitchOutcome(sourceIndex)
        },
    )
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

    // Stremio Sources state
    private var stremioSources = mutableListOf<StremioSource>()
    private var currentStremioSourceIndex = 0
    private var stremioSourceBadge: View? = null
    private var stremioSourceBadgeText: TextView? = null
    private var stremioResolutionToken = 0 // Guards against stale async resolution callbacks
    private var hasPlaylistResolver = false // True when source switching rebuilds entire playlist
    private var hasAdjacentEpisodeResolver = false
    private var customShuffleEpisodes: List<ShuffleEpisode>? = null
    private val startupGateController: TvStartupGateController = TvStartupGateController(
        this,
        object : TvStartupGateController.Host {
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsMenuVisible
            override var currentIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIndex = value }
            override var currentStremioSourceIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex = value }
            override fun failMoreTorrentSources(): Unit = this@AndroidTvTorrentPlayerActivity.failMoreTorrentSources()
            override val hasPlaylistResolver: Boolean get() = this@AndroidTvTorrentPlayerActivity.hasPlaylistResolver
            override fun heldResumePositionMs(actualMs: Long): Long? = this@AndroidTvTorrentPlayerActivity.heldResumePositionMs(actualMs)
            override fun hideStatusPill(): Unit = this@AndroidTvTorrentPlayerActivity.hideStatusPill()
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val isStremioTvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isStremioTvMode
            override val mediaPreparationGeneration: Int get() = this@AndroidTvTorrentPlayerActivity.mediaPreparationGeneration
            override val moreSourcesLoadingMode: String? get() = this@AndroidTvTorrentPlayerActivity.moreSourcesLoadingMode
            override val movieMoreSources: Boolean get() = this@AndroidTvTorrentPlayerActivity.movieMoreSources
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val pikPakRetryId: Int get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryId
            override fun playItem(index: Int, suppressTrakt: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.playItem(index, suppressTrakt)
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun rebuildPlaylistContent(): Unit = this@AndroidTvTorrentPlayerActivity.rebuildPlaylistContent()
            override fun reportValidatedSourceCommit(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.reportValidatedSourceCommit(sourceIndex)
            override fun requestMoreTorrentSources(mode: String): Unit = this@AndroidTvTorrentPlayerActivity.requestMoreTorrentSources(mode)
            override fun restartProgressUpdates(): Unit = this@AndroidTvTorrentPlayerActivity.restartProgressUpdates()
            override val seriesSourceTabs: Boolean get() = this@AndroidTvTorrentPlayerActivity.seriesSourceTabs
            override fun setResolvingState(resolving: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.setResolvingState(resolving)
            override fun showStatusPillTransient(message: String): Unit = this@AndroidTvTorrentPlayerActivity.showStatusPillTransient(message)
            override val sourceBrowser: TvSourceBrowserController? get() = this@AndroidTvTorrentPlayerActivity.sourceBrowser
            override val sourcePersistenceSessionId: Int get() = this@AndroidTvTorrentPlayerActivity.sourcePersistenceSessionId
            override val sourceSwitchController: TvSourceSwitchController get() = this@AndroidTvTorrentPlayerActivity.sourceSwitchController
            override val startupGateStatus: TextView get() = this@AndroidTvTorrentPlayerActivity.startupGateStatus
            override val startupGateView: View get() = this@AndroidTvTorrentPlayerActivity.startupGateView
            override var stremioResolutionToken: Int
                get() = this@AndroidTvTorrentPlayerActivity.stremioResolutionToken
                set(value) { this@AndroidTvTorrentPlayerActivity.stremioResolutionToken = value }
            override val stremioSources: MutableList<StremioSource> get() = this@AndroidTvTorrentPlayerActivity.stremioSources
            override val titleView: TextView get() = this@AndroidTvTorrentPlayerActivity.titleView
        },
    )
    private var sourcePersistenceSessionId = 0
    private var recoveryProfileId: String? = null
    private var recoveryDataGeneration = 0
    private var recoveryTitle: String? = null
    private var recoverySeriesTitle: String? = null
    private var useAddonTextFormatting = false
    private var showSourceAddonLogos = false
    private var recoveryImdbId: String? = null
    private val recoveryStartedAtMs = System.currentTimeMillis()
    private val progressReporter: TvProgressReporter = TvProgressReporter(
        this,
        object : TvProgressReporter.Host {
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override val currentStremioSourceIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex
            override val finalProgressSnapshot: Boolean get() = this@AndroidTvTorrentPlayerActivity.finalProgressSnapshot
            override fun heldResumePositionMs(actualMs: Long): Long? = this@AndroidTvTorrentPlayerActivity.heldResumePositionMs(actualMs)
            override val iptvChannels: MutableList<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val isStremioTvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isStremioTvMode
            override val manualSourceRestoreInProgress: Boolean get() = this@AndroidTvTorrentPlayerActivity.startupGateController.manualSourceRestoreInProgress
            override val manualSourceSwitchSnapshot: ManualSourceSwitchSnapshot? get() = this@AndroidTvTorrentPlayerActivity.startupGateController.manualSourceSwitchSnapshot
            override val maxStableDurationMs: Long get() = this@AndroidTvTorrentPlayerActivity.maxStableDurationMs
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val playbackSpeedIndex: Int get() = this@AndroidTvTorrentPlayerActivity.playbackSpeedIndex
            override val playbackSpeeds: Array<Float> get() = this@AndroidTvTorrentPlayerActivity.playbackSpeeds
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playlistAdapter: PlaylistOverlayAdapter? get() = this@AndroidTvTorrentPlayerActivity.playlistAdapter
            override val playlistVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.playlistVisible
            override fun recordPlaybackLifecycle(event: String, details: String): Unit = this@AndroidTvTorrentPlayerActivity.recordPlaybackLifecycle(event, details)
            override val recoveryDataGeneration: Int get() = this@AndroidTvTorrentPlayerActivity.recoveryDataGeneration
            override val recoveryImdbId: String? get() = this@AndroidTvTorrentPlayerActivity.recoveryImdbId
            override val recoveryProfileId: String? get() = this@AndroidTvTorrentPlayerActivity.recoveryProfileId
            override val recoverySeriesTitle: String? get() = this@AndroidTvTorrentPlayerActivity.recoverySeriesTitle
            override val recoveryStartedAtMs: Long get() = this@AndroidTvTorrentPlayerActivity.recoveryStartedAtMs
            override val recoveryTitle: String? get() = this@AndroidTvTorrentPlayerActivity.recoveryTitle
            override val resizeModeIndex: Int get() = this@AndroidTvTorrentPlayerActivity.resizeModeIndex
            override val resizeModeLabels: Array<String> get() = this@AndroidTvTorrentPlayerActivity.resizeModeLabels
            override val sourcePersistenceSessionId: Int get() = this@AndroidTvTorrentPlayerActivity.sourcePersistenceSessionId
            override val startupFailoverCursor: StartupFailoverCursor? get() = this@AndroidTvTorrentPlayerActivity.startupGateController.startupFailoverCursor
            override val startupSourcesExhausted: Boolean get() = this@AndroidTvTorrentPlayerActivity.startupGateController.startupSourcesExhausted
        },
    )

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
    private val stremioTvGuideController: TvStremioTvGuideController = TvStremioTvGuideController(
        this,
        object : TvStremioTvGuideController.Host {
            override fun fadeInNextOverlay(): Unit = this@AndroidTvTorrentPlayerActivity.fadeInNextOverlay()
            override fun hideControlsMenu(): Unit = this@AndroidTvTorrentPlayerActivity.hideControlsMenu()
            override fun hideNextOverlay(): Unit = this@AndroidTvTorrentPlayerActivity.hideNextOverlay()
            override var isStremioTvMode: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.isStremioTvMode
                set(value) { this@AndroidTvTorrentPlayerActivity.isStremioTvMode = value }
            override val nextSubtext: TextView get() = this@AndroidTvTorrentPlayerActivity.nextSubtext
            override val nextText: TextView get() = this@AndroidTvTorrentPlayerActivity.nextText
            override fun playStremioTvPlaybackMap(channel: StremioTvGuideChannel, map: Map<*, *>, url: String, title: String, hideGuideOnReady: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.playStremioTvPlaybackMap(channel, map, url, title, hideGuideOnReady)
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override val playlistMode: PlaylistMode get() = this@AndroidTvTorrentPlayerActivity.playlistMode
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
        },
    )

    // Subtitle Settings Panel
    private var subtitleSettingsRoot: View? = null
    private val subtitleController: TvSubtitleController = TvSubtitleController(
        this,
        object : TvSubtitleController.Host {
            override var autoSyncAppliedOffsetMs: Long?
                get() = this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncAppliedOffsetMs
                set(value) { this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncAppliedOffsetMs = value }
            override var autoSyncResultLabel: String?
                get() = this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncResultLabel
                set(value) { this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncResultLabel = value }
            override var autoSyncResultUrl: String?
                get() = this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncResultUrl
                set(value) { this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncResultUrl = value }
            override val autoSyncRunning: Boolean get() = this@AndroidTvTorrentPlayerActivity.autoSyncController.autoSyncRunning
            override fun cancelAutoSyncLadder(): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.cancelAutoSyncLadder()
            override fun cancelAutoSyncVerify(): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.cancelAutoSyncVerify()
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override var currentStremioSubtitleIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentStremioSubtitleIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentStremioSubtitleIndex = value }
            override fun currentSubtitleIdentityLabel(): String = this@AndroidTvTorrentPlayerActivity.currentSubtitleIdentityLabel()
            override val externalSubtitleHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.externalSubtitleHandler
            override val failedSubtitleUrls: MutableSet<String> get() = this@AndroidTvTorrentPlayerActivity.failedSubtitleUrls
            override fun hideStatusPill(): Unit = this@AndroidTvTorrentPlayerActivity.hideStatusPill()
            override val isLoadingStremioSubtitles: Boolean get() = this@AndroidTvTorrentPlayerActivity.isLoadingStremioSubtitles
            override var linePickerOverlay: SubtitleLinePickerController?
                get() = this@AndroidTvTorrentPlayerActivity.linePickerOverlay
                set(value) { this@AndroidTvTorrentPlayerActivity.linePickerOverlay = value }
            override val offsetRenderersFactory: OffsetRenderersFactory? get() = this@AndroidTvTorrentPlayerActivity.offsetRenderersFactory
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override val playerViewReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.playerViewReady
            override fun runSubtitleAutoSync(auto: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.runSubtitleAutoSync(auto)
            override fun scheduleAutoSyncVerify(): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.scheduleAutoSyncVerify()
            override fun showSearchSubtitleDialog(): Unit = this@AndroidTvTorrentPlayerActivity.showSearchSubtitleDialog()
            override fun showStatusPill(message: String): Unit = this@AndroidTvTorrentPlayerActivity.showStatusPill(message)
            override fun showStatusPillTransient(message: String): Unit = this@AndroidTvTorrentPlayerActivity.showStatusPillTransient(message)
            override fun showSyncToast(glyph: String, accent: Int, title: String, hint: String?, autoHideMs: Long?, uppercase: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.showSyncToast(glyph, accent, title, hint, autoHideMs, uppercase)
            override fun startAutoSyncLadder(): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.startAutoSyncLadder()
            override val stremioSubtitles: List<StremioSubtitle> get() = this@AndroidTvTorrentPlayerActivity.stremioSubtitles
            override val subtitleControlsLift: SubtitleControlsLiftController get() = this@AndroidTvTorrentPlayerActivity.subtitleControlsLift
            override val subtitleOverlay: SubtitleView get() = this@AndroidTvTorrentPlayerActivity.subtitleOverlay
            override val subtitleOverlayReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.subtitleOverlayReady
            override val subtitlePanel: SubtitlePanelController? get() = this@AndroidTvTorrentPlayerActivity.subtitlePanel
            override val subtitleScope: CoroutineScope get() = this@AndroidTvTorrentPlayerActivity.subtitleScope
            override var syncOverlay: SubtitleSyncOverlayController?
                get() = this@AndroidTvTorrentPlayerActivity.syncOverlay
                set(value) { this@AndroidTvTorrentPlayerActivity.syncOverlay = value }
            override val trackSelector: DefaultTrackSelector? get() = this@AndroidTvTorrentPlayerActivity.trackSelector
            override fun tryAutoSelectAddonSubtitle(): Unit = this@AndroidTvTorrentPlayerActivity.tryAutoSelectAddonSubtitle()
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
            override var userManuallySelectedSubtitle: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.userManuallySelectedSubtitle
                set(value) { this@AndroidTvTorrentPlayerActivity.userManuallySelectedSubtitle = value }
        },
    )
    private val playerViewReady: Boolean get() = ::playerView.isInitialized
    private val subtitleOverlayReady: Boolean get() = ::subtitleOverlay.isInitialized
    private var subtitlePanel: SubtitlePanelController? = null
    private var syncOverlay: SubtitleSyncOverlayController? = null
    private var linePickerOverlay: SubtitleLinePickerController? = null
    private var unifiedMenu: UnifiedMenuController? = null
    private var sourceBrowser: TvSourceBrowserController? = null

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
    private var subtitleAddonDiscoveryReady = false
    private var isLoadingStremioSubtitles = false  // Loading state for UI indicator
    private val subtitleTrackReadiness = SubtitleTrackReadiness()
    private var userManuallySelectedSubtitle = false  // Track if user manually selected a subtitle
    private var addonSubtitleFetchToken = 0  // Guard against stale async fetches on content switch
    private var manualSubtitleImdbId: String? = null  // Subtitle-only identity override from Search Subtitle
    private var manualSubtitleType: String? = null
    private var manualSubtitleSeason: Int? = null
    private var manualSubtitleEpisode: Int? = null
    private var manualSubtitleDisplayLabel: String? = null
    private val subtitleScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val skipSegmentController = TvSkipSegmentController(
        this,
        object : TvSkipSegmentController.Host {
            override val skipSegmentButtonBound: Boolean get() = this@AndroidTvTorrentPlayerActivity.skipSegmentButtonReady
            override val skipSegmentButton: AppCompatButton get() = this@AndroidTvTorrentPlayerActivity.skipSegmentButton
            override val skipSegmentsEnabled: Boolean get() = this@AndroidTvTorrentPlayerActivity.skipSegmentsEnabled
            override val skipSegmentProviderId: String get() = this@AndroidTvTorrentPlayerActivity.skipSegmentProviderId
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override val hasEverBeenReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.hasEverBeenReady
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsMenuVisible
            override val playlistVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.playlistVisible
            override val seekbarVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.seekbarVisible
            override val upNextVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.upNextController.upNextVisible
            override val subtitlePanel: SubtitlePanelController? get() = this@AndroidTvTorrentPlayerActivity.subtitlePanel
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
            override val sourceBrowser: TvSourceBrowserController? get() = this@AndroidTvTorrentPlayerActivity.sourceBrowser
            override val syncOverlay: SubtitleSyncOverlayController? get() = this@AndroidTvTorrentPlayerActivity.syncOverlay
            override val linePickerOverlay: SubtitleLinePickerController? get() = this@AndroidTvTorrentPlayerActivity.linePickerOverlay
            override val seekFeedbackManagerBound: Boolean get() = this@AndroidTvTorrentPlayerActivity.seekFeedbackManagerReady
            override val seekFeedbackManager: SeekFeedbackManager get() = this@AndroidTvTorrentPlayerActivity.seekFeedbackManager
            override fun releaseResumeHold() = this@AndroidTvTorrentPlayerActivity.releaseResumeHold()
        },
    )
    private val skipSegmentButtonReady: Boolean get() = ::skipSegmentButton.isInitialized
    private val seekFeedbackManagerReady: Boolean get() = ::seekFeedbackManager.isInitialized
    private val sleepTimerController = TvSleepTimerController(
        this,
        object : TvSleepTimerController.Host {
            override var sleepStopLatched: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.sleepStopLatched
                set(value) { this@AndroidTvTorrentPlayerActivity.sleepStopLatched = value }
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override fun sendProgress(completed: Boolean) = this@AndroidTvTorrentPlayerActivity.progressReporter.sendProgress(completed)
            override fun releaseScreenForSleep() = this@AndroidTvTorrentPlayerActivity.releaseScreenForSleep()
        },
    )

    /**
     * Latched from a sleep-timer stop until the user explicitly starts playback
     * again. Pausing alone is not enough to make the stop stick: `onStart()`
     * calls `play()` unconditionally, so the next time this activity restarts
     * it would resume and play through the night; a queued auto-advance would
     * do the same. Every automatic start checks this.
     */
    private var sleepStopLatched = false
    private val externalSubtitleHandler = Handler(Looper.getMainLooper())
    private var statusPill: TextView? = null
    private val statusPillHideRunnable = Runnable { hideStatusPill() }

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
    // ── Resume hold ──────────────────────────────────────────────────────────
    // While a resume target is armed and playback has not reached it, progress
    // reports substitute the TARGET for the live position. This protects the
    // stored bookmark (local and tracker-side) from the two ways a resume can
    // silently not happen: the anti-yank guard dropping the seek, and a seek
    // that a stream answers by clamping back to the start. Armed exactly where
    // the READY handler picks its seek target, so the held value is always the
    // position this player actually chose — never a re-derivation.
    // Self-releasing: playback reaching the target (within tolerance), any
    // viewer seek, an item change, or the settle window elapsing all release.
    private var resumeHoldTargetMs = 0L
    private var resumeHoldArmedAtMs = 0L

    private fun armResumeHold(targetMs: Long, durationMs: Long) {
        // Arming ALWAYS supersedes any previous hold, even when the new
        // target is rejected below — an early return that kept the old item's
        // target armed would file the old position against the new content
        // on paths that reach READY without passing playItem's release.
        releaseResumeHold()
        // Never hold a near-finished target: the Dart bridge stop-scrobbles
        // Trakt/Simkl above 80%, so substituting a target in that band would
        // finalize a watched mark for content playing at 0:00 (and ≥90% would
        // additionally read as locally finished). Those launches play
        // unguarded, like a fresh start.
        if (targetMs <= 0L || durationMs <= 0L) return
        if (targetMs >= (durationMs * 0.8).toLong()) return
        resumeHoldTargetMs = targetMs
        resumeHoldArmedAtMs = android.os.SystemClock.elapsedRealtime()
    }

    private fun releaseResumeHold() {
        resumeHoldTargetMs = 0L
    }

    // Returns the held target to report instead of [actualMs], or null when
    // no hold applies. Releases itself when playback reaches the target or
    // the 30 s settle window has elapsed (the viewer is really watching from
    // wherever playback is — their progress must not be blocked forever).
    private fun heldResumePositionMs(actualMs: Long): Long? {
        val target = resumeHoldTargetMs
        if (target <= 0L) return null
        if (actualMs >= target - RESUME_HOLD_TOLERANCE_MS) {
            releaseResumeHold()
            return null
        }
        if (android.os.SystemClock.elapsedRealtime() - resumeHoldArmedAtMs >=
            RESUME_HOLD_SETTLE_MS
        ) {
            releaseResumeHold()
            return null
        }
        return target
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Guards against falsely marking an item watched on Trakt. maxStableDurationMs
    // is the largest duration ExoPlayer has reported this item; lastRealPositionMs
    // is the most recent genuine playback position. A source re-prepare (channel/
    // source switch) can make ExoPlayer briefly report a short duration or fire a
    // spurious STATE_ENDED — either of which would otherwise inflate progress to
    // ~100% and scrobble the item as fully watched. Both reset per item.
    private var maxStableDurationMs: Long = 0L
    private var lastRealPositionMs: Long = 0L
    private val bufferingHandler = Handler(Looper.getMainLooper())
    private var bufferingDebounceRunnable: Runnable? = null

    private val progressRunnable = object : Runnable {
        override fun run() {
            progressReporter.sendProgress(completed = false)
            upNextController.maybeShowUpNext()
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
        override fun onEvents(player: Player, events: Player.Events) {
            if (isFinishing || isDestroyed) return
            progressReporter.sendPlaybackMaintenanceState()
            if (events.contains(Player.EVENT_TRACKS_CHANGED) ||
                events.contains(Player.EVENT_PLAYBACK_STATE_CHANGED)) {
                if (player.playbackState == Player.STATE_READY) {
                    subtitleTrackReadiness.onReady()
                    tryAutoSelectAddonSubtitle()
                }
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (nativeAudioRouting.reprepareIfPending(player, playbackSpeeds[playbackSpeedIndex])) return
            when (playbackState) {
                Player.STATE_READY -> {
                    if (pendingShufflePlayback?.mediaStarted == true) pendingShufflePlayback = null
                    hasEverBeenReady = true
                    iptvTuneDiagnostics.onReady(player?.currentPosition ?: 0L)
                    if (isIptvMode) {
                        iptvLiveRecovery.onReady()
                        rearmIptvTwinTrialDeadline()
                    }
                    iptvChannelStartController.reportIptvStremioWinnerIfNeeded()
                    hideBufferingIndicator()
                    // Debrid-resolved torrents commit at READY: the debrid API
                    // vouched for the link moments ago, and READY proves the
                    // stream demuxes and buffers — matching the Dart ladder's
                    // debrid-direct path. Addon direct URLs keep the
                    // first-frame proof (their stale/interstitial links are
                    // what the gate exists for), and PikPak keeps its own
                    // cold-storage gate.
                    if (startupGateController.startupFailoverCursor?.committed == false &&
                        stremioSources.getOrNull(currentStremioSourceIndex)
                            ?.streamType == "torrent" &&
                        !startupGateController.currentPlaybackItemIsPikPak()
                    ) {
                        startupGateController.commitStartupCandidate()
                    }
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
                                armResumeHold(offset, duration)
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
                                val hi = (duration * 0.9).toLong()
                                // The launched item's payload percent is an EXPLICIT
                                // promise (the details-screen Resume advertised this
                                // position) — honour it outright when seekable,
                                // matching the pre-rework launched-item behaviour.
                                val launchMs =
                                    if (launchTrakt > 0 && launchTrakt < 100) (duration * launchTrakt / 100.0).toLong() else 0L
                                // The candidate this player would seek — computed
                                // OUTSIDE the anti-yank gate so a dropped seek can
                                // still arm the resume hold: the drop leaves reports
                                // carrying the shallow live position, which must not
                                // overwrite the bookmark this target names.
                                val chosenResumeMs = if (launchMs > 2000 && launchMs < hi) {
                                    launchMs
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
                                    maxOf(traktMs, localMs)
                                }
                                // Arm only while playback is still near the
                                // start. Past ~15s the viewer has genuinely
                                // been watching (duration resolved late) —
                                // holding the stale bookmark over their real
                                // position would misreport them for 30s and
                                // discard genuine viewing on a quick exit.
                                if (chosenResumeMs > 0 && pos <= 15_000L) {
                                    armResumeHold(chosenResumeMs, duration)
                                }
                                if (pos <= 5000 && chosenResumeMs > 0) {
                                    player?.seekTo(chosenResumeMs)
                                    android.util.Log.d("AndroidTvPlayer", "Resume: chosen $chosenResumeMs ms of $duration ms (launchTrakt=${launchTrakt.toInt()}%)")
                                } else if (chosenResumeMs > 0) {
                                    android.util.Log.d("AndroidTvPlayer", "Resume: anti-yank dropped seek to $chosenResumeMs ms (pos=$pos ms) — holding bookmark")
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
                    // An unvalidated AIOStreams clip is not the programme's
                    // completion. Keep its EOF out of progress and slot advance.
                    if (isStremioTvMode && startupGateController.startupSourcesExhausted) return
                    if (isStremioTvMode && startupGateController.startupFailoverCursor?.committed == false &&
                        startupGateController.manualSourceSwitchSnapshot == null && !startupGateController.manualSourceRestoreInProgress
                    ) {
                        startupGateController.failStartupCandidate("ended-before-commit")
                        return
                    }
                    iptvTuneDiagnostics.onPlaybackEnded(lastRealPositionMs)
                    hideBufferingIndicator()
                    if (startupGateController.manualSourceRestoreInProgress) return
                    if (startupGateController.manualSourceSwitchSnapshot != null) {
                        startupGateController.failManualSourceCandidate("ended-before-commit")
                        return
                    }
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
                        if (sleepTimerController.sleepTimerMode == SleepTimerMode.END_OF_ITEM) {
                            sleepTimerController.cancelSleepTimer()
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
                    recordPlaybackLifecycle("playback_completed")
                    progressReporter.sendProgress(completed = true)

                    // "Stop at the end of this episode". Playback has already
                    // finished, so this only has to suppress every advance
                    // below and let the screen go to sleep.
                    if (sleepTimerController.sleepTimerMode == SleepTimerMode.END_OF_ITEM) {
                        sleepTimerController.cancelSleepTimer()
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
                        if (playShowShuffle(autoAdvance = true)) return
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
                        if (isStremioTvMode && stremioTvGuideController.stremioTvChannels.any { it.isCurrent }) {
                            stremioTvGuideController.requestStremioTvNext(finishOnFailure = true)
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
                            if (hasPlaylistResolver) {
                                requestAdjacentEpisodeFetch(
                                    model.imdbId,
                                    currentItem.season,
                                    currentItem.episode,
                                    autoAdvance = true,
                                )
                                return
                            }
                            if (model.imdbId != null) {
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
            if (isPlaying) iptvChannelStartController.noteLiveChannelPlaying()
        }

        override fun onPlayerError(error: PlaybackException) {
            startupGateController.mediaServerPlaybackLog("player_error", error.errorCode,
                generateSequence<Throwable>(error) { it.cause }.take(8)
                    .filterIsInstance<androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException>()
                    .firstOrNull()?.responseCode)
            if (pendingShufflePlayback?.mediaStarted == true &&
                !startupGateController.currentPlaybackItemIsPikPak() && failShufflePlayback()) return
            if (!isIptvMode && startupGateController.manualSourceRestoreInProgress) {
                startupGateController.manualSourceRestoreInProgress = false
                showStatusPillTransient("Previous source could not be restored")
                return
            }
            if (!isIptvMode && startupGateController.manualSourceSwitchSnapshot != null) {
                if (player?.playerError != null) {
                    if (startupGateController.manualSourceMediaReplaced && startupGateController.currentPlaybackItemIsPikPak()) {
                        // PikPak cold storage errors while the file warms up.
                        // The retry engine owns recovery (and reports its own
                        // exhaustion); the extended watchdog stays the bound.
                        startupLog(
                            "event=manual_error_deferred reason=pikpak-retry " +
                                "player:${error.errorCodeName}",
                        )
                        startupGateController.schedulePikPakGateReprepare()
                    } else {
                        startupGateController.failManualSourceCandidate("player:${error.errorCodeName}")
                    }
                }
                return
            }
            if (!isIptvMode && startupGateController.startupFailoverCursor?.committed == false) {
                // Ignore a queued callback from media already superseded by a
                // fallback prepare; Media3 clears playerError for that case.
                if (player?.playerError != null) {
                    if (startupGateController.currentPlaybackItemIsPikPak()) {
                        // Same PikPak exemption as the manual branch: failing
                        // here would abandon a source that recovers on its own,
                        // and the acquisition guard would then skip every other
                        // torrent row straight to "no playable source".
                        startupLog(
                            "event=candidate_error_deferred reason=pikpak-retry " +
                                "player:${error.errorCodeName}",
                        )
                        startupGateController.schedulePikPakGateReprepare()
                    } else {
                        startupGateController.failStartupCandidate("player:${error.errorCodeName}")
                    }
                }
                return
            }
            iptvTuneDiagnostics.onError(error)
            // Stale-delivery gate for EVERY IPTV recovery path below: a
            // queued onPlayerError whose media item was already superseded
            // (a zap's or the watchdog's prepare() cleared the error) reports
            // playerError == null. Acting on one would attribute channel A's
            // failure to channel B — e.g. force-HLS-poisoning B's URL for the
            // whole session, or restarting A's stream under B's identity.
            val isLiveIptvError = isIptvMode && player?.playerError != null
            if (isLiveIptvError && iptvStartOverActive) {
                // The legacy timeshift.php endpoint may serve HLS without
                // an extension. Try its format correction before returning live.
                if (iptvLiveRecoveryEligible() && retryIptvAsHlsIfUnrecognized(error)) return
                val entry = iptvChannels.getOrNull(currentIptvIndex)
                if (entry != null && entry.isLive) {
                    iptvStartOverController.cancelPendingIptvCatchupRequest()
                    // Archive rejection must not enter the live AUTH ladder.
                    if (iptvLiveRecoveryEligible()) {
                        iptvStartOverActive = false
                        iptvStartOverTimelineVisible = false
                        updateIptvControlPresentation(entry)
                        iptvChannelStartController.beginIptvPlayback(entry)
                    }
                    return
                }
            }

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
            if (isLiveIptvError && iptvChannelStartController.tryNextIptvStremioCandidate()) return
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
            DiagnosticFileLog.record(
                source = "android_tv_player",
                event = "player_error",
                message = "code=${error.errorCodeName}",
                level = "error",
            )
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
            // Resume-hold catch-all for viewer seeks arriving OUTSIDE the
            // on-screen controls (e.g. a MediaSession remote): a MEANINGFUL
            // backward seek can only be the viewer — every seek this activity
            // issues itself (resume, source-switch restore, skip) moves
            // forward. The 3s floor exists because "forward" is not exact:
            // the subtitle-offset self-seek (seekTo(currentPosition)) resolves
            // a few hundred ms BEHIND the live clock and must not release the
            // hold. Forward viewer seeks release in the control handlers, so
            // the activity's own seeks can never release the hold they arm.
            if (reason == Player.DISCONTINUITY_REASON_SEEK &&
                oldPosition.positionMs - newPosition.positionMs > 3_000L
            ) {
                releaseResumeHold()
            }
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

    private lateinit var playerPreferences: com.debrify.app.profiles.NativePlayerPreferences

    override fun onCreate(savedInstanceState: Bundle?) {
        DiagnosticFileLog.initialize(this)
        sourcePersistenceSessionId = intent.getIntExtra("playbackSessionId", 0)
        DiagnosticFileLog.recordCritical(
            source = "android_tv_player",
            event = "activity_create",
            message = "hasPayloadFile=${intent.hasExtra("payloadPath")} " +
                "pid=${android.os.Process.myPid()} activity=${System.identityHashCode(this)} " +
                "savedState=${savedInstanceState != null}",
        )
        super.onCreate(savedInstanceState)
        try {
            playerPreferences = com.debrify.app.profiles.NativePlayerPreferences.fromIntent(this, intent)
        } catch (_: Exception) {
            android.util.Log.w("AndroidTvPlayer", "Player settings handoff rejected")
            Toast.makeText(this, "Player settings could not be loaded. Try again.", Toast.LENGTH_LONG).show()
            finish()
            return
        }
        setContentView(R.layout.activity_android_tv_torrent_player)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Engine captures start/stop outside this activity (notification Stop,
        // duration cap) — the registry callback keeps the Record button honest.
        RecordingRegistry.addListener(iptvRecordingActionsController.recordingRegistryListener)

        // Load default player settings from Flutter's SharedPreferences
        loadPlayerDefaults()

        // Parse payload from temp file (avoids Android's ~1MB Intent size limit)
        val payloadPath = intent.getStringExtra("payloadPath")
        val rawPayload = if (payloadPath != null) {
            try {
                val file = java.io.File(payloadPath)
                val content = file.readText()
                file.delete() // Clean up temp file after reading
                DiagnosticFileLog.record(
                    source = "android_tv_player",
                    event = "payload_read",
                    message = "ok=true bytes=${content.length}",
                )
                android.util.Log.d("AndroidTvPlayer", "Read payload from file: $payloadPath (${content.length} bytes)")
                content
            } catch (e: Exception) {
                DiagnosticFileLog.recordError(
                    source = "android_tv_player",
                    event = "payload_read_failed",
                    throwable = e,
                )
                android.util.Log.e("AndroidTvPlayer", "Failed to read payload file: $payloadPath", e)
                null
            }
        } else {
            // Fallback to legacy Intent extra for backward compatibility
            intent.getStringExtra(PAYLOAD_KEY)
        }
        if (rawPayload.isNullOrEmpty()) {
            DiagnosticFileLog.record(
                source = "android_tv_player",
                event = "payload_missing",
                level = "warning",
            )
            finish()
            return
        }

        // Check for IPTV mode before normal payload parsing
        try {
            val payloadCheck = JSONObject(rawPayload)
            continuousShuffleEnabled = payloadCheck.optBoolean("initialContinuousShuffle", false)
            // IPTV returns from this block before [parsePayload], but its
            // finish event must still identify the bridge launch that owns
            // the callbacks it is about to clear.
            sourcePersistenceSessionId =
                payloadCheck.optInt("sourcePersistenceSessionId", sourcePersistenceSessionId)
            recoveryProfileId = payloadCheck.nullableString("playbackOwnerProfileId")
            recoveryDataGeneration =
                payloadCheck.optInt("playbackOwnerDataGeneration", 0)
            recoveryTitle = payloadCheck.nullableString("title")
            recoverySeriesTitle = payloadCheck.nullableString("seriesTitle")
            useAddonTextFormatting = payloadCheck.optBoolean("useAddonTextFormatting", false)
            showSourceAddonLogos = payloadCheck.optBoolean("showAddonLogos", false)
            recoveryImdbId = payloadCheck.nullableString("imdbId")
            if (payloadCheck.optString("mode") == "iptv") {
                initIptvMode(payloadCheck)
                return
            }
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "IPTV mode check failed", e)
        }

        payload = parsePayload(rawPayload)
        if (payload == null || payload!!.items.isEmpty()) {
            DiagnosticFileLog.record(
                source = "android_tv_player",
                event = "payload_invalid",
                level = "warning",
            )
            finish()
            return
        }
        currentIndex = payload!!.startIndex.coerceIn(0, payload!!.items.lastIndex)
        DiagnosticFileLog.record(
            source = "android_tv_player",
            event = "payload_ready",
            message = "items=${payload!!.items.size} startIndex=$currentIndex " +
                "sources=${stremioSources.size} " +
                "provider=${diagnosticProvider(payload!!.items[currentIndex].provider)}",
        )

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
        startupLog("event=player_setup_begin")
        setupPlayer()
        startupLog("event=player_setup_complete")
        setupSeekbar()
        setupPlaylist()
        setupControls()
        sourceSwitchController.setupStremioSources()

        // Check for Stremio TV guide data in payload
        try {
            val payloadJson = JSONObject(rawPayload)
            val guideJson = payloadJson.optJSONObject("stremioTvGuide")
            if (guideJson != null) {
                stremioTvGuideController.initStremioTvGuide(guideJson)
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
        startupGateController.beginStartupFailoverIfEligible()
        playItem(currentIndex)
    }

    private fun setupMetadataReceiver() {
        metadataUpdateReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
                // Large JSON arrives as cacheDir file paths — inline extras
                // over the binder limit get the process killed by the system
                // ("can't deliver broadcast"). Inline extras remain as a
                // fallback; a missing/unreadable file just skips the update.
                val updatesJson = readStagedExtra(
                    intent, "metadataUpdatesPath", "episode_metadata_",
                ) ?: intent?.getStringExtra("metadataUpdates")
                val imdbId = intent?.getStringExtra("imdbId")
                val guideJson = readStagedExtra(
                    intent, "guideEpisodesPath", "episode_guide_",
                ) ?: intent?.getStringExtra("guideEpisodes")
                val showName = intent?.getStringExtra("showName")
                handleMetadataUpdate(updatesJson, imdbId, guideJson, showName)
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

    /** Reads a staged cacheDir JSON file whose path rides in [key].
     *  Returns null when the extra is absent or the file can't be read.
     *
     *  Read-only on purpose: during an activity handoff two player instances
     *  briefly have live receivers, and a delete-on-read would let the dying
     *  one consume the file before the live one sees it. The sender sweeps
     *  old staged files on each push instead.
     *
     *  Pre-33 the receiver is effectively exported, so never trust the path:
     *  only files of the expected [prefix] directly inside our cacheDir. */
    private fun readStagedExtra(
        intent: android.content.Intent?,
        key: String,
        prefix: String,
    ): String? {
        val path = intent?.getStringExtra(key) ?: return null
        return try {
            val file = java.io.File(path).canonicalFile
            if (file.parentFile?.canonicalPath != cacheDir.canonicalPath ||
                !file.name.startsWith(prefix)
            ) {
                android.util.Log.e("TVMazeUpdate", "Rejected staged $key outside cacheDir")
                return null
            }
            file.readText()
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "Failed to read staged $key: ${e.message}")
            null
        }
    }

    private fun handleMetadataUpdate(
        updatesJson: String?,
        imdbId: String?,
        guideJson: String? = null,
        showName: String? = null,
    ) {
        android.util.Log.d("TVMazeUpdate", "handleMetadataUpdate CALLED")
        android.util.Log.d("TVMazeUpdate", "updatesJson length=${updatesJson?.length ?: 0}, imdbId=$imdbId")

        // TVMaze's official show title — the OTT dock's identity line reads
        // it; the payload title (often a release filename) never renders.
        if (!showName.isNullOrBlank()) {
            ottShowName = showName.trim()
            if (ottSkinInstalled) runOnUiThread { updateOttIdentity() }
        }

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
                            shuffleEligible = g.optBoolean("shuffleEligible", true),
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
                            model.items.getOrNull(currentIndex)?.let { updateTitle(it) }
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
                    allowLocalProgressDisplay = update.optBoolean("allowLocalProgressDisplay", item.allowLocalProgressDisplay),
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
        startupGateView = findViewById(R.id.android_tv_startup_gate)
        startupGateStatus = findViewById(R.id.android_tv_startup_gate_status)
        findViewById<View>(R.id.startup_back).setOnClickListener { finish() }
        findViewById<View>(R.id.startup_details).setOnClickListener {
            android.app.AlertDialog.Builder(this)
                .setTitle("Playback details")
                .setMessage("Connecting to source ${startupGateController.startupFailoverCursor?.attempts ?: 1} of ${if (startupGateController.startupTryNextOnFailure) startupGateController.startupMaxAttempts else 1}. Waiting for a valid first frame.")
                .setPositiveButton("Close", null).show()
        }
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
        subtitleControlsLift = SubtitleControlsLiftController(subtitleOverlay, dp(24))
        // Guide skin: swap the overlay children BEFORE the playlist binds so
        // they resolve inside the skin's layout (no-op on CLASSIC).
        installGuideOverlaySkin()
        playlistOverlay = findViewById(R.id.android_tv_playlist_overlay)
        playlistView = findViewById(R.id.android_tv_playlist)
        seasonTabsContainer = findViewById(R.id.season_tabs_container)
        bindGuideSkinViews()
        nextOverlay = findViewById(R.id.android_tv_next_overlay)
        nextText = findViewById(R.id.android_tv_next_text)
        nextSubtext = findViewById(R.id.android_tv_next_subtext)
        nextBackdrop = findViewById(R.id.android_tv_next_backdrop)
        upNextController.upNextCard = findViewById(R.id.android_tv_upnext_card)
        upNextController.upNextPoster = findViewById(R.id.android_tv_upnext_poster)
        upNextController.upNextTitle = findViewById(R.id.android_tv_upnext_title)
        upNextController.upNextCountdown = findViewById(R.id.android_tv_upnext_countdown)
        skipSegmentButton = findViewById(R.id.android_tv_skip_segment_button)
        skipSegmentButton.setOnClickListener { skipSegmentController.skipActiveSegment() }
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
                callbacks = subtitleController.subtitlePanelCallbacks
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
                callbacks = unifiedMenuCallbacks,
                sectionIds = unifiedSectionIds,
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
                    override fun entries(): List<TvSourceBrowserEntry> = stremioSources.filter { source ->
                        val item = payload?.items?.getOrNull(currentIndex)
                        source.index == currentStremioSourceIndex || sourceVisibleForEpisode(
                            source.streamType, source.videoId, item?.season, item?.episode
                        )
                    }.map { source ->
                        val original = if (useAddonTextFormatting) source.addonPresentation else null
                        TvSourceBrowserEntry(
                            index = source.index,
                            title = original?.first ?: source.displayTitle,
                            description = original?.second,
                            originalText = original != null,
                            transport = source.streamType,
                            addonName = if (showSourceAddonLogos) source.addonDisplayName else null,
                            addonLogo = if (showSourceAddonLogos) source.addonLogo else null,
                            source = source.source,
                            quality = source.quality,
                            size = source.formattedSize,
                            seeders = source.seeders,
                            direct = source.isDirectStream,
                            seasonPack = source.isSeasonPack,
                            badgeName = source.name,
                            badgeDescription = source.badgeDescription,
                        )
                    }

                    override fun requestBadges(entry: TvSourceBrowserEntry, complete: (TvSourceBadgeResult?) -> Unit) {
                        val channel = MainActivity.getAndroidTvPlayerChannel()
                        if (channel == null) { complete(null); return }
                        channel.invokeMethod("requestStreamBadges", mapOf(
                            "sourcePersistenceSessionId" to sourcePersistenceSessionId,
                            "name" to entry.badgeName,
                            "description" to entry.badgeDescription,
                        ), object : io.flutter.plugin.common.MethodChannel.Result {
                            override fun success(result: Any?) {
                                complete(if (isFinishing || isDestroyed) null else TvSourceBadgeResult.parse(result))
                            }
                            override fun error(code: String, message: String?, details: Any?) { complete(null) }
                            override fun notImplemented() { complete(null) }
                        })
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
                        startupGateController.sourceSelectionLog("player_manual_pick", index, currentStremioSourceIndex)
                        sourceBrowser?.hide()
                        sourceSwitchController.onStremioSourceSelected(source)
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
        val defaultAudioLang = playerPreferences.getString("player_default_audio_language", null)
        val defaultSubtitleLang = playerPreferences.getString("player_default_subtitle_language", null)

        // Build track selector parameters with robust language matching
        val paramsBuilder = trackSelector?.buildUponParameters()
            // HDMI can temporarily lose surround support during a display-mode
            // switch. Reconsider PCM fallback when the capabilities return.
            ?.setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
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
                paramsBuilder?.setPreferredTextLanguage("")
                paramsBuilder?.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
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

        // Start with text off until the selected audio is known. This also
        // prevents a file's default/forced track flashing before policy runs.
        // Wait for exact regional matching; ExoPlayer can treat pt-PT as a
        // partial match for pt-BR during its initial track selection.
        if (playerPreferences.getBoolean("subtitle_only_foreign_audio", false) ||
            playerPreferences.getBoolean("subtitle_forced_only", false) ||
            defaultSubtitleLang?.equals("pt-BR", ignoreCase = true) == true) {
            paramsBuilder?.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
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
        nativeAudioRouting.update(nightModeIndex > 0, systemAudioEffectsEnabled, playbackSpeeds[playbackSpeedIndex])
        val baseRenderersFactory = NativeAudioRenderersFactory(
            this, nativeAudioRouting, arrayOf(tap.processor),
        )
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
        protectedStreamClient = ProtectedStreamHttp.client(networkTimeoutMs)
        val vodHttpFactory = VodHttpDataSource.Factory(
            httpDataSourceFactory,
            ProtectedStreamHttp.dataSourceFactory(protectedStreamClient),
        )
        val upstreamDataSourceFactory = DefaultDataSource.Factory(
            this, if (isIptvMode) httpDataSourceFactory else vodHttpFactory,
        )
        val dataSourceFactory = run {
            ResolvingDataSource.Factory(
                upstreamDataSourceFactory,
                object : ResolvingDataSource.Resolver {
                    override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
                        val (protectedMediaOrigins, playbackHeaders) = activeVodHeaders
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
                iptvRecordingActionsController.updateRecordButtonState()
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
                .setLoadErrorHandlingPolicy(IptvLiveLoadErrorPolicy { iptvChannels.getOrNull(currentIptvIndex)?.isLive == true })
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

        when (displayMatchMode) {
            TvContentDisplayMatchMode.OFF -> playerBuilder.setVideoChangeFrameRateStrategy(
                C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF,
            )
            TvContentDisplayMatchMode.FRAME_RATE,
            TvContentDisplayMatchMode.FRAME_RATE_AND_RESOLUTION,
            -> playerBuilder.setVideoChangeFrameRateStrategy(
                C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS,
            )
            TvContentDisplayMatchMode.SYSTEM -> Unit
        }

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
        player?.setPlaybackSpeed(playbackSpeeds[playbackSpeedIndex])

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
                if (subtitleController.externalSubtitleActive) return
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
        SubtitleSettings.setActiveSubtitleIdentityProvider(this) { subtitleController.currentSubtitleIdentity() }
        subtitleController.applySubtitleSettings()

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

    // ── Guide skin ─────────────────────────────────────────────────────────
    // The series/collection Episodes overlay, restyled per dock skin: the
    // legacy overlay children are swapped for a per-skin layout that keeps
    // the id contract (android_tv_playlist + season_tabs_container), and the
    // adapters get a per-skin row layout + binder. CLASSIC never installs.
    //   OTT       — "The Shelf": bottom row of landscape stills.
    //   MARQUEE   — "The Playbill": serif index left, title page right.
    //   FROST     — "The Panel": translucent side sheet, video keeps playing.
    //   BROADCAST — "The Rundown": mono columns + PVW monitor, yellow bar focus.
    //   PULSE     — "The Grid": progress-ring cells, season rail on the left.
    //   TICKET    — "The Strip": slim bottom band, popover previews on focus.
    private var guideSkinInstalled = false
    private val guideGridSpan = 5
    private var gdShowTitle: TextView? = null
    private var gdCaption: TextView? = null
    private var gdDetailNum: TextView? = null
    private var gdDetailTitle: TextView? = null
    private var gdDetailMeta: TextView? = null
    private var gdDetailDesc: TextView? = null
    private var gdDetailArt: android.widget.ImageView? = null
    private var gdMonArt: android.widget.ImageView? = null
    private var gdMonLabel: TextView? = null
    private var gdPop: View? = null
    private var gdPopArt: android.widget.ImageView? = null
    private var gdPopTitle: TextView? = null
    private var gdPopDesc: TextView? = null

    private val guideOverlayLayoutRes: Int?
        get() = when (controlsSkin) {
            TvControlsSkin.CLASSIC -> null
            TvControlsSkin.OTT -> R.layout.view_tv_guide_ott
            TvControlsSkin.FROST -> R.layout.view_tv_guide_frost
            TvControlsSkin.MARQUEE -> R.layout.view_tv_guide_marquee
            TvControlsSkin.BROADCAST -> R.layout.view_tv_guide_broadcast
            TvControlsSkin.PULSE -> R.layout.view_tv_guide_pulse
            TvControlsSkin.TICKET -> R.layout.view_tv_guide_ticket
        }

    private val guideItemLayoutRes: Int
        get() = if (!guideSkinInstalled) {
            R.layout.item_android_tv_playlist_entry_horizontal
        } else when (controlsSkin) {
            TvControlsSkin.OTT -> R.layout.item_tv_guide_ott
            TvControlsSkin.FROST -> R.layout.item_tv_guide_frost
            TvControlsSkin.MARQUEE -> R.layout.item_tv_guide_marquee
            TvControlsSkin.BROADCAST -> R.layout.item_tv_guide_broadcast
            TvControlsSkin.PULSE -> R.layout.item_tv_guide_pulse
            TvControlsSkin.TICKET -> R.layout.item_tv_guide_ticket
            TvControlsSkin.CLASSIC -> R.layout.item_android_tv_playlist_entry_horizontal
        }

    /** Swap the legacy overlay children for the skin's guide layout. Runs in
     *  bindViews BEFORE any playlist findViewById so every legacy binding
     *  resolves inside the new layout. */
    private fun installGuideOverlaySkin() {
        if (guideSkinInstalled) return
        val layoutRes = guideOverlayLayoutRes ?: return
        val overlay = findViewById<ViewGroup?>(R.id.android_tv_playlist_overlay) ?: return
        overlay.removeAllViews()
        layoutInflater.inflate(layoutRes, overlay, true)
        guideSkinInstalled = true
    }

    /** Null-safe binds for the skin-only views (each layout has a subset). */
    private fun bindGuideSkinViews() {
        if (!guideSkinInstalled) return
        gdShowTitle = findViewById(R.id.gd_show_title)
        gdCaption = findViewById(R.id.gd_caption)
        gdDetailNum = findViewById(R.id.gd_detail_num)
        gdDetailTitle = findViewById(R.id.gd_detail_title)
        gdDetailMeta = findViewById(R.id.gd_detail_meta)
        gdDetailDesc = findViewById(R.id.gd_detail_desc)
        gdDetailArt = findViewById(R.id.gd_detail_art)
        gdMonArt = findViewById(R.id.gd_mon_art)
        gdMonLabel = findViewById(R.id.gd_mon_label)
        gdPop = findViewById(R.id.gd_pop)
        gdPopArt = findViewById(R.id.gd_pop_art)
        gdPopTitle = findViewById(R.id.gd_pop_title)
        gdPopDesc = findViewById(R.id.gd_pop_desc)
    }

    /** Vertical list for the reading skins, 5-up grid for PULSE; OTT/TICKET
     *  keep the legacy horizontal manager. */
    private fun applyGuideLayoutManager() {
        if (!guideSkinInstalled) return
        when (controlsSkin) {
            TvControlsSkin.MARQUEE, TvControlsSkin.FROST, TvControlsSkin.BROADCAST -> {
                playlistView.layoutManager =
                    LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false)
            }
            TvControlsSkin.PULSE -> {
                val glm = androidx.recyclerview.widget.GridLayoutManager(this, guideGridSpan)
                glm.spanSizeLookup =
                    object : androidx.recyclerview.widget.GridLayoutManager.SpanSizeLookup() {
                        override fun getSpanSize(position: Int): Int {
                            // Series season headers (view type 0) span the full
                            // row. Collection adapters have a single view type
                            // (also 0), so gate on the mode — every movie cell
                            // is a normal 1-span cell.
                            if (playlistMode != PlaylistMode.SERIES) return 1
                            val adapter = playlistView.adapter ?: return 1
                            return if (adapter.getItemViewType(position) == 0) guideGridSpan else 1
                        }
                    }
                playlistView.layoutManager = glm
            }
            else -> Unit
        }
    }

    /** The legacy key listener assumes a horizontal row (LEFT/RIGHT move,
     *  UP/DOWN escape to tabs). Vertical and grid skins swap the axes —
     *  deliberate last-set-wins over the listener set just above. */
    private fun applyGuideKeyOverride() {
        if (!guideSkinInstalled) return
        val vertical = controlsSkin == TvControlsSkin.MARQUEE ||
            controlsSkin == TvControlsSkin.FROST ||
            controlsSkin == TvControlsSkin.BROADCAST
        val grid = controlsSkin == TvControlsSkin.PULSE
        if (!vertical && !grid) return // OTT/TICKET: the horizontal listener is right
        playlistView.setOnKeyListener { _, keyCode, event ->
            if (!playlistVisible) return@setOnKeyListener false
            if (event.action != KeyEvent.ACTION_DOWN) return@setOnKeyListener false
            // Mirror movePlaylistFocus: during rapid input focus is in flight
            // and focusedChild is null — the tracked target is the truth, or
            // the edge decisions below (escape to tabs/rail) misfire.
            val pos = if (navigationTargetPosition >= 0) {
                navigationTargetPosition
            } else {
                playlistView.focusedChild
                    ?.let { playlistView.getChildAdapterPosition(it) }
                    ?: RecyclerView.NO_POSITION
            }
            if (vertical) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_DOWN -> { movePlaylistFocus(1); true }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        val first = findNextFocusablePosition(0, 1)
                        if (pos != RecyclerView.NO_POSITION && pos <= first) {
                            false // top row: let focus escape to the season tabs
                        } else {
                            movePlaylistFocus(-1); true
                        }
                    }
                    // Trap the cross axis so focus can't fall out of the overlay.
                    KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> true
                    else -> false
                }
            } else {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_RIGHT -> { movePlaylistFocus(1); true }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        // Column via the span lookup, not pos % span — a
                        // full-span season header would shift every row.
                        val col = (playlistView.layoutManager
                            as? androidx.recyclerview.widget.GridLayoutManager)
                            ?.spanSizeLookup
                            ?.takeIf { pos != RecyclerView.NO_POSITION }
                            ?.getSpanIndex(pos, guideGridSpan)
                        if (col == 0) {
                            false // first column: escape to the season rail
                        } else {
                            movePlaylistFocus(-1); true
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_DOWN -> { movePlaylistFocus(guideGridSpan); true }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        if (pos >= guideGridSpan) movePlaylistFocus(-guideGridSpan)
                        true
                    }
                    else -> false
                }
            }
        }
    }

    /** Restyle a season/collection tab into the skin's language (called after
     *  the legacy styling; classic tabs untouched). */
    private fun applyGuideTabStyle(tab: TextView) {
        if (!guideSkinInstalled) return
        val csl = { res: Int -> androidx.core.content.ContextCompat.getColorStateList(this, res) }
        when (controlsSkin) {
            TvControlsSkin.OTT -> {
                tab.background = null
                tab.setTextColor(csl(R.color.gd_tab_text_light))
                tab.textSize = 13f
            }
            TvControlsSkin.MARQUEE -> {
                tab.background = null
                tab.setTextColor(csl(R.color.gd_tab_text_marquee))
                tab.typeface = android.graphics.Typeface.create("serif", android.graphics.Typeface.BOLD)
                tab.textSize = 11.5f
                tab.letterSpacing = 0.14f
            }
            TvControlsSkin.FROST -> {
                tab.setBackgroundResource(R.drawable.gd_tab_frost)
                tab.setTextColor(csl(R.color.gd_tab_text_bcast))
                tab.textSize = 11f
                tab.setPadding(dp(11), dp(4), dp(11), dp(4))
            }
            TvControlsSkin.BROADCAST -> {
                tab.setBackgroundResource(R.drawable.gd_tab_bcast)
                tab.setTextColor(csl(R.color.gd_tab_text_bcast))
                tab.typeface = android.graphics.Typeface.create(
                    android.graphics.Typeface.MONOSPACE, android.graphics.Typeface.BOLD)
                tab.textSize = 10.5f
                tab.setPadding(dp(8), dp(3), dp(8), dp(3))
            }
            TvControlsSkin.PULSE -> {
                tab.setBackgroundResource(R.drawable.gd_tab_pulse)
                tab.setTextColor(csl(R.color.gd_tab_text_pulse))
                tab.textSize = 11.5f
                tab.setPadding(dp(10), dp(5), dp(10), dp(5))
                (tab.layoutParams as? android.widget.LinearLayout.LayoutParams)?.let {
                    it.marginEnd = 0
                    it.bottomMargin = dp(6) // vertical rail
                    it.width = android.widget.LinearLayout.LayoutParams.MATCH_PARENT
                }
                tab.gravity = android.view.Gravity.CENTER
            }
            TvControlsSkin.TICKET -> {
                tab.setBackgroundResource(R.drawable.gd_tab_ticket)
                tab.setTextColor(csl(R.color.gd_tab_text_ticket))
                tab.typeface = android.graphics.Typeface.MONOSPACE
                tab.textSize = 9f
                tab.setPadding(dp(6), dp(1), dp(6), dp(1))
            }
            TvControlsSkin.CLASSIC -> Unit
        }
    }

    /** Per-skin row styling appended after the shared bind. itemIndex is -1
     *  for absent guide rows (fetch-on-click). */
    private fun guideSkinBind(itemView: View, item: PlaybackItem, itemIndex: Int, isActive: Boolean) {
        val progress = item.displayProgressPercent()
        val watched = progress >= 95
        when (controlsSkin) {
            TvControlsSkin.MARQUEE, TvControlsSkin.TICKET -> {
                if (controlsSkin == TvControlsSkin.MARQUEE) {
                    itemView.findViewById<TextView?>(R.id.gd_item_num)?.text =
                        item.episode?.toString() ?: if (itemIndex >= 0) (itemIndex + 1).toString() else "·"
                }
                itemView.findViewById<TextView?>(R.id.android_tv_playlist_item_title)?.let { t ->
                    t.paintFlags = if (watched && !isActive) {
                        t.paintFlags or android.graphics.Paint.STRIKE_THRU_TEXT_FLAG
                    } else {
                        t.paintFlags and android.graphics.Paint.STRIKE_THRU_TEXT_FLAG.inv()
                    }
                }
            }
            TvControlsSkin.BROADCAST -> {
                val season = item.season
                val episode = item.episode
                itemView.findViewById<TextView?>(R.id.gd_item_num)?.text = when {
                    season != null && episode != null -> "%d%02d".format(season, episode)
                    episode != null -> "%03d".format(episode)
                    itemIndex >= 0 -> "%03d".format(itemIndex + 1)
                    else -> "———"
                }
                itemView.findViewById<TextView?>(R.id.gd_item_status)?.let { status ->
                    val (text, color) = when {
                        itemIndex < 0 && !isActive && item.url.isEmpty() ->
                            "FETCH" to 0xFFF5C518.toInt()
                        isActive -> "● ON AIR" to 0xFFEF4444.toInt()
                        watched -> "CLEARED" to 0x66FFFFFF.toInt()
                        progress in 6..94 -> "$progress% IN" to 0x8CFFFFFF.toInt()
                        else -> "READY" to 0x8CFFFFFF.toInt()
                    }
                    status.text = text
                    // Stateful color: the yellow focus bar needs dark text —
                    // a plain int here would defeat the row's focus flip.
                    status.setTextColor(
                        android.content.res.ColorStateList(
                            arrayOf(
                                intArrayOf(android.R.attr.state_focused),
                                intArrayOf(),
                            ),
                            intArrayOf(0xDE000000.toInt(), color),
                        )
                    )
                }
            }
            TvControlsSkin.PULSE -> {
                itemView.findViewById<android.widget.ProgressBar?>(R.id.gd_ring)?.progress =
                    if (watched) 100 else progress
                itemView.findViewById<TextView?>(R.id.gd_ring_num)?.text =
                    item.episode?.toString()
                        ?: if (itemIndex >= 0) (itemIndex + 1).toString() else "?"
            }
            else -> Unit
        }
    }

    /** The focused row feeds the skin's detail surface (Marquee title page,
     *  OTT caption, Broadcast PVW monitor, Pulse caption line, Ticket popover). */
    private fun updateGuideDetail(item: PlaybackItem) {
        if (!guideSkinInstalled) return
        val desc = item.description?.trim()
            ?.takeUnless { it.equals("null", ignoreCase = true) || it.isBlank() }
        val mins = (item.durationMs / 60000).toInt().takeIf { it > 0 }
        val se = if (item.season != null && item.episode != null) {
            "S%02dE%02d".format(item.season, item.episode)
        } else null
        when (controlsSkin) {
            TvControlsSkin.OTT -> gdCaption?.text = desc ?: ""
            TvControlsSkin.MARQUEE -> {
                gdDetailNum?.text = item.episode?.let { "%02d".format(it) } ?: ""
                gdDetailTitle?.text = item.title
                val parts = mutableListOf<String>()
                if (item.season != null && item.episode != null) {
                    parts.add("SEASON ${item.season} · EPISODE ${item.episode}")
                }
                item.rating?.takeIf { it > 0 }?.let { parts.add("★ %.1f".format(it)) }
                mins?.let { parts.add("$it MIN") }
                gdDetailMeta?.text = parts.joinToString("   ·   ")
                gdDetailDesc?.text = desc ?: ""
                loadGuideArt(gdDetailArt, item.artwork)
            }
            TvControlsSkin.BROADCAST -> {
                gdMonLabel?.text = "PVW · " + (se ?: item.title.uppercase(Locale.US))
                loadGuideArt(gdMonArt, item.artwork)
            }
            TvControlsSkin.PULSE -> {
                val lead = item.episode?.let { "E$it · " } ?: ""
                gdDetailDesc?.text = lead + item.title + (desc?.let { " — $it" } ?: "")
            }
            TvControlsSkin.TICKET -> {
                gdPop?.visibility = View.VISIBLE
                gdPopTitle?.text = (se?.let { "$it · " } ?: "") + item.title.uppercase(Locale.US)
                val meta = mutableListOf<String>()
                mins?.let { meta.add("${it}m") }
                item.rating?.takeIf { it > 0 }?.let { meta.add("★ %.1f".format(it)) }
                gdPopDesc?.text = desc ?: meta.joinToString(" · ")
                loadGuideArt(gdPopArt, item.artwork)
            }
            else -> Unit
        }
    }

    private fun loadGuideArt(target: android.widget.ImageView?, artwork: String?) {
        val v = target ?: return
        val art = artwork?.takeUnless { it.equals("null", ignoreCase = true) || it.isBlank() }
        if (art == null) {
            com.bumptech.glide.Glide.with(this).clear(v)
            v.setImageDrawable(null)
            return
        }
        com.bumptech.glide.Glide.with(this).load(art).centerCrop().into(v)
    }

    /** Show-open chrome: show title, counts, and the current item seeding the
     *  detail surface so the pane is never empty. */
    private fun seedGuideSkinChrome() {
        if (!guideSkinInstalled) return
        val model = payload
        val current = model?.items?.getOrNull(currentIndex)
        val show = ottShowName?.takeIf { it.isNotBlank() }
            ?: current?.title
            ?: ""
        gdShowTitle?.text = when (controlsSkin) {
            TvControlsSkin.BROADCAST, TvControlsSkin.TICKET -> show.uppercase(Locale.US)
            else -> show
        }
        val items = model?.items.orEmpty()
        if (items.size > 1) {
            val watchedCount = items.count { it.displayProgressPercent() >= 95 }
            when (controlsSkin) {
                TvControlsSkin.FROST, TvControlsSkin.PULSE ->
                    gdCaption?.text = "${items.size} episodes · $watchedCount watched"
                TvControlsSkin.BROADCAST ->
                    gdCaption?.text = "${items.size} LISTED · OK ROLLS THE FOCUSED ITEM"
                else -> Unit
            }
        }
        current?.let { updateGuideDetail(it) }
    }

    private fun setupPlaylist() {
        // Configure RecyclerView for optimal focus handling
        playlistView.layoutManager = LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false).apply {
            // Pre-fetch items for smoother scrolling
            isItemPrefetchEnabled = true
            initialPrefetchItemCount = 4
        }
        // Guide skin: vertical/grid managers replace the horizontal one (no-op
        // on CLASSIC and the horizontal skins).
        applyGuideLayoutManager()

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
            itemLayoutRes = guideItemLayoutRes,
            skinBinder = if (guideSkinInstalled) ::guideSkinBind else null,
            onItemFocused = if (guideSkinInstalled) { item, _ -> updateGuideDetail(item) } else null,
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
        val adapter = MoviePlaylistAdapter(
            items,
            groups,
            itemLayoutRes = guideItemLayoutRes,
            skinBinder = if (guideSkinInstalled) ::guideSkinBind else null,
            onItemFocused = if (guideSkinInstalled) { item, _ -> updateGuideDetail(item) } else null,
        ) { index ->
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

        applyGuideTabStyle(tab)
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

        // Guide skin: vertical/grid skins re-map the DPAD axes (no-op on
        // CLASSIC and the horizontal skins).
        applyGuideKeyOverride()
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

        applyGuideTabStyle(tab)
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

    /** Swaps the legacy Cinema controller layout for the selected dock skin.
     *
     * Media3 inflates `controller_layout_id` INTO its PlayerControlView with
     * attachToRoot, so the legacy root is an ordinary child we can replace at
     * the same index. Every dock layout shares every id the activity binds,
     * and the activity (not Media3) drives `debrify_controls_root` visibility,
     * so all downstream code works against whichever root is installed. Must
     * run before ANY controller-id findViewById — setupControls calls it first.
     */
    private fun installOttControlsSkin() {
        val spec = dockSkinSpec ?: return
        val legacy = playerView.findViewById<View>(R.id.debrify_controls_root) ?: return
        val parent = legacy.parent as? ViewGroup ?: return
        val index = parent.indexOfChild(legacy)
        val ott = try {
            LayoutInflater.from(this).inflate(spec.layoutRes, parent, false)
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Dock skin inflate failed; keeping classic", e)
            return
        }
        parent.removeViewAt(index)
        parent.addView(ott, index)
        ottSkinInstalled = true

        // The Flutter OTT scrim has FOUR stops; XML gradients cap at three, so
        // that one skin's placeholder background is replaced with the exact
        // ramp here. Every other skin's XML background is already final.
        if (spec.applyShaderScrim) {
            ott.findViewById<View>(R.id.ott_content)?.background = PaintDrawable().apply {
                shape = RectShape()
                shaderFactory = object : ShapeDrawable.ShaderFactory() {
                    override fun resize(width: Int, height: Int): Shader = LinearGradient(
                        0f, 0f, 0f, height.toFloat(),
                        intArrayOf(0x00000000, 0x66000000, 0xD9000000.toInt(), 0xF2000000.toInt()),
                        floatArrayOf(0f, 0.28f, 0.62f, 1f),
                        Shader.TileMode.CLAMP,
                    )
                }
            }
        }

        ottCaptionLabel = ott.findViewById(R.id.ott_caption_label)
        ottIdentityTitle = ott.findViewById(R.id.ott_identity_title)
        ottIdentitySubtitle = ott.findViewById(R.id.ott_identity_subtitle)
        ottIdentityOverline = ott.findViewById(R.id.ott_identity_overline)
        ottIdentityBadge = ott.findViewById(R.id.ott_identity_badge)
        ottIdentityDivider = ott.findViewById(R.id.ott_identity_divider)
        ottQualityChips[0] = ott.findViewById(R.id.ott_quality_1)
        ottQualityChips[1] = ott.findViewById(R.id.ott_quality_2)
        ottQualityChips[2] = ott.findViewById(R.id.ott_quality_3)
        ottRatingChip = ott.findViewById(R.id.ott_rating_chip)
        ottMetaLine = ott.findViewById(R.id.ott_meta_line)
        ottScrubPreviewChip = ott.findViewById(R.id.ott_scrub_preview_chip)
        ottScrubPreviewText = ott.findViewById(R.id.ott_scrub_preview_text)
        ottProgressTrackContainer = ott.findViewById(R.id.cinema_progress_track_container)

        // Idle bar height per spec; enter/exit cinema seek toggles it.
        setOttTrackHeight(focused = false)

        ott.findViewById<View>(R.id.ott_seek_back_button)?.setOnClickListener {
            seekBy(-10_000L)
            scheduleHideControlsMenu()
        }
        ott.findViewById<View>(R.id.ott_seek_forward_button)?.setOnClickListener {
            seekBy(10_000L)
            scheduleHideControlsMenu()
        }

        ottSourcesButton = ott.findViewById(R.id.ott_sources_button)
        // Same behaviour as the top-right badge this button replaces.
        ottSourcesButton?.setOnClickListener {
            hideControlsMenu()
            unifiedMenu?.hide()
            sourceBrowser?.show()
        }
    }

    private fun setOttTrackHeight(focused: Boolean) {
        val track = ottProgressTrackContainer ?: return
        val spec = dockSkinSpec ?: return
        val heightPx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            if (focused) spec.trackFocusDp else spec.trackIdleDp,
            resources.displayMetrics,
        ).toInt()
        val params = track.layoutParams
        if (params.height != heightPx) {
            params.height = heightPx
            track.layoutParams = params
        }
    }

    /** The shared caption under the OTT transport row: the focused button's
     *  (transparent) text. Cleared only by its owner so the fade-out of an
     *  outgoing button never eats the incoming button's label. */
    private fun updateOttCaption(view: View) {
        val label = ottCaptionLabel ?: return
        val text = (view as? TextView)?.text?.takeIf { it.isNotEmpty() }
            ?: view.contentDescription
            ?: return
        ottCaptionOwner = view
        label.text = text
        label.animate().cancel()
        label.animate().alpha(1f).setDuration(120).start()
    }

    private fun clearOttCaption(view: View) {
        if (ottCaptionOwner !== view) return
        ottCaptionOwner = null
        ottCaptionLabel?.animate()?.cancel()
        ottCaptionLabel?.animate()?.alpha(0f)?.setDuration(120)?.start()
    }

    /** Re-push the caption after a runtime label write (Play->Pause, "1.5x")
     *  so a focused button's caption can't go stale. */
    private fun refreshOttCaptionFor(view: View?) {
        if (!ottSkinInstalled || view == null || !view.isFocused) return
        updateOttCaption(view)
    }

    private fun setupControls() {
        if (!isIptvMode && dockSkinSpec != null && !ottSkinInstalled) {
            installOttControlsSkin()
        }
        controlsOverlay = playerView.findViewById(R.id.debrify_controls_root)
        // Media3 owns the parent controller surface and can hide it on its own
        // timeout before our dock timer runs (for example while a dock button
        // retains focus). Reconcile that independent hide through the same
        // path as Back so the subtitle lift and the rest of our chrome state
        // cannot remain stranded on screen.
        playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                if (visibility != View.VISIBLE && controlsMenuVisible) {
                    hideControlsMenu()
                    // This callback fires from inside Media3's hide-animation end
                    // dispatch, where the restore animation kicked off by
                    // hideControlsMenu never lands — the subtitle view stays
                    // translated off-screen until the next lift call. Snap it
                    // back directly; a no-op when the animated restore worked.
                    subtitleControlsLift.restore(animate = false)
                }
            }
        )
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
        iptvStartOverButton = playerView.findViewById(R.id.iptv_start_over_button)
        iptvStartOverSeekButton =
            playerView.findViewById(R.id.iptv_start_over_seek_button)
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
        val classicAppleTvAnimation = { view: View? ->
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

        // Dock focus: the fills/rings/underlines/icon tints live in each
        // skin's StateListDrawable + ColorStateList; code adds only the
        // spec's scale/lift gesture (@ 120ms) and the shared caption.
        val dockFocusSpec = dockSkinSpec
        val dockFocusLiftPx = if (dockFocusSpec != null) {
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                dockFocusSpec.focusLiftDp,
                resources.displayMetrics,
            )
        } else 0f
        val ottFocusTreatment = { view: View? ->
            view?.onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
                val scale = dockFocusSpec?.focusScale ?: 1.08f
                if (hasFocus) {
                    v.animate()
                        .scaleX(scale)
                        .scaleY(scale)
                        .translationY(-dockFocusLiftPx)
                        .setDuration(120)
                        .setInterpolator(android.view.animation.DecelerateInterpolator())
                        .start()
                    updateOttCaption(v)
                    if (controlsMenuVisible) {
                        scheduleHideControlsMenu()
                    }
                } else {
                    v.animate()
                        .scaleX(1.0f)
                        .scaleY(1.0f)
                        .translationY(0f)
                        .setDuration(120)
                        .setInterpolator(android.view.animation.AccelerateInterpolator())
                        .start()
                    clearOttCaption(v)
                }
            }
        }
        val applyAppleTvAnimation =
            if (ottSkinInstalled) ottFocusTreatment else classicAppleTvAnimation

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
        applyAppleTvAnimation(iptvStartOverButton)
        applyAppleTvAnimation(iptvStartOverSeekButton)

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

        iptvStartOverButton?.setOnClickListener {
            hideControlsMenu()
            iptvStartOverController.toggleIptvStartOver()
        }
        iptvStartOverButton?.onFocusChangeListener = extendTimerOnFocus

        iptvStartOverSeekButton?.setOnClickListener {
            iptvStartOverController.showIptvStartOverTimeline()
        }
        iptvStartOverSeekButton?.onFocusChangeListener = extendTimerOnFocus

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
                subtitleController.showSubtitleSettingsPanel()
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

        if (ottSkinInstalled) {
            // Every assignment above just overwrote the focus animation with
            // extendTimerOnFocus (a view holds ONE focus listener; last set
            // wins — which is also why the classic scale never fires today).
            // The OTT treatment includes the timer-extend behaviour, so
            // re-applying it LAST gives the dock its scale + caption.
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
            applyAppleTvAnimation(iptvStartOverButton)
            applyAppleTvAnimation(iptvRecordButton)
            applyAppleTvAnimation(ottSourcesButton)
            applyAppleTvAnimation(playerView.findViewById(R.id.ott_seek_back_button))
            applyAppleTvAnimation(playerView.findViewById(R.id.ott_seek_forward_button))
        }
    }

    // [suppressTrakt]: a source switch resumes the captured live position and
    // must not let the per-episode tracker percent override it. The parameter
    // retains its legacy name because the payload field does too.
    private fun playItem(
        index: Int,
        suppressTrakt: Boolean = false,
        suppressResume: Boolean = false,
        shuffleAttempt: ShufflePlaybackAttempt? = null,
    ) {
        if (shuffleAttempt != null && !shuffleAttemptCurrent(shuffleAttempt)) return
        val outgoingIndex = currentIndex
        if (shuffleAttempt != null && shuffleAttempt.restorePreparation == null) {
            shuffleAttempt.restorePreparation = {
                currentIndex = outgoingIndex
                payload?.items?.getOrNull(outgoingIndex)?.let {
                    activeVodHeaders = buildProtectedMediaOrigins(listOf(it)) to it.httpHeaders
                }
                updateCatalogEpisodeControls()
            }
        }
        pendingShufflePlayback = null
        mediaPreparationGeneration++
        if (shuffleAttempt != null) {
            shuffleAttempt.navigation = mediaPreparationGeneration
            watchShufflePlayback(shuffleAttempt)
        }
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
        sourceSwitchController.dropStaleSourceSwitchFeedback()

        // Reset buffering state for new content
        hasEverBeenReady = false
        maxStableDurationMs = 0L
        lastRealPositionMs = 0L
        hideBufferingIndicator()
        upNextController.hideUpNextCard()
        skipSegmentController.resetSkipSegmentState()

        // Cancel any ongoing PikPak retry before starting new item
        cancelPikPakRetry()

        currentIndex = index
        updateCatalogEpisodeControls()
        val item = model.items[index]
        activeVodHeaders = buildProtectedMediaOrigins(listOf(item)) to item.httpHeaders
        android.util.Log.d("AndroidTvPlayer", "playItem - item found: title=${item.title}, season=${item.season}, episode=${item.episode}, url=${item.url}, resumeId=${item.resumeId}")
        // Keep BOTH the local position and the remote tracker percent (the
        // payload field is the furthest of Trakt + Simkl + MDBList); STATE_READY resumes
        // the FURTHER of the two (never backward). Suppress every saved position
        // during auto-advance (binge starts the next episode fresh), and suppress
        // trackers during a source switch on the same content (which must honour
        // the captured live position).
        val autoAdvance = isAutoAdvancing
        isAutoAdvancing = false
        // A new item starts: any hold belongs to the outgoing one. (A
        // suppressed resume then simply never re-arms — pendingSeekMs stays 0.)
        releaseResumeHold()
        pendingSeekMs =
            if (autoAdvance || suppressResume) 0L else item.resumePositionMs
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
        val navigation = mediaPreparationGeneration
        val shuffleAttempt = pendingShufflePlayback
        setResolvingState(true)
        val startupGeneration = if (startupGateController.startupFailoverCursor?.committed == false) {
            startupGateController.startupFailoverGeneration
        } else {
            null
        }
        val manualSourceIndex = startupGateController.manualSourceSwitchIndex
        val manualResolutionToken = if (manualSourceIndex != null) {
            stremioResolutionToken
        } else {
            null
        }
        if (startupGeneration != null) {
            startupLog(
                "event=resolve route=initial_lazy generation=$startupGeneration " +
                    startupGateController.startupSourceFields(currentStremioSourceIndex),
            )
        }

        // Request stream from Flutter with async callback
        requestStreamFromFlutter(item, index) { url, provider ->
            if (navigation != mediaPreparationGeneration ||
                (shuffleAttempt != null && !shuffleAttemptCurrent(shuffleAttempt))) return@requestStreamFromFlutter
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - received url: $url")
            if (manualSourceIndex != null &&
                (startupGateController.manualSourceSwitchSnapshot == null ||
                    startupGateController.manualSourceSwitchIndex != manualSourceIndex ||
                    stremioResolutionToken != manualResolutionToken)
            ) {
                startupLog(
                    "event=resolve_result ok=false reason=stale_manual_token " +
                        "captured=$manualResolutionToken current=$stremioResolutionToken " +
                        startupGateController.startupSourceFields(manualSourceIndex),
                )
                return@requestStreamFromFlutter
            }
            if (!isCurrentStartupGeneration(
                    captured = startupGeneration,
                    current = startupGateController.startupFailoverGeneration,
                )
            ) {
                startupLog(
                    "event=resolve_result ok=false reason=stale_generation " +
                        "captured=$startupGeneration current=${startupGateController.startupFailoverGeneration} " +
                        startupGateController.startupSourceFields(currentStremioSourceIndex),
                )
                android.util.Log.d(
                    "AndroidTvPlayer",
                    "resolveAndPlay - stale startup generation $startupGeneration " +
                        "(current: ${startupGateController.startupFailoverGeneration}), discarding",
                )
                return@requestStreamFromFlutter
            }
            setResolvingState(false)

            if (url.isNullOrEmpty()) {
                startupLog(
                    "event=resolve_result ok=false reason=empty_initial_resolution " +
                        startupGateController.startupSourceFields(currentStremioSourceIndex),
                    warning = true,
                )
                android.util.Log.e("AndroidTvPlayer", "resolveAndPlay - URL is null or empty!")
                if (failShufflePlayback()) return@requestStreamFromFlutter
                if (!startupGateController.failManualSourceCandidate("initial-resolve") &&
                    !startupGateController.failStartupResolution(currentStremioSourceIndex, "initial-resolve")
                ) {
                    Toast.makeText(this, "Unable to load stream", Toast.LENGTH_SHORT).show()
                }
                return@requestStreamFromFlutter
            }

            // Update the item with resolved URL and provider
            val updatedItem = item.copy(url = url, provider = provider ?: item.provider)
            payload?.items?.set(index, updatedItem)
            if (manualSourceIndex != null) startupGateController.manualSourceCandidateUrl = url
            startupLog(
                "event=resolve_result ok=true route=initial_lazy " +
                    startupGateController.startupSourceFields(currentStremioSourceIndex),
            )
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - starting playback with resolved URL, provider: $provider")
            startPlayback(payload!!.items[index])
        }
    }

    private fun discoverProtectedMime(url: String, headers: Map<String, String>, ready: (String?) -> Unit) {
        val shuffleAttempt = pendingShufflePlayback
        val generation = ++mediaPreparationGeneration
        shuffleAttempt?.navigation = generation
        val sourceToken = stremioResolutionToken
        mediaPreparationScope.launch {
            val mimeType = withContext(Dispatchers.IO) {
                ProtectedStreamHttp.discoverMimeType(protectedStreamClient, url, headers)
            }
            if (generation == mediaPreparationGeneration && sourceToken == stremioResolutionToken &&
                (shuffleAttempt == null || shuffleAttemptCurrent(shuffleAttempt)) &&
                !isFinishing && !isDestroyed && !sleepStopLatched) {
                ready(mimeType)
            }
        }
    }

    private fun startPlayback(item: PlaybackItem, mimeDiscovered: Boolean = false) {
        pendingShufflePlayback?.let {
            if (!shuffleAttemptCurrent(it)) {
                restoreShufflePreparation(it)
                pendingShufflePlayback = null
                return
            }
        }
        if (!isIptvMode && !mimeDiscovered && item.mimeType == null &&
            ProtectedStreamHttp.needsDiscovery(item.url, item.httpHeaders)) {
            discoverProtectedMime(item.url, item.httpHeaders) { mimeType ->
                val current = payload?.items?.getOrNull(currentIndex)
                if (current == null || current.url != item.url) return@discoverProtectedMime
                val prepared = current.copy(mimeType = mimeType)
                payload?.items?.set(currentIndex, prepared)
                startPlayback(prepared, mimeDiscovered = true)
            }
            return
        }
        activeVodHeaders = buildProtectedMediaOrigins(listOf(item)) to item.httpHeaders
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
        subtitleController.stopExternalSubtitleRendering()
        stremioSubtitles.clear()
        subtitleController.subtitleTracks.clear()   // rebuilt lazily for the new media's embedded tracks
        addonSubtitleResults.clear()
        addonFetchTokens.clear()
        failedSubtitleUrls.clear()
        subtitleSearchResults = emptyList()
        subtitleSearchStatus = ""
        pendingSeriesResult = null
        currentStremioSubtitleIndex = -1
        isLoadingStremioSubtitles = false
        subtitleAddonDiscoveryReady = false
        subtitleTrackReadiness.onMediaReplacement()
        trackSelector?.let { selector ->
            selector.parameters = selector.parameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(
                    C.TRACK_TYPE_TEXT,
                    playerPreferences.getString("player_default_subtitle_language", null) == "off" ||
                        playerPreferences.getBoolean("subtitle_only_foreign_audio", false) ||
                        playerPreferences.getBoolean("subtitle_forced_only", false),
                )
                .build()
        }
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
            .setMimeType(item.mimeType)
            .setMediaMetadata(metadata)
            .build()

        // High-res YouTube: video and audio are separate streams. Merge a
        // video-only track with its audio track. If anything goes wrong we fall
        // back to [item.url], a muxed stream that already contains audio, so we
        // never end up with silent video.
        val mergedSource = buildMergedSourceOrNull(item, mediaItem)

        player?.apply {
            pendingShufflePlayback?.mediaStarted = true
            if (mergedSource != null) {
                subtitleTrackReadiness.onMediaReplacement()
                setMediaSource(mergedSource)
            } else {
                subtitleTrackReadiness.onMediaReplacement()
                setMediaItem(mediaItem)
            }
            prepare()
            playWhenReady = true
            play()
        }

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
        if (model.imdbId?.startsWith("custom-series:") == true && manualSubtitleImdbId.isNullOrEmpty()) return

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
        if (subtitleController.subtitleSettingsVisible) {
            subtitleController.refreshSubtitlePanelForLoading()
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
        subtitleAddonDiscoveryReady = true
        addonSubtitleResults.clear()
        addons.forEach { addonSubtitleResults.add(AddonSubtitleResult(it, AddonSubtitleStatus.LOADING)) }
        isLoadingStremioSubtitles = addons.isNotEmpty()
        rebuildFlatStremioSubtitles()
        refreshSubtitleUiForLoading()

        addons.forEach { launchAddonSubtitleFetch(it, type, imdbId, item, contentToken) }
        tryAutoSelectAddonSubtitle()
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
        if (subtitleController.subtitleSettingsVisible) subtitleController.refreshSubtitlePanelForLoading()
    }

    /**
     * Clear Stremio subtitle loading state and refresh panel if visible.
     */
    private fun clearStremioLoadingState() {
        isLoadingStremioSubtitles = false
        subtitleAddonDiscoveryReady = true
        tryAutoSelectAddonSubtitle()
        if (subtitleController.subtitleSettingsVisible) {
            subtitleController.refreshSubtitlePanelForLoading()
        }
    }

    private fun playNext() {
        if (continuousShuffleEnabled) {
            if (playShowShuffle()) return
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
            if (isStremioTvMode && stremioTvGuideController.stremioTvChannels.any { it.isCurrent }) {
                stremioTvGuideController.requestStremioTvNext()
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
                if (hasPlaylistResolver) {
                    requestAdjacentEpisodeFetch(
                        model.imdbId,
                        currentItem.season,
                        currentItem.episode,
                    )
                } else if (model.imdbId != null) {
                    requestQuickPlayNextEpisode(model.imdbId!!, currentItem.season, currentItem.episode)
                    finish()
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
            if (hasAdjacentEpisodeResolver &&
                currentItem?.season != null && currentItem.episode != null) {
                requestAdjacentEpisodeFetch(
                    model.imdbId,
                    currentItem.season,
                    currentItem.episode,
                    direction = -1,
                )
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
                    (guideAdjacent(model, currentItem, -1) != null ||
                        (hasAdjacentEpisodeResolver &&
                            ((currentItem?.season ?: 0) > 1 ||
                                (currentItem?.episode ?: 0) > 1)))))
        iptvPrevButton?.visibility = if (hasPrevious) View.VISIBLE else View.GONE
    }

    private fun playRandom() {
        if (playShowShuffle()) return
        val model = payload ?: return
        if (model.items.isEmpty()) {
            Toast.makeText(this, "No items in playlist", Toast.LENGTH_SHORT).show()
            return
        }

        val randomIndex = pickShuffleIndex() ?: return
        isAutoAdvancing = false
        playItem(randomIndex, suppressResume = true)
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
                        resetShuffle()
                        playRandom()
                    }
                    1 -> {
                        if (continuousShuffleEnabled) {
                            continuousShuffleEnabled = false
                            resetShuffle()
                            Toast.makeText(this, "Continuous shuffle off", Toast.LENGTH_SHORT).show()
                        } else {
                            continuousShuffleEnabled = true
                            resetShuffle()
                            Toast.makeText(this, "Continuous shuffle on", Toast.LENGTH_SHORT).show()
                            playRandom()
                        }
                    }
                }
            }
            .show()
    }

    private fun resetShuffle() {
        pendingShufflePlayback?.let { restoreShufflePreparation(it) }
        pendingShufflePlayback = null
        shuffleBag.clear()
        showShuffle.clear()
        showShuffleGeneration++
        queuedShuffleGeneration = null
    }

    internal class ShufflePlaybackAttempt(
        var navigation: Int,
        val generation: Int,
        val autoAdvance: Boolean,
        val onUnavailable: () -> Unit,
        var mediaStarted: Boolean = false,
        var restorePreparation: (() -> Unit)? = null,
        var finished: Boolean = false,
    )
    private var pendingShufflePlayback: ShufflePlaybackAttempt? = null
    private var queuedShuffleGeneration: Int? = null
    private var queuedShuffleNavigation: Int? = null

    private fun shuffleAttemptCurrent(attempt: ShufflePlaybackAttempt): Boolean =
        !attempt.finished && shuffleAttemptOwned(attempt)

    private fun shuffleAttemptOwned(attempt: ShufflePlaybackAttempt): Boolean =
        !isFinishing && !isDestroyed && attempt.generation == showShuffleGeneration &&
            attempt.navigation == mediaPreparationGeneration &&
            (!attempt.autoAdvance || !sleepStopLatched)

    private fun restoreShufflePreparation(attempt: ShufflePlaybackAttempt) {
        if (!attempt.mediaStarted && attempt.navigation == mediaPreparationGeneration) {
            attempt.restorePreparation?.invoke()
        }
    }

    private fun failShufflePlayback(): Boolean {
        val attempt = pendingShufflePlayback ?: return false
        pendingShufflePlayback = null
        restoreShufflePreparation(attempt)
        val current = shuffleAttemptCurrent(attempt)
        attempt.finished = true
        if (current) {
            progressHandler.post { if (shuffleAttemptOwned(attempt)) attempt.onUnavailable() }
        }
        return true
    }

    private var shuffleWatchGeneration = 0

    private fun watchShufflePlayback(attempt: ShufflePlaybackAttempt) {
        val watchGeneration = ++shuffleWatchGeneration
        pendingShufflePlayback = attempt
        progressHandler.postDelayed({
            if (pendingShufflePlayback === attempt && watchGeneration == shuffleWatchGeneration) {
                if (attempt.mediaStarted && startupGateController.currentPlaybackItemIsPikPak() && isPikPakRetrying &&
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
    private fun yieldEpisodeFetchToQueuedShuffle(): Boolean =
        queuedShuffleGeneration == showShuffleGeneration &&
            queuedShuffleNavigation == mediaPreparationGeneration &&
            !isFinishing && !isDestroyed

    private fun canShuffleWholeShow(): Boolean {
        val model = payload ?: return false
        return hasPlaylistResolver && !isIptvMode && !isStremioTvMode &&
            model.contentType.equals("series", ignoreCase = true) &&
            (customShuffleEpisodes != null || model.guideEpisodes.isNotEmpty())
    }

    /** Resolve outside the pack only when catalog playback supplies a resolver. */
    private fun playShowShuffle(
        attempted: Set<ShuffleEpisode> = emptySet(),
        autoAdvance: Boolean = false,
    ): Boolean {
        if (!canShuffleWholeShow()) return false
        if (episodeFetchInFlight) {
            if (autoAdvance || queuedShuffleGeneration == showShuffleGeneration) return true
            val generation = showShuffleGeneration
            queuedShuffleGeneration = generation
            val navigation = mediaPreparationGeneration
            queuedShuffleNavigation = navigation
            fun retryWhenIdle() {
                if (generation != showShuffleGeneration || navigation != mediaPreparationGeneration ||
                    isFinishing || isDestroyed) {
                    clearQueuedShuffle(generation)
                    return
                }
                if (episodeFetchInFlight) progressHandler.postDelayed({ retryWhenIdle() }, 50)
                else {
                    clearQueuedShuffle(generation)
                    playShowShuffle(attempted, autoAdvance)
                }
            }
            progressHandler.postDelayed({ retryWhenIdle() }, 50)
            return true
        }
        val model = payload ?: return false
        val current = model.items.getOrNull(currentIndex)?.let { item ->
            val season = item.season
            val episode = item.episode
            if (season != null && episode != null) ShuffleEpisode(season, episode) else null
        }
        val eligible = customShuffleEpisodes ?: model.guideEpisodes.filter {
            it.season > 0 && it.episode > 0 && it.shuffleEligible
        }.map { ShuffleEpisode(it.season, it.episode) }
        val target = if (attempted.size < 3) showShuffle.pick(eligible, current, attempted) else null
        if (target == null) {
            showStatusPillTransient("No other playable episode found for shuffle")
            return true
        }
        upNextController.hideUpNextCard()
        val generation = showShuffleGeneration
        fun fetchTarget() {
            val fetchAttempt = ShufflePlaybackAttempt(mediaPreparationGeneration, generation, autoAdvance,
                onUnavailable = { playShowShuffle(attempted + target, autoAdvance) })
            if (!shuffleAttemptCurrent(fetchAttempt)) return
            requestEpisodeFetch(target.season, target.episode, autoAdvance = autoAdvance,
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
        val attempt = ShufflePlaybackAttempt(mediaPreparationGeneration, generation, autoAdvance,
            onUnavailable = { fetchTarget() })
        fun openPrepared(item: PlaybackItem) {
            if (!shuffleAttemptCurrent(attempt)) return
            model.items[index] = item
            isAutoAdvancing = autoAdvance
            playItem(index, suppressResume = true, shuffleAttempt = attempt)
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

    private fun guideTitleFor(item: PlaybackItem): String? {
        if (item.season == null || item.episode == null) return null
        return payload?.guideEpisodes?.firstOrNull {
            it.season == item.season && it.episode == item.episode
        }?.title?.takeIf { it.isNotBlank() }
    }

    private fun updateTitle(item: PlaybackItem) {
        // Prefer the episode label / show title when the item title is blank, so
        // a series episode never renders as just the red badge with no text (the
        // "red line" bug). If everything is blank (rare non-series case) the
        // showControlsMenu guard keeps the header hidden rather than showing empty.
        val model = payload
        val fallbackTitle = item.seasonEpisodeLabel().ifEmpty { model?.title.orEmpty() }
        val displayTitle = guideTitleFor(item) ?: item.title
        titleView.text = displayTitle.ifBlank { fallbackTitle }

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
            ottEpisodeTitle.text = displayTitle.ifBlank {
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
        if (ottSkinInstalled) updateOttIdentity()
    }

    /** The OTT dock's in-dock identity row, mirroring the legacy OTT title
     *  mode: for series the FETCHED episode title (updateTitle keeps
     *  item.title current from the TVMaze/metadata updates, with the same
     *  "Episode N" fallback) with the S/E badge beneath — the raw payload
     *  title is never shown, because on torrent launches it's the release
     *  filename the legacy header deliberately hid. */
    private fun updateOttIdentity() {
        val title = ottIdentityTitle ?: return
        val model = payload
        val item = model?.items?.getOrNull(currentIndex)
        val isSeries = model?.contentType?.lowercase(java.util.Locale.US) == "series"
        val overline = ottIdentityOverline
        val badge = ottIdentityBadge
        if (isSeries && item != null && item.season != null && item.episode != null) {
            val episodeTitle = guideTitleFor(item)
                ?: item.title.ifBlank { "Episode ${item.episode}" }
            // The FETCHED show/episode names only (TVMaze via the metadata
            // pushes); never the payload title, which on torrent launches is
            // the release filename the legacy header deliberately hid. Each
            // skin arranges the same facts its own way.
            val show = ottShowName
            val seasonStr = item.season.toString().padStart(2, '0')
            val episodeStr = item.episode.toString().padStart(2, '0')
            when (controlsSkin) {
                TvControlsSkin.FROST -> {
                    // Eyebrow above a big episode title (subtitle view is the
                    // eyebrow in this layout, uppercased by XML).
                    title.text = episodeTitle
                    ottIdentitySubtitle?.text = if (show.isNullOrBlank()) {
                        "Season ${item.season} · Episode ${item.episode}"
                    } else {
                        "$show · Season ${item.season}"
                    }
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.MARQUEE -> {
                    // Italic show over a serif title, season/episode spelled
                    // out in words underneath.
                    title.text = episodeTitle
                    if (show.isNullOrBlank()) {
                        overline?.visibility = View.GONE
                    } else {
                        overline?.text = show
                        overline?.visibility = View.VISIBLE
                    }
                    ottIdentitySubtitle?.text =
                        "Season ${spellNumber(item.season)} · Episode ${spellNumber(item.episode)}"
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.BROADCAST -> {
                    // Channel-ident: show name leads in condensed caps.
                    if (show.isNullOrBlank()) {
                        title.text = episodeTitle
                        ottIdentitySubtitle?.text = "S$seasonStr · E$episodeStr"
                    } else {
                        title.text = show
                        ottIdentitySubtitle?.text = "E${item.episode} — $episodeTitle"
                    }
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.PULSE -> {
                    // Episode leads; the show name is accent-tinted inside
                    // the subtitle.
                    title.text = episodeTitle
                    val tail = "Season ${item.season}, Episode ${item.episode}"
                    ottIdentitySubtitle?.text = if (show.isNullOrBlank()) {
                        SpannableString(tail)
                    } else {
                        SpannableString("$show · $tail").apply {
                            setSpan(
                                ForegroundColorSpan(0xFF9BA5FB.toInt()),
                                0, show.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                            )
                            setSpan(
                                StyleSpan(Typeface.BOLD),
                                0, show.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                            )
                        }
                    }
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.TICKET -> {
                    // Gold S·E chip · rule · show overline / episode title.
                    title.text = episodeTitle
                    badge?.text = "S${item.season} · E${item.episode}"
                    badge?.visibility = View.VISIBLE
                    ottIdentityDivider?.visibility = View.VISIBLE
                    if (show.isNullOrBlank()) {
                        overline?.visibility = View.GONE
                    } else {
                        overline?.text = show
                        overline?.visibility = View.VISIBLE
                    }
                }
                else -> {
                    // OTT: "Show — Episode" with the S·E badge beneath.
                    title.text = if (show.isNullOrBlank()) {
                        episodeTitle
                    } else {
                        "$show — $episodeTitle"
                    }
                    ottIdentitySubtitle?.text = "S$seasonStr · E$episodeStr"
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
            }
        } else {
            title.text = titleView.text
            ottIdentitySubtitle?.visibility = View.GONE
            overline?.visibility = View.GONE
            badge?.visibility = View.GONE
            ottIdentityDivider?.visibility = View.GONE
        }
        updateOttExtras(item)
    }

    /**
     * Quality chips + rating for the premium dock skins. Quality is parsed
     * from the item's ORIGINAL payload title (the release name — metadata
     * pushes overwrite item.title with the fetched episode name, so
     * [PlaybackItem.sourceTitle] carries the parseable one), falling back to
     * the stream URL's filename. Rating is [PlaybackItem.rating] — already
     * pushed with the TVMaze metadata — so no extra network. Runs AFTER the
     * per-skin identity arms; on TICKET it also owns the overline so the
     * quality can ride it ("FOUNDATION · 4K · DOLBY VISION").
     */
    private fun updateOttExtras(item: PlaybackItem?) {
        val hasAnyView = ottQualityChips.any { it != null } ||
            ottRatingChip != null || ottMetaLine != null
        if (!hasAnyView) return

        val tags = if (item != null) dockTagsFor(item) else emptyList()
        val rating = item?.rating?.takeIf { it > 0 }
        val ratingText = rating?.let { String.format(java.util.Locale.US, "%.1f", it) }

        ottQualityChips.forEachIndexed { i, chip ->
            if (chip == null) return@forEachIndexed
            val tag = tags.getOrNull(i)
            if (tag != null) {
                chip.text = tag.short
                chip.visibility = View.VISIBLE
            } else {
                chip.visibility = View.GONE
            }
        }

        ottRatingChip?.let { rc ->
            if (ratingText == null) {
                rc.visibility = View.GONE
            } else {
                val starColor = when (controlsSkin) {
                    TvControlsSkin.PULSE -> 0xFF818CF8.toInt()
                    TvControlsSkin.FROST -> 0xFFF5C518.toInt()
                    else -> null
                }
                if (starColor != null) {
                    rc.text = SpannableString("★ $ratingText").apply {
                        setSpan(
                            ForegroundColorSpan(starColor),
                            0, 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    }
                } else {
                    rc.text = "★ $ratingText"
                }
                rc.visibility = View.VISIBLE
            }
        }

        // MARQUEE: one serif print line — "4K · DOLBY VISION · ATMOS — ★ 8.6".
        // Uppercased HERE, not via android:textAllCaps — the AllCaps
        // transform re-renders the text as a plain string and drops the
        // rating's gold span.
        ottMetaLine?.let { ml ->
            val quality = tags.joinToString(" · ") {
                it.long.uppercase(java.util.Locale.US)
            }
            val text = when {
                quality.isEmpty() && ratingText == null -> null
                quality.isEmpty() -> "★ $ratingText"
                ratingText == null -> quality
                else -> "$quality — ★ $ratingText"
            }
            if (text == null) {
                ml.visibility = View.GONE
            } else {
                ml.text = if (ratingText != null) {
                    SpannableString(text).apply {
                        setSpan(
                            ForegroundColorSpan(0xFFEAC981.toInt()),
                            text.length - ratingText.length - 2, text.length,
                            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    }
                } else {
                    text
                }
                ml.visibility = View.VISIBLE
            }
        }

        // TICKET: the quality rides the gold overline after the show name —
        // resolution short + HDR long only, per the mock. Movies (no show)
        // get the quality alone, so the overline earns its keep either way.
        if (controlsSkin == TvControlsSkin.TICKET) {
            val overline = ottIdentityOverline
            if (overline != null) {
                val parts = mutableListOf<String>()
                ottShowName?.takeIf { it.isNotBlank() }?.let { parts.add(it) }
                tags.firstOrNull()?.let { parts.add(it.short) }
                tags.getOrNull(1)?.let { parts.add(it.long) }
                if (parts.isEmpty()) {
                    overline.visibility = View.GONE
                } else {
                    overline.text = parts.joinToString(" · ")
                    overline.visibility = View.VISIBLE
                }
            }
        }
    }

    /** Tags for the current item, cached — the regexes only rerun when the
     *  underlying release name changes (zap / source switch). */
    private fun dockTagsFor(item: PlaybackItem): List<DockFormatTags.Tag> {
        val name = item.sourceTitle?.takeIf { it.isNotBlank() } ?: item.title
        val fromName = if (name == dockTagsCacheKey) {
            dockTagsCache
        } else {
            DockFormatTags.detect(name).also {
                dockTagsCacheKey = name
                dockTagsCache = it
            }
        }
        if (fromName.isNotEmpty()) return fromName
        // Fallback: the stream URL usually ends in the real filename
        // (debrid links keep it) even when the payload title was cleaned.
        val urlName = item.url.substringAfterLast('/').substringBefore('?')
        if (urlName.isBlank() || urlName == name) return fromName
        val decoded = try {
            java.net.URLDecoder.decode(urlName, "UTF-8")
        } catch (_: Exception) {
            urlName
        }
        return DockFormatTags.detect(decoded)
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

    private fun reportValidatedSourceCommit(sourceIndex: Int) {
        if (sourceIndex !in stremioSources.indices) return
        try {
            MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "commitStremioSource",
                mapOf(
                    "sourceIndex" to sourceIndex,
                    "sourcePersistenceSessionId" to sourcePersistenceSessionId,
                ),
            )
        } catch (e: Exception) {
            android.util.Log.w(
                "AndroidTvPlayer",
                "Failed to report committed source $sourceIndex: ${e.message}",
            )
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
        subtitleController.stopExternalSubtitleRendering()

        stremioSubtitles.clear()
        currentStremioSubtitleIndex = -1
        userManuallySelectedSubtitle = false
        isLoadingStremioSubtitles = true

        trackSelector?.let { selector ->
            selector.parameters = selector.parameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
        }

        if (subtitleController.subtitleSettingsVisible) {
            subtitleController.refreshSubtitlePanelForLoading()
        }

        val subtitleItem = if (type == "series") {
            currentItem.copy(season = season, episode = episode)
        } else {
            currentItem.copy(season = null, episode = null)
        }

        Toast.makeText(this, "Searching subtitles for ${result.name}", Toast.LENGTH_SHORT).show()
        fetchStremioSubtitlesWithImdb(result.imdbId, type, subtitleItem)
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
            pendingShufflePlayback?.mediaStarted = true
            subtitleTrackReadiness.onMediaReplacement()
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
                startupGateController.cancelPikPakGateReprepare()

                // Clear state synchronously
                isPikPakRetrying = false
                pikPakRetryCount = 0
                hidePikPakRetryOverlay()

                // A validation gate deferred its error/timeout handling to
                // this engine — exhaustion is the engine's verdict, so hand
                // the failure back to the gate (manual pick restores the
                // previous source; startup advances the failover cursor)
                // instead of skipping to the next playlist item.
                if (failShufflePlayback()) return@waitForPikPakMetadata
                if (startupGateController.failManualSourceCandidate("pikpak-exhausted")) {
                    return@waitForPikPakMetadata
                }
                if (startupGateController.startupFailoverCursor?.committed == false) {
                    startupGateController.failStartupCandidate("pikpak-exhausted")
                    return@waitForPikPakMetadata
                }

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
                    startupGateController.cancelPikPakGateReprepare()

                    // CRITICAL FIX: Clear retry state IMMEDIATELY when video loads
                    // This prevents race conditions and ensures UI updates instantly
                    isPikPakRetrying = false
                    pikPakRetryCount = 0
                    hidePikPakRetryOverlay()

                    // Clean up handler callbacks
                    checkHandler.removeCallbacks(this)

                    // Ensure subtitles are selected after successful load
                    tryAutoSelectAddonSubtitle()

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

                // Stremio TV has no VOD startup gate. A cold-storage error
                // still needs a new request; polling an IDLE player alone
                // cannot make the file ready. Keep the retry engine's bound.
                if (isStremioTvMode && currentPlayer?.playerError != null) {
                    startupGateController.schedulePikPakGateReprepare(retryId)
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
            // During startup validation the opaque gate covers this overlay —
            // mirror the message so the user isn't stuck on "Checking stream…"
            // for the whole cold-storage warmup.
            if (::startupGateStatus.isInitialized &&
                startupGateController.startupFailoverCursor?.committed == false
            ) {
                startupGateStatus.text = message
            }
            pikPakReactivationText.text = message
            pikPakReactivationIndicator.animate().cancel()
            pikPakReactivationIndicator.visibility = View.VISIBLE
            pikPakReactivationIndicator.animate().alpha(1f).setDuration(250).start()
        }
    }

    private fun hidePikPakRetryOverlay() {
        runOnUiThread {
            if (isFinishing || isDestroyed || !::pikPakReactivationIndicator.isInitialized) return@runOnUiThread
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
        startupGateController.cancelPikPakGateReprepare()

        // Remove any pending retry callbacks
        pikPakRetryHandler.removeCallbacksAndMessages(null)

        // Hide overlay
        hidePikPakRetryOverlay()
    }

    /** Apply source priority once tracks and any higher-priority addons are ready. */
    private fun tryAutoSelectAddonSubtitle() {
        val currentPlayer = player ?: return
        val defaultSubtitleLang = playerPreferences.getString("player_default_subtitle_language", null)
        val targetLanguage = defaultSubtitleLang ?: "en"
        val tracks = currentPlayer.currentTracks
        val positions = mutableListOf<Pair<Tracks.Group, Int>>()
        val candidates = mutableListOf<EmbeddedSubtitleCandidate>()
        for (group in tracks.groups) {
            // A manual subtitle identity search explicitly asks for addon results.
            if (!manualSubtitleImdbId.isNullOrEmpty()) break
            if (group.type != C.TRACK_TYPE_TEXT) continue
            for (i in 0 until group.length) {
                val format = group.getTrackFormat(i)
                positions.add(group to i)
                candidates.add(EmbeddedSubtitleCandidate(
                    supported = group.isTrackSupported(i),
                    selected = group.isTrackSelected(i),
                    matchesLanguage = LanguageMapper.matchesLanguage(targetLanguage, format.language) ||
                        (!playerPreferences.getBoolean("subtitle_forced_only", false) &&
                            (LanguageMapper.matchesLanguage(targetLanguage, format.label) ||
                                LanguageMapper.matchesLanguage(targetLanguage, format.id))),
                    defaultTrack = format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0,
                    forcedTrack = format.selectionFlags and C.SELECTION_FLAG_FORCED != 0,
                    undeclaredHlsCaption = isUndeclaredHlsCaption(
                        isHls = currentPlayer.currentManifest is HlsManifest,
                        mimeType = format.sampleMimeType,
                        accessibilityChannel = format.accessibilityChannel,
                        language = format.language,
                    ),
                ))
            }
        }
        when (val choice = chooseAutomaticSubtitle(
            tracksReady = subtitleTrackReadiness.canSelect(currentPlayer.playbackState == Player.STATE_READY),
            preference = defaultSubtitleLang,
            manualSelection = userManuallySelectedSubtitle,
            suppressed = suppressSubtitleAutoSelect,
            addonSelected = currentStremioSubtitleIndex >= 0,
            audioAllowsSubtitles = audioAllowsAutomaticSubtitles(
                onlyForeignAudio = playerPreferences.getBoolean("subtitle_only_foreign_audio", false),
                preferredAudio = playerPreferences.getString("player_default_audio_language", null),
                selectedAudio = selectedAudioLanguage(tracks),
            ),
            forcedOnly = playerPreferences.getBoolean("subtitle_forced_only", false),
            candidates = candidates,
            sourcePriority = SubtitleSettings.getSubtitleSourcePriority(this),
            addonDiscoveryReady = subtitleAddonDiscoveryReady,
            addons = addonSubtitleResults.map { slot ->
                val eligible = slot.subtitles.indices.filter { slot.subtitles[it].url !in failedSubtitleUrls }
                val matching = eligible.filter {
                    val subtitle = slot.subtitles[it]
                    LanguageMapper.matchesLanguage(targetLanguage, subtitle.lang) ||
                        (targetLanguage.equals("pt-BR", ignoreCase = true) &&
                            LanguageMapper.matchesLanguage(targetLanguage, subtitle.label))
                }
                AddonSubtitleCandidate(
                    addonId = slot.addon.priorityId,
                    loading = slot.status == AddonSubtitleStatus.LOADING,
                    matchingIndices = matching + if (defaultSubtitleLang == null) eligible.filter { it !in matching } else emptyList(),
                )
            },
        )) {
            SubtitleAutoSelection.Off -> {
                if (currentStremioSubtitleIndex >= 0 || subtitleController.externalSubtitleActive) {
                    subtitleController.stopExternalSubtitleRendering() // invalidates in-flight addon downloads
                    currentStremioSubtitleIndex = -1
                }
                trackSelector?.let { selector ->
                    if (!selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)) {
                        selector.parameters = selector.parameters.buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                            .build()
                    }
                }
                return
            }
            SubtitleAutoSelection.Wait, SubtitleAutoSelection.Keep -> return
            is SubtitleAutoSelection.Embedded -> {
                val (group, index) = positions[choice.index]
                if (!group.isTrackSelected(index)) {
                    trackSelector?.let { selector ->
                        selector.parameters = selector.parameters.buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, listOf(index)))
                            .build()
                    }
                }
                return
            }
            is SubtitleAutoSelection.AddonTrack -> {
                val sub = addonSubtitleResults.firstOrNull { it.addon.priorityId == choice.addonId }
                    ?.subtitles?.getOrNull(choice.index) ?: return
                currentStremioSubtitleIndex = stremioSubtitles.indexOfFirst { it.url == sub.url }
                subtitleController.loadStremioSubtitle(sub)
            }
            SubtitleAutoSelection.Addon -> return
        }

    }

    // D-pad navigation
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (::startupGateView.isInitialized && startupGateView.visibility == View.VISIBLE &&
            keyCode in listOf(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER)) {
            return super.dispatchKeyEvent(event)
        }

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
        if (stremioTvGuideController.stremioTvGuideVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_BACK -> {
                        stremioTvGuideController.hideStremioTvGuide()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        if (stremioTvGuideController.isFocusInStremioTvGuideList()) {
                            return true
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        if (stremioTvGuideController.isFocusInStremioTvGuideList() && event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                            stremioTvGuideController.stremioTvGuideSearch?.requestFocus()
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
        if (upNextController.upNextVisible) {
            when (keyCode) {
                KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                    if (event.action == KeyEvent.ACTION_DOWN) upNextController.triggerUpNext()
                    return true
                }
                KeyEvent.KEYCODE_BACK -> {
                    if (event.action == KeyEvent.ACTION_DOWN) upNextController.dismissUpNext()
                    return true
                }
                else -> {
                    if (event.action == KeyEvent.ACTION_DOWN) upNextController.hideUpNextCard()
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
            if (isStremioTvMode && stremioTvGuideController.stremioTvChannels.isNotEmpty()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    stremioTvGuideController.showStremioTvGuide()
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

        // The previous menu may have disappeared via Media3's parent-controller
        // timeout rather than our child dock animation.
        playerView.showController()

        // The channel panel and the dock share the bottom strip, so they merge
        // into one surface: the panel rides flush on top of the dock for as
        // long as it is open. Non-live playback has no panel to merge.
        val liveEntry = iptvChannels.getOrNull(currentIptvIndex)?.takeIf { it.isLive }
        if (liveEntry != null) {
            iptvZapBannerController.showIptvZapBanner(liveEntry, docked = true)
        } else {
            iptvZapBannerController.hideIptvZapBanner()
        }

        // The title and controls are one presentation state: metadata updates
        // may change the text, but only this method is allowed to reveal it.
        titleContainer.animate().cancel()

        // Switch to OTT mode if we have series metadata, otherwise keep simple mode
        val model = payload
        val currentItem = model?.items?.getOrNull(currentIndex)
        val hasSeriesMetadata = model?.contentType?.lowercase(java.util.Locale.US) == "series" &&
                               currentItem?.season != null && currentItem.episode != null

        if (ottSkinInstalled) {
            // The OTT dock carries its own identity row, mirroring the Flutter
            // dock — the top-of-screen title stays hidden entirely.
            titleContainer.visibility = View.GONE
            updateOttIdentity()
        } else {
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
        }

        // The source badge shares the top-right safe area with startup
        // validation. Keep the progress pill unobscured until the candidate is
        // committed; if controls remain open, commitStartupCandidate restores
        // the badge as soon as the gate drops.
        if (::startupGateView.isInitialized &&
            startupGateView.visibility == View.VISIBLE
        ) {
            sourceSwitchController.hideStremioSourceBadgeImmediately()
        } else {
            sourceSwitchController.showStremioSourceBadge()
        }

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
        updateSubtitleControlsLift()
    }

    private fun hideControlsMenu() {
        val overlay = controlsOverlay ?: return

        // The merged panel leaves with the dock it was riding on. A floating
        // banner (raised by a zap) is left alone to finish its own timeout.
        if (iptvZapBannerController.iptvZapBannerDocked) iptvZapBannerController.hideIptvZapBanner()

        overlay.animate().cancel()

        if (!controlsMenuVisible) {
            overlay.visibility = View.GONE
            overlay.alpha = 0f
            overlay.translationY = 0f
            hideTitleImmediately()
            sourceSwitchController.hideStremioSourceBadge()
            cancelScheduledHideControlsMenu()
            return
        }

        cancelScheduledHideControlsMenu()
        controlsMenuVisible = false
        subtitleControlsLift.restore()

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
        sourceSwitchController.hideStremioSourceBadge()

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
                }
            }
            .start()
    }

    /** Re-measure after layout because each controls skin occupies a different height. */
    private fun updateSubtitleControlsLift() {
        if (!controlsMenuVisible) return
        val dock = controlsOverlay ?: return
        val extraPanelHeight = iptvZapBannerController.iptvZapBanner
            ?.takeIf { iptvZapBannerController.iptvZapBannerDocked && it.visibility == View.VISIBLE }
            ?.height ?: 0
        subtitleControlsLift.liftAbove(dock.height + extraPanelHeight)
        dock.post {
            if (!controlsMenuVisible) return@post
            val laidOutExtra = iptvZapBannerController.iptvZapBanner
                ?.takeIf { iptvZapBannerController.iptvZapBannerDocked && it.visibility == View.VISIBLE }
                ?.height ?: 0
            subtitleControlsLift.liftAbove(dock.height + laidOutExtra)
        }
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
        // Each dock skin swaps within its own icon family; classic keeps the
        // legacy pair.
        val spec = dockSkinSpec.takeIf { ottSkinInstalled }
        val iconRes = if (playing) {
            spec?.pauseIconRes ?: R.drawable.ic_pause
        } else {
            spec?.playIconRes ?: R.drawable.ic_play
        }
        button.setCompoundDrawablesRelativeWithIntrinsicBounds(iconRes, 0, 0, 0)
        refreshOttCaptionFor(button)
    }

    private fun updateAspectButtonLabel() {
        aspectButton?.text = resizeModeLabels[resizeModeIndex]
        refreshOttCaptionFor(aspectButton)
    }

    private fun updateNightModeButtonLabel() {
        nightModeButton?.text = nightModeLabels[nightModeIndex]
        refreshOttCaptionFor(nightModeButton)
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
            skipSegmentController.updateSkipSegmentState(currentPosition, duration)

            // Update Cinema Mode split time displays
            debrifyTimeCurrent?.text = formatTime(currentPosition)
            debrifyTimeTotal?.text = if (ottSkinInstalled) {
                "-" + formatTime((duration - currentPosition).coerceAtLeast(0))
            } else {
                formatTime(duration)
            }

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
            if (ottSkinInstalled) {
                // The badge is permanently hidden under OTT (its requestFocus
                // would no-op and strand focus); the dock's Sources button is
                // already in normal traversal, so just fall back to Play.
                pauseButton?.requestFocus()
            } else if (stremioSources.isNotEmpty()) {
                stremioSourceBadge?.requestFocus()
            } else {
                pauseButton?.requestFocus()
            }
            return
        }

        // Preserve the user's playback intent. `isPlaying` can briefly be
        // false while buffering even though playWhenReady is true, so retain
        // the latter and only resume if seeking actually interrupted playback.
        cinemaSeekWasPlaying = player?.playWhenReady == true
        if (cinemaSeekWasPlaying) {
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

        if (ottSkinInstalled) {
            // OTT keeps the dock's own palette (white70 times) and swells the
            // bar 3->6dp instead of recoloring; the preview chip appears with
            // the first step via updateCinemaProgressUI.
            setOttTrackHeight(focused = true)
        } else {
            // Highlight current time with Netflix red
            debrifyTimeCurrent?.setTextColor(Color.parseColor("#E50914"))
        }

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

        if (ottSkinInstalled) {
            setOttTrackHeight(focused = false)
            ottScrubPreviewChip?.visibility = View.GONE
        } else {
            // Fade current time color back to white
            debrifyTimeCurrent?.setTextColor(Color.WHITE)
        }

        val shouldResume = cinemaSeekWasPlaying
        cinemaSeekWasPlaying = false
        if (shouldResume) player?.play()
    }

    private fun confirmCinemaSeek() {
        if (!cinemaSeekMode || player == null) return
        releaseResumeHold()  // viewer owns the position now
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
        debrifyTimeTotal?.text = if (ottSkinInstalled) {
            // The OTT bar mirrors the Flutter dock: remaining, not total.
            "-" + formatTime((videoDuration - seekbarPosition).coerceAtLeast(0))
        } else {
            formatTime(videoDuration)
        }

        if (ottSkinInstalled && cinemaSeekMode) {
            // Cinema-scrub preview chip: "H:MM:SS   ·   ±delta" against the
            // real (paused) playhead, U+2212 for the minus like the Flutter
            // chip — tv_controls.dart:718-741. Focusing the bar enters
            // cinemaSeekMode before any step, so the chip waits for a real
            // delta; once up, a scrub back through ±0:00 keeps it.
            val origin = player?.currentPosition ?: seekbarPosition
            val delta = seekbarPosition - origin
            if (delta != 0L || ottScrubPreviewChip?.visibility == View.VISIBLE) {
                val sign = if (delta < 0) "−" else "+"
                ottScrubPreviewText?.text =
                    "${formatTime(seekbarPosition)}   ·   $sign${formatTime(kotlin.math.abs(delta))}"
                ottScrubPreviewChip?.visibility = View.VISIBLE
            }
        }

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
        releaseResumeHold()  // viewer owns the position now
        player?.seekTo(seekbarPosition)
        hideSeekbar()
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
        releaseResumeHold()  // viewer owns the position now
        p.seekTo(target)

        // Show visual feedback for quick seek
        val seekSeconds = kotlin.math.abs(offsetMs / 1000).toString() + "s"
        if (offsetMs > 0) {
            seekFeedbackManager.showSeekForward(seekSeconds)
        } else {
            seekFeedbackManager.showSeekBackward(seekSeconds)
        }
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

    // Playlist
    private fun showPlaylist() {
        android.util.Log.d("PlaylistNav", "showPlaylist: Starting - playlistMode=$playlistMode")

        if (playlistMode == PlaylistMode.NONE || playlistAdapter == null) {
            android.util.Log.d("PlaylistNav", "showPlaylist: Exiting early - no playlist adapter")
            return
        }

        playlistVisible = true
        playlistOverlay.visibility = View.VISIBLE
        seedGuideSkinChrome()

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
        gdPop?.visibility = View.GONE
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
        if (iptvGuideVisible || stremioTvGuideController.stremioTvGuideVisible) return false
        if (subtitlePanel?.isVisible == true) return false
        if (linePickerOverlay?.isVisible == true || syncOverlay?.isVisible == true) return false
        if (unifiedMenu?.isVisible == true) return false
        if (sourceBrowser?.isVisible == true) return false
        if (nextOverlay.visibility == View.VISIBLE) return false
        if (pikPakReactivationIndicator.visibility == View.VISIBLE) return false
        return true
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
            iptvRecordingActionsController.toggleIptvRecording()
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
        iptvStartOverButton,
        iptvStartOverSeekButton,
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
    private val iptvRecordingActionsController = TvIptvRecordingActionsController(
        this,
        object : TvIptvRecordingActionsController.Host {
            override val currentIptvStreamUrl: String? get() = this@AndroidTvTorrentPlayerActivity.currentIptvStreamUrl
            override val iptvHlsForcedUrls: Set<String> get() = this@AndroidTvTorrentPlayerActivity.iptvHlsForcedUrls
            override val iptvChannels: List<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override val iptvSources: List<IptvSourceEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvSources
            override val iptvSourceId: String? get() = this@AndroidTvTorrentPlayerActivity.iptvSourceId
            override val currentIptvHttpHeaders: Map<String, String> get() = this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders
            override val iptvRecordingController: IptvRecordingController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingController
            override val iptvRecordButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.iptvRecordButton
            override val legacyStoragePermissionRequestCode: Int get() = this@AndroidTvTorrentPlayerActivity.legacyStoragePermissionRequestCode
        },
    )

    private fun updateIptvControlPresentation(entry: IptvChannelEntry?) {
        val live = entry?.isLive != false
        val vodVisibility = if (live) View.GONE else View.VISIBLE
        val archiveTimelineVisibility = if (
            !live || (iptvStartOverActive && iptvStartOverTimelineVisible)
        ) View.VISIBLE else View.GONE
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
        cinemaProgressContainer?.visibility = archiveTimelineVisibility
        debrifyTimeCurrent?.visibility = archiveTimelineVisibility
        debrifyTimeTotal?.visibility = archiveTimelineVisibility
        speedButton?.visibility = vodVisibility
        nightModeButton?.visibility = View.VISIBLE
        iptvJumpButton?.visibility = if (live) View.VISIBLE else View.GONE
        iptvGuideButton?.visibility = if (live) View.VISIBLE else View.GONE
        iptvStartOverController.updateIptvStartOverButton(entry)
        iptvStartOverController.updateIptvStartOverSeekButton()
        // Visibility follows the ACTIVE recorder: the engine records pre-Q
        // once storage is granted (and shows the button so it CAN be
        // granted); the tee remains Q+-only.
        val recorderAvailable = if (iptvRecordingActionsController.recordingEngineEnabled) {
            LiveRecordingService.isSupported(this) ||
                LiveRecordingService.needsLegacyPermission(this)
        } else {
            IptvRecordingController.isSupported
        }
        iptvRecordButton?.visibility =
            if (live && recorderAvailable) View.VISIBLE else View.GONE
        iptvRecordingActionsController.updateRecordButtonState()
        if (!live && iptvGuideVisible) hideIptvGuide()
        if (live) {
            cinemaSeekMode = false
            cinemaSeekWasPlaying = false
            cinemaProgressThumb?.visibility = View.INVISIBLE
            cinemaSpeedIndicator?.visibility = View.GONE
            if (currentFocus == cinemaProgressContainer) {
                pauseButton?.requestFocus()
            }
        }
    }

    /** Live IPTV uses a balanced dock:
     *  Audio · Subs · Aspect | CH- · Play/Pause · Start Over · Seek · CH+ |
     *  Guide · Jump · Record · Night.
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
            iptvStartOverButton,
            iptvStartOverSeekButton,
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
            iptvStartOverButton,
            iptvStartOverSeekButton,
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
        // Guide rows own their DPAD scale animation through
        // ViewPropertyAnimator. RecyclerView's DefaultItemAnimator uses that
        // same animator for change/removal transitions; rebinding a row then
        // cancels RecyclerView's animation from inside onBindViewHolder and
        // can synchronously recycle a still-tmp-detached holder. Android 9
        // throws in that state and kills the whole player process. List
        // changes are still applied immediately by DiffUtil; only the
        // conflicting decorative transition is disabled.
        guideList.itemAnimator = null
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
                iptvEpgEntry?.let { entry -> iptvStartOverController.requestIptvCatchup(entry, program) }
            },
            onRecordFuture = { program ->
                iptvEpgEntry?.let { entry -> iptvRecordingActionsController.promptScheduleRecording(entry, program) }
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
            R.id.iptv_epg_day_three_ago,
            R.id.iptv_epg_day_two_ago,
            R.id.iptv_epg_day_yesterday,
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
        findViewById<View>(R.id.iptv_epg_day_three_ago)?.setOnClickListener {
            selectIptvEpgDay(-3)
        }
        findViewById<View>(R.id.iptv_epg_day_two_ago)?.setOnClickListener {
            selectIptvEpgDay(-2)
        }
        findViewById<View>(R.id.iptv_epg_day_yesterday)?.setOnClickListener {
            selectIptvEpgDay(-1)
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
            R.id.iptv_epg_day_three_ago,
            R.id.iptv_epg_day_two_ago,
            R.id.iptv_epg_day_yesterday,
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

    private fun showIptvGuide() {
        if (iptvChannels.getOrNull(currentIptvIndex)?.isLive != true) return
        // The banner is attached last to the content view (topmost) — it must
        // never float over the guide.
        iptvZapBannerController.hideIptvZapBanner()
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
        val needsCatchupMetadata = entry.isCurrent && !entry.epgCatchupMetadataLoaded
        if (entry.epgLoaded && !stale && !needsCatchupMetadata) return
        if (!entry.url.startsWith("http")) return // stremio-tv:// keys etc.

        entry.epgLoading = true
        val requestedCatchupMetadata = entry.isCurrent
        requestIptvEpg(
            entry,
            includeSchedule = false,
            includeCatchupMetadata = requestedCatchupMetadata,
        ) { result ->
            entry.epgLoading = false
            entry.epgLoaded = true
            // A cheap now/next answer carries no panel archive fields and
            // overwrites epgNowHasArchive below. Invalidate the enrichment
            // marker with it so returning to this channel (including after
            // the programme advances) requests metadata for the new NOW row.
            entry.epgCatchupMetadataLoaded = requestedCatchupMetadata
            val now = result?.get("now") as? Map<*, *>
            entry.epgNowTitle =
                (now?.get("title") as? String)?.takeIf { it.isNotBlank() }
            entry.epgNowStartMs = (now?.get("startMs") as? Number)?.toLong() ?: 0L
            entry.epgNowStopMs = (now?.get("stopMs") as? Number)?.toLong() ?: 0L
            entry.epgNowHasArchive = now?.get("hasArchive") == true
            if (requestedCatchupMetadata && !entry.epgNowHasArchive) {
                // A recovered panel may publish archive metadata before the
                // current programme ends. Retry at a bounded cadence.
                iptvBrowseHandler.postDelayed({
                    entry.epgCatchupMetadataLoaded = false
                    if (entry.isCurrent && !isFinishing && !isDestroyed) {
                        ensureIptvChannelEpg(entry)
                    }
                }, 60_000L)
            }
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
                iptvStartOverController.updateIptvStartOverButton(entry)
                // A visible zap banner for this channel paints the fresh data.
                if (iptvZapBannerController.iptvZapBanner?.visibility == View.VISIBLE) {
                    iptvZapBannerController.paintIptvZapBannerEpg(entry)
                }
                // It may have become current while a cheap row request was
                // in flight. Follow that answer with the one archive-aware
                // upgrade instead of falsely marking metadata complete.
                if (!requestedCatchupMetadata) ensureIptvChannelEpg(entry)
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

        requestIptvEpg(entry, includeSchedule = true) { result ->
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
            -3 to findViewById<AppCompatButton>(R.id.iptv_epg_day_three_ago),
            -2 to findViewById<AppCompatButton>(R.id.iptv_epg_day_two_ago),
            -1 to findViewById<AppCompatButton>(R.id.iptv_epg_day_yesterday),
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
        iptvZapBannerController.refreshIptvZapBannerPosition()
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
        iptvZapBannerController.refreshIptvZapBannerPosition()
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
        iptvStartOverController.iptvCatchupToken++
        iptvStartOverActive = false
        iptvStartOverLoading = false
        iptvStartOverTimelineVisible = false
        val previousPlaying = iptvChannels.getOrNull(currentIptvIndex)
        // Bank the outgoing channel's position BEFORE currentIptvIndex moves,
        // or zapping back to a half-watched movie would rewind it to wherever
        // it stood when the player was launched.
        if (checkpointOutgoing) checkpointCurrentIptvPosition()
        // A channel zap orphans any pending source-switch watcher (see playItem)
        sourceSwitchController.dropStaleSourceSwitchFeedback()

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
        iptvChannelStartController.beginIptvPlaybackAfterWatchRegistration(selected)

        // Update title
        titleView.text = selected.displayName

        // Channel-change feedback belongs to live zapping. VOD keeps the
        // standard player presentation.
        if (selected.isLive) iptvZapBannerController.showIptvZapBanner(selected) else iptvZapBannerController.hideIptvZapBanner()

        updateIptvGuideCurrentName()
        // Index moved — a previous episode may have (dis)appeared.
        updateIptvEpisodeControls()
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
    private val iptvZapBannerController: TvIptvZapBannerController = TvIptvZapBannerController(
        this,
        object : TvIptvZapBannerController.Host {
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsMenuVisible
            override val controlsOverlay: View? get() = this@AndroidTvTorrentPlayerActivity.controlsOverlay
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override fun dp(value: Int): Int = this@AndroidTvTorrentPlayerActivity.dp(value)
            override fun ensureIptvChannelEpg(entry: IptvChannelEntry): Unit = this@AndroidTvTorrentPlayerActivity.ensureIptvChannelEpg(entry)
            override fun formatEpgTime(timeMs: Long): String = this@AndroidTvTorrentPlayerActivity.formatEpgTime(timeMs)
            override val guideStyle: GuideStyle get() = this@AndroidTvTorrentPlayerActivity.guideStyle
            override val guideTokens: GuideTokens? get() = this@AndroidTvTorrentPlayerActivity.guideTokens
            override fun guideTypeface(file: String?): Typeface? = this@AndroidTvTorrentPlayerActivity.guideTypeface(file)
            override val iptvChannels: MutableList<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvGuideVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvGuideVisible
            override val iptvRecordingActionsController: TvIptvRecordingActionsController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingActionsController
            override val iptvRecordingController: IptvRecordingController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingController
            override val iptvSources: List<IptvSourceEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvSources
            override val iptvZapCategoryTotal: Int get() = this@AndroidTvTorrentPlayerActivity.iptvZapCategoryTotal
            override val iptvZapPagingActive: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvZapPagingActive
            override val iptvZapSourceId: String? get() = this@AndroidTvTorrentPlayerActivity.iptvZapSourceId
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun updateSubtitleControlsLift(): Unit = this@AndroidTvTorrentPlayerActivity.updateSubtitleControlsLift()
        },
    )

    // ── In-player guide style (see IptvGuideStyle.kt) ──────────────────────
    // Read once per launch, like recordingEngineEnabled: the Dart side owns
    // the pref; changing it applies to the next playback session. CLASSIC
    // (null tokens) keeps every legacy paint path verbatim.
    private val guideStyle: GuideStyle by lazy {
        GuideStyle.fromPref(
            playerPreferences.getString(
                "iptv_player_guide_style",
                "classic",
            ),
        )
    }
    private val guideTokens: GuideTokens? by lazy { GuideTokens.of(guideStyle) }

    // ── Control skin (see TvControlsSkin.kt) ───────────────────────────────
    // Same read-once contract as guideStyle. Live IPTV sessions force CLASSIC
    // until the OTT skin's live arrangement ships, which is why the gate is
    // taken at setupControls time (isIptvMode is already set on that path)
    // rather than baked into this lazy.
    private val controlsSkin: TvControlsSkin by lazy {
        TvControlsSkin.fromPref(
            playerPreferences.getString(
                TvControlsSkin.PREF_KEY,
                "ott",
            ),
        )
    }

    /** Everything that differs between dock skins WITHOUT deserving its own
     *  code branch: which layout inflates, bar geometry, the focus gesture,
     *  which icon family play/pause swaps within. Behavior that can't be a
     *  number (identity arrangement, the PULSE spannable) branches on
     *  [controlsSkin] directly. */
    private data class DockSkinSpec(
        val layoutRes: Int,
        val trackIdleDp: Float,
        val trackFocusDp: Float,
        val focusScale: Float,
        val focusLiftDp: Float,
        // Only the OTT scrim needs 4 stops (its Flutter source of truth);
        // every other skin's XML background is final as inflated.
        val applyShaderScrim: Boolean,
        val playIconRes: Int,
        val pauseIconRes: Int,
    )

    /** null exactly when [controlsSkin] is CLASSIC — the "is a dock skin
     *  selected" test, evaluated before the IPTV launch gate. */
    private val dockSkinSpec: DockSkinSpec? by lazy {
        when (controlsSkin) {
            TvControlsSkin.CLASSIC -> null
            TvControlsSkin.OTT -> DockSkinSpec(
                R.layout.view_debrify_tv_ott_controls,
                trackIdleDp = 3f, trackFocusDp = 6f,
                focusScale = 1.08f, focusLiftDp = 0f,
                applyShaderScrim = true,
                playIconRes = R.drawable.ic_dock_play,
                pauseIconRes = R.drawable.ic_dock_pause,
            )
            TvControlsSkin.FROST -> DockSkinSpec(
                R.layout.view_debrify_tv_frost_controls,
                trackIdleDp = 3f, trackFocusDp = 6f,
                focusScale = 1.08f, focusLiftDp = 0f,
                applyShaderScrim = false,
                playIconRes = R.drawable.ic_dock_play,
                pauseIconRes = R.drawable.ic_dock_pause,
            )
            TvControlsSkin.MARQUEE -> DockSkinSpec(
                R.layout.view_debrify_tv_marquee_controls,
                trackIdleDp = 2f, trackFocusDp = 4f,
                // Bare glyphs don't scale; they lift onto their underline.
                focusScale = 1.0f, focusLiftDp = 2f,
                applyShaderScrim = false,
                playIconRes = R.drawable.ic_wire_play,
                pauseIconRes = R.drawable.ic_wire_pause,
            )
            TvControlsSkin.BROADCAST -> DockSkinSpec(
                R.layout.view_debrify_tv_broadcast_controls,
                trackIdleDp = 5f, trackFocusDp = 7f,
                focusScale = 1.06f, focusLiftDp = 0f,
                applyShaderScrim = false,
                playIconRes = R.drawable.ic_dock_play,
                pauseIconRes = R.drawable.ic_dock_pause,
            )
            TvControlsSkin.PULSE -> DockSkinSpec(
                R.layout.view_debrify_tv_pulse_controls,
                trackIdleDp = 5f, trackFocusDp = 8f,
                focusScale = 1.08f, focusLiftDp = 0f,
                applyShaderScrim = false,
                playIconRes = R.drawable.ic_dock_play,
                pauseIconRes = R.drawable.ic_dock_pause,
            )
            TvControlsSkin.TICKET -> DockSkinSpec(
                R.layout.view_debrify_tv_ticket_controls,
                trackIdleDp = 4f, trackFocusDp = 6f,
                focusScale = 1.0f, focusLiftDp = 1.5f,
                applyShaderScrim = false,
                playIconRes = R.drawable.ic_dock_play,
                pauseIconRes = R.drawable.ic_dock_pause,
            )
        }
    }

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

        iptvChannelStartController.beginIptvPlayback(entry)

        // Update the title content. Visibility stays synchronized with controls.
        titleView.text = entry.displayName

        // First tune on a live channel: the zap banner doubles as the "here's
        // what's on" card and teaches the zap/guide keys — without it, EPG
        // exists only inside a guide overlay nobody knows how to open.
        if (entry.isLive) iptvZapBannerController.showIptvZapBanner(entry)
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

    /** The shared ExoPlayer media-item swap both IPTV entry points use. */
    private fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String) {
        // A genuine channel change while recording: finalize the previous
        // channel's file before the stream identity flips. An HLS-fallback retry
        // re-enters with the SAME url and is handled via abortAndDelete instead.
        if (iptvRecordingController.isActive && streamUrl != currentIptvStreamUrl) {
            iptvRecordingActionsController.finalizeIptvRecordingIfActive()
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
        // Demux mode for this tune: strict immediately on known-strict devices,
        // for channels that earned it, and for the whole session once two did
        // (that's a strict-decoder device, not two odd channels). Read per
        // media-period load by the extractor factory installed in setupPlayer.
        // A twin — on trial or accepted — is always strict: it exists to reach
        // the demux mode that works (see the twin-trial fields).
        iptvStrictTsActive =
            iptvStartsWithStrictTs ||
            iptvStrictTsUrls.contains(streamUrl) || iptvStrictTsUrls.size >= 2 ||
            streamUrl == iptvTwinTrialUrl ||
            iptvTwinPreferredUrls.containsValue(streamUrl)
        iptvTuneDiagnostics.onTuneStart(
            entry.name,
            streamUrl,
            entry.isLive,
            forcedHls = iptvHlsForcedUrls.contains(streamUrl),
        )
        if (iptvStartsWithStrictTs) {
            iptvTuneDiagnostics.note("demux=strict reason=device-quirk")
        }
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
                subtitleTrackReadiness.onMediaReplacement()
                setMediaItem(mediaItem, startAt)
            } else {
                subtitleTrackReadiness.onMediaReplacement()
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
        iptvRecordingActionsController.updateRecordButtonState()
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
        iptvRecordingActionsController.updateRecordButtonState()
        // Stremio candidate: give the forced-HLS attempt a FULL stall window
        // (arming re-cancels the one ticking since candidate start — a slow
        // panel can eat most of that window on the failed sniff alone, and
        // the ladder would advance past a candidate that plays when forced).
        if (iptvChannelStartController.iptvStremioChannelKey != null) {
            iptvChannelStartController.armIptvStremioStallWatchdog()
        }
        return true
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

    // Passed to the controller so named shortcuts match the visible rows.
    private val unifiedSectionIds = listOf("audio", "subs", "display", "playback")

    private fun umSectionRows(): List<UnifiedMenuController.Row> {
        val subBadge = when {
            isLoadingStremioSubtitles -> "…"
            stremioSubtitles.isNotEmpty() -> "${stremioSubtitles.size}"
            else -> null
        }
        return listOf(
            mrow("Audio"),
            mrow("Subtitles", value = subBadge),
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
            tag == "emb" -> "Track" to subtitleController.umEmbeddedTrackRows()
            tag == "appearance" -> "Appearance · live" to subtitleController.umAppearanceRows()
            tag == "timing" -> "Timing" to subtitleController.umTimingRows()
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
                        tag = "subtitle:${sub.url}",
                        // Require addonId match too: a URL shared by two addons dedupes
                        // to one owner, so only that addon's row highlights.
                        selected = cur?.url == sub.url && cur.addonId == addonId,
                        onOk = { subtitleController.umSelectStremioSubtitleByUrl(sub.url) }
                    )
                }
        }
    }

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
                onOk = { sourceSwitchController.onStremioSourceSelected(src); unifiedMenu?.hide() }
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
            mrow("Sleep timer", value = sleepTimerController.sleepTimerValueLabel(), tag = "sleep"),
            mrow("Shuffle & autoplay", tag = "shuffle")
        )
        val tag = col2.getOrNull(col2Index)?.tag
        val (title, col3) = if (tag == "sleep") {
            "Sleep timer" to buildList {
                add(
                    mrow("Off", selected = sleepTimerController.sleepTimerMode == SleepTimerMode.OFF, onOk = {
                        sleepTimerController.cancelSleepTimer(announce = true)
                    })
                )
                sleepTimerController.sleepTimerMinuteOptions.forEach { minutes ->
                    add(mrow("$minutes minutes", onOk = { sleepTimerController.startSleepCountdown(minutes) }))
                }
                // A live channel has no end to stop at, so only the countdown
                // applies there — which is the case people actually want it for.
                if (iptvChannels.getOrNull(currentIptvIndex)?.isLive != true) {
                    add(
                        mrow(
                            "End of episode",
                            selected = sleepTimerController.sleepTimerMode == SleepTimerMode.END_OF_ITEM,
                            onOk = { sleepTimerController.armSleepAtEndOfItem() }
                        )
                    )
                }
            }
        } else if (tag == "shuffle") {
            "Shuffle & autoplay" to listOf(
                mrow("Play random once", accent = true, onOk = {
                    continuousShuffleEnabled = false; resetShuffle(); playRandom(); unifiedMenu?.hide()
                }),
                mrow("Shuffle continuously", value = if (continuousShuffleEnabled) "On" else "Off",
                    selected = continuousShuffleEnabled, onOk = {
                        val turningOn = !continuousShuffleEnabled
                        continuousShuffleEnabled = turningOn
                        resetShuffle()
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
                    applyPlaybackSpeed(i)
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
        applyPlaybackSpeed((playbackSpeedIndex + 1) % playbackSpeeds.size)
        Toast.makeText(this, "Speed: ${playbackSpeedLabels[playbackSpeedIndex]}", Toast.LENGTH_SHORT).show()
    }

    private fun applyPlaybackSpeed(index: Int) {
        playbackSpeedIndex = index.coerceIn(0, playbackSpeeds.lastIndex)
        val speed = playbackSpeeds[playbackSpeedIndex]
        val routeChanged = nativeAudioRouting.update(nightModeIndex > 0, systemAudioEffectsEnabled, speed)
        if (routeChanged) {
            releaseLoudnessEnhancer()
        }
        nativeAudioRouting.setPlaybackSpeed(player, speed, routeChanged)
        // Dock skins carry the speed on the button itself — visibly on
        // BROADCAST's labeled pill, and as the shared focus caption on the
        // rest (which would otherwise go stale). Classic keeps its Toast-only
        // presentation untouched.
        if (ottSkinInstalled) {
            speedButton?.text = playbackSpeedLabels[playbackSpeedIndex]
            refreshOttCaptionFor(speedButton)
        }
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
            resizeModeIndex = playerPreferences
                .getLong("player_default_aspect_index_tv", 0L).toInt()
                .coerceIn(0, resizeModes.lastIndex)

            // Load night mode index (default: 0 = Off)
            nightModeIndex = playerPreferences
                .getLong("player_night_mode_index", 0L).toInt()
                .coerceIn(0, nightModeGains.lastIndex)

            // Announce our audio session to system effect apps (default: off)
            systemAudioEffectsEnabled = playerPreferences
                .getBoolean("player_system_audio_effects", false)

            displayMatchMode = TvContentDisplayMatchMode.fromStorage(
                playerPreferences.getString(
                    "content_display_match_mode",
                    TvContentDisplayMatchMode.SYSTEM.storageKey,
                ),
            )
            displayModeController?.clear()
            displayModeController = TvDisplayModeController(this, displayMatchMode)

            // Manual community intro/outro buttons. These are the same keys the
            // Flutter Playback settings page writes; enabled never means auto-seek.
            skipSegmentsEnabled = playerPreferences
                .getBoolean("skip_segments_enabled", true)
            val storedSkipSegmentProvider = playerPreferences.getString(
                "skip_segment_provider",
                TvSkipSegmentClients.AUTO,
            ) ?: TvSkipSegmentClients.AUTO
            skipSegmentProviderId = if (TvSkipSegmentClients.supports(storedSkipSegmentProvider)) {
                storedSkipSegmentProvider
            } else {
                TvSkipSegmentClients.AUTO
            }

            android.util.Log.d("AndroidTvPlayer", "Loaded defaults - aspect=$resizeModeIndex, nightMode=$nightModeIndex, audioEffects=$systemAudioEffectsEnabled, displayMatch=${displayMatchMode.storageKey}, skipSegments=$skipSegmentsEnabled, skipProvider=$skipSegmentProviderId")
            android.util.Log.d("AndroidTvPlayer", "Player settings handoff: style=$controlsSkin subtitles=${playerPreferences.getString("player_default_subtitle_language", "auto")} nightMode=$nightModeIndex")
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

        val speed = playbackSpeeds[playbackSpeedIndex]
        val routeChanged = nativeAudioRouting.update(nightModeIndex > 0, systemAudioEffectsEnabled, speed)
        if (routeChanged) {
            // A recreated AudioTrack may retain its session ID; READY must
            // attach a fresh effect even without onAudioSessionIdChanged.
            releaseLoudnessEnhancer()
        }
        val restartingAudio = routeChanged && nativeAudioRouting.reprepare(player, speed)

        if (nightModeIndex == 0) {
            // Turn off
            loudnessEnhancer?.enabled = false
        } else if (!restartingAudio) {
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
    private var finalProgressSnapshot = false
    private var finishProgressAttempted = false

    private fun recordPlaybackLifecycle(event: String, details: String = "") {
        DiagnosticFileLog.recordCritical(
            source = "android_tv_player", event = event,
            message = "pid=${android.os.Process.myPid()} activity=${System.identityHashCode(this)} " +
                "session=$sourcePersistenceSessionId finishing=$isFinishing " +
                "changingConfigurations=$isChangingConfigurations " +
                "sent=${progressReporter.progressSentCount} acknowledged=${progressReporter.progressAckCount} $details",
        )
    }

    override fun finish() {
        // Write the exact exit position before Android uncovers/recreates the
        // Flutter host. The normal five-second writer is asynchronous; relying
        // on it here recreates the stale Continue Watching race seen on Bravia.
        if (!finishProgressAttempted) {
            finalProgressSnapshot = true
            try {
                progressReporter.sendProgress(completed = false)
            } finally {
                finalProgressSnapshot = false
            }
            finishProgressAttempted = true
        }
        PlaybackReturnHandoff.markReturning(sourcePersistenceSessionId)
        recordPlaybackLifecycle("finish_requested")
        super.finish()
    }

    private fun sendFinished() {
        val result = hashMapOf<String, Any>(
            "sourcePersistenceSessionId" to sourcePersistenceSessionId,
        )
        if (startupGateController.startupSourcesExhausted) {
            result["startupSourcesExhausted"] = true
            result["startupRecoveryConsumed"] = startupGateController.startupRecoveryConsumed
        }
        val channel = MainActivity.getAndroidTvPlayerChannel()
        recordPlaybackLifecycle("finish_sent", "bridgeAvailable=${channel != null}")
        try {
            channel?.invokeMethod("torrentPlaybackFinished", result)
        } catch (error: RuntimeException) {
            DiagnosticFileLog.recordError(
                source = "android_tv_player", event = "finish_delivery_failed", throwable = error,
            )
        }
    }

    /** The guide episode adjacent to the current item (specials excluded). */
    private fun guideAdjacent(model: PlaybackPayload, currentItem: PlaybackItem?, direction: Int, allowResolverFallback: Boolean = false): SeasonEpisode? {
        // Custom catalogs own navigation even when the ordinary guide is loaded.
        if (hasAdjacentEpisodeResolver && !allowResolverFallback) return null
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
        if (direction > 0 && !eps[t].shuffleEligible) return null
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
        suppressResume: Boolean = autoAdvance,
        shuffleAttempt: ShufflePlaybackAttempt? = null,
        onUnavailable: (() -> Unit)? = null,
        shouldContinue: (() -> Boolean)? = null,
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
                        if (token != stremioResolutionToken || shouldContinue?.invoke() == false) return@runOnUiThread
                        if (yieldEpisodeFetchToQueuedShuffle()) return@runOnUiThread
                        val map = result as? Map<*, *>
                        val items = map?.get("items") as? List<*>
                        val fetchedSourceIndex = (map?.get("sourceIndex") as? Number)?.toInt()
                        if (map == null || items.isNullOrEmpty() || fetchedSourceIndex == null) {
                            if (onUnavailable != null) onUnavailable()
                            else showStatusPillTransient("No playable source found for $label")
                            return@runOnUiThread
                        }
                        isAutoAdvancing = autoAdvance
                        adoptSourceList(map)
                        if (shuffleAttempt != null) watchShufflePlayback(shuffleAttempt)
                        sourceSwitchController.applier.switchToSourcePlaylist(
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
                    runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != stremioResolutionToken || shouldContinue?.invoke() == false) return@runOnUiThread
                        if (onUnavailable != null) onUnavailable()
                        else showStatusPillTransient("No playable source found for $label")
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
        imdbId: String?,
        currentSeason: Int,
        currentEpisode: Int,
        autoAdvance: Boolean = false,
        direction: Int = 1,
    ) {
        if (episodeFetchInFlight) return
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            showStatusPillTransient("Couldn't fetch next episode")
            return
        }
        episodeFetchInFlight = true
        val token = ++stremioResolutionToken
        val directionLabel = if (direction < 0) "previous" else "next"
        showStatusPillTransient("Finding $directionLabel episode…")
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
                    runOnUiThread {
                        episodeFetchInFlight = false
                        if (token != stremioResolutionToken) return@runOnUiThread
                        if (yieldEpisodeFetchToQueuedShuffle()) return@runOnUiThread
                        val map = result as? Map<*, *>
                        val items = map?.get("items") as? List<*>
                        val fetchedSourceIndex = (map?.get("sourceIndex") as? Number)?.toInt()
                        if (map == null || items.isNullOrEmpty() || fetchedSourceIndex == null) {
                            showStatusPillTransient("No playable $directionLabel episode found")
                            return@runOnUiThread
                        }
                        val targetSeason = (map["targetSeason"] as? Number)?.toInt()
                        val targetEpisode = (map["targetEpisode"] as? Number)?.toInt()
                        if (targetSeason == null || targetEpisode == null) {
                            showStatusPillTransient("No playable $directionLabel episode found")
                            return@runOnUiThread
                        }
                        adoptSourceList(map)
                        sourceSwitchController.applier.switchToSourcePlaylist(
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
                        if (yieldEpisodeFetchToQueuedShuffle()) return@runOnUiThread
                        if (errorCode == "episode_guide_unavailable") {
                            val model = payload
                            val current = model?.items?.getOrNull(currentIndex)
                            if (model != null && current?.season == currentSeason && current.episode == currentEpisode) {
                                val target = guideAdjacent(model, current, direction, allowResolverFallback = true)
                                if (target != null) {
                                    requestEpisodeFetch(target.season, target.episode, autoAdvance = autoAdvance)
                                    return@runOnUiThread
                                }
                            }
                        }
                        showStatusPillTransient("No playable $directionLabel episode found")
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
    private val sourceSwitchController: TvSourceSwitchController = TvSourceSwitchController(
        this,
        object : TvSourceSwitchController.Host {
            override var activeVodHeaders: Pair<Set<String>, Map<String, String>>
                get() = this@AndroidTvTorrentPlayerActivity.activeVodHeaders
                set(value) { this@AndroidTvTorrentPlayerActivity.activeVodHeaders = value }
            override fun armStartupCandidate(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.startupGateController.armStartupCandidate(sourceIndex)
            override fun attemptPikPakPlaybackLoop(item: PlaybackItem, attemptNumber: Int, retryId: Int): Unit = this@AndroidTvTorrentPlayerActivity.attemptPikPakPlaybackLoop(item, attemptNumber, retryId)
            override fun beginManualSourceCandidate(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.startupGateController.beginManualSourceCandidate(sourceIndex)
            override fun buildMergedSource(videoUrl: String, audioUrl: String): MergingMediaSource? = this@AndroidTvTorrentPlayerActivity.buildMergedSource(videoUrl, audioUrl)
            override fun cancelPikPakRetry(): Unit = this@AndroidTvTorrentPlayerActivity.cancelPikPakRetry()
            override var currentIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIndex = value }
            override var currentStremioSourceIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex = value }
            override fun discoverProtectedMime(url: String, headers: Map<String, String>, ready: (String?) -> Unit): Unit = this@AndroidTvTorrentPlayerActivity.discoverProtectedMime(url, headers, ready)
            override fun failManualSourceCandidate(reason: String): Boolean = this@AndroidTvTorrentPlayerActivity.startupGateController.failManualSourceCandidate(reason)
            override fun failStartupResolution(sourceIndex: Int, reason: String): Boolean = this@AndroidTvTorrentPlayerActivity.startupGateController.failStartupResolution(sourceIndex, reason)
            override val hasPlaylistResolver: Boolean get() = this@AndroidTvTorrentPlayerActivity.hasPlaylistResolver
            override fun heldResumePositionMs(actualMs: Long): Long? = this@AndroidTvTorrentPlayerActivity.heldResumePositionMs(actualMs)
            override fun hideControlsMenu(): Unit = this@AndroidTvTorrentPlayerActivity.hideControlsMenu()
            override fun hidePikPakRetryOverlay(): Unit = this@AndroidTvTorrentPlayerActivity.hidePikPakRetryOverlay()
            override fun hideStatusPill(): Unit = this@AndroidTvTorrentPlayerActivity.hideStatusPill()
            override val iptvChannelStartController: TvIptvChannelStartController get() = this@AndroidTvTorrentPlayerActivity.iptvChannelStartController
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override var isPikPakRetrying: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.isPikPakRetrying
                set(value) { this@AndroidTvTorrentPlayerActivity.isPikPakRetrying = value }
            override var manualSourceCandidateUrl: String?
                get() = this@AndroidTvTorrentPlayerActivity.startupGateController.manualSourceCandidateUrl
                set(value) { this@AndroidTvTorrentPlayerActivity.startupGateController.manualSourceCandidateUrl = value }
            override var manualSourceMediaReplaced: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.startupGateController.manualSourceMediaReplaced
                set(value) { this@AndroidTvTorrentPlayerActivity.startupGateController.manualSourceMediaReplaced = value }
            override val manualSourceSwitchSnapshot: ManualSourceSwitchSnapshot? get() = this@AndroidTvTorrentPlayerActivity.startupGateController.manualSourceSwitchSnapshot
            override var mediaPreparationGeneration: Int
                get() = this@AndroidTvTorrentPlayerActivity.mediaPreparationGeneration
                set(value) { this@AndroidTvTorrentPlayerActivity.mediaPreparationGeneration = value }
            override val ottSkinInstalled: Boolean get() = this@AndroidTvTorrentPlayerActivity.ottSkinInstalled
            override val ottSourcesButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.ottSourcesButton
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override var percentSeekApplied: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.percentSeekApplied
                set(value) { this@AndroidTvTorrentPlayerActivity.percentSeekApplied = value }
            override var pikPakRetryCount: Int
                get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryCount
                set(value) { this@AndroidTvTorrentPlayerActivity.pikPakRetryCount = value }
            override var pikPakRetryId: Int
                get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryId
                set(value) { this@AndroidTvTorrentPlayerActivity.pikPakRetryId = value }
            override fun playItem(index: Int, suppressTrakt: Boolean, suppressResume: Boolean, shuffleAttempt: ShufflePlaybackAttempt?): Unit = this@AndroidTvTorrentPlayerActivity.playItem(index, suppressTrakt, suppressResume, shuffleAttempt)
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun rebuildPlaylistContent(): Unit = this@AndroidTvTorrentPlayerActivity.rebuildPlaylistContent()
            override fun requestMetadataFromFlutter(): Unit = this@AndroidTvTorrentPlayerActivity.requestMetadataFromFlutter()
            override var resumeHoldArmedAtMs: Long
                get() = this@AndroidTvTorrentPlayerActivity.resumeHoldArmedAtMs
                set(value) { this@AndroidTvTorrentPlayerActivity.resumeHoldArmedAtMs = value }
            override fun showStatusPill(text: String): Unit = this@AndroidTvTorrentPlayerActivity.showStatusPill(text)
            override fun showStatusPillTransient(text: String): Unit = this@AndroidTvTorrentPlayerActivity.showStatusPillTransient(text)
            override val shuffleBag: MutableList<Int> get() = this@AndroidTvTorrentPlayerActivity.shuffleBag
            override val sourceBrowser: TvSourceBrowserController? get() = this@AndroidTvTorrentPlayerActivity.sourceBrowser
            override var startupFailoverCursor: StartupFailoverCursor?
                get() = this@AndroidTvTorrentPlayerActivity.startupGateController.startupFailoverCursor
                set(value) { this@AndroidTvTorrentPlayerActivity.startupGateController.startupFailoverCursor = value }
            override val startupFailoverDispatching: Boolean get() = this@AndroidTvTorrentPlayerActivity.startupGateController.startupFailoverDispatching
            override val startupRecoveryCandidateIndices: List<Int>? get() = this@AndroidTvTorrentPlayerActivity.startupGateController.startupRecoveryCandidateIndices
            override fun startupSourceFields(index: Int): String = this@AndroidTvTorrentPlayerActivity.startupGateController.startupSourceFields(index)
            override var stremioResolutionToken: Int
                get() = this@AndroidTvTorrentPlayerActivity.stremioResolutionToken
                set(value) { this@AndroidTvTorrentPlayerActivity.stremioResolutionToken = value }
            override val stremioSourceBadge: View? get() = this@AndroidTvTorrentPlayerActivity.stremioSourceBadge
            override val stremioSourceBadgeText: TextView? get() = this@AndroidTvTorrentPlayerActivity.stremioSourceBadgeText
            override val stremioSources: MutableList<StremioSource> get() = this@AndroidTvTorrentPlayerActivity.stremioSources
            override val subtitleTrackReadiness: SubtitleTrackReadiness get() = this@AndroidTvTorrentPlayerActivity.subtitleTrackReadiness
            override val titleView: TextView get() = this@AndroidTvTorrentPlayerActivity.titleView
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
            override fun updateCatalogEpisodeControls(): Unit = this@AndroidTvTorrentPlayerActivity.updateCatalogEpisodeControls()
        },
    )

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
            failMoreTorrentSources()
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
        if (isFinishing || isDestroyed) return
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
        sourceSwitchController.updateStremioQualityBadge()
        unifiedMenu?.render()
        sourceBrowser?.render()
        if (startupGateController.startupRecoveryFetching) {
            startupGateController.startupRecoveryFetching = false
            // A completed search with candidates owns recovery, even when all
            // were duplicates/ineligible or fewer than the attempt budget.
            // Do not restart Dart recovery with a fresh acquisition allowance.
            startupGateController.startupRecoveryProducedCandidates = startupGateController.startupRecoveryProducedCandidates ||
                (map["recoveryCandidateCount"] as? Number)?.toInt()?.let { it > 0 } == true
            startupGateController.startupRecoveryCandidateIndices = (map["recoveryCandidateIndices"] as? List<*>)
                ?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
            startupGateController.startupRecoveryNextMode = map["recoveryNextMode"] as? String
            startupGateController.failStartupCandidate("recovery-results")
        }
    }

    /** Per-addon fetch from the source browser: episode results first — the
     * response merges them into the list AND says whether they carried
     * torrent magnets (probePacks). Only then does the lazy season-pack probe
     * run as a SECOND call, so direct links render the moment they arrive. */
    private fun requestAddonTorrentSources(groupId: String) {
        // Configuration-specific group ids keep separately configured copies
        // of the same manifest independently fetchable.
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
        if (map?.get("preferredSourceMissing") == true) {
            android.widget.Toast.makeText(this,
                "Your previous source is unavailable for this episode. Using another source.",
                android.widget.Toast.LENGTH_LONG).show()
        }
        val newSources = (map?.get("stremioSources") as? List<*>) ?: return
        if (newSources.isEmpty()) return
        stremioSources.clear()
        for ((idx, src) in newSources.withIndex()) {
            val srcMap = src as? Map<*, *> ?: continue
            stremioSources.add(StremioSource.fromMap(srcMap, idx))
        }
        currentStremioSourceIndex = currentStremioSourceIndex
            .coerceIn(0, stremioSources.lastIndex.coerceAtLeast(0))
        sourceSwitchController.updateStremioQualityBadge()
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
        if (startupGateController.startupRecoveryFetching) {
            startupGateController.startupRecoveryFetching = false
            progressHandler.post { if (!isFinishing && !isDestroyed) startupGateController.failStartupCandidate("recovery-results") }
        }
    }

    private fun parsePayload(raw: String): PlaybackPayload? {
        return try {
            val obj = JSONObject(raw)
            val itemsJson = obj.optJSONArray("items") ?: JSONArray()
            val items = mutableListOf<PlaybackItem>()
            for (i in 0 until itemsJson.length()) {
                val itemObj = itemsJson.getJSONObject(i)
                // Legacy session headers apply only while parsing original
                // launch items. Replacement items never inherit them.
                if (!itemObj.has("httpHeaders")) {
                    itemObj.put("httpHeaders", obj.optJSONObject("httpHeaders") ?: JSONObject())
                }
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
            val imdbId = obj.nullableString("imdbId")

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
                obj.optInt("movieCompletionThreshold", 80).coerceIn(50, 100)
            val episodeCompletionThreshold =
                obj.optInt("episodeCompletionThreshold", 80).coerceIn(50, 100)

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
            hasAdjacentEpisodeResolver = obj.optBoolean("hasAdjacentEpisodeResolver", false)
            customShuffleEpisodes = obj.optJSONArray("customShuffleEpisodes")?.let { rows ->
                (0 until rows.length()).mapNotNull { index ->
                    val row = rows.optJSONObject(index) ?: return@mapNotNull null
                    val season = row.optInt("season", -1)
                    val episode = row.optInt("number", -1)
                    if (season > 0 && episode > 0) ShuffleEpisode(season, episode) else null
                }
            }
            startupGateController.startupTryNextOnFailure = obj.optBoolean("startupTryNextOnFailure", false)
            startupGateController.startupMaxAttempts = obj.optInt("startupMaxAttempts", 1).coerceIn(1, 10)
            startupGateController.startupResolverProvider = obj.optString("startupResolverProvider")
                .takeIf { it.isNotEmpty() }
            startupGateController.startupRecoveryAvailable = obj.optBoolean("startupRecoveryAvailable", false)
            startupGateController.startupHasRemainingSavedSources = obj.optBoolean("startupHasRemainingSavedSources", false)
            sourcePersistenceSessionId = obj.optInt("sourcePersistenceSessionId", sourcePersistenceSessionId)
            startupLog(
                "event=payload_parsed sourceCount=${stremioSources.size} " +
                    "selectedIndex=$currentStremioSourceIndex " +
                    "tryNext=${startupGateController.startupTryNextOnFailure} maxAttempts=${startupGateController.startupMaxAttempts} " +
                    "playlistResolver=$hasPlaylistResolver",
            )

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
            progressReporter.locallyCompletedItemKeys.clear()
            progressReporter.recoveryCompletedItemKeys.clear()

            android.util.Log.d("AndroidTvPlayer", "parsePayload - startIndex: $startIndex, items: ${items.size}, nextMap: ${nextEpisodeMap.size}, prevMap: ${prevEpisodeMap.size}, collectionGroups: ${collectionGroups?.size ?: 0}, imdbId: $imdbId, startAtPercent: $startAtPercent")

            PlaybackPayload(
                title = obj.optString("title"),
                subtitle = obj.optString("subtitle"),
                contentType = obj.optString("contentType", "single"),
                items = items,
                startIndex = startIndex,
                seriesTitle = obj.nullableString("seriesTitle"),
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
        recordPlaybackLifecycle("activity_start")
        progressReporter.sendPlaybackActivityState(true)
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
                !iptvStartOverActive &&
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
        if (subtitleController.externalSubtitleActive) subtitleController.startExternalSubtitleTicker()
    }

    override fun onStop() {
        // A MethodChannel result may arrive after Home. Invalidate it before
        // pausing so it cannot call setIptvMediaItem and restart background
        // playback underneath this lifecycle stop.
        iptvStartOverController.cancelPendingIptvCatchupRequest()
        recordPlaybackLifecycle("activity_stop")
        progressReporter.sendPlaybackActivityState(false)
        // Checkpoint before teardown or background process eviction. Keep the
        // startup/source-switch guards intact when taking this snapshot.
        finalProgressSnapshot = true
        progressReporter.sendProgress(completed = false)
        finalProgressSnapshot = false
        super.onStop()
        // Publish the recording HERE, not just in onDestroy: Home / app-switch
        // runs onStop and Android may kill the process afterwards without ever
        // calling onDestroy, which would strand the row IS_PENDING (invisible,
        // still eating storage) with no persisted state to recover it from.
        // Nothing is lost by stopping now — the pause below ends the byte flow
        // the recording tees anyway.
        iptvRecordingActionsController.finalizeIptvRecordingIfActive()
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
        subtitleController.externalSubtitleTicker?.let { externalSubtitleHandler.removeCallbacks(it) }
    }

    private fun setupBackPressHandler() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // System Back can arrive without a KeyEvent (e.g. remote input).
                if (linePickerOverlay?.isVisible == true) {
                    linePickerOverlay?.hide()
                    return
                }
                if (syncOverlay?.isVisible == true) {
                    syncOverlay?.hide()
                    return
                }
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
                    recordPlaybackLifecycle("back_exit")
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == legacyStoragePermissionRequestCode) {
            // Granted or not, the button's enabled/label state may change.
            iptvRecordingActionsController.updateRecordButtonState()
        }
    }

    override fun onResume() {
        super.onResume()
        recordPlaybackLifecycle("activity_resume")
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
        recordPlaybackLifecycle("activity_pause")
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
        iptvStartOverController.cancelPendingIptvCatchupRequest()
        displayModeController?.clear()
        displayModeController = null
        mediaPreparationScope.cancel()
        mediaPreparationGeneration++
        sourceBrowser?.destroy()
        sourceBrowser = null
        recordPlaybackLifecycle("activity_destroy_begin")
        // finish/onStop may have been blocked by an uncommitted source switch.
        // Retry before tearing down the player, keeping sendProgress's guards.
        finalProgressSnapshot = true
        try {
            progressReporter.sendProgress(completed = false)
        } finally {
            finalProgressSnapshot = false
        }
        if (::subtitleControlsLift.isInitialized) subtitleControlsLift.cancel()
        iptvTuneDiagnostics.onSessionEnd()
        startupGateController.startupFailoverTimeout?.let { progressHandler.removeCallbacks(it) }
        startupGateController.startupFailoverTimeout = null
        startupGateController.startupCommitCheck?.let { progressHandler.removeCallbacks(it) }
        startupGateController.startupCommitCheck = null
        startupGateController.manualSourceSwitchTimeout?.let { progressHandler.removeCallbacks(it) }
        startupGateController.manualSourceSwitchTimeout = null
        startupGateController.manualSourceCommitCheck?.let { progressHandler.removeCallbacks(it) }
        startupGateController.manualSourceCommitCheck = null
        startupGateController.pikPakGateReprepare?.let { progressHandler.removeCallbacks(it) }
        startupGateController.pikPakGateReprepare = null
        startupGateController.manualSourceSwitchSnapshot = null
        startupGateController.manualSourceSwitchIndex = null
        startupGateController.manualSourceRestoreInProgress = false
        startupGateController.startupFailoverGeneration++
        startupGateController.startupFailoverCursor = null
        if (::startupGateView.isInitialized) startupGateView.visibility = View.GONE
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
        RecordingRegistry.removeListener(iptvRecordingActionsController.recordingRegistryListener)
        // The sleep timer belongs to this playback session — a pending one must
        // not outlive the player and fire against a dead surface.
        sleepTimerController.cancelSleepTimer()
        // Finalize any in-progress TEE recording so its MediaStore row isn't
        // left pending (invisible) when the player is torn down. Engine
        // captures deliberately ignore player teardown.
        iptvRecordingActionsController.finalizeIptvRecordingIfActive()

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
        if (::pikPakReactivationIndicator.isInitialized) {
            pikPakReactivationIndicator.animate().cancel()
            pikPakReactivationIndicator.visibility = View.GONE
        }
        if (::bufferingIndicator.isInitialized) bufferingIndicator.animate().cancel()
        bufferingHandler.removeCallbacksAndMessages(null)

        // Clean up Up Next card
        upNextController.upNextHandler.removeCallbacksAndMessages(null)

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
        skipSegmentController.skipSegmentFetchGeneration++
        skipSegmentController.skipSegmentFetchJob?.cancel()
        skipSegmentController.skipSegmentFetchJob = null
        skipSegmentController.skipSegmentScope.cancel()
        skipSegmentController.skipSegmentCache.clear()

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
            recordPlaybackLifecycle("player_release_begin")
            try {
                it.removeListener(playbackListener)
                subtitleListener?.let { listener -> it.removeListener(listener) }
                it.release()
                recordPlaybackLifecycle("player_release_complete")
            } catch (error: RuntimeException) {
                DiagnosticFileLog.recordError(
                    source = "android_tv_player", event = "player_release_failed", throwable = error,
                )
            }
        }
        player = null
        subtitleListener = null
        trackSelector = null
        offsetRenderersFactory = null
        speechTap = null
        syncOverlay = null
        linePickerOverlay?.hide()
        linePickerOverlay = null
        subtitleController.subtitleSeekHandler.removeCallbacks(subtitleController.subtitleSeekRunnable)
        externalSubtitleHandler.removeCallbacksAndMessages(null)
        // Drop the identity provider so the SubtitleSettings singleton doesn't
        // retain this Activity via the captured lambda (no-op if a newer player
        // already registered its own).
        SubtitleSettings.clearActiveSubtitleIdentityProvider(this)

        // Clear adapters to release lambda references
        if (::playlistView.isInitialized) playlistView.adapter = null
        playlistAdapter = null
        seriesPlaylistAdapter = null
        moviePlaylistAdapter = null

        // Clean up Stremio sources
        focusRecoveryHandler.removeCallbacksAndMessages(null)
        focusRecoveryRunnable = null
        sourceSwitchController.cancelSourceSwitchWait()
        stremioSources.clear()

        // Clear tab references
        seasonTabs.clear()
        movieTabs.clear()

        // Clear view listeners
        if (::seekbarOverlay.isInitialized) seekbarOverlay.setOnKeyListener(null)

        sendFinished()
        super.onDestroy()
        recordPlaybackLifecycle("activity_destroy_complete")
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
            sourceSwitchController.setupStremioSources()
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
        ottShowName = null

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
        stremioTvGuideController.updateStremioTvGuideHeader()
        sourceSwitchController.updateStremioQualityBadge()
        if (ottSkinInstalled) {
            ottSourcesButton?.visibility =
                if (stremioSources.isEmpty()) View.GONE else View.VISIBLE
        } else if (stremioSources.isNotEmpty()) {
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
        // This path replaces the payload WITHOUT passing playItem, so the
        // item-change release there never runs. A slot with no resume signal
        // would otherwise inherit the previous item's hold and file its stale
        // position against the new content. (A slot WITH a signal re-arms at
        // READY — armResumeHold supersedes unconditionally.)
        releaseResumeHold()
        hasEverBeenReady = false

        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .build()
        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(metadata)
            .build()

        player?.apply {
            subtitleTrackReadiness.onMediaReplacement()
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
        stremioTvGuideController.stremioTvChannelAdapter?.notifyDataSetChanged()
        if (hideGuideOnReady) {
            stremioTvGuideController.hideGuideWhenReady()
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // COMPANION OBJECT
    // ═══════════════════════════════════════════════════════════════

    companion object {
        const val PAYLOAD_KEY = "payload"
        private const val DECODER_LOG_TAG = "DEBRIFY_PLAYER_DECODER"
        // Resume hold (see resumeHoldTargetMs): landing tolerance (seeks
        // resolve to keyframes) and how long an unlanded target keeps
        // substituting before real playback wins.
        private const val RESUME_HOLD_TOLERANCE_MS = 10_000L
        private const val RESUME_HOLD_SETTLE_MS = 30_000L
        /**
         * When true, the dock buttons (Audio, Subs, Fill, Speed, Night, Shuffle) open the
         * unified Miller-columns menu instead of the individual dialogs/panels. Additive —
         * flip to false to restore the exact prior behaviour.
         */
        private const val USE_UNIFIED_MENU = true
        private const val PROGRESS_INTERVAL_MS = 5_000L
        private const val CONTROLS_AUTO_HIDE_DELAY_MS = 4000L
        private const val SEEK_STEP_MS = 10_000L
        private const val SEEK_LONG_PRESS_THRESHOLD = 3
        private const val BACK_PRESS_INTERVAL_MS = 2000L  // 2 seconds
        private const val PIKPAK_MAX_RETRIES = 5
        private const val PIKPAK_METADATA_TIMEOUT_MS = 10000  // 10 seconds to wait for metadata
        private const val PIKPAK_BASE_DELAY_MS = 2000  // 2 seconds base delay
        private const val PIKPAK_MAX_DELAY_MS = 18000  // 18 seconds max delay
    }
}
