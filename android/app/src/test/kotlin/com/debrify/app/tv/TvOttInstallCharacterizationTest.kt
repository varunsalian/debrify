package com.debrify.app.tv

import android.view.View
import android.view.ViewGroup
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvOttInstallCharacterizationTest : TvPhase15OriginalTest() {
    override val skin = TvControlsSkin.OTT
    private fun install() {
        try { call("installOttControlsSkin", emptyArray()) }
        catch (failure: Exception) { fail("OTT install handles missing dependencies without throwing: $failure") }
    }
    private fun pending() = TvPlaylistUiQueue.pending(field("controlsHandler") as android.os.Handler, field("hideControlsRunnable") as Runnable)
    @Test fun installReplacesExactlyTheOldRootAtItsOriginalParentIndex() {
        val old = view(R.id.debrify_controls_root)!!; val parent = old.parent as ViewGroup; val index = parent.indexOfChild(old)
        val before = List(parent.childCount) { parent.getChildAt(it) }
        set("ottSkinInstalled", false); install()
        assertTrue(field("ottSkinInstalled") as Boolean); assertNull(old.parent)
        assertNotSame(old, parent.getChildAt(index)); assertSame(view(R.id.debrify_controls_root), parent.getChildAt(index))
        assertEquals(before.size, parent.childCount)
        before.indices.filter { it != index }.forEach { assertSame(before[it], parent.getChildAt(it)) }
    }
    @Test fun missingSkinSpecLeavesTheExistingRootAndInstallationFlagUntouched() {
        val old = view(R.id.debrify_controls_root)
        TvPlayerOriginalAccess.set(activity, "dockSkinSpec\$delegate", lazyOf<Any?>(null))
        set("ottSkinInstalled", false); install()
        assertSame(old, view(R.id.debrify_controls_root)); assertFalse(field("ottSkinInstalled") as Boolean)
    }
    @Test fun missingLegacyRootDoesNotInflateOrReplaceTheController() {
        val old = view(R.id.debrify_controls_root)!!; old.id = View.NO_ID
        set("ottSkinInstalled", false); install()
        assertNotNull(old.parent); assertFalse(field("ottSkinInstalled") as Boolean)
        assertNotNull(old.parent)
    }
    @Test fun detachedRootParentGuardLeavesThePlayerViewUntouched() {
        val playerView = pv(); (playerView.parent as ViewGroup).removeView(playerView)
        playerView.id = R.id.debrify_controls_root; val count = playerView.childCount
        set("ottSkinInstalled", false); install()
        assertNull(playerView.parent); assertEquals(count, playerView.childCount); assertFalse(field("ottSkinInstalled") as Boolean)
    }
    @Test fun inflateFailureKeepsTheOriginalRootAndReportsTheOriginalMessage() {
        val old = view(R.id.debrify_controls_root)!!; val parent = old.parent
        val spec = call("getDockSkinSpec", emptyArray())!!
        TvPlayerOriginalAccess.set(spec, "layoutRes", -1); set("ottSkinInstalled", false)
        install()
        assertSame(old, view(R.id.debrify_controls_root)); assertSame(parent, old.parent); assertFalse(field("ottSkinInstalled") as Boolean)
        val log = ShadowLog.getLogsForTag("AndroidTvPlayer").last()
        assertEquals("Dock skin inflate failed; keeping classic", log.msg); assertNotNull(log.throwable)
    }
    @Test fun iptvSetupGateDoesNotReinstallAnOttSkinEvenWhenItsFlagWasCleared() {
        val old = view(R.id.debrify_controls_root); set("isIptvMode", true); set("ottSkinInstalled", false)
        setup(); assertSame(old, view(R.id.debrify_controls_root)); assertFalse(field("ottSkinInstalled") as Boolean)
    }
    @Test fun ottSeekButtonsUseOppositeTenSecondOffsetsAndExtendTheDockTimer() {
        set("controlsMenuVisible", true); probe.position = 25_000
        assertTrue(view(R.id.ott_seek_back_button)!!.performClick())
        assertEquals(15_000L, probe.position); assertTrue(pending())
        call("cancelScheduledHideControlsMenu", emptyArray()); assertFalse(pending())
        assertTrue(view(R.id.ott_seek_forward_button)!!.performClick())
        assertEquals(25_000L, probe.position); assertTrue(pending())
        assertEquals(listOf("seek:15000", "seek:25000"), probe.events)
    }
    @Test fun sourcesClickHidesTheDockAndUnifiedMenuBeforeOpeningTheSourceBrowser() {
        val browser = field("sourceBrowser") as TvSourceBrowserController
        set("controlsMenuVisible", true); menu().show("playback")
        assertTrue(view(R.id.ott_sources_button)!!.performClick())
        assertFalse(field("controlsMenuVisible") as Boolean); assertFalse(menu().isVisible); assertTrue(browser.isVisible)
    }
    @Test fun subtitleFallbackRoutesToTheBorrowedPanelAfterHidingTheDock() {
        set("unifiedMenu", null); set("controlsMenuVisible", true)
        assertTrue(button("subtitleButton").performClick())
        assertFalse(field("controlsMenuVisible") as Boolean); assertTrue(field("subtitleSettingsVisible") as Boolean)
    }
}
