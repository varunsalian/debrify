package com.debrify.app.tv

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

/** A separate real activity launch: live IPTV forces the legacy layout before binding. */
@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvLiveLaunchDockCharacterizationTest : TvPhase15LiveOriginalTest() {
    override val skin = TvControlsSkin.OTT
    @Test fun liveBootstrapKeepsClassicDockDespiteTheSelectedOttSkin() {
        assertTrue(field("isIptvMode") as Boolean); assertFalse(field("ottSkinInstalled") as Boolean)
        assertNull(field("ottCaptionLabel")); assertNotNull(field("iptvJumpButton"))
        assertEquals("CH -", button("iptvPrevButton").text.toString()); assertEquals("CH +", button("iptvNextButton").text.toString())
        assertEquals(0f, (field("controlsOverlay") as android.view.View).alpha, 0f)
    }
}
