package com.debrify.app.tv

import androidx.media3.common.PlaybackException
import android.os.Handler
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvHlsRetryCharacterizationTest : TvPhase17OriginalTest() {
    private fun retry(e: PlaybackException)=call("retryIptvAsHlsIfUnrecognized",arrayOf(PlaybackException::class.java),e)
    @Test fun missingCurrentUrlDeclinesWithoutRecordingEvidence() {iptv();assertEquals(false,retry(sniff()));assertTrue(forced().isEmpty());assertTrue(tuning().isEmpty())}
    @Test fun alreadyForcedUrlCannotRetryAgain() {iptv();set("currentIptvStreamUrl",original);forced().add(original);assertEquals(false,retry(sniff()));assertEquals(setOf(original),forced());assertTrue(tuning().isEmpty())}
    @Test fun unrelatedCauseChainDoesNotForceHls() {iptv();set("currentIptvStreamUrl",original);assertEquals(false,retry(error()));assertTrue(forced().isEmpty());assertTrue(tuning().isEmpty())}
    @Test fun sniffFailureWithoutACurrentEntryDoesNotPoisonTheUrl() {set("currentIptvStreamUrl",original);assertEquals(false,retry(sniff()));assertTrue(forced().isEmpty());assertTrue(tuning().isEmpty())}
    @Test fun stremioCandidateGetsANewFullWatchdogWindowAfterHlsCorrection() {
        iptv();set("currentIptvStreamUrl",original);set("iptvStremioChannelKey","candidate");invoke("armIptvStremioStallWatchdog")
        val old=field("iptvStremioStallRunnable") as Runnable;advance(10_000)
        assertEquals(true,retry(sniff()));val replacement=field("iptvStremioStallRunnable") as Runnable
        assertNotSame(old,replacement);val h=field("progressHandler") as Handler;assertFalse(TvPlaylistUiQueue.pending(h,old));assertTrue(TvPlaylistUiQueue.pending(h,replacement))
        advance(19_999);assertSame(replacement,field("iptvStremioStallRunnable"));advance(1);assertFalse(TvPlaylistUiQueue.pending(h,replacement))
    }
    @Test fun ordinaryHlsRetryDoesNotCreateAStremioWatchdog() {iptv();set("currentIptvStreamUrl",original);assertEquals(true,retry(sniff()));assertNull(field("iptvStremioStallRunnable"));assertEquals(1,probe.mediaItems.size)}
    @Test fun successfulCorrectionLogsTheCurrentEntryNameAndUsesSameUrlHeaders() {val e=iptv();set("currentIptvStreamUrl",original);assertEquals(true,retry(sniff()));assertEquals(e.httpHeaders,field("currentIptvHttpHeaders"));assertEquals(original,field("currentIptvStreamUrl"));assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("AndroidTvPlayer").any {it.msg=="Unrecognized format for Cinema — retrying as HLS"})}
    @Test fun outOfWindowIndexCannotForceHlsForTheFirstEntry() {
        iptv();set("currentIptvStreamUrl",original);set("currentIptvIndex",1);assertEquals(false,retry(sniff()));assertTrue(forced().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun hlsCorrectionRefreshesTheRecordButtonAfterReplacementAndAgainAfterPrepare() {
        iptv(channel("http://h/opaque"));set("currentIptvStreamUrl","http://h/opaque")
        val writes=mutableListOf<Boolean>()
        val b=object : androidx.appcompat.widget.AppCompatButton(activity) {
            var observing=false
            override fun setEnabled(enabled: Boolean) {if(observing)writes.add(enabled);super.setEnabled(enabled)}
        }
        set("iptvRecordButton",b);b.observing=true;assertEquals(true,retry(sniff()));assertEquals(listOf(false,false),writes)
    }
    @Test fun sniffMatchStopsBeforeReadingAnIrrelevantNestedCause() {
        var reads=0
        val marker=object : androidx.media3.exoplayer.source.UnrecognizedInputFormatException("sniff",android.net.Uri.parse(original)) {
            override val cause: Throwable? get() {reads++;return null}
        }
        iptv();set("currentIptvStreamUrl",original);assertEquals(true,retry(error(java.io.IOException("wrapper",marker))));assertEquals(0,reads)
    }
}
