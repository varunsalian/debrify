package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.launch

@OptIn(UnstableApi::class)
internal class TvIptvTuneController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val controlsDockController: TvControlsDockController
        var currentIptvHttpHeaders: Map<String, String>
        val currentIptvIndex: Int
        val iptvChannelStartController: TvIptvChannelStartController
        val iptvChannels: List<IptvChannelEntry>
        val iptvRecordingActionsController: TvIptvRecordingActionsController
        val iptvRecordingController: IptvRecordingController
        var iptvStartOverActive: Boolean
        val iptvStartOverController: TvIptvStartOverController
        var iptvStartOverLoading: Boolean
        var iptvStartOverTimelineVisible: Boolean
        var iptvStrictTsActive: Boolean
        val iptvTuneDiagnostics: IptvTuneDiagnostics
        val isIptvMode: Boolean
        val player: ExoPlayer?
        val playerView: PlayerView
        fun restartProgressUpdates(): Unit
        val sleepStopLatched: Boolean
        val sleepTimerController: TvSleepTimerController
        val subtitleTrackReadiness: SubtitleTrackReadiness
    }

    // ── IPTV live recovery (Phases 1/3/5 of the resilience plan) ──────────
    //
    // The ONE owner of live re-tunes. Sources: STATE_ENDED, unclaimed fatal
    // errors, the tune watchdog, the stall detector, lifecycle rejoin, and
    // the user's play press on a dead stream. See IptvLiveRecovery.kt.

    /** True while a machine-driven re-tune is inside setIptvMediaItem, so
     *  onTuneStarted keeps the recovery episode instead of resetting it. */
    internal var iptvLiveRetuneInFlight = false

    /** Bottom-center "Reconnecting…" pill; created on first use, lives in
     *  the decor content view so it floats over every player surface. */
    private var iptvReconnectPill: TextView? = null

    val iptvLiveRecovery: IptvLiveRecovery by lazy {
        IptvLiveRecovery(
            Handler(Looper.getMainLooper()),
            object : IptvLiveRecovery.Callbacks {
                override fun isEligible(): Boolean = iptvLiveRecoveryEligible()

                override fun performRetune(source: String, attempt: Int) {
                    performIptvLiveRetune(source, attempt)
                }

                override fun onEpisodeVisible(attempt: Int) {
                    showIptvReconnectPill("Reconnecting…")
                }

                override fun onRecovered() {
                    hideIptvReconnectPill()
                    // Re-arm the zap frame-hold a surrender may have cleared.
                    if (host.isIptvMode) host.playerView.setKeepContentOnPlayerReset(true)
                }

                override fun onSurrender(source: String) {
                    host.iptvTuneDiagnostics.onRecovery(source, "surrender")
                    // The held last frame must not keep painting a dead
                    // channel under the failure pill (plan invariant T11).
                    host.playerView.setKeepContentOnPlayerReset(false)
                    showIptvReconnectPill(
                        if (source == "auth") {
                            "Stream refused (expired or blocked) — press play to retry"
                        } else {
                            "Stream lost — press play to retry"
                        }
                    )
                }
            },
        )
    }

    /** The machine may act only on a LIVE entry with nothing else in charge:
     *  the Stremio candidate ladder owns recovery until its winner plays,
     *  sleep stops outrank reconnects, and a user pause (playWhenReady
     *  false — onStop pauses too) means nobody asked for playback. */
    fun iptvLiveRecoveryEligible(): Boolean {
        if (!host.isIptvMode || activity.isFinishing || activity.isDestroyed) return false
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return false
        if (!entry.isLive) return false
        if (host.sleepStopLatched || host.sleepTimerController.sleepTimerMode == SleepTimerMode.END_OF_ITEM) return false
        if (host.iptvChannelStartController.iptvStremioChannelKey != null && !host.iptvChannelStartController.iptvStremioWinnerReported) return false
        if (host.player?.playWhenReady != true) return false
        return true
    }

    /** Re-tune the current live channel with its full identity — the SAME
     *  resolved URL and per-channel headers (already in
     *  currentIptvHttpHeaders; setIptvMediaItem re-stamps both). A fresh
     *  prepare joins the live edge, never a stale position. */
    private fun performIptvLiveRetune(source: String, attempt: Int) {
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)?.takeIf { it.isLive } ?: return
        // A start-over URL is a finite archive segment. Recovery from its EOF
        // must join the channel's real live URL, not reopen the old segment.
        val url = if (host.iptvStartOverActive) entry.url else currentIptvStreamUrl ?: entry.url
        if (host.iptvStartOverActive || host.iptvStartOverLoading) {
            host.iptvStartOverActive = false
            host.iptvStartOverLoading = false
            host.iptvStartOverTimelineVisible = false
            host.iptvStartOverController.iptvCatchupToken++
            host.controlsDockController.styler.updateIptvControlPresentation(entry)
        }
        host.iptvTuneDiagnostics.onRecovery(source, "retune", "attempt=$attempt")
        // Video-stall attempt 1 was a plain re-tune (transient wedges heal
        // on a codec reset). Still frozen: drop the aggressive TS join flags
        // for this channel before going again — mid-GOP joins are exactly
        // what strict MediaTek decoders wedge on (frozen video, running
        // audio; the Google TV Streamer report). setIptvMediaItem below
        // recomputes iptvStrictTsActive from the set. Segmented/HLS streams
        // never see the progressive extractor factory, so a stall there says
        // nothing about the flags — recording one would only poison the
        // two-URLs-means-strict-device session escalation. Same for a tune
        // that was ALREADY strict (a twin — strict from birth — or a
        // session-strict device): its wedge was observed with the aggressive
        // flags off, so it is not evidence about them; without this gate two
        // failed twin trials would flip the whole session strict.
        if (source == "video-stall" && attempt >= 2 &&
            !host.iptvRecordingActionsController.isCurrentIptvSegmented() && !host.iptvStrictTsActive &&
            iptvStrictTsUrls.add(url)
        ) {
            host.iptvTuneDiagnostics.onRecovery(source, "strict-ts")
        }
        // Segmented streams have no strict rung — but an Xtream `.m3u8` has a
        // progressive `.ts` twin that does. Divert the strict-rung re-tune
        // into a reversible twin trial (see the twin-trial fields for the
        // full story). Only ever from an objectively detected video stall;
        // no twin / already failed / twin known HLS-forced falls through to
        // the plain re-tune below, exactly as before.
        if (source == "video-stall" && attempt >= 2 && host.iptvRecordingActionsController.isCurrentIptvSegmented() &&
            trial.iptvTwinTrialOriginalUrl == null && !trial.iptvTwinFailedUrls.contains(url)
        ) {
            val twin = xtreamTsTwin(url)
            if (twin != null && !iptvHlsForcedUrls.contains(twin)) {
                trial.beginIptvTwinTrial(entry, url, twin)
                return
            }
        }
        // A same-URL reopen would append a fresh TS connection — reset
        // PCR/PTS, no discontinuity marker — into the active tee file, and
        // setIptvMediaItem's finalize only fires on URL CHANGE. Finalize
        // here instead: the recorded portion stays a valid file; the
        // recovered stream simply isn't recorded further (plan invariant,
        // codex round 2 finding 7).
        if (host.iptvRecordingController.isActive) {
            host.iptvRecordingActionsController.finalizeIptvRecordingIfActive()
            host.iptvRecordingActionsController.updateRecordButtonState()
        }
        iptvLiveRetuneInFlight = true
        try {
            setIptvMediaItem(entry, url)
        } finally {
            iptvLiveRetuneInFlight = false
        }
    }

    private fun showIptvReconnectPill(text: String) {
        val pill = iptvReconnectPill ?: TextView(activity).apply {
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dpToPx(20), dpToPx(10), dpToPx(20), dpToPx(10))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#CC101418"))
                cornerRadius = dpToPx(22).toFloat()
            }
            val params = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
                bottomMargin = dpToPx(56)
            }
            // addContentView reaches the decor content FrameLayout, which
            // exists whatever the activity's own root layout is.
            activity.addContentView(this, params)
            iptvReconnectPill = this
        }
        pill.text = text
        pill.visibility = View.VISIBLE
    }

    fun hideIptvReconnectPill() {
        iptvReconnectPill?.visibility = View.GONE
    }

    private fun dpToPx(dp: Int): Int =
        (dp * activity.resources.displayMetrics.density).toInt()

    // URLs that failed extractor sniffing and play as HLS instead (bare
    // extension-less URLs — jmp2.uk-style — infer as progressive). Session
    // memory so zapping back starts straight in HLS with no failed attempt.
    internal val iptvHlsForcedUrls = HashSet<String>()

    /** Channels whose video wedged twice under the aggressive TS join flags
     *  (see the IPTV media-source factory in setupPlayer): their re-tunes
     *  and later visits demux strictly — IDR-only sync points, spec AU
     *  boundaries — the way the browse screen's stock preview player does.
     *  Session-scoped, like [iptvHlsForcedUrls]. Two distinct URLs earning
     *  a place means the DEVICE is the strict one (MediaTek boxes refusing
     *  mid-GOP joins), so from there every tune goes strict. */
    private val iptvStrictTsUrls = HashSet<String>()

    /** The Google TV Streamer must use the same stock TS join policy as the
     *  working browse preview from its first fullscreen tune. Other devices
     *  retain the faster aggressive join and the existing adaptive fallback. */
    private val iptvStartsWithStrictTs by lazy {
        IptvDeviceQuirks.startsIptvWithStrictTs(
            manufacturer = android.os.Build.MANUFACTURER,
            model = android.os.Build.MODEL,
            device = android.os.Build.DEVICE,
        )
    }
    internal val trial = TvIptvTwinTrial(activity, host, this)

    internal var currentIptvStreamUrl: String? = null

    /** The shared ExoPlayer media-item swap both IPTV entry points use. */
    fun setIptvMediaItem(entry: IptvChannelEntry, streamUrl: String) {
        // A genuine channel change while recording: finalize the previous
        // channel's file before the stream identity flips. An HLS-fallback retry
        // re-enters with the SAME url and is handled via abortAndDelete instead.
        if (host.iptvRecordingController.isActive && streamUrl != currentIptvStreamUrl) {
            host.iptvRecordingActionsController.finalizeIptvRecordingIfActive()
        }

        val metadata = MediaMetadata.Builder()
            .setTitle(entry.name)
            .setArtist(entry.group ?: "IPTV")
            .build()

        // The channel's own headers ride every request from here on (the
        // resolver installed in setupPlayer reads this per request). Set
        // BEFORE the media item so the first playlist fetch already has them.
        host.currentIptvHttpHeaders = entry.httpHeaders
        currentIptvStreamUrl = streamUrl
        // Any tune to a URL other than the twin under trial supersedes the
        // trial (a zap, a Stremio candidate, a lifecycle rejoin — every path
        // funnels through here). Without this, the trial's timeout could
        // later fire against a different channel.
        if (trial.iptvTwinTrialUrl != null && streamUrl != trial.iptvTwinTrialUrl) {
            trial.clearIptvTwinTrial()
        }
        // A same-twin recovery must not destroy a parked rollback (sleep can
        // leave that twin errored before the user presses Play). Tuning the
        // original consumes the restore; tuning anywhere else supersedes it.
        if (trial.iptvTwinTrialRestoreOriginal != null &&
            streamUrl != trial.iptvTwinTrialRestoreTwin
        ) {
            trial.clearParkedIptvTwinRestore()
        }
        // Demux mode for this tune: strict immediately on known-strict devices,
        // for channels that earned it, and for the whole session once two did
        // (that's a strict-decoder device, not two odd channels). Read per
        // media-period load by the extractor factory installed in setupPlayer.
        // A twin — on trial or accepted — is always strict: it exists to reach
        // the demux mode that works (see the twin-trial fields).
        host.iptvStrictTsActive =
            iptvStartsWithStrictTs ||
            iptvStrictTsUrls.contains(streamUrl) || iptvStrictTsUrls.size >= 2 ||
            streamUrl == trial.iptvTwinTrialUrl ||
            trial.iptvTwinPreferredUrls.containsValue(streamUrl)
        host.iptvTuneDiagnostics.onTuneStart(
            entry.name,
            streamUrl,
            entry.isLive,
            forcedHls = iptvHlsForcedUrls.contains(streamUrl),
        )
        if (iptvStartsWithStrictTs) {
            host.iptvTuneDiagnostics.note("demux=strict reason=device-quirk")
        }
        // A machine-driven re-tune keeps its recovery episode (attempt count,
        // surrender budget); a real zap/launch resets the machine — and takes
        // any reconnect pill with it (the pill described the OLD channel).
        iptvLiveRecovery.expectRetune = iptvLiveRetuneInFlight
        iptvLiveRecovery.onTuneStarted()
        if (!iptvLiveRetuneInFlight) hideIptvReconnectPill()
        // Every tune re-arms the zap frame-hold: a surrender turned it off,
        // and without this, zapping AWAY from the surrendered channel would
        // black-flash forever after (codex round 2, finding 17).
        host.playerView.setKeepContentOnPlayerReset(true)

        val mediaItem = MediaItem.Builder()
            .setUri(streamUrl)
            .setMediaMetadata(metadata)
            .apply {
                // Extension-less URLs infer as progressive and fail on HLS
                // playlists; once a URL has proven to be HLS (via the error
                // fallback) start it as HLS directly.
                if (iptvHlsForcedUrls.contains(streamUrl)) {
                    setMimeType(MimeTypes.APPLICATION_M3U8)
                }
            }
            .build()

        // Resume on-demand items where they were left off. Passing the start
        // position to setMediaItem rather than seeking after prepare avoids
        // briefly rendering frame 0. Live channels always take the plain form:
        // a start position on a live stream would drop it off the live edge.
        val startAt = if (entry.isLive) 0L else entry.resumePositionMs
        host.player?.apply {
            if (startAt > 0L) {
                host.subtitleTrackReadiness.onMediaReplacement()
                setMediaItem(mediaItem, startAt)
            } else {
                host.subtitleTrackReadiness.onMediaReplacement()
                setMediaItem(mediaItem)
            }
            prepare()
            playWhenReady = true
            play()
        }

        // IPTV mode never goes through playMediaDirect, so nothing else starts
        // the progress ticker here — without this the Flutter side is told
        // nothing about on-demand playback and can't save a resume position.
        host.restartProgressUpdates()

        // Reflect the new stream's HLS-ness on the record button (progressive →
        // enabled, HLS → disabled).
        host.iptvRecordingActionsController.updateRecordButtonState()
    }

    fun retryIptvAsHlsIfUnrecognized(error: PlaybackException): Boolean {
        val url = currentIptvStreamUrl ?: return false
        if (iptvHlsForcedUrls.contains(url)) return false // already tried
        var cause: Throwable? = error
        var unrecognized = false
        while (cause != null) {
            if (cause is UnrecognizedInputFormatException) {
                unrecognized = true
                break
            }
            cause = cause.cause
        }
        if (!unrecognized) return false

        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return false
        android.util.Log.d(
            "AndroidTvPlayer",
            "Unrecognized format for ${entry.name} — retrying as HLS"
        )
        // The stream is HLS, so any tee-recorded bytes are an unusable
        // playlist/segment mix — discard them and lock the button off.
        if (host.iptvRecordingController.isActive) {
            host.iptvRecordingController.abortAndDelete()
            Toast.makeText(
                activity,
                "Recording stopped — this channel is HLS",
                Toast.LENGTH_LONG,
            ).show()
        }
        iptvHlsForcedUrls.add(url)
        setIptvMediaItem(entry, url)
        host.iptvRecordingActionsController.updateRecordButtonState()
        // Stremio candidate: give the forced-HLS attempt a FULL stall window
        // (arming re-cancels the one ticking since candidate start — a slow
        // panel can eat most of that window on the failed sniff alone, and
        // the ladder would advance past a candidate that plays when forced).
        if (host.iptvChannelStartController.iptvStremioChannelKey != null) {
            host.iptvChannelStartController.armIptvStremioStallWatchdog()
        }
        return true
    }
}
