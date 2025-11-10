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
                        Handler(Looper.getMainLooper()).postDelayed({
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

        // Start playback
        playItem(currentIndex)
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
        player?.addListener(object : Player.Listener {
            override fun onCues(cueGroup: androidx.media3.common.text.CueGroup) {
                subtitleOverlay.setCues(cueGroup.cues)
            }
        })

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
        playlistView.layoutManager = LinearLayoutManager(this)
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
        if (playlistMode == PlaylistMode.NONE || playlistAdapter == null) {
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
        if (activePosition != -1) {
            playlistView.post {
                playlistView.scrollToPosition(activePosition)
                playlistView.postDelayed({
                    val viewHolder = playlistView.findViewHolderForAdapterPosition(activePosition)
                    viewHolder?.itemView?.requestFocus() ?: playlistView.requestFocus()
                }, 100)
            }
        } else {
            playlistView.post {
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
        if (playlistMode != PlaylistMode.COLLECTION) {
            val next = fromIndex + 1
            return if (next < model.items.size) next else null
        }

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

            val requestedStartIndex = obj.optInt("startIndex", 0)
            val startItem = items.getOrNull(requestedStartIndex)

            // Sort items by season and episode for proper playback order
            items.sortWith(compareBy(
                { it.season ?: 0 },
                { it.episode ?: 0 }
            ))

            // Find the new position of the start item after sorting
            val actualStartIndex = if (startItem != null) {
                items.indexOf(startItem).coerceAtLeast(0)
            } else {
                0
            }

            android.util.Log.d("AndroidTvPlayer", "parsePayload - requested start: $requestedStartIndex, actual after sort: $actualStartIndex, startItem: ${startItem?.title}")

            PlaybackPayload(
                title = obj.optString("title"),
                subtitle = obj.optString("subtitle"),
                contentType = obj.optString("contentType", "single"),
                items = items,
                startIndex = actualStartIndex,
                seriesTitle = obj.optString("seriesTitle")
            )
        } catch (e: Exception) {
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

    override fun onDestroy() {
        progressHandler.removeCallbacksAndMessages(null)
        titleHandler.removeCallbacksAndMessages(null)
        controlsHandler.removeCallbacksAndMessages(null)

        player?.let {
            sendProgress(completed = false)
            it.removeListener(playbackListener)
            it.release()
        }
        player = null
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
    val seriesTitle: String?
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

            // Add episodes (already sorted at payload level)
            for (episode in episodesInSeason) {
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
                val view = inflater.inflate(R.layout.item_android_tv_playlist_entry, parent, false)
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
        // Notify the current playing item to update its progress display
        val position = findPositionForItemIndex(activeItemIndex)
        if (position != -1) {
            notifyItemChanged(position)
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

    // Season Header ViewHolder
    class SeasonHeaderViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val titleView: TextView = itemView.findViewById(R.id.season_header_title)
        private val subtitleView: TextView = itemView.findViewById(R.id.season_header_subtitle)

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
        val view = inflater.inflate(R.layout.item_android_tv_playlist_entry, parent, false)
        return MovieViewHolder(view, onItemClick)
    }

    override fun onBindViewHolder(holder: MovieViewHolder, position: Int) {
        val itemIndex = visibleIndices.getOrNull(position) ?: return
        val item = items[itemIndex]
        val isActive = itemIndex == activeItemIndex
        holder.bind(item, itemIndex, isActive, currentGroup)
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
            notifyItemChanged(position)
        }
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
