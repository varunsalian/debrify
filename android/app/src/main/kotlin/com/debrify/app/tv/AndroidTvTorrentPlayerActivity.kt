package com.debrify.app.tv

import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import androidx.core.content.ContextCompat
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
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import androidx.recyclerview.widget.LinearLayoutManager
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
import com.debrify.app.util.LanguageMapper
import com.debrify.app.util.OffsetRenderersFactory
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleCueCache
import com.debrify.app.util.SubtitleFontManager
import com.debrify.app.util.SubtitleSettings
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
    private var offsetRenderersFactory: OffsetRenderersFactory? = null

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
    private var iptvCategories = mutableListOf<String>()
    private var iptvSourceId: String? = null
    private var iptvSourceName: String = "IPTV"
    private var iptvContentType: String = "live"
    private var iptvSelectedCategory: String? = null
    private var iptvBrowseToken = 0
    private var iptvWatchRegistrationToken = 0
    private val iptvBrowseHandler = Handler(Looper.getMainLooper())

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

    // Focus navigation state - prevents focus recovery from interfering with active navigation
    private var isNavigating = false
    private var navigationTargetPosition = -1
    private val focusRecoveryHandler = Handler(Looper.getMainLooper())
    private var focusRecoveryRunnable: Runnable? = null

    private val resizeModes = arrayOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM
    )

    private val resizeModeLabels = arrayOf("Fit", "Fill", "Zoom")

    private val playbackSpeeds = arrayOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    private val playbackSpeedLabels = arrayOf("0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x")

    private val nightModeGains = arrayOf(0, 500, 1000, 1500, 2000, 2500, 3000, 5000)  // millibels
    private val nightModeLabels = arrayOf("Off", "Low", "Medium", "High", "Higher", "Extreme", "Max", "Sleeping Baby")

    // Handlers
    private val progressHandler = Handler(Looper.getMainLooper())
    private val titleHandler = Handler(Looper.getMainLooper())
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
    private val bufferingHandler = Handler(Looper.getMainLooper())
    private var bufferingDebounceRunnable: Runnable? = null

    private val progressRunnable = object : Runnable {
        override fun run() {
            sendProgress(completed = false)
            maybeShowUpNext()
            progressHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    private val hideTitleRunnable = Runnable {
        titleContainer.animate().alpha(0f).setDuration(220).withEndAction {
            titleContainer.visibility = View.GONE
        }.start()
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
                    if (hasEverBeenReady) {
                        showBufferingIndicatorDebounced()
                    }
                }
                Player.STATE_ENDED -> {
                    hideBufferingIndicator()
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

                        // No next in playlist — request Quick Play next episode for series
                        val currentItem = model.items[currentIndex]
                        if (model.contentType == "series" && currentItem.season != null && currentItem.episode != null && model.imdbId != null) {
                            requestQuickPlayNextEpisode(model.imdbId!!, currentItem.season, currentItem.episode)
                        }
                        finish()
                    }
                }
            }
            updatePauseButtonLabel()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updatePauseButtonLabel()
        }

        override fun onPlayerError(error: PlaybackException) {
            // Stale-delivery gate for EVERY IPTV recovery path below: a
            // queued onPlayerError whose media item was already superseded
            // (a zap's or the watchdog's prepare() cleared the error) reports
            // playerError == null. Acting on one would attribute channel A's
            // failure to channel B — e.g. force-HLS-poisoning B's URL for the
            // whole session, or restarting A's stream under B's identity.
            val isLiveIptvError = isIptvMode && player?.playerError != null

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
            android.util.Log.e("AndroidTvPlayer", "Player error: ${error.errorCodeName}")
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
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
                handleMetadataUpdate(updatesJson, imdbId)
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

    private fun handleMetadataUpdate(updatesJson: String?, imdbId: String?) {
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
                val originalIndex = update.optInt("originalIndex", -1)
                if (originalIndex < 0 || originalIndex >= model.items.size) {
                    android.util.Log.w("TVMazeUpdate", "Skipping invalid originalIndex=$originalIndex (items.size=${model.items.size})")
                    skippedCount++
                    continue
                }

                val item = model.items[originalIndex]
                val newTitle: String? = if (update.has("title")) update.optString("title") else null
                val newDescription: String? = if (update.has("description")) update.optString("description") else null
                val newArtwork: String? = if (update.has("artwork")) update.optString("artwork") else null
                val newRating = if (update.has("rating")) update.optDouble("rating") else null

                // Create updated item with new metadata
                val updatedItem = item.copy(
                    title = if (!newTitle.isNullOrEmpty()) newTitle else item.title,
                    description = if (!newDescription.isNullOrEmpty()) newDescription else item.description,
                    artwork = if (!newArtwork.isNullOrEmpty()) newArtwork else item.artwork,
                    rating = newRating ?: item.rating
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

        bufferingIndicator = findViewById(R.id.android_tv_buffering_indicator)
        pikPakReactivationIndicator = findViewById(R.id.android_tv_pikpak_reactivation_indicator)
        pikPakReactivationText = findViewById(R.id.android_tv_pikpak_reactivation_text)

        // Stremio sources badge (the picker itself lives in the unified menu)
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

    private fun setupPlayer() {
        trackSelector = DefaultTrackSelector(this)

        // Get default language settings
        val defaultAudioLang = SubtitleSettings.getDefaultAudioLanguage(this)
        val defaultSubtitleLang = SubtitleSettings.getDefaultSubtitleLanguage(this)

        // Build track selector parameters with robust language matching
        val paramsBuilder = trackSelector?.buildUponParameters()
            ?.setPreferredAudioMimeType("audio/opus")
            ?.setIgnoredTextSelectionFlags(C.SELECTION_FLAG_DEFAULT)

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

        val baseRenderersFactory = DefaultRenderersFactory(this)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true)
        val renderersFactory = OffsetRenderersFactory(baseRenderersFactory)
            .also { offsetRenderersFactory = it }

        // Create HTTP data source factory with redirect support for HLS/live streams.
        // The browser UA rides in defaultRequestProperties, NOT setUserAgent:
        // media3 applies the userAgent field LAST in makeConnection, silently
        // clobbering any per-request User-Agent — which would break IPTV
        // channels that declare their own UA (injected via the resolver's
        // dataSpec headers, which override defaults in the merge).
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(15000)
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

        // Create media source factory that uses the data source
        val mediaSourceFactory = DefaultMediaSourceFactory(this)
            .setDataSourceFactory(finalDataSourceFactory)

        val playerBuilder = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector!!)
            .setMediaSourceFactory(mediaSourceFactory)
            .setHandleAudioBecomingNoisy(true)

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
        }

        player = playerBuilder.build()

        player?.addListener(playbackListener)
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
        // The sync offset is per-subtitle and in-memory: start this session at 0
        // and let SubtitleSettings scope it to whatever subtitle is on screen.
        SubtitleSettings.resetSyncOffset()
        SubtitleSettings.setActiveSubtitleIdentityProvider(this) { currentSubtitleIdentity() }
        applySubtitleSettings()

        playerView.setControllerAutoShow(false)
        playerView.resizeMode = resizeModes[resizeModeIndex]
        playerView.requestFocus()
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
            playlistView.adapter = null
            seasonTabsContainer.visibility = View.GONE
            return
        }

        when (model.contentType.lowercase(Locale.US)) {
            "series" -> setupSeriesPlaylist(items)
            else -> setupCollectionPlaylist(items)
        }

        setupPlaylistNavigation()
    }

    private fun setupSeriesPlaylist(items: List<PlaybackItem>) {
        val adapter = PlaylistAdapter(items) { index ->
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

        // Previous-episode button — IPTV episode lists only (GONE by default in
        // the layout; shown via updateIptvEpisodeControls when a previous
        // episode exists).
        prevButton?.setOnClickListener {
            hideControlsMenu()
            prevIptvEpisode()?.let { switchToIptvChannel(it) }
        }
        prevButton?.onFocusChangeListener = extendTimerOnFocus

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
    private fun playItem(index: Int, suppressTrakt: Boolean = false) {
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

        // Cancel any ongoing PikPak retry before starting new item
        cancelPikPakRetry()

        currentIndex = index
        val item = model.items[index]
        android.util.Log.d("AndroidTvPlayer", "playItem - item found: title=${item.title}, season=${item.season}, episode=${item.episode}, url=${item.url}, resumeId=${item.resumeId}")
        // Keep BOTH the local position and the remote tracker percent (the
        // payload field is the furthest of Trakt + Simkl); STATE_READY resumes
        // the FURTHER of the two (never backward). Suppress trackers during
        // auto-advance (binge starts the next episode fresh) and during a source
        // switch on the same content (must honour the captured live position).
        val autoAdvance = isAutoAdvancing
        isAutoAdvancing = false
        pendingSeekMs = item.resumePositionMs
        pendingItemTraktPercent =
            if (autoAdvance || suppressTrakt) 0.0 else (item.traktProgressPercent ?: 0.0)

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

            // No next in playlist — request Quick Play next episode for series
            val model = payload
            val currentItem = model?.items?.getOrNull(currentIndex)
            if (model != null && currentItem != null &&
                model.contentType == "series" && currentItem.season != null &&
                currentItem.episode != null && model.imdbId != null) {
                requestQuickPlayNextEpisode(model.imdbId!!, currentItem.season, currentItem.episode)
                finish()
            } else {
                Toast.makeText(this, "End of playlist", Toast.LENGTH_SHORT).show()
            }
        }
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

        // Always show simple mode by default (OTT mode only when controls menu visible)
        titleView.visibility = View.VISIBLE
        titleOttContainer.visibility = View.GONE

        channelBadge.visibility = View.GONE
        titleContainer.visibility = View.VISIBLE
        titleContainer.alpha = 1f
        titleHandler.removeCallbacks(hideTitleRunnable)
        titleHandler.postDelayed(hideTitleRunnable, TITLE_FADE_DELAY_MS)
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
        if (isIptvMode && iptvChannels.size > 1 &&
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
            // IPTV mode: UP opens the channel guide
            if (isIptvMode) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    showIptvGuide()
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
                it.play()
            }
        }
        updatePauseButtonLabel()
    }

    private fun showControlsMenu() {
        val overlay = controlsOverlay ?: return
        cancelScheduledHideControlsMenu()

        // The IPTV zap banner sits above everything (added last to the
        // content view) — clear it rather than let it cover the dock.
        hideIptvZapBanner()

        // Hide subtitles when controls menu is shown
        subtitleOverlay.visibility = View.GONE

        // Show title when controls menu is shown
        titleHandler.removeCallbacks(hideTitleRunnable)
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

        overlay.animate().cancel()

        if (!controlsMenuVisible) {
            overlay.visibility = View.GONE
            overlay.alpha = 0f
            overlay.translationY = 0f
            cancelScheduledHideControlsMenu()
            return
        }

        cancelScheduledHideControlsMenu()
        controlsMenuVisible = false

        // Hide title and revert to simple mode when controls hide
        titleHandler.removeCallbacks(hideTitleRunnable)
        titleContainer.animate()
            .alpha(0f)
            .setDuration(250)
            .withEndAction {
                titleContainer.visibility = View.GONE
                // Revert to simple mode for next title flash
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

        iptvSourceId = json.optString("sourceId").takeIf { it.isNotEmpty() }
        iptvSourceName = json.optString("sourceName").takeIf { it.isNotEmpty() } ?: "IPTV"
        iptvContentType = json.optString("contentType").takeIf {
            it in setOf("live", "vod", "series", "episodes")
        } ?: "live"
        iptvSelectedCategory =
            json.optString("selectedCategory").takeIf { it.isNotEmpty() }
        iptvSources = parseIptvSources(json.optJSONArray("sources"))
        iptvCategories = parseStringList(json.optJSONArray("categories"))

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

        // Override playlist button to show IPTV guide instead
        val playlistButton: AppCompatButton? = playerView.findViewById(R.id.debrify_playlist_button)
        playlistButton?.text = "Guide"
        playlistButton?.setOnClickListener {
            hideControlsMenu()
            toggleIptvGuide()
        }

        // Play initial channel
        if (iptvChannels.isNotEmpty()) {
            playIptvChannel(currentIptvIndex)
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
            name = name,
            url = url,
            logoUrl = logoUrl,
            group = group,
            isLive = normalizedType == "live",
            isCurrent = false,
            resumePositionMs = resumePositionMs,
            httpHeaders = headers,
            contentType = normalizedType,
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
        playerView.findViewById<View>(R.id.debrify_controls_buttons)
            ?.setBackgroundResource(R.drawable.iptv_premium_panel_bg)

        val buttons = listOfNotNull(
            audioButton,
            subtitleButton,
            aspectButton,
            pauseButton,
            speedButton,
            nightModeButton,
            iptvPrevButton,
            iptvNextButton,
            playerView.findViewById<AppCompatButton>(R.id.debrify_playlist_button),
        )
        buttons.forEach {
            it.setBackgroundResource(R.drawable.iptv_premium_button_bg)
            it.setTextColor(
                ContextCompat.getColorStateList(this, R.color.iptv_premium_button_text)
            )
        }

        iptvPrevButton?.apply {
            visibility = View.VISIBLE
            text = "CH -"
            setOnClickListener {
                hideControlsMenu()
                val previous = prevIptvEpisode()
                if (previous != null) switchToIptvChannel(previous) else zapIptvChannel(-1)
            }
        }
        iptvNextButton?.apply {
            visibility = View.VISIBLE
            text = "CH +"
            setOnClickListener {
                hideControlsMenu()
                val next = nextIptvEpisode()
                if (next != null) switchToIptvChannel(next) else zapIptvChannel(1)
            }
        }
        updateIptvControlPresentation(iptvChannels.getOrNull(currentIptvIndex))
    }

    private fun updateIptvControlPresentation(entry: IptvChannelEntry?) {
        val live = entry?.isLive != false
        val vodVisibility = if (live) View.GONE else View.VISIBLE
        cinemaProgressContainer?.visibility = vodVisibility
        debrifyTimeCurrent?.visibility = vodVisibility
        debrifyTimeTotal?.visibility = vodVisibility
        speedButton?.visibility = vodVisibility
        nightModeButton?.visibility = vodVisibility
        if (live) {
            cinemaSeekMode = false
            cinemaProgressThumb?.visibility = View.INVISIBLE
            cinemaSpeedIndicator?.visibility = View.GONE
            if (currentFocus == cinemaProgressContainer) {
                pauseButton?.requestFocus()
            }
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
                } else {
                    hideIptvGuide()
                    switchToIptvChannel(entry)
                }
            },
            onItemLongClick = { entry ->
                if (isIptvSeriesSentinel(entry)) {
                    Toast.makeText(
                        this,
                        "Open the series to choose an episode",
                        Toast.LENGTH_SHORT,
                    ).show()
                } else {
                    toggleIptvFavorite(entry)
                }
            },
            onEpgNeeded = { entry -> ensureIptvChannelEpg(entry) },
        )
        guideList.adapter = iptvChannelAdapter

        iptvEpgList?.layoutManager =
            LinearLayoutManager(this, LinearLayoutManager.VERTICAL, false)
        iptvEpgAdapter = IptvEpgAdapter(emptyList()) { program ->
            iptvEpgEntry?.let { entry -> requestIptvCatchup(entry, program) }
        }
        iptvEpgList?.adapter = iptvEpgAdapter

        val premiumButtonIds = intArrayOf(
            R.id.iptv_nav_browse,
            R.id.iptv_nav_search,
            R.id.iptv_nav_favorites,
            R.id.iptv_nav_continue,
            R.id.iptv_nav_sources,
            R.id.iptv_nav_close,
            R.id.iptv_source_button,
            R.id.iptv_category_button,
            R.id.iptv_mode_live,
            R.id.iptv_mode_movies,
            R.id.iptv_mode_series,
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
        findViewById<View>(R.id.iptv_nav_continue)?.visibility =
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
                    "${iptvBrowseChannels.size} items"
                } else {
                    "Press OK to search"
                }
            }
        })
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
            requestIptvBrowse(action = "browse")
        }
        findViewById<View>(R.id.iptv_nav_search)?.setOnClickListener {
            iptvGuideSearch?.requestFocus()
        }
        findViewById<View>(R.id.iptv_nav_favorites)?.setOnClickListener {
            val source = iptvSources.firstOrNull { it.isFavorites }
            if (source != null) selectIptvSource(source) else {
                Toast.makeText(this, "No favorites source", Toast.LENGTH_SHORT).show()
            }
        }
        findViewById<View>(R.id.iptv_nav_continue)?.setOnClickListener {
            val source = iptvSources.firstOrNull { it.isContinue }
            if (source != null) selectIptvSource(source) else {
                Toast.makeText(this, "Nothing in continue watching", Toast.LENGTH_SHORT).show()
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
        findViewById<View>(R.id.iptv_mode_movies)?.setOnClickListener {
            selectIptvContentType("vod")
        }
        findViewById<View>(R.id.iptv_mode_series)?.setOnClickListener {
            selectIptvContentType("series")
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
    }

    private fun isIptvSeriesSentinel(entry: IptvChannelEntry): Boolean =
        entry.contentType == "series" || entry.url.startsWith("xtream-series://")

    private fun showIptvGuide() {
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
        iptvGuideVisible = false
        hideIptvEpgPane()
        iptvGuideOverlay?.animate()?.cancel() // cancel any pending show animation
        iptvGuideOverlay?.animate()?.alpha(0f)?.setDuration(150)?.withEndAction {
            iptvGuideOverlay?.visibility = View.GONE
        }?.start()
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
        iptvGuideCountText?.text = "${iptvBrowseChannels.size} items"

        val modeButtons = listOf(
            "live" to findViewById<AppCompatButton>(R.id.iptv_mode_live),
            "vod" to findViewById<AppCompatButton>(R.id.iptv_mode_movies),
            "series" to findViewById<AppCompatButton>(R.id.iptv_mode_series),
        )
        modeButtons.forEach { (type, button) ->
            button?.isSelected = iptvContentType == type ||
                (iptvContentType == "episodes" && type == "series")
        }
    }

    private fun selectIptvContentType(contentType: String) {
        if (iptvContentType == contentType) return
        iptvContentType = contentType
        iptvSelectedCategory = null
        refreshIptvBrowserChrome()
        requestIptvBrowse(action = "browse")
    }

    private fun selectIptvSource(source: IptvSourceEntry) {
        iptvSourceId = source.id
        iptvSourceName = source.name
        iptvSelectedCategory = null
        iptvCategories.clear()
        iptvContentType = when {
            source.isContinue -> "vod"
            source.isFavorites -> "live"
            iptvContentType == "episodes" -> if (source.isXtream) "series" else "live"
            !source.isXtream && iptvContentType == "series" -> "live"
            else -> iptvContentType
        }
        iptvGuideSearch?.setText("")
        refreshIptvBrowserChrome()
        requestIptvBrowse(action = "browse")
    }

    private fun showIptvSourcePicker() {
        if (iptvSources.isEmpty()) return
        val options = iptvSources.map { it.name }
        AlertDialog.Builder(this)
            .setTitle("Choose source")
            .setItems(options.toTypedArray()) { _, index ->
                selectIptvSource(iptvSources[index])
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
        val searchInput = EditText(this).apply {
            id = View.generateViewId()
            setSingleLine(true)
            hint = "Search categories"
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_DONE
            setTextColor(Color.WHITE)
            setHintTextColor(0x80FFFFFF.toInt())
            setBackgroundResource(R.drawable.iptv_guide_search_bg)
            setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0)
            compoundDrawablePadding = dp(10)
            compoundDrawableTintList =
                android.content.res.ColorStateList.valueOf(0xB3FFFFFF.toInt())
            setPadding(dp(16), 0, dp(16), 0)
        }
        val statusText = TextView(this).apply {
            setPadding(dp(2), dp(12), dp(2), dp(8))
            setTextColor(0xB3FFFFFF.toInt())
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
        ) { category ->
            dialog.dismiss()
            iptvSelectedCategory = category.takeUnless { it == allLabel }
            refreshIptvBrowserChrome()
            requestIptvBrowse(action = "browse")
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
                setBackgroundResource(R.drawable.iptv_premium_button_bg)
                setTextColor(
                    ContextCompat.getColorStateList(
                        context,
                        R.color.iptv_premium_button_text,
                    ),
                )
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

    private fun requestIptvBrowse(
        action: String,
        query: String = iptvGuideSearch?.text?.toString()?.trim().orEmpty(),
        channelUrl: String? = null,
        title: String? = null,
        sourceIdOverride: String? = null,
    ) {
        val channel = MainActivity.getAndroidTvPlayerChannel() ?: return
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
                    if (token != iptvBrowseToken) return
                    iptvBrowseLoading?.visibility = View.GONE
                    val response = result as? Map<*, *> ?: return
                    val keepSearchFocus = iptvGuideSearch?.hasFocus() == true
                    val channels = parseIptvChannels(response["channels"] as? List<*> ?: emptyList<Any>())
                    val playingUrl = iptvChannels.getOrNull(currentIptvIndex)?.url
                    channels.forEach { it.isCurrent = it.url == playingUrl }
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
                    if (token != iptvBrowseToken) return
                    iptvBrowseLoading?.visibility = View.GONE
                    Toast.makeText(
                        this@AndroidTvTorrentPlayerActivity,
                        message ?: "Unable to load IPTV catalog",
                        Toast.LENGTH_SHORT,
                    ).show()
                }

                override fun notImplemented() {
                    if (token == iptvBrowseToken) iptvBrowseLoading?.visibility = View.GONE
                }
            },
        )
    }

    private fun toggleIptvFavorite(entry: IptvChannelEntry) {
        entry.isFavorite = !entry.isFavorite
        iptvChannelAdapter?.notifyFavoriteFor(entry)
        val args = hashMapOf<String, Any?>(
            "url" to entry.url,
            "name" to entry.name,
            "logoUrl" to entry.logoUrl,
            "group" to entry.group,
            "sourceId" to entry.sourceId,
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
        iptvEpgDayOffset = 0
        iptvEpgPrograms = emptyList()
        iptvEpgPanel?.visibility = View.VISIBLE
        iptvEpgLoading?.visibility = View.VISIBLE
        iptvEpgEmpty?.visibility = View.GONE
        iptvEpgList?.visibility = View.GONE
        iptvEpgChannelName?.text = entry.name
        iptvEpgChannelGroup?.text =
            listOfNotNull(entry.group, "Channel ${entry.index + 1}").joinToString(" · ")
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
                    hideIptvGuide()
                    resetSubtitleState()
                    beginIptvPlayback(replay)
                    titleView.text = replay.name
                    titleContainer.visibility = View.VISIBLE
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
            iptvGuideCurrentName?.text = ch.name
            iptvGuideNowPlaying?.visibility = View.VISIBLE

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

    private fun switchToIptvChannel(entry: IptvChannelEntry) {
        android.util.Log.d("AndroidTvPlayer", "switchToIptvChannel: ${entry.name} (index=${entry.index})")
        // Bank the outgoing channel's position BEFORE currentIptvIndex moves,
        // or zapping back to a half-watched movie would rewind it to wherever
        // it stood when the player was launched.
        checkpointCurrentIptvPosition()
        // A channel zap orphans any pending source-switch watcher (see playItem)
        dropStaleSourceSwitchFeedback()

        // Browsing can replace the source/category without replacing playback.
        // Adopt the visible result set only when the chosen row is outside the
        // active zap list, then normalize indices for CH +/- navigation.
        var selected = entry
        val adoptsBrowseList = iptvChannels.none { it === entry }
        if (adoptsBrowseList) {
            iptvChannels = iptvChannelAdapter?.entriesSnapshot()
                ?.mapIndexed { index, item -> item.apply { this.index = index } }
                ?.toMutableList()
                ?: mutableListOf(entry.apply { index = 0 })
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

        // Clear subtitle identity/results when changing channels from the guide.
        resetSubtitleState()

        // Persist on-demand metadata before playback so the progress row can
        // join Continue Watching even when this item was discovered in-player.
        beginIptvPlaybackAfterWatchRegistration(selected)

        // Update title
        titleView.text = selected.name
        titleContainer.visibility = View.VISIBLE

        // Channel-change feedback: the zap banner (name, now/next, key hints)
        // replaces the old bare-name overlay for every IPTV switch.
        showIptvZapBanner(selected)

        updateIptvGuideCurrentName()
        // Index moved — a previous episode may have (dis)appeared.
        updateIptvEpisodeControls()
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
        isIptvMode && !controlsMenuVisible && iptvChannels.size > 1 &&
            iptvChannels.getOrNull(currentIptvIndex)?.isLive == true

    /** Fullscreen channel zap: previous/next channel in guide order,
     *  wrapping at the ends. */
    private fun zapIptvChannel(delta: Int) {
        if (iptvChannels.size < 2) return
        val from = currentIptvIndex.coerceIn(0, iptvChannels.lastIndex)
        val next = (from + delta + iptvChannels.size) % iptvChannels.size
        switchToIptvChannel(iptvChannels[next])
    }

    // ── IPTV zap banner ──────────────────────────────────────────────────
    // Fullscreen channel-change feedback: channel identity, what's airing
    // now (with a progress bar) and next, plus the key hints that make
    // zapping and the guide discoverable at all. Built in code and attached
    // to the content view on first use; EPG fields ride the same
    // ensureIptvChannelEpg flow the guide rows use, so a banner appearance
    // also warms the guide's data.

    private var iptvZapBanner: LinearLayout? = null
    private var iptvZapBannerName: TextView? = null
    private var iptvZapBannerMeta: TextView? = null
    private var iptvZapBannerNow: TextView? = null
    private var iptvZapBannerNext: TextView? = null
    private var iptvZapBannerHint: TextView? = null
    private var iptvZapBannerProgress: android.widget.ProgressBar? = null
    private val iptvZapBannerHideToken = Any()

    private fun ensureIptvZapBanner(): LinearLayout {
        iptvZapBanner?.let { return it }
        val accent = Color.parseColor("#00E5FF")

        fun label(size: Float, alpha: Int, bold: Boolean = false) =
            TextView(this).apply {
                textSize = size
                setTextColor(Color.argb(alpha, 255, 255, 255))
                if (bold) typeface = Typeface.DEFAULT_BOLD
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }

        val name = label(19f, 255, bold = true)
        val meta = label(11.5f, 150)
        val now = label(13.5f, 230).apply { visibility = View.GONE }
        val next = label(12f, 155).apply { visibility = View.GONE }
        val hint = label(10f, 115).apply { letterSpacing = 0.06f }
        val bar = android.widget.ProgressBar(
            this, null, android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 1000
            progressTintList =
                android.content.res.ColorStateList.valueOf(accent)
            progressBackgroundTintList = android.content.res.ColorStateList
                .valueOf(Color.argb(46, 255, 255, 255))
            visibility = View.GONE
        }

        val banner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(15), dp(24), dp(14))
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(Color.argb(234, 11, 13, 23))
                setStroke(dp(1), Color.argb(28, 255, 255, 255))
            }
            elevation = dp(8).toFloat()
            visibility = View.GONE
        }
        fun add(view: View, topDp: Int, height: Int = ViewGroup.LayoutParams.WRAP_CONTENT) {
            banner.addView(
                view,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, height
                ).apply { topMargin = dp(topDp) },
            )
        }
        add(name, 0)
        add(meta, 2)
        add(now, 10)
        add(bar, 7, dp(3))
        add(next, 7)
        add(hint, 12)

        val root = findViewById<ViewGroup>(android.R.id.content)
        root.addView(
            banner,
            android.widget.FrameLayout.LayoutParams(
                dp(430), ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = android.view.Gravity.BOTTOM or android.view.Gravity.START
                leftMargin = dp(28)
                bottomMargin = dp(28)
            },
        )

        iptvZapBanner = banner
        iptvZapBannerName = name
        iptvZapBannerMeta = meta
        iptvZapBannerNow = now
        iptvZapBannerNext = next
        iptvZapBannerHint = hint
        iptvZapBannerProgress = bar
        return banner
    }

    private fun showIptvZapBanner(entry: IptvChannelEntry) {
        // Never over the guide: a zap from inside the guide updates the
        // guide's own header instead, and the banner would otherwise paint
        // on top of the list (it's the topmost child of the content view).
        if (iptvGuideVisible) return
        val banner = ensureIptvZapBanner()
        iptvZapBannerName?.text = entry.name
        val meta = buildList {
            // "CH" reads wrong on an episode/movie list — plain position there.
            add(
                if (entry.isLive) "CH ${entry.index + 1}/${iptvChannels.size}"
                else "${entry.index + 1} of ${iptvChannels.size}"
            )
            entry.group?.takeIf { it.isNotEmpty() }?.let { add(it) }
        }.joinToString("   •   ")
        iptvZapBannerMeta?.text = meta
        // LEFT/RIGHT only zap on live channels — don't teach it on episode/
        // movie lists, where those keys still seek.
        iptvZapBannerHint?.text =
            if (entry.isLive) "◀ ▶  Channel      ▲  Guide" else "▲  Guide"
        paintIptvZapBannerEpg(entry) // whatever is already known paints now
        // The same lazy fetch the guide rows use — a fresh answer repaints
        // the banner via the isCurrent hook in ensureIptvChannelEpg.
        ensureIptvChannelEpg(entry)

        banner.animate().cancel()
        banner.visibility = View.VISIBLE
        banner.alpha = 0f
        banner.animate().alpha(1f).setDuration(160).start()
        progressHandler.removeCallbacksAndMessages(iptvZapBannerHideToken)
        progressHandler.postAtTime(
            { hideIptvZapBanner() },
            iptvZapBannerHideToken,
            android.os.SystemClock.uptimeMillis() + 4500,
        )
    }

    private fun hideIptvZapBanner() {
        val banner = iptvZapBanner ?: return
        banner.animate().cancel()
        banner.animate().alpha(0f).setDuration(180).withEndAction {
            banner.visibility = View.GONE
        }.start()
    }

    /** Paint the banner's now/next lines from [entry]'s EPG fields. */
    private fun paintIptvZapBannerEpg(entry: IptvChannelEntry) {
        val nowView = iptvZapBannerNow ?: return
        val nextView = iptvZapBannerNext ?: return
        val bar = iptvZapBannerProgress ?: return
        val nowTitle = entry.epgNowTitle
        if (entry.isLive && nowTitle != null) {
            nowView.text =
                "${formatEpgTime(entry.epgNowStartMs)} – " +
                    "${formatEpgTime(entry.epgNowStopMs)}    $nowTitle"
            nowView.visibility = View.VISIBLE
            val total = entry.epgNowStopMs - entry.epgNowStartMs
            if (total > 0) {
                val frac = (System.currentTimeMillis() - entry.epgNowStartMs)
                    .toDouble() / total
                bar.progress = (frac.coerceIn(0.0, 1.0) * 1000).toInt()
                bar.visibility = View.VISIBLE
            } else {
                bar.visibility = View.GONE
            }
        } else {
            nowView.visibility = View.GONE
            bar.visibility = View.GONE
        }
        val nextTitle = entry.epgNextTitle
        if (entry.isLive && nextTitle != null) {
            val at = if (entry.epgNextStartMs > 0) {
                "${formatEpgTime(entry.epgNextStartMs)}  "
            } else ""
            nextView.text = "Next:  $at$nextTitle"
            nextView.visibility = View.VISIBLE
        } else {
            nextView.visibility = View.GONE
        }
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

        // Show title briefly
        titleView.text = entry.name
        titleOttContainer.visibility = View.GONE
        titleContainer.visibility = View.VISIBLE

        // First tune on a live channel: the zap banner doubles as the "here's
        // what's on" card and teaches the zap/guide keys — without it, EPG
        // exists only inside a guide overlay nobody knows how to open.
        if (entry.isLive) showIptvZapBanner(entry)
    }

    // ── IPTV episode navigation (series/VOD lists) ──────────────────────────

    /** This IPTV session is an Xtream SERIES episode list. Scoped to series
     *  (the launcher sets seriesAudioKey only then) — NOT every non-live item —
     *  so a plain Movies-grid play keeps the guide only, with no Next/Previous
     *  or auto-advance, exactly as before. */
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

    /** Manage the episode controls ONLY for a series session: show Previous
     *  when a previous episode exists, and hide Next at the last episode. For
     *  every other flow (non-series IPTV, movies, torrent playlists) the
     *  controls are left exactly as they were — no regression. */
    private fun updateIptvEpisodeControls() {
        updateIptvControlPresentation(iptvChannels.getOrNull(currentIptvIndex))
        val seriesSession = isIptvMode && iptvSeriesAudioKey != null
        if (!seriesSession) {
            if (isIptvMode) {
                iptvPrevButton?.text = "CH -"
                iptvNextButton?.text = "CH +"
                val visible = if (iptvChannels.size > 1) View.VISIBLE else View.GONE
                iptvPrevButton?.visibility = visible
                iptvNextButton?.visibility = visible
            }
            return
        }
        iptvPrevButton?.text = "EP -"
        iptvNextButton?.text = "EP +"
        iptvPrevButton?.visibility =
            if (prevIptvEpisode() != null) View.VISIBLE else View.GONE
        iptvNextButton?.visibility =
            if (nextIptvEpisode() != null) View.VISIBLE else View.GONE
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
        val metadata = MediaMetadata.Builder()
            .setTitle(entry.name)
            .setArtist(entry.group ?: "IPTV")
            .build()

        // The channel's own headers ride every request from here on (the
        // resolver installed in setupPlayer reads this per request). Set
        // BEFORE the media item so the first playlist fetch already has them.
        currentIptvHttpHeaders = entry.httpHeaders
        currentIptvStreamUrl = streamUrl

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
        iptvHlsForcedUrls.add(url)
        setIptvMediaItem(entry, url)
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
            setIptvMediaItem(entry, entry.url)
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
            mrow("Sources", value = if (stremioSources.isNotEmpty()) "${stremioSources.size}" else null),
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
        UnifiedMenuSections.appearanceRows(this) { applySubtitleSettings() }

    private fun umTimingRows(): List<UnifiedMenuController.Row> {
        val ctx = this
        val ms = SubtitleSettings.getSyncOffsetMs(ctx)
        // Sync needs the subtitle on screen to judge alignment, which a bottom menu
        // column covers — so this opens the dedicated over-video sync overlay
        // (slider for embedded subs, "tap the line" picker for downloaded subs).
        // Single launcher — the overlay itself owns reset (OK on the slider /
        // hold-OK on the picker), which also clears the picker's remembered line.
        return listOf(
            mrow("Adjust timing  ▸", value = SubtitleSettings.formatSyncOffset(ms),
                swatch = SubtitleSettings.getSyncOffsetColor(ms), accent = true, onOk = {
                    unifiedMenu?.hide(); showSyncOverlay()
                })
        )
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
                playerView.resizeMode = resizeModes[resizeModeIndex]
                updateAspectButtonLabel()
            })
        }
        return UnifiedMenuController.Model(col1, "DISPLAY", col2, "Aspect ratio", col3)
    }

    // ── Playback ────────────────────────────────────────────────────────────
    private fun umPlaybackModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val col2 = listOf(
            mrow("Playback speed", value = playbackSpeedLabels.getOrNull(playbackSpeedIndex), tag = "speed"),
            mrow("Shuffle & autoplay", tag = "shuffle")
        )
        val tag = col2.getOrNull(col2Index)?.tag
        val (title, col3) = if (tag == "shuffle") {
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
        override fun onSettingsChanged() { applySubtitleSettings() }
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
        showStatusPillTransient("✓ ${subtitle.displayName}")
        android.util.Log.d("StremioSubs", "Side-rendering ${cues.size} cues from ${subtitle.displayName}")
    }

    /** Stop side-rendering and give the overlay back to the player's onCues. */
    private fun stopExternalSubtitleRendering() {
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

    // Aspect ratio
    private fun cycleAspectRatio() {
        resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size
        playerView.resizeMode = resizeModes[resizeModeIndex]
        updateAspectButtonLabel()
        Toast.makeText(this, "Aspect: ${resizeModeLabels[resizeModeIndex]}", Toast.LENGTH_SHORT).show()
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
            val prefs = getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)

            // Load aspect index for TV (separate from mobile)
            // TV only: 0=Fit, 1=Fill, 2=Zoom (default: 0=Fit)
            resizeModeIndex = prefs.getLong("flutter.player_default_aspect_index_tv", 0L).toInt()
                .coerceIn(0, resizeModes.lastIndex)

            // Load night mode index (default: 0 = Off)
            nightModeIndex = prefs.getLong("flutter.player_night_mode_index", 0L).toInt()
                .coerceIn(0, nightModeGains.lastIndex)

            // Announce our audio session to system effect apps (default: off)
            systemAudioEffectsEnabled = prefs.getBoolean("flutter.player_system_audio_effects", false)

            android.util.Log.d("AndroidTvPlayer", "Loaded defaults - aspect=$resizeModeIndex, nightMode=$nightModeIndex, audioEffects=$systemAudioEffectsEnabled")
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

        // Badge opens the unified menu's Sources section — the single picker,
        // landing on the tab that holds the currently playing source.
        stremioSourceBadge?.setOnClickListener {
            hideControlsMenu()
            unifiedMenu?.show("sources", currentSourcesTab())
        }
    }

    /** col2 tag of the tab containing the current source (null → default). */
    private fun currentSourcesTab(): String? {
        val current = stremioSources.getOrNull(currentStremioSourceIndex) ?: return null
        if (!seriesSourceTabs) return if (current.isDirectStream) "direct" else "torrent"
        return when {
            current.isDirectStream -> "direct"
            current.isSeasonPack -> "packs"
            else -> "episodes"
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
    }

    private fun failMoreTorrentSources(alreadyCleared: Boolean = false) {
        if (!alreadyCleared) moreSourcesLoadingMode = null
        showStatusPillTransient("Couldn't load more sources")
        unifiedMenu?.render()
    }

    private fun switchToSourcePlaylist(sourceIndex: Int, rawItems: List<*>) {
        android.util.Log.d("AndroidTvPlayer", "switchToSourcePlaylist: sourceIndex=$sourceIndex, rawItems=${rawItems.size}")

        val model = payload ?: return

        // Capture playback position + current item identity so the new source
        // resumes the same content instead of restarting from the beginning.
        val resumePositionMs = (player?.currentPosition ?: 0L).coerceAtLeast(0L)
        val currentItem = model.items.getOrNull(currentIndex)
        val resumeSeason = currentItem?.season
        val resumeEpisode = currentItem?.episode

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
            matchedSameContent = true
        } else if (resumeSeason != null && resumeEpisode != null) {
            val matched = newItems.indexOfFirst {
                it.season == resumeSeason && it.episode == resumeEpisode
            }
            if (matched >= 0) {
                targetIndex = matched
                matchedSameContent = true
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

        // Flash title to indicate source switch
        val currentSource = stremioSources.getOrNull(sourceIndex)
        if (currentSource != null) {
            titleView.text = currentSource.displayTitle
            titleView.visibility = View.VISIBLE
            titleOttContainer.visibility = View.GONE
            titleContainer.visibility = View.VISIBLE
            titleContainer.alpha = 1f
            titleHandler.removeCallbacks(hideTitleRunnable)
            titleHandler.postDelayed(hideTitleRunnable, TITLE_FADE_DELAY_MS)
        }

        // Resume the previously-playing item; the captured position is carried
        // on the item above as resumePositionMs. Suppress tracker/startAt percent
        // seeks so they can't override our explicit resume position — but ONLY
        // when the new source landed on the SAME content: a fallback episode
        // (exact episode missing from the new source) has no captured position
        // and must keep its own per-episode tracker resume, matching the Dart
        // player's landedOnSameContent behaviour.
        percentSeekApplied = true
        playItem(targetIndex, suppressTrakt = matchedSameContent)

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

        // Flash title to indicate source switch
        val currentSource = stremioSources.getOrNull(sourceIndex)
        if (currentSource != null) {
            titleView.text = currentSource.displayTitle
            titleView.visibility = View.VISIBLE
            titleOttContainer.visibility = View.GONE
            titleContainer.visibility = View.VISIBLE
            titleContainer.alpha = 1f
            titleHandler.removeCallbacks(hideTitleRunnable)
            titleHandler.postDelayed(hideTitleRunnable, TITLE_FADE_DELAY_MS)
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

            // Series source tabs: pack/episode split + per-tab "Load more"
            // availability. Parsed unconditionally (defaults off) so a
            // relaunch/next-episode payload can never inherit stale state.
            seriesSourceTabs = obj.optBoolean("seriesSourceTabs", false)
            seriesPacksFetched = obj.optBoolean("seriesPacksFetched", true)
            seriesEpisodesFetched = obj.optBoolean("seriesEpisodesFetched", true)
            movieMoreSources = obj.optBoolean("movieMoreSources", false)
            movieSourcesFetched = obj.optBoolean("movieSourcesFetched", true)
            moreSourcesLoadingMode = null

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
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "parsePayload failed", e)
            null
        }
    }

    override fun onStart() {
        super.onStart()
        player?.play()
        // Resume the side-rendered subtitle ticker paused in onStop.
        if (externalSubtitleActive) startExternalSubtitleTicker()
    }

    override fun onStop() {
        super.onStop()
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

    override fun onResume() {
        super.onResume()
        ActivityTracker.currentActivity = this
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
        // Clean up seek feedback manager
        if (::seekFeedbackManager.isInitialized) {
            seekFeedbackManager.destroy()
        }

        iptvBrowseHandler.removeCallbacksAndMessages(null)
        iptvEpgToken++

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

        // Clear all handlers
        progressHandler.removeCallbacksAndMessages(null)
        titleHandler.removeCallbacksAndMessages(null)
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
        private const val TITLE_FADE_DELAY_MS = 4000L
        private const val CONTROLS_AUTO_HIDE_DELAY_MS = 4000L
        private const val SEEK_STEP_MS = 10_000L
        private const val SEEK_LONG_PRESS_THRESHOLD = 3
        private const val BACK_PRESS_INTERVAL_MS = 2000L  // 2 seconds
        private const val SEARCH_SUBTITLE_LABEL = "Search Movie/Show Subtitles"
        private const val SUBTITLE_LOADING_LABEL = "⏳ Loading external subtitles..."
        private const val EXTERNAL_SUBTITLE_TICK_MS = 250L
        private const val EXTERNAL_SUBTITLE_PREFIX = "⬇"

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
            val lower = name.lowercase()
            return when {
                lower.contains("2160p") || lower.contains("4k") || lower.contains("uhd") -> "4K"
                lower.contains("1080p") || lower.contains("1080i") -> "1080p"
                lower.contains("720p") -> "720p"
                lower.contains("480p") || lower.contains("sd") -> "480p"
                else -> "HD"
            }
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
    // key is named traktProgressPercent, but Flutter sends the furthest of Trakt
    // and Simkl. Display-only fallback for the playlist bar and a resume source
    // when there's no local position.
    val traktProgressPercent: Double? = null,
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
}

private class PlaylistAdapter(
    private val items: List<PlaybackItem>,
    private val onItemClick: (Int) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>(), PlaylistOverlayAdapter {
    private var activeItemIndex = -1
    private val listItems = mutableListOf<PlaylistListItem>()
    private var selectedSeason: Int? = null

    val availableSeasons: List<Int> by lazy {
        items.mapNotNull { it.season }.distinct().sorted()
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

        // Group episodes by season
        val grouped = items.groupBy { it.season ?: 0 }
        val sortedSeasons = grouped.keys.sorted()

        for (season in sortedSeasons) {
            // Skip seasons that don't match filter
            if (filterSeason != null && season != filterSeason) {
                continue
            }

            val episodesInSeason = grouped[season] ?: continue

            // Don't show season header when filtering (tabs show the season)
            // Only show header when showing all seasons
            if (filterSeason == null && season > 0) {
                listItems.add(PlaylistListItem.SeasonHeader(season, episodesInSeason.size))
            }

            // Sort episodes by episode number (integer comparison to avoid "1", "10", "11", "2" string sorting)
            val sortedEpisodes = episodesInSeason.sortedBy { it.episode ?: 0 }
            for (episode in sortedEpisodes) {
                val originalIndex = items.indexOf(episode)
                listItems.add(PlaylistListItem.Episode(originalIndex))
            }
        }
    }

    override fun getItemViewType(position: Int): Int {
        return when (listItems[position]) {
            is PlaylistListItem.SeasonHeader -> VIEW_TYPE_HEADER
            is PlaylistListItem.Episode -> VIEW_TYPE_EPISODE
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
    var sourceId: String? = null,
    var sourceName: String? = null,
    var isFavorite: Boolean = false,
    val seriesId: String? = null,
    val seriesName: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val hasNextEpisode: Boolean? = null,
)

@androidx.annotation.OptIn(UnstableApi::class)
private class IptvChannelAdapter(
    private var channels: MutableList<IptvChannelEntry>,
    private val onItemClick: (IptvChannelEntry) -> Unit,
    private val onItemLongClick: ((IptvChannelEntry) -> Unit)? = null,
    // Fired from bind for live rows without (fresh) EPG — the activity
    // fetches over the bridge and answers with notifyEpgFor. Bind-driven, so
    // only rows that actually come on screen ever cost a request.
    private val onEpgNeeded: ((IptvChannelEntry) -> Unit)? = null,
) : RecyclerView.Adapter<IptvChannelAdapter.ViewHolder>() {

    companion object {
        private val ACCENT = Color.parseColor("#00E5FF")
        private val ACCENT_DIM = Color.parseColor("#CC00E5FF")
        const val PAYLOAD_EPG = "epg"
    }

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val number: TextView = view.findViewById(R.id.iptv_channel_number)
        val logo: android.widget.ImageView = view.findViewById(R.id.iptv_channel_logo)
        val letter: TextView = view.findViewById(R.id.iptv_channel_letter)
        val name: TextView = view.findViewById(R.id.iptv_channel_name)
        val group: TextView = view.findViewById(R.id.iptv_channel_group)
        val epg: TextView = view.findViewById(R.id.iptv_channel_epg)
        val favorite: TextView = view.findViewById(R.id.iptv_channel_favorite)
        val liveBadge: View = view.findViewById(R.id.iptv_channel_live_badge)
        val nowBadge: TextView = view.findViewById(R.id.iptv_channel_now_badge)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_iptv_channel, parent, false)
        return ViewHolder(view)
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
        holder.number.text = (entry.index + 1).toString()
        holder.number.setTextColor(
            if (entry.isCurrent) Color.argb(204, 0, 229, 255) // accent 80%
            else Color.argb(46, 255, 255, 255) // 18%
        )

        // Name
        holder.name.text = entry.name
        holder.name.setTextColor(
            if (entry.isCurrent) ACCENT else Color.argb(217, 255, 255, 255)
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

    fun updateChannels(filtered: List<IptvChannelEntry>) {
        channels.clear()
        channels.addAll(filtered)
        notifyDataSetChanged()
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
        return ViewHolder(view)
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
        holder.progress.visibility = if (airing) View.VISIBLE else View.GONE
        holder.progress.progress =
            ((elapsed.coerceIn(0L, duration) * 1000L) / duration).toInt()
        holder.itemView.alpha =
            if (program.stopMs < nowMs && !replayable) 0.55f else 1f
        holder.itemView.setOnClickListener {
            if (replayable) onReplay(program)
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
