package com.debrify.app.tv

import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
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
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import android.media.audiofx.LoudnessEnhancer
import com.debrify.app.MainActivity
import com.debrify.app.R
import com.debrify.app.util.SubtitleSettings
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

    // Seek feedback manager
    private lateinit var seekFeedbackManager: SeekFeedbackManager

    // State
    private var payload: PlaybackPayload? = null
    private var currentIndex = 0
    private var pendingSeekMs: Long = 0
    private var controlsMenuVisible = false
    private var playlistVisible = false
    private var seekbarVisible = false
    private var seekbarPosition: Long = 0
    private var videoDuration: Long = 0
    private var resizeModeIndex = 1  // Fill by default
    private var playbackSpeedIndex = 2  // 1.0x
    private var nightModeIndex = 2  // Medium by default
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var playlistMode: PlaylistMode = PlaylistMode.NONE
    private var playlistAdapter: PlaylistOverlayAdapter? = null
    private var seriesPlaylistAdapter: PlaylistAdapter? = null
    private var moviePlaylistAdapter: MoviePlaylistAdapter? = null
    private var movieGroups: MovieGroups? = null
    private var lastBackPressTime: Long = 0

    // Subtitle Settings Panel
    private var subtitleSettingsRoot: View? = null
    private var subtitleSettingsVisible = false
    private var subtitleColumnTrack: View? = null
    private var subtitleColumnSize: View? = null
    private var subtitleColumnStyle: View? = null
    private var subtitleColumnColor: View? = null
    private var subtitleColumnBg: View? = null
    private var subtitleResetButton: View? = null
    private var subtitleValueTrack: TextView? = null
    private var subtitleValueSize: TextView? = null
    private var subtitleValueStyle: TextView? = null
    private var subtitleValueColor: TextView? = null
    private var subtitleValueBg: TextView? = null
    private var subtitleColorSwatch: View? = null
    private var subtitlePreviewText: TextView? = null
    private var subtitleTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()
    private var currentSubtitleTrackIndex = 0

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

    private val progressRunnable = object : Runnable {
        override fun run() {
            sendProgress(completed = false)
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
                    if (pendingSeekMs > 0) {
                        val duration = player?.duration ?: 0
                        if (duration > 0 && pendingSeekMs < duration) {
                            player?.seekTo(pendingSeekMs)
                        }
                        pendingSeekMs = 0
                    }
                    // Initialize night mode if needed
                    if (loudnessEnhancer == null && nightModeIndex > 0) {
                        initializeLoudnessEnhancer()
                    }
                }
                Player.STATE_ENDED -> {
                    sendProgress(completed = true)
                    val model = payload ?: return
                    val nextIndex = getNextPlayableIndex(currentIndex)
                    if (nextIndex != null) {
                        showNextOverlay(model.items[nextIndex])
                        progressHandler.postDelayed({
                            hideNextOverlay()
                            playItem(nextIndex)
                        }, 1500)
                    } else {
                        finish()
                    }
                }
            }
            updatePauseButtonLabel()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updatePauseButtonLabel()
        }

        override fun onAudioSessionIdChanged(audioSessionId: Int) {
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
        payload = parsePayload(rawPayload)
        if (payload == null || payload!!.items.isEmpty()) {
            finish()
            return
        }
        currentIndex = payload!!.startIndex.coerceIn(0, payload!!.items.lastIndex)

        bindViews()
        setupPlayer()
        setupSeekbar()
        setupPlaylist()
        setupControls()

        // Initialize seek feedback manager
        seekFeedbackManager = SeekFeedbackManager(findViewById(android.R.id.content))
        setupBackPressHandler()
        setupMetadataReceiver()

        // Start playback
        playItem(currentIndex)
    }

    private fun setupMetadataReceiver() {
        metadataUpdateReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
                val updatesJson = intent?.getStringExtra("metadataUpdates") ?: return
                handleMetadataUpdate(updatesJson)
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

    private fun handleMetadataUpdate(updatesJson: String) {
        android.util.Log.d("TVMazeUpdate", "handleMetadataUpdate CALLED")
        android.util.Log.d("TVMazeUpdate", "updatesJson length=${updatesJson.length}")
        try {
            val updatesArray = JSONArray(updatesJson)
            android.util.Log.d("TVMazeUpdate", "Parsed ${updatesArray.length()} updates")

            val model = payload
            if (model == null) {
                android.util.Log.e("TVMazeUpdate", "payload is NULL - cannot update")
                return
            }
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
        seekbarOverlay = findViewById(R.id.seekbar_overlay)
        seekbarProgress = findViewById(R.id.seekbar_progress)
        seekbarHandle = findViewById(R.id.seekbar_handle)
        seekbarCurrentTime = findViewById(R.id.seekbar_current_time)
        seekbarTotalTime = findViewById(R.id.seekbar_total_time)
        seekbarSpeedIndicator = findViewById(R.id.seekbar_speed_indicator)

        // Subtitle Settings Panel
        subtitleSettingsRoot = findViewById(R.id.subtitle_settings_root)
        subtitleColumnTrack = findViewById(R.id.subtitle_column_track)
        subtitleColumnSize = findViewById(R.id.subtitle_column_size)
        subtitleColumnStyle = findViewById(R.id.subtitle_column_style)
        subtitleColumnColor = findViewById(R.id.subtitle_column_color)
        subtitleColumnBg = findViewById(R.id.subtitle_column_bg)
        subtitleValueTrack = findViewById(R.id.subtitle_value_track)
        subtitleValueSize = findViewById(R.id.subtitle_value_size)
        subtitleValueStyle = findViewById(R.id.subtitle_value_style)
        subtitleValueColor = findViewById(R.id.subtitle_value_color)
        subtitleValueBg = findViewById(R.id.subtitle_value_bg)
        subtitleColorSwatch = findViewById(R.id.subtitle_color_swatch)
        subtitlePreviewText = findViewById(R.id.subtitle_preview_text)
        subtitleResetButton = findViewById(R.id.subtitle_reset_button)
    }

    private fun setupPlayer() {
        trackSelector = DefaultTrackSelector(this)
        trackSelector?.parameters = trackSelector?.buildUponParameters()
            ?.setPreferredAudioLanguage("en")
            ?.setPreferredTextLanguage("en")
            ?.setPreferredAudioMimeType("audio/opus")
            ?.setIgnoredTextSelectionFlags(C.SELECTION_FLAG_DEFAULT)
            ?.build()!!

        val renderersFactory = DefaultRenderersFactory(this)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            .setEnableDecoderFallback(true)

        player = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector!!)
            .setHandleAudioBecomingNoisy(true)
            .build()

        player?.addListener(playbackListener)
        playerView.player = player

        // Hide internal subtitle view, use custom one
        playerView.subtitleView?.visibility = View.GONE

        // Connect subtitle output to custom view
        subtitleListener = object : Player.Listener {
            override fun onCues(cueGroup: androidx.media3.common.text.CueGroup) {
                subtitleOverlay.setCues(cueGroup.cues)
            }
        }
        player?.addListener(subtitleListener!!)

        // Setup subtitle styling from saved preferences
        subtitleOverlay.setApplyEmbeddedStyles(false)
        subtitleOverlay.setApplyEmbeddedFontSizes(false)
        subtitleOverlay.setBottomPaddingFraction(0.0f)
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
        val randomButton: AppCompatButton? = playerView.findViewById(R.id.debrify_random_button)

        // Time display views (Cinema Mode)
        debrifyTimeDisplay = playerView.findViewById(R.id.debrify_time_display)  // Legacy (hidden)
        debrifyTimeCurrent = playerView.findViewById(R.id.debrify_time_current)  // Current time
        debrifyTimeTotal = playerView.findViewById(R.id.debrify_time_total)      // Total time
        debrifyProgressLine = playerView.findViewById(R.id.debrify_progress_line)

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
            showNightModeDialog()
        }
        nightModeButton?.onFocusChangeListener = extendTimerOnFocus
        updateNightModeButtonLabel()

        audioButton?.setOnClickListener {
            showAudioTrackDialog()
            scheduleHideControlsMenu()
        }
        audioButton?.onFocusChangeListener = extendTimerOnFocus

        subtitleButton?.setOnClickListener {
            hideControlsMenu()
            showSubtitleSettingsPanel()
        }
        subtitleButton?.onFocusChangeListener = extendTimerOnFocus

        aspectButton?.setOnClickListener {
            cycleAspectRatio()
            scheduleHideControlsMenu()
        }
        aspectButton?.onFocusChangeListener = extendTimerOnFocus
        updateAspectButtonLabel()

        speedButton?.setOnClickListener {
            cyclePlaybackSpeed()
            scheduleHideControlsMenu()
        }
        speedButton?.onFocusChangeListener = extendTimerOnFocus

        playlistButton?.setOnClickListener {
            hideControlsMenu()
            showPlaylist()
        }
        playlistButton?.onFocusChangeListener = extendTimerOnFocus

        nextButton?.setOnClickListener {
            hideControlsMenu()
            playNext()
        }
        nextButton?.onFocusChangeListener = extendTimerOnFocus

        randomButton?.setOnClickListener {
            hideControlsMenu()
            playRandom()
        }
        randomButton?.onFocusChangeListener = extendTimerOnFocus
    }

    private fun playItem(index: Int) {
        val model = payload ?: return
        android.util.Log.d("AndroidTvPlayer", "playItem called - index: $index, total items: ${model.items.size}")

        if (index < 0 || index >= model.items.size) {
            android.util.Log.e("AndroidTvPlayer", "playItem - index out of bounds! index: $index, size: ${model.items.size}")
            return
        }

        // Cancel any ongoing PikPak retry before starting new item
        cancelPikPakRetry()

        currentIndex = index
        val item = model.items[index]
        android.util.Log.d("AndroidTvPlayer", "playItem - item found: title=${item.title}, season=${item.season}, episode=${item.episode}, url=${item.url}, resumeId=${item.resumeId}")
        pendingSeekMs = item.resumePositionMs

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
        val isPikPak = PROVIDER_PIKPAK.equals(item.provider, ignoreCase = true)
        android.util.Log.d("AndroidTvPlayer", "startPlayback - provider: ${item.provider}, isPikPak: $isPikPak")

        if (isPikPak) {
            android.util.Log.d("AndroidTvPlayer", "startPlayback - using PikPak retry logic")
            playPikPakVideoWithRetry(item)
        } else {
            android.util.Log.d("AndroidTvPlayer", "startPlayback - using direct playback")
            playMediaDirect(item)
        }
    }

    private fun playMediaDirect(item: PlaybackItem) {
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
            playWhenReady = true
            play()
        }

        updateTitle(item)
        playlistAdapter?.setActiveIndex(currentIndex)
        restartProgressUpdates()
    }

    private fun playNext() {
        val nextIndex = getNextPlayableIndex(currentIndex)
        if (nextIndex != null) {
            playItem(nextIndex)
        } else {
            Toast.makeText(this, "End of playlist", Toast.LENGTH_SHORT).show()
        }
    }

    private fun playRandom() {
        val model = payload ?: return
        if (model.items.isEmpty()) {
            Toast.makeText(this, "No items in playlist", Toast.LENGTH_SHORT).show()
            return
        }

        val randomIndex = (0 until model.items.size).random()
        playItem(randomIndex)
    }

    private fun updateTitle(item: PlaybackItem) {
        // Always set the simple title (used when controls not visible)
        titleView.text = item.title

        // Pre-populate OTT fields for when controls menu is shown
        val model = payload
        if (model?.contentType?.lowercase(java.util.Locale.US) == "series") {
            if (item.season != null && item.episode != null) {
                val seasonStr = item.season.toString().padStart(2, '0')
                val episodeStr = item.episode.toString().padStart(2, '0')
                ottEpisodeBadge.text = "S$seasonStr E$episodeStr"
            }
            ottEpisodeTitle.text = item.title

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
            nextText.text = "📺 TUNING STREAM..."
            nextSubtext.visibility = View.GONE
            nextOverlay.visibility = View.VISIBLE
        } else {
            nextOverlay.visibility = View.GONE
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

    // PikPak Cold Storage Retry Logic
    // PikPak uses "cold storage" where files that haven't been accessed recently need 10-30 seconds
    // to reactivate. This implements retry logic with exponential backoff.

    private fun playPikPakVideoWithRetry(item: PlaybackItem) {
        android.util.Log.d("AndroidTvPlayer", "PikPak: Starting retry logic for cold storage handling")

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
            nextText.text = message
            nextSubtext.visibility = View.GONE
            nextOverlay.visibility = View.VISIBLE
        }
    }

    private fun hidePikPakRetryOverlay() {
        runOnUiThread {
            nextOverlay.visibility = View.GONE
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

                    // Find and select default subtitle track
                    val trackSelector = trackSelector ?: return
                    val params = trackSelector.parameters

                    for (trackGroup in tracks.groups) {
                        if (trackGroup.type == C.TRACK_TYPE_TEXT) {
                            for (i in 0 until trackGroup.length) {
                                val format = trackGroup.getTrackFormat(i)
                                if (format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0) {
                                    // Found default subtitle track
                                    val override = TrackSelectionOverride(
                                        trackGroup.mediaTrackGroup,
                                        listOf(i)
                                    )
                                    trackSelector.parameters = params.buildUpon()
                                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                        .addOverride(override)
                                        .build()
                                    android.util.Log.d("AndroidTvPlayer", "PikPak: Default subtitle track selected")
                                    return
                                }
                            }
                        }
                    }
                }
            })
        }
    }

    // D-pad navigation
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode

        // Handle subtitle settings panel
        if (subtitleSettingsVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_BACK -> {
                        hideSubtitleSettingsPanel()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        cycleSubtitleValueUp()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_DOWN -> {
                        cycleSubtitleValueDown()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                        handleSubtitlePanelSelect()
                        return true
                    }
                }
            }
            // Let left/right navigation work normally for focus
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

        if (controlsMenuVisible && keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
            hideControlsMenu()
            return true
        }

        val focusInControls = isFocusInControlsOverlay()

        // Center button - play/pause
        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER) {
            if (focusInControls) {
                return super.dispatchKeyEvent(event)
            }
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                handlePlayPauseToggleFromCenter()
            }
            return true
        }

        // Down button - show controls menu
        if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
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

        // Up button - from dock go to progress bar, otherwise show playlist
        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
            // If focus is in controls dock, UP goes to progress bar
            if (focusInControls && controlsMenuVisible && !cinemaSeekMode) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    cinemaProgressContainer?.requestFocus()
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

        // Left/Right - seek
        if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
            if (focusInControls) {
                return super.dispatchKeyEvent(event)
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
            Toast.makeText(this, "Seeking not available", Toast.LENGTH_SHORT).show()
            pauseButton?.requestFocus()
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
        nextText.text = "📺 LOADING NEXT..."
        nextSubtext.text = nextItem.title
        nextSubtext.visibility = View.VISIBLE
        nextOverlay.visibility = View.VISIBLE
    }

    private fun hideNextOverlay() {
        nextOverlay.visibility = View.GONE
    }

    // Track selection
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

    private fun showSubtitleSettingsPanel() {
        // Collect available subtitle tracks
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

        // Check if no subtitle is currently selected (means "Off")
        val hasSelectedSubtitle = tracks?.groups?.any { group ->
            group.type == C.TRACK_TYPE_TEXT && (0 until group.length).any { group.isTrackSelected(it) }
        } ?: false
        if (!hasSelectedSubtitle) {
            currentSubtitleTrackIndex = 0
        }

        // Update UI values
        updateSubtitlePanelValues()

        // Show panel
        subtitleSettingsRoot?.visibility = View.VISIBLE
        subtitleSettingsVisible = true

        // Focus first column
        subtitleColumnTrack?.requestFocus()
    }

    private fun hideSubtitleSettingsPanel() {
        subtitleSettingsRoot?.visibility = View.GONE
        subtitleSettingsVisible = false
        if (::playerView.isInitialized) {
            playerView.requestFocus()
        }
    }

    private fun updateSubtitlePanelValues() {
        // Track
        subtitleValueTrack?.text = if (subtitleTracks.isNotEmpty() && currentSubtitleTrackIndex < subtitleTracks.size) {
            subtitleTracks[currentSubtitleTrackIndex].first
        } else {
            "Off"
        }

        // Size
        subtitleValueSize?.text = SubtitleSettings.getCurrentSize(this).label

        // Style
        subtitleValueStyle?.text = SubtitleSettings.getCurrentStyle(this).label

        // Color
        val colorOption = SubtitleSettings.getCurrentColor(this)
        subtitleValueColor?.text = colorOption.label
        subtitleColorSwatch?.backgroundTintList = android.content.res.ColorStateList.valueOf(colorOption.color)

        // Background
        subtitleValueBg?.text = SubtitleSettings.getCurrentBg(this).label

        // Update preview
        updateSubtitlePreview()
    }

    private fun updateSubtitlePreview() {
        val colorOption = SubtitleSettings.getCurrentColor(this)
        val styleOption = SubtitleSettings.getCurrentStyle(this)
        val sizeOption = SubtitleSettings.getCurrentSize(this)
        val bgOption = SubtitleSettings.getCurrentBg(this)

        subtitlePreviewText?.apply {
            setTextColor(colorOption.color)
            textSize = sizeOption.sizeSp

            // Apply shadow based on edge style
            when (styleOption.edgeType) {
                CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW -> {
                    setShadowLayer(4f, 2f, 2f, Color.BLACK)
                }
                CaptionStyleCompat.EDGE_TYPE_OUTLINE -> {
                    setShadowLayer(2f, 1f, 1f, Color.BLACK)
                }
                else -> {
                    setShadowLayer(0f, 0f, 0f, Color.TRANSPARENT)
                }
            }

            // Background
            if (bgOption.color != Color.TRANSPARENT) {
                setBackgroundColor(bgOption.color)
                setPadding(8, 4, 8, 4)
            } else {
                setBackgroundColor(Color.TRANSPARENT)
                setPadding(0, 0, 0, 0)
            }
        }
    }

    private fun cycleSubtitleValueUp() {
        val focusedView = currentFocus ?: return

        when (focusedView.id) {
            R.id.subtitle_column_track -> {
                // Track uses dialog, no cycling
                return
            }
            R.id.subtitle_column_size -> {
                SubtitleSettings.cycleSizeUp(this)
            }
            R.id.subtitle_column_style -> {
                SubtitleSettings.cycleStyleUp(this)
            }
            R.id.subtitle_column_color -> {
                SubtitleSettings.cycleColorUp(this)
            }
            R.id.subtitle_column_bg -> {
                SubtitleSettings.cycleBgUp(this)
            }
            R.id.subtitle_reset_button -> {
                // Reset button doesn't cycle
                return
            }
        }

        updateSubtitlePanelValues()
        applySubtitleSettings()
    }

    private fun cycleSubtitleValueDown() {
        val focusedView = currentFocus ?: return

        when (focusedView.id) {
            R.id.subtitle_column_track -> {
                // Track uses dialog, no cycling
                return
            }
            R.id.subtitle_column_size -> {
                SubtitleSettings.cycleSizeDown(this)
            }
            R.id.subtitle_column_style -> {
                SubtitleSettings.cycleStyleDown(this)
            }
            R.id.subtitle_column_color -> {
                SubtitleSettings.cycleColorDown(this)
            }
            R.id.subtitle_column_bg -> {
                SubtitleSettings.cycleBgDown(this)
            }
            R.id.subtitle_reset_button -> {
                // Reset button doesn't cycle
                return
            }
        }

        updateSubtitlePanelValues()
        applySubtitleSettings()
    }

    private fun handleSubtitlePanelSelect() {
        val focusedView = currentFocus ?: return

        when (focusedView.id) {
            R.id.subtitle_column_track -> {
                showSubtitleTrackSelectionDialog()
            }
            R.id.subtitle_reset_button -> {
                resetSubtitleSettings()
            }
        }
    }

    private fun showSubtitleTrackSelectionDialog() {
        if (subtitleTracks.isEmpty()) {
            Toast.makeText(this, "No subtitle tracks available", Toast.LENGTH_SHORT).show()
            return
        }

        val labels = subtitleTracks.map { it.first }.toTypedArray()
        AlertDialog.Builder(this)
            .setTitle("Select Subtitle Track")
            .setSingleChoiceItems(labels, currentSubtitleTrackIndex) { dialog, which ->
                currentSubtitleTrackIndex = which
                applySelectedSubtitleTrack()
                updateSubtitlePanelValues()
                dialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun resetSubtitleSettings() {
        SubtitleSettings.resetToDefaults(this)
        updateSubtitlePanelValues()
        applySubtitleSettings()
        Toast.makeText(this, "Subtitle settings reset to defaults", Toast.LENGTH_SHORT).show()
    }

    private fun applySelectedSubtitleTrack() {
        val ts = trackSelector ?: return
        val override = subtitleTracks.getOrNull(currentSubtitleTrackIndex)?.second

        val params = ts.parameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
        if (override != null) {
            params.setOverrideForType(override)
            params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
        } else {
            params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        }
        ts.parameters = params.build()
    }

    private fun applySubtitleSettings() {
        subtitleOverlay.setFixedTextSize(
            TypedValue.COMPLEX_UNIT_SP,
            SubtitleSettings.getFontSizeSp(this)
        )
        subtitleOverlay.setStyle(SubtitleSettings.buildCaptionStyle(this))
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
        val model = payload ?: return
        val item = model.items[currentIndex]
        val position = if (completed) player?.duration ?: 0 else player?.currentPosition ?: 0
        val duration = player?.duration ?: 0

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
            "url" to item.url
        )

        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("torrentPlaybackProgress", map)
    }

    private fun sendFinished() {
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("torrentPlaybackFinished", null)
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

            android.util.Log.d("AndroidTvPlayer", "parsePayload - startIndex: $startIndex, items: ${items.size}, nextMap: ${nextEpisodeMap.size}, prevMap: ${prevEpisodeMap.size}, collectionGroups: ${collectionGroups?.size ?: 0}")

            PlaybackPayload(
                title = obj.optString("title"),
                subtitle = obj.optString("subtitle"),
                contentType = obj.optString("contentType", "single"),
                items = items,
                startIndex = startIndex,
                seriesTitle = obj.optString("seriesTitle"),
                nextEpisodeMap = nextEpisodeMap,
                prevEpisodeMap = prevEpisodeMap,
                collectionGroups = collectionGroups
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "parsePayload failed", e)
            null
        }
    }

    override fun onStart() {
        super.onStart()
        player?.play()
    }

    override fun onStop() {
        super.onStop()
        player?.pause()
    }

    private fun setupBackPressHandler() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
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

    override fun onPause() {
        super.onPause()
        // Cancel any ongoing PikPak retry operations
        cancelPikPakRetry()
    }

    override fun onDestroy() {
        // Clean up seek feedback manager
        if (::seekFeedbackManager.isInitialized) {
            seekFeedbackManager.destroy()
        }

        // Cancel PikPak retry operations
        cancelPikPakRetry()
        pikPakRetryHandler.removeCallbacksAndMessages(null)

        // Unregister broadcast receiver
        metadataUpdateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                android.util.Log.w("AndroidTvPlayer", "Failed to unregister metadata receiver", e)
            }
        }
        metadataUpdateReceiver = null

        // Clear all handlers
        progressHandler.removeCallbacksAndMessages(null)
        titleHandler.removeCallbacksAndMessages(null)
        controlsHandler.removeCallbacksAndMessages(null)
        seekbarHandler.removeCallbacksAndMessages(null)

        // Release night mode audio effect
        releaseLoudnessEnhancer()

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

        // Clear adapters to release lambda references
        playlistView.adapter = null
        playlistAdapter = null
        seriesPlaylistAdapter = null
        moviePlaylistAdapter = null

        // Clear tab references
        seasonTabs.clear()
        movieTabs.clear()

        // Clear view listeners
        seekbarOverlay.setOnKeyListener(null)

        sendFinished()
        super.onDestroy()
    }

    companion object {
        const val PAYLOAD_KEY = "payload"
        private const val PROGRESS_INTERVAL_MS = 5_000L
        private const val TITLE_FADE_DELAY_MS = 4000L
        private const val CONTROLS_AUTO_HIDE_DELAY_MS = 4000L
        private const val SEEK_STEP_MS = 10_000L
        private const val SEEK_LONG_PRESS_THRESHOLD = 3
        private const val BACK_PRESS_INTERVAL_MS = 2000L  // 2 seconds

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

private data class PlaybackPayload(
    val title: String,
    val subtitle: String?,
    val contentType: String,
    val items: MutableList<PlaybackItem>,
    val startIndex: Int,
    val seriesTitle: String?,
    val nextEpisodeMap: Map<Int, Int> = emptyMap(),
    val prevEpisodeMap: Map<Int, Int> = emptyMap(),
    val collectionGroups: List<JSONObject>? = null // Collection groups from Flutter
)

private data class PlaybackItem(
    val id: String,
    val title: String,
    val url: String,
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

    companion object {
        fun fromJson(obj: JSONObject): PlaybackItem {
            return PlaybackItem(
                id = obj.optString("id"),
                title = obj.optString("title"),
                url = obj.optString("url"),
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
            )
        }
    }
}

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
            val progressPercent = if (item.durationMs > 0 && item.resumePositionMs > 0) {
                ((item.resumePositionMs.toDouble() / item.durationMs.toDouble()) * 100).toInt()
            } else 0

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
            val progressPercent = if (item.durationMs > 0 && item.resumePositionMs > 0) {
                ((item.resumePositionMs.toDouble() / item.durationMs.toDouble()) * 100).toInt()
            } else 0

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

            val progressPercent = if (item.durationMs > 0 && item.resumePositionMs > 0) {
                ((item.resumePositionMs.toDouble() / item.durationMs.toDouble()) * 100).toInt()
            } else {
                0
            }

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
            val progressPercent = if (item.durationMs > 0 && item.resumePositionMs > 0) {
                ((item.resumePositionMs.toDouble() / item.durationMs.toDouble()) * 100).toInt()
            } else {
                0
            }

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
