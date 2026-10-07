package com.debrify.app.tv

import android.os.SystemClock
import android.view.WindowManager
import androidx.media3.common.Player
import com.debrify.app.MainActivity
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvSleepTimerCharacterizationTest : TvPhase3OriginalTest() {
    private val messenger = TvPlayerRecordingMessenger()
    private var previous: MethodChannel? = null
    @Before fun channel() {
        previous = MainActivity.getAndroidTvPlayerChannel()
        MainActivity.setAndroidTvPlayerChannel(MethodChannel(messenger, "com.debrify.app/android_tv_player"))
    }
    @After fun restoreChannel() = MainActivity.setAndroidTvPlayerChannel(previous)

    @Test fun countdownUsesElapsedTimeAndCeilingMinutesAndRearmReplacesTheOldCallback() {
        val probe = PlayerProbe(); set("player", probe.player)
        val now = SystemClock.elapsedRealtime()
        invoke("startSleepCountdown", 1)
        assertEquals(now + 60_000L, field("sleepTimerDeadlineElapsedMs"))
        invoke("startSleepCountdown", 2)
        assertEquals("2 min", invoke("sleepTimerValueLabel"))
        advance(59_999L)
        assertEquals(2, invoke("sleepTimerMinutesLeft"))
        advance(1L)
        assertEquals(1, invoke("sleepTimerMinutesLeft"))
        assertTrue("superseded timer did not pause", probe.events.isEmpty())
        advance(60_000L)
        assertEquals(listOf("pause"), probe.events)
        assertEquals("Off", invoke("sleepTimerValueLabel"))
    }

    @Test fun cancelAndEndArmingRemoveCountdownAndKeepOriginalLabels() {
        val probe = PlayerProbe(); set("player", probe.player)
        invoke("startSleepCountdown", 1)
        invoke("armSleepAtEndOfItem")
        assertEquals("End of episode", invoke("sleepTimerValueLabel"))
        assertEquals(0, invoke("sleepTimerMinutesLeft"))
        assertNull(field("sleepTimerRunnable"))
        assertEquals(0L, field("sleepTimerDeadlineElapsedMs"))
        advance(60_000L); assertTrue(probe.events.isEmpty())
        invoke("cancelSleepTimer", true)
        assertEquals("Off", invoke("sleepTimerValueLabel"))
        assertEquals("Sleep timer off", ShadowToast.getTextOfLatestToast())
    }

    @Test fun fireCancelsThenLatchesReportsBeforePauseReleasesBothScreenHoldsAndToasts() {
        bindViews(); val model = series(); val probe = PlayerProbe(position = 25_000L)
        set("player", probe.player)
        val view = field("playerView") as androidx.media3.ui.PlayerView
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); view.keepScreenOn = true
        val order = mutableListOf<String>()
        messenger.onSend = { request ->
            if (request.call.method == "torrentPlaybackProgress") {
                assertEquals("Off", invoke("sleepTimerValueLabel"))
                assertNull(field("sleepTimerRunnable")); assertEquals(true, field("sleepStopLatched"))
                assertTrue(probe.events.isEmpty())
                assertEquals(false, (request.call.arguments as Map<*, *>)["completed"])
                order.add("progress")
            }
        }
        probe.onPause = {
            assertEquals(listOf("progress"), order)
            assertEquals(25_000L, model.items[0].resumePositionMs)
            assertTrue(view.keepScreenOn)
            order.add("pause")
        }
        invoke("startSleepCountdown", 1); invoke("fireSleepTimer")
        assertEquals(listOf("progress", "pause"), order)
        assertFalse(view.keepScreenOn)
        assertEquals(0, activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        assertEquals("Sleep timer ended — paused", ShadowToast.getTextOfLatestToast())
        advance(60_000L); assertEquals(1, probe.events.size)
    }

    @Test fun vodEndedReportsCompletionBeforeConsumingEndTimerAndNeverAdvances() {
        bindViews(); series(); val probe = PlayerProbe(position = 600_000L, state = Player.STATE_ENDED)
        set("player", probe.player); set("maxStableDurationMs", 600_000L); set("lastRealPositionMs", 600_000L)
        invoke("armSleepAtEndOfItem")
        messenger.onSend = {
            if (it.call.method == "torrentPlaybackProgress") {
                assertEquals("End of episode", invoke("sleepTimerValueLabel"))
                assertEquals(false, field("sleepStopLatched"))
            }
        }
        (field("playbackListener") as Player.Listener).onPlaybackStateChanged(Player.STATE_ENDED)
        assertEquals(true, field("sleepStopLatched")); assertEquals("Off", invoke("sleepTimerValueLabel"))
        assertEquals(true, (messenger.requests.single().call.arguments as Map<*, *>)["completed"])
        advance(2000); assertEquals(0, field("currentIndex")); assertTrue(probe.events.isEmpty())
    }

    @Test fun liveEndedConsumesEndTimerWithoutCompletionOrAdvancing() {
        bindViews(); set("isIptvMode", true); set("iptvChannels", listOf(p2Channel(live = true)))
        set("player", PlayerProbe(state = Player.STATE_ENDED).player)
        invoke("armSleepAtEndOfItem")
        (field("playbackListener") as Player.Listener).onPlaybackStateChanged(Player.STATE_ENDED)
        assertEquals(true, field("sleepStopLatched")); assertEquals("Off", invoke("sleepTimerValueLabel"))
        assertTrue(messenger.requests.isEmpty()); assertEquals(0, field("currentIptvIndex"))
    }

    @Test fun unifiedMenuRowsDispatchEveryCountdownOffAndEndModeAndHideEndForLiveChannels() {
        fun menu() = call("umPlaybackModel", arrayOf(listType, intType), emptyList<UnifiedMenuController.Row>(), 1) as UnifiedMenuController.Model
        var rows = menu().col3
        assertEquals(listOf("Off", "15 minutes", "30 minutes", "45 minutes", "60 minutes", "90 minutes", "End of episode"), rows.map { it.title })
        assertTrue(rows.first().selected)
        for ((index, minutes) in listOf(15, 30, 45, 60, 90).withIndex()) {
            rows[index + 1].onOk!!.invoke(); assertEquals("$minutes min", invoke("sleepTimerValueLabel"))
        }
        rows.last().onOk!!.invoke(); assertTrue(menu().col3.last().selected)
        rows.first().onOk!!.invoke(); assertEquals("Off", menu().col2[1].value)
        set("iptvChannels", listOf(p2Channel(live = true))); rows = menu().col3
        assertEquals(6, rows.size); assertFalse(rows.any { it.title == "End of episode" })
    }
}
