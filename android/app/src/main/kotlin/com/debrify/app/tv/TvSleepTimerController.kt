package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

    // ── Sleep timer ───────────────────────────────────────────────────────────
    // Stops playback after a countdown, or at the end of the current item.
    //
    // The activity adds FLAG_KEEP_SCREEN_ON on create and never clears it, so
    // pausing alone would leave the TV lit all night — the exact thing this
    // feature exists to prevent. Firing therefore drops the flag as well, and
    // any later playback re-arms it (see onIsPlayingChanged).
    internal enum class SleepTimerMode { OFF, COUNTDOWN, END_OF_ITEM }

@OptIn(UnstableApi::class)
internal class TvSleepTimerController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        var sleepStopLatched: Boolean
        val player: ExoPlayer?
        fun sendProgress(completed: Boolean)
        fun releaseScreenForSleep()
    }
    var sleepTimerMode = SleepTimerMode.OFF
    private var sleepTimerDeadlineElapsedMs = 0L
    private val sleepTimerHandler = Handler(Looper.getMainLooper())
    private var sleepTimerRunnable: Runnable? = null
    val sleepTimerMinuteOptions = listOf(15, 30, 45, 60, 90)

    // ── Sleep timer ───────────────────────────────────────────────────────────

    /** Whole minutes left, rounded up so a fresh 30-minute timer reads "30". */
    private fun sleepTimerMinutesLeft(): Int {
        if (sleepTimerMode != SleepTimerMode.COUNTDOWN) return 0
        val remaining = sleepTimerDeadlineElapsedMs - android.os.SystemClock.elapsedRealtime()
        return kotlin.math.ceil(remaining / 60_000.0).toInt().coerceAtLeast(0)
    }

    fun sleepTimerValueLabel(): String = when (sleepTimerMode) {
        SleepTimerMode.OFF -> "Off"
        SleepTimerMode.END_OF_ITEM -> "End of episode"
        SleepTimerMode.COUNTDOWN -> "${sleepTimerMinutesLeft()} min"
    }

    fun startSleepCountdown(minutes: Int) {
        cancelSleepTimer()
        val durationMs = minutes * 60_000L
        sleepTimerMode = SleepTimerMode.COUNTDOWN
        // elapsedRealtime, not currentTimeMillis: the countdown must survive a
        // clock adjustment and keep counting while the box is dozing.
        sleepTimerDeadlineElapsedMs = android.os.SystemClock.elapsedRealtime() + durationMs
        val runnable = Runnable { fireSleepTimer() }
        sleepTimerRunnable = runnable
        sleepTimerHandler.postDelayed(runnable, durationMs)
        Toast.makeText(activity, "Sleep timer set for $minutes minutes", Toast.LENGTH_SHORT).show()
    }

    fun armSleepAtEndOfItem() {
        cancelSleepTimer()
        sleepTimerMode = SleepTimerMode.END_OF_ITEM
        Toast.makeText(activity, "Sleep timer: stopping at the end of this episode", Toast.LENGTH_SHORT).show()
    }

    fun cancelSleepTimer(announce: Boolean = false) {
        sleepTimerRunnable?.let { sleepTimerHandler.removeCallbacks(it) }
        sleepTimerRunnable = null
        sleepTimerMode = SleepTimerMode.OFF
        sleepTimerDeadlineElapsedMs = 0L
        if (announce) Toast.makeText(activity, "Sleep timer off", Toast.LENGTH_SHORT).show()
    }

    /**
     * Stop for the night: persist the position first (losing someone's place
     * overnight is exactly the moment this feature is supposed to be helping),
     * pause, then release the screen so the TV can sleep on its own.
     */
    private fun fireSleepTimer() {
        cancelSleepTimer()
        host.sleepStopLatched = true
        host.sendProgress(completed = false)
        host.player?.pause()
        host.releaseScreenForSleep()
        Toast.makeText(activity, "Sleep timer ended — paused", Toast.LENGTH_LONG).show()
    }
}
