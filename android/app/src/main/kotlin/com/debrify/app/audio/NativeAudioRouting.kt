package com.debrify.app.audio

import android.content.Context
import android.os.Handler
import android.util.Log
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioOffloadSupport
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import com.debrify.app.diagnostics.DiagnosticFileLog

/** Shared by both native players. UI writes; Media3's playback thread reads. */
class NativeAudioRouting {
    @Volatile var requiresPcm: Boolean = false
        private set

    fun update(nightMode: Boolean, systemEffects: Boolean): Boolean {
        val next = nightMode || systemEffects
        val changed = next != requiresPcm
        requiresPcm = next
        return changed
    }

    /**
     * Re-evaluate bypass/decoder selection, not just the effect's enabled flag.
     * stop/prepare retains the playlist, position, track overrides, speed and
     * playWhenReady. In particular, do not call play() on a paused session.
     * Idle/ended players pick up the policy on their next normal preparation.
     */
    fun reprepare(player: Player?): Boolean {
        if (player == null || player.mediaItemCount == 0 ||
            (player.playbackState != Player.STATE_READY &&
                player.playbackState != Player.STATE_BUFFERING)) return false
        player.stop()
        player.prepare()
        return true
    }
}

/** Native encoded output first; FFmpeg remains available for unsupported codecs. */
class NativeAudioRenderersFactory @JvmOverloads constructor(
    context: Context,
    private val routing: NativeAudioRouting,
    private val processors: Array<AudioProcessor> = emptyArray(),
) : DefaultRenderersFactory(context) {
    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>,
    ) {
        // Only change AUDIO ordering. In particular, preserve the caller's
        // video-extension preference and its IPTV video codec selector.
        val audioMode = if (extensionRendererMode == EXTENSION_RENDERER_MODE_OFF)
            EXTENSION_RENDERER_MODE_OFF else EXTENSION_RENDERER_MODE_ON
        super.buildAudioRenderers(context, audioMode, mediaCodecSelector,
            enableDecoderFallback, audioSink, eventHandler, eventListener, out)
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioTrackPlaybackParams: Boolean,
    ): AudioSink = EffectsAwareAudioSink(
        DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(enableFloatOutput)
            .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
            .setAudioProcessorChain(DefaultAudioSink.DefaultAudioProcessorChain(*processors))
            .build(),
        routing,
    )
}

/** Deny encoded bypass while PCM effects are requested, not decoded playback. */
internal class EffectsAwareAudioSink(
    delegate: AudioSink,
    private val routing: NativeAudioRouting,
) : ForwardingAudioSink(delegate) {
    private fun blocks(format: Format) =
        routing.requiresPcm && format.sampleMimeType != MimeTypes.AUDIO_RAW

    override fun supportsFormat(format: Format): Boolean =
        !blocks(format) && super.supportsFormat(format)

    override fun getFormatSupport(format: Format): Int =
        if (blocks(format)) AudioSink.SINK_FORMAT_UNSUPPORTED else super.getFormatSupport(format)

    override fun getFormatOffloadSupport(format: Format): AudioOffloadSupport =
        if (routing.requiresPcm) AudioOffloadSupport.DEFAULT_UNSUPPORTED
        else super.getFormatOffloadSupport(format)

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        super.configure(inputFormat, specifiedBufferSize, outputChannels)
        // Records the actual sink input, not merely a preference or source codec.
        val mode = if (inputFormat.sampleMimeType == MimeTypes.AUDIO_RAW) "pcm" else "encoded"
        val message = "mode=$mode mime=${inputFormat.sampleMimeType} " +
            "channels=${inputFormat.channelCount} rate=${inputFormat.sampleRate} " +
            "effectsRequirePcm=${routing.requiresPcm}"
        Log.i("NativeAudio", message)
        DiagnosticFileLog.record("native_audio", "output_configured", message)
    }
}
