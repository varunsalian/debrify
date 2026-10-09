package com.debrify.app.tv

import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.debrify.app.R
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.cancel
import java.util.Locale

@OptIn(UnstableApi::class)
internal class TvControlsOverlayController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val channelBadge: TextView
        val controlsDockController: TvControlsDockController
        val controlsSkin: TvControlsSkin
        val currentIndex: Int
        val currentIptvIndex: Int
        val dockSkinSpec: DockSkinSpec?
        val iptvChannels: List<IptvChannelEntry>
        val iptvGuideController: TvIptvGuideController
        val iptvLiveRecovery: IptvLiveRecovery
        val iptvZapBannerController: TvIptvZapBannerController
        val isIptvMode: Boolean
        var lastRealPositionMs: Long
        val linePickerOverlay: SubtitleLinePickerController?
        var maxStableDurationMs: Long
        val nextBackdrop: android.widget.ImageView
        val nextBackdropReady: Boolean
        val nextOverlay: View
        val nextSubtext: TextView
        val nextText: TextView
        val ottEpisodeBadge: TextView
        val ottEpisodeTitle: TextView
        val ottRating: TextView
        val ottRatingContainer: View
        val ottSkinInstalled: Boolean
        val payload: PlaybackPayload?
        val pikPakReactivationIndicator: View
        val player: ExoPlayer?
        val playerView: PlayerView
        val playlistController: TvPlaylistOverlayController
        fun releaseResumeHold(): Unit
        fun restoreParkedIptvTwinIfNeeded(): Boolean
        val seekFeedbackManager: SeekFeedbackManager
        val seekbarCurrentTime: TextView
        val seekbarHandle: View
        val seekbarOverlay: View
        val seekbarProgress: View
        val seekbarSpeedIndicator: TextView
        val seekbarTotalTime: TextView
        val skipSegmentController: TvSkipSegmentController
        var sleepStopLatched: Boolean
        val sourceBrowser: TvSourceBrowserController?
        val sourceSwitchController: TvSourceSwitchController
        val startupGateView: View
        val startupGateViewReady: Boolean
        val stremioSourceBadge: View?
        val stremioSources: List<StremioSource>
        val stremioTvGuideController: TvStremioTvGuideController
        val subtitleControlsLift: SubtitleControlsLiftController
        val subtitlePanel: SubtitlePanelController?
        val syncOverlay: SubtitleSyncOverlayController?
        val titleContainer: View
        val titleOttContainer: View
        val titleView: TextView
        val unifiedMenu: UnifiedMenuController?
    }

    // Controls
    internal var controlsOverlay: View? = null
    internal var pauseButton: AppCompatButton? = null
    internal var controlsMenuVisible = false
    internal val controlsHandler = Handler(Looper.getMainLooper())

    private val hideControlsRunnable = Runnable {
        if (!isFocusInControlsOverlay()) {
            hideControlsMenu()
        } else {
            scheduleHideControlsMenu()
        }
    }
    internal val identity = TvDockIdentityPresenter(host)
    internal val seek = TvSeekScrubController(activity, host, this)

    fun setResolvingState(resolving: Boolean) {
        if (resolving) {
            host.nextText.text = "" // Title is filled in once the stream resolves
            host.nextSubtext.visibility = View.GONE
            fadeInNextOverlay()
        } else {
            hideNextOverlay()
            setNextOverlayBackdrop(null)
        }
    }

    // Loads dimmed backdrop art behind the loading/tuning overlay, or clears it.
    private fun setNextOverlayBackdrop(artworkUrl: String?) {
        if (!host.nextBackdropReady) return
        // Glide.with(activity) throws once the activity is destroyed; the
        // loading overlay is torn down from async MethodChannel callbacks that
        // can resolve after onDestroy, so bail out defensively.
        if (activity.isFinishing || activity.isDestroyed) return
        if (!artworkUrl.isNullOrEmpty()) {
            host.nextBackdrop.visibility = View.VISIBLE
            com.bumptech.glide.Glide.with(activity).load(artworkUrl).into(host.nextBackdrop)
        } else {
            com.bumptech.glide.Glide.with(activity).clear(host.nextBackdrop)
            host.nextBackdrop.setImageDrawable(null)
            host.nextBackdrop.visibility = View.GONE
        }
    }

    fun isFocusInControlsOverlay(): Boolean {
        val overlay = controlsOverlay ?: return false
        var current = activity.currentFocus
        while (current != null) {
            if (current == overlay) return true
            val parent = current.parent
            current = if (parent is View) parent else null
        }
        return false
    }

    fun handlePlayPauseToggleFromCenter() {
        showControlsMenu()
        togglePlayPause()
        if (host.player?.isPlaying == true) {
            scheduleHideControlsMenu()
        }
    }

    fun togglePlayPause() {
        host.player?.let {
            if (it.isPlaying) {
                it.pause()
            } else {
                // An explicit press is the one thing that clears a sleep stop.
                host.sleepStopLatched = false
                // A verdict timeout or onStop may have parked the original
                // HLS while leaving the paused twin media item installed.
                // Resolve that identity before ordinary play/userRetry logic.
                if (host.restoreParkedIptvTwinIfNeeded()) return@let
                // LIVE: play on a dead stream must re-tune to the live edge.
                // A bare play() on an ENDED/errored live stream either does
                // nothing (media3 leaves it parked) or replays stale bytes —
                // both read as "the app is broken". The machine treats the
                // press as a fresh user ask: budget reset, immediate attempt.
                val deadLive = host.isIptvMode &&
                    host.iptvChannels.getOrNull(host.currentIptvIndex)?.isLive == true &&
                    (it.playbackState == Player.STATE_ENDED ||
                        it.playerError != null ||
                        host.iptvLiveRecovery.isSurrendered)
                if (deadLive) {
                    it.playWhenReady = true // eligibility reads this
                    host.iptvLiveRecovery.userRetry("play-press")
                } else {
                    it.play()
                }
            }
        }
        updatePauseButtonLabel()
    }

    fun showControlsMenu() {
        val overlay = controlsOverlay ?: return
        cancelScheduledHideControlsMenu()

        // The previous menu may have disappeared via Media3's parent-controller
        // timeout rather than our child dock animation.
        host.playerView.showController()

        // The channel panel and the dock share the bottom strip, so they merge
        // into one surface: the panel rides flush on top of the dock for as
        // long as it is open. Non-live playback has no panel to merge.
        val liveEntry = host.iptvChannels.getOrNull(host.currentIptvIndex)?.takeIf { it.isLive }
        if (liveEntry != null) {
            host.iptvZapBannerController.showIptvZapBanner(liveEntry, docked = true)
        } else {
            host.iptvZapBannerController.hideIptvZapBanner()
        }

        // The title and controls are one presentation state: metadata updates
        // may change the text, but only this method is allowed to reveal it.
        host.titleContainer.animate().cancel()

        // Switch to OTT mode if we have series metadata, otherwise keep simple mode
        val model = host.payload
        val currentItem = model?.items?.getOrNull(host.currentIndex)
        val hasSeriesMetadata = model?.contentType?.lowercase(java.util.Locale.US) == "series" &&
                               currentItem?.season != null && currentItem.episode != null

        if (host.ottSkinInstalled) {
            // The OTT dock carries its own identity row, mirroring the Flutter
            // dock — the top-of-screen title stays hidden entirely.
            host.titleContainer.visibility = View.GONE
            identity.updateOttIdentity()
        } else {
            if (hasSeriesMetadata) {
                host.titleView.visibility = View.GONE
                host.titleOttContainer.visibility = View.VISIBLE
            } else {
                host.titleView.visibility = View.VISIBLE
                host.titleOttContainer.visibility = View.GONE
            }

            if (host.titleView.text?.isNotEmpty() == true || hasSeriesMetadata) {
                host.titleContainer.visibility = View.VISIBLE
                host.titleContainer.alpha = 1f
            }
        }

        // The source badge shares the top-right safe area with startup
        // validation. Keep the progress pill unobscured until the candidate is
        // committed; if controls remain open, commitStartupCandidate restores
        // the badge as soon as the gate drops.
        if (host.startupGateViewReady &&
            host.startupGateView.visibility == View.VISIBLE
        ) {
            host.sourceSwitchController.hideStremioSourceBadgeImmediately()
        } else {
            host.sourceSwitchController.showStremioSourceBadge()
        }

        overlay.animate().cancel()

        if (!controlsMenuVisible) {
            controlsMenuVisible = true
            overlay.visibility = View.VISIBLE
            overlay.alpha = 0f
            overlay.translationY = 30f  // Start slightly below for Apple TV effect
            overlay.animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(300)
                .setInterpolator(android.view.animation.DecelerateInterpolator(1.5f))
                .withEndAction {
                    overlay.alpha = 1f
                    overlay.translationY = 0f
                }
                .start()
            pauseButton?.post {
                pauseButton?.requestFocus()
            }
        } else {
            overlay.alpha = 1f
            overlay.translationY = 0f
            overlay.visibility = View.VISIBLE
            pauseButton?.post {
                pauseButton?.requestFocus()
            }
        }
        updatePauseButtonLabel()
        updateSubtitleControlsLift()
    }

    fun hideControlsMenu() {
        val overlay = controlsOverlay ?: return

        // The merged panel leaves with the dock it was riding on. A floating
        // banner (raised by a zap) is left alone to finish its own timeout.
        if (host.iptvZapBannerController.iptvZapBannerDocked) host.iptvZapBannerController.hideIptvZapBanner()

        overlay.animate().cancel()

        if (!controlsMenuVisible) {
            overlay.visibility = View.GONE
            overlay.alpha = 0f
            overlay.translationY = 0f
            hideTitleImmediately()
            host.sourceSwitchController.hideStremioSourceBadge()
            cancelScheduledHideControlsMenu()
            return
        }

        cancelScheduledHideControlsMenu()
        controlsMenuVisible = false
        host.subtitleControlsLift.restore()

        // Hide title and revert to simple mode when controls hide
        host.titleContainer.animate()
            .alpha(0f)
            .setDuration(250)
            .withEndAction {
                host.titleContainer.visibility = View.GONE
                // Revert to simple mode for the next controls reveal.
                host.titleView.visibility = View.VISIBLE
                host.titleOttContainer.visibility = View.GONE
            }
            .start()

        // Hide Stremio source quality badge
        host.sourceSwitchController.hideStremioSourceBadge()

        overlay.animate()
            .alpha(0f)
            .translationY(20f)  // Slide down slightly for premium effect
            .setDuration(250)
            .setInterpolator(android.view.animation.AccelerateInterpolator(1.2f))
            .withEndAction {
                if (!controlsMenuVisible) {
                    overlay.visibility = View.GONE
                    overlay.alpha = 0f
                    overlay.translationY = 0f
                }
            }
            .start()
    }

    /** Re-measure after layout because each controls skin occupies a different height. */
    fun updateSubtitleControlsLift() {
        if (!controlsMenuVisible) return
        val dock = controlsOverlay ?: return
        val extraPanelHeight = host.iptvZapBannerController.iptvZapBanner
            ?.takeIf { host.iptvZapBannerController.iptvZapBannerDocked && it.visibility == View.VISIBLE }
            ?.height ?: 0
        host.subtitleControlsLift.liftAbove(dock.height + extraPanelHeight)
        dock.post {
            if (!controlsMenuVisible) return@post
            val laidOutExtra = host.iptvZapBannerController.iptvZapBanner
                ?.takeIf { host.iptvZapBannerController.iptvZapBannerDocked && it.visibility == View.VISIBLE }
                ?.height ?: 0
            host.subtitleControlsLift.liftAbove(dock.height + laidOutExtra)
        }
    }

    private fun hideTitleImmediately() {
        host.titleContainer.animate().cancel()
        host.titleContainer.visibility = View.GONE
        host.titleContainer.alpha = 0f
        // Reset the presentation mode for the next controls reveal.
        host.titleView.visibility = View.VISIBLE
        host.titleOttContainer.visibility = View.GONE
    }

    fun scheduleHideControlsMenu() {
        if (!controlsMenuVisible) return
        controlsHandler.removeCallbacks(hideControlsRunnable)
        if (host.player?.isPlaying == true) {
            controlsHandler.postDelayed(hideControlsRunnable, CONTROLS_AUTO_HIDE_DELAY_MS)
        }
    }

    fun cancelScheduledHideControlsMenu() {
        controlsHandler.removeCallbacks(hideControlsRunnable)
    }

    fun updatePauseButtonLabel() {
        val button = pauseButton ?: return
        val playing = host.player?.isPlaying == true
        button.text = if (playing) "Pause" else "Play"
        // Each dock skin swaps within its own icon family; classic keeps the
        // legacy pair.
        val spec = host.dockSkinSpec.takeIf { host.ottSkinInstalled }
        val iconRes = if (playing) {
            spec?.pauseIconRes ?: R.drawable.ic_pause
        } else {
            spec?.playIconRes ?: R.drawable.ic_play
        }
        button.setCompoundDrawablesRelativeWithIntrinsicBounds(iconRes, 0, 0, 0)
        host.controlsDockController.refreshOttCaptionFor(button)
    }

    // Next overlay
    fun showNextOverlay(nextItem: PlaybackItem) {
        host.nextText.text = nextItem.title
        host.nextSubtext.visibility = View.GONE
        fadeInNextOverlay()
    }

    fun fadeInNextOverlay() {
        host.nextOverlay.animate().cancel()
        host.nextOverlay.alpha = 0f
        host.nextOverlay.visibility = View.VISIBLE
        host.nextOverlay.animate().alpha(1f).setDuration(220).start()
    }

    fun hideNextOverlay() {
        if (host.nextOverlay.visibility != View.VISIBLE) return
        host.nextOverlay.animate().cancel()
        host.nextOverlay.animate().alpha(0f).setDuration(160).withEndAction {
            host.nextOverlay.visibility = View.GONE
            host.nextOverlay.alpha = 1f
        }.start()
    }

    // ═══════════════════════════════════════════════════════════════
    // UP NEXT CARD
    // ═══════════════════════════════════════════════════════════════

    // True only during plain playback (no overlay/panel/controls on screen).
    fun isCleanPlaybackState(): Boolean {
        if (controlsMenuVisible || seek.seekbarVisible || host.playlistController.playlistVisible) return false
        if (host.iptvGuideController.iptvGuideVisible || host.stremioTvGuideController.stremioTvGuideVisible) return false
        if (host.subtitlePanel?.isVisible == true) return false
        if (host.linePickerOverlay?.isVisible == true || host.syncOverlay?.isVisible == true) return false
        if (host.unifiedMenu?.isVisible == true) return false
        if (host.sourceBrowser?.isVisible == true) return false
        if (host.nextOverlay.visibility == View.VISIBLE) return false
        if (host.pikPakReactivationIndicator.visibility == View.VISIBLE) return false
        return true
    }
}
        private const val CONTROLS_AUTO_HIDE_DELAY_MS = 4000L
