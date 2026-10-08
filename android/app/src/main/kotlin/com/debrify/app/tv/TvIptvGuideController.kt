package com.debrify.app.tv

import android.os.Handler
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import com.debrify.app.R

@OptIn(UnstableApi::class)
internal class TvIptvGuideController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val controlsMenuVisible: Boolean
        var currentIptvIndex: Int
        fun hideIptvEpgPane(): Unit
        val iptvBrowseHandler: Handler
        val iptvChannelStartController: TvIptvChannelStartController
        var iptvChannels: MutableList<IptvChannelEntry>
        val iptvNextButton: AppCompatButton?
        val iptvPrevButton: AppCompatButton?
        var iptvSourceId: String?
        val iptvSources: List<IptvSourceEntry>
        var iptvStartOverActive: Boolean
        val iptvStartOverController: TvIptvStartOverController
        var iptvStartOverLoading: Boolean
        var iptvStartOverTimelineVisible: Boolean
        val iptvZapBannerController: TvIptvZapBannerController
        val isIptvMode: Boolean
        val player: ExoPlayer?
        fun resetSubtitleState(): Unit
        val sourceSwitchController: TvSourceSwitchController
        val titleView: TextView
        val trackSelector: DefaultTrackSelector?
        fun updateIptvControlPresentation(entry: IptvChannelEntry?): Unit
        fun updateIptvGuideCurrentName(): Unit
    }
    internal val pager = TvIptvZapPager(activity, host, this)
    internal val navigator = TvIptvChannelNavigator(activity, host, this)

    // Xtream series audio memory: the `<playlistId>::<seriesId>` key the Flutter
    // store uses, and the language resolved from it at launch. A native audio
    // pick updates the TrackSelector's preferred language (so it carries to the
    // next episode) and rounds back to Flutter to persist. Null unless this
    // IPTV session is an Xtream series.
    internal var iptvSeriesAudioKey: String? = null
    internal var iptvPreferredAudioLang: String? = null
    internal var iptvGuideOverlay: View? = null
    internal var iptvGuideList: RecyclerView? = null
    internal var iptvGuideSearch: android.widget.EditText? = null
    internal var iptvGuideTitle: TextView? = null
    internal var iptvGuideCountText: TextView? = null
    internal var iptvSourceButton: AppCompatButton? = null
    internal var iptvCategoryButton: AppCompatButton? = null
    internal var iptvBrowseLoading: View? = null
    internal var iptvChannelAdapter: IptvChannelAdapter? = null
    internal var iptvGuideVisible = false
    internal var iptvBrowseChannels = mutableListOf<IptvChannelEntry>()

    // The user's channel lists, shipped once at launch (never per channel —
    // the channel payload is already capped for size on the Dart side).
    internal var iptvLists = mutableListOf<IptvListEntry>()
    internal var iptvCategories = mutableListOf<String>()
    internal var iptvSourceName: String = "IPTV"
    internal var iptvContentType: String = "live"
    internal var iptvSelectedCategory: String? = null
    internal var iptvBrowseToken = 0
    internal val iptvZapPageSize = 200
    internal var iptvZapPagingActive = false
    internal var iptvZapCategory: String? = null
    internal var iptvZapSourceId: String? = null
    internal var iptvZapSourceName: String = "IPTV"
    internal var iptvZapContentType: String = "live"
    internal var iptvZapCategories = mutableListOf<String>()
    internal var iptvZapCategoryTotal = 0
    internal var iptvZapRequestToken = 0
    internal var iptvZapRequestInFlight = false
    internal val iptvZapPendingInputs = java.util.ArrayDeque<Int>()
    internal var iptvZapDrainingInputs = false
    internal var iptvGuideUsesZapWindow = false
    internal var iptvUiContextToken = 0
    internal var iptvZapOwnsUiContext = false
    // Search always spans the whole source. Keep the visible category context
    // aside while the search field/results are active so Back/Close/Browse can
    // restore it exactly when the user leaves without tuning another channel.
    internal var iptvAllCategorySearchActive = false
    private var iptvSearchSavedCategory: String? = null
    internal var iptvSearchSavedChannels = mutableListOf<IptvChannelEntry>()
    private var iptvSearchSavedCategories = mutableListOf<String>()
    private var iptvSearchSavedUsesZapWindow = false
    private var iptvSearchSavedZapOwnsUiContext = false
    internal val iptvZapMaxHiddenWindow = 600
    internal var iptvZapCachedOriginCategory: String? = null
    internal var iptvZapCachedDirection = 0
    internal var iptvZapCachedChannels = mutableListOf<IptvChannelEntry>()
    internal var iptvZapCachedOffset = 0
    internal var iptvZapCachedTotal = 0
    internal var iptvZapCachedCategory: String? = null
    internal var iptvZapCachedCategories = emptyList<String>()

    fun showIptvGuide() {
        if (host.iptvChannels.getOrNull(host.currentIptvIndex)?.isLive != true) return
        // The banner is attached last to the content view (topmost) — it must
        // never float over the guide.
        host.iptvZapBannerController.hideIptvZapBanner()
        iptvGuideVisible = true
        iptvGuideOverlay?.animate()?.cancel() // cancel any pending hide animation
        iptvGuideOverlay?.visibility = View.VISIBLE
        iptvGuideOverlay?.alpha = 0f
        iptvGuideOverlay?.animate()?.alpha(1f)?.setDuration(200)?.start()

        host.hideIptvEpgPane()
        refreshIptvBrowserChrome()
        host.updateIptvGuideCurrentName()

        // Focus the list and scroll to current channel
        iptvGuideList?.post {
            val currentPos = iptvChannelAdapter?.getCurrentChannelPosition() ?: 0
            iptvGuideList?.scrollToPosition(currentPos)
            iptvGuideList?.postDelayed({
                val holder = iptvGuideList?.findViewHolderForAdapterPosition(currentPos)
                holder?.itemView?.requestFocus()
            }, 150)
        }
    }

    fun hideIptvGuide() {
        restoreIptvCategoryAfterSearch()
        iptvGuideVisible = false
        // Deferred: hide is often reached from inside a guide row's own click
        // dispatch, and trimming can remove hundreds of rows (including the
        // focused one) from the RecyclerView mid-event. Posting lets the click
        // finish first; after a channel pick the trim then no-ops because the
        // zap session has already replaced the window.
        host.iptvBrowseHandler.post { pager.trimHiddenIptvZapWindow() }
        host.hideIptvEpgPane()
        iptvGuideOverlay?.animate()?.cancel() // cancel any pending show animation
        iptvGuideOverlay?.animate()?.alpha(0f)?.setDuration(150)?.withEndAction {
            iptvGuideOverlay?.visibility = View.GONE
        }?.start()
    }

    fun beginIptvAllCategorySearch() {
        if (iptvContentType != "live" || iptvAllCategorySearchActive) return
        iptvAllCategorySearchActive = true
        iptvSearchSavedCategory = iptvSelectedCategory
        iptvSearchSavedChannels =
            iptvChannelAdapter?.entriesSnapshot()?.toMutableList()
                ?: iptvBrowseChannels.toMutableList()
        iptvSearchSavedCategories = iptvCategories.toMutableList()
        iptvSearchSavedUsesZapWindow = iptvGuideUsesZapWindow
        iptvSearchSavedZapOwnsUiContext = iptvZapOwnsUiContext

        // Search is a temporary browsing context. Invalidate any page that was
        // about to update the category window and send subsequent browse
        // requests without a category filter.
        iptvUiContextToken++
        iptvBrowseToken++
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()
        iptvZapOwnsUiContext = false
        iptvSelectedCategory = null
        iptvBrowseLoading?.visibility = View.GONE
        refreshIptvBrowserChrome()
    }

    /**
     * Restore the category/list that was visible before Search got focus.
     * Returning true lets callers avoid a redundant bridge request and keep
     * the guide responsive.
     */
    fun restoreIptvCategoryAfterSearch(): Boolean {
        if (!iptvAllCategorySearchActive) return false
        val savedCategory = iptvSearchSavedCategory
        val savedChannels = iptvSearchSavedChannels.toMutableList()
        val savedCategories = iptvSearchSavedCategories.toMutableList()
        val savedUsesZapWindow = iptvSearchSavedUsesZapWindow
        val savedZapOwnsUiContext = iptvSearchSavedZapOwnsUiContext
        clearIptvAllCategorySearchState()

        // A submitted All-categories result may still be returning. Make it
        // stale before putting the original category window back.
        iptvUiContextToken++
        iptvBrowseToken++
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()
        iptvBrowseLoading?.visibility = View.GONE
        iptvSelectedCategory = savedCategory
        iptvCategories = savedCategories
        iptvBrowseChannels = savedChannels
        iptvGuideUsesZapWindow = savedUsesZapWindow
        iptvZapOwnsUiContext = savedZapOwnsUiContext
        iptvGuideSearch?.setText("")
        iptvChannelAdapter?.updateChannels(savedChannels)
        refreshIptvBrowserChrome()
        host.updateIptvGuideCurrentName()
        if (savedZapOwnsUiContext && !iptvZapPagingActive) {
            host.iptvChannels.getOrNull(host.currentIptvIndex)?.let {
                pager.bootstrapInitialIptvZapPaging(it)
            }
        }
        return true
    }

    fun commitIptvAllCategorySearch() {
        if (!iptvAllCategorySearchActive) return
        clearIptvAllCategorySearchState()
    }

    fun clearIptvAllCategorySearchState() {
        iptvAllCategorySearchActive = false
        iptvSearchSavedCategory = null
        iptvSearchSavedChannels = mutableListOf()
        iptvSearchSavedCategories = mutableListOf()
        iptvSearchSavedUsesZapWindow = false
        iptvSearchSavedZapOwnsUiContext = false
    }

    fun focusCurrentIptvGuideRow() {
        iptvGuideList?.post {
            val position = iptvChannelAdapter?.getCurrentChannelPosition() ?: 0
            iptvGuideList?.scrollToPosition(position)
            iptvGuideList?.post {
                iptvGuideList?.findViewHolderForAdapterPosition(position)
                    ?.itemView?.requestFocus()
            }
        }
    }

    fun toggleIptvGuide() {
        if (iptvGuideVisible) hideIptvGuide() else showIptvGuide()
    }

    fun refreshIptvBrowserChrome(title: String? = null) {
        iptvSourceButton?.text = iptvSourceName
        iptvCategoryButton?.text = iptvSelectedCategory ?: "All categories"
        iptvGuideTitle?.text = title ?: when (iptvContentType) {
            "vod" -> "Movies"
            "series" -> "Series"
            "episodes" -> "Episodes"
            else -> "Live television"
        }
        iptvGuideCountText?.text = iptvGuideItemCountLabel()

        val modeButtons = listOf(
            "live" to activity.findViewById<AppCompatButton>(R.id.iptv_mode_live),
        )
        modeButtons.forEach { (type, button) ->
            button?.isSelected = iptvContentType == type
        }
        updateIptvCatalogControlVisibility()
    }

    fun updateIptvCatalogControlVisibility() {
        val liveCatalog = iptvContentType == "live"
        val liveVisibility = if (liveCatalog) View.VISIBLE else View.GONE
        activity.findViewById<View>(R.id.iptv_nav_browse)?.visibility = liveVisibility
        activity.findViewById<View>(R.id.iptv_nav_search)?.visibility = liveVisibility
        activity.findViewById<View>(R.id.iptv_filter_bar)?.visibility = liveVisibility

        val sourceVisibility =
            if (liveCatalog && host.iptvSources.isNotEmpty()) View.VISIBLE else View.GONE
        activity.findViewById<View>(R.id.iptv_nav_favorites)?.visibility = sourceVisibility
        activity.findViewById<View>(R.id.iptv_nav_sources)?.visibility = sourceVisibility
        iptvSourceButton?.visibility = sourceVisibility
    }

    fun iptvGuideItemCountLabel(): String {
        val count = if (iptvGuideUsesZapWindow &&
            iptvZapPagingActive &&
            iptvZapCategoryTotal > 0
        ) {
            iptvZapCategoryTotal
        } else {
            iptvBrowseChannels.size
        }
        return "$count items"
    }

    fun selectIptvContentType(contentType: String) {
        if (iptvContentType == contentType) {
            restoreIptvCategoryAfterSearch()
            return
        }
        commitIptvAllCategorySearch()
        iptvContentType = contentType
        iptvSelectedCategory = null
        iptvGuideSearch?.setText("")
        refreshIptvBrowserChrome()
        requestIptvBrowse(action = "browse", query = "")
    }

    fun selectIptvSource(source: IptvSourceEntry) {
        commitIptvAllCategorySearch()
        host.iptvSourceId = source.id
        iptvSourceName = source.name
        iptvSelectedCategory = null
        iptvCategories.clear()
        iptvContentType = when {
            source.isContinue -> "vod"
            source.isFavorites -> "live"
            // A list is a curated mix with no content type of its own. Without
            // this arm a lingering "vod" state would ride through and ask Dart
            // for the wrong slice of the list.
            source.isList -> "live"
            iptvContentType == "episodes" -> if (source.isXtream) "series" else "live"
            !source.isXtream && iptvContentType == "series" -> "live"
            else -> iptvContentType
        }
        iptvGuideSearch?.setText("")
        refreshIptvBrowserChrome()
        requestIptvBrowse(action = "browse")
    }


    fun requestIptvBrowse(
        action: String,
        query: String = iptvGuideSearch?.text?.toString()?.trim().orEmpty(),
        channelUrl: String? = null,
        title: String? = null,
        sourceIdOverride: String? = null,
    ) {
        val channel = MainActivity.getAndroidTvPlayerChannel() ?: return
        val uiContext = ++iptvUiContextToken
        iptvZapOwnsUiContext = false
        iptvZapRequestToken++
        iptvZapRequestInFlight = false
        iptvZapPendingInputs.clear()
        val token = ++iptvBrowseToken
        iptvBrowseLoading?.visibility = View.VISIBLE
        val args = hashMapOf<String, Any?>(
            "action" to action,
            "sourceId" to (sourceIdOverride ?: host.iptvSourceId),
            "contentType" to iptvContentType,
            "category" to iptvSelectedCategory,
            "query" to query,
            "channelUrl" to channelUrl,
            "title" to title,
        )
        channel.invokeMethod(
            "requestIptvBrowse",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {
                    if (token != iptvBrowseToken ||
                        uiContext != iptvUiContextToken ||
                        iptvZapOwnsUiContext
                    ) return
                    iptvBrowseLoading?.visibility = View.GONE
                    val response = result as? Map<*, *> ?: return
                    val keepSearchFocus = iptvGuideSearch?.hasFocus() == true
                    val channels = parseIptvChannels(response["channels"] as? List<*> ?: emptyList<Any>())
                    val playingUrl = host.iptvChannels.getOrNull(host.currentIptvIndex)?.url
                    channels.forEach { it.isCurrent = it.url == playingUrl }
                    iptvGuideUsesZapWindow = false
                    iptvBrowseChannels = channels
                    iptvChannelAdapter?.updateChannels(channels)
                    (response["sourceId"] as? String)?.let { host.iptvSourceId = it }
                    (response["sourceName"] as? String)?.let { iptvSourceName = it }
                    (response["contentType"] as? String)?.let { iptvContentType = it }
                    iptvSelectedCategory =
                        (response["selectedCategory"] as? String)?.takeIf { it.isNotEmpty() }
                            ?: iptvSelectedCategory
                    val categories = (response["categories"] as? List<*>)
                        ?.mapNotNull { it as? String }
                        ?.filter { it.isNotEmpty() }
                        .orEmpty()
                    if (iptvSelectedCategory == null) {
                        iptvCategories = categories.toMutableList()
                    }
                    refreshIptvBrowserChrome(response["title"] as? String ?: title)
                    if (keepSearchFocus) {
                        // RecyclerView updates and the result-focus post below
                        // must not eject the IME after every typed character.
                        iptvGuideSearch?.post {
                            if (iptvGuideVisible) iptvGuideSearch?.requestFocus()
                        }
                    } else if (channels.isNotEmpty()) {
                        iptvGuideList?.scrollToPosition(0)
                        iptvGuideList?.post {
                            iptvGuideList?.findViewHolderForAdapterPosition(0)
                                ?.itemView?.requestFocus()
                        }
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (token != iptvBrowseToken ||
                        uiContext != iptvUiContextToken ||
                        iptvZapOwnsUiContext
                    ) return
                    iptvBrowseLoading?.visibility = View.GONE
                    Toast.makeText(
                        activity,
                        message ?: "Unable to load IPTV catalog",
                        Toast.LENGTH_SHORT,
                    ).show()
                }

                override fun notImplemented() {
                    if (token == iptvBrowseToken &&
                        uiContext == iptvUiContextToken &&
                        !iptvZapOwnsUiContext
                    ) {
                        iptvBrowseLoading?.visibility = View.GONE
                    }
                }
            },
        )
    }
}
