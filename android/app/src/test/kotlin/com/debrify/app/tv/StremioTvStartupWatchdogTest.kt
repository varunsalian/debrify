package com.debrify.app.tv

import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import com.debrify.app.R
import java.io.IOException
import java.lang.reflect.Proxy
import java.time.Duration
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Exercise the activity's real startup entry point and scheduled callbacks. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class StremioTvStartupWatchdogTest {
    private fun field(activity: Any, name: String, value: Any?) {
        activity.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(activity, value)
    }

    private fun read(activity: Any, name: String): Any? =
        activity.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(activity)

    private fun call(activity: Any, name: String, vararg args: Any?): Any? {
        val method = activity.javaClass.declaredMethods.first { it.name == name && it.parameterCount == args.size }
        method.isAccessible = true
        return method.invoke(activity, *args)
    }

    private fun activity(stremioTv: Boolean = false, iptv: Boolean = false, pikpak: Boolean = false, aiostreams: Boolean = false): AndroidTvTorrentPlayerActivity {
        val activity = Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java).get()
        activity.setTheme(androidx.appcompat.R.style.Theme_AppCompat)
        val root = FrameLayout(activity)
        for (id in listOf(R.id.startup_title, R.id.startup_explanation, R.id.startup_back)) {
            root.addView(TextView(activity).apply { this.id = id })
        }
        activity.setContentView(root)
        field(activity, "startupGateView", View(activity).apply { visibility = View.GONE })
        field(activity, "startupGateStatus", TextView(activity))
        field(activity, "titleView", TextView(activity).apply { text = "Channel programme" })
        field(activity, "nextOverlay", View(activity).apply { visibility = View.GONE })
        field(activity, "pikPakReactivationIndicator", View(activity).apply { visibility = View.GONE })
        val payload = call(activity, "parsePayload", """
            {
              "title": "Channel programme", "contentType": "single", "startAtPercent": 0.4,
              "items": [{"id": "programme", "title": "Channel programme", "url": "https://cdn.test/video", "provider": "${if (pikpak) "pikpak" else "realdebrid"}"}],
              "stremioSources": [{"name": "Direct source", "stream_type": "directUrl", "direct_url": "https://cdn.test/video", "stremio_addon_id": "${if (aiostreams) "org.aiostreams" else "other.addon"}"}],
              "startupTryNextOnFailure": false, "startupMaxAttempts": 1
            }
        """.trimIndent())
        assertNotNull(payload)
        field(activity, "payload", payload)
        if (stremioTv) {
            // The real launch initializes guide mode before starting the guard.
            call(activity, "initStremioTvGuide", JSONObject())
        }
        field(activity, "isIptvMode", iptv)
        return activity
    }

    private class ColdPlayer {
        var prepares = 0
        var plays = 0
        var stops = 0
        var durationMs = 0L
        var durationReads = 0
        var error: ExoPlaybackException? = ExoPlaybackException.createForSource(
            IOException("Cold storage"), PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)
        val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
            arrayOf(ExoPlayer::class.java)) { _, method, _ ->
            when (method.name) {
                "getPlayerError" -> error
                "getPlaybackState" -> Player.STATE_IDLE
                "getDuration" -> { durationReads++; durationMs }
                "prepare" -> { prepares++; error = null; null }
                "play" -> { plays++; null }
                "stop" -> { stops++; null }
                else -> when (method.returnType) {
                    java.lang.Boolean.TYPE -> false
                    java.lang.Integer.TYPE -> 0
                    java.lang.Long.TYPE -> 0L
                    else -> null
                }
            }
        } as ExoPlayer
    }

    @Test fun aioChannelRejectsErrorClipAndSuppressesFinalCompletion() {
        val activity = activity(stremioTv = true, aiostreams = true)
        call(activity, "beginStartupFailoverIfEligible")
        val player = ColdPlayer().apply { error = null; durationMs = 30_000 }
        field(activity, "player", player.player)
        assertNotNull(read(activity, "startupFailoverCursor"))
        assertNull(read(activity, "startupFailoverTimeout"))
        call(activity, "sendProgress", true)
        assertEquals(0, player.durationReads)
        call(activity, "commitStartupCandidate")
        assertTrue(activity.isFinishing)
        assertEquals(true, read(activity, "startupSourcesExhausted"))
        assertEquals(1, player.stops)

        // The cursor is cleared on failure; EOF and exit must remain muted.
        val durationReads = player.durationReads
        (read(activity, "playbackListener") as Player.Listener)
            .onPlaybackStateChanged(Player.STATE_ENDED)
        call(activity, "sendProgress", true)
        call(activity, "sendProgress", false)
        assertEquals(durationReads, player.durationReads)
        assertTrue((read(activity, "recoveryCompletedItemKeys") as Set<*>).isEmpty())
        assertEquals(0, read(activity, "currentIndex"))
    }

    @Test fun aioChannelKeepsSlateValidationWithoutAStartupDeadline() {
        val activity = activity(stremioTv = true, aiostreams = true)
        call(activity, "beginStartupFailoverIfEligible")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(90))
        assertFalse(activity.isFinishing)
        assertNull(read(activity, "startupFailoverTimeout"))
        assertFalse((read(activity, "startupFailoverCursor") as StartupFailoverCursor).committed)
    }

    @Test fun aioChannelEofBeforeValidationCannotAdvanceTheSlot() {
        val activity = activity(stremioTv = true, aiostreams = true)
        call(activity, "beginStartupFailoverIfEligible")
        (read(activity, "playbackListener") as Player.Listener)
            .onPlaybackStateChanged(Player.STATE_ENDED)
        assertTrue(activity.isFinishing)
        assertTrue((read(activity, "recoveryCompletedItemKeys") as Set<*>).isEmpty())
        assertEquals(0, read(activity, "currentIndex"))
    }

    @Test fun aioChannelAcceptsProgrammeDurationsAtOrAboveThreeMinutes() {
        for (duration in listOf(180_000L, 3_600_000L)) {
            val activity = activity(stremioTv = true, aiostreams = true)
            call(activity, "beginStartupFailoverIfEligible")
            field(activity, "player", ColdPlayer().apply {
                error = null; durationMs = duration
            }.player)
            call(activity, "commitStartupCandidate")
            assertTrue((read(activity, "startupFailoverCursor") as StartupFailoverCursor).committed)
            assertFalse(activity.isFinishing)
            assertNull(read(activity, "startupFailoverTimeout"))
        }
    }

    @Test fun aioChannelRejectsAnErrorDurationArrivingDuringMetadataGrace() {
        val activity = activity(stremioTv = true, aiostreams = true)
        call(activity, "beginStartupFailoverIfEligible")
        val player = ColdPlayer().apply { error = null }
        field(activity, "player", player.player)
        call(activity, "commitStartupCandidate")
        assertFalse((read(activity, "startupFailoverCursor") as StartupFailoverCursor).committed)
        player.durationMs = 30_000
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(200))
        assertTrue(activity.isFinishing)
        assertEquals(true, read(activity, "startupSourcesExhausted"))
    }

    private fun monitorColdPlayer(activity: AndroidTvTorrentPlayerActivity, player: ColdPlayer) {
        field(activity, "player", player.player)
        val payload = read(activity, "payload")!!
        val item = (read(payload, "items") as List<*>).first()!!
        call(activity, "waitForPikPakMetadata", item, 0, 0, 0L, { _: Boolean -> Unit })
    }

    @Test fun coldStremioTvReissuesFailedRequestWithoutStartupGate() {
        val activity = activity(stremioTv = true, pikpak = true)
        call(activity, "beginStartupFailoverIfEligible")
        val player = ColdPlayer()
        monitorColdPlayer(activity, player)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertEquals(1, player.prepares)
        assertEquals(1, player.plays)
        assertNull(read(activity, "startupFailoverCursor"))
        assertFalse(activity.isFinishing)
        // Continued buffering is not an error and must not burn the URL again.
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(4))
        assertEquals(1, player.prepares)
        call(activity, "cancelPikPakRetry")
    }

    @Test fun startupAndManualGatesRetainTheirPikPakErrorRecovery() {
        for (manual in listOf(false, true)) {
            val activity = activity(stremioTv = manual, pikpak = true)
            call(activity, "beginStartupFailoverIfEligible")
            if (manual) call(activity, "beginManualSourceCandidate", 0)
            val player = ColdPlayer()
            field(activity, "player", player.player)
            // Existing onPlayerError gate callers do not pass a retry token.
            call(activity, "schedulePikPakGateReprepare", null)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
            assertEquals(1, player.prepares)
            assertEquals(1, player.plays)
            assertFalse(activity.isFinishing)
            // Stop the remaining validation watchdog between fixtures.
            field(activity, "player", null)
            if (manual) call(activity, "commitManualSourceCandidate")
            else call(activity, "commitStartupCandidate")
        }
    }

    @Test fun cancelledColdStorageRetryCannotPrepareTheNextChannel() {
        val activity = activity(stremioTv = true, pikpak = true)
        val player = ColdPlayer()
        monitorColdPlayer(activity, player)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertNotNull(read(activity, "pikPakGateReprepare"))
        call(activity, "cancelPikPakRetry")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertEquals(0, player.prepares)
        assertNull(read(activity, "pikPakGateReprepare"))
    }

    @Test fun coldStorageCallbackCannotReprepareAReplacementPlayer() {
        val activity = activity(stremioTv = true, pikpak = true)
        val player = ColdPlayer()
        monitorColdPlayer(activity, player)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        val replacement = ColdPlayer()
        field(activity, "player", replacement.player)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertEquals(0, player.prepares)
        assertEquals(0, replacement.prepares)
        call(activity, "cancelPikPakRetry")
    }

    @Test fun slowStremioTvLaunchDoesNotArmOrExpireTheVodWatchdog() {
        val activity = activity(stremioTv = true)
        val payload = read(activity, "payload")
        call(activity, "beginStartupFailoverIfEligible")
        assertNull(read(activity, "startupFailoverCursor"))
        assertNull(read(activity, "startupFailoverTimeout"))

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(90))
        // A late first-frame callback is harmless when no startup gate exists.
        call(activity, "commitStartupCandidate")
        assertFalse(activity.isFinishing)
        assertEquals(false, read(activity, "startupSourcesExhausted"))
        assertSame(payload, read(activity, "payload"))
        assertEquals(View.GONE, (read(activity, "startupGateView") as View).visibility)
    }

    @Test fun ordinarySingleAttemptVodStillTimesOut() {
        val activity = activity()
        call(activity, "beginStartupFailoverIfEligible")
        assertNotNull(read(activity, "startupFailoverCursor"))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(11))
        assertFalse(activity.isFinishing)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertTrue(activity.isFinishing)
        assertEquals(true, read(activity, "startupSourcesExhausted"))
    }

    @Test fun successfulVodCancelsItsStartupTimeout() {
        val activity = activity()
        call(activity, "beginStartupFailoverIfEligible")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(2))
        call(activity, "commitStartupCandidate")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(15))
        assertFalse(activity.isFinishing)
        assertTrue((read(activity, "startupFailoverCursor") as StartupFailoverCursor).committed)
        assertNull(read(activity, "startupFailoverTimeout"))
    }

    @Test fun iptvStillBypassesTheVodWatchdog() {
        val activity = activity(iptv = true)
        call(activity, "beginStartupFailoverIfEligible")
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(15))
        assertNull(read(activity, "startupFailoverCursor"))
        assertFalse(activity.isFinishing)
    }

    @Test fun explicitStremioTvSourceSwitchStillUsesManualValidation() {
        val activity = activity(stremioTv = true)
        call(activity, "beginStartupFailoverIfEligible")
        call(activity, "beginManualSourceCandidate", 0)
        assertNotNull(read(activity, "manualSourceSwitchSnapshot"))
        assertNotNull(read(activity, "manualSourceSwitchTimeout"))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(12))
        assertNull(read(activity, "manualSourceSwitchSnapshot"))
        assertEquals(0, read(activity, "currentStremioSourceIndex"))
        assertFalse(activity.isFinishing)
    }
}
