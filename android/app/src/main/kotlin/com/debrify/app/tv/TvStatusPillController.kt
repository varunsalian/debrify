package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

internal class TvStatusPillController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        fun dp(value: Int): Int
        val externalSubtitleHandler: Handler
    }
    private var statusPill: TextView? = null
    private val statusPillHideRunnable = Runnable { hideStatusPill() }

    // ── Status pill ──────────────────────────────────────────────────────────
    // Small bottom-center chip for transient progress feedback that must not
    // touch playback: external subtitle downloads and source switches.

    private fun ensureStatusPill(): TextView {
        statusPill?.let { return it }
        val pill = TextView(activity).apply {
            textSize = 13f
            setTextColor(Color.WHITE)
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            background = GradientDrawable().apply {
                setColor(0xD9101014.toInt())
                cornerRadius = host.dp(18).toFloat()
                setStroke(host.dp(1), 0x33FFFFFF)
            }
            setPadding(host.dp(16), host.dp(8), host.dp(16), host.dp(8))
            elevation = host.dp(240).toFloat()
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            ).also { it.bottomMargin = host.dp(48) }
        }
        activity.findViewById<ViewGroup>(android.R.id.content).addView(pill)
        statusPill = pill
        return pill
    }

    fun showStatusPill(message: String) {
        host.externalSubtitleHandler.removeCallbacks(statusPillHideRunnable)
        val pill = ensureStatusPill()
        pill.text = message
        if (pill.visibility != View.VISIBLE) {
            pill.alpha = 0f
            pill.visibility = View.VISIBLE
        }
        pill.animate().cancel()
        pill.animate().alpha(1f).setDuration(180).start()
    }

    /** Show a short confirmation/error message, then fade the pill away. */
    internal fun showStatusPillTransient(message: String) {
        showStatusPill(message)
        host.externalSubtitleHandler.postDelayed(statusPillHideRunnable, 1400)
    }

    internal fun hideStatusPill() {
        host.externalSubtitleHandler.removeCallbacks(statusPillHideRunnable)
        val pill = statusPill ?: return
        if (pill.visibility != View.VISIBLE) return
        pill.animate().cancel()
        pill.animate().alpha(0f).setDuration(220).withEndAction {
            pill.visibility = View.GONE
        }.start()
    }
}
