package com.debrify.app.tv

import android.util.Log
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.C
import androidx.media3.exoplayer.hls.HlsManifest
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.subtitle.AddonSubtitleResult
import com.debrify.app.subtitle.AddonSubtitleStatus
import com.debrify.app.subtitle.StremioAddon
import com.debrify.app.subtitle.StremioSubtitle
import com.debrify.app.subtitle.StremioSubtitleService
import com.debrify.app.util.LanguageMapper
import com.debrify.app.util.OffsetRenderersFactory
import com.debrify.app.util.SubtitleSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.util.Locale

@OptIn(UnstableApi::class)
internal class TvSubtitleSourcesController(
    private val activity: AppCompatActivity,
    private val host: Host,
) {
    interface Host {
        val currentIndex: Int
        val currentIptvIndex: Int
        fun dp(value: Int): Int
        val iptvChannels: List<IptvChannelEntry>
        val isIptvMode: Boolean
        val offsetRenderersFactory: OffsetRenderersFactory?
        val payload: PlaybackPayload?
        val player: ExoPlayer?
        val playerPreferences: com.debrify.app.profiles.NativePlayerPreferences
        val stremioSubtitleService: StremioSubtitleService?
        val subtitleController: TvSubtitleController
        val subtitleScope: CoroutineScope
        val subtitleTrackReadiness: SubtitleTrackReadiness
        val trackSelector: DefaultTrackSelector?
        val unifiedMenu: UnifiedMenuController?
    }
    internal val dialogs = TvSubtitleSearchDialogs(activity, host, this)
    internal val stremioSubtitles = mutableListOf<StremioSubtitle>()  // deduped flat view over addonSubtitleResults
    private val addonSubtitleResults = mutableListOf<AddonSubtitleResult>()  // per-addon, ordered/stable
    // Subtitles supplied at launch (e.g. YouTube closed captions). Parsed once
    // from the payload; re-seeded as a provider group on each item instead of
    // an IMDb-keyed addon fetch. Non-empty only for sources that carry their
    // own captions.
    internal val injectedSubtitles = mutableListOf<StremioSubtitle>()
    // When launch-supplied captions are the only subtitles (YouTube), don't
    // auto-enable them — matches YouTube's captions-off default and the phone
    // player. The user turns them on from the subtitle menu.
    private var suppressSubtitleAutoSelect = false
    private val addonFetchTokens = mutableMapOf<String, Int>()  // per-addon retry generation
    internal val failedSubtitleUrls = mutableSetOf<String>()  // external subs that parsed to zero cues — don't re-auto-select
    internal var currentStremioSubtitleIndex: Int = -1  // -1 means no Stremio subtitle selected
    private var subtitleAddonDiscoveryReady = false
    internal var isLoadingStremioSubtitles = false  // Loading state for UI indicator
    internal var userManuallySelectedSubtitle = false  // Track if user manually selected a subtitle
    private var addonSubtitleFetchToken = 0  // Guard against stale async fetches on content switch
    private var manualSubtitleImdbId: String? = null  // Subtitle-only identity override from Search Subtitle
    private var manualSubtitleType: String? = null
    internal var manualSubtitleSeason: Int? = null
    internal var manualSubtitleEpisode: Int? = null
    private var manualSubtitleDisplayLabel: String? = null

    fun resetSubtitleState() {
        host.subtitleController.stopExternalSubtitleRendering()
        stremioSubtitles.clear()
        host.subtitleController.subtitleTracks.clear()   // rebuilt lazily for the new media's embedded tracks
        addonSubtitleResults.clear()
        addonFetchTokens.clear()
        failedSubtitleUrls.clear()
        subtitleSearchResults = emptyList()
        subtitleSearchStatus = ""
        pendingSeriesResult = null
        currentStremioSubtitleIndex = -1
        isLoadingStremioSubtitles = false
        subtitleAddonDiscoveryReady = false
        host.subtitleTrackReadiness.onMediaReplacement()
        host.trackSelector?.let { selector ->
            selector.parameters = selector.parameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(
                    C.TRACK_TYPE_TEXT,
                    host.playerPreferences.getString("player_default_subtitle_language", null) == "off" ||
                        host.playerPreferences.getBoolean("subtitle_only_foreign_audio", false) ||
                        host.playerPreferences.getBoolean("subtitle_forced_only", false),
                )
                .build()
        }
        userManuallySelectedSubtitle = false
        // Re-established by seedInjectedSubtitles() when the next item has
        // launch-supplied captions; cleared here so a non-injected item never
        // inherits the previous item's auto-select suppression.
        suppressSubtitleAutoSelect = false
        manualSubtitleImdbId = null
        manualSubtitleType = null
        manualSubtitleSeason = null
        manualSubtitleEpisode = null
        manualSubtitleDisplayLabel = null
        addonSubtitleFetchToken++
        // Switching content resets the sync offset (it belonged to the previous
        // item's subtitle). The identity-scoped read already returns 0 for the
        // new content, but the embedded renderer offset is push-based and would
        // otherwise keep the previous item's shift — pushing a stale offset onto
        // the next episode's auto-selected subtitles while the UI reads 0.
        SubtitleSettings.resetSyncOffset()
        host.offsetRenderersFactory?.setOffsetUs(0L)
    }

    /**
     * Fetch external subtitles from Stremio addons for the current item.
     * For series: uses payload.imdbId
     * For movie collections: uses per-item IMDB ID from perItemImdbIds cache or requests from Flutter
     */
    fun fetchStremioSubtitles(item: PlaybackItem) {
        val model = host.payload ?: return
        if (model.imdbId?.startsWith("custom-series:") == true && manualSubtitleImdbId.isNullOrEmpty()) return

        // Launch-supplied captions (e.g. YouTube): use them directly and skip
        // addon discovery entirely — the title-based IMDB lookup would be
        // spurious for arbitrary video titles, and these tracks are already
        // known. Seeded as a single provider group so the subtitle menu shows
        // them; not auto-selected (captions stay off until the user picks one).
        //
        // Exception: once the user has manually identified a title (Search
        // Subtitle), honour that identity and fall through to the real addon
        // fetch below — otherwise a re-fetch (source/quality switch, playlist
        // advance) would silently discard their searched subtitles.
        if (injectedSubtitles.isNotEmpty() && manualSubtitleImdbId.isNullOrEmpty()) {
            seedInjectedSubtitles()
            return
        }

        // The addon match is spurious for YouTube (title-based IMDB lookup on
        // arbitrary video titles), so skip addon subtitle fetching for merged
        // YouTube items. (Side-rendering no longer re-prepares the source, so
        // the old merged-audio-drop hazard is gone — manually searched
        // subtitles now work on YouTube too.)
        if (!item.audioUrl.isNullOrEmpty()) {
            stremioSubtitles.clear()
            currentStremioSubtitleIndex = -1
            clearStremioLoadingState()
            return
        }

        val isSeries = model.contentType.lowercase(Locale.US) == "series"
        val type = if (isSeries) "series" else "movie"

        // Set loading state and refresh panel if visible
        isLoadingStremioSubtitles = true
        if (host.subtitleController.subtitleSettingsVisible) {
            host.subtitleController.refreshSubtitlePanelForLoading()
        }

        val manualImdbId = manualSubtitleImdbId
        if (!manualImdbId.isNullOrEmpty()) {
            val manualType = if (manualSubtitleType == "series") "series" else "movie"
            val subtitleItem = if (manualType == "series") {
                item.copy(
                    season = manualSubtitleSeason ?: item.season,
                    episode = manualSubtitleEpisode ?: item.episode
                )
            } else {
                item.copy(season = null, episode = null)
            }
            android.util.Log.d(
                "StremioSubs",
                "Using manual subtitle identity $manualImdbId type=$manualType S${subtitleItem.season}E${subtitleItem.episode}"
            )
            fetchStremioSubtitlesWithImdb(manualImdbId, manualType, subtitleItem)
            return
        }

        // For series, use the shared IMDB ID directly
        if (isSeries) {
            val imdbId = model.imdbId
            if (imdbId.isNullOrEmpty()) {
                stremioSubtitles.clear()
                currentStremioSubtitleIndex = -1
                clearStremioLoadingState()
                return
            }
            fetchStremioSubtitlesWithImdb(imdbId, type, item)
            return
        }

        // For movie collections, use per-item IMDB ID
        val itemIndex = item.index

        // Check if we already have a cached IMDB ID for this item
        if (model.perItemImdbIds.containsKey(itemIndex)) {
            val cachedImdbId = model.perItemImdbIds[itemIndex]
            if (cachedImdbId.isNullOrEmpty()) {
                // Already looked up and found nothing
                android.util.Log.d("StremioSubs", "No cached IMDB ID for item $itemIndex (previously not found)")
                stremioSubtitles.clear()
                currentStremioSubtitleIndex = -1
                clearStremioLoadingState()
                return
            }
            android.util.Log.d("StremioSubs", "Using cached IMDB ID $cachedImdbId for item $itemIndex")
            fetchStremioSubtitlesWithImdb(cachedImdbId, type, item)
            return
        }

        // Check if we have a fallback IMDB ID from payload (e.g., first item lookup)
        val fallbackImdbId = model.imdbId
        if (!fallbackImdbId.isNullOrEmpty() && model.items.size == 1) {
            // Single item, use payload IMDB ID
            android.util.Log.d("StremioSubs", "Single item, using payload IMDB ID: $fallbackImdbId")
            fetchStremioSubtitlesWithImdb(fallbackImdbId, type, item)
            return
        }

        // Request IMDB ID from Flutter for this item
        android.util.Log.d("StremioSubs", "Requesting IMDB ID from Flutter for item $itemIndex")
        val metadataFetchToken = addonSubtitleFetchToken
        requestMovieMetadataFromFlutter(item, itemIndex) { imdbId ->
            if (metadataFetchToken != addonSubtitleFetchToken) {
                android.util.Log.d("StremioSubs", "Content changed during metadata lookup, discarding IMDB result for item $itemIndex")
                return@requestMovieMetadataFromFlutter
            }

            // Cache the result (even if null to prevent repeated requests)
            model.perItemImdbIds[itemIndex] = imdbId
            android.util.Log.d("StremioSubs", "Received IMDB ID from Flutter: $imdbId for item $itemIndex")

            if (imdbId.isNullOrEmpty()) {
                stremioSubtitles.clear()
                currentStremioSubtitleIndex = -1
                clearStremioLoadingState()
                return@requestMovieMetadataFromFlutter
            }

            fetchStremioSubtitlesWithImdb(imdbId, type, item)
        }
    }

    /**
     * Seed the launch-supplied captions ([injectedSubtitles]) as a single
     * OK provider group, so they appear in the subtitle menu without any addon
     * fetch. Not auto-selected: [suppressSubtitleAutoSelect] keeps them off
     * until the user opts in from the menu (matching YouTube's own default).
     */
    private fun seedInjectedSubtitles() {
        suppressSubtitleAutoSelect = true
        val groupName = injectedSubtitles.first().source
        val addon = StremioAddon(
            id = "injected",
            name = groupName,
            manifestUrl = "",
            baseUrl = "",
            resources = listOf("subtitles"),
            types = emptyList(),
            enabled = true
        )
        addonSubtitleResults.clear()
        addonSubtitleResults.add(
            AddonSubtitleResult(
                addon,
                AddonSubtitleStatus.OK,
                injectedSubtitles.filter { isSideRenderableSubtitle(it.url) }
            )
        )
        rebuildFlatStremioSubtitles()
        clearStremioLoadingState()
        refreshSubtitleUiForLoading()
    }

    /**
     * Actually fetch subtitles with a known IMDB ID.
     */
    private fun fetchStremioSubtitlesWithImdb(imdbId: String, type: String, item: PlaybackItem) {
        // Fan out one independent fetch per addon so each keeps its own identity,
        // loading/failed state and can be retried alone. Two guards:
        //  • addonSubtitleFetchToken — invalidates ALL slots on a content switch.
        //  • addonFetchTokens[addonId] — invalidates one addon's in-flight call
        //    when that addon is retried.
        val contentToken = addonSubtitleFetchToken
        val addons = host.stremioSubtitleService?.getSubtitleAddons() ?: emptyList()
        subtitleAddonDiscoveryReady = true
        addonSubtitleResults.clear()
        addons.forEach { addonSubtitleResults.add(AddonSubtitleResult(it, AddonSubtitleStatus.LOADING)) }
        isLoadingStremioSubtitles = addons.isNotEmpty()
        rebuildFlatStremioSubtitles()
        refreshSubtitleUiForLoading()

        addons.forEach { launchAddonSubtitleFetch(it, type, imdbId, item, contentToken) }
        tryAutoSelectAddonSubtitle()
    }

    private fun launchAddonSubtitleFetch(
        addon: StremioAddon,
        type: String,
        imdbId: String,
        item: PlaybackItem,
        contentToken: Int
    ) {
        val slotToken = (addonFetchTokens[addon.id] ?: 0) + 1
        addonFetchTokens[addon.id] = slotToken
        setAddonSubtitleSlot(addon.id, AddonSubtitleStatus.LOADING, emptyList(), null)
        isLoadingStremioSubtitles = true   // covers single-addon retry too
        refreshSubtitleUiForLoading()

        host.subtitleScope.launch {
            val result = try {
                val subs = (host.stremioSubtitleService?.fetchSubtitlesForAddon(
                    addon = addon,
                    type = type,
                    imdbId = imdbId,
                    season = if (type == "series") item.season else null,
                    episode = if (type == "series") item.episode else null
                ) ?: emptyList()).filter { isSideRenderableSubtitle(it.url) }
                AddonSubtitleResult(addon, AddonSubtitleStatus.OK, subs)
            } catch (e: Exception) {
                android.util.Log.w("StremioSubs", "${addon.name} subtitle fetch failed: ${e.message}")
                AddonSubtitleResult(addon, AddonSubtitleStatus.FAILED, emptyList(), e.message)
            }

            if (contentToken != addonSubtitleFetchToken) return@launch      // content switched
            if (slotToken != addonFetchTokens[addon.id]) return@launch      // superseded by a retry

            setAddonSubtitleSlot(addon.id, result.status, result.subtitles, result.error)
            rebuildFlatStremioSubtitles()
            isLoadingStremioSubtitles =
                addonSubtitleResults.any { it.status == AddonSubtitleStatus.LOADING }
            tryAutoSelectAddonSubtitle()   // no-ops once a subtitle is selected
            // When the LAST addon finishes a manual "Fix movie" search with nothing
            // usable, tell the user (the old merged fetch showed this toast).
            if (!isLoadingStremioSubtitles && stremioSubtitles.isEmpty() && !manualSubtitleImdbId.isNullOrEmpty()) {
                Toast.makeText(activity, "No online subtitles found for this title", Toast.LENGTH_SHORT).show()
            }
            refreshSubtitleUiForLoading()
        }
    }

    private fun setAddonSubtitleSlot(
        addonId: String,
        status: AddonSubtitleStatus,
        subs: List<StremioSubtitle>,
        error: String?
    ) {
        val i = addonSubtitleResults.indexOfFirst { it.addon.id == addonId }
        if (i >= 0) {
            addonSubtitleResults[i] =
                addonSubtitleResults[i].copy(status = status, subtitles = subs, error = error)
        }
    }

    /** Rebuild the deduped flat [stremioSubtitles] view, re-pinning the active
     *  selection by URL so a late-arriving addon can't shift the user's pick. */
    private fun rebuildFlatStremioSubtitles() {
        val activeUrl = if (currentStremioSubtitleIndex >= 0)
            stremioSubtitles.getOrNull(currentStremioSubtitleIndex)?.url else null
        val seen = HashSet<String>()
        stremioSubtitles.clear()
        for (r in addonSubtitleResults) {
            for (s in r.subtitles) {
                if (s.url.isNotEmpty() && seen.add(s.url)) stremioSubtitles.add(s)
            }
        }
        currentStremioSubtitleIndex =
            if (activeUrl != null) stremioSubtitles.indexOfFirst { it.url == activeUrl } else -1
    }

    /** Retry a single addon's subtitle fetch (bound to the col3 "retry" row). */
    private fun retryAddonSubtitles(addonId: String) {
        val model = host.payload ?: return
        val addon = addonSubtitleResults.firstOrNull { it.addon.id == addonId }?.addon ?: return
        val item = model.items.getOrNull(host.currentIndex) ?: return
        // Mirror fetchStremioSubtitles' id resolution: multi-item movie collections
        // resolve per-item via perItemImdbIds (payload.imdbId is null for them).
        val imdbId = manualSubtitleImdbId ?: model.perItemImdbIds[item.index] ?: model.imdbId ?: return
        val type = if ((manualSubtitleType ?: model.contentType).lowercase(Locale.US) == "series")
            "series" else "movie"
        val subtitleItem = if (type == "series") {
            item.copy(
                season = manualSubtitleSeason ?: item.season,
                episode = manualSubtitleEpisode ?: item.episode
            )
        } else item
        launchAddonSubtitleFetch(addon, type, imdbId, subtitleItem, addonSubtitleFetchToken)
    }

    /** Repaint whichever subtitle surface is showing (unified menu or legacy panel). */
    private fun refreshSubtitleUiForLoading() {
        if (host.unifiedMenu?.isVisible == true) host.unifiedMenu?.render()
        if (host.subtitleController.subtitleSettingsVisible) host.subtitleController.refreshSubtitlePanelForLoading()
    }

    /**
     * Clear Stremio subtitle loading state and refresh panel if visible.
     */
    fun clearStremioLoadingState() {
        isLoadingStremioSubtitles = false
        subtitleAddonDiscoveryReady = true
        tryAutoSelectAddonSubtitle()
        if (host.subtitleController.subtitleSettingsVisible) {
            host.subtitleController.refreshSubtitlePanelForLoading()
        }
    }

    fun applyManualSubtitleIdentity(
        result: SubtitleCatalogResult,
        season: Int?,
        episode: Int?
    ) {
        val currentItem = dialogs.getCurrentSubtitleSearchItem()
        if (currentItem == null) {
            Toast.makeText(activity, "No current video to search", Toast.LENGTH_SHORT).show()
            return
        }

        val type = if (result.type == "series") "series" else "movie"
        if (type == "series" && (season == null || episode == null || season <= 0 || episode <= 0)) {
            dialogs.showSeasonEpisodePrompt(result)
            return
        }

        addonSubtitleFetchToken++
        manualSubtitleImdbId = result.imdbId
        manualSubtitleType = type
        manualSubtitleSeason = if (type == "series") season else null
        manualSubtitleEpisode = if (type == "series") episode else null
        manualSubtitleDisplayLabel = buildManualSubtitleDisplayLabel(
            result,
            type,
            manualSubtitleSeason,
            manualSubtitleEpisode
        )

        // Tear down any side-rendered subtitle before switching identity —
        // otherwise its cues keep drawing while the panel shows nothing selected.
        host.subtitleController.stopExternalSubtitleRendering()

        stremioSubtitles.clear()
        currentStremioSubtitleIndex = -1
        userManuallySelectedSubtitle = false
        isLoadingStremioSubtitles = true

        host.trackSelector?.let { selector ->
            selector.parameters = selector.parameters.buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
        }

        if (host.subtitleController.subtitleSettingsVisible) {
            host.subtitleController.refreshSubtitlePanelForLoading()
        }

        val subtitleItem = if (type == "series") {
            currentItem.copy(season = season, episode = episode)
        } else {
            currentItem.copy(season = null, episode = null)
        }

        Toast.makeText(activity, "Searching subtitles for ${result.name}", Toast.LENGTH_SHORT).show()
        fetchStremioSubtitlesWithImdb(result.imdbId, type, subtitleItem)
    }

    fun currentSubtitleIdentityLabel(): String {
        val manualLabel = manualSubtitleDisplayLabel?.trim()
        if (!manualLabel.isNullOrEmpty()) {
            return "Subtitles for $manualLabel"
        }

        val detectedTitle = dialogs.getCurrentSubtitleSearchItem()
            ?.let { buildSubtitleSearchInitialQuery(it).trim() }
            ?.takeIf { it.isNotEmpty() }

        return if (detectedTitle != null) {
            "Detected: $detectedTitle"
        } else {
            "Detected title unavailable"
        }
    }

    /** Apply source priority once tracks and any higher-priority addons are ready. */
    fun tryAutoSelectAddonSubtitle() {
        val currentPlayer = host.player ?: return
        val defaultSubtitleLang = host.playerPreferences.getString("player_default_subtitle_language", null)
        val targetLanguage = defaultSubtitleLang ?: "en"
        val tracks = currentPlayer.currentTracks
        val positions = mutableListOf<Pair<Tracks.Group, Int>>()
        val candidates = mutableListOf<EmbeddedSubtitleCandidate>()
        for (group in tracks.groups) {
            // A manual subtitle identity search explicitly asks for addon results.
            if (!manualSubtitleImdbId.isNullOrEmpty()) break
            if (group.type != C.TRACK_TYPE_TEXT) continue
            for (i in 0 until group.length) {
                val format = group.getTrackFormat(i)
                positions.add(group to i)
                candidates.add(EmbeddedSubtitleCandidate(
                    supported = group.isTrackSupported(i),
                    selected = group.isTrackSelected(i),
                    matchesLanguage = LanguageMapper.matchesLanguage(targetLanguage, format.language) ||
                        (!host.playerPreferences.getBoolean("subtitle_forced_only", false) &&
                            (LanguageMapper.matchesLanguage(targetLanguage, format.label) ||
                                LanguageMapper.matchesLanguage(targetLanguage, format.id))),
                    defaultTrack = format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0,
                    forcedTrack = format.selectionFlags and C.SELECTION_FLAG_FORCED != 0,
                    undeclaredHlsCaption = isUndeclaredHlsCaption(
                        isHls = currentPlayer.currentManifest is HlsManifest,
                        mimeType = format.sampleMimeType,
                        accessibilityChannel = format.accessibilityChannel,
                        language = format.language,
                    ),
                ))
            }
        }
        when (val choice = chooseAutomaticSubtitle(
            tracksReady = host.subtitleTrackReadiness.canSelect(currentPlayer.playbackState == Player.STATE_READY),
            preference = defaultSubtitleLang,
            manualSelection = userManuallySelectedSubtitle,
            suppressed = suppressSubtitleAutoSelect,
            addonSelected = currentStremioSubtitleIndex >= 0,
            audioAllowsSubtitles = audioAllowsAutomaticSubtitles(
                onlyForeignAudio = host.playerPreferences.getBoolean("subtitle_only_foreign_audio", false),
                preferredAudio = host.playerPreferences.getString("player_default_audio_language", null),
                selectedAudio = selectedAudioLanguage(tracks),
            ),
            forcedOnly = host.playerPreferences.getBoolean("subtitle_forced_only", false),
            candidates = candidates,
            sourcePriority = SubtitleSettings.getSubtitleSourcePriority(activity),
            addonDiscoveryReady = subtitleAddonDiscoveryReady,
            addons = addonSubtitleResults.map { slot ->
                val eligible = slot.subtitles.indices.filter { slot.subtitles[it].url !in failedSubtitleUrls }
                val matching = eligible.filter {
                    val subtitle = slot.subtitles[it]
                    LanguageMapper.matchesLanguage(targetLanguage, subtitle.lang) ||
                        (targetLanguage.equals("pt-BR", ignoreCase = true) &&
                            LanguageMapper.matchesLanguage(targetLanguage, subtitle.label))
                }
                AddonSubtitleCandidate(
                    addonId = slot.addon.priorityId,
                    loading = slot.status == AddonSubtitleStatus.LOADING,
                    matchingIndices = matching + if (defaultSubtitleLang == null) eligible.filter { it !in matching } else emptyList(),
                )
            },
        )) {
            SubtitleAutoSelection.Off -> {
                if (currentStremioSubtitleIndex >= 0 || host.subtitleController.externalSubtitleActive) {
                    host.subtitleController.stopExternalSubtitleRendering() // invalidates in-flight addon downloads
                    currentStremioSubtitleIndex = -1
                }
                host.trackSelector?.let { selector ->
                    if (!selector.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)) {
                        selector.parameters = selector.parameters.buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                            .build()
                    }
                }
                return
            }
            SubtitleAutoSelection.Wait, SubtitleAutoSelection.Keep -> return
            is SubtitleAutoSelection.Embedded -> {
                val (group, index) = positions[choice.index]
                if (!group.isTrackSelected(index)) {
                    host.trackSelector?.let { selector ->
                        selector.parameters = selector.parameters.buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, listOf(index)))
                            .build()
                    }
                }
                return
            }
            is SubtitleAutoSelection.AddonTrack -> {
                val sub = addonSubtitleResults.firstOrNull { it.addon.priorityId == choice.addonId }
                    ?.subtitles?.getOrNull(choice.index) ?: return
                currentStremioSubtitleIndex = stremioSubtitles.indexOfFirst { it.url == sub.url }
                host.subtitleController.loadStremioSubtitle(sub)
            }
            SubtitleAutoSelection.Addon -> return
        }

    }

    // Inline subtitle-search state (rendered in the Subtitles → Fix movie column).
    internal var subtitleSearchResults: List<SubtitleCatalogResult> = emptyList()
    internal var subtitleSearchStatus: String = ""
    internal var pendingSeriesResult: SubtitleCatalogResult? = null
    private var pendingSeason: Int = 1
    private var pendingEpisode: Int = 1

    // ── Subtitles (embedded + per-addon + appearance + timing + search) ─────────
    fun umSubsModel(col1: List<UnifiedMenuController.Row>, col2Index: Int): UnifiedMenuController.Model {
        val curSub = stremioSubtitles.getOrNull(currentStremioSubtitleIndex)
        val col2 = mutableListOf<UnifiedMenuController.Row>()
        col2.add(mrow("Embedded", tag = "emb", selected = curSub == null))
        for (r in addonSubtitleResults) {
            val badge = when (r.status) {
                AddonSubtitleStatus.LOADING -> "…"
                AddonSubtitleStatus.OK -> "${r.subtitles.size}"
                AddonSubtitleStatus.FAILED -> "⚠"
            }
            col2.add(mrow(
                r.addon.name, value = badge, tag = "addon:${r.addon.id}",
                selected = curSub != null && curSub.addonId == r.addon.id
            ))
        }
        col2.add(mrow("Fix movie", tag = "search", accent = true))
        col2.add(mrow("Appearance", tag = "appearance"))
        col2.add(mrow("Timing", tag = "timing"))

        val tag = col2.getOrNull(col2Index)?.tag
        var mode = UnifiedMenuController.Col3Mode.ROWS
        val (col3Title, col3) = when {
            tag == "emb" -> "Track" to host.subtitleController.umEmbeddedTrackRows()
            tag == "appearance" -> "Appearance · live" to host.subtitleController.umAppearanceRows()
            tag == "timing" -> "Timing" to host.subtitleController.umTimingRows()
            tag == "search" -> {
                if (pendingSeriesResult == null) mode = UnifiedMenuController.Col3Mode.SEARCH
                "Fix movie" to umSearchRows()
            }
            tag != null && tag.startsWith("addon:") -> {
                val id = tag.removePrefix("addon:")
                (addonSubtitleResults.firstOrNull { it.addon.id == id }?.addon?.name ?: "Addon") to
                    umAddonTrackRows(id)
            }
            else -> "" to emptyList()
        }
        // Column header carries the detected/override identity ("Detected: <title>" /
        // "Subtitles for <title>") that the old panel showed as a persistent row.
        return UnifiedMenuController.Model(
            col1, currentSubtitleIdentityLabel(), col2, col3Title, col3, mode,
            previewVisible = tag == "appearance"
        )
    }

    private fun umAddonTrackRows(addonId: String): List<UnifiedMenuController.Row> {
        val r = addonSubtitleResults.firstOrNull { it.addon.id == addonId } ?: return emptyList()
        return when (r.status) {
            AddonSubtitleStatus.LOADING -> listOf(mrow("Loading…", enabled = false))
            AddonSubtitleStatus.FAILED -> {
                val rows = mutableListOf(mrow("Failed — retry this addon", accent = true,
                    onOk = { retryAddonSubtitles(addonId) }))
                r.error?.takeIf { it.isNotBlank() }?.let { rows.add(mrow(it.take(48), enabled = false)) }
                rows
            }
            AddonSubtitleStatus.OK ->
                if (r.subtitles.isEmpty()) listOf(mrow("No subtitles from this addon", enabled = false))
                else r.subtitles.map { sub ->
                    val cur = stremioSubtitles.getOrNull(currentStremioSubtitleIndex)
                    mrow(
                        sub.displayName, value = sub.lang.uppercase(Locale.US),
                        tag = "subtitle:${sub.url}",
                        // Require addonId match too: a URL shared by two addons dedupes
                        // to one owner, so only that addon's row highlights.
                        selected = cur?.url == sub.url && cur.addonId == addonId,
                        onOk = { host.subtitleController.umSelectStremioSubtitleByUrl(sub.url) }
                    )
                }
        }
    }

    private fun umSearchRows(): List<UnifiedMenuController.Row> {
        if (pendingSeriesResult != null) {
            return listOf(
                mrow("Season  ◀ ▶", value = "$pendingSeason", adjustable = true,
                    onAdjust = { d -> pendingSeason = (pendingSeason + d).coerceIn(1, 99) }),
                mrow("Episode  ◀ ▶", value = "$pendingEpisode", adjustable = true,
                    onAdjust = { d -> pendingEpisode = (pendingEpisode + d).coerceIn(1, 999) }),
                mrow("Fetch subtitles", accent = true, onOk = {
                    val r = pendingSeriesResult
                    pendingSeriesResult = null
                    if (r != null) applyManualSubtitleIdentity(r, pendingSeason, pendingEpisode)
                    host.unifiedMenu?.hide()
                })
            )
        }
        val rows = mutableListOf<UnifiedMenuController.Row>()
        if (subtitleSearchStatus.isNotEmpty()) rows.add(mrow(subtitleSearchStatus, enabled = false))
        for (r in subtitleSearchResults) {
            rows.add(mrow(r.titleLine(), value = r.detailLine(), onOk = { umPickSearchResult(r) }))
        }
        return rows
    }

    private fun umPickSearchResult(r: SubtitleCatalogResult) {
        if (r.type == "series") {
            val se = dialogs.getCurrentSubtitleSearchItem()?.let { resolveSeasonEpisodeForSubtitle(it) }
            if (se != null) {
                applyManualSubtitleIdentity(r, se.season, se.episode)
                host.unifiedMenu?.hide()
            } else {
                val cur = dialogs.getCurrentSubtitleSearchItem()
                pendingSeriesResult = r
                pendingSeason = (cur?.season ?: manualSubtitleSeason ?: 1).coerceAtLeast(1)
                pendingEpisode = (cur?.episode ?: manualSubtitleEpisode ?: 1).coerceAtLeast(1)
                host.unifiedMenu?.render()
            }
        } else {
            applyManualSubtitleIdentity(r, null, null)
            host.unifiedMenu?.hide()
        }
    }
}
