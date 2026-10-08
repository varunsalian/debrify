package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.debrify.app.MainActivity
import com.debrify.app.R
import com.debrify.app.profiles.NativePlayerPreferences
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.After
import org.junit.Before
import org.junit.Assert.*
import org.json.JSONObject
import org.robolectric.util.ReflectionHelpers
import java.lang.reflect.Proxy
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Real original selection/apply bodies, layout and source browser; fake transport/player only. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@org.robolectric.annotation.Config(instrumentedPackages = ["com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
    "com.debrify.app.tv.TvSourceSwitchController", "com.debrify.app.tv.TvSourceSwitchApplier"])
internal open class TvPhase8OriginalTest : TvPhase3OriginalTest() {
    protected val messenger = TvPlayerRecordingMessenger()
    protected val probe = TvPhase8PlayerProbe()
    private var previous: MethodChannel? = null
    private var frameDelay = java.time.Duration.ZERO
    private var framesPaused = false
    protected val attemptType = Class.forName("com.debrify.app.tv.AndroidTvTorrentPlayerActivity\$ShufflePlaybackAttempt")
    @Before fun preparePhase8() {
        frameDelay = org.robolectric.shadows.ShadowChoreographer.getFrameDelay()
        framesPaused = org.robolectric.shadows.ShadowChoreographer.isPaused()
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(15))
        org.robolectric.shadows.ShadowChoreographer.setPaused(true)
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear().commit()
        lifecycle.create().start().resume().visible()
        // Missing launch payload deliberately avoids setupPlayer. Undo only that
        // fixture finish flag, so retained async liveness checks see a live host.
        ReflectionHelpers.setField(activity, "mFinished", false)
        set("finishProgressAttempted", false)
        set("playerPreferences", NativePlayerPreferences.fromIntent(activity, activity.intent))
        invoke("bindViews")
        val subtitles = androidx.media3.ui.SubtitleView(activity)
        set("subtitleOverlay", subtitles); set("subtitleControlsLift", SubtitleControlsLiftController(subtitles, 24))
        previous = MainActivity.getAndroidTvPlayerChannel()
        MainActivity.setAndroidTvPlayerChannel(MethodChannel(messenger, "com.debrify.app/android_tv_player"))
        set("player", probe.player)
        set("payload", PlaybackPayload("Film", null, "single", mutableListOf(p2Item()), 0, null))
        set("currentIndex", 0)
        sources().addAll(listOf(source(0), source(1)))
        layout(); tick(32); messenger.requests.clear(); probe.events.clear()
    }
    @Suppress("UNCHECKED_CAST") protected fun sources() = field("stremioSources") as MutableList<StremioSource>
    protected fun source(i: Int, direct: String? = null, headers: Map<String, String> = emptyMap()) =
        StremioSource.fromJson(JSONObject().put("name", "Source $i").put("stream_type", if (direct == null) "torrent" else "directUrl")
            .put("direct_url", direct).put("http_headers", JSONObject(headers)), i)
    protected fun model() = field("payload") as PlaybackPayload
    protected fun pill() = field("statusPill") as TextView
    protected fun badge() = field("stremioSourceBadge") as View
    protected fun browser() = field("sourceBrowser") as TvSourceBrowserController
    protected fun requests(method: String) = messenger.requests.filter { it.call.method == method }
    protected fun index(method: String) = messenger.requests.indexOfLast { it.call.method == method }
    protected fun resolve(playlist: Boolean, token: Int = 7) {
        set("stremioResolutionToken", token)
        call(if (playlist) "resolveSourceToPlaylistViaFlutter" else "resolveStremioSourceViaFlutter",
            arrayOf(StremioSource::class.java, intType), sources()[1], token)
    }
    protected fun reply(playlist: Boolean, value: Any?) { messenger.success(value, index(if (playlist) "requestSourcePlaylistResolve" else "requestStremioSourceResolve")); idle() }
    /** Deliver binary callback on a bounded worker, without draining the paused main queue. */
    protected fun workerReply(kind: String, value: Any? = null) {
        val request = messenger.requests.last(); val failure = AtomicReference<Throwable?>()
        val worker = Thread {
            try {
                val encoded = when (kind) {
                    "error" -> StandardMethodCodec.INSTANCE.encodeErrorEnvelope("error", "message", null)
                    "missing" -> null
                    else -> StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(value)
                }?.apply { flip() }
                request.reply!!.reply(encoded)
            } catch (t: Throwable) { failure.set(t) }
        }
        worker.start(); worker.join(TimeUnit.SECONDS.toMillis(5))
        assertFalse("reply worker completed before token supersession", worker.isAlive)
        failure.get()?.let { throw AssertionError("binary reply worker failed", it) }
    }
    protected fun direct(url: String = "https://phase8.invalid/new.mp4", i: Int = 1, mime: String? = null, discovered: Boolean = false) =
        call("switchToStremioSource", arrayOf(stringType, intType, stringType, boolType), url, i, mime, discovered)
    protected fun pack(items: List<*>, season: Int? = null, episode: Int? = null,
                       suppress: Boolean = false, exact: Boolean = false, attempt: Any? = null) =
        call("switchToSourcePlaylist", arrayOf(intType, listType, boxedIntType, boxedIntType, boolType, boolType, attemptType),
            1, items, season, episode, suppress, exact, attempt)
    protected fun raw(title: String = "Incoming", season: Int? = null, episode: Int? = null, url: String = "https://phase8.invalid/pack.mp4") =
        mapOf("id" to title, "title" to title, "url" to url, "season" to season, "episode" to episode,
            "resumePositionMs" to 123L, "traktProgressPercent" to 50.0).filterValues { it != null }
    protected fun seriesItem(season: Int = 2, episode: Int = 4) {
        model().contentType = "series"; model().items.clear(); model().items.add(p2Item("Fetched title", season = season, episode = episode).copy(sourceTitle = "old filename", artwork = "old art", description = "old description", rating = 8.0))
    }
    protected fun cursor(committed: Boolean = false) = StartupFailoverCursor(0, maxAttempts = 3).also {
        it.beginInitial(2); if (committed) it.commit(); set("startupFailoverCursor", it)
    }
    protected fun attempt(): Any = attemptType.declaredConstructors.first { it.parameterCount == 7 }.apply { isAccessible = true }
        .newInstance(field("mediaPreparationGeneration"), field("showShuffleGeneration"), false, {}, false, null, false)
    protected fun attemptField(attempt: Any, name: String) = attemptType.getDeclaredField(name).apply { isAccessible = true }.get(attempt)
    protected fun tick(ms: Long) { var rest = ms; while (rest > 0) { val step = rest.coerceAtMost(15); advance(step); rest -= step } }
    protected fun layout() {
        val root = activity.findViewById<View>(android.R.id.content)
        root.measure(View.MeasureSpec.makeMeasureSpec(1200, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(900, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, 1200, 900)
    }
    @After fun cleanPhase8() {
        invoke("cancelSourceSwitchWait"); (field("sourceBrowser") as? TvSourceBrowserController)?.destroy()
        for (name in listOf("progressHandler", "controlsHandler", "externalSubtitleHandler", "iptvBrowseHandler", "bufferingHandler", "seekbarHandler", "focusRecoveryHandler"))
            (field(name) as Handler).removeCallbacksAndMessages(null)
        for (name in listOf("subtitleScope", "mediaPreparationScope"))
            (field(name) as kotlinx.coroutines.CoroutineScope).coroutineContext[kotlinx.coroutines.Job]?.cancel()
        MainActivity.setAndroidTvPlayerChannel(previous)
        if (!activity.isDestroyed) lifecycle.pause().stop().destroy()
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(frameDelay)
        org.robolectric.shadows.ShadowChoreographer.setPaused(framesPaused)
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPhase8PlayerProbe {
    val events = mutableListOf<String>()
    val listeners = mutableListOf<Player.Listener>()
    val removed = mutableListOf<Player.Listener>()
    val media = mutableListOf<MediaItem>()
    var position = 25_000L
    var state = Player.STATE_BUFFERING
    var error: androidx.media3.exoplayer.ExoPlaybackException? = null
    var onEvent: ((String) -> Unit)? = null
    val player: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { proxy, method, args ->
        fun event(v: String) { onEvent?.invoke(v); events.add(v) }
        when (method.name) {
            "getCurrentPosition", "getContentPosition" -> position
            "getDuration", "getContentDuration" -> 100_000L
            "getPlaybackState" -> state
            "getPlayerError" -> error
            "addListener" -> { listeners.add(args!![0] as Player.Listener); event("listen:add"); null }
            "removeListener" -> { val v = args!![0] as Player.Listener; removed.add(v); listeners.remove(v); event("listen:remove"); null }
            "setMediaItem" -> { val v = args!![0] as MediaItem; media.add(v); event("media:${v.localConfiguration!!.uri}"); null }
            "setMediaSource" -> { event("merged"); null }
            "seekTo" -> { event("seek:${args!!.last()}"); null }
            "setPlayWhenReady" -> { event("playWhenReady:${args!![0]}"); null }
            "prepare", "play", "pause", "release", "stop" -> { event(method.name); null }
            "getApplicationLooper" -> Looper.getMainLooper()
            "getCurrentTracks" -> androidx.media3.common.Tracks.EMPTY
            "getVideoSize" -> androidx.media3.common.VideoSize.UNKNOWN
            "getAvailableCommands" -> Player.Commands.EMPTY
            "getCurrentTimeline" -> androidx.media3.common.Timeline.EMPTY
            "toString" -> "TvPhase8PlayerProbe"
            "hashCode" -> System.identityHashCode(proxy)
            "equals" -> proxy === args?.firstOrNull()
            else -> when (method.returnType) { java.lang.Boolean.TYPE -> false; java.lang.Integer.TYPE -> 0; java.lang.Long.TYPE -> 0L; java.lang.Float.TYPE -> 0f; else -> null }
        }
    } as ExoPlayer
    fun emit(value: Int) { state = value; listeners.toList().forEach { it.onPlaybackStateChanged(value) } }
}
