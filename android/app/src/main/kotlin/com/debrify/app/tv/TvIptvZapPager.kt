package com.debrify.app.tv

import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.debrify.app.MainActivity

internal class TvIptvZapPager(
    private val activity: AppCompatActivity,
    private val host: TvIptvGuideController.Host,
    private val guide: TvIptvGuideController,
) {

    /**
     * A guide search is only a way to discover the destination. Once selected,
     * playback belongs to the channel's category: the search is cleared and a
     * small page centered on the channel becomes the CH +/- and guide context.
     */
    fun beginIptvCategoryZapSession(entry: IptvChannelEntry) {
        guide.commitIptvAllCategorySearch()
        val category = entry.group?.trim()?.takeIf { it.isNotEmpty() }
        val sourceId = host.iptvSourceId
        val sourceName = guide.iptvSourceName
        val contentType = guide.iptvContentType
        val fallbackChannels = guide.iptvChannelAdapter?.entriesSnapshot().orEmpty()

        guide.iptvSelectedCategory = category
        guide.iptvGuideSearch?.setText("")
        guide.refreshIptvBrowserChrome()

        guide.iptvUiContextToken++
        guide.iptvZapOwnsUiContext = true
        guide.iptvBrowseToken++
        guide.iptvZapPagingActive = true
        guide.iptvZapCategory = category
        guide.iptvZapSourceId = sourceId
        guide.iptvZapSourceName = sourceName
        guide.iptvZapContentType = contentType
        guide.iptvZapCategories = guide.iptvCategories.toMutableList()
        guide.iptvZapCategoryTotal = 1
        guide.iptvZapPendingInputs.clear()
        guide.iptvGuideUsesZapWindow = false
        // A second rapid selection supersedes a page still returning for the
        // previous result.
        guide.iptvZapRequestToken++
        guide.iptvZapRequestInFlight = false
        guide.navigator.clearIptvZapBoundaryCache()

        // Do not let the search matches become the temporary zap list while
        // the centered category page crosses the platform channel.
        guide.navigator.switchToIptvChannel(entry, adoptVisibleBrowseList = false)
        requestIptvZapPage(
            category = category,
            offset = 0,
            anchor = entry,
            onFailure = {
                restoreIptvZapBootstrapFallback(entry, fallbackChannels)
            },
        ) { channels, pageOffset, total, responseCategory, categories ->
            val containsPlayingChannel = channels.any {
                it.url == entry.url && it.name == entry.name
            }
            if (channels.isEmpty() || !containsPlayingChannel) {
                restoreIptvZapBootstrapFallback(entry, fallbackChannels)
                return@requestIptvZapPage
            }
            installIptvZapWindow(
                channels = channels,
                pageOffset = pageOffset,
                total = total,
                category = responseCategory,
                categories = categories,
                preservePlayingChannel = true,
            )
            drainPendingIptvZapInputs()
            prefetchIptvZapPage(1)
            guide.navigator.prefetchAdjacentIptvCategory(1)
        }
    }

    /**
     * The launch payload is capped and has window-relative indices. Resolve a
     * small anchored page immediately so CH +/- works across the full category
     * even before the user opens the guide for the first time.
     */
    fun bootstrapInitialIptvZapPaging(entry: IptvChannelEntry) {
        if (!entry.isLive || guide.iptvContentType != "live") return
        val category =
            entry.group?.trim()?.takeIf { it.isNotEmpty() } ?: guide.iptvSelectedCategory
        guide.iptvSelectedCategory = category
        guide.iptvZapCategory = category
        guide.refreshIptvBrowserChrome()
        requestIptvZapPage(
            category = category,
            offset = 0,
            anchor = entry,
        ) { channels, pageOffset, total, responseCategory, categories ->
            val playing = host.iptvChannels.getOrNull(host.currentIptvIndex)
            if (playing?.url != entry.url || playing.name != entry.name) {
                if (playing?.isLive == true && guide.iptvZapOwnsUiContext) {
                    bootstrapInitialIptvZapPaging(playing)
                }
                return@requestIptvZapPage
            }
            val containsPlayingChannel = channels.any {
                it.url == playing.url && it.name == playing.name
            }
            if (channels.isEmpty() || !containsPlayingChannel) return@requestIptvZapPage
            guide.iptvZapPagingActive = true
            installIptvZapWindow(
                channels = channels,
                pageOffset = pageOffset,
                total = total,
                category = responseCategory,
                categories = categories,
                preservePlayingChannel = true,
            )
            guide.navigator.updateIptvEpisodeControls()
            prefetchIptvZapPage(1)
            guide.navigator.prefetchAdjacentIptvCategory(1)
        }
    }

    fun restoreIptvZapBootstrapFallback(
        selected: IptvChannelEntry,
        fallbackChannels: List<IptvChannelEntry>,
    ) {
        val playing = host.iptvChannels.getOrNull(host.currentIptvIndex)
        if (playing?.url != selected.url || playing.name != selected.name) return
        disableIptvZapPaging()
        val fallback = fallbackChannels
            .ifEmpty { listOf(selected) }
            .mapIndexed { index, entry ->
                entry.apply {
                    this.index = index
                    isCurrent = url == selected.url && name == selected.name
                }
            }
            .toMutableList()
        if (fallback.none { it.isCurrent }) {
            selected.index = fallback.size
            selected.isCurrent = true
            fallback.add(selected)
        }
        host.iptvChannels = fallback
        host.currentIptvIndex = fallback.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        guide.iptvBrowseChannels = fallback.toMutableList()
        guide.iptvGuideUsesZapWindow = false
        guide.iptvChannelAdapter?.updateChannels(fallback)
        guide.refreshIptvBrowserChrome()
    }

    fun requestIptvChannelJump(channelNumber: Int) {
        val bridge = MainActivity.getAndroidTvPlayerChannel()
        if (bridge == null) {
            Toast.makeText(activity, "Channel lookup is unavailable", Toast.LENGTH_SHORT).show()
            return
        }
        val token = ++guide.iptvZapRequestToken
        guide.iptvZapRequestInFlight = true
        bridge.invokeMethod(
            "requestIptvBrowse",
            hashMapOf<String, Any?>(
                "action" to "channelNumber",
                "sourceId" to guide.iptvZapSourceId,
                "contentType" to "live",
                "channelNumber" to channelNumber,
                "limit" to guide.iptvZapPageSize,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    if (token != guide.iptvZapRequestToken) return
                    guide.iptvZapRequestInFlight = false
                    val response = result as? Map<*, *>
                    if (response == null || response["channelNotFound"] == true) {
                        Toast.makeText(
                            activity,
                            "Channel $channelNumber was not found",
                            Toast.LENGTH_SHORT,
                        ).show()
                        drainPendingIptvZapInputs()
                        return
                    }
                    val channels = parseIptvChannels(
                        response["channels"] as? List<*> ?: emptyList<Any>()
                    )
                    val target = channels.firstOrNull {
                        it.channelNumber == channelNumber
                    }
                    if (target == null) {
                        Toast.makeText(
                            activity,
                            "Channel $channelNumber was not found",
                            Toast.LENGTH_SHORT,
                        ).show()
                        drainPendingIptvZapInputs()
                        return
                    }
                    (response["sourceId"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        guide.iptvZapSourceId = it
                        host.iptvSourceId = it
                    }
                    (response["sourceName"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        guide.iptvZapSourceName = it
                        guide.iptvSourceName = it
                    }
                    val category =
                        (response["selectedCategory"] as? String)?.takeIf { it.isNotEmpty() }
                    val categories = (response["categories"] as? List<*>)
                        ?.mapNotNull { it as? String }
                        ?.filter { it.isNotEmpty() }
                        .orEmpty()
                    guide.iptvZapContentType = "live"
                    guide.iptvContentType = "live"
                    guide.iptvZapOwnsUiContext = true
                    guide.iptvZapPagingActive = true
                    installIptvZapWindow(
                        channels,
                        (response["pageOffset"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0,
                        (response["totalChannels"] as? Number)?.toInt()
                            ?.coerceAtLeast(0) ?: channels.size,
                        category,
                        categories,
                        preservePlayingChannel = false,
                    )
                    val selected = host.iptvChannels.firstOrNull {
                        it.channelNumber == channelNumber
                    } ?: return
                    guide.navigator.switchToIptvChannel(selected, checkpointOutgoing = false)
                    drainPendingIptvZapInputs()
                    prefetchIptvZapPage(1)
                    prefetchIptvZapPage(-1)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (token != guide.iptvZapRequestToken) return
                    guide.iptvZapRequestInFlight = false
                    Toast.makeText(
                        activity,
                        message ?: "Unable to look up that channel",
                        Toast.LENGTH_SHORT,
                    ).show()
                    drainPendingIptvZapInputs()
                }

                override fun notImplemented() {
                    if (token != guide.iptvZapRequestToken) return
                    guide.iptvZapRequestInFlight = false
                    Toast.makeText(
                        activity,
                        "Channel lookup is unavailable",
                        Toast.LENGTH_SHORT,
                    ).show()
                    drainPendingIptvZapInputs()
                }
            },
        )
    }

    fun requestIptvZapPage(
        category: String?,
        offset: Int,
        anchor: IptvChannelEntry? = null,
        fromEnd: Boolean = false,
        onFailure: (() -> Unit)? = null,
        onLoaded: (
            channels: MutableList<IptvChannelEntry>,
            pageOffset: Int,
            total: Int,
            category: String?,
            categories: List<String>,
        ) -> Unit,
    ) {
        if (guide.iptvZapRequestInFlight) return
        val bridge = MainActivity.getAndroidTvPlayerChannel()
        if (bridge == null) {
            onFailure?.invoke()
            return
        }
        val uiContext = guide.iptvUiContextToken
        val token = ++guide.iptvZapRequestToken
        guide.iptvZapRequestInFlight = true
        bridge.invokeMethod(
            "requestIptvBrowse",
            hashMapOf<String, Any?>(
                "action" to "zapPage",
                "sourceId" to guide.iptvZapSourceId,
                "contentType" to guide.iptvZapContentType,
                "category" to category,
                "query" to "",
                "offset" to offset.coerceAtLeast(0),
                "limit" to guide.iptvZapPageSize,
                "anchorUrl" to anchor?.url,
                "anchorName" to anchor?.name,
                "fromEnd" to fromEnd,
            ),
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    // The flag belongs to the latest request (token), not to the
                    // UI context: a context change while this page was in flight
                    // must not strand iptvZapRequestInFlight at true, or every
                    // later zap page is silently dropped for the whole session.
                    if (token == guide.iptvZapRequestToken) guide.iptvZapRequestInFlight = false
                    if (token != guide.iptvZapRequestToken ||
                        uiContext != guide.iptvUiContextToken ||
                        !guide.iptvZapOwnsUiContext
                    ) return
                    val response = result as? Map<*, *>
                    if (response == null) {
                        guide.iptvZapPendingInputs.clear()
                        onFailure?.invoke()
                        return
                    }
                    (response["sourceId"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        guide.iptvZapSourceId = it
                        host.iptvSourceId = it
                    }
                    (response["sourceName"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        guide.iptvZapSourceName = it
                        guide.iptvSourceName = it
                    }
                    (response["contentType"] as? String)?.takeIf { it.isNotEmpty() }?.let {
                        guide.iptvZapContentType = it
                        guide.iptvContentType = it
                    }
                    val channels = parseIptvChannels(
                        response["channels"] as? List<*> ?: emptyList<Any>()
                    )
                    val pageOffset =
                        (response["pageOffset"] as? Number)?.toInt()?.coerceAtLeast(0) ?: 0
                    val total =
                        (response["totalChannels"] as? Number)?.toInt()?.coerceAtLeast(0)
                            ?: channels.size
                    val responseCategory =
                        (response["selectedCategory"] as? String)?.takeIf { it.isNotEmpty() }
                    val categories = (response["categories"] as? List<*>)
                        ?.mapNotNull { it as? String }
                        ?.filter { it.isNotEmpty() }
                        .orEmpty()
                    onLoaded(channels, pageOffset, total, responseCategory, categories)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (token == guide.iptvZapRequestToken) guide.iptvZapRequestInFlight = false
                    if (token != guide.iptvZapRequestToken ||
                        uiContext != guide.iptvUiContextToken ||
                        !guide.iptvZapOwnsUiContext
                    ) return
                    guide.iptvZapPendingInputs.clear()
                    onFailure?.invoke()
                    Toast.makeText(
                        activity,
                        message ?: "Unable to load more channels",
                        Toast.LENGTH_SHORT,
                    ).show()
                }

                override fun notImplemented() {
                    if (token == guide.iptvZapRequestToken) guide.iptvZapRequestInFlight = false
                    if (token != guide.iptvZapRequestToken ||
                        uiContext != guide.iptvUiContextToken ||
                        !guide.iptvZapOwnsUiContext
                    ) return
                    guide.iptvZapPendingInputs.clear()
                    onFailure?.invoke()
                }
            },
        )
    }

    fun installIptvZapWindow(
        channels: MutableList<IptvChannelEntry>,
        pageOffset: Int,
        total: Int,
        category: String?,
        categories: List<String>,
        preservePlayingChannel: Boolean,
    ) {
        if (category != guide.iptvZapCategory) guide.navigator.clearIptvZapBoundaryCache()
        val playing = host.iptvChannels.getOrNull(host.currentIptvIndex)
        if (!preservePlayingChannel) {
            // The old list is about to disappear. Bank its VOD position while
            // currentIptvIndex still identifies the actual outgoing item.
            guide.navigator.checkpointCurrentIptvPosition()
        }
        channels.forEachIndexed { index, entry ->
            entry.index = pageOffset + index
            entry.isCurrent = preservePlayingChannel &&
                playing != null &&
                entry.url == playing.url &&
                entry.name == playing.name
        }

        guide.iptvZapCategory = category
        guide.iptvZapCategoryTotal = total
        if (categories.isNotEmpty()) {
            guide.iptvZapCategories = categories.toMutableList()
            guide.iptvCategories = categories.toMutableList()
        }
        guide.iptvSelectedCategory = category
        host.iptvChannels = channels
        guide.iptvBrowseChannels = channels.toMutableList()
        guide.iptvGuideUsesZapWindow = true
        host.currentIptvIndex = channels.indexOfFirst { it.isCurrent }.let { index ->
            if (index >= 0) index else 0
        }
        if (preservePlayingChannel &&
            channels.isNotEmpty() &&
            channels.none { it.isCurrent }
        ) {
            channels[host.currentIptvIndex].isCurrent = true
        }
        guide.iptvChannelAdapter?.updateChannels(channels)
        guide.refreshIptvBrowserChrome()
        host.updateIptvGuideCurrentName()
        host.iptvZapBannerController.refreshIptvZapBannerPosition()
    }

    fun mergeIptvZapPage(
        page: MutableList<IptvChannelEntry>,
        pageOffset: Int,
        total: Int,
        category: String?,
        categories: List<String>,
    ) {
        if (!guide.iptvZapPagingActive || category != guide.iptvZapCategory) return
        val playing = host.iptvChannels.getOrNull(host.currentIptvIndex)
        page.forEachIndexed { index, entry -> entry.index = pageOffset + index }
        val byPosition = java.util.TreeMap<Int, IptvChannelEntry>()
        host.iptvChannels.forEach { byPosition[it.index] = it }
        page.forEach { byPosition[it.index] = it }
        val merged = byPosition.values.toMutableList()
        merged.forEach {
            it.isCurrent = playing != null &&
                it.url == playing.url &&
                it.name == playing.name
        }
        guide.iptvZapCategoryTotal = total
        if (categories.isNotEmpty()) {
            guide.iptvZapCategories = categories.toMutableList()
            guide.iptvCategories = categories.toMutableList()
        }
        val window = boundedHiddenIptvZapWindow(merged)
        host.iptvChannels = window
        guide.iptvBrowseChannels = window.toMutableList()
        guide.iptvGuideUsesZapWindow = true
        host.currentIptvIndex = window.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        guide.iptvChannelAdapter?.updateChannels(window)
        guide.refreshIptvBrowserChrome()
        host.iptvZapBannerController.refreshIptvZapBannerPosition()
    }

    fun boundedHiddenIptvZapWindow(
        channels: MutableList<IptvChannelEntry>,
    ): MutableList<IptvChannelEntry> {
        if (guide.iptvGuideVisible || channels.size <= guide.iptvZapMaxHiddenWindow) return channels
        val current = channels.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        val maxStart = channels.size - guide.iptvZapMaxHiddenWindow
        val start = (current - guide.iptvZapMaxHiddenWindow / 2).coerceIn(0, maxStart)
        return channels.subList(start, start + guide.iptvZapMaxHiddenWindow).toMutableList()
    }

    fun trimHiddenIptvZapWindow() {
        if (!guide.iptvZapPagingActive || host.iptvChannels.size <= guide.iptvZapMaxHiddenWindow) return
        val trimmed = boundedHiddenIptvZapWindow(host.iptvChannels)
        if (trimmed.size == host.iptvChannels.size) return
        host.iptvChannels = trimmed
        guide.iptvBrowseChannels = trimmed.toMutableList()
        host.currentIptvIndex = trimmed.indexOfFirst { it.isCurrent }.coerceAtLeast(0)
        if (guide.iptvGuideUsesZapWindow) guide.iptvChannelAdapter?.updateChannels(trimmed)
    }

    fun prefetchIptvZapPage(delta: Int, force: Boolean = false) {
        if (!guide.iptvZapPagingActive || guide.iptvZapRequestInFlight || host.iptvChannels.isEmpty()) return
        val firstAbsolute = host.iptvChannels.first().index
        val lastAbsolute = host.iptvChannels.last().index
        val shouldLoad = if (delta > 0) {
            lastAbsolute + 1 < guide.iptvZapCategoryTotal &&
                (force || host.currentIptvIndex >= host.iptvChannels.size - 12)
        } else {
            firstAbsolute > 0 && (force || host.currentIptvIndex <= 11)
        }
        if (!shouldLoad) return
        val offset = if (delta > 0) {
            lastAbsolute + 1
        } else {
            (firstAbsolute - guide.iptvZapPageSize).coerceAtLeast(0)
        }
        requestIptvZapPage(
            category = guide.iptvZapCategory,
            offset = offset,
        ) { channels, loadedOffset, total, category, categories ->
            mergeIptvZapPage(channels, loadedOffset, total, category, categories)
            drainPendingIptvZapInputs()
        }
    }

    fun queuePendingIptvZapInput(delta: Int) {
        if (guide.iptvZapPendingInputs.size < 24) {
            guide.iptvZapPendingInputs.addLast(if (delta >= 0) 1 else -1)
        }
    }

    fun drainPendingIptvZapInputs() {
        if (guide.iptvZapDrainingInputs) return
        guide.iptvZapDrainingInputs = true
        try {
            while (guide.iptvZapPendingInputs.isNotEmpty()) {
                val delta = guide.iptvZapPendingInputs.removeFirst()
                guide.navigator.zapIptvChannel(delta)
                if (guide.iptvZapRequestInFlight) break
            }
        } finally {
            guide.iptvZapDrainingInputs = false
        }
    }

    fun disableIptvZapPaging() {
        guide.iptvZapPagingActive = false
        guide.iptvZapRequestToken++
        guide.iptvZapRequestInFlight = false
        guide.iptvZapPendingInputs.clear()
        guide.navigator.clearIptvZapBoundaryCache()
    }
}
