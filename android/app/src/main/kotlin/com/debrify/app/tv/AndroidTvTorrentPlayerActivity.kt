package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
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
import com.debrify.app.MainActivity
import com.debrify.app.R
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
    private var seekButton: AppCompatButton? = null

    // Player
    private var player: ExoPlayer? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var subtitleListener: Player.Listener? = null

    // State
    private var payload: PlaybackPayload? = null
    private var currentIndex = 0
    private var pendingSeekMs: Long = 0
    private var controlsMenuVisible = false
    private var playlistVisible = false
    private var seekbarVisible = false
    private var seekbarPosition: Long = 0
    private var videoDuration: Long = 0
    private var resizeModeIndex = 0
    private var playbackSpeedIndex = 2  // 1.0x
    private var playlistMode: PlaylistMode = PlaylistMode.NONE
    private var playlistAdapter: PlaylistOverlayAdapter? = null
    private var seriesPlaylistAdapter: PlaylistAdapter? = null
    private var moviePlaylistAdapter: MoviePlaylistAdapter? = null
    private var movieGroups: MovieGroups? = null
    private var lastBackPressTime: Long = 0

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

    // Handlers
    private val progressHandler = Handler(Looper.getMainLooper())
    private val titleHandler = Handler(Looper.getMainLooper())
    private val controlsHandler = Handler(Looper.getMainLooper())

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
    }

    // Broadcast receiver for async metadata updates from Flutter
    private var metadataUpdateReceiver: android.content.BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_android_tv_torrent_player)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Parse payload
        val rawPayload = intent.getStringExtra(PAYLOAD_KEY)
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
                val newTitle = update.optString("title", null)
                val newDescription = update.optString("description", null)
                val newArtwork = update.optString("artwork", null)
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
    }

    private fun setupPlayer() {
        trackSelector = DefaultTrackSelector(this)
        trackSelector?.parameters = trackSelector?.buildUponParameters()
            ?.setPreferredAudioLanguage("en")
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

        // Setup subtitle styling
        subtitleOverlay.setApplyEmbeddedStyles(false)
        subtitleOverlay.setApplyEmbeddedFontSizes(false)
        subtitleOverlay.setBottomPaddingFraction(0.0f)
        subtitleOverlay.setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        subtitleOverlay.setStyle(CaptionStyleCompat(
            Color.WHITE,
            Color.TRANSPARENT,
            Color.TRANSPARENT,
            CaptionStyleCompat.EDGE_TYPE_OUTLINE,
            Color.BLACK,
            Typeface.create("sans-serif", Typeface.NORMAL)
        ))

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
        tab.textSize = 14f
        tab.setTextColor(0xFFFFFFFF.toInt())
        tab.setPadding(32, 16, 32, 16)
        tab.setBackgroundResource(R.drawable.season_tab_selector)
        tab.isFocusable = true
        tab.isFocusableInTouchMode = true

        val params = android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.marginEnd = 12
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

        val tabs = mutableListOf<MovieGroup>()
        tabs.add(MovieGroup.MAIN)
        if (groups.extras.isNotEmpty()) {
            tabs.add(MovieGroup.EXTRAS)
        }

        if (tabs.size <= 1) {
            seasonTabsContainer.visibility = View.GONE
            // Ensure adapter still shows main group
            adapter.showGroup(MovieGroup.MAIN, force = true)
            return
        }

        seasonTabsContainer.visibility = View.VISIBLE

        tabs.forEach { group ->
            val label = if (group == MovieGroup.MAIN) {
                "MAIN (${groups.main.size})"
            } else {
                "EXTRAS (${groups.extras.size})"
            }
            val tab = createMovieTab(label, group, adapter)
            seasonTabsContainer.addView(tab)
            movieTabs.add(MovieTab(tab, group))
        }

        selectMovieTab(MovieGroup.MAIN, adapter, scrollToTop = false, forceAdapterUpdate = true)
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

    private fun createMovieTab(label: String, group: MovieGroup, adapter: MoviePlaylistAdapter): TextView {
        val tab = TextView(this)
        tab.text = label
        tab.textSize = 14f
        tab.setTextColor(0xFFFFFFFF.toInt())
        tab.setPadding(32, 16, 32, 16)
        tab.setBackgroundResource(R.drawable.season_tab_selector)
        tab.isFocusable = true
        tab.isFocusableInTouchMode = true

        val params = android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.marginEnd = 12
        tab.layoutParams = params

        tab.setOnClickListener {
            selectMovieTab(group, adapter)
        }

        return tab
    }

    private fun selectMovieTab(
        group: MovieGroup,
        adapter: MoviePlaylistAdapter,
        scrollToTop: Boolean = true,
        forceAdapterUpdate: Boolean = false,
    ) {
        movieTabs.forEach { movieTab ->
            movieTab.view.isSelected = movieTab.group == group
        }
        val changed = adapter.showGroup(group, force = forceAdapterUpdate)
        if ((scrollToTop || changed) && adapter.itemCount > 0) {
            playlistView.scrollToPosition(0)
        }
    }

    private fun setupControls() {
        controlsOverlay = playerView.findViewById(R.id.debrify_controls_root)
        pauseButton = playerView.findViewById(R.id.debrify_pause_button)
        seekButton = playerView.findViewById(R.id.debrify_seek_button)
        audioButton = playerView.findViewById(R.id.debrify_audio_button)
        subtitleButton = playerView.findViewById(R.id.debrify_subtitle_button)
        aspectButton = playerView.findViewById(R.id.debrify_aspect_button)
        speedButton = playerView.findViewById(R.id.debrify_speed_button)
        val guideButton: AppCompatButton? = playerView.findViewById(R.id.debrify_guide_button)
        val nextButton: AppCompatButton? = playerView.findViewById(R.id.debrify_next_button)
        val randomButton: AppCompatButton? = playerView.findViewById(R.id.debrify_random_button)

        controlsOverlay?.visibility = View.GONE
        controlsOverlay?.alpha = 0f

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

        seekButton?.setOnClickListener {
            hideControlsMenu()
            showSeekbar()
        }
        seekButton?.onFocusChangeListener = extendTimerOnFocus

        audioButton?.setOnClickListener {
            showAudioTrackDialog()
            scheduleHideControlsMenu()
        }
        audioButton?.onFocusChangeListener = extendTimerOnFocus

        subtitleButton?.setOnClickListener {
            showSubtitleTrackDialog()
            scheduleHideControlsMenu()
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

        guideButton?.setOnClickListener {
            hideControlsMenu()
            showPlaylist()
        }
        guideButton?.onFocusChangeListener = extendTimerOnFocus
        guideButton?.text = "Playlist"

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
        requestStreamFromFlutter(item, index) { url ->
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - received url: $url")
            setResolvingState(false)

            if (url.isNullOrEmpty()) {
                android.util.Log.e("AndroidTvPlayer", "resolveAndPlay - URL is null or empty!")
                Toast.makeText(this, "Unable to load stream", Toast.LENGTH_SHORT).show()
                return@requestStreamFromFlutter
            }

            // Update the item with resolved URL
            payload?.items?.set(index, item.copy(url = url))
            android.util.Log.d("AndroidTvPlayer", "resolveAndPlay - starting playback with resolved URL")
            startPlayback(payload!!.items[index])
        }
    }

    private fun startPlayback(item: PlaybackItem) {
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
        titleView.text = item.title
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

    private fun requestStreamFromFlutter(item: PlaybackItem, index: Int, callback: (String?) -> Unit) {
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
                        android.util.Log.d("AndroidTvPlayer", "requestStreamFromFlutter - extracted URL: $url")
                        callback(url)
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        android.util.Log.e("AndroidTvPlayer", "requestStreamFromFlutter - error: $errorCode - $errorMessage")
                        callback(null)
                    }

                    override fun notImplemented() {
                        android.util.Log.e("AndroidTvPlayer", "requestStreamFromFlutter - not implemented")
                        callback(null)
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "requestStreamFromFlutter - exception: ${e.message}", e)
            callback(null)
        }
    }

    // D-pad navigation
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode

        // Handle seekbar
        if (seekbarVisible) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekBackward(step)
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekForward(step)
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

        // Up button - show playlist
        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
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
                    if (!seekbarVisible) {
                        showSeekbar()
                    }
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
                    if (!seekbarVisible) {
                        showSeekbar()
                    }
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

        overlay.animate().cancel()

        if (!controlsMenuVisible) {
            controlsMenuVisible = true
            overlay.visibility = View.VISIBLE
            overlay.alpha = 0f
            overlay.animate()
                .alpha(1f)
                .setDuration(180)
                .withEndAction {
                    overlay.alpha = 1f
                }
                .start()
            pauseButton?.post {
                pauseButton?.requestFocus()
            }
        } else {
            overlay.alpha = 1f
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
            cancelScheduledHideControlsMenu()
            return
        }

        cancelScheduledHideControlsMenu()
        controlsMenuVisible = false
        overlay.animate()
            .alpha(0f)
            .setDuration(140)
            .withEndAction {
                if (!controlsMenuVisible) {
                    overlay.visibility = View.GONE
                    overlay.alpha = 0f
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

    // Seekbar
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

    private fun seekBackward(stepMs: Long = 10_000L) {
        seekbarPosition = (seekbarPosition - stepMs).coerceAtLeast(0)
        updateSeekSpeed(stepMs)
        updateSeekbarUI()
    }

    private fun seekForward(stepMs: Long = 10_000L) {
        seekbarPosition = (seekbarPosition + stepMs).coerceAtMost(videoDuration)
        updateSeekSpeed(stepMs)
        updateSeekbarUI()
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
        val group = if (groups.extras.contains(currentIndex)) MovieGroup.EXTRAS else MovieGroup.MAIN
        selectMovieTab(group, adapter, scrollToTop = false)
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
            val currentGroup = when {
                groups.main.contains(fromIndex) -> MovieGroup.MAIN
                groups.extras.contains(fromIndex) -> MovieGroup.EXTRAS
                else -> null
            }

            val source = when (currentGroup) {
                MovieGroup.MAIN -> groups.main
                MovieGroup.EXTRAS -> groups.extras
                else -> null
            }

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
            val currentGroup = when {
                groups.main.contains(fromIndex) -> MovieGroup.MAIN
                groups.extras.contains(fromIndex) -> MovieGroup.EXTRAS
                else -> null
            }

            val source = when (currentGroup) {
                MovieGroup.MAIN -> groups.main
                MovieGroup.EXTRAS -> groups.extras
                else -> null
            }

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
            return MovieGroups(emptyList(), emptyList())
        }

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

        return MovieGroups(main, extras)
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

            android.util.Log.d("AndroidTvPlayer", "parsePayload - startIndex: $startIndex, items: ${items.size}, nextMap: ${nextEpisodeMap.size}, prevMap: ${prevEpisodeMap.size}")

            PlaybackPayload(
                title = obj.optString("title"),
                subtitle = obj.optString("subtitle"),
                contentType = obj.optString("contentType", "single"),
                items = items,
                startIndex = startIndex,
                seriesTitle = obj.optString("seriesTitle"),
                nextEpisodeMap = nextEpisodeMap,
                prevEpisodeMap = prevEpisodeMap
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

    override fun onDestroy() {
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
    }
}

private enum class PlaylistMode { NONE, SERIES, COLLECTION }

private enum class MovieGroup { MAIN, EXTRAS }

private data class MovieGroups(
    val main: List<Int>,
    val extras: List<Int>,
)

private data class MovieTab(
    val view: TextView,
    val group: MovieGroup,
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
    val prevEpisodeMap: Map<Int, Int> = emptyMap()
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
                artwork = obj.optString("artwork", null),
                description = obj.optString("description", null),
                resumePositionMs = obj.optLong("resumePositionMs", 0),
                durationMs = obj.optLong("durationMs", 0),
                updatedAt = obj.optLong("updatedAt", 0),
                resumeId = obj.optString("resumeId", null),
                sizeBytes = if (obj.has("sizeBytes")) obj.optLong("sizeBytes") else null,
                rating = if (obj.has("rating")) obj.optDouble("rating") else null,
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

    // Episode ViewHolder with image loading
    class EpisodeViewHolder(
        itemView: View,
        private val onItemClick: (Int) -> Unit
    ) : RecyclerView.ViewHolder(itemView) {
        private val container: View = itemView.findViewById(R.id.android_tv_playlist_item_container)
        private val selectionOverlay: View? = itemView.findViewById(R.id.selection_overlay)
        private val posterImageView: android.widget.ImageView = itemView.findViewById(R.id.android_tv_playlist_item_poster)
        private val fallbackTextView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_fallback)
        private val watchedOverlay: View = itemView.findViewById(R.id.android_tv_playlist_item_watched_overlay)
        private val watchedIcon: TextView = itemView.findViewById(R.id.android_tv_playlist_item_watched_icon)
        private val posterProgress: android.widget.ProgressBar = itemView.findViewById(R.id.android_tv_playlist_item_poster_progress)
        private val badgeView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_badge)
        private val watchedView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_watched)
        private val playingView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_playing)
        private val titleView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_title)
        private val descriptionView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_description)
        private val progressContainer: View = itemView.findViewById(R.id.android_tv_playlist_item_progress_container)
        private val progressText: TextView = itemView.findViewById(R.id.android_tv_playlist_item_progress_text)
        private val ratingBadge: View = itemView.findViewById(R.id.android_tv_playlist_item_rating_badge)
        private val ratingText: TextView = itemView.findViewById(R.id.android_tv_playlist_item_rating_text)
        private val durationView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_duration)

        fun bind(item: PlaybackItem, itemIndex: Int, isActive: Boolean) {
            // Episode badge
            val badge = item.seasonEpisodeLabel().ifEmpty { "EP ${itemIndex + 1}" }
            badgeView.text = badge

            // Title from TVMaze (or fallback to item title)
            titleView.text = item.title

            // Description from TVMaze
            if (!item.description.isNullOrBlank()) {
                descriptionView.text = item.description
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

            // Duration (convert ms to minutes)
            if (item.durationMs > 0) {
                val durationMinutes = (item.durationMs / 60000).toInt()
                durationView.text = "• ${durationMinutes}m"
                durationView.visibility = View.VISIBLE
            } else {
                durationView.visibility = View.GONE
            }

            // Calculate progress percentage
            val progressPercent = if (item.durationMs > 0 && item.resumePositionMs > 0) {
                ((item.resumePositionMs.toDouble() / item.durationMs.toDouble()) * 100).toInt()
            } else {
                0
            }

            // Status indicators (Watched, Playing, or Progress)
            val isWatched = progressPercent >= 95

            // Gray out watched episodes
            container.alpha = if (isWatched && !isActive) 0.4f else 1.0f

            // Hide overlay and icon (using gray out instead)
            watchedOverlay.visibility = View.GONE
            watchedIcon.visibility = View.GONE

            // Text badges
            watchedView.visibility = if (isWatched && !isActive) View.VISIBLE else View.GONE
            playingView.visibility = if (isActive) View.VISIBLE else View.GONE

            // Progress indicator
            if (progressPercent > 5 && progressPercent < 95 && !isWatched) {
                progressText.text = "$progressPercent% watched"
                progressContainer.visibility = View.VISIBLE

                // Show progress on poster too
                posterProgress.max = 100
                posterProgress.progress = progressPercent
                posterProgress.visibility = View.VISIBLE
            } else {
                progressContainer.visibility = View.GONE
                posterProgress.visibility = View.GONE
            }

            // Load poster image with Glide
            loadPosterImage(item)

            // Selection state
            container.isSelected = isActive

            // Click handling
            container.isFocusable = true
            container.setOnClickListener {
                android.util.Log.d("AndroidTvPlayer", "Episode clicked - itemIndex: $itemIndex, title: ${item.title}, season: ${item.season}, episode: ${item.episode}, id: ${item.id}, url: ${item.url}")
                onItemClick(itemIndex)
            }

            // Focus handling for selection overlay
            container.onFocusChangeListener = View.OnFocusChangeListener { view, hasFocus ->
                android.util.Log.d("PlaylistNav", "EpisodeViewHolder focus changed - itemIndex=$itemIndex, hasFocus=$hasFocus, position=${bindingAdapterPosition}")
                selectionOverlay?.visibility = if (hasFocus) View.VISIBLE else View.GONE
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
            if (progressPercent > 5 && progressPercent < 95 && !isWatched) {
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

        private fun loadPosterImage(item: PlaybackItem) {
            val artwork = item.artwork

            if (!artwork.isNullOrBlank()) {
                // Load image with Glide
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
                            posterImageView.visibility = View.VISIBLE
                            fallbackTextView.visibility = View.GONE
                            return false
                        }
                    })
                    .into(posterImageView)
            } else {
                showFallback(item)
            }
        }

        private fun showFallback(item: PlaybackItem) {
            posterImageView.visibility = View.GONE
            fallbackTextView.visibility = View.VISIBLE

            // Show episode number as fallback
            val episodeNum = item.episode ?: (bindingAdapterPosition + 1)
            fallbackTextView.text = "$episodeNum"

            // Color based on season
            val seasonColor = getSeasonColor(item.season ?: 1)
            fallbackTextView.setBackgroundColor(seasonColor)
        }

        private fun getSeasonColor(season: Int): Int {
            val colors = intArrayOf(
                0xFF6366F1.toInt(), // Indigo
                0xFF8B5CF6.toInt(), // Purple
                0xFFEC4899.toInt(), // Pink
                0xFFF59E0B.toInt(), // Amber
                0xFF10B981.toInt(), // Emerald
                0xFF06B6D4.toInt(), // Cyan
            )
            // Ensure season is at least 1 to avoid negative index
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
    private var currentGroup: MovieGroup = MovieGroup.MAIN
    private val visibleIndices = mutableListOf<Int>()

    init {
        showGroup(MovieGroup.MAIN, force = true)
    }

    fun showGroup(group: MovieGroup, force: Boolean = false): Boolean {
        if (!force && currentGroup == group) {
            return false
        }
        currentGroup = group
        rebuildVisibleItems()
        notifyDataSetChanged()
        return true
    }

    private fun rebuildVisibleItems() {
        visibleIndices.clear()
        val source = when (currentGroup) {
            MovieGroup.MAIN -> groups.main
            MovieGroup.EXTRAS -> groups.extras
        }
        visibleIndices.addAll(source)
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
        holder.bind(item, itemIndex, isActive, currentGroup)
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

        fun bind(item: PlaybackItem, itemIndex: Int, isActive: Boolean, group: MovieGroup) {
            badgeView.text = if (group == MovieGroup.MAIN) "MAIN" else "EXTRA"
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

            loadPosterImage(item, itemIndex, group)

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

        private fun loadPosterImage(item: PlaybackItem, itemIndex: Int, group: MovieGroup) {
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
                            showFallback(itemIndex, group)
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
                showFallback(itemIndex, group)
            }
        }

        private fun showFallback(itemIndex: Int, group: MovieGroup) {
            posterImageView.visibility = View.GONE
            fallbackTextView.visibility = View.VISIBLE
            val positionNumber = if (bindingAdapterPosition != RecyclerView.NO_POSITION) {
                bindingAdapterPosition + 1
            } else {
                itemIndex + 1
            }
            fallbackTextView.text = positionNumber.coerceAtLeast(1).toString()
            fallbackTextView.setBackgroundColor(getGroupColor(group))
        }

        private fun getGroupColor(group: MovieGroup): Int {
            return if (group == MovieGroup.MAIN) {
                0xFF6366F1.toInt()
            } else {
                0xFFF59E0B.toInt()
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
