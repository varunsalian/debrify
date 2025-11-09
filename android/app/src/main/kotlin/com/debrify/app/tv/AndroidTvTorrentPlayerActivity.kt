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
    private lateinit var nextOverlay: View
    private lateinit var nextText: TextView
    private lateinit var nextSubtext: TextView

    // Seekbar
    private lateinit var seekbarOverlay: View
    private lateinit var seekbarProgress: View
    private lateinit var seekbarHandle: View
    private lateinit var seekbarCurrentTime: TextView
    private lateinit var seekbarTotalTime: TextView

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
                    if (currentIndex + 1 < model.items.size) {
                        showNextOverlay(model.items[currentIndex + 1])
                        Handler(Looper.getMainLooper()).postDelayed({
                            hideNextOverlay()
                            playItem(currentIndex + 1)
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
        nextOverlay = findViewById(R.id.android_tv_next_overlay)
        nextText = findViewById(R.id.android_tv_next_text)
        nextSubtext = findViewById(R.id.android_tv_next_subtext)
        seekbarOverlay = findViewById(R.id.seekbar_overlay)
        seekbarProgress = findViewById(R.id.seekbar_progress)
        seekbarHandle = findViewById(R.id.seekbar_handle)
        seekbarCurrentTime = findViewById(R.id.seekbar_current_time)
        seekbarTotalTime = findViewById(R.id.seekbar_total_time)
    }

    private fun setupPlayer() {
        trackSelector = DefaultTrackSelector(this)
        trackSelector?.parameters = trackSelector?.buildUponParameters()
            ?.setPreferredAudioLanguage("en")
            ?.build()!!

        player = ExoPlayer.Builder(this)
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
        val adapter = PlaylistAdapter(payload!!.items) { index ->
            hidePlaylist()
            playItem(index)
        }
        playlistView.adapter = adapter
        playlistOverlay.visibility = View.GONE
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
    }

    private fun playItem(index: Int) {
        val model = payload ?: return
        if (index < 0 || index >= model.items.size) return

        currentIndex = index
        val item = model.items[index]
        pendingSeekMs = item.resumePositionMs

        // Check if URL needs to be resolved (lazy loading)
        if (item.url.isBlank()) {
            resolveAndPlay(index, item)
            return
        }

        startPlayback(item)
    }

    private fun resolveAndPlay(index: Int, item: PlaybackItem) {
        setResolvingState(true)
        thread {
            val url = requestStreamFromFlutter(item, index)
            runOnUiThread {
                setResolvingState(false)
                if (url.isNullOrEmpty()) {
                    Toast.makeText(this, "Unable to load stream", Toast.LENGTH_SHORT).show()
                    return@runOnUiThread
                }
                // Update the item with resolved URL
                payload?.items?.set(index, item.copy(url = url))
                startPlayback(payload!!.items[index])
            }
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
        (playlistView.adapter as? PlaylistAdapter)?.setActiveIndex(currentIndex)
        restartProgressUpdates()
    }

    private fun playNext() {
        val model = payload ?: return
        if (currentIndex + 1 < model.items.size) {
            playItem(currentIndex + 1)
        } else {
            Toast.makeText(this, "End of playlist", Toast.LENGTH_SHORT).show()
        }
    }

    private fun updateTitle(item: PlaybackItem) {
        titleView.text = item.title
        channelBadge.text = "TORRENT MODE"
        channelBadge.visibility = View.VISIBLE

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

    private fun requestStreamFromFlutter(item: PlaybackItem, index: Int): String? {
        return try {
            val args = hashMapOf<String, Any?>(
                "resumeId" to item.resumeId,
                "itemId" to item.id,
                "index" to index
            )
            val result = MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
                "requestTorrentStream",
                args
            )
            val map = result as? Map<*, *>
            map?.get("url") as? String
        } catch (e: Exception) {
            null
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
                        seekBackward()
                        return true
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        seekForward()
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

    private fun seekBackward() {
        seekbarPosition = (seekbarPosition - 10_000L).coerceAtLeast(0)
        updateSeekbarUI()
    }

    private fun seekForward() {
        seekbarPosition = (seekbarPosition + 10_000L).coerceAtMost(videoDuration)
        updateSeekbarUI()
    }

    private fun updateSeekbarUI() {
        seekbarCurrentTime.text = formatTime(seekbarPosition)
        seekbarTotalTime.text = formatTime(videoDuration)

        val progressPercent = if (videoDuration > 0) {
            seekbarPosition.toFloat() / videoDuration.toFloat()
        } else 0f

        val seekbarBackground = findViewById<View>(R.id.seekbar_background)
        seekbarBackground?.post {
            val totalWidth = seekbarBackground.width
            if (totalWidth > 0) {
                val progressWidth = (totalWidth * progressPercent).toInt()

                val progressParams = seekbarProgress.layoutParams
                progressParams.width = progressWidth
                seekbarProgress.layoutParams = progressParams

                val handleSize = seekbarHandle.width
                val handleX = progressWidth - (handleSize / 2f)
                seekbarHandle.translationX = handleX
            }
        }
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
        playlistVisible = true
        playlistOverlay.visibility = View.VISIBLE
        playlistView.post {
            playlistView.requestFocus()
        }
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
            PlaybackPayload(
                title = obj.optString("title"),
                subtitle = obj.optString("subtitle"),
                contentType = obj.optString("contentType", "single"),
                items = items,
                startIndex = obj.optInt("startIndex", 0),
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
    val description: String?,
    val resumePositionMs: Long,
    val durationMs: Long,
    val updatedAt: Long,
    val resumeId: String?
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
                description = obj.optString("description", null),
                resumePositionMs = obj.optLong("resumePositionMs", 0),
                durationMs = obj.optLong("durationMs", 0),
                updatedAt = obj.optLong("updatedAt", 0),
                resumeId = obj.optString("resumeId", null)
            )
        }
    }
}

private class PlaylistAdapter(
    private val items: List<PlaybackItem>,
    private val onItemClick: (Int) -> Unit
) : RecyclerView.Adapter<PlaylistAdapter.PlaylistViewHolder>() {
    private var activeIndex = 0

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PlaylistViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_android_tv_playlist_entry, parent, false)
        return PlaylistViewHolder(view, onItemClick)
    }

    override fun onBindViewHolder(holder: PlaylistViewHolder, position: Int) {
        holder.bind(items[position], position == activeIndex, position)
    }

    override fun getItemCount(): Int = items.size

    fun setActiveIndex(index: Int) {
        val previous = activeIndex
        activeIndex = index
        notifyItemChanged(previous)
        notifyItemChanged(activeIndex)
    }

    class PlaylistViewHolder(
        itemView: View,
        private val onItemClick: (Int) -> Unit
    ) : RecyclerView.ViewHolder(itemView) {
        private val container: View = itemView.findViewById(R.id.android_tv_playlist_item_container)
        private val titleView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_title)
        private val subtitleView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_subtitle)
        private val badgeView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_badge)
        private val playingView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_playing)

        init {
            container.isFocusable = true
            container.setOnClickListener {
                val position = bindingAdapterPosition
                if (position != RecyclerView.NO_POSITION) {
                    onItemClick(position)
                }
            }
        }

        fun bind(item: PlaybackItem, isActive: Boolean, position: Int) {
            titleView.text = item.title
            subtitleView.text = item.description ?: ""
            val badge = item.seasonEpisodeLabel().ifEmpty { "Item ${position + 1}" }
            badgeView.text = badge
            playingView.visibility = if (isActive) View.VISIBLE else View.GONE
            container.isSelected = isActive
        }
    }
}
