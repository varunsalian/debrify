# IPTV settings two-pane — dependency report

Companion to [iptv-settings-two-pane-plan.md](iptv-settings-two-pane-plan.md).
Seeded by Claude at plan time (base `49c53e2e`); execution completes it at
step 0 from the actual AST references (reads of `widget` by property,
State vs lexical `context`, `mounted`, owner fields, statics, tear-offs) and
it is then frozen.

## Frozen member map

| Original (lines) | Destination file | New name |
| --- | --- | --- |
| `iptvAutoRefreshLabel`, `iptvAutoRefreshExplanation`, `IptvAutoRefreshDialog` (13–58) | `presentation/iptv_auto_refresh_dialog.dart` | unchanged |
| `_Dest` family (256–301) | `presentation/iptv_two_pane_destination.dart` | `IptvTwoPaneDest`, `IptvTwoPaneSourceDest`, `IptvTwoPaneAddDest`, `IptvTwoPaneListsDest`, `IptvTwoPaneStartupDest`, `IptvTwoPaneAutoRefreshDest`, `IptvTwoPaneContinueWatchingDest`, `IptvTwoPaneChannelPreviewDest`, `IptvTwoPaneAppearanceDest`, `IptvTwoPanePlayerGuideDest`, `IptvTwoPaneRecordingDest` |
| `_RailHeading`, `_RailEntry`, `_RailEntryState` (1583–1784) | `presentation/iptv_two_pane_rail_entry.dart` | `IptvTwoPaneRailHeading`, `IptvTwoPaneRailEntry`, `IptvTwoPaneRailEntryState` |
| `_PaneHeader`, `_Badge`, `_StatStrip`, `_QuietBanner`, `_RowGroup` (1786–1977) | `presentation/iptv_two_pane_pane_parts.dart` | `IptvTwoPanePaneHeader`, `IptvTwoPaneBadge`, `IptvTwoPaneStatStrip`, `IptvTwoPaneQuietBanner`, `IptvTwoPaneRowGroup` |
| `_PaneRow`, `_PaneRowState` (1979–2119) | `presentation/iptv_two_pane_row.dart` | `IptvTwoPaneRow`, `IptvTwoPaneRowState` |
| `_MethodCard`, `_MethodCardState` (2121–2231) | `presentation/iptv_two_pane_method_card.dart` | `IptvTwoPaneMethodCard`, `IptvTwoPaneMethodCardState` |
| `IptvSettingsTwoPane` (60–254, doc from 60) | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` | unchanged |
| State lifecycle, `focusRail`, `focusAddPane`, `build` | same file, `IptvSettingsTwoPaneState` | unchanged |
| `_panePoolSize`, `_app`, `_dest`, `_railNodes`, `_paneNodes`, `_railScroll`, `_stats`, `_statsSignature` | `legacy_…/iptv_settings_two_pane_owners.dart` | `_panePoolSize` (static, private), `app`, `dest`, `railNodes`, `paneNodes`, `railScroll`, `stats`, `statsSignature` |
| `_initialDest`, `_railCount`, index getters, `_syncRailNodes`, `_syncStats`, `_paneNode`, `_focusRail`, `_selectedRailIndex`, `_destForRail`, `_enterPane`, `_returnToRail` | `legacy_…/iptv_settings_two_pane_navigation.dart` | `initialDest`, `_railCount`, `channelPreviewIndex`…`autoRefreshIndex`, `syncRailNodes`, `syncStats`, `paneNode`, `focusRailAt`, `selectedRailIndex`, `destForRail`, `enterPane`, `returnToRail` |
| `_buildRail`, `_listsSubtitle`, `_iconFor`, `_railSubtitle` | `legacy_…/iptv_settings_two_pane_rail.dart` | `buildRail`, `_listsSubtitle`, `iconFor`, `_railSubtitle` |
| `_buildPane`, `_buildSourcePane`, `_sourceMeta`, `_buildAddPane`, `_chevron` | `legacy_…/iptv_settings_two_pane_panes.dart` | `buildPane`, `_buildSourcePane`, `_sourceMeta`, `_buildAddPane`, `chevron` |
| `_buildListsPane`, `_buildStartupPane` | `legacy_…/iptv_settings_two_pane_list_panes.dart` | `buildListsPane`, `buildStartupPane` |
| `_buildContinueWatchingPane`, `_buildChannelPreviewPane`, `_buildAppearancePane`, `_buildPlayerGuidePane`, `_buildRecordingPane` | `legacy_…/iptv_settings_two_pane_preference_panes.dart` | public `build…Pane` names |

## State-context sites (seed)

- State `context` in moved code: 586 (`_buildRail`), 1120–1122 (`_buildAddPane`) → `_deps.context()`.
- Lexical: 574 (`build` VLB builder, stays in State), 591 (rail VLB builder parameter).
- `mounted`: 479 only (`focusAddPane`, stays in State). No `setState` or `this` in State bodies.

## Wiring checklist

Original AST inventory at R `6c0a609962f673616c08aed513ccf4e5f04d59ed`.
All 73 leaves below still execute in the original facade at step 0; every row
has one planned destination and activation step in the LF manifest. A row is
wired when that production declaration moves there and the real checker,
source reader and affected behaviour pass. No duplicate State row exists.

The AST confirms eight field declarations, 38 other State members, and no
State-body `setState` or `this`. The live section widget getter preserves all
`widget` tokens. The owners field initializer creates resources eagerly;
only section composition is cached lazily. Host method nodes remain borrowed.

`styleIcon` and `styleRow` are the actual block-local functions (there is no
`option` function in this original); they stay lexical. `row` counters and the
VLB `dest` parameter also stay lexical. Only the four inherited State-context
reads in rail width and form calls become `_deps.context()`; the State build's
lexical context and both VLB parameter declarations stay unchanged.

| Original leaf | Destination / owner / new member | Widget properties | Owner/static reads | Context / lifecycle / cross-class references | Step / wiring |
| --- | --- | --- | --- | --- | --- |

| `iptvAutoRefreshLabel` | `iptv_auto_refresh_dialog.dart` / `iptvAutoRefreshLabel` | — | — | — | 1 / pending move; original verified |
| `iptvAutoRefreshExplanation` | `iptv_auto_refresh_dialog.dart` / `iptvAutoRefreshExplanation` | — | — | — | 1 / pending move; original verified |
| `IptvAutoRefreshDialog` | `iptv_auto_refresh_dialog.dart` / `IptvAutoRefreshDialog` | — | — | context:decl:member/method1#context#0 | 1 / pending move; original verified |
| `IptvSettingsTwoPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` / `IptvSettingsTwoPane` | — | — | — | 2 / pending move; original verified |
| `_Dest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneDest` | — | — | — | 1 / pending move; original verified |
| `_SourceDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneSourceDest` | — | — | — | 1 / pending move; original verified |
| `_AddDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneAddDest` | — | — | — | 1 / pending move; original verified |
| `_ListsDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneListsDest` | — | — | — | 1 / pending move; original verified |
| `_StartupDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneStartupDest` | — | — | — | 1 / pending move; original verified |
| `_AutoRefreshDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneAutoRefreshDest` | — | — | — | 1 / pending move; original verified |
| `_ContinueWatchingDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneContinueWatchingDest` | — | — | — | 1 / pending move; original verified |
| `_ChannelPreviewDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneChannelPreviewDest` | — | — | — | 1 / pending move; original verified |
| `_AppearanceDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneAppearanceDest` | — | — | — | 1 / pending move; original verified |
| `_PlayerGuideDest` | `iptv_two_pane_destination.dart` / `IptvTwoPanePlayerGuideDest` | — | — | — | 1 / pending move; original verified |
| `_RecordingDest` | `iptv_two_pane_destination.dart` / `IptvTwoPaneRecordingDest` | — | — | — | 1 / pending move; original verified |
| `IptvSettingsTwoPaneState._panePoolSize` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `_panePoolSize` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._app` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `app` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._dest` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `dest` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._railNodes` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `railNodes` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._paneNodes` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `paneNodes` | — | `_panePoolSize` | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._railScroll` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `railScroll` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._stats` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `stats` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._statsSignature` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart` / `IptvSettingsTwoPaneOwners` / `statsSignature` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState.initState` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` / `IptvSettingsTwoPaneState` / `initState` | `openAddSource` | `_dest` | calls/tear-offs: _initialDest, _syncRailNodes, _syncStats | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState.didUpdateWidget` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` / `IptvSettingsTwoPaneState` / `didUpdateWidget` | `playlists` | `_dest` | dest:decl:member/block0#dest#0; calls/tear-offs: _initialDest, _syncRailNodes, _syncStats | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState.dispose` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` / `IptvSettingsTwoPaneState` / `dispose` | — | `_dest`, `_paneNodes`, `_railNodes`, `_railScroll` | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._initialDest` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `initialDest` | `defaultPlaylistId`, `playlists` | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._railCount` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `_railCount` | `playlists`, `showAppearanceSection`, `showRecordingSection` | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._channelPreviewIndex` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `channelPreviewIndex` | `playlists` | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._continueWatchingIndex` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `continueWatchingIndex` | `playlists` | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._appearanceIndex` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `appearanceIndex` | `playlists` | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._playerGuideIndex` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `playerGuideIndex` | `playlists`, `showAppearanceSection` | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._recordingIndex` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `recordingIndex` | — | — | calls/tear-offs: _playerGuideIndex | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._autoRefreshIndex` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `autoRefreshIndex` | — | — | calls/tear-offs: _railCount | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._syncRailNodes` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `syncRailNodes` | — | `_railNodes` | calls/tear-offs: _railCount | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._syncStats` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `syncStats` | `playlists`, `refreshingIds` | `_stats`, `_statsSignature` | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._paneNode` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `paneNode` | — | `_paneNodes` | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._focusRail` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `focusRailAt` | — | `_railNodes` | calls/tear-offs: _railCount | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState.focusRail` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` / `IptvSettingsTwoPaneState` / `focusRail` | — | — | calls/tear-offs: _focusRail, _selectedRailIndex | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState.focusAddPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` / `IptvSettingsTwoPaneState` / `focusAddPane` | — | `_dest` | mounted:unbound; calls/tear-offs: _enterPane | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._selectedRailIndex` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `selectedRailIndex` | `playlists` | `_dest` | dest:decl:member/block0#dest#0; calls/tear-offs: _appearanceIndex, _autoRefreshIndex, _channelPreviewIndex, _continueWatchingIndex, _playerGuideIndex, _recordingIndex | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._destForRail` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `destForRail` | `playlists`, `showAppearanceSection`, `showRecordingSection` | — | calls/tear-offs: _autoRefreshIndex | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._enterPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `enterPane` | `addMethod`, `fileMethodFocusNode`, `urlMethodFocusNode`, `xtreamMethodFocusNode` | `_dest`, `_paneNodes` | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState.build` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` / `IptvSettingsTwoPaneState` / `build` | — | `_app`, `_dest` | context:decl:member#context#0; dest:decl:member/block0/closure0#dest#0; calls/tear-offs: _buildPane, _buildRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildRail` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_rail.dart` / `IptvSettingsTwoPaneRail` / `buildRail` | `autoRefreshHours`, `channelPreviewEnabled`, `defaultPlaylistId`, `iptvStyle`, `playerGuideStyle`, `playlists`, `recordingEngineEnabled`, `refreshingIds`, `scheduledCount`, `showAppearanceSection`, `showEngineToggle`, `showRecordingSection`, `startupEnabled`, `startupMode`, `trackContinueWatching` | `_app`, `_dest`, `_railNodes`, `_railScroll` | context:unbound; calls/tear-offs: _appearanceIndex, _autoRefreshIndex, _channelPreviewIndex, _continueWatchingIndex, _destForRail, _enterPane, _focusRail, _iconFor, _listsSubtitle, _playerGuideIndex, _railSubtitle, _recordingIndex, _selectedRailIndex | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._listsSubtitle` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_rail.dart` / `IptvSettingsTwoPaneRail` / `_listsSubtitle` | `customLists` | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._iconFor` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_rail.dart` / `IptvSettingsTwoPaneRail` / `iconFor` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._railSubtitle` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_rail.dart` / `IptvSettingsTwoPaneRail` / `_railSubtitle` | — | `_stats` | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_panes.dart` / `IptvSettingsTwoPanePanes` / `buildPane` | `autoRefreshHours`, `onPickAutoRefresh` | `_paneNodes` | dest:decl:member#dest#0; calls/tear-offs: _autoRefreshIndex, _buildAddPane, _buildAppearancePane, _buildChannelPreviewPane, _buildContinueWatchingPane, _buildListsPane, _buildPlayerGuidePane, _buildRecordingPane, _buildSourcePane, _buildStartupPane, _focusRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildSourcePane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_panes.dart` / `IptvSettingsTwoPanePanes` / `_buildSourcePane` | `defaultPlaylistId`, `hiddenCounts`, `onDelete`, `onEdit`, `onManageCategoryOrder`, `onManageHidden`, `onRefresh`, `onSetDefault`, `playlists`, `refreshingIds` | `_app`, `_stats` | row:decl:member/block0#row#0; calls/tear-offs: _buildAddPane, _chevron, _iconFor, _paneNode, _returnToRail, _sourceMeta | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._sourceMeta` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_panes.dart` / `IptvSettingsTwoPanePanes` / `_sourceMeta` | — | — | — | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildAddPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_panes.dart` / `IptvSettingsTwoPanePanes` / `_buildAddPane` | `addMethod`, `fileFormBuilder`, `fileMethodFocusNode`, `onAddMethodChanged`, `onFocusFirstFormField`, `urlFormBuilder`, `urlMethodFocusNode`, `xtreamFormBuilder`, `xtreamMethodFocusNode` | — | context:unbound; calls/tear-offs: _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildListsPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_list_panes.dart` / `IptvSettingsTwoPaneListPanes` / `buildListsPane` | `customLists`, `onCreateList`, `onListActions`, `onManageChannelOrder` | — | row:decl:member/block0#row#0; calls/tear-offs: _chevron, _paneNode, _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildStartupPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_list_panes.dart` / `IptvSettingsTwoPaneListPanes` / `buildStartupPane` | `hasLastLiveChannel`, `hasStartupChannel`, `lastLiveChannelLabel`, `onPickStartupChannel`, `onStartupModeChanged`, `onToggleStartup`, `startupChannelLabel`, `startupEnabled`, `startupMode` | — | row:decl:member/block0#row#0; calls/tear-offs: _chevron, _paneNode, _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildContinueWatchingPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_preference_panes.dart` / `IptvSettingsTwoPanePreferencePanes` / `buildContinueWatchingPane` | `onToggleTrackContinueWatching`, `trackContinueWatching` | — | calls/tear-offs: _paneNode, _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildChannelPreviewPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_preference_panes.dart` / `IptvSettingsTwoPanePreferencePanes` / `buildChannelPreviewPane` | `channelPreviewEnabled`, `onToggleChannelPreview` | — | calls/tear-offs: _paneNode, _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildAppearancePane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_preference_panes.dart` / `IptvSettingsTwoPanePreferencePanes` / `buildAppearancePane` | `iptvStyle`, `onIptvStyleChanged` | — | row:decl:member/block0#row#0; styleIcon:decl:member/block0#styleIcon#0; styleRow:decl:member/block0#styleRow#0; calls/tear-offs: _paneNode, _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildPlayerGuidePane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_preference_panes.dart` / `IptvSettingsTwoPanePreferencePanes` / `buildPlayerGuidePane` | `onPlayerGuideStyleChanged`, `playerGuideStyle` | — | row:decl:member/block0#row#0; styleRow:decl:member/block0#styleRow#0; calls/tear-offs: _paneNode, _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._buildRecordingPane` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_preference_panes.dart` / `IptvSettingsTwoPanePreferencePanes` / `buildRecordingPane` | `batteryExempt`, `maxConcurrentRecordings`, `onOpenScheduledRecordings`, `onPickMaxConcurrent`, `onRequestBatteryExemption`, `onToggleRecordingEngine`, `recordingEngineEnabled`, `scheduledCount`, `showEngineToggle` | — | row:decl:member/block0#row#0; calls/tear-offs: _chevron, _paneNode, _returnToRail | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._returnToRail` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart` / `IptvSettingsTwoPaneNavigation` / `returnToRail` | — | — | calls/tear-offs: _focusRail, _selectedRailIndex | 2 / pending move; original verified |
| `IptvSettingsTwoPaneState._chevron` | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_panes.dart` / `IptvSettingsTwoPanePanes` / `chevron` | — | `_app` | — | 2 / pending move; original verified |
| `_RailHeading` | `iptv_two_pane_rail_entry.dart` / `IptvTwoPaneRailHeading` | — | — | context:decl:member/method1#context#0 | 1 / pending move; original verified |
| `_RailEntry` | `iptv_two_pane_rail_entry.dart` / `IptvTwoPaneRailEntry` | — | — | — | 1 / pending move; original verified |
| `_RailEntryState` | `iptv_two_pane_rail_entry.dart` / `IptvTwoPaneRailEntryState` | `busy`, `chevron`, `focusNode`, `icon`, `onDown`, `onFocused`, `onRight`, `onSelect`, `onUp`, `selected`, `subtitle`, `title`, `trailing` | — | context:decl:member/method1#context#0; mounted:unbound | 1 / pending move; original verified |
| `_PaneHeader` | `iptv_two_pane_pane_parts.dart` / `IptvTwoPanePaneHeader` | — | — | context:decl:member/method1#context#0 | 1 / pending move; original verified |
| `_Badge` | `iptv_two_pane_pane_parts.dart` / `IptvTwoPaneBadge` | — | — | — | 1 / pending move; original verified |
| `_StatStrip` | `iptv_two_pane_pane_parts.dart` / `IptvTwoPaneStatStrip` | — | — | context:decl:member/method1#context#0 | 1 / pending move; original verified |
| `_QuietBanner` | `iptv_two_pane_pane_parts.dart` / `IptvTwoPaneQuietBanner` | — | — | context:decl:member/method1#context#0 | 1 / pending move; original verified |
| `_RowGroup` | `iptv_two_pane_pane_parts.dart` / `IptvTwoPaneRowGroup` | — | — | context:decl:member/method1#context#0 | 1 / pending move; original verified |
| `_PaneRow` | `iptv_two_pane_row.dart` / `IptvTwoPanePaneRow` | — | — | — | 1 / pending move; original verified |
| `_PaneRowState` | `iptv_two_pane_row.dart` / `IptvTwoPanePaneRowState` | `danger`, `focusNode`, `icon`, `onLeft`, `onTap`, `subtitle`, `title`, `trailing` | — | context:decl:member/method3#context#0; mounted:unbound | 1 / pending move; original verified |
| `_MethodCard` | `iptv_two_pane_method_card.dart` / `IptvTwoPaneMethodCard` | — | — | — | 1 / pending move; original verified |
| `_MethodCardState` | `iptv_two_pane_method_card.dart` / `IptvTwoPaneMethodCardState` | `focusNode`, `hint`, `icon`, `label`, `onDown`, `onLeft`, `onRight`, `onTap`, `selected` | — | context:decl:member/method1#context#0; mounted:unbound | 1 / pending move; original verified |

## Frozen callback map

The exact callback sidecar contains 115 constructor callback expressions,
including all ten `onFocused` assignments and all conditional `onUp`/`onDown`
branches. It stores original, step-1 and destination tokens and original /
destination expression text. Seventy-three supported direct tear-off and
single-call sites also use the shared identity checker (instance receivers,
never class identity alone). Block callbacks stay in whole-body guards.
The auto-refresh pane's `onLeft` is distinct from `returnToRail`.

## Import and source-text inventory

All service-free pieces require only Flutter and the existing theme contracts;
the destination family requires no imports. Per-file bridge service `show`
lists are frozen by the fixture's `imports_for` composition:

- widget: media store `IptvListMeta`; appearance storage `IptvAppearanceStorage`.
- owners: source stats `IptvSourceStats`.
- navigation: source stats `IptvSourceStatsLoader`.
- rail: source stats `IptvSourceStatsLoader`; startup storage
  `StartupIptvStorage`; style page `iptvStyleLabel`.
- panes: source stats `IptvGuideSource`, `IptvSourceStats`,
  `IptvSourceStatsLoader`.
- list panes: startup storage `StartupIptvStorage`.
- preference panes: style page `kIptvStyleChoices`.

The exact URI inventory finds six direct `iptv_settings` feature importers,
the settings page's relative import, and three existing tests. The feature
composition is the seventh participating feature file in the plan's broader
count. All consumers remain unchanged; no implementation importer is edited.
Step 1 registers shape/theme/ink/CI paths; step 3 measures the final facade cap
and removes its historical size entry. Existing source guards and the IPTV
settings manifest/reader point to their own legacy feature file and remain
unchanged. Step-0 checker fixtures introduce no shared-tool keys or edits.

## Exceptions and found-not-fixed

All exceptions and exits remain those in the plan. Every found-not-fixed item
is preserved, including the misplaced fallback-node doc, unused `isLast`,
synchronous stats reads, null auto-refresh action and fallback pointer focus.
