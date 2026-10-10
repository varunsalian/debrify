package com.debrify.app.tv

import android.media.MediaFormat
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.MediaCodecInfoBuilder
import org.robolectric.shadows.MediaCodecInfoBuilder.CodecCapabilitiesBuilder
import org.robolectric.shadows.ShadowMediaCodecList

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvMediaPipelineCodecTest : TvPhase5OriginalTest() {
    private fun clearCache() = (MediaCodecUtil::class.java.getDeclaredField("decoderInfosCache").apply { isAccessible = true }.get(null) as MutableMap<*, *>).clear()
    @Before fun seedCodecs() { ShadowMediaCodecList.reset(); clearCache(); codec("vendor.hardware", false); codec("c2.android.software", true) }
    @After fun clearCodecs() { ShadowMediaCodecList.reset(); clearCache() }
    private fun codec(name: String, software: Boolean) {
        val video = CodecCapabilitiesBuilder.newBuilder().setMediaFormat(MediaFormat.createVideoFormat("video/avc", 1280, 720)).setColorFormats(intArrayOf(android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)).setProfileLevels(emptyArray()).build()
        val audio = CodecCapabilitiesBuilder.newBuilder().setMediaFormat(MediaFormat.createAudioFormat("audio/mp4a-latm", 44100, 2)).setProfileLevels(emptyArray()).build()
        ShadowMediaCodecList.addCodec(MediaCodecInfoBuilder.newBuilder().setName(name).setIsSoftwareOnly(software)
            .setIsHardwareAccelerated(!software).setCapabilities(video, audio).build())
    }
    private fun names(iptv: Boolean, mode: String, mime: String = "video/avc", secure: Boolean = false, tunnel: Boolean = false): List<String> {
        set("isIptvMode", iptv); set("iptvDecoderMode", mode)
        val selector = call("iptvMediaCodecSelector", emptyArray()) as MediaCodecSelector
        return selector.getDecoderInfos(mime, secure, tunnel).map { it.name }
    }
    @Test fun softwarePreferencePromotesSoftwareAndKeepsHardwareFallback() {
        assertEquals(listOf("c2.android.software", "vendor.hardware"), names(true, "software"))
    }
    @Test fun hardwarePreferenceKeepsHardwareThenSoftware() {
        assertEquals(listOf("vendor.hardware", "c2.android.software"), names(true, "hardware"))
    }
    @Test fun autoNonIptvAndAudioKeepPlatformOrder() {
        val video = MediaCodecSelector.DEFAULT.getDecoderInfos("video/avc", false, false).map { it.name }
        assertEquals(video, names(true, "auto")); assertEquals(video, names(false, "software"))
        val audio = MediaCodecSelector.DEFAULT.getDecoderInfos("audio/mp4a-latm", false, false).map { it.name }
        assertEquals(audio, names(true, "software", "audio/mp4a-latm"))
    }
    @Test fun absentPreferredClassKeepsAllDecoders() {
        ShadowMediaCodecList.reset(); clearCache(); codec("vendor.hardware", false)
        assertEquals(listOf("vendor.hardware"), names(true, "software"))
        val selected = call("iptvMediaCodecSelector", emptyArray()) as MediaCodecSelector
        assertSame("absent preferred class returns the cached platform list",
            MediaCodecSelector.DEFAULT.getDecoderInfos("video/avc", false, false), selected.getDecoderInfos("video/avc", false, false))
    }
    @Test fun secureAndTunnelingRequirementsAreForwarded() {
        assertTrue(names(true, "software", secure = true).isEmpty())
        assertTrue(names(true, "software", tunnel = true).isEmpty())
    }
}
