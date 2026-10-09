package com.debrify.app.tv

import android.content.Context
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import org.json.JSONObject
import java.lang.reflect.InvocationTargetException
import android.graphics.drawable.Drawable
import android.widget.ImageView
import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.request.target.DrawableImageViewTarget

/** Only this helper knows the original private JVM names/constructor order.
 * Move commits retarget this helper; the behavioural assertions stay unchanged.
 */
internal object TvPlayerOriginalAccess {
    private val movedFunctions = mapOf(
        "adoptIptvEpg" to "IptvEntryRulesKt",
        "androidDecoderStatus" to "TvStartupDiagnosticsKt",
        "buildAudioTrackLabel" to "TvTrackLabelsKt",
        "buildManualSubtitleDisplayLabel" to "SubtitleSearchQueryKt",
        "buildNowPlayingText" to "StremioTvGuideDataKt",
        "buildProtectedMediaOrigins" to "TvStartupDiagnosticsKt",
        "buildSubtitleSearchInitialQuery" to "SubtitleSearchQueryKt",
        "buildSubtitleTrackLabel" to "TvTrackLabelsKt",
        "classifyIptvError" to "IptvLoadErrorPolicyKt",
        "currentIptvStartOverProgramme" to "IptvEntryRulesKt",
        "diagnosticProvider" to "TvStartupDiagnosticsKt",
        "formatIptvRemaining" to "IptvEntryRulesKt",
        "formatTime" to "TvPlayerFormattingKt",
        "getAcceleratedSeekStep" to "TvPlayerFormattingKt",
        "iptvChannelEntry" to "IptvPayloadParsingKt",
        "iptvQualityFromLabel" to "IptvEntryRulesKt",
        "isExternalSubtitleOption" to "TvTrackLabelsKt",
        "isIptvSeriesSentinel" to "IptvEntryRulesKt",
        "isLoadingSubtitleOption" to "TvTrackLabelsKt",
        "isPikPakPlaybackItem" to "TvStartupDiagnosticsKt",
        "isSearchSubtitleOption" to "TvTrackLabelsKt",
        "isSegmentedStreamUrl" to "IptvRecordingUrlRulesKt",
        "isSideRenderableSubtitle" to "TvTrackLabelsKt",
        "isStremioIptvUrl" to "IptvEntryRulesKt",
        "languageOfOverride" to "TvTrackLabelsKt",
        "mrow" to "UnifiedMenuRowsKt",
        "originKey" to "TvStartupDiagnosticsKt",
        "parseIptvChannels" to "IptvPayloadParsingKt",
        "parseIptvLists" to "IptvPayloadParsingKt",
        "parseIptvSources" to "IptvPayloadParsingKt",
        "parseSeasonEpisodeFromTitle" to "SubtitleSearchQueryKt",
        "parseStringList" to "IptvPayloadParsingKt",
        "parseSubtitleCatalogResults" to "SubtitleSearchQueryKt",
        "rebuildNavigationMaps" to "PlaylistNavigationMapsKt",
        "recordingTimestamp" to "IptvRecordingUrlRulesKt",
        "reportIptvStreamResult" to "TvPlayerFlutterRequestsKt",
        "requestIptvEpg" to "TvPlayerFlutterRequestsKt",
        "requestIptvStreamUrls" to "TvPlayerFlutterRequestsKt",
        "requestMovieMetadataFromFlutter" to "TvPlayerFlutterRequestsKt",
        "requestQuickPlayNextEpisode" to "TvPlayerFlutterRequestsKt",
        "requestStreamFromFlutter" to "TvPlayerFlutterRequestsKt",
        "resolveSeasonEpisodeForSubtitle" to "SubtitleSearchQueryKt",
        "sanitizeRecordingName" to "IptvRecordingUrlRulesKt",
        "spellNumber" to "TvPlayerFormattingKt",
        "startupLog" to "TvStartupDiagnosticsKt",
        "updateStremioTvGuideChannelData" to "StremioTvGuideDataKt",
        "xtreamTsTwin" to "IptvRecordingUrlRulesKt",
    )

    private val controllerOwners = TvPlayerControllerOwners.routes

    fun isStartupArm(frame: StackTraceElement): Boolean =
        frame.className == TvStartupGateController::class.java.name &&
            frame.methodName.substringBefore('$') == "armStartupCandidate"

    private fun memberOwner(owner: Any, name: String): Any {
        if (owner !is AndroidTvTorrentPlayerActivity) return owner
        val controller = controllerOwners[name.removeSuffix("\$delegate")] ?: return owner
        // Routes are installed before extraction; the original still owns this phase's members.
        if (controller.startsWith("controlsOverlayController") &&
            owner.javaClass.declaredFields.none { it.name == "controlsOverlayController" }) return owner
        return controller.split('.').fold(owner as Any) { current, field ->
            current.javaClass.getDeclaredField(field).apply { isAccessible = true }.get(current)!!
        }
    }

    fun type(name: String): Class<*> = Class.forName(
        "com.debrify.app.tv." + when (name) {
            "AndroidTvTorrentPlayerActivity\$IptvStremioCandidate" -> "IptvStremioCandidate"
            "AndroidTvTorrentPlayerActivity\$SleepTimerMode" -> "SleepTimerMode"
            "AndroidTvTorrentPlayerActivity\$SkipSegmentRequest" -> "SkipSegmentRequest"
            else -> name
        },
    )

    fun construct(name: String, vararg arguments: Any?): Any {
        val constructor = type(name).declaredConstructors.single {
            !it.isSynthetic && it.parameterCount == arguments.size
        }
        constructor.isAccessible = true
        return unwrap { constructor.newInstance(*arguments) }
    }

    fun call(owner: Any, name: String, vararg arguments: Any?): Any? {
        val actualOwner = memberOwner(owner, name)
        val method = actualOwner.javaClass.declaredMethods.single {
            it.name == name && it.parameterCount == arguments.size && !it.isBridge
        }
        method.isAccessible = true
        return unwrap { method.invoke(actualOwner, *arguments) }
    }

    /** Exact JVM signatures keep same-arity overloads distinct. */
    @Suppress("UNCHECKED_CAST")
    fun callTyped(owner: Any, name: String, types: Array<Class<*>>, vararg arguments: Any?): Any? {
        if (owner is AndroidTvTorrentPlayerActivity) {
            val fetchNames = setOf("requestEpisodeFetch", "requestAdjacentEpisodeFetch", "requestMoreTorrentSources", "requestAddonTorrentSources")
            if (name in fetchNames) {
                val fetch = field(owner, "sourceFetchController") as TvSourceFetchController
                when (name) {
                    "requestEpisodeFetch" -> fetch.requestEpisodeFetch(
                        arguments[0] as Int, arguments[1] as Int, arguments[2] as Boolean, arguments[3] as Boolean,
                        arguments[4] as AndroidTvTorrentPlayerActivity.ShufflePlaybackAttempt?,
                        arguments[5] as (() -> Unit)?, arguments[6] as (() -> Boolean)?)
                    "requestAdjacentEpisodeFetch" -> fetch.requestAdjacentEpisodeFetch(
                        arguments[0] as String?, arguments[1] as Int, arguments[2] as Int,
                        arguments[3] as Boolean, arguments[4] as Int)
                    "requestMoreTorrentSources" -> fetch.requestMoreTorrentSources(arguments[0] as String)
                    "requestAddonTorrentSources" -> fetch.requestAddonTorrentSources(arguments[0] as String)
                }
                return Unit
            }
        }
        val facade = if (owner is AndroidTvTorrentPlayerActivity) movedFunctions[name]?.let(::type) else null
        val actualOwner = memberOwner(owner, name)
        val method = (facade ?: actualOwner.javaClass).getDeclaredMethod(name, *types).apply { isAccessible = true }
        return unwrap { method.invoke(if (facade == null) actualOwner else null, *arguments) }
    }

    fun constructTyped(name: String, types: Array<Class<*>>, vararg arguments: Any?): Any {
        if (name == "AndroidTvTorrentPlayerActivity\$IptvLiveLoadErrorPolicy") {
            check(types.contentEquals(arrayOf(AndroidTvTorrentPlayerActivity::class.java)))
            return movedPolicy(arguments.single() as AndroidTvTorrentPlayerActivity)
        }
        val constructor = type(name).getDeclaredConstructor(*types).apply { isAccessible = true }
        return unwrap { constructor.newInstance(*arguments) }
    }

    /** Invoke Kotlin's real omitted-argument dispatcher, including its mask. */
    fun callDefault(owner: Any, name: String, types: Array<Class<*>>, mask: Int, vararg arguments: Any?): Any? {
        if (owner is AndroidTvTorrentPlayerActivity && name == "requestEpisodeFetch") {
            check(mask == 120)
            val fetch = field(owner, "sourceFetchController") as TvSourceFetchController
            return fetch.requestEpisodeFetch(arguments[0] as Int, arguments[1] as Int, autoAdvance = arguments[2] as Boolean)
        }
        if (owner is AndroidTvTorrentPlayerActivity && name == "requestAdjacentEpisodeFetch") {
            check(mask == 24)
            val fetch = field(owner, "sourceFetchController") as TvSourceFetchController
            return fetch.requestAdjacentEpisodeFetch(arguments[0] as String?, arguments[1] as Int, arguments[2] as Int)
        }
        val facade = if (owner is AndroidTvTorrentPlayerActivity) movedFunctions[name]?.let(::type) else null
        val actualOwner = memberOwner(owner, name)
        val receiverTypes = if (facade == null) arrayOf(actualOwner.javaClass) else emptyArray()
        val receiver = if (facade == null) arrayOf(actualOwner) else emptyArray()
        val method = (facade ?: actualOwner.javaClass).getDeclaredMethod(
            name + "\$default", *receiverTypes, *types, Int::class.javaPrimitiveType, Any::class.java,
        ).apply { isAccessible = true }
        return unwrap { method.invoke(null, *receiver, *arguments, mask, null) }
    }

    /** Retarget the former inner constructor without snapshotting its activity. */
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun movedPolicy(activity: AndroidTvTorrentPlayerActivity): Any {
        val invokingThreads = mutableListOf<Thread>()
        val liveNow = {
            invokingThreads.add(Thread.currentThread())
            val entries = field(activity, "iptvChannels") as List<*>
            val index = field(activity, "currentIptvIndex") as Int
            (entries.getOrNull(index) as IptvChannelEntry?)?.isLive == true
        }
        val policy = type("IptvLiveLoadErrorPolicy").getDeclaredConstructor(kotlin.jvm.functions.Function0::class.java)
            .apply { isAccessible = true }.newInstance(liveNow) as androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
        org.junit.Assert.assertTrue("supplier must not run at construction", invokingThreads.isEmpty())
        val probe = java.util.concurrent.FutureTask<Unit> {
            policy.getMinimumLoadableRetryCount(androidx.media3.common.C.DATA_TYPE_MEDIA)
            val spec = androidx.media3.datasource.DataSpec(android.net.Uri.parse("https://example.test/probe"))
            policy.getRetryDelayMsFor(androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy.LoadErrorInfo(
                androidx.media3.exoplayer.source.LoadEventInfo(1, spec, 0L),
                androidx.media3.exoplayer.source.MediaLoadData(androidx.media3.common.C.DATA_TYPE_MEDIA),
                java.io.IOException("probe"), 1,
            ))
        }
        val invokingThread = Thread(probe, "policy-supplier-test")
        invokingThread.start()
        probe.get(5, java.util.concurrent.TimeUnit.SECONDS)
        org.junit.Assert.assertEquals("both methods invoke the supplier", 2, invokingThreads.size)
        invokingThreads.forEach { org.junit.Assert.assertSame("supplier runs on the invoking thread", invokingThread, it) }
        return policy
    }

    private fun <T> unwrap(action: () -> T): T = try {
        action()
    } catch (error: InvocationTargetException) {
        throw error.targetException
    }

    fun get(owner: Any, name: String): Any? {
        val getter = if (name.startsWith("is")) name else "get" + name.replaceFirstChar { it.uppercase() }
        return call(owner, getter)
    }

    fun field(owner: Any, name: String): Any? {
        val actualOwner = memberOwner(owner, name)
        return actualOwner.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(actualOwner)
    }

    fun glideTracks(manager: com.bumptech.glide.RequestManager, request: com.bumptech.glide.request.Request): Boolean {
        val tracker = com.bumptech.glide.RequestManager::class.java.getDeclaredField("requestTracker")
            .apply { isAccessible = true }.get(manager)!!
        return (field(tracker, "requests") as Set<*>).contains(request)
    }

    fun set(owner: Any, name: String, value: Any?) {
        val actualOwner = memberOwner(owner, name)
        actualOwner.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(actualOwner, value)
    }

    fun source(value: Any, index: Int = 3): Any {
        val companion = type("StremioSource").getDeclaredField("Companion").apply { isAccessible = true }.get(null)!!
        return call(companion, if (value is JSONObject) "fromJson" else "fromMap", value, index)!!
    }

    @Suppress("UNCHECKED_CAST")
    private fun adapter(name: String, vararg arguments: Any?) =
        construct(name, *arguments) as RecyclerView.Adapter<RecyclerView.ViewHolder>

    fun guide(season: Int, episode: Int, title: String? = null, watched: Boolean = false): Any =
        construct("GuideEpisode", true, season, episode, title, null, null, 8.5, 30, 300_000L, 1_800_000L, 40.0, watched)

    fun playlist(
        items: List<PlaybackItem>, guide: List<Any> = emptyList(),
        fetch: ((Int, Int) -> Unit)? = null,
        skin: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
        focus: ((PlaybackItem, Int) -> Unit)? = null,
        click: (Int) -> Unit = {},
    ) = adapter("PlaylistAdapter", items, guide, fetch,
        com.debrify.app.R.layout.item_android_tv_playlist_entry_horizontal, skin, focus, click)

    fun groups(vararg groups: Pair<String, List<Int>>): Any = construct("MovieGroups",
        groups.map { construct("CollectionGroup", it.first, it.second) })

    fun movies(
        items: List<PlaybackItem>, groups: Any,
        skin: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
        focus: ((PlaybackItem, Int) -> Unit)? = null,
        click: (Int) -> Unit = {},
    ) = adapter("MoviePlaylistAdapter", items, groups,
        com.debrify.app.R.layout.item_android_tv_playlist_entry_horizontal, skin, focus, click)

    fun channel(
        index: Int = 0, name: String = "Cinema", live: Boolean = true,
        current: Boolean = false, favorite: Boolean = false, loaded: Boolean = false,
        loading: Boolean = false, stop: Long = 0L, epg: String? = null,
        source: String? = "source", number: Int? = 7, group: String? = "Movies",
    ): Any = construct("IptvChannelEntry", index, number, name, "https://example.test/$index", null, group,
        live, current, 0L, emptyMap<String, String>(), epg, 0L, stop, false, false,
        "Next", 0L, loaded, loading, if (live) "live" else "vod", -1,
        null, null, source, "Source", favorite, null, null, null, null, null)

    fun channels(
        entries: MutableList<Any>, click: (Any) -> Unit = {}, longClick: ((Any) -> Unit)? = null,
        epg: ((Any) -> Unit)? = null, style: GuideStyle = GuideStyle.CLASSIC,
    ) = adapter("IptvChannelAdapter", entries, click, longClick, epg, GuideTokens.of(style), style,
        null, null, null, null, 8f, 1)

    fun program(title: String, start: Long, stop: Long, archive: Boolean = false, description: String? = null) =
        construct("IptvEpgProgram", title, description, start, stop, archive)

    fun epg(
        programs: List<Any>, replay: (Any) -> Unit = {}, record: (Any) -> Unit = {},
        style: GuideStyle = GuideStyle.CLASSIC,
    ) = adapter("IptvEpgAdapter", programs, replay, record, GuideTokens.of(style), style, null, null, 8f, 1)

    fun tvChannel(
        id: String = "one", name: String = "Cinema", current: Boolean = false,
        title: String? = "Film", progress: Float = 0.25f, data: Boolean = true,
        loading: Boolean = false, switching: Boolean = false,
    ): Any = construct("StremioTvGuideChannel", id, name, 7, "movie", true, current,
        title, null, "2024", 8.5, System.currentTimeMillis() + 3_600_000L, progress,
        "Next Film", null, "2025", 7.0, data, loading, switching)

    fun tvGuide(channels: MutableList<Any>, click: (Any) -> Unit = {}) = adapter("StremioTvGuideAdapter", channels, click)

    fun categories(selected: String? = null, search: Int = 123, style: GuideStyle = GuideStyle.CLASSIC,
                   click: (String) -> Unit = {}) =
        adapter("IptvCategoryAdapter", selected, search, GuideTokens.of(style), 8f, click)

    fun list(id: String, name: String): Any = construct("IptvListEntry", id, name, false)

    fun lists(entries: List<Any>, membership: Set<String>, style: GuideStyle = GuideStyle.CLASSIC,
              toggle: (Any) -> Unit = {}) =
        adapter("IptvListPickerAdapter", entries, membership, GuideTokens.of(style), 8f, toggle)

    fun ring(outer: AndroidTvTorrentPlayerActivity, context: Context): View =
        construct("AutoSyncRingView", context) as View

    fun defaultPayload(): Any {
        val constructor = type("PlaybackPayload").declaredConstructors.single { it.isSynthetic }
        constructor.isAccessible = true
        return unwrap { constructor.newInstance(
            "Title", null, "single", mutableListOf<PlaybackItem>(), 0, null,
            null, null, null, null, null, null, 0.0, 0.0, false, 0, 0, null,
            ((1 shl 18) - 1) xor ((1 shl 6) - 1), null,
        ) }
    }

    fun episodeHolder(view: View): RecyclerView.ViewHolder =
        construct("PlaylistAdapter\$EpisodeViewHolder", view, { _: Int -> }, null, null) as RecyclerView.ViewHolder

    /** Exercise the original listener installed by a real bind without network
     * or decoder timing. This is a test-only seam into Glide's request object.
     */
    @Suppress("UNCHECKED_CAST")
    fun artworkListener(image: ImageView): RequestListener<Drawable> {
        val request = DrawableImageViewTarget(image).request!!
        val listeners = request.javaClass.getDeclaredField("requestListeners").apply {
            isAccessible = true
        }.get(request) as List<RequestListener<Drawable>>
        return listeners.single()
    }
}
