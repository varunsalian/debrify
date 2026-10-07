package com.debrify.app.tv

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import java.util.Locale

internal data class MovieTab(
    val view: TextView,
    val groupIndex: Int, // Index into MovieGroups.groups list
    val groupName: String,
)

internal class MoviePlaylistAdapter(
    private val items: List<PlaybackItem>,
    private val groups: MovieGroups,
    // Guide-skin seam — see PlaylistAdapter; defaults keep classic identical.
    private val itemLayoutRes: Int = R.layout.item_android_tv_playlist_entry_horizontal,
    private val skinBinder: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
    private val onItemFocused: ((PlaybackItem, Int) -> Unit)? = null,
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
        val view = inflater.inflate(itemLayoutRes, parent, false)
        return MovieViewHolder(view, onItemClick, skinBinder, onItemFocused)
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
        private val skinBinder: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
        private val onItemFocused: ((PlaybackItem, Int) -> Unit)? = null,
    ) : RecyclerView.ViewHolder(itemView) {
        private var lastBoundIndex: Int = -1

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

            // Guide-skin hook (null on classic) — same seam as EpisodeViewHolder:
            // skins own their focus visuals via XML selectors, so the reporting
            // listener replaces the classic scale animation (last-set-wins).
            lastBoundIndex = itemIndex
            skinBinder?.invoke(itemView, item, itemIndex, isActive)
            if (onItemFocused != null) {
                container.onFocusChangeListener = View.OnFocusChangeListener { _, hasFocus ->
                    if (hasFocus) onItemFocused.invoke(item, lastBoundIndex)
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

            skinBinder?.invoke(itemView, item, lastBoundIndex, isActive)
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
