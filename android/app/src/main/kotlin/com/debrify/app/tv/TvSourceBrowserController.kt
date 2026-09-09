package com.debrify.app.tv

import android.app.Activity
import android.animation.ValueAnimator
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
    val badgeName: String = title,
    val badgeDescription: String? = null,
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
        fun requestBadges(entry: TvSourceBrowserEntry, complete: (TvSourceBadgeResult?) -> Unit) { complete(TvSourceBadgeResult(false, emptyList())) }

        /** Applicable addons with no entries yet, as (groupId, label) — shown
         * as zero-count rail groups so a silent addon stays visible. */
        fun placeholderGroups(): List<Pair<String, String>> = emptyList()

        /** Per-addon fetch state for an EMPTY group: null = no fetch for this
         * group, else "idle" / "fetching" / "failed" / "fetched" (fetched but
         * still empty = retryable). */
        fun groupFetchState(groupId: String): String? = null

        /** True while the lazy season-pack probe for this group runs. */
        fun isGroupProbing(groupId: String): Boolean = false

        fun requestGroupFetch(groupId: String) {}
    }

    private data class Group(val id: String, val label: String, val entries: List<TvSourceBrowserEntry>)
    private enum class Zone { RAIL, RESULTS }

    private var groups: List<Group> = emptyList()
    private var selectedGroup = 0
    private var selectedResult = 0
    private var zone = Zone.RESULTS
    private var transientError: String? = null
    var isVisible = false
        private set

    private val badgeCache = object : LinkedHashMap<String, List<Map<*, *>>>(64, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<Map<*, *>>>?): Boolean = size > 400
    }
    private val pendingBadges = mutableMapOf<String, Any>()
    private val badgeTimeouts = mutableSetOf<Runnable>()
    private var sourceScrollAnimator: ValueAnimator? = null
    private var badgeGeneration = 0
    private var destroyed = false
    private var sourceScrollStart = 0f
    private var sourceScrollTarget = 0f
    private val unresolvedBadges = linkedSetOf<String>()
    private var badgeRetryScheduled = false
    private var badgeRetryDelayMs = 1000L
    private val badgeRetry = Runnable {
        badgeRetryScheduled = false
        badgeRetryDelayMs = (badgeRetryDelayMs * 2).coerceAtMost(10_000L)
        unresolvedBadges.clear()
        requestVisibleBadges()
    }
    private var badgeScanScheduled = false
    private val badgeScan = Runnable {
        badgeScanScheduled = false
        scanVisibleBadges()
    }
    private val badgeLayoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> requestVisibleBadges() }
    private val badgeScrollListener = android.view.ViewTreeObserver.OnScrollChangedListener { requestVisibleBadges() }
    private var customBadgesConfigured = false
    private data class BadgeSlot(
        val entry: TvSourceBrowserEntry,
        val title: TextView,
        val view: TvStreamBadgeStrip,
        val builtIn: TvStreamBadgeStrip,
        val current: Boolean,
        var active: Boolean,
    ) {
        fun showBuiltIn(configured: Boolean) {
            fun badge(label: String): Map<String, Any> = mapOf(
                "label" to label,
                "textColor" to if (current && label == "▮▮▮") {
                    if (active) 0xFFAB2733.toInt() else 0xFFE23D4C.toInt()
                } else if (active) Color.BLACK else 0xCCFFFFFF.toInt(),
                "fillColor" to if (active) 0x0F000000 else 0x14FFFFFF,
            )
            builtIn.show(buildList {
                if (!configured && entry.quality.isNotBlank()) add(badge(entry.quality))
                entry.size?.let { add(badge(it)) }
                if (!entry.direct && entry.seeders > 0) add(badge("${entry.seeders} seeders"))
                if (entry.direct) add(badge("DIRECT"))
                if (current) add(badge("▮▮▮"))
            })
        }
    }
    private fun updateBadgeMode(configured: Boolean) {
        if (customBadgesConfigured == configured) return
        customBadgesConfigured = configured
        for (i in 0 until results.childCount) {
            (results.getChildAt(i).tag as? BadgeSlot)?.showBuiltIn(configured)
        }
    }
    private fun badgeKey(entry: TvSourceBrowserEntry) = "${entry.badgeName}\u0000${entry.badgeDescription.orEmpty()}"

    private fun clearBadgeRequests() {
        badgeTimeouts.forEach { root.removeCallbacks(it) }
        badgeTimeouts.clear()
        pendingBadges.clear()
        unresolvedBadges.clear()
        root.removeCallbacks(badgeRetry)
        root.removeCallbacks(badgeScan)
        badgeRetryScheduled = false
        badgeRetryDelayMs = 1000L
        badgeScanScheduled = false
    }

    fun destroy() {
        destroyed = true
        isVisible = false
        badgeGeneration++
        clearBadgeRequests()
        sourceScrollAnimator?.cancel()
        sourceScrollAnimator = null
        root.animate().cancel()
        results.removeOnLayoutChangeListener(badgeLayoutListener)
        if (resultsScroll.viewTreeObserver.isAlive) {
            resultsScroll.viewTreeObserver.removeOnScrollChangedListener(badgeScrollListener)
        }
    }

    private fun retryBadge(key: String) {
        unresolvedBadges.add(key)
        if (unresolvedBadges.size > 400) unresolvedBadges.remove(unresolvedBadges.first())
        if (!badgeRetryScheduled && isVisible) {
            badgeRetryScheduled = true
            root.postDelayed(badgeRetry, badgeRetryDelayMs)
        }
    }

    private fun animateSourceFocus() {
        if (!isVisible) return
        val focusTop = results.getChildAt(selectedResult)?.top ?: return
        val target = (focusTop - resultsScroll.height / 3).coerceAtLeast(0)
        sourceScrollAnimator?.cancel()
        sourceScrollStart = resultsScroll.scrollY.toFloat()
        sourceScrollTarget = target.toFloat()
        sourceScrollAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 250
            addUpdateListener {
                val fraction = it.animatedValue as Float
                resultsScroll.scrollTo(0, (sourceScrollStart + (sourceScrollTarget - sourceScrollStart) * fraction).toInt())
            }
            start()
        }
    }

    private fun preserveBadgeAnchor(row: View, top: Int, oldTop: Int, oldHeight: Int) {
        if (!isVisible || zone != Zone.RESULTS || oldHeight <= 0 || top == oldTop ||
            results.getChildAt(selectedResult) !== row) return
        if (sourceScrollAnimator?.isRunning != true &&
            (oldTop + oldHeight <= resultsScroll.scrollY ||
            oldTop >= resultsScroll.scrollY + resultsScroll.height)) return
        val correction = top - oldTop
        // Correct before this layout is drawn. Scans are posted separately so
        // scrolling here cannot mutate badge children during layout.
        resultsScroll.scrollTo(0, resultsScroll.scrollY + correction)
        if (sourceScrollAnimator?.isRunning == true) {
            val fraction = sourceScrollAnimator?.animatedValue as? Float ?: 0f
            sourceScrollTarget = (top - resultsScroll.height / 3).coerceAtLeast(0).toFloat()
            if (fraction < 1f) {
                sourceScrollStart = (resultsScroll.scrollY - fraction * sourceScrollTarget) / (1f - fraction)
            }
        }
    }

    private fun requestVisibleBadges() {
        if (!isVisible || destroyed || badgeScanScheduled) return
        badgeScanScheduled = true
        root.post(badgeScan)
    }

    private fun scanVisibleBadges() {
        if (!isVisible || destroyed || !results.isLaidOut || results.isLayoutRequested) return
        val top = resultsScroll.scrollY
        val bottom = top + resultsScroll.height
        for (i in 0 until results.childCount) {
            val row = results.getChildAt(i)
            if (row.top > bottom) break
            if (row.bottom < top) continue
            val slot = row.tag as? BadgeSlot ?: continue
            val key = badgeKey(slot.entry)
            val cached = badgeCache[key]
            if (cached != null) { slot.view.show(cached); continue }
            if (key in unresolvedBadges) continue
            if (pendingBadges.size >= 16 || pendingBadges.containsKey(key)) continue
            val admission = Any()
            pendingBadges[key] = admission
            val generation = badgeGeneration
            // A dead Flutter channel must not leave a permanent pending row.
            lateinit var timeout: Runnable
            timeout = Runnable {
                badgeTimeouts.remove(timeout)
                if (generation == badgeGeneration && pendingBadges[key] === admission) {
                    pendingBadges.remove(key)
                    retryBadge(key)
                    requestVisibleBadges()
                }
            }
            badgeTimeouts.add(timeout)
            // Covers startup, preparation, cold execution and the bounded
            // shared worker queue. Hidden pickers cancel this fallback.
            root.postDelayed(timeout, 45_000)
            callbacks.requestBadges(slot.entry) { reply ->
                root.removeCallbacks(timeout)
                badgeTimeouts.remove(timeout)
                if (generation == badgeGeneration && pendingBadges[key] === admission) {
                    pendingBadges.remove(key)
                    if (reply != null) updateBadgeMode(reply.configured)
                    val badges = reply?.badges
                    if (badges == null) {
                        retryBadge(key)
                    } else {
                        badgeRetryDelayMs = 1000L
                        badgeCache[key] = badges
                    }
                    requestVisibleBadges()
                }
            }
        }
    }

    init {
        root.isFocusable = true
        root.isFocusableInTouchMode = true
        loadMore.visibility = View.GONE
        results.addOnLayoutChangeListener(badgeLayoutListener)
        resultsScroll.viewTreeObserver.addOnScrollChangedListener(badgeScrollListener)
    }

    fun show() {
        if (destroyed) return
        badgeGeneration++
        badgeCache.clear()
        clearBadgeRequests()
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
        badgeGeneration++
        clearBadgeRequests()
        sourceScrollAnimator?.cancel()
        sourceScrollAnimator = null
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
            KeyEvent.KEYCODE_DPAD_LEFT -> if (zone == Zone.RESULTS) changeZone(Zone.RAIL)
            KeyEvent.KEYCODE_DPAD_RIGHT -> if (zone == Zone.RAIL) changeZone(Zone.RESULTS)
            KeyEvent.KEYCODE_DPAD_UP -> move(-1)
            KeyEvent.KEYCODE_DPAD_DOWN -> move(1)
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> activate()
        }
        return true
    }

    private fun changeZone(next: Zone) {
        zone = next
        renderRail()
        if (visible().isEmpty()) renderResults() else refreshResultSelection(selectedResult)
    }

    private fun move(delta: Int) {
        if (zone == Zone.RAIL) {
            selectedGroup = (selectedGroup + delta).coerceIn(0, (groups.size - 1).coerceAtLeast(0))
            val current = visible().indexOfFirst { it.index == callbacks.currentIndex() }
            selectedResult = if (current >= 0) current else 0
            render()
        } else {
            val oldSelection = selectedResult
            selectedResult = (selectedResult + delta).coerceIn(0, (visible().size - 1).coerceAtLeast(0))
            if (selectedResult != oldSelection) refreshResultSelection(oldSelection)
        }
    }

    private fun activate() {
        if (zone == Zone.RAIL) { changeZone(Zone.RESULTS); return }
        val entry = visible().getOrNull(selectedResult)
        if (entry != null) {
            callbacks.onSourceSelected(entry.index)
            return
        }
        // Empty addon group: the sole row is "Fetch results".
        val groupId = groups.getOrNull(selectedGroup)?.id ?: return
        val state = callbacks.groupFetchState(groupId) ?: return
        if (state != "fetching") callbacks.requestGroupFetch(groupId)
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
            add(Group("all", "All sources", all))
            lists.forEach { (id, entries) -> add(Group(id, labels[id] ?: "Other sources", entries)) }
            // Applicable addons with nothing yet — same group id their fetched
            // rows will use, so the placeholder becomes the real group.
            callbacks.placeholderGroups().forEach { (id, label) ->
                if (!lists.containsKey(id)) add(Group(id, label, emptyList()))
            }
        }
        selectedGroup = groups.indexOfFirst { it.id == selectedId }.let { if (it < 0) 0 else it }
        val target = focusedIndex ?: if (landOnCurrent) callbacks.currentIndex() else null
        selectedResult = target?.let { wanted -> visible().indexOfFirst { it.index == wanted } } ?: selectedResult
        if (selectedResult < 0 && visible().isNotEmpty()) selectedResult = 0
    }

    private fun visible(): List<TvSourceBrowserEntry> = groups.getOrNull(selectedGroup)?.entries ?: emptyList()

    private fun sourceLabel(raw: String): String {
        if (raw.isEmpty()) return "Other sources"
        // The title-level binding (Dart stamps 'pinned' on bound plays).
        if (raw.equals("pinned", ignoreCase = true)) return "Pinned source"
        val label = if (raw.startsWith("stremio:", ignoreCase = true)) raw.substring(8) else raw
        return label.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
    }

    private fun renderRail() {
        rail.removeAllViews()
        groups.forEachIndexed { i, group ->
            val active = zone == Zone.RAIL && i == selectedGroup
            val selected = i == selectedGroup
            val failed = group.entries.isEmpty() &&
                callbacks.groupFetchState(group.id) == "failed"
            rail.addView(row(group.label, if (failed) "!" else "${group.entries.size}", active, selected) {
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
        val groupId = groups.getOrNull(selectedGroup)?.id
        header.text = (groups.getOrNull(selectedGroup)?.label ?: "All sources").uppercase()
        count.text = "${entries.size} source${if (entries.size == 1) "" else "s"}"
        val probing = groupId != null && callbacks.isGroupProbing(groupId)
        context.text = transientError
            ?: if (probing) "Looking for season packs from this add-on…" else contextLabel(entries)
        context.setTextColor(if (transientError == null) 0x8CFFFFFF.toInt() else 0xFFFF7A85.toInt())
        loadMore.visibility = View.GONE
        results.removeAllViews()
        // Empty addon group: one "Fetch results" row (also the retry after a
        // failure or an empty fetch).
        val fetchState = if (entries.isEmpty() && groupId != null) {
            callbacks.groupFetchState(groupId)
        } else null
        if (fetchState != null && groupId != null) {
            val active = zone == Zone.RESULTS && selectedResult >= 0
            val label = when (fetchState) {
                "fetching" -> "Fetching episode results…"
                "failed" -> "Fetch failed — try again"
                else -> "Fetch results  ›"
            }
            results.addView(fetchRow(label, active, fetchState != "fetching") {
                callbacks.requestGroupFetch(groupId)
            })
        }
        entries.forEachIndexed { i, entry ->
            results.addView(sourceRow(entry, zone == Zone.RESULTS && i == selectedResult, entry.index == callbacks.currentIndex()) {
                selectedResult = i
                callbacks.onSourceSelected(entry.index)
            })
        }
        resultsScroll.post {
            animateSourceFocus()
            requestVisibleBadges()
        }
    }

    private fun refreshResultSelection(oldSelection: Int) {
        listOf(oldSelection, selectedResult).distinct().forEach { index ->
            val row = results.getChildAt(index) ?: return@forEach
            val slot = row.tag as? BadgeSlot ?: return@forEach
            val active = zone == Zone.RESULTS && index == selectedResult
            if (slot.active == active) return@forEach
            slot.active = active
            (row.background as GradientDrawable).setColor(if (active) Color.WHITE else 0x07FFFFFF)
            slot.title.setTextColor(if (active) Color.BLACK else 0xE6FFFFFF.toInt())
            slot.showBuiltIn(customBadgesConfigured)
        }
        resultsScroll.post {
            if (zone == Zone.RESULTS) animateSourceFocus()
            requestVisibleBadges()
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
        orientation = LinearLayout.VERTICAL
        minimumHeight = dp(58)
        setPadding(dp(18), dp(11), dp(18), dp(11))
        background = bg(active, false)
        setOnClickListener { click() }
        val title = TextView(activity).apply {
            text = entry.title
            setTextColor(if (active) Color.BLACK else 0xE6FFFFFF.toInt())
            textSize = 14f
            setTypeface(typeface, 1)
        }
        addView(title, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        val builtIn = TvStreamBadgeStrip(activity, chipHeightDp = 22)
        addView(builtIn, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        val badges = TvStreamBadgeStrip(activity)
        addView(badges, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
        // Unlike Flutter's lazy list, every native row remains laid out. The
        // selected row's top delta directly captures expansion above it.
        addOnLayoutChangeListener { view, _, top, _, _, _, oldTop, _, oldBottom ->
            preserveBadgeAnchor(view, top, oldTop, oldBottom - oldTop)
        }
        val slot = BadgeSlot(entry, title, badges, builtIn, current, active)
        tag = slot
        slot.showBuiltIn(customBadgesConfigured)
        badgeCache[badgeKey(entry)]?.let { badges.show(it) }
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(5) }
    }

    private fun fetchRow(label: String, active: Boolean, enabled: Boolean, click: () -> Unit): View = TextView(activity).apply {
        text = label
        textSize = 14f
        setTypeface(typeface, 1)
        setTextColor(if (active) Color.BLACK else 0xD9FFFFFF.toInt())
        setPadding(dp(18), dp(14), dp(18), dp(14))
        background = bg(active, false)
        if (enabled) setOnClickListener { click() }
        layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(5) }
    }

    private fun tagView(tag: String, inverse: Boolean): TextView = TextView(activity).apply { text = tag; textSize = 10f; setTextColor(if (inverse) 0x99000000.toInt() else 0xAFFFFFFF.toInt()); setPadding(dp(6), dp(3), dp(6), dp(3)); background = GradientDrawable().apply { cornerRadius = dp(5).toFloat(); setColor(if (inverse) 0x12000000 else 0x12FFFFFF) }; layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(6) } }
    private fun bg(active: Boolean, selected: Boolean): GradientDrawable = GradientDrawable().apply { cornerRadius = dp(10).toFloat(); setColor(when { active -> Color.WHITE; selected -> 0x18FFFFFF; else -> 0x07FFFFFF }) }
    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
}
