# IPTV Spotlight live timeline — dependency and characterization report

Reference R: `49c53e2e8` (the source object also matches plan HEAD `cea18cef4`). Application source remains untouched at step 0. The separate facts file mentioned in the plan was not present; this inventory is reconstructed from the analyzer AST, original source and original test identities. No guessed inventory was substituted.

## Ownership and resource lifetimes

All mutable workflow state remains owned by the facade State. The planned owners record preserves all 19 field declarations, their order, `late` and initializers, and is constructed eagerly. All sections are created once through the nullable cached sections getter. Each constructor stores only `_deps`. The retained lazy hold is read through exactly `_deps.holdOk()` at every original site. No application/controller/service design change is introduced.

The State owns the guide and Now focus nodes, vertical scroll controller, 375ms viewport timer, 375ms pointer timer and 30s periodic timer. The clock controls the 30min refresh. Cancellation and disposal retain original order. The host owns callbacks, list identity and schedule loader. Schedules are profile/source-context agnostic here: source/session identity remains supplied by the host, and all original stale guards remain in place.

The bridge exception is type/cache access to the existing EPG and image-cache services, with the exits listed in the plan. English strings remain unchanged until the localization migration. Hold ownership exits with an application-owned TV activation controller; the widget view exits with source/session-keyed Riverpod timeline state.

## Complete leaf map and wiring checklist

Each row is an extraction checklist entry: retain/move the whole declaration and attached original comments; apply only the registered rename/receiver path; wire every listed caller; prove its checker/reader, callback and occurrence contracts; remove its original implementation once activated. At step 0 every checklist entry is inventoried; production wiring is original and extraction is pending. `ctx` distinguishes a State read from a lexical parameter. No builder lexical context parameter is read.

| Original / lines | Step and destination / member | Widget properties read | State context / mounted / setState / hold | Fields and statics read | Cross-section calls | Wiring |
| --- | --- | --- | --- | --- | --- | --- |
| `SpotlightScheduleLoader` 15–22 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart` / `SpotlightScheduleLoader` |  |  |  |  | inventoried; original caller retained |
| `SpotlightChannelActivate` 24–24 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart` / `SpotlightChannelActivate` |  |  |  |  | inventoried; original caller retained |
| `SpotlightProgrammeActivate` 26–27 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart` / `SpotlightProgrammeActivate` |  |  |  |  | inventoried; original caller retained |
| `SpotlightTimelineEntryKey` 29–60 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart` / `SpotlightTimelineEntryKey` |  |  |  |  | inventoried; original caller retained |
| `SpotlightTimelineEntry` 62–82 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart` / `SpotlightTimelineEntry` |  |  |  |  | inventoried; original caller retained |
| `SpotlightTimelineSelection` 84–96 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart` / `SpotlightTimelineSelection` |  |  |  |  | inventoried; original caller retained |
| `IptvSpotlightTimelineController` 98–134 | 0 `facade` / `IptvSpotlightTimelineController` |  |  |  |  | inventoried; original caller retained |
| `SpotlightProgrammeGeometry` 136–143 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `SpotlightProgrammeGeometry` |  |  |  |  | inventoried; original caller retained |
| `spotlightProgrammeGeometry` 145–175 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `spotlightProgrammeGeometry` |  |  |  |  | inventoried; original caller retained |
| `spotlightRulerMarks` 177–209 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `spotlightRulerMarks` |  |  |  |  | inventoried; original caller retained |
| `SpotlightLiveTimeline` 211–294 | 0 `facade` / `SpotlightLiveTimeline` |  |  |  |  | inventoried; original caller retained |
| `_CursorLane` 296–296 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart` / `SpotlightTimelineCursorLane` |  |  |  |  | inventoried; original caller retained |
| `_GuideStatus` 298–298 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart` / `SpotlightTimelineGuideStatus` |  |  |  |  | inventoried; original caller retained |
| `_GuideSnapshot` 300–316 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart` / `SpotlightTimelineGuideSnapshot` |  |  |  |  | inventoried; original caller retained |
| `_LoadToken` 318–352 | 1 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart` / `SpotlightTimelineLoadToken` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._background` 355–355 | 2 `spotlight_timeline_palette.dart` / `SpotlightTimelinePalette.background` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._identityBackground` 356–356 | 2 `spotlight_timeline_palette.dart` / `SpotlightTimelinePalette.identityBackground` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._timelineBackground` 357–357 | 2 `spotlight_timeline_palette.dart` / `SpotlightTimelinePalette.timelineBackground` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._ownedFocusNode` 359–361 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.ownedFocusNode` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._nowFocusNode` 362–362 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.nowFocusNode` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._verticalController` 363–363 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.verticalController` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._guides` 364–364 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.guides` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._pendingLoads` 365–365 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.pendingLoads` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._windowStart` 367–367 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.windowStart` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._followNow` 368–368 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.followNow` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._lastGuideRefreshAt` 369–369 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.lastGuideRefreshAt` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._viewportSettle` 370–370 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.viewportSettle` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._clockTick` 371–371 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.clockTick` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._pointerSettle` 372–372 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.pointerSettle` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._guideRefreshInterval` 373–373 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow._guideRefreshInterval` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._requestGeneration` 374–374 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.requestGeneration` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._viewportHeight` 375–375 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.viewportHeight` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._cursorRow` 376–376 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.cursorRow` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._cursorLane` 377–377 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.cursorLane` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._selectedProgrammeStartMs` 378–378 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.selectedProgrammeStartMs` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._cursorTimeMs` 379–379 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.cursorTimeMs` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._hasFocus` 380–380 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.hasFocus` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._lastTappedCell` 381–381 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_owners.dart` / `SpotlightTimelineOwners.lastTappedCell` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._holdOk` 383–389 | 0 `facade` / `_SpotlightLiveTimelineState._holdOk` | onChannelActions |  | _cursorRow | _activateCursor, _entryAt | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._focusNode` 391–391 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.focusNode` |  |  | _ownedFocusNode |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._rowHeight` 395–402 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.rowHeight` | dense, rowHeight | context |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState.didChangeDependencies` 404–409 | 0 `facade` / `_SpotlightLiveTimelineState.didChangeDependencies` |  |  | _cursorRow | _armViewportLoad, _revealRow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState.initState` 411–431 | 0 `facade` / `_SpotlightLiveTimelineState.initState` | autofocus, controller, initialWindowStart, now | mounted | _clockTick, _cursorTimeMs, _followNow, _lastGuideRefreshAt, _verticalController, _windowStart | _announceSelection, _armViewportLoad, _defaultWindowStart, _focusNode, _onClockTick, _onViewportMoved | inventoried; original caller retained |
| `_SpotlightLiveTimelineState.didUpdateWidget` 433–486 | 0 `facade` / `_SpotlightLiveTimelineState.didUpdateWidget` | channels, controller, epgContextVersion, height, initialWindowStart, loadGeneration, now, rowHeight, rulerHeight, sourceId, viewportSettleDelay | mounted, _holdOk | _cursorLane, _cursorRow, _followNow, _guides, _lastGuideRefreshAt, _lastTappedCell, _pendingLoads, _selectedProgrammeStartMs, _windowStart | _announceSelection, _armViewportLoad, _cancelPointerSelection, _defaultWindowStart, _reconcileProgrammeCursor | inventoried; original caller retained |
| `_SpotlightLiveTimelineState.dispose` 488–501 | 0 `facade` / `_SpotlightLiveTimelineState.dispose` | controller | _holdOk | _clockTick, _nowFocusNode, _ownedFocusNode, _pointerSettle, _verticalController, _viewportSettle | _onViewportMoved | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._defaultWindowStart` 503–513 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow.defaultWindowStart` | now |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._onClockTick` 515–547 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow.onClockTick` | now | mounted, setState | _cursorLane, _cursorTimeMs, _followNow, _guideRefreshInterval, _guides, _lastGuideRefreshAt, _pendingLoads, _selectedProgrammeStartMs, _windowStart | _announceSelection, _armViewportLoad | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._entryAt` 549–557 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.entryAt` | channels, loadGeneration, sourceId |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._onViewportMoved` 559–559 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.onViewportMoved` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._armViewportLoad` 561–569 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.armViewportLoad` | viewportSettleDelay | mounted | _requestGeneration, _viewportSettle |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._visibleRange` 571–588 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.visibleRange` | channels |  | _verticalController, _viewportHeight |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._loadVisibleRows` 590–624 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading._loadVisibleRows` | epgContextVersion | mounted, setState | _guides, _pendingLoads |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._evictDistantRows` 626–641 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading._evictDistantRows` | channels |  | _cursorRow, _guides, _pendingLoads |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._loadSchedule` 643–689 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading._loadSchedule` | scheduleLoader | setState | _cursorLane, _cursorRow, _guides, _pendingLoads, _selectedProgrammeStartMs | _announceSelection, _reconcileProgrammeCursor | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._removePendingIfCurrent` 691–695 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading._removePendingIfCurrent` |  |  | _pendingLoads |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._accepts` 697–709 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading._accepts` | channels, epgContextVersion, loadGeneration, sourceId | mounted | _pendingLoads, _requestGeneration |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._retry` 711–736 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.retry` | epgContextVersion | setState | _cursorLane, _cursorRow, _guides, _pendingLoads, _requestGeneration, _selectedProgrammeStartMs | _announceSelection | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._onFocusChange` 738–747 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor.onFocusChange` |  | setState, _holdOk | _hasFocus, _lastTappedCell |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._onKeyEvent` 749–784 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor.onKeyEvent` | onChannelActions | _holdOk | _cursorLane, _lastTappedCell | _cancelPointerSelection, _jumpToNow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._moveVertical` 786–826 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor._moveVertical` | channels, onExitUp | setState | _cursorLane, _cursorRow, _cursorTimeMs, _followNow, _nowFocusNode, _selectedProgrammeStartMs | _announceSelection, _entryAt, _hasGuideError, _programmesForRow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._moveHorizontal` 828–908 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor._moveHorizontal` | channels, onExitLeft | setState | _cursorLane, _cursorRow, _cursorTimeMs, _selectedProgrammeStartMs | _announceSelection, _ensureProgrammeVisible, _entryAt, _hasGuideError, _programmesForRow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._programmesForRow` 910–915 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.programmesForRow` |  |  | _guides |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._nearestProgramme` 917–928 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor._nearestProgramme` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._distanceToProgramme` 930–935 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor._distanceToProgramme` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._selectProgrammeValue` 937–940 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor.selectProgrammeValue` |  |  | _cursorTimeMs, _selectedProgrammeStartMs |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._ensureProgrammeVisible` 942–967 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow.ensureProgrammeVisible` | windowDuration |  | _followNow, _windowStart |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._reconcileProgrammeCursor` 969–995 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor.reconcileProgrammeCursor` |  | mounted, setState | _cursorLane, _cursorRow, _cursorTimeMs, _selectedProgrammeStartMs | _announceSelection, _programmesForRow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._revealRow` 997–1017 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor.revealRow` |  | mounted | _verticalController | _rowHeight | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._activateCursor` 1019–1039 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor.activateCursor` | onProgrammeActivate |  | _cursorLane, _cursorRow, _selectedProgrammeStartMs | _entryAt, _hasGuideError, _programmesForRow, _retry | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._hasGuideError` 1041–1043 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_guide_loading.dart` / `SpotlightTimelineGuideLoading.hasGuideError` |  |  | _guides |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._activateIdentity` 1045–1046 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_cursor.dart` / `SpotlightTimelineCursor.activateIdentity` | onChannelActivate |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._restoreFocus` 1048–1065 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.restoreFocus` | channels | mounted, setState | _cursorLane, _cursorRow, _selectedProgrammeStartMs | _ensureProgrammeVisible, _programmesForRow, _revealRow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._tapIdentity` 1067–1072 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.tapIdentity` | selectBeforeActivate |  | _lastTappedCell | _entryAt | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._tapProgramme` 1074–1082 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.tapProgramme` | selectBeforeActivate |  | _lastTappedCell | _entryAt | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._focusFirstChannel` 1084–1088 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions._focusFirstChannel` | channels | mounted |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._focusChannelAt` 1090–1094 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions._focusChannelAt` | channels | mounted |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._focusChannel` 1096–1115 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions._focusChannel` | channels | mounted | _cursorRow | _entryAt, _visibleRange | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._selectIdentity` 1117–1140 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.selectIdentity` |  | setState | _cursorLane, _cursorRow, _lastTappedCell, _selectedProgrammeStartMs | _activateIdentity, _entryAt, _revealRow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._selectProgramme` 1142–1165 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.selectProgramme` | onProgrammeActivate | setState | _cursorLane, _cursorRow, _lastTappedCell | _entryAt, _revealRow, _selectProgrammeValue | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._announceSelection` 1167–1188 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.announceSelection` | onSelectionChanged |  | _cursorLane, _cursorRow, _selectedProgrammeStartMs | _entryAt, _programmesForRow | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._armPointerSelection` 1190–1211 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.armPointerSelection` | channels, epgContextVersion, loadGeneration, sourceId | mounted | _pointerSettle |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._cancelPointerSelection` 1213–1216 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_selection.dart` / `SpotlightTimelineSelectionActions.cancelPointerSelection` |  |  | _pointerSettle |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._handlePointerSignal` 1218–1234 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow.handlePointerSignal` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._panTimeline` 1236–1248 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow.panTimeline` | windowDuration | setState | _followNow, _lastTappedCell, _windowStart | _cancelPointerSelection | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._onNowKeyEvent` 1250–1273 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow.onNowKeyEvent` | onExitLeft, onExitUp |  |  | _restoreFocus | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._jumpToNow` 1275–1285 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_window.dart` / `SpotlightTimelineWindow.jumpToNow` | now | setState | _cursorLane, _cursorTimeMs, _followNow, _selectedProgrammeStartMs, _windowStart | _cancelPointerSelection, _restoreFocus | inventoried; original caller retained |
| `_SpotlightLiveTimelineState.build` 1287–1372 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_frame.dart` / `SpotlightTimelineFrame.build` | autofocus, channels, height, identityWidth | mounted | _background, _verticalController, _viewportHeight | _armViewportLoad, _buildRow, _cancelPointerSelection, _entryAt, _focusNode, _handlePointerSignal, _onFocusChange, _onKeyEvent, _panTimeline, _rowHeight | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._buildRuler` 1374–1494 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_frame.dart` / `SpotlightTimelineFrame._buildRuler` | channels, rulerHeight | setState, _holdOk | _followNow, _identityBackground, _lastTappedCell, _nowFocusNode, _timelineBackground, _windowStart | _cancelPointerSelection, _jumpToNow, _onNowKeyEvent, _rulerMarks, _timeX | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._rulerMarks` 1496–1499 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `SpotlightTimelineTrack.rulerMarks` | windowDuration |  | _windowStart |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._timeX` 1501–1504 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `SpotlightTimelineTrack.timeX` | windowDuration |  | _windowStart |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._buildEmpty` 1506–1518 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_frame.dart` / `SpotlightTimelineFrame._buildEmpty` |  |  | _timelineBackground |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._buildRow` 1520–1550 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_rows.dart` / `SpotlightTimelineRows.buildRow` |  |  |  | _buildProgrammeTrack, _handlePointerSignal | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._buildIdentity` 1552–1702 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_rows.dart` / `SpotlightTimelineRows._buildIdentity` | dense, onChannelActions, selectBeforeActivate |  | _cursorLane, _cursorRow, _guides, _hasFocus, _identityBackground, _lastTappedCell, _nowFocusNode | _armPointerSelection, _cancelPointerSelection, _selectIdentity, _tapIdentity | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._buildProgrammeTrack` 1704–1848 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `SpotlightTimelineTrack.buildProgrammeTrack` | windowDuration |  | _cursorLane, _cursorRow, _guides, _hasFocus, _nowFocusNode, _timelineBackground, _windowStart | _retry, _tapIdentity | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._buildProgrammeCell` 1850–2024 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `SpotlightTimelineTrack._buildProgrammeCell` | dense, now, onChannelActions, selectBeforeActivate |  | _cursorLane, _cursorRow, _formatTime, _hasFocus, _nowFocusNode, _selectedProgrammeStartMs | _armPointerSelection, _cancelPointerSelection, _selectProgramme, _tapProgramme | inventoried; original caller retained |
| `_SpotlightLiveTimelineState.itemCanFitBadge` 2026–2027 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `SpotlightTimelineTrack.itemCanFitBadge` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._buildPlayhead` 2029–2083 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_frame.dart` / `SpotlightTimelineFrame._buildPlayhead` | now, windowDuration |  | _formatTime, _windowStart | _timeX | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._formatTime` 2085–2090 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_track.dart` / `SpotlightTimelineTrack.formatTime` |  |  |  |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._dayHeading` 2092–2115 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_frame.dart` / `SpotlightTimelineFrame._dayHeading` | now |  | _weekday |  | inventoried; original caller retained |
| `_SpotlightLiveTimelineState._weekday` 2117–2125 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_frame.dart` / `SpotlightTimelineFrame._weekday` |  |  |  |  | inventoried; original caller retained |
| `_RulerMark` 2128–2173 | 1 `spotlight_timeline_parts.dart` / `SpotlightTimelineRulerMark` |  |  |  |  | inventoried; original caller retained |
| `_GuideMessage` 2175–2259 | 1 `spotlight_timeline_parts.dart` / `SpotlightTimelineGuideMessage` |  |  |  |  | inventoried; original caller retained |
| `_ChannelMark` 2261–2304 | 2 `legacy_iptv_spotlight_timeline/spotlight_timeline_rows.dart` / `SpotlightTimelineChannelMark` |  |  |  |  | inventoried; original caller retained |

## Typed view

The view has exactly 21 live getters: `channels`, `sourceId`, `loadGeneration`, `scheduleLoader`, `onChannelActivate`, `onProgrammeActivate`, `epgContextVersion`, `onSelectionChanged`, `autofocus`, `onExitUp`, `onExitLeft`, `onChannelActions`, `selectBeforeActivate`, `now`, `windowDuration`, `viewportSettleDelay`, `height`, `dense`, `identityWidth`, `rowHeight`, `rulerHeight`. `controller` and `initialWindowStart` remain lifecycle-only. Function/list identity is preserved by `=> widget.property`; direct identity probes belong to step 0b. Original callback/loader/clock replacement behavior is characterized in the lifecycle/input tests.

## Lexical context and labels

`build(context)` and all three builder parameters (`LayoutBuilder` twice, `ListView.itemBuilder`) keep their names, positions and unused status. `_rowHeight` is the sole State-context read; its two leading comments travel with the method. `_deps.context()` is evaluated at that read, and cached-context negatives reject. Every moved unbound `mounted`/`setState` access becomes its live `_deps` callback at that original site.

The `windowStart:` named arguments in `_rulerMarks` and `_buildProgrammeTrack` stay labels. No original parameter/local shadows an underscore-prefixed owner field. Owner reads always use `_owners`; bare renamed field reads are rejected by the opt-in record binder. The callback sidecar pins all 22 inventoried argument expressions, including block closures; seven direct callback identities have independent swapped/wrapped negatives. The State reference passed to controller attach/detach remains `this`.

## Characterization coverage

Existing coverage stays byte-identical in `test/widgets/iptv/spotlight/spotlight_live_timeline_test.dart`. The additions cover gaps rather than replacing those assertions. Full original bodies/comments have one named source-contract test per manifest leaf; inaccessible/masked mutations use the step 0b source-only ledger with the plan’s stated reasons.

| Contract | Existing ORIGINAL tests / new gaps |
| --- | --- |
| 1 Lifecycle | New lifecycle tests: controller rebind/disposal, initialWindowStart transitions, each size/delay re-arm, unrelated callback update. Whole bodies pin exact order and explicit removeListener (masked by disposal). |
| 2 Hold | Existing “short OK plays, held OK and touch long press open channel actions”; new focus/source cancellation, live cursor/actions replacement, retry bypass and no-actions immediate activation. Lazy declaration/composition are source contracts; eagerly-created hold negatives are checker fixtures. |
| 3 Loads/eviction | Existing “settles for 375ms and only loads visible live rows”, “does not materialize a large lazy channel list”; new actual default-delay boundary, same-context ready skip, eight-row buffer and distant cursor retention. |
| 4 Results/retry | Existing recycled-source, context retry, same-start refreshed instance, failed-guide refresh; new start/stop ordering, zero/negative duration filtering, unmounted completion, viewport generation, independent same-generation pending-token rejection through public error callbacks, in-place recycled channel/out-of-range ordinal, retry retaining another row’s generation. |
| 5 Clock | Existing “follow-now advances the unselected programme time anchor”; new exact 30s tick/anchor/replacement clock, 30min expiration/settled reload/retry announcement and selected-time retention. |
| 6 Keys | Existing edge exits, nearest vertical programme, cached-error fallback, activation repeat and alternate keys, oversized clip rule; new arrow repeat/Home and exact 12% reveal geometry. |
| 7 Now | Existing four-key DPAD reaches Now / exits Up-Left / Down restores / activation repeats; new Home and follow-now visibility, explicit-window transitions. Exact focus/reset order remains source-pinned. |
| 8 Pointer | Existing tap-preview-tap, programme restoration, hover disarming, mouse/Shift/trackpad matrix, swipe/Now, in-place recycled dwell and source/context cancellation; new 374/375ms dwell, origin/payload, exit/drag/disposal/shrink cancellation. |
| 9 Controller | Existing logical cell restoration, identity playback and index-only 50k lazy focus; new cursor+visible-range-only focusChannel with a throwing index proxy. |
| 10 Announcements | Existing source projection and same-start refreshed programme instance; new pointer-vs-controller identity/programme payload and replacement selection callback. |
| 11 Paint | Existing scaled names/focus reveal, geometry/quarter-hour zones and unchanged IPTV results golden; new exact 45% clamp and scaler arithmetic, 24/25min badge threshold, replay/semantics flags/hint and 130ms scale, playhead bounds/zero width, day/empty/VOD text. Six deterministic scenes cover focused identity, archive programme, focused retry, mixed panned states, dense scaling and empty list. |
| 12 Boundaries | Original-only lib/pubspec object equality; source contracts ban playback, keep-alive and sibling implementation imports. Planned architecture and CI registration remain step 1, and real architecture negatives remain later as scheduled. |

## Strict baseline and rename probe

Strict options are inherited from `lib/features/analysis_options.yaml` on a scratch copy; only relative imports are qualified. ORIGINAL: one `directives_ordering` info at imports. Type-rename probe: that info plus exactly one `use_key_in_widget_constructors` each for `_RulerMark` and `_ChannelMark`. Zero warnings/errors; `invalid_use_of_visible_for_testing_member` remains absent. No key parameter, constructor, const, suppression or behavior is changed. Inventory maxima are taken per severity/rule/original symbol/message, never summed. Full composition-specific inventory/facade measurement is intentionally step 0b.

## Facade baseline line accounting

Original facade: 2,304 physical lines. AST top-level range accounting: declarations 2272 lines; imports/gaps/trailing lines 32 lines. The State range is 1,773 lines (353–2,125), controller 37 (98–134), widget 84 (211–294). Step 0b measures the complete formatted proposed facade; step 2 records its final AST-range breakdown and each actual destination size. The hard cap remains 400 with a target of 360, and no size exception is introduced.

## Found, not fixed during characterization

The original three items in the plan are preserved. The cache constructor requests filesystem/cache-repository directories eagerly even though the recording image cache never invokes an image loader. The artwork fixture blocks those construction-only futures before installing the loading tripwire; no real filesystem/database/cache load occurs. Equal same-generation retry tokens compare by value: when two error taps precede the next frame, the first completion may win and remove the equal pending token. A dedicated ORIGINAL test pins that behavior. Neither condition is repaired. The bundled Roboto regular/bold assets contain HTML; they remain untouched. Dedicated goldens pin the existing valid Inter TrueType bytes under a unique test family and disable the fixture's debug banner. This affects the capture harness only and prevents silently capturing test-font blocks.

## Per-leaf `this`, callback and timer inventory

Empty cells are an evidenced absence in the original leaf. Callback sites use frozen sidecar ordinals; block closures retain their entire enclosing body. Timer/resource names stay owned by the State and retain the cancellation/disposal protocol recorded above.

| Leaf | `this` syntax | Callback sites / expressions | Timer/resource access |
| --- | --- | --- | --- |
| `SpotlightScheduleLoader` |  |  |  |
| `SpotlightChannelActivate` |  |  |  |
| `SpotlightProgrammeActivate` |  |  |  |
| `SpotlightTimelineEntryKey` | `this.sourceId`, `this.loadGeneration`, `this.sourceOrdinal`, `this` |  |  |
| `SpotlightTimelineEntry` | `this.sourceId`, `this.loadGeneration`, `this.sourceOrdinal`, `this.channel` |  |  |
| `SpotlightTimelineSelection` | `this.entry`, `this.programme`, `this.fromPointer` |  |  |
| `IptvSpotlightTimelineController` |  |  |  |
| `SpotlightProgrammeGeometry` | `this.left`, `this.width` |  |  |
| `spotlightProgrammeGeometry` |  |  |  |
| `spotlightRulerMarks` |  |  |  |
| `SpotlightLiveTimeline` | `this.channels`, `this.sourceId`, `this.loadGeneration`, `this.scheduleLoader`, `this.onChannelActivate`, `this.onProgrammeActivate`, `this.epgContextVersion`, `this.onSelectionChanged`, `this.controller`, `this.autofocus`, `this.onExitUp`, `this.onExitLeft`, `this.onChannelActions`, `this.selectBeforeActivate`, `this.now`, `this.initialWindowStart`, `this.windowDuration`, `this.viewportSettleDelay`, `this.height`, `this.dense`, `this.identityWidth`, `this.rowHeight`, `this.rulerHeight` |  |  |
| `_CursorLane` |  |  |  |
| `_GuideStatus` |  |  |  |
| `_GuideSnapshot` | `this.contextVersion`, `this.contextVersion`, `this.programmes`, `this.contextVersion` |  |  |
| `_LoadToken` | `this.generation`, `this.entryKey`, `this.contextVersion`, `this.sourceIndex`, `this.channel`, `this` |  |  |
| `_SpotlightLiveTimelineState._background` |  |  |  |
| `_SpotlightLiveTimelineState._identityBackground` |  |  |  |
| `_SpotlightLiveTimelineState._timelineBackground` |  |  |  |
| `_SpotlightLiveTimelineState._ownedFocusNode` |  |  | _ownedFocusNode |
| `_SpotlightLiveTimelineState._nowFocusNode` |  |  | _nowFocusNode |
| `_SpotlightLiveTimelineState._verticalController` |  |  | _verticalController |
| `_SpotlightLiveTimelineState._guides` |  |  |  |
| `_SpotlightLiveTimelineState._pendingLoads` |  |  |  |
| `_SpotlightLiveTimelineState._windowStart` |  |  |  |
| `_SpotlightLiveTimelineState._followNow` |  |  |  |
| `_SpotlightLiveTimelineState._lastGuideRefreshAt` |  |  |  |
| `_SpotlightLiveTimelineState._viewportSettle` |  |  | _viewportSettle |
| `_SpotlightLiveTimelineState._clockTick` |  |  | _clockTick |
| `_SpotlightLiveTimelineState._pointerSettle` |  |  | _pointerSettle |
| `_SpotlightLiveTimelineState._guideRefreshInterval` |  |  |  |
| `_SpotlightLiveTimelineState._requestGeneration` |  |  |  |
| `_SpotlightLiveTimelineState._viewportHeight` |  |  |  |
| `_SpotlightLiveTimelineState._cursorRow` |  |  |  |
| `_SpotlightLiveTimelineState._cursorLane` |  |  |  |
| `_SpotlightLiveTimelineState._selectedProgrammeStartMs` |  |  |  |
| `_SpotlightLiveTimelineState._cursorTimeMs` |  |  |  |
| `_SpotlightLiveTimelineState._hasFocus` |  |  |  |
| `_SpotlightLiveTimelineState._lastTappedCell` |  |  |  |
| `_SpotlightLiveTimelineState._holdOk` |  | 0: TvHoldOk / `_activateCursor`; 1: TvHoldOk / `( ) { final entry = _entryAt ( _cursorRow ) ; if ( entry != null ) widget . onChannelActions ?. call ( entry ) ; }` | _holdOk |
| `_SpotlightLiveTimelineState._focusNode` |  |  | _ownedFocusNode |
| `_SpotlightLiveTimelineState._rowHeight` |  |  |  |
| `_SpotlightLiveTimelineState.didChangeDependencies` |  |  |  |
| `_SpotlightLiveTimelineState.initState` | `this` | 2: addListener / `_onViewportMoved` | _clockTick, _verticalController |
| `_SpotlightLiveTimelineState.didUpdateWidget` | `this`, `this` |  | _holdOk |
| `_SpotlightLiveTimelineState.dispose` | `this` | 3: removeListener / `_onViewportMoved` | _clockTick, _holdOk, _nowFocusNode, _ownedFocusNode, _pointerSettle, _verticalController, _viewportSettle |
| `_SpotlightLiveTimelineState._defaultWindowStart` |  |  |  |
| `_SpotlightLiveTimelineState._onClockTick` |  |  |  |
| `_SpotlightLiveTimelineState._entryAt` |  |  |  |
| `_SpotlightLiveTimelineState._onViewportMoved` |  |  |  |
| `_SpotlightLiveTimelineState._armViewportLoad` |  |  | _viewportSettle |
| `_SpotlightLiveTimelineState._visibleRange` |  |  | _verticalController |
| `_SpotlightLiveTimelineState._loadVisibleRows` |  |  |  |
| `_SpotlightLiveTimelineState._evictDistantRows` |  |  |  |
| `_SpotlightLiveTimelineState._loadSchedule` |  |  |  |
| `_SpotlightLiveTimelineState._removePendingIfCurrent` |  |  |  |
| `_SpotlightLiveTimelineState._accepts` |  |  |  |
| `_SpotlightLiveTimelineState._retry` |  |  |  |
| `_SpotlightLiveTimelineState._onFocusChange` |  |  | _holdOk |
| `_SpotlightLiveTimelineState._onKeyEvent` |  |  | _holdOk |
| `_SpotlightLiveTimelineState._moveVertical` |  |  | _nowFocusNode |
| `_SpotlightLiveTimelineState._moveHorizontal` |  |  |  |
| `_SpotlightLiveTimelineState._programmesForRow` |  |  |  |
| `_SpotlightLiveTimelineState._nearestProgramme` |  |  |  |
| `_SpotlightLiveTimelineState._distanceToProgramme` |  |  |  |
| `_SpotlightLiveTimelineState._selectProgrammeValue` |  |  |  |
| `_SpotlightLiveTimelineState._ensureProgrammeVisible` |  |  |  |
| `_SpotlightLiveTimelineState._reconcileProgrammeCursor` |  |  |  |
| `_SpotlightLiveTimelineState._revealRow` |  |  | _verticalController |
| `_SpotlightLiveTimelineState._activateCursor` |  |  |  |
| `_SpotlightLiveTimelineState._hasGuideError` |  |  |  |
| `_SpotlightLiveTimelineState._activateIdentity` |  |  |  |
| `_SpotlightLiveTimelineState._restoreFocus` |  |  |  |
| `_SpotlightLiveTimelineState._tapIdentity` |  |  |  |
| `_SpotlightLiveTimelineState._tapProgramme` |  |  |  |
| `_SpotlightLiveTimelineState._focusFirstChannel` |  |  |  |
| `_SpotlightLiveTimelineState._focusChannelAt` |  |  |  |
| `_SpotlightLiveTimelineState._focusChannel` |  |  |  |
| `_SpotlightLiveTimelineState._selectIdentity` |  |  |  |
| `_SpotlightLiveTimelineState._selectProgramme` |  |  |  |
| `_SpotlightLiveTimelineState._announceSelection` |  |  |  |
| `_SpotlightLiveTimelineState._armPointerSelection` |  |  | _pointerSettle |
| `_SpotlightLiveTimelineState._cancelPointerSelection` |  |  | _pointerSettle |
| `_SpotlightLiveTimelineState._handlePointerSignal` |  |  |  |
| `_SpotlightLiveTimelineState._panTimeline` |  |  |  |
| `_SpotlightLiveTimelineState._onNowKeyEvent` |  |  |  |
| `_SpotlightLiveTimelineState._jumpToNow` |  |  |  |
| `_SpotlightLiveTimelineState.build` |  | 4: Focus / `_onFocusChange`; 5: Focus / `_onKeyEvent`; 6: Listener / `( signal ) => _handlePointerSignal ( signal , timelineWidth )`; 7: GestureDetector / `( _ ) => _cancelPointerSelection ( )`; 8: GestureDetector / `( details ) => _panTimeline ( - details . delta . dx , timelineWidth )` | _verticalController |
| `_SpotlightLiveTimelineState._buildRuler` |  | 9: Focus / `_onNowKeyEvent`; 10: TextButton / `( focused ) { if ( focused ) { _cancelPointerSelection ( ) ; _holdOk . reset ( ) ; _lastTappedCell = null ; } setState ( ( ) { } ) ; }`; 11: TextButton / `_jumpToNow` | _holdOk, _nowFocusNode |
| `_SpotlightLiveTimelineState._rulerMarks` |  |  |  |
| `_SpotlightLiveTimelineState._timeX` |  |  |  |
| `_SpotlightLiveTimelineState._buildEmpty` |  |  |  |
| `_SpotlightLiveTimelineState._buildRow` |  | 12: Listener / `( signal ) => _handlePointerSignal ( signal , timelineWidth )` |  |
| `_SpotlightLiveTimelineState._buildIdentity` |  | 13: GestureDetector / `( ) => _tapIdentity ( row )`; 14: GestureDetector / `widget . onChannelActions == null ? null : ( ) { _selectIdentity ( row , fromPointer : true ) ; widget . onChannelActions ! ( entry ) ; }`; 15: MouseRegion / `( _ ) => _armPointerSelection ( entry , ( ) => _selectIdentity ( row , requestFocus : false , fromPointer : true ) )`; 16: MouseRegion / `( _ ) => _cancelPointerSelection ( )` | _nowFocusNode |
| `_SpotlightLiveTimelineState._buildProgrammeTrack` |  |  | _nowFocusNode |
| `_SpotlightLiveTimelineState._buildProgrammeCell` |  | 17: GestureDetector / `( ) => _tapProgramme ( row , programme )`; 18: GestureDetector / `widget . onChannelActions == null ? null : ( ) { _selectProgramme ( row , programme , fromPointer : true ) ; widget . onChannelActions ! ( entry ) ; }`; 19: MouseRegion / `( _ ) => _armPointerSelection ( entry , ( ) => _selectProgramme ( row , programme , requestFocus : false , fromPointer : true ) )`; 20: MouseRegion / `( _ ) => _cancelPointerSelection ( )` | _nowFocusNode |
| `_SpotlightLiveTimelineState.itemCanFitBadge` |  |  |  |
| `_SpotlightLiveTimelineState._buildPlayhead` |  |  |  |
| `_SpotlightLiveTimelineState._formatTime` |  |  |  |
| `_SpotlightLiveTimelineState._dayHeading` |  |  |  |
| `_SpotlightLiveTimelineState._weekday` |  |  |  |
| `_RulerMark` | `this.time`, `this.color`, `this.lineColor` |  |  |
| `_GuideMessage` | `this.label`, `this.color`, `this.leading`, `this.onTap`, `this.hint`, `this.focused`, `this.focusFill`, `this.focusInk` | 21: GestureDetector / `onTap` |  |
| `_ChannelMark` | `this.logoUrl`, `this.size`, `this.selected`, `this.tokens` |  |  |

## Observed existing timeline test identities

These exact names passed in the untouched full-suite baseline. They supply the existing side of the contract table; no existing test was edited.

- `long channel names have two readable lines beside the logo`
- `dense rows keep long names visible at larger text sizes`
- `scaled names fit and focused rows remain visible after scaling`
- `spotlightProgrammeGeometry uses epoch duration for variable width and clips to the window`
- `spotlightProgrammeGeometry rejects gaps, reversed programmes, and empty viewports`
- `ruler marks align to local half hours in quarter-hour zones`
- `touch selects before playback, even on the focused startup row`
- `programme tap previews first and restores the same cell after leaving`
- `guide edges exit explicitly and bottom/right do not lose focus`
- `horizontal swipe pans programmes, Now restores, vertical swipe scrolls channels`
- `short OK plays, held OK and touch long press open channel actions`
- `DPAD reaches Now and returns to the guide with Select`
- `DPAD reaches Now and returns to the guide with Game Button A`
- `DPAD reaches Now and returns to the guide with Numpad Enter`
- `DPAD reaches Now and returns to the guide with Enter`
- `hover disarms a previously tapped channel`
- `hover disarms a previously tapped programme`
- `wheel chooses one axis for Offset(120.0, 1.0), shift=false, PointerDeviceKind.mouse`
- `wheel chooses one axis for Offset(-120.0, 1.0), shift=false, PointerDeviceKind.mouse`
- `wheel chooses one axis for Offset(1.0, 120.0), shift=false, PointerDeviceKind.mouse`
- `wheel chooses one axis for Offset(120.0, 0.0), shift=false, PointerDeviceKind.mouse`
- `wheel chooses one axis for Offset(0.0, 120.0), shift=false, PointerDeviceKind.mouse`
- `wheel chooses one axis for Offset(1.0, 120.0), shift=true, PointerDeviceKind.mouse`
- `wheel chooses one axis for Offset(1.0, 120.0), shift=true, PointerDeviceKind.trackpad`
- `settles for 375ms and only loads visible live rows`
- `does not materialize a large lazy channel list`
- `rejects a result for a recycled source ordinal`
- `epgContextVersion retries visible rows`
- `guide refresh republishes a same-start programme instance`
- `failed guide refresh restores the playable channel cursor`
- `shows empty and error states and retries errors by click`
- `identity stays playable and RIGHT exposes TV guide retry`
- `source projection change republishes the new identity`
- `pending pointer dwell rejects an in-place recycled row`
- `pending pointer dwell is canceled on source context changes`
- `DPAD keeps one cursor and selects nearest time vertically`
- `vertical move into a cached guide error restores channel focus`
- `holding Enter activates the logical cursor only once`
- `alternate TV activation keys work and repeats are swallowed`
- `follow-now advances the unselected programme time anchor`
- `selecting an oversized current programme keeps the now window anchored`
- `controller hands focus to a channel and identity stays playable`
- `controller focuses a lazy-list index without scanning`

## Source-text inventory at step 0

`file_size_baseline.txt` retains the facade’s 2,304-line entry. Both shape manifests leave the facade unregistered (six bare radii); future destinations are also unregistered. The measured theme surfaces are unchanged, and the light-ink inventory remains 774 sites / 240 primary. Hashes of the source guards and storage-member map are in `base-source-text-hashes.json`; whole-suite outcomes record their observed status. The profile guard already fails on two unrelated storage opens, as recorded in `base-summary.json`. No guard or assertion is removed. Architecture/size registration and CI format/analyzer inputs remain scheduled for step 1.
