package com.debrify.app.tv

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.NestedScrollView
import androidx.media3.ui.CaptionStyleCompat
import com.debrify.app.R
import com.debrify.app.util.SubtitleFontManager
import com.debrify.app.util.SubtitleSettings

/**
 * Two-pane subtitle settings controller used by both Android TV player activities.
 *
 * Layout responsibilities live in [R.layout.view_subtitle_settings_panel].
 * Activities provide track/search callbacks through [Callbacks] and delegate
 * key events while the panel is visible via [dispatchKey].
 */
class SubtitlePanelController(
    private val activity: Activity,
    private val root: View,
    private val categoriesContainer: LinearLayout,
    private val optionsContainer: LinearLayout,
    private val categoriesScroll: NestedScrollView,
    private val optionsScroll: NestedScrollView,
    private val previewText: TextView,
    private val identityLabel: TextView?,
    private val searchButton: View?,
    private val callbacks: Callbacks
) {

    interface Callbacks {
        /** All selectable subtitle tracks, including a leading "Off" entry. */
        fun getTrackLabels(): List<String>

        /** Index in [getTrackLabels] for the currently active track. */
        fun getCurrentTrackIndex(): Int

        /** Apply the track at the given index (from [getTrackLabels]). */
        fun selectTrack(index: Int)

        /** Trigger the online subtitle search flow. May be null on players that don't support it. */
        fun onSearchSubtitle()

        /** Title/identity string for the search row, e.g. "Detected: The Matrix (1999)". */
        fun getIdentityLabel(): String

        /** Apply the in-memory subtitle settings to the player's subtitle overlay. */
        fun onSettingsChanged()

        /** Panel was dismissed; activity should restore its prior focus. */
        fun onHidden()

        /** Whether the search row should be available (some players don't expose it). */
        fun supportsSearch(): Boolean = true
    }

    var isVisible: Boolean = false
        private set

    /** 0 = search row, 1 = categories pane, 2 = options pane. */
    private var pane: Int = PANE_CATEGORIES
    private var catIndex: Int = 0
    private var optIndex: Int = 0

    private val categoryRows = mutableListOf<View>()
    private val optionRows = mutableListOf<View>()

    private val categories: List<Category> by lazy { buildCategories() }

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    fun show() {
        val showSearch = callbacks.supportsSearch() && searchButton != null
        identityLabel?.text = callbacks.getIdentityLabel()
        // Toggle the whole search row (label + button) together
        val searchRow = (identityLabel?.parent as? View) ?: searchButton
        searchRow?.visibility = if (showSearch) View.VISIBLE else View.GONE

        renderCategories()
        catIndex = catIndex.coerceIn(0, (categories.size - 1).coerceAtLeast(0))
        pane = if (showSearch) PANE_SEARCH else PANE_CATEGORIES
        renderOptionsForSelectedCategory()
        applyHighlights()

        root.visibility = View.VISIBLE
        isVisible = true
    }

    fun hide() {
        root.visibility = View.GONE
        isVisible = false
        callbacks.onHidden()
    }

    /** Re-collect tracks / re-render lists (e.g. external subtitles finished loading). */
    fun refresh() {
        if (!isVisible) return
        identityLabel?.text = callbacks.getIdentityLabel()
        renderCategories()
        renderOptionsForSelectedCategory()
        applyHighlights()
    }

    /** Returns true if the key was consumed. */
    fun dispatchKey(event: KeyEvent): Boolean {
        if (!isVisible) return false
        if (event.action != KeyEvent.ACTION_DOWN) return true

        return when (event.keyCode) {
            KeyEvent.KEYCODE_BACK -> { hide(); true }
            KeyEvent.KEYCODE_DPAD_UP -> { onUp(); true }
            KeyEvent.KEYCODE_DPAD_DOWN -> { onDown(); true }
            KeyEvent.KEYCODE_DPAD_LEFT -> { onLeft(); true }
            KeyEvent.KEYCODE_DPAD_RIGHT -> { onRight(); true }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> { onSelect(); true }
            else -> true // swallow stray keys while panel is up
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Navigation
    // ─────────────────────────────────────────────────────────────────────────

    private fun onUp() {
        when (pane) {
            PANE_SEARCH -> { /* no-op */ }
            PANE_CATEGORIES -> {
                if (catIndex > 0) {
                    catIndex--
                    renderOptionsForSelectedCategory()
                } else if (callbacks.supportsSearch() && searchButton != null) {
                    pane = PANE_SEARCH
                }
            }
            PANE_OPTIONS -> {
                val cat = currentCategory() ?: return
                if (optIndex > 0) {
                    optIndex--
                    if (cat.applyOnArrow) {
                        cat.onSelect(optIndex)
                        afterOptionChanged()
                    }
                }
            }
        }
        applyHighlights()
    }

    private fun onDown() {
        when (pane) {
            PANE_SEARCH -> {
                pane = PANE_CATEGORIES
            }
            PANE_CATEGORIES -> {
                if (catIndex < categories.size - 1) {
                    catIndex++
                    renderOptionsForSelectedCategory()
                }
            }
            PANE_OPTIONS -> {
                val cat = currentCategory() ?: return
                if (optIndex < cat.getOptionCount() - 1) {
                    optIndex++
                    if (cat.applyOnArrow) {
                        cat.onSelect(optIndex)
                        afterOptionChanged()
                    }
                }
            }
        }
        applyHighlights()
    }

    private fun onLeft() {
        if (pane == PANE_OPTIONS) {
            pane = PANE_CATEGORIES
            applyHighlights()
        }
    }

    private fun onRight() {
        if (pane == PANE_SEARCH) {
            pane = PANE_CATEGORIES
            applyHighlights()
            return
        }
        if (pane == PANE_CATEGORIES) {
            val cat = currentCategory() ?: return
            if (cat.getOptionCount() > 0) {
                pane = PANE_OPTIONS
                optIndex = cat.getCurrentIndex().coerceIn(0, cat.getOptionCount() - 1)
                applyHighlights()
            }
        }
    }

    private fun onSelect() {
        when (pane) {
            PANE_SEARCH -> callbacks.onSearchSubtitle()
            PANE_CATEGORIES -> onRight()
            PANE_OPTIONS -> {
                val cat = currentCategory() ?: return
                cat.onSelect(optIndex)
                afterOptionChanged()
                if (cat.dismissOnSelect) {
                    // Reset to top so the next open starts fresh, not on Reset
                    catIndex = 0
                    hide()
                }
            }
        }
    }

    private fun afterOptionChanged() {
        callbacks.onSettingsChanged()
        updatePreview()
        // Refresh labels (current value on category row)
        renderCategories()
        applyHighlights()
    }

    private fun currentCategory(): Category? = categories.getOrNull(catIndex)

    // ─────────────────────────────────────────────────────────────────────────
    // Rendering
    // ─────────────────────────────────────────────────────────────────────────

    private fun renderCategories() {
        categoriesContainer.removeAllViews()
        categoryRows.clear()
        categories.forEachIndexed { i, cat ->
            val row = inflateCategoryRow(cat.name, cat.getCurrentLabel())
            categoriesContainer.addView(row)
            categoryRows.add(row)
            row.setOnClickListener {
                pane = PANE_CATEGORIES
                if (catIndex != i) {
                    catIndex = i
                    renderOptionsForSelectedCategory()
                }
                onRight()
            }
        }
    }

    private fun renderOptionsForSelectedCategory() {
        optionsContainer.removeAllViews()
        optionRows.clear()
        val cat = currentCategory() ?: return
        optIndex = cat.getCurrentIndex().coerceIn(0, (cat.getOptionCount() - 1).coerceAtLeast(0))
        for (i in 0 until cat.getOptionCount()) {
            val row = inflateOptionRow(cat.getOptionLabel(i), cat.getOptionSwatch(i))
            optionsContainer.addView(row)
            optionRows.add(row)
            row.setOnClickListener {
                pane = PANE_OPTIONS
                optIndex = i
                cat.onSelect(i)
                afterOptionChanged()
                if (cat.dismissOnSelect) {
                    catIndex = 0
                    hide()
                }
            }
        }
        // Scroll to current
        optionsScroll.post {
            optionRows.getOrNull(optIndex)?.let { row ->
                optionsScroll.smoothScrollTo(0, (row.top - 16).coerceAtLeast(0))
            }
        }
    }

    private fun inflateCategoryRow(label: String, valueLabel: String): View {
        val row = LinearLayout(activity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).also {
                it.setMargins(dp(6), dp(2), dp(6), dp(2))
            }
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
            isClickable = true
            isFocusable = true
        }
        val title = TextView(activity).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }
        val value = TextView(activity).apply {
            text = valueLabel
            setTextColor(0xB3FFFFFF.toInt())
            textSize = 11f
            setSingleLine(true)
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        row.addView(title)
        row.addView(value)
        return row
    }

    private fun inflateOptionRow(label: String, swatch: Int?): View {
        val row = LinearLayout(activity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).also {
                it.setMargins(dp(6), dp(2), dp(6), dp(2))
            }
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            isClickable = true
            isFocusable = true
        }
        if (swatch != null) {
            val s = View(activity).apply {
                layoutParams = LinearLayout.LayoutParams(dp(14), dp(14)).also {
                    it.marginEnd = dp(10)
                }
                background = activity.resources.getDrawable(R.drawable.subtitle_color_swatch, activity.theme)
                backgroundTintList = ColorStateList.valueOf(swatch)
            }
            row.addView(s)
        }
        val text = TextView(activity).apply {
            this.text = label
            setTextColor(Color.WHITE)
            textSize = 13f
            setSingleLine(true)
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        row.addView(text)
        return row
    }

    private fun applyHighlights() {
        // Search button highlight (use non-stateful drawables so Android focus doesn't
        // override our pane-state-driven visuals)
        searchButton?.background = if (pane == PANE_SEARCH) {
            activity.resources.getDrawable(R.drawable.subtitle_row_focused, activity.theme)
        } else {
            activity.resources.getDrawable(R.drawable.subtitle_row_idle, activity.theme)
        }

        // Categories
        categoryRows.forEachIndexed { i, row ->
            row.background = when {
                pane == PANE_CATEGORIES && i == catIndex ->
                    activity.resources.getDrawable(R.drawable.subtitle_row_focused, activity.theme)
                i == catIndex ->
                    activity.resources.getDrawable(R.drawable.subtitle_row_selected, activity.theme)
                else -> null
            }
        }

        // Options
        optionRows.forEachIndexed { i, row ->
            row.background = when {
                pane == PANE_OPTIONS && i == optIndex ->
                    activity.resources.getDrawable(R.drawable.subtitle_row_focused, activity.theme)
                i == optIndex ->
                    activity.resources.getDrawable(R.drawable.subtitle_row_selected, activity.theme)
                else -> null
            }
        }

        // Scroll category into view if needed
        categoriesScroll.post {
            categoryRows.getOrNull(catIndex)?.let { row ->
                val rowTop = row.top
                val rowBottom = row.bottom
                val scrollY = categoriesScroll.scrollY
                val viewportH = categoriesScroll.height
                if (rowTop < scrollY) {
                    categoriesScroll.smoothScrollTo(0, (rowTop - 8).coerceAtLeast(0))
                } else if (rowBottom > scrollY + viewportH) {
                    categoriesScroll.smoothScrollTo(0, rowBottom - viewportH + 8)
                }
            }
        }
        if (pane == PANE_OPTIONS) {
            optionsScroll.post {
                optionRows.getOrNull(optIndex)?.let { row ->
                    val rowTop = row.top
                    val rowBottom = row.bottom
                    val scrollY = optionsScroll.scrollY
                    val viewportH = optionsScroll.height
                    if (rowTop < scrollY) {
                        optionsScroll.smoothScrollTo(0, (rowTop - 8).coerceAtLeast(0))
                    } else if (rowBottom > scrollY + viewportH) {
                        optionsScroll.smoothScrollTo(0, rowBottom - viewportH + 8)
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Preview
    // ─────────────────────────────────────────────────────────────────────────

    private fun updatePreview() {
        val color = SubtitleSettings.getCurrentColor(activity)
        val style = SubtitleSettings.getCurrentStyle(activity)
        val size = SubtitleSettings.getCurrentSize(activity)
        val bg = SubtitleSettings.getCurrentBg(activity)
        val outline = SubtitleSettings.getCurrentOutlineColor(activity)
        val typeface = SubtitleFontManager.getTypeface(activity)

        val edgeColor = if (outline.isAuto || outline.color == null) Color.BLACK else outline.color!!

        previewText.setTextColor(color.color)
        previewText.textSize = size.sizeSp
        previewText.typeface = typeface
        when (style.edgeType) {
            CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW -> previewText.setShadowLayer(4f, 2f, 2f, edgeColor)
            CaptionStyleCompat.EDGE_TYPE_OUTLINE -> previewText.setShadowLayer(2f, 1f, 1f, edgeColor)
            else -> previewText.setShadowLayer(0f, 0f, 0f, Color.TRANSPARENT)
        }
        if (bg.color != Color.TRANSPARENT) {
            previewText.setBackgroundColor(bg.color)
            previewText.setPadding(dp(8), dp(4), dp(8), dp(4))
        } else {
            previewText.setBackgroundColor(Color.TRANSPARENT)
            previewText.setPadding(0, 0, 0, 0)
        }
    }

    private fun dp(v: Int): Int = (v * activity.resources.displayMetrics.density).toInt()

    // ─────────────────────────────────────────────────────────────────────────
    // Categories
    // ─────────────────────────────────────────────────────────────────────────

    private interface Category {
        val name: String
        val dismissOnSelect: Boolean get() = false

        /**
         * If true, [onSelect] fires as the user arrows over options (live preview).
         * If false, options highlight on arrow but [onSelect] only fires on OK.
         * Use false for expensive operations like switching the active subtitle track.
         */
        val applyOnArrow: Boolean get() = true

        fun getCurrentLabel(): String
        fun getOptionCount(): Int
        fun getOptionLabel(i: Int): String
        fun getOptionSwatch(i: Int): Int? = null
        fun getCurrentIndex(): Int
        fun onSelect(i: Int)
    }

    private fun buildCategories(): List<Category> = listOf(
        object : Category {
            override val name = "Track"
            override val applyOnArrow = false  // Switching tracks rebuilds the media item; only apply on OK
            override fun getCurrentLabel(): String {
                val labels = callbacks.getTrackLabels()
                val idx = callbacks.getCurrentTrackIndex()
                return labels.getOrNull(idx) ?: "Off"
            }
            override fun getOptionCount(): Int = callbacks.getTrackLabels().size
            override fun getOptionLabel(i: Int): String = callbacks.getTrackLabels()[i]
            override fun getCurrentIndex(): Int = callbacks.getCurrentTrackIndex()
            override fun onSelect(i: Int) { callbacks.selectTrack(i) }
        },
        object : Category {
            override val name = "Size"
            override fun getCurrentLabel() = SubtitleSettings.getCurrentSize(activity).label
            override fun getOptionCount() = SubtitleSettings.SIZE_OPTIONS.size
            override fun getOptionLabel(i: Int) = SubtitleSettings.SIZE_OPTIONS[i].label
            override fun getCurrentIndex() = SubtitleSettings.getSizeIndex(activity)
            override fun onSelect(i: Int) { SubtitleSettings.setSizeIndex(activity, i) }
        },
        object : Category {
            override val name = "Style"
            override fun getCurrentLabel() = SubtitleSettings.getCurrentStyle(activity).label
            override fun getOptionCount() = SubtitleSettings.STYLE_OPTIONS.size
            override fun getOptionLabel(i: Int) = SubtitleSettings.STYLE_OPTIONS[i].label
            override fun getCurrentIndex() = SubtitleSettings.getStyleIndex(activity)
            override fun onSelect(i: Int) { SubtitleSettings.setStyleIndex(activity, i) }
        },
        object : Category {
            override val name = "Color"
            override fun getCurrentLabel() = SubtitleSettings.getCurrentColor(activity).label
            override fun getOptionCount() = SubtitleSettings.COLOR_OPTIONS.size
            override fun getOptionLabel(i: Int) = SubtitleSettings.COLOR_OPTIONS[i].label
            override fun getOptionSwatch(i: Int) = SubtitleSettings.COLOR_OPTIONS[i].color
            override fun getCurrentIndex() = SubtitleSettings.getColorIndex(activity)
            override fun onSelect(i: Int) { SubtitleSettings.setColorIndex(activity, i) }
        },
        object : Category {
            override val name = "Outline"
            override fun getCurrentLabel() = SubtitleSettings.getCurrentOutlineColor(activity).label
            override fun getOptionCount() = SubtitleSettings.OUTLINE_COLOR_OPTIONS.size
            override fun getOptionLabel(i: Int) = SubtitleSettings.OUTLINE_COLOR_OPTIONS[i].label
            override fun getOptionSwatch(i: Int): Int? = SubtitleSettings.OUTLINE_COLOR_OPTIONS[i].color
            override fun getCurrentIndex() = SubtitleSettings.getOutlineColorIndex(activity)
            override fun onSelect(i: Int) { SubtitleSettings.setOutlineColorIndex(activity, i) }
        },
        object : Category {
            override val name = "Background"
            override fun getCurrentLabel() = SubtitleSettings.getCurrentBg(activity).label
            override fun getOptionCount() = SubtitleSettings.BG_OPTIONS.size
            override fun getOptionLabel(i: Int) = SubtitleSettings.BG_OPTIONS[i].label
            override fun getCurrentIndex() = SubtitleSettings.getBgIndex(activity)
            override fun onSelect(i: Int) { SubtitleSettings.setBgIndex(activity, i) }
        },
        object : Category {
            override val name = "Position"
            override fun getCurrentLabel() = SubtitleSettings.getCurrentElevation(activity).label
            override fun getOptionCount() = SubtitleSettings.ELEVATION_OPTIONS.size
            override fun getOptionLabel(i: Int) = SubtitleSettings.ELEVATION_OPTIONS[i].label
            override fun getCurrentIndex() = SubtitleSettings.getElevationIndex(activity)
            override fun onSelect(i: Int) { SubtitleSettings.setElevationIndex(activity, i) }
        },
        object : Category {
            override val name = "Font"
            override fun getCurrentLabel() = SubtitleFontManager.getCurrentFontLabel(activity)
            override fun getOptionCount() = SubtitleFontManager.FONT_OPTIONS.size
            override fun getOptionLabel(i: Int) = SubtitleFontManager.FONT_OPTIONS[i].label
            override fun getCurrentIndex() = SubtitleFontManager.getFontIndex(activity)
            override fun onSelect(i: Int) { SubtitleFontManager.setFontIndex(activity, i) }
        },
        object : Category {
            override val name = "Reset"
            override val dismissOnSelect = true
            override fun getCurrentLabel() =
                if (SubtitleSettings.isDefault(activity)) "All defaults" else "Customized"
            override fun getOptionCount() = 1
            override fun getOptionLabel(i: Int) = "Reset all to defaults"
            override fun getCurrentIndex() = 0
            override fun onSelect(i: Int) {
                SubtitleSettings.resetToDefaults(activity)
                SubtitleFontManager.resetToDefault(activity)
            }
        }
    )

    companion object {
        private const val PANE_SEARCH = 0
        private const val PANE_CATEGORIES = 1
        private const val PANE_OPTIONS = 2
    }
}
