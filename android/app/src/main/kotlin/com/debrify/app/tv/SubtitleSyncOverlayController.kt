package com.debrify.app.tv

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import com.debrify.app.util.SubtitleSettings

class SubtitleSyncOverlayController(
    private val activity: Activity,
    private val rootContainer: ViewGroup,
    private val onSettingsChanged: Runnable,
    private val onDismissed: Runnable
) {

    var isVisible: Boolean = false
        private set

    private var overlayView: View? = null
    private var valueLabel: TextView? = null
    private var trackContainer: FrameLayout? = null
    private var trackFill: View? = null
    private var thumb: View? = null

    fun show() {
        if (isVisible) return
        val overlay = buildOverlay()
        rootContainer.addView(overlay)
        overlayView = overlay
        isVisible = true
        overlay.post { updateSlider() }
    }

    fun hide() {
        if (!isVisible) return
        overlayView?.let { rootContainer.removeView(it) }
        overlayView = null
        valueLabel = null
        trackContainer = null
        trackFill = null
        thumb = null
        isVisible = false
        onDismissed.run()
    }

    fun dispatchKey(event: KeyEvent): Boolean {
        if (!isVisible) return false
        if (event.action != KeyEvent.ACTION_DOWN) return true

        return when (event.keyCode) {
            KeyEvent.KEYCODE_BACK -> { hide(); true }
            KeyEvent.KEYCODE_DPAD_LEFT -> {
                step(-SubtitleSettings.SYNC_OFFSET_STEP_MS)
                true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT -> {
                step(SubtitleSettings.SYNC_OFFSET_STEP_MS)
                true
            }
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                SubtitleSettings.setSyncOffsetMs(activity, 0L)
                onSettingsChanged.run()
                updateSlider()
                true
            }
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> {
                hide()
                true
            }
            else -> true
        }
    }

    private fun step(deltaMs: Long) {
        val current = SubtitleSettings.getSyncOffsetMs(activity)
        SubtitleSettings.setSyncOffsetMs(activity, current + deltaMs)
        onSettingsChanged.run()
        updateSlider()
    }

    private fun buildOverlay(): View {
        val ms = SubtitleSettings.getSyncOffsetMs(activity)
        val accent = SubtitleSettings.getSyncOffsetColor(ms)

        val wrapper = FrameLayout(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            elevation = dp(280).toFloat()
        }

        val bar = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).also { it.gravity = Gravity.BOTTOM }
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(48), dp(12), dp(48), dp(32))
            background = GradientDrawable(
                GradientDrawable.Orientation.BOTTOM_TOP,
                intArrayOf(0xCC000000.toInt(), 0x00000000)
            )
        }

        // Title row: "SUBTITLE SYNC" label + value
        val titleRow = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            gravity = Gravity.CENTER_VERTICAL
        }
        titleRow.addView(TextView(activity).apply {
            text = "SUBTITLE SYNC"
            setTextColor(0x99FFFFFF.toInt())
            textSize = 11f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            letterSpacing = 0.08f
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        })
        titleRow.addView(Space(activity).apply {
            layoutParams = LinearLayout.LayoutParams(dp(12), 0)
        })
        val vLabel = TextView(activity).apply {
            text = SubtitleSettings.formatSyncOffset(ms)
            setTextColor(accent)
            textSize = 22f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        valueLabel = vLabel
        titleRow.addView(vLabel)
        bar.addView(titleRow)

        bar.addView(Space(activity).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(10))
        })

        // Track
        val trackHeight = dp(4)
        val thumbSize = dp(20)
        val tc = FrameLayout(activity).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(36)
            )
        }

        tc.addView(View(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, trackHeight
            ).also { it.gravity = Gravity.CENTER_VERTICAL }
            background = GradientDrawable().apply {
                setColor(0x44FFFFFF)
                cornerRadius = trackHeight / 2f
            }
        })

        val fill = View(activity).apply {
            layoutParams = FrameLayout.LayoutParams(0, trackHeight).also {
                it.gravity = Gravity.CENTER_VERTICAL
            }
            background = GradientDrawable().apply {
                setColor(accent)
                cornerRadius = trackHeight / 2f
            }
        }
        trackFill = fill
        tc.addView(fill)

        tc.addView(View(activity).apply {
            layoutParams = FrameLayout.LayoutParams(dp(2), dp(12)).also {
                it.gravity = Gravity.CENTER
            }
            background = GradientDrawable().apply { setColor(0x99FFFFFF.toInt()) }
        })

        val th = View(activity).apply {
            layoutParams = FrameLayout.LayoutParams(thumbSize, thumbSize).also {
                it.gravity = Gravity.CENTER_VERTICAL
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
            }
            elevation = dp(4).toFloat()
        }
        thumb = th
        tc.addView(th)

        trackContainer = tc
        bar.addView(tc)

        bar.addView(Space(activity).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(6))
        })

        // Min/max labels
        val labels = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        fun dimLabel(text: String, grav: Int, weight: Float) = TextView(activity).apply {
            this.text = text
            setTextColor(0x66FFFFFF)
            textSize = 9f
            gravity = grav
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight)
        }
        labels.addView(dimLabel("-1hr", Gravity.START, 1f))
        labels.addView(dimLabel("0", Gravity.CENTER, 1f))
        labels.addView(dimLabel("+1hr", Gravity.END, 1f))
        bar.addView(labels)

        bar.addView(Space(activity).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(8))
        })

        bar.addView(TextView(activity).apply {
            text = "◄ ► adjust  ·  OK reset  ·  BACK close"
            setTextColor(0x55FFFFFF)
            textSize = 10f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        })

        wrapper.addView(bar)
        return wrapper
    }

    private fun updateSlider() {
        val container = trackContainer ?: return
        val th = thumb ?: return
        val fill = trackFill ?: return
        val label = valueLabel ?: return

        val ms = SubtitleSettings.getSyncOffsetMs(activity)
        val accent = SubtitleSettings.getSyncOffsetColor(ms)
        val range = SubtitleSettings.SYNC_OFFSET_MAX_MS - SubtitleSettings.SYNC_OFFSET_MIN_MS
        val fraction = ((ms - SubtitleSettings.SYNC_OFFSET_MIN_MS).toFloat() / range).coerceIn(0f, 1f)

        val trackWidth = container.width - container.paddingLeft - container.paddingRight
        val thumbSize = th.layoutParams.width
        val usableWidth = trackWidth - thumbSize
        val thumbLeft = (fraction * usableWidth).toInt()

        th.animate().translationX(thumbLeft.toFloat()).setDuration(80).start()

        val centerPx = (0.5f * usableWidth + thumbSize / 2f).toInt()
        val thumbCenterPx = (thumbLeft + thumbSize / 2f).toInt()
        val fillLeft = minOf(centerPx, thumbCenterPx)
        val fillRight = maxOf(centerPx, thumbCenterPx)
        val fillParams = fill.layoutParams as FrameLayout.LayoutParams
        fillParams.width = fillRight - fillLeft
        fillParams.marginStart = fillLeft
        fill.layoutParams = fillParams
        (fill.background as? GradientDrawable)?.setColor(accent)

        label.text = SubtitleSettings.formatSyncOffset(ms)
        label.setTextColor(accent)

        (th.background as? GradientDrawable)?.setColor(if (ms == 0L) accent else Color.WHITE)
    }

    private fun dp(v: Int): Int = (v * activity.resources.displayMetrics.density).toInt()
}
