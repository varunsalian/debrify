package com.debrify.app.tv

import android.os.SystemClock
import android.util.Log
import androidx.media3.common.PlaybackException
import androidx.media3.datasource.HttpDataSource

/**
 * Phase 0 of the IPTV playback-resilience plan (dev/design/plans/
 * IPTV_FLAWLESS_PLAYBACK_PLAN.md): a per-tune diagnostics recorder.
 *
 * Every IPTV tune (launch, zap, Stremio candidate, HLS-forced retry) gets a
 * monotonically increasing generation and a handful of single-line `IptvDiag`
 * logcat entries: tune start, first frame, rebuffers, stall suspicion,
 * errors (with the HTTP status dug out of the cause chain), end of stream,
 * and — from Phase 1 on — which recovery source fired and what it did.
 *
 * This is how every later phase of the plan is judged (did time-to-first-frame
 * move? did the reconnect actually engage?) and how "is it the app or the
 * provider" Discord reports get triaged from a logcat capture.
 *
 * Deliberately inert unless a tune is active: non-IPTV playback never calls
 * [onTuneStart], so every other callback no-ops and ordinary
 * torrent/debrid/YouTube playback logs nothing. All methods must be called
 * from the main thread (they are — every caller is a player callback or a
 * main-thread handler).
 */
class IptvTuneDiagnostics {

    private companion object {
        const val TAG = "IptvDiag"

        /** No position advance for this long while playing = one stall-suspect
         *  line. Groundwork for the Phase-1 post-READY stall detector: Phase 0
         *  only OBSERVES, so the threshold errs generous. */
        const val STALL_SUSPECT_MS = 5_000L
    }

    private var generation = 0
    private var active = false
    private var channelName: String? = null
    private var protocol: String = "unknown"
    private var live = false

    private var tuneStartRealtime = 0L
    private var firstFrameLogged = false
    private var readyLogged = false

    private var rebufferCount = 0
    private var rebufferStartRealtime = 0L
    private var inRebuffer = false

    private var bytesLoaded = 0L

    private var lastPositionMs = -1L
    private var lastAdvanceRealtime = 0L
    private var stallSuspectLogged = false

    /** A new stream is being handed to the player. [forcedHls] is the
     *  extension-less-HLS retry set membership — it changes the protocol
     *  label, not the generation (a forced retry of the same URL is a new
     *  tune on purpose: its timings start over). */
    fun onTuneStart(name: String?, url: String, isLive: Boolean, forcedHls: Boolean) {
        generation++
        active = true
        channelName = name
        live = isLive
        protocol = when {
            url.startsWith("stremio-tv://") -> "stremio"
            forcedHls -> "hls-forced"
            url.substringBefore('?').endsWith(".m3u8", ignoreCase = true) -> "hls"
            else -> "progressive"
        }
        tuneStartRealtime = SystemClock.elapsedRealtime()
        firstFrameLogged = false
        readyLogged = false
        rebufferCount = 0
        inRebuffer = false
        bytesLoaded = 0L
        lastPositionMs = -1L
        lastAdvanceRealtime = tuneStartRealtime
        stallSuspectLogged = false
        line("tune-start", "url=${sanitizeUrl(url)}")
    }

    /** These lines get pasted into Discord. Xtream URLs carry credentials in
     *  the PATH (`/live/<user>/<pass>/123.ts`) and signed links carry tokens
     *  in the query — log scheme + host + last path segment only. */
    private fun sanitizeUrl(url: String): String {
        val noQuery = url.substringBefore('?')
        val schemeSplit = noQuery.split("://", limit = 2)
        if (schemeSplit.size < 2) return noQuery.take(40)
        val host = schemeSplit[1].substringBefore('/')
        val lastSegment = schemeSplit[1].substringAfterLast('/', "")
        return "${schemeSplit[0]}://$host/…/${lastSegment.take(40)}"
    }

    fun onReady(positionMs: Long) {
        if (!active) return
        if (!readyLogged) {
            readyLogged = true
            line("ready", "ttr=${sinceTune()}ms pos=${positionMs}ms")
        }
        if (inRebuffer) {
            inRebuffer = false
            val heldMs = SystemClock.elapsedRealtime() - rebufferStartRealtime
            line("rebuffer-end", "held=${heldMs}ms count=$rebufferCount")
        }
    }

    /** First decoded frame on screen — the number zap speed is judged by. */
    fun onFirstFrame() {
        if (!active || firstFrameLogged) return
        firstFrameLogged = true
        line("first-frame", "ttff=${sinceTune()}ms")
    }

    fun onBufferingStart(positionMs: Long) {
        if (!active) return
        // Pre-READY buffering is the tune itself, not a rebuffer.
        if (!readyLogged || inRebuffer) return
        inRebuffer = true
        rebufferCount++
        rebufferStartRealtime = SystemClock.elapsedRealtime()
        line("rebuffer-start", "pos=${positionMs}ms count=$rebufferCount ${advanceAge()}")
    }

    fun onPlaybackEnded(positionMs: Long) {
        if (!active) return
        line("ended", "pos=${positionMs}ms bytes=$bytesLoaded rebuffers=$rebufferCount ${advanceAge()}")
    }

    fun onError(error: PlaybackException) {
        if (!active) return
        val http = httpStatusOf(error)?.let { " http=$it" } ?: ""
        line(
            "error",
            "code=${error.errorCodeName}$http bytes=$bytesLoaded " +
                "rebuffers=$rebufferCount ${advanceAge()}"
        )
    }

    /** Fed by the existing 1s progress ticker. Cheap: arithmetic + at most one
     *  log line per stall episode. [playing] excludes user pause — a paused
     *  stream is supposed to hold still. */
    fun onProgress(positionMs: Long, playing: Boolean) {
        if (!active) return
        val now = SystemClock.elapsedRealtime()
        if (positionMs != lastPositionMs) {
            lastPositionMs = positionMs
            lastAdvanceRealtime = now
            if (stallSuspectLogged) {
                stallSuspectLogged = false
                line("stall-cleared", "pos=${positionMs}ms")
            }
            return
        }
        if (!playing || inRebuffer) return
        if (!stallSuspectLogged && now - lastAdvanceRealtime >= STALL_SUSPECT_MS) {
            stallSuspectLogged = true
            line("stall-suspect", "pos=${positionMs}ms ${advanceAge()} bytes=$bytesLoaded")
        }
    }

    /** Segment/chunk load accounting, from an AnalyticsListener. */
    fun onBytesLoaded(bytes: Long) {
        if (!active) return
        bytesLoaded += bytes
    }

    /** Phase 1+: the recovery state machine narrates itself through here
     *  ("source=ended action=retune attempt=2"). Phase 0 ships it unused so
     *  the log grammar is settled before the machine exists. */
    fun onRecovery(source: String, action: String, detail: String = "") {
        if (!active) return
        line("recovery", "source=$source action=$action${if (detail.isEmpty()) "" else " $detail"}")
    }

    /** Freeform breadcrumb (Stremio candidate hops etc.). */
    fun note(message: String) {
        if (!active) return
        line("note", message)
    }

    /** Playback left IPTV entirely (player teardown). */
    fun onSessionEnd() {
        if (!active) return
        active = false
        line("session-end", "bytes=$bytesLoaded rebuffers=$rebufferCount")
    }

    private fun sinceTune(): Long = SystemClock.elapsedRealtime() - tuneStartRealtime

    private fun advanceAge(): String =
        "advanceAge=${SystemClock.elapsedRealtime() - lastAdvanceRealtime}ms"

    private fun line(event: String, detail: String) {
        Log.i(
            TAG,
            "gen=$generation event=$event proto=$protocol live=$live " +
                "ch=\"${channelName ?: "?"}\" $detail"
        )
    }

    private fun httpStatusOf(error: PlaybackException): Int? {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is HttpDataSource.InvalidResponseCodeException) return cause.responseCode
            cause = cause.cause
        }
        return null
    }
}
