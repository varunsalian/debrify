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
            override fun isCleanPlaybackState(): Boolean = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.isCleanPlaybackState()
            override fun canShuffleWholeShow(): Boolean = this@AndroidTvTorrentPlayerActivity.canShuffleWholeShow()
            override fun pickShuffleIndex(): Int? = this@AndroidTvTorrentPlayerActivity.pickShuffleIndex()
            override fun getNextPlayableIndex(i: Int): Int? = this@AndroidTvTorrentPlayerActivity.playlistController.getNextPlayableIndex(i)
            override fun playItem(index: Int) = this@AndroidTvTorrentPlayerActivity.playItem(index)
        },
    )
    private lateinit var skipSegmentButton: AppCompatButton
    private val playlistController: TvPlaylistOverlayController = TvPlaylistOverlayController(
        this,
        object : TvPlaylistOverlayController.Host {
            override val controlsSkin: TvControlsSkin get() = this@AndroidTvTorrentPlayerActivity.controlsSkin
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override fun dp(value: Int): Int { return this@AndroidTvTorrentPlayerActivity.dp(value) }
            override val hasPlaylistResolver: Boolean get() = this@AndroidTvTorrentPlayerActivity.hasPlaylistResolver
            override val ottShowName: String? get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottShowName
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override fun playItem(index: Int): Unit { return this@AndroidTvTorrentPlayerActivity.playItem(index) }
            override val playlistOverlay: View get() = this@AndroidTvTorrentPlayerActivity.playlistOverlay
            override val playlistView: RecyclerView get() = this@AndroidTvTorrentPlayerActivity.playlistView
            override val seasonTabsContainer: LinearLayout get() = this@AndroidTvTorrentPlayerActivity.seasonTabsContainer
            override val sourceFetchController: TvSourceFetchController get() = this@AndroidTvTorrentPlayerActivity.sourceFetchController
        },
    )

    // Seekbar
    private lateinit var seekbarOverlay: View
    private lateinit var seekbarProgress: View
    private lateinit var seekbarHandle: View
    private lateinit var seekbarCurrentTime: TextView
    private lateinit var seekbarTotalTime: TextView
    private lateinit var seekbarSpeedIndicator: TextView
    private val controlsOverlayController: TvControlsOverlayController = TvControlsOverlayController(
        this,
        object : TvControlsOverlayController.Host {
            override val channelBadge: TextView get() = this@AndroidTvTorrentPlayerActivity.channelBadge
            override val controlsDockController: TvControlsDockController get() = this@AndroidTvTorrentPlayerActivity.controlsDockController
            override val controlsSkin: TvControlsSkin get() = this@AndroidTvTorrentPlayerActivity.controlsSkin
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override val dockSkinSpec: DockSkinSpec? get() = this@AndroidTvTorrentPlayerActivity.dockSkinSpec
            override val iptvChannels: List<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvGuideController: TvIptvGuideController get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController
            override val iptvLiveRecovery: IptvLiveRecovery get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.iptvLiveRecovery
            override val iptvZapBannerController: TvIptvZapBannerController get() = this@AndroidTvTorrentPlayerActivity.iptvZapBannerController
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override var lastRealPositionMs: Long
                get() = this@AndroidTvTorrentPlayerActivity.lastRealPositionMs
                set(value) { this@AndroidTvTorrentPlayerActivity.lastRealPositionMs = value }
            override val linePickerOverlay: SubtitleLinePickerController? get() = this@AndroidTvTorrentPlayerActivity.linePickerOverlay
            override var maxStableDurationMs: Long
                get() = this@AndroidTvTorrentPlayerActivity.maxStableDurationMs
                set(value) { this@AndroidTvTorrentPlayerActivity.maxStableDurationMs = value }
            override val nextBackdrop: android.widget.ImageView get() = this@AndroidTvTorrentPlayerActivity.nextBackdrop
            override val nextBackdropReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.nextBackdropReady
            override val nextOverlay: View get() = this@AndroidTvTorrentPlayerActivity.nextOverlay
            override val nextSubtext: TextView get() = this@AndroidTvTorrentPlayerActivity.nextSubtext
            override val nextText: TextView get() = this@AndroidTvTorrentPlayerActivity.nextText
            override val ottEpisodeBadge: TextView get() = this@AndroidTvTorrentPlayerActivity.ottEpisodeBadge
            override val ottEpisodeTitle: TextView get() = this@AndroidTvTorrentPlayerActivity.ottEpisodeTitle
            override val ottRating: TextView get() = this@AndroidTvTorrentPlayerActivity.ottRating
            override val ottRatingContainer: View get() = this@AndroidTvTorrentPlayerActivity.ottRatingContainer
            override val ottSkinInstalled: Boolean get() = this@AndroidTvTorrentPlayerActivity.ottSkinInstalled
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val pikPakReactivationIndicator: View get() = this@AndroidTvTorrentPlayerActivity.pikPakReactivationIndicator
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override val playlistController: TvPlaylistOverlayController get() = this@AndroidTvTorrentPlayerActivity.playlistController
            override fun releaseResumeHold(): Unit { return this@AndroidTvTorrentPlayerActivity.releaseResumeHold() }
            override fun restoreParkedIptvTwinIfNeeded(): Boolean { return this@AndroidTvTorrentPlayerActivity.iptvTuneController.trial.restoreParkedIptvTwinIfNeeded() }
            override val seekFeedbackManager: SeekFeedbackManager get() = this@AndroidTvTorrentPlayerActivity.seekFeedbackManager
            override val seekbarCurrentTime: TextView get() = this@AndroidTvTorrentPlayerActivity.seekbarCurrentTime
            override val seekbarHandle: View get() = this@AndroidTvTorrentPlayerActivity.seekbarHandle
            override val seekbarOverlay: View get() = this@AndroidTvTorrentPlayerActivity.seekbarOverlay
            override val seekbarProgress: View get() = this@AndroidTvTorrentPlayerActivity.seekbarProgress
            override val seekbarSpeedIndicator: TextView get() = this@AndroidTvTorrentPlayerActivity.seekbarSpeedIndicator
            override val seekbarTotalTime: TextView get() = this@AndroidTvTorrentPlayerActivity.seekbarTotalTime
            override val skipSegmentController: TvSkipSegmentController get() = this@AndroidTvTorrentPlayerActivity.skipSegmentController
            override var sleepStopLatched: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.sleepStopLatched
                set(value) { this@AndroidTvTorrentPlayerActivity.sleepStopLatched = value }
            override val sourceBrowser: TvSourceBrowserController? get() = this@AndroidTvTorrentPlayerActivity.sourceBrowser
            override val sourceSwitchController: TvSourceSwitchController get() = this@AndroidTvTorrentPlayerActivity.sourceSwitchController
            override val startupGateView: View get() = this@AndroidTvTorrentPlayerActivity.startupGateView
            override val startupGateViewReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.startupGateViewReady
            override val stremioSourceBadge: View? get() = this@AndroidTvTorrentPlayerActivity.stremioSourceBadge
            override val stremioSources: List<StremioSource> get() = this@AndroidTvTorrentPlayerActivity.stremioSources
            override val stremioTvGuideController: TvStremioTvGuideController get() = this@AndroidTvTorrentPlayerActivity.stremioTvGuideController
            override val subtitleControlsLift: SubtitleControlsLiftController get() = this@AndroidTvTorrentPlayerActivity.subtitleControlsLift
            override val subtitlePanel: SubtitlePanelController? get() = this@AndroidTvTorrentPlayerActivity.subtitlePanel
            override val syncOverlay: SubtitleSyncOverlayController? get() = this@AndroidTvTorrentPlayerActivity.syncOverlay
            override val titleContainer: View get() = this@AndroidTvTorrentPlayerActivity.titleContainer
            override val titleOttContainer: View get() = this@AndroidTvTorrentPlayerActivity.titleOttContainer
            override val titleView: TextView get() = this@AndroidTvTorrentPlayerActivity.titleView
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
        },
    )
    private val startupGateViewReady: Boolean get() = ::startupGateView.isInitialized
    private val nextBackdropReady: Boolean get() = ::nextBackdrop.isInitialized
    private val controlsDockController: TvControlsDockController = TvControlsDockController(
        this,
        object : TvControlsDockController.Host {
            override fun cancelScheduledHideControlsMenu(): Unit { return this@AndroidTvTorrentPlayerActivity.controlsOverlayController.cancelScheduledHideControlsMenu() }
            override var cinemaProgressBackground: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressBackground
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressBackground = value }
            override var cinemaProgressBuffered: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressBuffered
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressBuffered = value }
            override var cinemaProgressContainer: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressContainer
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressContainer = value }
            override var cinemaProgressThumb: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressThumb
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaProgressThumb = value }
            override var cinemaSeekMode: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaSeekMode
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaSeekMode = value }
            override var cinemaSeekWasPlaying: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaSeekWasPlaying
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaSeekWasPlaying = value }
            override var cinemaSpeedIndicator: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaSpeedIndicator
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.cinemaSpeedIndicator = value }
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsMenuVisible
            override var controlsOverlay: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsOverlay
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsOverlay = value }
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override var debrifyProgressLine: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyProgressLine
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyProgressLine = value }
            override var debrifyTimeCurrent: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyTimeCurrent
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyTimeCurrent = value }
            override var debrifyTimeDisplay: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyTimeDisplay
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyTimeDisplay = value }
            override var debrifyTimeTotal: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyTimeTotal
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.debrifyTimeTotal = value }
            override val displayController: TvPlaybackDisplayController get() = this@AndroidTvTorrentPlayerActivity.displayController
            override val dockSkinSpec: DockSkinSpec? get() = this@AndroidTvTorrentPlayerActivity.dockSkinSpec
            override fun dp(value: Int): Int { return this@AndroidTvTorrentPlayerActivity.dp(value) }
            override val guideStyle: GuideStyle get() = this@AndroidTvTorrentPlayerActivity.guideStyle
            override val guideTokens: GuideTokens? get() = this@AndroidTvTorrentPlayerActivity.guideTokens
            override fun guideTypeface(file: String?): Typeface? { return this@AndroidTvTorrentPlayerActivity.guideTypeface(file) }
            override fun hideControlsMenu(): Unit { return this@AndroidTvTorrentPlayerActivity.controlsOverlayController.hideControlsMenu() }
            override val iptvChannels: List<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvGuideChromeController: TvIptvGuideChromeController get() = this@AndroidTvTorrentPlayerActivity.iptvGuideChromeController
            override val iptvGuideController: TvIptvGuideController get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController
            override val iptvRecordingActionsController: TvIptvRecordingActionsController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingActionsController
            override val iptvStartOverActive: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverActive
            override val iptvStartOverController: TvIptvStartOverController get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverController
            override val iptvStartOverTimelineVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override var ottIdentityBadge: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityBadge
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityBadge = value }
            override var ottIdentityDivider: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityDivider
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityDivider = value }
            override var ottIdentityOverline: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityOverline
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityOverline = value }
            override var ottIdentitySubtitle: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentitySubtitle
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentitySubtitle = value }
            override var ottIdentityTitle: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityTitle
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottIdentityTitle = value }
            override var ottMetaLine: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottMetaLine
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottMetaLine = value }
            override val ottQualityChips: Array<TextView?> get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottQualityChips
            override var ottRatingChip: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottRatingChip
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.identity.ottRatingChip = value }
            override var ottScrubPreviewChip: View?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.ottScrubPreviewChip
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.ottScrubPreviewChip = value }
            override var ottScrubPreviewText: TextView?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.ottScrubPreviewText
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.ottScrubPreviewText = value }
            override var ottSkinInstalled: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.ottSkinInstalled
                set(value) { this@AndroidTvTorrentPlayerActivity.ottSkinInstalled = value }
            override var pauseButton: AppCompatButton?
                get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.pauseButton
                set(value) { this@AndroidTvTorrentPlayerActivity.controlsOverlayController.pauseButton = value }
            override fun playNext(): Unit { return this@AndroidTvTorrentPlayerActivity.playNext() }
            override fun playPrevious(): Unit { return this@AndroidTvTorrentPlayerActivity.playPrevious() }
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override val playlistController: TvPlaylistOverlayController get() = this@AndroidTvTorrentPlayerActivity.playlistController
            override fun scheduleHideControlsMenu(): Unit { return this@AndroidTvTorrentPlayerActivity.controlsOverlayController.scheduleHideControlsMenu() }
            override fun seekBy(offsetMs: Long): Unit { return this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.seekBy(offsetMs) }
            override fun setupCinemaProgressBar(): Unit { return this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.setupCinemaProgressBar() }
            override fun showRandomPlaybackDialog(): Unit { return this@AndroidTvTorrentPlayerActivity.showRandomPlaybackDialog() }
            override val sourceBrowser: TvSourceBrowserController? get() = this@AndroidTvTorrentPlayerActivity.sourceBrowser
            override fun startSeekbarProgressUpdates(): Unit { return this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.startSeekbarProgressUpdates() }
            override val subtitleController: TvSubtitleController get() = this@AndroidTvTorrentPlayerActivity.subtitleController
            override val subtitleControlsLift: SubtitleControlsLiftController get() = this@AndroidTvTorrentPlayerActivity.subtitleControlsLift
            override fun togglePlayPause(): Unit { return this@AndroidTvTorrentPlayerActivity.controlsOverlayController.togglePlayPause() }
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
            override fun updateCatalogEpisodeControls(): Unit { return this@AndroidTvTorrentPlayerActivity.updateCatalogEpisodeControls() }
        },
    )
    // Tees the live progressive stream to a MediaStore file while playing.
    private val iptvRecordingController by lazy { IptvRecordingController(this) }
    private var iptvUpPressActive = false
    private var iptvUpLongPressHandled = false

    // OTT skin views (null while CLASSIC is installed). ottSkinInstalled is
    // the single truth every OTT branch tests — it can only become true after
    // the controller-layout swap succeeded, so a failed inflate degrades to
    // the classic skin instead of a half-styled one.
    private var ottSkinInstalled = false

    // Player
    private var player: ExoPlayer? = null
    private val nativeAudioRouting = NativeAudioRouting()
    private var trackSelector: DefaultTrackSelector? = null
    private var subtitleListener: Player.Listener? = null
    private val displayController: TvPlaybackDisplayController = TvPlaybackDisplayController(
        this,
        object : TvPlaybackDisplayController.Host {
            override val controlsDockController: TvControlsDockController get() = this@AndroidTvTorrentPlayerActivity.controlsDockController
            override val controlsSkin: TvControlsSkin get() = this@AndroidTvTorrentPlayerActivity.controlsSkin
            override val iptvGuideController: TvIptvGuideController get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController
            override val nativeAudioRouting: NativeAudioRouting get() = this@AndroidTvTorrentPlayerActivity.nativeAudioRouting
            override val ottSkinInstalled: Boolean get() = this@AndroidTvTorrentPlayerActivity.ottSkinInstalled
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerPreferences: com.debrify.app.profiles.NativePlayerPreferences get() = this@AndroidTvTorrentPlayerActivity.playerPreferences
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override var skipSegmentProviderId: String
                get() = this@AndroidTvTorrentPlayerActivity.skipSegmentProviderId
                set(value) { this@AndroidTvTorrentPlayerActivity.skipSegmentProviderId = value }
            override var skipSegmentsEnabled: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.skipSegmentsEnabled
                set(value) { this@AndroidTvTorrentPlayerActivity.skipSegmentsEnabled = value }
            override val trackSelector: DefaultTrackSelector? get() = this@AndroidTvTorrentPlayerActivity.trackSelector
        },
    )
    private var offsetRenderersFactory: OffsetRenderersFactory? = null

    // Phase 0 of the IPTV resilience plan: per-tune logcat diagnostics.
    // Inert for non-IPTV playback (nothing calls onTuneStart there).
    private val iptvTuneDiagnostics = IptvTuneDiagnostics()
    private val iptvTuneController: TvIptvTuneController = TvIptvTuneController(
        this,
        object : TvIptvTuneController.Host {
            override val controlsDockController: TvControlsDockController get() = this@AndroidTvTorrentPlayerActivity.controlsDockController
            override var currentIptvHttpHeaders: Map<String, String>
                get() = this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders = value }
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override val iptvChannelStartController: TvIptvChannelStartController get() = this@AndroidTvTorrentPlayerActivity.iptvChannelStartController
            override val iptvChannels: List<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvRecordingActionsController: TvIptvRecordingActionsController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingActionsController
            override val iptvRecordingController: IptvRecordingController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingController
            override var iptvStartOverActive: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverActive
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverActive = value }
            override val iptvStartOverController: TvIptvStartOverController get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverController
            override var iptvStartOverLoading: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading = value }
            override var iptvStartOverTimelineVisible: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible = value }
            override var iptvStrictTsActive: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStrictTsActive
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStrictTsActive = value }
            override val iptvTuneDiagnostics: IptvTuneDiagnostics get() = this@AndroidTvTorrentPlayerActivity.iptvTuneDiagnostics
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override fun restartProgressUpdates(): Unit { return this@AndroidTvTorrentPlayerActivity.restartProgressUpdates() }
            override val sleepStopLatched: Boolean get() = this@AndroidTvTorrentPlayerActivity.sleepStopLatched
            override val sleepTimerController: TvSleepTimerController get() = this@AndroidTvTorrentPlayerActivity.sleepTimerController
            override val subtitleTrackReadiness: SubtitleTrackReadiness get() = this@AndroidTvTorrentPlayerActivity.subtitleTrackReadiness
        },
    )

    /** Wall time we left the foreground; a live channel resumed after more
     *  than [IPTV_LIVE_REJOIN_AFTER_MS] away re-tunes to the live edge
     *  instead of resuming a stale (possibly dead) connection. */
    private var iptvStoppedAtRealtime = 0L

    private val IPTV_LIVE_REJOIN_AFTER_MS = 30_000L

    private var iptvNetworkCallback: ConnectivityManager.NetworkCallback? = null

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
    private var skipSegmentsEnabled = true
    private var skipSegmentProviderId = TvSkipSegmentClients.AUTO
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
            override fun checkpointCurrentIptvPosition(): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideController.navigator.checkpointCurrentIptvPosition()
            override fun commitIptvAllCategorySearch(): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideController.commitIptvAllCategorySearch()
            override var currentIptvIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIptvIndex = value }
            override fun hideIptvGuide(): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideController.hideIptvGuide()
            override var iptvChannels: MutableList<IptvChannelEntry>
                get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvChannels = value }
            override val iptvEpgToken: Int get() = this@AndroidTvTorrentPlayerActivity.iptvGuideChromeController.iptvEpgToken
            override val iptvGuideVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvGuideVisible
            override var iptvSeriesAudioKey: String?
                get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvSeriesAudioKey
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvSeriesAudioKey = value }
            override var iptvStartOverActive: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverActive
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverActive = value }
            override val iptvStartOverButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.controlsDockController.iptvStartOverButton
            override var iptvStartOverLoading: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading = value }
            override val iptvStartOverSeekButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.controlsDockController.iptvStartOverSeekButton
            override var iptvStartOverTimelineVisible: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible = value }
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override fun resetSubtitleState(): Unit = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.resetSubtitleState()
            override fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String): Unit = this@AndroidTvTorrentPlayerActivity.iptvTuneController.setIptvMediaItem(entry, streamUrl)
            override fun showControlsAndFocusProgressBar(): Unit = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.showControlsAndFocusProgressBar()
            override fun switchToIptvChannel(entry: IptvChannelEntry, adoptVisibleBrowseList: Boolean, checkpointOutgoing: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideController.navigator.switchToIptvChannel(entry, adoptVisibleBrowseList, checkpointOutgoing)
            override val titleView: TextView get() = this@AndroidTvTorrentPlayerActivity.titleView
            override fun updateIptvControlPresentation(entry: IptvChannelEntry?): Unit = this@AndroidTvTorrentPlayerActivity.controlsDockController.styler.updateIptvControlPresentation(entry)
            override fun updateIptvEpisodeControls(): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideController.navigator.updateIptvEpisodeControls()
        },
    )
    private val iptvGuideController: TvIptvGuideController = TvIptvGuideController(
        this,
        object : TvIptvGuideController.Host {
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsMenuVisible
            override var currentIptvIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIptvIndex = value }
            override fun hideIptvEpgPane(): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideChromeController.hideIptvEpgPane()
            override val iptvBrowseHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.iptvBrowseHandler
            override val iptvChannelStartController: TvIptvChannelStartController get() = this@AndroidTvTorrentPlayerActivity.iptvChannelStartController
            override var iptvChannels: MutableList<IptvChannelEntry>
                get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvChannels = value }
            override val iptvNextButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.controlsDockController.iptvNextButton
            override val iptvPrevButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.controlsDockController.iptvPrevButton
            override var iptvSourceId: String?
                get() = this@AndroidTvTorrentPlayerActivity.iptvSourceId
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvSourceId = value }
            override val iptvSources: List<IptvSourceEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvSources
            override var iptvStartOverActive: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverActive
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverActive = value }
            override val iptvStartOverController: TvIptvStartOverController get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverController
            override var iptvStartOverLoading: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverLoading = value }
            override var iptvStartOverTimelineVisible: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvStartOverTimelineVisible = value }
            override val iptvZapBannerController: TvIptvZapBannerController get() = this@AndroidTvTorrentPlayerActivity.iptvZapBannerController
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override fun resetSubtitleState(): Unit = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.resetSubtitleState()
            override val sourceSwitchController: TvSourceSwitchController get() = this@AndroidTvTorrentPlayerActivity.sourceSwitchController
            override val titleView: TextView get() = this@AndroidTvTorrentPlayerActivity.titleView
            override val trackSelector: DefaultTrackSelector? get() = this@AndroidTvTorrentPlayerActivity.trackSelector
            override fun updateIptvControlPresentation(entry: IptvChannelEntry?): Unit = this@AndroidTvTorrentPlayerActivity.controlsDockController.styler.updateIptvControlPresentation(entry)
            override fun updateIptvGuideCurrentName(): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideChromeController.updateIptvGuideCurrentName()
        },
    )

    // Per-channel HTTP headers for the CURRENT channel, injected into every
    // player request by the IPTV resolver installed in setupPlayer. Written
    // on the main thread in setIptvMediaItem, read on ExoPlayer's loader
    // threads — hence @Volatile.
    @Volatile
    private var currentIptvHttpHeaders: Map<String, String> = emptyMap()

    /** The factory's per-tune switch: written on main before each prepare
     *  (setIptvMediaItem), read on the extractor's loader thread. */
    @Volatile private var iptvStrictTsActive = false
    private val iptvGuideChromeController: TvIptvGuideChromeController = TvIptvGuideChromeController(
        this,
        object : TvIptvGuideChromeController.Host {
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override fun dp(value: Int): Int { return this@AndroidTvTorrentPlayerActivity.dp(value) }
            override val guideStyle: GuideStyle get() = this@AndroidTvTorrentPlayerActivity.guideStyle
            override val guideTokens: GuideTokens? get() = this@AndroidTvTorrentPlayerActivity.guideTokens
            override fun guideTypeface(file: String?): Typeface? { return this@AndroidTvTorrentPlayerActivity.guideTypeface(file) }
            override val iptvBrowseHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.iptvBrowseHandler
            override val iptvChannels: MutableList<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvGuideController: TvIptvGuideController get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController
            override val iptvRecordingActionsController: TvIptvRecordingActionsController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingActionsController
            override val iptvSourceId: String? get() = this@AndroidTvTorrentPlayerActivity.iptvSourceId
            override val iptvSources: List<IptvSourceEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvSources
            override val iptvStartOverController: TvIptvStartOverController get() = this@AndroidTvTorrentPlayerActivity.iptvStartOverController
            override val iptvZapBannerController: TvIptvZapBannerController get() = this@AndroidTvTorrentPlayerActivity.iptvZapBannerController
        },
    )
    private var iptvSources = mutableListOf<IptvSourceEntry>()
    private var iptvSourceId: String? = null
    private val iptvChannelStartController: TvIptvChannelStartController = TvIptvChannelStartController(
        this,
        object : TvIptvChannelStartController.Host {
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override var currentIptvStreamUrl: String?
                get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.currentIptvStreamUrl
                set(value) { this@AndroidTvTorrentPlayerActivity.iptvTuneController.currentIptvStreamUrl = value }
            override var currentStremioSourceIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex = value }
            override fun dropStaleSourceSwitchFeedback(): Unit = this@AndroidTvTorrentPlayerActivity.sourceSwitchController.dropStaleSourceSwitchFeedback()
            override val iptvBrowseHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.iptvBrowseHandler
            override val iptvChannels: MutableList<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvRecordingActionsController: TvIptvRecordingActionsController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingActionsController
            override val iptvSourceId: String? get() = this@AndroidTvTorrentPlayerActivity.iptvSourceId
            override val iptvTwinPreferredUrls: MutableMap<String, String> get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.trial.iptvTwinPreferredUrls
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String): Unit = this@AndroidTvTorrentPlayerActivity.iptvTuneController.setIptvMediaItem(entry, streamUrl)
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
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsMenuVisible
            override var currentIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentIndex = value }
            override var currentStremioSourceIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex = value }
            override fun failMoreTorrentSources(): Unit = this@AndroidTvTorrentPlayerActivity.sourceFetchController.failMoreTorrentSources()
            override val hasPlaylistResolver: Boolean get() = this@AndroidTvTorrentPlayerActivity.hasPlaylistResolver
            override fun heldResumePositionMs(actualMs: Long): Long? = this@AndroidTvTorrentPlayerActivity.heldResumePositionMs(actualMs)
            override fun hideStatusPill(): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.hideStatusPill()
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val isStremioTvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isStremioTvMode
            override val mediaPreparationGeneration: Int get() = this@AndroidTvTorrentPlayerActivity.mediaPreparationGeneration
            override val moreSourcesLoadingMode: String? get() = this@AndroidTvTorrentPlayerActivity.moreSourcesLoadingMode
            override val movieMoreSources: Boolean get() = this@AndroidTvTorrentPlayerActivity.movieMoreSources
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val pikPakRetryId: Int get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.pikPakRetryId
            override fun playItem(index: Int, suppressTrakt: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.playItem(index, suppressTrakt)
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun rebuildPlaylistContent(): Unit = this@AndroidTvTorrentPlayerActivity.playlistController.rebuildPlaylistContent()
            override fun reportValidatedSourceCommit(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.reportValidatedSourceCommit(sourceIndex)
            override fun requestMoreTorrentSources(mode: String): Unit = this@AndroidTvTorrentPlayerActivity.sourceFetchController.requestMoreTorrentSources(mode)
            override fun restartProgressUpdates(): Unit = this@AndroidTvTorrentPlayerActivity.restartProgressUpdates()
            override val seriesSourceTabs: Boolean get() = this@AndroidTvTorrentPlayerActivity.seriesSourceTabs
            override fun setResolvingState(resolving: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.setResolvingState(resolving)
            override fun showStatusPillTransient(message: String): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.showStatusPillTransient(message)
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
            override val playbackSpeedIndex: Int get() = this@AndroidTvTorrentPlayerActivity.displayController.playbackSpeedIndex
            override val playbackSpeeds: Array<Float> get() = this@AndroidTvTorrentPlayerActivity.displayController.playbackSpeeds
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playlistAdapter: PlaylistOverlayAdapter? get() = this@AndroidTvTorrentPlayerActivity.playlistController.playlistAdapter
            override val playlistVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.playlistController.playlistVisible
            override fun recordPlaybackLifecycle(event: String, details: String): Unit = this@AndroidTvTorrentPlayerActivity.recordPlaybackLifecycle(event, details)
            override val recoveryDataGeneration: Int get() = this@AndroidTvTorrentPlayerActivity.recoveryDataGeneration
            override val recoveryImdbId: String? get() = this@AndroidTvTorrentPlayerActivity.recoveryImdbId
            override val recoveryProfileId: String? get() = this@AndroidTvTorrentPlayerActivity.recoveryProfileId
            override val recoverySeriesTitle: String? get() = this@AndroidTvTorrentPlayerActivity.recoverySeriesTitle
            override val recoveryStartedAtMs: Long get() = this@AndroidTvTorrentPlayerActivity.recoveryStartedAtMs
            override val recoveryTitle: String? get() = this@AndroidTvTorrentPlayerActivity.recoveryTitle
            override val resizeModeIndex: Int get() = this@AndroidTvTorrentPlayerActivity.displayController.resizeModeIndex
            override val resizeModeLabels: Array<String> get() = this@AndroidTvTorrentPlayerActivity.displayController.resizeModeLabels
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
            override fun fadeInNextOverlay(): Unit = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.fadeInNextOverlay()
            override fun hideControlsMenu(): Unit = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.hideControlsMenu()
            override fun hideNextOverlay(): Unit = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.hideNextOverlay()
            override var isStremioTvMode: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.isStremioTvMode
                set(value) { this@AndroidTvTorrentPlayerActivity.isStremioTvMode = value }
            override val nextSubtext: TextView get() = this@AndroidTvTorrentPlayerActivity.nextSubtext
            override val nextText: TextView get() = this@AndroidTvTorrentPlayerActivity.nextText
            override fun playStremioTvPlaybackMap(channel: StremioTvGuideChannel, map: Map<*, *>, url: String, title: String, hideGuideOnReady: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.playStremioTvPlaybackMap(channel, map, url, title, hideGuideOnReady)
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerView: PlayerView get() = this@AndroidTvTorrentPlayerActivity.playerView
            override val playlistMode: PlaylistMode get() = this@AndroidTvTorrentPlayerActivity.playlistController.playlistMode
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
                get() = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.currentStremioSubtitleIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.currentStremioSubtitleIndex = value }
            override fun currentSubtitleIdentityLabel(): String = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.currentSubtitleIdentityLabel()
            override val externalSubtitleHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.externalSubtitleHandler
            override val failedSubtitleUrls: MutableSet<String> get() = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.failedSubtitleUrls
            override fun hideStatusPill(): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.hideStatusPill()
            override val isLoadingStremioSubtitles: Boolean get() = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.isLoadingStremioSubtitles
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
            override fun showSearchSubtitleDialog(): Unit = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.dialogs.showSearchSubtitleDialog()
            override fun showStatusPill(message: String): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.showStatusPill(message)
            override fun showStatusPillTransient(message: String): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.showStatusPillTransient(message)
            override fun showSyncToast(glyph: String, accent: Int, title: String, hint: String?, autoHideMs: Long?, uppercase: Boolean): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.showSyncToast(glyph, accent, title, hint, autoHideMs, uppercase)
            override fun startAutoSyncLadder(): Unit = this@AndroidTvTorrentPlayerActivity.autoSyncController.startAutoSyncLadder()
            override val stremioSubtitles: List<StremioSubtitle> get() = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.stremioSubtitles
            override val subtitleControlsLift: SubtitleControlsLiftController get() = this@AndroidTvTorrentPlayerActivity.subtitleControlsLift
            override val subtitleOverlay: SubtitleView get() = this@AndroidTvTorrentPlayerActivity.subtitleOverlay
            override val subtitleOverlayReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.subtitleOverlayReady
            override val subtitlePanel: SubtitlePanelController? get() = this@AndroidTvTorrentPlayerActivity.subtitlePanel
            override val subtitleScope: CoroutineScope get() = this@AndroidTvTorrentPlayerActivity.subtitleScope
            override var syncOverlay: SubtitleSyncOverlayController?
                get() = this@AndroidTvTorrentPlayerActivity.syncOverlay
                set(value) { this@AndroidTvTorrentPlayerActivity.syncOverlay = value }
            override val trackSelector: DefaultTrackSelector? get() = this@AndroidTvTorrentPlayerActivity.trackSelector
            override fun tryAutoSelectAddonSubtitle(): Unit = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.tryAutoSelectAddonSubtitle()
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
            override var userManuallySelectedSubtitle: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.userManuallySelectedSubtitle
                set(value) { this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.userManuallySelectedSubtitle = value }
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
    private val subtitleSourcesController: TvSubtitleSourcesController = TvSubtitleSourcesController(
        this,
        object : TvSubtitleSourcesController.Host {
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override fun dp(value: Int): Int { return this@AndroidTvTorrentPlayerActivity.dp(value) }
            override val iptvChannels: List<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override val offsetRenderersFactory: OffsetRenderersFactory? get() = this@AndroidTvTorrentPlayerActivity.offsetRenderersFactory
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val playerPreferences: com.debrify.app.profiles.NativePlayerPreferences get() = this@AndroidTvTorrentPlayerActivity.playerPreferences
            override val stremioSubtitleService: StremioSubtitleService? get() = this@AndroidTvTorrentPlayerActivity.stremioSubtitleService
            override val subtitleController: TvSubtitleController get() = this@AndroidTvTorrentPlayerActivity.subtitleController
            override val subtitleScope: CoroutineScope get() = this@AndroidTvTorrentPlayerActivity.subtitleScope
            override val subtitleTrackReadiness: SubtitleTrackReadiness get() = this@AndroidTvTorrentPlayerActivity.subtitleTrackReadiness
            override val trackSelector: DefaultTrackSelector? get() = this@AndroidTvTorrentPlayerActivity.trackSelector
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
        },
    )
    private val subtitleTrackReadiness = SubtitleTrackReadiness()
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
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsMenuVisible
            override val playlistVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.playlistController.playlistVisible
            override val seekbarVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.seek.seekbarVisible
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
    private val statusPillController: TvStatusPillController = TvStatusPillController(
        this,
        object : TvStatusPillController.Host {
            override fun dp(value: Int): Int = this@AndroidTvTorrentPlayerActivity.dp(value)
            override val externalSubtitleHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.externalSubtitleHandler
        },
    )

    // Handlers
    private val progressHandler = Handler(Looper.getMainLooper())
    private val pikPakRetryController: TvPikPakRetryController = TvPikPakRetryController(
        this,
        object : TvPikPakRetryController.Host {
            override fun failShufflePlayback(): Boolean = this@AndroidTvTorrentPlayerActivity.failShufflePlayback()
            override val isStremioTvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isStremioTvMode
            override val pikPakReactivationIndicator: View get() = this@AndroidTvTorrentPlayerActivity.pikPakReactivationIndicator
            override val pikPakReactivationIndicatorReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.pikPakReactivationIndicatorReady
            override val pikPakReactivationText: TextView get() = this@AndroidTvTorrentPlayerActivity.pikPakReactivationText
            override fun playNext(): Unit = this@AndroidTvTorrentPlayerActivity.playNext()
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val startupGateController: TvStartupGateController get() = this@AndroidTvTorrentPlayerActivity.startupGateController
            override val startupGateStatus: TextView get() = this@AndroidTvTorrentPlayerActivity.startupGateStatus
            override val startupGateStatusReady: Boolean get() = this@AndroidTvTorrentPlayerActivity.startupGateStatusReady
            override fun tryAutoSelectAddonSubtitle(): Unit = this@AndroidTvTorrentPlayerActivity.subtitleSourcesController.tryAutoSelectAddonSubtitle()
        },
    )
    private val startupGateStatusReady: Boolean get() = ::startupGateStatus.isInitialized
    private val pikPakReactivationIndicatorReady: Boolean get() = ::pikPakReactivationIndicator.isInitialized

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
                    iptvTuneController.iptvLiveRecovery.onProgress(it.currentPosition, it.playWhenReady)
                    // The renderer's own output counter — the one signal
                    // that survives a wedged video decoder under a healthy
                    // audio clock (finding #13; the Streamer report).
                    val frames = it.videoDecoderCounters?.let { c ->
                        c.ensureUpdated()
                        c.renderedOutputBufferCount
                    } ?: -1
                    iptvTuneController.iptvLiveRecovery.onVideoFrames(
                        renderedFrames = frames,
                        hasVideoTrack = it.videoFormat != null,
                        wantsPlayback = it.playWhenReady,
                    )
                    // The twin trial's verdict rides the same counter: a
                    // continuous advancing streak accepts, nothing else does
                    // (see judgeIptvTwinTrial).
                    iptvTuneController.trial.judgeIptvTwinTrial(frames)
                }
            }
            progressHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
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
                    subtitleSourcesController.tryAutoSelectAddonSubtitle()
                }
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (nativeAudioRouting.reprepareIfPending(player, displayController.playbackSpeeds[displayController.playbackSpeedIndex])) return
            when (playbackState) {
                Player.STATE_READY -> {
                    if (pendingShufflePlayback?.mediaStarted == true) pendingShufflePlayback = null
                    hasEverBeenReady = true
                    iptvTuneDiagnostics.onReady(player?.currentPosition ?: 0L)
                    if (isIptvMode) {
                        iptvTuneController.iptvLiveRecovery.onReady()
                        iptvTuneController.trial.rearmIptvTwinTrialDeadline()
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
                    if (displayController.loudnessEnhancer == null && displayController.nightModeIndex > 0) {
                        displayController.initializeLoudnessEnhancer()
                    }
                    // Announce the audio session to system effect apps. Mirrors
                    // the night-mode handling above: the session id only exists
                    // once the audio renderer is live, and onAudioSessionIdChanged
                    // doesn't re-fire when a seamless transition reuses the
                    // same AudioTrack.
                    displayController.syncAudioEffectSession()
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
                            iptvTuneController.iptvLiveRecovery.onEnded()
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
                        iptvGuideController.navigator.nextIptvEpisode()?.let { iptvGuideController.navigator.switchToIptvChannel(it) }
                        return
                    }

                    val model = payload ?: return
                    if (continuousShuffleEnabled) {
                        if (playShowShuffle(autoAdvance = true)) return
                        val shuffleIndex = pickShuffleIndex()
                        if (shuffleIndex != null) {
                            controlsOverlayController.showNextOverlay(model.items[shuffleIndex])
                            progressHandler.postDelayed({
                                controlsOverlayController.hideNextOverlay()
                                isAutoAdvancing = true
                                playItem(shuffleIndex)
                            }, 1500)
                            return
                        }
                    }

                    val nextIndex = playlistController.getNextPlayableIndex(currentIndex)
                    if (nextIndex != null) {
                        controlsOverlayController.showNextOverlay(model.items[nextIndex])
                        progressHandler.postDelayed({
                            controlsOverlayController.hideNextOverlay()
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
                                sourceFetchController.requestEpisodeFetch(
                                    nextTarget.season,
                                    nextTarget.episode,
                                    autoAdvance = true,
                                )
                                return
                            }
                            if (hasPlaylistResolver) {
                                sourceFetchController.requestAdjacentEpisodeFetch(
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
            controlsOverlayController.updatePauseButtonLabel()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            controlsOverlayController.updatePauseButtonLabel()
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
                statusPillController.showStatusPillTransient("Previous source could not be restored")
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
                if (iptvTuneController.iptvLiveRecoveryEligible() && iptvTuneController.retryIptvAsHlsIfUnrecognized(error)) return
                val entry = iptvChannels.getOrNull(currentIptvIndex)
                if (entry != null && entry.isLive) {
                    iptvStartOverController.cancelPendingIptvCatchupRequest()
                    // Archive rejection must not enter the live AUTH ladder.
                    if (iptvTuneController.iptvLiveRecoveryEligible()) {
                        iptvStartOverActive = false
                        iptvStartOverTimelineVisible = false
                        controlsDockController.styler.updateIptvControlPresentation(entry)
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
            if (isLiveIptvError && iptvTuneController.trial.iptvTwinTrialUrl != null &&
                iptvTuneController.currentIptvStreamUrl == iptvTuneController.trial.iptvTwinTrialUrl
            ) {
                iptvTuneController.trial.failIptvTwinTrial("error:${error.errorCodeName}")
                return
            }

            // A twin that proved itself earlier can still disappear later.
            // AUTH-class answers are deterministic, so retrying that twin is
            // pointless; revoke it and restore the original HLS once.
            if (isLiveIptvError && iptvTuneController.trial.restoreAcceptedIptvTwinAfterAuth(error)) return

            // IPTV: a stream that failed extractor sniffing is almost always
            // an HLS playlist behind an extension-less URL (inferred as
            // progressive). Retry the SAME url once with the type forced —
            // before the Stremio ladder, so a playable-if-forced candidate
            // isn't skipped.
            if (isLiveIptvError && iptvTuneController.retryIptvAsHlsIfUnrecognized(error)) return

            // IPTV live: falling behind the live window (long pause, hiccup
            // on a short-window stream) is recoverable by rejoining the live
            // edge — without this the channel just dies with an error.
            if (isLiveIptvError &&
                iptvTuneController.currentIptvStreamUrl != null &&
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
                iptvTuneController.iptvLiveRecovery.onFatalError(classifyIptvError(error))
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
            displayController.releaseLoudnessEnhancer()
        }

        override fun onAudioSessionIdChanged(audioSessionId: Int) {
            // Let system effect apps follow the new session (no-op if unchanged).
            displayController.syncAudioEffectSession(audioSessionId)
            // Reinitialize night mode effect when audio session changes
            if (displayController.nightModeIndex > 0 && audioSessionId != 0) {
                displayController.releaseLoudnessEnhancer()
                displayController.initializeLoudnessEnhancer()
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
        displayController.loadPlayerDefaults()

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
        controlsOverlayController.seek.setupSeekbar()
        playlistController.setupPlaylist()
        controlsDockController.setupControls()
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
                    subtitleSourcesController.injectedSubtitles.add(StremioSubtitle.fromJson(obj, source, addonId = "injected"))
                }
                android.util.Log.d("AndroidTvPlayer", "Loaded ${subtitleSourcesController.injectedSubtitles.size} launch-supplied subtitles")
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
            controlsOverlayController.identity.ottShowName = showName.trim()
            if (ottSkinInstalled) runOnUiThread { controlsOverlayController.identity.updateOttIdentity() }
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
                    subtitleSourcesController.fetchStremioSubtitles(currentItem)
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
                            playlistController.rebuildPlaylistContent()
                            playlistController.seriesPlaylistAdapter?.setActiveIndex(currentIndex)
                            updateCatalogEpisodeControls()
                            model.items.getOrNull(currentIndex)?.let { controlsOverlayController.identity.updateTitle(it) }
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
                    val seriesAdapter = playlistController.seriesPlaylistAdapter
                    val movieAdapter = playlistController.moviePlaylistAdapter
                    android.util.Log.d("TVMazeUpdate", "seriesAdapter=${seriesAdapter != null}, movieAdapter=${movieAdapter != null}")
                    seriesAdapter?.notifyDataSetChanged()
                    movieAdapter?.notifyDataSetChanged()
                    android.util.Log.d("TVMazeUpdate", "UI refresh done")

                    // Also refresh title bar for currently playing episode
                    val currentItem = model.items.getOrNull(currentIndex)
                    if (currentItem != null) {
                        android.util.Log.d("TVMazeUpdate", "Refreshing title for current episode: ${currentItem.title}")
                        controlsOverlayController.identity.updateTitle(currentItem)
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
        playlistController.guideSkin.installGuideOverlaySkin()
        playlistOverlay = findViewById(R.id.android_tv_playlist_overlay)
        playlistView = findViewById(R.id.android_tv_playlist)
        seasonTabsContainer = findViewById(R.id.season_tabs_container)
        playlistController.guideSkin.bindGuideSkinViews()
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
                        sourceFetchController.requestMoreTorrentSources(mode)
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
                        sourceFetchController.requestAddonTorrentSources(groupId)
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
        nativeAudioRouting.update(displayController.nightModeIndex > 0, displayController.systemAudioEffectsEnabled, displayController.playbackSpeeds[displayController.playbackSpeedIndex])
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

        when (displayController.displayMatchMode) {
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
        player?.setPlaybackSpeed(displayController.playbackSpeeds[displayController.playbackSpeedIndex])

        player?.addListener(playbackListener)
        player?.addAnalyticsListener(displayController.decoderAnalyticsListener)
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
        displayController.applyResizeMode()
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
                        runOnUiThread { iptvTuneController.iptvLiveRecovery.setOffline(false) }
                    }

                    override fun onLost(network: Network) {
                        runOnUiThread { iptvTuneController.iptvLiveRecovery.setOffline(true) }
                    }
                }
                try {
                    cm.registerDefaultNetworkCallback(callback)
                    iptvNetworkCallback = callback
                    // Cold-start truth: registration alone reports nothing
                    // until the network CHANGES — launched offline, the
                    // ladder must know now, not at the first handover.
                    iptvTuneController.iptvLiveRecovery.setOffline(cm.activeNetwork == null)
                } catch (e: Exception) {
                    // Some ROMs throw on registration limits; the ladder
                    // works without the gate, just less politely offline.
                    android.util.Log.w("AndroidTvPlayer", "network callback: $e")
                }
            }
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
        pikPakRetryController.cancelPikPakRetry()

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
        controlsOverlayController.setResolvingState(true)
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
            controlsOverlayController.setResolvingState(false)

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

    private fun playMediaDirect(item: PlaybackItem) {
        // Clear subtitle state when switching content
        subtitleSourcesController.resetSubtitleState()

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

        controlsOverlayController.identity.updateTitle(item)
        playlistController.playlistAdapter?.setActiveIndex(currentIndex)
        restartProgressUpdates()

        // Fetch Stremio subtitles for this item
        subtitleSourcesController.fetchStremioSubtitles(item)
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

        val nextIndex = playlistController.getNextPlayableIndex(currentIndex)
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
                    sourceFetchController.requestEpisodeFetch(nextTarget.season, nextTarget.episode)
                    return
                }
                if (hasPlaylistResolver) {
                    sourceFetchController.requestAdjacentEpisodeFetch(
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
        val prevIndex = playlistController.getPrevPlayableIndex(currentIndex)
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
                sourceFetchController.requestEpisodeFetch(previousTarget.season, previousTarget.episode)
                return
            }
            if (hasAdjacentEpisodeResolver &&
                currentItem?.season != null && currentItem.episode != null) {
                sourceFetchController.requestAdjacentEpisodeFetch(
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
            (playlistController.getPrevPlayableIndex(currentIndex) != null ||
                (hasPlaylistResolver &&
                    (guideAdjacent(model, currentItem, -1) != null ||
                        (hasAdjacentEpisodeResolver &&
                            ((currentItem?.season ?: 0) > 1 ||
                                (currentItem?.episode ?: 0) > 1)))))
        controlsDockController.iptvPrevButton?.visibility = if (hasPrevious) View.VISIBLE else View.GONE
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
                if (attempt.mediaStarted && startupGateController.currentPlaybackItemIsPikPak() && pikPakRetryController.isPikPakRetrying &&
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
        if (sourceFetchController.episodeFetchInFlight) {
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
                if (sourceFetchController.episodeFetchInFlight) progressHandler.postDelayed({ retryWhenIdle() }, 50)
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
            statusPillController.showStatusPillTransient("No other playable episode found for shuffle")
            return true
        }
        upNextController.hideUpNextCard()
        val generation = showShuffleGeneration
        fun fetchTarget() {
            val fetchAttempt = ShufflePlaybackAttempt(mediaPreparationGeneration, generation, autoAdvance,
                onUnavailable = { playShowShuffle(attempted + target, autoAdvance) })
            if (!shuffleAttemptCurrent(fetchAttempt)) return
            sourceFetchController.requestEpisodeFetch(target.season, target.episode, autoAdvance = autoAdvance,
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

        if (playlistController.playlistMode == PlaylistMode.SERIES) {
            val episodeIndices = model.items.mapIndexedNotNull { index, item ->
                if (item.season != null && item.episode != null) index else null
            }
            if (episodeIndices.isNotEmpty()) return episodeIndices
        }

        if (playlistController.playlistMode == PlaylistMode.COLLECTION) {
            val preferredGroup = playlistController.movieGroups?.groups?.firstOrNull {
                it.name.equals("Main", ignoreCase = true)
            } ?: playlistController.movieGroups?.groups?.firstOrNull()
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

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    // PikPak Cold Storage Retry Logic
    // PikPak uses "cold storage" where files that haven't been accessed recently need 10-30 seconds
    // to reactivate. This implements retry logic with exponential backoff.

    private fun playPikPakVideoWithRetry(item: PlaybackItem) {
        android.util.Log.d("AndroidTvPlayer", "PikPak: Starting retry logic for cold storage handling")

        // Clear subtitle state when switching content
        subtitleSourcesController.resetSubtitleState()

        // Cancel any previous retry loops
        pikPakRetryController.pikPakRetryId++
        val myRetryId = pikPakRetryController.pikPakRetryId

        // Reset retry state
        pikPakRetryController.pikPakRetryCount = 0
        pikPakRetryController.isPikPakRetrying = false
        pikPakRetryController.hidePikPakRetryOverlay()

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

        controlsOverlayController.identity.updateTitle(item)
        playlistController.playlistAdapter?.setActiveIndex(currentIndex)
        restartProgressUpdates()

        // Fetch Stremio subtitles for this item (same as playMediaDirect)
        subtitleSourcesController.fetchStremioSubtitles(item)

        // Start retry loop with attempt 0
        pikPakRetryController.attemptPikPakPlaybackLoop(item, 0, myRetryId)
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
            (iptvChannels.size > 1 || iptvGuideController.iptvZapPagingActive) &&
            (keyCode == KeyEvent.KEYCODE_CHANNEL_UP ||
                keyCode == KeyEvent.KEYCODE_CHANNEL_DOWN)
        ) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                iptvGuideController.navigator.zapIptvChannel(if (keyCode == KeyEvent.KEYCODE_CHANNEL_UP) 1 else -1)
            }
            return true
        }

        // Handle IPTV guide overlay
        if (iptvGuideController.iptvGuideVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_BACK -> {
                        if (iptvGuideChromeController.iptvEpgVisible) {
                            iptvGuideChromeController.hideIptvEpgPane()
                            iptvGuideController.iptvGuideList?.requestFocus()
                        } else {
                            iptvGuideController.hideIptvGuide()
                        }
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        if (iptvGuideChromeController.isFocusInIptvEpgPanel()) {
                            val entry = iptvGuideChromeController.iptvEpgEntry
                            iptvGuideChromeController.hideIptvEpgPane()
                            val position = iptvGuideController.iptvChannelAdapter?.positionOf(entry) ?: 0
                            iptvGuideController.iptvGuideList?.findViewHolderForAdapterPosition(position)
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
                            iptvGuideChromeController.focusedIptvGuideEntry()?.let { entry ->
                                if (entry.isLive) iptvGuideChromeController.showIptvSchedulePane(entry)
                            }
                            return true
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        // Long-press up in channel list: jump to search bar
                        if (isFocusInIptvChannelList() && event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                            iptvGuideController.iptvGuideSearch?.requestFocus()
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
        if (controlsOverlayController.seek.seekbarVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        controlsOverlayController.seek.seekBackward(step, isContinuous = event.repeatCount > 0)
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        controlsOverlayController.seek.seekForward(step, isContinuous = event.repeatCount > 0)
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                        controlsOverlayController.seek.confirmSeekPosition()
                        return true
                    }
                    KeyEvent.KEYCODE_BACK -> {
                        controlsOverlayController.seek.hideSeekbar()
                        return true
                    }
                }
            }
            return true
        }

        // Handle playlist
        if (playlistController.playlistVisible) {
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
                playlistController.hidePlaylist()
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

        if (controlsOverlayController.controlsMenuVisible && keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
            controlsOverlayController.hideControlsMenu()
            return true
        }

        val focusInControls = controlsOverlayController.isFocusInControlsOverlay()

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
                controlsOverlayController.handlePlayPauseToggleFromCenter()
            }
            return true
        }

        // Down button - show controls menu, or from badge go to progress bar
        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            // If focus is on Stremio badge, DOWN goes back to progress bar (or controls dock if seeking unavailable)
            if (currentFocus == stremioSourceBadge && controlsOverlayController.controlsMenuVisible) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    val duration = player?.duration ?: 0
                    if (duration > 0) {
                        controlsOverlayController.seek.cinemaProgressContainer?.requestFocus()
                    } else {
                        controlsOverlayController.pauseButton?.requestFocus()
                    }
                }
                return true
            }
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                if (!controlsOverlayController.controlsMenuVisible) {
                    controlsOverlayController.showControlsMenu()
                    controlsOverlayController.scheduleHideControlsMenu()
                    return true
                } else if (!focusInControls) {
                    controlsOverlayController.showControlsMenu()
                    controlsOverlayController.scheduleHideControlsMenu()
                    return true
                }
            }
            return super.dispatchKeyEvent(event)
        }

        // Up button - from dock go to progress bar, from progress bar go to badge, otherwise show playlist/guide
        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
            // If focus is on progress bar and Stremio badge is available, UP goes to badge
            if (currentFocus == controlsOverlayController.seek.cinemaProgressContainer && controlsOverlayController.controlsMenuVisible && stremioSources.isNotEmpty()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    stremioSourceBadge?.requestFocus()
                }
                return true
            }
            // If focus is in controls dock, UP goes to progress bar (or badge if seeking unavailable)
            if ((!isIptvMode ||
                    iptvChannels.getOrNull(currentIptvIndex)?.isLive == false) &&
                focusInControls && controlsOverlayController.controlsMenuVisible && !controlsOverlayController.seek.cinemaSeekMode
            ) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    val duration = player?.duration ?: 0
                    if (duration > 0) {
                        controlsOverlayController.seek.cinemaProgressContainer?.requestFocus()
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
                            controlsOverlayController.hideControlsMenu()
                            iptvGuideChromeController.overlay.showIptvChannelJumpDialog()
                        }
                    }
                    KeyEvent.ACTION_UP -> {
                        if (iptvUpPressActive && !iptvUpLongPressHandled) {
                            iptvGuideController.showIptvGuide()
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
            if (playlistController.playlistMode == PlaylistMode.NONE) {
                return super.dispatchKeyEvent(event)
            }
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                playlistController.showPlaylist()
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
            if (iptvGuideController.navigator.isLiveIptvZapContext()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    iptvGuideController.navigator.zapIptvChannel(1)
                }
                return true
            }
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                    // Long-press: Show controls and focus progress bar for seeking
                    controlsOverlayController.seek.showControlsAndFocusProgressBar()
                } else if (event.repeatCount == 0) {
                    controlsOverlayController.seek.seekBy(SEEK_STEP_MS)
                }
            }
            return true
        }

        if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) {
            if (focusInControls) {
                return super.dispatchKeyEvent(event)
            }
            if (iptvGuideController.navigator.isLiveIptvZapContext()) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    iptvGuideController.navigator.zapIptvChannel(-1)
                }
                return true
            }
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount >= SEEK_LONG_PRESS_THRESHOLD) {
                    // Long-press: Show controls and focus progress bar for seeking
                    controlsOverlayController.seek.showControlsAndFocusProgressBar()
                } else if (event.repeatCount == 0) {
                    controlsOverlayController.seek.seekBy(-SEEK_STEP_MS)
                }
            }
            return true
        }

        return super.dispatchKeyEvent(event)
    }

    private fun isFocusInIptvChannelList(): Boolean {
        val list = iptvGuideController.iptvGuideList ?: return false
        var current = currentFocus
        while (current != null) {
            if (current == list) return true
            val parent = current.parent
            current = if (parent is View) parent else null
        }
        return false
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
        iptvGuideController.iptvSourceName = json.optString("sourceName").takeIf { it.isNotEmpty() } ?: "IPTV"
        iptvGuideController.iptvContentType = json.optString("contentType").takeIf {
            it in setOf("live", "vod", "series", "episodes")
        } ?: "live"
        iptvGuideController.iptvSelectedCategory =
            json.optString("selectedCategory").takeIf { it.isNotEmpty() }
        iptvSources = parseIptvSources(json.optJSONArray("sources"))
        iptvGuideController.iptvLists = parseIptvLists(json.optJSONArray("lists"))
        iptvGuideController.iptvCategories = parseStringList(json.optJSONArray("categories"))
        // Playback owns this context until the user starts browsing another
        // source/category. CH +/- can then restore the actual playing source
        // instead of whatever catalog happens to be visible in the guide.
        iptvGuideController.iptvZapSourceId = iptvSourceId
        iptvGuideController.iptvZapSourceName = iptvGuideController.iptvSourceName
        iptvGuideController.iptvZapContentType = iptvGuideController.iptvContentType
        iptvGuideController.iptvZapCategory = iptvGuideController.iptvSelectedCategory
        iptvGuideController.iptvZapCategories = iptvGuideController.iptvCategories.toMutableList()
        iptvGuideController.iptvZapOwnsUiContext = true

        iptvChannels = parseIptvChannels(json.optJSONArray("channels") ?: JSONArray())
        iptvChannels.forEach { channel ->
            if (channel.sourceId == null) channel.sourceId = iptvSourceId
            if (channel.sourceName == null) channel.sourceName = iptvGuideController.iptvSourceName
        }
        iptvGuideController.iptvBrowseChannels = iptvChannels.toMutableList()

        currentIptvIndex = json.optInt("startIndex", 0).coerceIn(0, iptvChannels.lastIndex.coerceAtLeast(0))
        if (iptvChannels.isNotEmpty()) {
            iptvChannels[currentIptvIndex].isCurrent = true
        }

        val title = json.optString("title")
        android.util.Log.d("AndroidTvPlayer", "initIptvMode: ${iptvChannels.size} channels, startIndex=$currentIptvIndex, title=$title")

        // Xtream series audio memory (see fields). Applied to the TrackSelector
        // below so it carries across every episode automatically.
        iptvGuideController.iptvSeriesAudioKey = json.optString("seriesAudioKey").takeIf { it.isNotEmpty() }
        iptvGuideController.iptvPreferredAudioLang = json.optString("preferredAudioLang").takeIf { it.isNotEmpty() }

        // Bind views and setup player
        bindViews()
        setupPlayer()
        controlsOverlayController.seek.setupSeekbar()
        controlsDockController.setupControls()
        controlsDockController.styler.setupIptvControls()

        // A remembered per-series audio language overrides setupPlayer's global
        // default. It's a TrackSelector parameter, so it re-applies to every
        // episode on switch without any per-media work.
        iptvGuideController.iptvPreferredAudioLang?.let { iptvGuideController.navigator.setIptvPreferredAudioLang(it) }

        // Show the Previous-episode control only for a non-live episode list.
        iptvGuideController.navigator.updateIptvEpisodeControls()

        // Initialize seek feedback manager
        seekFeedbackManager = SeekFeedbackManager(findViewById(android.R.id.content))
        setupBackPressHandler()
        setupMetadataReceiver()

        // Initialize Stremio subtitle service
        stremioSubtitleService = StremioSubtitleService(this)

        // Bind IPTV guide overlay views
        iptvGuideController.iptvGuideOverlay = findViewById(R.id.iptv_guide_overlay)
        iptvGuideController.iptvGuideList = findViewById(R.id.iptv_guide_list)
        iptvGuideController.iptvGuideSearch = findViewById(R.id.iptv_guide_search)
        iptvGuideController.iptvGuideTitle = findViewById(R.id.iptv_guide_title)
        iptvGuideController.iptvGuideCountText = findViewById(R.id.iptv_guide_count)
        iptvGuideController.iptvSourceButton = findViewById(R.id.iptv_source_button)
        iptvGuideController.iptvCategoryButton = findViewById(R.id.iptv_category_button)
        iptvGuideController.iptvBrowseLoading = findViewById(R.id.iptv_browse_loading)
        iptvGuideChromeController.iptvGuideCurrentName = findViewById(R.id.iptv_guide_current_name)
        iptvGuideChromeController.iptvGuideCurrentGroup = findViewById(R.id.iptv_guide_current_group)
        iptvGuideChromeController.iptvGuideCurrentEpg = findViewById(R.id.iptv_guide_current_epg)
        iptvGuideChromeController.iptvGuideNowPlaying = findViewById(R.id.iptv_guide_now_playing)
        iptvGuideChromeController.iptvGuideNowLogo = findViewById(R.id.iptv_guide_now_logo)
        iptvGuideChromeController.iptvGuideNowLetter = findViewById(R.id.iptv_guide_now_letter)
        iptvGuideChromeController.iptvEpgPanel = findViewById(R.id.iptv_epg_panel)
        iptvGuideChromeController.iptvEpgLogo = findViewById(R.id.iptv_epg_logo)
        iptvGuideChromeController.iptvEpgLetter = findViewById(R.id.iptv_epg_letter)
        iptvGuideChromeController.iptvEpgChannelName = findViewById(R.id.iptv_epg_channel_name)
        iptvGuideChromeController.iptvEpgChannelGroup = findViewById(R.id.iptv_epg_channel_group)
        iptvGuideChromeController.iptvEpgDate = findViewById(R.id.iptv_epg_date)
        iptvGuideChromeController.iptvEpgLoading = findViewById(R.id.iptv_epg_loading)
        iptvGuideChromeController.iptvEpgEmpty = findViewById(R.id.iptv_epg_empty)
        iptvGuideChromeController.iptvEpgList = findViewById(R.id.iptv_epg_list)

        iptvGuideChromeController.overlay.setupIptvOverlay()

        // Override the normal List button only for live television. VOD keeps
        // the standard video controls installed by setupControls().
        val playlistButton: AppCompatButton? = playerView.findViewById(R.id.debrify_playlist_button)
        if (iptvChannels.getOrNull(currentIptvIndex)?.isLive == true) {
            playlistButton?.text = "Guide"
            playlistButton?.setOnClickListener {
                controlsOverlayController.hideControlsMenu()
                iptvGuideController.toggleIptvGuide()
            }
        }

        // Play initial channel
        if (iptvChannels.isNotEmpty()) {
            val initial = iptvChannels[currentIptvIndex]
            iptvGuideController.navigator.playIptvChannel(currentIptvIndex)
            iptvGuideController.pager.bootstrapInitialIptvZapPaging(initial)
        }
    }
    private val iptvRecordingActionsController = TvIptvRecordingActionsController(
        this,
        object : TvIptvRecordingActionsController.Host {
            override val currentIptvStreamUrl: String? get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.currentIptvStreamUrl
            override val iptvHlsForcedUrls: Set<String> get() = this@AndroidTvTorrentPlayerActivity.iptvTuneController.iptvHlsForcedUrls
            override val iptvChannels: List<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override val iptvSources: List<IptvSourceEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvSources
            override val iptvSourceId: String? get() = this@AndroidTvTorrentPlayerActivity.iptvSourceId
            override val currentIptvHttpHeaders: Map<String, String> get() = this@AndroidTvTorrentPlayerActivity.currentIptvHttpHeaders
            override val iptvRecordingController: IptvRecordingController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingController
            override val iptvRecordButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.controlsDockController.iptvRecordButton
            override val legacyStoragePermissionRequestCode: Int get() = this@AndroidTvTorrentPlayerActivity.legacyStoragePermissionRequestCode
        },
    )
    private val iptvZapBannerController: TvIptvZapBannerController = TvIptvZapBannerController(
        this,
        object : TvIptvZapBannerController.Host {
            override val controlsMenuVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsMenuVisible
            override val controlsOverlay: View? get() = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.controlsOverlay
            override val currentIptvIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIptvIndex
            override fun dp(value: Int): Int = this@AndroidTvTorrentPlayerActivity.dp(value)
            override fun ensureIptvChannelEpg(entry: IptvChannelEntry): Unit = this@AndroidTvTorrentPlayerActivity.iptvGuideChromeController.ensureIptvChannelEpg(entry)
            override fun formatEpgTime(timeMs: Long): String = this@AndroidTvTorrentPlayerActivity.iptvGuideChromeController.formatEpgTime(timeMs)
            override val guideStyle: GuideStyle get() = this@AndroidTvTorrentPlayerActivity.guideStyle
            override val guideTokens: GuideTokens? get() = this@AndroidTvTorrentPlayerActivity.guideTokens
            override fun guideTypeface(file: String?): Typeface? = this@AndroidTvTorrentPlayerActivity.guideTypeface(file)
            override val iptvChannels: MutableList<IptvChannelEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvChannels
            override val iptvGuideVisible: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvGuideVisible
            override val iptvRecordingActionsController: TvIptvRecordingActionsController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingActionsController
            override val iptvRecordingController: IptvRecordingController get() = this@AndroidTvTorrentPlayerActivity.iptvRecordingController
            override val iptvSources: List<IptvSourceEntry> get() = this@AndroidTvTorrentPlayerActivity.iptvSources
            override val iptvZapCategoryTotal: Int get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvZapCategoryTotal
            override val iptvZapPagingActive: Boolean get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvZapPagingActive
            override val iptvZapSourceId: String? get() = this@AndroidTvTorrentPlayerActivity.iptvGuideController.iptvZapSourceId
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun updateSubtitleControlsLift(): Unit = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.updateSubtitleControlsLift()
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

    // Passed to the controller so named shortcuts match the visible rows.
    private val unifiedSectionIds = listOf("audio", "subs", "display", "playback")

    private fun umSectionRows(): List<UnifiedMenuController.Row> {
        val subBadge = when {
            subtitleSourcesController.isLoadingStremioSubtitles -> "…"
            subtitleSourcesController.stremioSubtitles.isNotEmpty() -> "${subtitleSourcesController.stremioSubtitles.size}"
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
                "audio" -> displayController.umAudioModel(col1, col2Index)
                "subs" -> subtitleSourcesController.umSubsModel(col1, col2Index)
                "sources" -> umSourcesModel(col1, col2Index)
                "display" -> displayController.umDisplayModel(col1, col2Index)
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
            subtitleSourcesController.subtitleSearchStatus = "Searching…"
            subtitleSourcesController.subtitleSearchResults = emptyList()
            subtitleSourcesController.pendingSeriesResult = null
            unifiedMenu?.render()
            subtitleSourcesController.dialogs.requestSubtitleCatalogSearchFromFlutter(
                query,
                onSuccess = { results ->
                    if (unifiedMenu?.isVisible != true) return@requestSubtitleCatalogSearchFromFlutter
                    subtitleSourcesController.subtitleSearchResults = results
                    subtitleSourcesController.subtitleSearchStatus =
                        if (results.isEmpty()) "No matches — try a different title" else "${results.size} results"
                    unifiedMenu?.render()
                },
                onError = { msg ->
                    if (unifiedMenu?.isVisible != true) return@requestSubtitleCatalogSearchFromFlutter
                    subtitleSourcesController.subtitleSearchStatus = msg
                    unifiedMenu?.render()
                }
            )
        }

        override fun searchInitialQuery(): String {
            val item = subtitleSourcesController.dialogs.getCurrentSubtitleSearchItem() ?: return ""
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
                    onOk = { sourceFetchController.requestMoreTorrentSources(mode) }))
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

    // ── Playback ────────────────────────────────────────────────────────────
    private fun umPlaybackModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val col2 = listOf(
            mrow("Playback speed", value = displayController.playbackSpeedLabels.getOrNull(displayController.playbackSpeedIndex), tag = "speed"),
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
            "Playback speed" to displayController.playbackSpeedLabels.mapIndexed { i, l ->
                mrow(l, selected = i == displayController.playbackSpeedIndex, onOk = {
                    displayController.applyPlaybackSpeed(i)
                })
            }
        }
        return UnifiedMenuController.Model(col1, "PLAYBACK", col2, title, col3)
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
    private val sourceFetchController: TvSourceFetchController = TvSourceFetchController(
        this,
        object : TvSourceFetchController.Host {
            override val addonFetchState: MutableMap<String, String> get() = this@AndroidTvTorrentPlayerActivity.addonFetchState
            override val addonPackProbing: MutableSet<String> get() = this@AndroidTvTorrentPlayerActivity.addonPackProbing
            override val currentIndex: Int get() = this@AndroidTvTorrentPlayerActivity.currentIndex
            override var currentStremioSourceIndex: Int
                get() = this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex
                set(value) { this@AndroidTvTorrentPlayerActivity.currentStremioSourceIndex = value }
            override fun guideAdjacent(model: PlaybackPayload, currentItem: PlaybackItem?, direction: Int, allowResolverFallback: Boolean): SeasonEpisode? = this@AndroidTvTorrentPlayerActivity.guideAdjacent(model, currentItem, direction, allowResolverFallback)
            override var isAutoAdvancing: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.isAutoAdvancing
                set(value) { this@AndroidTvTorrentPlayerActivity.isAutoAdvancing = value }
            override var moreSourcesLoadingMode: String?
                get() = this@AndroidTvTorrentPlayerActivity.moreSourcesLoadingMode
                set(value) { this@AndroidTvTorrentPlayerActivity.moreSourcesLoadingMode = value }
            override var movieSourcesFetched: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.movieSourcesFetched
                set(value) { this@AndroidTvTorrentPlayerActivity.movieSourcesFetched = value }
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override var seriesEpisodesFetched: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.seriesEpisodesFetched
                set(value) { this@AndroidTvTorrentPlayerActivity.seriesEpisodesFetched = value }
            override var seriesPacksFetched: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.seriesPacksFetched
                set(value) { this@AndroidTvTorrentPlayerActivity.seriesPacksFetched = value }
            override fun showStatusPillTransient(message: String): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.showStatusPillTransient(message)
            override val sourceAddons: List<TvSourceAddon> get() = this@AndroidTvTorrentPlayerActivity.sourceAddons
            override val sourceBrowser: TvSourceBrowserController? get() = this@AndroidTvTorrentPlayerActivity.sourceBrowser
            override val sourceSwitchController: TvSourceSwitchController get() = this@AndroidTvTorrentPlayerActivity.sourceSwitchController
            override val startupGateController: TvStartupGateController get() = this@AndroidTvTorrentPlayerActivity.startupGateController
            override var stremioResolutionToken: Int
                get() = this@AndroidTvTorrentPlayerActivity.stremioResolutionToken
                set(value) { this@AndroidTvTorrentPlayerActivity.stremioResolutionToken = value }
            override val stremioSources: MutableList<StremioSource> get() = this@AndroidTvTorrentPlayerActivity.stremioSources
            override val unifiedMenu: UnifiedMenuController? get() = this@AndroidTvTorrentPlayerActivity.unifiedMenu
            override fun watchShufflePlayback(attempt: ShufflePlaybackAttempt): Unit = this@AndroidTvTorrentPlayerActivity.watchShufflePlayback(attempt)
            override fun yieldEpisodeFetchToQueuedShuffle(): Boolean = this@AndroidTvTorrentPlayerActivity.yieldEpisodeFetchToQueuedShuffle()
        },
    )
    private val sourceSwitchController: TvSourceSwitchController = TvSourceSwitchController(
        this,
        object : TvSourceSwitchController.Host {
            override var activeVodHeaders: Pair<Set<String>, Map<String, String>>
                get() = this@AndroidTvTorrentPlayerActivity.activeVodHeaders
                set(value) { this@AndroidTvTorrentPlayerActivity.activeVodHeaders = value }
            override fun armStartupCandidate(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.startupGateController.armStartupCandidate(sourceIndex)
            override fun attemptPikPakPlaybackLoop(item: PlaybackItem, attemptNumber: Int, retryId: Int): Unit = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.attemptPikPakPlaybackLoop(item, attemptNumber, retryId)
            override fun beginManualSourceCandidate(sourceIndex: Int): Unit = this@AndroidTvTorrentPlayerActivity.startupGateController.beginManualSourceCandidate(sourceIndex)
            override fun buildMergedSource(videoUrl: String, audioUrl: String): MergingMediaSource? = this@AndroidTvTorrentPlayerActivity.buildMergedSource(videoUrl, audioUrl)
            override fun cancelPikPakRetry(): Unit = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.cancelPikPakRetry()
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
            override fun hideControlsMenu(): Unit = this@AndroidTvTorrentPlayerActivity.controlsOverlayController.hideControlsMenu()
            override fun hidePikPakRetryOverlay(): Unit = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.hidePikPakRetryOverlay()
            override fun hideStatusPill(): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.hideStatusPill()
            override val iptvChannelStartController: TvIptvChannelStartController get() = this@AndroidTvTorrentPlayerActivity.iptvChannelStartController
            override val isIptvMode: Boolean get() = this@AndroidTvTorrentPlayerActivity.isIptvMode
            override var isPikPakRetrying: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.isPikPakRetrying
                set(value) { this@AndroidTvTorrentPlayerActivity.pikPakRetryController.isPikPakRetrying = value }
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
            override val ottSourcesButton: AppCompatButton? get() = this@AndroidTvTorrentPlayerActivity.controlsDockController.ottSourcesButton
            override val payload: PlaybackPayload? get() = this@AndroidTvTorrentPlayerActivity.payload
            override var percentSeekApplied: Boolean
                get() = this@AndroidTvTorrentPlayerActivity.percentSeekApplied
                set(value) { this@AndroidTvTorrentPlayerActivity.percentSeekApplied = value }
            override var pikPakRetryCount: Int
                get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.pikPakRetryCount
                set(value) { this@AndroidTvTorrentPlayerActivity.pikPakRetryController.pikPakRetryCount = value }
            override var pikPakRetryId: Int
                get() = this@AndroidTvTorrentPlayerActivity.pikPakRetryController.pikPakRetryId
                set(value) { this@AndroidTvTorrentPlayerActivity.pikPakRetryController.pikPakRetryId = value }
            override fun playItem(index: Int, suppressTrakt: Boolean, suppressResume: Boolean, shuffleAttempt: ShufflePlaybackAttempt?): Unit = this@AndroidTvTorrentPlayerActivity.playItem(index, suppressTrakt, suppressResume, shuffleAttempt)
            override val player: ExoPlayer? get() = this@AndroidTvTorrentPlayerActivity.player
            override val progressHandler: Handler get() = this@AndroidTvTorrentPlayerActivity.progressHandler
            override fun rebuildPlaylistContent(): Unit = this@AndroidTvTorrentPlayerActivity.playlistController.rebuildPlaylistContent()
            override fun requestMetadataFromFlutter(): Unit = this@AndroidTvTorrentPlayerActivity.requestMetadataFromFlutter()
            override var resumeHoldArmedAtMs: Long
                get() = this@AndroidTvTorrentPlayerActivity.resumeHoldArmedAtMs
                set(value) { this@AndroidTvTorrentPlayerActivity.resumeHoldArmedAtMs = value }
            override fun showStatusPill(text: String): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.showStatusPill(text)
            override fun showStatusPillTransient(text: String): Unit = this@AndroidTvTorrentPlayerActivity.statusPillController.showStatusPillTransient(text)
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
            if (liveEntry != null && iptvTuneController.trial.restoreParkedIptvTwinIfNeeded()) {
                // Restored and started by setIptvMediaItem.
            } else if (liveEntry != null &&
                !iptvStartOverActive &&
                iptvStoppedAtRealtime > 0L &&
                awayMs > IPTV_LIVE_REJOIN_AFTER_MS
            ) {
                player?.playWhenReady = true // eligibility reads this
                iptvTuneController.iptvLiveRecovery.userRetry("lifecycle-rejoin")
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
        if (!iptvTuneController.trial.parkIptvTwinTrialRestore()) iptvTuneController.trial.clearIptvTwinTrial()
        iptvTuneController.iptvLiveRecovery.cancel()
        iptvTuneController.hideIptvReconnectPill()
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
                if (iptvGuideController.iptvGuideVisible) {
                    iptvGuideController.hideIptvGuide()
                    return
                }

                // If playlist is visible, hide it first
                if (playlistOverlay.visibility == View.VISIBLE) {
                    playlistController.hidePlaylist()
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
        pikPakRetryController.cancelPikPakRetry()
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
        displayController.displayModeController?.clear()
        displayController.displayModeController = null
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
        iptvTuneController.trial.clearIptvTwinTrial()
        iptvTuneController.iptvLiveRecovery.cancel()
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
        iptvGuideChromeController.iptvEpgToken++
        iptvGuideController.iptvUiContextToken++
        iptvGuideController.iptvBrowseToken++
        iptvGuideController.iptvZapRequestToken++
        iptvGuideController.iptvZapRequestInFlight = false
        iptvGuideController.iptvZapPendingInputs.clear()

        // Cancel PikPak retry operations
        pikPakRetryController.cancelPikPakRetry()
        pikPakRetryController.pikPakRetryHandler.removeCallbacksAndMessages(null)

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
        subtitleSourcesController.stremioSubtitles.clear()
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
        controlsOverlayController.controlsHandler.removeCallbacksAndMessages(null)
        controlsOverlayController.seek.seekbarHandler.removeCallbacksAndMessages(null)

        // Release night mode audio effect
        displayController.releaseLoudnessEnhancer()

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
        playlistController.playlistAdapter = null
        playlistController.seriesPlaylistAdapter = null
        playlistController.moviePlaylistAdapter = null

        // Clean up Stremio sources
        playlistController.navigator.focusRecoveryHandler.removeCallbacksAndMessages(null)
        playlistController.navigator.focusRecoveryRunnable = null
        sourceSwitchController.cancelSourceSwitchWait()
        stremioSources.clear()

        // Clear tab references
        playlistController.seasonTabs.clear()
        playlistController.movieTabs.clear()

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
        controlsOverlayController.identity.ottShowName = null

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
            controlsDockController.ottSourcesButton?.visibility =
                if (stremioSources.isEmpty()) View.GONE else View.VISIBLE
        } else if (stremioSources.isNotEmpty()) {
            stremioSourceBadge?.visibility = View.VISIBLE
        } else {
            stremioSourceBadge?.visibility = View.GONE
        }

        subtitleSourcesController.resetSubtitleState()
        subtitleSourcesController.clearStremioLoadingState()
        pikPakRetryController.cancelPikPakRetry()

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

        controlsOverlayController.identity.updateTitle(playbackItem)
        subtitleSourcesController.fetchStremioSubtitles(playbackItem)

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
        // Resume hold (see resumeHoldTargetMs): landing tolerance (seeks
        // resolve to keyframes) and how long an unlanded target keeps
        // substituting before real playback wins.
        private const val RESUME_HOLD_TOLERANCE_MS = 10_000L
        private const val RESUME_HOLD_SETTLE_MS = 30_000L
        private const val PROGRESS_INTERVAL_MS = 5_000L
        private const val SEEK_STEP_MS = 10_000L
        private const val SEEK_LONG_PRESS_THRESHOLD = 3
        private const val BACK_PRESS_INTERVAL_MS = 2000L  // 2 seconds
    }
}
