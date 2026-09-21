package com.debrify.app.audio

import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.RendererCapabilities
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.video.VideoRendererEventListener
import java.lang.reflect.Proxy
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class NativeAudioRoutingTest {
    private val encodedMimes = listOf(
        MimeTypes.AUDIO_AC3, MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC,
        MimeTypes.AUDIO_DTS, MimeTypes.AUDIO_DTS_HD, MimeTypes.AUDIO_TRUEHD,
    )

    private fun format(mime: String) = Format.Builder().setSampleMimeType(mime)
        .setChannelCount(6).setSampleRate(48000).setPcmEncoding(C.ENCODING_PCM_16BIT).build()

    private val pcm = format(MimeTypes.AUDIO_RAW)
    private val offload = AudioOffloadSupport.Builder().setIsFormatSupported(true).build()

    private fun sink(support: Int = AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY): AudioSink =
        Proxy.newProxyInstance(AudioSink::class.java.classLoader, arrayOf(AudioSink::class.java)) { _, method, _ ->
            when (method.name) {
                "supportsFormat" -> support != AudioSink.SINK_FORMAT_UNSUPPORTED
                "getFormatSupport" -> support
                "getFormatOffloadSupport" -> offload
                "setListener", "release", "reset" -> null
                else -> error("Unexpected sink call ${method.name}")
            }
        } as AudioSink

    @Test fun defaultsAllowEncodedAudio() {
        val routing = NativeAudioRouting()
        val sink = EffectsAwareAudioSink(sink(), routing)
        assertFalse(routing.requiresPcm)
        encodedMimes.forEach {
            assertTrue(it, sink.supportsFormat(format(it)))
            assertEquals(it, AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY, sink.getFormatSupport(format(it)))
        }
    }

    @Test fun bothNativePlayersEnableCapabilityRecovery() {
        // Wiring contract: a correct sink alone cannot trigger reselection if
        // either activity leaves Media3's opt-in recovery flag at its default.
        val appDir = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
            .flatMap { sequenceOf(it, File(it, "app"), File(it, "android/app")) }
            .first { File(it, "src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt").isFile }
        for (relative in listOf(
            "src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt",
            "src/main/java/com/debrify/app/tv/TorboxTvPlayerActivity.java",
        )) {
            val source = File(appDir, relative).readText()
            assertTrue(relative, source.contains(".setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)"))
            assertFalse(relative, source.contains(".setAllowInvalidateSelectionsOnRendererCapabilitiesChange(false)"))
        }
    }

    @Test fun restoredHdmiCapabilitiesRespectEffectsPolicy() {
        for ((night, system) in listOf(false to false, true to false, false to true)) {
            var surroundAvailable = true
            val delegate = Proxy.newProxyInstance(
                AudioSink::class.java.classLoader, arrayOf(AudioSink::class.java),
            ) { _, method, args ->
                val supported = (args!![0] as Format).sampleMimeType == MimeTypes.AUDIO_RAW || surroundAvailable
                when (method.name) {
                    "supportsFormat" -> supported
                    "getFormatSupport" -> if (supported) AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY else AudioSink.SINK_FORMAT_UNSUPPORTED
                    else -> error("Unexpected sink call ${method.name}")
                }
            } as AudioSink
            val routing = NativeAudioRouting().apply { update(night, system) }
            val sink = EffectsAwareAudioSink(delegate, routing)
            val ac3 = format(MimeTypes.AUDIO_AC3)
            assertEquals(!night && !system, sink.supportsFormat(ac3))
            surroundAvailable = false
            assertFalse(sink.supportsFormat(ac3))
            assertTrue(sink.supportsFormat(pcm))
            surroundAvailable = true
            assertEquals(!night && !system, sink.supportsFormat(ac3))
            assertEquals(
                if (night || system) AudioSink.SINK_FORMAT_UNSUPPORTED else AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY,
                sink.getFormatSupport(ac3),
            )
        }
    }

    @Test fun neverInventsHardwareSupport() {
        val sink = EffectsAwareAudioSink(sink(AudioSink.SINK_FORMAT_UNSUPPORTED), NativeAudioRouting())
        encodedMimes.forEach {
            assertFalse(sink.supportsFormat(format(it)))
            assertEquals(AudioSink.SINK_FORMAT_UNSUPPORTED, sink.getFormatSupport(format(it)))
        }
    }

    @Test fun nightModeBlocksEncodedButKeepsPcm() {
        val routing = NativeAudioRouting()
        routing.update(true, false)
        assertPcmOnly(EffectsAwareAudioSink(sink(), routing))
    }

    @Test fun systemEffectsAloneRequirePcm() {
        val routing = NativeAudioRouting()
        routing.update(false, true)
        assertPcmOnly(EffectsAwareAudioSink(sink(), routing))
    }

    private fun assertPcmOnly(sink: AudioSink) {
        encodedMimes.forEach {
            assertFalse(it, sink.supportsFormat(format(it)))
            assertEquals(it, AudioSink.SINK_FORMAT_UNSUPPORTED, sink.getFormatSupport(format(it)))
            assertEquals(AudioOffloadSupport.DEFAULT_UNSUPPORTED, sink.getFormatOffloadSupport(format(it)))
        }
        assertTrue(sink.supportsFormat(pcm))
        assertEquals(AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY, sink.getFormatSupport(pcm))
    }

    @Test fun turningNightModeOffDoesNotBypassSystemEffects() {
        val routing = NativeAudioRouting()
        routing.update(true, true)
        assertFalse(routing.update(false, true))
        assertTrue(routing.requiresPcm)
    }

    @Test fun turningAllEffectsOffRestoresRouteCapabilityChecks() {
        val routing = NativeAudioRouting()
        val sink = EffectsAwareAudioSink(sink(), routing)
        routing.update(true, false)
        assertTrue(routing.update(false, false))
        assertTrue(sink.supportsFormat(format(MimeTypes.AUDIO_AC3)))
        assertEquals(offload, sink.getFormatOffloadSupport(format(MimeTypes.AUDIO_AC3)))
    }

    @Test fun gainChangesDoNotRequestRestart() {
        val routing = NativeAudioRouting()
        assertFalse(routing.update(false, false))
        assertTrue(routing.update(true, false))
        assertFalse(routing.update(true, false))
        assertTrue(routing.update(false, false))
    }

    @Test fun retainsPcmTranscodingSupport() {
        val routing = NativeAudioRouting()
        routing.update(true, false)
        val sink = EffectsAwareAudioSink(sink(AudioSink.SINK_FORMAT_SUPPORTED_WITH_TRANSCODING), routing)
        assertEquals(AudioSink.SINK_FORMAT_SUPPORTED_WITH_TRANSCODING, sink.getFormatSupport(pcm))
    }

    @Test fun media3AcceptsEncodedOutputWithoutADecoderButRequiresOneForEffects() {
        val routing = NativeAudioRouting()
        val renderer = MediaCodecAudioRenderer(
            RuntimeEnvironment.getApplication(), MediaCodecSelector { _, _, _ -> emptyList() },
            Handler(Looper.getMainLooper()), object : AudioRendererEventListener {},
            EffectsAwareAudioSink(sink(), routing),
        )
        encodedMimes.forEach {
            assertEquals(it, C.FORMAT_HANDLED, RendererCapabilities.getFormatSupport(renderer.supportsFormat(format(it))))
        }
        routing.update(true, false)
        encodedMimes.forEach {
            // Without a platform decoder this renderer must now yield to the
            // installed FFmpeg decoder, rather than silently bypass the effect.
            assertEquals(it, C.FORMAT_UNSUPPORTED_SUBTYPE, RendererCapabilities.getFormatSupport(renderer.supportsFormat(format(it))))
        }
        routing.update(false, false)
        assertEquals(C.FORMAT_HANDLED, RendererCapabilities.getFormatSupport(renderer.supportsFormat(format(MimeTypes.AUDIO_AC3))))
        renderer.release()
    }

    @Test fun nativeAudioPrecedesFfmpegEvenWhenVideoExtensionsArePreferred() {
        val factory = NativeAudioRenderersFactory(RuntimeEnvironment.getApplication(), NativeAudioRouting())
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
        val renderers = factory.createRenderers(
            Handler(Looper.getMainLooper()), object : VideoRendererEventListener {},
            object : AudioRendererEventListener {}, {}, {},
        )
        val audio = renderers.filter { it.trackType == C.TRACK_TYPE_AUDIO }
        assertEquals("MediaCodecAudioRenderer", audio.first().name)
        assertTrue("Software fallback must remain installed", audio.any { it.name == "FfmpegAudioRenderer" })
        renderers.forEach { it.release() }
    }

    @Test fun explicitExtensionOffRemainsOff() {
        val factory = NativeAudioRenderersFactory(RuntimeEnvironment.getApplication(), NativeAudioRouting())
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF)
        val renderers = factory.createRenderers(
            Handler(Looper.getMainLooper()), object : VideoRendererEventListener {},
            object : AudioRendererEventListener {}, {}, {},
        )
        assertEquals(listOf("MediaCodecAudioRenderer"), renderers.filter { it.trackType == C.TRACK_TYPE_AUDIO }.map { it.name })
        renderers.forEach { it.release() }
    }

    @Test fun videoRendererOrderingIsUnchanged() {
        val context = RuntimeEnvironment.getApplication()
        val factories = listOf(
            DefaultRenderersFactory(context),
            NativeAudioRenderersFactory(context, NativeAudioRouting()),
        )
        val videos = factories.map { factory ->
            val renderers = factory
                .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
                .createRenderers(
                    Handler(Looper.getMainLooper()), object : VideoRendererEventListener {},
                    object : AudioRendererEventListener {}, {}, {},
                )
            val names = renderers.filter { it.trackType == C.TRACK_TYPE_VIDEO }.map { it.name }
            renderers.forEach { it.release() }
            names
        }
        assertTrue(videos.first().isNotEmpty())
        assertEquals(videos.first(), videos.last())
    }

    private class Playback(var state: Int, val paused: Boolean, val items: Int = 2) {
        val calls = mutableListOf<String>()
        val position = 123456L
        val index = 1
        val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, _ ->
            when (method.name) {
                "getPlaybackState" -> state
                "getMediaItemCount" -> items
                "getPlayWhenReady" -> !paused
                "getCurrentPosition" -> position
                "getCurrentMediaItemIndex" -> index
                "stop" -> { calls.add("stop"); state = Player.STATE_IDLE; null }
                "prepare" -> { calls.add("prepare"); state = Player.STATE_BUFFERING; null }
                // Fail on play(), seek(), playlist replacement, track override
                // clearing, or any other accidental mutation during the flip.
                else -> error("Unexpected playback mutation ${method.name}")
            }
        } as Player
    }

    @Test fun liveSwitchPreservesPausedAndPlayingSessions() {
        for (paused in listOf(true, false)) {
            val playback = Playback(Player.STATE_READY, paused)
            assertTrue(NativeAudioRouting().reprepare(playback.player))
            assertEquals(listOf("stop", "prepare"), playback.calls)
            assertEquals(!paused, playback.player.playWhenReady)
            assertEquals(123456L, playback.player.currentPosition)
            assertEquals(1, playback.player.currentMediaItemIndex)
        }
    }

    @Test fun bufferingSessionsCanSwitchWithoutForcingPlay() {
        val playback = Playback(Player.STATE_BUFFERING, true)
        assertTrue(NativeAudioRouting().reprepare(playback.player))
        assertFalse(playback.player.playWhenReady)
    }

    @Test fun idleEndedAndEmptyPlayersAreNotStarted() {
        for (state in listOf(Player.STATE_IDLE, Player.STATE_ENDED)) {
            val playback = Playback(state, true)
            assertFalse(NativeAudioRouting().reprepare(playback.player))
            assertTrue(playback.calls.isEmpty())
        }
        val empty = Playback(Player.STATE_READY, true, 0)
        assertFalse(NativeAudioRouting().reprepare(empty.player))
        assertTrue(empty.calls.isEmpty())
        assertFalse(NativeAudioRouting().reprepare(null))
    }
}
