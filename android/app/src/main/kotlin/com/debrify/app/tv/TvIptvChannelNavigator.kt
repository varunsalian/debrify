package com.debrify.app.tv

import android.view.View
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import com.debrify.app.MainActivity
import com.debrify.app.util.LanguageMapper

@OptIn(UnstableApi::class)
internal class TvIptvChannelNavigator(
    private val activity: AppCompatActivity,
    private val host: TvIptvGuideController.Host,
    private val guide: TvIptvGuideController,
) {

    fun clearIptvZapBoundaryCache() {
        guide.iptvZapCachedOriginCategory = null
        guide.iptvZapCachedDirection = 0
        // Replace rather than clear: a boundary consumer may already hold the
        // previous list while it atomically installs that cached category.
        guide.iptvZapCachedChannels = mutableListOf()
        guide.iptvZapCachedOffset = 0
        guide.iptvZapCachedTotal = 0
        guide.iptvZapCachedCategory = null
        guide.iptvZapCachedCategories = emptyList()
    }

    fun adjacentIptvCategory(delta: Int, attempt: Int): String? {
        val categories = guide.iptvZapCategories.distinct()
        val currentCategory = guide.iptvZapCategory ?: return null
        if (categories.isEmpty() || attempt !in 1..categories.size) return null
        val currentIndex = categories.indexOf(currentCategory).let {
            if (it >= 0) it else 0
        }
        val target =
            (currentIndex + delta * attempt + categories.size * 2) % categories.size
        return categories[target]
    }

    fun prefetchAdjacentIptvCategory(delta: Int, attempt: Int = 1) {
        if (guide.iptvZapCachedChannels.isNotEmpty() &&
            guide.iptvZapCachedDirection != delta
        ) {
            clearIptvZapBoundaryCache()
        }
        if (!guide.iptvZapPagingActive ||
            guide.iptvZapRequestInFlight ||
            guide.iptvZapCategory == null ||
            guide.iptvZapCachedChannels.isNotEmpty()
        ) return
        val nearBoundary = if (delta > 0) {
            host.iptvChannels.lastOrNull()?.index == guide.iptvZapCategoryTotal - 1 &&
                host.currentIptvIndex >= host.iptvChannels.size - 12
        } else {
            host.iptvChannels.firstOrNull()?.index == 0 && host.currentIptvIndex <= 11
        }
        if (!nearBoundary) return
        val targetCategory = adjacentIptvCategory(delta, attempt) ?: return
        val originCategory = guide.iptvZapCategory
        guide.pager.requestIptvZapPage(
            category = targetCategory,
            offset = 0,
            fromEnd = delta < 0,
        ) { channels, pageOffset, total, category, categories ->
            if (originCategory != guide.iptvZapCategory) return@requestIptvZapPage
            if (channels.isEmpty()) {
                prefetchAdjacentIptvCategory(delta, attempt + 1)
                return@requestIptvZapPage
            }
            guide.iptvZapCachedOriginCategory = originCategory
            guide.iptvZapCachedDirection = delta
            guide.iptvZapCachedChannels = channels
            guide.iptvZapCachedOffset = pageOffset
            guide.iptvZapCachedTotal = total
            guide.iptvZapCachedCategory = category
            guide.iptvZapCachedCategories = categories
            guide.pager.drainPendingIptvZapInputs()
        }
    }

    fun consumeCachedAdjacentIptvCategory(delta: Int): Boolean {
        if (guide.iptvZapCachedOriginCategory != guide.iptvZapCategory ||
            guide.iptvZapCachedDirection != delta ||
            guide.iptvZapCachedChannels.isEmpty()
        ) return false
        // Detach from the cache before clearing it. Keeping the same mutable
        // instance here made clearIptvZapBoundaryCache() empty [channels] and
        // the following first()/last() crash at category boundaries.
        val channels = guide.iptvZapCachedChannels.toMutableList()
        val offset = guide.iptvZapCachedOffset
        val total = guide.iptvZapCachedTotal
        val category = guide.iptvZapCachedCategory
        val categories = guide.iptvZapCachedCategories
        clearIptvZapBoundaryCache()
        if (channels.isEmpty()) return false
        guide.pager.installIptvZapWindow(
            channels,
            offset,
            total,
            category,
            categories,
            preservePlayingChannel = false,
        )
        val destination =
            if (delta > 0) host.iptvChannels.firstOrNull() else host.iptvChannels.lastOrNull()
        if (destination == null) return false
        switchToIptvChannel(destination, checkpointOutgoing = false)
        guide.pager.prefetchIptvZapPage(delta)
        prefetchAdjacentIptvCategory(delta)
        return true
    }

    fun switchToIptvChannel(
        entry: IptvChannelEntry,
        adoptVisibleBrowseList: Boolean = true,
        checkpointOutgoing: Boolean = true,
    ) {
        android.util.Log.d("AndroidTvPlayer", "switchToIptvChannel: ${entry.name} (index=${entry.index})")
        host.iptvStartOverController.iptvCatchupToken++
        host.iptvStartOverActive = false
        host.iptvStartOverLoading = false
        host.iptvStartOverTimelineVisible = false
        val previousPlaying = host.iptvChannels.getOrNull(host.currentIptvIndex)
        // Bank the outgoing channel's position BEFORE currentIptvIndex moves,
        // or zapping back to a half-watched movie would rewind it to wherever
        // it stood when the player was launched.
        if (checkpointOutgoing) checkpointCurrentIptvPosition()
        // A channel zap orphans any pending source-switch watcher (see playItem)
        host.sourceSwitchController.dropStaleSourceSwitchFeedback()

        // Browsing can replace the source/category without replacing playback.
        // Adopt the visible result set only when the chosen row is outside the
        // active zap list, then normalize indices for CH +/- navigation.
        var selected = entry
        val adoptsBrowseList = host.iptvChannels.none { it === entry }
        if (adoptsBrowseList) {
            host.iptvChannels = if (adoptVisibleBrowseList) {
                guide.iptvChannelAdapter?.entriesSnapshot()
                    ?.mapIndexed { index, item -> item.apply { this.index = index } }
                    ?.toMutableList()
                    ?: mutableListOf(entry.apply { index = 0 })
            } else {
                // Copy: `entry` is still row N of the guide adapter's list, and
                // DiffUtil keys on `index` — rewriting it in place desyncs the
                // adapter from its own rows while the anchored page is in flight.
                mutableListOf(entry.copy(index = 0))
            }
            selected = host.iptvChannels.firstOrNull { it === entry || it.url == entry.url }
                ?: host.iptvChannels.first()
            guide.iptvSeriesAudioKey = selected.seriesId?.let { seriesId ->
                "${selected.sourceId.orEmpty()}::$seriesId"
            }
        }

        // Update current flags
        host.iptvChannels.forEach { it.isCurrent = false }
        selected.isCurrent = true
        host.currentIptvIndex = host.iptvChannels.indexOfFirst { it === selected }.coerceAtLeast(0)
        guide.iptvChannelAdapter?.notifyCurrentChanged(previousPlaying, selected)

        // Clear subtitle identity/results when changing channels from the guide.
        host.resetSubtitleState()

        // Persist on-demand metadata before playback so the progress row can
        // join Continue Watching even when this item was discovered in-player.
        host.iptvChannelStartController.beginIptvPlaybackAfterWatchRegistration(selected)

        // Update title
        host.titleView.text = selected.displayName

        // Channel-change feedback belongs to live zapping. VOD keeps the
        // standard player presentation.
        if (selected.isLive) host.iptvZapBannerController.showIptvZapBanner(selected) else host.iptvZapBannerController.hideIptvZapBanner()

        host.updateIptvGuideCurrentName()
        // Index moved — a previous episode may have (dis)appeared.
        updateIptvEpisodeControls()
    }

    /** True when LEFT/RIGHT should zap instead of seek: an IPTV session with
     *  a live channel playing, at least one other channel to go to, and the
     *  controls fully hidden — with the dock (or the sources badge) up,
     *  LEFT/RIGHT belong to whatever the user is looking at, and a surprise
     *  channel change under an open menu would read as a glitch. */
    fun isLiveIptvZapContext(): Boolean =
        host.isIptvMode && !host.controlsMenuVisible &&
            (host.iptvChannels.size > 1 || guide.iptvZapPagingActive) &&
            host.iptvChannels.getOrNull(host.currentIptvIndex)?.isLive == true

    fun activateIptvZapUiContext() {
        if (guide.iptvZapOwnsUiContext) return
        guide.iptvUiContextToken++
        guide.iptvBrowseToken++
        guide.iptvZapRequestToken++
        guide.iptvZapRequestInFlight = false
        guide.iptvZapOwnsUiContext = true
        host.iptvSourceId = guide.iptvZapSourceId
        guide.iptvSourceName = guide.iptvZapSourceName
        guide.iptvContentType = guide.iptvZapContentType
        guide.iptvSelectedCategory = guide.iptvZapCategory
        guide.iptvCategories = guide.iptvZapCategories.toMutableList()
        guide.iptvGuideSearch?.setText("")
        guide.iptvBrowseChannels = host.iptvChannels.toMutableList()
        guide.iptvGuideUsesZapWindow = true
        guide.iptvChannelAdapter?.updateChannels(host.iptvChannels)
        guide.refreshIptvBrowserChrome()
    }

    /** Fullscreen channel zap: previous/next channel in guide order,
     *  paging through the active category and crossing into the adjacent
     *  category at its ends. */
    fun zapIptvChannel(delta: Int) {
        if (host.iptvChannels.getOrNull(host.currentIptvIndex)?.isLive != true) return
        // A physical channel key is a real tune, so the temporary search scope
        // is no longer eligible for restoration.
        guide.commitIptvAllCategorySearch()
        activateIptvZapUiContext()
        if (!guide.iptvZapPagingActive && host.iptvChannels.size < 2) return
        val from = host.currentIptvIndex.coerceIn(0, host.iptvChannels.lastIndex)
        val next = from + delta
        if (!guide.iptvZapPagingActive) {
            val wrapped = (next + host.iptvChannels.size) % host.iptvChannels.size
            switchToIptvChannel(host.iptvChannels[wrapped])
            return
        }
        if (next in host.iptvChannels.indices) {
            switchToIptvChannel(host.iptvChannels[next])
            guide.pager.prefetchIptvZapPage(delta)
            prefetchAdjacentIptvCategory(delta)
            return
        }

        val firstAbsolute = host.iptvChannels.first().index
        val lastAbsolute = host.iptvChannels.last().index
        val hasAnotherPage = if (delta > 0) {
            lastAbsolute + 1 < guide.iptvZapCategoryTotal
        } else {
            firstAbsolute > 0
        }
        if (hasAnotherPage) {
            guide.pager.queuePendingIptvZapInput(delta)
            guide.pager.prefetchIptvZapPage(delta)
            return
        }
        if (consumeCachedAdjacentIptvCategory(delta)) return
        requestAdjacentIptvCategory(delta)
    }

    fun requestAdjacentIptvCategory(delta: Int, attempt: Int = 1) {
        if (guide.iptvZapRequestInFlight) {
            guide.pager.queuePendingIptvZapInput(delta)
            return
        }
        val categories = guide.iptvZapCategories.distinct()
        val currentCategory = guide.iptvZapCategory
        if (currentCategory == null || categories.isEmpty()) {
            // An uncategorized/All-channels context has no category boundary;
            // wrap by paging the opposite end of the same result set.
            guide.pager.requestIptvZapPage(
                category = null,
                offset = 0,
                fromEnd = delta < 0,
            ) { channels, pageOffset, total, category, returnedCategories ->
                if (channels.isEmpty()) return@requestIptvZapPage
                guide.pager.installIptvZapWindow(
                    channels,
                    pageOffset,
                    total,
                    category,
                    returnedCategories,
                    preservePlayingChannel = false,
                )
                switchToIptvChannel(
                    if (delta > 0) host.iptvChannels.first() else host.iptvChannels.last(),
                    checkpointOutgoing = false,
                )
                guide.pager.prefetchIptvZapPage(delta)
                guide.pager.drainPendingIptvZapInputs()
            }
            return
        }

        if (attempt > categories.size) {
            guide.iptvZapPendingInputs.clear()
            return
        }
        val targetCategory = adjacentIptvCategory(delta, attempt) ?: return
        guide.pager.requestIptvZapPage(
            category = targetCategory,
            offset = 0,
            fromEnd = delta < 0,
        ) { channels, pageOffset, total, category, returnedCategories ->
            if (channels.isEmpty()) {
                requestAdjacentIptvCategory(delta, attempt + 1)
                return@requestIptvZapPage
            }
            guide.pager.installIptvZapWindow(
                channels,
                pageOffset,
                total,
                category,
                returnedCategories,
                preservePlayingChannel = false,
            )
            switchToIptvChannel(
                if (delta > 0) host.iptvChannels.first() else host.iptvChannels.last(),
                checkpointOutgoing = false,
            )
            guide.pager.prefetchIptvZapPage(delta)
            prefetchAdjacentIptvCategory(delta)
            guide.pager.drainPendingIptvZapInputs()
        }
    }

    /**
     * Store the playing on-demand item's live position on its own entry, so a
     * later zap back to it resumes from there.
     *
     * Mirrors the Flutter-side window: a barely-started or effectively
     * finished item banks 0 and replays from the beginning, rather than
     * stranding the viewer a second from the credits.
     */
    fun checkpointCurrentIptvPosition() {
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return
        if (entry.isLive) return

        val duration = host.player?.duration ?: 0L
        val position = host.player?.currentPosition ?: 0L
        if (duration <= 0L || position <= 0L) return

        val fraction = position.toDouble() / duration.toDouble()
        entry.resumePositionMs = if (fraction in 0.02..0.95) position else 0L
    }

    fun playIptvChannel(index: Int) {
        if (index !in host.iptvChannels.indices) return
        val entry = host.iptvChannels[index]

        android.util.Log.d("AndroidTvPlayer", "playIptvChannel: ${entry.name} url=${entry.url.take(60)}")

        // Clear subtitle identity/results when changing channels.
        host.resetSubtitleState()

        host.iptvChannelStartController.beginIptvPlayback(entry)

        // Update the title content. Visibility stays synchronized with controls.
        host.titleView.text = entry.displayName

        // First tune on a live channel: the zap banner doubles as the "here's
        // what's on" card and teaches the zap/guide keys — without it, EPG
        // exists only inside a guide overlay nobody knows how to open.
        if (entry.isLive) host.iptvZapBannerController.showIptvZapBanner(entry)
    }

    // ── IPTV episode navigation (series/VOD lists) ──────────────────────────

    /** This IPTV session is an Xtream SERIES episode list. Scoped to series
     *  (the launcher sets seriesAudioKey only then) — NOT every non-live item —
     *  so automatic episode progression never applies to a standalone movie. */
    fun isIptvEpisodeMode(): Boolean {
        if (!host.isIptvMode || guide.iptvSeriesAudioKey == null) return false
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex) ?: return false
        return !entry.isLive
    }

    fun nextIptvEpisode(): IptvChannelEntry? {
        if (!isIptvEpisodeMode()) return null
        return host.iptvChannels.getOrNull(host.currentIptvIndex + 1)
    }

    fun prevIptvEpisode(): IptvChannelEntry? {
        if (!isIptvEpisodeMode()) return null
        return host.iptvChannels.getOrNull(host.currentIptvIndex - 1)
    }

    /** IPTV guide and CH controls belong to live television only. VOD keeps
     *  the standard seek controls and episode Previous/Next actions. */
    fun updateIptvEpisodeControls() {
        val entry = host.iptvChannels.getOrNull(host.currentIptvIndex)
        host.updateIptvControlPresentation(entry)
        if (!host.isIptvMode) return
        if (entry?.isLive == true) {
            host.iptvPrevButton?.text = "CH -"
            host.iptvNextButton?.text = "CH +"
            val visibility =
                if (host.iptvChannels.size > 1 || guide.iptvZapPagingActive) {
                    View.VISIBLE
                } else {
                    View.GONE
                }
            host.iptvPrevButton?.visibility = visibility
            host.iptvNextButton?.visibility = visibility
        } else {
            host.iptvPrevButton?.text = "Previous"
            host.iptvNextButton?.text = "Next"
            host.iptvPrevButton?.visibility =
                if (prevIptvEpisode() != null) View.VISIBLE else View.GONE
            host.iptvNextButton?.visibility =
                if (nextIptvEpisode() != null) View.VISIBLE else View.GONE
        }
    }

    /** Set the TrackSelector's preferred audio language — a persistent
     *  parameter, so it re-applies to each episode's tracks on switch. */
    fun setIptvPreferredAudioLang(lang: String) {
        val ts = host.trackSelector ?: return
        val variants = LanguageMapper.getLanguageVariantsForExoPlayer(lang)
        val p = ts.parameters.buildUpon()
        if (variants.isNotEmpty()) {
            p.setPreferredAudioLanguages(*variants.toTypedArray())
        } else {
            p.setPreferredAudioLanguage(lang)
        }
        ts.parameters = p.build()
    }

    /** A native audio pick in a series: carry it to later episodes (preferred-
     *  language param) and persist it back to Flutter's per-series store. */
    fun onIptvSeriesAudioPicked(lang: String?) {
        val key = guide.iptvSeriesAudioKey ?: return
        if (lang.isNullOrEmpty() || lang == "und" || lang == "auto") return
        guide.iptvPreferredAudioLang = lang
        setIptvPreferredAudioLang(lang)
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod(
            "saveIptvSeriesAudio",
            mapOf("seriesKey" to key, "lang" to lang)
        )
    }
}
