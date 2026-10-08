package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import com.debrify.app.R
import com.debrify.app.profiles.NativePlayerPreferences
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Before
import java.lang.reflect.Proxy

/** Real activity methods/trio and attached guide; only transport and player are fakes. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@org.robolectric.annotation.Config(instrumentedPackages = ["com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
    "com.debrify.app.tv.TvStremioTvGuideController"])
internal open class TvPhase7OriginalTest : TvPhase3OriginalTest() {
    protected val messenger = TvPlayerRecordingMessenger()
    protected val probe = TvPhase7PlayerProbe()
    protected lateinit var root: FrameLayout
    protected lateinit var playlistButton: AppCompatButton
    private var previous: MethodChannel? = null
    private var previousFrameDelay = java.time.Duration.ZERO
    private var previousFramesPaused = false

    @Before fun preparePhase7() {
        previousFrameDelay = org.robolectric.shadows.ShadowChoreographer.getFrameDelay()
        previousFramesPaused = org.robolectric.shadows.ShadowChoreographer.isPaused()
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(15))
        org.robolectric.shadows.ShadowChoreographer.setPaused(true)
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear().commit()
        lifecycle.create().start().resume().visible()
        root = bindViews()
        set("playerPreferences", NativePlayerPreferences.fromIntent(activity, activity.intent))
        for (name in listOf("nextText", "nextSubtext", "titleView", "channelBadge")) {
            val view = TextView(activity); root.addView(view); set(name, view)
        }
        for (name in listOf("titleContainer", "titleOttContainer")) {
            val view = FrameLayout(activity); root.addView(view); set(name, view)
        }
        val controls = FrameLayout(activity); root.addView(controls); set("controlsOverlay", controls)
        val subtitles = SubtitleView(activity); root.addView(subtitles); set("subtitleOverlay", subtitles)
        set("subtitleControlsLift", SubtitleControlsLiftController(subtitles, 24))
        LayoutInflater.from(activity).inflate(R.layout.view_stremio_tv_guide, root, true)
        playlistButton = AppCompatButton(activity).apply { id = R.id.debrify_playlist_button; text = "Playlist" }
        (field("playerView") as PlayerView).addView(playlistButton)
        previous = MainActivity.getAndroidTvPlayerChannel()
        MainActivity.setAndroidTvPlayerChannel(MethodChannel(messenger, "com.debrify.app/android_tv_player"))
        set("player", probe.player); set("finishProgressAttempted", false)
        // Advance frames explicitly: automatic vsync advances the clock while
        // draining animations, hiding the exact Handler deadline boundaries.
        layout(); tick(32)
    }

    protected fun init(vararg channels: JSONObject, current: String = "0") =
        call("initStremioTvGuide", arrayOf(JSONObject::class.java), JSONObject().put("channels", JSONArray(channels.toList())).put("currentChannelId", current))
    protected fun json(id: String, title: String = "Channel $id", data: Boolean = true): JSONObject =
        JSONObject().put("id", id).put("name", title).also { if (data) it.put("nowPlaying", JSONObject().put("title", "Film $id")) }
    @Suppress("UNCHECKED_CAST") protected fun channels() = field("stremioTvChannels") as MutableList<StremioTvGuideChannel>
    protected fun standard() { init(json("0"), json("1")); probe.events.clear(); messenger.requests.clear() }
    protected fun view(name: String) = field(name) as View
    protected fun text(name: String) = field(name) as TextView
    protected fun list() = field("stremioTvGuideList") as RecyclerView
    protected fun adapter() = field("stremioTvChannelAdapter") as StremioTvGuideAdapter
    protected fun guide() = view("stremioTvGuideOverlay")
    protected fun visible() = field("stremioTvGuideVisible") as Boolean
    protected fun pump() { idle(); tick(30); idle() }
    protected fun tick(ms: Long) {
        var remaining = ms
        while (remaining > 0) { val step = remaining.coerceAtMost(15); advance(step); remaining -= step }
    }
    protected fun tickUntil(deadline: Long) = tick((deadline - android.os.SystemClock.uptimeMillis()).coerceAtLeast(0))
    protected fun next(finish: Boolean = false) = call("requestStremioTvNext", arrayOf(boolType), finish)
    protected fun nextDefault() = defaultCall("requestStremioTvNext", arrayOf(boolType), 1, false)
    protected fun switch(channel: StremioTvGuideChannel = channels()[1]) = call("switchToStremioTvChannel", arrayOf(StremioTvGuideChannel::class.java), channel)
    protected fun requests(method: String) = messenger.requests.filter { it.call.method == method }
    protected fun index(method: String) = messenger.requests.indexOfLast { it.call.method == method }
    protected fun playback(title: String = "New programme") = mapOf("url" to "https://phase7.invalid/play.mp4", "title" to title,
        "contentType" to "movie", "startAtPercent" to 0.25, "nowPlaying" to mapOf("title" to title), "nextUp" to mapOf("title" to "Later"))
    protected fun payload() = PlaybackPayload("Old", null, "single", mutableListOf(p2Item()), 0, null).also { set("payload", it) }
    protected fun layout() {
        root.measure(View.MeasureSpec.makeMeasureSpec(1200, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(900, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, 1200, 900)
    }
    protected fun range(first: Int, last: Int) = TvPhase7RangeLayoutManager(activity, first, last).also { list().layoutManager = it }
    protected fun error(message: String?, at: Int = messenger.requests.lastIndex) {
        val envelope = StandardMethodCodec.INSTANCE.encodeErrorEnvelope("error", message, null).apply { flip() }
        Handler(Looper.getMainLooper()).post { messenger.requests[at].reply!!.reply(envelope) }
    }

    @After fun cleanPhase7() {
        invoke("cancelGuideWait")
        MainActivity.setAndroidTvPlayerChannel(previous)
        for (name in listOf("progressHandler", "controlsHandler", "externalSubtitleHandler", "iptvBrowseHandler", "bufferingHandler", "seekbarHandler", "focusRecoveryHandler"))
            (field(name) as Handler).removeCallbacksAndMessages(null)
        if (!activity.isDestroyed) lifecycle.pause().stop().destroy()
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(previousFrameDelay)
        org.robolectric.shadows.ShadowChoreographer.setPaused(previousFramesPaused)
    }
}

internal class TvPhase7RangeLayoutManager(context: android.content.Context, var first: Int, var last: Int) : LinearLayoutManager(context) {
    val scrolls = mutableListOf<Int>()
    var scrolledAt = 0L
    override fun findFirstVisibleItemPosition() = first
    override fun findLastVisibleItemPosition() = last
    override fun scrollToPosition(position: Int) { scrolledAt = android.os.SystemClock.uptimeMillis(); scrolls.add(position); super.scrollToPosition(position) }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPhase7PlayerProbe {
    val events = mutableListOf<String>()
    val listeners = mutableListOf<Player.Listener>()
    val removed = mutableListOf<Player.Listener>()
    var onEvent: ((String) -> Unit)? = null
    var state = Player.STATE_BUFFERING
    val player: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { proxy, method, args ->
        fun event(value: String) { onEvent?.invoke(value); events.add(value) }
        when (method.name) {
            "addListener" -> { listeners.add(args!![0] as Player.Listener); event("listen:add"); null }
            "removeListener" -> { val listener = args!![0] as Player.Listener; removed.add(listener); listeners.remove(listener); event("listen:remove"); null }
            "setMediaItem" -> { val item = args!![0] as MediaItem; event("media:${item.localConfiguration!!.uri}:${item.mediaMetadata.title}"); null }
            "prepare" -> { event("prepare"); null }
            "setPlayWhenReady" -> { event("playWhenReady:${args!![0]}"); null }
            "play", "pause", "release", "stop" -> { event(method.name); null }
            "getPlaybackState" -> state
            "getApplicationLooper" -> Looper.getMainLooper()
            "getCurrentTracks" -> androidx.media3.common.Tracks.EMPTY
            "getVideoSize" -> androidx.media3.common.VideoSize.UNKNOWN
            "getAvailableCommands" -> Player.Commands.EMPTY
            "getCurrentTimeline" -> androidx.media3.common.Timeline.EMPTY
            "toString" -> "TvPhase7PlayerProbe"
            "hashCode" -> System.identityHashCode(proxy)
            "equals" -> proxy === args?.firstOrNull()
            else -> when (method.returnType) {
                java.lang.Boolean.TYPE -> false
                java.lang.Integer.TYPE -> 0
                java.lang.Long.TYPE -> 0L
                java.lang.Float.TYPE -> 0f
                else -> null
            }
        }
    } as ExoPlayer
    fun emit(state: Int) { this.state = state; listeners.toList().forEach { it.onPlaybackStateChanged(state) } }
}
