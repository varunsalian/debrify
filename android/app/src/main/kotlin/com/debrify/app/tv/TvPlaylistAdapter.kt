package com.debrify.app.tv

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R

internal interface PlaylistOverlayAdapter {
    fun setActiveIndex(index: Int)
    fun updateCurrentProgress()
    fun getActiveItemPosition(): Int
}

// Sealed class for playlist items (header or episode)
internal sealed class PlaylistListItem {
    data class SeasonHeader(val season: Int, val episodeCount: Int) : PlaylistListItem()
    data class Episode(val itemIndex: Int) : PlaylistListItem()
    // Full-guide mode: an episode of the show that is NOT in the playlist —
    // rendered dimmed; clicking it fetches the episode in-player.
    data class MissingEpisode(val guideIndex: Int) : PlaylistListItem()
}

internal class PlaylistAdapter(
    private val items: List<PlaybackItem>,
    private val guide: List<GuideEpisode> = emptyList(),
    private val onFetchEpisode: ((Int, Int) -> Unit)? = null,
    // Guide-skin seam (all default to legacy => classic byte-identical):
    // premium skins swap the row layout and append their own styling +
    // focus reporting after the shared bind.
    private val itemLayoutRes: Int = R.layout.item_android_tv_playlist_entry_horizontal,
    private val skinBinder: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
    private val onItemFocused: ((PlaybackItem, Int) -> Unit)? = null,
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
                val view = inflater.inflate(itemLayoutRes, parent, false)
                EpisodeViewHolder(view, onItemClick, skinBinder, onItemFocused)
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
        private val onItemClick: (Int) -> Unit,
        private val skinBinder: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
        private val onItemFocused: ((PlaybackItem, Int) -> Unit)? = null,
    ) : RecyclerView.ViewHolder(itemView) {
        private var lastBoundIndex: Int = -1
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

            // Guide-skin hook (null on classic): per-skin styling on top of the
            // shared bind, and a focus listener that reports into the detail
            // pane instead of the classic scale animation (deliberate
            // last-set-wins on container.onFocusChangeListener).
            lastBoundIndex = itemIndex
            skinBinder?.invoke(itemView, item, itemIndex, isActive)
            if (onItemFocused != null) {
                container.onFocusChangeListener = View.OnFocusChangeListener { _, hasFocus ->
                    if (hasFocus) onItemFocused.invoke(item, lastBoundIndex)
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

            skinBinder?.invoke(itemView, item, lastBoundIndex, isActive)
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
