package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.PlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.cancel

internal class TvIptvTwinTrial(
    private val activity: AppCompatActivity,
    private val host: TvIptvTuneController.Host,
    private val tune: TvIptvTuneController,
) {

    /** Start the reversible twin trial: tune the `.ts` twin under the
     *  machine's episode (expectRetune keeps ladder state) with a verdict
     *  deadline armed. A sustained advancing-frames streak accepts
     *  ([judgeIptvTwinTrial]); an error on the twin or the deadline →
     *  [failIptvTwinTrial]. */
    fun beginIptvTwinTrial(entry: IptvChannelEntry, original: String, twin: String) {
        host.iptvTuneDiagnostics.onRecovery("video-stall", "twin-ts", "trial")
        iptvTwinTrialOriginalUrl = original
        iptvTwinTrialUrl = twin
        iptvTwinTrialLastFrames = -1
        iptvTwinTrialAdvanceSince = 0L
        iptvTwinTrialStartedRealtime = SystemClock.elapsedRealtime()
        scheduleIptvTwinTrialTimeout(IPTV_TWIN_TRIAL_TIMEOUT_MS)
        tune.iptvLiveRetuneInFlight = true
        try {
            tune.setIptvMediaItem(entry, twin)
        } finally {
            tune.iptvLiveRetuneInFlight = false
        }
    }

    /** The trial's verdict, fed the rendered-frame counter by the 5s
     *  progress ticker. First valid sample is a baseline; every later
     *  sample must ADVANCE to keep the acceptance streak alive — a frozen
     *  sample (or a counter reset, i.e. a decoder swap from an interleaved
     *  machine re-tune) re-baselines and the streak starts over. Only a
     *  streak of [IPTV_TWIN_TRIAL_STABLE_MS] accepts; anything short of
     *  that leaves the verdict to the error path or the deadline. */
    fun judgeIptvTwinTrial(frames: Int) {
        val twin = iptvTwinTrialUrl ?: return
        if (tune.currentIptvStreamUrl != twin || frames < 0) return
        if (frames <= iptvTwinTrialLastFrames || iptvTwinTrialLastFrames < 0) {
            // Baseline, stalled, or reset: no streak to speak of.
            iptvTwinTrialLastFrames = frames
            iptvTwinTrialAdvanceSince = 0L
            return
        }
        iptvTwinTrialLastFrames = frames
        val now = SystemClock.elapsedRealtime()
        if (iptvTwinTrialAdvanceSince == 0L) {
            iptvTwinTrialAdvanceSince = now
            return
        }
        if (now - iptvTwinTrialAdvanceSince >= IPTV_TWIN_TRIAL_STABLE_MS) {
            acceptIptvTwinTrial()
        }
    }

    /** Frames advanced continuously for the stability window: keep the twin
     *  for the session. The original→twin preference applies at zap time,
     *  and the preferred twin keeps strict demux (both via the maps'
     *  readers) — nothing is enrolled in [iptvStrictTsUrls], whose
     *  two-URLs-means-strict-DEVICE escalation must only count wedges
     *  observed under the aggressive flags, which the twin (strict from
     *  birth) never was. */
    private fun acceptIptvTwinTrial() {
        val original = iptvTwinTrialOriginalUrl ?: return
        val twin = iptvTwinTrialUrl ?: return
        if (tune.currentIptvStreamUrl != twin) return
        clearIptvTwinTrial()
        iptvTwinPreferredUrls[original] = twin
        host.iptvTuneDiagnostics.onRecovery("video-stall", "twin-ts", "accepted")
    }

    /** The twin errored or never rendered: blacklist it for the session and
     *  restore the original HLS stream under the machine's episode. The
     *  machine handles what follows on its own — the restored stream's
     *  frozen video recurs, the twin rung is now closed, and the recurrence
     *  ladder latches: audio plays on, today's end state, never worse. */
    fun failIptvTwinTrial(reason: String) {
        val original = iptvTwinTrialOriginalUrl ?: return
        val twin = iptvTwinTrialUrl
        clearIptvTwinTrial()
        // A zap/teardown superseded the trial: nothing to restore, and the
        // twin was never judged — don't blacklist it on an interruption.
        if (twin == null || tune.currentIptvStreamUrl != twin) return
        if (activity.isFinishing || activity.isDestroyed) return
        iptvTwinFailedUrls.add(original)
        host.iptvTuneDiagnostics.onRecovery("video-stall", "twin-ts", "failed:$reason")
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)?.takeIf { it.isLive } ?: return
        tune.iptvLiveRetuneInFlight = true
        try {
            tune.setIptvMediaItem(entry, original)
        } finally {
            tune.iptvLiveRetuneInFlight = false
        }
    }

    /** A verdict timeout is recovery too, so it must respect explicit pause
     *  just like [IptvLiveRecovery]. Park the original instead of calling
     *  setIptvMediaItem (which deliberately starts playback); the next
     *  explicit Play or foreground resume consumes the parked restore. */
    private fun onIptvTwinTrialTimeout() {
        if (host.player?.playWhenReady != true || host.sleepStopLatched) {
            parkIptvTwinTrialRestore()
            return
        }
        failIptvTwinTrial("timeout")
    }

    private fun scheduleIptvTwinTrialTimeout(delayMs: Long) {
        iptvTwinTrialTimeout?.let { iptvTwinTrialHandler.removeCallbacks(it) }
        val timeout = Runnable { onIptvTwinTrialTimeout() }
        iptvTwinTrialTimeout = timeout
        iptvTwinTrialHandler.postDelayed(timeout, delayMs.coerceAtLeast(0L))
    }

    /** Each READY on the twin restarts the verdict deadline at the
     *  post-READY bound: the proof (baseline sample + advancing streak) can
     *  only begin once rendering can, so prepare time — including an
     *  interleaved tune-watchdog re-tune's — must not be charged against
     *  the streak. Without this, a twin READY around the 20s watchdog
     *  boundary would be killed by the trial-start deadline one sample
     *  short of acceptance. */
    fun rearmIptvTwinTrialDeadline() {
        val twin = iptvTwinTrialUrl ?: return
        if (tune.currentIptvStreamUrl != twin) return
        val started = iptvTwinTrialStartedRealtime
        if (started == 0L) return
        val absoluteRemaining =
            started + IPTV_TWIN_TRIAL_MAX_MS - SystemClock.elapsedRealtime()
        scheduleIptvTwinTrialTimeout(
            minOf(IPTV_TWIN_TRIAL_POST_READY_MS, absoluteRemaining)
        )
    }

    /** Suspend an unjudged twin without changing the paused player's media
     *  item. The pair is essential: a same-twin retry must preserve the
     *  rollback, while a tune anywhere else invalidates it. */
    fun parkIptvTwinTrialRestore(): Boolean {
        val original = iptvTwinTrialOriginalUrl ?: return false
        val twin = iptvTwinTrialUrl ?: return false
        if (tune.currentIptvStreamUrl != twin) return false
        iptvTwinTrialRestoreOriginal = original
        iptvTwinTrialRestoreTwin = twin
        clearIptvTwinTrial()
        return true
    }

    /** Restore a trial parked by pause/onStop. Used by both lifecycle resume
     *  and the explicit Play button because Play need not cause onStart. */
    fun restoreParkedIptvTwinIfNeeded(): Boolean {
        val original = iptvTwinTrialRestoreOriginal ?: return false
        val twin = iptvTwinTrialRestoreTwin
        clearParkedIptvTwinRestore()
        if (twin == null || tune.currentIptvStreamUrl != twin) return false
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)?.takeIf { it.isLive }
            ?: return false
        tune.setIptvMediaItem(entry, original)
        return true
    }

    fun clearParkedIptvTwinRestore() {
        iptvTwinTrialRestoreOriginal = null
        iptvTwinTrialRestoreTwin = null
    }

    /** Disarm the trial without a verdict. Safe to call at any time; every
     *  tune to a non-twin URL and both recovery-cancel sites go through
     *  here, so a stale timeout can never restore an old channel's URL —
     *  or restart playback from the background. */
    fun clearIptvTwinTrial() {
        iptvTwinTrialTimeout?.let { iptvTwinTrialHandler.removeCallbacks(it) }
        iptvTwinTrialTimeout = null
        iptvTwinTrialOriginalUrl = null
        iptvTwinTrialUrl = null
        iptvTwinTrialLastFrames = -1
        iptvTwinTrialAdvanceSince = 0L
        iptvTwinTrialStartedRealtime = 0L
    }

    /** An accepted twin is still speculative provider infrastructure. If it
     *  later becomes deterministically unavailable, revoke the preference
     *  and give the original HLS endpoint one chance before AUTH surrender. */
    fun restoreAcceptedIptvTwinAfterAuth(error: PlaybackException): Boolean {
        if (classifyIptvError(error) != IptvLiveRecovery.ErrorClass.AUTH) return false
        val twin = tune.currentIptvStreamUrl ?: return false
        val preferred = iptvTwinPreferredUrls.entries.firstOrNull { it.value == twin }
            ?: return false
        val original = preferred.key
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)?.takeIf { it.isLive }
            ?: return false
        iptvTwinPreferredUrls.remove(original)
        iptvTwinFailedUrls.add(original)
        host.iptvTuneDiagnostics.onRecovery("auth", "twin-ts", "revoked")
        tune.iptvLiveRetuneInFlight = true
        try {
            tune.setIptvMediaItem(entry, original)
        } finally {
            tune.iptvLiveRetuneInFlight = false
        }
        return true
    }

    // ── Xtream HLS→TS twin trial ─────────────────────────────────────────
    // Segmented streams never see the strict-demux remedy (they bypass the
    // progressive extractor factory), so an Xtream `.m3u8` channel whose
    // video wedges has nowhere to escalate — the ladder plain-re-tunes and
    // latches with frozen video under running audio. But Xtream panels serve
    // the SAME channel as one progressive `.ts` stream (xtreamTsTwin), which
    // IS reachable by the demux path the browse preview proves works on
    // strict decoders. So: at the video-stall strict rung on a segmented
    // URL, trial the twin — reversibly. Frames rendering accepts it for the
    // session; an error or a no-frames timeout restores the original HLS URL
    // and blacklists the twin so the channel can't ping-pong. All state is
    // session-scoped, like [iptvHlsForcedUrls].

    /** Original `.m3u8` URL while its `.ts` twin is on trial; null = idle. */
    internal var iptvTwinTrialOriginalUrl: String? = null

    /** The twin URL under trial. Its tune runs strict demux from the first
     *  attempt: the stall already proved this device+channel wedges, and the
     *  twin exists precisely to reach the demux mode that works — joining it
     *  mid-GOP under the aggressive flags would recreate the wedge and doom
     *  the trial. Read on main only (setIptvMediaItem computes the volatile
     *  [iptvStrictTsActive] from it before prepare). */
    internal var iptvTwinTrialUrl: String? = null

    /** Originals whose twin trial failed this session — never re-trialed. */
    internal val iptvTwinFailedUrls = HashSet<String>()

    /** Accepted trials, original → twin: later zaps to the channel start on
     *  the twin directly (still strict — see [iptvStrictTsActive]'s
     *  computation), instead of wedging on HLS and re-earning it. */
    internal val iptvTwinPreferredUrls = HashMap<String, String>()

    private var iptvTwinTrialTimeout: Runnable? = null
    private val iptvTwinTrialHandler = Handler(Looper.getMainLooper())

    /** Set by onStop when it abandons an UNJUDGED trial: the original HLS
     *  URL onStart must re-tune to. Bookkeeping alone can't express this —
     *  while backgrounded the player still holds the twin media item, and
     *  lying about the identity would misroute error attribution, recording
     *  eligibility and diagnostics on a quick resume. Consumed (and the
     *  actual media item restored) at the top of onStart. */
    internal var iptvTwinTrialRestoreOriginal: String? = null

    /** Twin paired with [iptvTwinTrialRestoreOriginal]. Same-twin recovery
     *  keeps the parked rollback alive; any different tune discards it. */
    internal var iptvTwinTrialRestoreTwin: String? = null

    /** Verdict sampling state, fed by the 5s progress ticker
     *  (judgeIptvTwinTrial): last rendered-frame count seen on the twin, and
     *  when its current uninterrupted advancing streak began (0 = none). */
    private var iptvTwinTrialLastFrames = -1
    private var iptvTwinTrialAdvanceSince = 0L
    private var iptvTwinTrialStartedRealtime = 0L

    /** Acceptance = frames advancing on EVERY 5s sample for this long —
     *  the machine's own STABLE_MS idiom. One frame over baseline is not a
     *  verdict: a twin that renders a moment and wedges must fail, not get
     *  remembered as the channel's preferred URL. */
    private val IPTV_TWIN_TRIAL_STABLE_MS = 15_000L

    /** Verdict deadline from trial start — the PRE-READY bound: a twin that
     *  can't even reach READY inside this (the machine's 20s watchdog gets
     *  one same-URL re-tune in between) fails and HLS is restored. Every
     *  READY on the twin re-arms the deadline to the post-READY bound below,
     *  so prepare time is never charged against the proof itself. */
    private val IPTV_TWIN_TRIAL_TIMEOUT_MS = 40_000L

    /** Verdict deadline from (each) READY: a baseline sample (≤5s) + the
     *  15s advancing streak + sampling jitter. Re-armed per READY, so a
     *  mid-trial machine re-tune restarts the proof rather than inheriting
     *  a clock its prepare already spent; the machine's own strict/latch
     *  budgets bound how often that can happen. */
    private val IPTV_TWIN_TRIAL_POST_READY_MS = 30_000L

    /** Hard ceiling across every READY/rebuffer cycle. A pathological twin
     *  cannot renew its post-READY deadline forever. */
    private val IPTV_TWIN_TRIAL_MAX_MS = 90_000L
}
