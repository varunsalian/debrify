package com.debrify.app.tv

import android.os.Handler
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import com.debrify.app.R
import org.json.JSONObject

@OptIn(UnstableApi::class)
internal class TvStremioTvGuideController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        fun fadeInNextOverlay(): Unit
        fun hideControlsMenu(): Unit
        fun hideNextOverlay(): Unit
        var isStremioTvMode: Boolean
        val nextSubtext: TextView
        val nextText: TextView
        fun playStremioTvPlaybackMap(channel: StremioTvGuideChannel, map: Map<*, *>, url: String, title: String, hideGuideOnReady: Boolean): Unit
        val player: ExoPlayer?
        val playerView: PlayerView
        val playlistMode: PlaylistMode
        val progressHandler: Handler
    }
    var stremioTvChannels = mutableListOf<StremioTvGuideChannel>()
    private var stremioTvGuideOverlay: View? = null
    private var stremioTvGuideList: RecyclerView? = null
    var stremioTvGuideSearch: android.widget.EditText? = null
    private var stremioTvGuideCountText: TextView? = null
    private var stremioTvGuideNowPlaying: View? = null
    private var stremioTvGuideNowPoster: android.widget.ImageView? = null
    private var stremioTvGuideNowLetter: TextView? = null
    private var stremioTvGuideCurrentName: TextView? = null
    private var stremioTvGuideCurrentTitle: TextView? = null
    var stremioTvChannelAdapter: StremioTvGuideAdapter? = null
    var stremioTvGuideVisible = false
    private var stremioTvChannelSwitchInProgress = false
    private var stremioTvNextInProgress = false
    private var stremioTvSwitchToken = 0

    private var guidePanelReadyListener: Player.Listener? = null
    private var guidePanelTimeoutRunnable: Runnable? = null

    fun hideGuideWhenReady() {
        if (!stremioTvGuideVisible) return

        // Clean up any previous listener/timeout
        cancelGuideWait()

        // Timeout fallback — hide after 10s regardless
        val timeout = Runnable {
            cancelGuideWait()
            if (stremioTvGuideVisible) hideStremioTvGuide()
        }
        guidePanelTimeoutRunnable = timeout
        host.progressHandler.postDelayed(timeout, 10_000)

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
        host.player?.addListener(listener)
    }

    private fun cancelGuideWait() {
        guidePanelReadyListener?.let { host.player?.removeListener(it) }
        guidePanelReadyListener = null
        guidePanelTimeoutRunnable?.let { host.progressHandler.removeCallbacks(it) }
        guidePanelTimeoutRunnable = null
    }


    // ═══════════════════════════════════════════════════════════════
    // STREMIO TV CHANNEL GUIDE
    // ═══════════════════════════════════════════════════════════════

    fun initStremioTvGuide(guideJson: JSONObject) {
        host.isStremioTvMode = true
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
        stremioTvGuideOverlay = activity.findViewById(R.id.stremio_tv_guide_overlay)
        stremioTvGuideList = activity.findViewById(R.id.stremio_tv_guide_list)
        stremioTvGuideSearch = activity.findViewById(R.id.stremio_tv_guide_search)
        stremioTvGuideCountText = activity.findViewById(R.id.stremio_tv_guide_count)
        stremioTvGuideNowPlaying = activity.findViewById(R.id.stremio_tv_guide_now_playing)
        stremioTvGuideNowPoster = activity.findViewById(R.id.stremio_tv_guide_now_poster)
        stremioTvGuideNowLetter = activity.findViewById(R.id.stremio_tv_guide_now_letter)
        stremioTvGuideCurrentName = activity.findViewById(R.id.stremio_tv_guide_current_name)
        stremioTvGuideCurrentTitle = activity.findViewById(R.id.stremio_tv_guide_current_title)

        val guideList = stremioTvGuideList ?: return

        guideList.layoutManager = LinearLayoutManager(activity, LinearLayoutManager.VERTICAL, false)
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
        val playlistButton: AppCompatButton? = host.playerView.findViewById(R.id.debrify_playlist_button)
        if (host.playlistMode == PlaylistMode.NONE) {
            playlistButton?.text = "Guide"
            playlistButton?.setOnClickListener {
                host.hideControlsMenu()
                toggleStremioTvGuide()
            }
        }
    }

    fun showStremioTvGuide() {
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

    fun hideStremioTvGuide() {
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

    fun updateStremioTvGuideHeader() {
        val current = stremioTvChannels.firstOrNull { it.isCurrent } ?: return
        stremioTvGuideNowPlaying?.visibility = View.VISIBLE
        stremioTvGuideCurrentName?.text = current.name
        stremioTvGuideCurrentTitle?.text = buildNowPlayingText(current)

        val firstLetter = if (current.name.isNotEmpty()) current.name[0].uppercase() else "?"
        val poster = current.nowPlayingPoster
        if (!poster.isNullOrEmpty()) {
            stremioTvGuideNowLetter?.visibility = View.GONE
            stremioTvGuideNowPoster?.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(activity)
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

    fun isFocusInStremioTvGuideList(): Boolean {
        val list = stremioTvGuideList ?: return false
        var current = activity.currentFocus
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
                        activity.runOnUiThread {
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
                        activity.runOnUiThread {
                            for (id in idsToLoad) {
                                stremioTvChannels.firstOrNull { it.id == id }?.isLoadingGuideData = false
                            }
                        }
                    }

                    override fun notImplemented() {
                        activity.runOnUiThread {
                            for (id in idsToLoad) {
                                stremioTvChannels.firstOrNull { it.id == id }?.isLoadingGuideData = false
                            }
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "requestGuideDataForVisibleChannels exception", e)
            activity.runOnUiThread {
                for (id in idsToLoad) {
                    stremioTvChannels.firstOrNull { it.id == id }?.isLoadingGuideData = false
                }
            }
        }
    }

    fun requestStremioTvNext(finishOnFailure: Boolean = false) {
        if (stremioTvNextInProgress || stremioTvChannelSwitchInProgress) return

        val channel = stremioTvChannels.firstOrNull { it.isCurrent }
        if (channel == null) {
            Toast.makeText(activity, "Channel unavailable", Toast.LENGTH_SHORT).show()
            if (finishOnFailure) activity.finish()
            return
        }

        val methodChannel = MainActivity.getAndroidTvPlayerChannel()
        if (methodChannel == null) {
            Toast.makeText(activity, "Playback bridge unavailable", Toast.LENGTH_SHORT).show()
            if (finishOnFailure) activity.finish()
            return
        }

        stremioTvNextInProgress = true
        stremioTvSwitchToken++
        val token = stremioTvSwitchToken

        host.nextText.text = channel.nextUpTitle ?: channel.name
        host.nextSubtext.visibility = View.GONE
        host.fadeInNextOverlay()

        try {
            val args = hashMapOf<String, Any?>("channelId" to channel.id)
            methodChannel.invokeMethod(
                "requestStremioTvNext",
                args,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (token != stremioTvSwitchToken) return
                        activity.runOnUiThread {
                            stremioTvNextInProgress = false
                            val map = result as? Map<*, *>
                            val url = map?.get("url") as? String
                            if (url.isNullOrEmpty()) {
                                host.hideNextOverlay()
                                Toast.makeText(activity, "Next item unavailable", Toast.LENGTH_SHORT).show()
                                if (finishOnFailure) activity.finish()
                                return@runOnUiThread
                            }

                            val title = map["title"] as? String ?: channel.name
                            host.nextText.text = title
                            host.nextSubtext.visibility = View.GONE

                            host.playStremioTvPlaybackMap(
                                channel = channel,
                                map = map,
                                url = url,
                                title = title,
                                hideGuideOnReady = false
                            )
                            host.progressHandler.postDelayed({ host.hideNextOverlay() }, 1500)
                        }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        if (token != stremioTvSwitchToken) return
                        activity.runOnUiThread {
                            stremioTvNextInProgress = false
                            host.hideNextOverlay()
                            Toast.makeText(
                                activity,
                                errorMessage ?: "Failed to load next item",
                                Toast.LENGTH_SHORT
                            ).show()
                            if (finishOnFailure) activity.finish()
                        }
                    }

                    override fun notImplemented() {
                        if (token != stremioTvSwitchToken) return
                        activity.runOnUiThread {
                            stremioTvNextInProgress = false
                            host.hideNextOverlay()
                            if (finishOnFailure) activity.finish()
                        }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "requestStremioTvNext exception", e)
            stremioTvNextInProgress = false
            host.hideNextOverlay()
            if (finishOnFailure) activity.finish()
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
                        activity.runOnUiThread {
                            stremioTvChannelSwitchInProgress = false
                            val map = result as? Map<*, *>
                            val url = map?.get("url") as? String
                            if (url.isNullOrEmpty()) {
                                android.util.Log.e("AndroidTvPlayer", "channel switch returned null URL")
                                Toast.makeText(activity, "Channel switch failed", Toast.LENGTH_SHORT).show()
                                // Revert current marker
                                channel.isSwitchingChannel = false
                                channel.isCurrent = false
                                previousCurrent?.isCurrent = true
                                stremioTvChannelAdapter?.notifyDataSetChanged()
                                return@runOnUiThread
                            }

                            val title = map["title"] as? String ?: channel.name
                            host.playStremioTvPlaybackMap(
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
                        activity.runOnUiThread {
                            stremioTvChannelSwitchInProgress = false
                            Toast.makeText(activity, "Channel switch failed: $errorMessage", Toast.LENGTH_SHORT).show()
                            channel.isSwitchingChannel = false
                            channel.isCurrent = false
                            previousCurrent?.isCurrent = true
                            stremioTvChannelAdapter?.notifyDataSetChanged()
                        }
                    }

                    override fun notImplemented() {
                        if (token != stremioTvSwitchToken) return
                        activity.runOnUiThread {
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
}
