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

@OptIn(UnstableApi::class)
internal class TvAutoSyncController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val activeExternalSubtitleUrl: String?
        fun applySubtitleSettings(): Unit
        fun dp(value: Int): Int
        val externalSubtitleActive: Boolean
        val externalSubtitleHandler: Handler
        val player: ExoPlayer?
        val speechTap: SpeechFeatureTap?
        val subtitleScope: CoroutineScope
    }
    var autoSyncRunning = false

    // Auto-sync's toast (bottom-right, quiet): out of the subtitles' way at
    // bottom-center, and deliberately soft-spoken — sync happens by default
    // now, so its feedback must never feel like an alert.
    private var autoSyncPill: LinearLayout? = null
    private var autoSyncPillRing: AutoSyncRingView? = null
    private var autoSyncPillLabel: TextView? = null
    private var autoSyncPillResultShowing = false
    private var autoSyncPillWindowActive = false
    private var autoSyncPillAnnounceShowing = false
    // Dismiss the announce line only if it's still what's on screen — a
    // status shown meanwhile (manual sync-now) must not be clobbered.
    private val autoSyncPillAnnounceDismissRunnable = Runnable {
        if (autoSyncPillAnnounceShowing) {
            autoSyncPillAnnounceShowing = false
            hideAutoSyncPillView()
        }
    }
    private val autoSyncCardHideRunnable = Runnable { hideAutoSyncCard() }

    /** Last auto-sync outcome, shown on the menu row while its subtitle is active. */
    var autoSyncResultLabel: String? = null
    var autoSyncResultUrl: String? = null

    // Hands-free auto-sync (Settings → Playback, Android TV only): a ladder of
    // attempts as audio accrues — narrow search needs ~20s, wider ones more —
    // each silent unless it SUCCEEDS. Stops on success, on drift (retrying
    // won't fix a framerate mismatch), when the user dials any manual offset,
    // or when the rungs run out.
    private val autoSyncLadderSec = intArrayOf(20, 45, 90, 180)
    private var autoSyncLadderIdx = 0
    private var autoSyncLadderDone = false
    private var autoSyncLadderTick: Runnable? = null

    // Verify mode: after an offset WE applied (auto, manual button, or a
    // restored memory), periodically re-check the CURRENT region of the film
    // against that offset — piecewise alignment delivered where the user is.
    // The applied value doubles as the tamper flag: the moment the stored
    // offset differs from it, the user has taken over and verification ends.
    var autoSyncAppliedOffsetMs: Long? = null
    private var autoSyncVerifyTick: Runnable? = null
    private var autoSyncVerifyMisses = 0

    /**
     * Run the audio↔subtitle aligner over whatever anchored PCM history the
     * tap holds and apply the offset through the exact pathway the manual
     * slider and line picker use — one offset store, three ways to fill it.
     *
     * Every failure mode gets its own honest message; nothing is ever applied
     * below the aligner's confidence gate. The v1 lesson, kept on purpose: a
     * wrong auto-sync reads as "broken feature", a declined one as a miss.
     */
    fun runSubtitleAutoSync(auto: Boolean = false) {
        if (autoSyncRunning) return
        val tap = host.speechTap
        val url = host.activeExternalSubtitleUrl
        val rawCues = url?.let { SubtitleCueCache.get(it) }
        if (tap == null || rawCues.isNullOrEmpty()) {
            if (!auto) showSyncToast(
                "✕", AutoSyncColors.FAIL,
                "Pick an addon subtitle first",
                autoHideMs = 3_500,
            )
            return
        }
        val segments = tap.snapshot()
        val heardSec = (segments.sumOf { it.durationMs } / 1000.0).toInt()
        val anchoredSec =
            (segments.filter { it.anchorMs != Long.MIN_VALUE }.sumOf { it.durationMs } / 1000.0).toInt()
        android.util.Log.d(
            "AutoSync",
            "run: heard=${heardSec}s anchored=${anchoredSec}s segments=${segments.size} cues=${rawCues.size}"
        )
        if (anchoredSec < 1 && host.player?.isPlaying == true && !tap.hasRecentAudio(8_000)) {
            // Playing, yet no PCM ever reached the tap: passthrough/tunneled
            // audio, or a format the sink won't route through processors.
            if (auto) return
            showSyncToast(
                "✕", AutoSyncColors.FAIL,
                "Can't analyze this stream's audio",
                autoHideMs = 4_000,
            )
            return
        }
        autoSyncRunning = true
        if (!auto) {
            showSyncToast(
                "●", AutoSyncColors.BUSY,
                "Syncing subtitles…",
                autoHideMs = null,
            )
        } else if (autoSyncPillWindowActive) {
            // Ladder attempt: the heartbeat flips to its checking face
            // (white dot + label) while the aligner runs.
            showSyncToast("●", AutoSyncColors.BUSY, "Checking…", autoHideMs = null)
            autoSyncPillRing?.arcColor = Color.WHITE
        }
        host.subtitleScope.launch {
            val result = try {
                val cues = rawCues.map { CueSpan(it.startMs, it.endMs, it.text) }
                withContext(Dispatchers.Default) { SubtitleAligner.alignTiered(segments, cues) }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e // activity teardown — let the scope die quietly
            } catch (e: Throwable) {
                // Pure math should never throw; if it somehow does, the player
                // must not die for a subtitle convenience feature. Throwable,
                // not Exception: the 2026-08-25 MiBox crash was an
                // OutOfMemoryError (an Error) from a garbage-sized grid, and
                // it sailed straight past an Exception-only guard.
                android.util.Log.e("AutoSync", "aligner failed", e)
                AlignResult.NoMatch(0)
            } finally {
                autoSyncRunning = false
            }
            android.util.Log.d("AutoSync", "result: $result")
            // An intermediate rung that stays silent hands the screen back
            // its quiet; speaking results overwrite this at once.
            if (auto && autoSyncPillWindowActive) {
                hideAutoSyncPillView()
            }
            // The user may have switched subtitles during the analysis — the
            // computed offset belongs to the cue timeline it was computed FROM.
            if (host.activeExternalSubtitleUrl != url) {
                if (!auto) showSyncToast(
                    "●", AutoSyncColors.BUSY,
                    "Subtitle changed — try again",
                    autoHideMs = 3_000,
                )
                return@launch
            }
            fun remember(label: String) {
                autoSyncResultLabel = label
                autoSyncResultUrl = url
            }
            when (result) {
                is AlignResult.Synced -> {
                    autoSyncLadderDone = true
                    SubtitleSettings.setSyncOffsetMs(activity, result.offsetMs)
                    host.applySubtitleSettings()
                    autoSyncAppliedOffsetMs = result.offsetMs
                    scheduleAutoSyncVerify()
                    val fmt = SubtitleSettings.formatSyncOffset(result.offsetMs)
                    remember("✓ $fmt")
                    // Shown in BOTH modes — an offset changing under the user
                    // must always announce itself, however quietly.
                    // Number-free by design; the offset lives in the menu row
                    // (autoSyncResultLabel) and logcat.
                    showSyncToast(
                        "✓", AutoSyncColors.OK,
                        "Subtitles synced",
                        autoHideMs = 3_000,
                    )
                }
                is AlignResult.Drift -> {
                    autoSyncLadderDone = true // a longer listen can't fix drift
                    remember("drifting")
                    // Worth a word in both modes: drift means THIS subtitle
                    // file can never be fixed by an offset — switching is the
                    // only cure, so say so.
                    showSyncToast(
                        "✕", AutoSyncColors.FAIL,
                        "Subs drift on this file",
                        hint = "Try another subtitle",
                        autoHideMs = 4_500,
                    )
                }
                is AlignResult.NoMatch -> {
                    remember("no match")
                    if (auto) {
                        // Intermediate rungs stay silent; only the LAST rung's
                        // failure earns a (gentle) word, so the user knows the
                        // hand-off is theirs now.
                        if (autoSyncLadderIdx >= autoSyncLadderSec.size) {
                            showSyncToast(
                                "✕", AutoSyncColors.FAIL,
                                "Couldn't sync automatically",
                                hint = "Switch subs, or adjust in Subtitles → Timing",
                                autoHideMs = 5_000,
                            )
                        }
                        return@launch
                    }
                    showSyncToast(
                        "✕", AutoSyncColors.FAIL,
                        "No confident match",
                        hint = "Adjust in Subtitles → Timing",
                        autoHideMs = 4_500,
                    )
                }
                is AlignResult.NotEnoughAudio -> {
                    remember("${result.analyzedSec}s heard")
                    if (auto) {
                        if (autoSyncLadderIdx >= autoSyncLadderSec.size) {
                            showSyncToast(
                                "✕", AutoSyncColors.FAIL,
                                "Couldn't sync automatically",
                                hint = "Switch subs, or adjust in Subtitles → Timing",
                                autoHideMs = 5_000,
                            )
                        }
                        return@launch
                    }
                    showSyncToast(
                        "●", AutoSyncColors.BUSY,
                        "Keep watching a little, then try again",
                        autoHideMs = 3_500,
                    )
                }
            }
        }
    }

    /**
     * Arm the hands-free ladder for a freshly loaded addon subtitle. Each tick
     * asks the tap how much ANCHORED audio exists and fires the next attempt
     * when a rung's worth is on hand — so the first attempt (narrow search)
     * lands ~20s in, without the user touching anything. Skips entirely while
     * a manual offset is dialed in: the user's hand beats the machine's.
     */
    fun startAutoSyncLadder() {
        cancelAutoSyncLadder()
        if (!isAutoSyncPrefEnabled()) return
        // The one up-front sentence, then the heartbeat. Skipped when a
        // remembered offset just restored — that pill already said everything.
        if (SubtitleSettings.getSyncOffsetMs(activity) == 0L) {
            openAutoSyncPillWindow()
        }
        autoSyncLadderIdx = 0
        autoSyncLadderDone = false
        val tick = object : Runnable {
            override fun run() {
                if (autoSyncLadderDone || !host.externalSubtitleActive) return
                val tap = host.speechTap
                if (tap != null && !autoSyncRunning &&
                    SubtitleSettings.getSyncOffsetMs(activity) == 0L &&
                    autoSyncLadderIdx < autoSyncLadderSec.size &&
                    tap.anchoredDurationMs() >= autoSyncLadderSec[autoSyncLadderIdx] * 1000.0
                ) {
                    autoSyncLadderIdx++
                    android.util.Log.d("AutoSync", "ladder attempt ${autoSyncLadderIdx}/${autoSyncLadderSec.size}")
                    runSubtitleAutoSync(auto = true)
                }
                if (!autoSyncLadderDone && autoSyncLadderIdx < autoSyncLadderSec.size) {
                    host.externalSubtitleHandler.postDelayed(this, 8_000)
                }
            }
        }
        autoSyncLadderTick = tick
        host.externalSubtitleHandler.postDelayed(tick, 8_000)
    }

    fun cancelAutoSyncLadder() {
        autoSyncLadderTick?.let { host.externalSubtitleHandler.removeCallbacks(it) }
        autoSyncLadderTick = null
        autoSyncLadderDone = true
    }

    fun scheduleAutoSyncVerify() {
        cancelAutoSyncVerify()
        if (!isAutoSyncPrefEnabled()) return
        val tick = object : Runnable {
            override fun run() {
                maybeRunAutoSyncVerify()
                if (autoSyncVerifyTick === this) {
                    host.externalSubtitleHandler.postDelayed(this, 120_000)
                }
            }
        }
        autoSyncVerifyTick = tick
        host.externalSubtitleHandler.postDelayed(tick, 90_000)
    }

    fun cancelAutoSyncVerify() {
        autoSyncVerifyTick?.let { host.externalSubtitleHandler.removeCallbacks(it) }
        autoSyncVerifyTick = null
        autoSyncVerifyMisses = 0
    }

    /**
     * Re-check the region the user is CURRENTLY watching against the offset
     * we applied. Cues ride in pre-shifted by that offset, so a still-correct
     * sync correlates at lag 0 and any confident peak IS the residual to add.
     * Two confident-audio misses escalate the residual search from ±10s to
     * the full width over the same recent window — the ad-break/cut case,
     * where timing jumps too far for the narrow check to see.
     */
    private fun maybeRunAutoSyncVerify() {
        val applied = autoSyncAppliedOffsetMs ?: return
        if (!host.externalSubtitleActive || autoSyncRunning) return
        if (host.player?.isPlaying != true) return
        if (SubtitleSettings.getSyncOffsetMs(activity) != applied) {
            // The user dialed something since — their hand wins, permanently.
            cancelAutoSyncVerify()
            return
        }
        val tap = host.speechTap ?: return
        val url = host.activeExternalSubtitleUrl ?: return
        val rawCues = SubtitleCueCache.get(url) ?: return
        val pos = host.player?.currentPosition ?: return
        val windowStart = pos - 360_000
        val segments = tap.snapshot().filter {
            it.anchorMs != Long.MIN_VALUE &&
                it.anchorMs + it.durationMs >= windowStart &&
                it.anchorMs <= pos + 10_000
        }
        if (segments.sumOf { it.durationMs } < 30_000.0) return
        autoSyncRunning = true
        host.subtitleScope.launch {
            val escalated = autoSyncVerifyMisses >= 2
            val result = try {
                val centered = rawCues.map {
                    CueSpan(it.startMs + applied, it.endMs + applied, it.text)
                }
                withContext(Dispatchers.Default) {
                    if (escalated) {
                        SubtitleAligner.align(segments, centered)
                    } else {
                        SubtitleAligner.align(
                            segments, centered,
                            searchMs = 10_000.0,
                            minAudioMs = 25_000.0,
                            minCueOverlapFrames = SubtitleAligner.Tuning.NARROW_MIN_CUE_OVERLAP_FRAMES,
                            minCues = SubtitleAligner.Tuning.NARROW_MIN_CUES,
                            minZPeak = SubtitleAligner.Tuning.NARROW_MIN_ZPEAK,
                            minPsr = SubtitleAligner.Tuning.NARROW_MIN_PSR,
                            scales = doubleArrayOf(1.0),
                        )
                    }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                android.util.Log.e("AutoSync", "verify failed", e)
                AlignResult.NoMatch(0)
            } finally {
                autoSyncRunning = false
            }
            if (host.activeExternalSubtitleUrl != url || autoSyncAppliedOffsetMs != applied) return@launch
            when (result) {
                is AlignResult.Synced -> {
                    autoSyncVerifyMisses = 0
                    if (kotlin.math.abs(result.offsetMs) > 400) {
                        val newOffset = applied + result.offsetMs
                        SubtitleSettings.setSyncOffsetMs(activity, newOffset)
                        host.applySubtitleSettings()
                        autoSyncAppliedOffsetMs = newOffset
                        autoSyncResultLabel = "✓ ${SubtitleSettings.formatSyncOffset(newOffset)}"
                        autoSyncResultUrl = url
                        android.util.Log.d("AutoSync", "verify re-synced $applied -> $newOffset (escalated=$escalated)")
                        showSyncToast(
                            "↻", AutoSyncColors.OK,
                            "Re-synced",
                            autoHideMs = 3_000,
                        )
                    } else {
                        android.util.Log.d("AutoSync", "verify confirmed $applied (residual ${result.offsetMs}ms)")
                    }
                }
                is AlignResult.NoMatch -> {
                    autoSyncVerifyMisses++
                    android.util.Log.d("AutoSync", "verify miss ${autoSyncVerifyMisses}: $result")
                }
                else -> {
                    // NotEnoughAudio / Drift: wait for more playback; a miss
                    // count here would escalate on silence, not on evidence.
                    android.util.Log.d("AutoSync", "verify skipped: $result")
                }
            }
        }
    }

    /**
     * Settings → Playback → "Auto-sync addon subtitles" (Flutter-side pref).
     *
     * OFF by default — experimental opt-in. Must stay in lock-step with the
     * Dart default in StorageService.getSubtitleAutoSyncEnabled, or an
     * untouched toggle would mean different things on the two sides.
     */
    private fun isAutoSyncPrefEnabled(): Boolean =
        com.debrify.app.profiles.ProfilePreferenceProjection.getBoolean(
            activity,
            "subtitle_auto_sync_enabled",
            false,
        )

    private fun ensureAutoSyncPill(): LinearLayout {
        autoSyncPill?.let { return it }
        val ring = AutoSyncRingView(activity)
        val label = TextView(activity).apply {
            textSize = 11f
            setTextColor(0xEBFFFFFF.toInt())
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            letterSpacing = 0.08f
            isSingleLine = true
        }
        val pill = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(0xA80C0E12.toInt())
                cornerRadius = host.dp(18).toFloat()
                setStroke(host.dp(1), 0x21FFFFFF)
            }
            minimumHeight = host.dp(36)
            setPadding(host.dp(12), 0, host.dp(14), 0)
            elevation = host.dp(240).toFloat()
            visibility = View.GONE
            isFocusable = false
            addView(ring, LinearLayout.LayoutParams(host.dp(17), host.dp(17)))
            addView(
                label,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).also { it.marginStart = host.dp(8) },
            )
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.END
            ).also {
                it.bottomMargin = host.dp(42)
                it.rightMargin = host.dp(48)
            }
        }
        activity.findViewById<ViewGroup>(android.R.id.content).addView(pill)
        autoSyncPill = pill
        autoSyncPillRing = ring
        autoSyncPillLabel = label
        return pill
    }

    /**
     * Open the auto-sync window: one plain sentence for ~5 seconds, then the
     * screen stays quiet until a real event — a checking pass or a verdict —
     * has something to say. No countdown, no persistent indicator.
     */
    private fun openAutoSyncPillWindow() {
        stopAutoSyncPillWindow()
        autoSyncPillWindowActive = true
        showSyncToast(
            "●", AutoSyncColors.BUSY,
            "Trying to auto-sync subtitles — this may take a minute, keep watching",
            autoHideMs = null,
            uppercase = false,
        )
        autoSyncPillAnnounceShowing = true
        host.externalSubtitleHandler.postDelayed(autoSyncPillAnnounceDismissRunnable, 5_000)
    }

    private fun stopAutoSyncPillWindow() {
        host.externalSubtitleHandler.removeCallbacks(autoSyncPillAnnounceDismissRunnable)
        autoSyncPillAnnounceShowing = false
        autoSyncPillWindowActive = false
    }

    /**
     * Auto-sync status, rendered on the pill. The [glyph] keys the face:
     * "●" = active (pulsing dot + one line), anything else = result (colored
     * glyph + label; the window closes). [hint] is no longer drawn — the pill
     * stays one quiet line — so it goes to logcat instead. [autoHideMs] null
     * keeps the pill up until replaced. [uppercase] false keeps a sentence
     * (the announce line) in its natural case.
     */
    fun showSyncToast(
        glyph: String,
        accent: Int,
        title: String,
        hint: String? = null,
        autoHideMs: Long?,
        uppercase: Boolean = true,
    ) {
        host.externalSubtitleHandler.removeCallbacks(autoSyncCardHideRunnable)
        if (hint != null) Log.d("AutoSync", "pill: $title — $hint")
        autoSyncPillAnnounceShowing = false
        val pill = ensureAutoSyncPill()
        val active = glyph == "●"
        autoSyncPillResultShowing = !active
        if (!active) stopAutoSyncPillWindow()
        autoSyncPillRing?.visibility = if (active) View.VISIBLE else View.GONE
        autoSyncPillRing?.setPulsing(active)
        autoSyncPillRing?.arcColor = accent
        pill.setPadding(host.dp(12), 0, host.dp(14), 0)
        autoSyncPillLabel?.let { labelView ->
            labelView.visibility = View.VISIBLE
            val text = if (uppercase) title.uppercase() else title
            if (active) {
                labelView.setTextColor(0xEBFFFFFF.toInt())
                labelView.letterSpacing = if (uppercase) 0.08f else 0.01f
                labelView.text = text
            } else {
                labelView.setTextColor(accent)
                labelView.letterSpacing = 0.08f
                labelView.text = "$glyph  $text"
            }
        }
        (pill.background as? GradientDrawable)?.setStroke(
            host.dp(1),
            if (active) 0x21FFFFFF else (accent and 0x00FFFFFF) or 0x4D000000,
        )
        revealAutoSyncPill()
        if (autoHideMs != null) {
            host.externalSubtitleHandler.postDelayed(autoSyncCardHideRunnable, autoHideMs)
        }
    }

    private fun revealAutoSyncPill() {
        val pill = autoSyncPill ?: return
        pill.animate().cancel()
        if (pill.visibility != View.VISIBLE) {
            pill.alpha = 0f
            pill.translationY = host.dp(8).toFloat()
            pill.visibility = View.VISIBLE
        }
        pill.animate().alpha(1f).translationY(0f).setDuration(220).start()
    }

    /** View-only fade; window state is untouched (idle-hide relies on this). */
    private fun hideAutoSyncPillView() {
        autoSyncPillRing?.setPulsing(false)
        val pill = autoSyncPill ?: return
        if (pill.visibility != View.VISIBLE) return
        pill.animate().cancel()
        pill.animate().alpha(0f).translationY(host.dp(6).toFloat()).setDuration(240).withEndAction {
            pill.visibility = View.GONE
        }.start()
    }

    private fun hideAutoSyncCard() {
        host.externalSubtitleHandler.removeCallbacks(autoSyncCardHideRunnable)
        stopAutoSyncPillWindow()
        hideAutoSyncPillView()
    }
}
