package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
        private const val PIKPAK_MAX_RETRIES = 5
        private const val PIKPAK_METADATA_TIMEOUT_MS = 10000  // 10 seconds to wait for metadata
        private const val PIKPAK_BASE_DELAY_MS = 2000  // 2 seconds base delay
        private const val PIKPAK_MAX_DELAY_MS = 18000  // 18 seconds max delay

@OptIn(UnstableApi::class)
internal class TvPikPakRetryController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        fun failShufflePlayback(): Boolean
        val isStremioTvMode: Boolean
        val pikPakReactivationIndicator: View
        val pikPakReactivationIndicatorReady: Boolean
        val pikPakReactivationText: TextView
        fun playNext(): Unit
        val player: ExoPlayer?
        val startupGateController: TvStartupGateController
        val startupGateStatus: TextView
        val startupGateStatusReady: Boolean
        fun tryAutoSelectAddonSubtitle(): Unit
    }

    // PikPak cold storage retry state
    internal var isPikPakRetrying: Boolean = false
    internal var pikPakRetryCount: Int = 0
    internal var pikPakRetryId: Int = 0
    internal val pikPakRetryHandler = Handler(Looper.getMainLooper())

    internal fun attemptPikPakPlaybackLoop(item: PlaybackItem, attemptNumber: Int, retryId: Int) {
        // Check if this retry has been cancelled
        if (pikPakRetryId != retryId) {
            android.util.Log.d("AndroidTvPlayer", "PikPak: Retry cancelled (token mismatch)")
            isPikPakRetrying = false
            pikPakRetryCount = 0
            hidePikPakRetryOverlay()
            return
        }

        // Null safety check for player
        if (host.player == null) {
            android.util.Log.e("AndroidTvPlayer", "PikPak: Player is null, cannot continue playback")
            isPikPakRetrying = false
            pikPakRetryCount = 0
            hidePikPakRetryOverlay()
            return
        }

        android.util.Log.d("AndroidTvPlayer", "PikPak: Playback attempt ${attemptNumber + 1}/${PIKPAK_MAX_RETRIES + 1}")

        // Calculate delay for this attempt (0 for first attempt, exponential backoff for subsequent)
        val delayMs = if (attemptNumber == 0) {
            0L
        } else {
            val calculatedDelay = PIKPAK_BASE_DELAY_MS * (1 shl (attemptNumber - 1))
            calculatedDelay.toLong().coerceAtMost(PIKPAK_MAX_DELAY_MS.toLong())
        }

        // Monitor during BOTH the timeout period AND the delay period
        waitForPikPakMetadata(item, attemptNumber, retryId, additionalMonitoringMs = delayMs) { success ->
            // Check if retry was cancelled during monitoring
            if (pikPakRetryId != retryId) {
                android.util.Log.d("AndroidTvPlayer", "PikPak: Retry cancelled during monitoring")
                return@waitForPikPakMetadata
            }

            if (success) {
                // Video loaded successfully, exit retry loop
                android.util.Log.d("AndroidTvPlayer", "PikPak: Video loaded successfully, exiting retry loop")
                return@waitForPikPakMetadata
            }

            // Check if this was the last attempt
            if (attemptNumber >= PIKPAK_MAX_RETRIES) {
                // All retries exhausted
                android.util.Log.e("AndroidTvPlayer", "PikPak: All retry attempts exhausted. Video failed to load.")
                host.startupGateController.cancelPikPakGateReprepare()

                // Clear state synchronously
                isPikPakRetrying = false
                pikPakRetryCount = 0
                hidePikPakRetryOverlay()

                // A validation gate deferred its error/timeout handling to
                // this engine — exhaustion is the engine's verdict, so hand
                // the failure back to the gate (manual pick restores the
                // previous source; startup advances the failover cursor)
                // instead of skipping to the next playlist item.
                if (host.failShufflePlayback()) return@waitForPikPakMetadata
                if (host.startupGateController.failManualSourceCandidate("pikpak-exhausted")) {
                    return@waitForPikPakMetadata
                }
                if (host.startupGateController.startupFailoverCursor?.committed == false) {
                    host.startupGateController.failStartupCandidate("pikpak-exhausted")
                    return@waitForPikPakMetadata
                }

                if (!activity.isFinishing) {
                    activity.runOnUiThread {
                        Toast.makeText(activity, "Video failed to load. Skipping to next...", Toast.LENGTH_SHORT).show()

                        // Auto-advance to next video
                        pikPakRetryHandler.postDelayed({
                            host.playNext()
                        }, 1500)
                    }
                }
                return@waitForPikPakMetadata
            }

            // Video didn't load, need to retry
            // Update retry UI
            pikPakRetryCount = attemptNumber + 1
            isPikPakRetrying = true
            if (!activity.isFinishing) {
                showPikPakRetryOverlay("Reactivating video... (Attempt ${attemptNumber + 2}/${PIKPAK_MAX_RETRIES + 1})")
            }

            android.util.Log.d("AndroidTvPlayer", "PikPak: Video didn't load, monitoring for next attempt")

            // Continue to next attempt
            attemptPikPakPlaybackLoop(item, attemptNumber + 1, retryId)
        }
    }

    fun waitForPikPakMetadata(
        item: PlaybackItem,
        attemptNumber: Int,
        retryId: Int,
        additionalMonitoringMs: Long = 0,
        onComplete: (Boolean) -> Unit
    ) {
        val startTime = System.currentTimeMillis()
        val totalTimeoutMs = PIKPAK_METADATA_TIMEOUT_MS + additionalMonitoringMs
        val checkHandler = Handler(Looper.getMainLooper())

        val checkRunnable = object : Runnable {
            override fun run() {
                // Check if retry was cancelled
                if (pikPakRetryId != retryId) {
                    android.util.Log.d("AndroidTvPlayer", "PikPak: Metadata check cancelled")
                    checkHandler.removeCallbacks(this)
                    onComplete(false)
                    return
                }

                val elapsed = System.currentTimeMillis() - startTime

                // Check if player state is ready or has duration (with null safety)
                val currentPlayer = host.player
                if (currentPlayer != null && (currentPlayer.playbackState == Player.STATE_READY || currentPlayer.duration > 0)) {
                    android.util.Log.d("AndroidTvPlayer", "PikPak: Video metadata loaded successfully - file is ready!")
                    host.startupGateController.cancelPikPakGateReprepare()

                    // CRITICAL FIX: Clear retry state IMMEDIATELY when video loads
                    // This prevents race conditions and ensures UI updates instantly
                    isPikPakRetrying = false
                    pikPakRetryCount = 0
                    hidePikPakRetryOverlay()

                    // Clean up handler callbacks
                    checkHandler.removeCallbacks(this)

                    // Ensure subtitles are selected after successful load
                    host.tryAutoSelectAddonSubtitle()

                    onComplete(true)
                    return
                }

                // Check timeout (now includes additional monitoring period)
                if (elapsed >= totalTimeoutMs) {
                    android.util.Log.d("AndroidTvPlayer", "PikPak: Timeout waiting for metadata after ${totalTimeoutMs}ms - file likely in cold storage")
                    checkHandler.removeCallbacks(this)
                    onComplete(false)
                    return
                }

                // Stremio TV has no VOD startup gate. A cold-storage error
                // still needs a new request; polling an IDLE player alone
                // cannot make the file ready. Keep the retry engine's bound.
                if (host.isStremioTvMode && currentPlayer?.playerError != null) {
                    host.startupGateController.schedulePikPakGateReprepare(retryId)
                }

                // Continue checking
                checkHandler.postDelayed(this, 500)
            }
        }

        // Start checking
        checkHandler.postDelayed(checkRunnable, 500)
    }


    private fun showPikPakRetryOverlay(message: String) {
        activity.runOnUiThread {
            if (activity.isFinishing || activity.isDestroyed) return@runOnUiThread
            // During startup validation the opaque gate covers this overlay —
            // mirror the message so the user isn't stuck on "Checking stream…"
            // for the whole cold-storage warmup.
            if (host.startupGateStatusReady &&
                host.startupGateController.startupFailoverCursor?.committed == false
            ) {
                host.startupGateStatus.text = message
            }
            host.pikPakReactivationText.text = message
            host.pikPakReactivationIndicator.animate().cancel()
            host.pikPakReactivationIndicator.visibility = View.VISIBLE
            host.pikPakReactivationIndicator.animate().alpha(1f).setDuration(250).start()
        }
    }

    internal fun hidePikPakRetryOverlay() {
        activity.runOnUiThread {
            if (activity.isFinishing || activity.isDestroyed || !host.pikPakReactivationIndicatorReady) return@runOnUiThread
            host.pikPakReactivationIndicator.animate().cancel()
            host.pikPakReactivationIndicator.alpha = 0f
            host.pikPakReactivationIndicator.visibility = View.GONE
        }
    }

    fun cancelPikPakRetry() {
        // Increment retry ID to invalidate any ongoing retry operations
        pikPakRetryId++
        isPikPakRetrying = false
        pikPakRetryCount = 0
        host.startupGateController.cancelPikPakGateReprepare()

        // Remove any pending retry callbacks
        pikPakRetryHandler.removeCallbacksAndMessages(null)

        // Hide overlay
        hidePikPakRetryOverlay()
    }
}
