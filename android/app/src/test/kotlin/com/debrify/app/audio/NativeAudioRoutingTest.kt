package com.debrify.app.audio

import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.RendererCapabilities
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer
import androidx.media3.exoplayer.mediacodec.MediaCodecRenderer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.AudioCapabilities
import androidx.media3.exoplayer.audio.DefaultAudioSink
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

    @Test fun variableSpeedBlocksPassthroughAndOffloadButKeepsPcm() {
        for (speed in listOf(0.5f, 0.75f, 1.25f, 1.5f, 2f)) {
            val routing = NativeAudioRouting()
            assertTrue(routing.update(false, false, speed))
            val sink = EffectsAwareAudioSink(sink(), routing)
            assertPcmOnly(sink)
            assertTrue(routing.update(false, false, 1f))
            encodedMimes.forEach { assertTrue(sink.supportsFormat(format(it))) }
            assertEquals(offload, sink.getFormatOffloadSupport(format(MimeTypes.AUDIO_AC3)))
        }
    }

    @Test fun returningToNormalSpeedKeepsEnabledEffectsOnPcm() {
        for ((night, system) in listOf(true to false, false to true, true to true)) {
            val routing = NativeAudioRouting()
            routing.update(night, system, 1.5f)
            assertFalse(routing.update(night, system, 1f))
            assertPcmOnly(EffectsAwareAudioSink(sink(), routing))
        }
    }

    @Test fun effectAndSpeedChangesWithinPcmDoNotRestartAudio() {
        val routing = NativeAudioRouting()
        routing.update(true, false, 1.5f)
        assertFalse(routing.update(false, false, 1.5f))
        assertFalse(routing.update(false, false, 0.5f))
        assertPcmOnly(EffectsAwareAudioSink(sink(), routing))
    }

    @Suppress("DEPRECATION")
    @Test fun realMedia3SinkKeepsRequestedSpeedAfterRoutingToPcm() {
        val routing = NativeAudioRouting()
        val delegate = DefaultAudioSink.Builder()
            .setAudioCapabilities(AudioCapabilities(intArrayOf(C.ENCODING_PCM_16BIT, C.ENCODING_AC3), 8))
            .setEnableAudioTrackPlaybackParams(false)
            .build()
        val sink = EffectsAwareAudioSink(delegate, routing)
        // Exercise Media3's real speed application without requiring a hardware
        // AudioTrack. handleBuffer calls this method after a route/speed change.
        val applySpeed = DefaultAudioSink::class.java.getDeclaredMethod(
            "applyAudioProcessorPlaybackParametersAndSkipSilence", java.lang.Long.TYPE,
        ).apply { isAccessible = true }
        try {
            for (speed in listOf(1f, 1.5f, 2f, 0.5f, 1f)) {
                routing.update(false, false, speed)
                val input = if (sink.supportsFormat(format(MimeTypes.AUDIO_AC3))) {
                    format(MimeTypes.AUDIO_AC3)
                } else pcm
                sink.configure(input, 16384, null)
                sink.setPlaybackParameters(PlaybackParameters(speed))
                applySpeed.invoke(delegate, 0L)
                // Before the fix, encoded output accepted the request but reset
                // every non-1x speed to 1x when this Media3 method ran.
                assertEquals("requested=$speed input=${input.sampleMimeType}", speed, sink.playbackParameters.speed, 0f)
                sink.reset()
            }
        } finally {
            sink.release()
        }
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
        for ((night, system, speed) in listOf(Triple(true, false, 1f), Triple(false, false, 1.5f))) {
            routing.update(night, system, speed)
            encodedMimes.forEach {
                // Without a platform decoder this renderer must now yield to
                // FFmpeg, rather than bypass the effect or requested speed.
                assertEquals(it, C.FORMAT_UNSUPPORTED_SUBTYPE, RendererCapabilities.getFormatSupport(renderer.supportsFormat(format(it))))
            }
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
        var speed = 1f
        var preparedSpeed: Float? = null
        var onStateChanged: (() -> Unit)? = null
        val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, args ->
            when (method.name) {
                "getPlaybackState" -> state
                "getMediaItemCount" -> items
                "getPlayWhenReady" -> !paused
                "getCurrentPosition" -> position
                "getCurrentMediaItemIndex" -> index
                "getPlaybackParameters" -> PlaybackParameters(speed)
                "setPlaybackSpeed" -> { speed = args!![0] as Float; calls.add("speed:$speed"); null }
                "stop" -> { calls.add("stop"); state = Player.STATE_IDLE; onStateChanged?.invoke(); null }
                "prepare" -> { calls.add("prepare"); preparedSpeed = speed; state = Player.STATE_BUFFERING; onStateChanged?.invoke(); null }
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

    @Test fun routeSwitchSetsSpeedBetweenStopAndPrepareWithoutChangingSessionState() {
        for (state in listOf(Player.STATE_READY, Player.STATE_BUFFERING)) {
            for (paused in listOf(true, false)) {
                val playback = Playback(state, paused)
                for (speed in listOf(1.5f, 1f, 0.5f, 1f)) {
                    playback.calls.clear()
                    assertTrue(NativeAudioRouting().reprepare(playback.player, speed))
                    assertEquals(listOf("stop", "speed:$speed", "prepare"), playback.calls)
                    assertEquals(speed, playback.preparedSpeed)
                    assertEquals(speed, playback.player.playbackParameters.speed, 0f)
                    assertEquals(!paused, playback.player.playWhenReady)
                    assertEquals(123456L, playback.player.currentPosition)
                    assertEquals(1, playback.player.currentMediaItemIndex)
                }
            }
        }
    }

    @Test fun speedChangesOnIdleAndEmptyPlayersDoNotStartPlayback() {
        for (playback in listOf(
            Playback(Player.STATE_IDLE, true),
            Playback(Player.STATE_READY, true, 0),
        )) {
            assertFalse(NativeAudioRouting().reprepare(playback.player, 1.5f))
            assertEquals(listOf("speed:1.5"), playback.calls)
            assertEquals(1.5f, playback.player.playbackParameters.speed, 0f)
        }
        assertFalse(NativeAudioRouting().reprepare(null, 1.5f))
    }

    @Test fun endedRouteChangesWaitForReplayAndUseTheLatestSpeedExactlyOnce() {
        for (paused in listOf(true, false)) {
            for (resumeState in listOf(Player.STATE_BUFFERING, Player.STATE_READY)) {
                for (latestSpeed in listOf(2f, 1f)) {
                    val routing = NativeAudioRouting()
                    val playback = Playback(Player.STATE_ENDED, paused)
                    var requestedSpeed = 1.5f
                    playback.onStateChanged = {
                        routing.reprepareIfPending(playback.player, requestedSpeed)
                    }
                    routing.setPlaybackSpeed(playback.player, requestedSpeed,
                        routing.update(false, false, requestedSpeed))
                    requestedSpeed = latestSpeed
                    routing.setPlaybackSpeed(playback.player, requestedSpeed,
                        routing.update(false, false, requestedSpeed))
                    assertFalse(routing.reprepareIfPending(playback.player, requestedSpeed))
                    assertEquals(Player.STATE_ENDED, playback.state)
                    assertTrue("An ended player must not start or touch its old sink", playback.calls.isEmpty())

                    playback.state = resumeState
                    assertTrue(routing.reprepareIfPending(playback.player, requestedSpeed))
                    assertEquals(listOf("stop", "speed:$latestSpeed", "prepare"), playback.calls)
                    assertEquals(latestSpeed, playback.player.playbackParameters.speed, 0f)
                    assertEquals(latestSpeed != 1f, routing.requiresPcm)
                    assertEquals(!paused, playback.player.playWhenReady)
                    assertEquals(123456L, playback.player.currentPosition)
                    assertEquals(1, playback.player.currentMediaItemIndex)
                    assertFalse(routing.reprepareIfPending(playback.player, requestedSpeed))
                }
            }
        }
    }

    @Test fun replacementPlayerDoesNotInheritAnEndedPlayersPendingRestart() {
        val routing = NativeAudioRouting()
        val ended = Playback(Player.STATE_ENDED, true)
        routing.reprepare(ended.player, 1.5f)
        val replacement = Playback(Player.STATE_BUFFERING, true)
        assertFalse(routing.reprepareIfPending(replacement.player, 1.5f))
        assertTrue(replacement.calls.isEmpty())
        ended.state = Player.STATE_READY
        assertFalse(routing.reprepareIfPending(ended.player, 1.5f))
        assertTrue(ended.calls.isEmpty())
    }

    @Suppress("DEPRECATION")
    @Test fun endedPassthroughRendererIsResetBeforeApplyingReplaySpeed() {
        val routing = NativeAudioRouting()
        val delegate = DefaultAudioSink.Builder()
            .setAudioCapabilities(AudioCapabilities(intArrayOf(C.ENCODING_PCM_16BIT, C.ENCODING_AC3), 8))
            .setEnableAudioTrackPlaybackParams(false).build()
        val sink = EffectsAwareAudioSink(delegate, routing)
        val renderer = MediaCodecAudioRenderer(
            RuntimeEnvironment.getApplication(), MediaCodecSelector { _, _, _ -> emptyList() },
            Handler(Looper.getMainLooper()), object : AudioRendererEventListener {}, sink,
        )
        val ac3 = format(MimeTypes.AUDIO_AC3)
        val bypass = MediaCodecRenderer::class.java.getDeclaredField("bypassEnabled")
            .apply { isAccessible = true }
        val applySpeed = DefaultAudioSink::class.java.getDeclaredMethod(
            "applyAudioProcessorPlaybackParametersAndSkipSilence", java.lang.Long.TYPE,
        ).apply { isAccessible = true }
        // Start with the real renderer/sink state retained after encoded playback.
        MediaCodecRenderer::class.java.getDeclaredMethod("initBypass", Format::class.java)
            .apply { isAccessible = true }.invoke(renderer, ac3)
        sink.configure(ac3, 16384, null)
        var state = Player.STATE_ENDED
        val player = Proxy.newProxyInstance(Player::class.java.classLoader, arrayOf(Player::class.java)) { _, method, args ->
            when (method.name) {
                "getMediaItemCount" -> 1
                "getPlaybackState" -> state
                "setPlaybackSpeed" -> { renderer.setPlaybackParameters(PlaybackParameters(args!![0] as Float)); null }
                "stop" -> { renderer.reset(); sink.reset(); state = Player.STATE_IDLE; null }
                "prepare" -> {
                    assertFalse("The old encoded renderer must be reset", bypass.getBoolean(renderer))
                    sink.configure(if (sink.supportsFormat(ac3)) ac3 else pcm, 16384, null)
                    applySpeed.invoke(delegate, 0L)
                    state = Player.STATE_BUFFERING
                    null
                }
                else -> error("Unexpected player call ${method.name}")
            }
        } as Player
        try {
            routing.setPlaybackSpeed(player, 1.5f, routing.update(false, false, 1.5f))
            assertEquals(Player.STATE_ENDED, state)
            assertEquals(1f, sink.playbackParameters.speed, 0f)
            // A same-period seek flushes the renderer but leaves bypass enabled.
            MediaCodecAudioRenderer::class.java.getDeclaredMethod(
                "onPositionReset", java.lang.Long.TYPE, java.lang.Boolean.TYPE,
            ).apply { isAccessible = true }.invoke(renderer, 0L, false)
            assertTrue(bypass.getBoolean(renderer))
            state = Player.STATE_BUFFERING
            assertTrue(routing.reprepareIfPending(player, 1.5f))
            assertEquals(1.5f, sink.playbackParameters.speed, 0f)
            assertFalse(routing.reprepareIfPending(player, 1.5f))
        } finally {
            renderer.release()
        }
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
