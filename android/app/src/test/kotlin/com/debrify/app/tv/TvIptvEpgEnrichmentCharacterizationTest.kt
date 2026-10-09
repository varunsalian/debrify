package com.debrify.app.tv
import android.view.View
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.widget.TextView
import android.widget.ImageView
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import com.debrify.app.MainActivity
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28], instrumentedPackages=["com.debrify.app.tv.AndroidTvTorrentPlayerActivity","com.debrify.app.tv.TvIptvGuideChromeController"])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvEpgEnrichmentCharacterizationTest : TvPhase12OriginalTest() {

    @Test fun freshnessPinsExactStopAndZeroSentinel() {
        val now=1_000_000L
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(now))
        for(stop in listOf(0L,now,now+1)){val e=entry(false)
        e.epgLoaded=true
        e.epgNowStopMs=stop
        clearTransport()
        ensure(e)
        assertTrue("zero/future/exact stop is fresh",requests("requestIptvEpg").isEmpty())}
        val stale=entry(false)
        stale.epgLoaded=true
        stale.epgNowStopMs=now-1
        ensure(stale)
        assertEquals(1,requests("requestIptvEpg").size)
        assertTrue(stale.epgLoading)
    }

    @Test fun guardMatrixRejectsVodInFlightAndNonHttp() {
        for(e in listOf(entry().copy(isLive=false),entry().copy(epgLoading=true),entry().copy(url="stremio-tv://id"))){clearTransport()
        ensure(e)
        assertTrue(requests("requestIptvEpg").isEmpty())}
        val oddlyAllowed=entry(false).copy(url="httpish")
        ensure(oddlyAllowed)
        assertEquals("httpish",args("requestIptvEpg")["channelUrl"])
    }

    @Test fun currentFreshRowNeedsCatchupUntilMarkerLoaded() {
        val e=entry()
        e.epgLoaded=true
        e.epgNowStopMs=Long.MAX_VALUE
        ensure(e)
        assertTrue(e.epgLoading)
        assertEquals(true,args("requestIptvEpg")["includeCatchupMetadata"])
        epgAnswer(value=epgReply())
        clearTransport()
        ensure(e)
        assertTrue(requests("requestIptvEpg").isEmpty())
    }

    @Test fun enrichedInlineReplyPinsEveryFieldAndVisibleHeader() {
        val e=playing(entry().copy(tvArchiveDuration=null))
        button().visibility=View.GONE
        e.epgNowTitle="old"
        e.epgNextTitle="old next"
        ensure(e)
        assertTrue(e.epgLoading)
        epgAnswer(value=epgReply(start=123L,stop=Long.MAX_VALUE,nextStart=456L),queued=false)
        idle()
        assertFalse(e.epgLoading)
        assertTrue(e.epgLoaded)
        assertTrue(e.epgCatchupMetadataLoaded)
        assertEquals("Now",e.epgNowTitle)
        assertEquals(123L,e.epgNowStartMs)
        assertEquals(Long.MAX_VALUE,e.epgNowStopMs)
        assertTrue(e.epgNowHasArchive)
        assertEquals("Next",e.epgNextTitle)
        assertEquals(456L,e.epgNextStartMs)
        assertEquals("Now: Now   ›   Next: Next",text("iptvGuideCurrentEpg"))
        assertEquals(View.VISIBLE,v("iptvGuideCurrentEpg").visibility)
        assertEquals(View.VISIBLE,button().visibility)
        assertTrue(button().isEnabled)
    }

    @Test fun cheapInlineReplyClearsPriorEnrichmentAndDoesNotUpgradeNonCurrent() {
        val e=entry(false)
        e.epgCatchupMetadataLoaded=true
        ensure(e)
        assertEquals(false,args("requestIptvEpg")["includeCatchupMetadata"])
        epgAnswer(value=epgReply(archive=false),queued=false)
        idle()
        assertFalse(e.epgLoading)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgCatchupMetadataLoaded)
        assertFalse(e.epgNowHasArchive)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun cheapInlineReplyBecomingCurrentRequestsOneUpgrade() {
        val e=entry(false)
        ensure(e)
        e.isCurrent=true
        playing(e)
        epgAnswer(value=epgReply(archive=false),queued=false)
        idle()
        assertEquals(2,requests("requestIptvEpg").size)
        assertEquals(true,args("requestIptvEpg")["includeCatchupMetadata"])
        assertEquals(false,args("requestIptvEpg")["includeSchedule"])
        assertFalse(e.epgCatchupMetadataLoaded)
        assertTrue(e.epgLoading)
        assertEquals("Now: Now   ›   Next: Next",text("iptvGuideCurrentEpg"))
        epgAnswer(value=epgReply())
        idle()
        assertTrue(e.epgCatchupMetadataLoaded)
        assertFalse(e.epgLoading)
        assertEquals(2,requests("requestIptvEpg").size)
    }

    @Test fun enrichedInlineReplyBecomingNonCurrentKeepsCapturedMarker() {
        val e=entry()
        ensure(e)
        e.isCurrent=false
        t("iptvGuideCurrentEpg").text="untouched"
        epgAnswer(value=epgReply(),queued=false)
        idle()
        assertTrue(e.epgCatchupMetadataLoaded)
        assertEquals("untouched",text("iptvGuideCurrentEpg"))
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun enrichedInlineAfterDestroyStillPublishesAndPostsRetry() {
        val e=playing()
        ensure(e)
        destroyNow()
        epgAnswer(value=epgReply(archive=false),queued=false)
        idle()
        assertTrue(e.epgLoaded)
        assertTrue(e.epgCatchupMetadataLoaded)
        assertFalse(e.epgLoading)
        assertEquals("Now",e.epgNowTitle)
        untilUptime(replyUptime+59_999)
        assertTrue(e.epgCatchupMetadataLoaded)
        untilUptime(replyUptime+60_000)
        assertFalse("retry clears marker before destroy guard",e.epgCatchupMetadataLoaded)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun nullInlineReplyDefaultsAndSixtySecondDeadline() {
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(1_000_000L))
        val e=entry(false)
        e.epgNowStartMs=99
        e.epgNextStartMs=99
        e.epgNowHasArchive=true
        ensure(e)
        epgAnswer(value=null,queued=false)
        idle()
        assertNull(e.epgNowTitle)
        assertNull(e.epgNextTitle)
        assertEquals(0L,e.epgNowStartMs)
        assertEquals(0L,e.epgNextStartMs)
        assertFalse(e.epgNowHasArchive)
        assertEquals(replyWallClock+60_000L,e.epgNowStopMs)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgLoading)
    }

    @Test fun malformedInlineReplyDefaultsAndSixtySecondDeadline() {
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(1_000_000L))
        val e=entry(false)
        e.epgNowStartMs=99
        e.epgNextStartMs=99
        e.epgNowHasArchive=true
        ensure(e)
        epgAnswer(value=mapOf("now" to "bad","next" to 123),queued=false)
        idle()
        assertNull(e.epgNowTitle)
        assertNull(e.epgNextTitle)
        assertEquals(0L,e.epgNowStartMs)
        assertEquals(0L,e.epgNextStartMs)
        assertFalse(e.epgNowHasArchive)
        assertEquals(replyWallClock+60_000L,e.epgNowStopMs)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgLoading)
    }

    @Test fun blankInlineReplyDefaultsAndSixtySecondDeadline() {
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(1_000_000L))
        val e=entry(false)
        e.epgNowStartMs=99
        e.epgNextStartMs=99
        e.epgNowHasArchive=true
        ensure(e)
        epgAnswer(value=mapOf("now" to mapOf("title" to " ","startMs" to "1","hasArchive" to "true"),"next" to mapOf("title" to " ","startMs" to "2")),queued=false)
        idle()
        assertNull(e.epgNowTitle)
        assertNull(e.epgNextTitle)
        assertEquals(0L,e.epgNowStartMs)
        assertEquals(0L,e.epgNextStartMs)
        assertFalse(e.epgNowHasArchive)
        assertEquals(replyWallClock+60_000L,e.epgNowStopMs)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgLoading)
    }

    @Test fun enrichedQueuedReplyPinsEveryFieldAndVisibleHeader() {
        val e=playing(entry().copy(tvArchiveDuration=null))
        button().visibility=View.GONE
        e.epgNowTitle="old"
        e.epgNextTitle="old next"
        ensure(e)
        assertTrue(e.epgLoading)
        epgAnswer(value=epgReply(start=123L,stop=Long.MAX_VALUE,nextStart=456L),queued=true)
        assertTrue(e.epgLoading)
        idle()
        assertFalse(e.epgLoading)
        assertTrue(e.epgLoaded)
        assertTrue(e.epgCatchupMetadataLoaded)
        assertEquals("Now",e.epgNowTitle)
        assertEquals(123L,e.epgNowStartMs)
        assertEquals(Long.MAX_VALUE,e.epgNowStopMs)
        assertTrue(e.epgNowHasArchive)
        assertEquals("Next",e.epgNextTitle)
        assertEquals(456L,e.epgNextStartMs)
        assertEquals("Now: Now   ›   Next: Next",text("iptvGuideCurrentEpg"))
        assertEquals(View.VISIBLE,v("iptvGuideCurrentEpg").visibility)
        assertEquals(View.VISIBLE,button().visibility)
        assertTrue(button().isEnabled)
    }

    @Test fun cheapQueuedReplyClearsPriorEnrichmentAndDoesNotUpgradeNonCurrent() {
        val e=entry(false)
        e.epgCatchupMetadataLoaded=true
        ensure(e)
        assertEquals(false,args("requestIptvEpg")["includeCatchupMetadata"])
        epgAnswer(value=epgReply(archive=false),queued=true)
        idle()
        assertFalse(e.epgLoading)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgCatchupMetadataLoaded)
        assertFalse(e.epgNowHasArchive)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun cheapQueuedReplyBecomingCurrentRequestsOneUpgrade() {
        val e=entry(false)
        ensure(e)
        e.isCurrent=true
        playing(e)
        epgAnswer(value=epgReply(archive=false),queued=true)
        idle()
        assertEquals(2,requests("requestIptvEpg").size)
        assertEquals(true,args("requestIptvEpg")["includeCatchupMetadata"])
        assertEquals(false,args("requestIptvEpg")["includeSchedule"])
        assertFalse(e.epgCatchupMetadataLoaded)
        assertTrue(e.epgLoading)
        assertEquals("Now: Now   ›   Next: Next",text("iptvGuideCurrentEpg"))
        epgAnswer(value=epgReply())
        idle()
        assertTrue(e.epgCatchupMetadataLoaded)
        assertFalse(e.epgLoading)
        assertEquals(2,requests("requestIptvEpg").size)
    }

    @Test fun enrichedQueuedReplyBecomingNonCurrentKeepsCapturedMarker() {
        val e=entry()
        ensure(e)
        e.isCurrent=false
        t("iptvGuideCurrentEpg").text="untouched"
        epgAnswer(value=epgReply(),queued=true)
        idle()
        assertTrue(e.epgCatchupMetadataLoaded)
        assertEquals("untouched",text("iptvGuideCurrentEpg"))
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun enrichedQueuedAfterDestroyStillPublishesAndPostsRetry() {
        val e=playing()
        ensure(e)
        destroyNow()
        epgAnswer(value=epgReply(archive=false),queued=true)
        idle()
        assertTrue(e.epgLoaded)
        assertTrue(e.epgCatchupMetadataLoaded)
        assertFalse(e.epgLoading)
        assertEquals("Now",e.epgNowTitle)
        untilUptime(replyUptime+59_999)
        assertTrue(e.epgCatchupMetadataLoaded)
        untilUptime(replyUptime+60_000)
        assertFalse("retry clears marker before destroy guard",e.epgCatchupMetadataLoaded)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun nullQueuedReplyDefaultsAndSixtySecondDeadline() {
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(1_000_000L))
        val e=entry(false)
        e.epgNowStartMs=99
        e.epgNextStartMs=99
        e.epgNowHasArchive=true
        ensure(e)
        epgAnswer(value=null,queued=true)
        idle()
        assertNull(e.epgNowTitle)
        assertNull(e.epgNextTitle)
        assertEquals(0L,e.epgNowStartMs)
        assertEquals(0L,e.epgNextStartMs)
        assertFalse(e.epgNowHasArchive)
        assertEquals(replyWallClock+60_000L,e.epgNowStopMs)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgLoading)
    }

    @Test fun malformedQueuedReplyDefaultsAndSixtySecondDeadline() {
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(1_000_000L))
        val e=entry(false)
        e.epgNowStartMs=99
        e.epgNextStartMs=99
        e.epgNowHasArchive=true
        ensure(e)
        epgAnswer(value=mapOf("now" to "bad","next" to 123),queued=true)
        idle()
        assertNull(e.epgNowTitle)
        assertNull(e.epgNextTitle)
        assertEquals(0L,e.epgNowStartMs)
        assertEquals(0L,e.epgNextStartMs)
        assertFalse(e.epgNowHasArchive)
        assertEquals(replyWallClock+60_000L,e.epgNowStopMs)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgLoading)
    }

    @Test fun blankQueuedReplyDefaultsAndSixtySecondDeadline() {
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(1_000_000L))
        val e=entry(false)
        e.epgNowStartMs=99
        e.epgNextStartMs=99
        e.epgNowHasArchive=true
        ensure(e)
        epgAnswer(value=mapOf("now" to mapOf("title" to " ","startMs" to "1","hasArchive" to "true"),"next" to mapOf("title" to " ","startMs" to "2")),queued=true)
        idle()
        assertNull(e.epgNowTitle)
        assertNull(e.epgNextTitle)
        assertEquals(0L,e.epgNowStartMs)
        assertEquals(0L,e.epgNextStartMs)
        assertFalse(e.epgNowHasArchive)
        assertEquals(replyWallClock+60_000L,e.epgNowStopMs)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgLoading)
    }

    @Test fun blankNowDeadlineChoosesEarlierPositiveNextOnly() {
        assertTrue(android.os.SystemClock.setCurrentTimeMillis(1_000_000L))
        for(delta in listOf(10L,0L,-1L,60_001L)){val nextStart=if(delta>0) org.robolectric.shadows.ShadowSystem.currentTimeMillis()+delta else delta
        val e=entry(false)
        ensure(e)
        epgAnswer(value=epgReply(title=null,nextStart=nextStart))
        idle()
        assertEquals(if(delta==10L) nextStart else replyWallClock+60_000L,e.epgNowStopMs)}
    }

    @Test fun archiveRetryPinsSixtySecondsAndRequestsMetadataAgain() {
        val e=playing()
        ensure(e)
        epgAnswer(value=epgReply(archive=false))
        idle()
        assertTrue(e.epgCatchupMetadataLoaded)
        untilUptime(replyUptime+59_999)
        assertEquals(1,requests("requestIptvEpg").size)
        assertTrue(e.epgCatchupMetadataLoaded)
        untilUptime(replyUptime+60_000)
        assertEquals(2,requests("requestIptvEpg").size)
        assertTrue(e.epgLoading)
        assertFalse(e.epgCatchupMetadataLoaded)
        assertEquals(true,args("requestIptvEpg")["includeCatchupMetadata"])
    }

    @Test fun archiveRetryNotCurrentClearsMetadataWithoutRefetch() {
        val e=playing()
        ensure(e)
        epgAnswer(value=epgReply(archive=false))
        idle()
        e.isCurrent=false
        untilUptime(replyUptime+60_000)
        assertFalse(e.epgCatchupMetadataLoaded)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun archiveRetryFinishingClearsMetadataWithoutRefetch() {
        val e=playing()
        ensure(e)
        epgAnswer(value=epgReply(archive=false))
        idle()
        activity.finish()
        untilUptime(replyUptime+60_000)
        assertFalse(e.epgCatchupMetadataLoaded)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun destroyCancelsAlreadyPostedArchiveRetry() {
        val e=playing()
        ensure(e)
        epgAnswer(value=epgReply(archive=false))
        idle()
        destroyNow()
        untilUptime(replyUptime+60_000)
        assertTrue(e.epgCatchupMetadataLoaded)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun archiveTrueDoesNotPostAnotherRetry() {
        val e=playing()
        ensure(e)
        epgAnswer(value=epgReply(archive=true))
        idle()
        untilUptime(replyUptime+60_000)
        assertTrue(e.epgCatchupMetadataLoaded)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun silentWatchdogAfterDestroyPostsAnotherBorrowedRetry() {
        val e=playing()
        val armedAt=android.os.SystemClock.uptimeMillis()
        ensure(e)
        destroyNow()
        untilUptime(armedAt+44_999)
        assertFalse(e.epgLoaded)
        assertTrue(e.epgLoading)
        untilUptime(armedAt+45_000)
        assertTrue(e.epgLoaded)
        assertFalse(e.epgLoading)
        assertTrue(e.epgCatchupMetadataLoaded)
        assertNull(e.epgNowTitle)
        assertEquals(org.robolectric.shadows.ShadowSystem.currentTimeMillis()+60_000,e.epgNowStopMs)
        untilUptime(armedAt+104_999)
        assertTrue(e.epgCatchupMetadataLoaded)
        untilUptime(armedAt+105_000)
        assertFalse(e.epgCatchupMetadataLoaded)
        assertEquals(1,requests("requestIptvEpg").size)
    }

    @Test fun fetchStartPinsOneExactMetadataRequest() {
        val e=entry()
        ensure(e)
        assertTrue(e.epgLoading)
        assertEquals(1,requests("requestIptvEpg").size)
        assertEquals(e.url,args("requestIptvEpg")["channelUrl"])
        assertEquals(false,args("requestIptvEpg")["includeSchedule"])
        assertEquals(true,args("requestIptvEpg")["includeCatchupMetadata"])
    }
}
