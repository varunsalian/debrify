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
 * watchdog, the post-READY stall detector, lifecycle rejoin, and the user's
 * play-press retry. One machine means one ladder — no two sources can ever
 * schedule competing re-tunes.
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
    }

    fun onReady() {
        readySeen = true
        if (episodeActive) callbacks.onRecovered()
    }

    /** Fed by the 1s progress ticker. [wantsPlayback] must be playWhenReady,
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
