package com.debrify.app.tv

import android.os.Looper
import java.time.Duration
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Exercise the activity's failure/timeout/cancellation routing, not the bag. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class ShufflePlaybackFlowTest {
    private fun activity() = Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java).get()
    private fun field(activity: Any, name: String, value: Any?) {
        activity.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(activity, value)
    }
    private fun call(activity: Any, name: String, vararg args: Any): Any? {
        val method = activity.javaClass.declaredMethods.first { it.name == name && it.parameterCount == args.size }
        method.isAccessible = true
        return method.invoke(activity, *args)
    }
    private fun attempt(activity: Any, opened: Boolean = false, failure: () -> Unit, restore: () -> Unit = {}): Any {
        val type = activity.javaClass.declaredClasses.first { it.simpleName == "ShufflePlaybackAttempt" }
        val ctor = type.declaredConstructors.first { it.parameterCount == 7 }
        ctor.isAccessible = true
        return ctor.newInstance(0, 0, false, failure, opened, restore, false)
    }

    @Test fun completedFetchYieldsToNewExplicitShuffle() {
        val activity = activity()
        field(activity, "queuedShuffleGeneration", 0)
        field(activity, "queuedShuffleNavigation", 0)
        field(activity, "episodeFetchInFlight", false)
        assertEquals(true, call(activity, "yieldEpisodeFetchToQueuedShuffle"))
        call(activity, "clearQueuedShuffle", 0)
        assertEquals(false, call(activity, "yieldEpisodeFetchToQueuedShuffle"))
    }

    @Test fun abandonedQueueDoesNotBlockLaterCommands() {
        val activity = activity()
        field(activity, "queuedShuffleGeneration", 0)
        field(activity, "queuedShuffleNavigation", 0)
        field(activity, "mediaPreparationGeneration", 1)
        assertEquals(false, call(activity, "yieldEpisodeFetchToQueuedShuffle"))
        call(activity, "clearQueuedShuffle", 0)
        field(activity, "queuedShuffleGeneration", 0)
        field(activity, "queuedShuffleNavigation", 1)
        assertEquals(true, call(activity, "yieldEpisodeFetchToQueuedShuffle"))
        // An older cancellation must not clear a newer generation's command.
        field(activity, "queuedShuffleGeneration", 1)
        field(activity, "showShuffleGeneration", 1)
        call(activity, "clearQueuedShuffle", 0)
        assertEquals(true, call(activity, "yieldEpisodeFetchToQueuedShuffle"))
    }

    @Test fun rearmingSameAttemptStartsAFreshTimeout() {
        val activity = activity()
        var retries = 0
        val attempt = attempt(activity, failure = { retries++ })
        call(activity, "watchShufflePlayback", attempt)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(14))
        call(activity, "watchShufflePlayback", attempt)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
        assertEquals(0, retries)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(14))
        assertEquals(1, retries)
    }

    @Test fun failedPlaybackRoutesToFallbackOnce() {
        val activity = activity()
        var retries = 0
        val attempt = attempt(activity, opened = true, failure = { retries++ })
        call(activity, "watchShufflePlayback", attempt)
        assertEquals(true, call(activity, "failShufflePlayback"))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, retries)
        assertEquals(false, call(activity, "shuffleAttemptCurrent", attempt))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(16))
        assertEquals(1, retries)
    }

    @Test fun preparationTimeoutRestoresIdentityThenRetries() {
        val activity = activity()
        val events = mutableListOf<String>()
        val attempt = attempt(activity, failure = { events.add("retry") }, restore = { events.add("restore") })
        call(activity, "watchShufflePlayback", attempt)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(16))
        assertEquals(listOf("restore", "retry"), events)
    }

    @Test fun manualNavigationPreventsLateRetryAndRollback() {
        val activity = activity()
        var retries = 0
        var restores = 0
        call(activity, "watchShufflePlayback", attempt(activity, failure = { retries++ }, restore = { restores++ }))
        field(activity, "mediaPreparationGeneration", 1)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(16))
        assertEquals(0, retries)
        assertEquals(0, restores)
    }

    @Test fun disablingShuffleRestoresOnlyBeforeMediaReplacement() {
        for (opened in listOf(false, true)) {
            val activity = activity()
            var restores = 0
            var retries = 0
            call(activity, "watchShufflePlayback", attempt(activity, opened, { retries++ }, { restores++ }))
            call(activity, "resetShuffle")
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(16))
            assertEquals(if (opened) 0 else 1, restores)
            assertEquals(0, retries)
        }
    }
}
