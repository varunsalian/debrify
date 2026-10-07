package com.debrify.app.tv

import android.animation.ValueAnimator
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.PaintDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RectShape
import android.view.LayoutInflater
import android.media.MediaCodecList
import android.os.Bundle
import android.view.animation.DecelerateInterpolator
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import androidx.core.content.ContextCompat
import androidx.core.widget.TextViewCompat
import com.debrify.app.recording.LiveRecordingService
import com.debrify.app.recording.RecordingAlarmReceiver
import com.debrify.app.recording.RecordingRegistry
import com.debrify.app.recording.RecordingSchedule
import com.debrify.app.recording.RecordingScheduleStore
import com.debrify.app.diagnostics.DiagnosticFileLog
import com.debrify.app.audio.NativeAudioRouting
import com.debrify.app.audio.NativeAudioRenderersFactory
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.annotation.OptIn
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.exoplayer.hls.HlsManifest
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.text.Cue
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import android.net.ConnectivityManager
import android.net.Network
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.RecyclerView
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import com.debrify.app.ActivityTracker
import com.debrify.app.MainActivity
import com.debrify.app.R
import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import com.debrify.app.subtitle.StremioAddon
import com.debrify.app.subtitle.StremioSubtitle
import com.debrify.app.subtitle.StremioSubtitleService
import com.debrify.app.util.AlignResult
import com.debrify.app.util.CueSpan
import com.debrify.app.util.LanguageMapper
import com.debrify.app.util.OffsetRenderersFactory
import com.debrify.app.util.SubtitleAligner
import com.debrify.app.util.SubtitleCue
import com.debrify.app.util.SubtitleCueCache
import com.debrify.app.util.SubtitleFontManager
import com.debrify.app.util.SubtitleSettings
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import kotlin.concurrent.thread
        private const val SUBTITLE_LOADING_LABEL = "⏳ Loading external subtitles..."
        private const val EXTERNAL_SUBTITLE_TICK_MS = 250L

@OptIn(UnstableApi::class)
internal class TvSubtitleController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        var autoSyncAppliedOffsetMs: Long?
        var autoSyncResultLabel: String?
        var autoSyncResultUrl: String?
        val autoSyncRunning: Boolean
        fun cancelAutoSyncLadder(): Unit
        fun cancelAutoSyncVerify(): Unit
        val currentIndex: Int
        var currentStremioSubtitleIndex: Int
        fun currentSubtitleIdentityLabel(): String
        val externalSubtitleHandler: Handler
        val failedSubtitleUrls: MutableSet<String>
        fun hideStatusPill(): Unit
        val isLoadingStremioSubtitles: Boolean
        var linePickerOverlay: SubtitleLinePickerController?
        val offsetRenderersFactory: OffsetRenderersFactory?
        val payload: PlaybackPayload?
        val player: ExoPlayer?
        val playerView: PlayerView
        val playerViewReady: Boolean
        fun runSubtitleAutoSync(auto: Boolean = false): Unit
        fun scheduleAutoSyncVerify(): Unit
        fun showSearchSubtitleDialog(): Unit
        fun showStatusPill(message: String): Unit
        fun showStatusPillTransient(message: String): Unit
        fun showSyncToast(glyph: String, accent: Int, title: String, hint: String? = null, autoHideMs: Long?, uppercase: Boolean = true): Unit
        fun startAutoSyncLadder(): Unit
        val stremioSubtitles: List<StremioSubtitle>
        val subtitleControlsLift: SubtitleControlsLiftController
        val subtitleOverlay: SubtitleView
        val subtitleOverlayReady: Boolean
        val subtitlePanel: SubtitlePanelController?
        val subtitleScope: CoroutineScope
        var syncOverlay: SubtitleSyncOverlayController?
        val trackSelector: DefaultTrackSelector?
        fun tryAutoSelectAddonSubtitle(): Unit
        val unifiedMenu: UnifiedMenuController?
        var userManuallySelectedSubtitle: Boolean
    }
    var subtitleSettingsVisible = false
    val subtitleSeekHandler = Handler(Looper.getMainLooper())
    val subtitleSeekRunnable = Runnable {
        host.player?.let { p ->
            val pos = p.currentPosition
            if (pos >= 0) p.seekTo(pos)
        }
    }
    var subtitleTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()
    private var currentSubtitleTrackIndex = 0

    // Side-loaded external subtitle rendering. External (Stremio) subtitles are
    // downloaded + parsed off-thread and fed straight to subtitleOverlay from a
    // position ticker — the player source is never rebuilt, so switching
    // subtitles never interrupts playback (and never touches the fragile
    // resume/seek logic that a re-prepare would).
    private var externalSubtitleCues: List<SubtitleCue> = emptyList()
    var externalSubtitleActive = false
    var activeExternalSubtitleUrl: String? = null  // URL of the side-rendered subtitle currently on screen; identifies it for sync-offset scoping
    private var externalSubtitleLoadToken = 0  // Guard against stale downloads (fast switching / content change)
    var externalSubtitleTicker: Runnable? = null
    private var lastExternalCueText: String? = null

    fun umEmbeddedTrackRows(): List<UnifiedMenuController.Row> {
        // Build the flat track list only when we don't already have one (menu open /
        // after a content switch clears it). Rebuilding on every render would re-derive
        // currentSubtitleTrackIndex from the not-yet-updated player.currentTracks and
        // clobber a just-made selection, painting the wrong row as selected.
        if (subtitleTracks.isEmpty()) rebuildSubtitleTrackList()
        val rows = mutableListOf<UnifiedMenuController.Row>()
        for ((i, pair) in subtitleTracks.withIndex()) {
            val isOff = i == 0
            val isEmbedded = pair.second != null
            if (isOff || isEmbedded) {
                rows.add(mrow(
                    if (isOff) "Off" else pair.first,
                    selected = currentSubtitleTrackIndex == i,
                    onOk = { umSelectSubtitleRowIndex(i) }
                ))
            }
        }
        return rows
    }

    fun umAppearanceRows(): List<UnifiedMenuController.Row> =
        // Shared with the Torbox player so the subtitle-appearance controls
        // can't drift between the two (see UnifiedMenuSections).
        UnifiedMenuSections.appearanceRows(activity) { applyAndPersistSubtitleSettings() }

    fun umTimingRows(): List<UnifiedMenuController.Row> {
        val ctx = activity
        val ms = SubtitleSettings.getSyncOffsetMs(ctx)
        // Sync needs the subtitle on screen to judge alignment, which a bottom menu
        // column covers — so this opens the dedicated over-video sync overlay
        // (slider for embedded subs, "tap the line" picker for downloaded subs).
        // Single launcher — the overlay itself owns reset (OK on the slider /
        // hold-OK on the picker), which also clears the picker's remembered line.
        return listOf(
            // Listens to the played audio it has already seen (the PCM tap) and
            // cross-correlates it against the subtitle's cue schedule — answers
            // in under a second, applies only on a confident match. Addon subs
            // only: their cue timelines are in hand, and they're the ones that
            // arrive mistimed; embedded tracks are authored against this video.
            mrow(
                "Auto-sync from audio",
                value = when {
                    !externalSubtitleActive -> "needs an addon subtitle"
                    host.autoSyncRunning -> "listening…"
                    // Last outcome, only while the subtitle it was computed
                    // against is still the one on screen.
                    host.autoSyncResultUrl == activeExternalSubtitleUrl -> host.autoSyncResultLabel
                    else -> null
                },
                accent = true,
                enabled = externalSubtitleActive && !host.autoSyncRunning,
                onOk = { host.unifiedMenu?.hide(); host.runSubtitleAutoSync() },
            ),
            mrow("Adjust timing  ▸", value = SubtitleSettings.formatSyncOffset(ms),
                swatch = SubtitleSettings.getSyncOffsetColor(ms), accent = true, onOk = {
                    host.unifiedMenu?.hide(); showSyncOverlay()
                })
        )
    }

    /** Select an entry from the flat [subtitleTracks] list (Off / embedded) and apply it. */
    private fun umSelectSubtitleRowIndex(rowIndex: Int) {
        if (rowIndex !in subtitleTracks.indices) return
        currentSubtitleTrackIndex = rowIndex
        host.userManuallySelectedSubtitle = true
        applySelectedSubtitleTrack()
    }

    /** Select an external Stremio subtitle by URL, reusing the battle-tested apply path. */
    fun umSelectStremioSubtitleByUrl(url: String) {
        rebuildSubtitleTrackList()
        val k = host.stremioSubtitles.indexOfFirst { it.url == url }
        if (k < 0) return
        var ext = 0
        var rowIdx = -1
        for ((i, pair) in subtitleTracks.withIndex()) {
            if (isExternalSubtitleOption(pair.first)) {
                if (ext == k) { rowIdx = i; break }
                ext++
            }
        }
        if (rowIdx < 0) return
        currentSubtitleTrackIndex = rowIdx
        host.userManuallySelectedSubtitle = true
        applySelectedSubtitleTrack()
    }

    private fun showSubtitleTrackDialog() {
        val ts = host.trackSelector ?: return
        val tracks = host.player?.currentTracks ?: return

        val subtitleTracks = mutableListOf<Pair<String, TrackSelectionOverride?>>()
        subtitleTracks.add(Pair("Off", null))

        for (group in tracks.groups) {
            if (group.type == C.TRACK_TYPE_TEXT) {
                for (i in 0 until group.length) {
                    val format = group.getTrackFormat(i)
                    val label = buildSubtitleTrackLabel(format)
                    val override = TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                    subtitleTracks.add(Pair(label, override))
                }
            }
        }

        if (subtitleTracks.size <= 1) {
            Toast.makeText(activity, "No subtitle tracks available", Toast.LENGTH_SHORT).show()
            return
        }

        val labels = subtitleTracks.map { it.first }.toTypedArray()
        AlertDialog.Builder(activity)
            .setTitle("Select Subtitle Track")
            .setItems(labels) { _, which ->
                val override = subtitleTracks[which].second
                val params = ts.parameters.buildUpon()
                if (override != null) {
                    params.setOverrideForType(override)
                    params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                } else {
                    params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                }
                ts.parameters = params.build()
            }
            .show()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUBTITLE SETTINGS PANEL
    // ═══════════════════════════════════════════════════════════════════════════

    private fun rebuildSubtitleTrackList() {
        subtitleTracks.clear()
        subtitleTracks.add(Pair("Off", null))
        currentSubtitleTrackIndex = 0

        val tracks = host.player?.currentTracks
        if (tracks != null) {
            for (group in tracks.groups) {
                if (group.type == C.TRACK_TYPE_TEXT) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)
                        val label = buildSubtitleTrackLabel(format)
                        val override = TrackSelectionOverride(group.mediaTrackGroup, listOf(i))
                        subtitleTracks.add(Pair(label, override))

                        // Check if this track is currently selected
                        if (group.isTrackSelected(i)) {
                            currentSubtitleTrackIndex = subtitleTracks.size - 1
                        }
                    }
                }
            }
        }

        // Add Stremio external subtitles to the track list
        // These are marked with "⬇" prefix to indicate they're external/downloadable
        for ((index, sub) in host.stremioSubtitles.withIndex()) {
            val label = "$EXTERNAL_SUBTITLE_PREFIX ${sub.displayName} (${sub.source})"
            // Use null override to indicate this is an external subtitle
            subtitleTracks.add(Pair(label, null))

            // Check if this Stremio subtitle is currently selected
            if (host.currentStremioSubtitleIndex == index) {
                currentSubtitleTrackIndex = subtitleTracks.lastIndex
            }
        }

        // Add loading indicator if still fetching Stremio subtitles
        if (host.isLoadingStremioSubtitles) {
            subtitleTracks.add(Pair(SUBTITLE_LOADING_LABEL, null))
        }

        // Check if no subtitle is currently selected (means "Off")
        val hasSelectedSubtitle = tracks?.groups?.any { group ->
            group.type == C.TRACK_TYPE_TEXT && (0 until group.length).any { group.isTrackSelected(it) }
        } ?: false
        if (!hasSelectedSubtitle && host.currentStremioSubtitleIndex < 0) {
            currentSubtitleTrackIndex = 0
        }
    }

    val subtitlePanelCallbacks = object : SubtitlePanelController.Callbacks {
        override fun getTrackLabels(): List<String> = subtitleTracks.map { it.first }
        override fun getCurrentTrackIndex(): Int = currentSubtitleTrackIndex
        override fun selectTrack(index: Int) {
            val label = subtitleTracks.getOrNull(index)?.first ?: return
            if (isLoadingSubtitleOption(label)) return
            if (isSearchSubtitleOption(label)) {
                host.showSearchSubtitleDialog()
                return
            }
            currentSubtitleTrackIndex = index
            host.userManuallySelectedSubtitle = true
            applySelectedSubtitleTrack()
        }
        override fun onSearchSubtitle() { host.showSearchSubtitleDialog() }
        override fun getIdentityLabel(): String = host.currentSubtitleIdentityLabel()
        override fun onSettingsChanged() { applyAndPersistSubtitleSettings() }
        override fun onSyncOverlayRequested() { showSyncOverlay() }
        override fun onHidden() {
            subtitleSettingsVisible = false
            if (host.playerViewReady) host.playerView.requestFocus()
        }
    }

    fun showSubtitleSettingsPanel() {
        rebuildSubtitleTrackList()
        host.subtitlePanel?.show()
        subtitleSettingsVisible = true
    }

    private fun hideSubtitleSettingsPanel() {
        host.subtitlePanel?.hide() ?: run { subtitleSettingsVisible = false }
    }

    private fun showSyncOverlay() {
        val root = activity.findViewById<ViewGroup>(android.R.id.content)?.getChildAt(0) as? ViewGroup ?: return

        // Use line picker for external (Stremio) subtitles. Prefer the actually-
        // rendering URL: a per-addon retry can transiently drop the current sub's
        // URL from the flat list (currentStremioSubtitleIndex → -1) while it's still
        // on screen, and we must not fall through to the embedded slider for it.
        val externalUrl = activeExternalSubtitleUrl?.takeIf { externalSubtitleActive }
            ?: host.stremioSubtitles.getOrNull(host.currentStremioSubtitleIndex)?.url
        if (externalUrl != null) {
            if (host.linePickerOverlay == null) {
                host.linePickerOverlay = SubtitleLinePickerController(
                    activity = activity,
                    rootContainer = root,
                    getCurrentPositionMs = { host.player?.currentPosition ?: 0L },
                    onOffsetApplied = { applySubtitleSettings() },
                    onDismissed = Runnable {
                        host.linePickerOverlay = null
                        if (host.playerViewReady) host.playerView.requestFocus()
                    }
                )
            }
            host.linePickerOverlay?.show(externalUrl)
            return
        }

        // Fall back to slider for embedded subtitles
        if (host.syncOverlay == null) {
            host.syncOverlay = SubtitleSyncOverlayController(
                activity = activity,
                rootContainer = root,
                onSettingsChanged = Runnable { applySubtitleSettings() },
                onDismissed = Runnable { if (host.playerViewReady) host.playerView.requestFocus() }
            )
        }
        host.syncOverlay?.show()
    }

    /**
     * Refresh subtitle panel to update loading state / loaded subtitles.
     * Re-collects tracks and updates UI without changing visibility or focus.
     */
    fun refreshSubtitlePanelForLoading() {
        rebuildSubtitleTrackList()
        host.subtitlePanel?.refresh()
    }

    private fun applySelectedSubtitleTrack() {
        val ts = host.trackSelector ?: return
        val selectedTrack = subtitleTracks.getOrNull(currentSubtitleTrackIndex)
        val label = selectedTrack?.first ?: ""
        val override = selectedTrack?.second

        // Check if this is a Stremio external subtitle (marked with ⬇ prefix)
        if (isSearchSubtitleOption(label)) {
            host.showSearchSubtitleDialog()
            return
        }

        if (isExternalSubtitleOption(label)) {
            // Calculate the Stremio subtitle index without assuming where utility rows live.
            val stremioIndex = subtitleTracks
                .take(currentSubtitleTrackIndex)
                .count { isExternalSubtitleOption(it.first) }

            if (stremioIndex >= 0 && stremioIndex < host.stremioSubtitles.size) {
                // Disable embedded subtitles first
                val params = ts.parameters.buildUpon()
                    .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                ts.parameters = params.build()

                // Load Stremio subtitle
                loadStremioSubtitle(host.stremioSubtitles[stremioIndex])
                host.currentStremioSubtitleIndex = stremioIndex
            }
            return
        }

        // Clear Stremio subtitle selection and stop any side-rendered subtitle
        host.currentStremioSubtitleIndex = -1
        stopExternalSubtitleRendering()

        // Handle embedded subtitle selection
        val params = ts.parameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
        if (override != null) {
            params.setOverrideForType(override)
            params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
        } else {
            params.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        }
        ts.parameters = params.build()
        // Selecting a different embedded subtitle (or Off) resets the sync offset:
        // it was calibrated for the previous subtitle. Do it explicitly rather
        // than via an identity-scoped read — player.currentTracks hasn't updated
        // to the new selection yet, so a read here would be stale, and embedded
        // subs carry the offset at the (push-based) renderer level. This also
        // prevents a same-language embedded track from inheriting a sibling
        // track's offset through the folded "emb" identity.
        SubtitleSettings.resetSyncOffset()
        host.offsetRenderersFactory?.setOffsetUs(0L)
    }

    /**
     * Load an external Stremio subtitle by side-rendering it: the file is
     * downloaded + parsed off-thread and cues are fed to subtitleOverlay from
     * a position ticker. The player source is never rebuilt, so playback is
     * never interrupted — no re-prepare, no rebuffer, no resume/seek juggling.
     */
    fun loadStremioSubtitle(subtitle: StremioSubtitle) {
        val loadToken = ++externalSubtitleLoadToken
        // Capture the currently-*rendering* external selection so a failed load
        // can fall back to it instead of tearing down a working subtitle. At
        // this point currentStremioSubtitleIndex still holds the previous value
        // (callers overwrite it only after this returns), but only trust it when
        // a subtitle is actually active — otherwise the previous pick was still
        // downloading (and will be discarded by the token check), so there's
        // nothing real to fall back to.
        val previousStremioIndex = if (externalSubtitleActive) host.currentStremioSubtitleIndex else -1
        host.showStatusPill("Loading ${subtitle.displayName}…")

        val cached = SubtitleCueCache.get(subtitle.url)
        if (cached != null) {
            onExternalSubtitleLoaded(subtitle, cached, previousStremioIndex)
            return
        }

        host.subtitleScope.launch {
            val parsed = withContext(Dispatchers.IO) { SubtitleCueCache.fetch(subtitle.url) }
            // Stale if the user picked another subtitle or content changed meanwhile
            if (loadToken != externalSubtitleLoadToken) return@launch
            onExternalSubtitleLoaded(subtitle, parsed, previousStremioIndex)
        }
    }

    private fun onExternalSubtitleLoaded(
        subtitle: StremioSubtitle,
        cues: List<SubtitleCue>,
        previousStremioIndex: Int
    ) {
        if (cues.isEmpty()) {
            android.util.Log.w("StremioSubs", "Failed to load/parse external subtitle: ${subtitle.url}")
            host.failedSubtitleUrls.add(subtitle.url)   // don't auto-select this broken sub again
            host.showStatusPillTransient("Couldn't load ${subtitle.displayName}")
            // Keep whatever was rendering before — do NOT stopExternalSubtitleRendering()
            // here (it would wipe a working subtitle and cancel the error pill).
            // Just restore the selection state to the previously-good subtitle.
            host.currentStremioSubtitleIndex = previousStremioIndex
            if (previousStremioIndex < 0) {
                // Nothing external was active before; the selecting caller already
                // disabled embedded text tracks in anticipation. Re-enable so
                // ExoPlayer can restore an embedded subtitle.
                host.trackSelector?.let { ts ->
                    ts.parameters = ts.parameters.buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                        .build()
                }
            }
            if (subtitleSettingsVisible) refreshSubtitlePanelForLoading()
            host.tryAutoSelectAddonSubtitle()
            return
        }

        // Disable embedded text tracks so they don't double-render under the
        // side-loaded cues (covers the auto-select path, which doesn't go
        // through applySelectedSubtitleTrack).
        host.trackSelector?.let { ts ->
            ts.parameters = ts.parameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
        }

        externalSubtitleCues = cues
        externalSubtitleActive = true
        activeExternalSubtitleUrl = subtitle.url
        lastExternalCueText = null
        // Clear immediately: disabling the embedded track fires onCues(empty),
        // but that's now suppressed, and the first ticker render early-returns
        // when no cue is active — without this a stale embedded line would
        // freeze on screen until the next external cue.
        if (host.subtitleOverlayReady) host.subtitleOverlay.setCues(emptyList())
        startExternalSubtitleTicker()
        // Remembered sync for this exact content+subtitle (keyed by the same
        // identity that scopes the live offset): restore BEFORE the ladder
        // arms — a non-zero recall parks the ladder via its own offset==0
        // gate. Announced: an offset appearing out of nowhere must say why.
        val recalledIdentity = currentSubtitleIdentity()
        val recalled = recalledIdentity?.let { SubtitleSettings.recallSyncOffset(activity, it) }
        if (recalled != null) {
            SubtitleSettings.setSyncOffsetMs(activity, recalled)
            // Same initialized-guard the overlay clear above uses: the side
            // ticker reads the offset at lookup time anyway, so on a very
            // early load the apply can be safely skipped rather than touch a
            // lateinit view.
            if (host.subtitleOverlayReady) applySubtitleSettings()
            host.autoSyncResultLabel = "↻ ${SubtitleSettings.formatSyncOffset(recalled)}"
            host.autoSyncResultUrl = subtitle.url
            host.autoSyncAppliedOffsetMs = recalled
            host.scheduleAutoSyncVerify()
            host.showSyncToast(
                "↻", AutoSyncColors.OK,
                "Sync restored",
                autoHideMs = 3_000,
            )
        }
        host.startAutoSyncLadder()
        host.showStatusPillTransient("✓ ${subtitle.displayName}")
        android.util.Log.d("StremioSubs", "Side-rendering ${cues.size} cues from ${subtitle.displayName}")
    }

    /** Stop side-rendering and give the overlay back to the player's onCues. */
    fun stopExternalSubtitleRendering() {
        host.cancelAutoSyncLadder()
        host.cancelAutoSyncVerify()
        host.autoSyncAppliedOffsetMs = null
        externalSubtitleLoadToken++
        externalSubtitleTicker?.let { host.externalSubtitleHandler.removeCallbacks(it) }
        externalSubtitleTicker = null
        if (externalSubtitleActive || externalSubtitleCues.isNotEmpty()) {
            externalSubtitleActive = false
            activeExternalSubtitleUrl = null
            externalSubtitleCues = emptyList()
            lastExternalCueText = null
            if (host.subtitleOverlayReady) host.subtitleOverlay.setCues(emptyList())
            // Re-enable the embedded text track type that onExternalSubtitleLoaded
            // disabled — otherwise embedded-subtitle auto-selection stays dead for
            // every subsequent item. Callers that want text off (Off selection)
            // re-apply their own params right after this returns.
            host.trackSelector?.let { ts ->
                ts.parameters = ts.parameters.buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                    .build()
            }
        }
        host.hideStatusPill()
    }

    fun startExternalSubtitleTicker() {
        externalSubtitleTicker?.let { host.externalSubtitleHandler.removeCallbacks(it) }
        val ticker = object : Runnable {
            override fun run() {
                if (!externalSubtitleActive) return
                renderExternalSubtitleCue()
                host.externalSubtitleHandler.postDelayed(this, EXTERNAL_SUBTITLE_TICK_MS)
            }
        }
        externalSubtitleTicker = ticker
        ticker.run()
    }

    private fun renderExternalSubtitleCue() {
        val cues = externalSubtitleCues
        if (cues.isEmpty()) return
        // Same convention as the sync line picker: a positive offset means the
        // subtitle text lags the audio, so we look up cues at (position - offset).
        val effectiveMs = (host.player?.currentPosition ?: return) - SubtitleSettings.getSyncOffsetMs(activity)

        // Binary search for the last cue starting at or before effectiveMs,
        // then collect all still-active overlapping cues. Cues are sorted only
        // by start time, so a long-running cue (e.g. an anime sign/song event)
        // can begin many entries before the current dialogue line — scan the
        // whole prefix (cheap: a few thousand comparisons a few times a second).
        var lo = 0
        var hi = cues.size - 1
        var last = -1
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            if (cues[mid].startMs <= effectiveMs) { last = mid; lo = mid + 1 } else hi = mid - 1
        }

        var text: String? = null
        if (last >= 0) {
            val active = StringBuilder()
            for (i in 0..last) {
                val cue = cues[i]
                if (cue.startMs <= effectiveMs && effectiveMs < cue.endMs) {
                    if (active.isNotEmpty()) active.append('\n')
                    active.append(cue.text)
                }
            }
            if (active.isNotEmpty()) text = active.toString()
        }

        if (text == lastExternalCueText) return
        lastExternalCueText = text
        host.subtitleOverlay.setCues(
            if (text == null) emptyList()
            else listOf(Cue.Builder().setText(text).build())
        )
    }

    /**
     * A stable key for "the subtitle currently on screen", used to scope the
     * sync offset (see SubtitleSettings). It changes whenever the subtitle
     * changes OR the content/episode changes, so the offset — which is only
     * valid for the exact subtitle it was dialed in against — resets by
     * construction. Returns null when no subtitle is showing.
     *
     * The content key is folded in so the same embedded language (or a reused
     * subtitle URL) across two different episodes never shares an offset.
     */
    fun currentSubtitleIdentity(): String? {
        val contentKey = host.payload?.items?.getOrNull(host.currentIndex)?.resumeId ?: "idx:${host.currentIndex}"
        if (externalSubtitleActive) {
            val url = activeExternalSubtitleUrl ?: return null
            return "$contentKey|ext:$url"
        }
        // Fold all embedded text tracks into a single "emb" identity: switching
        // between embedded tracks of the SAME episode keeping the offset is an
        // acceptable edge; the offset only needs to reset across episodes (the
        // content key handles that) and across the external⇄embedded boundary.
        val embeddedSelected = host.player?.currentTracks?.groups?.any { group ->
            group.type == C.TRACK_TYPE_TEXT && (0 until group.length).any { group.isTrackSelected(it) }
        } ?: false
        return if (embeddedSelected) "$contentKey|emb" else null
    }

    fun applySubtitleSettings() {
        host.subtitleOverlay.setFixedTextSize(
            TypedValue.COMPLEX_UNIT_SP,
            SubtitleSettings.getFontSizeSp(activity)
        )
        host.subtitleOverlay.setStyle(SubtitleSettings.buildCaptionStyle(activity))
        host.subtitleControlsLift.setBasePaddingFraction(SubtitleSettings.getElevationPaddingFraction(activity))
        // Only carry an offset onto the renderer when a subtitle is actually on
        // screen. Dialing the slider with subtitles off stores an offset under a
        // null owner (so the slider stays live), but it must NOT be pushed to the
        // renderer — otherwise a later auto-selected subtitle, which doesn't pass
        // through the selection reset, would render shifted while the read is 0.
        val hasSubtitle = currentSubtitleIdentity() != null
        val newOffsetUs = if (hasSubtitle) SubtitleSettings.getSyncOffsetMs(activity) * 1000L else 0L
        val oldOffsetUs = host.offsetRenderersFactory?.currentOffsetUs ?: 0L
        host.offsetRenderersFactory?.setOffsetUs(newOffsetUs)
        if (externalSubtitleActive) {
            // Side-rendered subtitles pick the offset up at lookup time — just
            // force an immediate re-render, no seek needed.
            lastExternalCueText = null
            renderExternalSubtitleCue()
        } else if (newOffsetUs != oldOffsetUs) {
            // Debounce: rapid offset changes (line picker tap, arrow key hold)
            // would otherwise pile up seeks and confuse the text renderer.
            subtitleSeekHandler.removeCallbacks(subtitleSeekRunnable)
            subtitleSeekHandler.postDelayed(subtitleSeekRunnable, 150)
        }
    }

    private fun applyAndPersistSubtitleSettings() {
        applySubtitleSettings()
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "saveSubtitleAppearance",
            SubtitleSettings.profileAppearanceSnapshot(activity),
        )
    }
}
