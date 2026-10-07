package com.debrify.app.tv

import android.os.Looper
import com.debrify.app.MainActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpgRequestCharacterizationTest : TvFlutterRequestsOriginalTest() {
    private val types get() = arrayOf(IptvChannelEntry::class.java, boolType, boolType, function1Type)
    private fun request(entry: IptvChannelEntry = p2Channel(), callback: (Map<*, *>?) -> Unit) =
        call("requestIptvEpg", types, entry, true, false, callback)

    @Test fun epgPinsArgumentsAndAlwaysAnswersAsynchronouslyForEveryResultAndFailure() {
        val entry = p2Channel(archive = "0", days = 3); val answers = mutableListOf<Map<*, *>?>()
        val callback: (Map<*, *>?) -> Unit = { assertMainThread(); answers.add(it) }
        for ((reply, expected) in listOf(mapOf("now" to "Show") to mapOf("now" to "Show"), null to null, "wrong" to null)) {
            answers.clear(); request(entry, callback)
            assertRequest("requestIptvEpg", mapOf("channelUrl" to entry.url, "includeSchedule" to true,
                "includeCatchupMetadata" to false, "archiveDisabled" to true, "archiveDurationDays" to 3))
            messenger.success(reply); assertTrue(answers.isEmpty()); idle(); assertEquals(listOf(expected), answers)
        }
        for (error in listOf(true, false)) {
            answers.clear(); request(entry, callback); if (error) messenger.error() else messenger.notImplemented()
            assertTrue(answers.isEmpty()); idle(); assertEquals(listOf<Map<*, *>?>(null), answers)
        }
        MainActivity.setAndroidTvPlayerChannel(null); answers.clear(); request(entry, callback)
        assertTrue(answers.isEmpty()); idle(); assertEquals(listOf<Map<*, *>?>(null), answers)
        reconnectChannel(); messenger.throwOnSend = true; answers.clear(); request(entry, callback)
        assertTrue(answers.isEmpty()); idle(); assertEquals(listOf<Map<*, *>?>(null), answers)
    }

    @Test fun epgDefaultDispatcherReadsCurrentEntryWhenCatchupArgumentIsOmitted() {
        for (current in listOf(true, false)) {
            val entry = p2Channel(current = current); val answers = mutableListOf<Map<*, *>?>()
            val callback: (Map<*, *>?) -> Unit = { assertMainThread(); answers.add(it) }
            defaultCall("requestIptvEpg", types, 4, entry, false, false, callback)
            assertRequest("requestIptvEpg", mapOf("channelUrl" to entry.url, "includeSchedule" to false,
                "includeCatchupMetadata" to current, "archiveDisabled" to false, "archiveDurationDays" to null))
            assertTrue(answers.isEmpty()); messenger.success(emptyMap<String, Any>()); idle(); assertEquals(listOf(emptyMap<String, Any>()), answers)
        }
    }

    @Test fun epgWatchdogFiresExactlyAtFortyFiveSecondsAndLateReplyCannotRedeliver() {
        val answers = mutableListOf<Map<*, *>?>(); request { assertMainThread(); answers.add(it) }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(44_999)); assertTrue(answers.isEmpty())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1)); assertEquals(listOf<Map<*, *>?>(null), answers)
        messenger.success(mapOf("late" to true)); idle(); assertEquals(listOf<Map<*, *>?>(null), answers)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(45)); assertEquals(1, answers.size)
    }

    @Test fun epgReplyBeforeDeadlineWinsAndWatchdogCannotRedeliver() {
        val answers = mutableListOf<Map<*, *>?>(); request { assertMainThread(); answers.add(it) }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(44_999)); assertTrue(answers.isEmpty())
        messenger.success(mapOf("show" to "Now")); assertTrue(answers.isEmpty()); idle()
        assertEquals(listOf(mapOf("show" to "Now")), answers)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1)); assertEquals(listOf(mapOf("show" to "Now")), answers)
    }
}
