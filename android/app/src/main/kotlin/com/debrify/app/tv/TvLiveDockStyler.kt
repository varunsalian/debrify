package com.debrify.app.tv

import android.graphics.Typeface
import android.view.View
import androidx.core.content.ContextCompat
import androidx.core.widget.TextViewCompat
import com.debrify.app.recording.LiveRecordingService
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.debrify.app.R

@OptIn(UnstableApi::class)
internal class TvLiveDockStyler(
    private val activity: AppCompatActivity,
    private val host: TvControlsDockController.Host,
    private val controlsDock: TvControlsDockController,
) {

    fun setupIptvControls() {
        host.playerView.findViewById<View>(R.id.debrify_random_button)?.visibility = View.GONE
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)
        if (entry?.isLive == false) {
            // IPTV VOD uses the same cinema/Netflix-style dock installed by
            // setupControls(). Do not replace its panel/button backgrounds or
            // handlers with the live-TV presentation.
            controlsDock.iptvGuideButton?.visibility = View.GONE
            controlsDock.iptvPrevButton?.visibility = View.GONE
            controlsDock.iptvNextButton?.visibility = View.GONE
            updateIptvControlPresentation(entry)
            return
        }

        applyLiveIptvControlStyle()

        controlsDock.iptvRecordButton?.setOnClickListener {
            host.hideControlsMenu()
            host.iptvRecordingActionsController.toggleIptvRecording()
        }

        controlsDock.iptvPrevButton?.apply {
            text = "CH -"
            setOnClickListener {
                host.hideControlsMenu()
                host.iptvGuideController.navigator.zapIptvChannel(-1)
            }
        }
        controlsDock.iptvNextButton?.apply {
            text = "CH +"
            setOnClickListener {
                host.hideControlsMenu()
                host.iptvGuideController.navigator.zapIptvChannel(1)
            }
        }
        updateIptvControlPresentation(host.iptvChannels.getOrNull(host.currentIptvIndex))
    }

    /** The live dock buttons that restyle for live IPTV — the same set the
     *  original setup loop touched, so classic stays verbatim. */
    private fun liveIptvDockButtons(): List<AppCompatButton> = listOfNotNull(
        controlsDock.audioButton,
        controlsDock.subtitleButton,
        controlsDock.aspectButton,
        host.pauseButton,
        controlsDock.speedButton,
        controlsDock.nightModeButton,
        controlsDock.iptvPrevButton,
        controlsDock.iptvNextButton,
        controlsDock.iptvJumpButton,
        controlsDock.iptvStartOverButton,
        controlsDock.iptvStartOverSeekButton,
        controlsDock.iptvRecordButton,
        host.playerView.findViewById<AppCompatButton>(R.id.debrify_playlist_button),
    )

    /** Cinema compound-drawable tints + typefaces captured before the first
     *  styled live swap, so a styled live→VOD transition can put them back —
     *  [restoreCinemaIptvControlStyle] only restores backgrounds/text. */
    private val cinemaIconTints = HashMap<View, android.content.res.ColorStateList?>()
    private val cinemaButtonTypefaces = HashMap<View, Typeface?>()

    /**
     * The live-IPTV dock skin. Extracted from `setupIptvControls` so the
     * VOD→live transition can re-apply it (`restoreCinemaIptvControlStyle`
     * overwrites every drawable on the way to VOD, and the return trip only
     * reordered children). Classic keeps its original swap verbatim AND its
     * original call graph — only styled launches call this from
     * `updateIptvControlPresentation`.
     */
    private fun applyLiveIptvControlStyle() {
        val t = host.guideTokens
        if (t == null) {
            host.playerView.findViewById<View>(R.id.debrify_controls_buttons)
                ?.setBackgroundResource(R.drawable.iptv_premium_panel_bg)

            val buttons = liveIptvDockButtons()
            buttons.forEach {
                it.setBackgroundResource(R.drawable.iptv_premium_button_bg)
                it.setTextColor(
                    ContextCompat.getColorStateList(activity, R.color.iptv_premium_button_text)
                )
            }
            return
        }

        val radius = when (host.guideStyle) {
            GuideStyle.GLASS -> host.dp(22).toFloat()
            GuideStyle.EDITION -> host.dp(8).toFloat()
            else -> host.dp(4).toFloat()
        }
        host.playerView.findViewById<View>(R.id.debrify_controls_buttons)?.background =
            t.panelDrawable(radius, host.dp(1))
        val buttonRadius = when (host.guideStyle) {
            GuideStyle.GLASS -> host.dp(16).toFloat()
            GuideStyle.EDITION -> host.dp(6).toFloat()
            else -> host.dp(3).toFloat()
        }
        liveIptvDockButtons().forEach { button ->
            if (!cinemaIconTints.containsKey(button)) {
                // TextViewCompat throughout: the direct getter/setter is
                // API 23 and this app ships to minSdk 21.
                cinemaIconTints[button] =
                    TextViewCompat.getCompoundDrawableTintList(button)
                cinemaButtonTypefaces[button] = button.typeface
            }
            button.background = t.buttonBackground(buttonRadius)
            val colors = t.buttonTextColors()
            button.setTextColor(colors)
            TextViewCompat.setCompoundDrawableTintList(button, colors)
            if (host.guideStyle == GuideStyle.CONSOLE) {
                button.typeface = host.guideTypeface(t.monoFont) ?: button.typeface
            }
        }
    }

    /** Styled-only tail after [restoreCinemaIptvControlStyle]: put back the
     *  cinema icon tints AND typefaces the styled live skin replaced.
     *  Classic never runs this (its restore function is untouched and
     *  sufficient). */
    private fun restoreCinemaDockIconTints() {
        if (cinemaIconTints.isEmpty()) return
        liveIptvDockButtons().forEach { button ->
            if (cinemaIconTints.containsKey(button)) {
                TextViewCompat.setCompoundDrawableTintList(
                    button,
                    cinemaIconTints[button],
                )
            }
            if (cinemaButtonTypefaces.containsKey(button)) {
                button.typeface = cinemaButtonTypefaces[button]
            }
        }
    }

    fun updateIptvControlPresentation(entry: IptvChannelEntry?) {
        val live = entry?.isLive != false
        val vodVisibility = if (live) View.GONE else View.VISIBLE
        val archiveTimelineVisibility = if (
            !live || (host.iptvStartOverActive && host.iptvStartOverTimelineVisible)
        ) View.VISIBLE else View.GONE
        if (live) {
            arrangeLiveIptvControlDock()
            // Styled only: a VOD trip restored every cinema drawable, and
            // reordering alone doesn't bring the live skin back. Classic
            // keeps its original call graph (and its original quirk).
            if (host.guideTokens != null) applyLiveIptvControlStyle()
        } else {
            restoreCinemaIptvControlStyle()
            if (host.guideTokens != null) restoreCinemaDockIconTints()
        }
        host.cinemaProgressContainer?.visibility = archiveTimelineVisibility
        host.debrifyTimeCurrent?.visibility = archiveTimelineVisibility
        host.debrifyTimeTotal?.visibility = archiveTimelineVisibility
        controlsDock.speedButton?.visibility = vodVisibility
        controlsDock.nightModeButton?.visibility = View.VISIBLE
        controlsDock.iptvJumpButton?.visibility = if (live) View.VISIBLE else View.GONE
        controlsDock.iptvGuideButton?.visibility = if (live) View.VISIBLE else View.GONE
        host.iptvStartOverController.updateIptvStartOverButton(entry)
        host.iptvStartOverController.updateIptvStartOverSeekButton()
        // Visibility follows the ACTIVE recorder: the engine records pre-Q
        // once storage is granted (and shows the button so it CAN be
        // granted); the tee remains Q+-only.
        val recorderAvailable = if (host.iptvRecordingActionsController.recordingEngineEnabled) {
            LiveRecordingService.isSupported(activity) ||
                LiveRecordingService.needsLegacyPermission(activity)
        } else {
            IptvRecordingController.isSupported
        }
        controlsDock.iptvRecordButton?.visibility =
            if (live && recorderAvailable) View.VISIBLE else View.GONE
        host.iptvRecordingActionsController.updateRecordButtonState()
        if (!live && host.iptvGuideController.iptvGuideVisible) host.iptvGuideController.hideIptvGuide()
        if (live) {
            host.cinemaSeekMode = false
            host.cinemaSeekWasPlaying = false
            host.cinemaProgressThumb?.visibility = View.INVISIBLE
            host.cinemaSpeedIndicator?.visibility = View.GONE
            if (activity.currentFocus == host.cinemaProgressContainer) {
                host.pauseButton?.requestFocus()
            }
        }
    }

    /** Live IPTV uses a balanced dock:
     *  Audio · Subs · Aspect | CH- · Play/Pause · Start Over · Seek · CH+ |
     *  Guide · Jump · Record · Night.
     *  Record is present only for progressive streams (disabled for HLS). The
     *  XML order remains the standard cinema/VOD order; only the live
     *  presentation is rearranged, so movies and episodes keep their old UX. */
    private fun arrangeLiveIptvControlDock() {
        val dock =
            host.playerView.findViewById<LinearLayout>(R.id.debrify_controls_buttons)
                ?: return
        val desired = listOfNotNull(
            controlsDock.audioButton,
            controlsDock.subtitleButton,
            controlsDock.aspectButton,
            host.playerView.findViewById<View>(R.id.debrify_controls_left_divider),
            controlsDock.iptvPrevButton,
            host.pauseButton,
            controlsDock.iptvStartOverButton,
            controlsDock.iptvStartOverSeekButton,
            controlsDock.iptvNextButton,
            host.playerView.findViewById<View>(R.id.debrify_controls_right_divider),
            controlsDock.iptvGuideButton,
            controlsDock.iptvJumpButton,
            controlsDock.iptvRecordButton,
            controlsDock.nightModeButton,
        )
        replaceControlDockOrder(dock, desired)
    }

    private fun restoreOriginalControlDockOrder() {
        val dock =
            host.playerView.findViewById<LinearLayout>(R.id.debrify_controls_buttons)
                ?: return
        if (controlsDock.originalControlDockOrder.isNotEmpty()) {
            replaceControlDockOrder(dock, controlsDock.originalControlDockOrder)
        }
    }

    private fun replaceControlDockOrder(dock: LinearLayout, leading: List<View>) {
        // Keep hidden/format-specific controls attached after the requested
        // order. GONE children consume no space, but retaining them lets the
        // same dock switch back to VOD without reinflating the controller.
        val order = leading + controlsDock.originalControlDockOrder.filterNot { it in leading }
        val alreadyApplied =
            dock.childCount == order.size &&
                order.indices.all { index -> dock.getChildAt(index) === order[index] }
        if (alreadyApplied) return
        dock.removeAllViews()
        order.forEach { dock.addView(it) }
    }

    private fun restoreCinemaIptvControlStyle() {
        restoreOriginalControlDockOrder()
        host.playerView.findViewById<View>(R.id.debrify_controls_buttons)
            ?.setBackgroundResource(R.drawable.cinema_dock_bg)
        val standardButtons = listOfNotNull(
            controlsDock.audioButton,
            controlsDock.subtitleButton,
            controlsDock.aspectButton,
            controlsDock.speedButton,
            controlsDock.nightModeButton,
            controlsDock.iptvPrevButton,
            controlsDock.iptvNextButton,
            controlsDock.iptvGuideButton,
            controlsDock.iptvJumpButton,
            controlsDock.iptvStartOverButton,
            controlsDock.iptvStartOverSeekButton,
            controlsDock.iptvRecordButton,
        )
        standardButtons.forEach {
            it.setBackgroundResource(R.drawable.cinema_button_bg)
            it.setTextColor(
                ContextCompat.getColorStateList(activity, R.color.cinema_control_button_text)
            )
        }
        host.pauseButton?.apply {
            setBackgroundResource(R.drawable.cinema_play_button_bg)
            setTextColor(
                ContextCompat.getColorStateList(
                    activity,
                    R.color.cinema_play_button_text,
                ),
            )
        }
    }
}
