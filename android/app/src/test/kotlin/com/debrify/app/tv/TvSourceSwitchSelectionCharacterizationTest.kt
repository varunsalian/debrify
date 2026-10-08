package com.debrify.app.tv

import android.view.View
import android.widget.LinearLayout
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSourceSwitchSelectionCharacterizationTest : TvPhase8OriginalTest() {
    @Test fun manualPickBeforeCommitStartsSingleAttemptAndCancelsOldWork() {
        val old = cursor(); set("hasPlaylistResolver", true)
        invoke("watchSourceSwitchOutcome", 0); val listener = field("sourceSwitchReadyListener")
        set("pikPakRetryId", 8); set("stremioResolutionToken", 12)
        call("onStremioSourceSelected", arrayOf(StremioSource::class.java), sources()[1])
        val now = field("startupFailoverCursor") as StartupFailoverCursor
        assertNotSame(old, now); assertNull(now.nextIndex(2, listOf(0)) { true })
        assertEquals(1, field("currentStremioSourceIndex")); assertEquals(13, field("stremioResolutionToken"))
        assertTrue(probe.removed.contains(listener)); assertTrue((field("pikPakRetryId") as Int) > 8)
        assertEquals("Switching to Source 1…", pill().text.toString())
        assertEquals(mapOf("sourceIndex" to 1, "automaticRecovery" to false), requests("requestSourcePlaylistResolve").single().call.arguments)
    }
    @Test fun automaticRecoveryPreservesCursorAndPinsRecoveryArgument() {
        val old = cursor(); set("startupFailoverDispatching", true); set("startupRecoveryCandidateIndices", listOf(1)); set("hasPlaylistResolver", true)
        call("onStremioSourceSelected", arrayOf(StremioSource::class.java), sources()[1])
        assertSame(old, field("startupFailoverCursor")); assertNull(field("manualSourceSwitchSnapshot"))
        assertEquals(mapOf("sourceIndex" to 1, "automaticRecovery" to true), requests("requestSourcePlaylistResolve").single().call.arguments)
        set("startupRecoveryCandidateIndices", null); resolve(true)
        assertEquals(false, (requests("requestSourcePlaylistResolve").last().call.arguments as Map<*, *>)["automaticRecovery"])
    }
    @Test fun committedManualDirectPickSnapshotsOutgoingAndAppliesImmediately() {
        cursor(true); sources()[1] = source(1, "https://phase8.invalid/direct.mp4")
        call("onStremioSourceSelected", arrayOf(StremioSource::class.java), sources()[1])
        assertNotNull(field("manualSourceSwitchSnapshot")); assertTrue(requests("requestStremioSourceResolve").isEmpty())
        assertEquals("https://phase8.invalid/direct.mp4", probe.media.single().localConfiguration!!.uri.toString())
        assertEquals(true, field("manualSourceMediaReplaced")); assertEquals("https://phase8.invalid/direct.mp4", field("manualSourceCandidateUrl"))
    }
    @Test fun torrentPickRequestsSingleUrlAndSupersedesEarlierResolution() {
        call("onStremioSourceSelected", arrayOf(StremioSource::class.java), sources()[1]); val old = index("requestStremioSourceResolve")
        call("onStremioSourceSelected", arrayOf(StremioSource::class.java), sources()[0])
        messenger.success(mapOf("url" to "https://phase8.invalid/stale.mp4"), old); idle()
        assertTrue(probe.media.isEmpty()); assertEquals(3, field("stremioResolutionToken"))
        assertEquals(mapOf("sourceIndex" to 0), requests("requestStremioSourceResolve").last().call.arguments)
    }
    @Test fun setupRendersSourcesHighlightsCommittedIndexAndBadgeOpensBrowser() {
        browser().show(); set("currentStremioSourceIndex", 1); invoke("setupStremioSources")
        val rows = activity.findViewById<LinearLayout>(R.id.tv_source_browser_results)
        assertEquals(2, rows.childCount); assertFalse(rows.getChildAt(0).isSelected); assertTrue(rows.getChildAt(1).isSelected)
        assertEquals("Sources", (field("stremioSourceBadgeText") as android.widget.TextView).text.toString())
        badge().performClick(); assertTrue(browser().isVisible)
        assertEquals(false, field("controlsMenuVisible"))
    }
    @Test fun browserReselectDoesNothingButAnotherRowDispatchesSelection() {
        invoke("setupStremioSources")
        val callbacks = TvSourceBrowserController::class.java.getDeclaredField("callbacks").apply { isAccessible = true }.get(browser()) as TvSourceBrowserController.Callbacks
        callbacks.onSourceSelected(0); assertEquals(0, field("stremioResolutionToken")); assertTrue(messenger.requests.isEmpty())
        callbacks.onSourceSelected(1); assertEquals(1, field("stremioResolutionToken")); assertEquals(1, requests("requestStremioSourceResolve").size)
    }
    @Test fun emptySourceSetupLeavesBadgeTextAndClickUntouched() {
        sources().clear(); val text = field("stremioSourceBadgeText") as android.widget.TextView; text.text = "sentinel"
        invoke("setupStremioSources"); invoke("updateStremioQualityBadge")
        assertEquals("sentinel", text.text.toString()); assertFalse(badge().hasOnClickListeners())
    }
}
