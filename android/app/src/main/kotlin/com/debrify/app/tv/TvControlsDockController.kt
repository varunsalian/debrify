package com.debrify.app.tv

import android.graphics.LinearGradient
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.PaintDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RectShape
import android.view.LayoutInflater
import android.view.animation.DecelerateInterpolator
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.debrify.app.R
import kotlinx.coroutines.cancel

@OptIn(UnstableApi::class)
internal class TvControlsDockController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        fun cancelScheduledHideControlsMenu(): Unit
        var cinemaProgressBackground: View?
        var cinemaProgressBuffered: View?
        var cinemaProgressContainer: View?
        var cinemaProgressThumb: View?
        var cinemaSeekMode: Boolean
        var cinemaSeekWasPlaying: Boolean
        var cinemaSpeedIndicator: TextView?
        val controlsMenuVisible: Boolean
        var controlsOverlay: View?
        val currentIptvIndex: Int
        var debrifyProgressLine: View?
        var debrifyTimeCurrent: TextView?
        var debrifyTimeDisplay: TextView?
        var debrifyTimeTotal: TextView?
        val displayController: TvPlaybackDisplayController
        val dockSkinSpec: DockSkinSpec?
        fun dp(value: Int): Int
        val guideStyle: GuideStyle
        val guideTokens: GuideTokens?
        fun guideTypeface(file: String?): Typeface?
        fun hideControlsMenu(): Unit
        val iptvChannels: List<IptvChannelEntry>
        val iptvGuideChromeController: TvIptvGuideChromeController
        val iptvGuideController: TvIptvGuideController
        val iptvRecordingActionsController: TvIptvRecordingActionsController
        val iptvStartOverActive: Boolean
        val iptvStartOverController: TvIptvStartOverController
        val iptvStartOverTimelineVisible: Boolean
        val isIptvMode: Boolean
        var ottIdentityBadge: TextView?
        var ottIdentityDivider: View?
        var ottIdentityOverline: TextView?
        var ottIdentitySubtitle: TextView?
        var ottIdentityTitle: TextView?
        var ottMetaLine: TextView?
        val ottQualityChips: Array<TextView?>
        var ottRatingChip: TextView?
        var ottScrubPreviewChip: View?
        var ottScrubPreviewText: TextView?
        var ottSkinInstalled: Boolean
        var pauseButton: AppCompatButton?
        fun playNext(): Unit
        fun playPrevious(): Unit
        val player: ExoPlayer?
        val playerView: PlayerView
        val playlistController: TvPlaylistOverlayController
        fun scheduleHideControlsMenu(): Unit
        fun seekBy(offsetMs: Long): Unit
        fun setupCinemaProgressBar(): Unit
        fun showRandomPlaybackDialog(): Unit
        val sourceBrowser: TvSourceBrowserController?
        fun startSeekbarProgressUpdates(): Unit
        val subtitleController: TvSubtitleController
        val subtitleControlsLift: SubtitleControlsLiftController
        fun togglePlayPause(): Unit
        val unifiedMenu: UnifiedMenuController?
        fun updateCatalogEpisodeControls(): Unit
    }
    internal val styler = TvLiveDockStyler(activity, host, this)
    internal var iptvPrevButton: AppCompatButton? = null
    internal var iptvNextButton: AppCompatButton? = null
    internal var iptvGuideButton: AppCompatButton? = null
    internal var iptvJumpButton: AppCompatButton? = null
    internal var iptvStartOverButton: AppCompatButton? = null
    internal var iptvStartOverSeekButton: AppCompatButton? = null
    internal var iptvRecordButton: AppCompatButton? = null
    internal var originalControlDockOrder: List<View> = emptyList()
    internal var audioButton: AppCompatButton? = null
    internal var subtitleButton: AppCompatButton? = null
    internal var aspectButton: AppCompatButton? = null
    internal var speedButton: AppCompatButton? = null
    internal var nightModeButton: AppCompatButton? = null
    private var ottCaptionLabel: TextView? = null
    private var ottCaptionOwner: View? = null
    private var ottProgressTrackContainer: View? = null

    /** In-dock Sources button; replaces the top-right stremio_source_badge
     *  under the OTT skin (the badge stays permanently hidden there). */
    internal var ottSourcesButton: AppCompatButton? = null

    /** Swaps the legacy Cinema controller layout for the selected dock skin.
     *
     * Media3 inflates `controller_layout_id` INTO its PlayerControlView with
     * attachToRoot, so the legacy root is an ordinary child we can replace at
     * the same index. Every dock layout shares every id the activity binds,
     * and the activity (not Media3) drives `debrify_controls_root` visibility,
     * so all downstream code works against whichever root is installed. Must
     * run before ANY controller-id findViewById — setupControls calls it first.
     */
    private fun installOttControlsSkin() {
        val spec = host.dockSkinSpec ?: return
        val legacy = host.playerView.findViewById<View>(R.id.debrify_controls_root) ?: return
        val parent = legacy.parent as? ViewGroup ?: return
        val index = parent.indexOfChild(legacy)
        val ott = try {
            LayoutInflater.from(activity).inflate(spec.layoutRes, parent, false)
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Dock skin inflate failed; keeping classic", e)
            return
        }
        parent.removeViewAt(index)
        parent.addView(ott, index)
        host.ottSkinInstalled = true

        // The Flutter OTT scrim has FOUR stops; XML gradients cap at three, so
        // that one skin's placeholder background is replaced with the exact
        // ramp here. Every other skin's XML background is already final.
        if (spec.applyShaderScrim) {
            ott.findViewById<View>(R.id.ott_content)?.background = PaintDrawable().apply {
                shape = RectShape()
                shaderFactory = object : ShapeDrawable.ShaderFactory() {
                    override fun resize(width: Int, height: Int): Shader = LinearGradient(
                        0f, 0f, 0f, height.toFloat(),
                        intArrayOf(0x00000000, 0x66000000, 0xD9000000.toInt(), 0xF2000000.toInt()),
                        floatArrayOf(0f, 0.28f, 0.62f, 1f),
                        Shader.TileMode.CLAMP,
                    )
                }
            }
        }

        ottCaptionLabel = ott.findViewById(R.id.ott_caption_label)
        host.ottIdentityTitle = ott.findViewById(R.id.ott_identity_title)
        host.ottIdentitySubtitle = ott.findViewById(R.id.ott_identity_subtitle)
        host.ottIdentityOverline = ott.findViewById(R.id.ott_identity_overline)
        host.ottIdentityBadge = ott.findViewById(R.id.ott_identity_badge)
        host.ottIdentityDivider = ott.findViewById(R.id.ott_identity_divider)
        host.ottQualityChips[0] = ott.findViewById(R.id.ott_quality_1)
        host.ottQualityChips[1] = ott.findViewById(R.id.ott_quality_2)
        host.ottQualityChips[2] = ott.findViewById(R.id.ott_quality_3)
        host.ottRatingChip = ott.findViewById(R.id.ott_rating_chip)
        host.ottMetaLine = ott.findViewById(R.id.ott_meta_line)
        host.ottScrubPreviewChip = ott.findViewById(R.id.ott_scrub_preview_chip)
        host.ottScrubPreviewText = ott.findViewById(R.id.ott_scrub_preview_text)
        ottProgressTrackContainer = ott.findViewById(R.id.cinema_progress_track_container)

        // Idle bar height per spec; enter/exit cinema seek toggles it.
        setOttTrackHeight(focused = false)

        ott.findViewById<View>(R.id.ott_seek_back_button)?.setOnClickListener {
            host.seekBy(-10_000L)
            host.scheduleHideControlsMenu()
        }
        ott.findViewById<View>(R.id.ott_seek_forward_button)?.setOnClickListener {
            host.seekBy(10_000L)
            host.scheduleHideControlsMenu()
        }

        ottSourcesButton = ott.findViewById(R.id.ott_sources_button)
        // Same behaviour as the top-right badge this button replaces.
        ottSourcesButton?.setOnClickListener {
            host.hideControlsMenu()
            host.unifiedMenu?.hide()
            host.sourceBrowser?.show()
        }
    }

    fun setOttTrackHeight(focused: Boolean) {
        val track = ottProgressTrackContainer ?: return
        val spec = host.dockSkinSpec ?: return
        val heightPx = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            if (focused) spec.trackFocusDp else spec.trackIdleDp,
            activity.resources.displayMetrics,
        ).toInt()
        val params = track.layoutParams
        if (params.height != heightPx) {
            params.height = heightPx
            track.layoutParams = params
        }
    }

    /** The shared caption under the OTT transport row: the focused button's
     *  (transparent) text. Cleared only by its owner so the fade-out of an
     *  outgoing button never eats the incoming button's label. */
    private fun updateOttCaption(view: View) {
        val label = ottCaptionLabel ?: return
        val text = (view as? TextView)?.text?.takeIf { it.isNotEmpty() }
            ?: view.contentDescription
            ?: return
        ottCaptionOwner = view
        label.text = text
        label.animate().cancel()
        label.animate().alpha(1f).setDuration(120).start()
    }

    private fun clearOttCaption(view: View) {
        if (ottCaptionOwner !== view) return
        ottCaptionOwner = null
        ottCaptionLabel?.animate()?.cancel()
        ottCaptionLabel?.animate()?.alpha(0f)?.setDuration(120)?.start()
    }

    /** Re-push the caption after a runtime label write (Play->Pause, "1.5x")
     *  so a focused button's caption can't go stale. */
    fun refreshOttCaptionFor(view: View?) {
        if (!host.ottSkinInstalled || view == null || !view.isFocused) return
        updateOttCaption(view)
    }

    fun setupControls() {
        if (!host.isIptvMode && host.dockSkinSpec != null && !host.ottSkinInstalled) {
            installOttControlsSkin()
        }
        host.controlsOverlay = host.playerView.findViewById(R.id.debrify_controls_root)
        // Media3 owns the parent controller surface and can hide it on its own
        // timeout before our dock timer runs (for example while a dock button
        // retains focus). Reconcile that independent hide through the same
        // path as Back so the subtitle lift and the rest of our chrome state
        // cannot remain stranded on screen.
        host.playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                if (visibility != View.VISIBLE && host.controlsMenuVisible) {
                    host.hideControlsMenu()
                    // This callback fires from inside Media3's hide-animation end
                    // dispatch, where the restore animation kicked off by
                    // hideControlsMenu never lands — the subtitle view stays
                    // translated off-screen until the next lift call. Snap it
                    // back directly; a no-op when the animated restore worked.
                    host.subtitleControlsLift.restore(animate = false)
                }
            }
        )
        host.pauseButton = host.playerView.findViewById(R.id.debrify_pause_button)
        nightModeButton = host.playerView.findViewById(R.id.debrify_night_mode_button)
        audioButton = host.playerView.findViewById(R.id.debrify_audio_button)
        subtitleButton = host.playerView.findViewById(R.id.debrify_subtitle_button)
        aspectButton = host.playerView.findViewById(R.id.debrify_aspect_button)
        speedButton = host.playerView.findViewById(R.id.debrify_speed_button)
        val playlistButton: AppCompatButton? = host.playerView.findViewById(R.id.debrify_playlist_button)
        val nextButton: AppCompatButton? = host.playerView.findViewById(R.id.debrify_next_button)
        val prevButton: AppCompatButton? = host.playerView.findViewById(R.id.debrify_prev_button)
        val randomButton: AppCompatButton? = host.playerView.findViewById(R.id.debrify_random_button)
        iptvNextButton = nextButton
        iptvPrevButton = prevButton
        iptvGuideButton = playlistButton
        iptvJumpButton = host.playerView.findViewById(R.id.iptv_jump_channel_button)
        iptvStartOverButton = host.playerView.findViewById(R.id.iptv_start_over_button)
        iptvStartOverSeekButton =
            host.playerView.findViewById(R.id.iptv_start_over_seek_button)
        iptvRecordButton = host.playerView.findViewById(R.id.iptv_record_button)
        host.playerView.findViewById<LinearLayout>(R.id.debrify_controls_buttons)?.let { dock ->
            if (originalControlDockOrder.isEmpty()) {
                originalControlDockOrder =
                    List(dock.childCount) { index -> dock.getChildAt(index) }
            }
        }

        // Time display views (Cinema Mode)
        host.debrifyTimeDisplay = host.playerView.findViewById(R.id.debrify_time_display)  // Legacy (hidden)
        host.debrifyTimeCurrent = host.playerView.findViewById(R.id.debrify_time_current)  // Current time
        host.debrifyTimeTotal = host.playerView.findViewById(R.id.debrify_time_total)      // Total time
        host.debrifyProgressLine = host.playerView.findViewById(R.id.debrify_progress_line)
        host.cinemaProgressBuffered = host.playerView.findViewById(R.id.cinema_progress_buffered)

        // Cinema Mode Interactive Progress Bar
        host.cinemaProgressContainer = host.playerView.findViewById(R.id.cinema_progress_container)
        host.cinemaProgressBackground = host.playerView.findViewById(R.id.cinema_progress_background)
        host.cinemaProgressThumb = host.playerView.findViewById(R.id.cinema_progress_thumb)
        host.cinemaSpeedIndicator = host.playerView.findViewById(R.id.cinema_speed_indicator)
        host.setupCinemaProgressBar()

        host.controlsOverlay?.visibility = View.GONE
        host.controlsOverlay?.alpha = 0f

        // Start updating time display
        host.startSeekbarProgressUpdates()

        // Apple TV-style focus animation with scale effect
        val classicAppleTvAnimation = { view: View? ->
            view?.onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
                if (hasFocus) {
                    // Scale up with premium smooth animation when focused
                    v.animate()
                        .scaleX(1.12f)
                        .scaleY(1.12f)
                        .translationZ(8f)
                        .setDuration(200)
                        .setInterpolator(android.view.animation.DecelerateInterpolator())
                        .start()
                    // Extend timer when focused
                    if (host.controlsMenuVisible) {
                        host.scheduleHideControlsMenu()
                    }
                } else {
                    // Scale back to normal smoothly
                    v.animate()
                        .scaleX(1.0f)
                        .scaleY(1.0f)
                        .translationZ(2f)
                        .setDuration(200)
                        .setInterpolator(android.view.animation.AccelerateInterpolator())
                        .start()
                }
            }
        }

        // Dock focus: the fills/rings/underlines/icon tints live in each
        // skin's StateListDrawable + ColorStateList; code adds only the
        // spec's scale/lift gesture (@ 120ms) and the shared caption.
        val dockFocusSpec = host.dockSkinSpec
        val dockFocusLiftPx = if (dockFocusSpec != null) {
            TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                dockFocusSpec.focusLiftDp,
                activity.resources.displayMetrics,
            )
        } else 0f
        val ottFocusTreatment = { view: View? ->
            view?.onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
                val scale = dockFocusSpec?.focusScale ?: 1.08f
                if (hasFocus) {
                    v.animate()
                        .scaleX(scale)
                        .scaleY(scale)
                        .translationY(-dockFocusLiftPx)
                        .setDuration(120)
                        .setInterpolator(android.view.animation.DecelerateInterpolator())
                        .start()
                    updateOttCaption(v)
                    if (host.controlsMenuVisible) {
                        host.scheduleHideControlsMenu()
                    }
                } else {
                    v.animate()
                        .scaleX(1.0f)
                        .scaleY(1.0f)
                        .translationY(0f)
                        .setDuration(120)
                        .setInterpolator(android.view.animation.AccelerateInterpolator())
                        .start()
                    clearOttCaption(v)
                }
            }
        }
        val applyAppleTvAnimation =
            if (host.ottSkinInstalled) ottFocusTreatment else classicAppleTvAnimation

        // Apply Apple TV animations to all control buttons
        applyAppleTvAnimation(host.pauseButton)
        applyAppleTvAnimation(nightModeButton)
        applyAppleTvAnimation(audioButton)
        applyAppleTvAnimation(subtitleButton)
        applyAppleTvAnimation(aspectButton)
        applyAppleTvAnimation(speedButton)
        applyAppleTvAnimation(playlistButton)
        applyAppleTvAnimation(nextButton)
        applyAppleTvAnimation(prevButton)
        applyAppleTvAnimation(randomButton)
        applyAppleTvAnimation(iptvJumpButton)
        applyAppleTvAnimation(iptvStartOverButton)
        applyAppleTvAnimation(iptvStartOverSeekButton)

        val extendTimerOnFocus = View.OnFocusChangeListener { _, hasFocus ->
            if (hasFocus && host.controlsMenuVisible) {
                host.scheduleHideControlsMenu()
            }
        }

        host.pauseButton?.setOnClickListener {
            host.togglePlayPause()
            if (host.player?.isPlaying == true) {
                host.scheduleHideControlsMenu()
            } else {
                host.cancelScheduledHideControlsMenu()
            }
        }
        host.pauseButton?.onFocusChangeListener = extendTimerOnFocus

        nightModeButton?.setOnClickListener {
            if (USE_UNIFIED_MENU && host.unifiedMenu != null) {
                host.hideControlsMenu(); host.unifiedMenu?.show("audio", "night")
            } else {
                host.displayController.showNightModeDialog()
            }
        }
        nightModeButton?.onFocusChangeListener = extendTimerOnFocus
        host.displayController.updateNightModeButtonLabel()

        iptvJumpButton?.setOnClickListener {
            host.hideControlsMenu()
            host.iptvGuideChromeController.overlay.showIptvChannelJumpDialog()
        }
        iptvJumpButton?.onFocusChangeListener = extendTimerOnFocus

        iptvStartOverButton?.setOnClickListener {
            host.hideControlsMenu()
            host.iptvStartOverController.toggleIptvStartOver()
        }
        iptvStartOverButton?.onFocusChangeListener = extendTimerOnFocus

        iptvStartOverSeekButton?.setOnClickListener {
            host.iptvStartOverController.showIptvStartOverTimeline()
        }
        iptvStartOverSeekButton?.onFocusChangeListener = extendTimerOnFocus

        audioButton?.setOnClickListener {
            if (USE_UNIFIED_MENU && host.unifiedMenu != null) {
                host.hideControlsMenu(); host.unifiedMenu?.show("audio")
            } else {
                host.displayController.showAudioTrackDialog()
                host.scheduleHideControlsMenu()
            }
        }
        audioButton?.onFocusChangeListener = extendTimerOnFocus

        subtitleButton?.setOnClickListener {
            host.hideControlsMenu()
            if (USE_UNIFIED_MENU && host.unifiedMenu != null) {
                host.unifiedMenu?.show("subs")
            } else {
                host.subtitleController.showSubtitleSettingsPanel()
            }
        }
        subtitleButton?.onFocusChangeListener = extendTimerOnFocus

        // Aspect is a 3-value cycle — apply it right from the controls bar
        // (with its toast feedback) instead of routing through the menu.
        aspectButton?.setOnClickListener {
            host.displayController.cycleAspectRatio()
            host.scheduleHideControlsMenu()
        }
        aspectButton?.onFocusChangeListener = extendTimerOnFocus
        host.displayController.updateAspectButtonLabel()

        speedButton?.setOnClickListener {
            if (USE_UNIFIED_MENU && host.unifiedMenu != null) {
                host.hideControlsMenu(); host.unifiedMenu?.show("playback", "speed")
            } else {
                host.displayController.cyclePlaybackSpeed()
                host.scheduleHideControlsMenu()
            }
        }
        speedButton?.onFocusChangeListener = extendTimerOnFocus

        playlistButton?.setOnClickListener {
            host.hideControlsMenu()
            host.playlistController.showPlaylist()
        }
        playlistButton?.onFocusChangeListener = extendTimerOnFocus

        nextButton?.setOnClickListener {
            host.hideControlsMenu()
            // In an IPTV episode list, walk the season; otherwise the playlist.
            val iptvNext = host.iptvGuideController.navigator.nextIptvEpisode()
            if (iptvNext != null) host.iptvGuideController.navigator.switchToIptvChannel(iptvNext) else host.playNext()
        }
        nextButton?.onFocusChangeListener = extendTimerOnFocus

        // Previous episode: IPTV walks its episode list; catalog series use the
        // current playlist first, then fetch across its boundary from the full
        // guide without leaving the native player.
        prevButton?.setOnClickListener {
            host.hideControlsMenu()
            if (host.isIptvMode) {
                host.iptvGuideController.navigator.prevIptvEpisode()?.let { host.iptvGuideController.navigator.switchToIptvChannel(it) }
            } else {
                host.playPrevious()
            }
        }
        prevButton?.onFocusChangeListener = extendTimerOnFocus
        host.updateCatalogEpisodeControls()

        randomButton?.setOnClickListener {
            host.hideControlsMenu()
            if (USE_UNIFIED_MENU && host.unifiedMenu != null) {
                host.unifiedMenu?.show("playback", "shuffle")
            } else {
                host.showRandomPlaybackDialog()
            }
        }
        randomButton?.onFocusChangeListener = extendTimerOnFocus

        if (host.ottSkinInstalled) {
            // Every assignment above just overwrote the focus animation with
            // extendTimerOnFocus (a view holds ONE focus listener; last set
            // wins — which is also why the classic scale never fires today).
            // The OTT treatment includes the timer-extend behaviour, so
            // re-applying it LAST gives the dock its scale + caption.
            applyAppleTvAnimation(host.pauseButton)
            applyAppleTvAnimation(nightModeButton)
            applyAppleTvAnimation(audioButton)
            applyAppleTvAnimation(subtitleButton)
            applyAppleTvAnimation(aspectButton)
            applyAppleTvAnimation(speedButton)
            applyAppleTvAnimation(playlistButton)
            applyAppleTvAnimation(nextButton)
            applyAppleTvAnimation(prevButton)
            applyAppleTvAnimation(randomButton)
            applyAppleTvAnimation(iptvJumpButton)
            applyAppleTvAnimation(iptvStartOverButton)
            applyAppleTvAnimation(iptvRecordButton)
            applyAppleTvAnimation(ottSourcesButton)
            applyAppleTvAnimation(host.playerView.findViewById(R.id.ott_seek_back_button))
            applyAppleTvAnimation(host.playerView.findViewById(R.id.ott_seek_forward_button))
        }
    }
}

    /** Everything that differs between dock skins WITHOUT deserving its own
     *  code branch: which layout inflates, bar geometry, the focus gesture,
     *  which icon family play/pause swaps within. Behavior that can't be a
     *  number (identity arrangement, the PULSE spannable) branches on
     *  [controlsSkin] directly. */
    internal data class DockSkinSpec(
        val layoutRes: Int,
        val trackIdleDp: Float,
        val trackFocusDp: Float,
        val focusScale: Float,
        val focusLiftDp: Float,
        // Only the OTT scrim needs 4 stops (its Flutter source of truth);
        // every other skin's XML background is final as inflated.
        val applyShaderScrim: Boolean,
        val playIconRes: Int,
        val pauseIconRes: Int,
    )
        /**
         * When true, the dock buttons (Audio, Subs, Fill, Speed, Night, Shuffle) open the
         * unified Miller-columns menu instead of the individual dialogs/panels. Additive —
         * flip to false to restore the exact prior behaviour.
         */
        private const val USE_UNIFIED_MENU = true
