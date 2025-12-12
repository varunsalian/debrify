package com.debrify.app.tv

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Manages visual feedback for seek operations in video players
 * Shows subtle, Netflix-style indicators when user presses left/right arrow keys
 */
class SeekFeedbackManager(private val rootView: View) {

    private val feedbackContainer: FrameLayout? = rootView.findViewById(com.debrify.app.R.id.seek_feedback_container)
    private val leftIndicator: FrameLayout? = rootView.findViewById(com.debrify.app.R.id.seek_feedback_left)
    private val rightIndicator: FrameLayout? = rootView.findViewById(com.debrify.app.R.id.seek_feedback_right)
    private val leftText: TextView? = rootView.findViewById(com.debrify.app.R.id.seek_feedback_left_text)
    private val rightText: TextView? = rootView.findViewById(com.debrify.app.R.id.seek_feedback_right_text)

    // Ripple effect views (optional, for double-tap style)
    private val leftRippleContainer: FrameLayout? = rootView.findViewById(com.debrify.app.R.id.seek_feedback_ripple_left)
    private val rightRippleContainer: FrameLayout? = rootView.findViewById(com.debrify.app.R.id.seek_feedback_ripple_right)

    private val handler = Handler(Looper.getMainLooper())
    private var currentAnimatorSet: AnimatorSet? = null
    private var hideRunnable: Runnable? = null

    companion object {
        private const val FEEDBACK_DURATION = 600L // Show for 600ms
        private const val FADE_IN_DURATION = 150L
        private const val FADE_OUT_DURATION = 200L
        private const val SCALE_OVERSHOOT = 1.1f
    }

    /**
     * Shows seek backward feedback on the left side of the screen
     * @param seekAmount The amount being seeked (e.g., "10s", "30s")
     */
    fun showSeekBackward(seekAmount: String = "10s") {
        leftText?.text = "-$seekAmount"
        showFeedback(leftIndicator, leftRippleContainer, isLeft = true)
    }

    /**
     * Shows seek forward feedback on the right side of the screen
     * @param seekAmount The amount being seeked (e.g., "10s", "30s")
     */
    fun showSeekForward(seekAmount: String = "10s") {
        rightText?.text = "+$seekAmount"
        showFeedback(rightIndicator, rightRippleContainer, isLeft = false)
    }

    /**
     * Shows feedback for continuous seeking (long press)
     * @param isForward True if seeking forward, false if backward
     * @param speed The speed multiplier (e.g., "2x", "4x")
     */
    fun showContinuousSeek(isForward: Boolean, speed: String = "") {
        if (isForward) {
            rightText?.text = if (speed.isNotEmpty()) "▶▶ $speed" else "▶▶"
            showFeedback(rightIndicator, rightRippleContainer, isLeft = false, continuous = true)
        } else {
            leftText?.text = if (speed.isNotEmpty()) "◀◀ $speed" else "◀◀"
            showFeedback(leftIndicator, leftRippleContainer, isLeft = true, continuous = true)
        }
    }

    private fun showFeedback(
        indicator: FrameLayout?,
        rippleContainer: FrameLayout?,
        isLeft: Boolean,
        continuous: Boolean = false
    ) {
        indicator ?: return

        // Cancel any pending hide operations
        hideRunnable?.let { handler.removeCallbacks(it) }
        currentAnimatorSet?.cancel()

        // Make sure the indicator is visible
        indicator.visibility = View.VISIBLE

        // Create animation set
        val animatorSet = AnimatorSet()
        val animations = mutableListOf<Animator>()

        // Fade in with scale effect
        val fadeIn = ObjectAnimator.ofFloat(indicator, View.ALPHA, indicator.alpha, 1f).apply {
            duration = FADE_IN_DURATION
            interpolator = DecelerateInterpolator()
        }
        animations.add(fadeIn)

        // Scale animation for pop effect
        val scaleXIn = ObjectAnimator.ofFloat(indicator, View.SCALE_X, 0.8f, SCALE_OVERSHOOT, 1f).apply {
            duration = FADE_IN_DURATION + 50
            interpolator = OvershootInterpolator(2f)
        }
        val scaleYIn = ObjectAnimator.ofFloat(indicator, View.SCALE_Y, 0.8f, SCALE_OVERSHOOT, 1f).apply {
            duration = FADE_IN_DURATION + 50
            interpolator = OvershootInterpolator(2f)
        }
        animations.add(scaleXIn)
        animations.add(scaleYIn)

        // Optional: Add ripple effect for double-tap style
        rippleContainer?.let { addRippleAnimation(it, animations) }

        animatorSet.playTogether(animations)
        animatorSet.start()
        currentAnimatorSet = animatorSet

        // Schedule hide unless it's continuous seeking
        if (!continuous) {
            hideRunnable = Runnable {
                hideFeedback(indicator, rippleContainer)
            }
            handler.postDelayed(hideRunnable!!, FEEDBACK_DURATION)
        }
    }

    private fun hideFeedback(indicator: FrameLayout?, rippleContainer: FrameLayout?) {
        indicator ?: return

        val fadeOut = ObjectAnimator.ofFloat(indicator, View.ALPHA, 1f, 0f).apply {
            duration = FADE_OUT_DURATION
            interpolator = DecelerateInterpolator()
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    indicator.visibility = View.GONE
                    indicator.scaleX = 1f
                    indicator.scaleY = 1f
                    rippleContainer?.visibility = View.GONE
                }
            })
        }

        fadeOut.start()
    }

    private fun addRippleAnimation(rippleContainer: FrameLayout, animations: MutableList<Animator>) {
        // This creates a subtle ripple effect similar to YouTube's double-tap
        rippleContainer.visibility = View.VISIBLE

        val ripple1 = rippleContainer.getChildAt(0)
        val ripple2 = rippleContainer.getChildAt(1)

        // First ripple
        val ripple1ScaleX = ObjectAnimator.ofFloat(ripple1, View.SCALE_X, 0.5f, 1.5f).apply {
            duration = 400
            interpolator = DecelerateInterpolator()
        }
        val ripple1ScaleY = ObjectAnimator.ofFloat(ripple1, View.SCALE_Y, 0.5f, 1.5f).apply {
            duration = 400
            interpolator = DecelerateInterpolator()
        }
        val ripple1Alpha = ObjectAnimator.ofFloat(ripple1, View.ALPHA, 0.6f, 0f).apply {
            duration = 400
            interpolator = DecelerateInterpolator()
        }

        // Second ripple (delayed)
        val ripple2ScaleX = ObjectAnimator.ofFloat(ripple2, View.SCALE_X, 0.5f, 1.8f).apply {
            duration = 500
            startDelay = 100
            interpolator = DecelerateInterpolator()
        }
        val ripple2ScaleY = ObjectAnimator.ofFloat(ripple2, View.SCALE_Y, 0.5f, 1.8f).apply {
            duration = 500
            startDelay = 100
            interpolator = DecelerateInterpolator()
        }
        val ripple2Alpha = ObjectAnimator.ofFloat(ripple2, View.ALPHA, 0.4f, 0f).apply {
            duration = 500
            startDelay = 100
            interpolator = DecelerateInterpolator()
        }

        animations.addAll(listOf(
            ripple1ScaleX, ripple1ScaleY, ripple1Alpha,
            ripple2ScaleX, ripple2ScaleY, ripple2Alpha
        ))
    }

    /**
     * Hides all feedback immediately
     */
    fun hideAllFeedback() {
        hideRunnable?.let { handler.removeCallbacks(it) }
        currentAnimatorSet?.cancel()

        leftIndicator?.apply {
            animate().cancel()
            visibility = View.GONE
            alpha = 0f
            scaleX = 1f
            scaleY = 1f
        }

        rightIndicator?.apply {
            animate().cancel()
            visibility = View.GONE
            alpha = 0f
            scaleX = 1f
            scaleY = 1f
        }

        leftRippleContainer?.visibility = View.GONE
        rightRippleContainer?.visibility = View.GONE
    }

    /**
     * Cleanup resources
     */
    fun destroy() {
        hideRunnable?.let { handler.removeCallbacks(it) }
        currentAnimatorSet?.cancel()
        hideAllFeedback()
    }
}