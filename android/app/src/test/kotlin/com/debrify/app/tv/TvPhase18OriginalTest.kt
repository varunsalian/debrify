package com.debrify.app.tv

import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.MediaItem
import com.debrify.app.MainActivity
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import org.junit.Assert.*
import org.junit.Before
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.coroutines.CoroutineContext

/** Production original bodies, binary replies and real view/player observations. */
@org.robolectric.annotation.Config(instrumentedPackages = [
    "com.debrify.app.tv.TvPlaybackStartController",
    "com.debrify.app.tv.TvPlaybackNavigator",
])
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase18OriginalTest : TvPhase8OriginalTest() {
    protected val functionType = kotlin.jvm.functions.Function1::class.java
    protected val setType = Set::class.java
    @Before fun preparePlaybackStart() {
        set("hasPlaylistResolver", false); set("hasAdjacentEpisodeResolver", false)
        set("isIptvMode", false); set("isStremioTvMode", false)
        set("startupFailoverCursor", null); set("manualSourceSwitchIndex", null)
        set("manualSourceSwitchSnapshot", null); set("isAutoAdvancing", false)
        set("sleepStopLatched", false); set("continuousShuffleEnabled", false)
        set("pendingShufflePlayback", null); set("queuedShuffleGeneration", null)
        set("queuedShuffleNavigation", null); set("customShuffleEpisodes", null)
        set("playlistMode", PlaylistMode.NONE)
        set("episodeFetchInFlight", false)
        set("userManuallySelectedSubtitle", true)
        set("subtitleAddonDiscoveryReady", false)
        set("iptvPrevButton", AppCompatButton(activity).apply { visibility = View.INVISIBLE })
        for (name in listOf("progressHandler", "externalSubtitleHandler"))
            (field(name) as android.os.Handler).removeCallbacksAndMessages(null)
        TvPlaylistUiQueue.attach(activity.findViewById(android.R.id.content))
        messenger.requests.clear(); probe.events.clear(); probe.media.clear()
        org.robolectric.shadows.ShadowToast.reset()
    }
    protected fun pump(ms: Long = 0) = TvPlaylistUiQueue.advance(ms)
    protected fun play(index: Int = 0, suppressTrakt: Boolean = false, suppressResume: Boolean = false, attempt: Any? = null) =
        call("playItem", arrayOf(intType, boolType, boolType, attemptType), index, suppressTrakt, suppressResume, attempt)
    protected fun playDefaults(index: Int = 0, mask: Int = 14, suppressTrakt: Boolean = true, suppressResume: Boolean = true, attempt: Any? = null) =
        defaultCall("playItem", arrayOf(intType, boolType, boolType, attemptType), mask, index, suppressTrakt, suppressResume, attempt)
    protected fun start(item: PlaybackItem = model().items[0], discovered: Boolean = false) =
        call("startPlayback", arrayOf(PlaybackItem::class.java, boolType), item, discovered)
    protected fun directItem(item: PlaybackItem = model().items[0]) = call("playMediaDirect", arrayOf(PlaybackItem::class.java), item)
    protected fun pikpak(item: PlaybackItem = model().items[0]) = call("playPikPakVideoWithRetry", arrayOf(PlaybackItem::class.java), item)
    protected fun shuffle(attempted: Set<ShuffleEpisode> = emptySet(), automatic: Boolean = false) =
        call("playShowShuffle", arrayOf(setType, boolType), attempted, automatic) as Boolean
    protected fun attemptWith(navigation: Int = field("mediaPreparationGeneration") as Int,
        generation: Int = field("showShuffleGeneration") as Int, automatic: Boolean = false,
        unavailable: () -> Unit = {}, started: Boolean = false, restore: (() -> Unit)? = null, finished: Boolean = false): Any =
        attemptType.declaredConstructors.single { it.parameterCount == 7 }.apply { isAccessible = true }
            .newInstance(navigation, generation, automatic, unavailable, started, restore, finished)
    protected fun setAttempt(attempt: Any, name: String, value: Any?) = TvPlayerOriginalAccess.set(attempt, name, value)
    protected fun readiness() = field("subtitleTrackReadiness") as SubtitleTrackReadiness
    protected fun title() = (field("titleView") as TextView).text.toString()
    protected fun item(index: Int = 0) = model().items[index]
    protected fun payload(vararg items: PlaybackItem, type: String = "single", imdb: String? = null) =
        PlaybackPayload("Payload title", "Payload subtitle", type, items.toMutableList(), 0, "Series", imdbId = imdb).also {
            set("payload", it); set("currentIndex", 0)
        }
    protected fun guide(season: Int, episode: Int, eligible: Boolean = true) = GuideEpisode(
        eligible, season, episode, "Episode $season/$episode", null, null, null, null, null, null, null, false)
    protected fun wholeShow(vararg episodes: ShuffleEpisode) {
        set("hasPlaylistResolver", true)
        model().contentType = "series"
        model().guideEpisodes.clear()
        model().guideEpisodes.addAll(episodes.map { guide(it.season, it.episode) })
    }
    protected fun dockCall(name: String): Any? {
        val host = TvPlayerOriginalAccess.field(field("controlsDockController")!!, "host")!!
        return TvPlayerOriginalAccess.callTyped(host, name, emptyArray())
    }
    protected fun sourceHost(name: String, types: Array<Class<*>>, vararg args: Any?): Any? {
        val host = TvPlayerOriginalAccess.field(field("sourceSwitchController")!!, "host")!!
        return TvPlayerOriginalAccess.callTyped(host, name, types, *args)
    }
    protected fun discover(url: String, headers: Map<String, String>, ready: (String?) -> Unit) =
        sourceHost("discoverProtectedMime", arrayOf(stringType, mapType, functionType), url, headers, ready)
    protected fun merged(video: String, audio: String) = sourceHost("buildMergedSource", arrayOf(stringType, stringType), video, audio)
    protected fun request(method: String): TvPlayerRecordingMessenger.Request {
        assertTrue("expected production request $method", requests(method).isNotEmpty())
        return requests(method).last()
    }
    protected fun replyDirect(value: Any?, request: TvPlayerRecordingMessenger.Request = request("requestTorrentStream")) {
        request.reply!!.reply(StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(value).apply { flip() })
    }
    protected fun finishing(value: Boolean) = ReflectionHelpers.setField(activity, "mFinished", value)
    protected fun destroyed(value: Boolean) = ReflectionHelpers.setField(activity, "mDestroyed", value)
    protected fun lastToast() = org.robolectric.shadows.ShadowToast.getTextOfLatestToast()
    protected fun pendingScope() = field("mediaPreparationScope") as CoroutineScope
    protected fun logs() = org.robolectric.shadows.ShadowLog.getLogs().filter { it.tag == "AndroidTvPlayer" }.map { it.msg }
    protected fun clearObservations() {
        messenger.requests.clear(); probe.media.clear(); probe.events.clear()
        org.robolectric.shadows.ShadowLog.clear(); org.robolectric.shadows.ShadowToast.reset()
    }
}

/** IO stays real; only Main dispatch is queued, and each continuation runs on the test's Main thread. */
internal class TvPhase18MainBarrier : CoroutineDispatcher() {
    private val queue = LinkedBlockingQueue<Runnable>()
    override fun dispatch(context: CoroutineContext, block: Runnable) { queue.add(block) }
    fun next(): Runnable {
        val task = queue.poll(5, TimeUnit.SECONDS)
        assertNotNull("bounded coroutine continuation reached Main barrier", task)
        return task!!
    }
    fun step() { assertEquals(Looper.getMainLooper(), Looper.myLooper()); next().run() }
    fun scope() = CoroutineScope(this + SupervisorJob())
}
