package com.debrify.app.tv

import android.graphics.Typeface
import android.util.Log
import android.view.View
import com.debrify.app.diagnostics.DiagnosticFileLog
import com.debrify.app.audio.NativeAudioRouting
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import android.media.audiofx.LoudnessEnhancer
import com.debrify.app.R

@OptIn(UnstableApi::class)
internal class TvPlaybackDisplayController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val controlsDockController: TvControlsDockController
        val controlsSkin: TvControlsSkin
        val iptvGuideController: TvIptvGuideController
        val nativeAudioRouting: NativeAudioRouting
        val ottSkinInstalled: Boolean
        val player: ExoPlayer?
        val playerPreferences: com.debrify.app.profiles.NativePlayerPreferences
        val playerView: PlayerView
        var skipSegmentProviderId: String
        var skipSegmentsEnabled: Boolean
        val trackSelector: DefaultTrackSelector?
    }
    internal var displayMatchMode = TvContentDisplayMatchMode.SYSTEM
    internal var displayModeController: TvDisplayModeController? = null

    internal val decoderAnalyticsListener = object : AnalyticsListener {
        private var inputFormat: Format? = null

        override fun onAudioTrackInitialized(
            eventTime: AnalyticsListener.EventTime,
            audioTrackConfig: AudioSink.AudioTrackConfig,
        ) {
            // Format/route changes can replace AudioTrack without changing its
            // session ID or media item. Reattach effects to the actual output.
            if (nightModeIndex > 0) initializeLoudnessEnhancer()
            syncAudioEffectSession()
        }

        override fun onVideoInputFormatChanged(
            eventTime: AnalyticsListener.EventTime,
            format: Format,
            decoderReuseEvaluation: DecoderReuseEvaluation?,
        ) {
            inputFormat = format
            displayModeController?.onVideoFormat(format)
        }

        override fun onVideoDecoderInitialized(
            eventTime: AnalyticsListener.EventTime,
            decoderName: String,
            initializedTimestampMs: Long,
            initializationDurationMs: Long,
        ) {
            val format = host.player?.videoFormat ?: inputFormat
            val generation = eventTime.mediaPeriodId?.windowSequenceNumber ?: -1L
            val message =
                "generation=$generation phase=stable " +
                    "status=${androidDecoderStatus(decoderName)} " +
                    "platform=android_tv backend=media3 " +
                    "codec=${format?.sampleMimeType ?: "unknown"} " +
                    "decoder=$decoderName output=surface_view " +
                    "resolution=${format?.width ?: 0}x${format?.height ?: 0}"
            DiagnosticFileLog.record(
                source = "android_tv_player",
                event = "decoder_initialized",
                message = message,
            )
            Log.i(
                DECODER_LOG_TAG,
                message,
            )
        }
    }
    internal var resizeModeIndex = 1  // Fill by default
    internal var playbackSpeedIndex = 2  // 1.0x
    internal var nightModeIndex = 0  // Off by default
    internal var loudnessEnhancer: LoudnessEnhancer? = null

    /** Opt-in (Settings → Player Settings): announce our audio session so system
     *  effect apps (Wavelet, OEM equalizers) can attach. Off by default. */
    internal var systemAudioEffectsEnabled = false

    private val resizeModes = arrayOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
        AspectRatioFrameLayout.RESIZE_MODE_FIT
    )

    internal val resizeModeLabels = arrayOf("Fit", "Fill", "Zoom", "Cinema Zoom")

    internal val playbackSpeeds = arrayOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    internal val playbackSpeedLabels = arrayOf("0.5x", "0.75x", "1.0x", "1.25x", "1.5x", "2.0x")

    private val nightModeGains = arrayOf(0, 500, 1000, 1500, 2000, 2500, 3000, 5000)  // millibels
    private val nightModeLabels = arrayOf("Off", "Low", "Medium", "High", "Higher", "Extreme", "Max", "Sleeping Baby")

    fun updateAspectButtonLabel() {
        host.controlsDockController.aspectButton?.text = resizeModeLabels[resizeModeIndex]
        host.controlsDockController.refreshOttCaptionFor(host.controlsDockController.aspectButton)
    }

    fun updateNightModeButtonLabel() {
        host.controlsDockController.nightModeButton?.text = nightModeLabels[nightModeIndex]
        host.controlsDockController.refreshOttCaptionFor(host.controlsDockController.nightModeButton)
    }

    // Track selection
    // ═══════════════════════════════════════════════════════════════════════════
    // UNIFIED MENU · backing (reuses existing apply logic; nothing is duplicated
    // that would drift from the individual dialogs).
    // ═══════════════════════════════════════════════════════════════════════════

    /** Same list [showAudioTrackDialog] builds: "Off" + one entry per audio track. */
    private fun umAudioTracks(): List<Pair<String, TrackSelectionOverride?>> {
        val out = mutableListOf<Pair<String, TrackSelectionOverride?>>()
        out.add("Off" to null)
        val tracks = host.player?.currentTracks ?: return out
        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_AUDIO) {
                for (i in 0 until group.length) {
                    out.add(
                        buildAudioTrackLabel(group.getTrackFormat(i)) to
                            TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                    )
                }
            }
        }
        return out
    }

    /** Index into [umAudioTracks] of the currently selected track (0 = Off). */
    private fun umAudioSelectedIndex(): Int {
        val tracks = host.player?.currentTracks ?: return 0
        var pos = 1
        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_AUDIO) {
                for (i in 0 until group.length) {
                    if (group.isTrackSelected(i)) return pos
                    pos++
                }
            }
        }
        return 0
    }

    // ── Audio ─────────────────────────────────────────────────────────────────
    fun umAudioModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val col2 = listOf(
            mrow("Audio track", tag = "audio"),
            mrow("Night mode", value = nightModeLabels.getOrNull(nightModeIndex), tag = "night")
        )
        val tag = col2.getOrNull(col2Index)?.tag
        val (title, col3) = if (tag == "night") {
            "Night mode · loudness" to nightModeLabels.mapIndexed { i, l ->
                mrow(l, selected = i == nightModeIndex, onOk = { applyNightMode(i) })
            }
        } else if (umAudioTracks().size <= 1) {   // only the synthetic "Off" entry → no real tracks
            "Audio tracks" to listOf(mrow("No audio tracks available", enabled = false))
        } else {
            val sel = umAudioSelectedIndex()
            "Audio tracks" to umAudioTracks().mapIndexed { i, pair ->
                mrow(pair.first, selected = i == sel, onOk = {
                    val ts = host.trackSelector
                    if (ts != null) {
                        val override = umAudioTracks().getOrNull(i)?.second
                        val p = ts.parameters.buildUpon()
                        if (override != null) {
                            p.setOverrideForType(override); p.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                        } else p.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                        ts.parameters = p.build()
                        // Series: remember this language for later episodes + sessions.
                        host.iptvGuideController.navigator.onIptvSeriesAudioPicked(languageOfOverride(override))
                    }
                })
            }
        }
        return UnifiedMenuController.Model(col1, "AUDIO", col2, title, col3)
    }

    // ── Display ───────────────────────────────────────────────────────────────
    fun umDisplayModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val col2 = listOf(
            mrow("Aspect ratio", value = resizeModeLabels.getOrNull(resizeModeIndex), tag = "aspect")
        )
        val col3 = resizeModeLabels.mapIndexed { i, l ->
            mrow(l, selected = i == resizeModeIndex, onOk = {
                resizeModeIndex = i.coerceIn(0, resizeModes.lastIndex)
                applyResizeMode()
                updateAspectButtonLabel()
            })
        }
        return UnifiedMenuController.Model(col1, "DISPLAY", col2, "Aspect ratio", col3)
    }

    fun showAudioTrackDialog() {
        val ts = host.trackSelector ?: return
        val tracks = host.player?.currentTracks ?: return

        val audioTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()
        audioTracks.add(Pair("Off", null))

        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_AUDIO) {
                for (i in 0 until group.length) {
                    val format = group.getTrackFormat(i)
                    val label = buildAudioTrackLabel(format)
                    val override = TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                    audioTracks.add(Pair(label, override))
                }
            }
        }

        if (audioTracks.size <= 1) {
            Toast.makeText(activity, "No audio tracks available", Toast.LENGTH_SHORT).show()
            return
        }

        val labels = audioTracks.map { it.first }.toTypedArray()
        AlertDialog.Builder(activity)
            .setTitle("Select Audio Track")
            .setItems(labels) { _, which ->
                val override = audioTracks[which].second
                val params = ts.parameters.buildUpon()
                if (override != null) {
                    params.setOverrideForType(override)
                    params.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                } else {
                    params.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
                }
                ts.parameters = params.build()
                // Series: remember this language for later episodes + sessions.
                host.iptvGuideController.navigator.onIptvSeriesAudioPicked(languageOfOverride(override))
            }
            .show()
    }

    // Aspect ratio
    fun cycleAspectRatio() {
        resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size
        applyResizeMode()
        updateAspectButtonLabel()
        Toast.makeText(activity, "Aspect: ${resizeModeLabels[resizeModeIndex]}", Toast.LENGTH_SHORT).show()
    }

    fun applyResizeMode() {
        host.playerView.resizeMode = resizeModes[resizeModeIndex]
        val content = host.playerView.findViewById<View>(androidx.media3.ui.R.id.exo_content_frame)
            ?: host.playerView.videoSurfaceView
        val scale = if (resizeModeIndex == 3) 4f / 3f else 1f
        content?.scaleX = scale
        content?.scaleY = scale
    }

    // Playback speed
    fun cyclePlaybackSpeed() {
        applyPlaybackSpeed((playbackSpeedIndex + 1) % playbackSpeeds.size)
        Toast.makeText(activity, "Speed: ${playbackSpeedLabels[playbackSpeedIndex]}", Toast.LENGTH_SHORT).show()
    }

    fun applyPlaybackSpeed(index: Int) {
        playbackSpeedIndex = index.coerceIn(0, playbackSpeeds.lastIndex)
        val speed = playbackSpeeds[playbackSpeedIndex]
        val routeChanged = host.nativeAudioRouting.update(nightModeIndex > 0, systemAudioEffectsEnabled, speed)
        if (routeChanged) {
            releaseLoudnessEnhancer()
        }
        host.nativeAudioRouting.setPlaybackSpeed(host.player, speed, routeChanged)
        // Dock skins carry the speed on the button itself — visibly on
        // BROADCAST's labeled pill, and as the shared focus caption on the
        // rest (which would otherwise go stale). Classic keeps its Toast-only
        // presentation untouched.
        if (host.ottSkinInstalled) {
            host.controlsDockController.speedButton?.text = playbackSpeedLabels[playbackSpeedIndex]
            host.controlsDockController.refreshOttCaptionFor(host.controlsDockController.speedButton)
        }
    }

    /**
     * Announce ExoPlayer's current audio session to system audio-effect apps
     * (Wavelet, OEM equalizers) so they can attach, the same way they do for
     * other video apps. Idempotent — AudioEffectSession ignores a re-announce
     * of the session already open and closes the previous one otherwise.
     */
    fun syncAudioEffectSession(sessionId: Int? = null) {
        if (!systemAudioEffectsEnabled) return
        // Prefer the id the callback handed us over re-reading the player,
        // which may not have published the new one yet.
        val audioSessionId = sessionId ?: host.player?.audioSessionId ?: return
        if (audioSessionId == 0) return  // Renderer not live yet
        com.debrify.app.audio.AudioEffectSession.open(activity, audioSessionId)
    }

    // Night mode (dynamic range compression)
    fun initializeLoudnessEnhancer() {
        try {
            val audioSessionId = host.player?.audioSessionId ?: return
            if (audioSessionId == 0) return  // Invalid session

            releaseLoudnessEnhancer()  // Clean up any existing instance

            loudnessEnhancer = LoudnessEnhancer(audioSessionId)
            loudnessEnhancer?.enabled = nightModeIndex > 0
            if (nightModeIndex > 0) {
                loudnessEnhancer?.setTargetGain(nightModeGains[nightModeIndex])
            }
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Failed to initialize LoudnessEnhancer", e)
            loudnessEnhancer = null
        }
    }

    fun releaseLoudnessEnhancer() {
        try {
            loudnessEnhancer?.release()
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Error releasing LoudnessEnhancer", e)
        }
        loudnessEnhancer = null
    }

    /**
     * Load default player settings from Flutter's SharedPreferences.
     * Keys are prefixed with "flutter." as per flutter shared_preferences package.
     */
    fun loadPlayerDefaults() {
        try {
            // Load aspect index for TV (separate from mobile)
            // TV only: 0=Fit, 1=Fill, 2=Zoom, 3=Cinema Zoom (default: 0=Fit)
            resizeModeIndex = host.playerPreferences
                .getLong("player_default_aspect_index_tv", 0L).toInt()
                .coerceIn(0, resizeModes.lastIndex)

            // Load night mode index (default: 0 = Off)
            nightModeIndex = host.playerPreferences
                .getLong("player_night_mode_index", 0L).toInt()
                .coerceIn(0, nightModeGains.lastIndex)

            // Announce our audio session to system effect apps (default: off)
            systemAudioEffectsEnabled = host.playerPreferences
                .getBoolean("player_system_audio_effects", false)

            displayMatchMode = TvContentDisplayMatchMode.fromStorage(
                host.playerPreferences.getString(
                    "content_display_match_mode",
                    TvContentDisplayMatchMode.SYSTEM.storageKey,
                ),
            )
            displayModeController?.clear()
            displayModeController = TvDisplayModeController(activity, displayMatchMode)

            // Manual community intro/outro buttons. These are the same keys the
            // Flutter Playback settings page writes; enabled never means auto-seek.
            host.skipSegmentsEnabled = host.playerPreferences
                .getBoolean("skip_segments_enabled", true)
            val storedSkipSegmentProvider = host.playerPreferences.getString(
                "skip_segment_provider",
                TvSkipSegmentClients.AUTO,
            ) ?: TvSkipSegmentClients.AUTO
            host.skipSegmentProviderId = if (TvSkipSegmentClients.supports(storedSkipSegmentProvider)) {
                storedSkipSegmentProvider
            } else {
                TvSkipSegmentClients.AUTO
            }

            android.util.Log.d("AndroidTvPlayer", "Loaded defaults - aspect=$resizeModeIndex, nightMode=$nightModeIndex, audioEffects=$systemAudioEffectsEnabled, displayMatch=${displayMatchMode.storageKey}, skipSegments=${host.skipSegmentsEnabled}, skipProvider=${host.skipSegmentProviderId}")
            android.util.Log.d("AndroidTvPlayer", "Player settings handoff: style=${host.controlsSkin} subtitles=${host.playerPreferences.getString("player_default_subtitle_language", "auto")} nightMode=$nightModeIndex")
        } catch (e: Exception) {
            android.util.Log.e("AndroidTvPlayer", "Error loading player defaults", e)
            // Keep default values
        }
    }

    fun showNightModeDialog() {
        AlertDialog.Builder(activity)
            .setTitle("Night Mode")
            .setSingleChoiceItems(nightModeLabels, nightModeIndex) { dialog, which ->
                applyNightMode(which)
                dialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun applyNightMode(index: Int) {
        nightModeIndex = index

        val speed = playbackSpeeds[playbackSpeedIndex]
        val routeChanged = host.nativeAudioRouting.update(nightModeIndex > 0, systemAudioEffectsEnabled, speed)
        if (routeChanged) {
            // A recreated AudioTrack may retain its session ID; READY must
            // attach a fresh effect even without onAudioSessionIdChanged.
            releaseLoudnessEnhancer()
        }
        val restartingAudio = routeChanged && host.nativeAudioRouting.reprepare(host.player, speed)

        if (nightModeIndex == 0) {
            // Turn off
            loudnessEnhancer?.enabled = false
        } else if (!restartingAudio) {
            // Turn on or adjust
            if (loudnessEnhancer == null) {
                initializeLoudnessEnhancer()
            }
            // Check if initialization succeeded before using
            loudnessEnhancer?.let {
                it.enabled = true
                it.setTargetGain(nightModeGains[nightModeIndex])
            }
        }

        updateNightModeButtonLabel()
        Toast.makeText(activity, "Night Mode: ${nightModeLabels[nightModeIndex]}", Toast.LENGTH_SHORT).show()
    }
}
        private const val DECODER_LOG_TAG = "DEBRIFY_PLAYER_DECODER"
