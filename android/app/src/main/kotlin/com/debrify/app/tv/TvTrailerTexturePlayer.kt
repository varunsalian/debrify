package com.debrify.app.tv

import android.content.Context
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Inline, texture-based ExoPlayer for the ambient trailer backdrop on Android TV.
 *
 * media_kit/libmpv stutters decoding the trailer on weak TV SoCs. This renders
 * the same YouTube trailer through ExoPlayer (hardware MediaCodec) into a Flutter
 * [Texture], so it can sit *inside* the widget tree behind the hero content — the
 * fullscreen [AndroidTvTorrentPlayerActivity] can't be embedded, so this is a
 * separate, controls-free surface that reuses that activity's proven
 * video-only + audio [MergingMediaSource] merge for high-res YouTube.
 *
 * One instance lives for the app; it manages N players keyed by textureId. All
 * ExoPlayer access happens on the platform/main thread (method-channel calls and
 * [Player.Listener] callbacks both run there). Native → Dart events are pushed on
 * the same channel and dispatched by `id` on the Dart side.
 */
@OptIn(UnstableApi::class)
class TvTrailerTexturePlayer(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val players = HashMap<Long, Handle>()

    init {
        channel.setMethodCallHandler(this)
    }

    private class Handle(
        val id: Long,
        val entry: TextureRegistry.SurfaceTextureEntry,
        val surface: Surface,
        val player: ExoPlayer,
        val maxHeight: Int,
    )

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> create(call, result)
            "setVolume" -> {
                handle(call)?.player?.volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                result.success(null)
            }
            "seek" -> {
                handle(call)?.player?.seekTo(call.argument<Number>("positionMs")?.toLong() ?: 0L)
                result.success(null)
            }
            "play" -> {
                handle(call)?.player?.play()
                result.success(null)
            }
            "pause" -> {
                handle(call)?.player?.pause()
                result.success(null)
            }
            "getPosition" -> {
                val p = handle(call)?.player
                val dur = p?.duration?.takeIf { it != C.TIME_UNSET } ?: 0L
                result.success(
                    mapOf(
                        "positionMs" to (p?.currentPosition ?: 0L),
                        "durationMs" to dur,
                    )
                )
            }
            "dispose" -> {
                dispose(call.argument<Number>("id")?.toLong())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handle(call: MethodCall): Handle? {
        val id = call.argument<Number>("id")?.toLong() ?: return null
        return players[id]
    }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        val videoUrl = call.argument<String>("videoUrl")
        if (videoUrl.isNullOrEmpty()) {
            result.error("bad_args", "videoUrl is required", null)
            return
        }
        val audioUrl = call.argument<String>("audioUrl")
        val maxHeight = call.argument<Number>("maxHeight")?.toInt() ?: 0
        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
        val loop = call.argument<Boolean>("loop") ?: true

        try {
            val entry = textureRegistry.createSurfaceTexture()
            val id = entry.id()
            val surface = Surface(entry.surfaceTexture())
            val player = ExoPlayer.Builder(context).build()
            player.setVideoSurface(surface)
            player.volume = volume
            player.repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            player.playWhenReady = true

            val handle = Handle(id, entry, surface, player, maxHeight)
            players[id] = handle

            // Reuse the app's high-res YouTube merge: a video-only track muxed
            // with its separate audio track. Cross-protocol redirects match the
            // main player (googlevideo redirects http↔https). If there's no
            // separate audio, [videoUrl] is already muxed — play it directly.
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
            val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
            if (!audioUrl.isNullOrEmpty()) {
                val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(videoUrl))
                val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(audioUrl))
                // adjustPeriodTimeOffsets + clipDurations tolerate the small
                // video/audio duration mismatch in YouTube adaptive streams.
                player.setMediaSource(MergingMediaSource(true, true, videoSource, audioSource))
            } else {
                player.setMediaSource(
                    ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(videoUrl))
                )
            }

            player.addListener(object : Player.Listener {
                private var firstFrameSent = false
                private var lastDuration = 0L

                override fun onRenderedFirstFrame() {
                    if (firstFrameSent) return
                    firstFrameSent = true
                    emit("firstFrame", id)
                }

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    emit("playing", id, mapOf("playing" to isPlaying))
                }

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    // Cap the texture (and thus GPU upload) to [maxHeight] — the
                    // backdrop never needs full res. Decode stays hardware-cheap
                    // regardless; this trims the per-frame upload on weak TV GPUs.
                    applyBufferCap(handle, videoSize.width, videoSize.height)
                    emit(
                        "videoSize",
                        id,
                        mapOf("width" to videoSize.width, "height" to videoSize.height),
                    )
                }

                override fun onPlaybackStateChanged(state: Int) {
                    if (state == Player.STATE_READY) {
                        val d = player.duration
                        if (d != C.TIME_UNSET && d != lastDuration) {
                            lastDuration = d
                            emit("duration", id, mapOf("durationMs" to d))
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    emit("error", id, mapOf("message" to (error.message ?: "playback error")))
                }
            })

            player.prepare()
            result.success(mapOf("textureId" to id))
        } catch (e: Exception) {
            android.util.Log.e("TvTrailer", "create failed", e)
            result.error("create_failed", e.message, null)
        }
    }

    private fun applyBufferCap(h: Handle, width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        var tw = width
        var th = height
        val cap = h.maxHeight
        if (cap in 1 until height) {
            val scale = cap.toDouble() / height.toDouble()
            tw = (width * scale).toInt().coerceAtLeast(2)
            th = cap
        }
        try {
            h.entry.surfaceTexture().setDefaultBufferSize(tw, th)
        } catch (_: Exception) {
        }
    }

    private fun emit(event: String, id: Long, extra: Map<String, Any?> = emptyMap()) {
        main.post {
            val payload = HashMap<String, Any?>(extra.size + 1)
            payload["id"] = id
            payload.putAll(extra)
            channel.invokeMethod(event, payload)
        }
    }

    private fun dispose(id: Long?) {
        val handle = players.remove(id ?: return) ?: return
        try {
            handle.player.release()
        } catch (_: Exception) {
        }
        try {
            handle.surface.release()
        } catch (_: Exception) {
        }
        try {
            handle.entry.release()
        } catch (_: Exception) {
        }
    }

    /** Tear down every player and detach the channel (call from Activity destroy). */
    fun releaseAll() {
        players.keys.toList().forEach { dispose(it) }
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val CHANNEL = "com.debrify.app/tv_trailer"
    }
}
