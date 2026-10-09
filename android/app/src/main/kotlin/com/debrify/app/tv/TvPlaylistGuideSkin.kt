package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import java.util.Locale

internal class TvPlaylistGuideSkin(
    private val activity: AppCompatActivity,
    private val host: TvPlaylistOverlayController.Host,
    private val playlist: TvPlaylistOverlayController,
) {

    // ── Guide skin ─────────────────────────────────────────────────────────
    // The series/collection Episodes overlay, restyled per dock skin: the
    // legacy overlay children are swapped for a per-skin layout that keeps
    // the id contract (android_tv_playlist + season_tabs_container), and the
    // adapters get a per-skin row layout + binder. CLASSIC never installs.
    //   OTT       — "The Shelf": bottom row of landscape stills.
    //   MARQUEE   — "The Playbill": serif index left, title page right.
    //   FROST     — "The Panel": translucent side sheet, video keeps playing.
    //   BROADCAST — "The Rundown": mono columns + PVW monitor, yellow bar focus.
    //   PULSE     — "The Grid": progress-ring cells, season rail on the left.
    //   TICKET    — "The Strip": slim bottom band, popover previews on focus.
    internal var guideSkinInstalled = false
    private val guideGridSpan = 5
    private var gdShowTitle: TextView? = null
    private var gdCaption: TextView? = null
    private var gdDetailNum: TextView? = null
    private var gdDetailTitle: TextView? = null
    private var gdDetailMeta: TextView? = null
    private var gdDetailDesc: TextView? = null
    private var gdDetailArt: android.widget.ImageView? = null
    private var gdMonArt: android.widget.ImageView? = null
    private var gdMonLabel: TextView? = null
    internal var gdPop: View? = null
    private var gdPopArt: android.widget.ImageView? = null
    private var gdPopTitle: TextView? = null
    private var gdPopDesc: TextView? = null

    val guideOverlayLayoutRes: Int?
        get() = when (host.controlsSkin) {
            TvControlsSkin.CLASSIC -> null
            TvControlsSkin.OTT -> R.layout.view_tv_guide_ott
            TvControlsSkin.FROST -> R.layout.view_tv_guide_frost
            TvControlsSkin.MARQUEE -> R.layout.view_tv_guide_marquee
            TvControlsSkin.BROADCAST -> R.layout.view_tv_guide_broadcast
            TvControlsSkin.PULSE -> R.layout.view_tv_guide_pulse
            TvControlsSkin.TICKET -> R.layout.view_tv_guide_ticket
        }

    val guideItemLayoutRes: Int
        get() = if (!guideSkinInstalled) {
            R.layout.item_android_tv_playlist_entry_horizontal
        } else when (host.controlsSkin) {
            TvControlsSkin.OTT -> R.layout.item_tv_guide_ott
            TvControlsSkin.FROST -> R.layout.item_tv_guide_frost
            TvControlsSkin.MARQUEE -> R.layout.item_tv_guide_marquee
            TvControlsSkin.BROADCAST -> R.layout.item_tv_guide_broadcast
            TvControlsSkin.PULSE -> R.layout.item_tv_guide_pulse
            TvControlsSkin.TICKET -> R.layout.item_tv_guide_ticket
            TvControlsSkin.CLASSIC -> R.layout.item_android_tv_playlist_entry_horizontal
        }

    /** Swap the legacy overlay children for the skin's guide layout. Runs in
     *  bindViews BEFORE any playlist findViewById so every legacy binding
     *  resolves inside the new layout. */
    fun installGuideOverlaySkin() {
        if (guideSkinInstalled) return
        val layoutRes = guideOverlayLayoutRes ?: return
        val overlay = activity.findViewById<ViewGroup?>(R.id.android_tv_playlist_overlay) ?: return
        overlay.removeAllViews()
        activity.layoutInflater.inflate(layoutRes, overlay, true)
        guideSkinInstalled = true
    }

    /** Null-safe binds for the skin-only views (each layout has a subset). */
    fun bindGuideSkinViews() {
        if (!guideSkinInstalled) return
        gdShowTitle = activity.findViewById(R.id.gd_show_title)
        gdCaption = activity.findViewById(R.id.gd_caption)
        gdDetailNum = activity.findViewById(R.id.gd_detail_num)
        gdDetailTitle = activity.findViewById(R.id.gd_detail_title)
        gdDetailMeta = activity.findViewById(R.id.gd_detail_meta)
        gdDetailDesc = activity.findViewById(R.id.gd_detail_desc)
        gdDetailArt = activity.findViewById(R.id.gd_detail_art)
        gdMonArt = activity.findViewById(R.id.gd_mon_art)
        gdMonLabel = activity.findViewById(R.id.gd_mon_label)
        gdPop = activity.findViewById(R.id.gd_pop)
        gdPopArt = activity.findViewById(R.id.gd_pop_art)
        gdPopTitle = activity.findViewById(R.id.gd_pop_title)
        gdPopDesc = activity.findViewById(R.id.gd_pop_desc)
    }

    /** Vertical list for the reading skins, 5-up grid for PULSE; OTT/TICKET
     *  keep the legacy horizontal manager. */
    fun applyGuideLayoutManager() {
        if (!guideSkinInstalled) return
        when (host.controlsSkin) {
            TvControlsSkin.MARQUEE, TvControlsSkin.FROST, TvControlsSkin.BROADCAST -> {
                host.playlistView.layoutManager =
                    LinearLayoutManager(activity, LinearLayoutManager.VERTICAL, false)
            }
            TvControlsSkin.PULSE -> {
                val glm = androidx.recyclerview.widget.GridLayoutManager(activity, guideGridSpan)
                glm.spanSizeLookup =
                    object : androidx.recyclerview.widget.GridLayoutManager.SpanSizeLookup() {
                        override fun getSpanSize(position: Int): Int {
                            // Series season headers (view type 0) span the full
                            // row. Collection adapters have a single view type
                            // (also 0), so gate on the mode — every movie cell
                            // is a normal 1-span cell.
                            if (playlist.playlistMode != PlaylistMode.SERIES) return 1
                            val adapter = host.playlistView.adapter ?: return 1
                            return if (adapter.getItemViewType(position) == 0) guideGridSpan else 1
                        }
                    }
                host.playlistView.layoutManager = glm
            }
            else -> Unit
        }
    }

    /** The legacy key listener assumes a horizontal row (LEFT/RIGHT move,
     *  UP/DOWN escape to tabs). Vertical and grid skins swap the axes —
     *  deliberate last-set-wins over the listener set just above. */
    fun applyGuideKeyOverride() {
        if (!guideSkinInstalled) return
        val vertical = host.controlsSkin == TvControlsSkin.MARQUEE ||
            host.controlsSkin == TvControlsSkin.FROST ||
            host.controlsSkin == TvControlsSkin.BROADCAST
        val grid = host.controlsSkin == TvControlsSkin.PULSE
        if (!vertical && !grid) return // OTT/TICKET: the horizontal listener is right
        host.playlistView.setOnKeyListener { _, keyCode, event ->
            if (!playlist.playlistVisible) return@setOnKeyListener false
            if (event.action != KeyEvent.ACTION_DOWN) return@setOnKeyListener false
            // Mirror movePlaylistFocus: during rapid input focus is in flight
            // and focusedChild is null — the tracked target is the truth, or
            // the edge decisions below (escape to tabs/rail) misfire.
            val pos = if (playlist.navigator.navigationTargetPosition >= 0) {
                playlist.navigator.navigationTargetPosition
            } else {
                host.playlistView.focusedChild
                    ?.let { host.playlistView.getChildAdapterPosition(it) }
                    ?: RecyclerView.NO_POSITION
            }
            if (vertical) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_DOWN -> { playlist.navigator.movePlaylistFocus(1); true }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        val first = playlist.navigator.findNextFocusablePosition(0, 1)
                        if (pos != RecyclerView.NO_POSITION && pos <= first) {
                            false // top row: let focus escape to the season tabs
                        } else {
                            playlist.navigator.movePlaylistFocus(-1); true
                        }
                    }
                    // Trap the cross axis so focus can't fall out of the overlay.
                    KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> true
                    else -> false
                }
            } else {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_RIGHT -> { playlist.navigator.movePlaylistFocus(1); true }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        // Column via the span lookup, not pos % span — a
                        // full-span season header would shift every row.
                        val col = (host.playlistView.layoutManager
                            as? androidx.recyclerview.widget.GridLayoutManager)
                            ?.spanSizeLookup
                            ?.takeIf { pos != RecyclerView.NO_POSITION }
                            ?.getSpanIndex(pos, guideGridSpan)
                        if (col == 0) {
                            false // first column: escape to the season rail
                        } else {
                            playlist.navigator.movePlaylistFocus(-1); true
                        }
                    }
                    KeyEvent.KEYCODE_DPAD_DOWN -> { playlist.navigator.movePlaylistFocus(guideGridSpan); true }
                    KeyEvent.KEYCODE_DPAD_UP -> {
                        if (pos >= guideGridSpan) playlist.navigator.movePlaylistFocus(-guideGridSpan)
                        true
                    }
                    else -> false
                }
            }
        }
    }

    /** Restyle a season/collection tab into the skin's language (called after
     *  the legacy styling; classic tabs untouched). */
    fun applyGuideTabStyle(tab: TextView) {
        if (!guideSkinInstalled) return
        val csl = { res: Int -> androidx.core.content.ContextCompat.getColorStateList(activity, res) }
        when (host.controlsSkin) {
            TvControlsSkin.OTT -> {
                tab.background = null
                tab.setTextColor(csl(R.color.gd_tab_text_light))
                tab.textSize = 13f
            }
            TvControlsSkin.MARQUEE -> {
                tab.background = null
                tab.setTextColor(csl(R.color.gd_tab_text_marquee))
                tab.typeface = android.graphics.Typeface.create("serif", android.graphics.Typeface.BOLD)
                tab.textSize = 11.5f
                tab.letterSpacing = 0.14f
            }
            TvControlsSkin.FROST -> {
                tab.setBackgroundResource(R.drawable.gd_tab_frost)
                tab.setTextColor(csl(R.color.gd_tab_text_bcast))
                tab.textSize = 11f
                tab.setPadding(host.dp(11), host.dp(4), host.dp(11), host.dp(4))
            }
            TvControlsSkin.BROADCAST -> {
                tab.setBackgroundResource(R.drawable.gd_tab_bcast)
                tab.setTextColor(csl(R.color.gd_tab_text_bcast))
                tab.typeface = android.graphics.Typeface.create(
                    android.graphics.Typeface.MONOSPACE, android.graphics.Typeface.BOLD)
                tab.textSize = 10.5f
                tab.setPadding(host.dp(8), host.dp(3), host.dp(8), host.dp(3))
            }
            TvControlsSkin.PULSE -> {
                tab.setBackgroundResource(R.drawable.gd_tab_pulse)
                tab.setTextColor(csl(R.color.gd_tab_text_pulse))
                tab.textSize = 11.5f
                tab.setPadding(host.dp(10), host.dp(5), host.dp(10), host.dp(5))
                (tab.layoutParams as? android.widget.LinearLayout.LayoutParams)?.let {
                    it.marginEnd = 0
                    it.bottomMargin = host.dp(6) // vertical rail
                    it.width = android.widget.LinearLayout.LayoutParams.MATCH_PARENT
                }
                tab.gravity = android.view.Gravity.CENTER
            }
            TvControlsSkin.TICKET -> {
                tab.setBackgroundResource(R.drawable.gd_tab_ticket)
                tab.setTextColor(csl(R.color.gd_tab_text_ticket))
                tab.typeface = android.graphics.Typeface.MONOSPACE
                tab.textSize = 9f
                tab.setPadding(host.dp(6), host.dp(1), host.dp(6), host.dp(1))
            }
            TvControlsSkin.CLASSIC -> Unit
        }
    }

    /** Per-skin row styling appended after the shared bind. itemIndex is -1
     *  for absent guide rows (fetch-on-click). */
    fun guideSkinBind(itemView: View, item: PlaybackItem, itemIndex: Int, isActive: Boolean) {
        val progress = item.displayProgressPercent()
        val watched = progress >= 95
        when (host.controlsSkin) {
            TvControlsSkin.MARQUEE, TvControlsSkin.TICKET -> {
                if (host.controlsSkin == TvControlsSkin.MARQUEE) {
                    itemView.findViewById<TextView?>(R.id.gd_item_num)?.text =
                        item.episode?.toString() ?: if (itemIndex >= 0) (itemIndex + 1).toString() else "·"
                }
                itemView.findViewById<TextView?>(R.id.android_tv_playlist_item_title)?.let { t ->
                    t.paintFlags = if (watched && !isActive) {
                        t.paintFlags or android.graphics.Paint.STRIKE_THRU_TEXT_FLAG
                    } else {
                        t.paintFlags and android.graphics.Paint.STRIKE_THRU_TEXT_FLAG.inv()
                    }
                }
            }
            TvControlsSkin.BROADCAST -> {
                val season = item.season
                val episode = item.episode
                itemView.findViewById<TextView?>(R.id.gd_item_num)?.text = when {
                    season != null && episode != null -> "%d%02d".format(season, episode)
                    episode != null -> "%03d".format(episode)
                    itemIndex >= 0 -> "%03d".format(itemIndex + 1)
                    else -> "———"
                }
                itemView.findViewById<TextView?>(R.id.gd_item_status)?.let { status ->
                    val (text, color) = when {
                        itemIndex < 0 && !isActive && item.url.isEmpty() ->
                            "FETCH" to 0xFFF5C518.toInt()
                        isActive -> "● ON AIR" to 0xFFEF4444.toInt()
                        watched -> "CLEARED" to 0x66FFFFFF.toInt()
                        progress in 6..94 -> "$progress% IN" to 0x8CFFFFFF.toInt()
                        else -> "READY" to 0x8CFFFFFF.toInt()
                    }
                    status.text = text
                    // Stateful color: the yellow focus bar needs dark text —
                    // a plain int here would defeat the row's focus flip.
                    status.setTextColor(
                        android.content.res.ColorStateList(
                            arrayOf(
                                intArrayOf(android.R.attr.state_focused),
                                intArrayOf(),
                            ),
                            intArrayOf(0xDE000000.toInt(), color),
                        )
                    )
                }
            }
            TvControlsSkin.PULSE -> {
                itemView.findViewById<android.widget.ProgressBar?>(R.id.gd_ring)?.progress =
                    if (watched) 100 else progress
                itemView.findViewById<TextView?>(R.id.gd_ring_num)?.text =
                    item.episode?.toString()
                        ?: if (itemIndex >= 0) (itemIndex + 1).toString() else "?"
            }
            else -> Unit
        }
    }

    /** The focused row feeds the skin's detail surface (Marquee title page,
     *  OTT caption, Broadcast PVW monitor, Pulse caption line, Ticket popover). */
    fun updateGuideDetail(item: PlaybackItem) {
        if (!guideSkinInstalled) return
        val desc = item.description?.trim()
            ?.takeUnless { it.equals("null", ignoreCase = true) || it.isBlank() }
        val mins = (item.durationMs / 60000).toInt().takeIf { it > 0 }
        val se = if (item.season != null && item.episode != null) {
            "S%02dE%02d".format(item.season, item.episode)
        } else null
        when (host.controlsSkin) {
            TvControlsSkin.OTT -> gdCaption?.text = desc ?: ""
            TvControlsSkin.MARQUEE -> {
                gdDetailNum?.text = item.episode?.let { "%02d".format(it) } ?: ""
                gdDetailTitle?.text = item.title
                val parts = mutableListOf<String>()
                if (item.season != null && item.episode != null) {
                    parts.add("SEASON ${item.season} · EPISODE ${item.episode}")
                }
                item.rating?.takeIf { it > 0 }?.let { parts.add("★ %.1f".format(it)) }
                mins?.let { parts.add("$it MIN") }
                gdDetailMeta?.text = parts.joinToString("   ·   ")
                gdDetailDesc?.text = desc ?: ""
                loadGuideArt(gdDetailArt, item.artwork)
            }
            TvControlsSkin.BROADCAST -> {
                gdMonLabel?.text = "PVW · " + (se ?: item.title.uppercase(Locale.US))
                loadGuideArt(gdMonArt, item.artwork)
            }
            TvControlsSkin.PULSE -> {
                val lead = item.episode?.let { "E$it · " } ?: ""
                gdDetailDesc?.text = lead + item.title + (desc?.let { " — $it" } ?: "")
            }
            TvControlsSkin.TICKET -> {
                gdPop?.visibility = View.VISIBLE
                gdPopTitle?.text = (se?.let { "$it · " } ?: "") + item.title.uppercase(Locale.US)
                val meta = mutableListOf<String>()
                mins?.let { meta.add("${it}m") }
                item.rating?.takeIf { it > 0 }?.let { meta.add("★ %.1f".format(it)) }
                gdPopDesc?.text = desc ?: meta.joinToString(" · ")
                loadGuideArt(gdPopArt, item.artwork)
            }
            else -> Unit
        }
    }

    fun loadGuideArt(target: android.widget.ImageView?, artwork: String?) {
        val v = target ?: return
        val art = artwork?.takeUnless { it.equals("null", ignoreCase = true) || it.isBlank() }
        if (art == null) {
            com.bumptech.glide.Glide.with(activity).clear(v)
            v.setImageDrawable(null)
            return
        }
        com.bumptech.glide.Glide.with(activity).load(art).centerCrop().into(v)
    }

    /** Show-open chrome: show title, counts, and the current item seeding the
     *  detail surface so the pane is never empty. */
    fun seedGuideSkinChrome() {
        if (!guideSkinInstalled) return
        val model = host.payload
        val current = model?.items?.getOrNull(host.currentIndex)
        val show = host.ottShowName?.takeIf { it.isNotBlank() }
            ?: current?.title
            ?: ""
        gdShowTitle?.text = when (host.controlsSkin) {
            TvControlsSkin.BROADCAST, TvControlsSkin.TICKET -> show.uppercase(Locale.US)
            else -> show
        }
        val items = model?.items.orEmpty()
        if (items.size > 1) {
            val watchedCount = items.count { it.displayProgressPercent() >= 95 }
            when (host.controlsSkin) {
                TvControlsSkin.FROST, TvControlsSkin.PULSE ->
                    gdCaption?.text = "${items.size} episodes · $watchedCount watched"
                TvControlsSkin.BROADCAST ->
                    gdCaption?.text = "${items.size} LISTED · OK ROLLS THE FOCUSED ITEM"
                else -> Unit
            }
        }
        current?.let { updateGuideDetail(it) }
    }
}
