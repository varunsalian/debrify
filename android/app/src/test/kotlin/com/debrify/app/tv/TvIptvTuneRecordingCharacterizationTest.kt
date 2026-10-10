package com.debrify.app.tv

import android.content.pm.ProviderInfo
import androidx.appcompat.widget.AppCompatButton
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowContentResolver
import org.robolectric.shadows.ShadowToast
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[29])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvTuneRecordingCharacterizationTest : TvPhase17OriginalTest() {
    private fun recording(url: String): Pair<IptvRecordingController,TvRecordingMediaStoreProvider> {
        activity.getSharedPreferences("FlutterSharedPreferences",0).edit().putBoolean("flutter.recording_engine_enabled",false).commit()
        val provider=TvRecordingMediaStoreProvider().also {
            it.file=File(activity.cacheDir,"p17.ts");it.attachInfo(activity,ProviderInfo().apply {authority="media"});ShadowContentResolver.registerProviderInternal("media",it)
        }
        val tee=invoke("getIptvRecordingController") as IptvRecordingController
        assertTrue(tee.start(url,"p17.ts","video/mp2t"));tee.write(byteArrayOf(1,2,3),0,3)
        set("iptvRecordButton",AppCompatButton(activity));set("currentIptvStreamUrl",url);return tee to provider
    }
    @Test fun changedUrlPublishesTeeBeforeAnyHeaderOrStreamIdentityChanges() {
        val old="http://h/old.ts";iptv(channel(old));val (tee,provider)=recording(old);set("currentIptvHttpHeaders",mapOf("Old" to "old"))
        provider.beforePublish={assertEquals(old,field("currentIptvStreamUrl"));assertEquals(mapOf("Old" to "old"),field("currentIptvHttpHeaders"));assertTrue(probe.events.isEmpty())}
        tune(iptv(channel("http://h/new.ts")));assertFalse(tee.isActive);assertEquals(1,provider.publications.size);assertArrayEquals(byteArrayOf(1,2,3),provider.file.readBytes())
    }
    @Test fun sameUrlOrdinaryReplacementLeavesTheTeeActive() {
        val url="http://h/live.ts";iptv(channel(url));val (tee,provider)=recording(url);tune(iptv(channel(url)));assertTrue(tee.isActive);assertTrue(provider.publications.isEmpty())
    }
    @Test fun sameUrlMachineRetuneFinalizesAndRefreshesBeforePrepare() {
        val url="http://h/live.ts";iptv(channel(url));val (tee,provider)=recording(url)
        val writes=mutableListOf<Boolean>()
        val button=object : AppCompatButton(activity) {
            var observing=false
            override fun setEnabled(enabled: Boolean) {if(observing)writes.add(enabled);super.setEnabled(enabled)}
        }
        set("iptvRecordButton",button);button.observing=true
        probe.onEvent={if(it.startsWith("media:")){assertFalse(tee.isActive);assertEquals(1,provider.publications.size);assertEquals("Record",button.text.toString());assertEquals(listOf(true,true),writes)}}
        retune("ended",1);assertFalse(tee.isActive);assertEquals(1,provider.publications.size);assertEquals(listOf(true,true,true),writes)
    }
    @Test fun sniffFailureAbortsUnusableTeeAndShowsTheExactHlsToastBeforeRetuning() {
        val url="http://h/no-extension";iptv(channel(url));val (tee,provider)=recording(url)
        probe.onEvent={if(it.startsWith("media:")){assertFalse(tee.isActive);assertTrue(provider.publications.isEmpty());assertEquals("Recording stopped — this channel is HLS",ShadowToast.getTextOfLatestToast())}}
        deliver(sniff());assertTrue(forced().contains(url));assertFalse(tee.isActive);assertFalse((field("iptvRecordButton") as AppCompatButton).isEnabled)
    }
}
