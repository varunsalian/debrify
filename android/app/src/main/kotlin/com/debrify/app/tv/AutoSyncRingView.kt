package com.debrify.app.tv

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

// ── Auto-sync countdown pill ─────────────────────────────────────────────
// The quiet bottom-right status pill (dev/design/mockups/
// subtitle_auto_sync_hint_mockup/countdown_devices.html, same component as
// the Dart player's AutoSyncPill): a draining 90-second ring + tracked
// uppercase label + tabular seconds while listening; colored glyph + label
// for results. Display-only, never focusable, anchored inside the overscan
// safe area. Numbers never appear in result states — offsets and hints
// live in logcat (adb logcat -s AutoSync).

internal object AutoSyncColors {
    const val OK = 0xFF82E0AD.toInt() // pill green — synced / restored
    const val FAIL = 0xFFE8C07B.toInt() // pill amber — declined, never alarming
    const val BUSY = 0xFF7BDCFF.toInt() // pill cyan — listening / checking
}

/** The pill's leading glyph: a heartbeat — pulsing halo around a dot. */
internal class AutoSyncRingView(context: android.content.Context) : View(context) {
    var arcColor = AutoSyncColors.BUSY
        set(value) { field = value; invalidate() }
    private var pulse = 0f
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1_800
        repeatCount = ValueAnimator.INFINITE
        addUpdateListener {
            pulse = it.animatedValue as Float
            invalidate()
        }
    }

    /**
         * Explicit, not attach-driven: the view lives on the content view for
         * the whole activity, so an always-on animator would invalidate every
         * frame forever after the first show — even while the pill is GONE.
         */
    fun setPulsing(on: Boolean) {
        if (on) {
            if (!pulseAnimator.isStarted) pulseAnimator.start()
        } else if (pulseAnimator.isStarted) {
            pulseAnimator.cancel()
            pulse = 0f
            invalidate()
        }
    }

    override fun onDetachedFromWindow() {
        pulseAnimator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val cx = w / 2f
        val cy = height / 2f
        val r = w / 2f
        if (pulse > 0f) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = w * 0.14f
            paint.color = arcColor
            paint.alpha = (82 * (1f - pulse)).toInt()
            canvas.drawCircle(cx, cy, r * (0.35f + 0.65f * pulse), paint)
            paint.alpha = 255
        }
        paint.style = Paint.Style.FILL
        paint.color = arcColor
        canvas.drawCircle(cx, cy, r * 0.32f, paint)
    }
}
