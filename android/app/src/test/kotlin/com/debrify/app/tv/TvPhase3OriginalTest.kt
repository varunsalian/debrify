package com.debrify.app.tv

import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import org.junit.After
import org.robolectric.Shadows.shadowOf
import java.lang.reflect.Proxy

/** Shared setup only; observations go through the original activity's real methods. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase3OriginalTest : TvPhase2OriginalTest() {
    protected fun field(name: String): Any? = TvPlayerOriginalAccess.field(activity, name)
    protected fun set(name: String, value: Any?) = TvPlayerOriginalAccess.set(activity, name, value)
    protected fun invoke(name: String, vararg args: Any): Any? = call(name, args.map {
        when (it) {
            is Int -> intType
            is Long -> longType
            is Boolean -> boolType
            else -> it.javaClass
        }
    }.toTypedArray(), *args)
    protected fun idle() = shadowOf(Looper.getMainLooper()).idle()
    protected fun advance(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(ms))

    protected fun bindViews(): FrameLayout {
        activity.setTheme(androidx.appcompat.R.style.Theme_AppCompat)
        return FrameLayout(activity).also { root ->
            activity.setContentView(root)
            fun bind(name: String, view: View) { set(name, view); root.addView(view) }
            bind("playerView", PlayerView(activity).apply { isFocusable = true })
            bind("upNextCard", FrameLayout(activity).apply { visibility = View.GONE })
            bind("upNextPoster", ImageView(activity))
            bind("upNextTitle", TextView(activity))
            bind("upNextCountdown", TextView(activity))
            bind("skipSegmentButton", AppCompatButton(activity).apply { visibility = View.GONE; isFocusable = true })
            bind("nextOverlay", View(activity).apply { visibility = View.GONE })
            bind("pikPakReactivationIndicator", View(activity).apply { visibility = View.GONE })
            bind("bufferingIndicator", FrameLayout(activity).apply { visibility = View.GONE })
        }
    }

    protected fun series(episode: Int = 1, duration: Long = 600_000L): PlaybackPayload = PlaybackPayload(
        "Show", null, "series", mutableListOf(p2Item("First", season = 0, episode = episode),
            p2Item("Second", season = 1, episode = episode + 1)), 0, "Show", imdbId = "  tt12345  ",
    ).also {
        set("payload", it); set("currentIndex", 0); set("skipSegmentsEnabled", true)
        set("skipSegmentProviderId", TvSkipSegmentClients.SKIP_DB)
        set("player", PlayerProbe(duration = duration).player)
        set("hasEverBeenReady", true)
    }

    @After fun removeOwnedWork() {
        invoke("cancelSleepTimer", false)
        (field("upNextHandler") as android.os.Handler).removeCallbacksAndMessages(null)
        (field("skipSegmentScope") as kotlinx.coroutines.CoroutineScope).coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class PlayerProbe(var position: Long = 0L, var duration: Long = 600_000L,
                           var state: Int = Player.STATE_READY, var playing: Boolean = true) {
    val events = mutableListOf<String>()
    var onPause: (() -> Unit)? = null
    val player: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
        arrayOf(ExoPlayer::class.java)) { proxy, method, args ->
        when (method.name) {
            "getCurrentPosition", "getContentPosition" -> position
            "getDuration", "getContentDuration" -> duration
            "getPlaybackState" -> state
            "isPlaying", "getPlayWhenReady" -> playing
            "pause" -> { onPause?.invoke(); events.add("pause"); playing = false; null }
            "seekTo" -> { position = args!![args.lastIndex] as Long; events.add("seek:$position"); null }
            "release" -> { events.add("release"); null }
            "getApplicationLooper" -> Looper.getMainLooper()
            "getCurrentTracks" -> androidx.media3.common.Tracks.EMPTY
            "getVideoSize" -> androidx.media3.common.VideoSize.UNKNOWN
            "getAvailableCommands" -> Player.Commands.EMPTY
            "toString" -> "PlayerProbe"
            "hashCode" -> System.identityHashCode(proxy)
            "equals" -> proxy === args?.firstOrNull()
            else -> when (method.returnType) {
                java.lang.Boolean.TYPE -> false
                java.lang.Integer.TYPE -> 0
                java.lang.Long.TYPE -> 0L
                java.lang.Float.TYPE -> 0f
                java.lang.Double.TYPE -> 0.0
                else -> null
            }
        }
    } as ExoPlayer
}
