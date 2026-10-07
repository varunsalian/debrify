package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.util.UnstableApi
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R

// IPTV Channel Data + Adapter
// ═══════════════════════════════════════════════════════════════

internal data class IptvChannelEntry(
    var index: Int,
    val channelNumber: Int?,
    val name: String,
    val url: String,
    val logoUrl: String?,
    val group: String?,
    val isLive: Boolean,
    var isCurrent: Boolean,
    // Where playback of this on-demand item should start. Seeded from the
    // Flutter payload and kept current in-session, so zapping away from a
    // half-watched movie and back returns to the right spot rather than to
    // the position it held at launch. Always 0 for live channels.
    var resumePositionMs: Long = 0L,
    // Headers the playlist declared for this channel (#EXTVLCOPT/#EXTHTTP/
    // pipe-suffix). Sent with every request while the channel plays — a
    // UA/Referer-guarded channel is unplayable without them.
    val httpHeaders: Map<String, String> = emptyMap(),
    // EPG (Xtream panels), fetched lazily over the bridge as rows bind.
    // Instances are shared between the master list and the adapter's filtered
    // copy, so a fetch landing updates both. epgLoaded means "asked once" —
    // a stale answer (now-programme ended) re-arms the fetch on next bind.
    var epgNowTitle: String? = null,
    var epgNowStartMs: Long = 0L,
    var epgNowStopMs: Long = 0L,
    var epgNowHasArchive: Boolean = false,
    var epgCatchupMetadataLoaded: Boolean = false,
    var epgNextTitle: String? = null,
    var epgNextStartMs: Long = 0L,
    var epgLoaded: Boolean = false,
    var epgLoading: Boolean = false,
    val contentType: String = if (isLive) "live" else "vod",
    // The playlist's declared runtime (-1 for live). Retained because a
    // channel saved into a list is rebuilt from stored metadata alone, and
    // without the runtime its progress/resume UI has nothing to divide by.
    val duration: Int = -1,
    // Xtream archive capability copied from the launch/browse payload. It is
    // sent back with explicit full-guide requests so Dart can cap the lazy
    // history without changing the normal now/next path.
    val tvArchive: String? = null,
    val tvArchiveDuration: Int? = null,
    var sourceId: String? = null,
    var sourceName: String? = null,
    var isFavorite: Boolean = false,
    val seriesId: String? = null,
    val seriesName: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val hasNextEpisode: Boolean? = null,
) {
    val displayName: String
        get() = if (isLive && channelNumber != null) {
            "CH $channelNumber  $name"
        } else {
            name
        }
}

@androidx.annotation.OptIn(UnstableApi::class)
internal class IptvChannelAdapter(
    private var channels: MutableList<IptvChannelEntry>,
    private val onItemClick: (IptvChannelEntry) -> Unit,
    private val onItemLongClick: ((IptvChannelEntry) -> Unit)? = null,
    // Fired from bind for live rows without (fresh) EPG — the activity
    // fetches over the bridge and answers with notifyEpgFor. Bind-driven, so
    // only rows that actually come on screen ever cost a request.
    private val onEpgNeeded: ((IptvChannelEntry) -> Unit)? = null,
    // Styled-look inputs (see IptvGuideStyle.kt); null tokens = classic, and
    // every styled branch below is skipped outright. Invariant styling is
    // applied ONCE per holder in onCreateViewHolder — bind only writes
    // entry-dependent colors/text/visibility.
    private val tokens: GuideTokens? = null,
    private val style: GuideStyle = GuideStyle.CLASSIC,
    private val nameTypeface: Typeface? = null,
    private val monoTypeface: Typeface? = null,
    private val headlineTypeface: Typeface? = null,
    private val captionTypeface: Typeface? = null,
    private val rowRadiusPx: Float = 0f,
    private val rowStrokePx: Int = 0,
) : RecyclerView.Adapter<IptvChannelAdapter.ViewHolder>() {

    companion object {
        private val ACCENT = Color.parseColor("#00E5FF")
        private val ACCENT_DIM = Color.parseColor("#CC00E5FF")
        const val PAYLOAD_EPG = "epg"
    }

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val number: TextView = view.findViewById(R.id.iptv_channel_number)
        val logoTile: FrameLayout = view.findViewById(R.id.iptv_channel_logo_tile)
        val logo: android.widget.ImageView = view.findViewById(R.id.iptv_channel_logo)
        val letter: TextView = view.findViewById(R.id.iptv_channel_letter)
        val name: TextView = view.findViewById(R.id.iptv_channel_name)
        val group: TextView = view.findViewById(R.id.iptv_channel_group)
        val epg: TextView = view.findViewById(R.id.iptv_channel_epg)
        val favorite: TextView = view.findViewById(R.id.iptv_channel_favorite)
        val liveBadge: View = view.findViewById(R.id.iptv_channel_live_badge)
        val liveDot: View = view.findViewById(R.id.iptv_channel_live_dot)
        val liveLabel: TextView = view.findViewById(R.id.iptv_channel_live_label)
        val nowBadge: TextView = view.findViewById(R.id.iptv_channel_now_badge)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_iptv_channel, parent, false)
        val holder = ViewHolder(view)
        val t = tokens ?: return holder
        // Invariant styled chrome — never re-done on bind/scroll.
        view.background = t.rowBackground(rowRadiusPx, rowStrokePx)
        holder.logoTile.background = if (style == GuideStyle.EDITION) {
            t.tileDrawable(view.resources.displayMetrics.density * 21f, 1)
        } else {
            t.tileDrawable(rowRadiusPx, 1)
        }
        holder.letter.setBackgroundColor(Color.TRANSPARENT)
        holder.letter.setTextColor(t.fg)
        holder.group.setTextColor(t.fgFaint)
        holder.epg.setTextColor(t.fgDim)
        holder.favorite.setTextColor(
            if (style == GuideStyle.EDITION) t.fg else t.accent,
        )
        holder.liveBadge.setBackgroundColor(Color.TRANSPARENT)
        holder.liveDot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(t.live)
        }
        holder.liveLabel.setTextColor(t.live)
        if (style == GuideStyle.EDITION) {
            // Edition's NOW is small-caps cream text, no pill.
            holder.nowBadge.background = null
            holder.nowBadge.setTextColor(t.fg)
        } else {
            holder.nowBadge.background = GradientDrawable().apply {
                cornerRadius = if (style == GuideStyle.CONSOLE) {
                    view.resources.displayMetrics.density * 2f
                } else {
                    view.resources.displayMetrics.density * 5f
                }
                setColor(t.accent)
            }
            holder.nowBadge.setTextColor(t.bg or 0xFF000000.toInt())
        }
        when (style) {
            GuideStyle.CONSOLE -> {
                holder.number.typeface = monoTypeface ?: holder.number.typeface
                holder.name.typeface = nameTypeface ?: holder.name.typeface
                holder.epg.typeface = monoTypeface ?: holder.epg.typeface
                holder.liveLabel.typeface = monoTypeface ?: holder.liveLabel.typeface
            }
            GuideStyle.EDITION -> {
                holder.name.typeface = headlineTypeface ?: holder.name.typeface
                holder.epg.typeface = captionTypeface?.let {
                    Typeface.create(it, Typeface.ITALIC)
                } ?: holder.epg.typeface
            }
            else -> {}
        }
        return holder
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int, payloads: MutableList<Any>) {
        if (payloads.isNotEmpty() && payloads[0] == PAYLOAD_EPG) {
            // Partial bind — refresh the EPG line only, preserving focus/scale.
            bindEpgLine(holder, channels[position])
            return
        }
        super.onBindViewHolder(holder, position, payloads)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val entry = channels[position]

        // Cancel any in-flight scale animation from recycled view
        holder.itemView.animate().cancel()
        holder.itemView.scaleX = 1.0f
        holder.itemView.scaleY = 1.0f

        // Channel number
        val t = tokens
        val displayNumber = (entry.channelNumber ?: (entry.index + 1)).toString()
        holder.number.text =
            if (t != null && style == GuideStyle.CONSOLE) {
                displayNumber.padStart(3, '0')
            } else {
                displayNumber
            }
        holder.number.setTextColor(
            if (t == null) {
                if (entry.isCurrent) Color.argb(204, 0, 229, 255) // accent 80%
                else Color.argb(46, 255, 255, 255) // 18%
            } else {
                if (entry.isCurrent) {
                    if (style == GuideStyle.EDITION) t.fg else t.accent
                } else {
                    t.fgFaint
                }
            }
        )

        // Name
        holder.name.text = entry.name
        holder.name.setTextColor(
            if (t == null) {
                if (entry.isCurrent) ACCENT else Color.argb(217, 255, 255, 255)
            } else {
                if (entry.isCurrent) {
                    if (style == GuideStyle.EDITION) t.fg else t.accent
                } else {
                    t.fgMid
                }
            }
        )

        // Group
        if (entry.group != null) {
            holder.group.text = entry.group
            holder.group.visibility = View.VISIBLE
        } else {
            holder.group.visibility = View.GONE
        }

        // EPG line — bind what we have; ask for what we don't. "Stale" means
        // the programme we knew about has ended, so the next bind re-asks.
        bindEpgLine(holder, entry)
        if (entry.isLive && !entry.epgLoading) {
            val stale = entry.epgLoaded && entry.epgNowStopMs > 0 &&
                entry.epgNowStopMs < System.currentTimeMillis()
            if (!entry.epgLoaded || stale) onEpgNeeded?.invoke(entry)
        }

        // Badges — show NOW for current, LIVE for non-current live
        if (entry.isCurrent) {
            holder.nowBadge.visibility = View.VISIBLE
            holder.liveBadge.visibility = View.GONE
        } else {
            holder.nowBadge.visibility = View.GONE
            holder.liveBadge.visibility = if (entry.isLive) View.VISIBLE else View.GONE
        }
        holder.favorite.visibility = if (entry.isFavorite) View.VISIBLE else View.GONE

        // Logo — clear previous Glide load to prevent stale images on recycled views
        com.bumptech.glide.Glide.with(holder.itemView.context).clear(holder.logo)
        val firstLetter = if (entry.name.isNotEmpty()) entry.name[0].uppercase() else "?"
        if (!entry.logoUrl.isNullOrEmpty()) {
            holder.logo.visibility = View.VISIBLE
            holder.letter.visibility = View.GONE
            com.bumptech.glide.Glide.with(holder.itemView.context)
                .load(entry.logoUrl)
                .centerInside()
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?,
                        model: Any?,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                        isFirstResource: Boolean
                    ): Boolean {
                        holder.logo.visibility = View.GONE
                        holder.letter.text = firstLetter
                        holder.letter.visibility = View.VISIBLE
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
                .into(holder.logo)
        } else {
            holder.logo.visibility = View.GONE
            holder.letter.text = firstLetter
            holder.letter.visibility = View.VISIBLE
        }

        // Focus animation
        holder.itemView.onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
            if (hasFocus) {
                v.animate().scaleX(1.02f).scaleY(1.02f).setDuration(150)
                    .setInterpolator(DecelerateInterpolator()).start()
            } else {
                v.animate().scaleX(1.0f).scaleY(1.0f).setDuration(150)
                    .setInterpolator(DecelerateInterpolator()).start()
            }
        }

        holder.itemView.setOnClickListener {
            onItemClick(entry)
        }
        holder.itemView.setOnLongClickListener {
            onItemLongClick?.invoke(entry)
            onItemLongClick != null
        }
    }

    override fun getItemCount(): Int = channels.size

    private fun bindEpgLine(holder: ViewHolder, entry: IptvChannelEntry) {
        val title = entry.epgNowTitle
        if (title != null) {
            holder.epg.text = "Now: $title"
            holder.epg.visibility = View.VISIBLE
        } else {
            holder.epg.visibility = View.GONE
        }
    }

    /** A bridge EPG fetch landed for [entry] — repaint its row if visible. */
    fun notifyEpgFor(entry: IptvChannelEntry) {
        val position = channels.indexOfFirst { it === entry }
        if (position >= 0) notifyItemChanged(position, PAYLOAD_EPG)
    }

    fun entryAt(position: Int): IptvChannelEntry? = channels.getOrNull(position)
    fun positionOf(entry: IptvChannelEntry?): Int =
        channels.indexOfFirst { it === entry }.coerceAtLeast(0)
    fun entriesSnapshot(): List<IptvChannelEntry> = channels.toList()

    fun notifyFavoriteFor(entry: IptvChannelEntry) {
        val position = channels.indexOfFirst { it === entry }
        if (position >= 0) notifyItemChanged(position)
    }

    fun notifyCurrentChanged(
        previous: IptvChannelEntry?,
        current: IptvChannelEntry,
    ) {
        val previousPosition = channels.indexOfFirst { it === previous }
        val currentPosition = channels.indexOfFirst { it === current }
        if (previousPosition >= 0) notifyItemChanged(previousPosition)
        if (currentPosition >= 0 && currentPosition != previousPosition) {
            notifyItemChanged(currentPosition)
        }
    }

    fun updateChannels(filtered: List<IptvChannelEntry>) {
        val old = channels.toList()
        val updated = filtered.toList()
        val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
            override fun getOldListSize(): Int = old.size
            override fun getNewListSize(): Int = updated.size

            override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
                val before = old[oldItemPosition]
                val after = updated[newItemPosition]
                return before.index == after.index &&
                    before.url == after.url &&
                    before.name == after.name &&
                    before.sourceId == after.sourceId
            }

            override fun areContentsTheSame(
                oldItemPosition: Int,
                newItemPosition: Int,
            ): Boolean {
                val before = old[oldItemPosition]
                val after = updated[newItemPosition]
                return before === after ||
                    (before.isCurrent == after.isCurrent &&
                        before.isFavorite == after.isFavorite &&
                        before.logoUrl == after.logoUrl &&
                        before.group == after.group &&
                        before.epgNowTitle == after.epgNowTitle &&
                        before.epgNextTitle == after.epgNextTitle)
            }
        }, true)
        channels.clear()
        channels.addAll(updated)
        diff.dispatchUpdatesTo(this)
    }

    fun getCurrentChannelPosition(): Int {
        return channels.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
    }
}

internal data class IptvSourceEntry(
    val id: String,
    val name: String,
    val isFavorites: Boolean,
    val isContinue: Boolean,
    val isXtream: Boolean,
    // A user-created channel list. Favorites keeps its own flag (the SAVED
    // nav button resolves the source by it) and is NOT flagged as a list.
    val isList: Boolean = false,
    val listId: String? = null,
    val connectionResourceId: String? = null,
    val connectionResourceRevision: Long? = null,
)

/// One of the user's channel lists, for the "add to list" picker.
internal data class IptvListEntry(
    val id: String,
    val name: String,
    val isBuiltin: Boolean,
)
