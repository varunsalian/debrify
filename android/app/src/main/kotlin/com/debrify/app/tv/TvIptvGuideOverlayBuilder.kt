package com.debrify.app.tv

import android.graphics.Typeface
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import androidx.core.content.ContextCompat
import androidx.core.widget.TextViewCompat
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.util.UnstableApi
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import com.debrify.app.R

@OptIn(UnstableApi::class)
internal class TvIptvGuideOverlayBuilder(
    private val activity: AppCompatActivity,
    private val host: TvIptvGuideChromeController.Host,
    private val chrome: TvIptvGuideChromeController,
) {

    fun setupIptvOverlay() {
        val guideList = host.iptvGuideController.iptvGuideList ?: return

        guideList.layoutManager = LinearLayoutManager(activity, LinearLayoutManager.VERTICAL, false)
        // Guide rows own their DPAD scale animation through
        // ViewPropertyAnimator. RecyclerView's DefaultItemAnimator uses that
        // same animator for change/removal transitions; rebinding a row then
        // cancels RecyclerView's animation from inside onBindViewHolder and
        // can synchronously recycle a still-tmp-detached holder. Android 9
        // throws in that state and kills the whole player process. List
        // changes are still applied immediately by DiffUtil; only the
        // conflicting decorative transition is disabled.
        guideList.itemAnimator = null
        host.iptvGuideController.iptvChannelAdapter = IptvChannelAdapter(
            channels = host.iptvGuideController.iptvBrowseChannels.toMutableList(),
            onItemClick = { entry ->
                if (isIptvSeriesSentinel(entry)) {
                    host.iptvGuideController.requestIptvBrowse(
                        action = "seriesEpisodes",
                        channelUrl = entry.url,
                        title = entry.name,
                        sourceIdOverride = entry.sourceId,
                    )
                } else if (host.iptvGuideController.iptvContentType == "episodes") {
                    host.iptvGuideController.commitIptvAllCategorySearch()
                    host.iptvGuideController.hideIptvGuide()
                    host.iptvGuideController.pager.disableIptvZapPaging()
                    host.iptvGuideController.navigator.switchToIptvChannel(entry)
                } else {
                    host.iptvGuideController.commitIptvAllCategorySearch()
                    host.iptvGuideController.hideIptvGuide()
                    host.iptvGuideController.pager.beginIptvCategoryZapSession(entry)
                }
            },
            onItemLongClick = { entry ->
                if (isIptvSeriesSentinel(entry)) {
                    Toast.makeText(
                        activity,
                        "Open the series to choose an episode",
                        Toast.LENGTH_SHORT,
                    ).show()
                } else if (host.iptvGuideController.iptvLists.any { !it.isBuiltin }) {
                    chrome.pickers.showIptvListPicker(entry)
                } else {
                    chrome.pickers.toggleIptvFavorite(entry)
                }
            },
            onEpgNeeded = { entry -> chrome.ensureIptvChannelEpg(entry) },
            tokens = host.guideTokens,
            style = host.guideStyle,
            nameTypeface = host.guideTokens?.let { host.guideTypeface(it.nameFont) },
            monoTypeface = host.guideTokens?.let { host.guideTypeface(it.monoFont) },
            headlineTypeface = host.guideTokens?.let { host.guideTypeface(it.headlineFont) },
            captionTypeface = host.guideTokens?.let { host.guideTypeface(it.captionFont) },
            rowRadiusPx = when (host.guideStyle) {
                GuideStyle.GLASS -> host.dp(14).toFloat()
                GuideStyle.EDITION -> host.dp(8).toFloat()
                else -> host.dp(3).toFloat()
            },
            rowStrokePx = host.dp(2),
        )
        guideList.adapter = host.iptvGuideController.iptvChannelAdapter
        guideList.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (!host.iptvGuideController.iptvZapPagingActive ||
                    !host.iptvGuideController.iptvGuideUsesZapWindow ||
                    host.iptvGuideController.iptvZapRequestInFlight
                ) return
                val layout = recyclerView.layoutManager as? LinearLayoutManager ?: return
                val last = layout.findLastVisibleItemPosition()
                val first = layout.findFirstVisibleItemPosition()
                val count = host.iptvGuideController.iptvChannelAdapter?.itemCount ?: return
                when {
                    dy >= 0 && last >= count - 12 -> host.iptvGuideController.pager.prefetchIptvZapPage(1, force = true)
                    dy < 0 && first in 0..11 -> host.iptvGuideController.pager.prefetchIptvZapPage(-1, force = true)
                }
            }
        })

        chrome.iptvEpgList?.layoutManager =
            LinearLayoutManager(activity, LinearLayoutManager.VERTICAL, false)
        chrome.iptvEpgAdapter = IptvEpgAdapter(
            emptyList(),
            onReplay = { program ->
                chrome.iptvEpgEntry?.let { entry -> host.iptvStartOverController.requestIptvCatchup(entry, program) }
            },
            onRecordFuture = { program ->
                chrome.iptvEpgEntry?.let { entry -> host.iptvRecordingActionsController.promptScheduleRecording(entry, program) }
            },
            tokens = host.guideTokens,
            style = host.guideStyle,
            monoTypeface = host.guideTokens?.let { host.guideTypeface(it.monoFont) },
            headlineTypeface = host.guideTokens?.let { host.guideTypeface(it.headlineFont) },
            rowRadiusPx = when (host.guideStyle) {
                GuideStyle.GLASS -> host.dp(14).toFloat()
                GuideStyle.EDITION -> host.dp(8).toFloat()
                else -> host.dp(3).toFloat()
            },
            rowStrokePx = host.dp(2),
        )
        chrome.iptvEpgList?.adapter = chrome.iptvEpgAdapter

        val premiumButtonIds = intArrayOf(
            R.id.iptv_nav_browse,
            R.id.iptv_nav_search,
            R.id.iptv_nav_favorites,
            R.id.iptv_nav_sources,
            R.id.iptv_nav_close,
            R.id.iptv_source_button,
            R.id.iptv_category_button,
            R.id.iptv_mode_live,
            R.id.iptv_epg_day_three_ago,
            R.id.iptv_epg_day_two_ago,
            R.id.iptv_epg_day_yesterday,
            R.id.iptv_epg_day_today,
            R.id.iptv_epg_day_tomorrow,
            R.id.iptv_epg_day_later,
        )
        premiumButtonIds.forEach { id ->
            activity.findViewById<AppCompatButton>(id)?.setTextColor(
                ContextCompat.getColorStateList(activity, R.color.iptv_premium_button_text)
            )
        }
        val sourceControlsVisibility =
            if (host.iptvSources.isEmpty()) View.GONE else View.VISIBLE
        activity.findViewById<View>(R.id.iptv_nav_favorites)?.visibility =
            sourceControlsVisibility
        activity.findViewById<View>(R.id.iptv_nav_sources)?.visibility =
            sourceControlsVisibility
        host.iptvGuideController.iptvSourceButton?.visibility = sourceControlsVisibility
        activity.findViewById<View>(R.id.iptv_nav_browse)?.isSelected = true

        // Submit-only search: typing does NOT filter. (A live filter only ever
        // reached the loaded <=1500 window, so it looked like search was missing
        // channels.) Instead show a hint so the user commits the query with the
        // OK / search key; the real search then runs over the WHOLE source.
        host.iptvGuideController.iptvGuideSearch?.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) {
                host.iptvGuideController.iptvGuideCountText?.text = if (s.isNullOrBlank()) {
                    host.iptvGuideController.iptvGuideItemCountLabel()
                } else {
                    "Press OK to search"
                }
            }
        })
        host.iptvGuideController.iptvGuideSearch?.setOnFocusChangeListener { _, focused ->
            if (focused) host.iptvGuideController.beginIptvAllCategorySearch()
        }
        // Submit-only catalog search: the paged browse of the current source
        // fires when the user commits the query with the search / enter key —
        // not on every keystroke,
        // which is what froze the player on six-figure catalogs.
        host.iptvGuideController.iptvGuideSearch?.setOnEditorActionListener { _, actionId, event ->
            val isSubmit = actionId == EditorInfo.IME_ACTION_SEARCH ||
                actionId == EditorInfo.IME_ACTION_DONE ||
                actionId == EditorInfo.IME_ACTION_GO ||
                (event?.keyCode == KeyEvent.KEYCODE_ENTER &&
                    event.action == KeyEvent.ACTION_UP)
            if (isSubmit) {
                host.iptvGuideController.requestIptvBrowse(
                    action = "browse",
                    query = host.iptvGuideController.iptvGuideSearch?.text?.toString()?.trim().orEmpty(),
                )
                true
            } else {
                false
            }
        }

        activity.findViewById<View>(R.id.iptv_nav_browse)?.setOnClickListener {
            if (host.iptvGuideController.restoreIptvCategoryAfterSearch()) {
                host.iptvGuideController.focusCurrentIptvGuideRow()
            } else {
                host.iptvGuideController.iptvGuideSearch?.setText("")
                host.iptvGuideController.requestIptvBrowse(action = "browse", query = "")
            }
        }
        activity.findViewById<View>(R.id.iptv_nav_search)?.setOnClickListener {
            host.iptvGuideController.beginIptvAllCategorySearch()
            host.iptvGuideController.iptvGuideSearch?.requestFocus()
        }
        activity.findViewById<View>(R.id.iptv_nav_favorites)?.setOnClickListener {
            val source = host.iptvSources.firstOrNull { it.isFavorites }
            if (source != null) host.iptvGuideController.selectIptvSource(source) else {
                Toast.makeText(activity, "No favorites source", Toast.LENGTH_SHORT).show()
            }
        }
        activity.findViewById<View>(R.id.iptv_nav_sources)?.setOnClickListener {
            showIptvSourcePicker()
        }
        activity.findViewById<View>(R.id.iptv_nav_close)?.setOnClickListener {
            host.iptvGuideController.hideIptvGuide()
        }
        host.iptvGuideController.iptvSourceButton?.setOnClickListener { showIptvSourcePicker() }
        host.iptvGuideController.iptvCategoryButton?.setOnClickListener { chrome.pickers.showIptvCategoryPicker() }
        activity.findViewById<View>(R.id.iptv_mode_live)?.setOnClickListener {
            host.iptvGuideController.selectIptvContentType("live")
        }
        activity.findViewById<View>(R.id.iptv_epg_day_three_ago)?.setOnClickListener {
            chrome.selectIptvEpgDay(-3)
        }
        activity.findViewById<View>(R.id.iptv_epg_day_two_ago)?.setOnClickListener {
            chrome.selectIptvEpgDay(-2)
        }
        activity.findViewById<View>(R.id.iptv_epg_day_yesterday)?.setOnClickListener {
            chrome.selectIptvEpgDay(-1)
        }
        activity.findViewById<View>(R.id.iptv_epg_day_today)?.setOnClickListener {
            chrome.selectIptvEpgDay(0)
        }
        activity.findViewById<View>(R.id.iptv_epg_day_tomorrow)?.setOnClickListener {
            chrome.selectIptvEpgDay(1)
        }
        activity.findViewById<View>(R.id.iptv_epg_day_later)?.setOnClickListener {
            chrome.selectIptvEpgDay(2)
        }

        host.iptvGuideController.refreshIptvBrowserChrome()
        chrome.updateIptvGuideCurrentName()
        // AFTER the premiumButtonIds loop above, so the legacy tinting can
        // never overwrite the styled pass.
        applyGuideStyle()
    }

    /**
     * The styled looks' one-shot re-tint of the guide overlay. Classic
     * returns immediately — the XML keeps every legacy value, and this runs
     * once from [setupIptvOverlay] (no per-frame or per-bind work).
     */
    fun applyGuideStyle() {
        val t = host.guideTokens ?: return
        val style = host.guideStyle
        val panelRadius = when (style) {
            GuideStyle.GLASS -> host.dp(18).toFloat()
            GuideStyle.EDITION -> host.dp(10).toFloat()
            else -> host.dp(4).toFloat()
        }
        val controlRadius = when (style) {
            GuideStyle.GLASS -> host.dp(12).toFloat()
            GuideStyle.EDITION -> host.dp(8).toFloat()
            else -> host.dp(3).toFloat()
        }
        val serif = host.guideTypeface(t.headlineFont)
        val serifItalic = host.guideTypeface(t.captionFont)
        val grotesk = host.guideTypeface(t.nameFont)
        val mono = host.guideTypeface(t.monoFont)
        val buttonColors = t.buttonTextColors()

        fun styleButton(id: Int) {
            activity.findViewById<AppCompatButton>(id)?.let { button ->
                button.background = t.buttonBackground(controlRadius)
                button.setTextColor(buttonColors)
                TextViewCompat.setCompoundDrawableTintList(button, buttonColors)
                if (style == GuideStyle.CONSOLE) {
                    button.typeface = mono ?: button.typeface
                }
            }
        }

        // Panels + rail.
        activity.findViewById<View>(R.id.iptv_guide_panel)?.background =
            t.panelDrawable(panelRadius, host.dp(1))
        activity.findViewById<View>(R.id.iptv_epg_panel)?.background =
            t.panelDrawable(panelRadius, host.dp(1))
        activity.findViewById<View>(R.id.iptv_guide_now_playing)?.background =
            t.panelDrawable(panelRadius, host.dp(1))
        activity.findViewById<View>(R.id.iptv_nav_rail)?.setBackgroundColor(t.bg)
        activity.findViewById<View>(R.id.iptv_rail_divider)?.setBackgroundColor(t.hairline)
        activity.findViewById<TextView>(R.id.iptv_nav_logo)?.let { d ->
            d.setBackgroundColor(t.fg)
            d.setTextColor(t.bg or 0xFF000000.toInt())
        }
        activity.findViewById<View>(R.id.iptv_mode_tabs)?.setBackgroundColor(t.bg)
        activity.findViewById<View>(R.id.iptv_epg_day_tabs)?.setBackgroundColor(t.bg)

        // Buttons — nav rail, source/category, mode, day tabs.
        intArrayOf(
            R.id.iptv_nav_browse,
            R.id.iptv_nav_search,
            R.id.iptv_nav_favorites,
            R.id.iptv_nav_sources,
            R.id.iptv_nav_close,
            R.id.iptv_source_button,
            R.id.iptv_category_button,
            R.id.iptv_mode_live,
            R.id.iptv_epg_day_three_ago,
            R.id.iptv_epg_day_two_ago,
            R.id.iptv_epg_day_yesterday,
            R.id.iptv_epg_day_today,
            R.id.iptv_epg_day_tomorrow,
            R.id.iptv_epg_day_later,
        ).forEach { styleButton(it) }

        // Kickers: the one place each style stamps its voice.
        val kickerColor = when (style) {
            GuideStyle.EDITION -> t.fgDim
            else -> t.accent
        }
        intArrayOf(R.id.iptv_guide_kicker, R.id.iptv_epg_kicker).forEach { id ->
            activity.findViewById<TextView>(id)?.let { kicker ->
                kicker.setTextColor(kickerColor)
                when (style) {
                    GuideStyle.EDITION -> kicker.typeface =
                        serifItalic?.let { Typeface.create(it, Typeface.ITALIC) }
                            ?: kicker.typeface
                    GuideStyle.CONSOLE -> kicker.typeface = mono ?: kicker.typeface
                    else -> {}
                }
            }
        }

        // Titles + secondary text.
        activity.findViewById<TextView>(R.id.iptv_guide_title)?.let { title ->
            title.setTextColor(t.fg)
            when (style) {
                GuideStyle.EDITION -> title.typeface = serif ?: title.typeface
                GuideStyle.CONSOLE -> title.typeface = grotesk ?: title.typeface
                else -> {}
            }
        }
        activity.findViewById<TextView>(R.id.iptv_epg_channel_name)?.let { name ->
            name.setTextColor(t.fg)
            when (style) {
                GuideStyle.EDITION -> name.typeface = serif ?: name.typeface
                GuideStyle.CONSOLE -> name.typeface = grotesk ?: name.typeface
                else -> {}
            }
        }
        activity.findViewById<TextView>(R.id.iptv_guide_count)?.setTextColor(t.fgFaint)
        activity.findViewById<TextView>(R.id.iptv_epg_channel_group)?.setTextColor(t.fgFaint)
        activity.findViewById<TextView>(R.id.iptv_epg_date)?.setTextColor(t.fgMid)
        activity.findViewById<TextView>(R.id.iptv_epg_empty)?.setTextColor(t.fgDim)
        intArrayOf(
            R.id.iptv_footer_play,
            R.id.iptv_footer_schedule,
            R.id.iptv_footer_favorite,
            R.id.iptv_epg_footer_channels,
            R.id.iptv_epg_footer_replay,
        ).forEach { activity.findViewById<TextView>(it)?.setTextColor(t.fgFaint) }

        // Search field.
        host.iptvGuideController.iptvGuideSearch?.let { search ->
            search.background = t.searchDrawable(controlRadius)
            search.setTextColor(t.fg)
            search.setHintTextColor(t.fgFaint)
            TextViewCompat.setCompoundDrawableTintList(
                search,
                android.content.res.ColorStateList.valueOf(t.fgFaint),
            )
            if (style == GuideStyle.CONSOLE) search.typeface = mono ?: search.typeface
        }

        // Spinners + logo tiles + the now-playing card texts.
        val accentTint = android.content.res.ColorStateList.valueOf(t.accent)
        activity.findViewById<ProgressBar>(R.id.iptv_browse_loading)?.indeterminateTintList =
            accentTint
        activity.findViewById<ProgressBar>(R.id.iptv_epg_loading)?.indeterminateTintList =
            accentTint
        val tileRadius = if (style == GuideStyle.EDITION) host.dp(24).toFloat() else controlRadius
        intArrayOf(R.id.iptv_epg_logo_tile, R.id.iptv_guide_now_logo_tile).forEach { id ->
            activity.findViewById<View>(id)?.background = t.tileDrawable(tileRadius, host.dp(1))
        }
        intArrayOf(R.id.iptv_epg_letter, R.id.iptv_guide_now_letter).forEach { id ->
            activity.findViewById<TextView>(id)?.setTextColor(t.fg)
        }
        activity.findViewById<TextView>(R.id.iptv_guide_current_epg)?.setTextColor(t.live)
        activity.findViewById<TextView>(R.id.iptv_guide_current_name)?.setTextColor(t.fg)
        activity.findViewById<TextView>(R.id.iptv_guide_current_group)?.setTextColor(t.fgFaint)
    }

    fun showIptvSourcePicker() {
        val liveSources = host.iptvSources.filterNot { it.isContinue }
        if (liveSources.isEmpty()) return
        val options = liveSources.map { it.name }
        AlertDialog.Builder(activity)
            .setTitle("Choose source")
            .setItems(options.toTypedArray()) { _, index ->
                host.iptvGuideController.selectIptvSource(liveSources[index])
            }
            .show()
    }

    fun showIptvChannelJumpDialog() {
        val current = host.iptvChannels.getOrNull(host.currentIptvIndex)
        if (current?.isLive != true) return
        val activeSource = host.iptvSources.firstOrNull { it.id == host.iptvGuideController.iptvZapSourceId }
        if (activeSource?.isFavorites == true || activeSource?.isList == true) {
            Toast.makeText(
                activity,
                "Select a provider before jumping by channel number",
                Toast.LENGTH_SHORT,
            ).show()
            return
        }
        val input = EditText(activity).apply {
            inputType = InputType.TYPE_CLASS_NUMBER
            hint = "Channel number"
            setSingleLine(true)
            imeOptions = EditorInfo.IME_ACTION_GO
            setPadding(host.dp(20), host.dp(14), host.dp(20), host.dp(14))
        }
        val dialog = AlertDialog.Builder(activity)
            .setTitle("Jump to channel")
            .setView(input)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Jump", null)
            .create()
        dialog.setOnShowListener {
            val submit = {
                val number = input.text?.toString()?.trim()?.toIntOrNull()
                if (number == null || number <= 0) {
                    input.error = "Enter a valid channel number"
                } else {
                    dialog.dismiss()
                    host.iptvGuideController.pager.requestIptvChannelJump(number)
                }
            }
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                submit()
            }
            input.setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_GO) {
                    submit()
                    true
                } else {
                    false
                }
            }
            input.requestFocus()
            dialog.window?.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE
            )
        }
        dialog.show()
    }
}
