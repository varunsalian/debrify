# IPTV settings dependency and wiring report

Original: `4f3ee3b3`. The manifest owns every original declaration. The oversized facade temporarily retains the original workflows and a frozen test accessor; Steps 2–6 remove these responsibilities and Step 7 enforces 400 lines. No source service, schema, profile semantics or widget constructor is redesigned.

State remains the observer and ticker provider. It owns the one two-pane key. All field initializers, collections and resource identities are retained at their declaration on the planned owner. Sections borrow them; facade lifecycle performs the original ordered cleanup. State/context/mounted, openAddSource and appearance are live reads at the original sites.

## Declaration inventory

| Declaration | Step / destination | Reads | Writes | Calls / tear-offs |
| --- | --- | --- | --- | --- |
| `_PhoneSection` | 1 / `lib/features/iptv_settings/models/iptv_settings_phone_section.dart` |  |  |  |
| `IptvSettingsPage` | 0 / `lib/screens/settings/iptv_settings_page.dart` |  |  | _IptvSettingsPageState |
| `_IptvSettingsPageState._nameController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._urlController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._epgUrlController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._backButtonFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._nameInputFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._urlInputFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._epgUrlInputFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._addButtonFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._importFileButtonFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcNameController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcServerController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcUsernameController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcPasswordController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcNameFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcServerFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcUsernameFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcPasswordFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcLoginButtonFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._isXcAdding` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._urlTabFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._fileTabFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._xcTabFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._tabController` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._playlistFocusNodes` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._listFocusNodes` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` | _playlistFocusNodes |  |  |
| `_IptvSettingsPageState._createListFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._hiddenFocusNodes` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` | _listFocusNodes |  |  |
| `_IptvSettingsPageState._hiddenCounts` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart` |  |  |  |
| `_IptvSettingsPageState._lists` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart` |  |  |  |
| `_IptvSettingsPageState._playlists` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart` |  |  |  |
| `_IptvSettingsPageState._defaultPlaylistId` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart` |  |  |  |
| `_IptvSettingsPageState._twoPaneActive` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart` |  |  |  |
| `_IptvSettingsPageState._twoPaneKey` | 0 / `lib/screens/settings/iptv_settings_page.dart` |  |  |  |
| `_IptvSettingsPageState._recordingSectionVisible` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart` |  |  |  |
| `_IptvSettingsPageState._engineToggleVisible` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart` |  |  |  |
| `_IptvSettingsPageState._recordingEngineOn` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart` |  |  |  |
| `_IptvSettingsPageState._scheduledCount` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart` |  |  |  |
| `_IptvSettingsPageState._maxConcurrent` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart` |  |  |  |
| `_IptvSettingsPageState._batteryExempt` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart` |  |  |  |
| `_IptvSettingsPageState._scheduledRecordingsFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._maxConcurrentFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._batteryFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._startupEnabled` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._startupMode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._startupChannel` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._lastLiveChannel` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._startupChannelFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._trackContinueWatching` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._channelPreviewEnabled` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._autoRefreshHours` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._pickAutoRefresh` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | _autoRefreshHours, context, mounted | _autoRefreshHours | _runProfileAction, setState |
| `_IptvSettingsPageState._runProfileAction` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_profile_actions.dart` | mounted |  |  |
| `_IptvSettingsPageState._iptvStyle` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._playerGuideStyle` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart` |  |  |  |
| `_IptvSettingsPageState._isDesktopPlatform` | 0 / `lib/screens/settings/iptv_settings_page.dart` |  |  |  |
| `_IptvSettingsPageState._appearanceVisible` | 0 / `lib/screens/settings/iptv_settings_page.dart` | _isDesktopPlatform |  |  |
| `_IptvSettingsPageState._loading` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart` |  |  |  |
| `_IptvSettingsPageState._isAdding` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart` |  |  |  |
| `_IptvSettingsPageState._refreshingIds` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart` |  |  |  |
| `_IptvSettingsPageState._phoneSection` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart` | _PhoneSection |  |  |
| `_IptvSettingsPageState._hubSourcesFocusNode` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._phoneViewMarker` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart` |  |  |  |
| `_IptvSettingsPageState._enterPhoneSection` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_actions.dart` | _phoneViewMarker, _twoPaneActive, mounted | _phoneSection | setState |
| `_IptvSettingsPageState.initState` | 0 / `lib/screens/settings/iptv_settings_page.dart` | _PhoneSection, _onTabChanged, _tabController, widget | _phoneSection, _tabController | _loadSettings |
| `_IptvSettingsPageState._onTabChanged` | 0 / `lib/screens/settings/iptv_settings_page.dart` | mounted |  | setState |
| `_IptvSettingsPageState._focusContentAfterTabSwitch` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_actions.dart` | mounted |  | _focusAndReveal |
| `_IptvSettingsPageState._focusAndReveal` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_actions.dart` | context |  |  |
| `_IptvSettingsPageState.dispose` | 0 / `lib/screens/settings/iptv_settings_page.dart` | _addButtonFocusNode, _backButtonFocusNode, _batteryFocusNode, _createListFocusNode, _epgUrlController, _epgUrlInputFocusNode, _fileTabFocusNode, _hiddenFocusNodes, _hubSourcesFocusNode, _importFileButtonFocusNode, _listFocusNodes, _maxConcurrentFocusNode, _nameController, _nameInputFocusNode, _onTabChanged, _phoneViewMarker, _playlistFocusNodes, _scheduledRecordingsFocusNode, _startupChannelFocusNode, _tabController, _urlController, _urlInputFocusNode, _urlTabFocusNode, _xcLoginButtonFocusNode, _xcNameController, _xcNameFocusNode, _xcPasswordController, _xcPasswordFocusNode, _xcServerController, _xcServerFocusNode, _xcTabFocusNode, _xcUsernameController, _xcUsernameFocusNode |  |  |
| `_IptvSettingsPageState._ensureFocusNodes` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_actions.dart` | _customLists, _hiddenFocusNodes, _hideableSources, _listFocusNodes, _playlistFocusNodes, _playlists |  |  |
| `_IptvSettingsPageState._hideableSources` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` | _playlists |  |  |
| `_IptvSettingsPageState._categoryOrderSources` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` | _playlists |  |  |
| `_IptvSettingsPageState._catalogKeysFor` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` |  |  |  |
| `_IptvSettingsPageState._catalogOwnerReferencesFor` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` |  |  |  |
| `_IptvSettingsPageState._openHiddenCategories` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` | _reloadHiddenCounts, context, mounted |  | setState |
| `_IptvSettingsPageState._openCategoryOrder` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` | context, mounted |  | _showSnackBar |
| `_IptvSettingsPageState._openChannelOrder` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` | context |  |  |
| `_IptvSettingsPageState._reloadHiddenCounts` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_catalog_actions.dart` | _hideableSources | _hiddenCounts, total | _catalogKeysFor |
| `_IptvSettingsPageState._customLists` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _lists |  |  |
| `_IptvSettingsPageState._startupChannelLabel` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | _startupChannel |  |  |
| `_IptvSettingsPageState._lastLiveChannelLabel` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | _lastLiveChannel |  |  |
| `_IptvSettingsPageState._setStartupMode` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` |  |  | _runProfileAction, _setStartupModeForProfile |
| `_IptvSettingsPageState._setStartupModeForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | _startupChannel, mounted | _startupMode | _pickStartupChannel, setState |
| `_IptvSettingsPageState._setStartupEnabled` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | mounted | _startupEnabled | _runProfileAction, setState |
| `_IptvSettingsPageState._setTrackContinueWatching` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` |  |  | _runProfileAction, _setTrackContinueWatchingForProfile |
| `_IptvSettingsPageState._setTrackContinueWatchingForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | mounted | _trackContinueWatching | setState |
| `_IptvSettingsPageState._setChannelPreviewEnabled` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` |  |  | _runProfileAction, _setChannelPreviewEnabledForProfile |
| `_IptvSettingsPageState._setChannelPreviewEnabledForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | mounted | _channelPreviewEnabled | setState |
| `_IptvSettingsPageState._setIptvStyle` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` |  |  | _runProfileAction, _setIptvStyleForProfile |
| `_IptvSettingsPageState._setIptvStyleForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | mounted | _iptvStyle | setState |
| `_IptvSettingsPageState._setPlayerGuideStyle` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` |  |  | _runProfileAction, _setPlayerGuideStyleForProfile |
| `_IptvSettingsPageState._setPlayerGuideStyleForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | mounted | _playerGuideStyle | setState |
| `_IptvSettingsPageState._pickStartupChannel` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | _pickStartupChannelForProfile |  | _runProfileAction |
| `_IptvSettingsPageState._pickStartupChannelForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | context, mounted | _startupChannel | setState |
| `_IptvSettingsPageState._loadSettings` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_load_settings.dart` | _PhoneSection, _hubSourcesFocusNode, _phoneSection, _twoPaneKey, _urlTabFocusNode, mounted, widget | _autoRefreshHours, _batteryExempt, _channelPreviewEnabled, _defaultPlaylistId, _engineToggleVisible, _iptvStyle, _lastLiveChannel, _lists, _loading, _maxConcurrent, _playerGuideStyle, _playlists, _recordingEngineOn, _recordingSectionVisible, _scheduledCount, _startupChannel, _startupEnabled, _startupMode, _trackContinueWatching | _ensureFocusNodes, _reloadHiddenCounts, setState |
| `_IptvSettingsPageState._addPlaylist` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_url_add.dart` | _addPlaylistForProfile |  | _runProfileAction |
| `_IptvSettingsPageState._addPlaylistForProfile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_url_add.dart` | _epgUrlController, _isAdding, _nameController, _playlists, _urlController, mounted | _isAdding, _playlists | _ensureFocusNodes, _showSnackBar, setState |
| `_IptvSettingsPageState._importFromFile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_file_import.dart` | _importFromFileForProfile |  | _runProfileAction |
| `_IptvSettingsPageState._importFromFileForProfile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_file_import.dart` | _playlists, context, mounted | _playlists, defaultName | _PlaylistNameDialog, _ensureFocusNodes, _showSnackBar, setState |
| `_IptvSettingsPageState._normalizeXtreamServerUrl` | 1 / `lib/features/iptv_settings/application/normalize_xtream_server_url.dart` |  | serverUrl |  |
| `_IptvSettingsPageState._addXtreamCodes` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_xtream_add.dart` | _addXtreamCodesForProfile |  | _runProfileAction |
| `_IptvSettingsPageState._addXtreamCodesForProfile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_xtream_add.dart` | _isXcAdding, _playlists, _xcNameController, _xcPasswordController, _xcServerController, _xcUsernameController, mounted | _isXcAdding, _playlists, statusMsg | _ensureFocusNodes, _normalizeXtreamServerUrl, _showSnackBar, setState |
| `_IptvSettingsPageState._removePlaylist` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_removal.dart` | mounted |  | _removePlaylistForProfile, _showSnackBar |
| `_IptvSettingsPageState._removePlaylistForProfile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_removal.dart` | _defaultPlaylistId, _fileTabFocusNode, _playlistFocusNodes, _playlists, _tabController, _urlTabFocusNode, _xcTabFocusNode, context, mounted | _defaultPlaylistId, _playlists, actor, authorization, revokeBorrowers | _catalogKeysFor, _catalogOwnerReferencesFor, _ensureFocusNodes, _focusAndReveal, _showSnackBar, setState |
| `_IptvSettingsPageState._setDefaultPlaylist` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_refresh.dart` |  |  | _runProfileAction, _setDefaultPlaylistForProfile |
| `_IptvSettingsPageState._setDefaultPlaylistForProfile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_refresh.dart` | mounted | _defaultPlaylistId | _showSnackBar, setState |
| `_IptvSettingsPageState._refreshPlaylist` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_refresh.dart` |  |  | _refreshPlaylistForProfile, _runProfileAction |
| `_IptvSettingsPageState._refreshPlaylistForProfile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_refresh.dart` | _refreshingIds, mounted | result | _showSnackBar, setState |
| `_IptvSettingsPageState._showSnackBar` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_feedback.dart` | context, mounted |  |  |
| `_IptvSettingsPageState._reloadLists` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | mounted | _lists | _ensureFocusNodes, setState |
| `_IptvSettingsPageState._createList` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _createListForProfile |  | _runProfileAction |
| `_IptvSettingsPageState._createListForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _lists, context, mounted |  | _reloadLists, _showSnackBar |
| `_IptvSettingsPageState._renameList` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` |  |  | _renameListForProfile, _runProfileAction |
| `_IptvSettingsPageState._renameListForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _lists, context, mounted |  | _reloadLists |
| `_IptvSettingsPageState._deleteList` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` |  |  | _deleteListForProfile, _runProfileAction |
| `_IptvSettingsPageState._deleteListForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _createListFocusNode, _listFocusNodes, context, mounted |  | _focusAndReveal, _reloadLists, _showSnackBar |
| `_IptvSettingsPageState._moveList` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` |  |  | _moveListForProfile, _runProfileAction |
| `_IptvSettingsPageState._moveListForProfile` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _customLists |  | _reloadLists |
| `_IptvSettingsPageState._showListActions` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _customLists, context, mounted |  | _deleteList, _moveList, _renameList |
| `_IptvSettingsPageState._buildHiddenCategoriesSection` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_category_views.dart` | _hiddenCounts, _hiddenFocusNodes, _hideableSources, context | i | _openHiddenCategories |
| `_IptvSettingsPageState._buildListsSection` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_list_views.dart` | _customLists, context | i | _IptvListSettingsRow, _deleteList, _listNodeAt, _moveList, _renameList |
| `_IptvSettingsPageState._listNodeAt` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_lists_actions.dart` | _listFocusNodes |  |  |
| `_IptvSettingsPageState._buildPlaylistsList` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_views.dart` | _defaultPlaylistId, _playlistFocusNodes, _playlists, _refreshingIds | i | _FocusablePlaylistTile, _editPlaylist, _refreshPlaylist, _removePlaylist, _setDefaultPlaylist |
| `_IptvSettingsPageState._editPlaylist` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_edit.dart` |  |  | _editPlaylistForProfile, _runProfileAction |
| `_IptvSettingsPageState._editPlaylistForProfile` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_edit.dart` | _playlists, context, mounted | _playlists, newServerUrl | _EditPlaylistDialog, _catalogKeysFor, _catalogOwnerReferencesFor, _normalizeXtreamServerUrl, _showSnackBar, setState |
| `_IptvSettingsPageState._buildUrlTabContent` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_forms.dart` | _addButtonFocusNode, _addPlaylist, _epgUrlController, _epgUrlInputFocusNode, _isAdding, _nameController, _nameInputFocusNode, _playlistFocusNodes, _playlists, _twoPaneActive, _urlController, _urlInputFocusNode, _urlTabFocusNode |  | _TvFocusableButton, _addPlaylist, _focusAndReveal |
| `_IptvSettingsPageState._buildFileTabContent` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_forms.dart` | _fileTabFocusNode, _importFileButtonFocusNode, _importFromFile, _playlistFocusNodes, _playlists, _twoPaneActive, context |  | _TvFocusableButton, _focusAndReveal |
| `_IptvSettingsPageState._buildXcTabContent` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_forms.dart` | _addXtreamCodes, _isXcAdding, _playlistFocusNodes, _playlists, _twoPaneActive, _xcLoginButtonFocusNode, _xcNameController, _xcNameFocusNode, _xcPasswordController, _xcPasswordFocusNode, _xcServerController, _xcServerFocusNode, _xcTabFocusNode, _xcUsernameController, _xcUsernameFocusNode |  | _TvFocusableButton, _addXtreamCodes, _focusAndReveal |
| `_IptvSettingsPageState.build` | 6 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_root_layout.dart` | _PhoneSection, _backButtonFocusNode, _fileTabFocusNode, _loading, _phoneSection, _phoneViewMarker, _tabController, _twoPaneActive, _twoPaneKey, _urlTabFocusNode, _xcTabFocusNode, mounted | _phoneSection, _twoPaneActive | _TvFocusableBackButton, _buildSingleColumn, _buildTwoPane, _enterPhoneSection, _focusAndReveal, setState |
| `_IptvSettingsPageState._buildTwoPane` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_two_pane.dart` | _appearanceVisible, _autoRefreshHours, _batteryExempt, _channelPreviewEnabled, _createList, _customLists, _defaultPlaylistId, _editPlaylist, _engineToggleVisible, _fileTabFocusNode, _hiddenCounts, _importFileButtonFocusNode, _iptvStyle, _lastLiveChannel, _lastLiveChannelLabel, _maxConcurrent, _nameInputFocusNode, _pickAutoRefresh, _pickStartupChannel, _playerGuideStyle, _playlists, _recordingEngineOn, _recordingSectionVisible, _refreshPlaylist, _refreshingIds, _removePlaylist, _scheduledCount, _setChannelPreviewEnabled, _setStartupEnabled, _setStartupMode, _setTrackContinueWatching, _showListActions, _startupChannel, _startupChannelLabel, _startupEnabled, _startupMode, _tabController, _trackContinueWatching, _twoPaneKey, _urlTabFocusNode, _xcNameFocusNode, _xcTabFocusNode, mounted, widget | _recordingEngineOn | _buildFileTabContent, _buildUrlTabContent, _buildXcTabContent, _focusAndReveal, _openCategoryOrder, _openChannelOrder, _openHiddenCategories, _openScheduledRecordings, _pickMaxConcurrent, _requestBatteryExemption, _setDefaultPlaylist, _setIptvStyle, _setPlayerGuideStyle, setState |
| `_IptvSettingsPageState._buildSingleColumn` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_actions.dart` | _PhoneSection, _phoneSection, _phoneViewMarker |  | _buildCategoryOrderView, _buildChannelPreviewView, _buildContinueWatchingView, _buildHiddenView, _buildListsView, _buildPhoneHub, _buildRecordingView, _buildSourcesView, _buildStartupView |
| `_IptvSettingsPageState._buildPhoneHub` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_phone_hub.dart` | _PhoneSection, _appearanceVisible, _autoRefreshHours, _categoryOrderSources, _channelPreviewEnabled, _customLists, _defaultPlaylistId, _engineToggleVisible, _hiddenCounts, _hideableSources, _hubSourcesFocusNode, _iptvStyle, _openChannelOrder, _pickAutoRefresh, _playerGuideStyle, _playlists, _recordingEngineOn, _recordingSectionVisible, _scheduledCount, _startupChannelLabel, _startupEnabled, _startupMode, _trackContinueWatching |  | _enterPhoneSection, _openIptvStylePicker, _openPlayerGuidePicker |
| `_IptvSettingsPageState._openIptvStylePicker` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | context, mounted | _iptvStyle | setState |
| `_IptvSettingsPageState._openPlayerGuidePicker` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_actions.dart` | context, mounted | _playerGuideStyle | setState |
| `_IptvSettingsPageState._buildSourcesView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_source_views.dart` | _backButtonFocusNode, _defaultPlaylistId, _fileTabFocusNode, _importFileButtonFocusNode, _nameInputFocusNode, _playlists, _tabController, _urlTabFocusNode, _xcNameFocusNode, _xcTabFocusNode, context |  | _TvFocusableTabBar, _buildFileTabContent, _buildPlaylistsList, _buildUrlTabContent, _buildXcTabContent, _focusContentAfterTabSwitch |
| `_IptvSettingsPageState._buildListsView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_list_views.dart` | _createList, _createListFocusNode, context |  | _FocusableSettingsTile, _buildListsSection |
| `_IptvSettingsPageState._buildCategoryOrderView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_category_views.dart` | _categoryOrderSources, context |  | _openCategoryOrder |
| `_IptvSettingsPageState._buildHiddenView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_category_views.dart` | context |  | _buildHiddenCategoriesSection |
| `_IptvSettingsPageState._buildStartupView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_views.dart` | _lastLiveChannel, _lastLiveChannelLabel, _pickStartupChannel, _setStartupEnabled, _setStartupMode, _startupChannel, _startupChannelFocusNode, _startupChannelLabel, _startupEnabled, _startupMode |  | _FocusableSettingsTile |
| `_IptvSettingsPageState._buildContinueWatchingView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_views.dart` | _setTrackContinueWatching, _trackContinueWatching |  |  |
| `_IptvSettingsPageState._buildChannelPreviewView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_views.dart` | _channelPreviewEnabled, _setChannelPreviewEnabled |  |  |
| `_IptvSettingsPageState._buildRecordingView` | 5 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_view.dart` | _batteryExempt, _batteryFocusNode, _engineToggleVisible, _maxConcurrent, _maxConcurrentFocusNode, _openScheduledRecordings, _pickMaxConcurrent, _recordingEngineOn, _requestBatteryExemption, _scheduledCount, _scheduledRecordingsFocusNode, mounted | _recordingEngineOn | _FocusableSettingsTile, setState |
| `_IptvSettingsPageState._recheckBatteryOnResume` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart` |  |  |  |
| `_IptvSettingsPageState.didChangeAppLifecycleState` | 0 / `lib/screens/settings/iptv_settings_page.dart` | _recheckBatteryOnResume, mounted | _batteryExempt, _recheckBatteryOnResume | setState |
| `_IptvSettingsPageState._requestBatteryExemption` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_actions.dart` |  | _recheckBatteryOnResume |  |
| `_IptvSettingsPageState._pickMaxConcurrent` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_actions.dart` | context, mounted | _maxConcurrent | setState |
| `_IptvSettingsPageState._openScheduledRecordings` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_actions.dart` | context, mounted | _scheduledCount | setState |
| `_TvFocusableButton` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_tv_button.dart` | _TvFocusableButton |  | _TvFocusableButtonState |
| `_TvFocusableButtonState` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_tv_button.dart` | _isFocused, _onFocusChange, context, mounted, widget |  | setState |
| `_TvFocusableTabBar` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_tv_tab_bar.dart` | _TvFocusableTabBar |  | _TvFocusableTabBarState |
| `_TvFocusableTabBarState` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_tv_tab_bar.dart` | _fileTabFocused, _onFileTabFocusChange, _onUrlTabFocusChange, _onXcTabFocusChange, _urlTabFocused, _xcTabFocused, context, mounted, widget | _fileTabFocused, _urlTabFocused, _xcTabFocused | setState |
| `_FocusablePlaylistTile` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_playlist_tile.dart` | _FocusablePlaylistTile |  | _FocusablePlaylistTileState |
| `_FocusablePlaylistTileState` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_playlist_tile.dart` | _deleteFocused, _editFocused, _onDeleteFocusChange, _onEditFocusChange, _onRefreshFocusChange, _onStarFocusChange, _refreshFocused, _starFocused, context, mounted, widget | _deleteFocused, _editFocused, _refreshFocused, _starFocused | _FocusableIconButton, _ensureVisible, setState |
| `_PlaylistEdit` | 1 / `lib/features/iptv_settings/models/iptv_settings_playlist_edit.dart` | _EditPlaylistDialog, _PlaylistEdit |  |  |
| `IptvSharedSourceDeleteDialog` | 2 / `lib/features/iptv_settings/presentation/iptv_shared_source_delete_dialog.dart` |  |  | _SharedIptvSourceDeleteDialogState |
| `_SharedIptvSourceDeleteDialogState` | 2 / `lib/features/iptv_settings/presentation/iptv_shared_source_delete_dialog.dart` | _cancelFocusNode, _dialogButtonFocusStyle, _okFocusNode, _onKeyEvent, context, widget |  |  |
| `_EditPlaylistDialog` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_edit_dialog.dart` | _EditPlaylistDialog |  | _EditPlaylistDialogState |
| `_EditPlaylistDialogState` | 3 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_edit_dialog.dart` | _canSave, _dialogButtonFocusStyle, _epgController, _epgFocusNode, _isUrl, _isXtream, _nameController, _nameError, _nameFocusNode, _passwordController, _passwordError, _passwordFocusNode, _revalidate, _serverController, _serverError, _serverFocusNode, _submit, _urlController, _urlError, _urlFocusNode, _usernameController, _usernameError, _usernameFocusNode, context, widget | _epgController, _nameController, _passwordController, _serverController, _urlController, _usernameController | _PlaylistEdit, _submit, setState |
| `_FocusableIconButton` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_icon_button.dart` | _FocusableIconButton |  | _FocusableIconButtonState |
| `_FocusableIconButtonState` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_icon_button.dart` | _isFocused, _onFocusChange, context, mounted, widget |  | setState |
| `_TvFocusableBackButton` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_back_button.dart` | _TvFocusableBackButton |  | _TvFocusableBackButtonState |
| `_TvFocusableBackButtonState` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_back_button.dart` | _goBack, _isFocused, _onFocusChange, context, mounted, widget |  | _goBack, setState |
| `_PlaylistNameDialog` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_playlist_name_dialog.dart` | _PlaylistNameDialog |  | _PlaylistNameDialogState |
| `_PlaylistNameDialogState` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_playlist_name_dialog.dart` | _controller, _dialogButtonFocusStyle, _errorText, _fieldFocusNode, _initialNameValid, _submit, _validateName, context, widget | _controller, _errorText, _initialNameValid | _errorFor, _submit, _validateName, setState |
| `_dialogButtonFocusStyle` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_dialog_button_style.dart` |  |  |  |
| `_IptvListSettingsRow` | 4 / `lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_list_row.dart` | _IptvListSettingsRow, context |  | _FocusableIconButton |
| `_FocusableSettingsTile` | 2 / `lib/features/iptv_settings/presentation/iptv_settings_focusable_tile.dart` | _FocusableSettingsTile, context |  |  |

## Per-entry wiring checklist

Review every entry against actual composition before pinning scaffold tokens. Defaults, named arguments, async return types and direct callback identity are preserved; no callback runs during construction. The review status starts pending until the corresponding production entry exists.

| Section | Dependency | Required binding | Review |
| --- | --- | --- | --- |
| `IptvSettingsProfileActions` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsFeedback` | `context` | `State live context getter` | Pending step 3 |
| `IptvSettingsFeedback` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsFocusActions` | `_customLists` | `IptvSettingsListsActions.customLists` | Pending step 3 |
| `IptvSettingsFocusActions` | `_hiddenFocusNodes` | `IptvSettingsFocusOwner.hiddenFocusNodes` | Pending step 3 |
| `IptvSettingsFocusActions` | `_hideableSources` | `IptvSettingsCatalogActions.hideableSources` | Pending step 3 |
| `IptvSettingsFocusActions` | `_listFocusNodes` | `IptvSettingsFocusOwner.listFocusNodes` | Pending step 3 |
| `IptvSettingsFocusActions` | `_playlistFocusNodes` | `IptvSettingsFocusOwner.playlistFocusNodes` | Pending step 3 |
| `IptvSettingsFocusActions` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 3 |
| `IptvSettingsFocusActions` | `context` | `State live context getter` | Pending step 3 |
| `IptvSettingsFocusActions` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsCatalogActions` | `_hiddenCounts` | `IptvSettingsSourcesOwner.hiddenCounts` | Pending step 4 |
| `IptvSettingsCatalogActions` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 4 |
| `IptvSettingsCatalogActions` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 4 |
| `IptvSettingsCatalogActions` | `context` | `State live context getter` | Pending step 4 |
| `IptvSettingsCatalogActions` | `mounted` | `State live mounted getter` | Pending step 4 |
| `IptvSettingsCatalogActions` | `setState` | `State setState tear-off` | Pending step 4 |
| `IptvSettingsLoadSettings` | `_autoRefreshHours` | `IptvSettingsPreferencesOwner.autoRefreshHours` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_batteryExempt` | `IptvSettingsRecordingOwner.batteryExempt` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_channelPreviewEnabled` | `IptvSettingsPreferencesOwner.channelPreviewEnabled` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_defaultPlaylistId` | `IptvSettingsSourcesOwner.defaultPlaylistId` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_engineToggleVisible` | `IptvSettingsRecordingOwner.engineToggleVisible` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_ensureFocusNodes` | `IptvSettingsFocusActions.ensureFocusNodes` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_hubSourcesFocusNode` | `IptvSettingsFocusOwner.hubSourcesFocusNode` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_iptvStyle` | `IptvSettingsPreferencesOwner.iptvStyle` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_lastLiveChannel` | `IptvSettingsPreferencesOwner.lastLiveChannel` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_lists` | `IptvSettingsSourcesOwner.lists` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_loading` | `IptvSettingsSourcesOwner.loading` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_maxConcurrent` | `IptvSettingsRecordingOwner.maxConcurrent` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_phoneSection` | `IptvSettingsLayoutOwner.phoneSection` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_playerGuideStyle` | `IptvSettingsPreferencesOwner.playerGuideStyle` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_recordingEngineOn` | `IptvSettingsRecordingOwner.recordingEngineOn` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_recordingSectionVisible` | `IptvSettingsRecordingOwner.recordingSectionVisible` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_reloadHiddenCounts` | `IptvSettingsCatalogActions.reloadHiddenCounts` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_scheduledCount` | `IptvSettingsRecordingOwner.scheduledCount` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_startupChannel` | `IptvSettingsPreferencesOwner.startupChannel` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_startupEnabled` | `IptvSettingsPreferencesOwner.startupEnabled` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_startupMode` | `IptvSettingsPreferencesOwner.startupMode` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_trackContinueWatching` | `IptvSettingsPreferencesOwner.trackContinueWatching` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_twoPaneKey` | `_IptvSettingsPageState._twoPaneKey` | Pending step 3 |
| `IptvSettingsLoadSettings` | `_urlTabFocusNode` | `IptvSettingsFocusOwner.urlTabFocusNode` | Pending step 3 |
| `IptvSettingsLoadSettings` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsLoadSettings` | `setState` | `State setState tear-off` | Pending step 3 |
| `IptvSettingsLoadSettings` | `widget` | `live openAddSource getter only` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_ensureFocusNodes` | `IptvSettingsFocusActions.ensureFocusNodes` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_epgUrlController` | `IptvSettingsInputOwner.epgUrlController` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_isAdding` | `IptvSettingsInputOwner.isAdding` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_nameController` | `IptvSettingsInputOwner.nameController` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_runProfileAction` | `IptvSettingsProfileActions.runProfileAction` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 3 |
| `IptvSettingsUrlAdd` | `_urlController` | `IptvSettingsInputOwner.urlController` | Pending step 3 |
| `IptvSettingsUrlAdd` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsUrlAdd` | `setState` | `State setState tear-off` | Pending step 3 |
| `IptvSettingsFileImport` | `_ensureFocusNodes` | `IptvSettingsFocusActions.ensureFocusNodes` | Pending step 3 |
| `IptvSettingsFileImport` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 3 |
| `IptvSettingsFileImport` | `_runProfileAction` | `IptvSettingsProfileActions.runProfileAction` | Pending step 3 |
| `IptvSettingsFileImport` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 3 |
| `IptvSettingsFileImport` | `context` | `State live context getter` | Pending step 3 |
| `IptvSettingsFileImport` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsFileImport` | `setState` | `State setState tear-off` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_ensureFocusNodes` | `IptvSettingsFocusActions.ensureFocusNodes` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_isXcAdding` | `IptvSettingsInputOwner.isXcAdding` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_normalizeXtreamServerUrl` | `.normalizeXtreamServerUrl` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_runProfileAction` | `IptvSettingsProfileActions.runProfileAction` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_xcNameController` | `IptvSettingsInputOwner.xcNameController` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_xcPasswordController` | `IptvSettingsInputOwner.xcPasswordController` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_xcServerController` | `IptvSettingsInputOwner.xcServerController` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `_xcUsernameController` | `IptvSettingsInputOwner.xcUsernameController` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsXtreamAdd` | `setState` | `State setState tear-off` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_catalogKeysFor` | `IptvSettingsCatalogActions.catalogKeysFor` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_catalogOwnerReferencesFor` | `IptvSettingsCatalogActions.catalogOwnerReferencesFor` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_defaultPlaylistId` | `IptvSettingsSourcesOwner.defaultPlaylistId` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_ensureFocusNodes` | `IptvSettingsFocusActions.ensureFocusNodes` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_fileTabFocusNode` | `IptvSettingsFocusOwner.fileTabFocusNode` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_focusAndReveal` | `IptvSettingsFocusActions.focusAndReveal` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_playlistFocusNodes` | `IptvSettingsFocusOwner.playlistFocusNodes` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_tabController` | `IptvSettingsInputOwner.tabController` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_urlTabFocusNode` | `IptvSettingsFocusOwner.urlTabFocusNode` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `_xcTabFocusNode` | `IptvSettingsFocusOwner.xcTabFocusNode` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `context` | `State live context getter` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsSourceRemoval` | `setState` | `State setState tear-off` | Pending step 3 |
| `IptvSettingsSourceEdit` | `_catalogKeysFor` | `IptvSettingsCatalogActions.catalogKeysFor` | Pending step 3 |
| `IptvSettingsSourceEdit` | `_catalogOwnerReferencesFor` | `IptvSettingsCatalogActions.catalogOwnerReferencesFor` | Pending step 3 |
| `IptvSettingsSourceEdit` | `_normalizeXtreamServerUrl` | `.normalizeXtreamServerUrl` | Pending step 3 |
| `IptvSettingsSourceEdit` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 3 |
| `IptvSettingsSourceEdit` | `_runProfileAction` | `IptvSettingsProfileActions.runProfileAction` | Pending step 3 |
| `IptvSettingsSourceEdit` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 3 |
| `IptvSettingsSourceEdit` | `context` | `State live context getter` | Pending step 3 |
| `IptvSettingsSourceEdit` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsSourceEdit` | `setState` | `State setState tear-off` | Pending step 3 |
| `IptvSettingsSourceRefresh` | `_defaultPlaylistId` | `IptvSettingsSourcesOwner.defaultPlaylistId` | Pending step 3 |
| `IptvSettingsSourceRefresh` | `_refreshingIds` | `IptvSettingsSourcesOwner.refreshingIds` | Pending step 3 |
| `IptvSettingsSourceRefresh` | `_runProfileAction` | `IptvSettingsProfileActions.runProfileAction` | Pending step 3 |
| `IptvSettingsSourceRefresh` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 3 |
| `IptvSettingsSourceRefresh` | `mounted` | `State live mounted getter` | Pending step 3 |
| `IptvSettingsSourceRefresh` | `setState` | `State setState tear-off` | Pending step 3 |
| `IptvSettingsListsActions` | `_createListFocusNode` | `IptvSettingsFocusOwner.createListFocusNode` | Pending step 4 |
| `IptvSettingsListsActions` | `_ensureFocusNodes` | `IptvSettingsFocusActions.ensureFocusNodes` | Pending step 4 |
| `IptvSettingsListsActions` | `_focusAndReveal` | `IptvSettingsFocusActions.focusAndReveal` | Pending step 4 |
| `IptvSettingsListsActions` | `_listFocusNodes` | `IptvSettingsFocusOwner.listFocusNodes` | Pending step 4 |
| `IptvSettingsListsActions` | `_lists` | `IptvSettingsSourcesOwner.lists` | Pending step 4 |
| `IptvSettingsListsActions` | `_runProfileAction` | `IptvSettingsProfileActions.runProfileAction` | Pending step 4 |
| `IptvSettingsListsActions` | `_showSnackBar` | `IptvSettingsFeedback.showSnackBar` | Pending step 4 |
| `IptvSettingsListsActions` | `context` | `State live context getter` | Pending step 4 |
| `IptvSettingsListsActions` | `mounted` | `State live mounted getter` | Pending step 4 |
| `IptvSettingsListsActions` | `setState` | `State setState tear-off` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_autoRefreshHours` | `IptvSettingsPreferencesOwner.autoRefreshHours` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_channelPreviewEnabled` | `IptvSettingsPreferencesOwner.channelPreviewEnabled` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_iptvStyle` | `IptvSettingsPreferencesOwner.iptvStyle` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_lastLiveChannel` | `IptvSettingsPreferencesOwner.lastLiveChannel` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_playerGuideStyle` | `IptvSettingsPreferencesOwner.playerGuideStyle` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_runProfileAction` | `IptvSettingsProfileActions.runProfileAction` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_startupChannel` | `IptvSettingsPreferencesOwner.startupChannel` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_startupEnabled` | `IptvSettingsPreferencesOwner.startupEnabled` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_startupMode` | `IptvSettingsPreferencesOwner.startupMode` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `_trackContinueWatching` | `IptvSettingsPreferencesOwner.trackContinueWatching` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `context` | `State live context getter` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `mounted` | `State live mounted getter` | Pending step 4 |
| `IptvSettingsPreferencesActions` | `setState` | `State setState tear-off` | Pending step 4 |
| `IptvSettingsRecordingActions` | `_maxConcurrent` | `IptvSettingsRecordingOwner.maxConcurrent` | Pending step 4 |
| `IptvSettingsRecordingActions` | `_recheckBatteryOnResume` | `IptvSettingsRecordingOwner.recheckBatteryOnResume` | Pending step 4 |
| `IptvSettingsRecordingActions` | `_scheduledCount` | `IptvSettingsRecordingOwner.scheduledCount` | Pending step 4 |
| `IptvSettingsRecordingActions` | `context` | `State live context getter` | Pending step 4 |
| `IptvSettingsRecordingActions` | `mounted` | `State live mounted getter` | Pending step 4 |
| `IptvSettingsRecordingActions` | `setState` | `State setState tear-off` | Pending step 4 |
| `IptvSettingsSourceForms` | `_addButtonFocusNode` | `IptvSettingsFocusOwner.addButtonFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_addPlaylist` | `IptvSettingsUrlAdd.addPlaylist` | Pending step 5 |
| `IptvSettingsSourceForms` | `_addXtreamCodes` | `IptvSettingsXtreamAdd.addXtreamCodes` | Pending step 5 |
| `IptvSettingsSourceForms` | `_epgUrlController` | `IptvSettingsInputOwner.epgUrlController` | Pending step 5 |
| `IptvSettingsSourceForms` | `_epgUrlInputFocusNode` | `IptvSettingsFocusOwner.epgUrlInputFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_fileTabFocusNode` | `IptvSettingsFocusOwner.fileTabFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_focusAndReveal` | `IptvSettingsFocusActions.focusAndReveal` | Pending step 5 |
| `IptvSettingsSourceForms` | `_importFileButtonFocusNode` | `IptvSettingsFocusOwner.importFileButtonFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_importFromFile` | `IptvSettingsFileImport.importFromFile` | Pending step 5 |
| `IptvSettingsSourceForms` | `_isAdding` | `IptvSettingsInputOwner.isAdding` | Pending step 5 |
| `IptvSettingsSourceForms` | `_isXcAdding` | `IptvSettingsInputOwner.isXcAdding` | Pending step 5 |
| `IptvSettingsSourceForms` | `_nameController` | `IptvSettingsInputOwner.nameController` | Pending step 5 |
| `IptvSettingsSourceForms` | `_nameInputFocusNode` | `IptvSettingsFocusOwner.nameInputFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_playlistFocusNodes` | `IptvSettingsFocusOwner.playlistFocusNodes` | Pending step 5 |
| `IptvSettingsSourceForms` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 5 |
| `IptvSettingsSourceForms` | `_twoPaneActive` | `IptvSettingsLayoutOwner.twoPaneActive` | Pending step 5 |
| `IptvSettingsSourceForms` | `_urlController` | `IptvSettingsInputOwner.urlController` | Pending step 5 |
| `IptvSettingsSourceForms` | `_urlInputFocusNode` | `IptvSettingsFocusOwner.urlInputFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_urlTabFocusNode` | `IptvSettingsFocusOwner.urlTabFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcLoginButtonFocusNode` | `IptvSettingsFocusOwner.xcLoginButtonFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcNameController` | `IptvSettingsInputOwner.xcNameController` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcNameFocusNode` | `IptvSettingsFocusOwner.xcNameFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcPasswordController` | `IptvSettingsInputOwner.xcPasswordController` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcPasswordFocusNode` | `IptvSettingsFocusOwner.xcPasswordFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcServerController` | `IptvSettingsInputOwner.xcServerController` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcServerFocusNode` | `IptvSettingsFocusOwner.xcServerFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcTabFocusNode` | `IptvSettingsFocusOwner.xcTabFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcUsernameController` | `IptvSettingsInputOwner.xcUsernameController` | Pending step 5 |
| `IptvSettingsSourceForms` | `_xcUsernameFocusNode` | `IptvSettingsFocusOwner.xcUsernameFocusNode` | Pending step 5 |
| `IptvSettingsSourceForms` | `context` | `State live context getter` | Pending step 5 |
| `IptvSettingsSourceViews` | `_backButtonFocusNode` | `IptvSettingsFocusOwner.backButtonFocusNode` | Pending step 5 |
| `IptvSettingsSourceViews` | `_buildFileTabContent` | `IptvSettingsSourceForms.buildFileTabContent` | Pending step 5 |
| `IptvSettingsSourceViews` | `_buildUrlTabContent` | `IptvSettingsSourceForms.buildUrlTabContent` | Pending step 5 |
| `IptvSettingsSourceViews` | `_buildXcTabContent` | `IptvSettingsSourceForms.buildXcTabContent` | Pending step 5 |
| `IptvSettingsSourceViews` | `_defaultPlaylistId` | `IptvSettingsSourcesOwner.defaultPlaylistId` | Pending step 5 |
| `IptvSettingsSourceViews` | `_editPlaylist` | `IptvSettingsSourceEdit.editPlaylist` | Pending step 5 |
| `IptvSettingsSourceViews` | `_fileTabFocusNode` | `IptvSettingsFocusOwner.fileTabFocusNode` | Pending step 5 |
| `IptvSettingsSourceViews` | `_focusContentAfterTabSwitch` | `IptvSettingsFocusActions.focusContentAfterTabSwitch` | Pending step 5 |
| `IptvSettingsSourceViews` | `_importFileButtonFocusNode` | `IptvSettingsFocusOwner.importFileButtonFocusNode` | Pending step 5 |
| `IptvSettingsSourceViews` | `_nameInputFocusNode` | `IptvSettingsFocusOwner.nameInputFocusNode` | Pending step 5 |
| `IptvSettingsSourceViews` | `_playlistFocusNodes` | `IptvSettingsFocusOwner.playlistFocusNodes` | Pending step 5 |
| `IptvSettingsSourceViews` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 5 |
| `IptvSettingsSourceViews` | `_refreshPlaylist` | `IptvSettingsSourceRefresh.refreshPlaylist` | Pending step 5 |
| `IptvSettingsSourceViews` | `_refreshingIds` | `IptvSettingsSourcesOwner.refreshingIds` | Pending step 5 |
| `IptvSettingsSourceViews` | `_removePlaylist` | `IptvSettingsSourceRemoval.removePlaylist` | Pending step 5 |
| `IptvSettingsSourceViews` | `_setDefaultPlaylist` | `IptvSettingsSourceRefresh.setDefaultPlaylist` | Pending step 5 |
| `IptvSettingsSourceViews` | `_tabController` | `IptvSettingsInputOwner.tabController` | Pending step 5 |
| `IptvSettingsSourceViews` | `_urlTabFocusNode` | `IptvSettingsFocusOwner.urlTabFocusNode` | Pending step 5 |
| `IptvSettingsSourceViews` | `_xcNameFocusNode` | `IptvSettingsFocusOwner.xcNameFocusNode` | Pending step 5 |
| `IptvSettingsSourceViews` | `_xcTabFocusNode` | `IptvSettingsFocusOwner.xcTabFocusNode` | Pending step 5 |
| `IptvSettingsSourceViews` | `context` | `State live context getter` | Pending step 5 |
| `IptvSettingsListViews` | `_createList` | `IptvSettingsListsActions.createList` | Pending step 5 |
| `IptvSettingsListViews` | `_createListFocusNode` | `IptvSettingsFocusOwner.createListFocusNode` | Pending step 5 |
| `IptvSettingsListViews` | `_customLists` | `IptvSettingsListsActions.customLists` | Pending step 5 |
| `IptvSettingsListViews` | `_deleteList` | `IptvSettingsListsActions.deleteList` | Pending step 5 |
| `IptvSettingsListViews` | `_listNodeAt` | `IptvSettingsListsActions.listNodeAt` | Pending step 5 |
| `IptvSettingsListViews` | `_moveList` | `IptvSettingsListsActions.moveList` | Pending step 5 |
| `IptvSettingsListViews` | `_renameList` | `IptvSettingsListsActions.renameList` | Pending step 5 |
| `IptvSettingsListViews` | `context` | `State live context getter` | Pending step 5 |
| `IptvSettingsCategoryViews` | `_categoryOrderSources` | `IptvSettingsCatalogActions.categoryOrderSources` | Pending step 5 |
| `IptvSettingsCategoryViews` | `_hiddenCounts` | `IptvSettingsSourcesOwner.hiddenCounts` | Pending step 5 |
| `IptvSettingsCategoryViews` | `_hiddenFocusNodes` | `IptvSettingsFocusOwner.hiddenFocusNodes` | Pending step 5 |
| `IptvSettingsCategoryViews` | `_hideableSources` | `IptvSettingsCatalogActions.hideableSources` | Pending step 5 |
| `IptvSettingsCategoryViews` | `_openCategoryOrder` | `IptvSettingsCatalogActions.openCategoryOrder` | Pending step 5 |
| `IptvSettingsCategoryViews` | `_openHiddenCategories` | `IptvSettingsCatalogActions.openHiddenCategories` | Pending step 5 |
| `IptvSettingsCategoryViews` | `context` | `State live context getter` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_channelPreviewEnabled` | `IptvSettingsPreferencesOwner.channelPreviewEnabled` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_lastLiveChannel` | `IptvSettingsPreferencesOwner.lastLiveChannel` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_lastLiveChannelLabel` | `IptvSettingsPreferencesActions.lastLiveChannelLabel` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_pickStartupChannel` | `IptvSettingsPreferencesActions.pickStartupChannel` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_setChannelPreviewEnabled` | `IptvSettingsPreferencesActions.setChannelPreviewEnabled` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_setStartupEnabled` | `IptvSettingsPreferencesActions.setStartupEnabled` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_setStartupMode` | `IptvSettingsPreferencesActions.setStartupMode` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_setTrackContinueWatching` | `IptvSettingsPreferencesActions.setTrackContinueWatching` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_startupChannel` | `IptvSettingsPreferencesOwner.startupChannel` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_startupChannelFocusNode` | `IptvSettingsFocusOwner.startupChannelFocusNode` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_startupChannelLabel` | `IptvSettingsPreferencesActions.startupChannelLabel` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_startupEnabled` | `IptvSettingsPreferencesOwner.startupEnabled` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_startupMode` | `IptvSettingsPreferencesOwner.startupMode` | Pending step 5 |
| `IptvSettingsPreferencesViews` | `_trackContinueWatching` | `IptvSettingsPreferencesOwner.trackContinueWatching` | Pending step 5 |
| `IptvSettingsRecordingView` | `_batteryExempt` | `IptvSettingsRecordingOwner.batteryExempt` | Pending step 5 |
| `IptvSettingsRecordingView` | `_batteryFocusNode` | `IptvSettingsFocusOwner.batteryFocusNode` | Pending step 5 |
| `IptvSettingsRecordingView` | `_engineToggleVisible` | `IptvSettingsRecordingOwner.engineToggleVisible` | Pending step 5 |
| `IptvSettingsRecordingView` | `_maxConcurrent` | `IptvSettingsRecordingOwner.maxConcurrent` | Pending step 5 |
| `IptvSettingsRecordingView` | `_maxConcurrentFocusNode` | `IptvSettingsFocusOwner.maxConcurrentFocusNode` | Pending step 5 |
| `IptvSettingsRecordingView` | `_openScheduledRecordings` | `IptvSettingsRecordingActions.openScheduledRecordings` | Pending step 5 |
| `IptvSettingsRecordingView` | `_pickMaxConcurrent` | `IptvSettingsRecordingActions.pickMaxConcurrent` | Pending step 5 |
| `IptvSettingsRecordingView` | `_recordingEngineOn` | `IptvSettingsRecordingOwner.recordingEngineOn` | Pending step 5 |
| `IptvSettingsRecordingView` | `_requestBatteryExemption` | `IptvSettingsRecordingActions.requestBatteryExemption` | Pending step 5 |
| `IptvSettingsRecordingView` | `_scheduledCount` | `IptvSettingsRecordingOwner.scheduledCount` | Pending step 5 |
| `IptvSettingsRecordingView` | `_scheduledRecordingsFocusNode` | `IptvSettingsFocusOwner.scheduledRecordingsFocusNode` | Pending step 5 |
| `IptvSettingsRecordingView` | `mounted` | `State live mounted getter` | Pending step 5 |
| `IptvSettingsRecordingView` | `setState` | `State setState tear-off` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_appearanceVisible` | `_IptvSettingsPageState._appearanceVisible` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_autoRefreshHours` | `IptvSettingsPreferencesOwner.autoRefreshHours` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_categoryOrderSources` | `IptvSettingsCatalogActions.categoryOrderSources` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_channelPreviewEnabled` | `IptvSettingsPreferencesOwner.channelPreviewEnabled` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_customLists` | `IptvSettingsListsActions.customLists` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_defaultPlaylistId` | `IptvSettingsSourcesOwner.defaultPlaylistId` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_engineToggleVisible` | `IptvSettingsRecordingOwner.engineToggleVisible` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_enterPhoneSection` | `IptvSettingsLayoutActions.enterPhoneSection` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_hiddenCounts` | `IptvSettingsSourcesOwner.hiddenCounts` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_hideableSources` | `IptvSettingsCatalogActions.hideableSources` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_hubSourcesFocusNode` | `IptvSettingsFocusOwner.hubSourcesFocusNode` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_iptvStyle` | `IptvSettingsPreferencesOwner.iptvStyle` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_openChannelOrder` | `IptvSettingsCatalogActions.openChannelOrder` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_openIptvStylePicker` | `IptvSettingsPreferencesActions.openIptvStylePicker` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_openPlayerGuidePicker` | `IptvSettingsPreferencesActions.openPlayerGuidePicker` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_pickAutoRefresh` | `IptvSettingsPreferencesActions.pickAutoRefresh` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_playerGuideStyle` | `IptvSettingsPreferencesOwner.playerGuideStyle` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_recordingEngineOn` | `IptvSettingsRecordingOwner.recordingEngineOn` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_recordingSectionVisible` | `IptvSettingsRecordingOwner.recordingSectionVisible` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_scheduledCount` | `IptvSettingsRecordingOwner.scheduledCount` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_startupChannelLabel` | `IptvSettingsPreferencesActions.startupChannelLabel` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_startupEnabled` | `IptvSettingsPreferencesOwner.startupEnabled` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_startupMode` | `IptvSettingsPreferencesOwner.startupMode` | Pending step 5 |
| `IptvSettingsPhoneHub` | `_trackContinueWatching` | `IptvSettingsPreferencesOwner.trackContinueWatching` | Pending step 5 |
| `IptvSettingsTwoPane` | `_appearanceVisible` | `_IptvSettingsPageState._appearanceVisible` | Pending step 5 |
| `IptvSettingsTwoPane` | `_autoRefreshHours` | `IptvSettingsPreferencesOwner.autoRefreshHours` | Pending step 5 |
| `IptvSettingsTwoPane` | `_batteryExempt` | `IptvSettingsRecordingOwner.batteryExempt` | Pending step 5 |
| `IptvSettingsTwoPane` | `_buildFileTabContent` | `IptvSettingsSourceForms.buildFileTabContent` | Pending step 5 |
| `IptvSettingsTwoPane` | `_buildUrlTabContent` | `IptvSettingsSourceForms.buildUrlTabContent` | Pending step 5 |
| `IptvSettingsTwoPane` | `_buildXcTabContent` | `IptvSettingsSourceForms.buildXcTabContent` | Pending step 5 |
| `IptvSettingsTwoPane` | `_channelPreviewEnabled` | `IptvSettingsPreferencesOwner.channelPreviewEnabled` | Pending step 5 |
| `IptvSettingsTwoPane` | `_createList` | `IptvSettingsListsActions.createList` | Pending step 5 |
| `IptvSettingsTwoPane` | `_customLists` | `IptvSettingsListsActions.customLists` | Pending step 5 |
| `IptvSettingsTwoPane` | `_defaultPlaylistId` | `IptvSettingsSourcesOwner.defaultPlaylistId` | Pending step 5 |
| `IptvSettingsTwoPane` | `_editPlaylist` | `IptvSettingsSourceEdit.editPlaylist` | Pending step 5 |
| `IptvSettingsTwoPane` | `_engineToggleVisible` | `IptvSettingsRecordingOwner.engineToggleVisible` | Pending step 5 |
| `IptvSettingsTwoPane` | `_fileTabFocusNode` | `IptvSettingsFocusOwner.fileTabFocusNode` | Pending step 5 |
| `IptvSettingsTwoPane` | `_focusAndReveal` | `IptvSettingsFocusActions.focusAndReveal` | Pending step 5 |
| `IptvSettingsTwoPane` | `_hiddenCounts` | `IptvSettingsSourcesOwner.hiddenCounts` | Pending step 5 |
| `IptvSettingsTwoPane` | `_importFileButtonFocusNode` | `IptvSettingsFocusOwner.importFileButtonFocusNode` | Pending step 5 |
| `IptvSettingsTwoPane` | `_iptvStyle` | `IptvSettingsPreferencesOwner.iptvStyle` | Pending step 5 |
| `IptvSettingsTwoPane` | `_lastLiveChannel` | `IptvSettingsPreferencesOwner.lastLiveChannel` | Pending step 5 |
| `IptvSettingsTwoPane` | `_lastLiveChannelLabel` | `IptvSettingsPreferencesActions.lastLiveChannelLabel` | Pending step 5 |
| `IptvSettingsTwoPane` | `_maxConcurrent` | `IptvSettingsRecordingOwner.maxConcurrent` | Pending step 5 |
| `IptvSettingsTwoPane` | `_nameInputFocusNode` | `IptvSettingsFocusOwner.nameInputFocusNode` | Pending step 5 |
| `IptvSettingsTwoPane` | `_openCategoryOrder` | `IptvSettingsCatalogActions.openCategoryOrder` | Pending step 5 |
| `IptvSettingsTwoPane` | `_openChannelOrder` | `IptvSettingsCatalogActions.openChannelOrder` | Pending step 5 |
| `IptvSettingsTwoPane` | `_openHiddenCategories` | `IptvSettingsCatalogActions.openHiddenCategories` | Pending step 5 |
| `IptvSettingsTwoPane` | `_openScheduledRecordings` | `IptvSettingsRecordingActions.openScheduledRecordings` | Pending step 5 |
| `IptvSettingsTwoPane` | `_pickAutoRefresh` | `IptvSettingsPreferencesActions.pickAutoRefresh` | Pending step 5 |
| `IptvSettingsTwoPane` | `_pickMaxConcurrent` | `IptvSettingsRecordingActions.pickMaxConcurrent` | Pending step 5 |
| `IptvSettingsTwoPane` | `_pickStartupChannel` | `IptvSettingsPreferencesActions.pickStartupChannel` | Pending step 5 |
| `IptvSettingsTwoPane` | `_playerGuideStyle` | `IptvSettingsPreferencesOwner.playerGuideStyle` | Pending step 5 |
| `IptvSettingsTwoPane` | `_playlists` | `IptvSettingsSourcesOwner.playlists` | Pending step 5 |
| `IptvSettingsTwoPane` | `_recordingEngineOn` | `IptvSettingsRecordingOwner.recordingEngineOn` | Pending step 5 |
| `IptvSettingsTwoPane` | `_recordingSectionVisible` | `IptvSettingsRecordingOwner.recordingSectionVisible` | Pending step 5 |
| `IptvSettingsTwoPane` | `_refreshPlaylist` | `IptvSettingsSourceRefresh.refreshPlaylist` | Pending step 5 |
| `IptvSettingsTwoPane` | `_refreshingIds` | `IptvSettingsSourcesOwner.refreshingIds` | Pending step 5 |
| `IptvSettingsTwoPane` | `_removePlaylist` | `IptvSettingsSourceRemoval.removePlaylist` | Pending step 5 |
| `IptvSettingsTwoPane` | `_requestBatteryExemption` | `IptvSettingsRecordingActions.requestBatteryExemption` | Pending step 5 |
| `IptvSettingsTwoPane` | `_scheduledCount` | `IptvSettingsRecordingOwner.scheduledCount` | Pending step 5 |
| `IptvSettingsTwoPane` | `_setChannelPreviewEnabled` | `IptvSettingsPreferencesActions.setChannelPreviewEnabled` | Pending step 5 |
| `IptvSettingsTwoPane` | `_setDefaultPlaylist` | `IptvSettingsSourceRefresh.setDefaultPlaylist` | Pending step 5 |
| `IptvSettingsTwoPane` | `_setIptvStyle` | `IptvSettingsPreferencesActions.setIptvStyle` | Pending step 5 |
| `IptvSettingsTwoPane` | `_setPlayerGuideStyle` | `IptvSettingsPreferencesActions.setPlayerGuideStyle` | Pending step 5 |
| `IptvSettingsTwoPane` | `_setStartupEnabled` | `IptvSettingsPreferencesActions.setStartupEnabled` | Pending step 5 |
| `IptvSettingsTwoPane` | `_setStartupMode` | `IptvSettingsPreferencesActions.setStartupMode` | Pending step 5 |
| `IptvSettingsTwoPane` | `_setTrackContinueWatching` | `IptvSettingsPreferencesActions.setTrackContinueWatching` | Pending step 5 |
| `IptvSettingsTwoPane` | `_showListActions` | `IptvSettingsListsActions.showListActions` | Pending step 5 |
| `IptvSettingsTwoPane` | `_startupChannel` | `IptvSettingsPreferencesOwner.startupChannel` | Pending step 5 |
| `IptvSettingsTwoPane` | `_startupChannelLabel` | `IptvSettingsPreferencesActions.startupChannelLabel` | Pending step 5 |
| `IptvSettingsTwoPane` | `_startupEnabled` | `IptvSettingsPreferencesOwner.startupEnabled` | Pending step 5 |
| `IptvSettingsTwoPane` | `_startupMode` | `IptvSettingsPreferencesOwner.startupMode` | Pending step 5 |
| `IptvSettingsTwoPane` | `_tabController` | `IptvSettingsInputOwner.tabController` | Pending step 5 |
| `IptvSettingsTwoPane` | `_trackContinueWatching` | `IptvSettingsPreferencesOwner.trackContinueWatching` | Pending step 5 |
| `IptvSettingsTwoPane` | `_twoPaneKey` | `_IptvSettingsPageState._twoPaneKey` | Pending step 5 |
| `IptvSettingsTwoPane` | `_urlTabFocusNode` | `IptvSettingsFocusOwner.urlTabFocusNode` | Pending step 5 |
| `IptvSettingsTwoPane` | `_xcNameFocusNode` | `IptvSettingsFocusOwner.xcNameFocusNode` | Pending step 5 |
| `IptvSettingsTwoPane` | `_xcTabFocusNode` | `IptvSettingsFocusOwner.xcTabFocusNode` | Pending step 5 |
| `IptvSettingsTwoPane` | `mounted` | `State live mounted getter` | Pending step 5 |
| `IptvSettingsTwoPane` | `setState` | `State setState tear-off` | Pending step 5 |
| `IptvSettingsTwoPane` | `widget` | `live openAddSource getter only` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildCategoryOrderView` | `IptvSettingsCategoryViews.buildCategoryOrderView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildChannelPreviewView` | `IptvSettingsPreferencesViews.buildChannelPreviewView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildContinueWatchingView` | `IptvSettingsPreferencesViews.buildContinueWatchingView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildHiddenView` | `IptvSettingsCategoryViews.buildHiddenView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildListsView` | `IptvSettingsListViews.buildListsView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildPhoneHub` | `IptvSettingsPhoneHub.buildPhoneHub` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildRecordingView` | `IptvSettingsRecordingView.buildRecordingView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildSourcesView` | `IptvSettingsSourceViews.buildSourcesView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_buildStartupView` | `IptvSettingsPreferencesViews.buildStartupView` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_phoneSection` | `IptvSettingsLayoutOwner.phoneSection` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_phoneViewMarker` | `IptvSettingsFocusOwner.phoneViewMarker` | Pending step 5 |
| `IptvSettingsLayoutActions` | `_twoPaneActive` | `IptvSettingsLayoutOwner.twoPaneActive` | Pending step 5 |
| `IptvSettingsLayoutActions` | `mounted` | `State live mounted getter` | Pending step 5 |
| `IptvSettingsLayoutActions` | `setState` | `State setState tear-off` | Pending step 5 |
| `IptvSettingsRootLayout` | `_backButtonFocusNode` | `IptvSettingsFocusOwner.backButtonFocusNode` | Pending step 6 |
| `IptvSettingsRootLayout` | `_buildSingleColumn` | `IptvSettingsLayoutActions.buildSingleColumn` | Pending step 6 |
| `IptvSettingsRootLayout` | `_buildTwoPane` | `IptvSettingsTwoPane.buildTwoPane` | Pending step 6 |
| `IptvSettingsRootLayout` | `_enterPhoneSection` | `IptvSettingsLayoutActions.enterPhoneSection` | Pending step 6 |
| `IptvSettingsRootLayout` | `_fileTabFocusNode` | `IptvSettingsFocusOwner.fileTabFocusNode` | Pending step 6 |
| `IptvSettingsRootLayout` | `_focusAndReveal` | `IptvSettingsFocusActions.focusAndReveal` | Pending step 6 |
| `IptvSettingsRootLayout` | `_loading` | `IptvSettingsSourcesOwner.loading` | Pending step 6 |
| `IptvSettingsRootLayout` | `_phoneSection` | `IptvSettingsLayoutOwner.phoneSection` | Pending step 6 |
| `IptvSettingsRootLayout` | `_phoneViewMarker` | `IptvSettingsFocusOwner.phoneViewMarker` | Pending step 6 |
| `IptvSettingsRootLayout` | `_tabController` | `IptvSettingsInputOwner.tabController` | Pending step 6 |
| `IptvSettingsRootLayout` | `_twoPaneActive` | `IptvSettingsLayoutOwner.twoPaneActive` | Pending step 6 |
| `IptvSettingsRootLayout` | `_twoPaneKey` | `_IptvSettingsPageState._twoPaneKey` | Pending step 6 |
| `IptvSettingsRootLayout` | `_urlTabFocusNode` | `IptvSettingsFocusOwner.urlTabFocusNode` | Pending step 6 |
| `IptvSettingsRootLayout` | `_xcTabFocusNode` | `IptvSettingsFocusOwner.xcTabFocusNode` | Pending step 6 |
| `IptvSettingsRootLayout` | `mounted` | `State live mounted getter` | Pending step 6 |
| `IptvSettingsRootLayout` | `setState` | `State setState tear-off` | Pending step 6 |

## Zones and deferred work

Every `_runProfileAction` body, including nested auto-refresh and the unawaited discovery call, remains one lexical unit. `runIfCurrent` only rejects before entering the body; original later continuation behavior is retained. No zone binding is added to post-frame callbacks.

- `_pickAutoRefresh`: profile-action closure=True; post-frame registrations=0.
- `_runProfileAction`: profile-action closure=True; post-frame registrations=0.
- `_enterPhoneSection`: profile-action closure=False; post-frame registrations=1.
- `_focusContentAfterTabSwitch`: profile-action closure=False; post-frame registrations=1.
- `_focusAndReveal`: profile-action closure=False; post-frame registrations=1.
- `_setStartupMode`: profile-action closure=True; post-frame registrations=0.
- `_setStartupEnabled`: profile-action closure=True; post-frame registrations=0.
- `_setTrackContinueWatching`: profile-action closure=True; post-frame registrations=0.
- `_setChannelPreviewEnabled`: profile-action closure=True; post-frame registrations=0.
- `_setIptvStyle`: profile-action closure=True; post-frame registrations=0.
- `_setPlayerGuideStyle`: profile-action closure=True; post-frame registrations=0.
- `_pickStartupChannel`: profile-action closure=True; post-frame registrations=0.
- `_loadSettings`: profile-action closure=False; post-frame registrations=1.
- `_addPlaylist`: profile-action closure=True; post-frame registrations=0.
- `_importFromFile`: profile-action closure=True; post-frame registrations=0.
- `_addXtreamCodes`: profile-action closure=True; post-frame registrations=0.
- `_removePlaylistForProfile`: profile-action closure=False; post-frame registrations=1.
- `_setDefaultPlaylist`: profile-action closure=True; post-frame registrations=0.
- `_refreshPlaylist`: profile-action closure=True; post-frame registrations=0.
- `_createList`: profile-action closure=True; post-frame registrations=0.
- `_renameList`: profile-action closure=True; post-frame registrations=0.
- `_deleteList`: profile-action closure=True; post-frame registrations=0.
- `_deleteListForProfile`: profile-action closure=False; post-frame registrations=1.
- `_moveList`: profile-action closure=True; post-frame registrations=0.
- `_editPlaylist`: profile-action closure=True; post-frame registrations=0.
- `build`: profile-action closure=False; post-frame registrations=1.

## Source registrations

- Shape: two regex-counted bare radii, one uncounted vertical top radius, five token calls. Every destination with tokens belongs in kShapeResidue; every other destination belongs in kExtractedShapeResidue, including zero budgets.
- Theme registry uses explicit application/models/presentation/bridge patterns. TV text-field source guard includes the original facade at step 0 and each new destination. Profile print-redaction scan includes the new feature.
- Size, architecture, CI formatting/analyzer paths and exact observed analyzer identities are updated at scheduled checkpoints. No existing feature manifest is expanded to own this extraction.

## Exceptions and exits

State-driven sections → later IPTV settings Riverpod controller; direct legacy service/storage bridge → playlist/list/appearance/startup/recording data contracts; unchanged text → localization migration; raw startup/last-channel maps → typed data contracts; synchronous build-time twoPaneActive/phoneSection writes → derived layout state in the controller milestone.

## Source-reader registrations

The original page contributes two regex-counted bare circular radii, the
vertical sheet radius (outside that regex), and five shape-token calls. The
488-call global floor has zero slack. Each moved file with a token call must
join `kShapeResidue`; other destinations join `kExtractedShapeResidue` with
their transferred residue, and the facade count only lowers. The token/bare
sites are frozen by the whole-widget/method manifest comparisons. Theme
surfaces use explicit application, models, presentation and bridge globs.
TV input reads include the original facade now and each destination as it
exists; redacted-log reads include the feature folder. CI names all six new
Dart suites and the existing full-page secret-repair suite, and formats all
three support helpers plus the facade.

The AST's `dispose` calls inside focus-node shrink loops are methods on nodes,
not a callback dependency on State.dispose; lifecycle stays exclusively in
the facade. Default/named-argument behavior and live context/getter sites are
reviewed again against actual constructor bindings at each extraction step.

Step 1 review: the three plain declarations import no services/UI and retain
all enum values, value fields, constructor defaults and URI normalization.
Their production reads and the accessor are wired; manifest/behavior checks
pass against the original checkpoint.
