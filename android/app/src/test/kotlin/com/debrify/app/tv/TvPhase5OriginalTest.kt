package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.debrify.app.MainActivity
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

/** No new production seam: real original methods, binary replies and writer executor. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal open class TvPhase5OriginalTest : TvPhase3OriginalTest() {
    protected val messenger = TvPlayerRecordingMessenger()
    private var previous: MethodChannel? = null
    protected val probe = TvPhase5PlayerProbe()
    private val barriers = mutableListOf<WriterBarrier>()
    private val writer: ExecutorService get() = TvPlaybackRecoveryStore::class.java
        .getDeclaredField("writer").apply { isAccessible = true }.get(TvPlaybackRecoveryStore) as ExecutorService

    @Before fun preparePhase5() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(true)
        activity.getSharedPreferences("FlutterSharedPreferences", 0).edit().clear().commit()
        set("playerPreferences", com.debrify.app.profiles.NativePlayerPreferences.fromIntent(activity, activity.intent))
        previous = MainActivity.getAndroidTvPlayerChannel()
        MainActivity.setAndroidTvPlayerChannel(MethodChannel(messenger, "com.debrify.app/android_tv_player"))
        drainWriter()
        java.io.File(activity.filesDir, "tv_playback_recovery.json").delete()
        java.io.File(activity.filesDir, "tv_playback_recovery.json.tmp").delete()
        TvPlaybackRecoveryStore.clearMemoryCache()
        bindViews().also { root ->
            for (name in listOf("titleView", "iptvStartOverButton", "iptvStartOverSeekButton")) {
                val view = if (name == "titleView") TextView(activity) else AppCompatButton(activity)
                set(name, view); root.addView(view)
            }
        }
        set("player", probe.player)
        val session = TvPlaybackRecoveryStore.allocateSessionId(activity.filesDir)
        TvPlaybackRecoveryStore.begin(activity.filesDir, session)
        set("sourcePersistenceSessionId", session)
        set("recoveryProfileId", "phase5-owner"); set("recoveryDataGeneration", 3)
        set("recoveryTitle", "Film"); set("recoverySeriesTitle", "Show"); set("recoveryImdbId", "tt5")
    }

    protected fun createLifecycle() {
        activity.intent.putExtra("playbackSessionId", field("sourcePersistenceSessionId") as Int)
        lifecycle.create().start().resume()
        messenger.requests.clear(); probe.events.clear(); set("player", probe.player)
    }
    protected fun drainWriter() { writer.submit {}.get(5, TimeUnit.SECONDS) }
    protected inner class WriterBarrier {
        private val entered = CountDownLatch(1)
        private val release = CountDownLatch(1)
        private val task = writer.submit {
            entered.countDown()
            check(release.await(5, TimeUnit.SECONDS)) { "bounded recovery writer barrier timed out" }
        }
        init { assertTrue("separate recovery writer entered", entered.await(5, TimeUnit.SECONDS)) }
        fun close() { release.countDown(); task.get(5, TimeUnit.SECONDS) }
    }
    protected fun blockWriter() = WriterBarrier().also { barriers.add(it) }
    protected fun journal(): JSONObject? = TvPlaybackRecoveryStore.read(activity.filesDir)?.let(::JSONObject)
    protected fun requireJournal(): JSONObject {
        val value = journal(); assertNotNull("recovery checkpoint persisted", value); return value!!
    }
    protected fun progress(): Map<*, *> = requests("torrentPlaybackProgress").last().call.arguments as Map<*, *>
    protected fun requests(method: String) = messenger.requests.filter { it.call.method == method }
    protected fun requestIndex(method: String) = messenger.requests.indexOfLast { it.call.method == method }
    protected fun movie(type: String = "single", local: Boolean = false): PlaybackPayload = PlaybackPayload(
        "Film", null, type, mutableListOf(p2Item(season = if (type == "series") 2 else null,
            episode = if (type == "series") 4 else null)), 0, "Show",
        localCompletionTracking = local, movieCompletionThreshold = 80, episodeCompletionThreshold = 90,
    ).also { set("payload", it); set("currentIndex", 0) }
    protected fun iptv(entry: IptvChannelEntry = channel()): IptvChannelEntry = entry.also {
        set("isIptvMode", true); set("iptvChannels", mutableListOf(it)); set("currentIptvIndex", 0)
    }
    protected fun channel(url: String = "https://phase5.invalid/live.ts", live: Boolean = true) =
        IptvChannelEntry(index = 0, channelNumber = 7, name = "Cinema", url = url,
            logoUrl = "https://phase5.invalid/logo", group = "Movies", isLive = live, isCurrent = true,
            sourceId = "playlist", sourceName = "Source", httpHeaders = mapOf("X-Test" to "header"),
            resumePositionMs = 12_345L, seriesId = "series", seriesName = "Show", season = 2, episode = 4,
            hasNextEpisode = true, tvArchive = "1", tvArchiveDuration = 3)
    protected fun programme(airing: Boolean = true): IptvEpgProgram {
        val now = System.currentTimeMillis()
        return IptvEpgProgram("Programme", "Description", now - 60_000, if (airing) now + 60_000 else now - 1, true)
    }
    protected fun catchup(entry: IptvChannelEntry, programme: IptvEpgProgram, controls: Boolean = false) =
        call("requestIptvCatchup", arrayOf(IptvChannelEntry::class.java, IptvEpgProgram::class.java, boolType), entry, programme, controls)
    protected fun resolve(vararg urls: String) {
        messenger.success(mapOf("candidates" to urls.mapIndexed { i, url -> mapOf("url" to url, "label" to "${i + 1} 1080p") }), requestIndex("requestIptvStreamUrls")); idle()
    }
    protected fun tuning() = probe.events.filter { it.startsWith("media:") }
    protected fun button() = field("iptvStartOverButton") as AppCompatButton
    protected fun seekButton() = field("iptvStartOverSeekButton") as AppCompatButton

    @After fun cleanPhase5() {
        barriers.forEach { it.close() }; drainWriter()
        (invoke("getIptvRecordingController") as IptvRecordingController).abortAndDelete()
        MainActivity.setAndroidTvPlayerChannel(previous)
        for (name in listOf("progressHandler", "iptvBrowseHandler", "externalSubtitleHandler", "controlsHandler", "seekbarHandler", "focusRecoveryHandler", "bufferingHandler"))
            (field(name) as Handler).removeCallbacksAndMessages(null)
        for (name in listOf("subtitleScope", "mediaPreparationScope"))
            (field(name) as CoroutineScope).coroutineContext[Job]?.cancel()
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
    }
}

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvPhase5PlayerProbe(var position: Long = 25_000L, var duration: Long = 100_000L,
                                  var state: Int = Player.STATE_READY, var playing: Boolean = true) {
    // Phase 17 opts in; all older fixtures retain their original fake semantics.
    var extended = false
    var playIntent = true
    var videoFormat: androidx.media3.common.Format? = null
    var counters = androidx.media3.exoplayer.DecoderCounters()
    val mediaItems = mutableListOf<MediaItem>()
    val events = mutableListOf<String>()
    var failPosition = false
    var error: androidx.media3.exoplayer.ExoPlaybackException? = null
    var onEvent: ((String) -> Unit)? = null
    val player: ExoPlayer = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { proxy, method, args ->
        fun event(text: String) { onEvent?.invoke(text); events.add(text) }
        when (method.name) {
            "getCurrentPosition", "getContentPosition" -> { if (failPosition) throw IllegalStateException("phase5 player read failed"); position }
            "getDuration", "getContentDuration" -> duration
            "getPlaybackState" -> state
            "getPlayerError" -> error
            "isPlaying" -> playing
            "getPlayWhenReady" -> if (extended) playIntent else playing
            "setPlayWhenReady" -> { if (extended) { playIntent = args!![0] as Boolean; event("intent:$playIntent") }; null }
            "getVideoFormat" -> if (extended) videoFormat else null
            "getVideoDecoderCounters" -> if (extended) counters else null
            "pause" -> { event("pause"); playing = false; if (extended) playIntent = false; null }
            "play" -> { event("play"); playing = true; if (extended) playIntent = true; null }
            "stop" -> { event("stop"); state = Player.STATE_IDLE; null }
            "prepare" -> { event("prepare"); null }
            "release" -> { event("release"); null }
            "setMediaItem" -> { if (extended) mediaItems.add(args!![0] as MediaItem); event("media:" + (args!![0] as MediaItem).localConfiguration!!.uri + if (args.size > 1) ":${args[1]}" else ""); null }
            "seekToDefaultPosition" -> { if (extended) event("seek-default"); null }
            "getApplicationLooper" -> Looper.getMainLooper()
            "getCurrentTracks" -> androidx.media3.common.Tracks.EMPTY
            "getVideoSize" -> androidx.media3.common.VideoSize.UNKNOWN
            "getAvailableCommands" -> Player.Commands.EMPTY
            "toString" -> "TvPhase5PlayerProbe"
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
