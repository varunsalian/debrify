package com.debrify.app.tv

import android.view.View
import android.widget.FrameLayout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvControlsLiftCharacterizationTest : TvPhase16OriginalTest() {
    private fun height() = TvPlayerOriginalAccess.field(field("subtitleControlsLift")!!, "controlsClearanceHeightPx") as Int
    private fun prepare(): FrameLayout {
        val dock = v("controlsOverlay"); dock.layout(0, 0, 1000, 100); set("controlsMenuVisible", true)
        return FrameLayout(activity).also { it.layout(0, 0, 1000, 60); it.visibility = View.VISIBLE; set("iptvZapBanner", it); set("iptvZapBannerDocked", true) }
    }
    @Test fun dockedVisibleBannerContributesHeightImmediatelyAndAfterPostedRemeasure() {
        val banner = prepare(); runOriginal("updateSubtitleControlsLift"); assertEquals(160, height())
        v("controlsOverlay").layout(0, 0, 1000, 140); banner.layout(0, 0, 1000, 80); step(17); assertEquals(220, height())
    }
    @Test fun floatingAndInvisibleBannerDoNotContributeHeight() {
        val banner = prepare(); set("iptvZapBannerDocked", false); runOriginal("updateSubtitleControlsLift"); assertEquals(100, height())
        set("iptvZapBannerDocked", true); banner.visibility = View.INVISIBLE; runOriginal("updateSubtitleControlsLift"); assertEquals(100, height())
        banner.visibility = View.GONE; runOriginal("updateSubtitleControlsLift"); assertEquals(100, height())
    }
    @Test fun hiddenDockAndNullDockLeaveLiftUnchangedAndLatePostedWorkDoesNotRestoreIt() {
        prepare(); runOriginal("updateSubtitleControlsLift"); assertEquals(160, height())
        set("controlsMenuVisible", false); v("controlsOverlay").layout(0, 0, 1000, 200); step(17); assertEquals(160, height())
        runOriginal("updateSubtitleControlsLift"); assertEquals(160, height())
        set("controlsMenuVisible", true); set("controlsOverlay", null); val absent = runCatching { runOriginal("updateSubtitleControlsLift") }; assertTrue(absent.isSuccess); assertEquals(160, height())
    }
    @Test fun visibleHideRestoresSubtitleClearanceImmediately() {
        prepare(); runOriginal("updateSubtitleControlsLift"); hideDock(); assertEquals(0, height())
        step(17); assertEquals(0, height())
    }
}
