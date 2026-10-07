package com.debrify.app.tv

import org.robolectric.Robolectric

/** The activity is instantiated, never created: no player, channel or lifecycle side effects. */
open class TvPhase2OriginalTest {
    protected val lifecycle = Robolectric.buildActivity(AndroidTvTorrentPlayerActivity::class.java)
    protected val activity = lifecycle.get()
    protected val stringType = String::class.java
    protected val intType = Int::class.javaPrimitiveType!!
    protected val longType = Long::class.javaPrimitiveType!!
    protected val boolType = Boolean::class.javaPrimitiveType!!
    protected val boxedIntType = Int::class.javaObjectType
    protected val listType = List::class.java
    protected val mapType = Map::class.java

    protected fun call(name: String, types: Array<Class<*>>, vararg arguments: Any?): Any? =
        TvPlayerOriginalAccess.callTyped(activity, name, types, *arguments)

    protected fun defaultCall(name: String, types: Array<Class<*>>, mask: Int, vararg arguments: Any?): Any? =
        TvPlayerOriginalAccess.callDefault(activity, name, types, mask, *arguments)
}

internal fun p2Item(title: String = "Film", url: String = "https://example.test/a", season: Int? = null,
                    episode: Int? = null, provider: String? = null): PlaybackItem = PlaybackItem(
    id = "item", title = title, url = url, index = 0, season = season, episode = episode,
    artwork = null, description = null, resumePositionMs = 0L, durationMs = 0L, updatedAt = 0L,
    resumeId = "resume", sizeBytes = null, rating = null, provider = provider,
)

internal fun p2Channel(live: Boolean = true, current: Boolean = false, archive: String? = null,
                       days: Int? = null): IptvChannelEntry = IptvChannelEntry(
    index = 0, channelNumber = null, name = "Cinema", url = "https://example.test/channel",
    logoUrl = null, group = null, isLive = live, isCurrent = current,
    tvArchive = archive, tvArchiveDuration = days,
)

internal fun p2Guide(): StremioTvGuideChannel = StremioTvGuideChannel(
    "id", "Channel", 1, "movie", false, false, null, null, null, null, 0L, 0f,
    null, null, null, null, false, true,
)
