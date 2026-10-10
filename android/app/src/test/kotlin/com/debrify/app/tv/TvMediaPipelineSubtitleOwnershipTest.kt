package com.debrify.app.tv

import com.debrify.app.util.SubtitleSettings
import com.debrify.app.util.SubtitleFontManager
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvMediaPipelineSubtitleOwnershipTest : TvPhase19PipelineTest() {
    @Test fun playerBuildResetsOffsetAndKeepsActivityAsTheProviderOwner() {
        SubtitleSettings.setActiveSubtitleIdentityProvider(activity) { null }
        SubtitleSettings.setSyncOffsetMs(activity, 2000)
        assertEquals(2000L, SubtitleSettings.getSyncOffsetMs(activity))
        buildPipeline()
        assertEquals("fresh session offset", 0L, SubtitleSettings.getSyncOffsetMs(activity))
        assertSame("provider ownership remains the Activity", activity, required(SubtitleSettings, "identityProviderOwner"))
        SubtitleSettings.clearActiveSubtitleIdentityProvider(activity)
        assertNull(read(SubtitleSettings, "activeSubtitleIdentityProvider"))
    }
    @Test fun identityProviderReevaluatesTheActiveSubtitleOnEachRead() {
        buildPipeline()
        set("externalSubtitleActive", true); set("activeExternalSubtitleUrl", "https://p19.test/one.srt")
        SubtitleSettings.setSyncOffsetMs(activity, 1500)
        assertEquals(1500L, SubtitleSettings.getSyncOffsetMs(activity))
        set("activeExternalSubtitleUrl", "https://p19.test/two.srt")
        assertEquals("new subtitle invalidates the old identity offset", 0L, SubtitleSettings.getSyncOffsetMs(activity))
        set("activeExternalSubtitleUrl", "https://p19.test/one.srt")
        assertEquals(1500L, SubtitleSettings.getSyncOffsetMs(activity))
    }
    @Test fun projectedAppearanceAndFontAreSynchronizedBeforeApplication() {
        val values = JSONObject().put("subtitle_size_index", 4).put("subtitle_style_index", 2)
            .put("subtitle_color_index", 3).put("subtitle_selected_font_id", "sourceserif")
        val projection = JSONObject().put("version", 2).put("state", "active").put("publication", 1)
            .put("profileId", "p19").put("dataGeneration", 1).put("sessionEpoch", 1).put("values", values)
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter.profiles_runtime_mode_v1", "profileCommitted")
            .putString("flutter.profiles_native_projection_v1", projection.toString())
            .putLong("flutter.profiles_native_projection_sequence_v1", 1).commit()
        buildPipeline()
        assertEquals("projected size", 4, SubtitleSettings.getSizeIndex(activity))
        assertEquals("projected style", 2, SubtitleSettings.getStyleIndex(activity))
        assertEquals("projected color", 3, SubtitleSettings.getColorIndex(activity))
        val overlay = field("subtitleOverlay")!!
        assertEquals("applied size uses synchronized settings", SubtitleSettings.getFontSizeSp(activity) * activity.resources.displayMetrics.scaledDensity,
            required(overlay, "defaultTextSize") as Float, 0.01f)
        assertEquals("selected font", "sourceserif", SubtitleFontManager.getProfileSelectedFontId(activity))
    }
    @Test fun resizeModeAndInitialFocusAreAppliedToTheRealPlayerView() {
        val view = field("playerView") as androidx.media3.ui.PlayerView
        view.isFocusableInTouchMode = true; view.clearFocus(); set("resizeModeIndex", 2)
        buildPipeline()
        assertEquals(androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM, view.resizeMode)
        assertTrue("player receives initial focus", view.hasFocus())
    }
}
