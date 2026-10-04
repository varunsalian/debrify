# Episodes panel dependency and wiring inventory

Reference R: `92339749` (format-only ORIGINAL); execution base `81fff4be`.

9 top-level declarations (one enum, eight classes including both private States);
85 State leaves: 31 instance fields, two static methods, six getters.
No seam, mixin, provider, lifecycle hook, key, or const is added.

## Ownership decisions

- All four service references retain State-construction timing and borrowed singleton ownership.
- Fresh view/progress/auth/resource records are constructed once per State, in original field order.
- Resource record owns the scroll controller, episode focus list and back/season/retry nodes; State disposes in original order.
- Metadata and season-option mid-class fields move with their methods, immediately before them.
- Stateless pure helpers retain static bodies in one service-free application policy class.
- Private widget and State names stay private; exact public typedef aliases expose constructors; the rename/alias strict probe adds zero diagnostic identities.
- Every section reads current widget properties through typed getters; context/mounted/setState stay live State callbacks.
- Sections borrow State.refreshWatchProgress as a bound tear-off. They never own a second refresh implementation.

## Cache and fixture scope

- Stremio series metadata: process-wide 15-minute cache, no reset; unique addon id for each named case.
- TVMaze: clearCache in setup and teardown, inside MockClient after preferences/profile initialization; availability probe /shows/1 returns 200, IMDb lookup returns 404.
- TrackerIdentityService: native Simkl resolutions cached 15 minutes; unique native id per case. TMDB/IMDb direct IDs need no cache lookup.
- MDBList retains its constructed client: the recording client resolves the current fixture from its live request zone, avoiding a previous-case capture.
- Trakt, Simkl and MDBList resetProfileScope in setup and teardown. Simkl playback has a 30-second real-clock cache; action cases establish cold cache before asserting GET.
- MetadataEpisodeService uses current provider metadata; any repository cache is isolated by unique content identity, no new production reset.

## Per-entry wiring checklist

Review each entry before scaffolds are pinned. The caller stays at its original
evaluation site; qualifiers alone select its named owner. Step 0 fixes ownership;
actual binding evidence is filled at the owning step.

| Original leaf | Destination / owner / member | Step | Live reads | Initial wiring |
| --- | --- | --- | --- | --- |
| `EpisodeFocusIntent` | `lib/features/episodes_panel/models/episodes_panel_view.dart` / `<top level>` / `EpisodeFocusIntent` | 1 |  | pending step 1 |
| `EpisodesPanelView` | `lib/features/episodes_panel/models/episodes_panel_view.dart` / `<top level>` / `EpisodesPanelView` | 1 | this | pending step 1 |
| `EpisodesPanel` | `lib/widgets/episodes_panel.dart` / `<top level>` / `EpisodesPanel` | 0 | context, this | retained |
| `EpisodesPanelState._stremioService` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart` / `EpisodesPanelServices` / `stremioService` | 3 |  | pending step 3 |
| `EpisodesPanelState._traktService` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart` / `EpisodesPanelServices` / `traktService` | 3 |  | pending step 3 |
| `EpisodesPanelState._simklService` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart` / `EpisodesPanelServices` / `simklService` | 3 |  | pending step 3 |
| `EpisodesPanelState._mdblistService` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_services.dart` / `EpisodesPanelServices` / `mdblistService` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeModeGeneration` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `episodeModeGeneration` | 3 |  | pending step 3 |
| `EpisodesPanelState._selectedShow` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `selectedShow` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeSeasons` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `episodeSeasons` | 3 |  | pending step 3 |
| `EpisodesPanelState._selectedSeasonNumber` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `selectedSeasonNumber` | 3 |  | pending step 3 |
| `EpisodesPanelState._isLoadingEpisodes` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `isLoadingEpisodes` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodesUnavailable` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `episodesUnavailable` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeWatchProgress` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `episodeWatchProgress` | 3 |  | pending step 3 |
| `EpisodesPanelState._trackingPolicy` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `trackingPolicy` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeMdblistRatings` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `episodeMdblistRatings` | 3 |  | pending step 3 |
| `EpisodesPanelState._viewGeneration` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `viewGeneration` | 3 | this | pending step 3 |
| `EpisodesPanelState._landing` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `landing` | 3 |  | pending step 3 |
| `EpisodesPanelState._focusIntent` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `focusIntent` | 3 |  | pending step 3 |
| `EpisodesPanelState._custom` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_root_layout.dart` / `EpisodesPanelRootLayout` / `custom` | 6 | widget.contentBuilder | pending step 6 |
| `EpisodesPanelState._nextEpisode` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `nextEpisode` | 3 |  | pending step 3 |
| `EpisodesPanelState._trackerNextRaw` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart` / `EpisodesPanelViewState` / `trackerNextRaw` | 3 |  | pending step 3 |
| `EpisodesPanelState._traktAuthenticated` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `traktAuthenticated` | 3 | this | pending step 3 |
| `EpisodesPanelState._isTraktAuthenticated` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `isTraktAuthenticated` | 4 | widget.show | pending step 4 |
| `EpisodesPanelState._simklAuthenticated` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `simklAuthenticated` | 3 |  | pending step 3 |
| `EpisodesPanelState._mdblistAuthenticated` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `mdblistAuthenticated` | 3 |  | pending step 3 |
| `EpisodesPanelState._isSimklAuthenticated` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `isSimklAuthenticated` | 4 | widget.show | pending step 4 |
| `EpisodesPanelState._isMdblistAuthenticated` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `isMdblistAuthenticated` | 4 | widget.show | pending step 4 |
| `EpisodesPanelState._mdblistRefreshToken` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `mdblistRefreshToken` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeFocusNodes` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart` / `EpisodesPanelResources` / `episodeFocusNodes` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeScrollController` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart` / `EpisodesPanelResources` / `episodeScrollController` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeBackButtonFocusNode` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart` / `EpisodesPanelResources` / `episodeBackButtonFocusNode` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeSeasonDropdownFocusNode` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart` / `EpisodesPanelResources` / `episodeSeasonDropdownFocusNode` | 3 |  | pending step 3 |
| `EpisodesPanelState._episodeRetryFocusNode` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart` / `EpisodesPanelResources` / `episodeRetryFocusNode` | 3 |  | pending step 3 |
| `EpisodesPanelState.initState` | `lib/widgets/episodes_panel.dart` / `EpisodesPanelState` / `initState` | 0 | widget.initialEpisode, widget.initialSeason, widget.show, widget.showChrome | retained |
| `EpisodesPanelState.dispose` | `lib/widgets/episodes_panel.dart` / `EpisodesPanelState` / `dispose` | 0 |  | retained |
| `EpisodesPanelState._loadEpisodeWatchProgress` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `loadEpisodeWatchProgress` | 4 | widget.watchProgressLoader, mounted, setState, this | pending step 4 |
| `EpisodesPanelState._logEpisodeProgress` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `logEpisodeProgress` | 4 |  | pending step 4 |
| `EpisodesPanelState._mergedUpNext` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `mergedUpNext` | 4 |  | pending step 4 |
| `EpisodesPanelState._publishNextEpisode` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `publishNextEpisode` | 4 | widget.onNextEpisodeChanged | pending step 4 |
| `EpisodesPanelState._publishSeriesCompletion` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_progress.dart` / `EpisodesPanelProgress` / `publishSeriesCompletion` | 4 | widget.onSeriesCompletedChanged | pending step 4 |
| `EpisodesPanelState._onMdblistPlaybackRevision` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `onMdblistPlaybackRevision` | 4 | mounted | pending step 4 |
| `EpisodesPanelState._refreshAfterMdblistMutation` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `refreshAfterMdblistMutation` | 4 | context, mounted | pending step 4 |
| `EpisodesPanelState.refreshWatchProgress` | `lib/widgets/episodes_panel.dart` / `EpisodesPanelState` / `refreshWatchProgress` | 0 |  | retained |
| `EpisodesPanelState._isDirectSource` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `isDirectSource` | 4 | widget.seasonsLoader | pending step 4 |
| `EpisodesPanelState._resolveTraktAuth` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `resolveTraktAuth` | 4 | mounted, setState | pending step 4 |
| `EpisodesPanelState._resolveSimklAuth` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `resolveSimklAuth` | 4 | mounted, setState | pending step 4 |
| `EpisodesPanelState._resolveMdblistAuth` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart` / `EpisodesPanelAuth` / `resolveMdblistAuth` | 4 | mounted, setState | pending step 4 |
| `EpisodesPanelState._watchedSyncTargets` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_watched_actions.dart` / `EpisodesPanelWatchedActions` / `watchedSyncTargets` | 4 | this | pending step 4 |
| `EpisodesPanelState._joinNames` | `lib/features/episodes_panel/application/episodes_panel_policies.dart` / `EpisodesPanelPolicies` / `joinNames` | 1 | this | pending step 1 |
| `EpisodesPanelState._setEpisodeWatchedEverywhere` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_watched_actions.dart` / `EpisodesPanelWatchedActions` / `setEpisodeWatchedEverywhere` | 4 | context, mounted, setState, this | pending step 4 |
| `EpisodesPanelState._onEpisodeMenuAction` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_watched_actions.dart` / `EpisodesPanelWatchedActions` / `onEpisodeMenuAction` | 4 | context, mounted | pending step 4 |
| `EpisodesPanelState._onEpisodeMdblistMenuAction` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_watched_actions.dart` / `EpisodesPanelWatchedActions` / `onEpisodeMdblistMenuAction` | 4 | context, mounted, setState | pending step 4 |
| `EpisodesPanelState._fallbackToDirectSearch` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart` / `EpisodesPanelNavigation` / `fallbackToDirectSearch` | 5 | widget.onBeforeTerminalDispatch, widget.onItemSelected, mounted | pending step 5 |
| `EpisodesPanelState._fetchSeasons` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_seasons.dart` / `EpisodesPanelSeasons` / `fetchSeasons` | 4 | widget.addon, widget.seasonsLoader, this | pending step 4 |
| `EpisodesPanelState._groupVideosIntoSeasons` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_seasons.dart` / `EpisodesPanelSeasons` / `groupVideosIntoSeasons` | 4 |  | pending step 4 |
| `EpisodesPanelState._downsizeMetahubThumb` | `lib/features/episodes_panel/application/episodes_panel_policies.dart` / `EpisodesPanelPolicies` / `downsizeMetahubThumb` | 1 |  | pending step 1 |
| `EpisodesPanelState._enterEpisodeMode` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_mode.dart` / `EpisodesPanelMode` / `enterEpisodeMode` | 4 | widget.addon, context, mounted, setState, this | pending step 4 |
| `EpisodesPanelState._directLandingTarget` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_mode.dart` / `EpisodesPanelMode` / `directLandingTarget` | 4 |  | pending step 4 |
| `EpisodesPanelState._enrichEpisodeRatings` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_enrichment.dart` / `EpisodesPanelEnrichment` / `enrichEpisodeRatings` | 4 | mounted, setState | pending step 4 |
| `EpisodesPanelState._fetchTvmazeThumbMap` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_enrichment.dart` / `EpisodesPanelEnrichment` / `fetchTvmazeThumbMap` | 4 |  | pending step 4 |
| `EpisodesPanelState._enrichEpisodeThumbnails` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_enrichment.dart` / `EpisodesPanelEnrichment` / `enrichEpisodeThumbnails` | 4 | mounted, setState | pending step 4 |
| `EpisodesPanelState._scrollFocusEpisode` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_enrichment.dart` / `EpisodesPanelEnrichment` / `scrollFocusEpisode` | 4 | widget.isTelevision, context, mounted | pending step 4 |
| `EpisodesPanelState._episodeMetadataBaselines` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart` / `EpisodesPanelMetadata` / `episodeMetadataBaselines` | 4 |  | pending step 4 |
| `EpisodesPanelState._episodeMetadataGeneration` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart` / `EpisodesPanelMetadata` / `episodeMetadataGeneration` | 4 |  | pending step 4 |
| `EpisodesPanelState._episodePolicyChanged` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart` / `EpisodesPanelMetadata` / `episodePolicyChanged` | 4 | mounted, setState | pending step 4 |
| `EpisodesPanelState._refreshMetadataLanding` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart` / `EpisodesPanelMetadata` / `refreshMetadataLanding` | 4 |  | pending step 4 |
| `EpisodesPanelState._loadSelectedEpisodeMetadata` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_metadata.dart` / `EpisodesPanelMetadata` / `loadSelectedEpisodeMetadata` | 4 | widget.show, mounted, setState | pending step 4 |
| `EpisodesPanelState._onSeasonChanged` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart` / `EpisodesPanelNavigation` / `onSeasonChanged` | 5 | setState | pending step 5 |
| `EpisodesPanelState._onEpisodeTap` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart` / `EpisodesPanelNavigation` / `onEpisodeTap` | 5 | widget.addon, widget.isMdblistSource, widget.isTraktSource, widget.onBeforeTerminalDispatch, widget.onItemSelected, widget.onPlayEpisode, this | pending step 5 |
| `EpisodesPanelState._onEpisodeQuickPlay` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart` / `EpisodesPanelNavigation` / `onEpisodeQuickPlay` | 5 | widget.addon, widget.isMdblistSource, widget.isTraktSource, widget.onBeforeTerminalDispatch, widget.onItemSelected, widget.onPlayEpisode, widget.onQuickPlay | pending step 5 |
| `EpisodesPanelState._buildEpisodeFiltersBar` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_chrome.dart` / `EpisodesPanelClassicChrome` / `buildEpisodeFiltersBar` | 6 | widget.boundSourceCount, widget.onBack, widget.onSelectSource, context, mounted, setState | pending step 6 |
| `EpisodesPanelState._handleEpisodeSeasonDropdownKeyEvent` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_chrome.dart` / `EpisodesPanelClassicChrome` / `handleEpisodeSeasonDropdownKeyEvent` | 6 | widget.onSelectSource | pending step 6 |
| `EpisodesPanelState._buildEpisodeSeasonDropdown` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_chrome.dart` / `EpisodesPanelClassicChrome` / `buildEpisodeSeasonDropdown` | 6 | widget.isTelevision, context, mounted | pending step 6 |
| `EpisodesPanelState._buildEpisodesUnavailable` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_content.dart` / `EpisodesPanelClassicContent` / `buildEpisodesUnavailable` | 6 | widget.initialEpisode, widget.initialSeason, widget.isTelevision, widget.onItemSelected, widget.show, context | pending step 6 |
| `EpisodesPanelState._buildEpisodeContent` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_content.dart` / `EpisodesPanelClassicContent` / `buildEpisodeContent` | 6 | widget.isTelevision, widget.showQuickPlay, context | pending step 6 |
| `EpisodesPanelState._buildSlimSeasonRow` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_classic_chrome.dart` / `EpisodesPanelClassicChrome` / `buildSlimSeasonRow` | 6 |  | pending step 6 |
| `EpisodesPanelState.build` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_root_layout.dart` / `EpisodesPanelRootLayout` / `build` | 6 | widget.compact, widget.contentBuilder, widget.showChrome, context | pending step 6 |
| `EpisodesPanelState._buildView` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_root_layout.dart` / `EpisodesPanelRootLayout` / `buildView` | 6 | widget.initialEpisode, widget.initialSeason, widget.onFocusLeftEdge, widget.onItemSelected, widget.show | pending step 6 |
| `EpisodesPanelState.consumeFocusIntent` | `lib/widgets/episodes_panel.dart` / `EpisodesPanelState` / `consumeFocusIntent` | 0 | this | retained |
| `EpisodesPanelState._currentSeasonIndex` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_layout.dart` / `EpisodesPanelCompactLayout` / `currentSeasonIndex` | 6 |  | pending step 6 |
| `EpisodesPanelState._seasonActionBusy` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_season_options.dart` / `EpisodesPanelSeasonOptions` / `seasonActionBusy` | 5 |  | pending step 5 |
| `EpisodesPanelState._seasonRetries` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_season_options.dart` / `EpisodesPanelSeasonOptions` / `seasonRetries` | 5 |  | pending step 5 |
| `EpisodesPanelState._showSeasonOptions` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_season_options.dart` / `EpisodesPanelSeasonOptions` / `showSeasonOptions` | 5 | widget.isTelevision, context, mounted | pending step 5 |
| `EpisodesPanelState._stepSeason` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart` / `EpisodesPanelNavigation` / `stepSeason` | 5 | mounted | pending step 5 |
| `EpisodesPanelState._buildCompactSeasonHeader` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_layout.dart` / `EpisodesPanelCompactLayout` / `buildCompactSeasonHeader` | 6 | widget.isTelevision, this | pending step 6 |
| `EpisodesPanelState._buildCompactContent` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_layout.dart` / `EpisodesPanelCompactLayout` / `buildCompactContent` | 6 | widget.isTelevision, widget.onFocusLeftEdge, context | pending step 6 |
| `EpisodesPanelState._showEpisodeOptions` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_episode_options.dart` / `EpisodesPanelEpisodeOptions` / `showEpisodeOptions` | 5 | widget.isTelevision, widget.onPlayEpisode, context, this | pending step 5 |
| `_CatalogSelectSourceButton` | `lib/features/episodes_panel/presentation/episodes_panel_source_button.dart` / `<top level>` / `_CatalogSelectSourceButton` | 2 | this | pending step 2 |
| `_CatalogSelectSourceButtonState` | `lib/features/episodes_panel/presentation/episodes_panel_source_button.dart` / `<top level>` / `_CatalogSelectSourceButtonState` | 2 | widget.hasBoundSource, widget.onDownArrow, widget.onLeftFocus, widget.onTap, widget.onUpArrow, widget.sourceCount, context, setState | pending step 2 |
| `_SeasonStepButton` | `lib/features/episodes_panel/presentation/episodes_panel_season_step.dart` / `<top level>` / `_SeasonStepButton` | 2 | context, this | pending step 2 |
| `_CompactEpisodeRow` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_row.dart` / `<top level>` / `_CompactEpisodeRow` | 2 | this | pending step 2 |
| `_CompactEpisodeRowState` | `lib/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_compact_row.dart` / `<top level>` / `_CompactEpisodeRowState` | 2 | widget.episode, widget.focusNode, widget.isNext, widget.isTelevision, widget.onLeft, widget.onOptions, widget.onPlay, widget.showImageUrl, widget.watchProgress, context, mounted, setState | pending step 2 |

## Comment fragments

The AST manifest retains every attached dartdoc and trailing comment. The enum
owns the contiguous panel doc (including its legacy misplaced documentation).
The State header doc stays in the facade. Free-standing line fragments are
assigned as follows; checker comment conservation remains unconditional:

| Fragment | Owner |
| --- | --- |
| Episode drill-down state | ViewState before episodeModeGeneration |
| MDBList acknowledge/route-consistency block | Auth before mdblistRefreshToken |
| Retry focus explanation | Resources before episodeRetryFocusNode |
| Episode drill-down separator | Navigation before fallbackToDirectSearch |
| Compact rendering separator | CompactLayout before currentSeasonIndex |
| Select Source / Season stepper / Compact row separators | Respective private widget class |

## Boundary dependencies

The view model imports Flutter foundation for VoidCallback and only the Trakt
episode DTO from services (file-scoped allowance). Source/season buttons use
Material, keyboard/tv_keys, DetailThemeScope and PlatformUtil only. The compact
row additionally imports TraktEpisode and DebrifyImageCache, so stays in the exact
legacy bridge. Every section needing TraktSeason/TraktEpisode is in that bridge.

## Tear-offs and dispatch

Both policy notifiers borrow the same metadata owner method; playback revision
borrows the same auth owner method at add/remove; season dropdown stores its
original handler only in initState. View callbacks, DropdownButton.onChanged,
private widget pass-throughs and host callbacks retain their original arguments.
Closures originally present (EpisodeTile play/sources/menus, sheet tiles, retry,
select season) stay closures; direct tear-offs stay direct. The host properties
are always evaluated live, including nullable callbacks and loader replacement.

No playback symbols, native/platform APIs, storage writes, or host changes are
introduced. FNF decisions and device-only validation remain in the plan.
