package com.debrify.app.util

import android.os.Handler
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RendererConfiguration
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.metadata.MetadataOutput
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.SampleStream
import androidx.media3.exoplayer.text.TextOutput
import androidx.media3.exoplayer.video.VideoRendererEventListener

@OptIn(UnstableApi::class)
class OffsetTextRenderer(
    private val delegate: Renderer
) : Renderer by delegate {

    @Volatile
    var offsetUs: Long = 0L

    override fun render(positionUs: Long, elapsedRealtimeUs: Long) {
        delegate.render(positionUs - offsetUs, elapsedRealtimeUs)
    }

    override fun resetPosition(positionUs: Long) {
        delegate.resetPosition(positionUs - offsetUs)
    }

    override fun enable(
        configuration: RendererConfiguration,
        formats: Array<out Format>,
        stream: SampleStream,
        positionUs: Long,
        joining: Boolean,
        mayRenderStartOfStream: Boolean,
        startPositionUs: Long,
        offsetUs: Long,
        mediaPeriodId: MediaSource.MediaPeriodId
    ) {
        val shift = this.offsetUs
        delegate.enable(
            configuration,
            formats,
            stream,
            positionUs - shift,
            joining,
            mayRenderStartOfStream,
            startPositionUs - shift,
            offsetUs,
            mediaPeriodId
        )
    }
}

@OptIn(UnstableApi::class)
class OffsetRenderersFactory(
    private val delegate: RenderersFactory
) : RenderersFactory {

    private val offsetRenderers = mutableListOf<OffsetTextRenderer>()

    fun setOffsetUs(value: Long) {
        offsetRenderers.forEach { it.offsetUs = value }
    }

    override fun createRenderers(
        eventHandler: Handler,
        videoRendererEventListener: VideoRendererEventListener,
        audioRendererEventListener: AudioRendererEventListener,
        textOutput: TextOutput,
        metadataOutput: MetadataOutput
    ): Array<Renderer> {
        offsetRenderers.clear()
        val renderers = delegate.createRenderers(
            eventHandler,
            videoRendererEventListener,
            audioRendererEventListener,
            textOutput,
            metadataOutput
        )
        return renderers.map { renderer ->
            if (renderer.trackType == C.TRACK_TYPE_TEXT) {
                OffsetTextRenderer(renderer).also { offsetRenderers.add(it) }
            } else {
                renderer
            }
        }.toTypedArray()
    }
}
