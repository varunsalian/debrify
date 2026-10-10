package com.debrify.app.tv

import android.os.Handler
import android.view.View
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.MediaItem
import androidx.media3.ui.PlayerView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvTuneCharacterizationTest : TvPhase17OriginalTest() {
    private fun item(): MediaItem {assertFalse("player receives replacement item",probe.mediaItems.isEmpty());return probe.mediaItems.last()}
    private fun frameHold()=org.robolectric.util.ReflectionHelpers.getField<Boolean>(field("playerView"),"keepContentOnPlayerReset")
    @Test fun firstMediaReplacementSeesHeadersIdentityAndStrictModeBeforePrepare() {
        val entry=iptv(channel(original));strict().add(original)
        val readiness=field("subtitleTrackReadiness") as SubtitleTrackReadiness
        readiness.onReady();assertTrue(readiness.canSelect(true))
        val observations=mutableListOf<String>()
        probe.onEvent={event -> if(event.startsWith("media:")) {
            assertEquals(entry.httpHeaders,field("currentIptvHttpHeaders"));assertEquals(original,field("currentIptvStreamUrl"));assertTrue(field("iptvStrictTsActive") as Boolean)
            assertFalse(readiness.canSelect(true));assertTrue(frameHold());observations.add(event)
        } }
        tune(entry);assertEquals(1,observations.size);assertEquals(listOf("media:$original","prepare","intent:true","play"),probe.events)
        assertEquals(entry.name,item().mediaMetadata.title);assertEquals(entry.group,item().mediaMetadata.artist)
    }
    @Test fun absentGroupKeepsTheIptvArtistFallback() { tune(iptv(channel().copy(group=null)));assertEquals("IPTV",item().mediaMetadata.artist) }
    @Test fun vodResumeIsPassedBeforePrepareWhileLiveIgnoresStoredResume() {
        val entry=iptv(channel(live=false));val readiness=field("subtitleTrackReadiness") as SubtitleTrackReadiness
        readiness.onReady();assertTrue(readiness.canSelect(true))
        probe.onEvent={if(it.startsWith("media:"))assertFalse("VOD replacement clears subtitle readiness before player dispatch",readiness.canSelect(true))}
        tune(entry);assertEquals("media:${entry.url}:12345",probe.events.first());assertEquals(1,probe.mediaItems.size)
        assertEquals(listOf("media:${entry.url}:12345","prepare","intent:true","play"),probe.events)
    }
    @Test fun zeroVodResumeUsesThePlainReplacementOverload() { val e=iptv(channel(live=false).copy(resumePositionMs=0));tune(e);assertEquals("media:${e.url}",probe.events.first()) }
    @Test fun negativeVodResumeAlsoUsesThePlainOverload() { val e=iptv(channel(live=false).copy(resumePositionMs=-1));tune(e);assertEquals("media:${e.url}",probe.events.first()) }
    @Test fun liveResumeAlwaysJoinsTheEdgeWithOneReplacement() { val e=iptv();tune(e);assertEquals("media:${e.url}",probe.events.first()) }
    @Test fun aForcedHlsUrlCarriesMimeWhileUnforcedUrlDoesNot() {
        val e=iptv(channel("http://h/opaque"));forced().add(e.url);tune(e);assertEquals("application/x-mpegURL",item().localConfiguration!!.mimeType)
        forced().clear();tune(e);assertNull(item().localConfiguration!!.mimeType)
    }
    @Test fun aSingleOtherStrictUrlDoesNotPoisonTheSession() { strict().add("http://h/other.ts");tune();assertFalse(field("iptvStrictTsActive") as Boolean) }
    @Test fun twoDistinctStrictUrlsEscalateTheWholeSession() { strict().addAll(listOf("http://h/a.ts","http://h/b.ts"));tune();assertTrue(field("iptvStrictTsActive") as Boolean) }
    @Test fun activeAndAcceptedTwinAlwaysUseStrictDemux() {
        begin();assertTrue(field("iptvStrictTsActive") as Boolean);invoke("acceptIptvTwinTrial");tune(url=twin);assertTrue(field("iptvStrictTsActive") as Boolean);assertTrue(strict().isEmpty())
    }
    @Test fun aNewTuneSupersedesTrialAndBothParkedFieldsBeforeMediaReplacement() {
        begin();set("iptvTwinTrialRestoreOriginal",original);set("iptvTwinTrialRestoreTwin",twin)
        probe.onEvent={if(it.startsWith("media:")){assertNull(trial());assertNull(field("iptvTwinTrialRestoreOriginal"));assertNull(field("iptvTwinTrialRestoreTwin"))}}
        tune(url="http://h/new.ts");assertNull(field("iptvTwinTrialTimeout"))
    }
    @Test fun sameTwinRetunePreservesTrialAndParkedRollback() {
        begin();set("iptvTwinTrialRestoreOriginal",original);set("iptvTwinTrialRestoreTwin",twin);set("iptvLiveRetuneInFlight",true)
        tune(url=twin);assertEquals(twin,trial());assertEquals(original,field("iptvTwinTrialRestoreOriginal"));assertEquals(twin,field("iptvTwinTrialRestoreTwin"))
    }
    @Test fun genuineTuneResetsRecoveryAndHidesOldPillWhileRetunePreservesBoth() {
        tune();quiet();recovery().onEnded();advance(0);quiet();invoke("showIptvReconnectPill","old")
        val pill=reconnectPill()
        retune("ended",2);quiet();assertEquals(View.VISIBLE,pill.visibility);assertTrue(TvPlayerOriginalAccess.field(recovery(),"episodeActive") as Boolean)
        tune();quiet();assertEquals(View.GONE,pill.visibility);assertFalse(TvPlayerOriginalAccess.field(recovery(),"episodeActive") as Boolean)
    }
    @Test fun tuneRestartsOnlyOneFiveSecondTickerAndRefreshesTheRecordButton() {
        val b=AppCompatButton(activity);set("iptvRecordButton",b);tune(iptv(channel("http://h/plain.ts",live=false)));tune(iptv(channel("http://h/plain.m3u8",live=false)))
        assertFalse(b.isEnabled);assertEquals(0.4f,b.alpha);val h=field("progressHandler") as Handler
        assertTrue(TvPlaylistUiQueue.pending(h,field("progressRunnable") as Runnable));messenger.requests.clear();advance(5_000)
        assertEquals(1,requests("torrentPlaybackProgress").size)
    }
    @Test fun nullPlayerStillPublishesIdentityAndSchedulesProgress() {
        iptv();set("player",null);tune();assertEquals(original,field("currentIptvStreamUrl"));assertTrue(probe.events.isEmpty())
        assertTrue(TvPlaylistUiQueue.pending(field("progressHandler") as Handler,field("progressRunnable") as Runnable))
    }
    @Test fun tuneDiagnosticsCarryChannelLiveFlagAndForcedHlsIdentity() {
        val url="http://h/opaque";forced().add(url);tune(iptv(channel(url)));val logs=org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").map {it.msg}
        assertTrue(logs.any {it.contains("Cinema") && it.contains("live=true") && it.contains("hls-forced")})
    }
    @Test fun threeStrictUrlsAlsoKeepTheWholeSessionStrict() {
        strict().addAll(listOf("a","b","c"));tune();assertTrue(field("iptvStrictTsActive") as Boolean)
    }
    @Test fun initialTuneConstructsTheBorrowedTeeEvenWhenNoRecordingIsActive() {
        val deferred=field("iptvRecordingController\$delegate") as Lazy<*>;assertFalse(deferred.isInitialized());tune();assertTrue(deferred.isInitialized())
    }
    @Test fun noTrialUrlDoesNotClearUnpairedTrialCounters() {
        set("iptvTwinTrialLastFrames",123);tune();assertEquals(123,field("iptvTwinTrialLastFrames"))
    }
    @Test fun noParkedOriginalDoesNotClearAnUnpairedParkedTwin() {
        set("iptvTwinTrialRestoreTwin",twin);tune();assertEquals(twin,field("iptvTwinTrialRestoreTwin"))
    }
}
