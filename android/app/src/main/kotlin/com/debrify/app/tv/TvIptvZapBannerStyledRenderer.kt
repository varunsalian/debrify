package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
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

@OptIn(UnstableApi::class)
internal class TvIptvZapBannerStyledRenderer(
    private val activity: AppCompatActivity,
    private val host: TvIptvZapBannerController.Host,
    private val classic: TvIptvZapBannerController,
) {

    // ── Styled zap banner (GLASS / EDITION / CONSOLE) ──────────────────────
    // Its own builder + painters, per the style contract: the classic tree
    // above never changes, and the styled tree owns every color, typeface,
    // and drawable it paints. The shared BEHAVIORAL fns (show/hide, ticker,
    // position text, hint gating) work on both trees through the same field
    // refs.

    private var iptvZapStyledScrim: View? = null
    private var iptvZapStyledCard: LinearLayout? = null
    private var iptvZapGlassCardWidth = 0
    private var iptvZapStyledRule: View? = null
    private var iptvZapStyledLive: TextView? = null
    private var iptvZapStyledRec: TextView? = null
    private var iptvZapStyledEnd: TextView? = null
    private var iptvZapStyledMeterRow: LinearLayout? = null

    private fun styledZapText(
        t: GuideTokens,
        size: Float,
        color: Int,
        font: String? = null,
        bold: Boolean = false,
        italic: Boolean = false,
    ) = TextView(activity).apply {
        textSize = size
        setTextColor(color)
        val base = host.guideTypeface(font)
        typeface = when {
            base != null && italic -> Typeface.create(base, Typeface.ITALIC)
            base != null && bold -> Typeface.create(base, Typeface.BOLD)
            base != null -> base
            bold && italic -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD_ITALIC)
            bold -> Typeface.DEFAULT_BOLD
            italic -> Typeface.create(Typeface.DEFAULT, Typeface.ITALIC)
            else -> Typeface.DEFAULT
        }
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
    }

    /** One styled rail entry: keycaps + label, token colors only. */
    private fun styledZapHint(t: GuideTokens, caps: List<String>, label: String): LinearLayout {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        caps.forEach { cap ->
            row.addView(
                styledZapText(t, 10f, t.fgMid, font = t.monoFont).apply {
                    text = cap
                    setPadding(host.dp(5), 0, host.dp(5), host.dp(1))
                    background = GradientDrawable().apply {
                        cornerRadius = host.dp(3).toFloat()
                        setColor(Color.TRANSPARENT)
                        setStroke(host.dp(1), t.hairline2)
                    }
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { rightMargin = host.dp(4) },
            )
        }
        row.addView(
            styledZapText(t, 10.5f, t.fgFaint).apply {
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

    fun buildStyledIptvZapBanner(t: GuideTokens): FrameLayout {
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        val wrap = ViewGroup.LayoutParams.WRAP_CONTENT
        val style = host.guideStyle

        val banner = FrameLayout(activity).apply {
            visibility = View.GONE
            elevation = host.dp(8).toFloat()
        }

        // Scrim: glass keeps the video visible; edition/console fade to their
        // own ink/black. Hidden entirely while docked (the dock is the panel).
        val scrim = View(activity).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                when (style) {
                    GuideStyle.GLASS -> intArrayOf(0x000A0C12, 0x730A0C12)
                    GuideStyle.EDITION -> intArrayOf(0x000D0B09, t.bg)
                    else -> intArrayOf(0x00050505, t.bg)
                },
            )
        }
        banner.addView(scrim, FrameLayout.LayoutParams(match, match))

        // Shared-role views. The behavioral painters write text into these no
        // matter which styled tree they sit in (or, for the logo pair in
        // edition/console, don't sit in at all).
        val logo = android.widget.ImageView(activity).apply {
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            visibility = View.GONE
        }
        val letter = styledZapText(t, 24f, t.fg, bold = true).apply {
            gravity = Gravity.CENTER
        }
        val number: TextView
        val name: TextView
        val now: TextView
        val times: TextView
        val next: TextView
        val meta: TextView
        val liveTag: TextView
        val recTag = styledZapText(t, 10.5f, t.rec, bold = true).apply {
            text = "● REC"
            letterSpacing = 0.12f
            visibility = View.GONE
        }

        when (style) {
            GuideStyle.EDITION -> {
                // Editorial: the PROGRAMME is the headline, the channel is
                // the byline. Kicker caps in the italic serif above it.
                number = styledZapText(t, 11f, t.fgDim, font = t.captionFont, italic = true)
                liveTag = styledZapText(t, 11f, t.live, font = t.captionFont, italic = true).apply {
                    text = "· LIVE"
                }
                meta = styledZapText(t, 11f, t.fgFaint, font = t.captionFont, italic = true).apply {
                    isAllCaps = true
                    letterSpacing = 0.09f
                }
                now = styledZapText(t, 26f, t.fg, font = t.headlineFont)
                name = styledZapText(t, 12.5f, t.fgDim)
                times = styledZapText(t, 12.5f, t.fgDim)
                next = styledZapText(t, 12f, t.fgFaint, font = t.captionFont, italic = true)
            }
            GuideStyle.CONSOLE -> {
                number = styledZapText(t, 18f, t.accent, font = t.monoFont, bold = true)
                name = styledZapText(t, 19f, t.fg, font = t.nameFont, bold = true)
                liveTag = styledZapText(t, 10.5f, t.live, font = t.monoFont, bold = true).apply {
                    text = "● LIVE"
                    letterSpacing = 0.12f
                }
                meta = styledZapText(t, 10.5f, t.fgFaint, font = t.monoFont).apply {
                    isAllCaps = true
                    letterSpacing = 0.09f
                }
                now = styledZapText(t, 15f, t.fg, bold = true)
                times = styledZapText(t, 11f, t.fgDim, font = t.monoFont)
                next = styledZapText(t, 10.5f, t.fgFaint, font = t.monoFont).apply {
                    isAllCaps = true
                }
            }
            else -> { // GLASS
                number = styledZapText(t, 20f, t.fg, bold = true)
                name = styledZapText(t, 22f, t.fg, bold = true)
                liveTag = styledZapText(t, 11f, t.live, bold = true).apply {
                    text = "● LIVE"
                    letterSpacing = 0.12f
                }
                meta = styledZapText(t, 11f, t.fgDim).apply {
                    isAllCaps = true
                    letterSpacing = 0.09f
                }
                now = styledZapText(t, 15f, t.fgMid, bold = true)
                times = styledZapText(t, 11.5f, t.fgDim)
                next = styledZapText(t, 11.5f, t.fgFaint)
            }
        }

        // Elapsed rule. Glass/edition use a plain bar; console pairs it with
        // the programme's end time, instrument style.
        val bar = ProgressBar(
            activity, null, android.R.attr.progressBarStyleHorizontal
        ).apply {
            max = 1000
            progressTintList = android.content.res.ColorStateList.valueOf(
                if (style == GuideStyle.EDITION) t.fg else t.accent,
            )
            progressBackgroundTintList =
                android.content.res.ColorStateList.valueOf(t.hairline2)
        }
        val endTime = styledZapText(t, 10.5f, t.fgDim, font = t.monoFont).apply {
            visibility = View.GONE
        }

        val hintChannel = styledZapHint(t, listOf("◀", "▶"), "Channel")
        val hintGuide = styledZapHint(t, listOf("▲"), "Guide")
        val hintJump = styledZapHint(t, listOf("HOLD ▲"), "Channel number")
        val rail = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        rail.addView(
            hintChannel,
            LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(20) },
        )
        rail.addView(hintGuide, LinearLayout.LayoutParams(wrap, wrap))
        rail.addView(View(activity), LinearLayout.LayoutParams(0, host.dp(1), 1f))
        rail.addView(hintJump, LinearLayout.LayoutParams(wrap, wrap))

        val body: LinearLayout
        when (style) {
            GuideStyle.GLASS -> {
                // Island card, bottom-left, like a broadcast bug.
                val tile = FrameLayout(activity).apply {
                    background = t.tileDrawable(host.dp(14).toFloat(), host.dp(1))
                    setPadding(host.dp(6), host.dp(6), host.dp(6), host.dp(6))
                }
                tile.addView(logo, FrameLayout.LayoutParams(match, match))
                tile.addView(letter, FrameLayout.LayoutParams(match, match))

                val nameRow = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                nameRow.addView(
                    number,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(10) },
                )
                nameRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))
                nameRow.addView(
                    liveTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(12) },
                )
                nameRow.addView(
                    recTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(10) },
                )

                val ident = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                }
                ident.addView(nameRow, LinearLayout.LayoutParams(match, wrap))
                ident.addView(
                    now,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(6) },
                )
                ident.addView(
                    times,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(3) },
                )
                ident.addView(
                    meta,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(3) },
                )
                ident.addView(
                    next,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(3) },
                )

                val contentRow = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(host.dp(20), host.dp(18), host.dp(20), host.dp(14))
                }
                contentRow.addView(tile, LinearLayout.LayoutParams(host.dp(60), host.dp(60)))
                contentRow.addView(
                    ident,
                    LinearLayout.LayoutParams(0, wrap, 1f).apply { leftMargin = host.dp(16) },
                )

                val card = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                    background = t.panelDrawable(host.dp(22).toFloat(), host.dp(1))
                    clipToOutline = true
                }
                card.addView(contentRow, LinearLayout.LayoutParams(match, wrap))
                card.addView(
                    bar,
                    LinearLayout.LayoutParams(match, host.dp(3)).apply {
                        leftMargin = host.dp(20)
                        rightMargin = host.dp(20)
                        bottomMargin = host.dp(16)
                    },
                )

                val cardWidth = minOf(
                    host.dp(620),
                    activity.resources.displayMetrics.widthPixels - host.dp(56),
                ).coerceAtLeast(host.dp(220))
                iptvZapGlassCardWidth = cardWidth
                banner.addView(
                    card,
                    FrameLayout.LayoutParams(cardWidth, wrap, Gravity.BOTTOM or Gravity.START)
                        .apply {
                            leftMargin = host.dp(28)
                            bottomMargin = host.dp(58)
                        },
                )
                iptvZapStyledCard = card
                body = card
            }
            GuideStyle.EDITION -> {
                val rule = View(activity).apply { setBackgroundColor(t.hairline2) }
                val kickerRow = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                kickerRow.addView(
                    number,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(6) },
                )
                kickerRow.addView(
                    liveTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(6) },
                )
                kickerRow.addView(
                    recTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(6) },
                )
                kickerRow.addView(meta, LinearLayout.LayoutParams(0, wrap, 1f))

                val bylineRow = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                bylineRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))
                bylineRow.addView(
                    times,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(14) },
                )

                val column = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                }
                column.addView(rule, LinearLayout.LayoutParams(match, host.dp(1)))
                column.addView(
                    kickerRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(12) },
                )
                column.addView(
                    now,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(7) },
                )
                column.addView(
                    bylineRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(6) },
                )
                column.addView(
                    next,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(4) },
                )

                banner.addView(
                    column,
                    FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                        leftMargin = host.dp(48)
                        rightMargin = host.dp(48)
                        bottomMargin = host.dp(58)
                    },
                )
                banner.addView(bar, FrameLayout.LayoutParams(match, host.dp(2), Gravity.BOTTOM))
                iptvZapStyledRule = rule
                body = column
            }
            else -> { // CONSOLE
                val nameRow = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                nameRow.addView(
                    number,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(12) },
                )
                nameRow.addView(name, LinearLayout.LayoutParams(0, wrap, 1f))
                nameRow.addView(
                    liveTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(12) },
                )
                nameRow.addView(
                    recTag,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(10) },
                )

                val nowLabel = styledZapText(t, 10f, t.fgFaint, font = t.monoFont, bold = true)
                    .apply {
                        text = "NOW"
                        letterSpacing = 0.2f
                    }
                val nowRow = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                nowRow.addView(
                    nowLabel,
                    LinearLayout.LayoutParams(wrap, wrap).apply { rightMargin = host.dp(10) },
                )
                nowRow.addView(now, LinearLayout.LayoutParams(0, wrap, 1f))
                nowRow.addView(
                    times,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(14) },
                )

                val content = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                }
                content.addView(nameRow, LinearLayout.LayoutParams(match, wrap))
                content.addView(
                    nowRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(7) },
                )
                content.addView(
                    meta,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(4) },
                )
                content.addView(
                    next,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(4) },
                )

                // The amber rule rides the content block as a left rule.
                val ruled = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                }
                val rule = View(activity).apply { setBackgroundColor(t.accent) }
                ruled.addView(rule, LinearLayout.LayoutParams(host.dp(3), match))
                ruled.addView(
                    content,
                    LinearLayout.LayoutParams(0, wrap, 1f).apply { leftMargin = host.dp(16) },
                )

                val meterRow = LinearLayout(activity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                }
                meterRow.addView(bar, LinearLayout.LayoutParams(0, host.dp(5), 1f))
                meterRow.addView(
                    endTime,
                    LinearLayout.LayoutParams(wrap, wrap).apply { leftMargin = host.dp(10) },
                )

                val column = LinearLayout(activity).apply {
                    orientation = LinearLayout.VERTICAL
                }
                column.addView(ruled, LinearLayout.LayoutParams(match, wrap))
                column.addView(
                    meterRow,
                    LinearLayout.LayoutParams(match, wrap).apply { topMargin = host.dp(12) },
                )

                banner.addView(
                    column,
                    FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                        leftMargin = host.dp(48)
                        rightMargin = host.dp(48)
                        bottomMargin = host.dp(58)
                    },
                )
                iptvZapStyledRule = rule
                iptvZapStyledMeterRow = meterRow
                body = column
            }
        }

        banner.addView(
            rail,
            FrameLayout.LayoutParams(match, wrap, Gravity.BOTTOM).apply {
                leftMargin = host.dp(48)
                rightMargin = host.dp(48)
                bottomMargin = host.dp(16)
            },
        )

        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        root.addView(
            banner,
            FrameLayout.LayoutParams(match, host.dp(250)).apply {
                gravity = Gravity.BOTTOM
            },
        )

        classic.iptvZapBanner = banner
        classic.iptvZapBannerLogo = logo
        classic.iptvZapBannerLetter = letter
        classic.iptvZapBannerNumber = number
        classic.iptvZapBannerName = name
        classic.iptvZapBannerMeta = meta
        classic.iptvZapBannerNow = now
        classic.iptvZapBannerTimes = times
        classic.iptvZapBannerNext = next
        classic.iptvZapBannerProgress = bar
        classic.iptvZapBannerHintChannel = hintChannel
        classic.iptvZapBannerHintJump = hintJump
        classic.iptvZapBannerBody = body
        classic.iptvZapBannerRail = rail
        iptvZapStyledScrim = scrim
        iptvZapStyledLive = liveTag
        iptvZapStyledRec = recTag
        iptvZapStyledEnd = endTime
        return banner
    }

    /** The styled counterpart of [applyIptvZapBannerMode]: same margin/dock
     *  bookkeeping, plus the styled chrome that changes between homes (scrim
     *  off while docked; the glass card hands its surface to the dock). */
    fun applyStyledZapBannerMode(docked: Boolean, t: GuideTokens) {
        val banner = classic.iptvZapBanner ?: return
        val dock = host.controlsOverlay
        val dockHeight = if (docked) (dock?.height ?: 0) else 0
        (banner.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            if (lp.bottomMargin != dockHeight) {
                lp.bottomMargin = dockHeight
                banner.layoutParams = lp
            }
        }
        iptvZapStyledScrim?.visibility = if (docked) View.GONE else View.VISIBLE
        classic.iptvZapBannerRail?.visibility = if (docked) View.GONE else View.VISIBLE
        // Edition's top hairline reads wrong pressed against the dock edge.
        if (host.guideStyle == GuideStyle.EDITION) {
            iptvZapStyledRule?.visibility = if (docked) View.INVISIBLE else View.VISIBLE
        }
        if (host.guideStyle == GuideStyle.GLASS) {
            // Docked, the island hands its surface AND its island geometry to
            // the dock: full-width flush band, full-width progress pill.
            val card = iptvZapStyledCard
            card?.background =
                if (docked) null else t.panelDrawable(host.dp(22).toFloat(), host.dp(1))
            (card?.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                val width = if (docked) {
                    ViewGroup.LayoutParams.MATCH_PARENT
                } else {
                    iptvZapGlassCardWidth
                }
                val left = if (docked) host.dp(20) else host.dp(28)
                val right = if (docked) host.dp(20) else 0
                if (lp.width != width || lp.leftMargin != left ||
                    lp.rightMargin != right
                ) {
                    lp.width = width
                    lp.leftMargin = left
                    lp.rightMargin = right
                    card.layoutParams = lp
                }
            }
            (classic.iptvZapBannerProgress?.layoutParams as? LinearLayout.LayoutParams)
                ?.let { lp ->
                    val side = if (docked) 0 else host.dp(20)
                    val bottom = if (docked) host.dp(4) else host.dp(16)
                    if (lp.leftMargin != side || lp.bottomMargin != bottom) {
                        lp.leftMargin = side
                        lp.rightMargin = side
                        lp.bottomMargin = bottom
                        classic.iptvZapBannerProgress?.layoutParams = lp
                    }
                }
        }
        (classic.iptvZapBannerBody?.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            val margin = if (docked) host.dp(16) else host.dp(58)
            if (lp.bottomMargin != margin) {
                lp.bottomMargin = margin
                classic.iptvZapBannerBody?.layoutParams = lp
            }
        }
        if (docked && dock != null && !classic.iptvDockLayoutListenerAttached) {
            classic.iptvDockLayoutListenerAttached = true
            dock.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
                if (classic.iptvZapBannerDocked) classic.applyIptvZapBannerMode(true)
            }
        }
    }

    /** The styled identity paint: same Glide dance for the glass tile, no
     *  logo at all for edition/console (the number IS the identity there),
     *  per-style number formatting. Ends on the shared position painter. */
    fun paintStyledZapBannerIdentity(entry: IptvChannelEntry, t: GuideTokens) {
        if (host.guideStyle == GuideStyle.GLASS) {
            val letter = classic.iptvZapBannerLetter
            val logo = classic.iptvZapBannerLogo
            if (letter != null && logo != null) {
                val firstLetter = entry.name.firstOrNull()?.uppercase() ?: "?"
                com.bumptech.glide.Glide.with(activity).clear(logo)
                logo.setImageDrawable(null)
                if (entry.logoUrl.isNullOrEmpty()) {
                    logo.visibility = View.GONE
                    letter.text = firstLetter
                    letter.visibility = View.VISIBLE
                } else {
                    letter.text = firstLetter
                    letter.visibility = View.VISIBLE
                    logo.visibility = View.VISIBLE
                    com.bumptech.glide.Glide.with(activity)
                        .load(entry.logoUrl)
                        .centerInside()
                        .listener(object :
                            com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                            override fun onLoadFailed(
                                e: com.bumptech.glide.load.engine.GlideException?,
                                model: Any?,
                                target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>,
                                isFirstResource: Boolean,
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
                                isFirstResource: Boolean,
                            ): Boolean {
                                letter.visibility = View.GONE
                                return false
                            }
                        })
                        .into(logo)
                }
            }
        }

        val displayNumber = (entry.channelNumber ?: (entry.index + 1)).toString()
        classic.iptvZapBannerNumber?.text = when (host.guideStyle) {
            GuideStyle.CONSOLE -> displayNumber.padStart(3, '0')
            GuideStyle.EDITION -> "CH $displayNumber"
            else -> displayNumber
        }
        classic.iptvZapBannerName?.text = entry.name
        classic.paintIptvZapBannerPosition(entry)
    }

    /** The styled now/next paint. Owns its colors outright — the classic
     *  painter resets typefaces/colors per call and must never run on a
     *  styled tree. Also the REC tag's only writer (show + 1s tick). */
    fun paintStyledZapBannerEpg(entry: IptvChannelEntry, t: GuideTokens) {
        val nowView = classic.iptvZapBannerNow ?: return
        val timesView = classic.iptvZapBannerTimes ?: return
        val nextView = classic.iptvZapBannerNext ?: return
        val bar = classic.iptvZapBannerProgress ?: return

        val nowTitle = entry.epgNowTitle
        if (host.guideStyle == GuideStyle.EDITION) {
            // Editorial hierarchy: the headline slot carries the programme;
            // a guideless channel promotes its name there and the byline
            // names the silence.
            if (nowTitle != null) {
                nowView.text = nowTitle
                classic.iptvZapBannerName?.text = entry.name
                classic.iptvZapBannerName?.setTextColor(t.fgDim)
            } else {
                nowView.text = entry.name
                classic.iptvZapBannerName?.text =
                    if (entry.epgLoading) "Loading guide…" else "No guide data"
                classic.iptvZapBannerName?.setTextColor(t.fgFaint)
            }
        } else {
            if (nowTitle != null) {
                nowView.text = nowTitle
                nowView.setTextColor(
                    if (host.guideStyle == GuideStyle.CONSOLE) t.fg else t.fgMid,
                )
            } else {
                nowView.text =
                    if (entry.epgLoading) "Loading guide…" else "No guide data"
                nowView.setTextColor(t.fgFaint)
            }
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
            iptvZapStyledEnd?.let {
                it.text = host.formatEpgTime(stop)
                it.visibility = View.VISIBLE
            }
        } else {
            timesView.visibility = View.GONE
            bar.progress = 0
            iptvZapStyledEnd?.visibility = View.GONE
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

        iptvZapStyledRec?.visibility =
            if (classic.isRecordingCurrentIptvChannel()) View.VISIBLE else View.GONE
    }
}
