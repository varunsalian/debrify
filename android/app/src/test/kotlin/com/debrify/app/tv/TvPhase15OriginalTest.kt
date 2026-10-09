package com.debrify.app.tv

import android.os.Handler
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.core.widget.TextViewCompat
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.debrify.app.R
import com.debrify.app.audio.NativeAudioRouting
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.robolectric.annotation.Config
import java.lang.reflect.Proxy

/** Real dock bootstrap, installed listeners and borrowed player/routing collaborators. */
@Config(sdk = [28], shadows = [TvPhase15LoudnessShadow::class, TvPhase15AudioEffectShadow::class])
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase15OriginalTest : TvPhase5OriginalTest() {
    protected open val skin = TvControlsSkin.CLASSIC
    protected open val guide = GuideStyle.CLASSIC
    protected var session = 51
    protected var mediaCount = 0
    protected var tracks = Tracks.EMPTY
    protected var speed = 1f
    protected var videoFormat: androidx.media3.common.Format? = null
    private var created = false
    private var frameDelay = java.time.Duration.ofMillis(16)
    protected val settingsPlayer: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
        arrayOf(ExoPlayer::class.java)) { _, method, args ->
        when (method.name) {
            "getAudioSessionId" -> session
            "getMediaItemCount" -> mediaCount
            "getCurrentTracks" -> tracks
            "getVideoFormat" -> videoFormat
            "seekTo" -> { probe.position = args!!.last() as Long; probe.events.add("seek:${probe.position}"); null }
            "getPlaybackParameters" -> PlaybackParameters(speed)
            "setPlaybackSpeed" -> { speed = args!![0] as Float; probe.events.add("speed:$speed"); null }
            else -> method.invoke(probe.player, *(args ?: emptyArray()))
        }
    } as ExoPlayer

    protected open fun bootstrapPayload(): JSONObject {
        val item = JSONObject().put("title", "Film.mkv").put("url", "https://phase15.invalid/film")
        return JSONObject().put("title", "Film").put("contentType", "single")
            .put("startIndex", 0).put("items", JSONArray().put(item))
    }
    @Before fun bootstrapPhase15() {
        TvPhase15Effects.reset()
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit()
            .putString("flutter." + TvControlsSkin.PREF_KEY, skin.name.lowercase())
            .putString("flutter.iptv_player_guide_style", guide.name.lowercase()).commit()
        frameDelay = org.robolectric.shadows.ShadowChoreographer.getFrameDelay()
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(16))
        activity.intent.putExtra("payload", bootstrapPayload().toString())
        lifecycle.create().start().resume().visible(); created = true
        (field("player") as? ExoPlayer)?.release()
        pv().player = null
        set("player", settingsPlayer)
        activity.findViewById<View>(R.id.android_tv_startup_gate).visibility = View.GONE
        idle()
        TvPlaylistUiQueue.attach(activity.window.decorView)
        TvPlaylistUiQueue.pauseFrames()
        messenger.requests.clear(); probe.events.clear(); TvPhase15Effects.reset()
    }
    protected fun pv() = field("playerView") as PlayerView
    protected fun view(id: Int): View? = pv().findViewById(id)
    protected fun button(name: String) = field(name) as AppCompatButton
    protected fun dock() = view(R.id.debrify_controls_buttons) as LinearLayout
    protected fun routing() = field("nativeAudioRouting") as NativeAudioRouting
    protected fun setup() = call("setupControls", emptyArray())
    protected fun presentation(entry: IptvChannelEntry?) = call("updateIptvControlPresentation", arrayOf(IptvChannelEntry::class.java), entry)
    protected fun aspect(index: Int) { set("resizeModeIndex", index); call("applyResizeMode", emptyArray()); call("updateAspectButtonLabel", emptyArray()) }
    protected fun playback(index: Int) = call("applyPlaybackSpeed", arrayOf(intType), index)
    protected fun night(index: Int) = call("applyNightMode", arrayOf(intType), index)
    protected fun effect() = field("loudnessEnhancer") as android.media.audiofx.LoudnessEnhancer?
    protected fun initialize() = call("initializeLoudnessEnhancer", emptyArray())
    protected fun releaseEffect() = call("releaseLoudnessEnhancer", emptyArray())
    protected fun sync(id: Int? = null) = call("syncAudioEffectSession", arrayOf(boxedIntType), id)
    protected fun toast() = org.robolectric.shadows.ShadowToast.getTextOfLatestToast()?.toString()
    protected fun menu() = field("unifiedMenu") as UnifiedMenuController
    protected fun menuModel() = TvPlayerOriginalAccess.field(menu(), "model") as UnifiedMenuController.Model
    protected fun model(name: String, index: Int = 0): UnifiedMenuController.Model =
        call(name, arrayOf(listType, intType), listOf(UnifiedMenuController.Row("Rail")), index) as UnifiedMenuController.Model
    protected fun layout() {
        val root = activity.window.decorView
        root.measure(View.MeasureSpec.makeMeasureSpec(1440, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(900, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, 1440, 900)
    }
    protected fun frames(ms: Long) = TvPlaylistUiQueue.advance(ms)
    protected fun focus(view: View, value: Boolean) {
        assertNotNull("setup installs focus listener", view.onFocusChangeListener)
        view.onFocusChangeListener.onFocusChange(view, value)
    }
    protected fun children() = List(dock().childCount) { dock().getChildAt(it) }
    protected fun destroyNow() { lifecycle.destroy(); created = false }
    @After fun cleanupPhase15() {
        TvPhase15Effects.failRelease = false
        if (created) lifecycle.destroy() else releaseEffect()
        com.debrify.app.audio.AudioEffectSession.close(activity, TvPlayerOriginalAccess.field(com.debrify.app.audio.AudioEffectSession, "openSessionId") as Int)
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(frameDelay)
    }
}

/** Real IPTV bootstrap for live-specific dock callers and guide ownership. */
internal open class TvPhase15LiveOriginalTest : TvPhase15OriginalTest() {
    override fun bootstrapPayload() = JSONObject().put("mode", "iptv").put("sourceId", "provider")
        .put("sourceName", "Provider").put("contentType", "live")
        .put("channels", JSONArray().put(JSONObject(mapOf("name" to "Alpha", "url" to "https://phase15.invalid/live.ts",
            "isLive" to true, "channelNumber" to 1, "sourceId" to "provider"))))
        .put("sources", JSONArray().put(JSONObject(mapOf("id" to "provider", "name" to "Provider", "type" to "xtream"))))
        .put("startIndex", 0)
}
