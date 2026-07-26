package com.debrify.app.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Inline ExoPlayer for the ambient trailer backdrop on Android TV.
 *
 * media_kit/libmpv stutters decoding the trailer on weak TV SoCs. This renders
 * the same YouTube trailer through ExoPlayer (hardware MediaCodec) in one of
 * two modes, chosen per-player by the Dart side:
 *
 *  - **Texture** (`underlay: false`): renders into a Flutter [android.graphics.SurfaceTexture]
 *    composited by a Flutter `Texture` widget. Works everywhere, but every
 *    video frame forces Flutter to re-composite the scene on the TV's GPU.
 *  - **Underlay** (`underlay: true`): renders into a plain [SurfaceView] that
 *    lives *under* a translucent FlutterView (see MainActivity's
 *    `getTransparencyMode` / `trailerUnderlayContainer`). The video becomes its
 *    own hardware overlay plane — Flutter never touches the frames — and shows
 *    through wherever the Dart side punches a transparent hole in its UI.
 *    `setBounds` positions the view (LOGICAL px on the wire — Flutter logical
 *    == Android dp — converted here with this side's display density).
 *
 * Both modes reuse the fullscreen [AndroidTvTorrentPlayerActivity]'s proven
 * video-only + audio [MergingMediaSource] merge for high-res YouTube — that
 * activity itself cannot be embedded, so this is a separate, controls-free
 * player.
 *
 * One instance lives for the app; it manages N players keyed by id (positive =
 * Flutter texture id, negative = underlay). All ExoPlayer access happens on the
 * platform/main thread (method-channel calls and [Player.Listener] callbacks
 * both run there). Native → Dart events are pushed on the same channel and
 * dispatched by `id` on the Dart side.
 */
@OptIn(UnstableApi::class)
class TvTrailerTexturePlayer(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    messenger: BinaryMessenger,
    /** Lazily provides the full-window layer under the FlutterView that hosts
     *  underlay SurfaceViews; null when the host can't offer one (underlay
     *  create then fails and the Dart side stays on its poster). */
    private val underlayHost: () -> FrameLayout?,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val players = HashMap<Long, Handle>()

    /** Underlay players have no texture entry to mint ids from — hand out
     *  negatives so they can never collide with texture ids. */
    private var nextUnderlayId = -1L

    init {
        channel.setMethodCallHandler(this)
    }

    private class Handle(
        val id: Long,
        val player: ExoPlayer,
        val maxHeight: Int,
        // Texture mode.
        val entry: TextureRegistry.SurfaceTextureEntry? = null,
        val surface: Surface? = null,
        // Underlay mode.
        val surfaceView: SurfaceView? = null,
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
            "setBounds" -> {
                setBounds(call)
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
        val underlay = call.argument<Boolean>("underlay") ?: false

        try {
            val player = ExoPlayer.Builder(context).build()
            val handle: Handle
            if (underlay) {
                val container = underlayHost()
                if (container == null) {
                    player.release()
                    result.error("no_underlay", "underlay container unavailable", null)
                    return
                }
                val id = nextUnderlayId--
                val surfaceView = SurfaceView(container.context)
                // Start 1×1: a valid render surface for ExoPlayer immediately,
                // but effectively invisible — the underlay only shows through
                // where Flutter clears pixels, and nothing is cleared until the
                // Dart side reveals the hole. Real bounds land via setBounds
                // (sent as soon as the Dart slot mounts) well before that, so
                // the surface is already full-size and rendering on reveal —
                // no black flash, no post-reveal resize.
                container.addView(surfaceView, FrameLayout.LayoutParams(1, 1))
                player.setVideoSurfaceView(surfaceView)
                // Cover-crop inside the bounds rect (the Texture path does this
                // with a Dart FittedBox; here MediaCodec crops while rendering).
                player.videoScalingMode = C.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING
                handle = Handle(id, player, maxHeight, surfaceView = surfaceView)
            } else {
                val entry = textureRegistry.createSurfaceTexture()
                val id = entry.id()
                val surface = Surface(entry.surfaceTexture())
                player.setVideoSurface(surface)
                handle = Handle(id, player, maxHeight, entry = entry, surface = surface)
            }
            player.volume = volume
            player.repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
            player.playWhenReady = true
            players[handle.id] = handle
            val id = handle.id

            // Reuse the app's high-res YouTube merge: a video-only track muxed
            // with its separate audio track. Cross-protocol redirects match the
            // main player (googlevideo redirects http↔https). If there's no
            // separate audio, [videoUrl] is already muxed — play it directly.
            //
            // UA + per-media headers match the main player: without a browser
            // UA (ExoPlayer's default identifies the library) a large share of
            // IPTV panels/CDNs 4xx every request, so channels previewed fine
            // nowhere while playing everywhere.
            val requestHeaders = (call.argument<Map<String, Any?>>("headers") ?: emptyMap())
                .entries.mapNotNull { (k, v) -> (v as? String)?.let { k to it } }
                .toMap()
            // UA via defaultRequestProperties, NOT setUserAgent — media3
            // applies the userAgent field last, which would clobber a
            // channel-declared User-Agent in [requestHeaders]. In this merge
            // the channel's own headers win over the browser default. The
            // default is only added when the channel names no UA in ANY
            // case — the merge map is case-sensitive, and two UA entries
            // would race on map order.
            val headerProps = HashMap<String, String>()
            if (requestHeaders.keys.none { it.equals("User-Agent", ignoreCase = true) }) {
                headerProps["User-Agent"] = DEFAULT_UA
            }
            headerProps.putAll(requestHeaders)
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setDefaultRequestProperties(headerProps)
            val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
            val mediaSourceFactory = DefaultMediaSourceFactory(context)
                .setDataSourceFactory(dataSourceFactory)
            if (!audioUrl.isNullOrEmpty()) {
                val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(videoUrl))
                val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(audioUrl))
                // adjustPeriodTimeOffsets + clipDurations tolerate the small
                // video/audio duration mismatch in YouTube adaptive streams.
                player.setMediaSource(MergingMediaSource(true, true, videoSource, audioSource))
            } else {
                // Single muxed URL. Unlike the YouTube merge above, this may be
                // ANY container — the IPTV channel preview feeds HLS (.m3u8)
                // and raw-TS live streams through here — so infer the source
                // type like the main player does instead of assuming a
                // progressive file (ProgressiveMediaSource can't parse an HLS
                // playlist: the stream errors out and the preview never shows).
                player.setMediaSource(
                    mediaSourceFactory.createMediaSource(MediaItem.fromUri(videoUrl))
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
                    // Texture mode: cap the texture (and thus GPU upload) to
                    // [maxHeight] — the backdrop never needs full res. Underlay
                    // mode needs no cap (the compositor scales the plane; there
                    // is no per-frame GPU upload to trim).
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

                // Extension-less HLS (jmp2.uk-style IPTV URLs): the source
                // factory infers by URL extension, so a bare URL is tried as
                // progressive and fails to sniff the #EXTM3U text. One retry
                // with the type forced to HLS before reporting failure.
                private var hlsRetried = false

                override fun onPlayerError(error: PlaybackException) {
                    if (!hlsRetried && audioUrl.isNullOrEmpty() &&
                        isUnrecognizedInputFormat(error)
                    ) {
                        hlsRetried = true
                        android.util.Log.d(
                            "TvTrailer",
                            "Unrecognized format — retrying $videoUrl as HLS"
                        )
                        player.setMediaSource(
                            mediaSourceFactory.createMediaSource(
                                MediaItem.Builder()
                                    .setUri(videoUrl)
                                    .setMimeType(MimeTypes.APPLICATION_M3U8)
                                    .build()
                            )
                        )
                        player.prepare()
                        player.play()
                        return
                    }
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

    /** Position an underlay SurfaceView. Bounds arrive in LOGICAL px
     *  (Flutter logical == Android dp) and are converted to window px with
     *  THIS side's display density — deliberately not Flutter's
     *  devicePixelRatio, which is scaled down under low-res rendering on
     *  weak-GPU TVs while the window stays in real display space.
     *  No-op for texture players and for unchanged rects. */
    private fun setBounds(call: MethodCall) {
        val sv = handle(call)?.surfaceView ?: return
        val d = sv.resources.displayMetrics.density
        val left = call.argument<Number>("left")?.let { Math.round(it.toFloat() * d) } ?: return
        val top = call.argument<Number>("top")?.let { Math.round(it.toFloat() * d) } ?: return
        val width = call.argument<Number>("width")?.let { Math.round(it.toFloat() * d) } ?: return
        val height = call.argument<Number>("height")?.let { Math.round(it.toFloat() * d) } ?: return
        if (width <= 0 || height <= 0) return
        val lp = sv.layoutParams as? FrameLayout.LayoutParams ?: return
        if (lp.width == width && lp.height == height &&
            lp.leftMargin == left && lp.topMargin == top
        ) {
            return
        }
        lp.width = width
        lp.height = height
        lp.leftMargin = left
        lp.topMargin = top
        sv.layoutParams = lp
    }

    private fun applyBufferCap(h: Handle, width: Int, height: Int) {
        val entry = h.entry ?: return
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
            entry.surfaceTexture().setDefaultBufferSize(tw, th)
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

    private fun dispose(id: Long?, deferHeavy: Boolean = true) {
        val handle = players.remove(id ?: return) ?: return
        // Underlay: drop the view (and its punched-through window region) NOW —
        // a view op that must run on the platform thread and should land in
        // the same frame as the teardown.
        try {
            handle.surfaceView?.let { (it.parent as? ViewGroup)?.removeView(it) }
        } catch (_: Exception) {
        }
        // The codec release is the expensive part (50-300ms on weak SoCs). It
        // must run on the thread the player was created on (this one), but it
        // must NOT run inside the same main-looper turn as the DPAD input
        // that triggered the teardown — that read as "navigation janks right
        // after a trailer". Post it to a later turn; synchronous only on the
        // Activity-destroy path where jank no longer matters.
        val releaseHeavy = Runnable {
            try {
                handle.player.release()
            } catch (_: Exception) {
            }
            try {
                handle.surface?.release()
            } catch (_: Exception) {
            }
            try {
                handle.entry?.release()
            } catch (_: Exception) {
            }
        }
        if (deferHeavy) main.post(releaseHeavy) else releaseHeavy.run()
    }

    /** Tear down every player and detach the channel (call from Activity destroy). */
    fun releaseAll() {
        players.keys.toList().forEach { dispose(it, deferHeavy = false) }
        channel.setMethodCallHandler(null)
    }

    /** True when [error]'s cause chain contains a failed extractor sniff. */
    private fun isUnrecognizedInputFormat(error: Throwable?): Boolean {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is UnrecognizedInputFormatException) return true
            cause = cause.cause
        }
        return false
    }

    companion object {
        private const val CHANNEL = "com.debrify.app/tv_trailer"

        /** Matches the main player's UA (and Dart's kIptvDefaultUserAgent):
         *  a channel must behave identically in preview and playback. */
        private const val DEFAULT_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
}
