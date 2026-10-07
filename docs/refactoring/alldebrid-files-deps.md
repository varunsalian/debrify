# AllDebrid files — frozen Step 0 dependency and wiring report

Original: `49c53e2e:lib/screens/alldebrid/alldebrid_files_screen.dart`; execution starts at `52996ce3`. The source is byte-identical at those revisions and has 1,996 physical lines. This checkpoint extracts nothing. All 98 original AST leaves are listed below; the manifest is the executable frozen map. Imports and class headers remain subject to the verbatim checker.

## Ownership and construction

All fields retain declaration initializers and mutable collection identity. The facade keeps the public widget, lifecycle and tab-12 registration constant. Library state owns credentials and the two root datasets; navigation owns view/magnet/files; search owns both queries and text controllers; selection owns mode/ids; focus owns the shared scroll controller, seven focus nodes, stored TV closure and load-focus flag; feedback owns the dialog flag. All are screen-instance owned; credentials still resolve the active profile through legacy storage at the original call sites. No new profile scoping, cancellation, retries or state framework is introduced.

In Step 2 the State constructs plain final owner fields without constructor arguments. A single nullable section cache and getter constructs the graph on first use. Constructors retain dependencies only. All graph slots are assigned before exposure. Step 3 methods use the same stable graph through disposal. Live `context`/`mounted`/`setState` callbacks and `widget.isPushedRoute`, `widget.selectSourceMode`, `widget.onSourceSelected` getters are evaluated at their original sites; `initialSearchQuery` stays an initialization-only State read. No saved context/widget snapshot, `late` field, `didUpdateWidget`, listener or action during composition.

Temporary 1,996-line facade retention is intentional through Steps 1–5; only the frozen accessor may extend it now. Every original responsibility remains until its scheduled extraction. Exit: Step 6 facade cap below 300 and no TEMP(alldebrid); all destination files ≤500 lines. Riverpod/data contracts/localization/shared helper migrations remain the later milestones named in the plan.

## External boundaries

| Boundary | Actual use / retained contract |
| --- | --- |
| AllDebridStorage | `_load` re-reads on every call; `_loadLinks` reads only when `_apiKey` is null. Actions use cached key. |
| AllDebridService | magnet/status POST; magnet/files POST; sequential unlock/delete; magnet upload, saved-link GET/save/delete. Successful response envelope required. |
| MainPageBridge | Route tear-off identity, key-only tab removal, stored TV closure identity on tab 12, deep-link assignment and own-disposal comparison; notify before each player launch. |
| VideoPlayerLauncher / PlaylistEntry | Three exact sites; full ledger below. Native launch remains pending device verification. |
| DownloadService | Three enqueue bodies and credential key; real FileSelectionDialog callback loop. Successful native enqueue messages require a proven fixture, otherwise pending. |
| PlaylistStorage | Two exact submitted maps; storage adds `addedAt` and dedupes. No service rewrite. |
| Clipboard | unlocked URL copy; trimmed http/https auto-paste before Add Link dialog. |
| Widget/platform | live context/mounted/setState, navigator/scaffold effects, ordered disposal; CloudFileRow keys/actions/focus, TV text-field callbacks. |
| Pure helper | `_findFirstEpisodeIndex` reads only its `infos` parameter/locals. Keep it a method on AllDebridPlayback in Step 4 without added parameters; pure-function extraction is deferred because it changes the occurrence-binder scope frame. |

## Frozen section map

Rows are original declaration → destination file / owner / step. Names in parentheses are the destination member; blank owner means top-level. No destination declaration exists at Step 0.

| Original declaration | Destination | Owner / member | Step |
| --- | --- | --- | --- |
| `AllDebridFilesScreen` (class container, doc comment and constructor surface) | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `AllDebridFilesScreen` | retained throughout 0–6 |
| `_AllDebridFilesScreenState` (class container) | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `_AllDebridFilesScreenState`; members follow the leaf rows | retained throughout 0–6 |
| `_AdView` | `lib/features/alldebrid_files/models/alldebrid_view.dart` | `(top-level).AllDebridView` | 1 |
| `AllDebridFilesScreen.isPushedRoute` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `AllDebridFilesScreen.isPushedRoute` | 0 |
| `AllDebridFilesScreen.initialSearchQuery` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `AllDebridFilesScreen.initialSearchQuery` | 0 |
| `AllDebridFilesScreen.selectSourceMode` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `AllDebridFilesScreen.selectSourceMode` | 0 |
| `AllDebridFilesScreen.onSourceSelected` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `AllDebridFilesScreen.onSourceSelected` | 0 |
| `AllDebridFilesScreen.AllDebridFilesScreen` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `AllDebridFilesScreen.AllDebridFilesScreen` | 0 |
| `AllDebridFilesScreen.createState` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `AllDebridFilesScreen.createState` | 0 |
| `_AllDebridFilesScreenState._tabIndex` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `_AllDebridFilesScreenState._tabIndex` | 0 |
| `_AllDebridFilesScreenState._apiKey` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.apiKey` | 2 |
| `_AllDebridFilesScreenState._loading` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.loading` | 2 |
| `_AllDebridFilesScreenState._error` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.error` | 2 |
| `_AllDebridFilesScreenState._magnets` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.magnets` | 2 |
| `_AllDebridFilesScreenState._selectedView` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart` | `AllDebridNavigationState.selectedView` | 2 |
| `_AllDebridFilesScreenState._links` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.links` | 2 |
| `_AllDebridFilesScreenState._loadingLinks` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.loadingLinks` | 2 |
| `_AllDebridFilesScreenState._linksLoadedOnce` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.linksLoadedOnce` | 2 |
| `_AllDebridFilesScreenState._linksError` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart` | `AllDebridLibraryState.linksError` | 2 |
| `_AllDebridFilesScreenState._currentMagnet` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart` | `AllDebridNavigationState.currentMagnet` | 2 |
| `_AllDebridFilesScreenState._currentFiles` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart` | `AllDebridNavigationState.currentFiles` | 2 |
| `_AllDebridFilesScreenState._loadingFiles` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart` | `AllDebridNavigationState.loadingFiles` | 2 |
| `_AllDebridFilesScreenState._isAtRoot` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart` | `AllDebridNavigation.isAtRoot` | 3 |
| `_AllDebridFilesScreenState._searchActive` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart` | `AllDebridSearchState.searchActive` | 2 |
| `_AllDebridFilesScreenState._searchQuery` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart` | `AllDebridSearchState.searchQuery` | 2 |
| `_AllDebridFilesScreenState._searchController` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart` | `AllDebridSearchState.searchController` | 2 |
| `_AllDebridFilesScreenState._searchFocusNode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.searchFocusNode` | 2 |
| `_AllDebridFilesScreenState._searchClearFocusNode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.searchClearFocusNode` | 2 |
| `_AllDebridFilesScreenState._fileSearchActive` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart` | `AllDebridSearchState.fileSearchActive` | 2 |
| `_AllDebridFilesScreenState._fileSearchQuery` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart` | `AllDebridSearchState.fileSearchQuery` | 2 |
| `_AllDebridFilesScreenState._fileSearchController` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart` | `AllDebridSearchState.fileSearchController` | 2 |
| `_AllDebridFilesScreenState._fileSearchFocusNode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.fileSearchFocusNode` | 2 |
| `_AllDebridFilesScreenState._selectionMode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart` | `AllDebridSelectionState.selectionMode` | 2 |
| `_AllDebridFilesScreenState._selectedIds` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart` | `AllDebridSelectionState.selectedIds` | 2 |
| `_AllDebridFilesScreenState._scrollController` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.scrollController` | 2 |
| `_AllDebridFilesScreenState._backButtonFocusNode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.backButtonFocusNode` | 2 |
| `_AllDebridFilesScreenState._deleteButtonFocusNode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.deleteButtonFocusNode` | 2 |
| `_AllDebridFilesScreenState._toolbarSearchFocusNode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.toolbarSearchFocusNode` | 2 |
| `_AllDebridFilesScreenState._tvContentFocusHandler` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.tvContentFocusHandler` | 2 |
| `_AllDebridFilesScreenState._shouldFocusOnLoad` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.shouldFocusOnLoad` | 2 |
| `_AllDebridFilesScreenState._firstItemFocusNode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart` | `AllDebridFocusState.firstItemFocusNode` | 2 |
| `_AllDebridFilesScreenState.initState` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `_AllDebridFilesScreenState.initState` | 0 |
| `_AllDebridFilesScreenState._focusWebDownloads` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart` | `AllDebridNavigation.focusWebDownloads` | 3 |
| `_AllDebridFilesScreenState.dispose` | `lib/screens/alldebrid/alldebrid_files_screen.dart` | `_AllDebridFilesScreenState.dispose` | 0 |
| `_AllDebridFilesScreenState._focusFirstItem` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart` | `AllDebridNavigation.focusFirstItem` | 3 |
| `_AllDebridFilesScreenState._load` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_loading.dart` | `AllDebridLibraryLoading.load` | 3 |
| `_AllDebridFilesScreenState._loadLinks` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_loading.dart` | `AllDebridLibraryLoading.loadLinks` | 3 |
| `_AllDebridFilesScreenState._refresh` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart` | `AllDebridNavigation.refresh` | 3 |
| `_AllDebridFilesScreenState._openMagnet` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart` | `AllDebridNavigation.openMagnet` | 3 |
| `_AllDebridFilesScreenState._navigateUp` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart` | `AllDebridNavigation.navigateUp` | 3 |
| `_AllDebridFilesScreenState._handleBackNavigation` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation.dart` | `AllDebridNavigation.handleBackNavigation` | 3 |
| `_AllDebridFilesScreenState._looksLikeVideo` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart` | `AllDebridPlayback.looksLikeVideo` | 4 |
| `_AllDebridFilesScreenState._unlockStart` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart` | `AllDebridPlayback.unlockStart` | 4 |
| `_AllDebridFilesScreenState._playFile` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart` | `AllDebridPlayback.playFile` | 4 |
| `_AllDebridFilesScreenState._playMagnet` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart` | `AllDebridPlayback.playMagnet` | 4 |
| `_AllDebridFilesScreenState._playVideos` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart` | `AllDebridPlayback.playVideos` | 4 |
| `_AllDebridFilesScreenState._findFirstEpisodeIndex` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart` | `AllDebridPlayback.findFirstEpisodeIndex` | 4 |
| `_AllDebridFilesScreenState._downloadFile` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_downloads.dart` | `AllDebridDownloads.downloadFile` | 4 |
| `_AllDebridFilesScreenState._downloadMagnet` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_downloads.dart` | `AllDebridDownloads.downloadMagnet` | 4 |
| `_AllDebridFilesScreenState._downloadSelectedFiles` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_downloads.dart` | `AllDebridDownloads.downloadSelectedFiles` | 4 |
| `_AllDebridFilesScreenState._showAddMagnetDialog` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_add_actions.dart` | `AllDebridAddActions.showAddMagnetDialog` | 4 |
| `_AllDebridFilesScreenState._playLink` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playback.dart` | `AllDebridPlayback.playLink` | 4 |
| `_AllDebridFilesScreenState._downloadLink` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_downloads.dart` | `AllDebridDownloads.downloadLink` | 4 |
| `_AllDebridFilesScreenState._copyLink` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_downloads.dart` | `AllDebridDownloads.copyLink` | 4 |
| `_AllDebridFilesScreenState._showAddLinkDialog` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_add_actions.dart` | `AllDebridAddActions.showAddLinkDialog` | 4 |
| `_AllDebridFilesScreenState._deleteLinks` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_delete_actions.dart` | `AllDebridDeleteActions.deleteLinks` | 4 |
| `_AllDebridFilesScreenState._confirmDeleteAllLinks` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_delete_actions.dart` | `AllDebridDeleteActions.confirmDeleteAllLinks` | 4 |
| `_AllDebridFilesScreenState._addMagnetToPlaylist` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_playlist_actions.dart` | `AllDebridPlaylistActions.addMagnetToPlaylist` | 4 |
| `_AllDebridFilesScreenState._deleteMagnets` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_delete_actions.dart` | `AllDebridDeleteActions.deleteMagnets` | 4 |
| `_AllDebridFilesScreenState._confirmDeleteAll` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_delete_actions.dart` | `AllDebridDeleteActions.confirmDeleteAll` | 4 |
| `_AllDebridFilesScreenState._toggleSelectionMode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection.dart` | `AllDebridSelection.toggleSelectionMode` | 3 |
| `_AllDebridFilesScreenState._exitSelectionMode` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection.dart` | `AllDebridSelection.exitSelectionMode` | 3 |
| `_AllDebridFilesScreenState._toggleSelection` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection.dart` | `AllDebridSelection.toggleSelection` | 3 |
| `_AllDebridFilesScreenState._isAllSelected` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection.dart` | `AllDebridSelection.isAllSelected` | 3 |
| `_AllDebridFilesScreenState._toggleSelectAll` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection.dart` | `AllDebridSelection.toggleSelectAll` | 3 |
| `_AllDebridFilesScreenState._handleDeleteSelected` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_delete_actions.dart` | `AllDebridDeleteActions.handleDeleteSelected` | 4 |
| `_AllDebridFilesScreenState._toggleSearch` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search.dart` | `AllDebridSearch.toggleSearch` | 3 |
| `_AllDebridFilesScreenState._visibleMagnets` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search.dart` | `AllDebridSearch.visibleMagnets` | 3 |
| `_AllDebridFilesScreenState._visibleFiles` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search.dart` | `AllDebridSearch.visibleFiles` | 3 |
| `_AllDebridFilesScreenState._visibleLinks` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search.dart` | `AllDebridSearch.visibleLinks` | 3 |
| `_AllDebridFilesScreenState._loadingDialogOpen` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback_state.dart` | `AllDebridFeedbackState.loadingDialogOpen` | 2 |
| `_AllDebridFilesScreenState._showLoading` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback.dart` | `AllDebridFeedback.showLoading` | 3 |
| `_AllDebridFilesScreenState._dismissLoading` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback.dart` | `AllDebridFeedback.dismissLoading` | 3 |
| `_AllDebridFilesScreenState._snack` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback.dart` | `AllDebridFeedback.snack` | 3 |
| `_AllDebridFilesScreenState.build` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_root_layout.dart` | `AllDebridRootLayout.build` | 5 |
| `_AllDebridFilesScreenState._isBrowsePush` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_toolbar.dart` | `AllDebridToolbar.isBrowsePush` | 5 |
| `_AllDebridFilesScreenState._buildToolbar` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_toolbar.dart` | `AllDebridToolbar.buildToolbar` | 5 |
| `_AllDebridFilesScreenState._buildViewSelectorBar` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_toolbar.dart` | `AllDebridToolbar.buildViewSelectorBar` | 5 |
| `_AllDebridFilesScreenState._buildSelectionBar` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_toolbar.dart` | `AllDebridToolbar.buildSelectionBar` | 5 |
| `_AllDebridFilesScreenState._searchDecoration` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_bars.dart` | `AllDebridSearchBars.searchDecoration` | 5 |
| `_AllDebridFilesScreenState._moveFocusTo` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search.dart` | `AllDebridSearch.moveFocusTo` | 3 |
| `_AllDebridFilesScreenState._buildSearchBar` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_bars.dart` | `AllDebridSearchBars.buildSearchBar` | 5 |
| `_AllDebridFilesScreenState._buildFileSearchBar` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_bars.dart` | `AllDebridSearchBars.buildFileSearchBar` | 5 |
| `_AllDebridFilesScreenState._buildBody` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_root_layout.dart` | `AllDebridRootLayout.buildBody` | 5 |
| `_AllDebridFilesScreenState._buildMagnetsView` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_list_views.dart` | `AllDebridListViews.buildMagnetsView` | 5 |
| `_AllDebridFilesScreenState._buildMagnetCard` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_list_views.dart` | `AllDebridListViews.buildMagnetCard` | 5 |
| `_AllDebridFilesScreenState._buildLinksView` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_list_views.dart` | `AllDebridListViews.buildLinksView` | 5 |
| `_AllDebridFilesScreenState._buildLinkCard` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_list_views.dart` | `AllDebridListViews.buildLinkCard` | 5 |
| `_AllDebridFilesScreenState._buildFilesView` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_list_views.dart` | `AllDebridListViews.buildFilesView` | 5 |
| `_AllDebridFilesScreenState._buildFileCard` | `lib/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_list_views.dart` | `AllDebridListViews.buildFileCard` | 5 |

The final file estimates (original normally formatted method/field lines plus modest imports/deps) are: library loading 90; navigation 170; playback 240; downloads 155; add actions 170; deletes 165; playlist 65; selection 55; search 70; feedback 55; root layout 95; toolbar 255; search bars 185; list views 370. Owners are at most 45 lines each. Reassess before extending; no size exception is pre-approved.

## Callback owner by step

| Callback | Step 0–1 | Step 2 | Step 3–6 |
| --- | --- | --- | --- |
| `_handleBackNavigation` push/pop/tab | State | State | stable `_sections.navigation.handleBackNavigation` |
| `_focusWebDownloads` assignment **and comparison operand** | State | State | stable `_sections.navigation.focusWebDownloads` |
| TV tab-12 stored closure | State field | `_focus.tvContentFocusHandler` | same `_focus.tvContentFocusHandler` |
| `_refresh` dormant accessor tear-off | State | State | stable `_sections.navigation.refresh` |

Both lifecycle methods remain in State throughout. Deep-link comparison reads the raw right operand of `focusAllDebridWebDownloads ==`; wrapper or receiver swap must independently fail there and at assignment. Unregister-tab remains key-only; it has no callback identity operand.

## Per-entry wiring checklist

Each row is one review item. Reads/writes derive from original AST references, including closure scopes. In-place clear/add/remove/removeWhere/sort mutations remain at their original statements (not moved into setters). Calls listed below are original State members; external calls stay in the original method body. At its extraction step, review the exact parameter/default/named argument signature, fields, live values and each listed cross-call against this row **before** recording scaffolds. Step 0 records expected wiring only; no future factory is blessed by a fingerprint. `☐` means production wiring review belongs to that later step.

| Entry / step | Original signature | State reads / writes | State calls or tear-offs | Review |
| --- | --- | --- | --- | --- |
| `AllDebridFilesScreen.AllDebridFilesScreen` / 0 | `const AllDebridFilesScreen({ super.key, this.isPushedRoute = false, this.initialSearchQuery, this.selectSourceMode = false, this.onSourceSelected, });` | read —; write — | — | retained; checked now |
| `AllDebridFilesScreen.createState` / 0 | `@override State<AllDebridFilesScreen> createState()` | read —; write — | — | retained; checked now |
| `_AllDebridFilesScreenState._isAtRoot` / 3 | `bool get _isAtRoot` | read _currentMagnet; write — | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState.initState` / 0 | `@override void initState()` | read _searchController, _selectedView, _tabIndex, _tvContentFocusHandler; write _searchActive, _searchQuery, _selectedView, _shouldFocusOnLoad, _tvContentFocusHandler | `_focusFirstItem`, `_focusWebDownloads`, `_handleBackNavigation`, `_load`, `_loadLinks`, `initState` | retained; checked now |
| `_AllDebridFilesScreenState._focusWebDownloads` / 3 | `/// Switches to the Web Downloads view and refreshes it. Invoked via /// [MainPageBridge.focusAllDebridWebDownloads] when a shared web link is saved /// while this screen is already mounted. Future<void> _focusWebDownloads()` | read _searchController, _selectedIds; write _currentFiles, _currentMagnet, _searchActive, _searchQuery, _selectedView, _selectionMode | `_loadLinks` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState.dispose` / 0 | `@override void dispose()` | read _backButtonFocusNode, _deleteButtonFocusNode, _fileSearchController, _fileSearchFocusNode, _firstItemFocusNode, _scrollController, _searchClearFocusNode, _searchController, _searchFocusNode, _tabIndex, _toolbarSearchFocusNode, _tvContentFocusHandler; write — | `_focusWebDownloads`, `_handleBackNavigation`, `dispose` | retained; checked now |
| `_AllDebridFilesScreenState._focusFirstItem` / 3 | `void _focusFirstItem()` | read _firstItemFocusNode, _selectedView, _shouldFocusOnLoad; write _shouldFocusOnLoad | `_isAtRoot`, `_visibleLinks`, `_visibleMagnets` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._load` / 3 | `Future<void> _load()` | read _magnets, _selectedIds; write _apiKey, _error, _loading, _magnets | `_focusFirstItem` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._loadLinks` / 3 | `Future<void> _loadLinks()` | read _apiKey; write _apiKey, _links, _linksError, _linksLoadedOnce, _loadingLinks | `_focusFirstItem` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._refresh` / 3 | `Future<void> _refresh()` | read _currentMagnet, _selectedView; write — | `_load`, `_loadLinks`, `_openMagnet` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._openMagnet` / 3 | `Future<void> _openMagnet(AllDebridMagnet magnet, {bool force = false})` | read _apiKey, _fileSearchController; write _currentFiles, _currentMagnet, _fileSearchActive, _fileSearchQuery, _loadingFiles | `_snack` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._navigateUp` / 3 | `void _navigateUp()` | read _fileSearchController, _scrollController; write _currentFiles, _currentMagnet, _fileSearchActive, _fileSearchQuery, _loadingFiles, _shouldFocusOnLoad | `_focusFirstItem` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._handleBackNavigation` / 3 | `bool _handleBackNavigation()` | read _currentMagnet, _fileSearchActive, _fileSearchController, _searchActive, _selectionMode; write _fileSearchActive, _fileSearchQuery | `_exitSelectionMode`, `_navigateUp`, `_toggleSearch` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._looksLikeVideo` / 4 | `bool _looksLikeVideo(AllDebridFile f)` | read —; write — | — | ☐ at Step 4 |
| `_AllDebridFilesScreenState._unlockStart` / 4 | `Future<String> _unlockStart(String apiKey, String lockedLink)` | read —; write — | — | ☐ at Step 4 |
| `_AllDebridFilesScreenState._playFile` / 4 | `Future<void> _playFile(AllDebridFile file)` | read _apiKey; write — | `_dismissLoading`, `_showLoading`, `_snack`, `_unlockStart` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._playMagnet` / 4 | `Future<void> _playMagnet(AllDebridMagnet magnet)` | read _apiKey, _currentFiles, _currentMagnet; write — | `_dismissLoading`, `_playVideos`, `_showLoading`, `_snack` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._playVideos` / 4 | `Future<void> _playVideos( List<AllDebridFile> files, String collectionName, )` | read _apiKey; write — | `_dismissLoading`, `_findFirstEpisodeIndex`, `_looksLikeVideo`, `_playFile`, `_showLoading`, `_snack`, `_unlockStart` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._findFirstEpisodeIndex` / 4 | `int _findFirstEpisodeIndex(List<SeriesInfo> infos)` | read —; write — | — | ☐ at Step 4 |
| `_AllDebridFilesScreenState._downloadFile` / 4 | `Future<void> _downloadFile(AllDebridFile file)` | read _apiKey; write — | `_dismissLoading`, `_showLoading`, `_snack`, `_unlockStart` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._downloadMagnet` / 4 | `Future<void> _downloadMagnet(AllDebridMagnet magnet)` | read _apiKey, _currentFiles, _currentMagnet; write — | `_dismissLoading`, `_downloadSelectedFiles`, `_showLoading`, `_snack` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._downloadSelectedFiles` / 4 | `Future<void> _downloadSelectedFiles( List<Map<String, dynamic>> selected, List<AllDebridFile> allFiles, String magnetName, )` | read _apiKey; write — | `_snack`, `_unlockStart` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._showAddMagnetDialog` / 4 | `Future<void> _showAddMagnetDialog()` | read _apiKey; write — | `_dismissLoading`, `_load`, `_showLoading`, `_snack` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._playLink` / 4 | `Future<void> _playLink(AllDebridLink l)` | read _apiKey; write — | `_dismissLoading`, `_showLoading`, `_snack`, `_unlockStart` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._downloadLink` / 4 | `Future<void> _downloadLink(AllDebridLink l)` | read _apiKey; write — | `_dismissLoading`, `_showLoading`, `_snack`, `_unlockStart` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._copyLink` / 4 | `Future<void> _copyLink(AllDebridLink l)` | read _apiKey; write — | `_dismissLoading`, `_showLoading`, `_snack`, `_unlockStart` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._showAddLinkDialog` / 4 | `Future<void> _showAddLinkDialog()` | read _apiKey; write — | `_dismissLoading`, `_loadLinks`, `_showLoading`, `_snack` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._deleteLinks` / 4 | `Future<void> _deleteLinks(List<AllDebridLink> links, {String? title})` | read _apiKey; write — | `_dismissLoading`, `_loadLinks`, `_showLoading`, `_snack` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._confirmDeleteAllLinks` / 4 | `void _confirmDeleteAllLinks()` | read _links; write — | `_deleteLinks` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._addMagnetToPlaylist` / 4 | `/// Saves a magnet to the playlist (RD-manner: keyed by infohash). Single /// video → 'single' with its locked link; multiple → 'collection' re-resolved /// by hash at play time. Future<void> _addMagnetToPlaylist(AllDebridMagnet magnet)` | read _apiKey, _currentFiles, _currentMagnet; write — | `_dismissLoading`, `_looksLikeVideo`, `_showLoading`, `_snack` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._deleteMagnets` / 4 | `Future<void> _deleteMagnets( List<AllDebridMagnet> magnets, { String? title, })` | read _apiKey; write — | `_dismissLoading`, `_exitSelectionMode`, `_load`, `_showLoading`, `_snack` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._confirmDeleteAll` / 4 | `void _confirmDeleteAll()` | read _magnets; write — | `_deleteMagnets` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._toggleSelectionMode` / 3 | `void _toggleSelectionMode()` | read _selectedIds, _selectionMode; write _selectionMode | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._exitSelectionMode` / 3 | `void _exitSelectionMode()` | read _selectedIds, _selectionMode; write _selectionMode | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._toggleSelection` / 3 | `void _toggleSelection(String id)` | read _selectedIds; write — | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._isAllSelected` / 3 | `bool get _isAllSelected` | read _selectedIds; write — | `_visibleMagnets` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._toggleSelectAll` / 3 | `void _toggleSelectAll()` | read _selectedIds; write — | `_isAllSelected`, `_visibleMagnets` | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._handleDeleteSelected` / 4 | `Future<void> _handleDeleteSelected()` | read _magnets, _selectedIds; write — | `_deleteMagnets` | ☐ at Step 4 |
| `_AllDebridFilesScreenState._toggleSearch` / 3 | `void _toggleSearch()` | read _searchActive, _searchController, _searchFocusNode; write _searchActive, _searchQuery | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._visibleMagnets` / 3 | `List<AllDebridMagnet> get _visibleMagnets` | read _magnets, _searchQuery; write — | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._visibleFiles` / 3 | `List<AllDebridFile> get _visibleFiles` | read _currentFiles, _fileSearchQuery; write — | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._visibleLinks` / 3 | `List<AllDebridLink> get _visibleLinks` | read _links, _searchQuery; write — | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._showLoading` / 3 | `void _showLoading(String message)` | read _loadingDialogOpen; write _loadingDialogOpen | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._dismissLoading` / 3 | `void _dismissLoading()` | read _loadingDialogOpen; write _loadingDialogOpen | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._snack` / 3 | `void _snack(String message, {bool isError = true})` | read —; write — | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState.build` / 5 | `@override Widget build(BuildContext context)` | read _backButtonFocusNode, _currentFiles, _currentMagnet, _fileSearchActive, _fileSearchController, _fileSearchFocusNode, _searchActive, _selectionMode; write _fileSearchActive, _fileSearchQuery | `_buildBody`, `_buildFileSearchBar`, `_buildSearchBar`, `_buildSelectionBar`, `_buildToolbar`, `_buildViewSelectorBar`, `_isAtRoot`, `_navigateUp` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._isBrowsePush` / 5 | `/// Pushed (from the Cloud hub or the openAllDebridFolder deep link) to browse /// — the root has no other Back affordance, so show one. bool get _isBrowsePush` | read —; write — | — | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildToolbar` / 5 | `Widget _buildToolbar()` | read _links, _magnets, _searchActive, _selectedView, _selectionMode, _toolbarSearchFocusNode; write — | `_confirmDeleteAll`, `_confirmDeleteAllLinks`, `_isBrowsePush`, `_refresh`, `_showAddLinkDialog`, `_showAddMagnetDialog`, `_toggleSearch`, `_toggleSelectionMode` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildViewSelectorBar` / 5 | `/// Full-width view switcher on its own line under the toolbar (two labels /// don't fit the toolbar slot the old single-label dropdown used). Widget _buildViewSelectorBar()` | read _linksLoadedOnce, _scrollController, _searchController, _selectedView; write _searchActive, _searchQuery, _selectedView | `_exitSelectionMode`, `_loadLinks` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildSelectionBar` / 5 | `Widget _buildSelectionBar()` | read _deleteButtonFocusNode, _selectedIds; write — | `_handleDeleteSelected`, `_isAllSelected`, `_toggleSelectAll` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._searchDecoration` / 5 | `/// Shared search-field decoration matching the cloud-screen styling. InputDecoration _searchDecoration(String hint)` | read —; write — | — | ☐ at Step 5 |
| `_AllDebridFilesScreenState._moveFocusTo` / 3 | `/// D-pad escape target for a search field (used by the TvTextField arrow /// callbacks below). void _moveFocusTo(FocusNode? target, FocusNode field)` | read —; write — | — | ✓ reviewed at Step 3 |
| `_AllDebridFilesScreenState._buildSearchBar` / 5 | `Widget _buildSearchBar()` | read _firstItemFocusNode, _searchClearFocusNode, _searchController, _searchFocusNode, _selectedView, _toolbarSearchFocusNode; write _searchQuery | `_moveFocusTo`, `_searchDecoration` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildFileSearchBar` / 5 | `Widget _buildFileSearchBar()` | read _backButtonFocusNode, _fileSearchController, _fileSearchFocusNode, _firstItemFocusNode; write _fileSearchQuery | `_moveFocusTo`, `_searchDecoration` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildBody` / 5 | `Widget _buildBody()` | read _error, _loading, _selectedView; write — | `_buildFilesView`, `_buildLinksView`, `_buildMagnetsView`, `_isAtRoot`, `_load` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildMagnetsView` / 5 | `Widget _buildMagnetsView()` | read _scrollController, _searchQuery; write — | `_buildMagnetCard`, `_load`, `_visibleMagnets` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildMagnetCard` / 5 | `Widget _buildMagnetCard(AllDebridMagnet m, int index)` | read _firstItemFocusNode, _selectedIds, _selectionMode; write — | `_addMagnetToPlaylist`, `_deleteMagnets`, `_downloadMagnet`, `_openMagnet`, `_playMagnet`, `_snack`, `_toggleSelection` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildLinksView` / 5 | `Widget _buildLinksView()` | read _linksError, _loadingLinks, _scrollController, _searchQuery; write — | `_buildLinkCard`, `_loadLinks`, `_visibleLinks` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildLinkCard` / 5 | `Widget _buildLinkCard(AllDebridLink l, int index)` | read _firstItemFocusNode; write — | `_copyLink`, `_deleteLinks`, `_downloadLink`, `_playLink` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildFilesView` / 5 | `Widget _buildFilesView()` | read _currentMagnet, _fileSearchQuery, _loadingFiles; write — | `_buildFileCard`, `_visibleFiles` | ☐ at Step 5 |
| `_AllDebridFilesScreenState._buildFileCard` / 5 | `Widget _buildFileCard(AllDebridFile f, int index)` | read _firstItemFocusNode; write — | `_downloadFile`, `_looksLikeVideo`, `_playFile` | ☐ at Step 5 |

## Playback argument ledger

`dev/tool/alldebrid_files_playback_ledger.json` freezes the scanner tokens for every ordered launch/entry argument and the complete owning methods. This is the authority for token-exact verification; do not regenerate it from moved code. The checker self-test checks the original fixture against it. Dart source guards additionally freeze complete playback/download/playlist/lifecycle bodies and pin site counts.

| Site | Launch arguments in order | Entry arguments in order |
| --- | --- | --- |
| `_playFile` | `videoUrl: url`, `title: file.fileName`, `subtitle: file.size > 0 ? Formatters.formatFileSize(file.size) : null`, `playlist: [PlaylistEntry(...)]`, `startIndex: 0`, `viewMode: PlaylistViewMode.sorted` | `url: url`, `title: file.fileName`, `relativePath: file.fileName`, `provider: 'alldebrid'`, `allDebridLink: file.link`, `sizeBytes: file.size > 0 ? file.size : null` |
| `_playVideos` (magnet) | `videoUrl: startUrl`, `title: collectionName`, `subtitle: subtitle`, `playlist: entries`, `startIndex: startIndex`, `viewMode: isSeries ? PlaylistViewMode.series : PlaylistViewMode.sorted` | `url: i == startIndex ? startUrl : ''`, `title: v.fileName`, `relativePath: relativePath`, `provider: 'alldebrid'`, `allDebridLink: v.link`, `sizeBytes: v.size > 0 ? v.size : null` |
| `_playLink` | `videoUrl: url`, `title: l.fileName`, `subtitle: l.size > 0 ? Formatters.formatFileSize(l.size) : null`, `playlist: [PlaylistEntry(...)]`, `startIndex: 0`, `viewMode: PlaylistViewMode.sorted` | `url: url`, `title: l.fileName`, `relativePath: l.fileName`, `provider: 'alldebrid'`, `allDebridLink: l.link`, `sizeBytes: l.size > 0 ? l.size : null` |

All three immediately call `MainPageBridge.notifyPlayerLaunching()` before `await VideoPlayerLauncher.push(context, ...)`. Multi-file relativePath strips the first segment only when firstSlash >0; subtitle is `N episodes/files • formatted size`; seasonal/episode/name sort, first-episode helper, clamp, sequential fallback and mounted guards remain frozen in complete method tokens. Entries except the chosen start retain an empty URL.

## Source-text inventory and port schedule

| Reader / registration | Observed original | Step owning the change |
| --- | --- | --- |
| `theme_surface_manifest.txt` cloud registry | cloud wildcard already covers facade; add feature globs when destinations exist | 1 |
| `test/theme/shape_manifest_test.dart` | facade 1 bare radius (`_buildSelectionBar`), 5 `app.shape.br` calls (toolbar 1, search decoration 3, search bar 1) | 5 destinations, 6 final facade transition |
| Shape destinations | toolbar + search-bars in kShapeResidue; every other owner/helper/model/deps/composition in kExtractedShapeResidue at zero; root/list-view also zero | each creation step; final facade leaves kShapeResidue and enters extracted at 0 in 6 |
| `file_size_baseline.txt:38` | 1,996 facade lines; manual seam-only raise now, shrink-only thereafter | 0 seam, then every extraction |
| `check_search_architecture.py` | feature unregistered; exact bridge, bidirectional models-inclusive peers, launcher/enqueue placement, 500 caps and negatives | 1; final facade cap/TEMP in 6 |
| `.github/workflows/checks.yml` | format/analyze facade + every new support helper path inside commands | 0 |
| `dev/tool/ci_behavior_tests.txt` | add all concrete new tests; retain both caller tests | 0 |
| `light_ink_inventory.py` PRIMARY | optional reporting feature path | 1 |
| Generic profile/theme/storage readers | repo scans; no hard-coded AllDebrid source rewrite found; run affected source guards and storage tools | 0 and subsequent checks |
| Production callers | main tab/deep-link/hub, home source editor; existing web picker/home editor tests | every step |

No Step 1 guard/theme registration or Step 5 shape redistribution is performed here. No Premiumize source/config is edited. Every existing manifest is run with an isolated parser package and existing adapter/checker output is compared before/after the opt-in callback selector. Fresh normal clone verification covers every new checker/self-test after flutter pub get.

## Verification records

Run evidence and mutation results are recorded in the plan Progress section and in the common git directory under `refactor-evidence/alldebrid_files/`. macOS original pixels are committed now; Linux capture remains Claude-owned Step L. Successful native enqueue, physical focus and all launcher handoffs remain pending unless an original-code fixture/device proof is explicitly recorded.
