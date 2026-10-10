package com.debrify.app.tv

import android.net.Uri
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.text.Cue
import androidx.media3.common.text.CueGroup
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.profiles.NativePlayerPreferences
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvMediaPipelineConfigurationTest : TvPhase19PipelineTest() {
    private fun preferences(vararg pairs: Pair<String, Any>) {
        activity.intent.putExtra(NativePlayerPreferences.EXTRA, JSONObject().put("committed", false)
            .put("values", JSONObject(mapOf(*pairs))).toString())
        set("playerPreferences", NativePlayerPreferences.fromIntent(activity, activity.intent))
    }
    private fun params() = (field("trackSelector") as DefaultTrackSelector).parameters
    private fun http(iptv: Boolean): Any {
        val source = sources(buildPipeline(iptv))
        val vod = if (iptv) upstream(upstream(source)) else source
        val transport = required(upstream(vod), "baseDataSourceFactory")
        return if (iptv) transport else required(transport, "standardFactory")
    }
    @Test fun audioDefaultPreferenceIsInstalled() {
        buildPipeline()
        val expected = com.debrify.app.util.LanguageMapper.getLanguageVariantsForExoPlayer("en")
        assertEquals("preferred audio languages", if (expected.isEmpty()) listOf("zz-custom") else expected.map { androidx.media3.common.util.Util.normalizeLanguageCode(it) }, params().preferredAudioLanguages.toList())
    }

    @Test fun audioFrenchPreferenceIsInstalled() {
        preferences("player_default_audio_language" to "fr")
        buildPipeline()
        val expected = com.debrify.app.util.LanguageMapper.getLanguageVariantsForExoPlayer("fr")
        assertEquals("preferred audio languages", if (expected.isEmpty()) listOf("zz-custom") else expected.map { androidx.media3.common.util.Util.normalizeLanguageCode(it) }, params().preferredAudioLanguages.toList())
    }

    @Test fun audioUnknownPreferenceIsInstalled() {
        preferences("player_default_audio_language" to "zz-custom")
        buildPipeline()
        val expected = com.debrify.app.util.LanguageMapper.getLanguageVariantsForExoPlayer("zz-custom")
        assertEquals("preferred audio languages", if (expected.isEmpty()) listOf("zz-custom") else expected.map { androidx.media3.common.util.Util.normalizeLanguageCode(it) }, params().preferredAudioLanguages.toList())
    }

    @Test fun textDefaultPreferenceIsInstalled() {
        buildPipeline()
        assertEquals("preferred text languages", listOf("en", "en", "english", "en-us", "en-gb", "en-au", "en-ca", "en-nz", "en-ie", "en-za"), params().preferredTextLanguages.toList())
        assertEquals("text disable flag", false, params().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun textFrenchPreferenceIsInstalled() {
        preferences("player_default_subtitle_language" to "fr")
        buildPipeline()
        assertEquals("preferred text languages", listOf("fr", "fr", "fr", "french", "français", "francais", "fr-fr", "fr-ca", "fr-be", "fr-ch"), params().preferredTextLanguages.toList())
        assertEquals("text disable flag", false, params().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun textUnknownPreferenceIsInstalled() {
        preferences("player_default_subtitle_language" to "zz-custom")
        buildPipeline()
        assertEquals("preferred text languages", listOf("zz-custom"), params().preferredTextLanguages.toList())
        assertEquals("text disable flag", false, params().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun textOffPreferenceIsInstalled() {
        preferences("player_default_subtitle_language" to "off")
        buildPipeline()
        assertEquals("preferred text languages", listOf(""), params().preferredTextLanguages.toList())
        assertEquals("text disable flag", true, params().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun textForeignStartsDisabled() {
        preferences("subtitle_only_foreign_audio" to true)
        buildPipeline()
        assertTrue("initial text selection disabled", params().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun textForcedStartsDisabled() {
        preferences("subtitle_forced_only" to true)
        buildPipeline()
        assertTrue("initial text selection disabled", params().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun textRegionalStartsDisabled() {
        preferences("player_default_subtitle_language" to "pT-bR")
        buildPipeline()
        assertTrue("initial text selection disabled", params().disabledTrackTypes.contains(C.TRACK_TYPE_TEXT))
    }

    @Test fun baseTrackAndIptvAdaptationParameters() {
        buildPipeline()
        assertEquals(listOf("audio/opus"), params().preferredAudioMimeTypes.toList())
        assertEquals(C.SELECTION_FLAG_DEFAULT, params().ignoredTextSelectionFlags)
        assertTrue(params().allowInvalidateSelectionsOnRendererCapabilitiesChange)
        assertTrue(params().allowVideoNonSeamlessAdaptiveness)
        buildPipeline(true)
        assertFalse("live video never non-seamlessly adapts", params().allowVideoNonSeamlessAdaptiveness)
    }

    @Test fun vodStandardTimeout() {
        set("networkPatience", "standard")
        val installed = http(false)
        assertEquals("connect timeout", 15000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 15000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun vodExtendedTimeout() {
        set("networkPatience", "extended")
        val installed = http(false)
        assertEquals("connect timeout", 30000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 30000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun vodPatientTimeout() {
        set("networkPatience", "patient")
        val installed = http(false)
        assertEquals("connect timeout", 60000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 60000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun vodOtherTimeout() {
        set("networkPatience", "other")
        val installed = http(false)
        assertEquals("connect timeout", 15000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 15000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun iptvStandardTimeout() {
        set("networkPatience", "standard")
        val installed = http(true)
        assertEquals("connect timeout", 15000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 15000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun iptvExtendedTimeout() {
        set("networkPatience", "extended")
        val installed = http(true)
        assertEquals("connect timeout", 15000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 15000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun iptvPatientTimeout() {
        set("networkPatience", "patient")
        val installed = http(true)
        assertEquals("connect timeout", 15000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 15000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun iptvOtherTimeout() {
        set("networkPatience", "other")
        val installed = http(true)
        assertEquals("connect timeout", 15000, required(installed, "connectTimeoutMs"))
        assertEquals("read timeout", 15000, required(installed, "readTimeoutMs"))
        assertEquals(true, required(installed, "allowCrossProtocolRedirects"))
        assertNull("UA does not clobber request headers", read(installed, "userAgent"))
        val properties = required(installed, "defaultRequestProperties") as androidx.media3.datasource.HttpDataSource.RequestProperties
        assertEquals("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", properties.snapshot["User-Agent"])
    }

    @Test fun bufferQuarterReadBack() {
        heap(256); set("networkBuffer", "large"); buildPipeline()
        val control = loadControl()
        assertEquals("min buffer", 120000000L, required(control, "minBufferUs"))
        assertEquals("max buffer", 120000000L, required(control, "maxBufferUs"))
        assertEquals("byte guard", 67108864, required(control, "targetBufferBytesOverwrite"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS * 1000L, required(control, "bufferForPlaybackAfterRebufferUs"))
    }

    @Test fun bufferLargeCapReadBack() {
        heap(1024); set("networkBuffer", "large"); buildPipeline()
        val control = loadControl()
        assertEquals("min buffer", 120000000L, required(control, "minBufferUs"))
        assertEquals("max buffer", 120000000L, required(control, "maxBufferUs"))
        assertEquals("byte guard", 100663296, required(control, "targetBufferBytesOverwrite"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS * 1000L, required(control, "bufferForPlaybackAfterRebufferUs"))
    }

    @Test fun bufferHugeQuarterReadBack() {
        heap(256); set("networkBuffer", "huge"); buildPipeline()
        val control = loadControl()
        assertEquals("min buffer", 300000000L, required(control, "minBufferUs"))
        assertEquals("max buffer", 300000000L, required(control, "maxBufferUs"))
        assertEquals("byte guard", 67108864, required(control, "targetBufferBytesOverwrite"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS * 1000L, required(control, "bufferForPlaybackAfterRebufferUs"))
    }

    @Test fun bufferUnknownPresetReadBack() {
        heap(1024); set("networkBuffer", "other"); buildPipeline()
        val control = loadControl()
        assertEquals("min buffer", 120000000L, required(control, "minBufferUs"))
        assertEquals("max buffer", 120000000L, required(control, "maxBufferUs"))
        assertEquals("byte guard", 100663296, required(control, "targetBufferBytesOverwrite"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS * 1000L, required(control, "bufferForPlaybackAfterRebufferUs"))
    }

    @Test fun bufferBelowBoundaryReadBack() {
        heap(191); set("networkBuffer", "large"); buildPipeline()
        val control = loadControl()
        assertEquals("min buffer", 50000000L, required(control, "minBufferUs"))
        assertEquals("max buffer", 50000000L, required(control, "maxBufferUs"))
        assertEquals("byte guard", -1, required(control, "targetBufferBytesOverwrite"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS * 1000L, required(control, "bufferForPlaybackAfterRebufferUs"))
    }

    @Test fun bufferStandardReadBack() {
        heap(1024); set("networkBuffer", "standard"); buildPipeline()
        val control = loadControl()
        assertEquals("min buffer", 50000000L, required(control, "minBufferUs"))
        assertEquals("max buffer", 50000000L, required(control, "maxBufferUs"))
        assertEquals("byte guard", -1, required(control, "targetBufferBytesOverwrite"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals(DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS * 1000L, required(control, "bufferForPlaybackAfterRebufferUs"))
    }

    @Test fun mergedBothBufferGuard() {
        val model = movie()
        model.items.add(p2Item("merged").copy(index = 1, hdVideoUrl = "https://v", audioUrl = "https://a"))
        buildPipeline()
        val control = loadControl()
        assertEquals("merge startup threshold", 1_000_000L, required(control, "bufferForPlaybackUs"))
        assertEquals(15_000_000L, required(control, "minBufferUs"))
        assertEquals(50_000_000L, required(control, "maxBufferUs"))
        assertEquals(2_000_000L, required(control, "bufferForPlaybackAfterRebufferUs"))
        assertEquals(true, required(control, "prioritizeTimeOverSizeThresholds"))
    }

    @Test fun mergedNoVideoBufferGuard() {
        val model = movie()
        model.items.add(p2Item("merged").copy(index = 1, hdVideoUrl = null, audioUrl = "https://a"))
        buildPipeline()
        val control = loadControl()
        assertEquals("merge startup threshold", DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals("single-track input keeps stock minimum", 50_000_000L, required(control, "minBufferUs"))
        assertEquals("single-track input keeps stock byte priority", false, required(control, "prioritizeTimeOverSizeThresholds"))
    }

    @Test fun mergedEmptyVideoBufferGuard() {
        val model = movie()
        model.items.add(p2Item("merged").copy(index = 1, hdVideoUrl = "", audioUrl = "https://a"))
        buildPipeline()
        val control = loadControl()
        assertEquals("merge startup threshold", DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals("single-track input keeps stock minimum", 50_000_000L, required(control, "minBufferUs"))
        assertEquals("single-track input keeps stock byte priority", false, required(control, "prioritizeTimeOverSizeThresholds"))
    }

    @Test fun mergedNoAudioBufferGuard() {
        val model = movie()
        model.items.add(p2Item("merged").copy(index = 1, hdVideoUrl = "https://v", audioUrl = null))
        buildPipeline()
        val control = loadControl()
        assertEquals("merge startup threshold", DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals("single-track input keeps stock minimum", 50_000_000L, required(control, "minBufferUs"))
        assertEquals("single-track input keeps stock byte priority", false, required(control, "prioritizeTimeOverSizeThresholds"))
    }

    @Test fun mergedEmptyAudioBufferGuard() {
        val model = movie()
        model.items.add(p2Item("merged").copy(index = 1, hdVideoUrl = "https://v", audioUrl = ""))
        buildPipeline()
        val control = loadControl()
        assertEquals("merge startup threshold", DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS * 1000L, required(control, "bufferForPlaybackUs"))
        assertEquals("single-track input keeps stock minimum", 50_000_000L, required(control, "minBufferUs"))
        assertEquals("single-track input keeps stock byte priority", false, required(control, "prioritizeTimeOverSizeThresholds"))
    }

    @Test fun displayMatchOFFIsInstalled() {
        set("displayMatchMode", TvContentDisplayMatchMode.OFF)
        buildPipeline()
        assertEquals("frame rate strategy", C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF, built.videoChangeFrameRateStrategy)
    }

    @Test fun displayMatchFRAME_RATEIsInstalled() {
        set("displayMatchMode", TvContentDisplayMatchMode.FRAME_RATE)
        buildPipeline()
        assertEquals("frame rate strategy", C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS, built.videoChangeFrameRateStrategy)
    }

    @Test fun displayMatchFRAME_RATE_AND_RESOLUTIONIsInstalled() {
        set("displayMatchMode", TvContentDisplayMatchMode.FRAME_RATE_AND_RESOLUTION)
        buildPipeline()
        assertEquals("frame rate strategy", C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS, built.videoChangeFrameRateStrategy)
    }

    @Test fun displayMatchSYSTEMIsInstalled() {
        set("displayMatchMode", TvContentDisplayMatchMode.SYSTEM)
        buildPipeline()
        assertEquals("frame rate strategy", C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS, built.videoChangeFrameRateStrategy)
    }

    @Test fun playbackSpeedAndNativeRoutingAreInstalled() {
        set("playbackSpeedIndex", 3); set("nightModeIndex", 1); buildPipeline()
        val speeds = read(field("displayController")!!, "playbackSpeeds") as Array<*>
        assertEquals("initial speed", speeds[3] as Float, built.playbackParameters.speed, 0f)
        assertTrue((field("nativeAudioRouting") as com.debrify.app.audio.NativeAudioRouting).requiresPcm)
        val native = required(field("offsetRenderersFactory")!!, "delegate")
        val processors = required(native, "processors") as Array<*>
        assertEquals("one user audio processor", 1, processors.size)
        assertSame("fresh tap processor installed", (field("speechTap") as SpeechFeatureTap).processor, processors.single())
    }

    @Test fun subtitleOutputIsCustomAndExternalRenderingOwnsItsCues() {
        buildPipeline()
        val view = field("playerView") as androidx.media3.ui.PlayerView
        assertSame(built, view.player)
        assertEquals(View.GONE, view.subtitleView!!.visibility)
        assertFalse(view.controllerAutoShow)
        val listener = field("subtitleListener") as androidx.media3.common.Player.Listener
        val overlay = field("subtitleOverlay") as androidx.media3.ui.SubtitleView
        val cue = Cue.Builder().setText("player cue").build()
        set("externalSubtitleActive", false); listener.onCues(CueGroup(listOf(cue), 0))
        assertEquals("custom player cue count", 1, (required(overlay, "cues") as List<*>).size)
        assertEquals("player cue", (required(overlay, "cues") as List<*>).let { (it.single() as Cue).text.toString() })
        set("externalSubtitleActive", true); listener.onCues(CueGroup(emptyList(), 0))
        assertEquals("external owner keeps existing cues", 1, (required(overlay, "cues") as List<*>).size)
        assertEquals(false, required(overlay, "applyEmbeddedStyles")); assertEquals(false, required(overlay, "applyEmbeddedFontSizes"))
    }

    @Test fun iptvKeepsContentAndNonIptvDoesNot() {
        buildPipeline(); val view = field("playerView") as androidx.media3.ui.PlayerView
        assertEquals(false, required(view, "keepContentOnPlayerReset"))
        buildPipeline(true); assertEquals(true, required(view, "keepContentOnPlayerReset"))
    }
    @Test fun nativeRoutingReadsEachIndependentPcmReason() {
        val routing = field("nativeAudioRouting") as com.debrify.app.audio.NativeAudioRouting
        set("nightModeIndex", 0); set("systemAudioEffectsEnabled", false); set("playbackSpeedIndex", 2)
        buildPipeline(); assertFalse("stock bypass", routing.requiresPcm)
        set("nightModeIndex", 1); buildPipeline(); assertTrue("night mode needs PCM", routing.requiresPcm)
        set("nightModeIndex", 0); set("systemAudioEffectsEnabled", true); buildPipeline(); assertTrue("effects need PCM", routing.requiresPcm)
        set("systemAudioEffectsEnabled", false); set("playbackSpeedIndex", 3); buildPipeline(); assertTrue("speed needs PCM", routing.requiresPcm)
    }
}
