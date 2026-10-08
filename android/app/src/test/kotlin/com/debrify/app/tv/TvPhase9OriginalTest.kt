package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.debrify.app.diagnostics.DiagnosticFileLog
import com.debrify.app.diagnostics.DiagnosticWorkQueue
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before

/** Original activity/borrowed switcher Host, real UI and queues; no production seam. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase9OriginalTest : TvPhase8OriginalTest() {
    protected var duration = 600_000L
    protected var buffered = 0L
    protected var durationReads = 0
    protected val gatePlayer: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,
        arrayOf(ExoPlayer::class.java)) { _, method, args ->
        when (method.name) {
            "getDuration", "getContentDuration" -> { durationReads++; duration }
            "getTotalBufferedDuration" -> buffered
            else -> method.invoke(probe.player, *(args ?: emptyArray()))
        }
    } as ExoPlayer
    private var logContext: Any? = null
    private var logAccepting: Any? = null
    protected val handler get() = field("progressHandler") as Handler
    protected fun view(name: String) = field(name) as android.view.View
    protected fun text(id: Int) = activity.findViewById<android.widget.TextView>(id)
    protected fun aio(i: Int = 0) = StremioSource.fromJson(JSONObject()
        .put("name", "AIO $i").put("stream_type", "directUrl").put("direct_url", "https://gate.invalid/$i")
        .put("stremio_addon_id", "org.aiostreams"), i)
    protected fun begin(tries: Int = 1) {
        set("startupTryNextOnFailure", tries > 1); set("startupMaxAttempts", tries)
        invoke("beginStartupFailoverIfEligible")
    }
    protected fun manual(i: Int = 1) = invoke("beginManualSourceCandidate", i)
    /** Public interface functions on the retained switcher Host; no internal gate reflection. */
    protected fun gateHost(name: String, types: Array<Class<*>>, vararg args: Any?): Any? {
        val host = TvPlayerOriginalAccess.field(field("sourceSwitchController")!!, "host")!!
        return TvPlayerOriginalAccess.callTyped(host, name, types, *args)
    }
    protected fun reject(reason: String = "test") =
        gateHost("failManualSourceCandidate", arrayOf(stringType), reason)
    protected fun fail(reason: String = "test") = resolveFailure(selected(), reason)
    protected fun resolveFailure(i: Int, reason: String = "resolve:test") =
        gateHost("failStartupResolution", arrayOf(intType, stringType), i, reason)
    protected fun arm(i: Int = 0) = gateHost("armStartupCandidate", arrayOf(intType), i)
    protected fun snapshot() = field("manualSourceSwitchSnapshot") as ManualSourceSwitchSnapshot
    protected fun selected() = field("currentStremioSourceIndex") as Int
    protected fun candidate() = field("startupFailoverCursor") as StartupFailoverCursor
    protected fun requestMap(name: String) = requests(name).last().call.arguments as Map<*, *>
    protected fun writer() = TvPlayerOriginalAccess.field(TvPlaybackRecoveryStore, "writer") as ExecutorService
    protected fun drainWriter() { writer().submit {}.get(5, TimeUnit.SECONDS) }
    protected fun diagnosticEvents(): List<JSONObject> {
        val latch = CountDownLatch(1)
        (TvPlayerOriginalAccess.field(DiagnosticFileLog, "executor") as DiagnosticWorkQueue).submit { latch.countDown() }
        assertTrue("diagnostics executor drained", latch.await(5, TimeUnit.SECONDS))
        return activity.filesDir.resolve("diagnostics").walkTopDown().filter { it.isFile && it.extension == "jsonl" }
            .flatMap { it.readLines().asSequence() }.filter { it.isNotBlank() }.map(::JSONObject).toList()
    }
    protected fun debugState() = "clock=${android.os.SystemClock.elapsedRealtime()} finishing=${activity.isFinishing} destroyed=${activity.isDestroyed} logs=" + org.robolectric.shadows.ShadowLog.getLogs().joinToString(" | ") { it.msg }
    protected fun immediateCallbacks(): Int {
        var message = org.robolectric.util.ReflectionHelpers.getField<android.os.Message?>(Looper.getMainLooper().queue, "mMessages")
        var found = 0
        while (message != null) {
            if (message.target === handler && message.callback != null && message.`when` <= android.os.SystemClock.uptimeMillis()) found++
            message = org.robolectric.util.ReflectionHelpers.getField(message, "next")
        }
        return found
    }
    protected fun lazyResolve() = call("resolveAndPlay", arrayOf(intType, PlaybackItem::class.java), 0, model().items[0])
    protected fun lazyReply(value: Any?) { messenger.success(value, index("requestTorrentStream")); tick(32) }
    @Before fun prepareGate() {
        set("player", gatePlayer); set("startupResolverProvider", "realdebrid")
        logContext = TvPlayerOriginalAccess.field(DiagnosticFileLog, "applicationContext")
        logAccepting = TvPlayerOriginalAccess.field(DiagnosticFileLog, "accepting")
        TvPlayerOriginalAccess.set(DiagnosticFileLog, "applicationContext", activity.applicationContext)
        TvPlayerOriginalAccess.set(DiagnosticFileLog, "accepting", true)
        diagnosticEvents(); activity.filesDir.resolve("diagnostics").deleteRecursively()
        drainWriter(); TvPlaybackRecoveryStore.clearMemoryCache()
    }
    @After fun cleanGate() {
        drainWriter(); diagnosticEvents()
        TvPlayerOriginalAccess.set(DiagnosticFileLog, "applicationContext", logContext)
        TvPlayerOriginalAccess.set(DiagnosticFileLog, "accepting", logAccepting)
    }
}
