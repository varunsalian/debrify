package com.debrify.app.tv

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Space
import android.widget.TextView
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleCueParser
import com.debrify.app.util.SubtitleSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class SubtitleLinePickerController(
    private val activity: Activity,
    private val rootContainer: ViewGroup,
    private val getCurrentPositionMs: () -> Long,
    private val onOffsetApplied: (Long) -> Unit,
    private val onDismissed: Runnable
) {

    companion object {
        // Cache parsed cues per URL so reopening doesn't re-download.
        private val cueCache = mutableMapOf<String, List<SubtitleCue>>()
        // Remember the cue start time the user explicitly synced to per URL,
        // so reopening restores their selection instead of jumping to whatever
        // cue is playing right now.
        private val lastSyncedCueStartMs = mutableMapOf<String, Long>()
    }

    var isVisible: Boolean = false
        private set

    private var currentUrl: String = ""
    private var overlayView: View? = null
    private var cues: List<SubtitleCue> = emptyList()
    private var selectedIndex: Int = -1
    private var highlightedIndex: Int = -1
    // Tracks whether the current OK hold already triggered a reset, so a single
    // long-press resets once and the eventual key-up doesn't also sync.
    private var centerResetFired: Boolean = false
    // True once we've seen the key-down for an OK press that started while the
    // picker was visible. Guards against the key-up of the very press that
    // opened this overlay (whose key-down went to the subtitle panel) leaking
    // through and triggering a spurious sync on open.
    private var centerDownSeen: Boolean = false
    private var cueContainer: LinearLayout? = null
    private var scrollView: ScrollView? = null
    private var offsetLabel: TextView? = null
    private var hintLabel: TextView? = null
    private val handler = Handler(Looper.getMainLooper())
    private var positionRunnable: Runnable? = null

    private val accentColor = 0xFFE50914.toInt()

    fun show(subtitleUrl: String) {
        if (isVisible) return
        currentUrl = subtitleUrl
        centerDownSeen = false
        centerResetFired = false

        val overlay = buildOverlay()
        rootContainer.addView(overlay)
        overlayView = overlay
        isVisible = true

        val cached = cueCache[subtitleUrl]
        if (cached != null) {
            cues = cached
            onCuesReady()
        } else {
            CoroutineScope(Dispatchers.IO).launch {
                val parsed = SubtitleCueParser.parseFromUrl(subtitleUrl)
                withContext(Dispatchers.Main) {
                    if (!isVisible) return@withContext
                    if (parsed.isNotEmpty()) cueCache[subtitleUrl] = parsed
                    cues = parsed
                    onCuesReady()
                }
            }
        }
    }

    private fun onCuesReady() {
        if (cues.isEmpty()) {
            hintLabel?.text = "Could not parse subtitle lines — use slider instead"
            return
        }
        hintLabel?.text = "▲ ▼ navigate  ·  OK sync  ·  hold OK reset  ·  BACK close"
        buildCueRows()

        highlightedIndex = computeHighlightIndex()

        // Restore last user-chosen cue if we have one; otherwise default to
        // the currently-playing cue so something is focused for D-pad input.
        val lastSynced = lastSyncedCueStartMs[currentUrl]
        selectedIndex = if (lastSynced != null) {
            cues.indexOfFirst { it.startMs == lastSynced }
                .takeIf { it >= 0 }
                ?: highlightedIndex
        } else {
            highlightedIndex
        }

        updateCueHighlights()
        startPositionTracking()

        val scrollTarget = if (selectedIndex >= 0) selectedIndex else highlightedIndex
        if (scrollTarget >= 0) {
            scrollView?.post { scrollToIndex(scrollTarget) }
        }
    }

    fun hide() {
        if (!isVisible) return
        stopPositionTracking()
        overlayView?.let { rootContainer.removeView(it) }
        overlayView = null
        cueContainer = null
        scrollView = null
        offsetLabel = null
        hintLabel = null
        cues = emptyList()
        selectedIndex = -1
        highlightedIndex = -1
        isVisible = false
        onDismissed.run()
    }

    fun dispatchKey(event: KeyEvent): Boolean {
        if (!isVisible) return false

        // OK/Center is special: a tap (act on key-up) syncs to the selected cue,
        // while holding it resets the offset to 0. Handle both actions here so a
        // long-press can suppress the sync that would otherwise fire on release.
        if (event.keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
            event.keyCode == KeyEvent.KEYCODE_ENTER
        ) {
            when (event.action) {
                KeyEvent.ACTION_DOWN -> {
                    if (event.repeatCount == 0) {
                        centerDownSeen = true
                        centerResetFired = false
                    } else if (centerDownSeen && !centerResetFired) {
                        // First key-repeat means the button has been held past the
                        // system long-press threshold.
                        centerResetFired = true
                        resetSync()
                    }
                }
                KeyEvent.ACTION_UP -> {
                    if (centerDownSeen &&
                        !centerResetFired &&
                        cues.isNotEmpty() &&
                        selectedIndex in cues.indices
                    ) {
                        applySyncFromCue(selectedIndex)
                    }
                    centerDownSeen = false
                }
            }
            return true
        }

        if (event.action != KeyEvent.ACTION_DOWN) return true

        return when (event.keyCode) {
            KeyEvent.KEYCODE_BACK -> { hide(); true }
            KeyEvent.KEYCODE_DPAD_UP -> {
                if (cues.isNotEmpty()) moveSelection(-1)
                true
            }
            KeyEvent.KEYCODE_DPAD_DOWN -> {
                if (cues.isNotEmpty()) moveSelection(1)
                true
            }
            KeyEvent.KEYCODE_DPAD_LEFT -> {
                step(-SubtitleSettings.SYNC_OFFSET_STEP_MS)
                true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT -> {
                step(SubtitleSettings.SYNC_OFFSET_STEP_MS)
                true
            }
            else -> true
        }
    }

    private fun moveSelection(delta: Int) {
        val base = if (selectedIndex < 0) highlightedIndex.coerceAtLeast(0) else selectedIndex
        val newIndex = (base + delta).coerceIn(0, cues.size - 1)
        if (newIndex == selectedIndex) return
        selectedIndex = newIndex
        updateCueHighlights()
        scrollToIndex(selectedIndex)
    }

    private fun applySyncFromCue(index: Int) {
        val cue = cues[index]
        val posMs = getCurrentPositionMs()
        val offset = posMs - cue.startMs
        val clamped = offset.coerceIn(
            SubtitleSettings.SYNC_OFFSET_MIN_MS,
            SubtitleSettings.SYNC_OFFSET_MAX_MS
        )
        SubtitleSettings.setSyncOffsetMs(activity, clamped)
        lastSyncedCueStartMs[currentUrl] = cue.startMs
        onOffsetApplied(clamped)

        // Immediate visual feedback — don't wait for the next tracker tick,
        // or the user thinks the sync didn't take.
        highlightedIndex = index
        updateCueHighlights()
        updateOffsetLabel()
    }

    private fun step(deltaMs: Long) {
        val current = SubtitleSettings.getSyncOffsetMs(activity)
        SubtitleSettings.setSyncOffsetMs(activity, current + deltaMs)
        onOffsetApplied(SubtitleSettings.getSyncOffsetMs(activity))
        updateOffsetLabel()
    }

    private fun resetSync() {
        SubtitleSettings.setSyncOffsetMs(activity, 0L)
        // Forget the remembered sync line so reopening doesn't restore it.
        lastSyncedCueStartMs.remove(currentUrl)
        onOffsetApplied(0L)
        updateOffsetLabel()
        // Recompute which cue is "now playing" at zero offset for instant feedback.
        updateHighlight()
    }

    private fun startPositionTracking() {
        positionRunnable = object : Runnable {
            override fun run() {
                if (!isVisible) return
                updateHighlight()
                handler.postDelayed(this, 300)
            }
        }
        handler.postDelayed(positionRunnable!!, 300)
    }

    private fun stopPositionTracking() {
        positionRunnable?.let { handler.removeCallbacks(it) }
        positionRunnable = null
    }

    private fun computeHighlightIndex(): Int {
        if (cues.isEmpty()) return -1
        val posMs = getCurrentPositionMs()
        val offset = SubtitleSettings.getSyncOffsetMs(activity)
        var best = -1
        for (i in cues.indices) {
            if (cues[i].startMs <= posMs - offset) best = i else break
        }
        return best
    }

    private fun updateHighlight() {
        val newHighlight = computeHighlightIndex()
        if (newHighlight != highlightedIndex) {
            highlightedIndex = newHighlight
            updateCueHighlights()
        }
    }

    private fun updateOffsetLabel() {
        val ms = SubtitleSettings.getSyncOffsetMs(activity)
        offsetLabel?.text = SubtitleSettings.formatSyncOffset(ms)
        offsetLabel?.setTextColor(SubtitleSettings.getSyncOffsetColor(ms))
    }

    private fun scrollToIndex(index: Int) {
        val sv = scrollView ?: return
        val container = cueContainer ?: return
        val child = container.getChildAt(index) ?: return
        val targetY = child.top - sv.height / 2 + child.height / 2
        sv.smoothScrollTo(0, targetY.coerceAtLeast(0))
    }

    private fun buildOverlay(): View {
        val ms = SubtitleSettings.getSyncOffsetMs(activity)

        val wrapper = FrameLayout(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            elevation = dp(280).toFloat()
            setBackgroundColor(0xE6000000.toInt())
        }

        val main = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // Header
        val header = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(32), dp(16), dp(32), dp(12))
        }

        header.addView(TextView(activity).apply {
            text = "☰"
            setTextColor(0x99FFFFFF.toInt())
            textSize = 16f
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).also { it.marginEnd = dp(10) }
        })
        header.addView(TextView(activity).apply {
            text = "SUBTITLE SYNC"
            setTextColor(0x99FFFFFF.toInt())
            textSize = 12f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            letterSpacing = 0.1f
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).also { it.marginEnd = dp(14) }
        })

        val oLabel = TextView(activity).apply {
            text = SubtitleSettings.formatSyncOffset(ms)
            setTextColor(SubtitleSettings.getSyncOffsetColor(ms))
            textSize = 17f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            val bg = GradientDrawable().apply {
                setColor(0x26FFFFFF)
                cornerRadius = dp(6).toFloat()
            }
            background = bg
            setPadding(dp(12), dp(4), dp(12), dp(4))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        offsetLabel = oLabel
        header.addView(oLabel)

        header.addView(Space(activity).apply {
            layoutParams = LinearLayout.LayoutParams(0, 0, 1f)
        })

        header.addView(TextView(activity).apply {
            text = "Tap the line you just heard"
            setTextColor(0x66FFFFFF)
            textSize = 12f
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        })

        main.addView(header)

        // Divider
        main.addView(View(activity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(1)
            )
            setBackgroundColor(0x14FFFFFF)
        })

        // Scrollable cue list
        val sv = ScrollView(activity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f
            )
            isSmoothScrollingEnabled = true
        }
        scrollView = sv

        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(8), dp(20), dp(8))
        }
        cueContainer = container

        // Loading state
        container.addView(TextView(activity).apply {
            text = "Loading subtitle lines..."
            setTextColor(0x66FFFFFF)
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, dp(60), 0, dp(60))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        })

        sv.addView(container)
        main.addView(sv)

        // Footer hint
        val hint = TextView(activity).apply {
            text = "Loading..."
            setTextColor(0x44FFFFFF)
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(8), dp(32), dp(14))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        hintLabel = hint
        main.addView(hint)

        wrapper.addView(main)
        return wrapper
    }

    private fun buildCueRows() {
        val container = cueContainer ?: return
        container.removeAllViews()

        for ((index, cue) in cues.withIndex()) {
            val row = buildCueRow(index, cue)
            container.addView(row)
        }
    }

    private fun buildCueRow(index: Int, cue: SubtitleCue): View {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).also {
                it.setMargins(dp(4), dp(2), dp(4), dp(2))
            }
            setPadding(dp(14), dp(10), dp(14), dp(10))
            val bg = GradientDrawable().apply {
                setColor(0x08FFFFFF)
                cornerRadius = dp(10).toFloat()
            }
            background = bg
            tag = index
        }

        // Timestamp
        row.addView(TextView(activity).apply {
            text = formatTime(cue.startMs)
            setTextColor(0x80FFFFFF.toInt())
            textSize = 11f
            typeface = Typeface.MONOSPACE
            layoutParams = LinearLayout.LayoutParams(
                dp(60), ViewGroup.LayoutParams.WRAP_CONTENT
            )
        })

        // Accent bar (visible when current)
        row.addView(View(activity).apply {
            layoutParams = LinearLayout.LayoutParams(dp(3), dp(24)).also {
                it.marginEnd = dp(10)
            }
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                cornerRadius = dp(2).toFloat()
            }
        })

        // Text
        row.addView(TextView(activity).apply {
            text = cue.text
            setTextColor(0xB3FFFFFF.toInt())
            textSize = 13f
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        })

        return row
    }

    private fun updateCueHighlights() {
        val container = cueContainer ?: return
        for (i in 0 until container.childCount) {
            val row = container.getChildAt(i) as? LinearLayout ?: continue
            val idx = row.tag as? Int ?: continue
            val isCurrent = idx == highlightedIndex
            val isSelected = idx == selectedIndex
            val isPast = idx < highlightedIndex

            // Row background
            val bg = row.background as? GradientDrawable ?: GradientDrawable()
            when {
                isSelected -> {
                    bg.setColor(if (isCurrent) 0x33E50914 else 0x1AFFFFFF)
                    bg.setStroke(dp(1), if (isCurrent) 0x66E50914 else 0x33FFFFFF)
                }
                isCurrent -> {
                    bg.setColor(0x1AE50914)
                    bg.setStroke(0, Color.TRANSPARENT)
                }
                else -> {
                    bg.setColor(0x08FFFFFF)
                    bg.setStroke(0, Color.TRANSPARENT)
                }
            }
            row.background = bg

            // Timestamp color
            val timestamp = row.getChildAt(0) as? TextView
            timestamp?.setTextColor(
                when {
                    isCurrent -> accentColor
                    isPast -> 0x59FFFFFF
                    else -> 0x80FFFFFF.toInt()
                }
            )

            // Accent bar
            val bar = row.getChildAt(1)
            (bar?.background as? GradientDrawable)?.setColor(
                if (isCurrent) accentColor else Color.TRANSPARENT
            )

            // Text styling
            val text = row.getChildAt(2) as? TextView
            text?.setTextColor(
                when {
                    isCurrent -> Color.WHITE
                    isPast -> 0x59FFFFFF
                    else -> 0xB3FFFFFF.toInt()
                }
            )
            text?.typeface = if (isCurrent)
                Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            else
                Typeface.DEFAULT
        }
    }

    private fun formatTime(ms: Long): String {
        val h = ms / 3600000
        val m = (ms % 3600000) / 60000
        val s = (ms % 60000) / 1000
        return if (h > 0) {
            "%02d:%02d:%02d".format(h, m, s)
        } else {
            "%02d:%02d".format(m, s)
        }
    }

    private fun dp(v: Int): Int = (v * activity.resources.displayMetrics.density).toInt()
}
