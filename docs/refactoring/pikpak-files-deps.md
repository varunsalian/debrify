# PikPak files declaration dependency report

Original source `c2e02c0d`, Flutter 3.44.8 / Dart 3.12.2. The 128-leaf manifest is authoritative; every original field and method has one owner. initState/dispose remain in State, with receiver-only changes. No lifecycle, timing, API, public surface or profile semantics change.

Temporary oversized facade: `lib/screens/pikpak/pikpak_files_screen.dart` holds all original workflows plus the frozen test accessor at step 0. It shrinks at each scheduled step; final cap 400 in step 7. The accessor is characterization scaffolding retained with a fixed token fingerprint; no service/clock seam is introduced.

Private `_email` remains in the State through step 2 and moves privately with `_loadSettings` in step 3. Keep its original unused_field warning; record relocation in the analyzer inventory, never suppress it.

The sort calculation reads no State and moves to application. `_applySeriesArrangeView` reads DateTime.now and stays in the legacy presentation bridge. No parameter is added to purify it. Dormant series/view/search/cache branches keep their reachability and original mutable map/cast behavior.

## Declaration inventory

| Original declaration | Step / destination | Reads | Writes | Calls / tear-offs |
| --- | --- | --- | --- | --- |
| `PikPakFilesScreen.initialFolderId` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` |  |  |  |
| `PikPakFilesScreen.initialFolderName` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` |  |  |  |
| `PikPakFilesScreen.selectSourceMode` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` |  |  |  |
| `PikPakFilesScreen.onSourceSelected` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` |  |  |  |
| `PikPakFilesScreen.isPushedRoute` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` |  |  |  |
| `PikPakFilesScreen.PikPakFilesScreen` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` |  |  |  |
| `PikPakFilesScreen.createState` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` |  |  |  |
| `_FolderViewMode` | 1 / `lib/features/pikpak_files/models/folder_view_mode.dart` |  |  |  |
| `_PikPakFilesScreenState._scrollController` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._files` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._tvContentFocusHandler` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._isLoading` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._initialLoad` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._errorMessage` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._pikpakEnabled` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._showVideosOnly` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._ignoreSmallVideos` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._email` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart` |  |  |  |
| `_PikPakFilesScreenState._linkController` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_state.dart` |  |  |  |
| `_PikPakFilesScreenState._isAddingLink` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_state.dart` |  |  |  |
| `_PikPakFilesScreenState._nextPageToken` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._hasMore` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._isLoadingMore` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart` |  |  |  |
| `_PikPakFilesScreenState._currentFolderId` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart` |  |  |  |
| `_PikPakFilesScreenState._currentFolderName` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart` |  |  |  |
| `_PikPakFilesScreenState._navigationStack` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart` |  |  |  |
| `_PikPakFilesScreenState._restrictedFolderId` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart` |  |  |  |
| `_PikPakFilesScreenState._restrictedFolderName` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart` |  |  |  |
| `_PikPakFilesScreenState._isAtRestrictedRoot` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart` |  |  |  |
| `_PikPakFilesScreenState._folderViewModes` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart` |  |  |  |
| `_PikPakFilesScreenState._isInVirtualFolder` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart` |  |  |  |
| `_PikPakFilesScreenState._virtualFolderName` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart` |  |  |  |
| `_PikPakFilesScreenState._virtualFolderFiles` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart` |  |  |  |
| `_PikPakFilesScreenState._recursiveFileCache` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart` |  |  |  |
| `_PikPakFilesScreenState._refreshButtonFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._backButtonFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._retryButtonFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._settingsButtonFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._viewModeDropdownFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._addLinkButtonFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._firstItemFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._shouldFocusOnLoad` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._isSelectionMode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_state.dart` |  |  |  |
| `_PikPakFilesScreenState._selectedFileIds` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_state.dart` |  |  |  |
| `_PikPakFilesScreenState._selectableFileCount` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_actions.dart` | _files |  |  |
| `_PikPakFilesScreenState._isAllSelected` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_actions.dart` | _selectableFileCount, _selectedFileIds |  |  |
| `_PikPakFilesScreenState._deleteButtonFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart` |  |  |  |
| `_PikPakFilesScreenState._isSearchActive` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart` |  |  |  |
| `_PikPakFilesScreenState._searchController` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart` |  |  |  |
| `_PikPakFilesScreenState._searchFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart` |  |  |  |
| `_PikPakFilesScreenState._searchButtonFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart` |  |  |  |
| `_PikPakFilesScreenState._searchClearFocusNode` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart` |  |  |  |
| `_PikPakFilesScreenState._searchResults` | 2 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart` |  |  |  |
| `_PikPakFilesScreenState.initState` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` | _currentFolderId, _handleBackNavigation, _onScroll, _scrollController, context, mounted, widget | _shouldFocusOnLoad, _tvContentFocusHandler | _focusFirstItemOrFallback, _loadSettings, initState |
| `_PikPakFilesScreenState._selectBoundSource` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_source_binding.dart` | context, mounted, widget |  | _showSnackBar |
| `_PikPakFilesScreenState._onScroll` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart` | _scrollController |  | _loadMoreFiles |
| `_PikPakFilesScreenState._resetListScroll` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart` | _onScroll, _scrollController |  |  |
| `_PikPakFilesScreenState._focusFirstItemOrFallback` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_actions.dart` | _addLinkButtonFocusNode, _files, _firstItemFocusNode, _isLoading, _shouldFocusOnLoad, mounted | _shouldFocusOnLoad |  |
| `_PikPakFilesScreenState.dispose` | 0 / `lib/screens/pikpak/pikpak_files_screen.dart` | _addLinkButtonFocusNode, _backButtonFocusNode, _deleteButtonFocusNode, _firstItemFocusNode, _handleBackNavigation, _linkController, _refreshButtonFocusNode, _retryButtonFocusNode, _scrollController, _searchButtonFocusNode, _searchClearFocusNode, _searchController, _searchFocusNode, _settingsButtonFocusNode, _tvContentFocusHandler, _viewModeDropdownFocusNode, widget |  | dispose |
| `_PikPakFilesScreenState._handleBackNavigation` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_back_navigation.dart` | _currentFolderId, _isInVirtualFolder, _isSearchActive, _isSelectionMode, _navigationStack, _restrictedFolderId, context, widget |  | _exitSelectionMode, _navigateUpWithVirtual, _toggleSearch |
| `_PikPakFilesScreenState._loadSettings` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart` | mounted, widget | _currentFolderId, _currentFolderName, _email, _ignoreSmallVideos, _isAtRestrictedRoot, _pikpakEnabled, _restrictedFolderId, _restrictedFolderName, _showVideosOnly | _handleRestrictedFolderDeleted, _loadFiles, setState |
| `_PikPakFilesScreenState._handleRestrictedFolderDeleted` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart` | mounted | _errorMessage, _initialLoad, _isLoading, _pikpakEnabled, _restrictedFolderId, _restrictedFolderName | _showSnackBar, setState |
| `_PikPakFilesScreenState._loadFiles` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart` | _currentFolderId, _files, _isLoading, _restrictedFolderId, mounted | _errorMessage, _hasMore, _initialLoad, _isLoading, _nextPageToken | _applyViewMode, _filterFiles, _focusFirstItemOrFallback, _getCurrentViewMode, _handleRestrictedFolderDeleted, setState |
| `_PikPakFilesScreenState._loadMoreFiles` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_loading.dart` | _currentFolderId, _files, _hasMore, _isLoadingMore, _nextPageToken, mounted | _hasMore, _isLoadingMore, _nextPageToken | _applyViewMode, _filterFiles, _getCurrentViewMode, _showSnackBar, setState |
| `_PikPakFilesScreenState._filterFiles` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_navigation.dart` | _ignoreSmallVideos, _showVideosOnly |  |  |
| `_PikPakFilesScreenState._navigateIntoFolder` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_navigation.dart` | _currentFolderId, _currentFolderName, _files, _navigationStack | _currentFolderId, _currentFolderName, _isAtRestrictedRoot, _shouldFocusOnLoad | _exitSelectionMode, _loadFiles, _resetListScroll, setState |
| `_PikPakFilesScreenState._navigateUp` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_navigation.dart` | _currentFolderId, _files, _navigationStack, _restrictedFolderId, _restrictedFolderName | _currentFolderId, _currentFolderName, _isAtRestrictedRoot, _shouldFocusOnLoad | _exitSelectionMode, _loadFiles, _resetListScroll, _showSnackBar, setState |
| `_PikPakFilesScreenState._navigateUpWithVirtual` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_navigation.dart` | _isInVirtualFolder, _virtualFolderFiles | _isInVirtualFolder, _shouldFocusOnLoad, _virtualFolderName | _focusFirstItemOrFallback, _getCurrentViewMode, _navigateUp, _resetListScroll, _setViewMode, setState |
| `_PikPakFilesScreenState._navigateIntoVirtualFolder` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_navigation.dart` | _files, _virtualFolderFiles | _isInVirtualFolder, _shouldFocusOnLoad, _virtualFolderFiles, _virtualFolderName | _exitSelectionMode, _focusFirstItemOrFallback, _resetListScroll, _showSnackBar, setState |
| `_PikPakFilesScreenState._playFile` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_playback.dart` | context, mounted |  | _showSnackBar |
| `_PikPakFilesScreenState._downloadFile` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_download.dart` | context, mounted |  | _showSnackBar |
| `_PikPakFilesScreenState._downloadFolder` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_download.dart` | context, mounted |  | _downloadSelectedPikPakFiles, _showSnackBar |
| `_PikPakFilesScreenState._downloadSelectedPikPakFiles` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_download.dart` | context, mounted |  | _showSnackBar |
| `_PikPakFilesScreenState._refreshFiles` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_feedback.dart` | _currentFolderId, _isInVirtualFolder, _recursiveFileCache, _virtualFolderFiles | _isInVirtualFolder, _virtualFolderName | _exitSelectionMode, _loadFiles, _showSnackBar, setState |
| `_PikPakFilesScreenState._showDeleteDialog` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_delete_actions.dart` | context |  | _deleteFile, _showSnackBar |
| `_PikPakFilesScreenState._deleteFile` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_delete_actions.dart` | _files, mounted |  | _showSnackBar, setState |
| `_PikPakFilesScreenState._toggleSelectionMode` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_actions.dart` | _isSelectionMode, _selectedFileIds | _isSelectionMode | setState |
| `_PikPakFilesScreenState._exitSelectionMode` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_actions.dart` | _isSelectionMode, _selectedFileIds | _isSelectionMode | setState |
| `_PikPakFilesScreenState._toggleFileSelection` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_actions.dart` | _selectedFileIds |  | setState |
| `_PikPakFilesScreenState._toggleSelectAll` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_actions.dart` | _files, _isAllSelected, _selectedFileIds |  | setState |
| `_PikPakFilesScreenState._handleDeleteSelected` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_delete_actions.dart` | _selectedFileIds, context, mounted |  | _executeDeleteSelected |
| `_PikPakFilesScreenState._executeDeleteSelected` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_delete_actions.dart` | _files, _selectedFileIds, mounted | _isSelectionMode | _exitSelectionMode, _showSnackBar, setState |
| `_PikPakFilesScreenState._showSnackBar` | 3 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_feedback.dart` | context, mounted |  |  |
| `_PikPakFilesScreenState._getCurrentViewMode` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_modes.dart` | _currentFolderId, _folderViewModes, _isInVirtualFolder |  |  |
| `_PikPakFilesScreenState._setViewMode` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_modes.dart` | _currentFolderId, _files, _folderViewModes, _recursiveFileCache | _hasMore, _isLoading, _nextPageToken | _applySeriesArrangeView, _applyViewMode, _showFallbackToSorted, setState |
| `_PikPakFilesScreenState._showFallbackToSorted` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_modes.dart` | _files, _folderViewModes, context, mounted | _isLoading | _applySortedView, setState |
| `_PikPakFilesScreenState._applyViewMode` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_modes.dart` |  |  | _applySeriesArrangeView, _applySortedView |
| `_PikPakFilesScreenState._applySortedView` | 1 / `lib/features/pikpak_files/application/pikpak_sort_policy.dart` |  |  | _extractLeadingNumber, _extractSeasonNumber |
| `_PikPakFilesScreenState._extractSeasonNumber` | 1 / `lib/features/pikpak_files/application/pikpak_sort_policy.dart` |  |  |  |
| `_PikPakFilesScreenState._extractLeadingNumber` | 1 / `lib/features/pikpak_files/application/pikpak_sort_policy.dart` |  |  |  |
| `_PikPakFilesScreenState._applySeriesArrangeView` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_modes.dart` |  |  | _applySortedView |
| `_PikPakFilesScreenState._buildViewModeDropdown` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_toolbar_layout.dart` | _backButtonFocusNode, _viewModeDropdownFocusNode, context |  | _getCurrentViewMode, _setViewMode |
| `_PikPakFilesScreenState._toggleSearch` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_actions.dart` | _isSearchActive, _searchController, _searchFocusNode, _searchResults | _isSearchActive | setState |
| `_PikPakFilesScreenState._performSearch` | 4 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_actions.dart` | _currentFolderId, _files, _recursiveFileCache | _searchResults | setState |
| `_PikPakFilesScreenState._buildSearchBar` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_layout.dart` | _performSearch, _searchClearFocusNode, _searchController, _searchFocusNode, _searchResults, context |  | setState |
| `_PikPakFilesScreenState._buildSearchResults` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_layout.dart` | _searchController, _searchResults |  | _buildSearchResultCard |
| `_PikPakFilesScreenState._buildSearchResultCard` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_layout.dart` | widget |  | _playFile, _selectBoundSource |
| `_PikPakFilesScreenState._isBrowsePush` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_root_layout.dart` | widget |  |  |
| `_PikPakFilesScreenState.build` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_root_layout.dart` | _addLinkButtonFocusNode, _backButtonFocusNode, _currentFolderId, _currentFolderName, _errorMessage, _files, _initialLoad, _isAtRestrictedRoot, _isBrowsePush, _isInVirtualFolder, _isLoading, _isSearchActive, _isSelectionMode, _navigationStack, _pikpakEnabled, _refreshButtonFocusNode, _refreshFiles, _restrictedFolderId, _searchButtonFocusNode, _showAddLinkDialog, _toggleSearch, _toggleSelectionMode, _virtualFolderName, context, widget |  | _buildEmpty, _buildError, _buildFileList, _buildNotEnabled, _buildSearchBar, _buildSearchResults, _buildSelectionBar, _buildViewModeDropdown, _getCurrentViewMode, _handleBackNavigation |
| `_PikPakFilesScreenState._buildNotEnabled` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_status_layout.dart` | _settingsButtonFocusNode, context |  | _showSnackBar |
| `_PikPakFilesScreenState._buildError` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_status_layout.dart` | _errorMessage, _refreshFiles, _retryButtonFocusNode, context |  |  |
| `_PikPakFilesScreenState._buildEmpty` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_status_layout.dart` | _currentFolderId, context |  |  |
| `_PikPakFilesScreenState._buildSelectionBar` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_toolbar_layout.dart` | _deleteButtonFocusNode, _handleDeleteSelected, _isAllSelected, _selectedFileIds, _toggleSelectAll, context |  |  |
| `_PikPakFilesScreenState._buildFileList` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_list.dart` | _files, _hasMore, _isLoadingMore, _scrollController |  | _buildFileCard, _buildLoadingIndicator |
| `_PikPakFilesScreenState._buildLoadingIndicator` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_list.dart` | _hasMore, _isLoadingMore |  |  |
| `_PikPakFilesScreenState._buildFileCard` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_list.dart` | _firstItemFocusNode, _isSelectionMode, _selectedFileIds, widget |  | _downloadFile, _downloadFolder, _formatDate, _handleAddToPlaylist, _navigateIntoFolder, _navigateIntoVirtualFolder, _playFile, _playFolder, _selectBoundSource, _showDeleteDialog, _toggleFileSelection |
| `_PikPakFilesScreenState._formatDate` | 6 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_file_list.dart` |  |  |  |
| `_PikPakFilesScreenState._playFolder` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_playback.dart` | _ignoreSmallVideos, _showVideosOnly, context, mounted |  | _playPikPakVideos, _showSnackBar |
| `_PikPakFilesScreenState._playPikPakVideos` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_folder_playback.dart` | context, mounted |  | _combineSeriesAndEpisodeTitle, _findFirstEpisodeIndex, _formatPikPakPlaylistTitle, _pikpakDisplayName, _showSnackBar |
| `_PikPakFilesScreenState._handleAddToPlaylist` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_playlist_actions.dart` |  |  | _addFolderToPlaylist, _addSingleFileToPlaylist |
| `_PikPakFilesScreenState._addSingleFileToPlaylist` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_playlist_actions.dart` |  |  | _showSnackBar |
| `_PikPakFilesScreenState._addFolderToPlaylist` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_playlist_actions.dart` | _ignoreSmallVideos, context, mounted |  | _showSnackBar |
| `_PikPakFilesScreenState._pikpakDisplayName` | 1 / `lib/features/pikpak_files/application/pikpak_playlist_titles.dart` |  |  |  |
| `_PikPakFilesScreenState._formatPikPakPlaylistTitle` | 1 / `lib/features/pikpak_files/application/pikpak_playlist_titles.dart` |  |  |  |
| `_PikPakFilesScreenState._combineSeriesAndEpisodeTitle` | 1 / `lib/features/pikpak_files/application/pikpak_playlist_titles.dart` |  |  |  |
| `_PikPakFilesScreenState._findFirstEpisodeIndex` | 1 / `lib/features/pikpak_files/application/pikpak_playlist_titles.dart` |  |  |  |
| `_PikPakFilesScreenState._showAddLinkDialog` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_actions.dart` | _addLink, _isAddingLink, _linkController, context, mounted |  | _autoPasteLink |
| `_PikPakFilesScreenState._autoPasteLink` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_actions.dart` | _linkController |  |  |
| `_PikPakFilesScreenState._isValidPikPakLink` | 1 / `lib/features/pikpak_files/application/pikpak_link_policy.dart` |  |  |  |
| `_PikPakFilesScreenState._addLink` | 5 / `lib/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_actions.dart` | _currentFolderId, _linkController, _restrictedFolderId, context, mounted | _isAddingLink | _isValidPikPakLink, _refreshFiles, _showSnackBar, setState |
| `_PikPakPlaylistItem.file` | 1 / `lib/features/pikpak_files/models/pikpak_playlist_item.dart` |  |  |  |
| `_PikPakPlaylistItem.originalIndex` | 1 / `lib/features/pikpak_files/models/pikpak_playlist_item.dart` |  |  |  |
| `_PikPakPlaylistItem.seriesInfo` | 1 / `lib/features/pikpak_files/models/pikpak_playlist_item.dart` |  |  |  |
| `_PikPakPlaylistItem.displayName` | 1 / `lib/features/pikpak_files/models/pikpak_playlist_item.dart` |  |  |  |
| `_PikPakPlaylistItem._PikPakPlaylistItem` | 1 / `lib/features/pikpak_files/models/pikpak_playlist_item.dart` |  |  |  |
| `_PikPakSearchResult.file` | 1 / `lib/features/pikpak_files/models/pikpak_search_result.dart` |  |  |  |
| `_PikPakSearchResult.path` | 1 / `lib/features/pikpak_files/models/pikpak_search_result.dart` |  |  |  |
| `_PikPakSearchResult._PikPakSearchResult` | 1 / `lib/features/pikpak_files/models/pikpak_search_result.dart` |  |  |  |

## Per-entry wiring checklist

Review these bindings before pinning each production scaffold. Every callback retains the exact signature, defaults and named arguments of its original declaration. A same-section call keeps its receiver; an outside call is deferred through a live closure into the sole owner. State and widget getters are live, and context/mounted are fetched at the original evaluation site, with builder-local context unchanged. No borrowed resource is constructed or disposed by a section.

| Section | Dependency | Required binding / review |
| --- | --- | --- |
| `PikpakFocusActions` | `_addLinkButtonFocusNode` | one PikpakFocusState owner / _addLinkButtonFocusNode (deferred only until its planned move) |
| `PikpakFocusActions` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakFocusActions` | `_firstItemFocusNode` | one PikpakFocusState owner / _firstItemFocusNode (deferred only until its planned move) |
| `PikpakFocusActions` | `_isLoading` | one PikpakCatalogState owner / _isLoading (deferred only until its planned move) |
| `PikpakFocusActions` | `_shouldFocusOnLoad` | one PikpakFocusState owner / _shouldFocusOnLoad (deferred only until its planned move) |
| `PikpakFocusActions` | `mounted` | State live mounted callback |
| `PikpakBackNavigation` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakBackNavigation` | `_exitSelectionMode` | one PikpakSelectionActions owner / _exitSelectionMode (deferred only until its planned move) |
| `PikpakBackNavigation` | `_isInVirtualFolder` | one PikpakViewState owner / _isInVirtualFolder (deferred only until its planned move) |
| `PikpakBackNavigation` | `_isSearchActive` | one PikpakSearchState owner / _isSearchActive (deferred only until its planned move) |
| `PikpakBackNavigation` | `_isSelectionMode` | one PikpakSelectionState owner / _isSelectionMode (deferred only until its planned move) |
| `PikpakBackNavigation` | `_navigateUpWithVirtual` | one PikpakFolderNavigation owner / _navigateUpWithVirtual (deferred only until its planned move) |
| `PikpakBackNavigation` | `_navigationStack` | one PikpakNavigationState owner / _navigationStack (deferred only until its planned move) |
| `PikpakBackNavigation` | `_restrictedFolderId` | one PikpakNavigationState owner / _restrictedFolderId (deferred only until its planned move) |
| `PikpakBackNavigation` | `_toggleSearch` | one PikpakSearchActions owner / _toggleSearch (deferred only until its planned move) |
| `PikpakBackNavigation` | `context` | State live context callback |
| `PikpakBackNavigation` | `widget` | live widget getter(s): initialFolderId, initialFolderName, isPushedRoute, selectSourceMode, onSourceSelected |
| `PikpakCatalogLoading` | `_applyViewMode` | one PikpakViewModes owner / _applyViewMode (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_currentFolderName` | one PikpakNavigationState owner / _currentFolderName (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_errorMessage` | one PikpakCatalogState owner / _errorMessage (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_filterFiles` | one PikpakFolderNavigation owner / _filterFiles (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_focusFirstItemOrFallback` | one PikpakFocusActions owner / _focusFirstItemOrFallback (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_getCurrentViewMode` | one PikpakViewModes owner / _getCurrentViewMode (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_hasMore` | one PikpakCatalogState owner / _hasMore (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_ignoreSmallVideos` | one PikpakCatalogState owner / _ignoreSmallVideos (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_initialLoad` | one PikpakCatalogState owner / _initialLoad (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_isAtRestrictedRoot` | one PikpakNavigationState owner / _isAtRestrictedRoot (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_isLoading` | one PikpakCatalogState owner / _isLoading (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_isLoadingMore` | one PikpakCatalogState owner / _isLoadingMore (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_nextPageToken` | one PikpakCatalogState owner / _nextPageToken (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_pikpakEnabled` | one PikpakCatalogState owner / _pikpakEnabled (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_restrictedFolderId` | one PikpakNavigationState owner / _restrictedFolderId (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_restrictedFolderName` | one PikpakNavigationState owner / _restrictedFolderName (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_scrollController` | one PikpakFocusState owner / _scrollController (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakCatalogLoading` | `_showVideosOnly` | one PikpakCatalogState owner / _showVideosOnly (deferred only until its planned move) |
| `PikpakCatalogLoading` | `mounted` | State live mounted callback |
| `PikpakCatalogLoading` | `setState` | State live setState callback |
| `PikpakCatalogLoading` | `widget` | live widget getter(s): initialFolderId, initialFolderName, isPushedRoute, selectSourceMode, onSourceSelected |
| `PikpakDeleteActions` | `_exitSelectionMode` | one PikpakSelectionActions owner / _exitSelectionMode (deferred only until its planned move) |
| `PikpakDeleteActions` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakDeleteActions` | `_isSelectionMode` | one PikpakSelectionState owner / _isSelectionMode (deferred only until its planned move) |
| `PikpakDeleteActions` | `_selectedFileIds` | one PikpakSelectionState owner / _selectedFileIds (deferred only until its planned move) |
| `PikpakDeleteActions` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakDeleteActions` | `context` | State live context callback |
| `PikpakDeleteActions` | `mounted` | State live mounted callback |
| `PikpakDeleteActions` | `setState` | State live setState callback |
| `PikpakSelectionActions` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakSelectionActions` | `_isSelectionMode` | one PikpakSelectionState owner / _isSelectionMode (deferred only until its planned move) |
| `PikpakSelectionActions` | `_selectedFileIds` | one PikpakSelectionState owner / _selectedFileIds (deferred only until its planned move) |
| `PikpakSelectionActions` | `setState` | State live setState callback |
| `PikpakFeedback` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakFeedback` | `_exitSelectionMode` | one PikpakSelectionActions owner / _exitSelectionMode (deferred only until its planned move) |
| `PikpakFeedback` | `_isInVirtualFolder` | one PikpakViewState owner / _isInVirtualFolder (deferred only until its planned move) |
| `PikpakFeedback` | `_loadFiles` | one PikpakCatalogLoading owner / _loadFiles (deferred only until its planned move) |
| `PikpakFeedback` | `_recursiveFileCache` | one PikpakViewState owner / _recursiveFileCache (deferred only until its planned move) |
| `PikpakFeedback` | `_virtualFolderFiles` | one PikpakViewState owner / _virtualFolderFiles (deferred only until its planned move) |
| `PikpakFeedback` | `_virtualFolderName` | one PikpakViewState owner / _virtualFolderName (deferred only until its planned move) |
| `PikpakFeedback` | `context` | State live context callback |
| `PikpakFeedback` | `mounted` | State live mounted callback |
| `PikpakFeedback` | `setState` | State live setState callback |
| `PikpakFolderNavigation` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_currentFolderName` | one PikpakNavigationState owner / _currentFolderName (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_exitSelectionMode` | one PikpakSelectionActions owner / _exitSelectionMode (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_focusFirstItemOrFallback` | one PikpakFocusActions owner / _focusFirstItemOrFallback (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_getCurrentViewMode` | one PikpakViewModes owner / _getCurrentViewMode (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_ignoreSmallVideos` | one PikpakCatalogState owner / _ignoreSmallVideos (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_isAtRestrictedRoot` | one PikpakNavigationState owner / _isAtRestrictedRoot (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_isInVirtualFolder` | one PikpakViewState owner / _isInVirtualFolder (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_loadFiles` | one PikpakCatalogLoading owner / _loadFiles (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_navigationStack` | one PikpakNavigationState owner / _navigationStack (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_resetListScroll` | one PikpakCatalogLoading owner / _resetListScroll (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_restrictedFolderId` | one PikpakNavigationState owner / _restrictedFolderId (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_restrictedFolderName` | one PikpakNavigationState owner / _restrictedFolderName (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_setViewMode` | one PikpakViewModes owner / _setViewMode (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_shouldFocusOnLoad` | one PikpakFocusState owner / _shouldFocusOnLoad (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_showVideosOnly` | one PikpakCatalogState owner / _showVideosOnly (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_virtualFolderFiles` | one PikpakViewState owner / _virtualFolderFiles (deferred only until its planned move) |
| `PikpakFolderNavigation` | `_virtualFolderName` | one PikpakViewState owner / _virtualFolderName (deferred only until its planned move) |
| `PikpakFolderNavigation` | `setState` | State live setState callback |
| `PikpakViewModes` | `_applySortedView` | one  owner / _applySortedView (deferred only until its planned move) |
| `PikpakViewModes` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakViewModes` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakViewModes` | `_folderViewModes` | one PikpakViewState owner / _folderViewModes (deferred only until its planned move) |
| `PikpakViewModes` | `_hasMore` | one PikpakCatalogState owner / _hasMore (deferred only until its planned move) |
| `PikpakViewModes` | `_isInVirtualFolder` | one PikpakViewState owner / _isInVirtualFolder (deferred only until its planned move) |
| `PikpakViewModes` | `_isLoading` | one PikpakCatalogState owner / _isLoading (deferred only until its planned move) |
| `PikpakViewModes` | `_nextPageToken` | one PikpakCatalogState owner / _nextPageToken (deferred only until its planned move) |
| `PikpakViewModes` | `_recursiveFileCache` | one PikpakViewState owner / _recursiveFileCache (deferred only until its planned move) |
| `PikpakViewModes` | `context` | State live context callback |
| `PikpakViewModes` | `mounted` | State live mounted callback |
| `PikpakViewModes` | `setState` | State live setState callback |
| `PikpakSearchActions` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakSearchActions` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakSearchActions` | `_isSearchActive` | one PikpakSearchState owner / _isSearchActive (deferred only until its planned move) |
| `PikpakSearchActions` | `_recursiveFileCache` | one PikpakViewState owner / _recursiveFileCache (deferred only until its planned move) |
| `PikpakSearchActions` | `_searchController` | one PikpakSearchState owner / _searchController (deferred only until its planned move) |
| `PikpakSearchActions` | `_searchFocusNode` | one PikpakSearchState owner / _searchFocusNode (deferred only until its planned move) |
| `PikpakSearchActions` | `_searchResults` | one PikpakSearchState owner / _searchResults (deferred only until its planned move) |
| `PikpakSearchActions` | `setState` | State live setState callback |
| `PikpakSourceBinding` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakSourceBinding` | `context` | State live context callback |
| `PikpakSourceBinding` | `mounted` | State live mounted callback |
| `PikpakSourceBinding` | `widget` | live widget getter(s): initialFolderId, initialFolderName, isPushedRoute, selectSourceMode, onSourceSelected |
| `PikpakFilePlayback` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakFilePlayback` | `context` | State live context callback |
| `PikpakFilePlayback` | `mounted` | State live mounted callback |
| `PikpakFileDownload` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakFileDownload` | `context` | State live context callback |
| `PikpakFileDownload` | `mounted` | State live mounted callback |
| `PikpakFolderDownload` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakFolderDownload` | `context` | State live context callback |
| `PikpakFolderDownload` | `mounted` | State live mounted callback |
| `PikpakFolderPlayback` | `_combineSeriesAndEpisodeTitle` | one  owner / _combineSeriesAndEpisodeTitle (deferred only until its planned move) |
| `PikpakFolderPlayback` | `_findFirstEpisodeIndex` | one  owner / _findFirstEpisodeIndex (deferred only until its planned move) |
| `PikpakFolderPlayback` | `_formatPikPakPlaylistTitle` | one  owner / _formatPikPakPlaylistTitle (deferred only until its planned move) |
| `PikpakFolderPlayback` | `_ignoreSmallVideos` | one PikpakCatalogState owner / _ignoreSmallVideos (deferred only until its planned move) |
| `PikpakFolderPlayback` | `_pikpakDisplayName` | one  owner / _pikpakDisplayName (deferred only until its planned move) |
| `PikpakFolderPlayback` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakFolderPlayback` | `_showVideosOnly` | one PikpakCatalogState owner / _showVideosOnly (deferred only until its planned move) |
| `PikpakFolderPlayback` | `context` | State live context callback |
| `PikpakFolderPlayback` | `mounted` | State live mounted callback |
| `PikpakPlaylistActions` | `_ignoreSmallVideos` | one PikpakCatalogState owner / _ignoreSmallVideos (deferred only until its planned move) |
| `PikpakPlaylistActions` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakPlaylistActions` | `context` | State live context callback |
| `PikpakPlaylistActions` | `mounted` | State live mounted callback |
| `PikpakLinkActions` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakLinkActions` | `_isAddingLink` | one PikpakLinkState owner / _isAddingLink (deferred only until its planned move) |
| `PikpakLinkActions` | `_isValidPikPakLink` | one  owner / _isValidPikPakLink (deferred only until its planned move) |
| `PikpakLinkActions` | `_linkController` | one PikpakLinkState owner / _linkController (deferred only until its planned move) |
| `PikpakLinkActions` | `_refreshFiles` | one PikpakFeedback owner / _refreshFiles (deferred only until its planned move) |
| `PikpakLinkActions` | `_restrictedFolderId` | one PikpakNavigationState owner / _restrictedFolderId (deferred only until its planned move) |
| `PikpakLinkActions` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakLinkActions` | `context` | State live context callback |
| `PikpakLinkActions` | `mounted` | State live mounted callback |
| `PikpakLinkActions` | `setState` | State live setState callback |
| `PikpakRootLayout` | `_addLinkButtonFocusNode` | one PikpakFocusState owner / _addLinkButtonFocusNode (deferred only until its planned move) |
| `PikpakRootLayout` | `_backButtonFocusNode` | one PikpakFocusState owner / _backButtonFocusNode (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildEmpty` | one PikpakStatusLayout owner / _buildEmpty (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildError` | one PikpakStatusLayout owner / _buildError (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildFileList` | one PikpakFileList owner / _buildFileList (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildNotEnabled` | one PikpakStatusLayout owner / _buildNotEnabled (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildSearchBar` | one PikpakSearchLayout owner / _buildSearchBar (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildSearchResults` | one PikpakSearchLayout owner / _buildSearchResults (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildSelectionBar` | one PikpakToolbarLayout owner / _buildSelectionBar (deferred only until its planned move) |
| `PikpakRootLayout` | `_buildViewModeDropdown` | one PikpakToolbarLayout owner / _buildViewModeDropdown (deferred only until its planned move) |
| `PikpakRootLayout` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakRootLayout` | `_currentFolderName` | one PikpakNavigationState owner / _currentFolderName (deferred only until its planned move) |
| `PikpakRootLayout` | `_errorMessage` | one PikpakCatalogState owner / _errorMessage (deferred only until its planned move) |
| `PikpakRootLayout` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakRootLayout` | `_getCurrentViewMode` | one PikpakViewModes owner / _getCurrentViewMode (deferred only until its planned move) |
| `PikpakRootLayout` | `_handleBackNavigation` | one PikpakBackNavigation owner / _handleBackNavigation (deferred only until its planned move) |
| `PikpakRootLayout` | `_initialLoad` | one PikpakCatalogState owner / _initialLoad (deferred only until its planned move) |
| `PikpakRootLayout` | `_isAtRestrictedRoot` | one PikpakNavigationState owner / _isAtRestrictedRoot (deferred only until its planned move) |
| `PikpakRootLayout` | `_isInVirtualFolder` | one PikpakViewState owner / _isInVirtualFolder (deferred only until its planned move) |
| `PikpakRootLayout` | `_isLoading` | one PikpakCatalogState owner / _isLoading (deferred only until its planned move) |
| `PikpakRootLayout` | `_isSearchActive` | one PikpakSearchState owner / _isSearchActive (deferred only until its planned move) |
| `PikpakRootLayout` | `_isSelectionMode` | one PikpakSelectionState owner / _isSelectionMode (deferred only until its planned move) |
| `PikpakRootLayout` | `_navigationStack` | one PikpakNavigationState owner / _navigationStack (deferred only until its planned move) |
| `PikpakRootLayout` | `_pikpakEnabled` | one PikpakCatalogState owner / _pikpakEnabled (deferred only until its planned move) |
| `PikpakRootLayout` | `_refreshButtonFocusNode` | one PikpakFocusState owner / _refreshButtonFocusNode (deferred only until its planned move) |
| `PikpakRootLayout` | `_refreshFiles` | one PikpakFeedback owner / _refreshFiles (deferred only until its planned move) |
| `PikpakRootLayout` | `_restrictedFolderId` | one PikpakNavigationState owner / _restrictedFolderId (deferred only until its planned move) |
| `PikpakRootLayout` | `_searchButtonFocusNode` | one PikpakSearchState owner / _searchButtonFocusNode (deferred only until its planned move) |
| `PikpakRootLayout` | `_showAddLinkDialog` | one PikpakLinkActions owner / _showAddLinkDialog (deferred only until its planned move) |
| `PikpakRootLayout` | `_toggleSearch` | one PikpakSearchActions owner / _toggleSearch (deferred only until its planned move) |
| `PikpakRootLayout` | `_toggleSelectionMode` | one PikpakSelectionActions owner / _toggleSelectionMode (deferred only until its planned move) |
| `PikpakRootLayout` | `_virtualFolderName` | one PikpakViewState owner / _virtualFolderName (deferred only until its planned move) |
| `PikpakRootLayout` | `context` | State live context callback |
| `PikpakRootLayout` | `widget` | live widget getter(s): initialFolderId, initialFolderName, isPushedRoute, selectSourceMode, onSourceSelected |
| `PikpakStatusLayout` | `_currentFolderId` | one PikpakNavigationState owner / _currentFolderId (deferred only until its planned move) |
| `PikpakStatusLayout` | `_errorMessage` | one PikpakCatalogState owner / _errorMessage (deferred only until its planned move) |
| `PikpakStatusLayout` | `_refreshFiles` | one PikpakFeedback owner / _refreshFiles (deferred only until its planned move) |
| `PikpakStatusLayout` | `_retryButtonFocusNode` | one PikpakFocusState owner / _retryButtonFocusNode (deferred only until its planned move) |
| `PikpakStatusLayout` | `_settingsButtonFocusNode` | one PikpakFocusState owner / _settingsButtonFocusNode (deferred only until its planned move) |
| `PikpakStatusLayout` | `_showSnackBar` | one PikpakFeedback owner / _showSnackBar (deferred only until its planned move) |
| `PikpakStatusLayout` | `context` | State live context callback |
| `PikpakFileList` | `_downloadFile` | one PikpakFileDownload owner / _downloadFile (deferred only until its planned move) |
| `PikpakFileList` | `_downloadFolder` | one PikpakFolderDownload owner / _downloadFolder (deferred only until its planned move) |
| `PikpakFileList` | `_files` | one PikpakCatalogState owner / _files (deferred only until its planned move) |
| `PikpakFileList` | `_firstItemFocusNode` | one PikpakFocusState owner / _firstItemFocusNode (deferred only until its planned move) |
| `PikpakFileList` | `_handleAddToPlaylist` | one PikpakPlaylistActions owner / _handleAddToPlaylist (deferred only until its planned move) |
| `PikpakFileList` | `_hasMore` | one PikpakCatalogState owner / _hasMore (deferred only until its planned move) |
| `PikpakFileList` | `_isLoadingMore` | one PikpakCatalogState owner / _isLoadingMore (deferred only until its planned move) |
| `PikpakFileList` | `_isSelectionMode` | one PikpakSelectionState owner / _isSelectionMode (deferred only until its planned move) |
| `PikpakFileList` | `_navigateIntoFolder` | one PikpakFolderNavigation owner / _navigateIntoFolder (deferred only until its planned move) |
| `PikpakFileList` | `_navigateIntoVirtualFolder` | one PikpakFolderNavigation owner / _navigateIntoVirtualFolder (deferred only until its planned move) |
| `PikpakFileList` | `_playFile` | one PikpakFilePlayback owner / _playFile (deferred only until its planned move) |
| `PikpakFileList` | `_playFolder` | one PikpakFolderPlayback owner / _playFolder (deferred only until its planned move) |
| `PikpakFileList` | `_scrollController` | one PikpakFocusState owner / _scrollController (deferred only until its planned move) |
| `PikpakFileList` | `_selectBoundSource` | one PikpakSourceBinding owner / _selectBoundSource (deferred only until its planned move) |
| `PikpakFileList` | `_selectedFileIds` | one PikpakSelectionState owner / _selectedFileIds (deferred only until its planned move) |
| `PikpakFileList` | `_showDeleteDialog` | one PikpakDeleteActions owner / _showDeleteDialog (deferred only until its planned move) |
| `PikpakFileList` | `_toggleFileSelection` | one PikpakSelectionActions owner / _toggleFileSelection (deferred only until its planned move) |
| `PikpakFileList` | `widget` | live widget getter(s): initialFolderId, initialFolderName, isPushedRoute, selectSourceMode, onSourceSelected |
| `PikpakToolbarLayout` | `_backButtonFocusNode` | one PikpakFocusState owner / _backButtonFocusNode (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_deleteButtonFocusNode` | one PikpakFocusState owner / _deleteButtonFocusNode (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_getCurrentViewMode` | one PikpakViewModes owner / _getCurrentViewMode (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_handleDeleteSelected` | one PikpakDeleteActions owner / _handleDeleteSelected (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_isAllSelected` | one PikpakSelectionActions owner / _isAllSelected (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_selectedFileIds` | one PikpakSelectionState owner / _selectedFileIds (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_setViewMode` | one PikpakViewModes owner / _setViewMode (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_toggleSelectAll` | one PikpakSelectionActions owner / _toggleSelectAll (deferred only until its planned move) |
| `PikpakToolbarLayout` | `_viewModeDropdownFocusNode` | one PikpakFocusState owner / _viewModeDropdownFocusNode (deferred only until its planned move) |
| `PikpakToolbarLayout` | `context` | State live context callback |
| `PikpakSearchLayout` | `_performSearch` | one PikpakSearchActions owner / _performSearch (deferred only until its planned move) |
| `PikpakSearchLayout` | `_playFile` | one PikpakFilePlayback owner / _playFile (deferred only until its planned move) |
| `PikpakSearchLayout` | `_searchClearFocusNode` | one PikpakSearchState owner / _searchClearFocusNode (deferred only until its planned move) |
| `PikpakSearchLayout` | `_searchController` | one PikpakSearchState owner / _searchController (deferred only until its planned move) |
| `PikpakSearchLayout` | `_searchFocusNode` | one PikpakSearchState owner / _searchFocusNode (deferred only until its planned move) |
| `PikpakSearchLayout` | `_searchResults` | one PikpakSearchState owner / _searchResults (deferred only until its planned move) |
| `PikpakSearchLayout` | `_selectBoundSource` | one PikpakSourceBinding owner / _selectBoundSource (deferred only until its planned move) |
| `PikpakSearchLayout` | `context` | State live context callback |
| `PikpakSearchLayout` | `setState` | State live setState callback |
| `PikpakSearchLayout` | `widget` | live widget getter(s): initialFolderId, initialFolderName, isPushedRoute, selectSourceMode, onSourceSelected |

Special identity checklist: init add / reset remove / reset add use the same catalogLoading.onScroll receiver; route push / route pop / tab registration use the same backNavigation.handleBackNavigation receiver; TV tab 6 registers and removes the focus owner's stored closure. Full 14 individual disposals remain in the original order.

## Source readers and staged updates

- Theme cloud registry: add feature glob at step 1. Shape manifest: distribute exactly 9 bare radii and 5 token calls at each move; token-bearing destinations belong to kShapeResidue, others to kExtractedShapeResidue, including every owner/composition file. Facade leaves kShapeResidue when its tokens leave in step 6.
- Size ratchet: step 0 seam-only manual raise, then shrink-only checks each step. Final composition-root guard cap/TEMP rejection activates at step 7.
- Architecture: register PikPak, exact legacy_pikpak bridge, application service ban, facade back-import ban and bidirectional cross-cloud-feature bans at step 1.
- CI: concrete test paths and every pikpak support helper; facade included in format/analyze. _email original facade warning recorded now, relocated at step 3.
- Generic profile/theme/storage readers remain active; run affected source tests and storage/key checks. Optional light_ink_inventory is diagnostic only.
- Linux capture resolves step 0 by exact commit subject; non-strict Linux golden behavior lasts only through step 5. Verify original revision, hash manifest, capture/strict logs and run URL before separate artifacts commit.

## Pending physical verification

Android TV directional focus/repeat, all three native launcher handoffs and real-account operations. Enqueue success/mixed result messages depend on connectivity/native downloader initialization; no isolated successful enqueue fixture is proven, so these remain pending and both complete original enqueue bodies are source-guarded.


## Original integration dependencies

The legacy bridge keeps direct calls to PikpakStorage (profile preferences and credentials), PikPakApiService (metadata/list/recursive/detail/offline/batch/logout), PlaylistStorage (persisted raw maps), DownloadService (sequential enqueue), VideoPlayerLauncher (three static handoffs), MainPageBridge (back/focus/tab), Clipboard, and Navigator/ScaffoldMessenger. Shared FileUtils, Formatters, SeriesParser and theme/cloud widgets keep their existing contracts. None is moved or upgraded. The application helpers import only their existing pure utilities; there is no cross-cloud feature import.

## Wiring review evidence

- Step 2: reviewed all seven state/resource owners and their facade/accessor receivers before pinning seven owner handles; declaration initializers, identities and lifecycle order are preserved.
- Step 3: reviewed all data-composition entries against the checklist above before pinning 33 scaffolds. Owners are the originating State instances, live callbacks resolve State/context/widget at use, deferred navigation callbacks invoke the real facade, and cross-section callbacks resolve the one fully wired composition. No constructor starts work; nullable slots are assigned before exposure, with no late fields.
- Step 4: reviewed every navigation/view/search/source-binding composition entry before pinning 45 current scaffolds. Deferred calls are removed; callbacks reach their single production section, live widget getters stay live, and Raw/cast collections are passed unchanged. Original source-reader assertions also replay successfully after whitespace/getter normalization.
- Step 5: reviewed all six playback/download/playlist/link composition entries before pinning 64 current scaffolds. Defaults and live contexts are preserved, feedback/refresh resolve their sole section, catalog/navigation/link state use the original owners, and launcher/enqueue/persistence payloads remain fully source-guarded. All 83 frozen characterizations still pass.
