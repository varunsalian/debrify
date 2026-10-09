package com.debrify.app.tv

import android.view.View
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

/** Actual IPTV episode bootstrap leaves setupControls' installed episode listeners in place. */
@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvEpisodeDockClickCharacterizationTest : TvPhase15LiveOriginalTest() {
    override fun bootstrapPayload(): JSONObject {
        val rows = (1..2).map { number -> JSONObject(mapOf("name" to "Episode $number",
            "url" to "https://phase15.invalid/episode$number.mp4", "channelNumber" to number,
            "isLive" to false, "contentType" to "episodes", "seriesId" to "series", "sourceId" to "provider", "season" to 1, "episode" to number)) }
        return super.bootstrapPayload().put("contentType", "episodes").put("seriesAudioKey", "provider::series")
            .put("channels", JSONArray(rows))
    }
    private fun watchAck() {
        val request = requestIndex("recordIptvWatch")
        assertTrue("episode click emits its actual registration request", request >= 0)
        val reply = messenger.requests[request].reply
        assertNotNull("real binary registration reply", reply)
        reply!!.reply(io.flutter.plugin.common.StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(null).apply { flip() })
    }
    private fun visible() { set("controlsMenuVisible", true); (field("controlsOverlay") as View).visibility = View.VISIBLE }
    @Test fun nextClickUsesTheIptvEpisodeNavigatorRatherThanCatalogNext() {
        visible(); assertTrue(button("iptvNextButton").performClick())
        assertFalse(field("controlsMenuVisible") as Boolean); assertEquals(1, field("currentIptvIndex")); watchAck()
        assertEquals("https://phase15.invalid/episode2.mp4", field("currentIptvStreamUrl"))
        assertTrue(probe.events.any { it.startsWith("media:https://phase15.invalid/episode2.mp4") })
    }
    @Test fun previousClickUsesTheIptvEpisodeNavigatorAndStopsAtItsBeginning() {
        button("iptvNextButton").performClick(); assertEquals("reached the second episode through its real caller", 1, field("currentIptvIndex"))
        probe.events.clear(); visible()
        assertNotNull("episode Previous is available: mode=${field("isIptvMode")} key=${field("iptvSeriesAudioKey")} channels=${field("iptvChannels")}", call("prevIptvEpisode", emptyArray()))
        assertTrue(button("iptvPrevButton").performClick())
        assertFalse(field("controlsMenuVisible") as Boolean); assertEquals(0, field("currentIptvIndex")); watchAck()
        assertEquals("https://phase15.invalid/episode1.mp4", field("currentIptvStreamUrl"))
        assertTrue(probe.events.any { it.startsWith("media:https://phase15.invalid/episode1.mp4") })
        probe.events.clear(); visible(); button("iptvPrevButton").performClick()
        assertFalse(field("controlsMenuVisible") as Boolean); assertEquals(0, field("currentIptvIndex")); assertTrue(probe.events.isEmpty())
    }
}
