package com.debrify.app.tv

import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSkipUiCharacterizationTest : TvPhase3OriginalTest() {
    private fun request(duration: Long = 600_000L) = invoke("currentSkipSegmentRequest", duration)
    private fun cached(segment: TvSkipSegment) {
        val key = TvPlayerOriginalAccess.field(request()!!, "key") as String
        set("loadedSkipSegmentKey", key)
        set("skipSegments", TvSkipSegments(if (segment.type == TvSkipSegmentType.INTRO) listOf(segment) else emptyList(),
            if (segment.type == TvSkipSegmentType.OUTRO) listOf(segment) else emptyList()))
    }

    @Test fun completeRequestIdentityIncludesProviderImdbSeasonEpisodeAndFlooredDuration() {
        val model = series(); model.contentType = "SERIES"
        var req = request(600_999L)!!
        assertEquals("skipdb:tt12345:0:1:600", TvPlayerOriginalAccess.field(req, "key"))
        assertEquals("tt12345", TvPlayerOriginalAccess.field(req, "imdbId"))
        assertEquals(0, TvPlayerOriginalAccess.field(req, "season")); assertEquals(1, TvPlayerOriginalAccess.field(req, "episode"))
        set("skipSegmentProviderId", "introdb"); req = request(601_000L)!!
        assertEquals("introdb:tt12345:0:1:601", TvPlayerOriginalAccess.field(req, "key"))
        for (duration in listOf(-1L, 0L, 999L, androidx.media3.common.C.TIME_UNSET)) assertNull(request(duration))
        model.imdbId = "ttbad"; assertNull(request()); model.imdbId = "tt12345"
        model.items[0] = model.items[0].copy(season = -1); assertNull(request())
        model.items[0] = model.items[0].copy(season = 0, episode = 0); assertNull(request())
        model.items[0] = model.items[0].copy(episode = 1)
        set("skipSegmentsEnabled", false); assertNull(request()); set("skipSegmentsEnabled", true)
        set("isIptvMode", true); assertNull(request()); set("isIptvMode", false)
        set("skipSegmentProviderId", "unsupported"); assertNull(request())
    }

    @Test fun viewBindingIsLiveAndReadyGateKeepsOutgoingPositionFromShowingANewItemMarker() {
        series(); invoke("updateSkipSegmentState", 5000L, 600_000L) // no bound button yet
        assertNull(field("skipSegmentFetchJob"))
        bindViews(); cached(TvSkipSegment(TvSkipSegmentType.INTRO, 1000, 20_000))
        set("hasEverBeenReady", false); invoke("updateSkipSegmentState", 5000L, 600_000L)
        assertEquals(View.GONE, (field("skipSegmentButton") as View).visibility)
        set("hasEverBeenReady", true); invoke("updateSkipSegmentState", 5000L, 600_000L)
        assertEquals(View.VISIBLE, (field("skipSegmentButton") as View).visibility)
        assertNull(field("skipSegmentFetchJob"))
    }

    @Test fun skipSeeksToBoundedEndReleasesResumeHoldAndHidesButton() {
        bindViews(); series(); val p = PlayerProbe(position = 5000, duration = 15_000); set("player", p.player)
        val segment = TvSkipSegment(TvSkipSegmentType.INTRO, 1000, 20_000)
        set("activeSkipSegment", segment); set("resumeHoldTargetMs", 10_000L)
        (field("skipSegmentButton") as View).visibility = View.VISIBLE
        invoke("skipActiveSegment")
        assertEquals(listOf("seek:15000"), p.events); assertEquals(0L, field("resumeHoldTargetMs"))
        assertNull(field("activeSkipSegment")); assertEquals(View.GONE, (field("skipSegmentButton") as View).visibility)
    }

    @Test fun creditsAndFocusOfferFollowActualUpNextShowAndDismiss() {
        bindViews(); series().nextEpisodeMap = mapOf(0 to 1)
        cached(TvSkipSegment(TvSkipSegmentType.OUTRO, 550_000, 600_000))
        invoke("updateSkipSegmentState", 575_000L, 600_000L)
        val button = field("skipSegmentButton") as View
        assertEquals(View.VISIBLE, button.visibility); val firstFocusKey = field("skipFocusOfferedKey")
        assertNotNull(firstFocusKey)
        invoke("showUpNextCard", 1); invoke("updateSkipSegmentState", 575_000L, 600_000L)
        assertEquals(View.GONE, button.visibility); assertNull(field("activeSkipSegment"))
        invoke("dismissUpNext"); set("skipFocusOfferedKey", null)
        invoke("updateSkipSegmentState", 575_000L, 600_000L)
        assertEquals(View.VISIBLE, button.visibility); assertEquals(firstFocusKey, field("skipFocusOfferedKey"))
        for (flag in listOf("controlsMenuVisible", "playlistVisible", "seekbarVisible", "upNextVisible")) {
            set("skipFocusOfferedKey", null); set(flag, true)
            invoke("updateSkipSegmentState", 575_000L, 600_000L)
            assertNull("focus blocked by $flag", field("skipFocusOfferedKey")); set(flag, false)
        }
    }
}
