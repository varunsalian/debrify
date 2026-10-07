package com.debrify.app.tv

import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.TextView
import androidx.media3.common.util.UnstableApi
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R

// ═══════════════════════════════════════════════════════════════
// Stremio TV Guide Data + Adapter
// ═══════════════════════════════════════════════════════════════

internal data class StremioTvGuideChannel(
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
internal class StremioTvGuideAdapter(
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
