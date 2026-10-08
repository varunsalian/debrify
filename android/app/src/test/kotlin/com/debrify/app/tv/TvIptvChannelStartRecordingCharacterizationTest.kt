package com.debrify.app.tv

import android.content.Context
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowContentResolver

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvIptvChannelStartRecordingCharacterizationTest : TvPhase5OriginalTest() {
    @Test fun outgoingTeePublishesBeforeTokenResetUrlClearStopAndResolveEvenWhenResolveIsEmpty() {
        val entry = iptv(channel("stremio-tv://phase5/new"))
        activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putBoolean("flutter.recording_engine_enabled", false).commit()
        val provider = TvRecordingMediaStoreProvider().also {
            it.file = File(activity.cacheDir, "phase5-tee.ts")
            it.attachInfo(activity, android.content.pm.ProviderInfo().apply { authority = "media" })
            ShadowContentResolver.registerProviderInternal("media", it)
        }
        val tee = invoke("getIptvRecordingController") as IptvRecordingController
        assertTrue(tee.start("https://phase5.invalid/old.ts", "fixture.ts", "video/mp2t"))
        tee.write(byteArrayOf(1, 2, 3), 0, 3)
        set("currentIptvStreamUrl", "https://phase5.invalid/old.ts"); set("iptvStremioChannelKey", "old-key")
        val before = field("iptvStremioToken")
        provider.beforePublish = {
            assertEquals("finalize before token reset", before, field("iptvStremioToken"))
            assertEquals("old-key", field("iptvStremioChannelKey"))
            assertEquals("https://phase5.invalid/old.ts", field("currentIptvStreamUrl")); assertTrue(probe.events.isEmpty())
        }
        messenger.onSend = { if (it.call.method == "requestIptvStreamUrls") {
            assertFalse(tee.isActive); assertEquals(1, provider.publications.size)
            assertEquals(listOf("stop"), probe.events)
        } }
        invoke("beginIptvPlayback", entry); resolve()
        assertFalse(tee.isActive); assertEquals(1, provider.publications.size)
        assertArrayEquals(byteArrayOf(1, 2, 3), provider.file.readBytes()); assertTrue(tuning().isEmpty())
    }
}
