package com.debrify.app.tv

import android.os.Looper
import android.os.Message
import android.view.View
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvStartupGateBoundaryCharacterizationTest : TvPhase9OriginalTest() {
    private fun queued(callback: Runnable): Int {
        var message = ReflectionHelpers.getField<Message?>(Looper.getMainLooper().queue, "mMessages")
        var count = 0
        while (message != null) {
            if (message.target === handler && message.callback === callback) count++
            message = ReflectionHelpers.getField(message, "next")
        }
        return count
    }
    private fun seed(names: List<String>): Map<String, Runnable> = names.associateWith { name ->
        Runnable { org.junit.Assert.fail("retired callback fired: $name") }.also { set(name, it); handler.postDelayed(it, 100) }
    }
    private fun retired(callbacks: Map<String, Runnable>) {
        callbacks.forEach { (name, callback) -> assertEquals("$name removed from borrowed queue", 0, queued(callback)) }
        advance(100)
    }
    private fun recovery() {
        sources().clear(); sources().add(source(0, "https://gate.invalid/saved.mp4"))
        set("movieMoreSources", true); set("startupRecoveryAvailable", true); begin(3)
    }
    private fun resolveZero() {
        call("resolveStremioSourceViaFlutter", arrayOf(StremioSource::class.java, intType), sources()[0], field("stremioResolutionToken"))
    }
    @Test fun armingVisibleGateKeepsExistingChildFocusAndDebridOpenDoesNotStealFocus() {
        sources()[0] = aio(); begin(2)
        val heading = text(R.id.startup_explanation)
        heading.isFocusable = true; heading.isFocusableInTouchMode = true
        assertTrue("fixture focuses another child inside gate", heading.requestFocus())
        assertTrue(view("startupGateView").hasFocus()); arm(0)
        assertTrue("arming must retain the gate's existing focus owner", heading.hasFocus())
        sources()[0] = source(0); view("startupGateView").visibility = View.GONE
        val title = text(R.id.android_tv_player_title)
        title.isFocusable = true; title.isFocusableInTouchMode = true
        assertTrue(title.requestFocus()); arm(0)
        assertTrue("debrid first open must leave outside focus alone", title.hasFocus())
    }
    @Test fun hiddenControlsKeepBadgeHiddenAfterStartupCommit() {
        set("controlsMenuVisible", false); begin(); assertEquals(View.GONE, badge().visibility)
        invoke("commitStartupCandidate"); tick(350); assertTrue(candidate().committed)
        assertEquals("commit cannot expose badge over hidden controls", View.GONE, badge().visibility)
    }
    private fun ticker(commit: String) {
        val callback = field("progressRunnable") as Runnable
        handler.removeCallbacks(callback); handler.postDelayed(callback, 100)
        invoke(commit)
        assertEquals("exactly one replacement progress pulse", 1, queued(callback))
        tick(4_999)
        assertTrue("no progress pulse before five seconds", requests("torrentPlaybackProgress").isEmpty())
        tick(1); idle()
        assertEquals("committed playback restarts real progress reporting at five seconds", 1, requests("torrentPlaybackProgress").size)
        assertEquals(25_000, requestMap("torrentPlaybackProgress")["positionMs"])
    }
    @Test fun startupCommitRestartsTheActualProgressTickerAtFiveSeconds() { begin(); ticker("commitStartupCandidate") }
    @Test fun manualCommitRestartsTheActualProgressTickerAtFiveSeconds() {
        manual(); set("manualSourceMediaReplaced", true); ticker("commitManualSourceCandidate")
    }
    @Test fun failedStartupRowInvalidatesLateResolveWhileRecoveryKeepsActivityAlive() {
        recovery(); resolveZero()
        val pending = index("requestStremioSourceResolve"); val before = model().items.toList()
        val token = field("stremioResolutionToken") as Int
        fail("saved-failed")
        assertFalse(activity.isFinishing); assertEquals(true, field("startupRecoveryFetching"))
        val events = probe.events.toList()
        messenger.success(mapOf("url" to "https://gate.invalid/too-late.mp4"), pending); tick(32)
        assertEquals("failed row's late reply must not replace payload", before, model().items)
        assertEquals("failed row's late reply must not touch player", events, probe.events)
        assertEquals("failure invalidates resolver exactly once without a new selection", token + 1, field("stremioResolutionToken"))
        assertEquals(true, field("startupRecoveryFetching"))
    }
    @Test fun manualFailureInvalidatesLateResolveAndCancelsSwitcherWaitBeforeRestore() {
        manual(); resolveZero(); val pending = index("requestStremioSourceResolve")
        invoke("watchSourceSwitchOutcome", 1)
        val listener = probe.listeners.last(); val before = snapshot().items
        val switchTimeout = TvPlayerOriginalAccess.field(field("sourceSwitchController")!!, "sourceSwitchTimeoutRunnable") as Runnable
        val token = field("stremioResolutionToken") as Int
        val callbacks = seed(listOf("manualSourceSwitchTimeout", "manualSourceCommitCheck", "pikPakGateReprepare"))
        assertEquals(true, reject()); retired(callbacks)
        assertTrue("manual failure removes current player ready listener", probe.removed.contains(listener))
        assertEquals("manual failure removes switcher timeout", 0, queued(switchTimeout))
        messenger.success(mapOf("url" to "https://gate.invalid/too-late.mp4"), pending); tick(32)
        assertEquals("manual failure's late reply must not replace restored payload", before, model().items)
        assertEquals(token + 1, field("stremioResolutionToken"))
    }
    @Test fun startupFailureRetiresEveryOwnedCheckAndSwitcherWaitBeforeRecovery() {
        recovery(); invoke("watchSourceSwitchOutcome", 0); val listener = probe.listeners.last()
        val switchTimeout = TvPlayerOriginalAccess.field(field("sourceSwitchController")!!, "sourceSwitchTimeoutRunnable") as Runnable
        val callbacks = seed(listOf("startupFailoverTimeout", "startupCommitCheck", "pikPakGateReprepare"))
        val generation = field("startupFailoverGeneration") as Int
        fail("saved-failed"); retired(callbacks)
        assertTrue("startup failure removes current player ready listener", probe.removed.contains(listener))
        assertEquals("startup failure removes switcher timeout", 0, queued(switchTimeout))
        assertEquals(generation + 1, field("startupFailoverGeneration"))
        assertTrue("failure stops rejected player", probe.events.contains("stop"))
        assertNull(field("startupFailoverTimeout")); assertNull(field("startupCommitCheck")); assertNull(field("pikPakGateReprepare"))
    }
    @Test fun startupAndManualCommitRetireEveryOwnedCallbackWithoutInvalidatingResolver() {
        begin(); val token = field("stremioResolutionToken")
        val startup = seed(listOf("startupFailoverTimeout", "startupCommitCheck", "pikPakGateReprepare"))
        invoke("commitStartupCandidate"); retired(startup)
        assertEquals("startup commit retains resolver generation", token, field("stremioResolutionToken"))
        manual(); set("manualSourceMediaReplaced", true)
        val manual = seed(listOf("manualSourceSwitchTimeout", "manualSourceCommitCheck", "pikPakGateReprepare"))
        invoke("commitManualSourceCandidate"); retired(manual)
        assertEquals("manual commit retains resolver generation", token, field("stremioResolutionToken"))
    }
    @Test fun rearmingStartupReplacesTimeoutAndRemovesPendingCommitCheck() {
        begin(); val callbacks = seed(listOf("startupFailoverTimeout", "startupCommitCheck"))
        val generation = field("startupFailoverGeneration") as Int
        arm(0); retired(callbacks)
        assertEquals(generation + 1, field("startupFailoverGeneration"))
        assertNotSame(callbacks["startupFailoverTimeout"], field("startupFailoverTimeout")); assertNull(field("startupCommitCheck"))
    }
    @Test fun newManualCandidateReplacesAnOrphanedOldTimeout() {
        val callbacks = seed(listOf("manualSourceSwitchTimeout"))
        manual(); retired(callbacks)
        assertNotSame(callbacks["manualSourceSwitchTimeout"], field("manualSourceSwitchTimeout"))
        assertNotNull(field("manualSourceSwitchSnapshot"))
    }
    @Test fun cancellingPikpakRetryRetiresItsGateReprepareCallback() {
        val callbacks = seed(listOf("pikPakGateReprepare"))
        invoke("cancelPikPakRetry"); retired(callbacks)
        assertNull(field("pikPakGateReprepare"))
    }
}
