package com.debrify.app.tv

import android.os.Handler
import android.view.KeyEvent
import android.view.View
import android.widget.TextView
import androidx.media3.exoplayer.ExoPlayer
import org.junit.Before
import org.junit.Assert.*
import java.lang.reflect.Proxy

/** Real per-skin dock, original entry points and an independently recorded player. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase16OriginalTest : TvPhase15OriginalTest() {
    protected var playIntent = true
    protected var buffered = 70_000L
    protected val reads = mutableListOf<String>()
    protected val floatType = Float::class.javaPrimitiveType!!
    private val runtimePlayer: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
        arrayOf(ExoPlayer::class.java)) { _, method, args ->
        when (method.name) {
            "getPlayWhenReady" -> { reads.add("intent"); playIntent }
            "setPlayWhenReady" -> { playIntent = args!![0] as Boolean; probe.events.add("intent:$playIntent"); null }
            "getBufferedPosition" -> { reads.add("buffered"); buffered }
            "getCurrentPosition" -> { reads.add("position"); probe.position }
            "getDuration" -> { reads.add("duration"); probe.duration }
            "pause" -> { playIntent = false; method.invoke(settingsPlayer) }
            "play" -> { playIntent = true; method.invoke(settingsPlayer) }
            else -> method.invoke(settingsPlayer, *(args ?: emptyArray()))
        }
    } as ExoPlayer

    @Before fun prepareControlsRuntime() {
        set("player", runtimePlayer)
        for (name in listOf("controlsHandler", "seekbarHandler", "progressHandler"))
            (field(name) as Handler).removeCallbacksAndMessages(null)
        set("controlsMenuVisible", false); set("cinemaSeekMode", false); set("seekbarVisible", false)
        v("controlsOverlay").animate().cancel(); v("controlsOverlay").visibility = View.GONE
        v("nextOverlay").animate().cancel(); v("nextOverlay").visibility = View.GONE
        v("pikPakReactivationIndicator").visibility = View.GONE
        v("seekbarOverlay").visibility = View.GONE
        v("titleContainer").animate().cancel(); v("titleContainer").visibility = View.GONE
        layout()
        activity.window.decorView.clearFocus()
        probe.playing = true; playIntent = true; probe.position = 25_000L; probe.duration = 100_000L
        probe.events.clear(); reads.clear()
    }
    protected fun v(name: String) = field(name) as View
    protected fun tv(name: String) = field(name) as TextView
    protected fun runOriginal(name: String, vararg args: Any): Any? = invoke(name, *args)
    protected fun showDock() = runOriginal("showControlsMenu")
    protected fun hideDock() = runOriginal("hideControlsMenu")
    protected fun enterScrub() = runOriginal("enterCinemaSeekMode")
    protected fun exitScrub(confirm: Boolean = false) = runOriginal("exitCinemaSeekMode", confirm)
    protected fun drawScrub(position: Long = 50_000L, duration: Long = 100_000L, width: Int = 1000) {
        set("cinemaSeekMode", true); set("seekbarPosition", position); set("videoDuration", duration)
        set("cinemaProgressTrackWidth", width); set("cinemaLastAnimatedProgress", 0.25f)
        runOriginal("updateCinemaProgressUI")
    }
    protected fun step(ms: Long) = TvControlsAnimationClock.advance(ms)
    protected fun pauseOffers(): MutableList<String> {
        val offers = mutableListOf<String>()
        val pause = object : androidx.appcompat.widget.AppCompatButton(activity) {
            override fun requestFocus(direction: Int, rect: android.graphics.Rect?): Boolean {
                offers.add("pause"); return super.requestFocus(direction, rect)
            }
        }
        (v("controlsOverlay") as android.view.ViewGroup).addView(pause); set("pauseButton", pause)
        return offers
    }
    protected fun beginRotation(name: String): Float {
        val view = v(name); view.animate().cancel(); view.rotation = 0f
        view.animate().rotation(90f).setDuration(1000).setInterpolator(android.view.animation.LinearInterpolator()).start()
        step(20); assertTrue(view.rotation > 0f); return view.rotation
    }
    protected fun frozenRotation(name: String, expected: Float) = assertEquals("prior animation cancelled: $name", expected, v(name).rotation, 0.01f)
    protected fun autoHidePending() = TvPlaylistUiQueue.pending(field("controlsHandler") as Handler, field("hideControlsRunnable") as Runnable)
    protected fun tickerPending() = TvPlaylistUiQueue.pending(field("seekbarHandler") as Handler, field("seekbarProgressRunnable") as Runnable)
    protected fun dispatch(code: Int, action: Int = KeyEvent.ACTION_DOWN, repeat: Int = 0): Boolean =
        activity.dispatchKeyEvent(KeyEvent(0, 0, action, code, repeat))
    protected fun originalPlayer() { set("player", runtimePlayer) }
    protected fun keyListener(view: View): View.OnKeyListener {
        val info = View::class.java.getDeclaredField("mListenerInfo").apply { isAccessible = true }.get(view)
        assertNotNull("original setup installs listener storage", info)
        val listener = TvPlayerOriginalAccess.field(info!!, "mOnKeyListener")
        assertNotNull("original setup installs the key listener", listener)
        return listener as View.OnKeyListener
    }
    protected fun seekEvents() = probe.events.filter { it.startsWith("seek:") }
}
