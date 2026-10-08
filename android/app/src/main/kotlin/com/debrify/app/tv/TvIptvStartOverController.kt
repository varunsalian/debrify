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
internal class TvIptvStartOverController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        fun beginIptvPlayback(entry: IptvChannelEntry): Unit
        fun checkpointCurrentIptvPosition(): Unit
        fun commitIptvAllCategorySearch(): Unit
        var currentIptvIndex: Int
        fun hideIptvGuide(): Unit
        var iptvChannels: MutableList<IptvChannelEntry>
        val iptvEpgToken: Int
        val iptvGuideVisible: Boolean
        var iptvSeriesAudioKey: String?
        var iptvStartOverActive: Boolean
        val iptvStartOverButton: AppCompatButton?
        var iptvStartOverLoading: Boolean
        val iptvStartOverSeekButton: AppCompatButton?
        var iptvStartOverTimelineVisible: Boolean
        val player: ExoPlayer?
        fun resetSubtitleState(): Unit
        fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String): Unit
        fun showControlsAndFocusProgressBar(): Unit
        fun switchToIptvChannel(entry: IptvChannelEntry, adoptVisibleBrowseList: Boolean = true, checkpointOutgoing: Boolean = true): Unit
        val titleView: TextView
        fun updateIptvControlPresentation(entry: IptvChannelEntry?): Unit
        fun updateIptvEpisodeControls(): Unit
    }
    var iptvCatchupToken = 0

    fun updateIptvStartOverButton(entry: IptvChannelEntry? =
        host.iptvChannels.getOrNull(host.currentIptvIndex)
    ) {
        val button = host.iptvStartOverButton ?: return
        val available = entry != null &&
            (host.iptvStartOverActive || currentIptvStartOverProgramme(entry) != null)
        button.visibility = if (available) View.VISIBLE else View.GONE
        button.isEnabled = available && !host.iptvStartOverLoading
        button.text = when {
            host.iptvStartOverLoading -> "Preparing…"
            host.iptvStartOverActive -> "Go Live"
            else -> "Start Over"
        }
        button.contentDescription = when {
            host.iptvStartOverLoading -> "Preparing start over"
            host.iptvStartOverActive -> "Return to live channel"
            else -> "Start programme from beginning"
        }
        updateIptvStartOverSeekButton()
    }

    fun updateIptvStartOverSeekButton() {
        val button = host.iptvStartOverSeekButton ?: return
        button.visibility = if (host.iptvStartOverActive) View.VISIBLE else View.GONE
        button.isEnabled = host.iptvStartOverActive && !host.iptvStartOverLoading
        button.text = if (host.iptvStartOverTimelineVisible) "Hide Timeline" else "Seek"
        button.contentDescription = if (host.iptvStartOverTimelineVisible) {
            "Hide start over timeline"
        } else {
            "Show start over timeline"
        }
    }

    fun showIptvStartOverTimeline() {
        if (!host.iptvStartOverActive) return
        val duration = host.player?.duration ?: 0L
        if (duration <= 0L) {
            Toast.makeText(activity, "Timeline is still loading", Toast.LENGTH_SHORT).show()
            return
        }
        host.iptvStartOverTimelineVisible = !host.iptvStartOverTimelineVisible
        host.updateIptvControlPresentation(host.iptvChannels.getOrNull(host.currentIptvIndex))
        if (host.iptvStartOverTimelineVisible) {
            host.showControlsAndFocusProgressBar()
        } else {
            host.iptvStartOverSeekButton?.requestFocus()
        }
    }

    fun toggleIptvStartOver() {
        if (host.iptvStartOverLoading) return
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return
        if (host.iptvStartOverActive) {
            iptvCatchupToken++
            host.iptvStartOverActive = false
            host.iptvStartOverTimelineVisible = false
            host.updateIptvControlPresentation(entry)
            host.resetSubtitleState()
            host.beginIptvPlayback(entry)
            return
        }
        val programme = currentIptvStartOverProgramme(entry) ?: return
        requestIptvCatchup(entry, programme, fromControls = true)
    }

    fun cancelPendingIptvCatchupRequest() {
        iptvCatchupToken++
        if (!host.iptvStartOverLoading) return
        host.iptvStartOverLoading = false
        updateIptvStartOverButton()
    }

    fun requestIptvCatchup(
        channelEntry: IptvChannelEntry,
        programme: IptvEpgProgram,
        fromControls: Boolean = false,
    ) {
        val now = System.currentTimeMillis()
        if (!programme.hasArchive || programme.startMs > now) return
        val airing = now < programme.stopMs
        val channel = MainActivity.getAndroidTvPlayerChannel() ?: return
        val token = ++iptvCatchupToken
        val scheduleToken = host.iptvEpgToken
        if (airing) {
            host.iptvStartOverLoading = true
            updateIptvStartOverButton(channelEntry)
        }
        Toast.makeText(
            activity,
            if (airing) "Preparing start over…" else "Preparing replay…",
            Toast.LENGTH_SHORT,
        ).show()
        fun requestStillRelevant(): Boolean {
            val relevant = token == iptvCatchupToken &&
                (fromControls || (host.iptvGuideVisible && scheduleToken == host.iptvEpgToken))
            if (!relevant && token == iptvCatchupToken && airing) {
                host.iptvStartOverLoading = false
                updateIptvStartOverButton()
            }
            return relevant
        }
        channel.invokeMethod(
            "requestIptvCatchup",
            mapOf(
                "channelUrl" to channelEntry.url,
                "startMs" to programme.startMs,
                "channelName" to channelEntry.name,
                "logoUrl" to channelEntry.logoUrl,
                "playlistId" to channelEntry.sourceId,
                "httpHeaders" to channelEntry.httpHeaders,
                "archiveDisabled" to (channelEntry.tvArchive == "0"),
                "archiveEnabled" to (channelEntry.tvArchive == "1"),
                "archiveDurationDays" to channelEntry.tvArchiveDuration,
                "startOver" to airing,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    if (!requestStillRelevant()) return
                    val response = result as? Map<*, *>
                    val url = response?.get("url") as? String
                    if (url.isNullOrEmpty()) {
                        host.iptvStartOverLoading = false
                        updateIptvStartOverButton()
                        Toast.makeText(
                            activity,
                            "Replay is not available",
                            Toast.LENGTH_SHORT,
                        ).show()
                        return
                    }
                    if (airing) {
                        host.commitIptvAllCategorySearch()
                        host.hideIptvGuide()
                        val current = host.iptvChannels.getOrNull(host.currentIptvIndex)
                        if (current?.url != channelEntry.url) {
                            host.switchToIptvChannel(channelEntry)
                        }
                        val selected = host.iptvChannels.getOrNull(host.currentIptvIndex)
                        if (selected == null || selected.url != channelEntry.url) {
                            host.iptvStartOverLoading = false
                            updateIptvStartOverButton()
                            return
                        }
                        host.iptvStartOverLoading = false
                        host.iptvStartOverActive = true
                        host.iptvStartOverTimelineVisible = false
                        host.resetSubtitleState()
                        host.setIptvMediaItem(selected, url)
                        host.titleView.text = selected.displayName
                        updateIptvStartOverButton(selected)
                        return
                    }
                    host.checkpointCurrentIptvPosition()
                    val replay = IptvChannelEntry(
                        index = 0,
                        channelNumber = null,
                        name = response["title"] as? String ?: programme.title,
                        url = url,
                        logoUrl = channelEntry.logoUrl,
                        group = channelEntry.name,
                        isLive = false,
                        isCurrent = true,
                        resumePositionMs =
                            (response["resumePositionMs"] as? Number)?.toLong() ?: 0L,
                        httpHeaders = channelEntry.httpHeaders,
                        contentType = "vod",
                        sourceId = channelEntry.sourceId,
                        sourceName = channelEntry.sourceName,
                    )
                    host.iptvChannels.forEach { it.isCurrent = false }
                    host.iptvChannels = mutableListOf(replay)
                    host.currentIptvIndex = 0
                    host.iptvSeriesAudioKey = null
                    // Starting a replay is a real playback switch, just like
                    // selecting a live search result. Do not restore the
                    // category that preceded Search while closing the guide.
                    host.commitIptvAllCategorySearch()
                    host.hideIptvGuide()
                    host.resetSubtitleState()
                    host.beginIptvPlayback(replay)
                    host.titleView.text = replay.name
                    host.updateIptvEpisodeControls()
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (!requestStillRelevant()) return
                    host.iptvStartOverLoading = false
                    updateIptvStartOverButton()
                    Toast.makeText(
                        activity,
                        message ?: "Replay is not available",
                        Toast.LENGTH_SHORT,
                    ).show()
                }

                override fun notImplemented() {
                    if (requestStillRelevant()) {
                        host.iptvStartOverLoading = false
                        updateIptvStartOverButton()
                        Toast.makeText(
                            activity,
                            "Replay is not available",
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            },
        )
    }
}
