package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.util.UnstableApi
import com.debrify.app.R
import kotlinx.coroutines.cancel
import java.util.Locale

@OptIn(UnstableApi::class)
internal class TvIptvZapBannerController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val controlsMenuVisible: Boolean
        val controlsOverlay: View?
        val currentIptvIndex: Int
        fun dp(value: Int): Int
        fun ensureIptvChannelEpg(entry: IptvChannelEntry): Unit
        fun formatEpgTime(timeMs: Long): String
        val guideStyle: GuideStyle
        val guideTokens: GuideTokens?
        fun guideTypeface(file: String?): Typeface?
        val iptvChannels: MutableList<IptvChannelEntry>
        val iptvGuideVisible: Boolean
        val iptvRecordingActionsController: TvIptvRecordingActionsController
        val iptvRecordingController: IptvRecordingController
        val iptvSources: List<IptvSourceEntry>
        val iptvZapCategoryTotal: Int
        val iptvZapPagingActive: Boolean
        val iptvZapSourceId: String?
        val progressHandler: Handler
        fun updateSubtitleControlsLift(): Unit
    }
    private val styled = TvIptvZapBannerStyledRenderer(activity, host, this)

    // ── IPTV zap banner ──────────────────────────────────────────────────
    // Channel-change feedback as a broadcast lower third: a scrim instead of
    // a card, so the picture stays whole. Channel identity anchors left, what
    // is on anchors right, a key-hint rail sits above the bottom edge, and the
    // elapsed rule runs the full width of the screen where it reads as part of
    // the broadcast rather than part of a dialog. Built in code and attached to
    // the content view on first use; EPG fields ride the same
    // ensureIptvChannelEpg flow the guide rows use, so a banner appearance also
    // warms the guide's data.

    var iptvZapBanner: FrameLayout? = null
    var iptvZapBannerLogo: android.widget.ImageView? = null
    var iptvZapBannerLetter: TextView? = null
    var iptvZapBannerNumber: TextView? = null
    var iptvZapBannerName: TextView? = null
    var iptvZapBannerMeta: TextView? = null
    var iptvZapBannerNow: TextView? = null
    var iptvZapBannerTimes: TextView? = null
    var iptvZapBannerNext: TextView? = null
    var iptvZapBannerProgress: ProgressBar? = null
    var iptvZapBannerHintChannel: View? = null
    var iptvZapBannerHintJump: View? = null
    var iptvZapBannerBody: View? = null
    var iptvZapBannerRail: View? = null

    /** The banner is riding on top of the controls dock as one merged panel,
     *  rather than floating over bare video after a zap. Docked, it has no
     *  auto-hide (it belongs to the dock's lifetime) and drops the key hints,
     *  whose keys move focus around the dock instead of zapping. */
    var iptvZapBannerDocked = false
    var iptvDockLayoutListenerAttached = false
    private var iptvZapBannerLayoutListenerAttached = false

    /** The channel the visible banner is describing. A paging window installed
     *  after the banner appeared changes this channel's position and the
     *  category total, so the banner needs a way back to its own entry. */
    private var iptvZapBannerEntry: IptvChannelEntry? = null
    private val iptvZapBannerHideToken = Any()
    private val iptvZapBannerTickToken = Any()

    private val iptvZapAccent = Color.parseColor("#00E5FF")

    /** One truth for "is THIS channel being recorded right now" — the same
     *  combination the Record button paints from. The styled zap banner's
     *  REC tag reads it on show and on every 1s repaint. */
    fun isRecordingCurrentIptvChannel(): Boolean =
        (host.iptvRecordingActionsController.recordingEngineEnabled && host.iptvRecordingActionsController.engineTaskIdForCurrentChannel() != null) ||
            host.iptvRecordingController.isActive

    private fun zapText(
        size: Float,
        alpha: Int,
        bold: Boolean = false,
        mono: Boolean = false,
    ) = TextView(activity).apply {
        textSize = size
        setTextColor(Color.argb(alpha, 255, 255, 255))
        typeface = when {
            mono && bold -> Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            mono -> Typeface.MONOSPACE
            bold -> Typeface.DEFAULT_BOLD
            else -> Typeface.DEFAULT
        }
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
    }

    /** One rail entry: keycaps followed by what pressing them does. */
    private fun zapHint(caps: List<String>, label: String): LinearLayout {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        caps.forEach { cap ->
            row.addView(
                zapText(10f, 190, mono = true).apply {
                    text = cap
                    setPadding(host.dp(5), 0, host.dp(5), host.dp(1))
                    background = GradientDrawable().apply {
                        cornerRadius = host.dp(3).toFloat()
                        setColor(Color.TRANSPARENT)
                        setStroke(host.dp(1), Color.argb(66, 255, 255, 255))
                    }
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { rightMargin = host.dp(4) },
            )
        }
        row.addView(
            zapText(10.5f, 102).apply {
                text = label
                isAllCaps = true
                letterSpacing = 0.1f
            },
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { leftMargin = host.dp(3) },
        )
        return row
    }

    private fun ensureIptvZapBanner(): FrameLayout {
        iptvZapBanner?.let { return it }
        host.guideTokens?.let { return styled.buildStyledIptvZapBanner(it) }

        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT

        val banner = FrameLayout(activity).apply {
            visibility = View.GONE
            elevation = host.dp(8).toFloat()
        }

        // The scrim replaces the old card: it darkens what sits under the text
        // without drawing a box the eye has to read around.
        banner.addView(
            View(activity).apply {
                background = GradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    intArrayOf(
                        Color.argb(0, 4, 6, 12),
                        Color.argb(184, 4, 6, 12),
                        Color.argb(240, 4, 6, 12),
                    ),
                )
            },
            FrameLayout.LayoutParams(match, match),
        )

        // ── channel identity (left) ──
        val logo = android.widget.ImageView(activity).apply {
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            visibility = View.GONE
        }
        val letter = zapText(30f, 255, bold = true).apply { gravity = Gravity.CENTER }
        val tile = FrameLayout(activity).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.argb(38, 255, 255, 255), Color.argb(13, 255, 255, 255)),
            ).apply {
                cornerRadius = host.dp(10).toFloat()
                setStroke(host.dp(1), Color.argb(41, 255, 255, 255))
            }
            setPadding(host.dp(6), host.dp(6), host.dp(6), host.dp(6))
        }
        tile.addView(logo, FrameLayout.LayoutParams(match, match))
        tile.addView(letter, FrameLayout.LayoutParams(match, match))

        val number = zapText(27f, 255, bold = true, mono = true).apply {
            setTextColor(iptvZapAccent)
        }
        val name = zapText(31f, 255, bold = true)
        val nameRow = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        nameRow.addView(
            number,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(12) },
        )
        nameRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))

        val liveTag = zapText(11.5f, 255, bold = true).apply {
            text = "● LIVE"
            setTextColor(Color.parseColor("#FF6470"))
            letterSpacing = 0.12f
        }
        val meta = zapText(11.5f, 143).apply {
            isAllCaps = true
            letterSpacing = 0.09f
        }
        val metaRow = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        metaRow.addView(
            liveTag,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(9) },
        )
        metaRow.addView(meta, LinearLayout.LayoutParams(0, wrap, 1f))

        val ident = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        ident.addView(nameRow, LinearLayout.LayoutParams(match, wrap))
        ident.addView(
            metaRow,
            LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(5) },
        )

        // ── what's on (right) ──
        val now = zapText(17f, 255, bold = true).apply {
            gravity = Gravity.END
            maxWidth = host.dp(380)
        }
        val times = zapText(11.5f, 153, mono = true).apply {
            gravity = Gravity.END
            maxWidth = host.dp(380)
        }
        val next = zapText(12.5f, 133).apply {
            gravity = Gravity.END
            maxWidth = host.dp(380)
        }
        val programme = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
        }
        programme.addView(now, LinearLayout.LayoutParams(wrap, wrap))
        programme.addView(
            times,
            LinearLayout.LayoutParams(wrap, wrap).apply { topMargin = host.dp(4) },
        )
        programme.addView(
            next,
            LinearLayout.LayoutParams(wrap, wrap).apply { topMargin = host.dp(4) },
        )

        // The identity column carries the weight, so a long channel name
        // ellipsizes before it can squeeze the programme out of the frame.
        val body = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        body.addView(tile, LinearLayout.LayoutParams(host.dp(68), host.dp(68)))
        body.addView(
            ident,
            LinearLayout.LayoutParams(0, wrap, 1f).apply { leftMargin = host.dp(20) },
        )
        body.addView(
            programme,
            LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(24) },
        )
        banner.addView(
            body,
            FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                leftMargin = host.dp(48)
                rightMargin = host.dp(48)
                bottomMargin = host.dp(58)
            },
        )

        // ── key hints ──
        // On its own line, so nothing it shares a row with can push it out when
        // a channel name runs long or the programme column empties.
        val hintChannel = zapHint(listOf("◀", "▶"), "Channel")
        val hintGuide = zapHint(listOf("▲"), "Guide")
        val hintJump = zapHint(listOf("HOLD ▲"), "Channel number")
        val rail = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        // Trailing margins rather than leading ones: when a hint is dropped
        // because its key does nothing on this channel, the one after it still
        // starts flush with the banner's 48 dp inset.
        rail.addView(
            hintChannel,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(20) },
        )
        rail.addView(hintGuide, LinearLayout.LayoutParams(wrap, wrap))
        rail.addView(View(activity), LinearLayout.LayoutParams(0, host.dp(1), 1f))
        rail.addView(hintJump, LinearLayout.LayoutParams(wrap, wrap))
        banner.addView(
            rail,
            FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                leftMargin = host.dp(48)
                rightMargin = host.dp(48)
                bottomMargin = host.dp(16)
            },
        )

        // ── elapsed rule, screen edge to screen edge ──
        val bar = ProgressBar(
            activity, null, android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 1000
            progressTintList =
                android.content.res.ColorStateList.valueOf(iptvZapAccent)
            progressBackgroundTintList = android.content.res.ColorStateList
                .valueOf(Color.argb(33, 255, 255, 255))
        }
        banner.addView(bar, FrameLayout.LayoutParams(match, host.dp(4), Gravity.BOTTOM))

        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        root.addView(
            banner,
            android.widget.FrameLayout.LayoutParams(match, host.dp(250)).apply {
                gravity = Gravity.BOTTOM
            },
        )

        iptvZapBanner = banner
        iptvZapBannerLogo = logo
        iptvZapBannerLetter = letter
        iptvZapBannerNumber = number
        iptvZapBannerName = name
        iptvZapBannerMeta = meta
        iptvZapBannerNow = now
        iptvZapBannerTimes = times
        iptvZapBannerNext = next
        iptvZapBannerProgress = bar
        iptvZapBannerHintChannel = hintChannel
        iptvZapBannerHintJump = hintJump
        iptvZapBannerBody = body
        iptvZapBannerRail = rail
        return banner
    }

    /**
     * Present [entry]'s channel panel.
     *
     * [docked] defaults to whether the controls dock is open, so every caller
     * lands in the right home without knowing about the modes: a zap with the
     * dock up repaints the dock's panel, and the same zap over bare video
     * floats the banner. Only the guide takes the screen outright.
     */
    fun showIptvZapBanner(
        entry: IptvChannelEntry,
        docked: Boolean = host.controlsMenuVisible,
    ) {
        // The banner is the topmost child of the content view and spans the
        // full width, so it would simply cover the guide; a zap from inside
        // the guide updates the guide's own header instead.
        if (host.iptvGuideVisible) return
        val banner = ensureIptvZapBanner()
        if (!iptvZapBannerLayoutListenerAttached) {
            iptvZapBannerLayoutListenerAttached = true
            banner.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                if (iptvZapBannerDocked && host.controlsMenuVisible) {
                    host.updateSubtitleControlsLift()
                }
            }
        }
        // Already on this surface: repaint in place. Re-running the entrance
        // would flash the panel on every keypress that re-arms the dock.
        val alreadyUp = banner.visibility == View.VISIBLE &&
            iptvZapBannerDocked == docked
        // Is this the same channel the panel is already describing? The dock
        // re-arms itself on every play/pause and DPAD press, and repainting
        // identity each time would re-run the logo's clear-and-fetch — a
        // visible flicker on every keypress. Position still refreshes: a
        // paging window can renumber the channel under a panel that stays up.
        val previous = iptvZapBannerEntry
        val sameChannel = previous != null &&
            previous.url == entry.url && previous.name == entry.name
        iptvZapBannerEntry = entry
        iptvZapBannerDocked = docked
        applyIptvZapBannerMode(docked)
        if (sameChannel) {
            paintIptvZapBannerPosition(entry)
        } else {
            paintIptvZapBannerIdentity(entry)
        }
        paintIptvZapBannerEpg(entry) // whatever is already known paints now
        // The same lazy fetch the guide rows use — a fresh answer repaints
        // the banner via the isCurrent hook in ensureIptvChannelEpg.
        host.ensureIptvChannelEpg(entry)

        if (!alreadyUp) {
            banner.animate().cancel()
            banner.visibility = View.VISIBLE
            banner.alpha = 0f
            if (docked) {
                // Ride the dock's entrance. It rises from +30 over 300ms, and
                // a panel that stayed put would visibly detach from the thing
                // it is supposed to be part of.
                banner.translationY = 30f
                banner.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(300)
                    .setInterpolator(android.view.animation.DecelerateInterpolator(1.5f))
                    .start()
            } else {
                banner.translationY = 0f
                banner.animate().alpha(1f).setDuration(160).start()
            }
        }
        host.progressHandler.removeCallbacksAndMessages(iptvZapBannerHideToken)
        // Docked, the panel belongs to the dock's lifetime — hideControlsMenu
        // takes it down. Only the floating banner times itself out.
        if (!docked) {
            host.progressHandler.postAtTime(
                { hideIptvZapBanner() },
                iptvZapBannerHideToken,
                android.os.SystemClock.uptimeMillis() + 4500,
            )
        }
        // Only when the panel is (re)entering: the tick chain re-posts itself
        // while visible, and re-scheduling on every repeat call would push the
        // next tick out by another second each time, so it would never fire.
        if (!alreadyUp) scheduleIptvZapBannerTick()
    }

    /**
     * Sit the panel flush on top of the controls dock, or back over bare
     * video.
     *
     * The dock's height is only known once it has been laid out, so a first
     * show re-applies on the next layout pass rather than stacking the panel
     * at the wrong offset.
     */
    fun applyIptvZapBannerMode(docked: Boolean) {
        host.guideTokens?.let { styled.applyStyledZapBannerMode(docked, it); return }
        val banner = iptvZapBanner ?: return
        val dock = host.controlsOverlay
        val dockHeight = if (docked) (dock?.height ?: 0) else 0
        (banner.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            if (lp.bottomMargin != dockHeight) {
                lp.bottomMargin = dockHeight
                banner.layoutParams = lp
            }
        }
        // The hints teach zapping; docked, those keys walk the dock's buttons.
        iptvZapBannerRail?.visibility = if (docked) View.GONE else View.VISIBLE
        // With the rail gone there is nothing between the text and the rule
        // to leave room for.
        (iptvZapBannerBody?.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            val margin = if (docked) host.dp(16) else host.dp(58)
            if (lp.bottomMargin != margin) {
                lp.bottomMargin = margin
                iptvZapBannerBody?.layoutParams = lp
            }
        }
        // The dock's height is 0 until it has been laid out, and it changes
        // with its own contents (the button row varies per channel). One
        // listener keeps the panel sitting on it whatever it does.
        if (docked && dock != null && !iptvDockLayoutListenerAttached) {
            iptvDockLayoutListenerAttached = true
            dock.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                if (iptvZapBannerDocked) {
                    applyIptvZapBannerMode(true)
                    host.updateSubtitleControlsLift()
                }
            }
        }
    }

    /**
     * Repaint the now/next block once a second while the banner is up.
     *
     * The elapsed rule and the "N min left" tail were computed once at paint
     * time, so both sat frozen for the whole time the banner was on screen —
     * a progress bar that visibly does not progress.
     */
    private fun scheduleIptvZapBannerTick() {
        host.progressHandler.removeCallbacksAndMessages(iptvZapBannerTickToken)
        host.progressHandler.postAtTime(
            {
                val entry = iptvZapBannerEntry
                if (entry != null && iptvZapBanner?.visibility == View.VISIBLE) {
                    paintIptvZapBannerEpg(entry)
                    scheduleIptvZapBannerTick()
                }
            },
            iptvZapBannerTickToken,
            android.os.SystemClock.uptimeMillis() + 1000,
        )
    }

    fun hideIptvZapBanner() {
        val banner = iptvZapBanner ?: return
        host.progressHandler.removeCallbacksAndMessages(iptvZapBannerTickToken)
        iptvZapBannerEntry = null
        iptvZapBannerDocked = false
        banner.animate().cancel()
        banner.animate().alpha(0f).setDuration(180).withEndAction {
            banner.visibility = View.GONE
        }.start()
    }

    /** Logo, channel number and name — the parts that only change on a zap. */
    private fun paintIptvZapBannerIdentity(entry: IptvChannelEntry) {
        host.guideTokens?.let { styled.paintStyledZapBannerIdentity(entry, it); return }
        val letter = iptvZapBannerLetter ?: return
        val logo = iptvZapBannerLogo ?: return

        val firstLetter = entry.name.firstOrNull()?.uppercase() ?: "?"
        // Drop the outgoing channel's image before anything else. Without
        // this, a zap between two channels that both have logos leaves the
        // PREVIOUS logo sitting beside the new channel's name for as long as
        // the new one takes to fetch — the banner showing two channels at
        // once. The guide adapter clears for the same reason on rebind.
        com.bumptech.glide.Glide.with(activity).clear(logo)
        logo.setImageDrawable(null)
        if (entry.logoUrl.isNullOrEmpty()) {
            logo.visibility = View.GONE
            letter.text = firstLetter
            letter.visibility = View.VISIBLE
        } else {
            // The letter holds the tile until the image actually lands, so the
            // cleared slot is never just an empty box.
            letter.text = firstLetter
            letter.visibility = View.VISIBLE
            logo.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(activity)
                .load(entry.logoUrl)
                .centerInside()
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?,
                        model: Any?,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                        isFirstResource: Boolean
                    ): Boolean {
                        logo.visibility = View.GONE
                        letter.text = firstLetter
                        letter.visibility = View.VISIBLE
                        return true
                    }
                    override fun onResourceReady(
                        resource: android.graphics.drawable.Drawable,
                        model: Any,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                        dataSource: com.bumptech.glide.load.DataSource,
                        isFirstResource: Boolean
                    ): Boolean {
                        // The image is here — retire the placeholder letter
                        // that was holding the tile.
                        letter.visibility = View.GONE
                        return false
                    }
                })
                .into(logo)
        }

        iptvZapBannerNumber?.text =
            (entry.channelNumber ?: (entry.index + 1)).toString()
        // The RAW name: the number already has its own accent slot beside
        // this, and displayName carries a "CH n" prefix of its own — pairing
        // the two printed the number twice ("7  CH 7  Sky Sports"). The guide
        // rows pair the same number view with entry.name for this reason.
        iptvZapBannerName?.text = entry.name
        paintIptvZapBannerPosition(entry)
    }

    /** Category, position within it, and which key hints are honest here. */
    fun paintIptvZapBannerPosition(entry: IptvChannelEntry) {
        val total = if (host.iptvZapPagingActive && host.iptvZapCategoryTotal > 0) {
            host.iptvZapCategoryTotal
        } else {
            host.iptvChannels.size
        }
        val locale = java.util.Locale.getDefault()
        val parts = buildList {
            entry.group?.trim()?.takeIf { it.isNotEmpty() }?.let { add(it) }
            if (total > 0) {
                add(
                    String.format(locale, "%,d", entry.index + 1) +
                        " of " + String.format(locale, "%,d", total)
                )
            }
        }
        iptvZapBannerMeta?.text =
            if (parts.isEmpty()) "" else "·  " + parts.joinToString("  ·  ")

        // Only teach a key that actually does something on this channel: with a
        // single channel and no paging there is nothing to zap to, and the jump
        // dialog refuses a favourites source outright.
        val canZap = host.iptvChannels.size > 1 || host.iptvZapPagingActive
        iptvZapBannerHintChannel?.visibility =
            if (canZap) View.VISIBLE else View.GONE
        val activeSource = host.iptvSources.firstOrNull { it.id == host.iptvZapSourceId }
        iptvZapBannerHintJump?.visibility =
            if (canZap && activeSource?.isFavorites != true) View.VISIBLE else View.GONE
    }

    /** Paint the banner's now/next lines from [entry]'s EPG fields. */
    fun paintIptvZapBannerEpg(entry: IptvChannelEntry) {
        host.guideTokens?.let { styled.paintStyledZapBannerEpg(entry, it); return }
        val nowView = iptvZapBannerNow ?: return
        val timesView = iptvZapBannerTimes ?: return
        val nextView = iptvZapBannerNext ?: return
        val bar = iptvZapBannerProgress ?: return

        val nowTitle = entry.epgNowTitle
        if (nowTitle != null) {
            nowView.text = nowTitle
            nowView.setTextColor(Color.WHITE)
            nowView.typeface = Typeface.DEFAULT_BOLD
        } else {
            // A channel with no guide still deserves a whole banner — say which
            // of the two silences this is rather than leaving a gap.
            nowView.text =
                if (entry.epgLoading) "Loading guide…" else "No guide data"
            nowView.setTextColor(Color.argb(107, 255, 255, 255))
            nowView.typeface = Typeface.DEFAULT
        }

        val start = entry.epgNowStartMs
        val stop = entry.epgNowStopMs
        val runtime = stop - start
        if (nowTitle != null && runtime > 0) {
            val nowMs = System.currentTimeMillis()
            val remaining = stop - nowMs
            val tail =
                if (remaining > 60_000L) "  ·  ${formatIptvRemaining(remaining)} left"
                else ""
            timesView.text =
                "${host.formatEpgTime(start)} – ${host.formatEpgTime(stop)}$tail"
            timesView.visibility = View.VISIBLE
            val elapsed = (nowMs - start).coerceIn(0L, runtime)
            bar.progress = ((elapsed.toDouble() / runtime) * 1000).toInt()
        } else {
            timesView.visibility = View.GONE
            // The rule stays — an empty track still reads as the edge of the
            // broadcast, where hiding it would make the banner look truncated.
            bar.progress = 0
        }

        val nextTitle = entry.epgNextTitle
        if (nowTitle != null && nextTitle != null) {
            val at =
                if (entry.epgNextStartMs > 0) "${host.formatEpgTime(entry.epgNextStartMs)}  ·  "
                else ""
            nextView.text = "Next  $at$nextTitle"
            nextView.visibility = View.VISIBLE
        } else {
            nextView.visibility = View.GONE
        }
    }

    /** A window install or merge renumbers this channel and can change the
     *  category total. Repaint a banner that is still on screen instead of
     *  leaving it showing whatever the launcher's list implied. */
    fun refreshIptvZapBannerPosition() {
        val banner = iptvZapBanner ?: return
        if (banner.visibility != View.VISIBLE) return
        val shown = iptvZapBannerEntry ?: return
        val playing = host.iptvChannels.getOrNull(host.currentIptvIndex)
        val entry = if (
            playing != null && playing.url == shown.url && playing.name == shown.name
        ) playing else shown
        if (entry !== shown) adoptIptvEpg(from = shown, to = entry)
        iptvZapBannerEntry = entry
        paintIptvZapBannerPosition(entry)
        paintIptvZapBannerEpg(entry)
    }
}
