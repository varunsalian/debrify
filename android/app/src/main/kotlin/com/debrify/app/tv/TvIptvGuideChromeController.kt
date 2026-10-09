package com.debrify.app.tv

import android.graphics.Typeface
import android.os.Handler
import android.view.View
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.util.UnstableApi
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import java.util.Locale

@OptIn(UnstableApi::class)
internal class TvIptvGuideChromeController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val currentIptvIndex: Int
        fun dp(value: Int): Int
        val guideStyle: GuideStyle
        val guideTokens: GuideTokens?
        fun guideTypeface(file: String?): Typeface?
        val iptvBrowseHandler: Handler
        val iptvChannels: MutableList<IptvChannelEntry>
        val iptvGuideController: TvIptvGuideController
        val iptvRecordingActionsController: TvIptvRecordingActionsController
        val iptvSourceId: String?
        val iptvSources: List<IptvSourceEntry>
        val iptvStartOverController: TvIptvStartOverController
        val iptvZapBannerController: TvIptvZapBannerController
    }
    internal val overlay = TvIptvGuideOverlayBuilder(activity, host, this)
    internal val pickers = TvIptvGuidePickers(activity, host, this)
    internal var iptvGuideCurrentName: TextView? = null
    internal var iptvGuideCurrentGroup: TextView? = null
    internal var iptvGuideCurrentEpg: TextView? = null
    internal var iptvGuideNowPlaying: View? = null
    internal var iptvGuideNowLogo: android.widget.ImageView? = null
    internal var iptvGuideNowLetter: TextView? = null

    // Contextual EPG pane shown beside the Lean Rail.
    internal var iptvEpgPanel: View? = null
    internal var iptvEpgLogo: android.widget.ImageView? = null
    internal var iptvEpgLetter: TextView? = null
    internal var iptvEpgChannelName: TextView? = null
    internal var iptvEpgChannelGroup: TextView? = null
    internal var iptvEpgDate: TextView? = null
    internal var iptvEpgLoading: View? = null
    internal var iptvEpgEmpty: View? = null
    internal var iptvEpgList: RecyclerView? = null
    internal var iptvEpgAdapter: IptvEpgAdapter? = null
    private var iptvEpgPrograms: List<IptvEpgProgram> = emptyList()
    private var iptvEpgDayOffset = 0
    internal var iptvEpgToken = 0
    internal var iptvEpgVisible = false
    internal var iptvEpgEntry: IptvChannelEntry? = null

    // ── IPTV EPG ─────────────────────────────────────────────────────────
    // Guide data comes from Flutter over the bridge (the Dart EPG service
    // recovers Xtream credentials from the channel URL and owns all caching),
    // so the native side only ever asks and paints.

    /** Fetch now/next for [entry] unless it's already fresh or in flight. */
    fun ensureIptvChannelEpg(entry: IptvChannelEntry) {
        if (!entry.isLive || entry.epgLoading) return
        val stale = entry.epgLoaded && entry.epgNowStopMs > 0 &&
            entry.epgNowStopMs < System.currentTimeMillis()
        val needsCatchupMetadata = entry.isCurrent && !entry.epgCatchupMetadataLoaded
        if (entry.epgLoaded && !stale && !needsCatchupMetadata) return
        if (!entry.url.startsWith("http")) return // stremio-tv:// keys etc.

        entry.epgLoading = true
        val requestedCatchupMetadata = entry.isCurrent
        requestIptvEpg(
            entry,
            includeSchedule = false,
            includeCatchupMetadata = requestedCatchupMetadata,
        ) { result ->
            entry.epgLoading = false
            entry.epgLoaded = true
            // A cheap now/next answer carries no panel archive fields and
            // overwrites epgNowHasArchive below. Invalidate the enrichment
            // marker with it so returning to this channel (including after
            // the programme advances) requests metadata for the new NOW row.
            entry.epgCatchupMetadataLoaded = requestedCatchupMetadata
            val now = result?.get("now") as? Map<*, *>
            entry.epgNowTitle =
                (now?.get("title") as? String)?.takeIf { it.isNotBlank() }
            entry.epgNowStartMs = (now?.get("startMs") as? Number)?.toLong() ?: 0L
            entry.epgNowStopMs = (now?.get("stopMs") as? Number)?.toLong() ?: 0L
            entry.epgNowHasArchive = now?.get("hasArchive") == true
            if (requestedCatchupMetadata && !entry.epgNowHasArchive) {
                // A recovered panel may publish archive metadata before the
                // current programme ends. Retry at a bounded cadence.
                host.iptvBrowseHandler.postDelayed({
                    entry.epgCatchupMetadataLoaded = false
                    if (entry.isCurrent && !activity.isFinishing && !activity.isDestroyed) {
                        ensureIptvChannelEpg(entry)
                    }
                }, 60_000L)
            }
            val next = result?.get("next") as? Map<*, *>
            entry.epgNextTitle =
                (next?.get("title") as? String)?.takeIf { it.isNotBlank() }
            entry.epgNextStartMs =
                (next?.get("startMs") as? Number)?.toLong() ?: 0L
            if (entry.epgNowTitle == null) {
                // Nothing airing per this answer — a guide still downloading
                // on the Flutter side, a transient fetch failure, or a gap
                // until the next programme. Without a retry deadline the
                // stale rule (`stopMs > 0 && stopMs < now`) never re-arms
                // and the entry stays blank all session. Reuse stopMs as
                // "re-ask at": when the next programme starts, or in 60
                // seconds — short, because the common cause is the guide
                // finishing its download moments after the first ask, and a
                // longer lock reads as "EPG doesn't work on TV". Dart's
                // caches rate-limit the repeat asks.
                val retryAt = System.currentTimeMillis() + 60 * 1000L
                val nextStart = entry.epgNextStartMs
                entry.epgNowStopMs =
                    if (nextStart > 0 && nextStart < retryAt) nextStart else retryAt
            }
            host.iptvGuideController.iptvChannelAdapter?.notifyEpgFor(entry)
            if (entry.isCurrent) {
                updateIptvGuideEpgHeader()
                host.iptvStartOverController.updateIptvStartOverButton(entry)
                // A visible zap banner for this channel paints the fresh data.
                if (host.iptvZapBannerController.iptvZapBanner?.visibility == View.VISIBLE) {
                    host.iptvZapBannerController.paintIptvZapBannerEpg(entry)
                }
                // It may have become current while a cheap row request was
                // in flight. Follow that answer with the one archive-aware
                // upgrade instead of falsely marking metadata complete.
                if (!requestedCatchupMetadata) ensureIptvChannelEpg(entry)
            }
        }
    }

    /** Paint the playing channel's now/next line in the guide header. */
    fun updateIptvGuideEpgHeader() {
        val epgView = iptvGuideCurrentEpg ?: return
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)
        val nowTitle = entry?.epgNowTitle
        if (entry == null || nowTitle == null) {
            epgView.visibility = View.GONE
            return
        }
        val text = StringBuilder("Now: $nowTitle")
        entry.epgNextTitle?.let { text.append("   ›   Next: $it") }
        epgView.text = text
        epgView.visibility = View.VISIBLE
    }

    /** The guide-list entry that currently holds DPAD focus, if any. */
    fun focusedIptvGuideEntry(): IptvChannelEntry? {
        val list = host.iptvGuideController.iptvGuideList ?: return null
        val focused = list.focusedChild ?: return null
        val holder = list.getChildViewHolder(focused) ?: return null
        val position = holder.bindingAdapterPosition
        if (position == RecyclerView.NO_POSITION) return null
        return host.iptvGuideController.iptvChannelAdapter?.entryAt(position)
    }

    fun formatEpgTime(ms: Long): String =
        android.text.format.DateFormat.getTimeFormat(activity).format(java.util.Date(ms))

    /** RIGHT on a live row opens its schedule beside the Lean Rail. */
    fun showIptvSchedulePane(entry: IptvChannelEntry) {
        val token = ++iptvEpgToken
        iptvEpgEntry = entry
        iptvEpgVisible = true
        // The floating now-playing card occupies the same right-hand space on
        // compact TV viewports. Keep the schedule column completely exposed.
        iptvGuideNowPlaying?.visibility = View.GONE
        iptvEpgDayOffset = 0
        iptvEpgPrograms = emptyList()
        iptvEpgPanel?.visibility = View.VISIBLE
        iptvEpgLoading?.visibility = View.VISIBLE
        iptvEpgEmpty?.visibility = View.GONE
        iptvEpgList?.visibility = View.GONE
        iptvEpgChannelName?.text = entry.displayName
        iptvEpgChannelGroup?.text =
            listOfNotNull(
                entry.group,
                "Channel ${entry.channelNumber ?: (entry.index + 1)}",
            ).joinToString(" · ")
        paintIptvEpgLogo(entry)
        selectIptvEpgDay(0, requestFocus = false)

        requestIptvEpg(entry, includeSchedule = true) { result ->
            if (token != iptvEpgToken || activity.isFinishing || activity.isDestroyed ||
                !host.iptvGuideController.iptvGuideVisible || !iptvEpgVisible
            ) {
                return@requestIptvEpg
            }
            iptvEpgPrograms = (result?.get("schedule") as? List<*>)
                ?.mapNotNull { it as? Map<*, *> }
                ?.mapNotNull { item ->
                    val title = (item["title"] as? String)?.takeIf { it.isNotBlank() }
                        ?: return@mapNotNull null
                    val startMs = (item["startMs"] as? Number)?.toLong()
                        ?: return@mapNotNull null
                    val stopMs = (item["stopMs"] as? Number)?.toLong()
                        ?: return@mapNotNull null
                    IptvEpgProgram(
                        title = title,
                        description = (item["description"] as? String)
                            ?.takeIf { it.isNotBlank() },
                        startMs = startMs,
                        stopMs = stopMs,
                        hasArchive = item["hasArchive"] == true,
                    )
                } ?: emptyList()
            iptvEpgLoading?.visibility = View.GONE
            selectIptvEpgDay(0)
        }
    }

    fun paintIptvEpgLogo(entry: IptvChannelEntry) {
        val firstLetter = entry.name.firstOrNull()?.uppercase() ?: "?"
        if (entry.logoUrl.isNullOrEmpty()) {
            iptvEpgLogo?.visibility = View.GONE
            iptvEpgLetter?.text = firstLetter
            iptvEpgLetter?.visibility = View.VISIBLE
            return
        }
        iptvEpgLetter?.visibility = View.GONE
        iptvEpgLogo?.visibility = View.VISIBLE
        iptvEpgLogo?.let { logo ->
            com.bumptech.glide.Glide.with(activity)
                .load(entry.logoUrl)
                .centerInside()
                .listener(
                    object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                        override fun onLoadFailed(
                            e: com.bumptech.glide.load.engine.GlideException?,
                            model: Any?,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                            isFirstResource: Boolean,
                        ): Boolean {
                            logo.visibility = View.GONE
                            iptvEpgLetter?.text = firstLetter
                            iptvEpgLetter?.visibility = View.VISIBLE
                            return true
                        }

                        override fun onResourceReady(
                            resource: android.graphics.drawable.Drawable,
                            model: Any,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                            dataSource: com.bumptech.glide.load.DataSource,
                            isFirstResource: Boolean,
                        ): Boolean = false
                    },
                )
                .into(logo)
        }
    }

    fun selectIptvEpgDay(dayOffset: Int, requestFocus: Boolean = true) {
        iptvEpgDayOffset = dayOffset
        val calendar = java.util.Calendar.getInstance().apply {
            add(java.util.Calendar.DAY_OF_YEAR, dayOffset)
        }
        val year = calendar.get(java.util.Calendar.YEAR)
        val day = calendar.get(java.util.Calendar.DAY_OF_YEAR)
        val filtered = iptvEpgPrograms.filter { program ->
            java.util.Calendar.getInstance().apply { timeInMillis = program.startMs }.let {
                it.get(java.util.Calendar.YEAR) == year &&
                    it.get(java.util.Calendar.DAY_OF_YEAR) == day
            }
        }
        iptvEpgDate?.text = java.text.SimpleDateFormat(
            "EEEE, d MMMM",
            Locale.getDefault(),
        ).format(calendar.time)
        iptvEpgAdapter?.updatePrograms(filtered)
        iptvEpgList?.visibility = if (filtered.isEmpty()) View.GONE else View.VISIBLE
        iptvEpgEmpty?.visibility =
            if (filtered.isEmpty() && iptvEpgLoading?.visibility != View.VISIBLE) {
                View.VISIBLE
            } else {
                View.GONE
            }
        val dayButtons = listOf(
            -3 to activity.findViewById<AppCompatButton>(R.id.iptv_epg_day_three_ago),
            -2 to activity.findViewById<AppCompatButton>(R.id.iptv_epg_day_two_ago),
            -1 to activity.findViewById<AppCompatButton>(R.id.iptv_epg_day_yesterday),
            0 to activity.findViewById<AppCompatButton>(R.id.iptv_epg_day_today),
            1 to activity.findViewById<AppCompatButton>(R.id.iptv_epg_day_tomorrow),
            2 to activity.findViewById<AppCompatButton>(R.id.iptv_epg_day_later),
        )
        dayButtons.forEach { (offset, button) ->
            button?.isSelected = offset == dayOffset
        }
        if (requestFocus && filtered.isNotEmpty()) {
            val now = System.currentTimeMillis()
            val position = filtered.indexOfFirst { it.startMs <= now && now < it.stopMs }
                .coerceAtLeast(0)
            iptvEpgList?.scrollToPosition(position)
            iptvEpgList?.post {
                iptvEpgList?.findViewHolderForAdapterPosition(position)
                    ?.itemView?.requestFocus()
            }
        }
    }

    fun hideIptvEpgPane() {
        iptvEpgToken++
        iptvEpgVisible = false
        iptvEpgEntry = null
        iptvEpgPanel?.visibility = View.GONE
        iptvGuideNowPlaying?.visibility =
            if (host.iptvGuideController.iptvGuideVisible && host.currentIptvIndex in host.iptvChannels.indices) {
                View.VISIBLE
            } else {
                View.GONE
            }
        iptvEpgPrograms = emptyList()
        iptvEpgAdapter?.updatePrograms(emptyList())
    }

    fun isFocusInIptvEpgPanel(): Boolean {
        val focused = activity.currentFocus ?: return false
        val panel = iptvEpgPanel ?: return false
        var node: View? = focused
        while (node != null) {
            if (node === panel) return true
            node = node.parent as? View
        }
        return false
    }

    fun updateIptvGuideCurrentName() {
        if (host.currentIptvIndex in host.iptvChannels.indices) {
            val ch = host.iptvChannels[host.currentIptvIndex]
            iptvGuideCurrentName?.text = ch.displayName
            iptvGuideNowPlaying?.visibility =
                if (iptvEpgVisible) View.GONE else View.VISIBLE

            // Group
            if (ch.group != null && ch.group.isNotEmpty()) {
                iptvGuideCurrentGroup?.text = ch.group
                iptvGuideCurrentGroup?.visibility = View.VISIBLE
            } else {
                iptvGuideCurrentGroup?.visibility = View.GONE
            }

            // EPG now/next for the playing channel
            updateIptvGuideEpgHeader()
            ensureIptvChannelEpg(ch)

            // Now playing logo
            val firstLetter = if (ch.name.isNotEmpty()) ch.name[0].uppercase() else "?"
            if (!ch.logoUrl.isNullOrEmpty()) {
                iptvGuideNowLetter?.visibility = View.GONE
                iptvGuideNowLogo?.visibility = View.VISIBLE
                com.bumptech.glide.Glide.with(activity)
                    .load(ch.logoUrl)
                    .centerInside()
                    .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                        override fun onLoadFailed(
                            e: com.bumptech.glide.load.engine.GlideException?,
                            model: Any?,
                            target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                            isFirstResource: Boolean
                        ): Boolean {
                            iptvGuideNowLogo?.visibility = View.GONE
                            iptvGuideNowLetter?.text = firstLetter
                            iptvGuideNowLetter?.visibility = View.VISIBLE
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
                    .into(iptvGuideNowLogo!!)
            } else {
                iptvGuideNowLogo?.visibility = View.GONE
                iptvGuideNowLetter?.text = firstLetter
                iptvGuideNowLetter?.visibility = View.VISIBLE
            }
        } else {
            iptvGuideNowPlaying?.visibility = View.GONE
        }
    }
}
