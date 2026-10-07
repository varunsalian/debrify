package com.debrify.app.tv

import android.content.Context
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import org.json.JSONObject
import java.lang.reflect.InvocationTargetException

/** Only this helper knows the original private JVM names/constructor order.
 * Move commits retarget this helper; the behavioural assertions stay unchanged.
 */
internal object TvPlayerOriginalAccess {
    private val nested = setOf("IptvCategoryAdapter", "IptvListPickerAdapter", "AutoSyncColors", "AutoSyncRingView")

    fun type(name: String): Class<*> = Class.forName(
        "com.debrify.app.tv." + if (name in nested) "AndroidTvTorrentPlayerActivity\$$name" else name,
    )

    fun construct(name: String, vararg arguments: Any?): Any {
        val constructor = type(name).declaredConstructors.single {
            !it.isSynthetic && it.parameterCount == arguments.size
        }
        constructor.isAccessible = true
        return unwrap { constructor.newInstance(*arguments) }
    }

    fun call(owner: Any, name: String, vararg arguments: Any?): Any? {
        val method = owner.javaClass.declaredMethods.single {
            it.name == name && it.parameterCount == arguments.size && !it.isBridge
        }
        method.isAccessible = true
        return unwrap { method.invoke(owner, *arguments) }
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

    fun field(owner: Any, name: String): Any? = owner.javaClass.getDeclaredField(name).apply {
        isAccessible = true
    }.get(owner)

    fun set(owner: Any, name: String, value: Any?) {
        owner.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(owner, value)
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
        construct("AutoSyncRingView", outer, context) as View
}
