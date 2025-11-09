package com.debrify.app.tv

import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import com.debrify.app.R
import org.json.JSONArray
import org.json.JSONObject
import kotlin.concurrent.thread

class AndroidTvTorrentPlayerActivity : AppCompatActivity(), Player.Listener {
    private lateinit var playerView: PlayerView
    private lateinit var dimBackground: View
    private lateinit var tuningOverlay: View
    private lateinit var headerContainer: View
    private lateinit var titleView: TextView
    private lateinit var subtitleView: TextView
    private lateinit var channelBadgeView: TextView
    private lateinit var episodeBadgeView: TextView
    private lateinit var fileBadgeView: TextView
    private lateinit var durationBadgeView: TextView
    private lateinit var chipPlayView: TextView
    private lateinit var chipPlaylistView: TextView
    private lateinit var chipInfoView: TextView
    private lateinit var bottomTitleView: TextView
    private lateinit var bottomDescriptionView: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var progressPositionView: TextView
    private lateinit var progressDurationView: TextView
    private lateinit var playlistView: RecyclerView

    private var playlistAdapter: PlaylistAdapter? = null
    private var player: ExoPlayer? = null
    private var payload: PlaybackPayload? = null
    private var currentIndex = 0
    private var pendingSeekMs: Long = 0

    private val progressHandler = Handler(Looper.getMainLooper())
    private val headerHandler = Handler(Looper.getMainLooper())

    private val progressRunnable = object : Runnable {
        override fun run() {
            sendProgress(completed = false)
            progressHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    private val hideHeaderRunnable = Runnable {
        headerContainer.animate().alpha(0f).setDuration(250).start()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_android_tv_torrent_player)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

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
        setupPlaylist()
        setupChips()
        playItem(currentIndex)
    }

    override fun onStart() {
        super.onStart()
        player?.play()
        updateChipStates()
    }

    override fun onStop() {
        super.onStop()
        player?.pause()
        updateChipStates()
    }

    override fun onDestroy() {
        progressHandler.removeCallbacksAndMessages(null)
        headerHandler.removeCallbacksAndMessages(null)
        player?.removeListener(this)
        player?.release()
        player = null
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("torrentPlaybackFinished", null)
        super.onDestroy()
    }

    private fun bindViews() {
        playerView = findViewById(R.id.android_tv_player_view)
        dimBackground = findViewById(R.id.android_tv_dim_background)
        tuningOverlay = findViewById(R.id.android_tv_static_overlay)
        headerContainer = findViewById(R.id.android_tv_header_container)
        titleView = findViewById(R.id.android_tv_player_title)
        subtitleView = findViewById(R.id.android_tv_player_subtitle)
        channelBadgeView = findViewById(R.id.android_tv_channel_badge)
        episodeBadgeView = findViewById(R.id.android_tv_episode_badge)
        fileBadgeView = findViewById(R.id.android_tv_file_badge)
        durationBadgeView = findViewById(R.id.android_tv_duration_badge)
        chipPlayView = findViewById(R.id.android_tv_chip_play)
        chipPlaylistView = findViewById(R.id.android_tv_chip_playlist)
        chipInfoView = findViewById(R.id.android_tv_chip_info)
        bottomTitleView = findViewById(R.id.android_tv_bottom_title)
        bottomDescriptionView = findViewById(R.id.android_tv_bottom_description)
        progressBar = findViewById(R.id.android_tv_progress)
        progressPositionView = findViewById(R.id.android_tv_progress_position)
        progressDurationView = findViewById(R.id.android_tv_progress_duration)
        playlistView = findViewById(R.id.android_tv_playlist)
    }

    private fun setupPlayer() {
        player = ExoPlayer.Builder(this)
            .build()
            .also {
                it.addListener(this)
                playerView.player = it
            }
    }

    private fun setupPlaylist() {
        playlistView.layoutManager = LinearLayoutManager(this)
        val items = payload!!.items
        playlistAdapter = PlaylistAdapter(items) { index ->
            hidePlaylist()
            playItem(index)
        }
        playlistView.adapter = playlistAdapter
        playlistView.visibility = View.GONE
    }

    private fun setupChips() {
        chipPlayView.setOnClickListener {
            player?.let {
                if (it.isPlaying) {
                    it.pause()
                } else {
                    it.play()
                }
                updateChipStates()
            }
        }
        chipPlaylistView.setOnClickListener {
            if (playlistView.visibility == View.VISIBLE) {
                hidePlaylist()
            } else {
                showPlaylist()
            }
        }
        chipInfoView.setOnClickListener {
            headerContainer.alpha = 1f
            headerContainer.visibility = View.VISIBLE
            headerHandler.removeCallbacks(hideHeaderRunnable)
            headerHandler.postDelayed(hideHeaderRunnable, 4000)
        }
    }

    private fun playItem(index: Int) {
        val model = payload ?: return
        if (index < 0 || index >= model.items.size) return
        currentIndex = index
        val item = model.items[index]
        pendingSeekMs = item.resumePositionMs

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

        updateHeader(item)
        playlistAdapter?.setActiveIndex(currentIndex)
        restartProgressUpdates()
        updateChipStates()
    }

    private fun updateHeader(item: PlaybackItem) {
        titleView.text = item.title
        subtitleView.text = payload?.subtitle ?: ""
        channelBadgeView.text = payload?.seriesTitle ?: payload?.title ?: "TORRENT"
        episodeBadgeView.text = item.seasonEpisodeLabel().ifEmpty { "PLAYLIST" }
        fileBadgeView.text = "${payload?.items?.size ?: 0} FILES"
        durationBadgeView.text = "${currentIndex + 1}/${payload?.items?.size ?: 1}"
        bottomTitleView.text = item.title
        bottomDescriptionView.text = item.description ?: ""
        headerContainer.visibility = View.VISIBLE
        headerContainer.alpha = 1f
        headerHandler.removeCallbacks(hideHeaderRunnable)
        headerHandler.postDelayed(hideHeaderRunnable, 4000)
    }

    private fun updateChipStates() {
        val playing = player?.isPlaying == true
        chipPlayView.text = if (playing) "❚❚ Pause" else "▶ Play"
        chipPlayView.isEnabled = true
    }

    private fun showPlaylist() {
        playlistView.visibility = View.VISIBLE
        dimBackground.visibility = View.VISIBLE
        playlistView.requestFocus()
    }

    private fun hidePlaylist() {
        playlistView.visibility = View.GONE
        dimBackground.visibility = View.GONE
    }

    private fun setResolvingState(resolving: Boolean) {
        tuningOverlay.visibility = if (resolving) View.VISIBLE else View.GONE
        chipPlayView.isEnabled = !resolving
        chipPlaylistView.isEnabled = !resolving
        chipInfoView.isEnabled = !resolving
    }

    private fun requestStreamFromFlutter(item: PlaybackItem, index: Int): String? {
        return try {
            val args = hashMapOf<String, Any?>(
                "resumeId" to item.resumeId,
                "itemId" to item.id,
                "index" to index,
            )
        val result = MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "requestTorrentStream",
            args,
        )
        val map = result as? Map<*, *>
        map?.get("url") as? String
        } catch (e: Exception) {
            null
        }
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState == Player.STATE_READY && pendingSeekMs > 0) {
            val duration = player?.duration ?: 0
            if (duration > 0 && pendingSeekMs < duration) {
                player?.seekTo(pendingSeekMs)
            }
            pendingSeekMs = 0
        } else if (playbackState == Player.STATE_ENDED) {
            sendProgress(completed = true)
            val model = payload ?: return
            if (currentIndex + 1 < model.items.size) {
                playItem(currentIndex + 1)
            } else {
                finish()
            }
        }
        updateChipStates()
    }

    private fun restartProgressUpdates() {
        progressHandler.removeCallbacks(progressRunnable)
        progressHandler.postDelayed(progressRunnable, PROGRESS_INTERVAL_MS)
    }

    private fun updateProgressUi(positionMs: Long, durationMs: Long) {
        if (durationMs > 0) {
            val ratio = (positionMs.toDouble() / durationMs.toDouble())
            progressBar.max = 1000
            progressBar.progress = (ratio * 1000).toInt().coerceIn(0, 1000)
        } else {
            progressBar.progress = 0
        }
        progressPositionView.text = formatTime(positionMs)
        progressDurationView.text = formatTime(durationMs)
    }

    private fun sendProgress(completed: Boolean) {
        val model = payload ?: return
        val item = model.items[currentIndex]
        val position = if (completed) player?.duration ?: 0 else player?.currentPosition ?: 0
        val duration = player?.duration ?: 0

        updateProgressUi(position, duration)

        val map = hashMapOf<String, Any?>(
            "contentType" to model.contentType,
            "itemIndex" to currentIndex,
            "resumeId" to item.resumeId,
            "positionMs" to position.toInt().coerceAtLeast(0),
            "durationMs" to duration.toInt().coerceAtLeast(0),
            "season" to item.season,
            "episode" to item.episode,
            "speed" to 1.0,
            "aspect" to "contain",
            "completed" to completed,
            "url" to item.url,
        )

        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "torrentPlaybackProgress",
            map,
        )
    }

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
                seriesTitle = obj.optString("seriesTitle"),
            )
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val PAYLOAD_KEY = "payload"
        private const val PROGRESS_INTERVAL_MS = 5_000L
    }
}

private data class PlaybackPayload(
    val title: String,
    val subtitle: String?,
    val contentType: String,
    val items: MutableList<PlaybackItem>,
    val startIndex: Int,
    val seriesTitle: String?,
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
    val resumeId: String?,
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
                resumeId = obj.optString("resumeId", null),
            )
        }
    }
}

private class PlaylistAdapter(
    private val items: List<PlaybackItem>,
    private val onItemClick: (Int) -> Unit,
) : RecyclerView.Adapter<PlaylistAdapter.PlaylistViewHolder>() {
    private var activeIndex = 0

    override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): PlaylistViewHolder {
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
        private val onItemClick: (Int) -> Unit,
    ) : RecyclerView.ViewHolder(itemView) {
        private val titleView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_title)
        private val subtitleView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_subtitle)
        private val badgeView: TextView = itemView.findViewById(R.id.android_tv_playlist_item_badge)

        init {
            itemView.isFocusable = true
            itemView.setOnClickListener {
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
            titleView.setTypeface(titleView.typeface, if (isActive) Typeface.BOLD else Typeface.NORMAL)
            itemView.isSelected = isActive
        }
    }
}
