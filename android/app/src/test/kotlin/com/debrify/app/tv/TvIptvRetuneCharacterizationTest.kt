package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvRetuneCharacterizationTest : TvPhase17OriginalTest() {
    @Test fun strictEnrollmentFirstRungDoesNotAddEvidence() {
        iptv(channel("http://h/a.ts"));set("currentIptvStreamUrl","http://h/a.ts");val source="video-stall";val attempt=1;retune(source,attempt);assertTrue(strict().isEmpty());assertEquals(1,tuning().size)
    }
    @Test fun strictEnrollmentWrongSourceDoesNotAddEvidence() {
        iptv(channel("http://h/a.ts"));set("currentIptvStreamUrl","http://h/a.ts");val source="ended";val attempt=2;retune(source,attempt);assertTrue(strict().isEmpty());assertEquals(1,tuning().size)
    }
    @Test fun strictEnrollmentAlreadyStrictDoesNotAddEvidence() {
        iptv(channel("http://h/a.ts"));set("currentIptvStreamUrl","http://h/a.ts");set("iptvStrictTsActive",true);val source="video-stall";val attempt=2;retune(source,attempt);assertTrue(strict().isEmpty());assertEquals(1,tuning().size)
    }
    @Test fun strictEnrollmentExactSecondRungAddsOneUrlThenASecondEscalatesTheSession() {
        iptv(channel("http://h/a.ts"));set("currentIptvStreamUrl","http://h/a.ts");retune();assertEquals(setOf("http://h/a.ts"),strict());assertTrue(field("iptvStrictTsActive") as Boolean);iptv(channel("http://h/b.ts"));set("currentIptvStreamUrl","http://h/b.ts");set("iptvStrictTsActive",false);retune();assertEquals(2,strict().size);tune(url="http://h/c.ts");assertTrue(field("iptvStrictTsActive") as Boolean)
    }
    @Test fun repeatedStrictEvidenceDoesNotEmitASecondEnrollment() {
        iptv(channel("http://h/a.ts"));set("currentIptvStreamUrl","http://h/a.ts");strict().add("http://h/a.ts");set("iptvStrictTsActive",false);retune();assertEquals(1,strict().size);assertFalse(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("action=strict-ts")})
    }
    @Test fun segmentedStrictRungStartsAReversibleTwinAndNeverEnrollsStrictEvidence() {
        iptv(channel(original));set("currentIptvStreamUrl",original);retune();assertEquals(twin,trial());assertEquals(original,field("iptvTwinTrialOriginalUrl"));assertTrue(strict().isEmpty());assertEquals(listOf("media:$twin"),tuning())
    }
    @Test fun twinDiversionWrongSourceUsesTheOriginalUrl() {
        iptv(channel(original));set("currentIptvStreamUrl",original);val source="ended";val attempt=2;retune(source,attempt);assertEquals(original,field("currentIptvStreamUrl"));assertNull(trial());assertEquals(listOf("media:$original"),tuning())
    }
    @Test fun twinDiversionFirstRungUsesTheOriginalUrl() {
        iptv(channel(original));set("currentIptvStreamUrl",original);val source="video-stall";val attempt=1;retune(source,attempt);assertEquals(original,field("currentIptvStreamUrl"));assertNull(trial());assertEquals(listOf("media:$original"),tuning())
    }
    @Test fun twinDiversionExistingTrialUsesTheOriginalUrl() {
        iptv(channel(original));set("currentIptvStreamUrl",original);set("iptvTwinTrialOriginalUrl","old");val source="video-stall";val attempt=2;retune(source,attempt);assertEquals(original,field("currentIptvStreamUrl"));assertNull(trial());assertEquals(listOf("media:$original"),tuning())
    }
    @Test fun twinDiversionFailedOriginalUsesTheOriginalUrl() {
        iptv(channel(original));set("currentIptvStreamUrl",original);failed().add(original);val source="video-stall";val attempt=2;retune(source,attempt);assertEquals(original,field("currentIptvStreamUrl"));assertNull(trial());assertEquals(listOf("media:$original"),tuning())
    }
    @Test fun twinDiversionForcedTwinUsesTheOriginalUrl() {
        iptv(channel(original));set("currentIptvStreamUrl",original);forced().add(twin);val source="video-stall";val attempt=2;retune(source,attempt);assertEquals(original,field("currentIptvStreamUrl"));assertNull(trial());assertEquals(listOf("media:$original"),tuning())
    }
    @Test fun segmentedUrlWithoutAnXtreamTwinFallsThroughToPlainRetune() {
        val url="http://h/plain.m3u8";iptv(channel(url));set("currentIptvStreamUrl",url);retune();assertNull(trial());assertEquals(url,field("currentIptvStreamUrl"));assertTrue(strict().isEmpty())
    }
    @Test fun retuneNoEntryReturnsWithoutTouchingIdentity() {
        iptv();set("currentIptvStreamUrl","old");set("iptvChannels",mutableListOf<IptvChannelEntry>());retune();assertEquals("old",field("currentIptvStreamUrl"));assertTrue(tuning().isEmpty())
    }
    @Test fun retuneVodReturnsWithoutTouchingIdentity() {
        iptv();set("currentIptvStreamUrl","old");iptv(channel(live=false));retune();assertEquals("old",field("currentIptvStreamUrl"));assertTrue(tuning().isEmpty())
    }
    @Test fun retuneUsesResolvedUrlAndFallsBackToEntryOnlyWhenIdentityIsMissing() {
        val e=iptv(channel("http://h/live.ts"));set("currentIptvStreamUrl","http://h/resolved.ts");retune("ended",1);assertEquals("http://h/resolved.ts",field("currentIptvStreamUrl"));set("currentIptvStreamUrl",null);retune("ended",1);assertEquals(e.url,field("currentIptvStreamUrl"))
    }
    @Test fun retuneExitsStartOverAndBumpsTheOwningTokenBeforeMediaReplacement() {
        val e=iptv(channel("http://h/live.ts"));set("currentIptvStreamUrl","http://h/archive.ts");set("iptvStartOverActive",true);set("iptvStartOverLoading",true);set("iptvStartOverTimelineVisible",true);val token=field("iptvCatchupToken") as Int;probe.onEvent={if(it.startsWith("media:")){assertFalse(field("iptvStartOverActive") as Boolean);assertFalse(field("iptvStartOverLoading") as Boolean);assertFalse(field("iptvStartOverTimelineVisible") as Boolean);assertEquals(token+1,field("iptvCatchupToken"))}};retune("ended",1);assertEquals(e.url,field("currentIptvStreamUrl"));assertFalse(field("iptvLiveRetuneInFlight") as Boolean)
    }
    @Test fun loadingWithoutActiveStartOverStillClearsFlagsButKeepsResolvedUrl() {
        iptv(channel("http://h/live.ts"));set("currentIptvStreamUrl","http://h/resolved.ts");set("iptvStartOverLoading",true);set("iptvStartOverTimelineVisible",true);val token=field("iptvCatchupToken") as Int;retune("ended",1);assertFalse(field("iptvStartOverLoading") as Boolean);assertFalse(field("iptvStartOverTimelineVisible") as Boolean);assertEquals(token+1,field("iptvCatchupToken"));assertEquals("http://h/resolved.ts",field("currentIptvStreamUrl"))
    }
    @Test fun retuneClearsFlagInFinallyEvenWhenPrepareThrows() {
        iptv(channel("http://h/live.ts"));probe.onEvent={if(it=="prepare")throw IllegalStateException("fixture")};try {retune("ended",1);fail("expected fixture throw")} catch(e: IllegalStateException){assertEquals("fixture",e.message)};assertFalse(field("iptvLiveRetuneInFlight") as Boolean)
    }
    @Test fun thirdVideoStallRungStillEnrollsStrictEvidence() {
        tune(iptv(channel("http://h/live.ts")));quiet();retune("video-stall",3);assertEquals(setOf("http://h/live.ts"),strict())
    }
    @Test fun thirdSegmentedStallRungStillTriesTheTwinAndLogsTheDiversion() {
        tune();quiet();retune("video-stall",3);assertEquals(twin,trial());assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("action=twin-ts") && it.msg.contains("trial")})
    }
    @Test fun activeWithoutLoadingStillClearsTheStartOverTimelineAndToken() {
        tune(iptv(channel("http://h/live.ts")));quiet();set("iptvStartOverActive",true);set("iptvStartOverLoading",false);set("iptvStartOverTimelineVisible",true)
        val token=field("iptvCatchupToken") as Int;retune("ended",1);assertFalse(field("iptvStartOverActive") as Boolean);assertFalse(field("iptvStartOverTimelineVisible") as Boolean);assertEquals(token+1,field("iptvCatchupToken"))
    }
    @Test fun outOfWindowCurrentIndexDoesNotRetuneTheFirstEntry() {
        iptv();set("currentIptvIndex",1);retune();assertTrue(tuning().isEmpty());assertNull(field("currentIptvStreamUrl"))
    }
    @Test fun strictEnrollmentLogsTheDecisionBeforeTheNextTuneGeneration() {
        tune(iptv(channel("http://h/live.ts")));quiet();retune("video-stall",2)
        assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("gen=1 ") && it.msg.contains("source=video-stall action=strict-ts")})
    }
    @Test fun leavingStartOverRestylesTheArchiveTimelineBeforeMediaReplacement() {
        val timeline=View(activity).apply {visibility=View.VISIBLE};set("cinemaProgressContainer",timeline)
        tune(iptv(channel("http://h/live.ts")));quiet();set("iptvStartOverActive",true);set("iptvStartOverTimelineVisible",true)
        probe.onEvent={if(it.startsWith("media:"))assertEquals(View.GONE,timeline.visibility)}
        retune("ended",1);assertEquals(View.GONE,timeline.visibility)
    }
}
