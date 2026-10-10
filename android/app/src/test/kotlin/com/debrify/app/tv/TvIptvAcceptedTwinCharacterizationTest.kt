package com.debrify.app.tv

import android.net.Uri
import androidx.media3.common.PlaybackException
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvAcceptedTwinCharacterizationTest : TvPhase17OriginalTest() {
    private fun auth()=error(HttpDataSource.InvalidResponseCodeException(403,"status",null,emptyMap(),DataSpec(Uri.parse(twin)),byteArrayOf()))
    private fun restore(e: PlaybackException)=call("restoreAcceptedIptvTwinAfterAuth",arrayOf(PlaybackException::class.java),e)
    private fun seed() { tune(iptv(channel(original)),twin);quiet();probe.events.clear();pref()[original]=twin }
    @Test fun authRestoreTransientLeavesSessionEvidenceUntouched() {
        seed();val before=pref().toMap();assertEquals(false,restore(error()));assertEquals(before,pref());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun authRestoreDecoderLeavesSessionEvidenceUntouched() {
        seed();val before=pref().toMap();assertEquals(false,restore(error(code=PlaybackException.ERROR_CODE_DECODER_INIT_FAILED)));assertEquals(before,pref());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun authRestoreNoCurrentLeavesSessionEvidenceUntouched() {
        seed();set("currentIptvStreamUrl",null);val before=pref().toMap();assertEquals(false,restore(auth()));assertEquals(before,pref());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun authRestoreNoPreferenceLeavesSessionEvidenceUntouched() {
        seed();pref().clear();val before=pref().toMap();assertEquals(false,restore(auth()));assertEquals(before,pref());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun authRestoreOtherValueLeavesSessionEvidenceUntouched() {
        seed();pref()[original]="http://h/other.ts";val before=pref().toMap();assertEquals(false,restore(auth()));assertEquals(before,pref());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun authRestoreNoEntryLeavesSessionEvidenceUntouched() {
        seed();set("iptvChannels",mutableListOf<IptvChannelEntry>());val before=pref().toMap();assertEquals(false,restore(auth()));assertEquals(before,pref());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun authRestoreVodLeavesSessionEvidenceUntouched() {
        seed();iptv(channel(original,live=false));val before=pref().toMap();assertEquals(false,restore(auth()));assertEquals(before,pref());assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
    @Test fun authRestoresOnlyTheFirstMatchingPreferenceAndLogsRevocation() {
        seed();pref()["http://h/second.m3u8"]=twin;val chosen=pref().entries.first().key;probe.onEvent={if(it.startsWith("media:")){assertTrue(field("iptvLiveRetuneInFlight") as Boolean);assertFalse(pref().containsKey(chosen));assertTrue(failed().contains(chosen))}};assertEquals(true,restore(auth()));assertEquals(chosen,field("currentIptvStreamUrl"));assertEquals(1,pref().size);assertFalse(field("iptvLiveRetuneInFlight") as Boolean);assertTrue(org.robolectric.shadows.ShadowLog.getLogsForTag("IptvDiag").any {it.msg.contains("revoked")})
    }
    @Test fun authRestoresFlagWhenPlayerThrowsAfterPreferenceRevocation() {
        seed();probe.onEvent={if(it=="prepare")throw IllegalStateException("fixture")};try {restore(auth());fail("expected fixture throw")} catch(e: IllegalStateException){assertEquals("fixture",e.message)};assertFalse(field("iptvLiveRetuneInFlight") as Boolean);assertTrue(failed().contains(original));assertFalse(pref().containsKey(original))
    }
    @Test fun acceptedTwinAuthRestoreRetainsTheOriginalFinishingQuirk() {
        seed();activity.finish();assertEquals(true,restore(auth()));assertEquals(original,field("currentIptvStreamUrl"));assertTrue(failed().contains(original))
    }
    @Test fun authWithOutOfWindowIndexCannotRestoreTheFirstEntry() {
        seed();set("currentIptvIndex",1);assertEquals(false,restore(auth()));assertEquals(twin,pref()[original]);assertTrue(failed().isEmpty());assertTrue(tuning().isEmpty())
    }
}
