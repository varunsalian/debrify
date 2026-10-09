package com.debrify.app.tv

import android.animation.ValueAnimator
import android.graphics.Color
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.debrify.app.R
import kotlinx.coroutines.cancel

internal class TvSeekScrubController(
    private val activity: AppCompatActivity,
    private val host: TvControlsOverlayController.Host,
    private val controls: TvControlsOverlayController,
) {
    private var seekbarBackgroundWidth: Int = 0
    private var currentSeekSpeed: Float = 1.0f

    // Time Display in Controls (Cinema Mode - split displays)
    internal var debrifyTimeDisplay: TextView? = null  // Legacy combined display (hidden)
    internal var debrifyTimeCurrent: TextView? = null  // Current time (left)
    internal var debrifyTimeTotal: TextView? = null    // Total time (right)
    internal var debrifyProgressLine: View? = null
    internal var cinemaProgressBuffered: View? = null

    // Cinema Mode Interactive Progress Bar
    internal var cinemaProgressContainer: View? = null
    internal var cinemaProgressBackground: View? = null
    internal var cinemaProgressThumb: View? = null
    internal var cinemaSpeedIndicator: TextView? = null
    internal var ottScrubPreviewChip: View? = null
    internal var ottScrubPreviewText: TextView? = null
    private var cinemaProgressTrackWidth: Int = 0
    internal var cinemaSeekMode: Boolean = false  // True when actively seeking via progress bar
    internal var cinemaSeekWasPlaying: Boolean = false
    private var cinemaProgressAnimator: ValueAnimator? = null
    private var cinemaLastAnimatedProgress: Float = 0f
    internal var seekbarVisible = false
    private var seekbarPosition: Long = 0
    private var videoDuration: Long = 0
    internal val seekbarHandler = Handler(Looper.getMainLooper())

    private val seekbarProgressRunnable = object : Runnable {
        override fun run() {
            updateSeekbarProgress()
            seekbarHandler.postDelayed(this, 100) // Update every 100ms for smooth progress
        }
    }

    fun setupSeekbar() {
        host.seekbarOverlay.visibility = View.GONE
        host.seekbarOverlay.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_DOWN) {
                hideSeekbar()
                return@setOnKeyListener true
            }
            false
        }
    }

    // Premium Seekbar Progress Updates
    fun startSeekbarProgressUpdates() {
        seekbarHandler.removeCallbacks(seekbarProgressRunnable)
        seekbarHandler.post(seekbarProgressRunnable)
    }

    private fun stopSeekbarProgressUpdates() {
        seekbarHandler.removeCallbacks(seekbarProgressRunnable)
    }

    private fun updateSeekbarProgress() {
        // Skip updates when in cinema seek mode (progress bar is being controlled manually)
        if (cinemaSeekMode) return

        val player = host.player ?: return

        val currentPosition = player.currentPosition
        val duration = player.duration

        if (duration > 0) {
            // Track the largest stable duration and the last genuine position so a
            // later transient short-duration reading or a spurious STATE_ENDED can be
            // recognised and not scrobbled as a full watch (see maxStableDurationMs).
            if (duration > host.maxStableDurationMs) host.maxStableDurationMs = duration
            if (currentPosition in 0..duration) host.lastRealPositionMs = currentPosition
            host.skipSegmentController.updateSkipSegmentState(currentPosition, duration)

            // Update Cinema Mode split time displays
            debrifyTimeCurrent?.text = formatTime(currentPosition)
            debrifyTimeTotal?.text = if (host.ottSkinInstalled) {
                "-" + formatTime((duration - currentPosition).coerceAtLeast(0))
            } else {
                formatTime(duration)
            }

            // Update legacy combined display (for compatibility)
            debrifyTimeDisplay?.text = "${formatTime(currentPosition)} / ${formatTime(duration)}"

            // Update progress line width
            debrifyProgressLine?.let { progressLine ->
                val progressPercentage = (currentPosition.toFloat() / duration.toFloat())
                val parentWidth = (progressLine.parent as? View)?.width ?: 0
                if (parentWidth > 0) {
                    val progressWidth = (parentWidth * progressPercentage).toInt()
                    val layoutParams = progressLine.layoutParams
                    layoutParams.width = progressWidth
                    progressLine.layoutParams = layoutParams
                }
            }

            // Update buffered-ahead width (translucent bar behind the played line).
            // bufferedPosition fills in chunks, so skip the relayout when the
            // computed width hasn't actually changed (avoids a layout pass each tick).
            cinemaProgressBuffered?.let { buffered ->
                val bufferedPercentage = (player.bufferedPosition.toFloat() / duration.toFloat())
                    .coerceIn(0f, 1f)
                val parentWidth = (buffered.parent as? View)?.width ?: 0
                if (parentWidth > 0) {
                    val bufferedWidth = (parentWidth * bufferedPercentage).toInt()
                    val layoutParams = buffered.layoutParams
                    if (layoutParams.width != bufferedWidth) {
                        layoutParams.width = bufferedWidth
                        buffered.layoutParams = layoutParams
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CINEMA MODE - Interactive Progress Bar (replaces old seekbar overlay)
    // ═══════════════════════════════════════════════════════════════════════════

    fun showControlsAndFocusProgressBar() {
        if (!controls.controlsMenuVisible) {
            controls.showControlsMenu()
        }
        // Delay focus to allow controls to become visible
        controls.controlsHandler.postDelayed({
            cinemaProgressContainer?.requestFocus()
        }, 100)
    }

    fun setupCinemaProgressBar() {
        cinemaProgressContainer?.setOnFocusChangeListener { _, hasFocus ->
            if (hasFocus) {
                enterCinemaSeekMode()
            } else {
                exitCinemaSeekMode(confirm = false)
            }
        }

        cinemaProgressContainer?.setOnKeyListener { _, keyCode, event ->
            if (!cinemaSeekMode) return@setOnKeyListener false

            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekbarPosition = (seekbarPosition - step).coerceAtLeast(0)
                        updateCinemaSeekSpeed(step)
                        updateCinemaProgressUI()
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        val step = getAcceleratedSeekStep(event.repeatCount)
                        seekbarPosition = (seekbarPosition + step).coerceAtMost(videoDuration)
                        updateCinemaSeekSpeed(step)
                        updateCinemaProgressUI()
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER -> {
                        confirmCinemaSeek()
                        true
                    }
                    KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> {
                        exitCinemaSeekMode(confirm = false)
                        controls.pauseButton?.requestFocus()
                        true
                    }
                    KeyEvent.KEYCODE_DPAD_DOWN -> {
                        exitCinemaSeekMode(confirm = false)
                        controls.pauseButton?.requestFocus()
                        true
                    }
                    else -> false
                }
            } else if (event.action == KeyEvent.ACTION_UP) {
                // Reset speed indicator when key is released
                if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT || keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
                    currentSeekSpeed = 1.0f
                    cinemaSpeedIndicator?.visibility = View.GONE
                }
                false
            } else false
        }
    }

    private fun enterCinemaSeekMode() {
        if (cinemaSeekMode || host.player == null) return

        seekbarPosition = host.player?.currentPosition ?: 0
        videoDuration = host.player?.duration ?: 0

        if (videoDuration <= 0) {
            // Don't trap focus — let DPAD navigation skip to Sources badge
            if (host.ottSkinInstalled) {
                // The badge is permanently hidden under OTT (its requestFocus
                // would no-op and strand focus); the dock's Sources button is
                // already in normal traversal, so just fall back to Play.
                controls.pauseButton?.requestFocus()
            } else if (host.stremioSources.isNotEmpty()) {
                host.stremioSourceBadge?.requestFocus()
            } else {
                controls.pauseButton?.requestFocus()
            }
            return
        }

        // Preserve the user's playback intent. `isPlaying` can briefly be
        // false while buffering even though playWhenReady is true, so retain
        // the latter and only resume if seeking actually interrupted playback.
        cinemaSeekWasPlaying = host.player?.playWhenReady == true
        if (cinemaSeekWasPlaying) {
            host.player?.pause()
        }

        cinemaSeekMode = true
        currentSeekSpeed = 1.0f

        // Reset animated progress to current position
        cinemaLastAnimatedProgress = if (videoDuration > 0) {
            seekbarPosition.toFloat() / videoDuration.toFloat()
        } else 0f

        // Show thumb with smooth entrance animation
        cinemaProgressThumb?.let { thumb ->
            thumb.visibility = View.VISIBLE
            thumb.alpha = 0f
            thumb.scaleX = 0.6f
            thumb.scaleY = 0.6f
            thumb.animate()
                .alpha(1f)
                .scaleX(1.15f)  // Slight overshoot
                .scaleY(1.15f)
                .setDuration(200)
                .setInterpolator(android.view.animation.OvershootInterpolator(2f))
                .withEndAction {
                    // Settle to normal size
                    thumb.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(100)
                        .start()
                }
                .start()
        }

        if (host.ottSkinInstalled) {
            // OTT keeps the dock's own palette (white70 times) and swells the
            // bar 3->6dp instead of recoloring; the preview chip appears with
            // the first step via updateCinemaProgressUI.
            host.controlsDockController.setOttTrackHeight(focused = true)
        } else {
            // Highlight current time with Netflix red
            debrifyTimeCurrent?.setTextColor(Color.parseColor("#E50914"))
        }

        // Cache track width
        cinemaProgressBackground?.let { bg ->
            cinemaProgressTrackWidth = bg.width
        }

        updateCinemaProgressUI()
    }

    private fun exitCinemaSeekMode(confirm: Boolean) {
        if (!cinemaSeekMode) return

        cinemaSeekMode = false

        // Cancel any running progress animation
        cinemaProgressAnimator?.cancel()

        // Hide thumb with smooth exit animation
        cinemaProgressThumb?.let { thumb ->
            thumb.animate()
                .alpha(0f)
                .scaleX(0.3f)
                .scaleY(0.3f)
                .setDuration(150)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction {
                    thumb.visibility = View.INVISIBLE
                    thumb.scaleX = 1f
                    thumb.scaleY = 1f
                }
                .start()
        }

        if (host.ottSkinInstalled) {
            host.controlsDockController.setOttTrackHeight(focused = false)
            ottScrubPreviewChip?.visibility = View.GONE
        } else {
            // Fade current time color back to white
            debrifyTimeCurrent?.setTextColor(Color.WHITE)
        }

        val shouldResume = cinemaSeekWasPlaying
        cinemaSeekWasPlaying = false
        if (shouldResume) host.player?.play()
    }

    private fun confirmCinemaSeek() {
        if (!cinemaSeekMode || host.player == null) return
        host.releaseResumeHold()  // viewer owns the position now
        host.player?.seekTo(seekbarPosition)
        exitCinemaSeekMode(confirm = true)
        controls.pauseButton?.requestFocus()
    }

    private fun updateCinemaSeekSpeed(stepMs: Long) {
        currentSeekSpeed = stepMs / 10_000f  // Base is 10s = 1x
        // Speed indicator removed for cleaner UI - speed still affects seeking behavior
    }

    private fun updateCinemaProgressUI() {
        // Update time display
        debrifyTimeCurrent?.text = formatTime(seekbarPosition)
        debrifyTimeTotal?.text = if (host.ottSkinInstalled) {
            // The OTT bar mirrors the Flutter dock: remaining, not total.
            "-" + formatTime((videoDuration - seekbarPosition).coerceAtLeast(0))
        } else {
            formatTime(videoDuration)
        }

        if (host.ottSkinInstalled && cinemaSeekMode) {
            // Cinema-scrub preview chip: "H:MM:SS   ·   ±delta" against the
            // real (paused) playhead, U+2212 for the minus like the Flutter
            // chip — tv_controls.dart:718-741. Focusing the bar enters
            // cinemaSeekMode before any step, so the chip waits for a real
            // delta; once up, a scrub back through ±0:00 keeps it.
            val origin = host.player?.currentPosition ?: seekbarPosition
            val delta = seekbarPosition - origin
            if (delta != 0L || ottScrubPreviewChip?.visibility == View.VISIBLE) {
                val sign = if (delta < 0) "−" else "+"
                ottScrubPreviewText?.text =
                    "${formatTime(seekbarPosition)}   ·   $sign${formatTime(kotlin.math.abs(delta))}"
                ottScrubPreviewChip?.visibility = View.VISIBLE
            }
        }

        val targetProgress = if (videoDuration > 0) {
            seekbarPosition.toFloat() / videoDuration.toFloat()
        } else 0f

        val parentWidth = cinemaProgressTrackWidth
        if (parentWidth <= 0) return

        // Cancel any running animation
        cinemaProgressAnimator?.cancel()

        // Animate from current to target position
        cinemaProgressAnimator = ValueAnimator.ofFloat(cinemaLastAnimatedProgress, targetProgress).apply {
            duration = 80  // Quick but smooth
            interpolator = DecelerateInterpolator()
            addUpdateListener { animator ->
                val animatedProgress = animator.animatedValue as Float

                // Update progress bar width
                debrifyProgressLine?.let { progressLine ->
                    val progressWidth = (parentWidth * animatedProgress).toInt()
                    val layoutParams = progressLine.layoutParams
                    layoutParams.width = progressWidth
                    progressLine.layoutParams = layoutParams
                }

                // Update thumb position with smooth glide
                cinemaProgressThumb?.let { thumb ->
                    val thumbOffset = (parentWidth * animatedProgress) - (thumb.width / 2f)
                    thumb.translationX = thumbOffset.coerceAtLeast(0f)
                }
            }
            start()
        }

        cinemaLastAnimatedProgress = targetProgress
    }

    // Seekbar (Legacy - kept for compatibility)
    private fun showSeekbar() {
        if (seekbarVisible || host.player == null) return

        seekbarPosition = host.player?.currentPosition ?: 0
        videoDuration = host.player?.duration ?: 0

        if (videoDuration <= 0) {
            Toast.makeText(activity, "Seeking not available", Toast.LENGTH_SHORT).show()
            return
        }

        val wasPlaying = host.player?.isPlaying == true
        if (wasPlaying) {
            host.player?.pause()
        }

        // Reset cached values
        seekbarBackgroundWidth = 0
        currentSeekSpeed = 1.0f
        host.seekbarSpeedIndicator.visibility = View.GONE

        updateSeekbarUI()

        seekbarVisible = true
        host.seekbarOverlay.visibility = View.VISIBLE
        host.seekbarOverlay.alpha = 0f
        host.seekbarOverlay.animate()
            .alpha(1f)
            .setDuration(200)
            .start()
    }

    fun hideSeekbar() {
        if (!seekbarVisible) return

        seekbarVisible = false
        host.seekbarSpeedIndicator.visibility = View.GONE
        host.seekbarOverlay.animate()
            .alpha(0f)
            .setDuration(150)
            .withEndAction {
                host.seekbarOverlay.visibility = View.GONE
                host.player?.play()
            }
            .start()
    }

    fun confirmSeekPosition() {
        if (!seekbarVisible || host.player == null) return
        host.releaseResumeHold()  // viewer owns the position now
        host.player?.seekTo(seekbarPosition)
        hideSeekbar()
    }

    fun seekBackward(stepMs: Long = 10_000L, isContinuous: Boolean = false) {
        seekbarPosition = (seekbarPosition - stepMs).coerceAtLeast(0)
        updateSeekSpeed(stepMs)
        updateSeekbarUI()

        // NO visual feedback - this is only called when seekbar is visible (long-press mode)
        // Visual feedback should only appear for quick single presses (handled in seekBy method)
    }

    fun seekForward(stepMs: Long = 10_000L, isContinuous: Boolean = false) {
        seekbarPosition = (seekbarPosition + stepMs).coerceAtMost(videoDuration)
        updateSeekSpeed(stepMs)
        updateSeekbarUI()

        // NO visual feedback - this is only called when seekbar is visible (long-press mode)
        // Visual feedback should only appear for quick single presses (handled in seekBy method)
    }

    private fun updateSeekSpeed(stepMs: Long) {
        currentSeekSpeed = stepMs / 10_000f  // Base is 10s = 1x

        if (currentSeekSpeed > 1.0f) {
            host.seekbarSpeedIndicator.text = String.format("→ %.1fx", currentSeekSpeed)
            host.seekbarSpeedIndicator.visibility = View.VISIBLE
        } else {
            host.seekbarSpeedIndicator.visibility = View.GONE
        }
    }

    private fun updateSeekbarUI() {
        host.seekbarCurrentTime.text = formatTime(seekbarPosition)
        host.seekbarTotalTime.text = formatTime(videoDuration)

        val progressPercent = if (videoDuration > 0) {
            seekbarPosition.toFloat() / videoDuration.toFloat()
        } else 0f

        // Cache the background width on first use
        val seekbarBackground = activity.findViewById<View>(R.id.seekbar_background)
        if (seekbarBackgroundWidth == 0 && seekbarBackground != null) {
            seekbarBackground.post {
                seekbarBackgroundWidth = seekbarBackground.width
                updateSeekbarPosition(progressPercent)
            }
        } else {
            updateSeekbarPosition(progressPercent)
        }
    }

    private fun updateSeekbarPosition(progressPercent: Float) {
        if (seekbarBackgroundWidth <= 0) return

        val progressWidth = (seekbarBackgroundWidth * progressPercent).toInt()

        // Update progress bar width
        val progressParams = host.seekbarProgress.layoutParams
        progressParams.width = progressWidth
        host.seekbarProgress.layoutParams = progressParams

        // Smoothly animate handle position
        val handleSize = host.seekbarHandle.width
        val handleX = progressWidth - (handleSize / 2f)
        host.seekbarHandle.animate()
            .translationX(handleX)
            .setDuration(0)  // Instant for responsiveness
            .start()
    }

    fun seekBy(offsetMs: Long) {
        val p = host.player ?: return
        val position = p.currentPosition
        val duration = p.duration
        var target = position + offsetMs
        if (duration != C.TIME_UNSET) {
            target = target.coerceIn(0L, duration)
        } else {
            target = target.coerceAtLeast(0L)
        }
        host.releaseResumeHold()  // viewer owns the position now
        p.seekTo(target)

        // Show visual feedback for quick seek
        val seekSeconds = kotlin.math.abs(offsetMs / 1000).toString() + "s"
        if (offsetMs > 0) {
            host.seekFeedbackManager.showSeekForward(seekSeconds)
        } else {
            host.seekFeedbackManager.showSeekBackward(seekSeconds)
        }
    }
}
