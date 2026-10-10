package com.debrify.app.tv

import android.view.View
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

/** Retained controllers reach the tune state through their real Activity Hosts. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvTuneCallerCharacterizationTest : TvPhase17OriginalTest() {
    @Test fun catchupReplyUsesTunePipelineWithArchiveFlagsAndCurrentHeaders() {
        val entry=iptv(channel(original)); catchup(entry,programme(),true)
        val archive="http://h/archive.ts"
        messenger.success(mapOf("url" to archive));idle();quiet()
        assertEquals(listOf("media:$archive"),tuning())
        assertEquals(archive,field("currentIptvStreamUrl"))
        assertSame(entry.httpHeaders,field("currentIptvHttpHeaders"))
        assertEquals(true,field("iptvStartOverActive"))
        assertEquals(false,field("iptvStartOverLoading"))
        assertEquals("Go Live",button().text.toString())
    }

    @Test fun channelStartReadsSessionPreferredTwinThenUsesTunePipeline() {
        val entry=iptv(channel(original)); pref()[original]=twin
        invoke("beginIptvPlayback",entry);quiet()
        assertEquals(listOf("media:$twin"),tuning())
        assertEquals(twin,field("currentIptvStreamUrl"))
        assertSame(entry.httpHeaders,field("currentIptvHttpHeaders"))
    }

    @Test fun asynchronousChannelStartClearsOutgoingTuneIdentityBeforeStop() {
        val entry=iptv(channel("stremio-tv://p17/channel"));set("currentIptvStreamUrl",original)
        probe.onEvent={ if(it=="stop") assertNull("stale outgoing URL must not pass a late error guard",field("currentIptvStreamUrl")) }
        invoke("beginIptvPlayback",entry);quiet()
        assertEquals(listOf("stop"),probe.events)
        assertNull(field("currentIptvStreamUrl"))
        assertEquals(1,requests("requestIptvStreamUrls").size)
    }

    @Test @Config(sdk=[29]) fun recordingRefreshReReadsTuneUrlAndForcedHlsSetAtEachInvocation() {
        activity.getSharedPreferences("FlutterSharedPreferences",0).edit().putBoolean("flutter.recording_engine_enabled",false).commit()
        val record=androidx.appcompat.widget.AppCompatButton(activity);set("iptvRecordButton",record)
        val url="http://h/extensionless";iptv(channel(url));set("currentIptvStreamUrl",url)
        invoke("updateRecordButtonState");assertTrue(record.isEnabled);assertEquals(View.VISIBLE,record.visibility)
        forced().add(url);invoke("updateRecordButtonState");assertFalse(record.isEnabled)
        forced().clear();set("currentIptvStreamUrl",null);invoke("updateRecordButtonState");assertFalse(record.isEnabled)
        set("currentIptvStreamUrl",url);invoke("updateRecordButtonState");assertTrue(record.isEnabled)
    }
}
