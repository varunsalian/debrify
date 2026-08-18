package com.debrify.app.tv

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.KeyEvent
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Full-screen, DPAD-driven source picker. Grouping is presentation only: entries
 * retain their original source indexes and their incoming order. */
data class TvSourceBrowserEntry(
    val index: Int,
    val title: String,
    val source: String?,
    val quality: String,
    val size: String?,
    val seeders: Int,
    val direct: Boolean,
    val seasonPack: Boolean,
)

class TvSourceBrowserController(
    private val activity: Activity,
    private val root: View,
    private val rail: LinearLayout,
    private val railScroll: ScrollView,
    private val header: TextView,
    private val count: TextView,
    private val context: TextView,
    private val loadMore: TextView,
    private val results: LinearLayout,
    private val resultsScroll: ScrollView,
    private val callbacks: Callbacks,
) {
    interface Callbacks {
        fun entries(): List<TvSourceBrowserEntry>
        fun currentIndex(): Int
        fun isSeries(): Boolean
        fun loadMoreMode(): String?
        fun isLoading(mode: String): Boolean
        fun requestLoadMore(mode: String)
        fun onSourceSelected(index: Int)
        fun onHidden()
    }

    private data class Group(val id: String, val label: String, val entries: List<TvSourceBrowserEntry>)
    private enum class Zone { RAIL, RESULTS }

    private var groups: List<Group> = emptyList()
    private var selectedGroup = 0
    private var selectedResult = 0 // -1 is the load-more action.
    private var zone = Zone.RESULTS
    private var transientError: String? = null
    var isVisible = false
        private set

    init {
        root.isFocusable = true
        root.isFocusableInTouchMode = true
        loadMore.setOnClickListener {
            callbacks.loadMoreMode()?.let { callbacks.requestLoadMore(it) }
        }
    }

    fun show() {
        rebuild(landOnCurrent = true)
        isVisible = true
        root.visibility = View.VISIBLE
        root.alpha = 0f
        root.animate().alpha(1f).setDuration(160).start()
        root.requestFocus()
        render()
    }

    fun hide() {
        if (!isVisible) return
        isVisible = false
        root.animate().cancel()
        root.animate().alpha(0f).setDuration(120).withEndAction {
            if (!isVisible) root.visibility = View.GONE
        }.start()
        callbacks.onHidden()
    }

    fun render() {
        if (!isVisible) return
        val priorId = groups.getOrNull(selectedGroup)?.id
        val priorIndex = visible().getOrNull(selectedResult)?.index
        rebuild(selectedId = priorId, focusedIndex = priorIndex)
        renderRail()
        renderResults()
    }

    fun showError(message: String) {
        transientError = message
        render()
        root.postDelayed({
            if (transientError == message) {
                transientError = null
                render()
            }
        }, 3000)
    }

    fun dispatchKey(event: KeyEvent): Boolean {
        if (!isVisible) return false
        when (event.keyCode) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE,
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER -> Unit
            else -> return false
        }
        if (event.action != KeyEvent.ACTION_DOWN) return true
        when (event.keyCode) {
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> hide()
            KeyEvent.KEYCODE_DPAD_LEFT -> if (zone == Zone.RESULTS) { zone = Zone.RAIL; render() }
            KeyEvent.KEYCODE_DPAD_RIGHT -> if (zone == Zone.RAIL) { zone = Zone.RESULTS; render() }
            KeyEvent.KEYCODE_DPAD_UP -> move(-1)
            KeyEvent.KEYCODE_DPAD_DOWN -> move(1)
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> activate()
        }
        return true
    }

    private fun move(delta: Int) {
        if (zone == Zone.RAIL) {
            selectedGroup = (selectedGroup + delta).coerceIn(0, (groups.size - 1).coerceAtLeast(0))
            val current = visible().indexOfFirst { it.index == callbacks.currentIndex() }
            selectedResult = if (current >= 0) current else 0
            render()
        } else {
            val oldSelection = selectedResult
            val minimum = if (callbacks.loadMoreMode() == null) 0 else -1
            selectedResult = (selectedResult + delta).coerceIn(minimum, (visible().size - 1).coerceAtLeast(minimum))
            if (selectedResult != oldSelection) refreshResultSelection(oldSelection)
        }
    }

    private fun activate() {
        if (zone == Zone.RAIL) { zone = Zone.RESULTS; render(); return }
        if (selectedResult < 0) {
            callbacks.loadMoreMode()?.let { callbacks.requestLoadMore(it) }
        } else visible().getOrNull(selectedResult)?.let { callbacks.onSourceSelected(it.index) }
    }

    private fun rebuild(landOnCurrent: Boolean = false, selectedId: String? = null, focusedIndex: Int? = null) {
        val all = callbacks.entries()
        val lists = linkedMapOf<String, MutableList<TvSourceBrowserEntry>>()
        val labels = linkedMapOf<String, String>()
        all.forEach { entry ->
            val raw = entry.source?.trim().orEmpty()
            val id = if (raw.isEmpty()) "_other" else raw.lowercase()
            lists.getOrPut(id) { mutableListOf() }.add(entry)
            labels.putIfAbsent(id, sourceLabel(raw))
        }
        groups = buildList {
            add(Group("all", "All add-ons", all))
            lists.forEach { (id, entries) -> add(Group(id, labels[id] ?: "Other sources", entries)) }
        }
        selectedGroup = groups.indexOfFirst { it.id == selectedId }.let { if (it < 0) 0 else it }
        val target = focusedIndex ?: if (landOnCurrent) callbacks.currentIndex() else null
        selectedResult = target?.let { wanted -> visible().indexOfFirst { it.index == wanted } } ?: selectedResult
        val minimum = if (callbacks.loadMoreMode() == null) 0 else -1
        if (selectedResult < minimum && visible().isNotEmpty()) selectedResult = minimum
    }

    private fun visible(): List<TvSourceBrowserEntry> = groups.getOrNull(selectedGroup)?.entries ?: emptyList()

    private fun sourceLabel(raw: String): String {
        if (raw.isEmpty()) return "Other sources"
        val label = if (raw.startsWith("stremio:", ignoreCase = true)) raw.substring(8) else raw
        return label.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
    }

    private fun renderRail() {
        rail.removeAllViews()
        groups.forEachIndexed { i, group ->
            val active = zone == Zone.RAIL && i == selectedGroup
            val selected = i == selectedGroup
            rail.addView(row(group.label, "${group.entries.size}", active, selected) {
                selectedGroup = i
                selectedResult = visible().indexOfFirst { it.index == callbacks.currentIndex() }
                    .let { if (it < 0) 0 else it }
                render()
            })
        }
        railScroll.post {
            val child = rail.getChildAt(selectedGroup) ?: return@post
            railScroll.smoothScrollTo(0, (child.top - railScroll.height / 3).coerceAtLeast(0))
        }
    }

    private fun renderResults() {
        val entries = visible()
        header.text = (groups.getOrNull(selectedGroup)?.label ?: "All add-ons").uppercase()
        count.text = "${entries.size} source${if (entries.size == 1) "" else "s"}"
        context.text = transientError ?: contextLabel(entries)
        context.setTextColor(if (transientError == null) 0x8CFFFFFF.toInt() else 0xFFFF7A85.toInt())
        val mode = callbacks.loadMoreMode()
        loadMore.visibility = if (mode == null) View.GONE else View.VISIBLE
        if (mode != null) {
            loadMore.text = if (callbacks.isLoading(mode)) "Loading sources…" else loadLabel(mode)
            loadMore.background = bg(zone == Zone.RESULTS && selectedResult < 0, false)
            loadMore.setTextColor(if (zone == Zone.RESULTS && selectedResult < 0) Color.BLACK else 0xD9FFFFFF.toInt())
        }
        results.removeAllViews()
        entries.forEachIndexed { i, entry ->
            results.addView(sourceRow(entry, zone == Zone.RESULTS && i == selectedResult, entry.index == callbacks.currentIndex()) {
                selectedResult = i
                callbacks.onSourceSelected(entry.index)
            })
        }
        resultsScroll.post {
            val focusTop = if (selectedResult < 0) loadMore.top else results.getChildAt(selectedResult)?.top ?: 0
            resultsScroll.smoothScrollTo(0, (focusTop - resultsScroll.height / 3).coerceAtLeast(0))
        }
    }

    private fun refreshResultSelection(oldSelection: Int) {
        val mode = callbacks.loadMoreMode()
        if (mode != null) {
            val loadMoreActive = selectedResult < 0
            loadMore.background = bg(loadMoreActive, false)
            loadMore.setTextColor(if (loadMoreActive) Color.BLACK else 0xD9FFFFFF.toInt())
        }
        val entries = visible()
        listOf(oldSelection, selectedResult).distinct().forEach { index ->
            val entry = entries.getOrNull(index) ?: return@forEach
            val replacement = sourceRow(
                entry,
                index == selectedResult,
                entry.index == callbacks.currentIndex(),
            ) {
                selectedResult = index
                callbacks.onSourceSelected(entry.index)
            }
            results.removeViewAt(index)
            results.addView(replacement, index)
        }
        resultsScroll.post {
            val focusTop = if (selectedResult < 0) loadMore.top else results.getChildAt(selectedResult)?.top ?: 0
            resultsScroll.smoothScrollTo(0, (focusTop - resultsScroll.height / 3).coerceAtLeast(0))
        }
    }

    private fun contextLabel(entries: List<TvSourceBrowserEntry>): String {
        if (!callbacks.isSeries()) return "Sources returned for this title."
        val packs = entries.any { it.seasonPack }
        val episodes = entries.any { !it.direct && !it.seasonPack }
        return when {
            packs && episodes -> "Season packs and episode results loaded."
            packs -> "Season packs loaded. Episode results are fetched separately."
            episodes -> "Episode results loaded. Season packs are fetched separately."
            else -> "Sources returned for this title."
        }
    }

    private fun loadLabel(mode: String) = when (mode) {
        "episodes" -> "Load episode sources  ›"
        "packs" -> "Load season-pack sources  ›"
        else -> "Load more sources  ›"
    }

    private fun row(title: String, value: String, active: Boolean, selected: Boolean, click: () -> Unit): View = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = android.view.Gravity.CENTER_VERTICAL
        setPadding(dp(13), dp(11), dp(13), dp(11))
        background = bg(active, selected)
        setOnClickListener { click() }
        val name = TextView(activity).apply { text = title; setTextColor(if (active) Color.BLACK else 0xD9FFFFFF.toInt()); textSize = 14f; setTypeface(typeface, 1); maxLines = 1 }
        addView(name, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(activity).apply { text = value; setTextColor(if (active) 0x88000000.toInt() else 0x70FFFFFF.toInt()); textSize = 11f })
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(3) }
    }

    private fun sourceRow(entry: TvSourceBrowserEntry, active: Boolean, current: Boolean, click: () -> Unit): View = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = android.view.Gravity.CENTER_VERTICAL
        setPadding(dp(18), dp(11), dp(18), dp(11))
        background = bg(active, false)
        setOnClickListener { click() }
        addView(TextView(activity).apply { text = entry.title; maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END; setTextColor(if (active) Color.BLACK else 0xE6FFFFFF.toInt()); textSize = 14f; setTypeface(typeface, 1) }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val tags = listOfNotNull(entry.quality.takeIf { it.isNotBlank() }, entry.size, if (!entry.direct && entry.seeders > 0) "${entry.seeders} seeders" else null, if (entry.direct) "DIRECT" else null)
        tags.forEach { tag -> addView(tagView(tag, active)) }
        if (current) addView(TextView(activity).apply { text = "▮▮▮"; setTextColor(if (active) 0xFFAB2733.toInt() else 0xFFE23D4C.toInt()); textSize = 11f; setPadding(dp(14), 0, 0, 0) })
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(58)).apply { bottomMargin = dp(5) }
    }

    private fun tagView(tag: String, inverse: Boolean): TextView = TextView(activity).apply { text = tag; textSize = 10f; setTextColor(if (inverse) 0x99000000.toInt() else 0xAFFFFFFF.toInt()); setPadding(dp(6), dp(3), dp(6), dp(3)); background = GradientDrawable().apply { cornerRadius = dp(5).toFloat(); setColor(if (inverse) 0x12000000 else 0x12FFFFFF) }; layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(6) } }
    private fun bg(active: Boolean, selected: Boolean): GradientDrawable = GradientDrawable().apply { cornerRadius = dp(10).toFloat(); setColor(when { active -> Color.WHITE; selected -> 0x18FFFFFF; else -> 0x07FFFFFF }) }
    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
}
