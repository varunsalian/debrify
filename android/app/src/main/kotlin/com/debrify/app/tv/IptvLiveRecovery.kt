package com.debrify.app.tv

import android.os.Handler
import android.os.SystemClock

/**
 * Phases 1/3/5 of the IPTV playback-resilience plan (design/plans/
 * IPTV_FLAWLESS_PLAYBACK_PLAN.md): the ONE recovery state machine for live
 * IPTV playback in the native TV player.
 *
 * Every recovery source feeds this machine and nothing else re-tunes on its
 * own: clean EOF (STATE_ENDED), fatal player errors, the pre-READY tune
 * watchdog, the post-READY stall detector, the video-render stall detector
 * (frames frozen under an advancing audio clock — see [onVideoFrames]),
 * lifecycle rejoin, and the user's play-press retry. One machine means one
 * ladder — no two sources can ever schedule competing re-tunes.
 *
 * Shape of a recovery episode:
 *  - something fails → [requestRecovery] → re-tune attempts at 0/1/3/5s,
 *    then every 10s;
 *  - the episode turns VISIBLE (reconnect pill) once it has run ~2s — a
 *    first instant re-tune that works stays invisible, which is the point;
 *  - reaching READY hides the pill, but the episode only closes (attempt
 *    counter reset) after [STABLE_MS] of advancing playback — a stream that
 *    dies again in 5 seconds keeps climbing the ladder instead of hammering
 *    the origin with instant retries forever;
 *  - [SURRENDER_BUDGET_MS] of failing (or an attempt cap for error classes
 *    that repeat deterministically) ends the episode in a surrendered state
 *    with a visible retry affordance. AUTH-class failures surrender
 *    immediately: a 401/403/404 is the same answer every time, and looping
 *    on it is how apps hammer providers.
 *  - while the device is offline, the ladder idles (nothing to hammer) and
 *    the moment connectivity validates it fires one immediate attempt.
 *
 * Eligibility is the OWNER's business ([Callbacks.isEligible]): current
 * entry is live, the Stremio candidate ladder isn't mid-hunt, sleep rules,
 * playWhenReady. The machine re-checks at every decision point, so a zap to
 * VOD mid-episode simply starves the episode.
 *
 * Threading: main thread only, like everything else in the player activity.
 */
class IptvLiveRecovery(
    private val handler: Handler,
    private val callbacks: Callbacks,
) {
    interface Callbacks {
        /** May this machine act right now? Re-checked before every attempt. */
        fun isEligible(): Boolean

        /** Re-tune the CURRENT live channel (same resolved URL + headers). */
        fun performRetune(source: String, attempt: Int)

        /** The episode has run long enough to narrate ("Reconnecting…"). */
        fun onEpisodeVisible(attempt: Int)

        /** Playback is back (READY) — hide the pill. */
        fun onRecovered()

        /** The machine gives up — visible failure state with a retry path. */
        fun onSurrender(source: String)
    }

    /** How a fatal error should climb the ladder. */
    enum class ErrorClass {
        /** Network-ish: full ladder. */
        TRANSIENT,

        /** 401/403/404: deterministic — surrender immediately, no retries. */
        AUTH,

        /** Decoder init/query: one retry (transient decoder hiccups exist),
         *  then surrender — the same stream will fail the same way. */
        DECODER,
    }

    companion object {
        /** Backoff ladder; past the end every attempt waits [LATE_DELAY_MS]. */
        private val DELAYS_MS = longArrayOf(0L, 1_000L, 3_000L, 5_000L)
        private const val LATE_DELAY_MS = 10_000L

        /** Advancing playback for this long closes the episode. */
        private const val STABLE_MS = 15_000L

        /** An episode older than this is narrated by the pill. */
        private const val VISIBLE_AFTER_MS = 2_000L

        /** Total failing time before the machine stops trying. */
        private const val SURRENDER_BUDGET_MS = 75_000L

        /** No position advance for this long while playback is wanted =
         *  post-READY stall (wedged decoder, stopped byte flow, stuck
         *  playlist — the review's "READY but frozen" class). */
        private const val STALL_WINDOW_MS = 12_000L

        /** A tune that never reaches READY at all gets this long. */
        private const val TUNE_WATCHDOG_MS = 20_000L

        private const val DECODER_MAX_ATTEMPTS = 1

        /** See [lastRetuneRealtime]. */
        private const val RETUNE_DEBOUNCE_MS = 300L

        /** Rendered-frame count static for this long, while the position
         *  clock stays fresh, = video-render stall (see [onVideoFrames]).
         *  Judged from READY, and generous enough that still-frame channels
         *  which repaint every few seconds never trip it. */
        private const val VIDEO_STALL_WINDOW_MS = 8_000L

        /** Plain re-tune first (transient decoder wedges heal on a codec
         *  reset), strict-demux re-tune second (the owner drops the
         *  aggressive TS join flags on attempt 2), then latch off. */
        private const val VIDEO_STALL_MAX_ATTEMPTS = 2

        /** The position clock must have advanced within this window for a
         *  frozen frame count to mean anything — a stopped clock is the
         *  stall/tune watchdogs' business, not the video detector's. Just
         *  over one 5s progress tick. */
        private const val POSITION_FRESH_MS = 6_000L

        /** Circuit breaker for the intermittent-wedge loop. The per-episode
         *  [VIDEO_STALL_MAX_ATTEMPTS] ladder only catches a video that STAYS
         *  frozen: any rendered frame resets the attempt climb, so a decoder
         *  that plays a few seconds, wedges, gets re-tuned, plays the re-tune's
         *  replayed buffer, then wedges AGAIN restarts at attempt 1 every
         *  cycle — plain re-tunes forever, each rewinding ~15s, and the
         *  strict-demux remedy at attempt 2 never gets its turn (the Google TV
         *  Streamer whose freeze strict-TS reduced from permanent to periodic,
         *  2026-08-18). So a stall within [VIDEO_STALL_RECUR_WINDOW_MS] of the
         *  previous video-stall re-tune is a RECURRENCE, and a recurrence
         *  skips straight to the strict-demux rung: the wedge already proved a
         *  plain re-tune doesn't stick. Once strict itself has been re-tuned
         *  [VIDEO_STALL_STRICT_MAX] times this tune and the wedge STILL
         *  recurs, re-tuning has nothing left to offer: latch off and let the
         *  imperfect-but-playing stream ride (audio was fine throughout).
         *  Recurrence state survives frame flow — only a real zap or user
         *  retry clears it — which is the whole point: the loop's own replays
         *  must not launder it back to attempt 1. A genuine one-off transient
         *  wedge heals, never recurs inside the window, and stays on the
         *  cheap plain-re-tune path. */
        private const val VIDEO_STALL_RECUR_WINDOW_MS = 180_000L
        private const val VIDEO_STALL_STRICT_MAX = 2

        /** The attempt number that means "strict demux" to the owner —
         *  [Callbacks.performRetune]'s contract is that attempt ≥ 2 drops the
         *  aggressive TS join flags (see performIptvLiveRetune). */
        private const val VIDEO_STALL_STRICT_RUNG = 2
    }

    /** True after the machine gave up; cleared by [userRetry] or a real zap. */
    var isSurrendered = false
        private set

    private var episodeActive = false
    private var episodeStartRealtime = 0L
    private var episodeVisible = false
    private var attempt = 0
    private var decoderAttempts = 0

    private var pending: Runnable? = null
    private var offline = false
    private var deferredSource: String? = null

    private var tuneStartRealtime = 0L
    private var readySeen = false
    private var lastPositionMs = Long.MIN_VALUE
    private var lastAdvanceRealtime = 0L
    private var stableSinceRealtime = 0L

    // Video-render stall state (see [onVideoFrames]).
    private var lastRenderedFrames = -1
    private var framesBaselineRealtime = 0L
    private var videoStallAttempts = 0
    private var videoStallLatched = false

    /** Elapsed-realtime of the last video-stall re-tune this TUNE, for the
     *  loop circuit breaker's recurrence test (see
     *  [VIDEO_STALL_RECUR_WINDOW_MS]). Deliberately NOT cleared when frames
     *  start flowing again — only a real zap / user retry clears it, so an
     *  intermittent wedge can't hide behind its own replays. */
    private var lastVideoStallRetuneRealtime = 0L

    /** How many strict-rung (effective attempt ≥ 2) video-stall re-tunes have
     *  fired this TUNE. Monotonic under frame flow for the same reason as
     *  [lastVideoStallRetuneRealtime]; at [VIDEO_STALL_STRICT_MAX] a further
     *  recurrence trips [videoStallLoopTripped] instead of re-tuning. */
    private var videoStallStrictRetunes = 0

    /** Sticky sibling of [videoStallLatched]: once the loop breaker trips, it
     *  STAYS tripped until a real zap / [cancel] / [userRetry]. [videoStallLatched]
     *  alone is not enough — the frame-flow branch clears that every time a
     *  re-tune's replayed buffer plays, which is exactly how the intermittent
     *  wedge would slip the leash and resume looping. */
    private var videoStallLoopTripped = false

    /** Set (and cleared) by the owner around a machine-driven re-tune so
     *  [onTuneStarted] can tell a recovery re-tune from a real zap. */
    var expectRetune = false

    // ── inputs ────────────────────────────────────────────────────────────

    /** Every live media hand-off (zap, launch, recovery re-tune). A real zap
     *  is a fresh start: any episode in progress belonged to the old tune. */
    fun onTuneStarted() {
        val now = SystemClock.elapsedRealtime()
        tuneStartRealtime = now
        readySeen = false
        lastPositionMs = Long.MIN_VALUE
        lastAdvanceRealtime = now
        stableSinceRealtime = 0L
        // A fresh prepare replaces the decoder, and with it the counters —
        // re-baseline unconditionally so a video-stall's own re-tune is
        // judged on the NEW decoder's output, not the wedged one's.
        lastRenderedFrames = -1
        framesBaselineRealtime = now
        if (expectRetune) {
            expectRetune = false
            return // recovery's own re-tune: the episode continues
        }
        cancelPending()
        episodeActive = false
        episodeVisible = false
        attempt = 0
        decoderAttempts = 0
        isSurrendered = false
        deferredSource = null
        resetVideoStallState()
    }

    /** The full video-stall reset — ladder, sticky latch, and the loop
     *  breaker's cross-episode evidence. ONLY a real zap, [cancel], or
     *  [userRetry] may call this; frame flow must never reach the last two
     *  fields (see [lastVideoStallRetuneRealtime]). */
    private fun resetVideoStallState() {
        videoStallAttempts = 0
        videoStallLatched = false
        videoStallLoopTripped = false
        videoStallStrictRetunes = 0
        lastVideoStallRetuneRealtime = 0L
    }

    fun onReady() {
        readySeen = true
        // Frames are judged from READY, not from tune start: nothing renders
        // pre-READY, so counting the tune's setup time against the video-
        // stall window would punish slow joins twice.
        framesBaselineRealtime = SystemClock.elapsedRealtime()
        if (episodeActive) callbacks.onRecovered()
    }

    /** Fed by the 5s progress ticker. [wantsPlayback] must be playWhenReady,
     *  NOT isPlaying — a buffering wedge reports isPlaying=false, and a user
     *  pause is exactly what must NOT look like a stall. */
    fun onProgress(positionMs: Long, wantsPlayback: Boolean) {
        val now = SystemClock.elapsedRealtime()
        if (positionMs != lastPositionMs) {
            lastPositionMs = positionMs
            lastAdvanceRealtime = now
            if (readySeen && wantsPlayback) {
                if (stableSinceRealtime == 0L) stableSinceRealtime = now
                if (episodeActive && now - stableSinceRealtime >= STABLE_MS) {
                    // Recovered for real: close the episode.
                    episodeActive = false
                    episodeVisible = false
                    attempt = 0
                    decoderAttempts = 0
                }
            }
            return
        }
        stableSinceRealtime = 0L
        if (!wantsPlayback || isSurrendered || pending != null) return
        if (!readySeen) {
            // Pre-READY watchdog: the tune itself is going nowhere.
            if (now - tuneStartRealtime >= TUNE_WATCHDOG_MS) {
                requestRecovery("tune-watchdog")
            }
            return
        }
        if (now - lastAdvanceRealtime >= STALL_WINDOW_MS) {
            requestRecovery("stall")
        }
    }

    /** Fed by the same progress ticker as [onProgress], from the video
     *  renderer's decoder counters. Closes the machine's structural blind
     *  spot (review finding #13): a wedged video decoder under live audio
     *  keeps the position clock advancing — audio is the clock master — so
     *  neither the stall detector nor the tune watchdog above ever fires,
     *  and the screen freezes while the sound carries on (the Google TV
     *  Streamer report, 2026-08-15: strict MediaTek decoders wedging on
     *  mid-GOP joins under the aggressive TS flags). A frame count that
     *  hasn't moved for [VIDEO_STALL_WINDOW_MS] while the clock stays fresh
     *  is that exact state.
     *
     *  The response is deliberately NOT a generic episode: that ladder ends
     *  in a "Stream lost" surrender pill, which is wrong while audio is
     *  audibly fine. Instead: one plain re-tune (transient wedges heal on a
     *  codec reset), one strict-demux re-tune ([Callbacks.performRetune]
     *  receives source "video-stall" and the attempt number; the owner drops
     *  the aggressive TS join flags at attempt 2), then a latch — a channel
     *  whose video STILL hasn't moved is static content (radio cover art) or
     *  beyond re-tuning, and audio plays on unbothered.
     *
     *  [renderedFrames] < 0 or [hasVideoTrack] false (audio-only entries)
     *  disarm the detector: zero frames is those channels' normal. Idle
     *  while an episode is active — the generic ladder owns the player then,
     *  and a frame gap mid-recovery is expected. */
    fun onVideoFrames(renderedFrames: Int, hasVideoTrack: Boolean, wantsPlayback: Boolean) {
        if (!hasVideoTrack || renderedFrames < 0) {
            lastRenderedFrames = -1
            return
        }
        val now = SystemClock.elapsedRealtime()
        if (lastRenderedFrames < 0 || renderedFrames < lastRenderedFrames) {
            // First sight of this decoder's counters — or a decoder swap
            // reset them. Baseline, don't judge.
            lastRenderedFrames = renderedFrames
            framesBaselineRealtime = now
            return
        }
        if (renderedFrames > lastRenderedFrames) {
            lastRenderedFrames = renderedFrames
            framesBaselineRealtime = now
            if (videoStallAttempts > 0 || videoStallLatched) {
                videoStallAttempts = 0
                videoStallLatched = false
                // Frames flow again: stand down, and take the attempt-2 pill
                // down too — unless a generic episode is running, in which
                // case the pill is ITS narration and stays until it closes.
                // (onRecovered with no pill up is just a harmless re-arm of
                // the zap frame-hold.)
                if (!episodeActive) callbacks.onRecovered()
            }
            return
        }
        // Count unchanged.
        if (videoStallLatched || videoStallLoopTripped ||
            episodeActive || isSurrendered || pending != null
        ) return
        if (offline || !wantsPlayback || !readySeen) return
        // A stopped clock is the position detectors' business, not ours.
        if (now - lastAdvanceRealtime > POSITION_FRESH_MS) return
        if (now - framesBaselineRealtime < VIDEO_STALL_WINDOW_MS) return
        if (now - lastRetuneRealtime < RETUNE_DEBOUNCE_MS) return
        if (!callbacks.isEligible()) return
        // Loop circuit breaker: a stall this soon after the last video-stall
        // re-tune means the cure didn't stick (an intermittent wedge, not a
        // one-off) — skip the plain rung and go straight to strict, and once
        // strict itself has been retried out, stop fighting: looping the user
        // through ~15s replays is worse than the glitch.
        val recurrence = lastVideoStallRetuneRealtime != 0L &&
            now - lastVideoStallRetuneRealtime <= VIDEO_STALL_RECUR_WINDOW_MS
        if (!recurrence) {
            // No re-tune inside the window behind this stall: a NEW wedge
            // cluster, not the old one still failing. Strict budget spent on
            // an earlier cluster is stale evidence — without this reset, a
            // channel that wedge-clustered once would greet every later
            // cluster with one plain re-tune and an instant sticky latch.
            videoStallStrictRetunes = 0
        }
        if (recurrence && videoStallStrictRetunes >= VIDEO_STALL_STRICT_MAX) {
            videoStallLatched = true
            videoStallLoopTripped = true
            callbacks.onRecovered()
            return
        }
        videoStallAttempts++
        framesBaselineRealtime = now // one judgment per window
        if (videoStallAttempts > VIDEO_STALL_MAX_ATTEMPTS) {
            videoStallLatched = true
            callbacks.onRecovered()
            return
        }
        // The rung actually re-tuned at: the per-episode climb, or the strict
        // rung directly on a recurrence — the wedge already proved a plain
        // re-tune doesn't stick. (videoStallAttempts is 1 or 2 here; the
        // > MAX return above already fired for anything higher.)
        val effectiveAttempt =
            if (recurrence) VIDEO_STALL_STRICT_RUNG else videoStallAttempts
        // Post rather than call: the progress ticker is on the stack here, and
        // a synchronous performRetune would restartProgressUpdates from INSIDE
        // the tick — that post plus the tick's own tail post leaves two 5s
        // ticker chains running until the next zap. Parking the attempt in
        // [pending] also gives it the ladder's cancellation story (a real
        // zap's cancelPending kills it) and keeps the one-pending-retune
        // invariant literal.
        val runnable = Runnable {
            pending = null
            if (isSurrendered || offline || !callbacks.isEligible()) return@Runnable
            // The breaker's evidence is committed HERE, past the bail guard —
            // a pause/zap/offline landing between the post and this drain
            // must not spend a strict slot or stamp the recurrence clock for
            // a re-tune that never fired (nor raise a pill with nothing in
            // flight).
            if (effectiveAttempt >= VIDEO_STALL_STRICT_RUNG) {
                videoStallStrictRetunes++
                // The first attempt stays invisible (the machine's own idiom:
                // an instant heal that works shouldn't narrate). Escalating
                // to the strict rung, the user deserves to know we're on it.
                callbacks.onEpisodeVisible(effectiveAttempt)
            }
            lastRetuneRealtime = SystemClock.elapsedRealtime()
            lastVideoStallRetuneRealtime = lastRetuneRealtime
            callbacks.performRetune("video-stall", effectiveAttempt)
        }
        pending = runnable
        handler.post(runnable)
    }

    /** STATE_ENDED on a live stream = the origin closed the connection.
     *  Returns true when the machine takes ownership of what happens next. */
    fun onEnded(): Boolean {
        if (!callbacks.isEligible()) return false
        return requestRecovery("ended")
    }

    /** A fatal player error the existing specific handlers didn't claim.
     *  Returns true when the machine takes ownership. */
    fun onFatalError(errorClass: ErrorClass): Boolean {
        if (!callbacks.isEligible()) return false
        return when (errorClass) {
            ErrorClass.AUTH -> {
                surrender("auth")
                true
            }
            ErrorClass.DECODER -> {
                if (decoderAttempts >= DECODER_MAX_ATTEMPTS) {
                    surrender("decoder")
                } else {
                    decoderAttempts++
                    requestRecovery("decoder-error")
                }
                true
            }
            ErrorClass.TRANSIENT -> requestRecovery("error")
        }
    }

    /** The user asked (play press on a dead stream, pill retry, lifecycle
     *  rejoin): fresh budget, immediate attempt. */
    fun userRetry(source: String) {
        cancelPending()
        isSurrendered = false
        episodeActive = true
        episodeStartRealtime = SystemClock.elapsedRealtime()
        episodeVisible = false
        attempt = 0
        decoderAttempts = 0
        resetVideoStallState()
        fire(source, immediate = true)
    }

    /** A real zap, playback teardown, or leaving the screen. */
    fun cancel() {
        cancelPending()
        episodeActive = false
        episodeVisible = false
        attempt = 0
        decoderAttempts = 0
        isSurrendered = false
        deferredSource = null
        resetVideoStallState()
        lastRenderedFrames = -1
    }

    /** Connectivity gate: offline idles the ladder (one attempt parked, not
     *  burning the budget); regaining network fires it immediately. */
    fun setOffline(nowOffline: Boolean) {
        if (offline == nowOffline) return
        offline = nowOffline
        if (!nowOffline) {
            val source = deferredSource ?: return
            deferredSource = null
            // The outage wasn't the stream's fault: don't let the time spent
            // offline exhaust the surrender budget.
            if (episodeActive) episodeStartRealtime = SystemClock.elapsedRealtime()
            fire("$source+online", immediate = true)
        }
    }

    // ── engine ────────────────────────────────────────────────────────────

    /** When the last re-tune was handed to the owner. Events landing within
     *  [RETUNE_DEBOUNCE_MS] of it are the OLD stream's queued death throes
     *  (a stale ENDED/error delivered while the new prepare is starting) —
     *  acting on them would double-schedule. A genuine failure of the new
     *  attempt arrives later and climbs the ladder normally; the watchdogs
     *  backstop anything the debounce swallows. (Codex round 2, finding 2.) */
    private var lastRetuneRealtime = 0L

    private fun requestRecovery(source: String): Boolean {
        if (isSurrendered || pending != null) return true // already on it
        if (SystemClock.elapsedRealtime() - lastRetuneRealtime < RETUNE_DEBOUNCE_MS) {
            return true // stale delivery from the stream we just replaced
        }
        if (!callbacks.isEligible()) return false
        val now = SystemClock.elapsedRealtime()
        if (!episodeActive) {
            episodeActive = true
            episodeStartRealtime = now
        }
        if (now - episodeStartRealtime > SURRENDER_BUDGET_MS) {
            surrender(source)
            return true
        }
        if (offline) {
            // Park exactly one pending wish; setOffline(false) fires it.
            deferredSource = source
            return true
        }
        fire(source, immediate = false)
        return true
    }

    private fun fire(source: String, immediate: Boolean) {
        attempt++
        val delay = if (immediate) 0L else DELAYS_MS.getOrElse(attempt - 1) { LATE_DELAY_MS }
        maybeShowPill()
        val runnable = Runnable {
            pending = null
            if (isSurrendered || !callbacks.isEligible()) return@Runnable
            // Wi-Fi vanished during the delay: park this attempt instead of
            // firing into a dead network; setOffline(false) re-fires it.
            if (offline) {
                deferredSource = source
                return@Runnable
            }
            maybeShowPill()
            lastRetuneRealtime = SystemClock.elapsedRealtime()
            callbacks.performRetune(source, attempt)
        }
        pending = runnable
        handler.postDelayed(runnable, delay)
    }

    private fun maybeShowPill() {
        if (!episodeActive || episodeVisible) return
        if (SystemClock.elapsedRealtime() - episodeStartRealtime >= VISIBLE_AFTER_MS ||
            attempt >= 2
        ) {
            episodeVisible = true
            callbacks.onEpisodeVisible(attempt)
        }
    }

    private fun surrender(source: String) {
        cancelPending()
        isSurrendered = true
        episodeActive = false
        episodeVisible = false
        callbacks.onSurrender(source)
    }

    private fun cancelPending() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
    }
}
