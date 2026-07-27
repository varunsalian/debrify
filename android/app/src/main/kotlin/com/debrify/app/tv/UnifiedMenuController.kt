package com.debrify.app.tv

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Unified player menu — a DPAD-driven three-column ("Miller columns") overlay that
 * consolidates the player's scattered dialogs (audio, subtitles + per-addon tracks,
 * appearance, timing/sync, sources, display, playback) behind one cinema-themed
 * surface. NOTHING is delegated to the old panels — every column is inline.
 *
 * The controller is a generic renderer: the Activity owns all state and apply-logic
 * and hands back a [Model] (three lists of [Row]s with `onOk`/`onAdjust` lambdas) via
 * [Callbacks.buildModel]. Selection/focus is painted manually (no native view focus)
 * except the search field, which uses real focus + IME (see edit mode).
 *
 * Column 1 = section, column 2 = sub-control, column 3 = options/actions.
 * Layout: [com.debrify.app.R.layout.view_unified_menu].
 */
class UnifiedMenuController(
    private val activity: Activity,
    private val root: View,
    private val col1: LinearLayout,
    private val col2: LinearLayout,
    private val col3: LinearLayout,
    private val col2Header: TextView,
    private val col3Header: TextView,
    private val preview: TextView,
    private val callbacks: Callbacks,
    // Ordered section ids — must match the order of Model.col1. Defaulted to the
    // torrent player's five sections; the Torbox player passes its own subset
    // (it has no "sources" section). Only used by show(sectionId).
    private val sectionIds: List<String> =
        listOf("audio", "subs", "sources", "display", "playback")
) {

    /** One rendered row. Painted, not natively focusable (except the search field). */
    data class Row(
        val title: String,
        val value: String? = null,
        val selected: Boolean = false,       // shows the ● "current value" marker
        val accent: Boolean = false,         // red title (actions)
        val enabled: Boolean = true,         // false = non-focusable info row (Loading…)
        val swatch: Int? = null,             // colour chip (subtitle colours)
        val adjustable: Boolean = false,     // ◀▶ changes value via onAdjust instead of moving column
        val tag: String? = null,             // stable id so show(section, sub) can target a col2 row
        val onOk: (() -> Unit)? = null,
        val onAdjust: ((Int) -> Unit)? = null
    )

    /** SAM shims so Java callers (the Torbox player) can pass lambdas for row actions. */
    fun interface OkAction { fun run() }
    fun interface AdjustAction { fun onAdjust(direction: Int) }

    /**
     * Fluent [Row] builder for Java callers — Kotlin's named/default args and
     * trailing-lambda syntax aren't available from Java, so this keeps the Torbox
     * player's menu model readable. Kotlin callers can keep using [Row] directly.
     */
    class RowBuilder internal constructor(private val title: String) {
        private var value: String? = null
        private var selected = false
        private var accent = false
        private var enabled = true
        private var swatch: Int? = null
        private var adjustable = false
        private var tag: String? = null
        private var onOk: (() -> Unit)? = null
        private var onAdjust: ((Int) -> Unit)? = null

        fun value(v: String?): RowBuilder { this.value = v; return this }
        fun selected(b: Boolean): RowBuilder { this.selected = b; return this }
        fun accent(b: Boolean): RowBuilder { this.accent = b; return this }
        fun enabled(b: Boolean): RowBuilder { this.enabled = b; return this }
        fun swatch(color: Int): RowBuilder { this.swatch = color; return this }
        fun tag(t: String?): RowBuilder { this.tag = t; return this }
        fun onOk(action: OkAction): RowBuilder { this.onOk = { action.run() }; return this }
        fun onAdjust(action: AdjustAction): RowBuilder {
            this.adjustable = true
            this.onAdjust = { d -> action.onAdjust(d) }
            return this
        }

        fun build(): Row =
            Row(title, value, selected, accent, enabled, swatch, adjustable, tag, onOk, onAdjust)
    }

    companion object {
        /** Start a [RowBuilder]; call `.build()` to finish. Intended for Java callers. */
        @JvmStatic fun row(title: String): RowBuilder = RowBuilder(title)
    }

    enum class Col3Mode { ROWS, SEARCH }

    data class Model @JvmOverloads constructor(
        val col1: List<Row>,
        val col2Title: String,
        val col2: List<Row>,
        val col3Title: String,
        val col3: List<Row>,
        val col3Mode: Col3Mode = Col3Mode.ROWS,
        val previewVisible: Boolean = false
    )

    interface Callbacks {
        /** Build the full menu model for the current (section, sub-control) selection. */
        fun buildModel(sectionIndex: Int, col2Index: Int): Model
        /** Run the subtitle movie/show search for [query]; results arrive async and
         *  the Activity calls [render] when ready. */
        fun onSearchSubmit(query: String)
        /** Pre-fill text for the search field when it first appears. */
        fun searchInitialQuery(): String
        /** Style the live subtitle-appearance preview from current SubtitleSettings. */
        fun stylePreview(tv: TextView)
        fun onHidden()
    }

    private val sel = intArrayOf(0, 0, 0)   // section, col2, col3(+1 in SEARCH where 0=field)
    private var activeCol = 0
    private var model: Model = Model(emptyList(), "", emptyList(), "", emptyList())

    var isVisible: Boolean = false
        private set
    var inEditMode: Boolean = false
        private set

    // Persistent search field (real focus + IME). Added into col3 in SEARCH mode.
    private val searchField: EditText = EditText(activity).apply {
        setSingleLine(true)
        inputType = InputType.TYPE_CLASS_TEXT
        imeOptions = EditorInfo.IME_ACTION_SEARCH
        setTextColor(Color.WHITE)
        setHintTextColor(0x80FFFFFF.toInt())
        hint = "Movie or show title"
        textSize = 13f
        isFocusable = true
        isFocusableInTouchMode = true
        setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH || actionId == EditorInfo.IME_ACTION_DONE) {
                submitSearch(); true
            } else false
        }
    }

    // ── public API ──────────────────────────────────────────────────────────
    fun show(sectionId: String, sub: String? = null) {
        val s = sectionIds.indexOf(sectionId).coerceAtLeast(0)
        sel[0] = s; sel[1] = 0; sel[2] = 0
        model = callbacks.buildModel(sel[0], sel[1])
        if (sub != null) {
            val idx = model.col2.indexOfFirst { it.tag == sub }
            if (idx >= 0) { sel[1] = idx; model = callbacks.buildModel(sel[0], sel[1]) }
        }
        // Land on the leaf column for a fast change; on the current option where possible.
        activeCol = 2
        sel[2] = if (model.col3Mode == Col3Mode.SEARCH) 0
                 else model.col3.indexOfFirst { it.selected }.let { if (it < 0) 0 else it }
        inEditMode = false
        isVisible = true
        render()
        root.animate().cancel()
        root.visibility = View.VISIBLE
        root.alpha = 0f
        root.animate().alpha(1f).setDuration(160).start()
        maybeEnterSearchField()
    }

    fun hide() {
        if (!isVisible) return
        isVisible = false
        inEditMode = false
        root.animate().cancel()
        root.animate().alpha(0f).setDuration(120).withEndAction {
            if (!isVisible) root.visibility = View.GONE
        }.start()
        callbacks.onHidden()
    }

    /** Keys handled while a text field is focused: exit/navigate; everything else
     *  (typing, IME) falls through in the Activity. */
    fun handleEditModeKey(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return false
        return when (event.keyCode) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> { exitEditMode(); render(); true }
            KeyEvent.KEYCODE_DPAD_DOWN -> {
                exitEditMode()
                if (model.col3.isNotEmpty()) sel[2] = 1
                render(); true
            }
            else -> false
        }
    }

    fun dispatchKey(event: KeyEvent): Boolean {
        val handled = when (event.keyCode) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE,
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER -> true
            else -> false
        }
        if (!handled) return false
        if (event.action != KeyEvent.ACTION_DOWN) return true
        when (event.keyCode) {
            // Single-press dismiss, matching the dialogs this menu replaced.
            // Column-back is on LEFT; BACK always closes.
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> hide()
            KeyEvent.KEYCODE_DPAD_LEFT -> onLeft()
            KeyEvent.KEYCODE_DPAD_RIGHT -> onRight()
            KeyEvent.KEYCODE_DPAD_UP -> moveSel(-1)
            KeyEvent.KEYCODE_DPAD_DOWN -> moveSel(1)
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> activate()
        }
        return true
    }

    // ── navigation ──────────────────────────────────────────────────────────
    private fun searchMode(): Boolean = model.col3Mode == Col3Mode.SEARCH && activeCol == 2

    private fun col3Rows(): List<Row> = model.col3

    private fun currentCol3Row(): Row? {
        if (model.col3Mode == Col3Mode.SEARCH) {
            // slot 0 = field, slots 1.. = result rows
            return if (sel[2] == 0) null else col3Rows().getOrNull(sel[2] - 1)
        }
        return col3Rows().getOrNull(sel[2])
    }

    private fun onLeft() {
        if (activeCol == 2) {
            val row = currentCol3Row()
            if (row != null && row.adjustable) { row.onAdjust?.invoke(-1); render(); return }
        }
        if (activeCol > 0) { activeCol--; clampSel(); render() }
    }

    private fun onRight() {
        if (activeCol == 2) {
            val row = currentCol3Row()
            if (row != null && row.adjustable) { row.onAdjust?.invoke(1); render(); return }
            return
        }
        activeCol++; clampSel()
        if (activeCol == 2) landOnCol3()
        render()
        maybeEnterSearchField()
    }

    private fun landOnCol3() {
        sel[2] = if (model.col3Mode == Col3Mode.SEARCH) 0
                 else firstEnabled(col3Rows())
    }

    private fun colCount(col: Int): Int = when (col) {
        0 -> model.col1.size
        1 -> model.col2.size
        else -> if (model.col3Mode == Col3Mode.SEARCH) col3Rows().size + 1 else col3Rows().size
    }

    private fun rowEnabledAt(col: Int, index: Int): Boolean = when (col) {
        0 -> model.col1.getOrNull(index)?.enabled ?: true
        1 -> model.col2.getOrNull(index)?.enabled ?: true
        else -> if (model.col3Mode == Col3Mode.SEARCH) {
            if (index == 0) true else col3Rows().getOrNull(index - 1)?.enabled ?: true
        } else col3Rows().getOrNull(index)?.enabled ?: true
    }

    private fun firstEnabled(rows: List<Row>): Int {
        val i = rows.indexOfFirst { it.enabled }
        return if (i < 0) 0 else i
    }

    private fun moveSel(delta: Int) {
        val count = colCount(activeCol)
        if (count == 0) return
        var i = sel[activeCol]
        var found = -1
        do {
            i = (i + delta).coerceIn(0, count - 1)
            if (rowEnabledAt(activeCol, i)) { found = i; break }
            if (i == 0 || i == count - 1) break
        } while (true)
        if (found < 0) return   // settled on a disabled boundary row — stay put
        sel[activeCol] = found
        if (activeCol == 0) { sel[1] = 0; sel[2] = 0 }   // new section resets sub-selection
        if (activeCol == 1) sel[2] = 0
        rebuildModel()
        if (activeCol == 2) maybeEnterSearchField() else exitEditMode()
        render()
    }

    private fun activate() {
        when (activeCol) {
            0 -> { activeCol = 1; sel[1] = 0; sel[2] = 0; rebuildModel(); render() }
            1 -> { activeCol = 2; landOnCol3(); rebuildModel(); render(); maybeEnterSearchField() }
            else -> {
                if (model.col3Mode == Col3Mode.SEARCH && sel[2] == 0) { enterEditMode(); render(); return }
                val row = currentCol3Row() ?: return
                if (!row.enabled) return
                when {
                    row.onOk != null -> { row.onOk.invoke(); rebuildModel(); render() }
                    row.adjustable -> { row.onAdjust?.invoke(1); render() }
                }
            }
        }
    }

    private fun clampSel() {
        sel[0] = sel[0].coerceIn(0, (model.col1.size - 1).coerceAtLeast(0))
        rebuildModel()
        sel[1] = sel[1].coerceIn(0, (model.col2.size - 1).coerceAtLeast(0))
        val c3 = colCount(2)
        sel[2] = sel[2].coerceIn(0, (c3 - 1).coerceAtLeast(0))
    }

    private fun rebuildModel() {
        model = callbacks.buildModel(sel[0], sel[1])
    }

    // ── search field / edit mode ──────────────────────────────────────────────
    private fun maybeEnterSearchField() {
        if (searchMode() && sel[2] == 0) enterEditMode() else exitEditMode()
    }

    private fun enterEditMode() {
        if (inEditMode) return
        inEditMode = true
        searchField.post {
            searchField.requestFocus()
            searchField.setSelection(searchField.text?.length ?: 0)
        }
    }

    private fun exitEditMode() {
        if (!inEditMode) return
        inEditMode = false
        searchField.clearFocus()
    }

    private fun submitSearch() {
        val q = searchField.text?.toString()?.trim().orEmpty()
        if (q.isEmpty()) return
        exitEditMode()
        callbacks.onSearchSubmit(q)
        // Results arrive async → Activity calls render(); leave cursor on the field.
    }

    // ── rendering ───────────────────────────────────────────────────────────
    fun render() {
        if (!isVisible) return
        rebuildModel()
        clampSelSilent()
        if (model.previewVisible) { preview.visibility = View.VISIBLE; callbacks.stylePreview(preview) }
        else preview.visibility = View.GONE
        var scrollTarget: View? = null

        col1.removeAllViews()
        model.col1.forEachIndexed { i, r ->
            val active = activeCol == 0 && i == sel[0]
            val v = makeRow(r, sel = i == sel[0], active = active)
            col1.addView(v); if (active) scrollTarget = v
        }

        col2Header.text = model.col2Title
        col2.removeAllViews()
        model.col2.forEachIndexed { i, r ->
            val active = activeCol == 1 && i == sel[1]
            val v = makeRow(r, sel = i == sel[1], active = active)
            col2.addView(v); if (active) scrollTarget = v
        }

        col3Header.text = model.col3Title
        col3.removeAllViews()
        if (model.col3Mode == Col3Mode.SEARCH) {
            (searchField.parent as? ViewGroup)?.removeView(searchField)
            val fieldActive = activeCol == 2 && sel[2] == 0
            searchField.background = rowBg(active = fieldActive, sel = fieldActive)
            searchField.setPadding(dp(12), dp(10), dp(12), dp(10))
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(6) }
            searchField.layoutParams = lp
            if (searchField.text.isNullOrEmpty()) searchField.setText(callbacks.searchInitialQuery())
            col3.addView(searchField)
            // removeAllViews above detaches the field mid-typing (an async render can
            // fire while the user types); restore focus so the IME/keystrokes survive.
            if (inEditMode) searchField.post {
                searchField.requestFocus()
                searchField.setSelection(searchField.text?.length ?: 0)
            }
            if (fieldActive) scrollTarget = searchField
            model.col3.forEachIndexed { i, r ->
                val active = activeCol == 2 && sel[2] == i + 1
                val v = makeRow(r, sel = sel[2] == i + 1, active = active)
                col3.addView(v); if (active) scrollTarget = v
            }
        } else {
            model.col3.forEachIndexed { i, r ->
                val active = activeCol == 2 && i == sel[2]
                val v = makeRow(r, sel = i == sel[2], active = active)
                col3.addView(v); if (active) scrollTarget = v
            }
        }

        scrollTarget?.let { t ->
            ((t.parent as? View)?.parent as? ScrollView)?.let { sv ->
                sv.post { sv.smoothScrollTo(0, (t.top - sv.height / 3).coerceAtLeast(0)) }
            }
        }
    }

    // Clamp without triggering a rebuild loop inside render().
    private fun clampSelSilent() {
        sel[0] = sel[0].coerceIn(0, (model.col1.size - 1).coerceAtLeast(0))
        sel[1] = sel[1].coerceIn(0, (model.col2.size - 1).coerceAtLeast(0))
        sel[2] = sel[2].coerceIn(0, (colCount(2) - 1).coerceAtLeast(0))
    }

    private fun rowBg(active: Boolean, sel: Boolean): GradientDrawable = GradientDrawable().apply {
        cornerRadius = dp(9).toFloat()
        setColor(when { active -> 0x40E50914; sel -> 0x18FFFFFF; else -> 0x00000000 })
        if (active) setStroke(dp(1), 0x80E50914.toInt())
    }

    private fun makeRow(r: Row, sel: Boolean, active: Boolean): View {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(9), dp(12), dp(9))
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = dp(3) }
            layoutParams = lp
            background = rowBg(active, sel)
        }
        r.swatch?.let { c ->
            row.addView(TextView(activity).apply {
                text = "■"
                textSize = 13f
                setTextColor(c)
                setPadding(0, 0, dp(9), 0)
            })
        }
        row.addView(TextView(activity).apply {
            text = r.title
            textSize = 13f
            setTextColor(
                when {
                    !r.enabled -> 0x66FFFFFF.toInt()
                    r.accent -> 0xFFFF4D57.toInt()
                    active || sel -> Color.WHITE
                    else -> 0xC8FFFFFF.toInt()
                }
            )
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        })
        if (r.selected) {
            row.addView(TextView(activity).apply {
                text = "●"; textSize = 10f; setTextColor(0xFFFF4D57.toInt()); setPadding(dp(6), 0, dp(6), 0)
            })
        }
        r.value?.let { v ->
            row.addView(TextView(activity).apply {
                text = v; textSize = 12f
                setTextColor(if (r.accent) 0xFFFF4D57.toInt() else 0x8CFFFFFF.toInt())
            })
        }
        return row
    }

    private fun dp(v: Int): Int = (v * activity.resources.displayMetrics.density).toInt()
}
