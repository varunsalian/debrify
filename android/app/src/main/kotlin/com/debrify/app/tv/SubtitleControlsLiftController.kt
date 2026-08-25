package com.debrify.app.tv

import android.animation.ValueAnimator
import android.view.animation.DecelerateInterpolator
import androidx.media3.ui.SubtitleView
import kotlin.math.max

/**
 * Temporarily moves subtitles above player chrome without changing the user's
 * persisted subtitle position. The activity supplies the measured height of
 * whatever is occupying the bottom edge (dock, plus any docked panel).
 */
class SubtitleControlsLiftController(
    private val subtitleView: SubtitleView,
    private val clearanceMarginPx: Int,
) {
    private var basePaddingFraction = 0f
    private var renderedLiftPx = 0f
    private var controlsClearanceHeightPx = 0
    private var animator: ValueAnimator? = null

    fun setBasePaddingFraction(fraction: Float) {
        basePaddingFraction = fraction.coerceIn(0f, MAX_PADDING_FRACTION)
        subtitleView.setBottomPaddingFraction(basePaddingFraction)
        animateTo(currentTargetLiftPx(), animate = false)
    }

    fun liftAbove(clearanceHeightPx: Int, animate: Boolean = true) {
        controlsClearanceHeightPx = clearanceHeightPx.coerceAtLeast(0)
        animateTo(currentTargetLiftPx(), animate)
    }

    fun restore(animate: Boolean = true) {
        controlsClearanceHeightPx = 0
        animateTo(0f, animate)
    }

    private fun currentTargetLiftPx(): Float =
        targetLiftPx(
            subtitleView.height,
            controlsClearanceHeightPx,
            clearanceMarginPx,
        )

    fun cancel() {
        animator?.cancel()
        animator = null
    }

    private fun animateTo(targetLiftPx: Float, animate: Boolean) {
        animator?.cancel()
        animator = null
        if (!animate || renderedLiftPx == targetLiftPx) {
            setRenderedLift(targetLiftPx)
            return
        }
        animator = ValueAnimator.ofFloat(renderedLiftPx, targetLiftPx).apply {
            duration = ANIMATION_DURATION_MS
            interpolator = DecelerateInterpolator()
            addUpdateListener { setRenderedLift(it.animatedValue as Float) }
            start()
        }
    }

    private fun setRenderedLift(liftPx: Float) {
        renderedLiftPx = liftPx
        // Move the entire subtitle surface so cues with explicit ASS/SSA or
        // embedded line positions clear the controls as well. Compensating the
        // ordinary bottom-padding fraction keeps already-high default cues in
        // place until the controls actually reach them.
        subtitleView.setBottomPaddingFraction(
            compensatedPaddingFraction(basePaddingFraction, subtitleView.height, liftPx),
        )
        subtitleView.translationY = -liftPx
    }

    companion object {
        private const val ANIMATION_DURATION_MS = 220L
        private const val MAX_PADDING_FRACTION = 0.8f

        @JvmStatic
        fun targetLiftPx(
            subtitleHeightPx: Int,
            clearanceHeightPx: Int,
            clearanceMarginPx: Int,
        ): Float {
            if (subtitleHeightPx <= 0 || clearanceHeightPx <= 0) return 0f
            return max(0, clearanceHeightPx + clearanceMarginPx).toFloat()
        }

        @JvmStatic
        fun compensatedPaddingFraction(
            basePaddingFraction: Float,
            subtitleHeightPx: Int,
            liftPx: Float,
        ): Float {
            val base = basePaddingFraction.coerceIn(0f, MAX_PADDING_FRACTION)
            if (subtitleHeightPx <= 0) return base
            return max(0f, base - (liftPx / subtitleHeightPx))
        }
    }
}
