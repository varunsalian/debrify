package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import java.util.Locale

internal class TvPlaylistOverlayController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val controlsSkin: TvControlsSkin
        val currentIndex: Int
        fun dp(value: Int): Int
        val hasPlaylistResolver: Boolean
        val ottShowName: String?
        val payload: PlaybackPayload?
        fun playItem(index: Int): Unit
        val playlistOverlay: View
        val playlistView: RecyclerView
        val seasonTabsContainer: LinearLayout
        val sourceFetchController: TvSourceFetchController
    }
    internal val navigator = TvPlaylistFocusNavigator(activity, host, this)
    internal val guideSkin = TvPlaylistGuideSkin(activity, host, this)
    internal val seasonTabs = mutableListOf<android.widget.TextView>()
    internal val movieTabs = mutableListOf<MovieTab>()
    internal var playlistVisible = false
    internal var playlistMode: PlaylistMode = PlaylistMode.NONE
    internal var playlistAdapter: PlaylistOverlayAdapter? = null
    internal var seriesPlaylistAdapter: PlaylistAdapter? = null
    internal var moviePlaylistAdapter: MoviePlaylistAdapter? = null
    internal var movieGroups: MovieGroups? = null

    fun setupPlaylist() {
        // Configure RecyclerView for optimal focus handling
        host.playlistView.layoutManager = LinearLayoutManager(activity, LinearLayoutManager.HORIZONTAL, false).apply {
            // Pre-fetch items for smoother scrolling
            isItemPrefetchEnabled = true
            initialPrefetchItemCount = 4
        }
        // Guide skin: vertical/grid managers replace the horizontal one (no-op
        // on CLASSIC and the horizontal skins).
        guideSkin.applyGuideLayoutManager()

        // Disable item animator to prevent focus issues during view animations
        host.playlistView.itemAnimator = null

        // Keep more views in memory to reduce recycling-related focus issues
        host.playlistView.setItemViewCacheSize(10)

        // Ensure children can receive focus
        host.playlistView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS

        // Add focus recovery listener for view recycling (with delay to prevent interference with navigation)
        host.playlistView.addOnChildAttachStateChangeListener(object : RecyclerView.OnChildAttachStateChangeListener {
            override fun onChildViewAttachedToWindow(view: View) {
                // Don't interfere during active navigation
                if (navigator.isNavigating) {
                    android.util.Log.d("PlaylistNav", "onChildViewAttached: Skipping - navigation in progress")
                    return
                }

                // Only consider recovery if playlist is visible and view is focusable
                if (playlistVisible && view.isFocusable) {
                    // Cancel any pending recovery
                    navigator.focusRecoveryRunnable?.let { navigator.focusRecoveryHandler.removeCallbacks(it) }

                    // Schedule focus check with delay to let transitions complete
                    navigator.focusRecoveryRunnable = Runnable {
                        // Double-check focus is actually lost after delay
                        if (playlistVisible && !navigator.isNavigating &&
                            !host.playlistView.hasFocus() &&
                            host.playlistView.focusedChild == null) {
                            android.util.Log.d("PlaylistNav", "onChildViewAttached: Recovering focus after delay")
                            navigator.ensureFocusInPlaylist()
                        }
                    }
                    // 100ms delay to let focus transitions complete
                    navigator.focusRecoveryHandler.postDelayed(navigator.focusRecoveryRunnable!!, 100)
                }
            }

            override fun onChildViewDetachedFromWindow(view: View) {
                // Only recover if the detached view had focus AND we're not navigating
                if (view.hasFocus() && playlistVisible && !navigator.isNavigating) {
                    android.util.Log.d("PlaylistNav", "Focused view being detached, scheduling recovery")

                    // Cancel any pending recovery
                    navigator.focusRecoveryRunnable?.let { navigator.focusRecoveryHandler.removeCallbacks(it) }

                    // Schedule recovery with delay
                    navigator.focusRecoveryRunnable = Runnable {
                        if (playlistVisible && !navigator.isNavigating &&
                            !host.playlistView.hasFocus() &&
                            host.playlistView.focusedChild == null) {
                            android.util.Log.d("PlaylistNav", "onChildViewDetached: Recovering focus after delay")
                            navigator.ensureFocusInPlaylist()
                        }
                    }
                    navigator.focusRecoveryHandler.postDelayed(navigator.focusRecoveryRunnable!!, 100)
                }
            }
        })

        host.playlistOverlay.visibility = View.GONE

        rebuildPlaylistContent()
    }

    /** Rebuilds playlist adapters, tabs, and mode from current payload items. Safe to call multiple times. */
    fun rebuildPlaylistContent() {
        val model = host.payload ?: return
        val items = model.items
        movieTabs.clear()
        seasonTabs.clear()
        host.seasonTabsContainer.removeAllViews()
        seriesPlaylistAdapter = null
        moviePlaylistAdapter = null
        playlistAdapter = null
        movieGroups = null
        playlistMode = PlaylistMode.NONE

        if (items.size <= 1) {
            // Single stream: with a full-show guide + a playlist resolver the
            // series overlay still renders (absent rows fetch in-player),
            // matching the Flutter player's synthetic guide.
            val guideCapable = host.hasPlaylistResolver &&
                model.contentType.lowercase(Locale.US) == "series" &&
                model.guideEpisodes.isNotEmpty()
            if (!guideCapable) {
                host.playlistView.adapter = null
                host.seasonTabsContainer.visibility = View.GONE
                return
            }
        }

        when (model.contentType.lowercase(Locale.US)) {
            "series" -> setupSeriesPlaylist(items)
            else -> setupCollectionPlaylist(items)
        }

        navigator.setupPlaylistNavigation()
    }

    fun setupSeriesPlaylist(items: List<PlaybackItem>) {
        // Full-guide mode only when absent rows can actually be fetched.
        val guide = if (host.hasPlaylistResolver) {
            host.payload?.guideEpisodes ?: emptyList()
        } else {
            emptyList()
        }
        val adapter = PlaylistAdapter(
            items,
            guide = guide,
            onFetchEpisode = if (guide.isEmpty()) null else { season, episode ->
                hidePlaylist()
                host.sourceFetchController.requestEpisodeFetch(season, episode)
            },
            itemLayoutRes = guideSkin.guideItemLayoutRes,
            skinBinder = if (guideSkin.guideSkinInstalled) guideSkin::guideSkinBind else null,
            onItemFocused = if (guideSkin.guideSkinInstalled) { item, _ -> guideSkin.updateGuideDetail(item) } else null,
        ) { index ->
            hidePlaylist()
            host.playItem(index)
        }
        host.playlistView.adapter = adapter
        playlistAdapter = adapter
        seriesPlaylistAdapter = adapter
        moviePlaylistAdapter = null
        playlistMode = PlaylistMode.SERIES
        setupSeasonTabs(adapter)
    }

    fun setupCollectionPlaylist(items: List<PlaybackItem>) {
        val groups = computeMovieGroups(items)
        val adapter = MoviePlaylistAdapter(
            items,
            groups,
            itemLayoutRes = guideSkin.guideItemLayoutRes,
            skinBinder = if (guideSkin.guideSkinInstalled) guideSkin::guideSkinBind else null,
            onItemFocused = if (guideSkin.guideSkinInstalled) { item, _ -> guideSkin.updateGuideDetail(item) } else null,
        ) { index ->
            hidePlaylist()
            host.playItem(index)
        }
        host.playlistView.adapter = adapter
        playlistAdapter = adapter
        moviePlaylistAdapter = adapter
        seriesPlaylistAdapter = null
        movieGroups = groups
        playlistMode = PlaylistMode.COLLECTION
        setupCollectionTabs(adapter, groups)
    }

    fun setupSeasonTabs(adapter: PlaylistAdapter) {
        host.seasonTabsContainer.removeAllViews()
        seasonTabs.clear()

        val seasons = adapter.availableSeasons
        if (seasons.isEmpty()) {
            host.seasonTabsContainer.visibility = View.GONE
            return
        }

        host.seasonTabsContainer.visibility = View.VISIBLE

        // Add season tabs
        for (season in seasons) {
            val tab = createSeasonTab("S$season", season, adapter)
            host.seasonTabsContainer.addView(tab)
            seasonTabs.add(tab)
        }

        // Default to the season of the currently playing episode
        val currentSeason = host.payload?.items?.getOrNull(host.currentIndex)?.season
        val defaultTabIndex = if (currentSeason != null) {
            seasons.indexOf(currentSeason).takeIf { it >= 0 } ?: 0
        } else {
            0
        }

        if (seasonTabs.isNotEmpty()) {
            selectSeasonTab(defaultTabIndex, adapter)
        }
    }

    fun createSeasonTab(label: String, season: Int?, adapter: PlaylistAdapter): TextView {
        val tab = TextView(activity)
        tab.text = label
        tab.textSize = 13f
        tab.setTextColor(0xFFFFFFFF.toInt())
        tab.setPadding(28, 14, 28, 14)
        tab.setBackgroundResource(R.drawable.season_tab_selector)
        tab.isFocusable = true
        tab.isFocusableInTouchMode = true
        tab.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD)
        tab.letterSpacing = 0.04f
        tab.elevation = 4f

        val params = android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.marginEnd = 10
        tab.layoutParams = params

        tab.setOnClickListener {
            val index = seasonTabs.indexOf(tab)
            if (index != -1) {
                selectSeasonTab(index, adapter)
            }
        }

        guideSkin.applyGuideTabStyle(tab)
        return tab
    }

    fun selectSeasonTab(index: Int, adapter: PlaylistAdapter, scrollToTop: Boolean = true) {
        // Update tab selection states
        seasonTabs.forEachIndexed { i, tab ->
            tab.isSelected = (i == index)
        }

        // Filter adapter to the selected season
        val season = adapter.availableSeasons.getOrNull(index)
        adapter.filterBySeason(season)

        // Scroll to top (unless explicitly disabled)
        if (scrollToTop) {
            host.playlistView.scrollToPosition(0)
        }
    }

    fun setupCollectionTabs(adapter: MoviePlaylistAdapter, groups: MovieGroups) {
        seasonTabs.clear()
        movieTabs.clear()
        host.seasonTabsContainer.removeAllViews()

        if (groups.groups.isEmpty()) {
            host.seasonTabsContainer.visibility = View.GONE
            return
        }

        if (groups.groups.size <= 1) {
            host.seasonTabsContainer.visibility = View.GONE
            // Ensure adapter still shows first group
            adapter.showGroup(0, force = true)
            return
        }

        host.seasonTabsContainer.visibility = View.VISIBLE

        groups.groups.forEachIndexed { index, group ->
            val label = "${group.name.uppercase()} (${group.fileIndices.size})"
            val tab = createMovieTab(label, index, group.name, adapter)
            host.seasonTabsContainer.addView(tab)
            movieTabs.add(MovieTab(tab, index, group.name))
        }

        selectMovieTab(0, adapter, scrollToTop = false, forceAdapterUpdate = true)
    }

    fun createMovieTab(label: String, groupIndex: Int, groupName: String, adapter: MoviePlaylistAdapter): TextView {
        val tab = TextView(activity)
        tab.text = label
        tab.textSize = 13f
        tab.setTextColor(0xFFFFFFFF.toInt())
        tab.setPadding(28, 14, 28, 14)
        tab.setBackgroundResource(R.drawable.season_tab_selector)
        tab.isFocusable = true
        tab.isFocusableInTouchMode = true
        tab.typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.BOLD)
        tab.letterSpacing = 0.04f
        tab.elevation = 4f

        val params = android.widget.LinearLayout.LayoutParams(
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT,
            android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
        )
        params.marginEnd = 10
        tab.layoutParams = params

        tab.setOnClickListener {
            selectMovieTab(groupIndex, adapter)
        }

        guideSkin.applyGuideTabStyle(tab)
        return tab
    }

    fun selectMovieTab(
        groupIndex: Int,
        adapter: MoviePlaylistAdapter,
        scrollToTop: Boolean = true,
        forceAdapterUpdate: Boolean = false,
    ) {
        movieTabs.forEach { movieTab ->
            movieTab.view.isSelected = movieTab.groupIndex == groupIndex
        }
        val changed = adapter.showGroup(groupIndex, force = forceAdapterUpdate)
        if ((scrollToTop || changed) && adapter.itemCount > 0) {
            host.playlistView.scrollToPosition(0)
        }
    }

    // Playlist
    fun showPlaylist() {
        android.util.Log.d("PlaylistNav", "showPlaylist: Starting - playlistMode=$playlistMode")

        if (playlistMode == PlaylistMode.NONE || playlistAdapter == null) {
            android.util.Log.d("PlaylistNav", "showPlaylist: Exiting early - no playlist adapter")
            return
        }

        playlistVisible = true
        host.playlistOverlay.visibility = View.VISIBLE
        guideSkin.seedGuideSkinChrome()

        when (playlistMode) {
            PlaylistMode.SERIES -> alignSeriesTabsForCurrentEpisode()
            PlaylistMode.COLLECTION -> alignMovieTabsForCurrentItem()
            else -> Unit
        }

        val activePosition = playlistAdapter?.getActiveItemPosition() ?: -1
        android.util.Log.d("PlaylistNav", "showPlaylist: activePosition=$activePosition, adapter.itemCount=${host.playlistView.adapter?.itemCount}")

        if (activePosition != -1) {
            host.playlistView.post {
                android.util.Log.d("PlaylistNav", "showPlaylist: Scrolling to position $activePosition")
                host.playlistView.scrollToPosition(activePosition)
                host.playlistView.postDelayed({
                    val viewHolder = host.playlistView.findViewHolderForAdapterPosition(activePosition)
                    android.util.Log.d("PlaylistNav", "showPlaylist: ViewHolder found=${viewHolder != null} for position $activePosition")
                    if (viewHolder != null) {
                        android.util.Log.d("PlaylistNav", "showPlaylist: Requesting focus on viewHolder at position $activePosition")
                        viewHolder.itemView.requestFocus()
                    } else {
                        android.util.Log.d("PlaylistNav", "showPlaylist: Requesting focus on playlistView itself")
                        host.playlistView.requestFocus()
                    }
                }, 100)
            }
        } else {
            host.playlistView.post {
                android.util.Log.d("PlaylistNav", "showPlaylist: No active position, requesting focus on playlistView")
                host.playlistView.requestFocus()
            }
        }
    }

    fun alignSeriesTabsForCurrentEpisode() {
        val adapter = seriesPlaylistAdapter ?: return
        val currentSeason = host.payload?.items?.getOrNull(host.currentIndex)?.season ?: return
        if (currentSeason <= 0 || seasonTabs.isEmpty()) return
        val seasons = adapter.availableSeasons
        val tabIndex = seasons.indexOf(currentSeason)
        if (tabIndex >= 0 && tabIndex < seasonTabs.size) {
            selectSeasonTab(tabIndex, adapter, scrollToTop = false)
        }
    }

    fun alignMovieTabsForCurrentItem() {
        val adapter = moviePlaylistAdapter ?: return
        val groups = movieGroups ?: return
        val groupIndex = groups.getGroupIndex(host.currentIndex)
        if (groupIndex >= 0) {
            selectMovieTab(groupIndex, adapter, scrollToTop = false)
        }
    }

    fun getNextPlayableIndex(fromIndex: Int): Int? {
        val model = host.payload ?: return null

        // For series content, use pre-computed navigation map from Flutter
        // This mirrors mobile video_player_screen.dart's navigation exactly
        if (playlistMode == PlaylistMode.SERIES && model.nextEpisodeMap.isNotEmpty()) {
            val nextIndex = model.nextEpisodeMap[fromIndex]
            android.util.Log.d("AndroidTvPlayer", "getNextPlayableIndex - series mode, fromIndex: $fromIndex, nextIndex: $nextIndex")
            return nextIndex
        }

        // For collections, continue using movie group logic
        if (playlistMode == PlaylistMode.COLLECTION) {
            val groups = movieGroups ?: return null
            val currentGroup = groups.findGroupContaining(fromIndex) ?: return null
            val source = currentGroup.fileIndices

            if (source.isNullOrEmpty()) {
                return null
            }

            val positionInGroup = source.indexOf(fromIndex)
            if (positionInGroup == -1) {
                return null
            }

            return if (positionInGroup + 1 < source.size) {
                source[positionInGroup + 1]
            } else {
                null
            }
        }

        // Fallback for single/unknown modes: simple sequential navigation
        val next = fromIndex + 1
        return if (next < model.items.size) next else null
    }

    fun getPrevPlayableIndex(fromIndex: Int): Int? {
        val model = host.payload ?: return null

        // For series content, use pre-computed navigation map from Flutter
        if (playlistMode == PlaylistMode.SERIES && model.prevEpisodeMap.isNotEmpty()) {
            val prevIndex = model.prevEpisodeMap[fromIndex]
            android.util.Log.d("AndroidTvPlayer", "getPrevPlayableIndex - series mode, fromIndex: $fromIndex, prevIndex: $prevIndex")
            return prevIndex
        }

        // For collections, use movie group logic
        if (playlistMode == PlaylistMode.COLLECTION) {
            val groups = movieGroups ?: return null
            val currentGroup = groups.findGroupContaining(fromIndex) ?: return null
            val source = currentGroup.fileIndices

            if (source.isNullOrEmpty()) {
                return null
            }

            val positionInGroup = source.indexOf(fromIndex)
            if (positionInGroup <= 0) {
                return null
            }

            return source[positionInGroup - 1]
        }

        // Fallback for single/unknown modes: simple sequential navigation
        val prev = fromIndex - 1
        return if (prev >= 0) prev else null
    }

    fun computeMovieGroups(items: List<PlaybackItem>): MovieGroups {
        if (items.isEmpty()) {
            return MovieGroups(emptyList())
        }

        // Check if payload contains collection groups
        val payloadGroups = host.payload?.collectionGroups
        if (!payloadGroups.isNullOrEmpty()) {
            // Use groups from Flutter payload
            val groups = payloadGroups.map { group ->
                CollectionGroup(
                    name = group.optString("name", "Group"),
                    fileIndices = mutableListOf<Int>().apply {
                        val indicesArray = group.optJSONArray("fileIndices")
                        if (indicesArray != null) {
                            for (i in 0 until indicesArray.length()) {
                                add(indicesArray.getInt(i))
                            }
                        }
                    }
                )
            }.filter { it.fileIndices.isNotEmpty() } // Only include non-empty groups

            android.util.Log.d("AndroidTvPlayer", "Using ${groups.size} collection groups from payload")
            return MovieGroups(groups)
        }

        // Fallback: compute Main/Extras groups based on file size (40% threshold)
        // This maintains backward compatibility
        var maxSize = -1L
        items.forEach { item ->
            val size = item.sizeBytes ?: -1L
            if (size > maxSize) {
                maxSize = size
            }
        }

        val threshold = if (maxSize > 0) (maxSize * 0.40).toLong() else -1L
        val main = mutableListOf<Int>()
        val extras = mutableListOf<Int>()

        items.forEachIndexed { index, item ->
            val size = item.sizeBytes ?: -1L
            val isSmall = threshold > 0 && size > 0 && size < threshold
            if (isSmall) {
                extras.add(index)
            } else {
                main.add(index)
            }
        }

        if (main.isEmpty()) {
            main.addAll(extras)
            extras.clear()
        }

        val yearRegex = Regex("\\b(19|20)\\d{2}\\b")
        fun yearOf(index: Int): Int? {
            val match = yearRegex.find(items[index].title)
            return match?.value?.toIntOrNull()
        }
        fun sizeOf(index: Int): Long = items[index].sizeBytes ?: -1L

        main.sortWith { a, b ->
            val yearA = yearOf(a)
            val yearB = yearOf(b)
            when {
                yearA != null && yearB != null && yearA != yearB -> yearA - yearB
                else -> sizeOf(b).compareTo(sizeOf(a))
            }
        }

        extras.sortWith { a, b ->
            sizeOf(a).compareTo(sizeOf(b))
        }

        val groups = mutableListOf<CollectionGroup>()
        if (main.isNotEmpty()) {
            groups.add(CollectionGroup("Main", main))
        }
        if (extras.isNotEmpty()) {
            groups.add(CollectionGroup("Extras", extras))
        }

        android.util.Log.d("AndroidTvPlayer", "Computed ${groups.size} collection groups (fallback)")
        return MovieGroups(groups)
    }

    fun hidePlaylist() {
        playlistVisible = false
        host.playlistOverlay.visibility = View.GONE
        guideSkin.gdPop?.visibility = View.GONE
    }
}
