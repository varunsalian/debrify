# Stremio TV dependency and wiring report

Original R: `c7a3d156d260e08421043a5430c6242124ba8e1b`. Source is 3,958 formatted physical lines. Nothing is extracted in step 0. The TSV owns 119 AST declaration leaves: retained widget, 40 State fields, 69 State methods/getter/static, and nine other top-level declarations. Free comment leaves below are pinned separately by the feature contracts; AST-owned comments remain in their declaration's token proof.

Each row was reviewed against the original caller and the raw occurrence/scope inventory before pinning its wiring. Record construction remains eager; sections remain cached once per State. Lexical locals/builders remain lexical. C1–C9 name observable coverage; source-only contracts remain labelled S.

| Original (R line) | Destination owner/member | Wiring review |
| --- | --- | --- |
| `StremioTvScreen (54)` | `lib/screens/stremio_tv/stremio_tv_screen.dart:StremioTvScreen` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._service (72)` | `presentation/legacy_stremio_tv/stremio_tv_library_state.dart:StremioTvLibraryState.service` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._channels (74)` | `presentation/legacy_stremio_tv/stremio_tv_library_state.dart:StremioTvLibraryState.channels` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._loading (75)` | `presentation/legacy_stremio_tv/stremio_tv_library_state.dart:StremioTvLibraryState.loading` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._refreshing (76)` | `presentation/legacy_stremio_tv/stremio_tv_library_state.dart:StremioTvLibraryState.refreshing` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._rotationMinutes (77)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.rotationMinutes` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._seriesRotationMinutes (78)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.seriesRotationMinutes` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._randomEpisodes (79)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.randomEpisodes` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._autoRefresh (80)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.autoRefresh` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._preferredQuality (81)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.preferredQuality` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._debridProvider (82)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.debridProvider` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._rdSkipBlockedTorrents (83)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.rdSkipBlockedTorrents` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._torrentsFirst (84)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.torrentsFirst` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._availableProviders (85)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.availableProviders` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._maxStartPercent (86)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.maxStartPercent` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._hideNowPlaying (87)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.hideNowPlaying` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._currentSlotProgress (88)` | `presentation/legacy_stremio_tv/stremio_tv_playback_state.dart:StremioTvPlaybackState.currentSlotProgress` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._playGeneration (89)` | `presentation/legacy_stremio_tv/stremio_tv_playback_state.dart:StremioTvPlaybackState.playGeneration` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._currentPlayTitle (90)` | `presentation/legacy_stremio_tv/stremio_tv_playback_state.dart:StremioTvPlaybackState.currentPlayTitle` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._playbackCursors (91)` | `presentation/legacy_stremio_tv/stremio_tv_playback_state.dart:StremioTvPlaybackState.playbackCursors` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._rotationFor (93)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary.rotationFor` | _seriesRotationMinutes (read) → _owners.settings.seriesRotationMinutes, _rotationMinutes (read) → _owners.settings.rotationMinutes; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._rowFocusNodes (97)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.rowFocusNodes` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._focusedIndex (98)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.focusedIndex` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._tunerController (100)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.tunerController` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._contentRevision (106)` | `presentation/legacy_stremio_tv/stremio_tv_library_state.dart:StremioTvLibraryState.contentRevision` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._mixSalt (114)` | `presentation/legacy_stremio_tv/stremio_tv_library_state.dart:StremioTvLibraryState.mixSalt` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._searchBtnFocusNode (117)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.searchBtnFocusNode` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._providerFocusNode (118)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.providerFocusNode` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._menuFocusNode (119)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.menuFocusNode` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._submenuFocusNode (120)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.submenuFocusNode` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._providerMenuController (121)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.providerMenuController` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._menuController (122)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.menuController` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._searchController (125)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.searchController` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._searchFocusNode (126)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.searchFocusNode` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._searchQuery (127)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.searchQuery` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._showSearchField (128)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.showSearchField` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._mdblistConnected (132)` | `presentation/legacy_stremio_tv/stremio_tv_settings_state.dart:StremioTvSettingsState.mdblistConnected` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._loadingChannelIds (135)` | `presentation/legacy_stremio_tv/stremio_tv_library_state.dart:StremioTvLibraryState.loadingChannelIds` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._pendingChannelId (138)` | `presentation/legacy_stremio_tv/stremio_tv_playback_state.dart:StremioTvPlaybackState.pendingChannelId` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._startupAutoPlayActive (139)` | `presentation/legacy_stremio_tv/stremio_tv_playback_state.dart:StremioTvPlaybackState.startupAutoPlayActive` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._tvContentFocusHandler (142)` | `presentation/legacy_stremio_tv/stremio_tv_focus_state.dart:StremioTvFocusState.tvContentFocusHandler` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState.initState (144)` | `lib/screens/stremio_tv/stremio_tv_screen.dart:_StremioTvScreenState.initState` | _mdblistConnected (read) → _owners.settings.mdblistConnected, _mdblistConnected (write) → _owners.settings.mdblistConnected, _searchController (read) → _owners.focus.searchController, _searchQuery (read) → _owners.focus.searchQuery, _searchQuery (write) → _owners.focus.searchQuery, _tvContentFocusHandler (write) → _owners.focus.tvContentFocusHandler, _searchBtnFocusNode (read) → _owners.focus.searchBtnFocusNode, _tvContentFocusHandler (read-write) → _owners.focus.tvContentFocusHandler, _pendingChannelId (write) → _owners.playback.pendingChannelId; live/lexical reads: mounted@150 unbound scope=member/block0/closure1/block0/if0, setState@151 unbound scope=member/block0/closure1/block0/if0/block0, setState@159 unbound scope=member/block0/closure2/block0/if0/block0, mounted@171 unbound scope=member/block0/closure4/block0/if0; same-name locals: none; 7 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState.dispose (188)` | `lib/screens/stremio_tv/stremio_tv_screen.dart:_StremioTvScreenState.dispose` | _contentRevision (read) → _owners.library.contentRevision, _searchBtnFocusNode (read) → _owners.focus.searchBtnFocusNode, _providerFocusNode (read) → _owners.focus.providerFocusNode, _menuFocusNode (read) → _owners.focus.menuFocusNode, _submenuFocusNode (read) → _owners.focus.submenuFocusNode, _searchController (read) → _owners.focus.searchController, _searchFocusNode (read) → _owners.focus.searchFocusNode, _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _tvContentFocusHandler (read) → _owners.focus.tvContentFocusHandler, _tvContentFocusHandler (read-write) → _owners.focus.tvContentFocusHandler; live/lexical reads: none; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._loadSettings (213)` | `presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart:StremioTvSettingsLoader.loadSettings` | _rotationMinutes (write) → _owners.settings.rotationMinutes, _seriesRotationMinutes (write) → _owners.settings.seriesRotationMinutes, _randomEpisodes (write) → _owners.settings.randomEpisodes, _autoRefresh (write) → _owners.settings.autoRefresh, _preferredQuality (write) → _owners.settings.preferredQuality, _availableProviders (write) → _owners.settings.availableProviders, _availableProviders (read) → _owners.settings.availableProviders, _debridProvider (write) → _owners.settings.debridProvider, _rdSkipBlockedTorrents (write) → _owners.settings.rdSkipBlockedTorrents, _torrentsFirst (write) → _owners.settings.torrentsFirst, _maxStartPercent (write) → _owners.settings.maxStartPercent, _hideNowPlaying (write) → _owners.settings.hideNowPlaying; live/lexical reads: none; same-name locals: debridProvider (decl:member/block0#debridProvider#0; scope=member/block0/if0), debridProvider (decl:member/block0#debridProvider#0; scope=member/block0/if0/closure0), debridProvider (decl:member/block0#debridProvider#0; scope=member/block0/if0/block1); 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._loadAvailableProviders (237)` | `presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart:StremioTvSettingsLoader._loadAvailableProviders` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._discoverAndLoad (264)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary.discoverAndLoad` | _loading (write) → _owners.library.loading, _service (read) → _owners.library.service, _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _channels (write) → _owners.library.channels, _pendingChannelId (read) → _owners.playback.pendingChannelId, _pendingChannelId (read-write) → _owners.playback.pendingChannelId, _pendingChannelId (write) → _owners.playback.pendingChannelId, _startupAutoPlayActive (write) → _owners.playback.startupAutoPlayActive; live/lexical reads: setState@265 unbound scope=member/block0, mounted@278 unbound scope=member/block0/if0, setState@279 unbound scope=member/block0/if0/block0, mounted@286 unbound scope=member/block0/if1, mounted@291 unbound scope=member/block0/if1/block0/if0; same-name locals: channels (decl:member/block0#channels#0; scope=member/block0/for1), channels (decl:member/block0#channels#0; scope=member/block0/if0/block0/closure0/block0); 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._notifyStartupAutoLaunchFailed (295)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary.notifyStartupAutoLaunchFailed` | _startupAutoPlayActive (read) → _owners.playback.startupAutoPlayActive, _startupAutoPlayActive (write) → _owners.playback.startupAutoPlayActive; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._notifyStartupPlayerLaunching (301)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary.notifyStartupPlayerLaunching` | _startupAutoPlayActive (read) → _owners.playback.startupAutoPlayActive, _startupAutoPlayActive (write) → _owners.playback.startupAutoPlayActive; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._refresh (307)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary.refresh` | _refreshing (read) → _owners.library.refreshing, _refreshing (write) → _owners.library.refreshing, _service (read) → _owners.library.service, _loadingChannelIds (read) → _owners.library.loadingChannelIds, _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _channels (write) → _owners.library.channels; live/lexical reads: setState@309 unbound scope=member/block0, mounted@329 unbound scope=member/block0/if1, setState@330 unbound scope=member/block0/if1/block0; same-name locals: channels (decl:member/block0#channels#0; scope=member/block0/for0), channels (decl:member/block0#channels#0; scope=member/block0/for2), channels (decl:member/block0#channels#0; scope=member/block0/if1/block0/closure0/block0); 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._sortedChannels (339)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary.sortedChannels` | no State-field dependencies; live/lexical reads: none; same-name locals: channels (decl:member#channels#0; scope=member/block0); 4 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._submenuItem (347)` | `presentation/legacy_stremio_tv/stremio_tv_chrome.dart:StremioTvChrome.submenuItem` | _submenuFocusNode (read) → _owners.focus.submenuFocusNode, _menuController (read) → _owners.focus.menuController, _menuFocusNode (read) → _owners.focus.menuFocusNode; live/lexical reads: none; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._topMenuItem (384)` | `presentation/legacy_stremio_tv/stremio_tv_chrome.dart:StremioTvChrome.topMenuItem` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._openChannelFilter (416)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.openChannelFilter` | _service (read) → _owners.library.service; live/lexical reads: mounted@419 unbound scope=member/block0/if0, context@424 unbound scope=member/block0, isTelevision@431 None scope=member/block0/closure0, mounted@436 unbound scope=member/block0/if1; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._openLocalCatalogs (441)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.openLocalCatalogs` | no State-field dependencies; live/lexical reads: context@442 unbound scope=member/block0, mounted@443 unbound scope=member/block0/if0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._importFromFile (448)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.importFromFile` | no State-field dependencies; live/lexical reads: context@449 unbound scope=member/block0, mounted@450 unbound scope=member/block0/if0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._importFromUrl (453)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.importFromUrl` | no State-field dependencies; live/lexical reads: context@454 unbound scope=member/block0, mounted@455 unbound scope=member/block0/if0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._importFromJson (458)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.importFromJson` | no State-field dependencies; live/lexical reads: context@459 unbound scope=member/block0, mounted@460 unbound scope=member/block0/if0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._importFromRepo (463)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.importFromRepo` | no State-field dependencies; live/lexical reads: context@464 unbound scope=member/block0, mounted@465 unbound scope=member/block0/if0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._importFromTrakt (468)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.importFromTrakt` | no State-field dependencies; live/lexical reads: context@470 unbound scope=member/block0, mounted@472 unbound scope=member/block0/if0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._importFromMdblist (475)` | `presentation/legacy_stremio_tv/stremio_tv_menu_actions.dart:StremioTvMenuActions.importFromMdblist` | no State-field dependencies; live/lexical reads: context@477 unbound scope=member/block0, mounted@479 unbound scope=member/block0/if0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._openStremioTvSettings (482)` | `presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart:StremioTvSettingsLoader.openStremioTvSettings` | no State-field dependencies; live/lexical reads: context@484 unbound scope=member/block0, mounted@486 unbound scope=member/block0/if0, mounted@488 unbound scope=member/block0/if1, setState@488 unbound scope=member/block0/if1; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._setDebridProvider (491)` | `presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart:StremioTvSettingsLoader.setDebridProvider` | _debridProvider (write) → _owners.settings.debridProvider; live/lexical reads: mounted@493 unbound scope=member/block0/if0, setState@494 unbound scope=member/block0; same-name locals: none; 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._providerShortLabel (497)` | `presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart:StremioTvSettingsLoader.providerShortLabel` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._providerFullLabel (514)` | `presentation/legacy_stremio_tv/stremio_tv_settings_loader.dart:StremioTvSettingsLoader.providerFullLabel` | _availableProviders (read) → _owners.settings.availableProviders; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._ensureChannelLoaded (536)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary._ensureChannelLoaded` | _channels (read) → _owners.library.channels; live/lexical reads: none; same-name locals: none; 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._ensureChannelItemsLoaded (543)` | `presentation/legacy_stremio_tv/stremio_tv_channel_library.dart:StremioTvChannelLibrary.ensureChannelItemsLoaded` | _loadingChannelIds (read) → _owners.library.loadingChannelIds, _service (read) → _owners.library.service, _channels (read) → _owners.library.channels, _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _searchFocusNode (read) → _owners.focus.searchFocusNode, _focusedIndex (write) → _owners.focus.focusedIndex, _focusedIndex (read) → _owners.focus.focusedIndex, _focusedIndex (read-write) → _owners.focus.focusedIndex, _contentRevision (read) → _owners.library.contentRevision; live/lexical reads: mounted@562 unbound scope=member/block0/if3, setState@566 unbound scope=member/block0/if4/block0; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._extractQuality (608)` | `application/stremio_tv_stream_quality.dart:StremioTvStreamQuality.extractQuality` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._tryDirectStreams (625)` | `presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart:StremioTvStreamSelection.tryDirectStreams` | _playGeneration (read) → _owners.playback.playGeneration; live/lexical reads: mounted@638 unbound scope=member/block0/for0/block0/if1, mounted@640 unbound scope=member/block0/for0/block0/if2; same-name locals: none; 3 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._tryTorrentsViaDebrid (652)` | `presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart:StremioTvStreamSelection.tryTorrentsViaDebrid` | _playGeneration (read) → _owners.playback.playGeneration, _debridProvider (read) → _owners.settings.debridProvider; live/lexical reads: mounted@668 unbound scope=member/block0/closure1/closure0, mounted@673 unbound scope=member/block0/for0/block0/if0, mounted@680 unbound scope=member/block0/for0/block0/closure0; same-name locals: none; 7 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._filterTorrentsForEpisode (701)` | `presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart:StremioTvStreamSelection.filterTorrentsForEpisode` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._sortStreamsByQuality (772)` | `presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart:StremioTvStreamSelection._sortStreamsByQuality` | _preferredQuality (read) → _owners.settings.preferredQuality; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._isValidStreamUrl (785)` | `presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart:StremioTvStreamSelection.isValidStreamUrl` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._tvProviderInfo (790)` | `presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart:StremioTvStreamSelection.tvProviderInfo` | _debridProvider (read) → _owners.settings.debridProvider; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._playChannel (841)` | `presentation/legacy_stremio_tv/stremio_tv_play_channel.dart:StremioTvPlayChannel.playChannel` | _playGeneration (read-write) → _owners.playback.playGeneration, _playGeneration (read) → _owners.playback.playGeneration, _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt, _currentSlotProgress (write) → _owners.playback.currentSlotProgress, _randomEpisodes (read) → _owners.settings.randomEpisodes, _currentPlayTitle (write) → _owners.playback.currentPlayTitle, _debridProvider (read) → _owners.settings.debridProvider, _preferredQuality (read) → _owners.settings.preferredQuality, _torrentsFirst (read) → _owners.settings.torrentsFirst, _currentPlayTitle (read) → _owners.playback.currentPlayTitle, _currentSlotProgress (read) → _owners.playback.currentSlotProgress, _rotationMinutes (read) → _owners.settings.rotationMinutes, _seriesRotationMinutes (read) → _owners.settings.seriesRotationMinutes; live/lexical reads: mounted@847 unbound scope=member/block0/if0/block0/if0, mounted@857 unbound scope=member/block0/if1/block0/if0, context@858 unbound scope=member/block0/if1/block0/if0/block0, mounted@873 unbound scope=member/block0/if2/block0/if0, context@874 unbound scope=member/block0/if2/block0/if0/block0, mounted@888 unbound scope=member/block0/if3, context@889 unbound scope=member/block0, context@892 unbound scope=member/block0, mounted@936 unbound scope=member/block0/if4/block0/if0, mounted@944 unbound scope=member/block0/if4/block0/if1/block0/if0, context@945 unbound scope=member/block0/if4/block0/if1/block0/if0/block0, mounted@975 unbound scope=member/block0/block0/if0, mounted@993 unbound scope=member/block0/block0/if1/block0/if0, context@994 unbound scope=member/block0/block0/if1/block0/if0/block0, mounted@1035 unbound scope=member/block0/block0/if3/block0/if0/block0/if0/block0/if0, mounted@1079 unbound scope=member/block0/block0/if4/block0/if0/block0/if0/block0/if0, mounted@1116 unbound scope=member/block0/block0/if5/block0/if0, context@1117 unbound scope=member/block0/block0/if5/block0/if0/block0, mounted@1167 unbound scope=member/block0/block0/if9/block0/if0, mounted@1175 unbound scope=member/block0/block0/if9/block0/if0/block0/if0, context@1183 unbound scope=member/block0/block0/if9/block0/if0/block0/if0/block0, mounted@1218 unbound scope=member/block0/block0/if10, context@1235 unbound scope=member/block0/block0, mounted@1265 unbound scope=member/block0/catch0/block0/if0, context@1267 unbound scope=member/block0/catch0/block0; same-name locals: none; 37 frozen outgoing callback arguments; delays/timeouts: Duration(seconds: 7), Duration(seconds: 10); REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._resolveChannelPlayback (1272)` | `presentation/legacy_stremio_tv/stremio_tv_channel_resolve.dart:StremioTvChannelResolve.resolveChannelPlayback` | _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt, _randomEpisodes (read) → _owners.settings.randomEpisodes, _debridProvider (read) → _owners.settings.debridProvider, _playGeneration (read) → _owners.playback.playGeneration, _torrentsFirst (read) → _owners.settings.torrentsFirst; live/lexical reads: none; same-name locals: none; 17 frozen outgoing callback arguments; delays/timeouts: Duration(seconds: 7); REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._showManualSourcePicker (1479)` | `presentation/legacy_stremio_tv/stremio_tv_channel_resolve.dart:StremioTvChannelResolve.showManualSourcePicker` | no State-field dependencies; live/lexical reads: context@1493 unbound scope=member/block0; same-name locals: none; 3 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._computeStartProgress (1504)` | `presentation/legacy_stremio_tv/stremio_tv_channel_resolve.dart:StremioTvChannelResolve.computeStartProgress` | _maxStartPercent (read) → _owners.settings.maxStartPercent; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._rememberPlaybackCursor (1517)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide.rememberPlaybackCursor` | _playbackCursors (read) → _owners.playback.playbackCursors; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._nextSlotOffsetFor (1528)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide._nextSlotOffsetFor` | _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt, _playbackCursors (read) → _owners.playback.playbackCursors; live/lexical reads: none; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._guideDataFor (1544)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide.guideDataFor` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._playbackResultToMap (1556)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide._playbackResultToMap` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._createSourceResolver (1580)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide.createSourceResolver` | _debridProvider (read) → _owners.settings.debridProvider; live/lexical reads: none; same-name locals: debridProvider (decl:member/block0#debridProvider#0; scope=member/block0/closure0/block0/if1/block0); 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._buildGuideChannelMetadata (1606)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide.buildGuideChannelMetadata` | _channels (read) → _owners.library.channels, _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt; live/lexical reads: none; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._createGuideDataProvider (1654)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide.createGuideDataProvider` | _channels (read) → _owners.library.channels, _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt; live/lexical reads: none; same-name locals: none; 3 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._createChannelSwitchProvider (1700)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide.createChannelSwitchProvider` | _channels (read) → _owners.library.channels; live/lexical reads: none; same-name locals: none; 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._createNextProvider (1717)` | `presentation/legacy_stremio_tv/stremio_tv_player_guide.dart:StremioTvPlayerGuide.createNextProvider` | _channels (read) → _owners.library.channels, _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt; live/lexical reads: none; same-name locals: none; 3 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._resolveTorrentUrl (1760)` | `presentation/legacy_stremio_tv/stremio_tv_debrid_resolvers.dart:StremioTvDebridResolvers.resolveTorrentUrl` | _rdSkipBlockedTorrents (read) → _owners.settings.rdSkipBlockedTorrents; live/lexical reads: none; same-name locals: debridProvider (decl:member#debridProvider#0; scope=member), debridProvider (decl:member#debridProvider#0; scope=member/closure0/block0/pattern1/if0); 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._loadTorboxCachedHashes (1849)` | `presentation/legacy_stremio_tv/stremio_tv_debrid_resolvers.dart:StremioTvDebridResolvers.loadTorboxCachedHashes` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 4 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._resolveViaRealDebrid (1889)` | `presentation/legacy_stremio_tv/stremio_tv_debrid_resolvers.dart:StremioTvDebridResolvers._resolveViaRealDebrid` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._resolveViaAllDebrid (1976)` | `presentation/legacy_stremio_tv/stremio_tv_debrid_resolvers.dart:StremioTvDebridResolvers._resolveViaAllDebrid` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 4 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._resolveViaTorbox (2050)` | `presentation/legacy_stremio_tv/stremio_tv_cloud_resolvers.dart:StremioTvCloudResolvers.resolveViaTorbox` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 6 frozen outgoing callback arguments; delays/timeouts: Duration(seconds: 3), .timeout(const Duration(seconds: 10); REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._resolveViaPikPak (2165)` | `presentation/legacy_stremio_tv/stremio_tv_cloud_resolvers.dart:StremioTvCloudResolvers.resolveViaPikPak` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._trashRejectedPikPakItem (2283)` | `presentation/legacy_stremio_tv/stremio_tv_cloud_resolvers.dart:StremioTvCloudResolvers._trashRejectedPikPakItem` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: .timeout(const Duration(seconds: 10); REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._resolveViaPremiumize (2296)` | `presentation/legacy_stremio_tv/stremio_tv_cloud_resolvers.dart:StremioTvCloudResolvers.resolveViaPremiumize` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 3 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._playChannelById (2347)` | `presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart:StremioTvChannelActions.playChannelById` | _channels (read) → _owners.library.channels, _startupAutoPlayActive (read) → _owners.playback.startupAutoPlayActive; live/lexical reads: none; same-name locals: none; 4 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._pushingChannelDetail (2368)` | `presentation/legacy_stremio_tv/stremio_tv_playback_state.dart:StremioTvPlaybackState.pushingChannelDetail` | initializer retained at State construction; no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._openChannelDetail (2370)` | `presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart:StremioTvChannelActions.openChannelDetail` | _pushingChannelDetail (read) → _owners.playback.pushingChannelDetail, _pushingChannelDetail (write) → _owners.playback.pushingChannelDetail; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._pushChannelDetail (2383)` | `presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart:StremioTvChannelActions._pushChannelDetail` | _loadingChannelIds (read) → _owners.library.loadingChannelIds, _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt; live/lexical reads: mounted@2392 unbound scope=member/block0/if0/block0, mounted@2399 unbound scope=member/block0/if0/block0/if0, mounted@2407 unbound scope=member/block0/if1/block0/if0, context@2408 unbound scope=member/block0/if1/block0/if0/block0, isTelevision@2416 None scope=member/block0, context@2421 unbound scope=member/block0; same-name locals: none; 6 frozen outgoing callback arguments; delays/timeouts: Duration(milliseconds: 120); REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._showGuide (2434)` | `presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart:StremioTvChannelActions.showGuide` | _service (read) → _owners.library.service, _mixSalt (read) → _owners.library.mixSalt; live/lexical reads: mounted@2437 unbound scope=member/block0/if0/block0/if0, mounted@2440 unbound scope=member/block0/if1/block0/if0, context@2441 unbound scope=member/block0/if1/block0/if0/block0, mounted@2454 unbound scope=member/block0/if2, context@2457 unbound scope=member/block0, mounted@2462 unbound scope=member/block0/if3; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._toggleFavorite (2471)` | `presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart:StremioTvChannelActions.toggleFavorite` | _channels (read) → _owners.library.channels, _channels (write) → _owners.library.channels, _rowFocusNodes (read) → _owners.focus.rowFocusNodes; live/lexical reads: mounted@2475 unbound scope=member/block0/if0, setState@2477 unbound scope=member/block0, mounted@2484 unbound scope=member/block0/if1/block0/closure0/block0/if0; same-name locals: none; 2 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._copyLocalCatalogJson (2495)` | `presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart:StremioTvChannelActions.copyLocalCatalogJson` | no State-field dependencies; live/lexical reads: mounted@2500 unbound scope=member/block0/if0, context@2502 unbound scope=member/block0/if1/block0, mounted@2512 unbound scope=member/block0/if2, context@2513 unbound scope=member/block0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._editLocalCatalog (2521)` | `presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart:StremioTvChannelActions.editLocalCatalog` | _focusedIndex (read) → _owners.focus.focusedIndex, _channels (read) → _owners.library.channels, _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _focusedIndex (write) → _owners.focus.focusedIndex, _searchBtnFocusNode (read) → _owners.focus.searchBtnFocusNode; live/lexical reads: context@2530 unbound scope=member/block0, mounted@2534 unbound scope=member/block0/if0, mounted@2537 unbound scope=member/block0/if1, mounted@2540 unbound scope=member/block0/closure1/block0/if0, setState@2546 unbound scope=member/block0/closure1/block0/function0/closure0/block0/if0/block0; same-name locals: none; 6 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._filteredChannels (2585)` | `presentation/legacy_stremio_tv/stremio_tv_navigation.dart:StremioTvNavigation.filteredChannels` | _searchQuery (read) → _owners.focus.searchQuery, _channels (read) → _owners.library.channels; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._currentFocusedChannelId (2598)` | `presentation/legacy_stremio_tv/stremio_tv_navigation.dart:StremioTvNavigation.currentFocusedChannelId` | _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _channels (read) → _owners.library.channels, _focusedIndex (read) → _owners.focus.focusedIndex; live/lexical reads: none; same-name locals: none; 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._focusDialFromHeader (2609)` | `presentation/legacy_stremio_tv/stremio_tv_navigation.dart:StremioTvNavigation.focusDialFromHeader` | _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _focusedIndex (read) → _owners.focus.focusedIndex, _channels (read) → _owners.library.channels, _tunerController (read) → _owners.focus.tunerController; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._reorderRowFocusNodes (2638)` | `presentation/legacy_stremio_tv/stremio_tv_navigation.dart:StremioTvNavigation.reorderRowFocusNodes` | _rowFocusNodes (read) → _owners.focus.rowFocusNodes; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._handleSearchBarBack (2667)` | `presentation/legacy_stremio_tv/stremio_tv_navigation.dart:StremioTvNavigation.handleSearchBarBack` | _searchController (read) → _owners.focus.searchController, _showSearchField (read) → _owners.focus.showSearchField, _showSearchField (write) → _owners.focus.showSearchField, _searchBtnFocusNode (read) → _owners.focus.searchBtnFocusNode; live/lexical reads: setState@2681 unbound scope=member/block0/if1/block0/if1/block0; same-name locals: none; 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState.build (2694)` | `presentation/legacy_stremio_tv/stremio_tv_layout.dart:StremioTvLayout.build` | _loading (read) → _owners.library.loading, _showSearchField (read) → _owners.focus.showSearchField, _searchController (read) → _owners.focus.searchController, _searchFocusNode (read) → _owners.focus.searchFocusNode, _searchBtnFocusNode (read) → _owners.focus.searchBtnFocusNode, _searchQuery (read) → _owners.focus.searchQuery, _showSearchField (write) → _owners.focus.showSearchField, _menuFocusNode (read) → _owners.focus.menuFocusNode, _menuController (read) → _owners.focus.menuController, _availableProviders (read) → _owners.settings.availableProviders, _providerFocusNode (read) → _owners.focus.providerFocusNode, _mixSalt (write) → _owners.library.mixSalt, _mixSalt (read) → _owners.library.mixSalt, _refreshing (read) → _owners.library.refreshing, _submenuFocusNode (read) → _owners.focus.submenuFocusNode, _mdblistConnected (read) → _owners.settings.mdblistConnected, _providerMenuController (read) → _owners.focus.providerMenuController, _debridProvider (read) → _owners.settings.debridProvider, _channels (read) → _owners.library.channels, _contentRevision (read) → _owners.library.contentRevision, _tunerController (read) → _owners.focus.tunerController, _rowFocusNodes (read) → _owners.focus.rowFocusNodes, _service (read) → _owners.library.service, _hideNowPlaying (read) → _owners.settings.hideNowPlaying, _autoRefresh (read) → _owners.settings.autoRefresh, _loadingChannelIds (read) → _owners.library.loadingChannelIds, _maxStartPercent (read) → _owners.settings.maxStartPercent, _focusedIndex (write) → _owners.focus.focusedIndex; live/lexical reads: context@2696 decl:member#context#0 scope=member/block0, context@2697 decl:member#context#0 scope=member/block0, setState@2783 unbound scope=member/block0/closure5/block0, setState@2855 unbound scope=member/block0/closure6/block0/if5/block0, setState@2870 unbound scope=member/block0/closure7/block0, setState@2964 unbound scope=member/block0/closure10/closure0/block0, isTelevision@3219 None scope=member/block0/closure11/block0/closure0/block0; same-name locals: none; 107 frozen outgoing callback arguments; delays/timeouts: Duration(milliseconds: 200); REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._headerButton (3268)` | `presentation/legacy_stremio_tv/stremio_tv_chrome.dart:StremioTvChrome.headerButton` | no State-field dependencies; live/lexical reads: context@3275 unbound scope=member/block0; same-name locals: none; 1 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvScreenState._buildLoadingSkeleton (3300)` | `presentation/legacy_stremio_tv/stremio_tv_chrome.dart:StremioTvChrome.buildLoadingSkeleton` | no State-field dependencies; live/lexical reads: context@3301 unbound scope=member/block0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_ManualSourcePickerSheet (3387)` | `presentation/stremio_tv_manual_source_picker.dart:_ManualSourcePickerSheet` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_ManualSourcePickerSheetState (3403)` | `presentation/stremio_tv_manual_source_picker.dart:_ManualSourcePickerSheetState` | no State-field dependencies; live/lexical reads: context@3451 unbound scope=member/method4/block0, setState@3469 unbound scope=member/method5/block0, mounted@3476 unbound scope=member/method5/block0/block0/if0, mounted@3481 unbound scope=member/method5/block0/block0/if1/block0/if0/block0/if0, setState@3483 unbound scope=member/method5/block0/block0/if1/block0/if0/block0/if1/block0, context@3491 unbound scope=member/method5/block0/block0/if1/block0, setState@3494 unbound scope=member/method5/block0/block0/if1/block1, mounted@3500 unbound scope=member/method5/block0/catch0/block0/if0, setState@3501 unbound scope=member/method5/block0/catch0/block0, setState@3520 unbound scope=member/method6/block0/closure0/block0, mounted@3523 unbound scope=member/method6/block0/closure0/block0/closure1/block0/if0, context@3532 decl:member/method7#context#0 scope=member/method7/block0, context@3537 decl:member/method7#context#0 scope=member/method7/block0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_SourcePickerTab (3660)` | `presentation/stremio_tv_source_picker_controls.dart:_SourcePickerTab` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_SourcePickerTabState (3680)` | `presentation/stremio_tv_source_picker_controls.dart:_SourcePickerTabState` | no State-field dependencies; live/lexical reads: context@3701 decl:member/method1#context#0 scope=member/method1/block0, setState@3704 unbound scope=member/method1/block0/closure0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_SourcePickerItem (3740)` | `presentation/stremio_tv_source_picker_controls.dart:_SourcePickerItem` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_SourcePickerItemState (3770)` | `presentation/stremio_tv_source_picker_controls.dart:_SourcePickerItemState` | no State-field dependencies; live/lexical reads: context@3798 unbound scope=member/method2/block0/if3/block0, context@3806 decl:member/method3#context#0 scope=member/method3/block0, setState@3810 unbound scope=member/method3/block0/closure0; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_ChannelPlaybackResult (3908)` | `models/stremio_tv_playback_records.dart:StremioTvChannelPlaybackResult` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_ResolvedSourceChoice (3943)` | `models/stremio_tv_playback_records.dart:StremioTvResolvedSourceChoice` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |
| `_StremioTvPlaybackCursor (3950)` | `models/stremio_tv_playback_records.dart:StremioTvPlaybackCursor` | no State-field dependencies; live/lexical reads: none; same-name locals: none; 0 frozen outgoing callback arguments; delays/timeouts: none; REVIEWED: owner, callers, callback identity and lifetime. |

## Free comment leaves

Free comments are not declarations in the analyzer adapter. Each is assigned to the next declaration (or its owning declaration for trailing text), with the Channel Detail banner explicitly owned by `openChannelDetail`, as required by the plan. The feature contracts freeze text/count/location; no adapter change is needed.

| R line | Text | Destination anchor |
| --- | --- | --- |
| 86 | `// -1 = no limit (slot progress), 0 = beginning` | `_StremioTvScreenState._maxStartPercent → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_settings_state.dart` |
| 90 | `// Overrides item.name when playing series episodes` | `_StremioTvScreenState._currentPlayTitle → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_playback_state.dart` |
| 113 | `// Mix salt (0-9, cycles on shuffle button)` | `_StremioTvScreenState._mixSalt → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_library_state.dart` |
| 116 | `// Header buttons` | `_StremioTvScreenState._searchBtnFocusNode → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_focus_state.dart` |
| 124 | `// Search` | `_StremioTvScreenState._searchController → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_focus_state.dart` |
| 129 | `// Whether MDBList is connected — gates the "Import → From MDBList" entry so` | `_StremioTvScreenState._mdblistConnected → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_settings_state.dart` |
| 130 | `// an unauthed user isn't offered a dead import (MDBList is also hidden from` | `_StremioTvScreenState._mdblistConnected → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_settings_state.dart` |
| 131 | `// Settings for the alpha).` | `_StremioTvScreenState._mdblistConnected → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_settings_state.dart` |
| 134 | `// Lazy loading: track channels currently being fetched to avoid duplicates` | `_StremioTvScreenState._loadingChannelIds → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_library_state.dart` |
| 137 | `// Track mounted state for auto-play` | `_StremioTvScreenState._pendingChannelId → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_playback_state.dart` |
| 141 | `// TV content focus handler (stored for proper unregistration)` | `_StremioTvScreenState._tvContentFocusHandler → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_focus_state.dart` |
| 532 | `// ============================================================================` | `_StremioTvScreenState._ensureChannelLoaded → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_library.dart` |
| 533 | `// Lazy Loading` | `_StremioTvScreenState._ensureChannelLoaded → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_library.dart` |
| 534 | `// ============================================================================` | `_StremioTvScreenState._ensureChannelLoaded → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_library.dart` |
| 604 | `// ============================================================================` | `_StremioTvScreenState._tryDirectStreams → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart` |
| 605 | `// Playback` | `_StremioTvScreenState._tryDirectStreams → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart` |
| 606 | `// ============================================================================` | `_StremioTvScreenState._tryDirectStreams → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_stream_selection.dart` |
| 1578 | `// ─── Source Resolution (no dialogs, returns URL) ────────────────────` | `_StremioTvScreenState._createSourceResolver → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_player_guide.dart` |
| 1604 | `// ─── Stremio TV In-Player Guide ─────────────────────────────────────` | `_StremioTvScreenState._buildGuideChannelMetadata → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_player_guide.dart` |
| 2364 | `// ============================================================================` | `_StremioTvScreenState._openChannelDetail → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2365 | `// Channel Detail (cinematic "tune-in")` | `_StremioTvScreenState._openChannelDetail → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2366 | `// ============================================================================` | `_StremioTvScreenState._openChannelDetail → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2430 | `// ============================================================================` | `_StremioTvScreenState._showGuide → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2431 | `// Channel Guide` | `_StremioTvScreenState._showGuide → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2432 | `// ============================================================================` | `_StremioTvScreenState._showGuide → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2467 | `// ============================================================================` | `_StremioTvScreenState._toggleFavorite → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2468 | `// Favorites` | `_StremioTvScreenState._toggleFavorite → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2469 | `// ============================================================================` | `_StremioTvScreenState._toggleFavorite → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_channel_actions.dart` |
| 2581 | `// ============================================================================` | `_StremioTvScreenState._filteredChannels → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_navigation.dart` |
| 2582 | `// Search` | `_StremioTvScreenState._filteredChannels → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_navigation.dart` |
| 2583 | `// ============================================================================` | `_StremioTvScreenState._filteredChannels → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_navigation.dart` |
| 2690 | `// ============================================================================` | `_StremioTvScreenState.build → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_layout.dart` |
| 2691 | `// Build` | `_StremioTvScreenState.build → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_layout.dart` |
| 2692 | `// ============================================================================` | `_StremioTvScreenState.build → lib/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_layout.dart` |
| 3385 | `// ─── Manual Source Picker (shown when auto-play fails) ────────────────────` | `_ManualSourcePickerSheet → lib/features/stremio_tv/presentation/stremio_tv_manual_source_picker.dart` |

## Frozen outgoing callbacks

Every recorded argument is in `dev/tool/stremio_tv_callback_sites.json`; whole enclosing bodies also remain verbatim. The explicit identities include the stored tab-9 closure at register/unregister and all direct external tear-offs. The raw inventory contains 259 arguments, including nested widget/builder closures.

## Design facts inventory (verbatim historical copy)

The following inventory uses unformatted line numbers at `0cb50df7`. R was verified against it; the table above supplies formatted R ownership and scope evidence.

# Stremio TV screen — facts inventory (Claude, 2026-10-06)

Source: `lib/screens/stremio_tv/stremio_tv_screen.dart` at `refactor/codebase`
`0cb50df7` (worktree `../debrify-wt/stremio-tv`, branch `refactor/stremio-tv`).
Line numbers are UNFORMATTED (the file is NOT dart-format clean: `dart format
--set-exit-if-changed` → 1 changed). Verify everything; do not trust.

## Size and shape
- 3,957 lines, 50 import directives (lines 1–51, mixed package/relative,
  unsorted), no `part`.
- Top-level declarations (11): `StremioTvScreen` (58–69, public, field
  `isTelevision`, doc comment), `_StremioTvScreenState` (71–3382),
  `_ManualSourcePickerSheet` (3386–3400) + State (3402–3655), `_SourcePickerTab`
  (3658–3675) + State (3677–3737), `_SourcePickerItem` (3740–3767) + State
  (3769–3905), `_ChannelPlaybackResult` (3908–3940), `_ResolvedSourceChoice`
  (3942–3947), `_StremioTvPlaybackCursor` (3949–3957). Banner comment
  `// ─── Manual Source Picker (shown when auto-play fails) ───` at 3384.
- `analysis_options.yaml` (root) on the file: 0 issues. Strict features config
  not yet probed.
- 13 `app.shape.br(` tokens: build 3 (2791, 2795, 2799), `_headerButton` 1
  (3284), `_buildLoadingSkeleton` 5 (3309, 3324, 3333, 3342, 3367), picker sheet
  1 (3552), tab 1 (3713), item 2 (3820, 3835). Plus one bare
  `BorderRadius.vertical(top: Radius.circular(20))` at 3540 inside a `const
  BoxDecoration` (check the shape regex). `test/theme/shape_manifest_test.dart:201`
  has the file in `kShapeResidue` at 0.
- Theme: `dev/tool/theme_surface_manifest.txt:23` `p2_stremio_tv =
  lib/screens/stremio_tv/*.dart` (widgets/ subdir NOT included);
  `dev/tool/theme_rendered_set.py:29` root `stremio_tv` = this file.
- `dev/tool/file_size_baseline.txt:15` `3957 …stremio_tv_screen.dart`.

## State fields (40) — declaration order
72 `final StremioTvService _service = StremioTvService.instance;`
74 `_channels` `List<StremioTvChannel>` = []
75 `_loading` = true; 76 `_refreshing` = false
77 `_rotationMinutes` = 90; 78 `_seriesRotationMinutes` = 45
79 `_randomEpisodes` = false; 80 `_autoRefresh` = true
81 `_preferredQuality` = 'auto'; 82 `_debridProvider` = 'auto'
83 `_rdSkipBlockedTorrents` = false; 84 `_torrentsFirst` = true
85 `_availableProviders` `List<MapEntry<String,String>>` = []
86 `_maxStartPercent` = -1 (trailing comment); 87 `_hideNowPlaying` = false
88 `double? _currentSlotProgress`; 89 `_playGeneration` = 0
90 `String? _currentPlayTitle` (trailing comment)
91 `final Map<String, _StremioTvPlaybackCursor> _playbackCursors = {}`
(93–95 method `_rotationFor`, doc comment, expression body — between fields)
97 `final List<FocusNode> _rowFocusNodes = []`; 98 `_focusedIndex` = 0
100–104 doc + `final StremioTvTunerController _tunerController = StremioTvTunerController();` (never disposed)
106–111 doc + `final ValueNotifier<int> _contentRevision = ValueNotifier<int>(0);`
113–114 comment + `_mixSalt` = 0
116–122 comment + 4 FocusNodes (debugLabels searchBtn, providerBtn, menuBtn,
  localCatalogs), 2 `MenuController`s (provider, menu)
124–128 comment + `_searchController` (TextEditingController), `_searchFocusNode`
  (FocusNode()), `_searchQuery` = '', `_showSearchField` = false
129–132 comment + `_mdblistConnected` = false
134–135 comment + `final Set<String> _loadingChannelIds = {}`
137–139 comment + `String? _pendingChannelId`, `_startupAutoPlayActive` = false
141–142 comment + `VoidCallback? _tvContentFocusHandler`
2364–2368 banner `// Channel Detail (cinematic "tune-in")` then
  `bool _pushingChannelDetail = false;` (mid-class field)
Getter: 2587 `List<StremioTvChannel> get _filteredChannels` (under `// Search` banner 2583–2585).

## Lifecycle
- `initState` 145–186: super → `AnalyticsService.screenView('stremio_tv')` →
  `_loadSettings().then((_) => _discoverAndLoad())` (unawaited) →
  `MdblistService.instance.isAuthenticated().then(v → if mounted && v != _mdblistConnected setState)` →
  `_searchController.addListener(closure: lowercased trimmed text → setState _searchQuery)` (never removed) →
  `_tvContentFocusHandler = () { _searchBtnFocusNode.requestFocus(); }` →
  `MainPageBridge.registerTvContentFocusHandler(9, _tvContentFocusHandler!)` →
  `MainPageBridge.watchStremioTvChannel = (channelId) async { if (mounted) { _playChannelById(channelId); } }` →
  `final pending = MainPageBridge.getAndClearStremioTvChannelToAutoPlay(); if (pending != null) _pendingChannelId = pending;` →
  trailing comment (no periodic refresh).
- `dispose` 189–211: `_contentRevision.dispose()` → `_searchBtnFocusNode`,
  `_providerFocusNode`, `_menuFocusNode`, `_submenuFocusNode` dispose →
  `_searchController.dispose()` → `_searchFocusNode.dispose()` → every row node
  dispose → `if (MainPageBridge.watchStremioTvChannel != null) { … = null; }`
  (comment "Only clear if we're the active handler" — the check does not test
  identity) → `if (_tvContentFocusHandler != null) unregisterTvContentFocusHandler(9, handler)`
  → `super.dispose()`. Tuner controller and menu controllers not disposed.
- No `didUpdateWidget`, `didChangeDependencies`, ticker, timer field,
  subscription, `RouteAware` or mixin.

## Methods (State) with ranges
213 `_loadSettings` (9 awaited reads + available providers + conditional
  `setStremioTvDebridProvider('auto')`; writes fields WITHOUT setState; local
  `debridProvider`)
237 `_loadAvailableProviders` (5 provider checks, locals rdKey/tbKey/…)
264 `_discoverAndLoad` (setState loading=true WITHOUT mounted check; await
  discoverChannels; disposes/recreates row nodes with no mounted check; mounted
  setState; pending auto-play: `_startupAutoPlayActive = true`,
  `_ensureChannelLoaded`, `_playChannelById`) — local `channels`
295 `_notifyStartupAutoLaunchFailed(reason)`, 301 `_notifyStartupPlayerLaunching()`
307 `_refresh` (guard `_refreshing`; setState; await `_loadSettings`; discover;
  clear loading ids; `lastFetched = null`; row nodes reset with no mounted check;
  mounted setState else `_refreshing = false`) — local `channels`
339 `_sortedChannels(List channels)` (param named `channels`)
347–382 doc + `_submenuItem` (Focus canRequestFocus false; Left/Right →
  `_submenuFocusNode`; Esc/Back → `_menuController.close()` + `_menuFocusNode`)
384 `_topMenuItem` (params controller/anchorFocusNode/closeOnArrowUp)
416 `_openChannelFilter` (getFilterTree, disabled filters, mounted, instant
  PageRouteBuilder push of `StremioTvFilterPage(isTelevision: widget.isTelevision)`, refresh on change)
441 `_openLocalCatalogs`, 448/453/458/463/468/475 six `_importFrom*`
  (StremioTvLocalCatalogsDialog statics with State context; refresh)
482 `_openStremioTvSettings` (MaterialPageRoute push of const settings page;
  reload settings; setState)
491 `_setDebridProvider` (persist, mounted, setState)
497 `_providerShortLabel`, 514 `_providerFullLabel` (reads `_availableProviders`)
532–534 banner `// Lazy Loading`
537 `_ensureChannelLoaded`, 546 `_ensureChannelItemsLoaded` (dedupe via
  `_loadingChannelIds`; try/catch/finally; removal of empty channel inside
  setState with focus rescue; else `_contentRevision.value++`)
604–606 banner `// Playback`
610 `static String? _extractQuality(String)` (doc 608–609)
625–653 doc (misplaced: describes sorting) + `_tryDirectStreams(sources, myGeneration)`
654 `_tryTorrentsViaDebrid(sources, item, myGeneration, {season, episode})`
  (memoized auto TorBox cache hashes; isCancelled closures read mounted +
  `_playGeneration`)
709–777 doc + `_filterTorrentsForEpisode` (pure)
779 `_sortStreamsByQuality`; 792–795 doc + `_isValidStreamUrl` (expression)
797–845 doc + `_tvProviderInfo()` (record return)
847–1268 **`_playChannel` (422 lines)**: generation bump; lazy load; now
  playing; start progress; valid id; `PipelineLoadingOverlay.show(context, …,
  onCancel: closure bumps _playGeneration + notify failed)`; series random
  episode; `TorrentService.searchByImdbWithStremio(… includeMediaServers:
  false, stremioTimeout 7s, engineTimeout 10s)`; filters; TorBox/Premiumize
  cache filters; torrents-first ordering; manual picker fallback push (P1) or
  auto push (P2); catch → snackbar.
1270–1467 doc + `_resolveChannelPlayback(channel, {slotOffset = 0})` (no UI;
  `searchByImdbWithStremio(… includeMediaServers: false, stremioTimeout 7s)`,
  NO engineTimeout; `gen = _playGeneration` snapshot)
1469–1492 doc + `_showManualSourcePicker` (showModalBottomSheet with
  `_ManualSourcePickerSheet(validateDirectUrl: _isValidStreamUrl)` tear-off)
1494–1505 doc + `_computeStartProgress` (pure on `_maxStartPercent`)
1507 `_rememberPlaybackCursor`, 1518 `_nextSlotOffsetFor`, 1534
  `_guideDataFor`, 1546 `_playbackResultToMap`
1568 banner `// ─── Source Resolution (no dialogs, returns URL) ───`
1570–1592 doc + `_createSourceResolver` (snapshots `_debridProvider` into
  local `debridProvider`)
1594 banner `// ─── Stremio TV In-Player Guide ───`
1596–1642 `_buildGuideChannelMetadata`, 1644–1688 `_createGuideDataProvider`,
1690–1705 `_createChannelSwitchProvider`, 1707–1751 `_createNextProvider` (doc)
1753–1844 doc + `_resolveTorrentUrl` (expression body →
  `StremioTvDebridFallback.resolve<String>` with `canAttempt`/`attempt` closures;
  params `debridProvider`, `isCancelled`, `loadAutoTorboxCachedHashes`)
1846 `_loadTorboxCachedHashes`, 1888 `_resolveViaRealDebrid`, 1975–2044 doc +
  `_resolveViaAllDebrid`, 2046 `_resolveViaTorbox` (3 s delay; finally delete
  with 10 s timeout), 2161 `_resolveViaPikPak` (finally trash),
  2279 `_trashRejectedPikPakItem` (10 s timeout), 2296 `_resolveViaPremiumize`
2347 `_playChannelById`
2364–2368 banner + `_pushingChannelDetail` field; 2370–2381 doc +
  `_openChannelDetail` (re-entrancy flag, try/finally)
2383 `_pushChannelDetail` (120 ms poll up to 8000 ms; `CatalogItemDetailScreen(
  item, isTelevision: widget.isTelevision, onPlay/onBrowse: () => _playChannel(channel),
  enablePrimarySourcesHold: false)`; instant PageRouteBuilder push)
2432–2434 banner `// Channel Guide`; 2436 `_showGuide` (StremioTvGuideSheet.show; plays on tap)
2469–2471 banner `// Favorites`; 2473 `_toggleFavorite` (persist; mounted;
  setState with `_reorderRowFocusNodes`; post-frame focus restore)
2497 `_copyLocalCatalogJson` (LocalCatalogExporter.loadCatalog; Clipboard; snackbars)
2523 `_editLocalCatalog` (StremioTvLocalCatalogEditorDialog.show; refresh;
  post-frame local function `focusChannelById` that calls setState)
2583–2585 banner `// Search`; 2587 `_filteredChannels` getter (local `q`)
2600 `_currentFocusedChannelId`, 2611–2638 doc + `_focusDialFromHeader`
  (`_tunerController.focusRealIndex` first, fallback requestFocus),
2640 `_reorderRowFocusNodes`, 2669–2690 doc + `_handleSearchBarBack`
2692–2694 banner `// Build`; **2696–3260 `build` (565 lines)**: Scaffold →
  Container(wash) → `_loading ? _buildLoadingSkeleton() : Column(header,
  Expanded(Builder → ValueListenableBuilder(_contentRevision) → StremioTvTuner(…)))`.
  Header: AnimatedSize search field (Focus onKeyEvent `_handleSearchBarBack`
  tear-off, TvTextField with arrow callbacks, clear button setState), Row with
  search button Focus (Left → `MainPageBridge.focusTvSidebar?.call()`), menu
  `MenuAnchor` (Shuffle `_topMenuItem` autofocus, Refresh, Filter, Settings
  tear-off `_openStremioTvSettings`, Import `SubmenuButton` with 6–7
  `_submenuItem`s, MDBList gated on `kMdblistEnabled && _mdblistConnected`),
  provider `MenuAnchor` (only when providers exist). Lexical contexts:
  `build(context)`, `ListenableBuilder` builders (context, _)/(context, child),
  `MenuAnchor.builder (context, controller, child)` ×2, `Builder(builder:
  (context))`, `ValueListenableBuilder (context, _, __)`.
3262 `_headerButton` (State context), 3298 `_buildLoadingSkeleton` (State
  context), 3381–3382 trailing blank + `}`.

## Playback handoff sites (frozen ledger material)
P1 manual-picker push 1180–1207 and P2 auto push 1232–1259: both
`await VideoPlayerLauncher.push(context, VideoPlayerLaunchArgs(` with 19 named
args in this order: `videoUrl` (P1 `result.url`, P2 `firstPlayableUrl`),
`title: _currentPlayTitle ?? item.name`, `startAtPercent: _currentSlotProgress`,
`contentImdbId: item.effectiveImdbId`, `contentTitle: item.name`,
`contentType: item.type`, `contentSeason: season`, `contentEpisode: episode`,
`stremioSources: playableSources`, `stremioCurrentSourceIndex` (P1
`result.sourceIndex`, P2 `firstPlayableIndex`), `resolveStremioSource:
_createSourceResolver(item, season: season, episode: episode)`,
`stremioTvChannels: _buildGuideChannelMetadata()`, `stremioTvCurrentChannelId:
channel.id`, `stremioTvRotationMinutes: _rotationMinutes`,
`stremioTvSeriesRotationMinutes: _seriesRotationMinutes`, `stremioTvMixSalt:
_mixSalt`, `stremioTvGuideDataProvider: _createGuideDataProvider()`,
`stremioTvChannelSwitchProvider: _createChannelSwitchProvider()`,
`stremioTvNextProvider: _createNextProvider()`. No push options
(`onPlayerHandoff` etc.) are passed.
Order before P2: generation/mounted gate (1216) → `overlay.setStage(starting)` →
`overlay.dismiss()` → `_notifyStartupPlayerLaunching()` →
`_rememberPlaybackCursor(channel.id, baseSlotStartMs: nowPlaying.slotStart…, slotOffset: 0)` → push.
Order before P1: `overlay.dismiss()` → `_notifyStartupAutoLaunchFailed('No auto-play stream resolved')`
→ `if (mounted && _playGeneration == myGeneration)` → `await _showManualSourcePicker(…)`
→ `if (result != null && mounted)` (NO generation re-check) → notify launching →
remember cursor → push → `return`.
Other player-facing contracts: `_playbackResultToMap` keys (`channelId`, `url`,
`title`, `contentType`, `contentImdbId`, conditional `contentSeason`,
`contentEpisode`, `startAtPercent`, `stremioSources` (toJson list),
`stremioCurrentSourceIndex`, `sourceResolver`, `nowPlaying`, conditional
`nextUp`); `_guideDataFor` 7 keys; `_buildGuideChannelMetadata` 5 base keys +
`nowPlaying` (7) / `nextUp` (5); guide data provider map; `_ChannelPlaybackResult`
14 fields.

## Cancellation (`_playGeneration`, 15 occurrences)
89 decl; 638, 640 (`_tryDirectStreams`); 675, 680, 688 (`_tryTorrentsViaDebrid`);
848 `final myGeneration = ++_playGeneration;`; 853; 923 (comment); 924
`_playGeneration++` in onCancel; 942, 981, 1165 (`==`), 1216; 1424 `final gen =
_playGeneration;` (`_resolveChannelPlayback`). `isCancelled` 18 occurrences in
resolvers. Not checked: after TorBox/Premiumize cache awaits in `_playChannel`
(only `mounted` before them), after `_showManualSourcePicker`, anywhere in
`_resolveChannelPlayback` after the snapshot except through the try* helpers.

## External hooks
MainPageBridge: `registerTvContentFocusHandler(9)`/unregister (stored closure);
`watchStremioTvChannel` set/cleared; `getAndClearStremioTvChannelToAutoPlay`;
`notifyAutoLaunchFailed` (via `_notifyStartupAutoLaunchFailed`, 11 call sites:
862, 878, 925, 949, 998, 1121, 1163, 1262, 2349, 2354 + definition);
`notifyPlayerLaunching` (via `_notifyStartupPlayerLaunching`, 1174, 1224);
`focusTvSidebar?.call()` at 2757, 2839, 3240.
Callers: `lib/features/home/presentation/home_hero_shell_bridge.dart:165–169`
(mounted → `watchStremioTvChannel!(id)`, else
`notifyStremioTvChannelToAutoPlay(id)`); `lib/main.dart:61` import, 1549
`const StremioTvScreen()`, 3264 `StremioTvScreen(isTelevision: _isAndroidTv)`.

## Timers/delays
TorBox 3 s settle (2073); TorBox delete timeout 10 s (2150); PikPak trash
timeout 10 s (2288); 120 ms poll ×≤8000 ms (2396); search timeouts 7 s/10 s;
AnimatedSize 200 ms. No Timer objects.

## Tests / tooling that read the file
- `test/media_server_service_test.dart:1268–1279` reads the file text, regex
  `searchByImdbWithStremio\([\s\S]*?\);` → exactly 2 matches, each containing
  `includeMediaServers: false`.
- `test/theme/source_guard_test.dart:130` frozen tab roots map (class still in
  facade → unchanged).
- `test/theme/shape_manifest_test.dart:201` `kShapeResidue` entry 0.
- No existing characterization/widget test mounts `StremioTvScreen`.
- `test/stremio_tv_debrid_fallback_test.dart` covers `StremioTvDebridFallback`.

## Sibling coupling
The screen imports and constructs `StremioTvTuner`/`StremioTvTunerController`
(widgets/stremio_tv_tuner.dart) and `StremioTvLocalCatalogsDialog`,
`StremioTvLocalCatalogEditorDialog`, `LocalCatalogExporter`
(widgets/stremio_tv_local_catalogs_dialog.dart). Two sibling forks refactor
those files concurrently (features `stremio_tv_tuner`, `stremio_tv_catalogs`);
their original paths stay as facades. This branch never edits them.

## Existing feature folder
`lib/features/stremio_tv/` already exists (catalog picker: application/,
data/, models/, presentation/ — `stremio_tv_catalog_picker_dialog.dart` is 618
lines); `stremio_tv` is already in `FEATURES`. New code goes under
`lib/features/stremio_tv/presentation/legacy_stremio_tv/` (+ one models file,
one application file); size/import rules must be scoped to the new files, not
the existing catalog-picker files.

## Found, not fixed (candidates)
1. `_discoverAndLoad` calls `setState(loading = true)` without a `mounted`
   check (from `_loadSettings().then`), and disposes/recreates row nodes after
   the await without a `mounted` check (double dispose after unmount).
2. `_refresh` likewise disposes row nodes after awaits without `mounted`.
3. `dispose` nulls `watchStremioTvChannel` whenever it is non-null (not identity).
4. P1 (manual picker) does not re-check `_playGeneration` after the picker returns.
5. `_playChannel` TorBox/Premiumize cache-check awaits are not generation-checked
   (only `mounted` before them); a cancelled play continues those requests.
6. `_resolveChannelPlayback` omits `engineTimeout` (P2 path passes 10 s).
7. `_tryDirectStreams` doc comment describes sorting (misplaced doc).
8. `_loadSettings` writes state fields without `setState` (callers rebuild later).
