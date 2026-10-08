package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.widget.TextView
import com.debrify.app.MainActivity
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.Assert.*
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.TimeUnit

/** Typed original selectors. Binary callbacks retain their real inline/UI-queue semantics. */
internal open class TvPhase10OriginalTest : TvPhase9OriginalTest() {
    protected val function0 = kotlin.jvm.functions.Function0::class.java
    protected val function1 = kotlin.jvm.functions.Function1::class.java
    protected fun fetch(season: Int = 2, episode: Int = 5, auto: Boolean = false, suppress: Boolean = auto,
                        attempt: Any? = null, unavailable: (() -> Unit)? = null, continueIf: (() -> Boolean)? = null) =
        call("requestEpisodeFetch", arrayOf(intType, intType, boolType, boolType, attemptType, function0, function0),
            season, episode, auto, suppress, attempt, unavailable, continueIf)
    protected fun adjacent(imdb: String? = "tt12345", season: Int = 2, episode: Int = 4, auto: Boolean = false, direction: Int = 1) =
        call("requestAdjacentEpisodeFetch", arrayOf(stringType, intType, intType, boolType, intType), imdb, season, episode, auto, direction)
    protected fun more(mode: String = "packs") = call("requestMoreTorrentSources", arrayOf(stringType), mode)
    protected fun addon(group: String = "group") = call("requestAddonTorrentSources", arrayOf(stringType), group)
    protected fun monitor(extra: Long = 0, retry: Int = field("pikPakRetryId") as Int, callback: (Boolean) -> Unit) =
        call("waitForPikPakMetadata", arrayOf(PlaybackItem::class.java, intType, intType, longType, function1),
            model().items[0], 0, retry, extra, callback)
    protected fun loop(attemptNumber: Int = 0, retry: Int = field("pikPakRetryId") as Int) =
        gateHost("attemptPikPakPlaybackLoop", arrayOf(PlaybackItem::class.java, intType, intType), model().items[0], attemptNumber, retry)
    protected fun showPill(message: String = "message", transient: Boolean = false) =
        gateHost(if (transient) "showStatusPillTransient" else "showStatusPill", arrayOf(stringType), message)
    protected fun hidePill() = gateHost("hideStatusPill", emptyArray())
    protected fun pillHandler() = field("externalSubtitleHandler") as Handler
    protected fun lock() = field("episodeFetchInFlight") as Boolean
    protected fun loading() = field("moreSourcesLoadingMode")
    protected fun browserError() = TvPlayerOriginalAccess.field(browser(), "transientError")
    protected fun callback(kind: String = "success", value: Any? = null, queued: Boolean = false,
                           code: String = "error", requestIndex: Int = messenger.requests.lastIndex) {
        val request = messenger.requests[requestIndex]
        fun reply() {
            val buffer = when (kind) {
                "error" -> StandardMethodCodec.INSTANCE.encodeErrorEnvelope(code, "message", null)
                "missing" -> null
                else -> StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(value)
            }?.apply { flip() }
            request.reply!!.reply(buffer)
        }
        if (!queued) { reply(); return }
        val failure = AtomicReference<Throwable?>(); val thread = Thread { try { reply() } catch (e: Throwable) { failure.set(e) } }
        thread.start(); thread.join(TimeUnit.SECONDS.toMillis(5))
        assertFalse("binary callback worker completed", thread.isAlive)
        failure.get()?.let { throw AssertionError("binary callback worker failed", it) }
    }
    protected fun result(vararg extra: Pair<String, Any?>): Map<String, Any?> = mapOf(
        "items" to listOf(raw("Fetched", 2, 5)), "sourceIndex" to 0,
        "stremioSources" to listOf(mapOf("name" to "Fetched source", "stream_type" to "torrent")),
        "targetSeason" to 2, "targetEpisode" to 5, *extra)
    protected fun noChannel() = MainActivity.setAndroidTvPlayerChannel(null)
    protected fun finishing(value: Boolean) = ReflectionHelpers.setField(activity, "mFinished", value)
    protected fun destroyed(value: Boolean) = ReflectionHelpers.setField(activity, "mDestroyed", value)
    protected fun queuedCallbacks(handler: Handler): List<android.os.Message> {
        val result = mutableListOf<android.os.Message>()
        var message = ReflectionHelpers.getField<android.os.Message?>(Looper.getMainLooper().queue, "mMessages")
        while (message != null) {
            if (message.target === handler && message.callback != null) result.add(message)
            message = ReflectionHelpers.getField(message, "next")
        }
        return result
    }
    protected fun labels(): List<String> {
        fun read(v: android.view.View): List<String> = when (v) {
            is android.view.ViewGroup -> (0 until v.childCount).flatMap { read(v.getChildAt(it)) }
            is TextView -> listOf(v.text.toString())
            else -> emptyList()
        }
        return read(activity.findViewById(android.R.id.content))
    }
}
