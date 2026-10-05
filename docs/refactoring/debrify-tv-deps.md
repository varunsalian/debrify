# Debrify TV dependency and wiring inventory

Reference R: `991029f64a6e4ce27b68626ac4537bf9f38f483c`. Flutter 3.44.8 / Dart 3.12.2. All application objects remain unchanged at checkpoint (b).

265 manifest leaves cover the 21 top-level declarations (19 outside the retained widget/State), all 244 State members, and the two choice-chip State members. Counts: 78 instance fields, 15 statics, one live getter, 150 State methods including lifecycle/build. The [manifest](../../dev/tool/debrify_tv_manifest.tsv) and [frozen destination map](../../dev/tool/debrify_tv_planned_destinations.json) are authoritative.

Offsets below are absolute ORIGINAL character offsets; `read`, `write`, `readWrite`, and `invocation` are raw AST roles. Scope/binding pairs distinguish lexical locals from fields before receiver normalization. Every entry was reviewed for one owner, the frozen section key, initializer timing, bound State versus lexical callbacks, full comments, and production wiring. No scaffold is pinned before this review. Original ownership passes the real checker; simulated partial/completed moves are separate guard fixtures, never application changes.

## Owners and resources

| Owner | Fields | Construction/lifetime |
| --- | --- | --- |
| `library` | 6: `_keywordsController`, `_channels`, `_debrifyTvStyle`, `_channelCache`, `_currentWatchingChannelId`, `_favoriteChannelIds` | Eager original declaration order; route-owned until State disposal |
| `stage` | 4: `_spotlightRailHealth`, `_spotlightStats`, `_spotlightStatsDebounce`, `_spotlightFocusedId` | Eager original declaration order; route-owned until State disposal |
| `settings` | 34: `_settingsManager`, `_tvEngineStates`, `_tvSmallChannelMaxByEngine`, `_tvLargeChannelMaxByEngine`, `_tvQuickPlayMaxByEngine`, `_channelBatchSize`, `_keywordThreshold`, `_minTorrentsPerKeyword`, `_quickPlayMaxKeywords`, `_startRandom`, `_randomStartPercent`, `_hideSeekbar`, `_showChannelName`, `_showVideoTitle`, `_hideOptions`, `_hideBackButton`, `_provider`, `_quickStartRandom`, `_quickRandomStartPercent`, `_quickHideSeekbar`, `_quickShowChannelName`, `_quickShowVideoTitle`, `_quickHideOptions`, `_quickHideBackButton`, `_quickAvoidNsfw`, `_rdSkipBlockedTorrents`, `_quickProvider`, `_tvFilters`, `_rdAvailable`, `_torboxAvailable`, `_pikpakAvailable`, `_premiumizeAvailable`, `_allDebridAvailable`, `_isAndroidTv` | Eager original declaration order; route-owned until State disposal |
| `session` | 14: `_queue`, `_isBusy`, `_status`, `_pikpakCandidatePool`, `_qualityFallbackNotified`, `_rdSizeRejections`, `_sizeFilterRelaxed`, `_seenRestrictedLinks`, `_seenLinkWithTorrentId`, `_lastQueueSize`, `_lastSearchAt`, `_launchedPlayer`, `_watchCancelled`, `_originalMaxCap` | Eager original declaration order; route-owned until State disposal |
| `prefetch` | 7: `_prefetchRunning`, `_prefetchStopRequested`, `_prefetchTask`, `_prefetchEpoch`, `_activeApiKey`, `_activeProvider`, `_inflightInfohashes` | Eager original declaration order; route-owned until State disposal |
| `progress` | 3: `_progress`, `_progressSheetContext`, `_progressOpen` | Eager original declaration order; route-owned until State disposal |
| `focus` | 10: `_channelSearchController`, `_channelSearchTerm`, `_showSearchBar`, `_channelSearchFocusNode`, `_quickPlayFocusNode`, `_channelSearchButtonFocusNode`, `_channelSearchClearFocusNode`, `_channelMenuFocusNode`, `_channelMenuController`, `_tvContentFocusHandler` | Eager original declaration order; route-owned until State disposal |

Resources: two TextEditingControllers, one ValueNotifier, five FocusNodes (channel search assigned in initState), one MenuController (no dispose API), one debounce Timer, one prefetch-loop Future. Dialog controllers/focus nodes/notifiers keep their original method-owned teardown. No subscriptions, tickers, mixins or route observers are introduced.

Hooks: HomeHeroShellBridge → MainPageBridge.watchDebrifyTvChannel → library.watchChannelById; unmounted Home requests store a pending ID consumed by the unguarded init post-frame callback (50 × 100 ms). Library register/unregister uses the same receiver/member; tab-3 registration/unregistration uses the stored identical closure. Remote-command imports write channel data only.

## Handoff inventory

| Site | ORIGINAL member / line | Callee | Every named argument, in original order |
| --- | --- | --- | --- |
| P1 | `_DebrifyTVScreenState._watch` / 4841 | `VideoPlayerScreen` | `videoUrl: firstUrl`, `title: firstTitleResolved`, `startFromRandom: _quickStartRandom`, `randomStartMaxPercent: _quickRandomStartPercent`, `hideSeekbar: _quickHideSeekbar`, `showChannelName: _quickShowChannelName`, `channelName: null`, `channelNumber: null`, `showVideoTitle: _quickShowVideoTitle`, `hideOptions: _quickHideOptions`, `requestMagicNext: requestMagicNext`, `requestNextChannel: _channels.length>1&&(_quickProvider==_providerRealDebrid\|\|_quickProvider==_providerTorbox\|\|_quickProvider==_providerPikPak\|\|_quickProvider==_providerPremiumize)?_requestNextChannel:null`, `channelDirectory: activeChannelDirectory`, `requestChannelById: _channels.length>1?_requestChannelById:null` |
| P2 | `_DebrifyTVScreenState._watch` / 5190 | `VideoPlayerScreen` | `videoUrl: firstUrl`, `title: firstTitle`, `startFromRandom: _quickStartRandom`, `randomStartMaxPercent: _quickRandomStartPercent`, `hideSeekbar: _quickHideSeekbar`, `showChannelName: _quickShowChannelName`, `channelName: null`, `channelNumber: null`, `showVideoTitle: _quickShowVideoTitle`, `hideOptions: _quickHideOptions`, `requestMagicNext: requestMagicNext`, `requestNextChannel: _channels.length>1&&(_quickProvider==_providerRealDebrid\|\|_quickProvider==_providerTorbox\|\|_quickProvider==_providerPikPak)?_requestNextChannel:null`, `channelDirectory: quickChannelDirectory`, `requestChannelById: _channels.length>1?_requestChannelById:null` |
| N1 | `_DebrifyTVScreenState._watch` / 4817 | `_launchRealDebridOnAndroidTv` | `firstStream: first`, `requestNext: requestMagicNext`, `showChannelNameOverride: _quickShowChannelName`, `channelId: activeChannelId`, `channelNumber: activeChannelNumber`, `channelDirectory: activeChannelDirectory` |
| N2 | `_DebrifyTVScreenState._watch` / 5168 | `_launchRealDebridOnAndroidTv` | `firstStream: first`, `requestNext: requestMagicNext`, `showChannelNameOverride: _quickShowChannelName`, `channelId: activeChannelId`, `channelNumber: activeChannelNumber`, `channelDirectory: quickChannelDirectory` |
| P3 | `_DebrifyTVScreenState._watchWithTorbox` / 5581 | `VideoPlayerScreen` | `videoUrl: first['url']??''`, `title: first['title']??'Debrify TV'`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `showChannelName: _showChannelName`, `channelName: null`, `channelNumber: null`, `showVideoTitle: _showVideoTitle`, `hideOptions: _hideOptions`, `requestMagicNext: requestTorboxNext`, `requestNextChannel: _channels.length>1&&(_quickProvider==_providerRealDebrid\|\|_quickProvider==_providerTorbox\|\|_quickProvider==_providerPikPak)?_requestNextChannel:null` |
| N3 | `_DebrifyTVScreenState._watchWithTorbox` / 5559 | `_launchTorboxOnAndroidTv` | `firstStream: first`, `requestNext: requestTorboxNext`, `showChannelNameOverride: _quickShowChannelName`, `channelName: null`, `channelId: null`, `channelNumber: null`, `channelDirectory: null` |
| P4 | `_DebrifyTVScreenState._watchWithPikPak` / 5863 | `VideoPlayerScreen` | `videoUrl: first['url']??''`, `title: first['title']??'Debrify TV'`, `startFromRandom: _quickStartRandom`, `randomStartMaxPercent: _quickRandomStartPercent`, `hideSeekbar: _quickHideSeekbar`, `showChannelName: _quickShowChannelName`, `channelName: null`, `channelNumber: null`, `showVideoTitle: _quickShowVideoTitle`, `hideOptions: _quickHideOptions`, `requestMagicNext: requestPikPakNext`, `requestNextChannel: _channels.length>1&&(_quickProvider==_providerRealDebrid\|\|_quickProvider==_providerTorbox\|\|_quickProvider==_providerPikPak)?_requestNextChannel:null` |
| N4 | `_DebrifyTVScreenState._watchWithPikPak` / 5841 | `_launchPikPakOnAndroidTv` | `firstStream: first`, `requestNext: requestPikPakNext`, `showChannelNameOverride: _quickShowChannelName`, `channelName: null`, `channelId: null`, `channelNumber: null`, `channelDirectory: null` |
| P5 | `_DebrifyTVScreenState._watchWithCachedTorrents` / 6165 | `VideoPlayerScreen` | `videoUrl: firstUrl`, `title: firstTitle`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `showChannelName: _showChannelName`, `channelName: channelName`, `channelNumber: channelNumber`, `showVideoTitle: _showVideoTitle`, `hideOptions: _hideOptions`, `requestMagicNext: requestMagicNext`, `requestNextChannel: _channels.length>1&&(_provider==_providerRealDebrid\|\|_provider==_providerTorbox\|\|_provider==_providerPikPak\|\|_provider==_providerPremiumize)?_requestNextChannel:null`, `channelDirectory: channelDirectory`, `requestChannelById: _channels.length>1?_requestChannelById:null` |
| N5 | `_DebrifyTVScreenState._watchWithCachedTorrents` / 6141 | `_launchRealDebridOnAndroidTv` | `firstStream: first`, `requestNext: requestMagicNext`, `channelName: channelName`, `channelId: channelId`, `channelNumber: channelNumber`, `channelDirectory: channelDirectory` |
| P6 | `_DebrifyTVScreenState._watchAllDebridWithCachedTorrents` / 6417 | `VideoPlayerScreen` | `videoUrl: firstUrl`, `title: firstTitle`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `showChannelName: _showChannelName`, `channelName: channelName`, `channelNumber: channelNumber`, `showVideoTitle: _showVideoTitle`, `hideOptions: _hideOptions`, `requestMagicNext: requestMagicNext`, `requestNextChannel: _channels.length>1&&(_provider==_providerRealDebrid\|\|_provider==_providerTorbox\|\|_provider==_providerPikPak\|\|_provider==_providerPremiumize\|\|_provider==_providerAllDebrid)?_requestNextChannel:null`, `channelDirectory: channelDirectory`, `requestChannelById: _channels.length>1?_requestChannelById:null` |
| N6 | `_DebrifyTVScreenState._watchAllDebridWithCachedTorrents` / 6395 | `_launchRealDebridOnAndroidTv` | `firstStream: first`, `requestNext: requestMagicNext`, `channelName: channelName`, `channelId: channelId`, `channelNumber: channelNumber`, `channelDirectory: channelDirectory` |
| B1 | `_DebrifyTVScreenState._launchTorboxOnAndroidTv` / 6491 | `launchTorboxPlayback` | `initialUrl: initialUrl`, `title: title.isEmpty?'Debrify TV':title`, `magnets: magnets`, `requestNext: requestNext`, `requestChannelSwitch: _channels.length>1?_requestNextChannel:null`, `requestChannelById: _channels.length>1?_requestChannelById:null`, `onFinished: ()async{AndroidTvPlayerBridge.clearTorboxProvider();if(!mounted){return;}setState((){_status=_queue.isEmpty?'':'Queue has ${_queue.length} remaining';});}`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `hideOptions: _hideOptions`, `showVideoTitle: _showVideoTitle`, `showChannelName: showChannelNameOverride??_showChannelName`, `channelName: channelName`, `channels: channelDirectory`, `currentChannelId: channelId??_currentWatchingChannelId`, `currentChannelNumber: channelNumber` |
| B2 | `_DebrifyTVScreenState._launchRealDebridOnAndroidTv` / 7164 | `launchRealDebridPlayback` | `initialUrl: initialUrl`, `title: title.isEmpty?'Debrify TV':title`, `channelName: channelName`, `requestNext: requestNext`, `requestChannelSwitch: canSwitchChannels?_requestNextChannel:null`, `requestChannelById: canSwitchChannels?_requestChannelById:null`, `onFinished: ()async{debugPrint('DebrifyTV: Android TV playback finished callback');await_stopPrefetch();debugPrint('DebrifyTV: Stopped prefetcher on player exit');AndroidTvPlayerBridge.clearStreamProvider();_currentWatchingChannelId=null;if(!mounted)return;setState((){_status=_queue.isEmpty?'':'Queue has ${_queue.length} remaining';});}`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `hideOptions: _hideOptions`, `showVideoTitle: _showVideoTitle`, `showChannelName: showChannelNameOverride??_showChannelName`, `channels: channelDirectory`, `currentChannelId: channelId??_currentWatchingChannelId`, `currentChannelNumber: channelNumber` |
| P7 | `_DebrifyTVScreenState._watchTorboxWithCachedTorrents` / 7459 | `VideoPlayerScreen` | `videoUrl: first['url']??''`, `title: first['title']??'Debrify TV'`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `showChannelName: _showChannelName`, `channelName: channelName`, `channelNumber: channelNumber`, `showVideoTitle: _showVideoTitle`, `hideOptions: _hideOptions`, `requestMagicNext: requestTorboxNext`, `requestNextChannel: _channels.length>1&&(_provider==_providerRealDebrid\|\|_provider==_providerTorbox\|\|_provider==_providerPikPak\|\|_provider==_providerPremiumize)?_requestNextChannel:null`, `channelDirectory: channelDirectory`, `requestChannelById: _channels.length>1?_requestChannelById:null` |
| N7 | `_DebrifyTVScreenState._watchTorboxWithCachedTorrents` / 7442 | `_launchTorboxOnAndroidTv` | `firstStream: first`, `requestNext: requestTorboxNext`, `channelName: channelName`, `channelId: channelId`, `channelNumber: channelNumber`, `channelDirectory: channelDirectory` |
| P8 | `_DebrifyTVScreenState._watchPikPakWithCachedTorrents` / 7630 | `VideoPlayerScreen` | `videoUrl: first['url']??''`, `title: first['title']??'Debrify TV'`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `showChannelName: _showChannelName`, `channelName: channelName`, `channelNumber: channelNumber`, `showVideoTitle: _showVideoTitle`, `hideOptions: _hideOptions`, `requestMagicNext: requestPikPakNext`, `requestNextChannel: _channels.length>1&&(_provider==_providerRealDebrid\|\|_provider==_providerTorbox\|\|_provider==_providerPikPak\|\|_provider==_providerPremiumize)?_requestNextChannel:null`, `channelDirectory: channelDirectory`, `requestChannelById: _channels.length>1?_requestChannelById:null` |
| N8 | `_DebrifyTVScreenState._watchPikPakWithCachedTorrents` / 7613 | `_launchPikPakOnAndroidTv` | `firstStream: first`, `requestNext: requestPikPakNext`, `channelName: channelName`, `channelId: channelId`, `channelNumber: channelNumber`, `channelDirectory: channelDirectory` |
| B3 | `_DebrifyTVScreenState._launchPikPakOnAndroidTv` / 7698 | `launchTorboxPlayback` | `initialUrl: initialUrl`, `title: title.isEmpty?'Debrify TV':title`, `magnets: const[]`, `requestNext: requestNext`, `requestChannelSwitch: _channels.length>1?_requestNextChannel:null`, `requestChannelById: _channels.length>1?_requestChannelById:null`, `onFinished: ()async{AndroidTvPlayerBridge.clearTorboxProvider();if(!mounted){return;}setState((){_status=_queue.isEmpty?'':'Queue has ${_queue.length} remaining';});}`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `hideOptions: _hideOptions`, `showVideoTitle: _showVideoTitle`, `showChannelName: showChannelNameOverride??_showChannelName`, `channelName: channelName`, `channels: channelDirectory`, `currentChannelId: channelId??_currentWatchingChannelId`, `currentChannelNumber: channelNumber` |
| P9 | `_DebrifyTVScreenState._playNextFromQueue` / 7887 | `VideoPlayerScreen` | `videoUrl: videoUrl`, `title: next.name`, `startFromRandom: _quickStartRandom`, `randomStartMaxPercent: _quickRandomStartPercent`, `hideSeekbar: _quickHideSeekbar`, `showChannelName: _quickShowChannelName`, `channelName: null`, `channelNumber: null`, `showVideoTitle: _quickShowVideoTitle`, `hideOptions: _quickHideOptions` |
| P10 | `_DebrifyTVScreenState._watchPremiumizeWithCachedTorrents` / 10166 | `VideoPlayerScreen` | `videoUrl: first['url']??''`, `title: first['title']??'Debrify TV'`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `showChannelName: _showChannelName`, `channelName: channelName`, `channelNumber: channelNumber`, `showVideoTitle: _showVideoTitle`, `hideOptions: _hideOptions`, `requestMagicNext: requestPremiumizeNext`, `requestNextChannel: _channels.length>1&&(_provider==_providerRealDebrid\|\|_provider==_providerTorbox\|\|_provider==_providerPikPak\|\|_provider==_providerPremiumize)?_requestNextChannel:null`, `channelDirectory: channelDirectory`, `requestChannelById: _channels.length>1?_requestChannelById:null` |
| N9 | `_DebrifyTVScreenState._watchPremiumizeWithCachedTorrents` / 10152 | `_launchPikPakOnAndroidTv` | `firstStream: first`, `requestNext: requestPremiumizeNext`, `channelName: channelName`, `channelId: channelId`, `channelNumber: channelNumber`, `channelDirectory: channelDirectory` |
| P11 | `_DebrifyTVScreenState._watchWithPremiumize` / 10461 | `VideoPlayerScreen` | `videoUrl: first['url']??''`, `title: first['title']??'Debrify TV'`, `startFromRandom: _startRandom`, `randomStartMaxPercent: _randomStartPercent`, `hideSeekbar: _hideSeekbar`, `showChannelName: _showChannelName`, `channelName: null`, `channelNumber: null`, `showVideoTitle: _showVideoTitle`, `hideOptions: _hideOptions`, `requestMagicNext: requestPremiumizeNext`, `requestNextChannel: _channels.length>1&&(_quickProvider==_providerRealDebrid\|\|_quickProvider==_providerTorbox\|\|_quickProvider==_providerPikPak\|\|_quickProvider==_providerPremiumize)?_requestNextChannel:null` |
| N10 | `_DebrifyTVScreenState._watchWithPremiumize` / 10445 | `_launchPikPakOnAndroidTv` | `firstStream: first`, `requestNext: requestPremiumizeNext`, `showChannelNameOverride: _quickShowChannelName`, `channelName: null`, `channelId: null`, `channelNumber: null`, `channelDirectory: null` |
| P12 | `_DebrifyTVScreenState._watchWithAllDebrid` / 10734 | `VideoPlayerScreen` | `videoUrl: first['url']??''`, `title: firstTitle`, `startFromRandom: _quickStartRandom`, `randomStartMaxPercent: _quickRandomStartPercent`, `hideSeekbar: _quickHideSeekbar`, `showChannelName: _quickShowChannelName`, `channelName: null`, `channelNumber: null`, `showVideoTitle: _quickShowVideoTitle`, `hideOptions: _quickHideOptions`, `requestMagicNext: requestMagicNext`, `requestNextChannel: _channels.length>1&&(_quickProvider==_providerRealDebrid\|\|_quickProvider==_providerTorbox\|\|_quickProvider==_providerPikPak\|\|_quickProvider==_providerPremiumize\|\|_quickProvider==_providerAllDebrid)?_requestNextChannel:null` |
| N11 | `_DebrifyTVScreenState._watchWithAllDebrid` / 10719 | `_launchRealDebridOnAndroidTv` | `firstStream: first`, `requestNext: requestMagicNext`, `showChannelNameOverride: _quickShowChannelName`, `channelId: null`, `channelNumber: null`, `channelDirectory: null` |

The [handoff ledger](../../dev/tool/debrify_tv_handoff_ledger.json) contains exact named-argument token pairs for 12 Flutter constructors (11 live + dormant P9), 11 native-helper invocations and 3 bridge calls, plus every VideoPlayerScreen constructor default. Callback presence and observable results are asserted through typed accessors without mounting the player. Native payload/onFinished expressions remain source evidence on this host.

## Delays and diagnostic inventory

| Member | ORIGINAL delay/timer expression |
| --- | --- |
| `_SpotlightChoiceChipState.build` | `Duration(milliseconds: 150)` |
| `_DebrifyTVScreenState._checkPendingAutoPlay` | `Duration(milliseconds: 100)` |
| `_DebrifyTVScreenState._handleImportChannels` | `Duration(milliseconds: 100)` |
| `_DebrifyTVScreenState._handleImportChannels` | `endOfFrame` |
| `_DebrifyTVScreenState._handleImportChannels` | `endOfFrame` |
| `_DebrifyTVScreenState._handleImportChannelsFromCommunity` | `Duration(milliseconds: 100)` |
| `_DebrifyTVScreenState._handleImportChannelsFromCommunity` | `endOfFrame` |
| `_DebrifyTVScreenState._handleImportChannelsFromCommunity` | `endOfFrame` |
| `_DebrifyTVScreenState._handleImportChannelsFromCommunity` | `Duration(seconds: 2)` |
| `_DebrifyTVScreenState._handleDeleteChannel` | `Duration(milliseconds: 100)` |
| `_DebrifyTVScreenState._handleDeleteChannel` | `endOfFrame` |
| `_DebrifyTVScreenState._handleDeleteChannel` | `endOfFrame` |
| `_DebrifyTVScreenState._handleDeleteAllChannels` | `Duration(milliseconds: 100)` |
| `_DebrifyTVScreenState._handleDeleteAllChannels` | `endOfFrame` |
| `_DebrifyTVScreenState._handleDeleteAllChannels` | `endOfFrame` |
| `_DebrifyTVScreenState._watch` | `Duration(seconds: 4)` |
| `_DebrifyTVScreenState._watch` | `Duration(seconds: 4)` |
| `_DebrifyTVScreenState._switchToChannel` | `Duration(seconds: 5)` |
| `_DebrifyTVScreenState._showChannelCreationDialog` | `Duration(milliseconds: 260)` |
| `_DebrifyTVScreenState._showCachedPlaybackDialog` | `Duration(milliseconds: 260)` |
| `_DebrifyTVScreenState._playNextFromQueue` | `Duration(seconds: 4)` |
| `_DebrifyTVScreenState._onSpotlightChannelFocused` | `Timer(` |
| `_DebrifyTVScreenState._onSpotlightChannelFocused` | `Duration(milliseconds: 250)` |
| `_DebrifyTVScreenState._buildTopActionButton` | `Duration(milliseconds: 150)` |
| `_DebrifyTVScreenState._buildTopMenuButton` | `Duration(milliseconds: 150)` |
| `_DebrifyTVScreenState._buildSettingsCard` | `Duration(seconds: 2)` |
| `_DebrifyTVScreenState._showQuickPlayDialog` | `Duration(milliseconds: 100)` |
| `_DebrifyTVScreenState._showQuickPlayDialog` | `endOfFrame` |
| `_DebrifyTVScreenState._showQuickPlayDialog` | `endOfFrame` |
| `_DebrifyTVScreenState._prepareTorboxTorrent` | `Duration(milliseconds: 400)` |
| `_DebrifyTVScreenState._showSnack` | `Duration(seconds: 3)` |
| `_DebrifyTVScreenState._runPrefetchLoop` | `Duration(milliseconds: 750)` |
| `_DebrifyTVScreenState._runPrefetchLoop` | `Duration(milliseconds: 750)` |
| `_DebrifyTVScreenState._runPrefetchLoop` | `Duration(milliseconds: prepared <= 2 ? 75 : 150)` |
| `_DebrifyTVScreenState._runPrefetchLoop` | `Duration(seconds: 1)` |

Root ORIGINAL: 50 identities (17 warnings, 33 infos). Strict ORIGINAL: 72 (root + 21 directives_ordering + one prefer_const_constructors at 3521). Warning ownership: six unused elements, six write-only fields, four unused locals, one unnecessary cast. Info ownership: eight sort_child_properties_last, six no_leading_underscores_for_local_identifiers, one prefer_interpolation_to_compose_strings, thirteen use_build_context_synchronously, five control_flow_in_finally. Machine inventories are in the evidence namespace; line relocation is not a new diagnostic. Rename/receiver probe records removals and additions by identity; maximum per identity is used, never summed.

## Reviewed per-leaf wiring checklist

### `_randomStartPercentDefault`

ORIGINAL lines 84–84; step 1; destination `lib/features/debrify_tv/application/debrify_tv_random_start.dart` → `randomStartPercentDefault`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_randomStartPercentMin`

ORIGINAL lines 85–85; step 1; destination `lib/features/debrify_tv/application/debrify_tv_random_start.dart` → `randomStartPercentMin`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_randomStartPercentMax`

ORIGINAL lines 86–86; step 1; destination `lib/features/debrify_tv/application/debrify_tv_random_start.dart` → `randomStartPercentMax`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_clampRandomStartPercent`

ORIGINAL lines 88–97; step 1; destination `lib/features/debrify_tv/application/debrify_tv_random_start.dart` → `clampDebrifyTvRandomStartPercent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_parseRandomStartPercent`

ORIGINAL lines 99–113; step 1; destination `lib/features/debrify_tv/application/debrify_tv_random_start.dart` → `_parseRandomStartPercent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_SettingsScope`

ORIGINAL lines 115–115; step 1; destination `lib/features/debrify_tv/models/debrify_tv_kinds.dart` → `DebrifyTvSettingsScope`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTvTopMenuAction`

ORIGINAL lines 117–117; step 1; destination `lib/features/debrify_tv/models/debrify_tv_kinds.dart` → `DebrifyTvTopMenuAction`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_ChannelImportOrigin`

ORIGINAL lines 119–119; step 1; destination `lib/features/debrify_tv/models/debrify_tv_kinds.dart` → `DebrifyTvChannelImportOrigin`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_ChannelImportType`

ORIGINAL lines 121–121; step 1; destination `lib/features/debrify_tv/models/debrify_tv_kinds.dart` → `DebrifyTvChannelImportType`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_SpotlightMetaPill`

ORIGINAL lines 123–167; step 3; destination `lib/features/debrify_tv/presentation/debrify_tv_meta_pill.dart` → `_SpotlightMetaPill`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@5103 lexical decl:member/method1#context#0 scope=member/method1/block0 read`.
### `_SpotlightChoiceChip`

ORIGINAL lines 169–186; step 3; destination `lib/features/debrify_tv/presentation/debrify_tv_choice_chip.dart` → `_SpotlightChoiceChip`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_SpotlightChoiceChipState._focused`

ORIGINAL lines 189–189; step 3; destination `lib/features/debrify_tv/presentation/debrify_tv_choice_chip.dart` → `_SpotlightChoiceChipState._focused`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_SpotlightChoiceChipState.build`

ORIGINAL lines 191–283; step 3; destination `lib/features/debrify_tv/presentation/debrify_tv_choice_chip.dart` → `_SpotlightChoiceChipState.build`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@6714 lexical decl:member#context#0 scope=member/block0 read`; `setState@7143 lexical unbound scope=member/block0/closure0 invocation`.
### `_formatBytes`

ORIGINAL lines 286–297; step 1; destination `lib/features/debrify_tv/application/debrify_tv_byte_format.dart` → `formatDebrifyTvBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_parseZipInBackground`

ORIGINAL lines 299–301; step 1; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_parsing.dart` → `parseZipInBackground`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_parseZipCompute`

ORIGINAL lines 303–305; step 1; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_parsing.dart` → `_parseZipCompute`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_parseYamlInBackground`

ORIGINAL lines 307–315; step 1; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_parsing.dart` → `parseYamlInBackground`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_parseYamlCompute`

ORIGINAL lines 317–324; step 1; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_parsing.dart` → `_parseYamlCompute`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_TvEngineWarmResult`

ORIGINAL lines 326–338; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart` → `_TvEngineWarmResult`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `DebrifyTVScreen`

ORIGINAL lines 340–345; step 0; destination `lib/screens/magic_tv_screen.dart` → `DebrifyTVScreen`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._providerRealDebrid`

ORIGINAL lines 348–348; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.providerRealDebrid`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._providerTorbox`

ORIGINAL lines 349–349; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.providerTorbox`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._providerPikPak`

ORIGINAL lines 350–350; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.providerPikPak`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._providerPremiumize`

ORIGINAL lines 351–351; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.providerPremiumize`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._providerAllDebrid`

ORIGINAL lines 352–352; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.providerAllDebrid`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._torboxFileEntryType`

ORIGINAL lines 353–353; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.torboxFileEntryType`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._torboxMinVideoSizeBytes`

ORIGINAL lines 354–355; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.torboxMinVideoSizeBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._settingsManager`

ORIGINAL lines 357–357; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.settingsManager`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._keywordsController`

ORIGINAL lines 358–358; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_library_state.dart` → `DebrifyTvLibraryState.keywordsController`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._queue`

ORIGINAL lines 360–360; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.queue`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._isBusy`

ORIGINAL lines 361–361; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.isBusy`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._status`

ORIGINAL lines 362–362; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.status`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channels`

ORIGINAL lines 363–363; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_library_state.dart` → `DebrifyTvLibraryState.channels`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._debrifyTvStyle`

ORIGINAL lines 365–368; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_library_state.dart` → `DebrifyTvLibraryState.debrifyTvStyle`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// `debrify_tv_style`, read once per mount from the mirror warmed in
/// `main()`: tabs are keyed by index and rebuilt on switch, so a picker
/// change is picked up on the next entry — no bridge, like `iptv_style`.
```
### `_DebrifyTVScreenState._spotlightRailHealth`

ORIGINAL lines 371–371; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_stage_state.dart` → `DebrifyTvStageState.spotlightRailHealth`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._spotlightStats`

ORIGINAL lines 372–372; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_stage_state.dart` → `DebrifyTvStageState.spotlightStats`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._spotlightStatsDebounce`

ORIGINAL lines 373–373; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_stage_state.dart` → `DebrifyTvStageState.spotlightStatsDebounce`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._spotlightFocusedId`

ORIGINAL lines 374–374; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_stage_state.dart` → `DebrifyTvStageState.spotlightFocusedId`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelCache`

ORIGINAL lines 375–375; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_library_state.dart` → `DebrifyTvLibraryState.channelCache`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._pikpakCandidatePool`

ORIGINAL lines 376–376; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.pikpakCandidatePool`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._tvEngineStates`

ORIGINAL lines 377–377; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.tvEngineStates`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._tvSmallChannelMaxByEngine`

ORIGINAL lines 378–378; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.tvSmallChannelMaxByEngine`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._tvLargeChannelMaxByEngine`

ORIGINAL lines 379–379; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.tvLargeChannelMaxByEngine`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._tvQuickPlayMaxByEngine`

ORIGINAL lines 380–380; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.tvQuickPlayMaxByEngine`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelBatchSize`

ORIGINAL lines 381–381; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.channelBatchSize`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._keywordThreshold`

ORIGINAL lines 382–382; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.keywordThreshold`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._minTorrentsPerKeyword`

ORIGINAL lines 383–383; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.minTorrentsPerKeyword`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickPlayMaxKeywords`

ORIGINAL lines 386–386; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickPlayMaxKeywords`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._playbackTorrentThreshold`

ORIGINAL lines 388–388; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.playbackTorrentThreshold`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._maxTorrentsPerKeywordPlayback`

ORIGINAL lines 389–389; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.maxTorrentsPerKeywordPlayback`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._minimumTorrentsForChannel`

ORIGINAL lines 390–390; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.minimumTorrentsForChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._maxChannelKeywords`

ORIGINAL lines 391–391; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.maxChannelKeywords`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._keywordWarmEstimateMs`

ORIGINAL lines 392–392; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.keywordWarmEstimateMs`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelSearchController`

ORIGINAL lines 393–394; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.channelSearchController`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelSearchTerm`

ORIGINAL lines 395–395; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.channelSearchTerm`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._currentWatchingChannelId`

ORIGINAL lines 396–397; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_library_state.dart` → `DebrifyTvLibraryState.currentWatchingChannelId`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._startRandom`

ORIGINAL lines 400–400; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.startRandom`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._randomStartPercent`

ORIGINAL lines 401–401; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.randomStartPercent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._hideSeekbar`

ORIGINAL lines 402–402; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.hideSeekbar`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._showChannelName`

ORIGINAL lines 403–403; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.showChannelName`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._showVideoTitle`

ORIGINAL lines 404–404; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.showVideoTitle`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._hideOptions`

ORIGINAL lines 405–405; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.hideOptions`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._hideBackButton`

ORIGINAL lines 406–406; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.hideBackButton`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._provider`

ORIGINAL lines 407–407; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.provider`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 14072 / read / `member` |
### `_DebrifyTVScreenState._quickStartRandom`

ORIGINAL lines 410–410; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickStartRandom`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickRandomStartPercent`

ORIGINAL lines 411–411; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickRandomStartPercent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickHideSeekbar`

ORIGINAL lines 412–412; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickHideSeekbar`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickShowChannelName`

ORIGINAL lines 413–413; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickShowChannelName`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickShowVideoTitle`

ORIGINAL lines 414–414; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickShowVideoTitle`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickHideOptions`

ORIGINAL lines 415–415; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickHideOptions`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickHideBackButton`

ORIGINAL lines 416–416; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickHideBackButton`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickAvoidNsfw`

ORIGINAL lines 417–417; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickAvoidNsfw`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._viewerForcesNsfw`

ORIGINAL lines 419–423; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.viewerForcesNsfw`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// The viewer-scoped, role-locked NSFW rail: forced for a child profile
/// regardless of any channel's stored flag or dialog toggle. Evaluated
/// live so a profile switch retunes filtering without a rebuild dance.
```
### `_DebrifyTVScreenState._rdSkipBlockedTorrents`

ORIGINAL lines 424–424; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.rdSkipBlockedTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickProvider`

ORIGINAL lines 425–425; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.quickProvider`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 14812 / read / `member` |
### `_DebrifyTVScreenState._tvFilters`

ORIGINAL lines 431–431; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.tvFilters`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._qualityFallbackNotified`

ORIGINAL lines 433–433; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.qualityFallbackNotified`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._rdSizeRejectionLimit`

ORIGINAL lines 436–436; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.rdSizeRejectionLimit`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._rdSizeRejections`

ORIGINAL lines 437–437; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.rdSizeRejections`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._sizeFilterRelaxed`

ORIGINAL lines 438–438; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.sizeFilterRelaxed`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._rdAvailable`

ORIGINAL lines 440–440; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.rdAvailable`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._torboxAvailable`

ORIGINAL lines 441–441; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.torboxAvailable`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._pikpakAvailable`

ORIGINAL lines 442–442; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.pikpakAvailable`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._premiumizeAvailable`

ORIGINAL lines 443–443; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.premiumizeAvailable`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._allDebridAvailable`

ORIGINAL lines 444–444; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.allDebridAvailable`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._seenRestrictedLinks`

ORIGINAL lines 446–446; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.seenRestrictedLinks`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._seenLinkWithTorrentId`

ORIGINAL lines 447–447; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.seenLinkWithTorrentId`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._minPrepared`

ORIGINAL lines 449–449; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.minPrepared`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._lookaheadWindow`

ORIGINAL lines 450–450; step 1; destination `lib/features/debrify_tv/models/debrify_tv_constants.dart` → `DebrifyTvConstants.lookaheadWindow`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._prefetchRunning`

ORIGINAL lines 451–451; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart` → `DebrifyTvPrefetchState.prefetchRunning`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._prefetchStopRequested`

ORIGINAL lines 452–452; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart` → `DebrifyTvPrefetchState.prefetchStopRequested`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._prefetchTask`

ORIGINAL lines 453–453; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart` → `DebrifyTvPrefetchState.prefetchTask`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._prefetchEpoch`

ORIGINAL lines 457–457; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart` → `DebrifyTvPrefetchState.prefetchEpoch`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._activeApiKey`

ORIGINAL lines 458–458; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart` → `DebrifyTvPrefetchState.activeApiKey`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._activeProvider`

ORIGINAL lines 463–463; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart` → `DebrifyTvPrefetchState.activeProvider`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 16699 / read / `member` |
### `_DebrifyTVScreenState._inflightInfohashes`

ORIGINAL lines 464–464; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch_state.dart` → `DebrifyTvPrefetchState.inflightInfohashes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._isAndroidTv`

ORIGINAL lines 465–465; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_state.dart` → `DebrifyTvSettingsState.isAndroidTv`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._showSearchBar`

ORIGINAL lines 466–466; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.showSearchBar`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._favoriteChannelIds`

ORIGINAL lines 467–467; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_library_state.dart` → `DebrifyTvLibraryState.favoriteChannelIds`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelSearchFocusNode`

ORIGINAL lines 468–468; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.channelSearchFocusNode`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickPlayFocusNode`

ORIGINAL lines 469–471; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.quickPlayFocusNode`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelSearchButtonFocusNode`

ORIGINAL lines 472–474; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.channelSearchButtonFocusNode`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelSearchClearFocusNode`

ORIGINAL lines 475–477; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.channelSearchClearFocusNode`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelMenuFocusNode`

ORIGINAL lines 478–480; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.channelMenuFocusNode`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._channelMenuController`

ORIGINAL lines 481–481; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.channelMenuController`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._tvContentFocusHandler`

ORIGINAL lines 484–484; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_focus_state.dart` → `DebrifyTvFocusState.tvContentFocusHandler`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._progress`

ORIGINAL lines 487–487; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_progress_state.dart` → `DebrifyTvProgressState.progress`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._progressSheetContext`

ORIGINAL lines 488–488; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_progress_state.dart` → `DebrifyTvProgressState.progressSheetContext`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._progressOpen`

ORIGINAL lines 489–489; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_progress_state.dart` → `DebrifyTvProgressState.progressOpen`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._lastQueueSize`

ORIGINAL lines 490–490; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.lastQueueSize`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._lastSearchAt`

ORIGINAL lines 491–491; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.lastSearchAt`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._launchedPlayer`

ORIGINAL lines 492–492; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.launchedPlayer`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._watchCancelled`

ORIGINAL lines 493–493; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.watchCancelled`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._originalMaxCap`

ORIGINAL lines 494–494; step 2; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_session_state.dart` → `DebrifyTvSessionState.originalMaxCap`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState.initState`

ORIGINAL lines 496–521; step 0; destination `lib/screens/magic_tv_screen.dart` → `_DebrifyTVScreenState.initState`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 17925 / write / `member/block0` |
| `_tvContentFocusHandler` → `_owners.focus.tvContentFocusHandler` | 18450 / write / `member/block0`; 18581 / read-write / `member/block0` |
| `_quickPlayFocusNode` → `_owners.focus.quickPlayFocusNode` | 18486 / read / `member/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// also warms the Spotlight rail health, once per reload
// Register watch channel handler for external calls (e.g., from home screen)
// Register TV sidebar focus handler (tab index 3 = Debrify TV)
// Check for pending auto-play from home screen
```
### `_DebrifyTVScreenState.dispose`

ORIGINAL lines 523–553; step 0; destination `lib/screens/magic_tv_screen.dart` → `_DebrifyTVScreenState.dispose`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_spotlightStatsDebounce` → `_owners.stage.spotlightStatsDebounce` | 18794 / read / `member/block0` |
| `_tvContentFocusHandler` → `_owners.focus.tvContentFocusHandler` | 19027 / read / `member/block0/if0`; 19134 / read-write / `member/block0/if0/block0` |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 19252 / write / `member/block0` |
| `_progressSheetContext` → `_owners.progress.progressSheetContext` | 19374 / write / `member/block0` |
| `_progressOpen` → `_owners.progress.progressOpen` | 19408 / write / `member/block0` |
| `_progress` → `_owners.progress.progress` | 19435 / read / `member/block0` |
| `_keywordsController` → `_owners.library.keywordsController` | 19460 / read / `member/block0` |
| `_channelSearchController` → `_owners.focus.channelSearchController` | 19495 / read / `member/block0` |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 19535 / read / `member/block0` |
| `_quickPlayFocusNode` → `_owners.focus.quickPlayFocusNode` | 19574 / read / `member/block0` |
| `_channelSearchButtonFocusNode` → `_owners.focus.channelSearchButtonFocusNode` | 19609 / read / `member/block0` |
| `_channelSearchClearFocusNode` → `_owners.focus.channelSearchClearFocusNode` | 19654 / read / `member/block0` |
| `_channelMenuFocusNode` → `_owners.focus.channelMenuFocusNode` | 19698 / read / `member/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Clear watch channel handler
// Ensure prefetch loop is stopped if this screen is disposed mid-run
// Clean up dialog state to avoid dangling context references
```
### `_DebrifyTVScreenState._handleChannelSearchBarBack`

ORIGINAL lines 555–583; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar.handleChannelSearchBarBack`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@20388 lexical unbound scope=member/block0/if1/block0/if0/block0 invocation`; `setState@20718 lexical unbound scope=member/block0/if1/block0/if1/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelSearchController` → `_owners.focus.channelSearchController` | 20294 / read / `member/block0/if1/block0/if0`; 20346 / read / `member/block0/if1/block0/if0/block0` |
| `_channelSearchTerm` → `_owners.focus.channelSearchTerm` | 20412 / write / `member/block0/if1/block0/if0/block0/closure0/block0` |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 20595 / read / `member/block0/if1/block0/if0/block0` |
| `_showSearchBar` → `_owners.focus.showSearchBar` | 20692 / read / `member/block0/if1/block0/if1`; 20742 / write / `member/block0/if1/block0/if1/block0/closure0/block0` |
| `_channelSearchButtonFocusNode` → `_owners.focus.channelSearchButtonFocusNode` | 20786 / read / `member/block0/if1/block0/if1/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Back/Escape ladder for the channel search bar: clear text first, then
/// close the bar. Sits on an ancestor Focus of the search field so it runs
/// when the TvTextField shell lets the key bubble.
// Clearing unmounts the suffix ✕ — if IT held focus, focus would be
// stranded; parking on the field covers both cases.
```
### `_DebrifyTVScreenState._closeProgressDialog`

ORIGINAL lines 585–613; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart` → `DebrifyTvFeedback.closeProgressDialog`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@21430 lexical unbound scope=member/block0/closure0/block0/if2 read`; `context@21478 lexical unbound scope=member/block0/closure0/block0/if2/block0/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_progressOpen` → `_owners.progress.progressOpen` | 20966 / read / `member/block0/if0`; 21171 / write / `member/block0/if1/block0`; 21280 / read / `member/block0/closure0/block0/if0`; 21588 / write / `member/block0/closure0/block0` |
| `_progressSheetContext` → `_owners.progress.progressSheetContext` | 21011 / read / `member/block0/if1`; 21077 / read-write / `member/block0/if1/block0/block0`; 21135 / write / `member/block0/if1/block0`; 21331 / read / `member/block0/closure0/block0/if1`; 21552 / write / `member/block0/closure0/block0` |
### `_DebrifyTVScreenState._updateProgress`

ORIGINAL lines 615–631; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart` → `DebrifyTvFeedback.updateProgress`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_progress` → `_owners.progress.progress` | 21909 / read / `member/block0/if1`; 21942 / read / `member/block0/if1/block0`; 22027 / read / `member/block0`; 22068 / read / `member/block0` |
### `_DebrifyTVScreenState._cancelActiveWatch`

ORIGINAL lines 633–690; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart` → `DebrifyTvFeedback.cancelActiveWatch`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@23657 lexical unbound scope=member/block0/if3 read`; `setState@23674 lexical unbound scope=member/block0/if3/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_watchCancelled` → `_owners.session.watchCancelled` | 22324 / read / `member/block0`; 22357 / read / `member/block0/if0`; 22721 / write / `member/block0` |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 22749 / write / `member/block0` |
| `_queue` → `_owners.session.queue` | 23019 / read / `member/block0/if1/block0`; 23058 / read / `member/block0/if1/block0` |
| `_progress` → `_owners.progress.progress` | 23084 / read / `member/block0` |
| `_progressOpen` → `_owners.progress.progressOpen` | 23407 / write / `member/block0/if2/block0`; 23481 / read / `member/block0/if2/if0` |
| `_progressSheetContext` → `_owners.progress.progressSheetContext` | 23436 / write / `member/block0/if2/block0` |
| `_isBusy` → `_owners.session.isBusy` | 23696 / write / `member/block0/if3/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 23721 / write / `member/block0/if3/block0/closure0/block0` |
### `_DebrifyTVScreenState._determineDefaultProvider`

ORIGINAL lines 692–736; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart` → `DebrifyTvSettingsLoader.determineDefaultProvider`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 24094 / read / `member/block0/if0`; 24153 / read / `member/block0/if0/block0`; 24791 / read / `member/block0/if7/block0` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 24201 / read / `member/block0/if1`; 24258 / read / `member/block0/if1/block0`; 24861 / read / `member/block0/if8/block0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 24305 / read / `member/block0/if2`; 24356 / read / `member/block0/if2/block0`; 24927 / read / `member/block0/if9/block0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 24400 / read / `member/block0/if3`; 24451 / read / `member/block0/if3/block0`; 24724 / read / `member/block0/if6/block0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 24495 / read / `member/block0/if4`; 24546 / read / `member/block0/if4/block0`; 24657 / read / `member/block0/if5/block0`; 25033 / read / `member/block0` |

Same-named lexical hazards (must remain bound to the same declaration): `premiumizeAvailable@24117 decl:member#premiumizeAvailable#0 scope=member/block0/if0 read`; `allDebridAvailable@24223 decl:member#allDebridAvailable#0 scope=member/block0/if1 read`; `pikpakAvailable@24324 decl:member#pikpakAvailable#0 scope=member/block0/if2 read`; `torboxAvailable@24419 decl:member#torboxAvailable#0 scope=member/block0/if3 read`; `rdAvailable@24518 decl:member#rdAvailable#0 scope=member/block0/if4 read`; `rdAvailable@24629 decl:member#rdAvailable#0 scope=member/block0/if5 read`; `torboxAvailable@24692 decl:member#torboxAvailable#0 scope=member/block0/if6 read`; `premiumizeAvailable@24755 decl:member#premiumizeAvailable#0 scope=member/block0/if7 read`; `allDebridAvailable@24826 decl:member#allDebridAvailable#0 scope=member/block0/if8 read`; `pikpakAvailable@24895 decl:member#pikpakAvailable#0 scope=member/block0/if9 read`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// If user has a preferred provider that's available, use it
// Fallback: pick first available provider
// No provider available, default to RD (will show as unavailable)
```
### `_DebrifyTVScreenState._isProviderSelectable`

ORIGINAL lines 738–752; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart` → `DebrifyTvSettingsLoader.isProviderSelectable`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 25127 / read / `member/block0/if0` |
| `_torboxAvailable` → `_owners.settings.torboxAvailable` | 25159 / read / `member/block0/if0/block0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 25203 / read / `member/block0/if1` |
| `_pikpakAvailable` → `_owners.settings.pikpakAvailable` | 25235 / read / `member/block0/if1/block0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 25279 / read / `member/block0/if2` |
| `_premiumizeAvailable` → `_owners.settings.premiumizeAvailable` | 25315 / read / `member/block0/if2/block0` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 25363 / read / `member/block0/if3` |
| `_allDebridAvailable` → `_owners.settings.allDebridAvailable` | 25398 / read / `member/block0/if3/block0` |
| `_rdAvailable` → `_owners.settings.rdAvailable` | 25436 / read / `member/block0` |

Same-named lexical hazards (must remain bound to the same declaration): `provider@25115 decl:member#provider#0 scope=member/block0/if0 read`; `provider@25191 decl:member#provider#0 scope=member/block0/if1 read`; `provider@25267 decl:member#provider#0 scope=member/block0/if2 read`; `provider@25351 decl:member#provider#0 scope=member/block0/if3 read`.
### `_DebrifyTVScreenState._loadSettings`

ORIGINAL lines 754–908; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart` → `DebrifyTvSettingsLoader.loadSettings`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@29525 lexical unbound scope=member/block0/if0 read`; `setState@29542 lexical unbound scope=member/block0/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_settingsManager` → `_owners.settings.settingsManager` | 26029 / read / `member/block0`; 27429 / read / `member/block0/for1/block0`; 27568 / read / `member/block0/for1/block0`; 27710 / read / `member/block0/for1/block0`; 27849 / read / `member/block0/for1/block0`; 28003 / read / `member/block0`; 28078 / read / `member/block0`; 28179 / read / `member/block0`; 28279 / read / `member/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 29564 / write / `member/block0/if0/block0/closure0/block0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 29600 / write / `member/block0/if0/block0/closure0/block0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 29676 / write / `member/block0/if0/block0/closure0/block0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 29712 / write / `member/block0/if0/block0/closure0/block0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 29756 / write / `member/block0/if0/block0/closure0/block0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 29798 / write / `member/block0/if0/block0/closure0/block0` |
| `_hideBackButton` → `_owners.settings.hideBackButton` | 29850 / write / `member/block0/if0/block0/closure0/block0` |
| `_rdAvailable` → `_owners.settings.rdAvailable` | 29905 / write / `member/block0/if0/block0/closure0/block0` |
| `_torboxAvailable` → `_owners.settings.torboxAvailable` | 29941 / write / `member/block0/if0/block0/closure0/block0` |
| `_pikpakAvailable` → `_owners.settings.pikpakAvailable` | 29985 / write / `member/block0/if0/block0/closure0/block0` |
| `_premiumizeAvailable` → `_owners.settings.premiumizeAvailable` | 30029 / write / `member/block0/if0/block0/closure0/block0` |
| `_allDebridAvailable` → `_owners.settings.allDebridAvailable` | 30081 / write / `member/block0/if0/block0/closure0/block0` |
| `_provider` → `_owners.settings.provider` | 30131 / write / `member/block0/if0/block0/closure0/block0` |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 30168 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickStartRandom` → `_owners.settings.quickStartRandom` | 30198 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickRandomStartPercent` → `_owners.settings.quickRandomStartPercent` | 30239 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickHideSeekbar` → `_owners.settings.quickHideSeekbar` | 30320 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 30361 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickShowVideoTitle` → `_owners.settings.quickShowVideoTitle` | 30410 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickHideOptions` → `_owners.settings.quickHideOptions` | 30457 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickHideBackButton` → `_owners.settings.quickHideBackButton` | 30514 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 30574 / write / `member/block0/if0/block0/closure0/block0` |
| `_rdSkipBlockedTorrents` → `_owners.settings.rdSkipBlockedTorrents` | 30611 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 30659 / write / `member/block0/if0/block0/closure0/block0` |
| `_tvFilters` → `_owners.settings.tvFilters` | 30701 / write / `member/block0/if0/block0/closure0/block0` |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 30875 / read / `member/block0/if0/block0/closure0/block0` |
| `_tvEngineStates` → `_owners.settings.tvEngineStates` | 30943 / read / `member/block0/if0/block0/closure0/block0` |
| `_tvSmallChannelMaxByEngine` → `_owners.settings.tvSmallChannelMaxByEngine` | 31023 / read / `member/block0/if0/block0/closure0/block0` |
| `_tvLargeChannelMaxByEngine` → `_owners.settings.tvLargeChannelMaxByEngine` | 31125 / read / `member/block0/if0/block0/closure0/block0` |
| `_tvQuickPlayMaxByEngine` → `_owners.settings.tvQuickPlayMaxByEngine` | 31227 / read / `member/block0/if0/block0/closure0/block0` |
| `_channelBatchSize` → `_owners.settings.channelBatchSize` | 31323 / write / `member/block0/if0/block0/closure0/block0` |
| `_keywordThreshold` → `_owners.settings.keywordThreshold` | 31369 / write / `member/block0/if0/block0/closure0/block0` |
| `_minTorrentsPerKeyword` → `_owners.settings.minTorrentsPerKeyword` | 31415 / write / `member/block0/if0/block0/closure0/block0` |
| `_quickPlayMaxKeywords` → `_owners.settings.quickPlayMaxKeywords` | 31471 / write / `member/block0/if0/block0/closure0/block0` |
| `_spotlightFocusedId` → `_owners.stage.spotlightFocusedId` | 31683 / read / `member/block0/if0/block0` |

Same-named lexical hazards (must remain bound to the same declaration): `tvEngineStates@27396 decl:member/block0#tvEngineStates#0 scope=member/block0/for1/block0 read`; `tvSmallChannelMaxByEngine@27524 decl:member/block0#tvSmallChannelMaxByEngine#0 scope=member/block0/for1/block0 read`; `tvLargeChannelMaxByEngine@27666 decl:member/block0#tvLargeChannelMaxByEngine#0 scope=member/block0/for1/block0 read`; `tvQuickPlayMaxByEngine@27808 decl:member/block0#tvQuickPlayMaxByEngine#0 scope=member/block0/for1/block0 read`; `rdAvailable@29334 decl:member/block0#rdAvailable#0 scope=member/block0 read`; `torboxAvailable@29353 decl:member/block0#torboxAvailable#0 scope=member/block0 read`; `pikpakAvailable@29376 decl:member/block0#pikpakAvailable#0 scope=member/block0 read`; `premiumizeAvailable@29399 decl:member/block0#premiumizeAvailable#0 scope=member/block0 read`; `allDebridAvailable@29426 decl:member/block0#allDebridAvailable#0 scope=member/block0 read`; `startRandom@29579 decl:member/block0#startRandom#0 scope=member/block0/if0/block0/closure0/block0 read`; `randomStartPercent@29647 decl:member/block0#randomStartPercent#0 scope=member/block0/if0/block0/closure0/block0 read`; `hideOptions@29691 decl:member/block0#hideOptions#0 scope=member/block0/if0/block0/closure0/block0 read`; `showChannelName@29731 decl:member/block0#showChannelName#0 scope=member/block0/if0/block0/closure0/block0 read`; `showVideoTitle@29774 decl:member/block0#showVideoTitle#0 scope=member/block0/if0/block0/closure0/block0 read`; `rdAvailable@29920 decl:member/block0#rdAvailable#0 scope=member/block0/if0/block0/closure0/block0 read`; `torboxAvailable@29960 decl:member/block0#torboxAvailable#0 scope=member/block0/if0/block0/closure0/block0 read`; `pikpakAvailable@30004 decl:member/block0#pikpakAvailable#0 scope=member/block0/if0/block0/closure0/block0 read`; `premiumizeAvailable@30052 decl:member/block0#premiumizeAvailable#0 scope=member/block0/if0/block0/closure0/block0 read`; `allDebridAvailable@30103 decl:member/block0#allDebridAvailable#0 scope=member/block0/if0/block0/closure0/block0 read`; `startRandom@30218 decl:member/block0#startRandom#0 scope=member/block0/if0/block0/closure0/block0 read`; `randomStartPercent@30291 decl:member/block0#randomStartPercent#0 scope=member/block0/if0/block0/closure0/block0 read`; `hideOptions@30340 decl:member/block0#hideOptions#0 scope=member/block0/if0/block0/closure0/block0 read`; `showChannelName@30385 decl:member/block0#showChannelName#0 scope=member/block0/if0/block0/closure0/block0 read`; `showVideoTitle@30433 decl:member/block0#showVideoTitle#0 scope=member/block0/if0/block0/closure0/block0 read`; `tvFilters@30714 decl:member/block0#tvFilters#0 scope=member/block0/if0/block0/closure0/block0 read`; `tvEngineStates@30998 decl:member/block0#tvEngineStates#0 scope=member/block0/if0/block0/closure0/block0 read`; `tvSmallChannelMaxByEngine@31089 decl:member/block0#tvSmallChannelMaxByEngine#0 scope=member/block0/if0/block0/closure0/block0 read`; `tvLargeChannelMaxByEngine@31191 decl:member/block0#tvLargeChannelMaxByEngine#0 scope=member/block0/if0/block0/closure0/block0 read`; `tvQuickPlayMaxByEngine@31290 decl:member/block0#tvQuickPlayMaxByEngine#0 scope=member/block0/if0/block0/closure0/block0 read`; `channelBatchSize@31343 decl:member/block0#channelBatchSize#0 scope=member/block0/if0/block0/closure0/block0 read`; `keywordThreshold@31389 decl:member/block0#keywordThreshold#0 scope=member/block0/if0/block0/closure0/block0 read`; `minTorrentsPerKeyword@31440 decl:member/block0#minTorrentsPerKeyword#0 scope=member/block0/if0/block0/closure0/block0 read`; `quickPlayMaxKeywords@31495 decl:member/block0#quickPlayMaxKeywords#0 scope=member/block0/if0/block0/closure0/block0 read`; `hideOptions@31772 decl:member/block0#hideOptions#0 scope=member/block0/if1 read`; `hideOptions@31845 decl:member/block0#hideOptions#0 scope=member/block0/if1/block0 read`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Hardcoded to false - no longer loading from storage
// hideBackButton is hardcoded to false - no longer loading from storage
// Global TV settings
// Hardcoded to false
// Hardcoded to false
// Hardcoded to false
// Hardcoded to false
// The filter is an INPUT to the memoised stage numbers: anything
// computed before this load landed used the empty default.
// Update search settings
// Outside the setState callback: recomputing the focused channel's
// numbers schedules its own rebuild.
```
### `_DebrifyTVScreenState._accumulateCachedTorrent`

ORIGINAL lines 910–938; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart` → `DebrifyTvChannelWarmup._accumulateCachedTorrent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._enabledTvKeywordEngines`

ORIGINAL lines 940–953; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart` → `DebrifyTvEngineLimits.enabledTvKeywordEngines`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_tvEngineStates` → `_owners.settings.tvEngineStates` | 33077 / read / `member/block0/closure0` |
### `_DebrifyTVScreenState._tvChannelMaxResultsForEngine`

ORIGINAL lines 955–971; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart` → `DebrifyTvEngineLimits.tvChannelMaxResultsForEngine`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_keywordThreshold` → `_owners.settings.keywordThreshold` | 33428 / read / `member/block0` |
| `_tvSmallChannelMaxByEngine` → `_owners.settings.tvSmallChannelMaxByEngine` | 33502 / read / `member/block0` |
| `_tvLargeChannelMaxByEngine` → `_owners.settings.tvLargeChannelMaxByEngine` | 33552 / read / `member/block0` |
### `_DebrifyTVScreenState._estimatePagesPulledForEngine`

ORIGINAL lines 973–992; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart` → `DebrifyTvEngineLimits.estimatePagesPulledForEngine`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._estimatePageRequestsForEngine`

ORIGINAL lines 994–1013; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart` → `DebrifyTvEngineLimits._estimatePageRequestsForEngine`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._quickPlayMaxResultsOverrides`

ORIGINAL lines 1015–1017; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart` → `DebrifyTvEngineLimits.quickPlayMaxResultsOverrides`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_tvQuickPlayMaxByEngine` → `_owners.settings.tvQuickPlayMaxByEngine` | 35217 / read / `member/block0` |
### `_DebrifyTVScreenState._tvEngineSearchStates`

ORIGINAL lines 1019–1029; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart` → `DebrifyTvEngineLimits.tvEngineSearchStates`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_tvEngineStates` → `_owners.settings.tvEngineStates` | 35510 / read / `member/block0/for0` |
### `_DebrifyTVScreenState._sortedCachedTorrents`

ORIGINAL lines 1031–1043; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart` → `DebrifyTvChannelWarmup._sortedCachedTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._loadChannels`

ORIGINAL lines 1045–1059; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.loadChannels`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@36114 lexical unbound scope=member/block0/if0 read`; `setState@36135 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 36155 / write / `member/block0/closure0/block0` |
| `_debrifyTvStyle` → `_owners.library.debrifyTvStyle` | 36493 / read / `member/block0/if1` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Every path that reloads channels (create, edit, delete-all, ZIP/YAML/
// community imports) has fresh pools too, so the rail's pips ride along
// here rather than each call site remembering to refresh them.
```
### `_DebrifyTVScreenState._handleSyncedDebrifyTvLibraryChanged`

ORIGINAL lines 1061–1069; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.handleSyncedDebrifyTvLibraryChanged`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@36635 lexical unbound scope=member/block0/if0 read`; `setState@36656 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelCache` → `_owners.library.channelCache` | 36676 / read / `member/block0/closure0/block0` |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 36705 / read / `member/block0/closure0/block0` |
| `_spotlightRailHealth` → `_owners.stage.spotlightRailHealth` | 36736 / write / `member/block0/closure0/block0` |
### `_DebrifyTVScreenState._loadFavoriteChannels`

ORIGINAL lines 1071–1077; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.loadFavoriteChannels`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@36980 lexical unbound scope=member/block0/if0 read`; `setState@37001 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_favoriteChannelIds` → `_owners.library.favoriteChannelIds` | 37021 / write / `member/block0/closure0/block0` |
### `_DebrifyTVScreenState._toggleChannelFavorite`

ORIGINAL lines 1079–1095; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.toggleChannelFavorite`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@37332 lexical unbound scope=member/block0/if0 read`; `setState@37353 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_favoriteChannelIds` → `_owners.library.favoriteChannelIds` | 37165 / read / `member/block0`; 37397 / write / `member/block0/closure0/block0/if0/block0`; 37423 / read / `member/block0/closure0/block0/if0/block0`; 37480 / write / `member/block0/closure0/block0/if0/block1`; 37502 / read / `member/block0/closure0/block0/if0/block1` |
### `_DebrifyTVScreenState._watchChannelById`

ORIGINAL lines 1097–1105; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.watchChannelById`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 37765 / read / `member/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Watch a channel by ID (called from external sources like home screen)
```
### `_DebrifyTVScreenState._checkPendingAutoPlay`

ORIGINAL lines 1107–1127; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.checkPendingAutoPlay`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@38450 lexical unbound scope=member/block0/block0/if0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 38311 / read / `member/block0`; 38482 / read / `member/block0/if1` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Check for pending auto-play channel from home screen
// Wait for channels to load
// 5 seconds max wait
```
### `_DebrifyTVScreenState._computeChannelCacheEntry`

ORIGINAL lines 1129–1245; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart` → `DebrifyTvChannelWarmup.computeChannelCacheEntry`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelBatchSize` → `_owners.settings.channelBatchSize` | 40772 / read / `member/block0/block0` |
| `_minTorrentsPerKeyword` → `_owners.settings.minTorrentsPerKeyword` | 41262 / read / `member/block0/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// The channel's own NSFW setting, FLOORED by the viewer: filtering is
// role-locked for a child profile no matter who authored the channel or
// what its stored flag says (the rail is viewer-scoped, evaluated at
// search/play — never only at creation).
// Use channel's NSFW setting
```
### `_DebrifyTVScreenState._warmKeyword`

ORIGINAL lines 1247–1389; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart` → `DebrifyTvChannelWarmup._warmKeyword`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Same-named lexical hazards (must remain bound to the same declaration): `minTorrentsPerKeyword@45411 decl:member#minTorrentsPerKeyword#0 scope=member/block0/if1 read`; `minTorrentsPerKeyword@45548 decl:member#minTorrentsPerKeyword#0 scope=member/block0/if1/block0 read`; `minTorrentsPerKeyword@46097 decl:member#minTorrentsPerKeyword#0 scope=member/block0/if1/block0 read`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Use channel's NSFW setting
// Apply NSFW filter to search results before caching
// Check minimum torrents per keyword threshold
```
### `_DebrifyTVScreenState._deleteChannel`

ORIGINAL lines 1391–1404; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.deleteChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@47408 lexical unbound scope=member/block0 invocation`; `setState@47555 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 47428 / write / `member/block0/closure0/block0`; 47440 / read / `member/block0/closure0/block0` |
| `_channelCache` → `_owners.library.channelCache` | 47575 / read / `member/block0/closure1/block0` |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 47607 / read / `member/block0/closure1/block0` |
| `_spotlightRailHealth` → `_owners.stage.spotlightRailHealth` | 47641 / write / `member/block0/closure1/block0`; 47671 / read / `member/block0/closure1/block0` |
| `_spotlightFocusedId` → `_owners.stage.spotlightFocusedId` | 47869 / read / `member/block0/closure1/block0/if0`; 47896 / write / `member/block0/closure1/block0/if0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// The layout's staged-channel repair fires onChannelFocused for its
// replacement; a dangling id here would make that look like a no-move.
```
### `_DebrifyTVScreenState._syncProviderAvailability`

ORIGINAL lines 1406–1466; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart` → `DebrifyTvSettingsLoader.syncProviderAvailability`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@49619 lexical unbound scope=member/block0/if0 read`; `setState@49702 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_provider` → `_owners.settings.provider` | 49269 / read / `member/block0`; 49687 / read / `member/block0`; 49938 / write / `member/block0/closure0/block0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 49468 / read / `member/block0`; 49977 / write / `member/block0/closure0/block0` |
| `_rdAvailable` → `_owners.settings.rdAvailable` | 49722 / write / `member/block0/closure0/block0` |
| `_torboxAvailable` → `_owners.settings.torboxAvailable` | 49756 / write / `member/block0/closure0/block0` |
| `_pikpakAvailable` → `_owners.settings.pikpakAvailable` | 49798 / write / `member/block0/closure0/block0` |
| `_premiumizeAvailable` → `_owners.settings.premiumizeAvailable` | 49840 / write / `member/block0/closure0/block0` |
| `_allDebridAvailable` → `_owners.settings.allDebridAvailable` | 49890 / write / `member/block0/closure0/block0` |

Same-named lexical hazards (must remain bound to the same declaration): `rdAvailable@49286 decl:member/block0#rdAvailable#0 scope=member/block0 read`; `torboxAvailable@49305 decl:member/block0#torboxAvailable#0 scope=member/block0 read`; `pikpakAvailable@49328 decl:member/block0#pikpakAvailable#0 scope=member/block0 read`; `premiumizeAvailable@49351 decl:member/block0#premiumizeAvailable#0 scope=member/block0 read`; `allDebridAvailable@49378 decl:member/block0#allDebridAvailable#0 scope=member/block0 read`; `rdAvailable@49490 decl:member/block0#rdAvailable#0 scope=member/block0 read`; `torboxAvailable@49509 decl:member/block0#torboxAvailable#0 scope=member/block0 read`; `pikpakAvailable@49532 decl:member/block0#pikpakAvailable#0 scope=member/block0 read`; `premiumizeAvailable@49555 decl:member/block0#premiumizeAvailable#0 scope=member/block0 read`; `allDebridAvailable@49582 decl:member/block0#allDebridAvailable#0 scope=member/block0 read`; `rdAvailable@49737 decl:member/block0#rdAvailable#0 scope=member/block0/closure0/block0 read`; `torboxAvailable@49775 decl:member/block0#torboxAvailable#0 scope=member/block0/closure0/block0 read`; `pikpakAvailable@49817 decl:member/block0#pikpakAvailable#0 scope=member/block0/closure0/block0 read`; `premiumizeAvailable@49863 decl:member/block0#premiumizeAvailable#0 scope=member/block0/closure0/block0 read`; `allDebridAvailable@49912 decl:member/block0#allDebridAvailable#0 scope=member/block0/closure0/block0 read`.
### `_DebrifyTVScreenState._parseKeywords`

ORIGINAL lines 1468–1474; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.parseKeywords`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._normalizedKeywords`

ORIGINAL lines 1476–1488; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.normalizedKeywords`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._ensureCacheEntry`

ORIGINAL lines 1490–1502; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.ensureCacheEntry`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelCache` → `_owners.library.channelCache` | 50791 / read / `member/block0`; 50972 / read / `member/block0/if1/block0` |
### `_DebrifyTVScreenState._getChannelKeywords`

ORIGINAL lines 1504–1526; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.getChannelKeywords`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@51461 lexical unbound scope=member/block0/if2 read`; `setState@51562 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 51126 / read / `member/block0`; 51255 / read / `member/block0`; 51623 / read / `member/block0/closure1/block0`; 51670 / write / `member/block0/closure1/block0` |
### `_DebrifyTVScreenState._fetchTorboxCacheWindow`

ORIGINAL lines 1528–1584; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver.fetchTorboxCacheWindow`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._estimatedWarmDurationSeconds`

ORIGINAL lines 1586–1616; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_engine_limits.dart` → `DebrifyTvEngineLimits.estimatedWarmDurationSeconds`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelBatchSize` → `_owners.settings.channelBatchSize` | 53690 / read / `member/block0`; 53716 / read / `member/block0` |
| `_keywordWarmEstimateMs` → `DebrifyTvConstants.keywordWarmEstimateMs` | 54021 / read / `member/block0` |
### `_DebrifyTVScreenState._filterCachedTorrentsForKeywords`

ORIGINAL lines 1618–1635; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart` → `DebrifyTvChannelWarmup._filterCachedTorrentsForKeywords`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._filterKeywordStats`

ORIGINAL lines 1637–1652; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_warmup.dart` → `DebrifyTvChannelWarmup._filterKeywordStats`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._applyQualityFilterToCached`

ORIGINAL lines 1654–1680; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart` → `DebrifyTvPlaybackFilters._applyQualityFilterToCached`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_tvFilters` → `_owners.settings.tvFilters` | 55722 / read / `member/block0/if0`; 55823 / read / `member/block0/closure0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Narrows a channel's cached torrents to the user's quality filter.
/// Applied at cache READ time (not warm time) so changing the filter takes
/// effect immediately instead of forcing a full channel rebuild the way the
/// NSFW toggle does. Returns the input untouched when the filter is off, and
/// falls back to the unfiltered pool (with a snackbar) when a channel has
/// nothing at the requested quality — a filtered channel that plays nothing
/// reads as broken, so it degrades instead of failing.
```
### `_DebrifyTVScreenState._applyQualityFilterToTorrents`

ORIGINAL lines 1682–1706; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart` → `DebrifyTvPlaybackFilters.applyQualityFilterToTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_tvFilters` → `_owners.settings.tvFilters` | 57148 / read / `member/block0/if0`; 57259 / read / `member/block0/closure0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Quick-play twin of [_applyQualityFilterToCached], for the live search
/// results each provider accumulates.
///
/// [allowFallback] must stay false while a search is still streaming in.
/// Quick play rebuilds this list on every engine that reports, and the RD
/// flow launches the player from the first rebuild that yields something
/// playable — so falling back on a partial result set would start playing an
/// off-filter source just because the fastest engine happened to return
/// none. Strict here means the queue simply stays empty until a matching
/// result arrives. Pass true only once the result set is final, where an
/// empty match genuinely means "this search has nothing".
```
### `_DebrifyTVScreenState._notifyQualityFallback`

ORIGINAL lines 1708–1718; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart` → `DebrifyTvPlaybackFilters.notifyQualityFallback`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_qualityFallbackNotified` → `_owners.session.qualityFallbackNotified` | 57694 / read / `member/block0/if0`; 57732 / write / `member/block0` |
| `_tvFilters` → `_owners.settings.tvFilters` | 57793 / read / `member/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Tells the user once per playback session that the quality filter was
/// relaxed. Rate-limited because the quick-play queue is rebuilt per engine
/// and channel switches re-enter the same path.
```
### `_DebrifyTVScreenState._rdLinkPassesSizeRules`

ORIGINAL lines 1720–1751; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart` → `DebrifyTvPlaybackFilters.rdLinkPassesSizeRules`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_torboxMinVideoSizeBytes` → `DebrifyTvConstants.torboxMinVideoSizeBytes` | 58915 / read / `member/block0/if1` |
| `_sizeFilterRelaxed` → `_owners.session.sizeFilterRelaxed` | 58963 / read / `member/block0/if2`; 59204 / write / `member/block0/if4/block0` |
| `_tvFilters` → `_owners.settings.tvFilters` | 58986 / read / `member/block0/if2`; 59027 / read / `member/block0/if3`; 59264 / read / `member/block0/if4/block0` |
| `_rdSizeRejections` → `_owners.session.rdSizeRejections` | 59071 / write / `member/block0/if3/block0`; 59123 / read-write / `member/block0`; 59152 / read / `member/block0/if4` |
| `_rdSizeRejectionLimit` → `DebrifyTvConstants.rdSizeRejectionLimit` | 59173 / read / `member/block0/if4` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Whether an unrestricted Real-Debrid link may be played, per the size
/// rules. RD is the one provider that hands back a flat list of links with
/// no per-file metadata, so a file's size is only knowable AFTER
/// unrestricting it — hence the check here rather than up front like the
/// others. Links whose size RD doesn't report are accepted.
///
/// Because RD can't pre-filter, a strict size choice could otherwise walk
/// the entire queue rejecting everything. After
/// [_rdSizeRejectionLimit] consecutive size-only rejections the size filter
/// is relaxed for the rest of the session (with a snackbar) — the same
/// degrade-don't-fail contract the other providers get per torrent.
// RD didn't report a size — don't guess.
// Trailer/sample guard, matching Torbox/Premiumize/PikPak/AllDebrid.
```
### `_DebrifyTVScreenState._selectTorrentsForPlayback`

ORIGINAL lines 1753–1810; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart` → `DebrifyTvPlaybackFilters.selectTorrentsForPlayback`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_playbackTorrentThreshold` → `DebrifyTvConstants.playbackTorrentThreshold` | 59822 / read / `member/block0/if0`; 60642 / read / `member/block0/if2/block0`; 60712 / read / `member/block0/if3`; 61011 / read / `member/block0/if3/block0/for0/block0/if1` |
| `_maxTorrentsPerKeywordPlayback` → `DebrifyTvConstants.maxTorrentsPerKeywordPlayback` | 60502 / read / `member/block0/if1/block0/for0/block0/for0/block0/if2` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Filter BEFORE the per-keyword/threshold narrowing below, so the
// selection draws from the full matching pool rather than from a
// pre-narrowed sample that the filter then guts.
```
### `_DebrifyTVScreenState._providerDisplay`

ORIGINAL lines 1812–1818; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_loader.dart` → `DebrifyTvSettingsLoader.providerDisplay`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 61232 / read / `member/block0/if0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 61286 / read / `member/block0/if1` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 61340 / read / `member/block0/if2` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 61402 / read / `member/block0/if3` |

Same-named lexical hazards (must remain bound to the same declaration): `provider@61220 decl:member#provider#0 scope=member/block0/if0 read`; `provider@61274 decl:member#provider#0 scope=member/block0/if1 read`; `provider@61328 decl:member#provider#0 scope=member/block0/if2 read`; `provider@61390 decl:member#provider#0 scope=member/block0/if3 read`.
### `_DebrifyTVScreenState._tvFilterChips`

ORIGINAL lines 1820–1909; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_chips.dart` → `DebrifyTvSettingsChips.tvFilterChips`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@61807 lexical unbound scope=member/block0/function0/closure0/block0 invocation`; `context@62868 lexical unbound scope=member/block0 read`; `context@62938 lexical unbound scope=member/block0 read`; `context@63147 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_tvFilters` → `_owners.settings.tvFilters` | 61822 / write / `member/block0/function0/closure0/block0/closure0`; 62150 / read / `member/block0/function1/closure0/block0`; 62285 / read / `member/block0/function1/closure0/block0`; 62528 / read / `member/block0/function2/closure0/block0`; 62653 / read / `member/block0/function2/closure0/block0`; 63855 / read / `member/block0/for0`; 64421 / read / `member/block0/for1` |
| `_isBusy` → `_owners.session.isBusy` | 63921 / read / `member/block0/for0`; 64482 / read / `member/block0/for1` |

Escaping callbacks/builders: `_SpotlightChoiceChip[0].onPressed = ()=>toggleQuality(quality)`; `_SpotlightChoiceChip[1].onPressed = ()=>toggleSize(bucket)`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Quality + size pickers for Debrify TV playback. One shared setting for
/// both channels and quick play, so the same feed rules apply wherever you
/// start watching. Nothing selected in a row = that facet is off.
// "At your quality" is computed WITH the filter; stale memos would
// keep the old filter's count while playback uses the new one.
```
### `_DebrifyTVScreenState._providerChoiceChips`

ORIGINAL lines 1911–1999; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_chips.dart` → `DebrifyTvSettingsChips.providerChoiceChips`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@65058 lexical unbound scope=member/block0/function0/closure0/block0/if1/block0 invocation`; `setState@65242 lexical unbound scope=member/block0/function0/closure0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_quickProvider` → `_owners.settings.quickProvider` | 64820 / read / `member/block0`; 64995 / read / `member/block0/function0/closure0/block0/if1/block0/if0`; 65082 / write / `member/block0/function0/closure0/block0/if1/block0/closure0/block0` |
| `_provider` → `_owners.settings.provider` | 64837 / read / `member/block0`; 65190 / read / `member/block0/function0/closure0/block0/if2`; 65264 / write / `member/block0/function0/closure0/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 65806 / read / `member/block0/function1/closure0/block0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 66006 / read / `member/block0` |
| `_rdAvailable` → `_owners.settings.rdAvailable` | 66080 / read / `member/block0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 66242 / read / `member/block0` |
| `_torboxAvailable` → `_owners.settings.torboxAvailable` | 66307 / read / `member/block0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 66454 / read / `member/block0` |
| `_pikpakAvailable` → `_owners.settings.pikpakAvailable` | 66519 / read / `member/block0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 66650 / read / `member/block0` |
| `_premiumizeAvailable` → `_owners.settings.premiumizeAvailable` | 66723 / read / `member/block0` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 66892 / read / `member/block0` |
| `_allDebridAvailable` → `_owners.settings.allDebridAvailable` | 66963 / read / `member/block0` |

Escaping callbacks/builders: `_SpotlightChoiceChip[0].onPressed = ()=>handleSelection(value)`.
### `_DebrifyTVScreenState._addKeywordsToList`

ORIGINAL lines 2001–2025; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_editor.dart` → `DebrifyTvChannelEditor._addKeywordsToList`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@67405 lexical decl:member#setState#0 scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_maxChannelKeywords` → `DebrifyTvConstants.maxChannelKeywords` | 67486 / read / `member/block0/closure0/block0/for0/block0/if0`; 67815 / read / `member/block0` |
### `_DebrifyTVScreenState._openChannelDialog`

ORIGINAL lines 2027–2344; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_editor.dart` → `DebrifyTvChannelEditor.openChannelDialog`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@69075 lexical unbound scope=member/block0/block0 read`; `context@69279 lexical decl:member/block0/block0/closure0/block0/closure0#context#0 scope=member/block0/block0/closure0/block0/closure0/block0 read`; `context@74112 selector None scope=member/block0/block0/closure0/block0/closure0/block0/closure1/block0 read`; `context@77187 selector None scope=member/block0/block0/closure0/block0/closure0/block0/closure4/block0 read`; `mounted@81473 lexical unbound scope=member/block0/block1/if0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 68150 / read / `member/block0/if0`; 73136 / read / `member/block0/block0/closure0/block0/closure0/block0` |
| `_maxChannelKeywords` → `DebrifyTvConstants.maxChannelKeywords` | 68799 / read / `member/block0/for0/block0/if2`; 70105 / read / `member/block0/block0/closure0/block0/closure0/block0/function0/closure0/block0/if0/block0/for0/block0/if2`; 70249 / read / `member/block0/block0/closure0/block0/closure0/block0/function0/closure0/block0/if0/block0/for0/block0/if2/block0/closure0/block0`; 71429 / read / `member/block0/block0/closure0/block0/closure0/block0/function0/closure0/block0/if3`; 71561 / read / `member/block0/block0/closure0/block0/closure0/block0/function0/closure0/block0/if3/block0/closure0/block0`; 74430 / read / `member/block0/block0/closure0/block0/closure0/block0`; 75727 / read / `member/block0/block0/closure0/block0/closure0/block0/closure2/closure0/block0/closure0/block0/if0`; 75856 / read / `member/block0/block0/closure0/block0/closure0/block0/closure2/closure0/block0/closure0/block0/if0`; 77921 / read / `member/block0/block0/closure0/block0/closure0/block0/closure5/block0/if0/block0/closure0/block0`; 78148 / read / `member/block0/block0/closure0/block0/closure0/block0/closure5/block0/if0/if0`; 79040 / read / `member/block0/block0/closure0/block0/closure0/block0/closure6/block0/if0/block0/if0/block0/closure0/block0`; 79275 / read / `member/block0/block0/closure0/block0/closure0/block0/closure6/block0/if0/block0/if0/if0` |

Escaping callbacks/builders: `StatefulBuilder[0].builder = (context,setModalState){finalapp=AppThemeScope.of(context);finaltv=app.debrifyTv;Future<void>submit()async{finalpendingRaw=keywordInputController.text.trim();if(pendingRaw.isNotEmpty){finalpendingKeywords=_parseKeywords(pendingRaw);for(finalrawKwinpendingKeywords){finaltrimmedKw=rawKw.trim();if(trimmedKw.isEmpty){continue;}finalalreadyPresent=keywordList.any((existing)=>existing.toLowerCase()==trimmedKw.toLowerCase());if(alreadyPresent){continue;}if(keywordList.length>=_maxChannelKeywords){setModalState((){error='You can add up to $_maxChannelKeywords keywords per channel.';});return;}keywordList.add(trimmedKw);}keywordInputController.clear();}finalname=nameController.text.trim();finalkeywords=<String>[];finalseen=<String>{};for(finalrawinkeywordList){finaltrimmed=raw.trim();if(trimmed.isEmpty)continue;finallower=trimmed.toLowerCase();if(seen.contains(lower))continue;seen.add(lower);keywords.add(trimmed);}if(name.isEmpty){setModalState((){error='Give the channel a name';});return;}if(keywords.isEmpty){setModalState((){error='Add at least one keyword';});return;}if(keywords.length>_maxChannelKeywords){setModalState((){error='You can add up to $_maxChannelKeywords keywords per channel.';});return;}finalnow=DateTime.now();finalchannel=DebrifyTvChannel(id:existing?.id??DateTime.now().microsecondsSinceEpoch.toString(),name:name,keywords:keywords,avoidNsfw:avoidNsfw,// Channel's own NSFW settingchannelNumber:existing?.channelNumber??0,createdAt:existing?.createdAt??now,updatedAt:now);Navigator.of(dialogContext).pop(channel);}returnDebrifyTvSpotlightDialog(eyebrow:existing==null?'Channel editor · new':'Channel editor · ${existing.channelNumber.toString().padLeft(2,'0')}',title:existing==null?'Create a channel':'Edit channel',subtitle:'Keywords are search terms. Add one or several and Debrify will pool the results.',icon:Icons.tv_rounded,maxWidth:720,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[TvTextField(controller:nameController,focusNode:channelNameFocus,autofocus:_isAndroidTv,textCapitalization:TextCapitalization.words,// The shared TV shell/keyboard chrome follows// settings.accent. NOT debrifyTv.accent: legacy// paints that the channel grid's Netflix red, while// the keyboard's highlight has always been violet.accent:app.settings.accent,keyboardGround:app.youtube.keyboardPanel,keyboardInk:app.core.tx,keyboardInkOnAccent:app.inkOn(app.settings.accent),decoration:constInputDecoration(labelText:'Channel name',prefixIcon:Icon(Icons.label_rounded)),onDownArrow:()=>channelKeywordFocus?.requestFocus(),onUpArrow:(){finalctx=channelNameFocus?.context;if(ctx!=null){FocusScope.of(ctx).previousFocus();}}),constSizedBox(height:12),Text('Keywords (${keywordList.length}/$_maxChannelKeywords)',style:TextStyle(color:tv.textDim,fontSize:12,fontWeight:FontWeight.w600)),constSizedBox(height:4),Text('Tip: type a keyword and press Enter. Add multiples by separating with commas.',style:TextStyle(color:tv.textFaint,fontSize:11)),constSizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[...keywordList.map((keyword)=>_SpotlightChoiceChip(label:keyword,selected:false,enabled:true,trailingIcon:Icons.close_rounded,onPressed:(){setModalState((){keywordList.remove(keyword);if(error!=null&&error!.contains('$_maxChannelKeywords keywords')&&keywordList.length<_maxChannelKeywords){error=null;}});})),SizedBox(width:200,child:TvTextField(controller:keywordInputController,focusNode:channelKeywordFocus,decoration:constInputDecoration(hintText:'Add keyword',prefixIcon:Icon(Icons.add_rounded)),style:TextStyle(color:app.core.tx),// Shared TV shell/keyboard chrome — see the// channel-name field above.accent:app.settings.accent,keyboardGround:app.youtube.keyboardPanel,keyboardInk:app.core.tx,keyboardInkOnAccent:app.inkOn(app.settings.accent),onUpArrow:()=>channelNameFocus?.requestFocus(),onDownArrow:(){finalctx=channelKeywordFocus?.context;if(ctx!=null){FocusScope.of(ctx).nextFocus();}},onSubmitted:(value){finallimitReached=_addKeywordsToList(value,keywordList,setModalState);keywordInputController.clear();if(limitReached){setModalState((){error='You can add up to $_maxChannelKeywords keywords per channel.';});}elseif(error!=null&&error!.contains('$_maxChannelKeywords keywords')){setModalState((){error=null;});}},onChanged:(value){if(value.contains(',')){finallimitReached=_addKeywordsToList(value,keywordList,setModalState);keywordInputController.clear();if(limitReached){setModalState((){error='You can add up to $_maxChannelKeywords keywords per channel.';});}elseif(error!=null&&error!.contains('$_maxChannelKeywords keywords')){setModalState((){error=null;});}}}))]),constSizedBox(height:18),DebrifyTvDialogSection(label:'Channel settings',child:SwitchRow(title:'Avoid NSFW content',subtitle:_viewerForcesNsfw?'Always on for this profile':'Best-effort filter while building this channel',value:_viewerForcesNsfw||avoidNsfw,onChanged:(v){if(_viewerForcesNsfw)return;setModalState(()=>avoidNsfw=v);})),if(error!=null)...[constSizedBox(height:16),Text(error!,style:constTextStyle(color:Colors.redAccent))]]),actions:[DebrifyTvDialogButton(label:'Cancel',onPressed:()=>Navigator.of(dialogContext).pop()),DebrifyTvDialogButton(label:'Save channel',icon:Icons.check_rounded,tone:DebrifyTvDialogButtonTone.primary,onPressed:submit)]);}`; `TvTextField[0].onDownArrow = ()=>channelKeywordFocus?.requestFocus()`; `TvTextField[0].onUpArrow = (){finalctx=channelNameFocus?.context;if(ctx!=null){FocusScope.of(ctx).previousFocus();}}`; `TvTextField[1].onUpArrow = ()=>channelNameFocus?.requestFocus()`; `TvTextField[1].onDownArrow = (){finalctx=channelKeywordFocus?.context;if(ctx!=null){FocusScope.of(ctx).nextFocus();}}`; `TvTextField[1].onSubmitted = (value){finallimitReached=_addKeywordsToList(value,keywordList,setModalState);keywordInputController.clear();if(limitReached){setModalState((){error='You can add up to $_maxChannelKeywords keywords per channel.';});}elseif(error!=null&&error!.contains('$_maxChannelKeywords keywords')){setModalState((){error=null;});}}`; `TvTextField[1].onChanged = (value){if(value.contains(',')){finallimitReached=_addKeywordsToList(value,keywordList,setModalState);keywordInputController.clear();if(limitReached){setModalState((){error='You can add up to $_maxChannelKeywords keywords per channel.';});}elseif(error!=null&&error!.contains('$_maxChannelKeywords keywords')){setModalState((){error=null;});}}}`; `_SpotlightChoiceChip[0].onPressed = (){setModalState((){keywordList.remove(keyword);if(error!=null&&error!.contains('$_maxChannelKeywords keywords')&&keywordList.length<_maxChannelKeywords){error=null;}});}`; `SwitchRow[0].onChanged = (v){if(_viewerForcesNsfw)return;setModalState(()=>avoidNsfw=v);}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`; `DebrifyTvDialogButton[1].onPressed = submit`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Channel defaults - keep NSFW preference per channel only
// Channel's own NSFW setting
// The shared TV shell/keyboard chrome follows
// settings.accent. NOT debrifyTv.accent: legacy
// paints that the channel grid's Netflix red, while
// the keyboard's highlight has always been violet.
// Shared TV shell/keyboard chrome — see the
// channel-name field above.
```
### `_DebrifyTVScreenState._handleImportChannels`

ORIGINAL lines 2346–2385; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart` → `DebrifyTvChannelImport.handleImportChannels`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@81774 lexical unbound scope=member/block0 invocation`; `mounted@81951 lexical unbound scope=member/block0/if1 read`; `mounted@82153 lexical unbound scope=member/block0/if2 read`; `mounted@82174 lexical unbound scope=member/block0/if2/block0/if0 read`; `setState@82193 lexical unbound scope=member/block0/if2/block0/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 81686 / read / `member/block0/if0`; 81794 / write / `member/block0/closure0/block0`; 82217 / write / `member/block0/if2/block0/if0/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Set busy to block interactions during dialog
// Wait for frames to ensure UI has updated and touch events are processed
```
### `_DebrifyTVScreenState._selectImportMode`

ORIGINAL lines 2387–2399; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart` → `DebrifyTvChannelImport._selectImportMode`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@82679 lexical unbound scope=member/block0/if0 read`; `context@82774 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 82898 / read / `member/block0/closure0/block0` |
### `_DebrifyTVScreenState._runChannelExportProgress`

ORIGINAL lines 2401–2423; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_export.dart` → `DebrifyTvChannelExport._runChannelExportProgress`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@83057 lexical unbound scope=member/block0/if0 read`; `context@83319 lexical unbound scope=member/block0 read`.
### `_DebrifyTVScreenState._showChannelExportUnavailableOnAppleTv`

ORIGINAL lines 2425–2456; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_export.dart` → `DebrifyTvChannelExport._showChannelExportUnavailableOnAppleTv`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@83758 lexical unbound scope=member/block0/if0 read`; `context@83818 lexical unbound scope=member/block0 read`.

Escaping callbacks/builders: `PopScope[0].onPopInvokedWithResult = (didPop,_){if(!didPop)Navigator.of(dialogContext).pop();}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`.
### `_DebrifyTVScreenState._handleExportChannels`

ORIGINAL lines 2458–2590; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_export.dart` → `DebrifyTvChannelExport.handleExportChannels`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@84886 lexical unbound scope=member/block0/if0 read`; `setState@85013 lexical unbound scope=member/block0 invocation`; `mounted@85553 lexical unbound scope=member/block0/block0/if0 read`; `context@85777 lexical unbound scope=member/block0/block0 read`; `mounted@86121 lexical unbound scope=member/block0/block0/if2 read`; `setState@86191 lexical unbound scope=member/block0/block0 invocation`; `mounted@87829 lexical unbound scope=member/block0/block0/if3 read`; `mounted@88177 lexical unbound scope=member/block0/block0/if6 read`; `context@88459 lexical unbound scope=member/block0/block0 read`; `mounted@88657 lexical unbound scope=member/block0/block0/if7 read`; `mounted@89140 lexical unbound scope=member/block0/catch0/block0/if0 read`; `mounted@89254 lexical unbound scope=member/block0/block1/if0 read`; `setState@89273 lexical unbound scope=member/block0/block1/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 84874 / read / `member/block0/if0`; 85033 / write / `member/block0/closure0/block0`; 89297 / write / `member/block0/block1/if0/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 85055 / write / `member/block0/closure0/block0`; 86206 / write / `member/block0/block0/closure1`; 89324 / write / `member/block0/block1/if0/block0/closure0/block0` |

Same-named lexical hazards (must remain bound to the same declaration): `channels@85580 decl:member/block0/block0#channels#0 scope=member/block0/block0/if1 read`; `channels@85946 decl:member/block0/block0#channels#0 scope=member/block0/block0/closure0 read`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Re-read after the selection dialog: a channel can be edited or
// removed while an overlay is open, and the archive must reflect
// the rows that actually exist at export time.
```
### `_DebrifyTVScreenState._handleAddChannel`

ORIGINAL lines 2592–2598; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_actions.dart` → `DebrifyTvChannelActions.handleAddChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._handleImportChannelsFromDevice`

ORIGINAL lines 2600–2667; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart` → `DebrifyTvChannelImport._handleImportChannelsFromDevice`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@90865 lexical unbound scope=member/block0/if3 read`; `setState@90901 lexical unbound scope=member/block0 invocation`; `mounted@91320 lexical unbound scope=member/block0/block2/if0 read`; `setState@91339 lexical unbound scope=member/block0/block2/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 90921 / write / `member/block0/closure0/block0`; 91363 / write / `member/block0/block2/if0/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 90943 / write / `member/block0/closure0/block0`; 91390 / write / `member/block0/block2/if0/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// FileType.any instead of custom: Android has no MimeTypeMap entry for
// `yaml`/`yml`/`debrify`, so a custom filter silently greys those files out
// in the system picker (and throws "Unsupported filter" outright when every
// extension is unmapped). The importer validates the bytes/format below.
// Reject an implausibly large pick before reading it into memory.
```
### `_DebrifyTVScreenState._handleImportChannelsFromUrl`

ORIGINAL lines 2669–2775; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_url_import.dart` → `DebrifyTvUrlImport.handleImportChannelsFromUrl`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@91600 lexical unbound scope=member/block0/if0/block0/if0 read`; `setState@91619 lexical unbound scope=member/block0/if0/block0/if0/block0 invocation`; `mounted@92307 lexical unbound scope=member/block0/catch0/block0/if0 read`; `setState@92326 lexical unbound scope=member/block0/catch0/block0/if0/block0 invocation`; `mounted@92417 lexical unbound scope=member/block0/if2 read`; `setState@92453 lexical unbound scope=member/block0 invocation`; `mounted@94259 lexical unbound scope=member/block0/block2/if0 read`; `setState@94278 lexical unbound scope=member/block0/block2/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 91643 / write / `member/block0/if0/block0/if0/block0/closure0/block0`; 92350 / write / `member/block0/catch0/block0/if0/block0/closure0/block0`; 92473 / write / `member/block0/closure0/block0`; 94302 / write / `member/block0/block2/if0/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 92495 / write / `member/block0/closure0/block0`; 94329 / write / `member/block0/block2/if0/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Check if it's a debrify link (pasted directly)
// Otherwise, treat as URL
```
### `_DebrifyTVScreenState._handleImportChannelsFromCommunity`

ORIGINAL lines 2777–2875; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart` → `DebrifyTvChannelImport._handleImportChannelsFromCommunity`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@94609 lexical unbound scope=member/block0/if0/block0/if0 read`; `setState@94628 lexical unbound scope=member/block0/if0/block0/if0/block0 invocation`; `mounted@94797 lexical unbound scope=member/block0/if1 read`; `mounted@94983 lexical unbound scope=member/block0/if2 read`; `setState@95019 lexical unbound scope=member/block0 invocation`; `mounted@97088 lexical unbound scope=member/block0/if5 read`; `setState@97105 lexical unbound scope=member/block0/if5/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 94652 / write / `member/block0/if0/block0/if0/block0/closure0/block0`; 95039 / write / `member/block0/closure0/block0`; 97127 / write / `member/block0/if5/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 95061 / write / `member/block0/closure0/block0`; 97152 / write / `member/block0/if5/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Wait for frames to ensure UI has updated and touch events are processed
// Download the channel file
// Import using existing method (don't show dialog/summary for each channel)
// Show first 5 errors
// Show summary
// Keep dialog open for 2 seconds to show summary
```
### `_DebrifyTVScreenState._promptCommunityChannelsDialog`

ORIGINAL lines 2877–2889; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart` → `DebrifyTvChannelImport._promptCommunityChannelsDialog`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@97301 lexical unbound scope=member/block0/if0 read`; `context@97400 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 97527 / read / `member/block0/closure0/block0` |
### `_DebrifyTVScreenState._readPickedFileBytes`

ORIGINAL lines 2891–2906; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_import.dart` → `DebrifyTvChannelImport._readPickedFileBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._importChannelBytes`

ORIGINAL lines 2908–2932; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats._importChannelBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._safeImportChannelBytes`

ORIGINAL lines 2934–2955; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats.safeImportChannelBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Corrupt archives throw ArchiveException/RangeError etc., not just
// FormatException — surface them the same way instead of leaving the
// import flow (and any progress dialog) stuck.
```
### `_DebrifyTVScreenState._determineImportType`

ORIGINAL lines 2957–2991; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats._determineImportType`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Check extension first
// Fallback: check file signature for zip
// PK — zip signature
// Smart content detection for unknown extensions
// If UTF-8 decode fails, not a text file
```
### `_DebrifyTVScreenState._importZipBytes`

ORIGINAL lines 2993–3019; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats._importZipBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._importYamlBytes`

ORIGINAL lines 3021–3051; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats._importYamlBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._importTextBytes`

ORIGINAL lines 3053–3104; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats._importTextBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 103551 / read / `member/block0` |
### `_DebrifyTVScreenState._importDebrifyBytes`

ORIGINAL lines 3106–3152; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats.importDebrifyBytes`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Validate debrify link format
// Decode debrify link
// Parse the decoded YAML
```
### `_DebrifyTVScreenState._importDebrifyLinkDirectly`

ORIGINAL lines 3154–3185; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_url_import.dart` → `DebrifyTvUrlImport._importDebrifyLinkDirectly`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@105500 lexical unbound scope=member/block0/if0 read`; `setState@105536 lexical unbound scope=member/block0 invocation`; `mounted@106002 lexical unbound scope=member/block0/block1/if0 read`; `setState@106021 lexical unbound scope=member/block0/block1/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 105556 / write / `member/block0/closure0/block0`; 106045 / write / `member/block0/block1/if0/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 105578 / write / `member/block0/closure0/block0`; 106072 / write / `member/block0/block1/if0/block0/closure0/block0` |
### `_DebrifyTVScreenState._stripExtension`

ORIGINAL lines 3187–3193; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats._stripExtension`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._guessExtensionFromHeaders`

ORIGINAL lines 3195–3205; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_url_import.dart` → `DebrifyTvUrlImport._guessExtensionFromHeaders`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._promptImportUrl`

ORIGINAL lines 3207–3333; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_url_import.dart` → `DebrifyTvUrlImport._promptImportUrl`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@106749 lexical unbound scope=member/block0/if0 read`; `context@107093 selector None scope=member/block0/closure0/block0 read`; `context@107651 lexical unbound scope=member/block0 read`; `context@107807 lexical decl:member/block0/closure1/block0/closure0#context#0 scope=member/block0/closure1/block0/closure0/block0 read`; `setState@109949 lexical decl:member/block0/closure1/block0/closure0#setState#0 scope=member/block0/closure1/block0/closure0/block0/closure1/block0/if0/block0 invocation`; `setState@110827 lexical decl:member/block0/closure1/block0/closure0#setState#0 scope=member/block0/closure1/block0/closure0/block0/closure1/block0/catch0/block0 invocation`.

Escaping callbacks/builders: `FocusNode[0].onKeyEvent = (node,event){if(eventis!KeyDownEvent){returnKeyEventResult.ignored;}finalfocusContext=node.context;if(focusContext==null){returnKeyEventResult.ignored;}finalkey=event.logicalKey;if(key==LogicalKeyboardKey.arrowDown){FocusScope.of(focusContext).nextFocus();returnKeyEventResult.handled;}if(key==LogicalKeyboardKey.arrowUp){FocusScope.of(focusContext).previousFocus();returnKeyEventResult.handled;}returnKeyEventResult.ignored;}`; `StatefulBuilder[0].builder = (context,setState){finalapp=AppThemeScope.of(context);returnDebrifyTvSpotlightDialog(eyebrow:'Import · from a link',title:'Paste a channel link',subtitle:'Use a debrify:// share link or an http(s) URL to a supported channel file.',icon:Icons.link_rounded,maxWidth:650,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[TvTextField(controller:controller,accent:app.settings.accent,keyboardGround:app.youtube.keyboardPanel,keyboardInk:app.core.tx,keyboardInkOnAccent:app.inkOn(app.settings.accent),decoration:InputDecoration(labelText:'Debrify link or file URL',hintText:'debrify://channel?... or https://...',errorText:errorText),autofocus:true,focusNode:urlFocusNode,keyboardType:TextInputType.url),constSizedBox(height:14),Text('Supported: .zip · .yaml · .txt · .debrify',style:TextStyle(fontFamily:'JetBrainsMono',fontSize:10,color:app.debrifyTv.textFaint))]),actions:[DebrifyTvDialogButton(label:'Cancel',onPressed:()=>Navigator.of(dialogContext).pop()),DebrifyTvDialogButton(label:'Import',icon:Icons.download_rounded,tone:DebrifyTvDialogButtonTone.primary,onPressed:(){finalcandidate=controller.text.trim();if(candidate.isEmpty){setState((){errorText='Enter a link or URL to continue.';});return;}// Check if it's a debrify link (valid and accepted)if(MagnetYamlService.isMagnetLink(candidate)){Navigator.of(dialogContext).pop(candidate);return;}// Otherwise validate as http(s) URLtry{finalparsed=Uri.parse(candidate);if(!parsed.hasAbsolutePath||(parsed.scheme!='http'&&parsed.scheme!='https')){throwconstFormatException('invalid');}}catch(_){setState((){errorText='Enter a valid debrify:// link or http(s) URL.';});return;}Navigator.of(dialogContext).pop(candidate);})]);}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`; `DebrifyTvDialogButton[1].onPressed = (){finalcandidate=controller.text.trim();if(candidate.isEmpty){setState((){errorText='Enter a link or URL to continue.';});return;}// Check if it's a debrify link (valid and accepted)if(MagnetYamlService.isMagnetLink(candidate)){Navigator.of(dialogContext).pop(candidate);return;}// Otherwise validate as http(s) URLtry{finalparsed=Uri.parse(candidate);if(!parsed.hasAbsolutePath||(parsed.scheme!='http'&&parsed.scheme!='https')){throwconstFormatException('invalid');}}catch(_){setState((){errorText='Enter a valid debrify:// link or http(s) URL.';});return;}Navigator.of(dialogContext).pop(candidate);}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Check if it's a debrify link (valid and accepted)
// Otherwise validate as http(s) URL
```
### `_DebrifyTVScreenState._persistImportedZipChannels`

ORIGINAL lines 3335–3440; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_persistence.dart` → `DebrifyTvImportPersistence.persistImportedZipChannels`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@114233 lexical unbound scope=member/block0/if1 read`; `setState@114250 lexical unbound scope=member/block0/if1/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 111778 / read / `member/block0`; 114272 / write / `member/block0/if1/block0/closure0/block0`; 114288 / read / `member/block0/if1/block0/closure0/block0` |
| `_maxChannelKeywords` → `DebrifyTvConstants.maxChannelKeywords` | 111945 / read / `member/block0/for0/block0/if0`; 112230 / read / `member/block0/for0/block0/if0/block0` |
| `_channelCache` → `_owners.library.channelCache` | 114329 / read / `member/block0/if1/block0/closure0/block0` |

Same-named lexical hazards (must remain bound to the same declaration): `channels@111422 decl:member#channels#0 scope=member/block0/if0 read`; `channels@111887 decl:member#channels#0 scope=member/block0/for0 read`.
### `_DebrifyTVScreenState._showZipImportSummary`

ORIGINAL lines 3442–3567; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_persistence.dart` → `DebrifyTvImportPersistence.showZipImportSummary`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@114636 lexical unbound scope=member/block0/if0 read`; `context@115540 lexical unbound scope=member/block0 read`.

Escaping callbacks/builders: `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`.
### `_DebrifyTVScreenState._resolveUniqueChannelName`

ORIGINAL lines 3569–3583; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.resolveUniqueChannelName`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._handleEditChannel`

ORIGINAL lines 3585–3620; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_actions.dart` → `DebrifyTvChannelActions.handleEditChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelCache` → `_owners.library.channelCache` | 120083 / read / `member/block0/if0/block0/if0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Store current channel's NSFW setting before dialog
// Check if channel's NSFW setting changed
// NSFW setting changed for this channel - rebuild cache with new filter
// Clear existing cache to force full rebuild
// Rebuild cache with new NSFW filter setting (isEdit: false forces full rebuild)
// No NSFW change, just normal update
```
### `_DebrifyTVScreenState._showDebrifyTvConfirmation`

ORIGINAL lines 3622–3665; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_actions.dart` → `DebrifyTvChannelActions._showDebrifyTvConfirmation`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@120843 lexical unbound scope=member/block0 read`.

Escaping callbacks/builders: `PopScope[0].onPopInvokedWithResult = (didPop,result){if(!didPop)Navigator.of(dialogContext).pop(false);}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop(false)`; `DebrifyTvDialogButton[1].onPressed = ()=>Navigator.of(dialogContext).pop(true)`.
### `_DebrifyTVScreenState._handleDeleteChannel`

ORIGINAL lines 3667–3701; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_actions.dart` → `DebrifyTvChannelActions.handleDeleteChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@122127 lexical unbound scope=member/block0 invocation`; `mounted@122652 lexical unbound scope=member/block0/if0 read`; `mounted@122858 lexical unbound scope=member/block0/if1 read`; `mounted@123009 lexical unbound scope=member/block0/if2 read`; `setState@123026 lexical unbound scope=member/block0/if2/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 122147 / write / `member/block0/closure0/block0`; 123048 / write / `member/block0/if2/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Set busy immediately to block any other interactions
// Wait for TWO frames to ensure UI has fully updated and touch events are processed
// Release busy state
```
### `_DebrifyTVScreenState._handleShareChannelAsMagnet`

ORIGINAL lines 3703–3825; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_share.dart` → `DebrifyTvChannelShare.handleShareChannelAsMagnet`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@123172 lexical unbound scope=member/block0/if0 read`; `setState@123208 lexical unbound scope=member/block0 invocation`; `mounted@123846 lexical unbound scope=member/block0/block0/if0 read`; `context@123956 lexical unbound scope=member/block0/block0 read`; `mounted@126923 lexical unbound scope=member/block0/block1/if0 read`; `setState@126942 lexical unbound scope=member/block0/block1/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 123228 / write / `member/block0/closure0/block0`; 126966 / write / `member/block0/block1/if0/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 123250 / write / `member/block0/closure0/block0`; 126993 / write / `member/block0/block1/if0/block0/closure0/block0` |

Escaping callbacks/builders: `showDialog[0].builder = (dialogContext){finalapp=AppThemeScope.of(dialogContext);finaltv=app.debrifyTv;returnDebrifyTvSpotlightDialog(eyebrow:'Share channel · ${channel.channelNumber.toString().padLeft(2,'0')}',title:channel.name,subtitle:'Anyone on Debrify can paste this link to import the channel and its saved pool.',icon:Icons.share_rounded,maxWidth:720,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[Container(padding:constEdgeInsets.all(18),decoration:BoxDecoration(color:tv.dialogDeep.withValues(alpha:.72),borderRadius:app.shape.br(16),border:Border.all(color:tv.hairline)),child:SelectableText(magnetLink,style:TextStyle(color:tv.textDim,fontSize:10,height:1.5,fontFamily:'JetBrainsMono'),maxLines:6)),constSizedBox(height:14),Wrap(spacing:8,runSpacing:8,children:[_SpotlightMetaPill(label:'Link size',value:_formatBytes(estimatedSize)),_SpotlightMetaPill(label:'Compression',value:'${compressionRatio.toStringAsFixed(1)}×'),_SpotlightMetaPill(label:'Keywords',value:'${channel.keywords.length}')])]),actions:[DebrifyTvDialogButton(label:'Close',onPressed:()=>Navigator.of(dialogContext).pop()),DebrifyTvDialogButton(autofocus:true,label:'Copy link',icon:Icons.copy_rounded,tone:DebrifyTvDialogButtonTone.primary,onPressed:(){Clipboard.setData(ClipboardData(text:magnetLink));_showSnack('Channel link copied!',color:Colors.green);Navigator.of(dialogContext).pop();})]);}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`; `DebrifyTvDialogButton[1].onPressed = (){Clipboard.setData(ClipboardData(text:magnetLink));_showSnack('Channel link copied!',color:Colors.green);Navigator.of(dialogContext).pop();}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Generate YAML for sharing (with cached torrents from DB)
// Encode as magnet link
// Estimate sizes for display
// Show magnet link dialog
```
### `_DebrifyTVScreenState._generateChannelYaml`

ORIGINAL lines 3827–3879; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_share.dart` → `DebrifyTvChannelShare._generateChannelYaml`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Generate YAML with channel config and torrent data from cache
// Get cached torrents from database (not in-memory cache)
// Find all torrents that match this keyword (case-insensitive)
// Dedupe by infohash
// Output full torrent object for proper import
```
### `_DebrifyTVScreenState._escapeYamlString`

ORIGINAL lines 3881–3889; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_share.dart` → `DebrifyTvChannelShare._escapeYamlString`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Escape special characters for YAML string
```
### `_DebrifyTVScreenState._handleDeleteAllChannels`

ORIGINAL lines 3891–3959; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_actions.dart` → `DebrifyTvChannelActions.handleDeleteAllChannels`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@129668 lexical unbound scope=member/block0/if1 read`; `setState@129764 lexical unbound scope=member/block0 invocation`; `mounted@130294 lexical unbound scope=member/block0/if2 read`; `mounted@130501 lexical unbound scope=member/block0/if3 read`; `mounted@130563 lexical unbound scope=member/block0/if3/block0/if0 read`; `setState@130582 lexical unbound scope=member/block0/if3/block0/if0/block0 invocation`; `setState@130668 lexical unbound scope=member/block0 invocation`; `setState@130889 lexical unbound scope=member/block0/block0 invocation`; `mounted@131226 lexical unbound scope=member/block0/block1/if0 read`; `setState@131245 lexical unbound scope=member/block0/block1/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 129551 / read / `member/block0/if0`; 129901 / read / `member/block0`; 130013 / read / `member/block0`; 130911 / write / `member/block0/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 129784 / write / `member/block0/closure0/block0`; 130606 / write / `member/block0/if3/block0/if0/block0/closure0/block0`; 130688 / write / `member/block0/closure1/block0`; 131269 / write / `member/block0/block1/if0/block0/closure0/block0` |
| `_channelCache` → `_owners.library.channelCache` | 130959 / read / `member/block0/block0/closure0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Set busy immediately to block any other interactions
// Wait for TWO frames to ensure UI has fully updated and touch events are processed
// Release busy state if cancelled
```
### `_DebrifyTVScreenState._createOrUpdateChannel`

ORIGINAL lines 3961–4189; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_save.dart` → `DebrifyTvChannelSave.createOrUpdateChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@136411 lexical unbound scope=member/block0/block0/if3 read`; `setState@137026 lexical unbound scope=member/block0/block0/if4/block0/if0/block0 invocation`; `setState@137373 lexical unbound scope=member/block0/block0/if4/block0/if0/block1 invocation`; `setState@137906 lexical unbound scope=member/block0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_maxChannelKeywords` → `DebrifyTvConstants.maxChannelKeywords` | 132431 / read / `member/block0/block0/if0`; 132509 / read / `member/block0/block0/if0/block0` |
| `_minimumTorrentsForChannel` → `DebrifyTvConstants.minimumTorrentsForChannel` | 136509 / read / `member/block0/block0/if4`; 136607 / read / `member/block0/block0/if4/block0` |
| `_channelCache` → `_owners.library.channelCache` | 137052 / read / `member/block0/block0/if4/block0/if0/block0/closure0/block0`; 137399 / read / `member/block0/block0/if4/block0/if0/block1/closure0/block0`; 138263 / read / `member/block0/block0/closure0/block0` |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 137102 / read / `member/block0/block0/if4/block0/if0/block0/closure0/block0`; 137445 / read / `member/block0/block0/if4/block0/if0/block1/closure0/block0`; 138313 / read / `member/block0/block0/closure0/block0` |
| `_channels` → `_owners.library.channels` | 137942 / read / `member/block0/block0/closure0/block0`; 138035 / write / `member/block0/block0/closure0/block0/if0/block0`; 138069 / read / `member/block0/block0/closure0/block0/if0/block0`; 138165 / read / `member/block0/block0/closure0/block0/if0/block1`; 138227 / write / `member/block0/block0/closure0/block0/if0/block1` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Memo removal alone would leave the stage on its placeholder: only a
// focus MOVE computes, and editing from the stage doesn't move focus.
```
### `_DebrifyTVScreenState._watchChannel`

ORIGINAL lines 4191–4356; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_watch.dart` → `DebrifyTvChannelWatch.watchChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@142447 lexical unbound scope=member/block0 invocation`; `mounted@145423 lexical unbound scope=member/block0/if7 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_qualityFallbackNotified` → `_owners.session.qualityFallbackNotified` | 139908 / write / `member/block0` |
| `_rdSizeRejections` → `_owners.session.rdSizeRejections` | 139946 / write / `member/block0` |
| `_sizeFilterRelaxed` → `_owners.session.sizeFilterRelaxed` | 139973 / write / `member/block0` |
| `_provider` → `_owners.settings.provider` | 140433 / read / `member/block0`; 140739 / read / `member/block0/if1/block0`; 140868 / read / `member/block0/if1/block0`; 141066 / read / `member/block0`; 143847 / read / `member/block0/if6`; 144139 / read / `member/block0/if6/if0`; 144431 / read / `member/block0/if6/if0/if0`; 144735 / read / `member/block0/if6/if0/if0/if0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 140452 / read / `member/block0/pattern0`; 143860 / read / `member/block0/if6` |
| `_torboxAvailable` → `_owners.settings.torboxAvailable` | 140471 / read / `member/block0/pattern0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 140495 / read / `member/block0/pattern1`; 144152 / read / `member/block0/if6/if0` |
| `_pikpakAvailable` → `_owners.settings.pikpakAvailable` | 140514 / read / `member/block0/pattern1` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 140538 / read / `member/block0/pattern2`; 144444 / read / `member/block0/if6/if0/if0` |
| `_premiumizeAvailable` → `_owners.settings.premiumizeAvailable` | 140561 / read / `member/block0/pattern2` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 140589 / read / `member/block0/pattern3`; 144748 / read / `member/block0/if6/if0/if0/if0` |
| `_allDebridAvailable` → `_owners.settings.allDebridAvailable` | 140611 / read / `member/block0/pattern3` |
| `_rdAvailable` → `_owners.settings.rdAvailable` | 140643 / read / `member/block0/pattern4` |
| `_keywordsController` → `_owners.library.keywordsController` | 142345 / read / `member/block0`; 142550 / read / `member/block0`; 145459 / read / `member/block0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 142467 / write / `member/block0/closure0/block0` |
| `_playbackTorrentThreshold` → `DebrifyTvConstants.playbackTorrentThreshold` | 143588 / read / `member/block0/if5/block0/if0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// [leadWith] (the Spotlight stage's play-one-title): that torrent plays
/// FIRST, with the rest of the shuffled selection behind it. NEVER a
/// single-element queue — the pick may not be cached at the provider, and
/// a one-item queue has nothing to fall back to, which would make a
/// deliberate choice fail exactly where Tune in would have succeeded.
// Track for channel switching
// The chosen title to the front; behaviour after it ends is unchanged.
// The filter narrowed the selection to the pick alone while the pool
// holds more: refill behind it from the wider pool (same cap the
// selector uses), or an uncached pick would have nothing to fall
// through to — the single-element queue the plan forbids.
```
### `_DebrifyTVScreenState._watch`

ORIGINAL lines 4358–5229; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play.dart` → `DebrifyTvQuickPlay.watch`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@146147 lexical unbound scope=member/block0/if0/block0/if0 read`; `setState@146166 lexical unbound scope=member/block0/if0/block0/if0/block0 invocation`; `setState@146654 lexical unbound scope=member/block0/if1/block0 invocation`; `setState@147014 lexical unbound scope=member/block0/if2/block0 invocation`; `setState@147261 lexical unbound scope=member/block0/if3/block0 invocation`; `setState@147713 lexical unbound scope=member/block0 invocation`; `context@148277 lexical unbound scope=member/block0 read`; `mounted@149615 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `context@149738 lexical unbound scope=member/block0/block0/if0/block0 read`; `mounted@159388 lexical unbound scope=member/block0/block0/block0/for0/block0/if5/block0/if1 read`; `setState@159433 lexical unbound scope=member/block0/block0/block0/for0/block0/if5/block0/if1/block0 invocation`; `mounted@159912 lexical unbound scope=member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1 read`; `context@163502 lexical unbound scope=member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0 read`; `mounted@166147 lexical unbound scope=member/block0/catch0/block0/if0 read`; `setState@166170 lexical unbound scope=member/block0/catch0/block0 invocation`; `mounted@166422 lexical unbound scope=member/block0/block1/if0 read`; `setState@166441 lexical unbound scope=member/block0/block1/if0/block0 invocation`; `mounted@166637 lexical unbound scope=member/block0/if9 read`; `mounted@166691 lexical unbound scope=member/block0/if10/block0/if0 read`; `setState@166714 lexical unbound scope=member/block0/if10/block0 invocation`; `mounted@167166 lexical unbound scope=member/block0/if10/block0/if2 read`; `setState@167185 lexical unbound scope=member/block0/if10/block0/if2/block0 invocation`; `context@167332 lexical unbound scope=member/block0/if10/block0/if2/block0 read`; `mounted@167756 lexical unbound scope=member/block0/if11/block0/if0 read`; `setState@167779 lexical unbound scope=member/block0/if11/block0 invocation`; `mounted@168340 lexical unbound scope=member/block0/if12/block0/if0 read`; `context@168384 lexical unbound scope=member/block0/if12/block0 read`; `setState@173241 lexical unbound scope=member/block0 invocation`; `mounted@173740 lexical unbound scope=member/block0/block2/if0/block0/if1 read`; `setState@173761 lexical unbound scope=member/block0/block2/if0/block0/if1/block0 invocation`; `context@174004 lexical unbound scope=member/block0/block2/if0/block0/if1/block0 read`; `mounted@174604 lexical unbound scope=member/block0/block2/if1 read`; `context@176576 lexical unbound scope=member/block0/block2 read`; `mounted@177847 lexical unbound scope=member/block0/block3/if0 read`; `setState@177866 lexical unbound scope=member/block0/block3/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_launchedPlayer` → `_owners.session.launchedPlayer` | 145545 / write / `member/block0`; 159690 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2`; 159942 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1`; 160015 / write / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0`; 165289 / read / `member/block0/block0/if1`; 167726 / read / `member/block0/if11` |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 145601 / write / `member/block0` |
| `_watchCancelled` → `_owners.session.watchCancelled` | 145637 / write / `member/block0`; 150492 / read / `member/block0/block0/function1/closure0/block0/if0`; 150690 / read / `member/block0/block0/function1/closure0/block0`; 150766 / read / `member/block0/block0/function1/closure0/block0/block0/if0`; 151453 / read / `member/block0/block0/function1/closure0/block0/block0/if1/block0/block0/if0`; 152253 / read / `member/block0/block0/function1/closure0/block0/block0/if1/block0/block0/if2/block0/if0`; 153102 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/if0`; 154262 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0`; 154642 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/block0/if0`; 155339 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/block0/if3`; 155456 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/block0/if4`; 156251 / read / `member/block0/block0`; 156797 / read / `member/block0/block0/block0/for0/block0/if0`; 158931 / read / `member/block0/block0/block0/for0/block0/if5/block0/if0`; 159400 / read / `member/block0/block0/block0/for0/block0/if5/block0/if1`; 159710 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2`; 159801 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if0`; 159980 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1`; 160312 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if0`; 160732 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1`; 165166 / read / `member/block0/block0/block0/if0`; 165743 / read / `member/block0/block0/if1/block0/if0`; 166517 / read / `member/block0/if8` |
| `_qualityFallbackNotified` → `_owners.session.qualityFallbackNotified` | 145666 / write / `member/block0` |
| `_rdSizeRejections` → `_owners.session.rdSizeRejections` | 145704 / write / `member/block0` |
| `_sizeFilterRelaxed` → `_owners.session.sizeFilterRelaxed` | 145731 / write / `member/block0` |
| `_originalMaxCap` → `_owners.session.originalMaxCap` | 145763 / write / `member/block0` |
| `_progress` → `_owners.progress.progress` | 145850 / read / `member/block0/function0/closure0/block0`; 145882 / read / `member/block0/function0/closure0/block0`; 147858 / read / `member/block0` |
| `_rdAvailable` → `_owners.settings.rdAvailable` | 145998 / read / `member/block0/if0` |
| `_torboxAvailable` → `_owners.settings.torboxAvailable` | 146023 / read / `member/block0/if0` |
| `_pikpakAvailable` → `_owners.settings.pikpakAvailable` | 146052 / read / `member/block0/if0` |
| `_premiumizeAvailable` → `_owners.settings.premiumizeAvailable` | 146081 / read / `member/block0/if0` |
| `_allDebridAvailable` → `_owners.settings.allDebridAvailable` | 146114 / read / `member/block0/if0` |
| `_status` → `_owners.session.status` | 146190 / write / `member/block0/if0/block0/if0/block0/closure0/block0`; 146676 / write / `member/block0/if1/block0/closure0/block0`; 147036 / write / `member/block0/if2/block0/closure0/block0`; 147283 / write / `member/block0/if3/block0/closure0/block0`; 147755 / write / `member/block0/closure0/block0`; 159463 / write / `member/block0/block0/block0/for0/block0/if5/block0/if1/block0/closure0/block0`; 166192 / write / `member/block0/catch0/block0/closure0/block0`; 166736 / write / `member/block0/if10/block0/closure0/block0`; 167236 / write / `member/block0/if10/block0/if2/block0/closure0/block0`; 167801 / write / `member/block0/if11/block0/closure0/block0`; 173261 / write / `member/block0/closure3/block0`; 173816 / write / `member/block0/block2/if0/block0/if1/block0/closure0/block0`; 177917 / write / `member/block0/block3/if0/block0/closure0/block0` |
| `_keywordsController` → `_owners.library.keywordsController` | 146528 / read / `member/block0` |
| `_quickPlayMaxKeywords` → `_owners.settings.quickPlayMaxKeywords` | 147230 / read / `member/block0/if3`; 147333 / read / `member/block0/if3/block0/closure0/block0`; 147465 / read / `member/block0/if3/block0` |
| `_isBusy` → `_owners.session.isBusy` | 147733 / write / `member/block0/closure0/block0`; 166465 / write / `member/block0/block1/if0/block0/closure0/block0`; 167209 / write / `member/block0/if10/block0/if2/block0/closure0/block0`; 173309 / write / `member/block0/closure3/block0`; 173787 / write / `member/block0/block2/if0/block0/if1/block0/closure0/block0`; 177890 / write / `member/block0/block3/if0/block0/closure0/block0` |
| `_queue` → `_owners.session.queue` | 147787 / read / `member/block0/closure0/block0`; 150625 / read / `member/block0/block0/function1/closure0/block0`; 150668 / read / `member/block0/block0/function1/closure0/block0`; 150732 / read / `member/block0/block0/function1/closure0/block0/block0`; 155399 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/block0/if3/block0`; 159159 / read / `member/block0/block0/block0/for0/block0/if5/block0`; 159253 / read / `member/block0/block0/block0/for0/block0/if5/block0`; 160601 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0`; 165633 / read / `member/block0/block0/if1/block0/if0`; 165887 / read / `member/block0/block0/if1/block0/if0/block0`; 166012 / read / `member/block0/block0/if1/block0`; 166055 / read / `member/block0/block0/if1/block0`; 166662 / read / `member/block0/if10`; 168813 / read / `member/block0/function2/closure0/block0`; 168852 / read / `member/block0/function2/closure0/block0`; 168894 / read / `member/block0/function2/closure0/block0/block0`; 171957 / read / `member/block0/function2/closure0/block0/block0/if1/block0/block0/if0/block0/for0/block0`; 172349 / read / `member/block0/function2/closure0/block0/block0/if1/block0/block0/if0/block0/if0/block0`; 174684 / read / `member/block0/block2` |
| `_progressOpen` → `_owners.progress.progressOpen` | 147884 / write / `member/block0`; 148794 / write / `member/block0/closure2/block0`; 160351 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if0`; 166976 / read / `member/block0/if10/block0/if1`; 167086 / write / `member/block0/if10/block0/if1/block0`; 173540 / read / `member/block0/block2/if0/block0/if0`; 173654 / write / `member/block0/block2/if0/block0/if0/block0`; 174882 / read / `member/block0/block2/if2` |
| `_quickProvider` → `_owners.settings.quickProvider` | 147932 / read / `member/block0`; 147995 / read / `member/block0`; 148058 / read / `member/block0`; 148129 / read / `member/block0`; 148870 / read / `member/block0/if4`; 148982 / read / `member/block0/if5`; 149094 / read / `member/block0/if6`; 149214 / read / `member/block0/if7`; 164355 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 164432 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 164505 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 164578 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 177229 / read / `member/block0/block2/closure0`; 177294 / read / `member/block0/block2/closure0`; 177355 / read / `member/block0/block2/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 147950 / read / `member/block0`; 148888 / read / `member/block0/if4`; 164450 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 177312 / read / `member/block0/block2/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 148013 / read / `member/block0`; 149000 / read / `member/block0/if5`; 164523 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 177373 / read / `member/block0/block2/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 148076 / read / `member/block0`; 149112 / read / `member/block0/if6`; 164596 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 148147 / read / `member/block0`; 149232 / read / `member/block0/if7` |
| `_progressSheetContext` → `_owners.progress.progressSheetContext` | 148391 / write / `member/block0/closure1/block0`; 148823 / write / `member/block0/closure2/block0`; 160388 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if0`; 160452 / read-write / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if0/block0`; 166993 / read / `member/block0/if10/block0/if1`; 167047 / read-write / `member/block0/if10/block0/if1/block0`; 167117 / write / `member/block0/if10/block0/if1/block0`; 173557 / read / `member/block0/block2/if0/block0/if0`; 173613 / read-write / `member/block0/block2/if0/block0/if0/block0`; 173687 / write / `member/block0/block2/if0/block0/if0/block0`; 174899 / read / `member/block0/block2/if2`; 174953 / read-write / `member/block0/block2/if2/block0` |
| `_seenRestrictedLinks` → `_owners.session.seenRestrictedLinks` | 153733 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/closure2`; 154356 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/block0`; 171689 / read / `member/block0/function2/closure0/block0/block0/if1/block0/block0/if0/block0/for0/block0/if1`; 171855 / read / `member/block0/function2/closure0/block0/block0/if1/block0/block0/if0/block0/for0/block0` |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 154412 / read / `member/block0/block0/function1/closure0/block0/block0/if2/block0/block0/block0`; 171748 / read / `member/block0/function2/closure0/block0/block0/if1/block0/block0/if0/block0/for0/block0/if1`; 171903 / read / `member/block0/function2/closure0/block0/block0/if1/block0/block0/if0/block0/for0/block0` |
| `_channelBatchSize` → `_owners.settings.channelBatchSize` | 156313 / read / `member/block0/block0/block0` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 157799 / read / `member/block0/block0/block0/for0/block0/if3` |
| `_rdSkipBlockedTorrents` → `_owners.settings.rdSkipBlockedTorrents` | 158485 / read / `member/block0/block0/block0/for0/block0/if4` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 159236 / write / `member/block0/block0/block0/for0/block0/if5/block0`; 166038 / write / `member/block0/block0/if1/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 159280 / write / `member/block0/block0/block0/for0/block0/if5/block0`; 166078 / write / `member/block0/block0/if1/block0` |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 160769 / write / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0`; 174767 / write / `member/block0/block2` |
| `_activeProvider` → `_owners.prefetch.activeProvider` | 160816 / write / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0`; 174797 / write / `member/block0/block2` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 160834 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0`; 164373 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 174815 / read / `member/block0/block2`; 177247 / read / `member/block0/block2/closure0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 160953 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0`; 175031 / read / `member/block0/block2` |
| `_channels` → `_owners.library.channels` | 161115 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/if0/block0`; 161346 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/if0/block0/if0/block0`; 161822 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0`; 164298 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 164813 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 175157 / read / `member/block0/block2/if3/block0`; 175294 / read / `member/block0/block2/if3/block0/if0/block0`; 175585 / read / `member/block0/block2`; 177184 / read / `member/block0/block2/closure0`; 177537 / read / `member/block0/block2/closure0` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 162666 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0`; 163937 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 175994 / read / `member/block0/block2`; 176907 / read / `member/block0/block2/closure0` |
| `_quickStartRandom` → `_owners.settings.quickStartRandom` | 163748 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 176754 / read / `member/block0/block2/closure0` |
| `_quickRandomStartPercent` → `_owners.settings.quickRandomStartPercent` | 163814 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 176808 / read / `member/block0/block2/closure0` |
| `_quickHideSeekbar` → `_owners.settings.quickHideSeekbar` | 163877 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 176859 / read / `member/block0/block2/closure0` |
| `_quickShowVideoTitle` → `_owners.settings.quickShowVideoTitle` | 164088 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 177022 / read / `member/block0/block2/closure0` |
| `_quickHideOptions` → `_owners.settings.quickHideOptions` | 164147 / read / `member/block0/block0/block0/for0/block0/if5/block0/if2/block0/if1/block0/if1/block0/closure0`; 177069 / read / `member/block0/block2/closure0` |
| `_tvFilters` → `_owners.settings.tvFilters` | 165663 / read / `member/block0/block0/if1/block0/if0` |

Escaping callbacks/builders: `CachedLoadingDialog[0].onCancel = ()=>_cancelActiveWatch(dialogContext:ctx)`; `_launchRealDebridOnAndroidTv[0].requestNext = requestMagicNext`; `_launchRealDebridOnAndroidTv[1].requestNext = requestMagicNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:firstUrl,title:firstTitleResolved,startFromRandom:_quickStartRandom,randomStartMaxPercent:_quickRandomStartPercent,hideSeekbar:_quickHideSeekbar,showChannelName:_quickShowChannelName,channelName:null,channelNumber:null,showVideoTitle:_quickShowVideoTitle,hideOptions:_quickHideOptions,requestMagicNext:requestMagicNext,requestNextChannel:_channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak||_quickProvider==_providerPremiumize)?_requestNextChannel:null,channelDirectory:activeChannelDirectory,requestChannelById:_channels.length>1?_requestChannelById:null)`; `videoPlayerRoute[1].builder = (_)=>VideoPlayerScreen(videoUrl:firstUrl,title:firstTitle,startFromRandom:_quickStartRandom,randomStartMaxPercent:_quickRandomStartPercent,hideSeekbar:_quickHideSeekbar,showChannelName:_quickShowChannelName,channelName:null,channelNumber:null,showVideoTitle:_quickShowVideoTitle,hideOptions:_quickHideOptions,requestMagicNext:requestMagicNext,requestNextChannel:_channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak)?_requestNextChannel:null,channelDirectory:quickChannelDirectory,requestChannelById:_channels.length>1?_requestChannelById:null)`; `VideoPlayerScreen[0].requestMagicNext = requestMagicNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak||_quickProvider==_providerPremiumize)?_requestNextChannel:null`; `VideoPlayerScreen[0].requestChannelById = _channels.length>1?_requestChannelById:null`; `VideoPlayerScreen[1].requestMagicNext = requestMagicNext`; `VideoPlayerScreen[1].requestNextChannel = _channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak)?_requestNextChannel:null`; `VideoPlayerScreen[1].requestChannelById = _channels.length>1?_requestChannelById:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// show non-dismissible loading modal
// ignore: unawaited_futures
// Prevent dismissing by tapping outside
// Silent approach - no progress logging needed
// Require RD API key early so we can prefetch as soon as results arrive
// Helper to infer a filename-like title from a URL
// Case 1: RD-restricted entry (append-only items)
// Case 2: Torrent entry
// Walk THIS torrent's own links until one is playable, rather
// than re-queuing the torrent after a single reject — that would
// cost another add+info round trip per sibling file (see the
// cached-channel flow for the same reasoning).
// Launch limited batches of per-keyword searches so we don't overwhelm
// Apply NSFW filter if enabled
// Filter out RD-blocked torrents
// Silent approach - no progress logging needed
// Do not start prefetch until player launches
// Try to launch player as soon as a playable stream is available
// Start background prefetch only while player is active
// External player set as the default: hand this one title
// over and stop the search — nothing rotates past it.
// Exit the search loop
// Try to launch on Android TV first (early launch path)
// Successfully launched on Android TV
// Prefetch will continue in background while TV player is active
// Exit the search loop
// Hide auto-launch overlay before launching player
// Fall back to Flutter video player
// Stop prefetch when player exits
// Final queue snapshot (if we didn't launch early)
// The per-batch rebuilds above filter strictly, so an empty queue here
// means nothing in the whole search matched the quality filter. This
// is the point where that's genuinely known — degrade to unfiltered
// rather than reporting "no results" for a search that found plenty.
// Close popup and show user-friendly message
// If we already launched the player early, we're done here
// Helper to infer a filename-like title from a URL
// Build a provider for "next" requests that reuses the same queue and keywords
// Case 1: RD-restricted entry (append-only items)
// Prefer filename inferred from URL; fallback to any stored displayName
// Case 2: Torrent entry
// Append other RD-restricted links from this torrent to the END of the queue
// We assume we used rdLinks[0] to play; enqueue remaining
// Prefer filename inferred from URL; fallback to torrent name
// Close popup and show user-friendly message
// Start background prefetch while player is active
// Try to launch on Android TV first
// Successfully launched on Android TV
// Prefetch will continue in background while TV player is active
// Hide auto-launch overlay before launching player
// Fall back to Flutter video player
// Stop prefetch when player exits
```
### `_DebrifyTVScreenState._watchWithTorbox`

ORIGINAL lines 5231–5622; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_torbox.dart` → `DebrifyTvQuickPlayTorbox.watchWithTorbox`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@178288 lexical unbound scope=member/block0/if0/block0/if0 read`; `setState@178311 lexical unbound scope=member/block0/if0/block0 invocation`; `mounted@178709 lexical unbound scope=member/block0/if1/block0/if0 read`; `setState@178732 lexical unbound scope=member/block0/if1/block0 invocation`; `mounted@181475 lexical unbound scope=member/block0/block0/for0/block0/if3/block0/if0 read`; `setState@181498 lexical unbound scope=member/block0/block0/for0/block0/if3/block0/if0/block0 invocation`; `mounted@181971 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@181992 lexical unbound scope=member/block0/block0/if0/block0/if0/block0 invocation`; `mounted@182293 lexical unbound scope=member/block0/block0/if1 read`; `setState@182312 lexical unbound scope=member/block0/block0/if1/block0 invocation`; `mounted@183175 lexical unbound scope=member/block0/block0/function0/closure0/block0/block0/if2 read`; `setState@183198 lexical unbound scope=member/block0/block0/function0/closure0/block0/block0/if2/block0 invocation`; `mounted@183655 lexical unbound scope=member/block0/block0/catch0/block0/if0 read`; `setState@183676 lexical unbound scope=member/block0/block0/catch0/block0/if0/block0 invocation`; `mounted@184000 lexical unbound scope=member/block0/block0/if2/block0/if0 read`; `setState@184021 lexical unbound scope=member/block0/block0/if2/block0/if0/block0 invocation`; `mounted@184720 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0 read`; `setState@184767 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0/block0 invocation`; `mounted@185713 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if3/block0/if1/block0/if0 read`; `setState@185760 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if3/block0/if1/block0/if0/block0 invocation`; `mounted@186535 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if1 read`; `setState@186582 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if1/block0 invocation`; `mounted@186967 lexical unbound scope=member/block0/block0/function1/closure0/block0/if1 read`; `setState@187008 lexical unbound scope=member/block0/block0/function1/closure0/block0/if1/block0 invocation`; `mounted@187313 lexical unbound scope=member/block0/block0/if4/block0/if0 read`; `setState@187354 lexical unbound scope=member/block0/block0/if4/block0/if0/block0 invocation`; `mounted@187696 lexical unbound scope=member/block0/block0/if5 read`; `context@188435 lexical unbound scope=member/block0/block0/if9/block0 read`; `mounted@189410 lexical unbound scope=member/block0/block0/if10 read`; `setState@189449 lexical unbound scope=member/block0/block0/if10/block0 invocation`; `mounted@189747 lexical unbound scope=member/block0/block1/if0 read`; `setState@189766 lexical unbound scope=member/block0/block1/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_status` → `_owners.session.status` | 178333 / write / `member/block0/if0/block0/closure0/block0`; 178754 / write / `member/block0/if1/block0/closure0/block0`; 181526 / write / `member/block0/block0/for0/block0/if3/block0/if0/block0/closure0/block0`; 182018 / write / `member/block0/block0/if0/block0/if0/block0/closure0/block0`; 182336 / write / `member/block0/block0/if1/block0/closure0/block0`; 183226 / write / `member/block0/block0/function0/closure0/block0/block0/if2/block0/closure0/block0`; 183702 / write / `member/block0/block0/catch0/block0/if0/block0/closure0/block0`; 184047 / write / `member/block0/block0/if2/block0/if0/block0/closure0/block0`; 184799 / write / `member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0/block0/closure0/block0`; 185792 / write / `member/block0/block0/function1/closure0/block0/block0/if3/block0/if1/block0/if0/block0/closure0/block0`; 186614 / write / `member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if1/block0/closure0/block0`; 187034 / write / `member/block0/block0/function1/closure0/block0/if1/block0/closure0/block0`; 187380 / write / `member/block0/block0/if4/block0/if0/block0/closure0/block0`; 189473 / write / `member/block0/block0/if10/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 178402 / write / `member/block0/if0/block0/closure0/block0`; 178833 / write / `member/block0/if1/block0/closure0/block0`; 189790 / write / `member/block0/block1/if0/block0/closure0/block0` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 180235 / read / `member/block0/block0/for0/block0/if2` |
| `_queue` → `_owners.session.queue` | 181316 / read / `member/block0/block0/for0/block0/if3/block0`; 181404 / read / `member/block0/block0/for0/block0/if3/block0`; 183003 / read / `member/block0/block0/function0/closure0/block0/block0`; 183104 / read / `member/block0/block0/function0/closure0/block0/block0`; 183236 / read / `member/block0/block0/function0/closure0/block0/block0/if2/block0/closure0/block0`; 183307 / read / `member/block0/block0/function0/closure0/block0/block0/if2/block0/closure0/block0`; 183387 / read / `member/block0/block0/function0/closure0/block0/block0`; 184467 / read / `member/block0/block0/function1/closure0/block0/block0/if0`; 185177 / read / `member/block0/block0/function1/closure0/block0/block0/if1`; 185249 / read / `member/block0/block0/function1/closure0/block0/block0`; 185802 / read / `member/block0/block0/function1/closure0/block0/block0/if3/block0/if1/block0/if0/block0/closure0/block0`; 185881 / read / `member/block0/block0/function1/closure0/block0/block0/if3/block0/if1/block0/if0/block0/closure0/block0`; 186624 / read / `member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if1/block0/closure0/block0`; 186703 / read / `member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if1/block0/closure0/block0`; 189483 / read / `member/block0/block0/if10/block0/closure0/block0`; 189546 / read / `member/block0/block0/if10/block0/closure0/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 181387 / write / `member/block0/block0/for0/block0/if3/block0`; 183087 / write / `member/block0/block0/function0/closure0/block0/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 181429 / write / `member/block0/block0/for0/block0/if3/block0`; 183129 / write / `member/block0/block0/function0/closure0/block0/block0` |
| `_watchCancelled` → `_owners.session.watchCancelled` | 184366 / read / `member/block0/block0/function1/closure0/block0/if0`; 184434 / read / `member/block0/block0/function1/closure0/block0`; 184732 / read / `member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0`; 185283 / read / `member/block0/block0/function1/closure0/block0/block0/if2`; 185599 / read / `member/block0/block0/function1/closure0/block0/block0/if3/block0/if0`; 185725 / read / `member/block0/block0/function1/closure0/block0/block0/if3/block0/if1/block0/if0`; 185962 / read / `member/block0/block0/function1/closure0/block0/block0/if3/block0/if1/block0/if1`; 186311 / read / `member/block0/block0/function1/closure0/block0/block0/if4/block0/if0`; 186442 / read / `member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if0`; 186547 / read / `member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if1`; 186784 / read / `member/block0/block0/function1/closure0/block0/block0/if4/block0/if1/block0/if2`; 186979 / read / `member/block0/block0/function1/closure0/block0/if1`; 187199 / read / `member/block0/block0/if3`; 187325 / read / `member/block0/block0/if4/block0/if0`; 188175 / read / `member/block0/block0/if7`; 188280 / read / `member/block0/block0/if9`; 189422 / read / `member/block0/block0/if10` |
| `_torboxFileEntryType` → `DebrifyTvConstants.torboxFileEntryType` | 185378 / read / `member/block0/block0/function1/closure0/block0/block0/if3` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 188020 / read / `member/block0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 188653 / read / `member/block0/block0/if9/block0/closure0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 188704 / read / `member/block0/block0/if9/block0/closure0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 188752 / read / `member/block0/block0/if9/block0/closure0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 188797 / read / `member/block0/block0/if9/block0/closure0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 188913 / read / `member/block0/block0/if9/block0/closure0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 188957 / read / `member/block0/block0/if9/block0/closure0` |
| `_channels` → `_owners.library.channels` | 189074 / read / `member/block0/block0/if9/block0/closure0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 189121 / read / `member/block0/block0/if9/block0/closure0`; 189188 / read / `member/block0/block0/if9/block0/closure0`; 189251 / read / `member/block0/block0/if9/block0/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 189139 / read / `member/block0/block0/if9/block0/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 189206 / read / `member/block0/block0/if9/block0/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 189269 / read / `member/block0/block0/if9/block0/closure0` |

Escaping callbacks/builders: `_resolveTorboxQueuedFile[0].log = log`; `_prepareTorboxTorrent[0].log = log`; `_launchTorboxOnAndroidTv[0].requestNext = requestTorboxNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:first['url']??'',title:first['title']??'Debrify TV',startFromRandom:_startRandom,randomStartMaxPercent:_randomStartPercent,hideSeekbar:_hideSeekbar,showChannelName:_showChannelName,channelName:null,channelNumber:null,showVideoTitle:_showVideoTitle,hideOptions:_hideOptions,requestMagicNext:requestTorboxNext,requestNextChannel:_channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak)?_requestNextChannel:null)`; `VideoPlayerScreen[0].requestMagicNext = requestTorboxNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak)?_requestNextChannel:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Apply NSFW filter if enabled
// Search is complete here — an empty match means this search really
// has nothing at the requested quality, so degrade rather than fail.
// Hide auto-launch overlay before launching player
```
### `_DebrifyTVScreenState._watchWithPikPak`

ORIGINAL lines 5624–5904; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_pikpak.dart` → `DebrifyTvQuickPlayPikPak.watchWithPikPak`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@190092 lexical unbound scope=member/block0/if0/block0/if0 read`; `setState@190115 lexical unbound scope=member/block0/if0/block0 invocation`; `mounted@192830 lexical unbound scope=member/block0/block0/for0/block0/if3/block0/if0 read`; `setState@192853 lexical unbound scope=member/block0/block0/for0/block0/if3/block0/if0/block0 invocation`; `mounted@193328 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@193349 lexical unbound scope=member/block0/block0/if0/block0/if0/block0 invocation`; `mounted@193790 lexical unbound scope=member/block0/block0/if1 read`; `setState@193809 lexical unbound scope=member/block0/block0/if1/block0 invocation`; `mounted@194937 lexical unbound scope=member/block0/block0/function0/closure0/block0/block0/if5 read`; `setState@194980 lexical unbound scope=member/block0/block0/function0/closure0/block0/block0/if5/block0 invocation`; `mounted@195341 lexical unbound scope=member/block0/block0/function0/closure0/block0/if1 read`; `setState@195382 lexical unbound scope=member/block0/block0/function0/closure0/block0/if1/block0 invocation`; `mounted@195680 lexical unbound scope=member/block0/block0/if3/block0/if0 read`; `setState@195721 lexical unbound scope=member/block0/block0/if3/block0/if0/block0 invocation`; `mounted@196143 lexical unbound scope=member/block0/block0/if4 read`; `context@196926 lexical unbound scope=member/block0/block0/if8/block0 read`; `mounted@197931 lexical unbound scope=member/block0/block0/if9 read`; `setState@197970 lexical unbound scope=member/block0/block0/if9/block0 invocation`; `mounted@198268 lexical unbound scope=member/block0/block1/if0 read`; `setState@198287 lexical unbound scope=member/block0/block1/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_status` → `_owners.session.status` | 190137 / write / `member/block0/if0/block0/closure0/block0`; 192881 / write / `member/block0/block0/for0/block0/if3/block0/if0/block0/closure0/block0`; 193375 / write / `member/block0/block0/if0/block0/if0/block0/closure0/block0`; 193833 / write / `member/block0/block0/if1/block0/closure0/block0`; 195008 / write / `member/block0/block0/function0/closure0/block0/block0/if5/block0/closure0/block0`; 195408 / write / `member/block0/block0/function0/closure0/block0/if1/block0/closure0/block0`; 195747 / write / `member/block0/block0/if3/block0/if0/block0/closure0/block0`; 197994 / write / `member/block0/block0/if9/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 190200 / write / `member/block0/if0/block0/closure0/block0`; 198311 / write / `member/block0/block1/if0/block0/closure0/block0` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 191590 / read / `member/block0/block0/for0/block0/if2` |
| `_queue` → `_owners.session.queue` | 192671 / read / `member/block0/block0/for0/block0/if3/block0`; 192759 / read / `member/block0/block0/for0/block0/if3/block0`; 193646 / read / `member/block0/block0`; 193726 / read / `member/block0/block0`; 194036 / read / `member/block0/block0/function0/closure0/block0`; 194100 / read / `member/block0/block0/function0/closure0/block0/block0`; 194774 / read / `member/block0/block0/function0/closure0/block0/block0/if4/block0`; 194867 / read / `member/block0/block0/function0/closure0/block0/block0/if4/block0`; 195018 / read / `member/block0/block0/function0/closure0/block0/block0/if5/block0/closure0/block0`; 195089 / read / `member/block0/block0/function0/closure0/block0/block0/if5/block0/closure0/block0`; 198004 / read / `member/block0/block0/if9/block0/closure0/block0`; 198067 / read / `member/block0/block0/if9/block0/closure0/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 192742 / write / `member/block0/block0/for0/block0/if3/block0`; 193709 / write / `member/block0/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 192784 / write / `member/block0/block0/for0/block0/if3/block0`; 193747 / write / `member/block0/block0` |
| `_watchCancelled` → `_owners.session.watchCancelled` | 193969 / read / `member/block0/block0/function0/closure0/block0/if0`; 194058 / read / `member/block0/block0/function0/closure0/block0`; 194134 / read / `member/block0/block0/function0/closure0/block0/block0/if0`; 194477 / read / `member/block0/block0/function0/closure0/block0/block0/if2`; 194949 / read / `member/block0/block0/function0/closure0/block0/block0/if5`; 195353 / read / `member/block0/block0/function0/closure0/block0/if1`; 195566 / read / `member/block0/block0/if2`; 195692 / read / `member/block0/block0/if3/block0/if0`; 196666 / read / `member/block0/block0/if6`; 196771 / read / `member/block0/block0/if8`; 197943 / read / `member/block0/block0/if9` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 196511 / read / `member/block0/block0`; 197303 / read / `member/block0/block0/if8/block0/closure0` |
| `_quickStartRandom` → `_owners.settings.quickStartRandom` | 197144 / read / `member/block0/block0/if8/block0/closure0` |
| `_quickRandomStartPercent` → `_owners.settings.quickRandomStartPercent` | 197200 / read / `member/block0/block0/if8/block0/closure0` |
| `_quickHideSeekbar` → `_owners.settings.quickHideSeekbar` | 197253 / read / `member/block0/block0/if8/block0/closure0` |
| `_quickShowVideoTitle` → `_owners.settings.quickShowVideoTitle` | 197424 / read / `member/block0/block0/if8/block0/closure0` |
| `_quickHideOptions` → `_owners.settings.quickHideOptions` | 197473 / read / `member/block0/block0/if8/block0/closure0` |
| `_channels` → `_owners.library.channels` | 197595 / read / `member/block0/block0/if8/block0/closure0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 197642 / read / `member/block0/block0/if8/block0/closure0`; 197709 / read / `member/block0/block0/if8/block0/closure0`; 197772 / read / `member/block0/block0/if8/block0/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 197660 / read / `member/block0/block0/if8/block0/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 197727 / read / `member/block0/block0/if8/block0/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 197790 / read / `member/block0/block0/if8/block0/closure0` |

Same-named lexical hazards (must remain bound to the same declaration): `pikpakAvailable@190032 decl:member/block0#pikpakAvailable#0 scope=member/block0/if0 read`.

Escaping callbacks/builders: `_preparePikPakTorrent[0].log = (msg)=>debugPrint('DebrifyTV/PikPak: $msg')`; `_launchPikPakOnAndroidTv[0].requestNext = requestPikPakNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:first['url']??'',title:first['title']??'Debrify TV',startFromRandom:_quickStartRandom,randomStartMaxPercent:_quickRandomStartPercent,hideSeekbar:_quickHideSeekbar,showChannelName:_quickShowChannelName,channelName:null,channelNumber:null,showVideoTitle:_quickShowVideoTitle,hideOptions:_quickHideOptions,requestMagicNext:requestPikPakNext,requestNextChannel:_channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak)?_requestNextChannel:null)`; `VideoPlayerScreen[0].requestMagicNext = requestPikPakNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak)?_requestNextChannel:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Apply NSFW filter if enabled
// Search is complete here — an empty match means this search really
// has nothing at the requested quality, so degrade rather than fail.
// Add back to queue if there are more files in this torrent
// Try Android TV native player first
// Hide auto-launch overlay before launching player
```
### `_DebrifyTVScreenState._watchWithCachedTorrents`

ORIGINAL lines 5906–6204; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_real_debrid.dart` → `DebrifyTvCachedRealDebrid.watchWithCachedTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@199319 lexical unbound scope=member/block0/if1/block0/if0 read`; `setState@205551 lexical unbound scope=member/block0 invocation`; `mounted@205772 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@205797 lexical unbound scope=member/block0/block0/if0/block0 invocation`; `mounted@206392 lexical unbound scope=member/block0/block0/if1 read`; `context@207445 lexical unbound scope=member/block0/block0 read`; `mounted@208732 lexical unbound scope=member/block0/block1/if0 read`; `setState@208755 lexical unbound scope=member/block0/block1 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 198861 / read / `member/block0`; 208039 / read / `member/block0/block0/closure0`; 208432 / read / `member/block0/block0/closure0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 198961 / read / `member/block0` |
| `_launchedPlayer` → `_owners.session.launchedPlayer` | 199021 / write / `member/block0` |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 199077 / write / `member/block0` |
| `_originalMaxCap` → `_owners.session.originalMaxCap` | 199113 / write / `member/block0` |
| `_seenRestrictedLinks` → `_owners.session.seenRestrictedLinks` | 199141 / read / `member/block0`; 203667 / read / `member/block0/function1/closure0/block0/block0/if1/block0/block0/closure2`; 204340 / read / `member/block0/function1/closure0/block0/block0/if1/block0/block0/block0` |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 199175 / read / `member/block0`; 204394 / read / `member/block0/function1/closure0/block0/block0/if1/block0/block0/block0` |
| `_rdSkipBlockedTorrents` → `_owners.settings.rdSkipBlockedTorrents` | 200309 / read / `member/block0/if3` |
| `_queue` → `_owners.session.queue` | 200693 / read / `member/block0`; 200807 / read / `member/block0`; 201277 / read / `member/block0/function1/closure0/block0`; 201316 / read / `member/block0/function1/closure0/block0`; 201358 / read / `member/block0/function1/closure0/block0/block0`; 205233 / read / `member/block0/function1/closure0/block0/block0/if1/block0/block0/block0/if2/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 200790 / write / `member/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 200826 / write / `member/block0` |
| `_status` → `_owners.session.status` | 205571 / write / `member/block0/closure0/block0`; 205848 / write / `member/block0/block0/if0/block0/closure0/block0`; 208802 / write / `member/block0/block1/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 205619 / write / `member/block0/closure0/block0`; 205821 / write / `member/block0/block0/if0/block0/closure0/block0`; 208777 / write / `member/block0/block1/closure0/block0` |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 206415 / write / `member/block0/block0` |
| `_activeProvider` → `_owners.prefetch.activeProvider` | 206445 / write / `member/block0/block0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 206463 / read / `member/block0/block0`; 208097 / read / `member/block0/block0/closure0` |
| `_startRandom` → `_owners.settings.startRandom` | 207623 / read / `member/block0/block0/closure0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 207672 / read / `member/block0/block0/closure0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 207718 / read / `member/block0/block0/closure0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 207761 / read / `member/block0/block0/closure0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 207887 / read / `member/block0/block0/closure0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 207929 / read / `member/block0/block0/closure0` |
| `_provider` → `_owners.settings.provider` | 208084 / read / `member/block0/block0/closure0`; 208144 / read / `member/block0/block0/closure0`; 208200 / read / `member/block0/block0/closure0`; 208256 / read / `member/block0/block0/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 208157 / read / `member/block0/block0/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 208213 / read / `member/block0/block0/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 208269 / read / `member/block0/block0/closure0` |

Escaping callbacks/builders: `_launchRealDebridOnAndroidTv[0].requestNext = requestMagicNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:firstUrl,title:firstTitle,startFromRandom:_startRandom,randomStartMaxPercent:_randomStartPercent,hideSeekbar:_hideSeekbar,showChannelName:_showChannelName,channelName:channelName,channelNumber:channelNumber,showVideoTitle:_showVideoTitle,hideOptions:_hideOptions,requestMagicNext:requestMagicNext,requestNextChannel:_channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null,channelDirectory:channelDirectory,requestChannelById:_channels.length>1?_requestChannelById:null)`; `VideoPlayerScreen[0].requestMagicNext = requestMagicNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null`; `VideoPlayerScreen[0].requestChannelById = _channels.length>1?_requestChannelById:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Apply NSFW filter to cached torrents if enabled
// Filter out RD-blocked torrents
// Walk THIS torrent's own links until one is playable. Bailing
// after a single reject and re-queuing the torrent would pay
// another add+info round trip just to reach a sibling file, so a
// pack full of samples could burn one RD add per sample and play
// nothing. Unrestrict calls are the cheap half — spend those.
// Try to launch on Android TV first (for cached flow)
// Successfully launched on Android TV
// Prefetch will continue in background while TV player is active
// Hide auto-launch overlay before launching player
// Fall back to Flutter video player
```
### `_DebrifyTVScreenState._watchAllDebridWithCachedTorrents`

ORIGINAL lines 6206–6457; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_all_debrid.dart` → `DebrifyTvCachedAllDebrid.watchAllDebridWithCachedTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@210180 lexical unbound scope=member/block0/if1/block0/if0 read`; `setState@214220 lexical unbound scope=member/block0 invocation`; `mounted@214441 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@214466 lexical unbound scope=member/block0/block0/if0/block0 invocation`; `mounted@215061 lexical unbound scope=member/block0/block0/if1 read`; `context@216081 lexical unbound scope=member/block0/block0 read`; `mounted@217427 lexical unbound scope=member/block0/block1/if0 read`; `setState@217450 lexical unbound scope=member/block0/block1 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 209714 / read / `member/block0`; 216675 / read / `member/block0/block0/closure0`; 217127 / read / `member/block0/block0/closure0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 209814 / read / `member/block0` |
| `_launchedPlayer` → `_owners.session.launchedPlayer` | 209874 / write / `member/block0` |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 209930 / write / `member/block0` |
| `_originalMaxCap` → `_owners.session.originalMaxCap` | 209966 / write / `member/block0` |
| `_seenRestrictedLinks` → `_owners.session.seenRestrictedLinks` | 209994 / read / `member/block0` |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 210028 / read / `member/block0` |
| `_queue` → `_owners.session.queue` | 211124 / read / `member/block0`; 211238 / read / `member/block0`; 211695 / read / `member/block0/function1/closure0/block0`; 211726 / read / `member/block0/function1/closure0/block0`; 211768 / read / `member/block0/function1/closure0/block0/block0`; 213262 / read / `member/block0/function1/closure0/block0/block0/if1/block0/for0/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 211221 / write / `member/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 211257 / write / `member/block0` |
| `_status` → `_owners.session.status` | 214240 / write / `member/block0/closure0/block0`; 214517 / write / `member/block0/block0/if0/block0/closure0/block0`; 217497 / write / `member/block0/block1/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 214288 / write / `member/block0/closure0/block0`; 214490 / write / `member/block0/block0/if0/block0/closure0/block0`; 217472 / write / `member/block0/block1/closure0/block0` |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 215084 / write / `member/block0/block0` |
| `_activeProvider` → `_owners.prefetch.activeProvider` | 215114 / write / `member/block0/block0` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 215132 / read / `member/block0/block0`; 216965 / read / `member/block0/block0/closure0` |
| `_startRandom` → `_owners.settings.startRandom` | 216259 / read / `member/block0/block0/closure0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 216308 / read / `member/block0/block0/closure0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 216354 / read / `member/block0/block0/closure0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 216397 / read / `member/block0/block0/closure0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 216523 / read / `member/block0/block0/closure0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 216565 / read / `member/block0/block0/closure0` |
| `_provider` → `_owners.settings.provider` | 216720 / read / `member/block0/block0/closure0`; 216780 / read / `member/block0/block0/closure0`; 216836 / read / `member/block0/block0/closure0`; 216892 / read / `member/block0/block0/closure0`; 216952 / read / `member/block0/block0/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 216733 / read / `member/block0/block0/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 216793 / read / `member/block0/block0/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 216849 / read / `member/block0/block0/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 216905 / read / `member/block0/block0/closure0` |

Escaping callbacks/builders: `_launchRealDebridOnAndroidTv[0].requestNext = requestMagicNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:firstUrl,title:firstTitle,startFromRandom:_startRandom,randomStartMaxPercent:_randomStartPercent,hideSeekbar:_hideSeekbar,showChannelName:_showChannelName,channelName:channelName,channelNumber:channelNumber,showVideoTitle:_showVideoTitle,hideOptions:_hideOptions,requestMagicNext:requestMagicNext,requestNextChannel:_channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize||_provider==_providerAllDebrid)?_requestNextChannel:null,channelDirectory:channelDirectory,requestChannelById:_channels.length>1?_requestChannelById:null)`; `VideoPlayerScreen[0].requestMagicNext = requestMagicNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize||_provider==_providerAllDebrid)?_requestNextChannel:null`; `VideoPlayerScreen[0].requestChannelById = _channels.length>1?_requestChannelById:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// AllDebrid channel playback. Mirrors the Real-Debrid cached flow
/// (sequential add-and-probe, no cache-check API) but resolves each candidate
/// through AllDebrid's `ready`-flag add (no polling) and lazily unlocks links
/// on demand. The background prefetcher keeps upcoming items prepared.
// Apply NSFW filter to cached torrents if enabled
// AllDebrid returns every file at once: enqueue the remaining video
// files (still locked) so siblings aren't lost if the head fails.
// Try to launch on Android TV first (reuses the generic direct-URL
// launcher; AllDebrid streams are ready URLs just like Real-Debrid's).
// Hide auto-launch overlay before launching player
// Fall back to Flutter video player
```
### `_DebrifyTVScreenState._showNativeSettingsFailure`

ORIGINAL lines 6459–6463; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart` → `DebrifyTvFeedback.showNativeSettingsFailure`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@217786 lexical unbound scope=member/block0/if0 read`.
### `_DebrifyTVScreenState._launchTorboxOnAndroidTv`

ORIGINAL lines 6465–6535; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_player_handoff.dart` → `DebrifyTvPlayerHandoff.launchTorboxOnAndroidTv`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@219200 lexical unbound scope=member/block0/block0/closure0/block0/if0 read`; `setState@219253 lexical unbound scope=member/block0/block0/closure0/block0 invocation`; `mounted@219904 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@219925 lexical unbound scope=member/block0/block0/if0/block0/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 218193 / read / `member/block0/if0` |
| `_channels` → `_owners.library.channels` | 218969 / read / `member/block0/block0`; 219048 / read / `member/block0/block0` |
| `_status` → `_owners.session.status` | 219279 / write / `member/block0/block0/closure0/block0/closure0/block0`; 219951 / write / `member/block0/block0/if0/block0/if0/block0/closure0/block0` |
| `_queue` → `_owners.session.queue` | 219289 / read / `member/block0/block0/closure0/block0/closure0/block0`; 219356 / read / `member/block0/block0/closure0/block0/closure0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 219433 / read / `member/block0/block0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 219478 / read / `member/block0/block0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 219520 / read / `member/block0/block0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 219555 / read / `member/block0/block0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 219593 / read / `member/block0/block0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 219662 / read / `member/block0/block0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 219789 / read / `member/block0/block0` |

Escaping callbacks/builders: `launchTorboxPlayback[0].requestNext = requestNext`; `launchTorboxPlayback[0].requestChannelSwitch = _channels.length>1?_requestNextChannel:null`; `launchTorboxPlayback[0].requestChannelById = _channels.length>1?_requestChannelById:null`; `launchTorboxPlayback[0].onFinished = ()async{AndroidTvPlayerBridge.clearTorboxProvider();if(!mounted){return;}setState((){_status=_queue.isEmpty?'':'Queue has ${_queue.length} remaining';});}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Torbox native player already receives a prepared stream URL, so skip sending magnet
// bundles—the binder payload stays small and launch succeeds.
// Hide auto-launch overlay before launching player
```
### `_DebrifyTVScreenState._requestNextChannel`

ORIGINAL lines 6537–6565; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_watch.dart` → `DebrifyTvChannelWatch.requestNextChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 220468 / read / `member/block0/if0`; 220662 / read / `member/block0/if1/block0`; 220797 / read / `member/block0`; 220858 / read / `member/block0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 220604 / read / `member/block0/if1`; 220707 / read / `member/block0/if1/block0/closure0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Handle channel switching on Android TV - cycles to next channel with looping
```
### `_DebrifyTVScreenState._requestChannelById`

ORIGINAL lines 6567–6606; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_watch.dart` → `DebrifyTvChannelWatch.requestChannelById`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 221284 / read / `member/block0/if0`; 221497 / read / `member/block0/for0`; 221544 / read / `member/block0/for0/block0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 221818 / read / `member/block0/if2` |
### `_DebrifyTVScreenState._switchToChannel`

ORIGINAL lines 6608–7084; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_switch.dart` → `DebrifyTvChannelSwitch.switchToChannel`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@230486 lexical unbound scope=member/block0/block0/if0/block0/for0/block0/if4 read`; `setState@230582 lexical unbound scope=member/block0/block0/if0/block0/for0/block0/if4/block0 invocation`; `mounted@233056 lexical unbound scope=member/block0/block0/if1/block0/for0/block0/if3 read`; `setState@233152 lexical unbound scope=member/block0/block0/if1/block0/for0/block0/if3/block0 invocation`; `mounted@235331 lexical unbound scope=member/block0/block0/if2/block0/for0/block0/if1 read`; `setState@235427 lexical unbound scope=member/block0/block0/if2/block0/for0/block0/if1/block0 invocation`; `mounted@237021 lexical unbound scope=member/block0/block0/if3/block0/for0/block0/if1 read`; `setState@237117 lexical unbound scope=member/block0/block0/if3/block0/for0/block0/if1/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 222564 / read / `member/block0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 223683 / read / `member/block0`; 230610 / write / `member/block0/block0/if0/block0/for0/block0/if4/block0/closure0/block0`; 233180 / write / `member/block0/block0/if1/block0/for0/block0/if3/block0/closure0/block0`; 235455 / write / `member/block0/block0/if2/block0/for0/block0/if1/block0/closure0/block0`; 237145 / write / `member/block0/block0/if3/block0/for0/block0/if1/block0/closure0/block0` |
| `_channelCache` → `_owners.library.channelCache` | 223753 / read / `member/block0/if3/block0` |
| `_seenRestrictedLinks` → `_owners.session.seenRestrictedLinks` | 223914 / read / `member/block0`; 228524 / read / `member/block0/block0/if0/block0/for0/block0/closure2`; 229087 / read / `member/block0/block0/if0/block0/for0/block0/for0/block0` |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 223948 / read / `member/block0`; 229181 / read / `member/block0/block0/if0/block0/for0/block0/for0/block0/if0/block0` |
| `_qualityFallbackNotified` → `_owners.session.qualityFallbackNotified` | 224105 / write / `member/block0` |
| `_rdSizeRejections` → `_owners.session.rdSizeRejections` | 224143 / write / `member/block0` |
| `_sizeFilterRelaxed` → `_owners.session.sizeFilterRelaxed` | 224170 / write / `member/block0` |
| `_provider` → `_owners.settings.provider` | 224436 / read / `member/block0/if4/block0/if0`; 224472 / read / `member/block0/if4/block0/if0`; 224869 / read / `member/block0/if5/block0/if0`; 224905 / read / `member/block0/if5/block0/if0`; 225246 / read / `member/block0/if6/block0/if0`; 225282 / read / `member/block0/if6/block0/if0`; 225446 / read / `member/block0/if7`; 226876 / read / `member/block0/block0/if0`; 231511 / read / `member/block0/block0/if1`; 234537 / read / `member/block0/block0/if2`; 236270 / read / `member/block0/block0/if3`; 238108 / read / `member/block0/block0`; 238303 / read / `member/block0/if8`; 238339 / read / `member/block0/if8` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 224449 / read / `member/block0/if4/block0/if0`; 224882 / read / `member/block0/if5/block0/if0`; 225259 / read / `member/block0/if6/block0/if0`; 226889 / read / `member/block0/block0/if0`; 230891 / read / `member/block0/block0/if0/block0/for0/block0`; 238316 / read / `member/block0/if8` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 224485 / read / `member/block0/if4/block0/if0`; 224918 / read / `member/block0/if5/block0/if0`; 225295 / read / `member/block0/if6/block0/if0`; 231524 / read / `member/block0/block0/if1`; 233947 / read / `member/block0/block0/if1/block0/for0/block0`; 238352 / read / `member/block0/if8` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 225459 / read / `member/block0/if7`; 234550 / read / `member/block0/block0/if2` |
| `_rdSkipBlockedTorrents` → `_owners.settings.rdSkipBlockedTorrents` | 227215 / read / `member/block0/block0/if0/block0/if1` |
| `_queue` → `_owners.session.queue` | 230670 / read / `member/block0/block0/if0/block0/for0/block0/if4/block0/closure0/block0`; 233240 / read / `member/block0/block0/if1/block0/for0/block0/if3/block0/closure0/block0`; 235515 / read / `member/block0/block0/if2/block0/for0/block0/if1/block0/closure0/block0`; 235639 / read / `member/block0/block0/if2/block0/for0/block0/if1/block0/closure0/block0/if0/block0`; 237205 / read / `member/block0/block0/if3/block0/for0/block0/if1/block0/closure0/block0`; 237404 / read / `member/block0/block0/if3/block0/for0/block0/if1/block0/closure0/block0/if0/block0` |
| `_keywordsController` → `_owners.library.keywordsController` | 230768 / read / `member/block0/block0/if0/block0/for0/block0/if4/block0`; 233824 / read / `member/block0/block0/if1/block0/for0/block0/if3/block0`; 235706 / read / `member/block0/block0/if2/block0/for0/block0/if1/block0`; 237471 / read / `member/block0/block0/if3/block0/for0/block0/if1/block0` |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 230839 / write / `member/block0/block0/if0/block0/for0/block0`; 233895 / write / `member/block0/block0/if1/block0/for0/block0` |
| `_activeProvider` → `_owners.prefetch.activeProvider` | 230873 / write / `member/block0/block0/if0/block0/for0/block0`; 233929 / write / `member/block0/block0/if1/block0/for0/block0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 236283 / read / `member/block0/block0/if3` |

Same-named lexical hazards (must remain bound to the same declaration): `pikpakAvailable@236393 decl:member/block0/block0/if3/block0#pikpakAvailable#0 scope=member/block0/block0/if3/block0/if0 read`.

Escaping callbacks/builders: `_prepareTorboxTorrent[0].log = (message)=>debugPrint(message)`; `_preparePikPakTorrent[0].log = (message)=>debugPrint('DebrifyTV/PikPak: $message')`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// New channel, new filter verdict — let it warn again if this one has
// nothing at the requested quality/size.
// Exhaust THIS candidate's links before moving on. Advancing to the
// next candidate costs a whole add+info round trip, so a sample as
// the first pick must not throw away a torrent that has a real
// episode sitting right behind it.
// Not cached/ready or no usable video; try the next candidate.
// Remaining video files of this torrent first (already
// resolved, still locked), then the other candidates.
// Add back to queue if there are more files in this torrent
```
### `_DebrifyTVScreenState._resolveChannelNumber`

ORIGINAL lines 7086–7098; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.resolveChannelNumber`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 238667 / read / `member/block0`; 238818 / read / `member/block0` |
### `_DebrifyTVScreenState._androidTvChannelMetadata`

ORIGINAL lines 7100–7120; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_channel_library.dart` → `DebrifyTvChannelLibrary.androidTvChannelMetadata`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 238997 / read / `member/block0/if0`; 239244 / read / `member/block0/for0`; 239291 / read / `member/block0/for0/block0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 239120 / read / `member/block0` |
### `_DebrifyTVScreenState._launchRealDebridOnAndroidTv`

ORIGINAL lines 7122–7226; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_player_handoff.dart` → `DebrifyTvPlayerHandoff.launchRealDebridOnAndroidTv`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@241788 lexical unbound scope=member/block0/block0/closure0/block0/if0 read`; `setState@241815 lexical unbound scope=member/block0/block0/closure0/block0 invocation`; `mounted@242552 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@242573 lexical unbound scope=member/block0/block0/if0/block0/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 240038 / read / `member/block0`; 240064 / read / `member/block0/if0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 240747 / read / `member/block0/block0`; 241713 / write / `member/block0/block0/closure0/block0`; 242317 / read / `member/block0/block0` |
| `_channels` → `_owners.library.channels` | 240794 / read / `member/block0/block0` |
| `_provider` → `_owners.settings.provider` | 240829 / read / `member/block0/block0`; 240865 / read / `member/block0/block0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 240842 / read / `member/block0/block0` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 240878 / read / `member/block0/block0` |
| `_status` → `_owners.session.status` | 241841 / write / `member/block0/block0/closure0/block0/closure0/block0`; 242599 / write / `member/block0/block0/if0/block0/if0/block0/closure0/block0` |
| `_queue` → `_owners.session.queue` | 241851 / read / `member/block0/block0/closure0/block0/closure0/block0`; 241918 / read / `member/block0/block0/closure0/block0/closure0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 241995 / read / `member/block0/block0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 242040 / read / `member/block0/block0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 242082 / read / `member/block0/block0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 242117 / read / `member/block0/block0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 242155 / read / `member/block0/block0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 242224 / read / `member/block0/block0` |

Escaping callbacks/builders: `launchRealDebridPlayback[0].requestNext = requestNext`; `launchRealDebridPlayback[0].requestChannelSwitch = canSwitchChannels?_requestNextChannel:null`; `launchRealDebridPlayback[0].requestChannelById = canSwitchChannels?_requestChannelById:null`; `launchRealDebridPlayback[0].onFinished = ()async{debugPrint('DebrifyTV: Android TV playback finished callback');// Stop prefetcher when exiting playerawait_stopPrefetch();debugPrint('DebrifyTV: Stopped prefetcher on player exit');AndroidTvPlayerBridge.clearStreamProvider();_currentWatchingChannelId=null;// Clear channel trackingif(!mounted)return;setState((){_status=_queue.isEmpty?'':'Queue has ${_queue.length} remaining';});}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Hide auto-launch overlay before launching player
// Stop prefetcher when exiting player
// Clear channel tracking
```
### `_DebrifyTVScreenState._watchTorboxWithCachedTorrents`

ORIGINAL lines 7228–7502; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_torbox.dart` → `DebrifyTvCachedTorbox.watchTorboxWithCachedTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@244704 lexical unbound scope=member/block0/if3 read`; `setState@244721 lexical unbound scope=member/block0/if3/block0 invocation`; `mounted@245556 lexical unbound scope=member/block0/function1/closure0/block0/block0/if2 read`; `setState@245577 lexical unbound scope=member/block0/function1/closure0/block0/block0/if2/block0 invocation`; `mounted@246084 lexical unbound scope=member/block0/catch0/block0/if0 read`; `setState@246103 lexical unbound scope=member/block0/catch0/block0/if0/block0 invocation`; `mounted@246391 lexical unbound scope=member/block0/if4/block0/if0 read`; `setState@246410 lexical unbound scope=member/block0/if4/block0/if0/block0 invocation`; `mounted@246917 lexical unbound scope=member/block0/function2/closure0/block0/block0/if0/block0/catch0/block0/if0 read`; `setState@246942 lexical unbound scope=member/block0/function2/closure0/block0/block0/if0/block0/catch0/block0/if0/block0 invocation`; `mounted@248155 lexical unbound scope=member/block0/block1/if0/block0/if0 read`; `setState@248180 lexical unbound scope=member/block0/block1/if0/block0 invocation`; `mounted@248591 lexical unbound scope=member/block0/block1/if1 read`; `context@249248 lexical unbound scope=member/block0/block1 read`; `mounted@250392 lexical unbound scope=member/block0/block1/if4 read`; `setState@250411 lexical unbound scope=member/block0/block1/if4/block0 invocation`; `mounted@250710 lexical unbound scope=member/block0/block2/if0 read`; `setState@250733 lexical unbound scope=member/block0/block2 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 243748 / read / `member/block0`; 249873 / read / `member/block0/block1/closure0`; 250266 / read / `member/block0/block1/closure0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 243848 / read / `member/block0` |
| `_status` → `_owners.session.status` | 244743 / write / `member/block0/if3/block0/closure0/block0`; 245603 / write / `member/block0/function1/closure0/block0/block0/if2/block0/closure0/block0`; 248204 / write / `member/block0/block1/if0/block0/closure0/block0`; 250435 / write / `member/block0/block1/if4/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 244789 / write / `member/block0/if3/block0/closure0/block0`; 246127 / write / `member/block0/catch0/block0/if0/block0/closure0/block0`; 246434 / write / `member/block0/if4/block0/if0/block0/closure0/block0`; 246972 / write / `member/block0/function2/closure0/block0/block0/if0/block0/catch0/block0/if0/block0/closure0/block0`; 248277 / write / `member/block0/block1/if0/block0/closure0/block0`; 250755 / write / `member/block0/block2/closure0/block0` |
| `_queue` → `_owners.session.queue` | 245394 / read / `member/block0/function1/closure0/block0/block0`; 245489 / read / `member/block0/function1/closure0/block0/block0`; 245613 / read / `member/block0/function1/closure0/block0/block0/if2/block0/closure0/block0`; 245680 / read / `member/block0/function1/closure0/block0/block0/if2/block0/closure0/block0`; 245779 / read / `member/block0/function1/closure0/block0/block0`; 246586 / read / `member/block0/function2/closure0/block0/block0/if0`; 247141 / read / `member/block0/function2/closure0/block0/block0/if1`; 247208 / read / `member/block0/function2/closure0/block0/block0`; 250445 / read / `member/block0/block1/if4/block0/closure0/block0`; 250508 / read / `member/block0/block1/if4/block0/closure0/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 245472 / write / `member/block0/function1/closure0/block0/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 245512 / write / `member/block0/function1/closure0/block0/block0` |
| `_torboxFileEntryType` → `DebrifyTvConstants.torboxFileEntryType` | 247271 / read / `member/block0/function2/closure0/block0/block0/if2` |
| `_startRandom` → `_owners.settings.startRandom` | 249456 / read / `member/block0/block1/closure0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 249505 / read / `member/block0/block1/closure0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 249551 / read / `member/block0/block1/closure0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 249594 / read / `member/block0/block1/closure0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 249720 / read / `member/block0/block1/closure0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 249762 / read / `member/block0/block1/closure0` |
| `_provider` → `_owners.settings.provider` | 249918 / read / `member/block0/block1/closure0`; 249978 / read / `member/block0/block1/closure0`; 250034 / read / `member/block0/block1/closure0`; 250090 / read / `member/block0/block1/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 249931 / read / `member/block0/block1/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 249991 / read / `member/block0/block1/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 250047 / read / `member/block0/block1/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 250103 / read / `member/block0/block1/closure0` |

Escaping callbacks/builders: `_resolveTorboxQueuedFile[0].log = log`; `_prepareTorboxTorrent[0].log = log`; `_launchTorboxOnAndroidTv[0].requestNext = requestTorboxNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:first['url']??'',title:first['title']??'Debrify TV',startFromRandom:_startRandom,randomStartMaxPercent:_randomStartPercent,hideSeekbar:_hideSeekbar,showChannelName:_showChannelName,channelName:channelName,channelNumber:channelNumber,showVideoTitle:_showVideoTitle,hideOptions:_hideOptions,requestMagicNext:requestTorboxNext,requestNextChannel:_channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null,channelDirectory:channelDirectory,requestChannelById:_channels.length>1?_requestChannelById:null)`; `VideoPlayerScreen[0].requestMagicNext = requestTorboxNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null`; `VideoPlayerScreen[0].requestChannelById = _channels.length>1?_requestChannelById:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Hide auto-launch overlay before launching player
```
### `_DebrifyTVScreenState._watchPikPakWithCachedTorrents`

ORIGINAL lines 7504–7673; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_pikpak.dart` → `DebrifyTvCachedPikPak.watchPikPakWithCachedTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@251892 lexical unbound scope=member/block0/if2 read`; `setState@251909 lexical unbound scope=member/block0/if2/block0 invocation`; `mounted@252941 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@252966 lexical unbound scope=member/block0/block0/if0/block0 invocation`; `mounted@253342 lexical unbound scope=member/block0/block0/if1 read`; `context@254039 lexical unbound scope=member/block0/block0 read`; `mounted@255183 lexical unbound scope=member/block0/block0/if4 read`; `setState@255202 lexical unbound scope=member/block0/block0/if4/block0 invocation`; `mounted@255501 lexical unbound scope=member/block0/block1/if0 read`; `setState@255524 lexical unbound scope=member/block0/block1 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 251266 / read / `member/block0`; 254664 / read / `member/block0/block0/closure0`; 255057 / read / `member/block0/block0/closure0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 251366 / read / `member/block0` |
| `_pikpakCandidatePool` → `_owners.session.pikpakCandidatePool` | 251779 / write / `member/block0`; 251842 / read-write / `member/block0`; 252049 / read-write / `member/block0/if2/block0/closure0/block0` |
| `_status` → `_owners.session.status` | 251931 / write / `member/block0/if2/block0/closure0/block0`; 252990 / write / `member/block0/block0/if0/block0/closure0/block0`; 255226 / write / `member/block0/block0/if4/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 251979 / write / `member/block0/if2/block0/closure0/block0`; 253063 / write / `member/block0/block0/if0/block0/closure0/block0`; 255546 / write / `member/block0/block1/closure0/block0` |
| `_queue` → `_owners.session.queue` | 252003 / read / `member/block0/if2/block0/closure0/block0`; 252205 / read / `member/block0/function1/closure0/block0`; 252267 / read / `member/block0/function1/closure0/block0/block0`; 252617 / read / `member/block0/function1/closure0/block0/block0/if4/block0`; 255236 / read / `member/block0/block0/if4/block0/closure0/block0`; 255299 / read / `member/block0/block0/if4/block0/closure0/block0` |
| `_watchCancelled` → `_owners.session.watchCancelled` | 252161 / read / `member/block0/function1/closure0/block0/if0`; 252227 / read / `member/block0/function1/closure0/block0`; 252299 / read / `member/block0/function1/closure0/block0/block0/if0`; 252481 / read / `member/block0/function1/closure0/block0/block0/if2` |
| `_startRandom` → `_owners.settings.startRandom` | 254247 / read / `member/block0/block0/closure0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 254296 / read / `member/block0/block0/closure0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 254342 / read / `member/block0/block0/closure0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 254385 / read / `member/block0/block0/closure0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 254511 / read / `member/block0/block0/closure0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 254553 / read / `member/block0/block0/closure0` |
| `_provider` → `_owners.settings.provider` | 254709 / read / `member/block0/block0/closure0`; 254769 / read / `member/block0/block0/closure0`; 254825 / read / `member/block0/block0/closure0`; 254881 / read / `member/block0/block0/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 254722 / read / `member/block0/block0/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 254782 / read / `member/block0/block0/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 254838 / read / `member/block0/block0/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 254894 / read / `member/block0/block0/closure0` |

Same-named lexical hazards (must remain bound to the same declaration): `pikpakAvailable@251591 decl:member/block0#pikpakAvailable#0 scope=member/block0/if1 read`.

Escaping callbacks/builders: `_preparePikPakTorrent[0].log = log`; `_launchPikPakOnAndroidTv[0].requestNext = requestPikPakNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:first['url']??'',title:first['title']??'Debrify TV',startFromRandom:_startRandom,randomStartMaxPercent:_randomStartPercent,hideSeekbar:_hideSeekbar,showChannelName:_showChannelName,channelName:channelName,channelNumber:channelNumber,showVideoTitle:_showVideoTitle,hideOptions:_hideOptions,requestMagicNext:requestPikPakNext,requestNextChannel:_channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null,channelDirectory:channelDirectory,requestChannelById:_channels.length>1?_requestChannelById:null)`; `VideoPlayerScreen[0].requestMagicNext = requestPikPakNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null`; `VideoPlayerScreen[0].requestChannelById = _channels.length>1?_requestChannelById:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Try Android TV native player first
// Fall back to Flutter video player (MediaKit)
```
### `_DebrifyTVScreenState._launchPikPakOnAndroidTv`

ORIGINAL lines 7675–7742; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_player_handoff.dart` → `DebrifyTvPlayerHandoff.launchPikPakOnAndroidTv`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@256724 lexical unbound scope=member/block0/block0/closure0/block0/if0 read`; `setState@256777 lexical unbound scope=member/block0/block0/closure0/block0 invocation`; `mounted@257428 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@257449 lexical unbound scope=member/block0/block0/if0/block0/if0/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 255917 / read / `member/block0/if0` |
| `_channels` → `_owners.library.channels` | 256493 / read / `member/block0/block0`; 256572 / read / `member/block0/block0` |
| `_status` → `_owners.session.status` | 256803 / write / `member/block0/block0/closure0/block0/closure0/block0`; 257475 / write / `member/block0/block0/if0/block0/if0/block0/closure0/block0` |
| `_queue` → `_owners.session.queue` | 256813 / read / `member/block0/block0/closure0/block0/closure0/block0`; 256880 / read / `member/block0/block0/closure0/block0/closure0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 256957 / read / `member/block0/block0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 257002 / read / `member/block0/block0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 257044 / read / `member/block0/block0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 257079 / read / `member/block0/block0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 257117 / read / `member/block0/block0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 257186 / read / `member/block0/block0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 257313 / read / `member/block0/block0` |

Escaping callbacks/builders: `launchTorboxPlayback[0].requestNext = requestNext`; `launchTorboxPlayback[0].requestChannelSwitch = _channels.length>1?_requestNextChannel:null`; `launchTorboxPlayback[0].requestChannelById = _channels.length>1?_requestChannelById:null`; `launchTorboxPlayback[0].onFinished = ()async{AndroidTvPlayerBridge.clearTorboxProvider();if(!mounted){return;}setState((){_status=_queue.isEmpty?'':'Queue has ${_queue.length} remaining';});}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Reuse Torbox bridge method - it works for any stream URL
```
### `_DebrifyTVScreenState._showChannelCreationDialog`

ORIGINAL lines 7744–7785; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart` → `DebrifyTvFeedback.showChannelCreationDialog`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@257897 lexical unbound scope=member/block0/if0 read`; `mounted@258017 lexical unbound scope=member/block0/closure0/block0/if0 read`; `context@258267 lexical unbound scope=member/block0/closure0/block0 read`; `context@258319 lexical unbound scope=member/block0/closure0/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_progressOpen` → `_owners.progress.progressOpen` | 257879 / read / `member/block0/if0`; 257958 / write / `member/block0`; 258029 / read / `member/block0/closure0/block0/if0` |
| `_progress` → `_owners.progress.progress` | 257932 / read / `member/block0` |
| `_progressSheetContext` → `_owners.progress.progressSheetContext` | 258737 / write / `member/block0/closure0/block0/closure0/block0/closure0/block0` |

Escaping callbacks/builders: `showGeneralDialog[0].pageBuilder = (ctx,_,__){returncapturedThemes.wrap(ChannelCreationDialog(channelName:channelName,countdownSeconds:countdownSeconds,onReady:(dialogCtx){_progressSheetContext=dialogCtx;}));}`; `showGeneralDialog[0].transitionBuilder = (ctx,animation,secondary,child){finalcurved=CurvedAnimation(parent:animation,curve:Curves.easeOutBack);returnFadeTransition(opacity:animation,child:ScaleTransition(scale:curved,child:child));}`; `ChannelCreationDialog[0].onReady = (dialogCtx){_progressSheetContext=dialogCtx;}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// showGeneralDialog skips InheritedTheme capture; snapshot this frozen
// screen's themes so the dialog stays legacy under any app theme.
```
### `_DebrifyTVScreenState._showCachedPlaybackDialog`

ORIGINAL lines 7787–7840; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart` → `DebrifyTvFeedback.showCachedPlaybackDialog`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@259336 lexical unbound scope=member/block0 read`; `mounted@259413 lexical unbound scope=member/block0/if0 read`; `mounted@259880 lexical unbound scope=member/block0/closure0/block0/if0 read`; `context@260045 lexical unbound scope=member/block0/closure0/block0 read`; `context@260097 lexical unbound scope=member/block0/closure0/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_progressOpen` → `_owners.progress.progressOpen` | 259312 / read / `member/block0`; 259395 / read / `member/block0/if0`; 259821 / write / `member/block0`; 259892 / read / `member/block0/closure0/block0/if0` |
| `_watchCancelled` → `_owners.session.watchCancelled` | 259362 / read / `member/block0`; 259665 / write / `member/block0` |
| `_progress` → `_owners.progress.progress` | 259795 / read / `member/block0` |
| `_progressSheetContext` → `_owners.progress.progressSheetContext` | 260392 / write / `member/block0/closure0/block0/closure0/block0` |

Escaping callbacks/builders: `showGeneralDialog[0].pageBuilder = (ctx,_,__){// Use pageBuilder context directly - simpler and avoids race conditions_progressSheetContext=ctx;returncapturedThemes.wrap(CachedLoadingDialog(onCancel:(){debugPrint('[MagicTV] onCancel callback triggered');_cancelActiveWatch(dialogContext:ctx);}));}`; `showGeneralDialog[0].transitionBuilder = (ctx,animation,secondary,child){finalcurved=CurvedAnimation(parent:animation,curve:Curves.easeOutBack);returnFadeTransition(opacity:animation,child:ScaleTransition(scale:curved,child:child));}`; `CachedLoadingDialog[0].onCancel = (){debugPrint('[MagicTV] onCancel callback triggered');_cancelActiveWatch(dialogContext:ctx);}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Reset cancellation flag for new playback session.
// This must happen before the auto-launch check so that playback can proceed
// even when the dialog is skipped (auto-launch has its own overlay UI).
// Same snapshot rule as the channel-creation dialog above.
// Use pageBuilder context directly - simpler and avoids race conditions
```
### `_DebrifyTVScreenState._playNextFromQueue`

ORIGINAL lines 7842–7942; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_dormant.dart` → `DebrifyTvDormant._playNextFromQueue`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@261247 lexical unbound scope=member/block0/if1/block0/if0 read`; `context@261291 lexical unbound scope=member/block0/if1/block0 read`; `setState@261491 lexical unbound scope=member/block0 invocation`; `mounted@262020 lexical unbound scope=member/block0/block0/block0/block0/if0/block0/if0 read`; `setState@262049 lexical unbound scope=member/block0/block0/block0/block0/if0/block0 invocation`; `context@262384 lexical unbound scope=member/block0/block0/block0/block0/if0/block0 read`; `mounted@263472 lexical unbound scope=member/block0/block0/if0/block0/if1 read`; `setState@263493 lexical unbound scope=member/block0/block0/if0/block0/if1/block0 invocation`; `context@263658 lexical unbound scope=member/block0/block0/if0/block0/if1/block0 read`; `setState@264014 lexical unbound scope=member/block0/block0/if0/block1 invocation`; `setState@264130 lexical unbound scope=member/block0/block1 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 261119 / read / `member/block0/if0`; 261511 / write / `member/block0/closure0/block0`; 263519 / write / `member/block0/block0/if0/block0/if1/block0/closure0/block0`; 264152 / write / `member/block0/block1/closure0/block0` |
| `_status` → `_owners.session.status` | 261533 / write / `member/block0/closure0/block0`; 262077 / write / `member/block0/block0/block0/block0/if0/block0/closure0/block0`; 263548 / write / `member/block0/block0/if0/block0/if1/block0/closure0/block0`; 264038 / write / `member/block0/block0/if0/block1/closure0/block0` |
| `_queue` → `_owners.session.queue` | 261607 / read / `member/block0/block0`; 261649 / read / `member/block0/block0/block0`; 263188 / read / `member/block0/block0/if0`; 264061 / read / `member/block0/block0/if0/block1/closure0/block0` |
| `_quickStartRandom` → `_owners.settings.quickStartRandom` | 262591 / read / `member/block0/block0/block0/block0/if0/block0/closure1` |
| `_quickRandomStartPercent` → `_owners.settings.quickRandomStartPercent` | 262651 / read / `member/block0/block0/block0/block0/if0/block0/closure1` |
| `_quickHideSeekbar` → `_owners.settings.quickHideSeekbar` | 262708 / read / `member/block0/block0/block0/block0/if0/block0/closure1` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 262762 / read / `member/block0/block0/block0/block0/if0/block0/closure1` |
| `_quickShowVideoTitle` → `_owners.settings.quickShowVideoTitle` | 262895 / read / `member/block0/block0/block0/block0/if0/block0/closure1` |
| `_quickHideOptions` → `_owners.settings.quickHideOptions` | 262948 / read / `member/block0/block0/block0/block0/if0/block0/closure1` |
| `_progressOpen` → `_owners.progress.progressOpen` | 263272 / read / `member/block0/block0/if0/block0/if0`; 263386 / write / `member/block0/block0/if0/block0/if0/block0` |
| `_progressSheetContext` → `_owners.progress.progressSheetContext` | 263289 / read / `member/block0/block0/if0/block0/if0`; 263345 / read-write / `member/block0/block0/if0/block0/if0/block0`; 263419 / write / `member/block0/block0/if0/block0/if0/block0` |

Escaping callbacks/builders: `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:videoUrl,title:next.name,startFromRandom:_quickStartRandom,randomStartMaxPercent:_quickRandomStartPercent,hideSeekbar:_quickHideSeekbar,showChannelName:_quickShowChannelName,channelName:null,channelNumber:null,showVideoTitle:_quickShowVideoTitle,hideOptions:_quickHideOptions)`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Hide auto-launch overlay before launching player
// Skip not readily available / failed items and continue
// Close popup and show user-friendly message
```
### `_DebrifyTVScreenState.build`

ORIGINAL lines 7944–7957; step 0; destination `lib/screens/magic_tv_screen.dart` → `_DebrifyTVScreenState.build`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@264279 lexical decl:member#context#0 scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_debrifyTvStyle` → `_owners.library.debrifyTvStyle` | 264315 / read / `member/block0/if0` |
| `_quickPlayFocusNode` → `_owners.focus.quickPlayFocusNode` | 264474 / read / `member/block0/if0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// The historical layout, byte-identical under `grid` — the branch calls
// it unchanged, never a re-implementation.
```
### `_DebrifyTVScreenState._buildSpotlightView`

ORIGINAL lines 7959–7985; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart` → `DebrifyTvSpotlightStage.buildSpotlightView`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 264915 / read / `member/block0` |
| `_favoriteChannelIds` → `_owners.library.favoriteChannelIds` | 264945 / read / `member/block0` |
| `_spotlightRailHealth` → `_owners.stage.spotlightRailHealth` | 264984 / read / `member/block0` |
| `_spotlightFocusedId` → `_owners.stage.spotlightFocusedId` | 265019 / read / `member/block0`; 265092 / read / `member/block0` |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 265076 / read / `member/block0` |
| `_isBusy` → `_owners.session.isBusy` | 265126 / read / `member/block0` |

Escaping callbacks/builders: `DebrifyTvView[0].onQuickPlay = _showQuickPlayDialog`; `DebrifyTvView[0].onAdd = _handleAddChannel`; `DebrifyTvView[0].onImport = _handleImportChannels`; `DebrifyTvView[0].onExport = _handleExportChannels`; `DebrifyTvView[0].onDeleteAll = _handleDeleteAllChannels`; `DebrifyTvView[0].onSettings = _showGlobalSettingsDialog`; `DebrifyTvView[0].onWatch = _watchChannel`; `DebrifyTvView[0].onEdit = _handleEditChannel`; `DebrifyTvView[0].onShare = _handleShareChannelAsMagnet`; `DebrifyTvView[0].onDelete = _handleDeleteChannel`; `DebrifyTvView[0].onToggleFavorite = _toggleChannelFavorite`; `DebrifyTvView[0].onChannelFocused = _onSpotlightChannelFocused`; `DebrifyTvView[0].onWatchOne = (channel,torrent)=>_watchChannel(channel,leadWith:torrent)`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// The Spotlight layout's window onto this state. Paint only: every
/// callback is an existing method, every playback path is shared verbatim.
```
### `_DebrifyTVScreenState._loadSpotlightRailHealth`

ORIGINAL lines 7987–7991; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart` → `DebrifyTvSpotlightStage.loadSpotlightRailHealth`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@265851 lexical unbound scope=member/block0/if0 read`; `setState@265872 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_spotlightRailHealth` → `_owners.stage.spotlightRailHealth` | 265887 / write / `member/block0/closure0` |
### `_DebrifyTVScreenState._onSpotlightChannelFocused`

ORIGINAL lines 7993–8012; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart` → `DebrifyTvSpotlightStage._onSpotlightChannelFocused`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@266735 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_spotlightStatsDebounce` → `_owners.stage.spotlightStatsDebounce` | 266447 / read / `member/block0`; 266813 / write / `member/block0` |
| `_spotlightFocusedId` → `_owners.stage.spotlightFocusedId` | 266486 / write / `member/block0` |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 266760 / read / `member/block0/if0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Focus moved to a channel row. The stage's numbers need a per-row name
/// classify over the pool, so: debounced (a DPAD glide crosses many rows),
/// computed only for the channel that focus RESTS on, and memoised — a
/// pool does not change while you are looking at it.
// Cancel FIRST, unconditionally: a memo hit must still kill a pending
// timer for the previous channel, or gliding B→A (A memoised) classifies
// B off-focus.
// Rebuild NOW either way. On a miss the view's stats go null and the
// stage draws placeholders — never another channel's numbers, which a
// plate press would turn into another channel's torrent.
```
### `_DebrifyTVScreenState._invalidateSpotlightStats`

ORIGINAL lines 8014–8021; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart` → `DebrifyTvSpotlightStage.invalidateSpotlightStats`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_debrifyTvStyle` → `_owners.library.debrifyTvStyle` | 267170 / read / `member/block0/if0` |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 267214 / read / `member/block0` |
| `_spotlightFocusedId` → `_owners.stage.spotlightFocusedId` | 267275 / read / `member/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Wipe every memoised stage snapshot and recompute the focused channel's.
/// For when the numbers' INPUTS change — the quality filter — rather than
/// one channel's pool.
```
### `_DebrifyTVScreenState._refreshSpotlightStatsIfFocused`

ORIGINAL lines 8023–8031; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart` → `DebrifyTvSpotlightStage.refreshSpotlightStatsIfFocused`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_debrifyTvStyle` → `_owners.library.debrifyTvStyle` | 267600 / read / `member/block0/if0` |
| `_spotlightFocusedId` → `_owners.stage.spotlightFocusedId` | 267669 / read / `member/block0/if1` |
| `_channels` → `_owners.library.channels` | 267731 / read / `member/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// A channel's pool (or the filter over it) changed; if it is the one the
/// stage is showing, schedule fresh numbers — memo removal alone leaves
/// the stage on its placeholder forever, since only a focus MOVE computes.
```
### `_DebrifyTVScreenState._computeSpotlightStats`

ORIGINAL lines 8033–8089; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_spotlight_stage.dart` → `DebrifyTvSpotlightStage._computeSpotlightStats`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@267933 lexical unbound scope=member/block0/if0 read`; `mounted@268237 lexical unbound scope=member/block0/if1 read`; `setState@269847 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_spotlightStats` → `_owners.stage.spotlightStats` | 267944 / read / `member/block0/if0`; 269867 / read / `member/block0/closure0/block0` |
| `_spotlightFocusedId` → `_owners.stage.spotlightFocusedId` | 268248 / read / `member/block0/if1` |
| `_tvFilters` → `_owners.settings.tvFilters` | 268610 / read / `member/block0`; 268970 / read / `member/block0/for0/block0/if0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Focus may have moved during the read; bail rather than classify an
// off-focus pool. The entry stays in _channelCache, so a return visit
// pays only the classify.
// ONE pass classifies every name: the quality count and the mix buckets
// share it. Quality only — size is a per-file rule the pool rows cannot
// answer, and counting it here would promise what playback can't keep.
```
### `_DebrifyTVScreenState._toggleChannelSearchBar`

ORIGINAL lines 8091–8105; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar._toggleChannelSearchBar`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@269956 lexical unbound scope=member/block0 invocation`; `mounted@270111 lexical unbound scope=member/block0/closure0/block0/if0/block0/closure0/block0/if0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_showSearchBar` → `_owners.focus.showSearchBar` | 269976 / write / `member/block0/closure0/block0`; 269994 / read / `member/block0/closure0/block0`; 270020 / read / `member/block0/closure0/block0/if0` |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 270134 / read / `member/block0/closure0/block0/if0/block0/closure0/block0/if0/block0` |
| `_channelSearchController` → `_owners.focus.channelSearchController` | 270221 / read / `member/block0/closure0/block0/if0/block1` |
| `_channelSearchTerm` → `_owners.focus.channelSearchTerm` | 270263 / write / `member/block0/closure0/block0/if0/block1` |
### `_DebrifyTVScreenState._clearChannelSearchAndRefocus`

ORIGINAL lines 8107–8113; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar.clearChannelSearchAndRefocus`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `setState@270392 lexical unbound scope=member/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelSearchController` → `_owners.focus.channelSearchController` | 270354 / read / `member/block0` |
| `_channelSearchTerm` → `_owners.focus.channelSearchTerm` | 270412 / write / `member/block0/closure0/block0` |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 270449 / read / `member/block0` |
### `_DebrifyTVScreenState._focusBelowChannelSearch`

ORIGINAL lines 8115–8120; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar.focusBelowChannelSearch`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@270579 selector None scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 270555 / read / `member/block0` |
### `_DebrifyTVScreenState._handleTopMenuAction`

ORIGINAL lines 8122–8140; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar._handleTopMenuAction`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._buildTopActionButton`

ORIGINAL lines 8142–8238; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar._buildTopActionButton`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@272891 lexical decl:member/block0/closure1#context#0 scope=member/block0/closure1/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_showSearchBar` → `_owners.focus.showSearchBar` | 272426 / read / `member/block0/closure0/block0/if3/block0/if0` |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 272456 / read / `member/block0/closure0/block0/if3/block0/if0/block0` |

Escaping callbacks/builders: `Focus[0].onKeyEvent = (node,event){if(eventis!KeyDownEvent)returnKeyEventResult.ignored;finalkey=event.logicalKey;if(key==LogicalKeyboardKey.arrowLeft){if(leftToSidebar){MainPageBridge.focusTvSidebar?.call();}else{leftFocusNode?.requestFocus();}returnKeyEventResult.handled;}if(key==LogicalKeyboardKey.arrowRight){rightFocusNode?.requestFocus();returnKeyEventResult.handled;}if(key==LogicalKeyboardKey.arrowUp){if(upToSearch&&_showSearchBar){_channelSearchFocusNode.requestFocus();}returnKeyEventResult.handled;}if(isActivateKey(key)||key==LogicalKeyboardKey.space){onPressed?.call();returnKeyEventResult.handled;}returnKeyEventResult.ignored;}`; `ListenableBuilder[0].builder = (context,_){finalapp=AppThemeScope.of(context);finaltv=app.debrifyTv;finaldisabled=onPressed==null;finalfocused=focusNode.hasFocus;finalhighlighted=!disabled&&(focused||isActive);returnTooltip(message:tooltip,child:GestureDetector(onTap:onPressed,child:AnimatedContainer(duration:constDuration(milliseconds:150),height:40,width:40,decoration:BoxDecoration(// LEFT LITERAL: the disabled greys. No role holds// Colors.grey / grey-at-0.3, and a disabled tone is not// one of this surface's fills.color:disabled?Colors.grey.withValues(alpha:0.3):(focused?activeColor:(inactiveColor??tv.controlBg)),borderRadius:app.shape.br(20),border:focused&&!disabled?Border.all(color:tv.focusRing.withValues(alpha:0.6),width:2):null),child:Icon(icon,size:20,color:disabled?Colors.grey:(highlighted?app.core.tx:app.core.tx.withValues(alpha:0.5))))));}`; `GestureDetector[0].onTap = onPressed`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Defaults to the surface's resting control fill (`controlBg`). Nullable
/// rather than a const default because a token is not a constant.
// LEFT LITERAL: the disabled greys. No role holds
// `Colors.grey` / grey-at-0.3, and a disabled tone is not
// one of this surface's fills.
```
### `_DebrifyTVScreenState._buildTopMenuButton`

ORIGINAL lines 8240–8399; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar._buildTopMenuButton`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@274620 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelMenuFocusNode` → `_owners.focus.channelMenuFocusNode` | 275407 / read / `member/block0`; 275771 / read / `member/block0/closure2/block0/if1/block0/if0/block0`; 276635 / read / `member/block0`; 279083 / read / `member/block0/closure3/closure5/block0` |
| `_channelMenuController` → `_owners.focus.channelMenuController` | 275582 / read / `member/block0/closure2/block0/if1`; 275727 / read / `member/block0/closure2/block0/if1/block0/if0/block0`; 276452 / read / `member/block0/closure2/block0/if5/block0`; 276725 / read / `member/block0/closure3` |
| `_channelSearchButtonFocusNode` → `_owners.focus.channelSearchButtonFocusNode` | 275977 / read / `member/block0/closure2/block0/if2/block0` |
| `_showSearchBar` → `_owners.focus.showSearchBar` | 276240 / read / `member/block0/closure2/block0/if4/block0/if0` |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 276270 / read / `member/block0/closure2/block0/if4/block0/if0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 277489 / read / `member/block0/closure3`; 277810 / read / `member/block0/closure3`; 278154 / read / `member/block0/closure3`; 278481 / read / `member/block0/closure3` |
| `_channels` → `_owners.library.channels` | 277821 / read / `member/block0/closure3`; 278492 / read / `member/block0/closure3` |

Escaping callbacks/builders: `Focus[0].onKeyEvent = (node,event){if(eventis!KeyDownEvent)returnKeyEventResult.ignored;finalkey=event.logicalKey;if(_channelMenuController.isOpen){if(key==LogicalKeyboardKey.escape||key==LogicalKeyboardKey.goBack){_channelMenuController.close();_channelMenuFocusNode.requestFocus();returnKeyEventResult.handled;}returnKeyEventResult.ignored;}if(key==LogicalKeyboardKey.arrowLeft){_channelSearchButtonFocusNode.requestFocus();returnKeyEventResult.handled;}if(key==LogicalKeyboardKey.arrowRight){returnKeyEventResult.handled;}if(key==LogicalKeyboardKey.arrowUp){if(_showSearchBar){_channelSearchFocusNode.requestFocus();}returnKeyEventResult.handled;}if(isActivateKey(key)||key==LogicalKeyboardKey.space){_channelMenuController.open();returnKeyEventResult.handled;}returnKeyEventResult.ignored;}`; `ListenableBuilder[0].builder = (context,_)=>MenuAnchor(controller:_channelMenuController,style:MenuStyle(backgroundColor:WidgetStatePropertyAll(tv.noticeBg),surfaceTintColor:constWidgetStatePropertyAll(Colors.transparent),elevation:constWidgetStatePropertyAll(18),padding:constWidgetStatePropertyAll(EdgeInsets.all(8)),shape:WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius:app.shape.br(18),side:BorderSide(color:tv.hairline)))),menuChildren:[MenuItemButton(autofocus:true,style:itemStyle,leadingIcon:constIcon(Icons.cloud_download_rounded),onPressed:_isBusy?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.import),child:constText('Import')),MenuItemButton(style:itemStyle,leadingIcon:constIcon(Icons.folder_zip_rounded),onPressed:_isBusy||_channels.isEmpty?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.export),child:constText('Export Channels')),MenuItemButton(style:itemStyle,leadingIcon:constIcon(Icons.add_rounded),onPressed:_isBusy?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.add),child:constText('Add Channel')),MenuItemButton(style:itemStyle,leadingIcon:constIcon(Icons.delete_outline_rounded),onPressed:_isBusy||_channels.isEmpty?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.deleteAll),child:constText('Delete All')),MenuItemButton(style:itemStyle,leadingIcon:constIcon(Icons.settings_rounded),onPressed:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.settings),child:constText('Settings'))],builder:(context,controller,child){finalfocused=_channelMenuFocusNode.hasFocus;returnTooltip(message:'Options',child:GestureDetector(onTap:(){if(controller.isOpen){controller.close();}else{controller.open();}},child:AnimatedContainer(duration:constDuration(milliseconds:150),height:40,width:40,decoration:BoxDecoration(color:focused?tv.fillStrong:tv.controlBg,borderRadius:app.shape.br(20),border:focused?Border.all(color:tv.focusRing.withValues(alpha:0.6),width:2):null),child:Icon(Icons.more_vert_rounded,size:20,color:focused?app.core.tx:app.core.tx.withValues(alpha:0.5)))));})`; `MenuAnchor[0].builder = (context,controller,child){finalfocused=_channelMenuFocusNode.hasFocus;returnTooltip(message:'Options',child:GestureDetector(onTap:(){if(controller.isOpen){controller.close();}else{controller.open();}},child:AnimatedContainer(duration:constDuration(milliseconds:150),height:40,width:40,decoration:BoxDecoration(color:focused?tv.fillStrong:tv.controlBg,borderRadius:app.shape.br(20),border:focused?Border.all(color:tv.focusRing.withValues(alpha:0.6),width:2):null),child:Icon(Icons.more_vert_rounded,size:20,color:focused?app.core.tx:app.core.tx.withValues(alpha:0.5)))));}`; `MenuItemButton[0].onPressed = _isBusy?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.import)`; `MenuItemButton[1].onPressed = _isBusy||_channels.isEmpty?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.export)`; `MenuItemButton[2].onPressed = _isBusy?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.add)`; `MenuItemButton[3].onPressed = _isBusy||_channels.isEmpty?null:()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.deleteAll)`; `MenuItemButton[4].onPressed = ()=>_handleTopMenuAction(_DebrifyTvTopMenuAction.settings)`; `GestureDetector[0].onTap = (){if(controller.isOpen){controller.close();}else{controller.open();}}`.
### `_DebrifyTVScreenState._buildTopActions`

ORIGINAL lines 8401–8432; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_top_bar.dart` → `DebrifyTvTopBar.buildTopActions`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@280446 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_quickPlayFocusNode` → `_owners.focus.quickPlayFocusNode` | 280623 / read / `member/block0`; 281316 / read / `member/block0` |
| `_isBusy` → `_owners.session.isBusy` | 280734 / read / `member/block0` |
| `_channelSearchButtonFocusNode` → `_owners.focus.channelSearchButtonFocusNode` | 280868 / read / `member/block0`; 280997 / read / `member/block0` |
| `_showSearchBar` → `_owners.focus.showSearchBar` | 281085 / read / `member/block0`; 281242 / read / `member/block0` |
| `_channelSearchTerm` → `_owners.focus.channelSearchTerm` | 281260 / read / `member/block0` |
| `_channelMenuFocusNode` → `_owners.focus.channelMenuFocusNode` | 281363 / read / `member/block0` |

Escaping callbacks/builders: `_buildTopActionButton[0].onPressed = _isBusy?null:_showQuickPlayDialog`; `_buildTopActionButton[1].onPressed = _toggleChannelSearchBar`.
### `_DebrifyTVScreenState._buildTvGridLayout`

ORIGINAL lines 8435–8674; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_layout.dart` → `DebrifyTvGridLayout.buildTvGridLayout`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@281641 lexical unbound scope=member/block0 read`; `context@282013 lexical unbound scope=member/block0 read`; `context@285873 lexical decl:member/block0/if0/closure5#context#0 scope=member/block0/if0/closure5/block0 read`; `context@285946 lexical decl:member/block0/if0/closure5#context#0 scope=member/block0/if0/closure5/block0 read`; `setState@288257 lexical unbound scope=member/block0/if0/closure6/block0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channelSearchTerm` → `_owners.focus.channelSearchTerm` | 281704 / read / `member/block0`; 284225 / read / `member/block0/if0`; 288291 / write / `member/block0/if0/closure6/block0/closure0/block0` |
| `_channels` → `_owners.library.channels` | 281803 / read / `member/block0`; 281823 / read / `member/block0` |
| `_showSearchBar` → `_owners.focus.showSearchBar` | 282584 / read / `member/block0/if0` |
| `_channelSearchFocusNode` → `_owners.focus.channelSearchFocusNode` | 282853 / read / `member/block0/if0`; 284762 / read / `member/block0/if0/closure4/block0/if1/block0` |
| `_channelSearchController` → `_owners.focus.channelSearchController` | 282906 / read / `member/block0/if0`; 283467 / read / `member/block0/if0/closure1/block0/if0` |
| `_channelSearchClearFocusNode` → `_owners.focus.channelSearchClearFocusNode` | 283531 / read / `member/block0/if0/closure1/block0/if0/block0`; 284323 / read / `member/block0/if0` |
| `_channelSearchButtonFocusNode` → `_owners.focus.channelSearchButtonFocusNode` | 283648 / read / `member/block0/if0/closure2`; 285223 / read / `member/block0/if0/closure4/block0/if3/block0` |
| `_channelMenuFocusNode` → `_owners.focus.channelMenuFocusNode` | 284995 / read / `member/block0/if0/closure4/block0/if2/block0` |
| `_favoriteChannelIds` → `_owners.library.favoriteChannelIds` | 288661 / read / `member/block0/if1` |

Escaping callbacks/builders: `Focus[0].onKeyEvent = _handleChannelSearchBarBack`; `Focus[1].onKeyEvent = (node,event){if(eventis!KeyDownEvent){returnKeyEventResult.ignored;}finalkey=event.logicalKey;if(key==LogicalKeyboardKey.arrowLeft){_channelSearchFocusNode.requestFocus();returnKeyEventResult.handled;}if(key==LogicalKeyboardKey.arrowRight){_channelMenuFocusNode.requestFocus();returnKeyEventResult.handled;}if(key==LogicalKeyboardKey.arrowUp){_channelSearchButtonFocusNode.requestFocus();returnKeyEventResult.handled;}if(isActivateKey(key)||key==LogicalKeyboardKey.space){_clearChannelSearchAndRefocus();returnKeyEventResult.handled;}returnKeyEventResult.ignored;}`; `TvTextField[0].onLeftArrow = ()=>MainPageBridge.focusTvSidebar?.call()`; `TvTextField[0].onRightArrow = (){if(_channelSearchController.text.isNotEmpty){_channelSearchClearFocusNode.requestFocus();}}`; `TvTextField[0].onUpArrow = ()=>_channelSearchButtonFocusNode.requestFocus()`; `TvTextField[0].onSubmitted = (_)=>_focusBelowChannelSearch()`; `TvTextField[0].onDownArrow = _focusBelowChannelSearch`; `TvTextField[0].onChanged = (value){setState((){_channelSearchTerm=value;});}`; `Builder[0].builder = (context){finalink=AppThemeScope.of(context).core.tx;finalfocused=Focus.of(context).hasFocus;returnContainer(decoration:focused?BoxDecoration(borderRadius:app.shape.br(20),border:Border.all(color:ink.withValues(alpha:0.3),width:1.5)):null,child:IconButton(icon:Icon(Icons.close_rounded,color:focused?ink:ink.withValues(alpha:0.5)),onPressed:_clearChannelSearchAndRefocus));}`; `IconButton[0].onPressed = _clearChannelSearchAndRefocus`; `LayoutBuilder[0].builder = (context,constraints){// Responsive grid: 2 cols on mobile, 3 on tablet, 4 on TV/desktopfinalwidth=constraints.maxWidth;intcrossAxisCount;doublespacing;doublechildAspectRatio;if(width<500){crossAxisCount=2;spacing=12;childAspectRatio=1.4;}elseif(width<800){crossAxisCount=3;spacing=16;childAspectRatio=1.45;}else{crossAxisCount=4;spacing=24;childAspectRatio=1.5;}returnGridView.builder(padding:constEdgeInsets.symmetric(horizontal:4,vertical:4),gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:crossAxisCount,mainAxisSpacing:spacing,crossAxisSpacing:spacing,childAspectRatio:childAspectRatio),itemCount:filteredChannels.length+1,// +1 for "Add Channel" carditemBuilder:(context,index){if(index==filteredChannels.length){// "Add Channel" card at the endreturnKeyedSubtree(key:constValueKey('add_channel_card'),child:_buildTvAddChannelCard());}finalchannel=filteredChannels[index];returnKeyedSubtree(key:ValueKey('channel_${channel.id}'),child:_buildTvChannelCard(channel));});}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Responsive padding: smaller on mobile, larger on TV/tablet
// Centered top controls: Play, Search, and overflow.
// Search field for TV (only show when toggled)
// Shared TV shell/keyboard chrome — settings.accent, with the
// keyboard's own panel ground and ink.
// The search field's focused border is `fillStrong` by
// design — see the token's own doc.
// Favorite channels section (only shows if there are favorites)
// "All" section header (only show when there are favorites to distinguish)
// Channel grid (responsive)
// Responsive grid: 2 cols on mobile, 3 on tablet, 4 on TV/desktop
// +1 for "Add Channel" card
// "Add Channel" card at the end
```
### `_DebrifyTVScreenState._buildTvEmptyState`

ORIGINAL lines 8677–8710; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_layout.dart` → `DebrifyTvGridLayout._buildTvEmptyState`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@292102 lexical unbound scope=member/block0 read`.

Escaping callbacks/builders: `TvFocusableButton[0].onPressed = _handleAddChannel`.
### `_DebrifyTVScreenState._buildFavoriteChannelsSection`

ORIGINAL lines 8713–8768; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_cards.dart` → `DebrifyTvGridCards.buildFavoriteChannelsSection`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@293201 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 293322 / read / `member/block0` |
| `_favoriteChannelIds` → `_owners.library.favoriteChannelIds` | 293360 / read / `member/block0/closure0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Get favorite channels from the channels list
// Don't show if no favorites
// Section header
// Horizontal scrolling favorites
```
### `_DebrifyTVScreenState._buildFavoriteChannelCard`

ORIGINAL lines 8771–8846; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_cards.dart` → `DebrifyTvGridCards._buildFavoriteChannelCard`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@295013 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 295972 / read / `member/block0` |

Escaping callbacks/builders: `TvFocusableCard[0].onPressed = ()=>_watchChannel(channel)`; `TvFocusableCard[0].onLongPress = ()=>_showTvChannelOptionsMenu(channel)`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Main content
// Channel number badge (smaller)
// Channel name
// Star indicator
```
### `_DebrifyTVScreenState._buildTvChannelCard`

ORIGINAL lines 8849–9023; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_cards.dart` → `DebrifyTvGridCards.buildTvChannelCard`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@297610 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_favoriteChannelIds` → `_owners.library.favoriteChannelIds` | 297674 / read / `member/block0` |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 297910 / read / `member/block0`; 300274 / read / `member/block0/if1` |
| `_channels` → `_owners.library.channels` | 299187 / read / `member/block0` |

Escaping callbacks/builders: `TvFocusableCard[0].onPressed = (){_watchChannel(channel);}`; `TvFocusableCard[0].onLongPress = (){_showTvChannelOptionsMenu(channel);}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Only show hint on Android TV
// Favorite star indicator (top-left)
// Main card content
// Channel number badge
// Channel name - centered
// 3-dot menu for non-Android TV devices
// Sits on the black plate above, so it takes glass ink.
```
### `_DebrifyTVScreenState._showTvChannelOptionsMenu`

ORIGINAL lines 9026–9103; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_dialogs.dart` → `DebrifyTvDialogs.showTvChannelOptionsMenu`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@304084 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_favoriteChannelIds` → `_owners.library.favoriteChannelIds` | 303998 / read / `member/block0` |

Escaping callbacks/builders: `DebrifyTvDialogOptionCard[0].onPressed = (){Navigator.of(dialogContext).pop();_toggleChannelFavorite(channel);}`; `DebrifyTvDialogOptionCard[1].onPressed = (){Navigator.of(dialogContext).pop();_handleEditChannel(channel);}`; `DebrifyTvDialogOptionCard[2].onPressed = (){Navigator.of(dialogContext).pop();_handleShareChannelAsMagnet(channel);}`; `DebrifyTvDialogOptionCard[3].onPressed = (){Navigator.of(dialogContext).pop();_handleDeleteChannel(channel);}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`.
### `_DebrifyTVScreenState._buildTvAddChannelCard`

ORIGINAL lines 9106–9138; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_grid_cards.dart` → `DebrifyTvGridCards.buildTvAddChannelCard`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@306955 lexical unbound scope=member/block0 read`.

Escaping callbacks/builders: `TvFocusableCard[0].onPressed = _handleAddChannel`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Ensures consistent height
```
### `_DebrifyTVScreenState._buildSettingsCard`

ORIGINAL lines 9140–9383; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_settings_card.dart` → `DebrifyTvSettingsCard.buildSettingsCard`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@308087 lexical unbound scope=member/block0 read`; `setState@308315 lexical unbound scope=member/block0/function0/closure0/block0 invocation`; `setState@308773 lexical unbound scope=member/block0/function1/closure0/block0 invocation`; `setState@309242 lexical unbound scope=member/block0/function2/closure0/block0 invocation`; `setState@309698 lexical unbound scope=member/block0/function3/closure0/block0 invocation`; `context@311531 lexical unbound scope=member/block0 read`; `setState@313289 lexical unbound scope=member/block0/if1/closure0/block0 invocation`; `setState@314309 lexical unbound scope=member/block0/closure1/block0 invocation`; `mounted@316333 lexical unbound scope=member/block0/closure1/block0/if1 read`; `context@316426 lexical unbound scope=member/block0/closure1/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_quickStartRandom` → `_owners.settings.quickStartRandom` | 308237 / read / `member/block0`; 308367 / write / `member/block0/function0/closure0/block0/closure0/block0/if0/block0`; 314381 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 308257 / read / `member/block0`; 308421 / write / `member/block0/function0/closure0/block0/closure0/block0/if0/block1`; 314913 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_quickRandomStartPercent` → `_owners.settings.quickRandomStartPercent` | 308667 / read / `member/block0`; 308825 / write / `member/block0/function1/closure0/block0/closure0/block0/if0/block0`; 314427 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 308702 / read / `member/block0`; 308886 / write / `member/block0/function1/closure0/block0/closure0/block0/if0/block1`; 314954 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 309144 / read / `member/block0`; 309294 / write / `member/block0/function2/closure0/block0/closure0/block0/if0/block0`; 314548 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 309176 / read / `member/block0`; 309352 / write / `member/block0/function2/closure0/block0/closure0/block0/if0/block1`; 315065 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_quickShowVideoTitle` → `_owners.settings.quickShowVideoTitle` | 309603 / read / `member/block0`; 309750 / write / `member/block0/function3/closure0/block0/closure0/block0/if0/block0`; 314598 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 309634 / read / `member/block0`; 309807 / write / `member/block0/function3/closure0/block0/closure0/block0/if0/block1`; 315110 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_isAndroidTv` → `_owners.settings.isAndroidTv` | 312213 / read / `member/block0/if0` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 313104 / read / `member/block0/if1`; 313323 / write / `member/block0/if1/closure0/block0/closure0/block0`; 314788 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_rdAvailable` → `_owners.settings.rdAvailable` | 314108 / read / `member/block0/closure1/block0` |
| `_torboxAvailable` → `_owners.settings.torboxAvailable` | 314140 / read / `member/block0/closure1/block0` |
| `_pikpakAvailable` → `_owners.settings.pikpakAvailable` | 314176 / read / `member/block0/closure1/block0` |
| `_premiumizeAvailable` → `_owners.settings.premiumizeAvailable` | 314212 / read / `member/block0/closure1/block0` |
| `_allDebridAvailable` → `_owners.settings.allDebridAvailable` | 314252 / read / `member/block0/closure1/block0` |
| `_quickHideSeekbar` → `_owners.settings.quickHideSeekbar` | 314502 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_quickHideOptions` → `_owners.settings.quickHideOptions` | 314647 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_quickHideBackButton` → `_owners.settings.quickHideBackButton` | 314716 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 314832 / write / `member/block0/closure1/block0/closure0/block0/if0/block0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 315024 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_hideOptions` → `_owners.settings.hideOptions` | 315154 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_hideBackButton` → `_owners.settings.hideBackButton` | 315218 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_provider` → `_owners.settings.provider` | 315285 / write / `member/block0/closure1/block0/closure0/block0/if0/block1` |
| `_tvFilters` → `_owners.settings.tvFilters` | 315469 / write / `member/block0/closure1/block0/closure0/block0` |

Same-named lexical hazards (must remain bound to the same declaration): `startRandom@311954 decl:member/block0#startRandom#0 scope=member/block0 read`; `startRandom@312049 decl:member/block0#startRandom#0 scope=member/block0/if0 read`; `randomStartPercent@312164 decl:member/block0#randomStartPercent#0 scope=member/block0/if0 read`.

Escaping callbacks/builders: `SwitchRow[0].onChanged = (v)=>setStartRandom(v)`; `SwitchRow[1].onChanged = (v){// Role-locked: a child session cannot loosen it.if(_viewerForcesNsfw)return;setState((){_quickAvoidNsfw=v;});dialogSetState?.call((){});}`; `RandomStartSlider[0].onChanged = (next)=>setRandomStartPercent(next)`; `RandomStartSlider[0].onChangeEnd = isQuickScope?null:(next)=>DebrifyTvStorage.saveDebrifyTvRandomStartPercent(next)`; `DebrifyTvDialogButton[0].onPressed = ()async{finaldefaultProvider=_determineDefaultProvider(null,_rdAvailable,_torboxAvailable,_pikpakAvailable,_premiumizeAvailable,_allDebridAvailable);setState((){if(isQuickScope){_quickStartRandom=true;_quickRandomStartPercent=_randomStartPercentDefault;_quickHideSeekbar=true;_quickShowChannelName=true;_quickShowVideoTitle=true;_quickHideOptions=false;// Hardcoded to false_quickHideBackButton=false;// Hardcoded to false_quickAvoidNsfw=true;_quickProvider=defaultProvider;}else{_startRandom=true;_randomStartPercent=_randomStartPercentDefault;_hideSeekbar=true;_showChannelName=true;_showVideoTitle=true;_hideOptions=false;// Hardcoded to false_hideBackButton=false;// Hardcoded to false_provider=defaultProvider;}// Playback filters are shared by both scopes, so reset// them from either one._tvFilters=constDebrifyTvFilters.empty();});_invalidateSpotlightStats();dialogSetState?.call((){});awaitDebrifyTvStorage.setDebrifyTvFilterQualities(const[]);awaitDebrifyTvStorage.setDebrifyTvFilterSizes(const[]);if(!isQuickScope){awaitDebrifyTvStorage.saveDebrifyTvStartRandom(true);awaitDebrifyTvStorage.saveDebrifyTvHideSeekbar(true);awaitDebrifyTvStorage.saveDebrifyTvShowChannelName(true);awaitDebrifyTvStorage.saveDebrifyTvShowVideoTitle(true);// No longer saving hideOptions and hideBackButton - they're hardcoded to falseawaitDebrifyTvStorage.saveDebrifyTvProvider(defaultProvider);}if(!mounted){return;}ScaffoldMessenger.of(context).showSnackBar(constSnackBar(content:Text('Reset to defaults successful'),backgroundColor:Colors.green,duration:Duration(seconds:2)));}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Hardcoded to false - no longer changeable
// No-op: hideOptions is now hardcoded to false
// Keep function for compatibility but it doesn't do anything
// Hardcoded to false - no longer changeable
// No-op: hideBackButton is now hardcoded to false
// Keep function for compatibility but it doesn't do anything
// Removed Hide all options and Hide back button settings
// These are now hardcoded to false (visible by default)
// Role-locked: a child session cannot loosen it.
// Kept LAST (above Reset) on purpose: these are ~14 focusable
// chips, and placing them higher would push every existing switch
// that many extra D-pad presses away on TV.
// Hardcoded to false
// Hardcoded to false
// Hardcoded to false
// Hardcoded to false
// Playback filters are shared by both scopes, so reset
// them from either one.
// No longer saving hideOptions and hideBackButton - they're hardcoded to false
```
### `_DebrifyTVScreenState._showQuickPlayDialog`

ORIGINAL lines 9385–9524; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_dialogs.dart` → `DebrifyTvDialogs.showQuickPlayDialog`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@317219 lexical unbound scope=member/block0 read`; `context@317413 lexical decl:member/block0/closure0/block0/closure0#context#0 scope=member/block0/closure0/block0/closure0/block0 read`; `context@318806 selector None scope=member/block0/closure0/block0/closure0/block0/closure0/block0 read`; `context@319046 selector None scope=member/block0/closure0/block0/closure0/block0/closure1/block0 read`; `mounted@321069 lexical unbound scope=member/block0/closure0/block0/closure0/block0/closure5/block0/if1 read`; `setState@321102 lexical unbound scope=member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0 invocation`; `mounted@322265 lexical unbound scope=member/block0/closure0/block0/closure0/block0/closure5/block0/if2 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_isBusy` → `_owners.session.isBusy` | 316824 / read / `member/block0/if0` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 316877 / read / `member/block0`; 321603 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickPlayMaxKeywords` → `_owners.settings.quickPlayMaxKeywords` | 317619 / read / `member/block0/closure0/block0/closure0/block0` |
| `_quickStartRandom` → `_owners.settings.quickStartRandom` | 321140 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 321160 / read / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickRandomStartPercent` → `_owners.settings.quickRandomStartPercent` | 321198 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 321225 / read / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickHideSeekbar` → `_owners.settings.quickHideSeekbar` | 321270 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 321290 / read / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 321328 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 321352 / read / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickShowVideoTitle` → `_owners.settings.quickShowVideoTitle` | 321394 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 321417 / read / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickHideOptions` → `_owners.settings.quickHideOptions` | 321458 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickHideBackButton` → `_owners.settings.quickHideBackButton` | 321529 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 321656 / write / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_provider` → `_owners.settings.provider` | 321673 / read / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0/closure0/block0` |
| `_keywordsController` → `_owners.library.keywordsController` | 321830 / read / `member/block0/closure0/block0/closure0/block0/closure5/block0/if1/block0` |

Escaping callbacks/builders: `StatefulBuilder[0].builder = (context,setDialogState){finalapp=AppThemeScope.of(context);returnDebrifyTvSpotlightDialog(eyebrow:'Quick play · no channel needed',title:'Play anything',subtitle:'Enter up to $_quickPlayMaxKeywords search terms. Nothing is saved when playback ends.',icon:Icons.play_arrow_rounded,maxWidth:680,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[TvTextField(controller:controller,autofocus:true,focusNode:keywordFocusNode,textInputAction:TextInputAction.search,// Shared TV shell/keyboard chrome — settings.accent,// with the keyboard's own panel ground and ink.accent:app.settings.accent,keyboardGround:app.youtube.keyboardPanel,keyboardInk:app.core.tx,keyboardInkOnAccent:app.inkOn(app.settings.accent),decoration:constInputDecoration(labelText:'Keywords',hintText:'Comma separated keywords'),onDownArrow:(){finalctx=keywordFocusNode.context;if(ctx!=null){FocusScope.of(ctx).nextFocus();}},onUpArrow:(){finalctx=keywordFocusNode.context;if(ctx!=null){FocusScope.of(ctx).previousFocus();}},onChanged:(_){if(error!=null){setDialogState(()=>error=null);}}),constSizedBox(height:12),SwitchRow(title:'Avoid NSFW content',subtitle:_viewerForcesNsfw?'Always on for this profile':'Best-effort filter while searching',value:_viewerForcesNsfw||avoidNsfw,onChanged:(value){// Role-locked: a child session cannot loosen it.if(_viewerForcesNsfw)return;setDialogState(()=>avoidNsfw=value);}),if(error!=null)...[constSizedBox(height:8),Text(error!,style:constTextStyle(color:Colors.redAccent))]]),actions:[DebrifyTvDialogButton(label:'Cancel',onPressed:()=>Navigator.of(dialogContext).pop()),DebrifyTvDialogButton(label:'Play now',icon:Icons.play_arrow_rounded,tone:DebrifyTvDialogButtonTone.primary,onPressed:()async{finalkeywords=controller.text.trim();if(keywords.isEmpty){setDialogState(()=>error='Enter one or more keywords to continue.');return;}if(mounted){setState((){_quickStartRandom=_startRandom;_quickRandomStartPercent=_randomStartPercent;_quickHideSeekbar=_hideSeekbar;_quickShowChannelName=_showChannelName;_quickShowVideoTitle=_showVideoTitle;_quickHideOptions=false;// Always false now_quickHideBackButton=false;// Always false now_quickAvoidNsfw=avoidNsfw;_quickProvider=_provider;});// Copy keywords from Quick Play controller to main controller for _watch()_keywordsController.text=keywords;}Navigator.of(dialogContext).pop();// Wait for frames to ensure UI has updated and touch events are processedawaitFuture.delayed(constDuration(milliseconds:100));awaitWidgetsBinding.instance.endOfFrame;awaitWidgetsBinding.instance.endOfFrame;if(mounted){await_watch();}})]);}`; `TvTextField[0].onDownArrow = (){finalctx=keywordFocusNode.context;if(ctx!=null){FocusScope.of(ctx).nextFocus();}}`; `TvTextField[0].onUpArrow = (){finalctx=keywordFocusNode.context;if(ctx!=null){FocusScope.of(ctx).previousFocus();}}`; `TvTextField[0].onChanged = (_){if(error!=null){setDialogState(()=>error=null);}}`; `SwitchRow[0].onChanged = (value){// Role-locked: a child session cannot loosen it.if(_viewerForcesNsfw)return;setDialogState(()=>avoidNsfw=value);}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`; `DebrifyTvDialogButton[1].onPressed = ()async{finalkeywords=controller.text.trim();if(keywords.isEmpty){setDialogState(()=>error='Enter one or more keywords to continue.');return;}if(mounted){setState((){_quickStartRandom=_startRandom;_quickRandomStartPercent=_randomStartPercent;_quickHideSeekbar=_hideSeekbar;_quickShowChannelName=_showChannelName;_quickShowVideoTitle=_showVideoTitle;_quickHideOptions=false;// Always false now_quickHideBackButton=false;// Always false now_quickAvoidNsfw=avoidNsfw;_quickProvider=_provider;});// Copy keywords from Quick Play controller to main controller for _watch()_keywordsController.text=keywords;}Navigator.of(dialogContext).pop();// Wait for frames to ensure UI has updated and touch events are processedawaitFuture.delayed(constDuration(milliseconds:100));awaitWidgetsBinding.instance.endOfFrame;awaitWidgetsBinding.instance.endOfFrame;if(mounted){await_watch();}}`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Create a separate controller for Quick Play to avoid sharing state with edit dialog
// Shared TV shell/keyboard chrome — settings.accent,
// with the keyboard's own panel ground and ink.
// Role-locked: a child session cannot loosen it.
// Always false now
// Always false now
// Copy keywords from Quick Play controller to main controller for _watch()
// Wait for frames to ensure UI has updated and touch events are processed
```
### `_DebrifyTVScreenState._showGlobalSettingsDialog`

ORIGINAL lines 9526–9561; step 7; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_dialogs.dart` → `DebrifyTvDialogs.showGlobalSettingsDialog`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `context@322606 lexical unbound scope=member/block0 read`.

Escaping callbacks/builders: `StatefulBuilder[0].builder = (context,setDialogState){returnDebrifyTvSpotlightDialog(eyebrow:'Debrify TV · applies to every channel',title:'Channel playback',subtitle:'Choose the provider, filters, and starting behavior used when a channel tunes.',icon:Icons.settings_rounded,maxWidth:920,maxHeightFactor:.94,child:_buildSettingsCard(scope:_SettingsScope.channels,includeNsfwToggle:false,title:'Playback rules',dialogSetState:setDialogState),actions:[DebrifyTvDialogButton(autofocus:true,label:'Done',icon:Icons.check_rounded,tone:DebrifyTvDialogButtonTone.primary,onPressed:()=>Navigator.of(dialogContext).pop())]);}`; `DebrifyTvDialogButton[0].onPressed = ()=>Navigator.of(dialogContext).pop()`.
### `_DebrifyTVScreenState._resolveTorboxQueuedFile`

ORIGINAL lines 9563–9587; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver.resolveTorboxQueuedFile`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._prepareTorboxTorrent`

ORIGINAL lines 9589–9691; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver.prepareTorboxTorrent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 326713 / read / `member/block0/closure0`; 327298 / read / `member/block0/block1` |
### `_DebrifyTVScreenState._preparePikPakTorrent`

ORIGINAL lines 9693–9807; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cloud_resolvers.dart` → `DebrifyTvCloudResolvers.preparePikPakTorrent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 329368 / read / `member/block0/function0/closure0/block0/closure0/block0/if1`; 331291 / read / `member/block0` |
| `_torboxMinVideoSizeBytes` → `DebrifyTvConstants.torboxMinVideoSizeBytes` | 329518 / read / `member/block0/function0/closure0/block0/closure0/block0/if2` |
| `_tvFilters` → `_owners.settings.tvFilters` | 329590 / read / `member/block0/function0/closure0/block0/closure0/block0/if3`; 329776 / read / `member/block0/if4` |

Escaping callbacks/builders: `prepareTorrent[0].onLog = log`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Check if this is a multi-file torrent
// Single file torrent - return directly
// Multi-file torrent - filter out seen files
// Filter unseen files. PikPak reports a per-file `size`, so the same
// per-FILE size rules the other providers use apply here — including the
// 50MB floor that keeps trailers and samples out of the rotation.
// Nothing in this torrent matched — take it unfiltered rather than
// discarding the torrent (see the Torbox builder).
// Shuffle and select next file
// Get streaming URL for selected file
// Mark as seen
```
### `_DebrifyTVScreenState._fetchPremiumizeCacheWindow`

ORIGINAL lines 9811–9855; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cloud_resolvers.dart` → `DebrifyTvCloudResolvers.fetchPremiumizeCacheWindow`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._preparePremiumizeTorrent`

ORIGINAL lines 9857–9910; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cloud_resolvers.dart` → `DebrifyTvCloudResolvers.preparePremiumizeTorrent`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 333877 / read / `member/block0/closure0`; 334255 / read / `member/block0` |
### `_DebrifyTVScreenState._buildPremiumizePlayableEntries`

ORIGINAL lines 9912–9973; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cloud_resolvers.dart` → `DebrifyTvCloudResolvers._buildPremiumizePlayableEntries`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_torboxMinVideoSizeBytes` → `DebrifyTvConstants.torboxMinVideoSizeBytes` | 334903 / read / `member/block0/for0/block0/if1` |
| `_tvFilters` → `_owners.settings.tvFilters` | 335043 / read / `member/block0/for0/block0/if2`; 336257 / read / `member/block0/if0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Per-FILE size filter (see the Torbox builder for the rationale).
```
### `_DebrifyTVScreenState._premiumizeFileLooksLikeVideo`

ORIGINAL lines 9975–9979; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cloud_resolvers.dart` → `DebrifyTvCloudResolvers._premiumizeFileLooksLikeVideo`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._watchPremiumizeWithCachedTorrents`

ORIGINAL lines 9981–10207; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_cached_premiumize.dart` → `DebrifyTvCachedPremiumize.watchPremiumizeWithCachedTorrents`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@338207 lexical unbound scope=member/block0/if3 read`; `setState@338224 lexical unbound scope=member/block0/if3/block0 invocation`; `mounted@339047 lexical unbound scope=member/block0/function1/closure0/block0/block0/if2 read`; `setState@339068 lexical unbound scope=member/block0/function1/closure0/block0/block0/if2/block0 invocation`; `mounted@339536 lexical unbound scope=member/block0/catch0/block0/if0 read`; `setState@339545 lexical unbound scope=member/block0/catch0/block0/if0 invocation`; `mounted@339794 lexical unbound scope=member/block0/if4/block0/if0 read`; `setState@339803 lexical unbound scope=member/block0/if4/block0/if0 invocation`; `mounted@340268 lexical unbound scope=member/block0/function2/closure0/block0/block0/if0/block0/catch0/block0/if0 read`; `setState@340277 lexical unbound scope=member/block0/function2/closure0/block0/block0/if0/block0/catch0/block0/if0 invocation`; `mounted@340983 lexical unbound scope=member/block0/block1/if0/block0/if0 read`; `setState@341008 lexical unbound scope=member/block0/block1/if0/block0 invocation`; `mounted@341431 lexical unbound scope=member/block0/block1/if1 read`; `context@342016 lexical unbound scope=member/block0/block1 read`; `mounted@343164 lexical unbound scope=member/block0/block1/if4 read`; `setState@343183 lexical unbound scope=member/block0/block1/if4/block0 invocation`; `mounted@343482 lexical unbound scope=member/block0/block2/if0 read`; `setState@343505 lexical unbound scope=member/block0/block2 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_channels` → `_owners.library.channels` | 337231 / read / `member/block0`; 342645 / read / `member/block0/block1/closure0`; 343038 / read / `member/block0/block1/closure0` |
| `_currentWatchingChannelId` → `_owners.library.currentWatchingChannelId` | 337331 / read / `member/block0` |
| `_status` → `_owners.session.status` | 338246 / write / `member/block0/if3/block0/closure0/block0`; 339094 / write / `member/block0/function1/closure0/block0/block0/if2/block0/closure0/block0`; 341032 / write / `member/block0/block1/if0/block0/closure0/block0`; 343207 / write / `member/block0/block1/if4/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 338296 / write / `member/block0/if3/block0/closure0/block0`; 339560 / write / `member/block0/catch0/block0/if0/closure0`; 339818 / write / `member/block0/if4/block0/if0/closure0`; 340292 / write / `member/block0/function2/closure0/block0/block0/if0/block0/catch0/block0/if0/closure0`; 341109 / write / `member/block0/block1/if0/block0/closure0/block0`; 343520 / write / `member/block0/block2/closure0` |
| `_queue` → `_owners.session.queue` | 338885 / read / `member/block0/function1/closure0/block0/block0`; 338980 / read / `member/block0/function1/closure0/block0/block0`; 339104 / read / `member/block0/function1/closure0/block0/block0/if2/block0/closure0/block0`; 339171 / read / `member/block0/function1/closure0/block0/block0/if2/block0/closure0/block0`; 339274 / read / `member/block0/function1/closure0/block0/block0`; 339955 / read / `member/block0/function2/closure0/block0/block0/if0`; 340404 / read / `member/block0/function2/closure0/block0/block0/if1`; 340449 / read / `member/block0/function2/closure0/block0/block0`; 343217 / read / `member/block0/block1/if4/block0/closure0/block0`; 343280 / read / `member/block0/block1/if4/block0/closure0/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 338963 / write / `member/block0/function1/closure0/block0/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 339003 / write / `member/block0/function1/closure0/block0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 342224 / read / `member/block0/block1/closure0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 342273 / read / `member/block0/block1/closure0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 342319 / read / `member/block0/block1/closure0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 342362 / read / `member/block0/block1/closure0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 342488 / read / `member/block0/block1/closure0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 342530 / read / `member/block0/block1/closure0` |
| `_provider` → `_owners.settings.provider` | 342690 / read / `member/block0/block1/closure0`; 342750 / read / `member/block0/block1/closure0`; 342806 / read / `member/block0/block1/closure0`; 342862 / read / `member/block0/block1/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 342703 / read / `member/block0/block1/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 342763 / read / `member/block0/block1/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 342819 / read / `member/block0/block1/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 342875 / read / `member/block0/block1/closure0` |

Escaping callbacks/builders: `_preparePremiumizeTorrent[0].log = log`; `_launchPikPakOnAndroidTv[0].requestNext = requestPremiumizeNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:first['url']??'',title:first['title']??'Debrify TV',startFromRandom:_startRandom,randomStartMaxPercent:_randomStartPercent,hideSeekbar:_hideSeekbar,showChannelName:_showChannelName,channelName:channelName,channelNumber:channelNumber,showVideoTitle:_showVideoTitle,hideOptions:_hideOptions,requestMagicNext:requestPremiumizeNext,requestNextChannel:_channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null,channelDirectory:channelDirectory,requestChannelById:_channels.length>1?_requestChannelById:null)`; `VideoPlayerScreen[0].requestMagicNext = requestPremiumizeNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_provider==_providerRealDebrid||_provider==_providerTorbox||_provider==_providerPikPak||_provider==_providerPremiumize)?_requestNextChannel:null`; `VideoPlayerScreen[0].requestChannelById = _channels.length>1?_requestChannelById:null`.
### `_DebrifyTVScreenState._watchWithPremiumize`

ORIGINAL lines 10209–10499; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_premiumize.dart` → `DebrifyTvQuickPlayPremiumize.watchWithPremiumize`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@343834 lexical unbound scope=member/block0/if0/block0/if0 read`; `setState@343857 lexical unbound scope=member/block0/if0/block0 invocation`; `mounted@344271 lexical unbound scope=member/block0/if1/block0/if0 read`; `setState@344294 lexical unbound scope=member/block0/if1/block0 invocation`; `mounted@345767 lexical unbound scope=member/block0/block0/for0/block0/if1 read`; `setState@345788 lexical unbound scope=member/block0/block0/for0/block0/if1/block0 invocation`; `mounted@346225 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@346246 lexical unbound scope=member/block0/block0/if0/block0/if0/block0 invocation`; `mounted@346523 lexical unbound scope=member/block0/block0/if1 read`; `setState@346532 lexical unbound scope=member/block0/block0/if1 invocation`; `mounted@347295 lexical unbound scope=member/block0/block0/function0/closure0/block0/block0/if2 read`; `setState@347318 lexical unbound scope=member/block0/block0/function0/closure0/block0/block0/if2/block0 invocation`; `mounted@347783 lexical unbound scope=member/block0/block0/catch0/block0/if0 read`; `setState@347804 lexical unbound scope=member/block0/block0/catch0/block0/if0/block0 invocation`; `mounted@348053 lexical unbound scope=member/block0/block0/if2/block0/if0 read`; `setState@348074 lexical unbound scope=member/block0/block0/if2/block0/if0/block0 invocation`; `mounted@348784 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0 read`; `setState@348831 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0/block0 invocation`; `mounted@349664 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if5/block0/if1 read`; `setState@349709 lexical unbound scope=member/block0/block0/function1/closure0/block0/block0/if5/block0/if1/block0 invocation`; `mounted@350032 lexical unbound scope=member/block0/block0/function1/closure0/block0/if1 read`; `setState@350073 lexical unbound scope=member/block0/block0/function1/closure0/block0/if1/block0 invocation`; `mounted@350334 lexical unbound scope=member/block0/block0/if4/block0/if0 read`; `setState@350375 lexical unbound scope=member/block0/block0/if4/block0/if0/block0 invocation`; `mounted@350725 lexical unbound scope=member/block0/block0/if5 read`; `context@351371 lexical unbound scope=member/block0/block0/if9/block0 read`; `mounted@352417 lexical unbound scope=member/block0/block0/if10 read`; `setState@352456 lexical unbound scope=member/block0/block0/if10/block0 invocation`; `mounted@352754 lexical unbound scope=member/block0/block1/if0 read`; `setState@352763 lexical unbound scope=member/block0/block1/if0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_status` → `_owners.session.status` | 343879 / write / `member/block0/if0/block0/closure0/block0`; 344316 / write / `member/block0/if1/block0/closure0/block0`; 345803 / write / `member/block0/block0/for0/block0/if1/block0/closure0`; 346261 / write / `member/block0/block0/if0/block0/if0/block0/closure0`; 346547 / write / `member/block0/block0/if1/closure0`; 347346 / write / `member/block0/block0/function0/closure0/block0/block0/if2/block0/closure0/block0`; 347819 / write / `member/block0/block0/catch0/block0/if0/block0/closure0`; 348102 / write / `member/block0/block0/if2/block0/if0/block0/closure0`; 348865 / write / `member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0/block0/closure0`; 349739 / write / `member/block0/block0/function1/closure0/block0/block0/if5/block0/if1/block0/closure0/block0`; 350088 / write / `member/block0/block0/function1/closure0/block0/if1/block0/closure0`; 350401 / write / `member/block0/block0/if4/block0/if0/block0/closure0/block0`; 352480 / write / `member/block0/block0/if10/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 343952 / write / `member/block0/if0/block0/closure0/block0`; 344411 / write / `member/block0/if1/block0/closure0/block0`; 352778 / write / `member/block0/block1/if0/closure0` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 345304 / read / `member/block0/block0/for0/block0/if0` |
| `_queue` → `_owners.session.queue` | 347123 / read / `member/block0/block0/function0/closure0/block0/block0`; 347224 / read / `member/block0/block0/function0/closure0/block0/block0`; 347356 / read / `member/block0/block0/function0/closure0/block0/block0/if2/block0/closure0/block0`; 347427 / read / `member/block0/block0/function0/closure0/block0/block0/if2/block0/closure0/block0`; 347507 / read / `member/block0/block0/function0/closure0/block0/block0`; 348527 / read / `member/block0/block0/function1/closure0/block0/block0/if0`; 349198 / read / `member/block0/block0/function1/closure0/block0/block0/if1`; 349245 / read / `member/block0/block0/function1/closure0/block0/block0`; 349749 / read / `member/block0/block0/function1/closure0/block0/block0/if5/block0/if1/block0/closure0/block0`; 349824 / read / `member/block0/block0/function1/closure0/block0/block0/if5/block0/if1/block0/closure0/block0`; 352490 / read / `member/block0/block0/if10/block0/closure0/block0`; 352553 / read / `member/block0/block0/if10/block0/closure0/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 347207 / write / `member/block0/block0/function0/closure0/block0/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 347249 / write / `member/block0/block0/function0/closure0/block0/block0` |
| `_watchCancelled` → `_owners.session.watchCancelled` | 348448 / read / `member/block0/block0/function1/closure0/block0/if0`; 348494 / read / `member/block0/block0/function1/closure0/block0`; 348796 / read / `member/block0/block0/function1/closure0/block0/block0/if0/block0/catch0/block0/if0`; 349279 / read / `member/block0/block0/function1/closure0/block0/block0/if2`; 349510 / read / `member/block0/block0/function1/closure0/block0/block0/if4`; 349607 / read / `member/block0/block0/function1/closure0/block0/block0/if5/block0/if0`; 349676 / read / `member/block0/block0/function1/closure0/block0/block0/if5/block0/if1`; 349899 / read / `member/block0/block0/function1/closure0/block0/block0/if5/block0/if2`; 350044 / read / `member/block0/block0/function1/closure0/block0/if1`; 350238 / read / `member/block0/block0/if3`; 350346 / read / `member/block0/block0/if4/block0/if0`; 351208 / read / `member/block0/block0/if7`; 351277 / read / `member/block0/block0/if9`; 352429 / read / `member/block0/block0/if10` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 351053 / read / `member/block0/block0` |
| `_startRandom` → `_owners.settings.startRandom` | 351589 / read / `member/block0/block0/if9/block0/closure0` |
| `_randomStartPercent` → `_owners.settings.randomStartPercent` | 351640 / read / `member/block0/block0/if9/block0/closure0` |
| `_hideSeekbar` → `_owners.settings.hideSeekbar` | 351688 / read / `member/block0/block0/if9/block0/closure0` |
| `_showChannelName` → `_owners.settings.showChannelName` | 351733 / read / `member/block0/block0/if9/block0/closure0` |
| `_showVideoTitle` → `_owners.settings.showVideoTitle` | 351849 / read / `member/block0/block0/if9/block0/closure0` |
| `_hideOptions` → `_owners.settings.hideOptions` | 351893 / read / `member/block0/block0/if9/block0/closure0` |
| `_channels` → `_owners.library.channels` | 352014 / read / `member/block0/block0/if9/block0/closure0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 352061 / read / `member/block0/block0/if9/block0/closure0`; 352128 / read / `member/block0/block0/if9/block0/closure0`; 352191 / read / `member/block0/block0/if9/block0/closure0`; 352254 / read / `member/block0/block0/if9/block0/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 352079 / read / `member/block0/block0/if9/block0/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 352146 / read / `member/block0/block0/if9/block0/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 352209 / read / `member/block0/block0/if9/block0/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 352272 / read / `member/block0/block0/if9/block0/closure0` |

Escaping callbacks/builders: `_preparePremiumizeTorrent[0].log = log`; `_launchPikPakOnAndroidTv[0].requestNext = requestPremiumizeNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:first['url']??'',title:first['title']??'Debrify TV',startFromRandom:_startRandom,randomStartMaxPercent:_randomStartPercent,hideSeekbar:_hideSeekbar,showChannelName:_showChannelName,channelName:null,channelNumber:null,showVideoTitle:_showVideoTitle,hideOptions:_hideOptions,requestMagicNext:requestPremiumizeNext,requestNextChannel:_channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak||_quickProvider==_providerPremiumize)?_requestNextChannel:null)`; `VideoPlayerScreen[0].requestMagicNext = requestPremiumizeNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak||_quickProvider==_providerPremiumize)?_requestNextChannel:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Search is complete here — an empty match means this search really
// has nothing at the requested quality, so degrade rather than fail.
```
### `_DebrifyTVScreenState._watchWithAllDebrid`

ORIGINAL lines 10501–10774; step 6; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_quick_play_alldebrid.dart` → `DebrifyTvQuickPlayAllDebrid.watchWithAllDebrid`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@353441 lexical unbound scope=member/block0/if0/block0/if0 read`; `setState@353464 lexical unbound scope=member/block0/if0/block0 invocation`; `mounted@353874 lexical unbound scope=member/block0/if1/block0/if0 read`; `setState@353897 lexical unbound scope=member/block0/if1/block0 invocation`; `mounted@355397 lexical unbound scope=member/block0/block0/for0/block0/if2 read`; `setState@355418 lexical unbound scope=member/block0/block0/for0/block0/if2/block0 invocation`; `mounted@355855 lexical unbound scope=member/block0/block0/if0/block0/if0 read`; `setState@355876 lexical unbound scope=member/block0/block0/if0/block0/if0/block0 invocation`; `mounted@359633 lexical unbound scope=member/block0/block0/if2/block0/if0 read`; `setState@359674 lexical unbound scope=member/block0/block0/if2/block0/if0/block0 invocation`; `mounted@360158 lexical unbound scope=member/block0/block0/if3 read`; `context@360841 lexical unbound scope=member/block0/block0/if7/block0 read`; `mounted@361989 lexical unbound scope=member/block0/block0/if8 read`; `setState@362028 lexical unbound scope=member/block0/block0/if8/block0 invocation`; `mounted@362326 lexical unbound scope=member/block0/block1/if0 read`; `setState@362335 lexical unbound scope=member/block0/block1/if0 invocation`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_status` → `_owners.session.status` | 353486 / write / `member/block0/if0/block0/closure0/block0`; 353919 / write / `member/block0/if1/block0/closure0/block0`; 355433 / write / `member/block0/block0/for0/block0/if2/block0/closure0`; 355891 / write / `member/block0/block0/if0/block0/if0/block0/closure0`; 359700 / write / `member/block0/block0/if2/block0/if0/block0/closure0/block0`; 362052 / write / `member/block0/block0/if8/block0/closure0/block0` |
| `_isBusy` → `_owners.session.isBusy` | 353558 / write / `member/block0/if0/block0/closure0/block0`; 354013 / write / `member/block0/if1/block0/closure0/block0`; 362350 / write / `member/block0/block1/if0/closure0` |
| `_watchCancelled` → `_owners.session.watchCancelled` | 354746 / read / `member/block0/block0/for0/block0/if0`; 356881 / read / `member/block0/block0/function1/closure0/block0/if0`; 357029 / read / `member/block0/block0/function1/closure0/block0`; 357379 / read / `member/block0/block0/function1/closure0/block0/block0/if0/block0/block0/if0`; 358110 / read / `member/block0/block0/function1/closure0/block0/block0/if1/block0/if0`; 358801 / read / `member/block0/block0/function1/closure0/block0/block0/if1/block0/block0/if0`; 359537 / read / `member/block0/block0/if1`; 359645 / read / `member/block0/block0/if2/block0/if0`; 360678 / read / `member/block0/block0/if5`; 360747 / read / `member/block0/block0/if7`; 362001 / read / `member/block0/block0/if8` |
| `_quickAvoidNsfw` → `_owners.settings.quickAvoidNsfw` | 354934 / read / `member/block0/block0/for0/block0/if1` |
| `_queue` → `_owners.session.queue` | 356301 / read / `member/block0/block0`; 356381 / read / `member/block0/block0`; 356974 / read / `member/block0/block0/function1/closure0/block0`; 357007 / read / `member/block0/block0/function1/closure0/block0`; 357071 / read / `member/block0/block0/function1/closure0/block0/block0`; 358422 / read / `member/block0/block0/function1/closure0/block0/block0/if1/block0/for0/block0`; 362062 / read / `member/block0/block0/if8/block0/closure0/block0`; 362125 / read / `member/block0/block0/if8/block0/closure0/block0` |
| `_lastQueueSize` → `_owners.session.lastQueueSize` | 356364 / write / `member/block0/block0` |
| `_lastSearchAt` → `_owners.session.lastSearchAt` | 356402 / write / `member/block0/block0` |
| `_seenRestrictedLinks` → `_owners.session.seenRestrictedLinks` | 356440 / read / `member/block0/block0` |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 356476 / read / `member/block0/block0` |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 360182 / write / `member/block0/block0` |
| `_activeProvider` → `_owners.prefetch.activeProvider` | 360212 / write / `member/block0/block0` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 360230 / read / `member/block0/block0`; 361814 / read / `member/block0/block0/if7/block0/closure0` |
| `_quickShowChannelName` → `_owners.settings.quickShowChannelName` | 360550 / read / `member/block0/block0`; 361198 / read / `member/block0/block0/if7/block0/closure0` |
| `_quickStartRandom` → `_owners.settings.quickStartRandom` | 361039 / read / `member/block0/block0/if7/block0/closure0` |
| `_quickRandomStartPercent` → `_owners.settings.quickRandomStartPercent` | 361095 / read / `member/block0/block0/if7/block0/closure0` |
| `_quickHideSeekbar` → `_owners.settings.quickHideSeekbar` | 361148 / read / `member/block0/block0/if7/block0/closure0` |
| `_quickShowVideoTitle` → `_owners.settings.quickShowVideoTitle` | 361319 / read / `member/block0/block0/if7/block0/closure0` |
| `_quickHideOptions` → `_owners.settings.quickHideOptions` | 361368 / read / `member/block0/block0/if7/block0/closure0` |
| `_channels` → `_owners.library.channels` | 361489 / read / `member/block0/block0/if7/block0/closure0` |
| `_quickProvider` → `_owners.settings.quickProvider` | 361536 / read / `member/block0/block0/if7/block0/closure0`; 361603 / read / `member/block0/block0/if7/block0/closure0`; 361666 / read / `member/block0/block0/if7/block0/closure0`; 361729 / read / `member/block0/block0/if7/block0/closure0`; 361796 / read / `member/block0/block0/if7/block0/closure0` |
| `_providerRealDebrid` → `DebrifyTvConstants.providerRealDebrid` | 361554 / read / `member/block0/block0/if7/block0/closure0` |
| `_providerTorbox` → `DebrifyTvConstants.providerTorbox` | 361621 / read / `member/block0/block0/if7/block0/closure0` |
| `_providerPikPak` → `DebrifyTvConstants.providerPikPak` | 361684 / read / `member/block0/block0/if7/block0/closure0` |
| `_providerPremiumize` → `DebrifyTvConstants.providerPremiumize` | 361747 / read / `member/block0/block0/if7/block0/closure0` |

Escaping callbacks/builders: `_launchRealDebridOnAndroidTv[0].requestNext = requestMagicNext`; `videoPlayerRoute[0].builder = (_)=>VideoPlayerScreen(videoUrl:first['url']??'',title:firstTitle,startFromRandom:_quickStartRandom,randomStartMaxPercent:_quickRandomStartPercent,hideSeekbar:_quickHideSeekbar,showChannelName:_quickShowChannelName,channelName:null,channelNumber:null,showVideoTitle:_quickShowVideoTitle,hideOptions:_quickHideOptions,requestMagicNext:requestMagicNext,requestNextChannel:_channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak||_quickProvider==_providerPremiumize||_quickProvider==_providerAllDebrid)?_requestNextChannel:null)`; `VideoPlayerScreen[0].requestMagicNext = requestMagicNext`; `VideoPlayerScreen[0].requestNextChannel = _channels.length>1&&(_quickProvider==_providerRealDebrid||_quickProvider==_providerTorbox||_quickProvider==_providerPikPak||_quickProvider==_providerPremiumize||_quickProvider==_providerAllDebrid)?_requestNextChannel:null`.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// AllDebrid Quick Play. Self-contained like [_watchWithPremiumize] for the
/// search phase, but follows Real-Debrid's resolve model (sequential
/// add-and-probe + background prefetcher) since AllDebrid has no cache-check
/// API. Each candidate is added trusting the `ready` flag (no polling) and
/// links are unlocked lazily on demand.
// Search is complete here — an empty match means this search really
// has nothing at the requested quality, so degrade rather than fail.
// Seed the queue with raw torrents — sequential add-and-probe, no cache
// check (mirrors Real-Debrid). The prefetcher prepares the rest.
```
### `_DebrifyTVScreenState._buildTorboxPlayableEntries`

ORIGINAL lines 10776–10837; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver._buildTorboxPlayableEntries`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_torboxMinVideoSizeBytes` → `DebrifyTvConstants.torboxMinVideoSizeBytes` | 362800 / read / `member/block0/for0/block0/if1` |
| `_tvFilters` → `_owners.settings.tvFilters` | 363007 / read / `member/block0/for0/block0/if2`; 364419 / read / `member/block0/if0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Per-FILE size filter: a pack's files are individual episodes, so this
// compares against the number the user actually meant.
// Sort series candidates by season and episode
// Sort other candidates alphabetically
// Nothing in THIS torrent matched the size filter — take it unfiltered
// rather than discarding the torrent, so a strict filter narrows what
// plays instead of walking the whole queue and playing nothing.
```
### `_DebrifyTVScreenState._formatTorboxSeriesTitle`

ORIGINAL lines 10839–10851; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver.formatTorboxSeriesTitle`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._torboxFileLooksLikeVideo`

ORIGINAL lines 10853–10861; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver._torboxFileLooksLikeVideo`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._torboxDisplayName`

ORIGINAL lines 10863–10871; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver._torboxDisplayName`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._normalizeInfohash`

ORIGINAL lines 10873–10875; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_playback_filters.dart` → `DebrifyTvPlaybackFilters.normalizeInfohash`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._showSnack`

ORIGINAL lines 10877–10886; step 3; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_feedback.dart` → `DebrifyTvFeedback.showSnack`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@366029 lexical unbound scope=member/block0/if0 read`; `context@366071 lexical unbound scope=member/block0 read`.
### `_DebrifyTVScreenState._asIntMapValue`

ORIGINAL lines 10888–10896; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver._asIntMapValue`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._formatTorboxError`

ORIGINAL lines 10898–10900; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_torbox_resolver.dart` → `DebrifyTvTorboxResolver.formatTorboxError`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._formatImportError`

ORIGINAL lines 10902–10907; step 4; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_formats.dart` → `DebrifyTvImportFormats.formatImportError`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.
### `_DebrifyTVScreenState._handOffToExternalPlayer`

ORIGINAL lines 10911–10961; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_player_handoff.dart` → `DebrifyTvPlayerHandoff.handOffToExternalPlayer`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@367880 lexical unbound scope=member/block0/if0 read`; `mounted@367988 lexical unbound scope=member/block0/if2 read`; `mounted@368378 lexical unbound scope=member/block0/if3 read`; `context@368871 lexical unbound scope=member/block0/if4 read`; `mounted@368946 lexical unbound scope=member/block0/if5 read`; `context@369050 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_launchedPlayer` → `_owners.session.launchedPlayer` | 369178 / write / `member/block0/if6/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Hands one resolved stream to the user's external player when that is
/// their default, after warning them what external playback costs here.
///
/// Returns true when the caller must abandon its own launch — either the
/// stream is now playing in another app, or the user backed out of the
/// warning. False means "carry on unchanged": the in-app player is the
/// default, or the external launch failed and the built-in player is the
/// fallback (same policy as [VideoPlayerLauncher.push]).
///
/// Channel rotation dies with the hand-off — nothing outside Debrify can
/// call back into `requestMagicNext` — so on any outcome that ends the flow
/// this also stops the prefetcher that exists purely to feed it. A failed
/// launch leaves the prefetcher running, because the in-app player that
/// picks the flow back up still wants it.
// The home-screen auto-launch overlay draws above routes, so drop it
// before the notice or the notice appears underneath it. Only the overlay
// — firing notifyPlayerLaunching here would stop other screens' trailers
// for a launch the user may still decline.
// Backing out must not silently fall through to the in-app player — that
// is the very thing the user chose against — so a decline reports
// "handled" too and every caller stops. Deliberately without touching
// _watchCancelled: that flag is only reset by the quick-play and cached-
// dialog entry points, so setting it here would leave channel plays
// stuck-cancelled on the next attempt.
```
### `_DebrifyTVScreenState._startPrefetch`

ORIGINAL lines 10965–10992; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher.startPrefetch`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@369830 lexical unbound scope=member/block0/if1 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_prefetchRunning` → `_owners.prefetch.prefetchRunning` | 369388 / read / `member/block0/if0`; 369889 / read / `member/block0/if1`; 370112 / write / `member/block0` |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 369408 / read / `member/block0/if0`; 369433 / read-write / `member/block0/if0`; 369917 / read / `member/block0/if1`; 369950 / read-write / `member/block0/if1` |
| `_prefetchEpoch` → `_owners.prefetch.prefetchEpoch` | 369503 / read / `member/block0`; 369863 / read / `member/block0/if1` |
| `_settingsManager` → `_owners.settings.settingsManager` | 369545 / read / `member/block0` |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 370141 / write / `member/block0` |
| `_prefetchTask` → `_owners.prefetch.prefetchTask` | 370223 / write / `member/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Re-check mutable state after the preference read. Multiple playback
// paths can request a start at nearly the same time, and playback may
// have stopped while this method was awaiting SharedPreferences.
```
### `_DebrifyTVScreenState._stopPrefetch`

ORIGINAL lines 10994–11005; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher.stopPrefetch`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_prefetchEpoch` → `_owners.prefetch.prefetchEpoch` | 370307 / read-write / `member/block0` |
| `_prefetchRunning` → `_owners.prefetch.prefetchRunning` | 370334 / read / `member/block0/if0`; 370455 / write / `member/block0` |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 370364 / write / `member/block0` |
| `_prefetchTask` → `_owners.prefetch.prefetchTask` | 370417 / read / `member/block0/block0`; 370485 / write / `member/block0` |
| `_inflightInfohashes` → `_owners.prefetch.inflightInfohashes` | 370511 / read / `member/block0` |
### `_DebrifyTVScreenState._runPrefetchLoop`

ORIGINAL lines 11007–11032; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher._runPrefetchLoop`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

State/lexical uses: `mounted@370644 lexical unbound scope=member/block0 read`.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_prefetchStopRequested` → `_owners.prefetch.prefetchStopRequested` | 370656 / read / `member/block0` |
| `_minPrepared` → `DebrifyTvConstants.minPrepared` | 370772 / read / `member/block0/block0/block0/if0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Find first unprepared torrent within lookahead window and prefetch it
// nothing to prefetch near head; small idle
// brief yield (faster when under target prepared)
```
### `_DebrifyTVScreenState._countPreparedInLookahead`

ORIGINAL lines 11034–11047; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher._countPreparedInLookahead`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_queue` → `_owners.session.queue` | 371591 / read / `member/block0`; 371634 / read / `member/block0`; 371750 / read / `member/block0/for0/block0` |
| `_lookaheadWindow` → `DebrifyTvConstants.lookaheadWindow` | 371607 / read / `member/block0`; 371658 / read / `member/block0` |
### `_DebrifyTVScreenState._findUnpreparedTorrentIndexInLookahead`

ORIGINAL lines 11049–11060; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher._findUnpreparedTorrentIndexInLookahead`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_queue` → `_owners.session.queue` | 371983 / read / `member/block0`; 372026 / read / `member/block0`; 372123 / read / `member/block0/for0/block0` |
| `_lookaheadWindow` → `DebrifyTvConstants.lookaheadWindow` | 371999 / read / `member/block0`; 372050 / read / `member/block0` |
| `_inflightInfohashes` → `_owners.prefetch.inflightInfohashes` | 372164 / read / `member/block0/for0/block0/if0` |
### `_DebrifyTVScreenState._prefetchOneAtIndex`

ORIGINAL lines 11062–11138; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher._prefetchOneAtIndex`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 372323 / read / `member/block0/if0`; 372348 / read-write / `member/block0/if0`; 372912 / read-write / `member/block0/block0` |
| `_queue` → `_owners.session.queue` | 372406 / read / `member/block0/if1`; 372446 / read / `member/block0`; 373223 / read / `member/block0/block0/if0/block0/if0`; 373250 / read / `member/block0/block0/if0/block0/if0`; 373282 / read / `member/block0/block0/if0/block0/if0/block0`; 373314 / read / `member/block0/block0/if0/block0/if0/block0`; 373816 / read / `member/block0/block0/if1/block0/if0`; 373843 / read / `member/block0/block0/if1/block0/if0`; 373875 / read / `member/block0/block0/if1/block0/if0/block0`; 373907 / read / `member/block0/block0/if1/block0/if0/block0`; 374176 / read / `member/block0/block0/if2`; 374203 / read / `member/block0/block0/if2`; 374233 / read / `member/block0/block0/if2/block0`; 374463 / read / `member/block0/block0/if3/block0`; 374573 / read / `member/block0/catch0/block0/if0`; 374600 / read / `member/block0/catch0/block0/if0`; 374630 / read / `member/block0/catch0/block0/if0/block0`; 374660 / read / `member/block0/catch0/block0/if0/block0` |
| `_activeProvider` → `_owners.prefetch.activeProvider` | 372501 / read / `member/block0/if3` |
| `_providerAllDebrid` → `DebrifyTvConstants.providerAllDebrid` | 372520 / read / `member/block0/if3` |
| `_inflightInfohashes` → `_owners.prefetch.inflightInfohashes` | 372648 / read / `member/block0`; 374788 / read / `member/block0/block1` |
| `_seenRestrictedLinks` → `_owners.session.seenRestrictedLinks` | 373688 / read / `member/block0/block0/closure1`; 374065 / read / `member/block0/block0` |
| `_seenLinkWithTorrentId` → `_owners.session.seenLinkWithTorrentId` | 374107 / read / `member/block0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
// Nothing ready; move to tail to retry later
// Convert this queue slot to rd_restricted using first link
// On failure, move to tail for retry later
```
### `_DebrifyTVScreenState._resolveAllDebridLinks`

ORIGINAL lines 11140–11202; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher.resolveAllDebridLinks`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_torboxMinVideoSizeBytes` → `DebrifyTvConstants.torboxMinVideoSizeBytes` | 376333 / read / `member/block0/function0/closure0/block0/closure0/block0/if1` |
| `_tvFilters` → `_owners.settings.tvFilters` | 376409 / read / `member/block0/function0/closure0/block0/closure0/block0/if2`; 376783 / read / `member/block0/if0` |
| `_seenRestrictedLinks` → `_owners.session.seenRestrictedLinks` | 376618 / read / `member/block0/function0/closure0/block0/closure2`; 377222 / read / `member/block0/for0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Adds [candidate] to AllDebrid (trusting the upload `ready` flag — no
/// polling) and returns its fresh (unseen) locked video-file links, marking
/// them seen. Returns null when the torrent is not cached/ready (the magnet
/// is deleted in that case) or has no usable video files. Each returned link
/// is still locked and must be unlocked via [AllDebridService.unlockLink]
/// before playback — the lazy model mirrors Real-Debrid's restricted links.
// Not cached/ready — don't leave it downloading on the account.
// AllDebrid returns a real per-file byte count, so the per-FILE size rules
// apply before the files are reduced to bare links (after that reduction
// the size is gone). The 50MB floor keeps trailers/samples out, matching
// Torbox and Premiumize.
// Nothing matched in this torrent — take it unfiltered rather than
// discarding the torrent (see the Torbox builder).
```
### `_DebrifyTVScreenState._prefetchOneAllDebrid`

ORIGINAL lines 11204–11257; step 5; destination `lib/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_prefetch.dart` → `DebrifyTvPrefetcher._prefetchOneAllDebrid`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

| Field → destination | Every occurrence (offset / role / scope) |
| --- | --- |
| `_inflightInfohashes` → `_owners.prefetch.inflightInfohashes` | 377793 / read / `member/block0`; 379339 / read / `member/block0/block1` |
| `_activeApiKey` → `_owners.prefetch.activeApiKey` | 377999 / read-write / `member/block0/block0` |
| `_queue` → `_owners.session.queue` | 378165 / read / `member/block0/block0/if0/block0/if0`; 378192 / read / `member/block0/block0/if0/block0/if0`; 378224 / read / `member/block0/block0/if0/block0/if0/block0`; 378256 / read / `member/block0/block0/if0/block0/if0/block0`; 378744 / read / `member/block0/block0/if1`; 378771 / read / `member/block0/block0/if1`; 378801 / read / `member/block0/block0/if1/block0`; 378939 / read / `member/block0/block0/if1/block1`; 379024 / read / `member/block0/block0/for0/block0`; 379097 / read / `member/block0/catch0/block0/if0`; 379124 / read / `member/block0/catch0/block0/if0`; 379154 / read / `member/block0/catch0/block0/if0/block0`; 379184 / read / `member/block0/catch0/block0/if0/block0` |

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// AllDebrid analog of the Real-Debrid prefetch path. Converts the [item]
/// queue slot into a prepared `ad_locked` entry (a still-locked link), and
/// since AllDebrid returns every file at once, enqueues the remaining video
/// files immediately rather than re-adding the torrent.
// Not ready / no usable video; move to tail to retry later.
// Slot shifted out from under us; don't lose the resolved head link.
```
### `_AllDebridPrepared`

ORIGINAL lines 11260–11271; step 1; destination `lib/features/debrify_tv/models/debrify_tv_alldebrid_prepared.dart` → `DebrifyTvAllDebridPrepared`.

Wiring review: checked one AST owner; retained until this step; original caller redirects through its registered owner/section; no extra forwarding, initialization, const, lifecycle, callback or resource ownership changes.

Comments/banners stay byte-exact apart from surrounding indentation; a banner belongs to the first following declaration:

```dart
/// Result of adding an AllDebrid magnet for Debrify TV: the resolved (still
/// locked) video-file links plus identifiers for the created magnet.
```
